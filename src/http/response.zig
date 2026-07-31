const std = @import("std");

pub fn write(
    out: *std.Io.Writer,
    status: u16,
    content_type: []const u8,
    extra_headers: []const u8,
    body: []const u8,
) !void {
    try out.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n{s}Connection: close\r\n\r\n",
        .{ status, statusText(status), content_type, body.len, extra_headers },
    );
    try out.writeAll(body);
    try out.flush();
}

pub fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        302 => "Found",
        303 => "See Other",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        429 => "Too Many Requests",
        413 => "Payload Too Large",
        422 => "Unprocessable Content",
        428 => "Precondition Required",
        500 => "Internal Server Error",
        else => "Error",
    };
}

test "response emits bounded HTTP response" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try write(&out.writer, 200, "application/json", "X-Test: yes\r\n", "{}");
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "HTTP/1.1 200 OK\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Content-Length: 2\r\n") != null);
}
