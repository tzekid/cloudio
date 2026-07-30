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
    return try request(gpa, io, .GET, url, null, extra, privileged);
}

pub fn request(gpa: Allocator, io: Io, method: std.http.Method, url: []const u8, body: ?[]const u8, extra: []const std.http.Header, privileged: []const std.http.Header) !Response {
    var client = std.http.Client{ .allocator = gpa, .io = io };
    defer client.deinit();
    const uri = try std.Uri.parse(url);
    // std.http.Client refuses request bodies on methods other than POST/PUT/PATCH,
    // but Hostinger's DNS delete endpoint takes a DELETE body. For that case we
    // emit Content-Length ourselves and write the payload straight to the connection.
    const manual_body = body != null and !method.requestHasBody();
    var content_length_buf: [24]u8 = undefined;
    var manual_headers: []std.http.Header = &.{};
    defer if (manual_headers.len != 0) gpa.free(manual_headers);
    if (manual_body) {
        const cl = try std.fmt.bufPrint(&content_length_buf, "{d}", .{body.?.len});
        manual_headers = try gpa.alloc(std.http.Header, extra.len + 1);
        @memcpy(manual_headers[0..extra.len], extra);
        manual_headers[extra.len] = .{ .name = "Content-Length", .value = cl };
    }
    var req = try client.request(method, uri, .{
        .redirect_behavior = if (manual_body) .unhandled else @enumFromInt(3),
        .headers = .{ .user_agent = .{ .override = "cloudflare-zig/0.1" } },
        .extra_headers = if (manual_body) manual_headers else extra,
        .privileged_headers = privileged,
    });
    defer req.deinit();
    if (manual_body) {
        try req.sendBodiless();
        const conn_writer = req.connection.?.writer();
        try conn_writer.writeAll(body.?);
        try req.connection.?.flush();
    } else if (body) |payload| {
        req.transfer_encoding = .{ .content_length = payload.len };
        var body_writer = try req.sendBodyUnflushed(&.{});
        try body_writer.writer.writeAll(payload);
        try body_writer.end();
        try req.connection.?.flush();
    } else {
        try req.sendBodiless();
    }
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
    const response_body = try out.toOwnedSlice();
    errdefer gpa.free(response_body);
    if (response_body.len > max_body_bytes) return error.ApiResponseTooLarge;
    return .{ .status = response.head.status, .body = response_body };
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
