const std = @import("std");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_limit = 200;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const Options = struct {
    domain: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    target: ?[]const u8 = null,
    action: ?[]const u8 = null,
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .domain = self.domain,
            .provider = self.provider,
            .target = self.target,
            .action = self.action,
            .limit = app_render.positiveLimit(self.limit, default_limit),
        };
    }
};

pub fn writeJson(ctx: Context, options: Options, writer: anytype) !void {
    const normalized = options.normalized();
    try writer.writeAll("{\"kind\":\"action_plans\",");
    try writeRequestJson(normalized, writer);
    try writer.writeAll(",\"filters\":");
    try writeFilterMetadataJson(writer);
    try writer.writeAll(",\"toggles\":");
    try writeToggleMetadataJson(writer);
    try writer.writeAll(",\"plans\":[");

    var first = true;
    try writeCaddyPlans(ctx, normalized, writer, &first);
    try writeSystemdPlans(ctx, normalized, writer, &first);
    try writeDockerPlans(ctx, normalized, writer, &first);
    try writeCloudflarePlans(ctx, normalized, writer, &first);
    try writeHostingerPlans(ctx, normalized, writer, &first);

    try writer.writeAll("]}\n");
}

pub fn writeFilterMetadataJson(writer: anytype) !void {
    try writer.writeAll("[");
    try writeFilter(writer, "domain", "text", "Domain or host suffix", true);
    try writeFilter(writer, "provider", "enum", "Provider or local subsystem", true);
    try writeFilter(writer, "status", "enum", "Inventory health or runtime status", true);
    try writeFilter(writer, "issue", "enum", "Topology or provider issue type", true);
    try writeFilter(writer, "service_running", "bool", "systemd service running state", true);
    try writeFilter(writer, "container_running", "bool", "Docker container running state", true);
    try writeFilter(writer, "exposure", "enum", "public, local, internal, or unknown", true);
    try writeFilter(writer, "proxied", "enum", "Cloudflare proxied or DNS-only state", false);
    try writer.writeAll("]");
}

pub fn writeToggleMetadataJson(writer: anytype) !void {
    try writer.writeAll("[");
    try writeToggle(writer, "caddy.site.enable", "caddy", "site", "enable", true);
    try writeToggle(writer, "caddy.site.disable", "caddy", "site", "disable", true);
    try writeToggle(writer, "caddy.render", "caddy", "config", "render", true);
    try writeToggle(writer, "caddy.diff", "caddy", "config", "diff", true);
    try writeToggle(writer, "caddy.validate", "caddy", "config", "validate", true);
    try writeToggle(writer, "systemd.status", "systemd", "service", "status", true);
    try writeToggle(writer, "systemd.restart", "systemd", "service", "restart", true);
    try writeToggle(writer, "systemd.logs", "systemd", "service", "logs", true);
    try writeToggle(writer, "docker.status", "docker", "container", "status", true);
    try writeToggle(writer, "docker.restart", "docker", "container", "restart", true);
    try writeToggle(writer, "docker.logs", "docker", "container", "logs", true);
    try writeToggle(writer, "cloudflare.dns.proxied", "cloudflare", "dns_record", "toggle_proxied", true);
    try writeToggle(writer, "cloudflare.dns.a_record_update", "cloudflare", "dns_record", "update_a_record", true);
    try writeToggle(writer, "hostinger.vps.reboot", "hostinger", "vps", "reboot", true);
    try writeToggle(writer, "hostinger.vps.shutdown", "hostinger", "vps", "shutdown", true);
    try writeToggle(writer, "hostinger.vps.snapshot", "hostinger", "vps", "snapshot", true);
    try writeToggle(writer, "hostinger.vps.firewall", "hostinger", "vps", "firewall", false);
    try writer.writeAll("]");
}

