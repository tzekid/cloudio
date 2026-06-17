const std = @import("std");

const Io = std.Io;

pub fn ensureParentDir(io: Io, path: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse return;
    if (dir.len == 0 or std.mem.eql(u8, dir, ".") or std.mem.eql(u8, dir, "/")) return;
    try Io.Dir.cwd().createDirPath(io, dir);
}

pub fn fileExists(io: Io, path: []const u8) !bool {
    Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}

test "filesystem helpers create parents and detect files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/nested/path/file.txt", .{tmp.sub_path});
    defer allocator.free(path);

    try std.testing.expect(!try fileExists(std.testing.io, path));
    try ensureParentDir(std.testing.io, path);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "ok" });
    try std.testing.expect(try fileExists(std.testing.io, path));
}
