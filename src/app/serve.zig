const std = @import("std");
const app_actions = @import("app_actions");
const app_dashboard = @import("app_dashboard");
const app_inventory = @import("app_inventory");
const app_topology = @import("app_topology");
const app_writes = @import("app_writes");
const app_caddy_desired = @import("app_caddy_desired");
const app_deploy = @import("app_deploy");
const app_provider_writes = @import("app_provider_writes");
const app_refresh = @import("app_refresh");
const app_system_control = @import("app_system_control");
const db_store = @import("db_store");
const core_config = @import("core_config");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const default_host = "127.0.0.1";
pub const default_port: u16 = 9328;

const max_request_body_bytes = 1024 * 1024;
const max_static_file_bytes = 8 * 1024 * 1024;
const auth_cookie_name = "cloudio_token";
const web_root = "web";

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    config: core_config.Config = .{ .domains = &.{} },
};

pub const Options = struct {
    host: []const u8 = default_host,
    port: u16 = default_port,
    once: bool = false,
    dashboard: app_dashboard.Options = .{},
};

/// Bumped after every completed refresh (scheduled or via POST /api/refresh);
/// /api/events/changes streams these bumps to open pages.
var refresh_epoch = std.atomic.Value(u64).init(0);

pub fn run(ctx: Context, options: Options) !void {
    var address = try std.Io.net.IpAddress.parse(options.host, options.port);
    var server = try address.listen(ctx.io, .{ .reuse_address = true });
    defer server.deinit(ctx.io);
    std.debug.print("cloudio serve http://{s}:{d}\n", .{ options.host, options.port });
    if (!options.once and ctx.config.refresh_seconds > 0) {
        if (std.Thread.spawn(.{}, refreshScheduler, .{ctx})) |thread| {
            thread.detach();
        } else |err| {
            std.debug.print("cloudio serve scheduler spawn failed: {s}\n", .{@errorName(err)});
        }
    }
    while (true) {
        const stream = try server.accept(ctx.io);
        if (options.once) {
            handleConnection(ctx, stream, options.dashboard) catch |err| {
                std.debug.print("cloudio serve request failed: {s}\n", .{@errorName(err)});
            };
            break;
        }
        const thread = std.Thread.spawn(.{}, connectionThread, .{ ctx, stream, options.dashboard }) catch |err| {
            std.debug.print("cloudio serve thread spawn failed: {s}\n", .{@errorName(err)});
            stream.close(ctx.io);
            continue;
        };
        thread.detach();
    }
}

/// Each connection thread opens its own Db handle: the shared handle is not
/// safe for concurrent use. Schema is already applied by startup, so we only
/// open here.
fn connectionThread(ctx: Context, stream: std.Io.net.Stream, dashboard_options: app_dashboard.Options) void {
    var db = Db.open(ctx.io, ctx.config.db_path) catch |err| {
        std.debug.print("cloudio serve db open failed: {s}\n", .{@errorName(err)});
        stream.close(ctx.io);
        return;
    };
    defer db.close();
    var thread_ctx = ctx;
    thread_ctx.db = &db;
    handleConnection(thread_ctx, stream, dashboard_options) catch |err| {
        std.debug.print("cloudio serve request failed: {s}\n", .{@errorName(err)});
    };
}

const Request = struct {
    method: []const u8 = "",
    target: []const u8 = "",
    content_length: ?usize = null,
    cookie: []const u8 = "",
    authorization: []const u8 = "",
    accept: []const u8 = "",
    body: []const u8 = "",
};

const Handler = enum {
    dashboard,
    topology,
    inventory,
    actions_plan,
    audit,
    login,
    events_ping,
    events_changes,
    caddy_routes_get,
    caddy_routes_post,
    caddy_routes_delete,
    caddy_routes_toggle,
    caddy_preview,
    caddy_apply,
    caddy_import,
    dns_records_get,
    dns_records_post,
    dns_records_put,
    dns_records_delete,
    cache_purge,
    zone_setting,
    vps_get,
    vps_action,
    firewalls_get,
    firewall_rule_post,
    firewall_rule_put,
    firewall_rule_delete,
    firewall_sync,
    containers_get,
    containers_action,
    containers_logs,
    refresh_now,
    apps_get,
    apps_post,
    apps_sub_get,
    apps_sub_post,
    apps_delete,
    events_deploy,
};

const Route = struct {
    method: []const u8,
    path: []const u8,
    handler: Handler,
    /// Prefix routes match `path` plus a trailing segment (e.g. /api/apps/<id>).
    prefix: bool = false,
    /// Public routes skip bearer/cookie auth.
    public: bool = false,
    /// SSE routes stream text/event-stream instead of a buffered JSON body.
    sse: bool = false,
};