fn writeCaddyPlans(ctx: Context, options: Options, writer: anytype, first: *bool) !void {
    if (!includeProvider(options, "caddy")) return;
    try writePlan(writer, first, .{
        .id = "caddy.render",
        .provider = "caddy",
        .resource_type = "config",
        .action = "render",
        .target = options.domain orelse "all",
        .title = "Render Caddy config",
        .plan = "cloudio caddy render --json",
        .destructive = false,
        .requires_confirmation = false,
        .available = true,
        .reason = "renders the current Caddyfile workflow without writing or reloading",
    });
    try writePlan(writer, first, .{
        .id = "caddy.diff",
        .provider = "caddy",
        .resource_type = "config",
        .action = "diff",
        .target = options.domain orelse "all",
        .title = "Diff rendered Caddy config",
        .plan = "cloudio caddy diff --json",
        .destructive = false,
        .requires_confirmation = false,
        .available = true,
        .reason = "dry-run config diff only",
    });
    try writePlan(writer, first, .{
        .id = "caddy.validate",
        .provider = "caddy",
        .resource_type = "config",
        .action = "validate",
        .target = options.domain orelse "all",
        .title = "Validate Caddy config",
        .plan = "cloudio caddy validate --json",
        .destructive = false,
        .requires_confirmation = false,
        .available = true,
        .reason = "validation does not write or reload Caddy",
    });

    var rows = try ctx.db.caddyUpstreams(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    for (rows.items) |row| {
        if (!includeDomain(options, row.name)) continue;
        if (!includeTarget(options, row.name)) continue;
        const target = if (row.name.len != 0) row.name else row.value;
        const enable_id = try std.fmt.allocPrint(ctx.gpa, "caddy.site.enable:{s}", .{target});
        defer ctx.gpa.free(enable_id);
        const disable_id = try std.fmt.allocPrint(ctx.gpa, "caddy.site.disable:{s}", .{target});
        defer ctx.gpa.free(disable_id);
        const enable_plan = try std.fmt.allocPrint(ctx.gpa, "plan only: enable rendered Caddy site for {s}", .{target});
        defer ctx.gpa.free(enable_plan);
        const disable_plan = try std.fmt.allocPrint(ctx.gpa, "plan only: disable rendered Caddy site for {s}", .{target});
        defer ctx.gpa.free(disable_plan);
        try writePlan(writer, first, .{
            .id = enable_id,
            .provider = "caddy",
            .resource_type = "site",
            .action = "enable",
            .target = target,
            .title = "Enable Caddy site",
            .plan = enable_plan,
            .destructive = false,
            .requires_confirmation = true,
            .available = true,
            .reason = "dry-run plan only; no file writes or reloads",
        });
        try writePlan(writer, first, .{
            .id = disable_id,
            .provider = "caddy",
            .resource_type = "site",
            .action = "disable",
            .target = target,
            .title = "Disable Caddy site",
            .plan = disable_plan,
            .destructive = true,
            .requires_confirmation = true,
            .available = true,
            .reason = "dry-run plan only; no file writes or reloads",
        });
    }
}

fn writeSystemdPlans(ctx: Context, options: Options, writer: anytype, first: *bool) !void {
    if (!includeProvider(options, "systemd") and !includeProvider(options, "system")) return;
    var rows = try ctx.db.serviceList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    var written: i64 = 0;
    for (rows.items) |row| {
        if (written >= options.limit) break;
        if (!includeTarget(options, row.name)) continue;
        try writeRuntimePlans(ctx, writer, first, "systemd", "service", row.name, "systemctl status", "journalctl -u", "systemctl restart");
        written += 1;
    }
}

fn writeDockerPlans(ctx: Context, options: Options, writer: anytype, first: *bool) !void {
    if (!includeProvider(options, "docker")) return;
    var rows = try ctx.db.containerList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    var written: i64 = 0;
    for (rows.items) |row| {
        if (written >= options.limit) break;
        if (!includeTarget(options, row.name)) continue;
        try writeRuntimePlans(ctx, writer, first, "docker", "container", row.name, "docker inspect", "docker logs", "docker restart");
        written += 1;
    }
}

fn writeCloudflarePlans(ctx: Context, options: Options, writer: anytype, first: *bool) !void {
    if (!includeProvider(options, "cloudflare")) return;
    var records = try ctx.db.cloudflareDnsRecordRows(ctx.gpa, options.limit);
    defer records.deinit(ctx.gpa);
    for (records.items) |row| {
        if (!includeDomain(options, row.name)) continue;
        if (!includeTarget(options, row.id) and !includeTarget(options, row.name)) continue;
        if (!std.ascii.eqlIgnoreCase(row.record_type, "A") and !std.ascii.eqlIgnoreCase(row.record_type, "AAAA")) continue;
        const proxied_id = try std.fmt.allocPrint(ctx.gpa, "cloudflare.dns.proxied:{s}", .{row.id});
        defer ctx.gpa.free(proxied_id);
        const update_id = try std.fmt.allocPrint(ctx.gpa, "cloudflare.dns.a_record_update:{s}", .{row.id});
        defer ctx.gpa.free(update_id);
        const proxied_plan = try std.fmt.allocPrint(ctx.gpa, "plan only: toggle Cloudflare proxied flag for DNS record {s} ({s})", .{ row.name, row.id });
        defer ctx.gpa.free(proxied_plan);
        const update_plan = try std.fmt.allocPrint(ctx.gpa, "plan only: update Cloudflare {s} record {s} ({s})", .{ row.record_type, row.name, row.id });
        defer ctx.gpa.free(update_plan);
        try writePlan(writer, first, .{
            .id = proxied_id,
            .provider = "cloudflare",
            .resource_type = "dns_record",
            .action = "toggle_proxied",
            .target = row.name,
            .title = "Toggle Cloudflare proxy",
            .plan = proxied_plan,
            .destructive = false,
            .requires_confirmation = true,
            .available = true,
            .reason = "dry-run plan only; no Cloudflare mutation",
        });
        try writePlan(writer, first, .{
            .id = update_id,
            .provider = "cloudflare",
            .resource_type = "dns_record",
            .action = "update_a_record",
            .target = row.name,
            .title = "Update Cloudflare address record",
            .plan = update_plan,
            .destructive = false,
            .requires_confirmation = true,
            .available = true,
            .reason = "dry-run plan only; no Cloudflare mutation",
        });
    }
}

fn writeHostingerPlans(ctx: Context, options: Options, writer: anytype, first: *bool) !void {
    if (!includeProvider(options, "hostinger")) return;
    var rows = try ctx.db.hostingerVpsRows(ctx.gpa, options.limit);
    defer rows.deinit(ctx.gpa);
    for (rows.items) |row| {
        if (!includeTarget(options, row.id) and !includeTarget(options, row.name) and !includeTarget(options, row.ipv4)) continue;
        try writeHostingerVpsPlan(ctx, writer, first, row, "reboot", false);
        try writeHostingerVpsPlan(ctx, writer, first, row, "shutdown", true);
        try writeHostingerVpsPlan(ctx, writer, first, row, "snapshot", false);
        try writeHostingerVpsPlan(ctx, writer, first, row, "firewall", false);
    }
}

fn writeRuntimePlans(ctx: Context, writer: anytype, first: *bool, provider: []const u8, resource_type: []const u8, target: []const u8, status_cmd: []const u8, logs_cmd: []const u8, restart_cmd: []const u8) !void {
    const status_id = try std.fmt.allocPrint(ctx.gpa, "{s}.status:{s}", .{ provider, target });
    defer ctx.gpa.free(status_id);
    const logs_id = try std.fmt.allocPrint(ctx.gpa, "{s}.logs:{s}", .{ provider, target });
    defer ctx.gpa.free(logs_id);
    const restart_id = try std.fmt.allocPrint(ctx.gpa, "{s}.restart:{s}", .{ provider, target });
    defer ctx.gpa.free(restart_id);
    const status_plan = try std.fmt.allocPrint(ctx.gpa, "{s} {s}", .{ status_cmd, target });
    defer ctx.gpa.free(status_plan);
    const logs_plan = try std.fmt.allocPrint(ctx.gpa, "{s} {s}", .{ logs_cmd, target });
    defer ctx.gpa.free(logs_plan);
    const restart_plan = try std.fmt.allocPrint(ctx.gpa, "plan only: {s} {s}", .{ restart_cmd, target });
    defer ctx.gpa.free(restart_plan);
    try writePlan(writer, first, .{
        .id = status_id,
        .provider = provider,
        .resource_type = resource_type,
        .action = "status",
        .target = target,
        .title = "Read runtime status",
        .plan = status_plan,
        .destructive = false,
        .requires_confirmation = false,
        .available = true,
        .reason = "read-only status command",
    });
    try writePlan(writer, first, .{
        .id = logs_id,
        .provider = provider,
        .resource_type = resource_type,
        .action = "logs",
        .target = target,
        .title = "Read runtime logs",
        .plan = logs_plan,
        .destructive = false,
        .requires_confirmation = false,
        .available = true,
        .reason = "bounded read-only log request",
    });
    try writePlan(writer, first, .{
        .id = restart_id,
        .provider = provider,
        .resource_type = resource_type,
        .action = "restart",
        .target = target,
        .title = "Restart runtime target",
        .plan = restart_plan,
        .destructive = true,
        .requires_confirmation = true,
        .available = true,
        .reason = "dry-run plan only; restart is not executed",
    });
}

fn writeHostingerVpsPlan(ctx: Context, writer: anytype, first: *bool, row: db_store.HostingerVpsRow, action: []const u8, destructive: bool) !void {
    const id = try std.fmt.allocPrint(ctx.gpa, "hostinger.vps.{s}:{s}", .{ action, row.id });
    defer ctx.gpa.free(id);
    const plan = try std.fmt.allocPrint(ctx.gpa, "plan only: Hostinger VPS {s} for {s}", .{ action, row.id });
    defer ctx.gpa.free(plan);
    const title = try std.fmt.allocPrint(ctx.gpa, "Hostinger VPS {s}", .{action});
    defer ctx.gpa.free(title);
    try writePlan(writer, first, .{
        .id = id,
        .provider = "hostinger",
        .resource_type = "vps",
        .action = action,
        .target = row.id,
        .title = title,
        .plan = plan,
        .destructive = destructive,
        .requires_confirmation = true,
        .available = true,
        .reason = "dry-run plan only; no Hostinger mutation",
    });
}

const PlanView = struct {
    id: []const u8,
    provider: []const u8,
    resource_type: []const u8,
    action: []const u8,
    target: []const u8,
    title: []const u8,
    plan: []const u8,
    destructive: bool,
    requires_confirmation: bool,
    available: bool,
    reason: []const u8,
};

fn writePlan(writer: anytype, first: *bool, plan: PlanView) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", plan.id, true);
    try app_render.writeJsonStringField(writer, "provider", plan.provider, true);
    try app_render.writeJsonStringField(writer, "resource_type", plan.resource_type, true);
    try app_render.writeJsonStringField(writer, "action", plan.action, true);
    try app_render.writeJsonStringField(writer, "target", plan.target, true);
    try app_render.writeJsonStringField(writer, "title", plan.title, true);
    try app_render.writeJsonStringField(writer, "mode", "dry_run", true);
    try app_render.writeJsonBoolField(writer, "mutates_live", false, true);
    try app_render.writeJsonBoolField(writer, "destructive", plan.destructive, true);
    try app_render.writeJsonBoolField(writer, "requires_confirmation", plan.requires_confirmation, true);
    try app_render.writeJsonBoolField(writer, "available", plan.available, true);
    try app_render.writeJsonStringField(writer, "reason", plan.reason, true);
    try app_render.writeJsonStringField(writer, "plan", plan.plan, false);
    try writer.writeByte('}');
}

