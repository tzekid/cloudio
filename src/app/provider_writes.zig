//! B2: typed provider mutation helpers (Cloudflare DNS/cache/settings, Hostinger VPS/firewall/DNS).
//! Every helper performs the live HTTP call, records an audit_actions row via
//! app_writes.record, and writes {"ok":bool,"status":N,"result":...} JSON to
//! the supplied writer. Response bodies are redacted before storage/echo.
const std = @import("std");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_json = @import("core_json");
const core_redact = @import("core_redact");
const db_store = @import("db_store");
const net_http = @import("net_http");
const cf_transport = @import("provider_cloudflare_transport");
const hostinger_transport = @import("provider_hostinger_transport");

const Allocator = std.mem.Allocator;

pub const cloudflare_base = "https://api.cloudflare.com/client/v4";
pub const hostinger_base = "https://developers.hostinger.com";

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
};

pub const VpsAction = enum {
    start,
    stop,
    restart,

    pub fn pathSegment(self: VpsAction) []const u8 {
        return @tagName(self);
    }

    pub fn auditKind(self: VpsAction) []const u8 {
        return switch (self) {
            .start => "hostinger.vps.start",
            .stop => "hostinger.vps.stop",
            .restart => "hostinger.vps.restart",
        };
    }
};

const Call = struct {
    method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
    kind: []const u8,
    target: []const u8,
};

// --- Cloudflare helpers ---