const routes = [_]Route{
    .{ .method = "GET", .path = "/api/dashboard", .handler = .dashboard },
    .{ .method = "GET", .path = "/api/topology", .handler = .topology },
    .{ .method = "GET", .path = "/api/inventory", .handler = .inventory },
    .{ .method = "POST", .path = "/api/actions/plan", .handler = .actions_plan },
    .{ .method = "GET", .path = "/api/audit", .handler = .audit },
    .{ .method = "POST", .path = "/api/login", .handler = .login, .public = true },
    .{ .method = "GET", .path = "/api/events/ping", .handler = .events_ping, .sse = true },
    .{ .method = "GET", .path = "/api/events/changes", .handler = .events_changes, .sse = true },
    .{ .method = "GET", .path = "/api/caddy/routes", .handler = .caddy_routes_get },
    .{ .method = "POST", .path = "/api/caddy/routes", .handler = .caddy_routes_post },
    .{ .method = "DELETE", .path = "/api/caddy/routes", .handler = .caddy_routes_delete },
    .{ .method = "POST", .path = "/api/caddy/routes/toggle", .handler = .caddy_routes_toggle },
    .{ .method = "GET", .path = "/api/caddy/preview", .handler = .caddy_preview },
    .{ .method = "POST", .path = "/api/caddy/apply", .handler = .caddy_apply },
    .{ .method = "POST", .path = "/api/caddy/import", .handler = .caddy_import },
    .{ .method = "GET", .path = "/api/dns/records", .handler = .dns_records_get },
    .{ .method = "POST", .path = "/api/dns/records", .handler = .dns_records_post },
    .{ .method = "PUT", .path = "/api/dns/records", .handler = .dns_records_put },
    .{ .method = "DELETE", .path = "/api/dns/records", .handler = .dns_records_delete },
    .{ .method = "POST", .path = "/api/cache/purge", .handler = .cache_purge },
    .{ .method = "POST", .path = "/api/zone/setting", .handler = .zone_setting },
    .{ .method = "GET", .path = "/api/vps", .handler = .vps_get },
    .{ .method = "POST", .path = "/api/vps/action", .handler = .vps_action },
    .{ .method = "GET", .path = "/api/firewalls", .handler = .firewalls_get },
    .{ .method = "POST", .path = "/api/firewall/rule", .handler = .firewall_rule_post },
    .{ .method = "PUT", .path = "/api/firewall/rule", .handler = .firewall_rule_put },
    .{ .method = "DELETE", .path = "/api/firewall/rule", .handler = .firewall_rule_delete },
    .{ .method = "POST", .path = "/api/firewall/sync", .handler = .firewall_sync },
    .{ .method = "GET", .path = "/api/containers", .handler = .containers_get },
    .{ .method = "POST", .path = "/api/containers/action", .handler = .containers_action },
    .{ .method = "GET", .path = "/api/containers/logs", .handler = .containers_logs },
    .{ .method = "POST", .path = "/api/refresh", .handler = .refresh_now },
    .{ .method = "GET", .path = "/api/apps", .handler = .apps_get },
    .{ .method = "POST", .path = "/api/apps", .handler = .apps_post },
    .{ .method = "GET", .path = "/api/apps/", .handler = .apps_sub_get, .prefix = true },
    .{ .method = "POST", .path = "/api/apps/", .handler = .apps_sub_post, .prefix = true },
    .{ .method = "DELETE", .path = "/api/apps/", .handler = .apps_delete, .prefix = true },
    .{ .method = "GET", .path = "/api/events/deploy/", .handler = .events_deploy, .prefix = true, .sse = true },
};

fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |route| {
        if (!std.mem.eql(u8, route.method, method)) continue;
        if (route.prefix) {
            if (std.mem.startsWith(u8, path, route.path)) return route;
        } else if (std.mem.eql(u8, route.path, path)) {
            return route;
        }
    }
    return null;
}

fn pathHasAnyMethod(path: []const u8) bool {
    for (routes) |route| {
        if (route.prefix) {
            if (std.mem.startsWith(u8, path, route.path)) return true;
        } else if (std.mem.eql(u8, route.path, path)) {
            return true;
        }
    }
    return false;
}

fn handleConnection(ctx: Context, stream: std.Io.net.Stream, dashboard_options: app_dashboard.Options) !void {
    defer stream.close(ctx.io);
    var read_buffer: [8192]u8 = undefined;
    var reader = stream.reader(ctx.io, &read_buffer);
    var write_buffer: [8192]u8 = undefined;
    var stream_writer = stream.writer(ctx.io, &write_buffer);
    const out = &stream_writer.interface;

    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const maybe_request = readRequest(arena, &reader.interface) catch |err| switch (err) {
        error.BadRequest => {
            try writeResponse(out, 400, "application/json", "", "{\"error\":\"bad_request\"}\n");
            return;
        },
        error.BodyTooLarge => {
            try writeResponse(out, 413, "application/json", "", "{\"error\":\"payload_too_large\"}\n");
            return;
        },
        else => return err,
    };
    const request = maybe_request orelse return;
    const path = pathOnly(request.target);
    const authed = blk: {
        const token = ctx.config.platform_token orelse break :blk true;
        break :blk isAuthorized(request, token);
    };

    if (std.mem.startsWith(u8, path, "/api/")) {
        const route = matchRoute(request.method, path) orelse {
            if (pathHasAnyMethod(path)) {
                try writeResponse(out, 405, "application/json", "", "{\"error\":\"method_not_allowed\"}\n");
            } else {
                try writeResponse(out, 404, "application/json", "", "{\"error\":\"not_found\"}\n");
            }
            return;
        };
        if (!route.public and !authed) {
            try writeResponse(out, 401, "application/json", "", "{\"error\":\"unauthorized\"}\n");
            return;
        }
        if (route.sse or std.mem.startsWith(u8, std.mem.trim(u8, request.accept, " "), "text/event-stream")) {
            try handleSse(ctx, route.handler, request, out);
            return;
        }
        var body = std.Io.Writer.Allocating.init(ctx.gpa);
        defer body.deinit();
        var extra_headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer extra_headers.deinit();
        const status = dispatchApi(ctx, request, route.handler, dashboard_options, &body.writer, &extra_headers.writer) catch |err| {
            std.debug.print("cloudio serve handler {s} failed: {s}\n", .{ @tagName(route.handler), @errorName(err) });
            try writeResponse(out, 500, "application/json", "", "{\"error\":\"internal\"}\n");
            return;
        };
        try writeResponse(out, status, "application/json", extra_headers.written(), body.written());
        return;
    }

    if (!std.mem.eql(u8, request.method, "GET")) {
        try writeResponse(out, 405, "application/json", "", "{\"error\":\"method_not_allowed\"}\n");
        return;
    }
    if (!authed and !staticPathIsPublic(path)) {
        try writeResponse(out, 302, "text/html", "Location: /login.html\r\n", "");
        return;
    }
    try serveStatic(ctx, path, out);
}

const ReadRequestError = error{ BadRequest, BodyTooLarge, ReadFailed, StreamTooLong } || std.Io.Reader.ReadAllocError;

