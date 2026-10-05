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

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: app_writes.Metadata = .{},
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
    const url = try cfDnsRecordsUrlAt(ctx.gpa, ctx.config.cloudflare_api_base, zone_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .POST, .url = url, .body = body_json, .kind = "cf.dns.create", .target = zone_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeCloudflare(ctx, call, writer);
}

pub fn dnsRecordUpdate(ctx: Context, zone_id: []const u8, record_id: []const u8, body_json: []const u8, writer: anytype) !void {
    const url = try cfDnsRecordUrlAt(ctx.gpa, ctx.config.cloudflare_api_base, zone_id, record_id);
    defer ctx.gpa.free(url);
    const call: Call = .{ .method = .PUT, .url = url, .body = body_json, .kind = "cf.dns.update", .target = zone_id };
    if (try rejectInvalidBody(ctx, call, body_json, writer)) return;
    try executeCloudflare(ctx, call, writer);
}

pub fn dnsRecordDelete(ctx: Context, zone_id: []const u8, record_id: []const u8, writer: anytype) !void {
    const url = try cfDnsRecordUrlAt(ctx.gpa, ctx.config.cloudflare_api_base, zone_id, record_id);
    defer ctx.gpa.free(url);
    try executeCloudflare(ctx, .{ .method = .DELETE, .url = url, .body = null, .kind = "cf.dns.delete", .target = zone_id }, writer);
}

// --- Hostinger helpers ---

pub fn vpsAction(ctx: Context, vm_id: []const u8, action: VpsAction, writer: anytype) !void {
    const url = try hostingerVpsActionUrlAt(ctx.gpa, ctx.config.hostinger_api_base, vm_id, action);
    defer ctx.gpa.free(url);
    try executeHostinger(ctx, .{ .method = .POST, .url = url, .body = null, .kind = action.auditKind(), .target = vm_id }, writer);
}

// --- URL builders (pure, tested below) ---

fn cfDnsRecordsUrlAt(gpa: Allocator, base: []const u8, zone_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/dns_records", .{ base, zone_id });
}

fn cfDnsRecordUrlAt(gpa: Allocator, base: []const u8, zone_id: []const u8, record_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/zones/{s}/dns_records/{s}", .{ base, zone_id, record_id });
}

fn hostingerVpsActionUrlAt(gpa: Allocator, base: []const u8, vm_id: []const u8, action: VpsAction) ![]u8 {
    const escaped_id = try @import("provider_hostinger").pathEscape(gpa, vm_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/api/vps/v1/virtual-machines/{s}/{s}", .{ base, escaped_id, action.pathSegment() });
}

// --- shared plumbing ---

fn cloudflareAuth(config: core_config.Config) cf_transport.Auth {
    return .{
        .token = config.cloudflare_api_token,
        .email = config.cloudflare_email,
        .key = config.cloudflare_api_key,
        .base_url = config.cloudflare_api_base,
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
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, call.kind, call.target, body_json, .err, "invalid request json");
    try writeErrorResult(writer, 0, "invalid_json");
    return true;
}

fn executeCloudflare(ctx: Context, call: Call, writer: anytype) !void {
    const resp = cf_transport.requestJson(ctx.io, ctx.gpa, cloudflareAuth(ctx.config), call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err, writer);
    };
    defer resp.deinit(ctx.gpa);
    try finish(ctx, call, resp, net_http.isOk(resp.status) and cloudflareEnvelopeSucceeded(ctx.gpa, resp.body), writer);
}

fn executeHostinger(ctx: Context, call: Call, writer: anytype) !void {
    const token = ctx.config.hostinger_api_token orelse return recordFailure(ctx, call, error.MissingHostingerToken, writer);
    const resp = hostinger_transport.requestJson(ctx.io, ctx.gpa, token, call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err, writer);
    };
    defer resp.deinit(ctx.gpa);
    try finish(ctx, call, resp, net_http.isOk(resp.status), writer);
}

fn recordFailure(ctx: Context, call: Call, err: anyerror, writer: anytype) !void {
    const detail = try std.fmt.allocPrint(ctx.gpa, "request failed: {s}", .{@errorName(err)});
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, call.kind, call.target, call.body, .err, detail);
    try writeErrorResult(writer, 0, @errorName(err));
}

fn finish(ctx: Context, call: Call, resp: net_http.Response, ok: bool, writer: anytype) !void {
    const redacted = try core_redact.providerResponse(ctx.gpa, resp.body);
    defer ctx.gpa.free(redacted);
    const detail = if (net_http.isOk(resp.status) and !ok)
        try std.fmt.allocPrint(ctx.gpa, "{s}: provider rejected the response envelope", .{call.kind})
    else
        try net_http.summary(ctx.gpa, call.kind, resp.status);
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, call.kind, call.target, call.body, if (ok) .ok else .err, detail);

    const status_code: u16 = @backingInt(resp.status);
    try writer.print("{{\"ok\":{},\"status\":{d},\"result\":", .{ ok, status_code });
    if (redacted.len != 0 and isValidJson(ctx.gpa, redacted)) {
        try writer.writeAll(redacted);
    } else {
        try core_json.writeString(writer, redacted);
    }
    try writer.writeAll("}\n");
}

fn cloudflareEnvelopeSucceeded(gpa: Allocator, body: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const success = parsed.value.object.get("success") orelse return false;
    return success == .bool and success.bool;
}

fn writeErrorResult(writer: anytype, status: u16, code: []const u8) !void {
    try writer.print("{{\"ok\":false,\"status\":{d},\"result\":{{\"error\":", .{status});
    try core_json.writeString(writer, code);
    try writer.writeAll("}}\n");
}

// --- tests ---

test "json validation accepts objects and rejects malformed payloads" {
    const allocator = std.testing.allocator;
    try std.testing.expect(isValidJson(allocator, "{\"type\":\"A\",\"name\":\"www\"}"));
    try std.testing.expect(isValidJson(allocator, "\"strict\""));
    try std.testing.expect(!isValidJson(allocator, "{not json"));
    try std.testing.expect(!isValidJson(allocator, ""));
}

test "Cloudflare HTTP success still requires a successful provider envelope" {
    const allocator = std.testing.allocator;
    try std.testing.expect(cloudflareEnvelopeSucceeded(allocator, "{\"success\":true,\"result\":{}}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "{\"success\":false,\"result\":null}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "{\"result\":{}}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "not-json"));
}

