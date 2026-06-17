const std = @import("std");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const max_manifest_bytes = 8 * 1024 * 1024;

pub const cloudflare_base_url = "https://api.cloudflare.com/client/v4";
pub const hostinger_base_url = "https://developers.hostinger.com";

pub const Paths = struct {
    cloudflare_manifest: []const u8 = "coverage/generated/cloudflare.jsonl",
    hostinger_manifest: []const u8 = "coverage/generated/hostinger.jsonl",

    pub fn manifestPath(self: Paths, provider: Provider) []const u8 {
        return switch (provider) {
            .cloudflare => self.cloudflare_manifest,
            .hostinger => self.hostinger_manifest,
        };
    }
};

pub const Provider = enum {
    cloudflare,
    hostinger,

    pub fn parse(value: []const u8) ?Provider {
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        return null;
    }

    pub fn name(self: Provider) []const u8 {
        return @tagName(self);
    }

    pub fn baseUrl(self: Provider) []const u8 {
        return switch (self) {
            .cloudflare => cloudflare_base_url,
            .hostinger => hostinger_base_url,
        };
    }
};

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,

    pub fn parse(value: []const u8) ?Method {
        inline for (std.meta.fields(Method)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn name(self: Method) []const u8 {
        return @tagName(self);
    }
};

pub const Support = enum {
    implemented,
    partial,
    planned,
    blocked_permission,
    unsafe_mutation,
    deprecated,
    not_applicable,

    pub fn parse(value: []const u8) ?Support {
        inline for (std.meta.fields(Support)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const Mode = enum {
    read,
    dry_run,
    write,
    none,

    pub fn parse(value: []const u8) ?Mode {
        inline for (std.meta.fields(Mode)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const PathParam = struct {
    name: []const u8,
    value: []const u8,
};

pub const Route = struct {
    provider: Provider,
    tag: []u8,
    method: Method,
    path_template: []u8,
    operation_id: ?[]u8,
    support: Support,
    mode: Mode,
    deprecated: bool,

    pub fn init(gpa: Allocator, expected_provider: Provider, value: std.json.Value) !Route {
        const provider_name = core_json.fieldString(value, "provider") orelse return error.InvalidProviderRoute;
        const provider = Provider.parse(provider_name) orelse return error.InvalidProviderRoute;
        if (provider != expected_provider) return error.InvalidProviderRoute;

        const tag = core_json.fieldString(value, "tag") orelse return error.InvalidProviderRoute;
        const method_text = core_json.fieldString(value, "method") orelse return error.InvalidProviderRoute;
        const path = core_json.fieldString(value, "path") orelse return error.InvalidProviderRoute;
        const operation_id = core_json.fieldString(value, "operation_id");
        const support_text = core_json.fieldString(value, "support") orelse return error.InvalidProviderRoute;
        const mode_text = core_json.fieldString(value, "mode") orelse return error.InvalidProviderRoute;
        const deprecated = core_json.fieldBool(value, "deprecated") orelse return error.InvalidProviderRoute;

        const tag_owned = try gpa.dupe(u8, tag);
        errdefer gpa.free(tag_owned);
        const path_owned = try gpa.dupe(u8, path);
        errdefer gpa.free(path_owned);
        const operation_id_owned = if (operation_id) |id| try gpa.dupe(u8, id) else null;
        errdefer if (operation_id_owned) |id| gpa.free(id);

        return .{
            .provider = provider,
            .tag = tag_owned,
            .method = Method.parse(method_text) orelse return error.InvalidProviderRoute,
            .path_template = path_owned,
            .operation_id = operation_id_owned,
            .support = Support.parse(support_text) orelse return error.InvalidProviderRoute,
            .mode = Mode.parse(mode_text) orelse return error.InvalidProviderRoute,
            .deprecated = deprecated,
        };
    }

    pub fn deinit(self: Route, gpa: Allocator) void {
        gpa.free(self.tag);
        gpa.free(self.path_template);
        if (self.operation_id) |id| gpa.free(id);
    }

    pub fn isRoutable(self: Route) bool {
        return !self.deprecated and self.support != .not_applicable and self.mode != .none;
    }

    pub fn isDryRunMutation(self: Route) bool {
        return self.mode == .dry_run and self.method != .GET and self.method != .HEAD;
    }

    pub fn parameterNames(self: Route, gpa: Allocator) ![][]u8 {
        return try templateParameterNames(gpa, self.path_template);
    }

    pub fn renderPath(self: Route, gpa: Allocator, params: []const PathParam) ![]u8 {
        return try renderTemplatePath(gpa, self.path_template, params);
    }

    pub fn renderUrl(self: Route, gpa: Allocator, base_url_override: ?[]const u8, params: []const PathParam) ![]u8 {
        const path = try self.renderPath(gpa, params);
        defer gpa.free(path);
        const base_url = base_url_override orelse self.provider.baseUrl();
        return try std.fmt.allocPrint(gpa, "{s}{s}", .{ base_url, path });
    }
};

pub const RouteSet = struct {
    items: []Route,

    pub fn deinit(self: *RouteSet, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn findByOperationId(self: RouteSet, operation_id: []const u8) ?*const Route {
        for (self.items) |*row| {
            if (row.operation_id) |id| {
                if (std.mem.eql(u8, id, operation_id)) return row;
            }
        }
        return null;
    }

    pub fn findByTemplate(self: RouteSet, method: Method, path_template: []const u8) ?*const Route {
        for (self.items) |*row| {
            if (row.method == method and std.mem.eql(u8, row.path_template, path_template)) return row;
        }
        return null;
    }

    pub fn countRoutable(self: RouteSet) usize {
        var count: usize = 0;
        for (self.items) |row| {
            if (row.isRoutable()) count += 1;
        }
        return count;
    }
};

pub fn loadProvider(io: Io, gpa: Allocator, paths: Paths, provider: Provider) !RouteSet {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try loadProviderFromText(gpa, provider, text);
}

pub fn loadProviderFromText(gpa: Allocator, provider: Provider, text: []const u8) !RouteSet {
    var rows = std.ArrayList(Route).empty;
    errdefer deinitRouteList(&rows, gpa);
    try appendProvider(gpa, provider, text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadAll(io: Io, gpa: Allocator, paths: Paths) !RouteSet {
    const cloudflare_text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(cloudflare_text);
    const hostinger_text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(hostinger_text);
    return try loadAllFromText(gpa, cloudflare_text, hostinger_text);
}

pub fn loadAllFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !RouteSet {
    var rows = std.ArrayList(Route).empty;
    errdefer deinitRouteList(&rows, gpa);
    try appendProvider(gpa, .cloudflare, cloudflare_text, &rows);
    try appendProvider(gpa, .hostinger, hostinger_text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn findByOperationId(io: Io, gpa: Allocator, paths: Paths, provider: Provider, operation_id: []const u8) !?Route {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try findByOperationIdFromText(gpa, provider, text, operation_id);
}

pub fn findByOperationIdFromText(gpa: Allocator, provider: Provider, text: []const u8, operation_id: []const u8) !?Route {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_operation_id = core_json.fieldString(parsed.value, "operation_id") orelse continue;
        if (!std.mem.eql(u8, row_operation_id, operation_id)) continue;
        return try Route.init(gpa, provider, parsed.value);
    }
    return null;
}

pub fn findByTemplate(io: Io, gpa: Allocator, paths: Paths, provider: Provider, method: Method, path_template: []const u8) !?Route {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try findByTemplateFromText(gpa, provider, text, method, path_template);
}

pub fn findByTemplateFromText(gpa: Allocator, provider: Provider, text: []const u8, method: Method, path_template: []const u8) !?Route {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_method = Method.parse(core_json.fieldString(parsed.value, "method") orelse return error.InvalidProviderRoute) orelse return error.InvalidProviderRoute;
        if (row_method != method) continue;
        const row_path = core_json.fieldString(parsed.value, "path") orelse return error.InvalidProviderRoute;
        if (!std.mem.eql(u8, row_path, path_template)) continue;
        return try Route.init(gpa, provider, parsed.value);
    }
    return null;
}

pub fn templateParameterNames(gpa: Allocator, path_template: []const u8) ![][]u8 {
    var names = std.ArrayList([]u8).empty;
    errdefer deinitParamNames(&names, gpa);

    var index: usize = 0;
    while (index < path_template.len) {
        const open_rel = std.mem.indexOfScalar(u8, path_template[index..], '{') orelse break;
        const open = index + open_rel;
        if (std.mem.indexOfScalar(u8, path_template[index..open], '}') != null) return error.InvalidRouteTemplate;
        const close_rel = std.mem.indexOfScalar(u8, path_template[open + 1 ..], '}') orelse return error.InvalidRouteTemplate;
        const close = open + 1 + close_rel;
        const name = path_template[open + 1 .. close];
        if (name.len == 0) return error.InvalidRouteTemplate;
        if (!containsParamName(names.items, name)) {
            const owned = try gpa.dupe(u8, name);
            errdefer gpa.free(owned);
            try names.append(gpa, owned);
        }
        index = close + 1;
    }
    if (std.mem.indexOfScalar(u8, path_template[index..], '}') != null) return error.InvalidRouteTemplate;
    return try names.toOwnedSlice(gpa);
}

pub fn freeParameterNames(gpa: Allocator, names: [][]u8) void {
    for (names) |name| gpa.free(name);
    gpa.free(names);
}

pub fn renderTemplatePath(gpa: Allocator, path_template: []const u8, params: []const PathParam) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();

    var index: usize = 0;
    while (index < path_template.len) {
        const open_rel = std.mem.indexOfScalar(u8, path_template[index..], '{') orelse {
            if (std.mem.indexOfScalar(u8, path_template[index..], '}') != null) return error.InvalidRouteTemplate;
            try out.writer.writeAll(path_template[index..]);
            return try out.toOwnedSlice();
        };
        const open = index + open_rel;
        if (std.mem.indexOfScalar(u8, path_template[index..open], '}') != null) return error.InvalidRouteTemplate;
        try out.writer.writeAll(path_template[index..open]);

        const close_rel = std.mem.indexOfScalar(u8, path_template[open + 1 ..], '}') orelse return error.InvalidRouteTemplate;
        const close = open + 1 + close_rel;
        const name = path_template[open + 1 .. close];
        if (name.len == 0) return error.InvalidRouteTemplate;

        const value = findParam(params, name) orelse return error.MissingRouteParameter;
        const escaped = try pathEscape(gpa, value);
        defer gpa.free(escaped);
        try out.writer.writeAll(escaped);
        index = close + 1;
    }
    return try out.toOwnedSlice();
}

pub fn pathEscape(gpa: Allocator, value: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try (std.Uri.Component{ .raw = value }).formatEscaped(&out.writer);
    return try out.toOwnedSlice();
}

fn appendProvider(gpa: Allocator, provider: Provider, text: []const u8, rows: *std.ArrayList(Route)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row = try Route.init(gpa, provider, parsed.value);
        errdefer row.deinit(gpa);
        try rows.append(gpa, row);
    }
}

fn deinitRouteList(rows: *std.ArrayList(Route), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitParamNames(rows: *std.ArrayList([]u8), gpa: Allocator) void {
    for (rows.items) |name| gpa.free(name);
    rows.deinit(gpa);
}

fn containsParamName(names: []const []u8, candidate: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn findParam(params: []const PathParam, name: []const u8) ?[]const u8 {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return param.value;
    }
    return null;
}

test "loads generated route metadata for both providers" {
    const allocator = std.testing.allocator;
    var routes = try loadAll(std.testing.io, allocator, .{});
    defer routes.deinit(allocator);

    try std.testing.expect(routes.items.len > 3000);
    try std.testing.expect(routes.countRoutable() > 3000);

    const cloudflare_accounts = routes.findByOperationId("accounts-list-accounts") orelse return error.TestExpectedRoute;
    try std.testing.expectEqual(Provider.cloudflare, cloudflare_accounts.provider);
    try std.testing.expectEqual(Method.GET, cloudflare_accounts.method);
    try std.testing.expectEqualStrings("/accounts", cloudflare_accounts.path_template);

    const hostinger_vps = routes.findByOperationId("VPS_getVirtualMachinesV1") orelse return error.TestExpectedRoute;
    try std.testing.expectEqual(Provider.hostinger, hostinger_vps.provider);
    try std.testing.expectEqual(Method.GET, hostinger_vps.method);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines", hostinger_vps.path_template);
}

test "finds routes by operation id and template without loading full tables" {
    const allocator = std.testing.allocator;

    const cloudflare_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-get-an-access-application")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    try std.testing.expectEqualStrings("Access applications", cloudflare_route.tag);
    try std.testing.expect(cloudflare_route.isRoutable());

    const hostinger_route = (try findByTemplate(std.testing.io, allocator, .{}, .hostinger, .GET, "/api/vps/v1/virtual-machines/{virtualMachineId}/metrics")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    try std.testing.expectEqualStrings("VPS: Virtual machine", hostinger_route.tag);
    try std.testing.expect(hostinger_route.isRoutable());
}

test "extracts required path parameters and renders escaped route paths" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-get-an-access-application")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const names = try route.parameterNames(allocator);
    defer freeParameterNames(allocator, names);
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("account_id", names[0]);
    try std.testing.expectEqualStrings("app_id", names[1]);

    const path = try route.renderPath(allocator, &.{
        .{ .name = "account_id", .value = "acct/1" },
        .{ .name = "app_id", .value = "app 1" },
    });
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/access/apps/app%201", path);

    const url = try route.renderUrl(allocator, "https://example.test", &.{
        .{ .name = "account_id", .value = "acct/1" },
        .{ .name = "app_id", .value = "app 1" },
    });
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://example.test/accounts/acct%2F1/access/apps/app%201", url);
}

test "reports missing parameters and invalid templates" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingRouteParameter, renderTemplatePath(allocator, "/accounts/{account_id}", &.{}));
    try std.testing.expectError(error.InvalidRouteTemplate, renderTemplatePath(allocator, "/accounts/{account_id", &.{.{ .name = "account_id", .value = "acct" }}));
    try std.testing.expectError(error.InvalidRouteTemplate, templateParameterNames(allocator, "/accounts/}"));
}