/// Returns null when the client closed the connection before sending a request.
fn readRequest(arena: Allocator, reader: *std.Io.Reader) ReadRequestError!?Request {
    const line = (try reader.takeDelimiter('\n')) orelse return null;
    const parsed = parseRequestLine(line) orelse return error.BadRequest;
    var request = Request{
        .method = try arena.dupe(u8, parsed.method),
        .target = try arena.dupe(u8, parsed.target),
    };
    while (true) {
        const header_line = (try reader.takeDelimiter('\n')) orelse break;
        const trimmed = trimLineEnding(header_line);
        if (trimmed.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const name = std.mem.trim(u8, trimmed[0..colon], " \t");
        const value = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            request.content_length = std.fmt.parseInt(usize, value, 10) catch return error.BadRequest;
        } else if (std.ascii.eqlIgnoreCase(name, "cookie")) {
            request.cookie = try arena.dupe(u8, value);
        } else if (std.ascii.eqlIgnoreCase(name, "authorization")) {
            request.authorization = try arena.dupe(u8, value);
        } else if (std.ascii.eqlIgnoreCase(name, "accept")) {
            request.accept = try arena.dupe(u8, value);
        }
    }
    if (request.content_length) |len| {
        if (len > max_request_body_bytes) return error.BodyTooLarge;
        request.body = try reader.readAlloc(arena, len);
    }
    return request;
}