fn writeRequestJson(options: Options, writer: anytype) !void {
    try writer.writeAll("\"request\":{");
    try app_render.writeJsonNullableStringField(writer, "domain", options.domain, true);
    try app_render.writeJsonNullableStringField(writer, "provider", options.provider, true);
    try app_render.writeJsonNullableStringField(writer, "target", options.target, true);
    try app_render.writeJsonNullableStringField(writer, "action", options.action, true);
    try app_render.writeJsonIntField(writer, "limit", options.limit, false);
    try writer.writeByte('}');
}

fn writeFilter(writer: anytype, id: []const u8, kind: []const u8, label: []const u8, trailing_comma: bool) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", id, true);
    try app_render.writeJsonStringField(writer, "type", kind, true);
    try app_render.writeJsonStringField(writer, "label", label, false);
    try writer.writeByte('}');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeToggle(writer: anytype, id: []const u8, provider: []const u8, resource: []const u8, action: []const u8, trailing_comma: bool) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", id, true);
    try app_render.writeJsonStringField(writer, "provider", provider, true);
    try app_render.writeJsonStringField(writer, "resource_type", resource, true);
    try app_render.writeJsonStringField(writer, "action", action, true);
    try app_render.writeJsonStringField(writer, "mode", "dry_run_plan", false);
    try writer.writeByte('}');
    if (trailing_comma) try writer.writeByte(',');
}

