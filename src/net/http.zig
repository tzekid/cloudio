const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_body_bytes = 12 * 1024 * 1024;

pub const Response = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: Response, allocator: Allocator) void {
        allocator.free(self.body);
    }
};

pub fn get(gpa: Allocator, io: Io, url: []const u8, extra: []const std.http.Header, privileged: []const std.http.Header) !Response {
    var client = std.http.Client{ .allocator = gpa, .io = io };
    defer client.deinit();
    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{
        .redirect_behavior = @enumFromInt(3),
        .headers = .{ .user_agent = .{ .override = "cloudio-poc/0.1" } },
        .extra_headers = extra,
        .privileged_headers = privileged,
    });
    defer req.deinit();
    try req.sendBodiless();
    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try gpa.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try gpa.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer.len != 0) gpa.free(decompress_buffer);
    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    _ = reader.streamRemaining(&out.writer) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };
    const body = try out.toOwnedSlice();
    errdefer gpa.free(body);
    if (body.len > max_body_bytes) return error.ApiResponseTooLarge;
    return .{ .status = response.head.status, .body = body };
}

pub fn statusText(status: std.http.Status) []const u8 {
    const code: u16 = @intFromEnum(status);
    if (code >= 200 and code < 300) return "ok";
    if (code == 401 or code == 403) return "permission";
    if (code == 404) return "not_found";
    return "http_error";
}

pub fn isOk(status: std.http.Status) bool {
    const code: u16 = @intFromEnum(status);
    return code >= 200 and code < 300;
}

pub fn summary(gpa: Allocator, label: []const u8, status: std.http.Status) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s} HTTP {d}", .{ label, @intFromEnum(status) });
}

test "status helpers classify api responses" {
    try std.testing.expectEqualStrings("ok", statusText(.ok));
    try std.testing.expectEqualStrings("permission", statusText(.unauthorized));
    try std.testing.expectEqualStrings("permission", statusText(.forbidden));
    try std.testing.expectEqualStrings("not_found", statusText(.not_found));
    try std.testing.expectEqualStrings("http_error", statusText(.unprocessable_entity));
    try std.testing.expect(isOk(.ok));
    try std.testing.expect(!isOk(.bad_request));

    const text = try summary(std.testing.allocator, "metrics", .ok);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("metrics HTTP 200", text);
}