fn dispatchApi(ctx: Context, request: Request, handler: Handler, dashboard_defaults: app_dashboard.Options, writer: *std.Io.Writer, extra_headers: *std.Io.Writer) !u16 {
    switch (handler) {
        .dashboard => {
            const options = dashboardOptionsFromQuery(request.target, dashboard_defaults);
            try app_dashboard.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, options, writer);
            return 200;
        },
        .topology => {
            const options = dashboardOptionsFromQuery(request.target, dashboard_defaults);
            try app_topology.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .limit = options.limit }, writer);
            return 200;
        },
        .inventory => {
            const options = dashboardOptionsFromQuery(request.target, dashboard_defaults);
            try app_inventory.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = options.domain, .limit = options.limit }, writer);
            return 200;
        },
        .actions_plan => {
            const options = dashboardOptionsFromQuery(request.target, dashboard_defaults);
            try app_actions.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = options.domain, .limit = options.limit }, writer);
            return 200;
        },
        .audit => {
            const limit: i64 = blk: {
                const raw = queryParam(request.target, "limit") orelse break :blk 200;
                break :blk std.fmt.parseInt(i64, raw, 10) catch 200;
            };
            try app_writes.writeAuditJson(ctx.gpa, ctx.db, limit, writer);
            return 200;
        },
        .login => return handleLogin(ctx, request, writer, extra_headers),
        .events_ping, .events_changes => unreachable, // routed through handleSse
        .caddy_routes_get => {
            try app_caddy_desired.writeRoutesJson(caddyCtx(ctx), writer);
            return 200;
        },
        .caddy_routes_post => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const host = strField(parsed.value, "host") orelse return badRequest(writer);
            try app_caddy_desired.upsertRoute(caddyCtx(ctx), host, strField(parsed.value, "upstream"), "manual", strField(parsed.value, "extra_directives"), null, null);
            try writer.writeAll("{\"ok\":true}\n");
            return 200;
        },
        .caddy_routes_delete => {
            const host = queryParam(request.target, "host") orelse return badRequest(writer);
            try app_caddy_desired.deleteRoute(caddyCtx(ctx), host);
            try writer.writeAll("{\"ok\":true}\n");
            return 200;
        },
        .caddy_routes_toggle => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const host = strField(parsed.value, "host") orelse return badRequest(writer);
            const enabled = boolField(parsed.value, "enabled") orelse return badRequest(writer);
            try app_caddy_desired.setEnabled(caddyCtx(ctx), host, enabled);
            try writer.writeAll("{\"ok\":true}\n");
            return 200;
        },
        .caddy_preview => {
            try app_caddy_desired.writePreviewJson(caddyCtx(ctx), writer);
            return 200;
        },
        .caddy_apply => {
            const result = app_caddy_desired.apply(caddyCtx(ctx), ctx.config.caddyfile_path, .{}) catch |err| switch (err) {
                error.ValidateFailed => {
                    try writer.writeAll("{\"ok\":false,\"error\":\"validate_failed\"}\n");
                    return 422;
                },
                else => return err,
            };
            defer result.deinit(ctx.gpa);
            try writer.writeAll("{\"ok\":true,");
            try core_json.writeBoolField(writer, "validated", result.validated, true);
            try core_json.writeBoolField(writer, "reloaded", result.reloaded, true);
            try core_json.writeIntField(writer, "bytes", result.bytes, true);
            try core_json.writeNullableStringField(writer, "backup_path", result.backup_path, false);
            try writer.writeAll("}\n");
            return 200;
        },
        .caddy_import => {
            const summary = try app_caddy_desired.importCaddyfile(caddyCtx(ctx), ctx.config.caddyfile_path);
            try writer.writeAll("{\"ok\":true,");
            try core_json.writeIntField(writer, "imported_manual", summary.imported_manual, true);
            try core_json.writeIntField(writer, "imported_raw", summary.imported_raw, true);
            try core_json.writeIntField(writer, "skipped_app", summary.skipped_app, false);
            try writer.writeAll("}\n");
            return 200;
        },
        .dns_records_get => {
            try writeDnsRecordsJson(ctx, queryParam(request.target, "domain"), writer);
            return 200;
        },
        .dns_records_post => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const zone_id = strField(parsed.value, "zone_id") orelse return badRequest(writer);
            const record = core_json.field(parsed.value, "record") orelse return badRequest(writer);
            const record_json = try core_json.stringifyValue(ctx.gpa, record);
            defer ctx.gpa.free(record_json);
            try app_provider_writes.dnsRecordCreate(providerCtx(ctx), zone_id, record_json, writer);
            return 200;
        },
        .dns_records_put => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const zone_id = strField(parsed.value, "zone_id") orelse return badRequest(writer);
            const record_id = strField(parsed.value, "record_id") orelse return badRequest(writer);
            const record = core_json.field(parsed.value, "record") orelse return badRequest(writer);
            const record_json = try core_json.stringifyValue(ctx.gpa, record);
            defer ctx.gpa.free(record_json);
            try app_provider_writes.dnsRecordUpdate(providerCtx(ctx), zone_id, record_id, record_json, writer);
            return 200;
        },
        .dns_records_delete => {
            const zone_id = queryParam(request.target, "zone_id") orelse return badRequest(writer);
            const record_id = queryParam(request.target, "record_id") orelse return badRequest(writer);
            try app_provider_writes.dnsRecordDelete(providerCtx(ctx), zone_id, record_id, writer);
            return 200;
        },
        .cache_purge => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const zone_id = strField(parsed.value, "zone_id") orelse return badRequest(writer);
            try app_provider_writes.cachePurgeEverything(providerCtx(ctx), zone_id, writer);
            return 200;
        },
        .zone_setting => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const zone_id = strField(parsed.value, "zone_id") orelse return badRequest(writer);
            const setting = strField(parsed.value, "setting") orelse return badRequest(writer);
            const value = core_json.field(parsed.value, "value") orelse return badRequest(writer);
            const value_json = try core_json.stringifyValue(ctx.gpa, value);
            defer ctx.gpa.free(value_json);
            try app_provider_writes.zoneSettingUpdate(providerCtx(ctx), zone_id, setting, value_json, writer);
            return 200;
        },
        .vps_get => {
            var rows = try ctx.db.hostingerVpsRows(ctx.gpa, 100);
            defer rows.deinit(ctx.gpa);
            try writer.writeAll("{\"kind\":\"vps\",\"machines\":[");
            for (rows.items, 0..) |row, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeByte('{');
                try core_json.writeStringField(writer, "id", row.id, true);
                try core_json.writeStringField(writer, "name", row.name, true);
                try core_json.writeStringField(writer, "status", row.status, true);
                try core_json.writeStringField(writer, "ipv4", row.ipv4, true);
                try core_json.writeStringField(writer, "plan", row.plan, false);
                try writer.writeByte('}');
            }
            try writer.writeAll("]}\n");
            return 200;
        },
        .vps_action => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const vm_id = strField(parsed.value, "vm_id") orelse return badRequest(writer);
            const action_text = strField(parsed.value, "action") orelse return badRequest(writer);
            const action = std.meta.stringToEnum(app_provider_writes.VpsAction, action_text) orelse return badRequest(writer);
            try app_provider_writes.vpsAction(providerCtx(ctx), vm_id, action, writer);
            return 200;
        },
        .firewalls_get => {
            var rows = try ctx.db.hostingerResourceHints(ctx.gpa, 5000);
            defer rows.deinit(ctx.gpa);
            try writer.writeAll("{\"kind\":\"firewalls\",\"firewalls\":[");
            var first = true;
            for (rows.items) |row| {
                if (std.ascii.indexOfIgnoreCase(row.kind, "firewall") == null) continue;
                if (!first) try writer.writeByte(',');
                first = false;
                try writer.writeByte('{');
                try core_json.writeStringField(writer, "kind", row.kind, true);
                try core_json.writeStringField(writer, "id", row.resource_id, true);
                try core_json.writeStringField(writer, "name", row.name, true);
                try core_json.writeStringField(writer, "status", row.status, true);
                try core_json.writeStringField(writer, "target", row.target, false);
                try writer.writeByte('}');
            }
            try writer.writeAll("]}\n");
            return 200;
        },
        .firewall_rule_post => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const firewall_id = strField(parsed.value, "firewall_id") orelse return badRequest(writer);
            const rule = core_json.field(parsed.value, "rule") orelse return badRequest(writer);
            const rule_json = try core_json.stringifyValue(ctx.gpa, rule);
            defer ctx.gpa.free(rule_json);
            try app_provider_writes.firewallRuleCreate(providerCtx(ctx), firewall_id, rule_json, writer);
            return 200;
        },
        .firewall_rule_put => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const firewall_id = strField(parsed.value, "firewall_id") orelse return badRequest(writer);
            const rule_id = strField(parsed.value, "rule_id") orelse return badRequest(writer);
            const rule = core_json.field(parsed.value, "rule") orelse return badRequest(writer);
            const rule_json = try core_json.stringifyValue(ctx.gpa, rule);
            defer ctx.gpa.free(rule_json);
            try app_provider_writes.firewallRuleUpdate(providerCtx(ctx), firewall_id, rule_id, rule_json, writer);
            return 200;
        },
        .firewall_rule_delete => {
            const firewall_id = queryParam(request.target, "firewall_id") orelse return badRequest(writer);
            const rule_id = queryParam(request.target, "rule_id") orelse return badRequest(writer);
            try app_provider_writes.firewallRuleDelete(providerCtx(ctx), firewall_id, rule_id, writer);
            return 200;
        },
        .firewall_sync => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const firewall_id = strField(parsed.value, "firewall_id") orelse return badRequest(writer);
            const vm_id = strField(parsed.value, "vm_id") orelse return badRequest(writer);
            try app_provider_writes.firewallSync(providerCtx(ctx), firewall_id, vm_id, writer);
            return 200;
        },
        .containers_get => {
            var rows = try ctx.db.containerRows(ctx.gpa, 200);
            defer rows.deinit(ctx.gpa);
            try writer.writeAll("{\"kind\":\"containers\",\"containers\":[");
            for (rows.items, 0..) |row, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeByte('{');
                try core_json.writeStringField(writer, "name", row.name, true);
                try core_json.writeStringField(writer, "image", row.image, true);
                try core_json.writeStringField(writer, "status", row.status, true);
                try core_json.writeStringField(writer, "ports", row.ports, false);
                try writer.writeByte('}');
            }
            try writer.writeAll("]}\n");
            return 200;
        },
        .containers_action => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const name = strField(parsed.value, "name") orelse return badRequest(writer);
            const action_text = strField(parsed.value, "action") orelse return badRequest(writer);
            const action = std.meta.stringToEnum(app_system_control.ContainerAction, action_text) orelse return badRequest(writer);
            try app_system_control.containerAction(systemCtx(ctx), name, action, writer);
            return 200;
        },
        .containers_logs => {
            const name = queryParam(request.target, "name") orelse return badRequest(writer);
            const tail: i64 = blk: {
                const raw = queryParam(request.target, "tail") orelse break :blk 100;
                break :blk std.fmt.parseInt(i64, raw, 10) catch 100;
            };
            try app_system_control.containerLogs(systemCtx(ctx), name, tail, writer);
            return 200;
        },
        .refresh_now => {
            try runRefresh(ctx);
            _ = refresh_epoch.fetchAdd(1, .monotonic);
            try writer.writeAll("{\"ok\":true}\n");
            return 200;
        },
        .apps_get => {
            try app_deploy.writeAppsJson(deployCtx(ctx), writer);
            return 200;
        },
        .apps_post => {
            var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
            defer parsed.deinit();
            const name = strField(parsed.value, "name") orelse return badRequest(writer);
            try app_deploy.registerApp(deployCtx(ctx), name, strField(parsed.value, "repo_url"), strField(parsed.value, "workdir"), writer);
            return 200;
        },
        .apps_sub_get => {
            const sub = appSubPath(pathOnly(request.target)) orelse return badRequest(writer);
            if (std.mem.eql(u8, sub.action, "deploys")) {
                const limit: i64 = blk: {
                    const raw = queryParam(request.target, "limit") orelse break :blk 50;
                    break :blk std.fmt.parseInt(i64, raw, 10) catch 50;
                };
                try app_deploy.writeDeploysJson(deployCtx(ctx), sub.name, limit, writer);
                return 200;
            }
            if (std.mem.eql(u8, sub.action, "log")) {
                const deploy_id_raw = queryParam(request.target, "deploy_id") orelse return badRequest(writer);
                const deploy_id = std.fmt.parseInt(i64, deploy_id_raw, 10) catch return badRequest(writer);
                try app_deploy.readDeployLog(deployCtx(ctx), sub.name, deploy_id, writer);
                return 200;
            }
            return error.UnknownRoute;
        },
        .apps_sub_post => {
            const sub = appSubPath(pathOnly(request.target)) orelse return badRequest(writer);
            if (std.mem.eql(u8, sub.action, "deploy")) {
                try app_deploy.deploy(deployCtx(ctx), sub.name, .{}, writer);
                _ = refresh_epoch.fetchAdd(1, .monotonic);
                return 200;
            }
            if (std.mem.eql(u8, sub.action, "rollback")) {
                var deploy_id: ?i64 = null;
                if (jsonBody(ctx.gpa, request.body)) |parsed_const| {
                    var parsed = parsed_const;
                    defer parsed.deinit();
                    deploy_id = core_json.fieldInt(parsed.value, "deploy_id");
                }
                try app_deploy.rollback(deployCtx(ctx), sub.name, deploy_id, .{}, writer);
                return 200;
            }
            if (std.mem.eql(u8, sub.action, "service")) {
                var parsed = jsonBody(ctx.gpa, request.body) orelse return badRequest(writer);
                defer parsed.deinit();
                const action_text = strField(parsed.value, "action") orelse return badRequest(writer);
                const action = std.meta.stringToEnum(app_system_control.ServiceAction, action_text) orelse return badRequest(writer);
                const unit = app_system_control.unitName(ctx.gpa, sub.name) catch return badRequest(writer);
                defer ctx.gpa.free(unit);
                try app_system_control.serviceAction(systemCtx(ctx), unit, action, writer);
                return 200;
            }
            return error.UnknownRoute;
        },
        .apps_delete => {
            const name = std.mem.trimEnd(u8, pathOnly(request.target)["/api/apps/".len..], "/");
            if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return badRequest(writer);
            try app_deploy.deleteApp(deployCtx(ctx), name, writer);
            return 200;
        },
        .events_deploy => unreachable, // routed through handleSse
    }
}

