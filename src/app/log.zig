const std = @import("std");
const core_log = @import("core_log");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const default_max_file_bytes = 8 * 1024 * 1024;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    path: []const u8,
    max_bytes: usize = default_max_file_bytes,
};

pub fn read(ctx: Context) ![]u8 {
    return try core_log.readRedactedFile(ctx.io, ctx.gpa, ctx.path, ctx.max_bytes);
}

pub fn writeText(ctx: Context, writer: anytype) !void {
    const text = try read(ctx);
    defer ctx.gpa.free(text);
    try writer.writeAll(text);
}

test "log app reads redacted run log text" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/latest-run.log", .{tmp.sub_path});
    defer allocator.free(path);

    try core_log.writeRedactedFile(std.testing.io, allocator, path, "Authorization: Bearer abc123\nnormal=value\n");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeText(.{
        .io = std.testing.io,
        .gpa = allocator,
        .path = path,
        .max_bytes = 1024,
    }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "abc123") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "normal=value") != null);
}
