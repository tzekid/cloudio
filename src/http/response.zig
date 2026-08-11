const std = @import("std");

pub fn write(
    out: *std.Io.Writer,
    status: u16,
    content_type: []const u8,
    extra_headers: []const u8,
    body: []const u8,
) !void {
    return writeRepresentation(out, status, content_type, extra_headers, body, false);
}

pub fn writeRepresentation(
    out: *std.Io.Writer,
    status: u16,
    content_type: []const u8,
    extra_headers: []const u8,
    body: []const u8,
    head_only: bool,
) !void {
    try out.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n{s}Connection: close\r\n\r\n",
        .{ status, statusText(status), content_type, body.len, extra_headers },
    );
    if (!head_only) try out.writeAll(body);
    try out.flush();
}

pub fn writeFile(
    io: std.Io,
    out: *std.Io.Writer,
    status: u16,
    content_type: []const u8,
    extra_headers: []const u8,
    path: []const u8,
    head_only: bool,
) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .follow_symlinks = false });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file) return error.NotAFile;
    try out.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n{s}Connection: close\r\n\r\n",
        .{ status, statusText(status), content_type, stat.size, extra_headers },
    );
    if (!head_only) {
        var read_buffer: [16 * 1024]u8 = undefined;
        var reader = file.readerStreaming(io, &read_buffer);
        var copy_buffer: [16 * 1024]u8 = undefined;
        while (true) {
            const read = try reader.interface.readSliceShort(&copy_buffer);
            if (read == 0) break;
            try out.writeAll(copy_buffer[0..read]);
        }
    }
    try out.flush();
}

pub fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        204 => "No Content",
        207 => "Multi-Status",
        302 => "Found",
        303 => "See Other",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        410 => "Gone",
        429 => "Too Many Requests",
        413 => "Payload Too Large",
        422 => "Unprocessable Content",
        428 => "Precondition Required",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
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

test "dynamic HEAD preserves representation length and omits body" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeRepresentation(&out.writer, 202, "text/plain", "", "ready", true);
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "HTTP/1.1 202 Accepted\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Content-Length: 5\r\n") != null);
    try std.testing.expect(!std.mem.endsWith(u8, out.written(), "ready"));
}

test "response streams files and supports HEAD" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/response.bin", .{tmp.sub_path});
    defer allocator.free(path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "file-body" });
    var get_out = std.Io.Writer.Allocating.init(allocator);
    defer get_out.deinit();
    try writeFile(std.testing.io, &get_out.writer, 200, "application/octet-stream", "", path, false);
    try std.testing.expect(std.mem.endsWith(u8, get_out.written(), "file-body"));
    var head_out = std.Io.Writer.Allocating.init(allocator);
    defer head_out.deinit();
    try writeFile(std.testing.io, &head_out.writer, 200, "application/octet-stream", "", path, true);
    try std.testing.expect(!std.mem.endsWith(u8, head_out.written(), "file-body"));
    try std.testing.expect(std.mem.indexOf(u8, head_out.written(), "Content-Length: 9\r\n") != null);
}