const AppSubPath = struct {
    name: []const u8,
    action: []const u8,
};

/// Splits /api/apps/<name>/<action> into its parts.
fn appSubPath(path: []const u8) ?AppSubPath {
    const rest = path["/api/apps/".len..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const name = rest[0..slash];
    const action = std.mem.trimEnd(u8, rest[slash + 1 ..], "/");
    if (name.len == 0 or action.len == 0) return null;
    return .{ .name = name, .action = action };
}

fn deployCtx(ctx: Context) app_deploy.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config };
}

fn caddyCtx(ctx: Context) app_caddy_desired.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db };
}

fn providerCtx(ctx: Context) app_provider_writes.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config };
}

fn systemCtx(ctx: Context) app_system_control.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db };
}

fn badRequest(writer: *std.Io.Writer) !u16 {
    try writer.writeAll("{\"error\":\"bad_request\"}\n");
    return 400;
}

fn jsonBody(gpa: Allocator, body: []const u8) ?std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    if (parsed.value != .object) {
        parsed.deinit();
        return null;
    }
    return parsed;
}

fn strField(value: std.json.Value, name: []const u8) ?[]const u8 {
    return core_json.fieldString(value, name);
}

fn boolField(value: std.json.Value, name: []const u8) ?bool {
    return core_json.fieldBool(value, name);
}