pub fn dnsRecordCreate(ctx: Context, zone_id: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try cfDnsRecordsUrl(ctx.gpa, zone_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .POST, .url = url, .body = body_json, .kind = "cf.dns.create", .target = zone_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeCloudflare(ctx, call, writer);
}

pub fn dnsRecordUpdate(ctx: Context, zone_id: []const u8, record_id: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try cfDnsRecordUrl(ctx.gpa, zone_id, record_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .PUT, .url = url, .body = body_json, .kind = "cf.dns.update", .target = zone_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeCloudflare(ctx, call, writer);
}

pub fn dnsRecordDelete(ctx: Context, zone_id: []const u8, record_id: []const u8, writer: anytype) !void {
    const url = try cfDnsRecordUrl(ctx.gpa, zone_id, record_id);
    defer ctx.gpa.free(url);
    try executeCloudflare(ctx, .{ .method = .DELETE, .url = url, .body = null, .kind = "cf.dns.delete", .target = zone_id }, writer);
}

pub fn cachePurgeEverything(ctx: Context, zone_id: []const u8, writer: anytype) !void {
    const url = try cfPurgeCacheUrl(ctx.gpa, zone_id);
    defer ctx.gpa.free(url);
    const body = "{\"purge_everything\":true}";
    try executeCloudflare(ctx, .{ .method = .POST, .url = url, .body = body, .kind = "cf.cache.purge", .target = zone_id }, writer);
}

pub fn zoneSettingUpdate(ctx: Context, zone_id: []const u8, setting: []const u8, value_json: []const u8, writer: anytype) !void {
    const url = try cfZoneSettingUrl(ctx.gpa, zone_id, setting);
    defer ctx.gpa.free(url);
    var probe_call: Call = .{ .method = .PATCH, .url = url, .body = value_json, .kind = "cf.setting.update", .target = zone_id };
    if (try rejectInvalidBody(ctx, probe_call, value_json, writer)) return;
    const body = try std.fmt.allocPrint(ctx.gpa, "{{\"value\":{s}}}", .{value_json});
    defer ctx.gpa.free(body);
    probe_call.body = body;
    try executeCloudflare(ctx, probe_call, writer);
}

// --- Hostinger helpers ---

pub fn vpsAction(ctx: Context, vm_id: []const u8, action: VpsAction, writer: anytype) !void {
    const url = try hostingerVpsActionUrl(ctx.gpa, vm_id, action);
    defer ctx.gpa.free(url);
    try executeHostinger(ctx, .{ .method = .POST, .url = url, .body = null, .kind = action.auditKind(), .target = vm_id }, writer);
}

pub fn firewallRuleCreate(ctx: Context, firewall_id: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try hostingerFirewallRulesUrl(ctx.gpa, firewall_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .POST, .url = url, .body = body_json, .kind = "hostinger.firewall.rule.create", .target = firewall_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeHostinger(ctx, call, writer);
}

pub fn firewallRuleUpdate(ctx: Context, firewall_id: []const u8, rule_id: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try hostingerFirewallRuleUrl(ctx.gpa, firewall_id, rule_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .PUT, .url = url, .body = body_json, .kind = "hostinger.firewall.rule.update", .target = firewall_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeHostinger(ctx, call, writer);
}

pub fn firewallRuleDelete(ctx: Context, firewall_id: []const u8, rule_id: []const u8, writer: anytype) !void {
    const url = try hostingerFirewallRuleUrl(ctx.gpa, firewall_id, rule_id);
    defer ctx.gpa.free(url);
    try executeHostinger(ctx, .{ .method = .DELETE, .url = url, .body = null, .kind = "hostinger.firewall.rule.delete", .target = firewall_id }, writer);
}

pub fn firewallSync(ctx: Context, firewall_id: []const u8, vm_id: []const u8, writer: anytype) !void {
    const url = try hostingerFirewallSyncUrl(ctx.gpa, firewall_id, vm_id);
    defer ctx.gpa.free(url);
    try executeHostinger(ctx, .{ .method = .POST, .url = url, .body = null, .kind = "hostinger.firewall.sync", .target = firewall_id }, writer);
}

pub fn hostingerDnsUpdate(ctx: Context, domain: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try hostingerDnsZoneUrl(ctx.gpa, domain);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .PUT, .url = url, .body = body_json, .kind = "hostinger.dns.update", .target = domain };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeHostinger(ctx, call, writer);
}

pub fn hostingerDnsDelete(ctx: Context, domain: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try hostingerDnsZoneUrl(ctx.gpa, domain);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .DELETE, .url = url, .body = body_json, .kind = "hostinger.dns.delete", .target = domain };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeHostinger(ctx, call, writer);
}

// --- URL builders (pure, tested below) ---

pub fn cfDnsRecordsUrl(gpa: Allocator, zone_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/dns_records", .{ cloudflare_base, zone_id });
}

pub fn cfDnsRecordUrl(gpa: Allocator, zone_id: []const u8, record_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/dns_records/{s}", .{ cloudflare_base, zone_id, record_id });
}

pub fn cfPurgeCacheUrl(gpa: Allocator, zone_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/purge_cache", .{ cloudflare_base, zone_id });
}

pub fn cfZoneSettingUrl(gpa: Allocator, zone_id: []const u8, setting: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/settings/{s}", .{ cloudflare_base, zone_id, setting });
}

pub fn hostingerVpsActionUrl(gpa: Allocator, vm_id: []const u8, action: VpsAction) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/api/vps/v1/virtual-machines/{s}/{s}", .{ hostinger_base, vm_id, action.pathSegment() });
}

pub fn hostingerFirewallRulesUrl(gpa: Allocator, firewall_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/api/vps/v1/firewall/{s}/rules", .{ hostinger_base, firewall_id });
}

pub fn hostingerFirewallRuleUrl(gpa: Allocator, firewall_id: []const u8, rule_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/api/vps/v1/firewall/{s}/rules/{s}", .{ hostinger_base, firewall_id, rule_id });
}

pub fn hostingerFirewallSyncUrl(gpa: Allocator, firewall_id: []const u8, vm_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/api/vps/v1/firewall/{s}/sync/{s}", .{ hostinger_base, firewall_id, vm_id });
}

pub fn hostingerDnsZoneUrl(gpa: Allocator, domain: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/api/dns/v1/zones/{s}", .{ hostinger_base, domain });
}

// --- shared plumbing ---

fn cloudflareAuth(config: core_config.Config) cf_transport.Auth {
    return .{
        .token = config.cloudflare_api_token,
        .email = config.cloudflare_email,
        .key = config.cloudflare_api_key,
    };
}

pub fn isValidJson(gpa: Allocator, input: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    _ = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), input, .{}) catch return false;
    return true;
}

/// Returns true (and writes the error result) when body_json is invalid.
fn rejectInvalidBody(ctx: Context, call: Call, body_json: []const u8, writer: anytype) !bool {
    if (isValidJson(ctx.gpa, body_json)) return false;
    _ = try app_writes.record(ctx.gpa, ctx.db, call.kind, call.target, body_json, .err, "invalid request json");
    try writeErrorResult(writer, 0, "invalid_json");
    return true;
}

fn executeCloudflare(ctx: Context, call: Call, writer: anytype) !void {
    const resp = cf_transport.requestJson(ctx.io, ctx.gpa, cloudflareAuth(ctx.config), call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err, writer);
    };
    defer resp.deinit(ctx.gpa);
    try finish(ctx, call, resp, writer);
}

fn executeHostinger(ctx: Context, call: Call, writer: anytype) !void {
    const token = ctx.config.hostinger_api_token orelse return recordFailure(ctx, call, error.MissingHostingerToken, writer);
    const resp = hostinger_transport.requestJson(ctx.io, ctx.gpa, token, call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err, writer);
    };
    defer resp.deinit(ctx.gpa);
    try finish(ctx, call, resp, writer);
}

