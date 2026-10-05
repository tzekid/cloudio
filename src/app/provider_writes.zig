//! Audited provider writes: Cloudflare DNS records and Hostinger VPS actions.
//! Every call performs the live request and records one audit_actions row.
const std = @import("std");
const percent = @import("../core/url.zig");
const app_writes = @import("writes.zig");
const core_config = @import("../core/config.zig");
const core_redact = @import("../core/redact.zig");
const db_store = @import("../db/store.zig");
const cf_transport = @import("cloudflare").transport;
const hostinger_transport = @import("hostinger").transport;

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

/// Outcome of one provider write.
pub const Result = union(enum) {
    /// The request did not complete.
    unavailable,
    /// The provider answered with a failing status or envelope.
    rejected,
    /// The provider accepted the change. The caller owns the redacted body.
    accepted: []u8,

    pub fn deinit(self: Result, gpa: Allocator) void {
        if (self == .accepted) gpa.free(self.accepted);
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

pub fn dnsRecordCreate(ctx: Context, zone_id: []const u8, body_json: []const u8) !Result {
    const url = try std.fmt.allocPrint(ctx.gpa, "{s}/zones/{s}/dns_records", .{ ctx.config.cloudflare_api_base, zone_id });
    defer ctx.gpa.free(url);
    return executeCloudflare(ctx, .{ .method = .POST, .url = url, .body = body_json, .kind = "cf.dns.create", .target = zone_id });
}

pub fn dnsRecordUpdate(ctx: Context, zone_id: []const u8, record_id: []const u8, body_json: []const u8) !Result {
    const url = try std.fmt.allocPrint(ctx.gpa, "{s}/zones/{s}/dns_records/{s}", .{ ctx.config.cloudflare_api_base, zone_id, record_id });
    defer ctx.gpa.free(url);
    return executeCloudflare(ctx, .{ .method = .PUT, .url = url, .body = body_json, .kind = "cf.dns.update", .target = zone_id });
}

pub fn dnsRecordDelete(ctx: Context, zone_id: []const u8, record_id: []const u8) !Result {
    const url = try std.fmt.allocPrint(ctx.gpa, "{s}/zones/{s}/dns_records/{s}", .{ ctx.config.cloudflare_api_base, zone_id, record_id });
    defer ctx.gpa.free(url);
    return executeCloudflare(ctx, .{ .method = .DELETE, .url = url, .body = null, .kind = "cf.dns.delete", .target = zone_id });
}

// --- Hostinger helpers ---

pub fn vpsAction(ctx: Context, vm_id: []const u8, action: VpsAction) !Result {
    const escaped_id = try percent.component(ctx.gpa, vm_id);
    defer ctx.gpa.free(escaped_id);
    const url = try std.fmt.allocPrint(ctx.gpa, "{s}/api/vps/v1/virtual-machines/{s}/{s}", .{ ctx.config.hostinger_api_base, escaped_id, action.pathSegment() });
    defer ctx.gpa.free(url);
    return executeHostinger(ctx, .{ .method = .POST, .url = url, .body = null, .kind = action.auditKind(), .target = vm_id });
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

fn executeCloudflare(ctx: Context, call: Call) !Result {
    const resp = cf_transport.requestJson(ctx.io, ctx.gpa, cloudflareAuth(ctx.config), call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err);
    };
    defer resp.deinit(ctx.gpa);
    return finish(ctx, call, resp, cloudflareEnvelopeSucceeded(ctx.gpa, resp.body));
}

fn executeHostinger(ctx: Context, call: Call) !Result {
    const token = ctx.config.hostinger_api_token orelse return recordFailure(ctx, call, error.MissingHostingerToken);
    const resp = hostinger_transport.requestJson(ctx.io, ctx.gpa, token, call.method, call.url, call.body) catch |err| {
        return recordFailure(ctx, call, err);
    };
    defer resp.deinit(ctx.gpa);
    return finish(ctx, call, resp, true);
}

fn recordFailure(ctx: Context, call: Call, err: anyerror) !Result {
    const detail = try std.fmt.allocPrint(ctx.gpa, "request failed: {s}", .{@errorName(err)});
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, call.kind, call.target, call.body, .err, detail);
    return .unavailable;
}

/// `envelope_ok` lets Cloudflare reject a 2xx response whose envelope says
/// `success: false`.
fn finish(ctx: Context, call: Call, resp: anytype, envelope_ok: bool) !Result {
    const status: u16 = @backingInt(resp.status);
    const http_ok = status >= 200 and status < 300;
    const ok = http_ok and envelope_ok;
    const detail = if (http_ok and !ok)
        try std.fmt.allocPrint(ctx.gpa, "{s}: provider rejected the response envelope", .{call.kind})
    else
        try std.fmt.allocPrint(ctx.gpa, "{s} HTTP {d}", .{ call.kind, status });
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, call.kind, call.target, call.body, if (ok) .ok else .err, detail);
    if (!ok) return .rejected;
    return .{ .accepted = try core_redact.providerResponse(ctx.gpa, resp.body) };
}

fn cloudflareEnvelopeSucceeded(gpa: Allocator, body: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const success = parsed.value.object.get("success") orelse return false;
    return success == .bool and success.bool;
}

// --- tests ---


test "Cloudflare HTTP success still requires a successful provider envelope" {
    const allocator = std.testing.allocator;
    try std.testing.expect(cloudflareEnvelopeSucceeded(allocator, "{\"success\":true,\"result\":{}}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "{\"success\":false,\"result\":null}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "{\"result\":{}}"));
    try std.testing.expect(!cloudflareEnvelopeSucceeded(allocator, "not-json"));
}