fn includeProvider(options: Options, provider: []const u8) bool {
    const requested = options.provider orelse return true;
    return std.ascii.eqlIgnoreCase(requested, provider);
}

fn includeTarget(options: Options, value: []const u8) bool {
    const requested = options.target orelse return true;
    return value.len != 0 and containsIgnoreCase(value, requested);
}

fn includeDomain(options: Options, value: []const u8) bool {
    const requested = options.domain orelse return true;
    return domainMatches(value, requested);
}

fn domainMatches(value: []const u8, domain: []const u8) bool {
    if (domain.len == 0) return true;
    if (std.ascii.eqlIgnoreCase(value, domain)) return true;
    if (value.len > domain.len and std.ascii.endsWithIgnoreCase(value, domain) and value[value.len - domain.len - 1] == '.') return true;
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

test "actions emit dry-run planner metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-actions.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertDnsRecord("record-1", "zone-1", "plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertService("plosca.service", "user", "active", "running", "plosca", "raw");
    try db.upsertContainer("plosca", "plosca:latest", "Up", "9327/tcp", "raw");
    try db.upsertHostingerVps("123", "vps", "running", "76.13.130.170", "KVM", "{}");
    try db.insertCaddyUpstream("plosca.ru", "", "127.0.0.1:9327");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJson(.{ .gpa = allocator, .db = &db }, .{ .domain = "plosca.ru" }, &out.writer);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"action_plans\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mode\":\"dry_run\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare.dns.proxied:record-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger.vps.reboot:123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger.vps.firewall:123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"caddy.site.disable:plosca.ru\"") != null);
}