fn writeDnsRecordsJson(ctx: Context, domain: ?[]const u8, writer: *std.Io.Writer) !void {
    var zones = try ctx.db.cloudflareZoneRows(ctx.gpa, 50);
    defer zones.deinit(ctx.gpa);
    var zone_id: []const u8 = "";
    if (domain) |d| {
        for (zones.items) |zone| {
            if (std.mem.eql(u8, zone.name, d)) zone_id = zone.id;
        }
    } else if (zones.items.len > 0) {
        zone_id = zones.items[0].id;
    }

    var rows = try ctx.db.cloudflareDnsRecordRows(ctx.gpa, 1000);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"dns_records\",");
    try core_json.writeStringField(writer, "zone_id", zone_id, true);
    try writer.writeAll("\"records\":[");
    var first = true;
    for (rows.items) |row| {
        if (domain) |d| {
            if (!dnsNameMatchesDomain(row.name, d)) continue;
        }
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", row.id, true);
        try core_json.writeStringField(writer, "zone_id", row.zone_id, true);
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "type", row.record_type, true);
        try core_json.writeStringField(writer, "content", row.content, true);
        const ttl: ?i64 = std.fmt.parseInt(i64, row.ttl, 10) catch null;
        try core_json.writeString(writer, "ttl");
        try writer.writeByte(':');
        if (ttl) |t| try writer.print("{d}", .{t}) else try writer.writeAll("null");
        try writer.writeByte(',');
        try core_json.writeString(writer, "proxied");
        try writer.writeByte(':');
        if (std.mem.eql(u8, row.proxied, "true")) {
            try writer.writeAll("true");
        } else if (std.mem.eql(u8, row.proxied, "false")) {
            try writer.writeAll("false");
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn dnsNameMatchesDomain(name: []const u8, domain: []const u8) bool {
    if (std.mem.eql(u8, name, domain)) return true;
    if (name.len > domain.len + 1 and std.mem.endsWith(u8, name, domain) and name[name.len - domain.len - 1] == '.') return true;
    return false;
}

fn runRefresh(ctx: Context) !void {
    try app_refresh.run(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .domains = ctx.config.domains,
        .cloudflare_auth = .{
            .token = ctx.config.cloudflare_api_token,
            .email = ctx.config.cloudflare_email,
            .key = ctx.config.cloudflare_api_key,
        },
        .hostinger_token = ctx.config.hostinger_api_token,
        .caddy_paths = .{
            .caddyfile_path = ctx.config.caddyfile_path,
            .caddy_sites_path = ctx.config.caddy_sites_path,
            .caddy_admin_socket = ctx.config.caddy_admin_socket,
        },
        .projects_root = ctx.config.projects_root,
        .log = .{
            .version = "serve",
            .db_path = ctx.config.db_path,
            .config_path = ctx.config.config_path,
            .log_path = ctx.config.log_path,
            .loaded_dotenv = ctx.config.loaded_dotenv,
            .loaded_fish_env = ctx.config.loaded_fish_env,
            .cloudflare_auth = ctx.config.hasCloudflareAuth(),
            .hostinger_auth = ctx.config.hasHostingerAuth(),
        },
    }, .{});
}

fn handleLogin(ctx: Context, request: Request, writer: *std.Io.Writer, extra_headers: *std.Io.Writer) !u16 {
    const token = ctx.config.platform_token orelse {
        try writer.writeAll("{\"error\":\"login_disabled\"}\n");
        return 400;
    };
    const provided = loginTokenFromBody(ctx.gpa, request.body) orelse {
        try writer.writeAll("{\"error\":\"bad_request\"}\n");
        return 400;
    };
    defer ctx.gpa.free(provided);
    if (!tokenEquals(provided, token)) {
        try writer.writeAll("{\"error\":\"unauthorized\"}\n");
        return 401;
    }
    try extra_headers.print("Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Strict\r\n", .{ auth_cookie_name, token });
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

fn loginTokenFromBody(gpa: Allocator, body: []const u8) ?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const value = parsed.value.object.get("token") orelse return null;
    if (value != .string) return null;
    return gpa.dupe(u8, value.string) catch null;
}

/// Minimal server-sent-events writer. Response headers are written by begin;
/// each writeEvent emits one event frame and flushes immediately.
pub const SseStream = struct {
    out: *std.Io.Writer,

    pub fn begin(out: *std.Io.Writer) !SseStream {
        try out.writeAll("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n");
        try out.flush();
        return .{ .out = out };
    }

    pub fn writeEvent(self: SseStream, event_name: ?[]const u8, payload: []const u8) !void {
        if (event_name) |name| try self.out.print("event: {s}\n", .{name});
        try self.out.print("data: {s}\n\n", .{payload});
        try self.out.flush();
    }
};

fn handleSse(ctx: Context, handler: Handler, request: Request, out: *std.Io.Writer) !void {
    var sse = try SseStream.begin(out);
    switch (handler) {
        .events_ping => try sse.writeEvent(null, "{\"ok\":true}"),
        .events_changes => try streamChanges(ctx, sse),
        .events_deploy => try streamDeployLog(ctx, request, sse),
        else => try sse.writeEvent("error", "{\"error\":\"not_streamable\"}"),
    }
}

/// Tails the latest deploy log for an app: emits new log content as `log`
/// events while the deploy row stays `running`, then a final `done` event.
fn streamDeployLog(ctx: Context, request: Request, sse: SseStream) !void {
    const name = std.mem.trimEnd(u8, pathOnly(request.target)["/api/events/deploy/".len..], "/");
    if (name.len == 0 or !app_deploy.isValidAppName(name)) {
        try sse.writeEvent("error", "{\"error\":\"bad_app_name\"}");
        return;
    }
    var offset: usize = 0;
    var iterations: usize = 0;
    // ~10 minutes at 500ms per poll.
    while (iterations < 1200) : (iterations += 1) {
        const status = app_deploy.latestDeployStatus(deployCtx(ctx), name) catch null;
        const chunk = app_deploy.readDeployLogTailFrom(deployCtx(ctx), name, &offset) catch null;
        if (chunk) |text| {
            defer ctx.gpa.free(text);
            if (text.len > 0) {
                var lines = std.mem.splitScalar(u8, text, '\n');
                while (lines.next()) |line| {
                    if (line.len == 0) continue;
                    var buf = std.Io.Writer.Allocating.init(ctx.gpa);
                    defer buf.deinit();
                    try core_json.writeString(&buf.writer, line);
                    try sse.writeEvent("log", buf.written());
                }
            }
        }
        const status_text = status orelse "unknown";
        if (!std.mem.eql(u8, status_text, "running")) {
            var buf = std.Io.Writer.Allocating.init(ctx.gpa);
            defer buf.deinit();
            try buf.writer.writeAll("{\"status\":");
            try core_json.writeString(&buf.writer, status_text);
            try buf.writer.writeByte('}');
            try sse.writeEvent("done", buf.written());
            return;
        }
        ctx.io.sleep(.fromNanoseconds(500 * std.time.ns_per_ms), .awake) catch return;
    }
}