fn recordFailure(ctx: Context, call: Call, err: anyerror, writer: anytype) !void {
    const detail = try std.fmt.allocPrint(ctx.gpa, "request failed: {s}", .{@errorName(err)});
    defer ctx.gpa.free(detail);
    _ = try app_writes.record(ctx.gpa, ctx.db, call.kind, call.target, call.body, .err, detail);
    try writeErrorResult(writer, 0, @errorName(err));
}

fn finish(ctx: Context, call: Call, resp: net_http.Response, writer: anytype) !void {
    const redacted = try core_redact.providerResponse(ctx.gpa, resp.body);
    defer ctx.gpa.free(redacted);
    const ok = net_http.isOk(resp.status);
    const detail = try net_http.summary(ctx.gpa, call.kind, resp.status);
    defer ctx.gpa.free(detail);
    _ = try app_writes.record(ctx.gpa, ctx.db, call.kind, call.target, call.body, if (ok) .ok else .err, detail);

    const status_code: u16 = @intFromEnum(resp.status);
    try writer.print("{{\"ok\":{},\"status\":{d},\"result\":", .{ ok, status_code });
    if (redacted.len != 0 and isValidJson(ctx.gpa, redacted)) {
        try writer.writeAll(redacted);
    } else {
        try core_json.writeString(writer, redacted);
    }
    try writer.writeAll("}\n");
}

fn writeErrorResult(writer: anytype, status: u16, code: []const u8) !void {
    try writer.print("{{\"ok\":false,\"status\":{d},\"result\":{{\"error\":", .{status});
    try core_json.writeString(writer, code);
    try writer.writeAll("}}\n");
}

// --- tests ---

test "cloudflare url builders match the generated route manifest paths" {
    const allocator = std.testing.allocator;

    const create = try cfDnsRecordsUrl(allocator, "zone-1");
    defer allocator.free(create);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-1/dns_records", create);

    const update = try cfDnsRecordUrl(allocator, "zone-1", "rec-9");
    defer allocator.free(update);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-1/dns_records/rec-9", update);

    const purge = try cfPurgeCacheUrl(allocator, "zone-1");
    defer allocator.free(purge);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-1/purge_cache", purge);

    const setting = try cfZoneSettingUrl(allocator, "zone-1", "always_use_https");
    defer allocator.free(setting);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-1/settings/always_use_https", setting);
}

test "hostinger url builders match the generated route manifest paths" {
    const allocator = std.testing.allocator;

    const start = try hostingerVpsActionUrl(allocator, "123", .start);
    defer allocator.free(start);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/123/start", start);

    const restart = try hostingerVpsActionUrl(allocator, "123", .restart);
    defer allocator.free(restart);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/123/restart", restart);

    const rules = try hostingerFirewallRulesUrl(allocator, "fw-1");
    defer allocator.free(rules);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/firewall/fw-1/rules", rules);

    const rule = try hostingerFirewallRuleUrl(allocator, "fw-1", "rule-2");
    defer allocator.free(rule);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/firewall/fw-1/rules/rule-2", rule);

    const sync = try hostingerFirewallSyncUrl(allocator, "fw-1", "123");
    defer allocator.free(sync);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/firewall/fw-1/sync/123", sync);

    const dns = try hostingerDnsZoneUrl(allocator, "example.com");
    defer allocator.free(dns);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/dns/v1/zones/example.com", dns);
}

test "json validation accepts objects and rejects malformed payloads" {
    const allocator = std.testing.allocator;
    try std.testing.expect(isValidJson(allocator, "{\"type\":\"A\",\"name\":\"www\"}"));
    try std.testing.expect(isValidJson(allocator, "\"strict\""));
    try std.testing.expect(!isValidJson(allocator, "{not json"));
    try std.testing.expect(!isValidJson(allocator, ""));
}

test "invalid body json records an error audit row without network access" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/provider_writes.db", .{tmp.sub_path});
    defer allocator.free(db_path);

    var db = try db_store.Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const ctx: Context = .{
        .io = std.testing.io,
        .gpa = allocator,
        .db = &db,
        .config = .{ .domains = &.{} },
    };

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try dnsRecordCreate(ctx, "zone-1", "{broken", &out.writer);
    try std.testing.expectEqualStrings("{\"ok\":false,\"status\":0,\"result\":{\"error\":\"invalid_json\"}}\n", out.written());

    var audit = std.Io.Writer.Allocating.init(allocator);
    defer audit.deinit();
    try app_writes.writeAuditJson(allocator, &db, 10, &audit.writer);
    const json = audit.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "cf.dns.create") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"target\":\"zone-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "invalid request json") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"error\"") != null);

    var out2 = std.Io.Writer.Allocating.init(allocator);
    defer out2.deinit();
    try hostingerDnsUpdate(ctx, "example.com", "[oops", &out2.writer);
    try std.testing.expect(std.mem.indexOf(u8, out2.written(), "\"error\":\"invalid_json\"") != null);
}
