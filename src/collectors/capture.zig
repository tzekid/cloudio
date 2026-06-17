const std = @import("std");
const core_redact = @import("core_redact");
const db_store = @import("db_store");
const net_http = @import("net_http");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Output = struct {
    text: ?[]u8 = null,

    pub fn deinit(self: Output, allocator: Allocator) void {
        if (self.text) |text| allocator.free(text);
    }
};

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

pub fn storeResponse(gpa: Allocator, db: *Db, input: ResponseCapture) ![]u8 {
    const redacted = if (std.mem.indexOf(u8, input.kind, "token") != null)
        try core_redact.tokenResponse(gpa, input.body)
    else
        try core_redact.secrets(gpa, input.body);
    errdefer gpa.free(redacted);
    const summary = try net_http.summary(gpa, input.summary_label, input.status);
    defer gpa.free(summary);
    _ = try db.insertSnapshot(input.provider, input.kind, input.target, net_http.statusText(input.status), summary, redacted, null);
    try db.insertProviderRaw(input.provider, input.endpoint, @intFromEnum(input.status), redacted);
    return redacted;
}

pub fn captureResponse(gpa: Allocator, db: *Db, input: ResponseCapture) !Output {
    const redacted = try storeResponse(gpa, db, input);
    errdefer gpa.free(redacted);
    if (input.capture_output) return .{ .text = redacted };
    gpa.free(redacted);
    return .{};
}

pub fn skipped(gpa: Allocator, db: *Db, provider: []const u8, kind: []const u8, target: ?[]const u8, summary: []const u8, output_text: []const u8, capture_output: bool) !Output {
    _ = try db.insertSnapshot(provider, kind, target, "skipped", summary, null, null);
    return try outputText(gpa, capture_output, output_text);
}

pub fn outputText(gpa: Allocator, capture_output: bool, text: []const u8) !Output {
    return .{ .text = if (capture_output) try gpa.dupe(u8, text) else null };
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
        .body = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz\n{\"ok\":true}",
        .capture_output = true,
    });
    defer output.deinit(allocator);

    try std.testing.expect(output.text != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text.?, "abcdefghijklmnopqrstuvwxyz") == null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("provider_raw"));
}