/// Push a refresh event whenever the refresh epoch advances; closes after
/// ~5 minutes so stale connections do not pile up (the UI reconnects).
fn streamChanges(ctx: Context, sse: SseStream) !void {
    var last = refresh_epoch.load(.monotonic);
    var payload_buf: [64]u8 = undefined;
    try sse.writeEvent("epoch", std.fmt.bufPrint(&payload_buf, "{{\"epoch\":{d}}}", .{last}) catch unreachable);
    var iterations: usize = 0;
    while (iterations < 150) : (iterations += 1) {
        ctx.io.sleep(.fromNanoseconds(2 * std.time.ns_per_s), .awake) catch return;
        const current = refresh_epoch.load(.monotonic);
        if (current != last) {
            last = current;
            try sse.writeEvent("refresh", std.fmt.bufPrint(&payload_buf, "{{\"epoch\":{d}}}", .{current}) catch unreachable);
        }
    }
}

fn refreshScheduler(ctx: Context) void {
    while (true) {
        const seconds: u64 = @max(ctx.config.refresh_seconds, 30);
        ctx.io.sleep(.fromNanoseconds(seconds * std.time.ns_per_s), .awake) catch return;
        var db = Db.open(ctx.io, ctx.config.db_path) catch |err| {
            std.debug.print("cloudio scheduler db open failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer db.close();
        var refresh_ctx = ctx;
        refresh_ctx.db = &db;
        runRefresh(refresh_ctx) catch |err| {
            std.debug.print("cloudio scheduled refresh failed: {s}\n", .{@errorName(err)});
            continue;
        };
        _ = refresh_epoch.fetchAdd(1, .monotonic);
    }
}

fn isAuthorized(request: Request, token: []const u8) bool {
    if (bearerToken(request.authorization)) |candidate| {
        if (tokenEquals(candidate, token)) return true;
    }
    if (cookieValue(request.cookie, auth_cookie_name)) |candidate| {
        if (tokenEquals(candidate, token)) return true;
    }
    return false;
}

fn bearerToken(authorization: []const u8) ?[]const u8 {
    const prefix = "Bearer ";
    if (!std.mem.startsWith(u8, authorization, prefix)) return null;
    const token = std.mem.trim(u8, authorization[prefix.len..], " \t");
    if (token.len == 0) return null;
    return token;
}

fn cookieValue(cookie_header: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, cookie_header, ';');
    while (it.next()) |pair_raw| {
        const pair = std.mem.trim(u8, pair_raw, " \t");
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, pair[0..eq], " \t"), name)) {
            return pair[eq + 1 ..];
        }
    }
    return null;
}

fn tokenEquals(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var acc: u8 = 0;
    for (a, b) |x, y| acc |= x ^ y;
    return acc == 0;
}

fn staticPathIsPublic(path: []const u8) bool {
    // Unauthenticated GET / redirects to the login page rather than 401.
    return std.mem.eql(u8, path, "/login.html") or std.mem.startsWith(u8, path, "/assets/");
}

fn isPathSafe(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "..") == null;
}

fn serveStatic(ctx: Context, path: []const u8, out: *std.Io.Writer) !void {
    if (!isPathSafe(path)) {
        try writeResponse(out, 403, "application/json", "", "{\"error\":\"forbidden\"}\n");
        return;
    }
    const rel = if (std.mem.eql(u8, path, "/")) "/index.html" else path;
    const full = try std.fmt.allocPrint(ctx.gpa, web_root ++ "{s}", .{rel});
    defer ctx.gpa.free(full);
    const data = Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(max_static_file_bytes)) catch |err| switch (err) {
        error.FileNotFound, error.IsDir, error.AccessDenied => {
            try writeResponse(out, 404, "application/json", "", "{\"error\":\"not_found\"}\n");
            return;
        },
        else => |e| return e,
    };
    defer ctx.gpa.free(data);
    try writeResponse(out, 200, contentTypeFor(rel), "", data);
}

fn contentTypeFor(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    const map = .{
        .{ ".html", "text/html; charset=utf-8" },
        .{ ".css", "text/css" },
        .{ ".js", "text/javascript" },
        .{ ".svg", "image/svg+xml" },
        .{ ".png", "image/png" },
        .{ ".ico", "image/x-icon" },
        .{ ".json", "application/json" },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, ext, entry[0])) return entry[1];
    }
    return "application/octet-stream";
}

fn writeResponse(out: *std.Io.Writer, status: u16, content_type: []const u8, extra_headers: []const u8, body: []const u8) !void {
    try out.print("HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n{s}Connection: close\r\n\r\n", .{ status, statusText(status), content_type, body.len, extra_headers });
    try out.writeAll(body);
    try out.flush();
}

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        302 => "Found",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        else => "Error",
    };
}

const RequestLine = struct {
    method: []const u8,
    target: []const u8,
};

fn parseRequestLine(line: []const u8) ?RequestLine {
    const trimmed = trimLineEnding(line);
    var it = std.mem.splitScalar(u8, trimmed, ' ');
    const method = it.next() orelse return null;
    const target = it.next() orelse return null;
    if (method.len == 0 or target.len == 0) return null;
    return .{ .method = method, .target = target };
}

fn pathOnly(target: []const u8) []const u8 {
    const index = std.mem.indexOfScalar(u8, target, '?') orelse return target;
    return target[0..index];
}

fn trimLineEnding(line: []const u8) []const u8 {
    if (line.len != 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const query_start = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var it = std.mem.splitScalar(u8, target[query_start + 1 ..], '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        if (std.mem.eql(u8, pair[0..equals], key)) {
            return if (equals < pair.len) pair[equals + 1 ..] else "";
        }
    }
    return null;
}

