const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_body_bytes = 12 * 1024 * 1024;
pub const network_timeout_seconds: isize = 30;

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
    const sensitive_headers = privileged.len != 0 or containsSensitiveHeader(extra);
    var wire_headers: []std.http.Header = &.{};
    defer if (wire_headers.len != 0) gpa.free(wire_headers);
    if (manual_body or privileged.len != 0) {
        wire_headers = try gpa.alloc(std.http.Header, extra.len + privileged.len + @intFromBool(manual_body));
        @memcpy(wire_headers[0..extra.len], extra);
        @memcpy(wire_headers[extra.len .. extra.len + privileged.len], privileged);
    }
    if (manual_body) {
        const cl = try std.fmt.bufPrint(&content_length_buf, "{d}", .{body.?.len});
        wire_headers[extra.len + privileged.len] = .{ .name = "Content-Length", .value = cl };
    }
    var req = try client.request(method, uri, .{
        .redirect_behavior = if (manual_body or sensitive_headers) .unhandled else @enumFromInt(3),
        .headers = .{ .user_agent = .{ .override = "hostinger-zig/0.1" } },
        .extra_headers = if (wire_headers.len != 0) wire_headers else extra,
        .privileged_headers = &.{},
    });
    defer req.deinit();
    try configureSocketTimeout(req.connection.?);
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
    if (response.head.content_length) |declared| {
        if (declared > max_body_bytes) return error.ApiResponseTooLarge;
    }
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
    _ = copyBounded(reader, &out.writer, max_body_bytes) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };
    const response_body = try out.toOwnedSlice();
    errdefer gpa.free(response_body);
    return .{ .status = response.head.status, .body = response_body };
}

fn containsSensitiveHeader(headers: []const std.http.Header) bool {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "Authorization") or
            std.ascii.eqlIgnoreCase(header.name, "Cookie") or
            std.ascii.eqlIgnoreCase(header.name, "X-Auth-Key") or
            std.ascii.eqlIgnoreCase(header.name, "X-Auth-Email")) return true;
    }
    return false;
}

fn copyBounded(reader: *std.Io.Reader, writer: *std.Io.Writer, max_bytes_allowed: usize) !usize {
    var total: usize = 0;
    var buffer: [16 * 1024]u8 = undefined;
    while (true) {
        const read = try reader.readSliceShort(&buffer);
        if (read == 0) return total;
        if (read > max_bytes_allowed - total) return error.ApiResponseTooLarge;
        try writer.writeAll(buffer[0..read]);
        total += read;
    }
}

fn configureSocketTimeout(connection: *std.http.Client.Connection) !void {
    if (comptime builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        const timeout: std.posix.timeval = .{ .sec = network_timeout_seconds, .usec = 0 };
        const bytes = std.mem.asBytes(&timeout);
        const handle = connection.stream_reader.stream.socket.handle;
        try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, bytes);
        try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, bytes);
    }
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

test "sensitive headers disable automatic redirect handling" {
    try std.testing.expect(containsSensitiveHeader(&.{.{ .name = "authorization", .value = "Bearer secret" }}));
    try std.testing.expect(containsSensitiveHeader(&.{.{ .name = "X-Auth-Key", .value = "secret" }}));
    try std.testing.expect(!containsSensitiveHeader(&.{.{ .name = "Accept", .value = "application/json" }}));
}

test "bounded copy rejects bytes beyond the limit" {
    var source = std.Io.Reader.fixed("12345");
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expectError(error.ApiResponseTooLarge, copyBounded(&source, &out.writer, 4));
}
