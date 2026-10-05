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
    try db.insertProviderRaw(input.provider, input.endpoint, @backingInt(input.status), redacted);
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
    try writer.print("{d}", .{@backingInt(input.status)});
    try writer.writeAll(",\"message\":\"empty response body from provider\"}],\"messages\":[],\"result\":null,\"diagnostic\":{");
    try writer.writeAll("\"provider\":");
    try core_json.writeString(writer, input.provider);
    try writer.writeAll(",\"kind\":");
    try core_json.writeString(writer, input.kind);
    try writer.writeAll(",\"endpoint\":");
    try core_json.writeString(writer, input.endpoint);
    try writer.writeAll(",\"http_status\":");
    try writer.print("{d}", .{@backingInt(input.status)});
    try writer.writeAll(",\"status\":");
    try core_json.writeString(writer, net_http.statusText(input.status));
    try writer.writeAll("}}\n");
    return try out.toOwnedSlice();
}

pub fn skipped(gpa: Allocator, db: *Db, provider: []const u8, kind: []const u8, target: ?[]const u8, summary: []const u8, output_text: []const u8, capture_output: bool) !Output {
    _ = try db.insertSnapshot(provider, kind, target, "skipped", summary, null, null);
    return try outputText(gpa, capture_output, output_text);
}

pub fn outputText(gpa: Allocator, capture_output: bool, text: []const u8) !Output {
    return try core_output.maybeText(gpa, capture_output, text);
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