fn dashboardOptionsFromQuery(target: []const u8, defaults: app_dashboard.Options) app_dashboard.Options {
    var out = defaults;
    const query_start = std.mem.indexOfScalar(u8, target, '?') orelse return out;
    var it = std.mem.splitScalar(u8, target[query_start + 1 ..], '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const key = pair[0..equals];
        const value = if (equals < pair.len) pair[equals + 1 ..] else "";
        if (std.mem.eql(u8, key, "domain")) out.domain = value;
        if (std.mem.eql(u8, key, "issues")) out.issues_only = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
        if (std.mem.eql(u8, key, "section")) out.section = app_dashboard.Section.parse(value) orelse out.section;
        if (std.mem.eql(u8, key, "limit")) out.limit = std.fmt.parseInt(i64, value, 10) catch out.limit;
    }
    return out.normalized();
}

test "serve request parser maps request targets" {
    const line = "GET /api/dashboard?domain=plosca.ru HTTP/1.1\r";
    const parsed = parseRequestLine(line).?;
    try std.testing.expectEqualStrings("GET", parsed.method);
    try std.testing.expectEqualStrings("/api/dashboard?domain=plosca.ru", parsed.target);
    try std.testing.expectEqualStrings("/api/dashboard", pathOnly(parsed.target));
    const options = dashboardOptionsFromQuery(parsed.target, .{});
    try std.testing.expectEqualStrings("plosca.ru", options.domain.?);
}

test "readRequest captures headers and body" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const raw = "POST /api/login HTTP/1.1\r\nContent-Length: 18\r\nCookie: a=b; cloudio_token=t0k\r\nAuthorization: Bearer abc\r\nAccept: text/event-stream\r\n\r\n{\"token\":\"secret\"}";
    var reader = std.Io.Reader.fixed(raw);
    const request = (try readRequest(arena_state.allocator(), &reader)).?;
    try std.testing.expectEqualStrings("POST", request.method);
    try std.testing.expectEqualStrings("/api/login", request.target);
    try std.testing.expectEqual(@as(?usize, 18), request.content_length);
    try std.testing.expectEqualStrings("{\"token\":\"secret\"}", request.body);
    try std.testing.expectEqualStrings("Bearer abc", request.authorization);
    try std.testing.expectEqualStrings("text/event-stream", request.accept);
    try std.testing.expectEqualStrings("t0k", cookieValue(request.cookie, auth_cookie_name).?);
}

test "readRequest rejects oversized bodies" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const raw = "POST /api/login HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n";
    var reader = std.Io.Reader.fixed(raw);
    try std.testing.expectError(error.BodyTooLarge, readRequest(arena_state.allocator(), &reader));
}

test "cookie extraction finds token among other cookies" {
    try std.testing.expectEqualStrings("abc", cookieValue("x=1; cloudio_token=abc; y=2", auth_cookie_name).?);
    try std.testing.expectEqualStrings("abc", cookieValue("cloudio_token=abc", auth_cookie_name).?);
    try std.testing.expect(cookieValue("cloudio_tokenish=abc", auth_cookie_name) == null);
    try std.testing.expect(cookieValue("", auth_cookie_name) == null);
}

test "path traversal is rejected" {
    try std.testing.expect(!isPathSafe("/../etc/passwd"));
    try std.testing.expect(!isPathSafe("/assets/../../secret"));
    try std.testing.expect(isPathSafe("/assets/app.js"));
    try std.testing.expect(isPathSafe("/index.html"));
}

test "route matching handles exact paths methods and unknowns" {
    try std.testing.expectEqual(Handler.dashboard, matchRoute("GET", "/api/dashboard").?.handler);
    try std.testing.expectEqual(Handler.actions_plan, matchRoute("POST", "/api/actions/plan").?.handler);
    try std.testing.expectEqual(Handler.audit, matchRoute("GET", "/api/audit").?.handler);
    try std.testing.expectEqual(Handler.login, matchRoute("POST", "/api/login").?.handler);
    try std.testing.expect(matchRoute("POST", "/api/login").?.public);
    try std.testing.expect(matchRoute("GET", "/api/events/ping").?.sse);
    try std.testing.expect(matchRoute("GET", "/api/actions/plan") == null);
    try std.testing.expect(pathHasAnyMethod("/api/actions/plan"));
    try std.testing.expect(matchRoute("GET", "/api/nope") == null);
    try std.testing.expect(!pathHasAnyMethod("/api/nope"));
}

test "login token compare is length and content sensitive" {
    try std.testing.expect(tokenEquals("secret", "secret"));
    try std.testing.expect(!tokenEquals("secret", "secreT"));
    try std.testing.expect(!tokenEquals("secret", "secre"));
    try std.testing.expect(!tokenEquals("", "x"));
    try std.testing.expect(tokenEquals("", ""));
}

test "login body parsing extracts token" {
    const gpa = std.testing.allocator;
    const token = loginTokenFromBody(gpa, "{\"token\":\"abc\"}").?;
    defer gpa.free(token);
    try std.testing.expectEqualStrings("abc", token);
    try std.testing.expect(loginTokenFromBody(gpa, "{\"token\":1}") == null);
    try std.testing.expect(loginTokenFromBody(gpa, "not json") == null);
    try std.testing.expect(loginTokenFromBody(gpa, "{}") == null);
}

test "content type mapping covers known extensions" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", contentTypeFor("/index.html"));
    try std.testing.expectEqualStrings("text/css", contentTypeFor("/assets/app.css"));
    try std.testing.expectEqualStrings("text/javascript", contentTypeFor("/assets/app.js"));
    try std.testing.expectEqualStrings("image/svg+xml", contentTypeFor("/logo.svg"));
    try std.testing.expectEqualStrings("image/png", contentTypeFor("/logo.png"));
    try std.testing.expectEqualStrings("image/x-icon", contentTypeFor("/favicon.ico"));
    try std.testing.expectEqualStrings("application/json", contentTypeFor("/data.json"));
    try std.testing.expectEqualStrings("application/octet-stream", contentTypeFor("/file.bin"));
}

test "bearer token parsing" {
    try std.testing.expectEqualStrings("abc", bearerToken("Bearer abc").?);
    try std.testing.expect(bearerToken("Basic abc") == null);
    try std.testing.expect(bearerToken("Bearer ") == null);
    try std.testing.expect(bearerToken("") == null);
}
