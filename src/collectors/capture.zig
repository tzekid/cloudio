const std = @import("std");
const core_json = @import("core_json");
const core_output = @import("core_output");
const core_redact = @import("core_redact");
const db_store = @import("db_store");
const net_http = @import("net_http");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Output = core_output.Output;

pub const ResponseCapture = struct {
    provider: []const u8,
    kind: []const u8,
    target: ?[]const u8 = null,
    summary_label: []const u8,
    endpoint: []const u8,
    status: std.http.Status,
    body: []const u8,
    capture_output: bool = false,
};

pub const StoredResponse = struct {
    redacted: []u8,
    snapshot_id: i64,

    pub fn deinit(self: StoredResponse, gpa: Allocator) void {
        gpa.free(self.redacted);
    }
};

pub fn storeResponseWithSnapshotId(gpa: Allocator, db: *Db, input: ResponseCapture) !StoredResponse {
    const body = if (input.body.len == 0) try emptyBodyDiagnostic(gpa, input) else input.body;
    defer if (input.body.len == 0) gpa.free(body);
    const redacted = if (std.mem.indexOf(u8, input.kind, "secret") != null)
        try core_redact.secretResponse(gpa, body)
    else if (std.mem.indexOf(u8, input.kind, "token") != null)
        try core_redact.tokenResponse(gpa, body)
    else
        try core_redact.providerResponse(gpa, body);
    errdefer gpa.free(redacted);
    const summary = try net_http.summary(gpa, input.summary_label, input.status);
    defer gpa.free(summary);
    const snapshot_id = try db.insertSnapshot(input.provider, input.kind, input.target, net_http.statusText(input.status), summary, redacted, null);
    try db.insertProviderRaw(input.provider, input.endpoint, @intFromEnum(input.status), redacted);
    return .{ .redacted = redacted, .snapshot_id = snapshot_id };
}

pub fn storeResponse(gpa: Allocator, db: *Db, input: ResponseCapture) ![]u8 {
    const stored = try storeResponseWithSnapshotId(gpa, db, input);
    return stored.redacted;
}

fn emptyBodyDiagnostic(gpa: Allocator, input: ResponseCapture) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{\"success\":false,\"errors\":[{\"code\":");
    try writer.print("{d}", .{@intFromEnum(input.status)});
    try writer.writeAll(",\"message\":\"empty response body from provider\"}],\"messages\":[],\"result\":null,\"diagnostic\":{");
    try writer.writeAll("\"provider\":");
    try core_json.writeString(writer, input.provider);
    try writer.writeAll(",\"kind\":");
    try core_json.writeString(writer, input.kind);
    try writer.writeAll(",\"endpoint\":");
    try core_json.writeString(writer, input.endpoint);
    try writer.writeAll(",\"http_status\":");
    try writer.print("{d}", .{@intFromEnum(input.status)});
    try writer.writeAll(",\"status\":");
    try core_json.writeString(writer, net_http.statusText(input.status));
    try writer.writeAll("}}\n");
    return try out.toOwnedSlice();
}

pub fn captureResponse(gpa: Allocator, db: *Db, input: ResponseCapture) !Output {
    const stored = try storeResponseWithSnapshotId(gpa, db, input);
    errdefer stored.deinit(gpa);
    if (input.capture_output) return .{ .text = stored.redacted };
    stored.deinit(gpa);
    return .{};
}

pub fn skipped(gpa: Allocator, db: *Db, provider: []const u8, kind: []const u8, target: ?[]const u8, summary: []const u8, output_text: []const u8, capture_output: bool) !Output {
    _ = try db.insertSnapshot(provider, kind, target, "skipped", summary, null, null);
    return try outputText(gpa, capture_output, output_text);
}

pub fn outputText(gpa: Allocator, capture_output: bool, text: []const u8) !Output {
    return try core_output.maybeText(gpa, capture_output, text);
}

test "captures redacted provider response into snapshots and provider raw" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try captureResponse(allocator, &db, .{
        .provider = "fixture",
        .kind = "auth-check",
        .summary_label = "auth check",
        .endpoint = "/fixture",
        .status = .ok,
        .body = "{\"Authorization\":\"Bearer abcdefghijklmnopqrstuvwxyz\",\"result_info\":{\"cursors\":{\"after\":\"opaque-next-cursor\"}},\"success\":true}",
        .capture_output = true,
    });
    defer output.deinit(allocator);

    try std.testing.expect(output.text != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text.?, "abcdefghijklmnopqrstuvwxyz") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.text.?, "opaque-next-cursor") == null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("provider_raw"));
}

test "captures exact snapshot id next to redacted provider response" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/capture-id.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const first = try storeResponseWithSnapshotId(allocator, &db, .{
        .provider = "fixture",
        .kind = "inventory",
        .summary_label = "inventory",
        .endpoint = "/first",
        .status = .ok,
        .body = "{\"ok\":true}",
    });
    defer first.deinit(allocator);
    const second = try storeResponseWithSnapshotId(allocator, &db, .{
        .provider = "fixture",
        .kind = "inventory",
        .summary_label = "inventory",
        .endpoint = "/second",
        .status = .ok,
        .body = "{\"ok\":true}",
    });
    defer second.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1), first.snapshot_id);
    try std.testing.expectEqual(@as(i64, 2), second.snapshot_id);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
}

test "captures empty provider response as structured diagnostic" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/empty-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try captureResponse(allocator, &db, .{
        .provider = "cloudflare",
        .kind = "tls-zone-per-hostname-tls-setting",
        .summary_label = "TLS setting detail",
        .endpoint = "/zones/zone/hostnames/settings/min_tls_version/plosca.ru",
        .status = .method_not_allowed,
        .body = "",
        .capture_output = true,
    });
    defer output.deinit(allocator);

    try std.testing.expect(output.text != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text.?, "\"http_status\":405") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text.?, "empty response body from provider") != null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("provider_raw"));
}
