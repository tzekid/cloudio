const std = @import("std");
const core_process = @import("core_process");
const core_redact = @import("core_redact");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

const max_command_bytes = 4 * 1024 * 1024;

pub fn collect(io: Io, gpa: Allocator, projects_root: []const u8, db: *Db) !void {
    const find = core_process.run(gpa, io, &.{ "find", projects_root, "-maxdepth", "4", "(", "-name", "docker-compose.yml", "-o", "-name", "docker-compose.yaml", "-o", "-name", "compose.yml", "-o", "-name", "compose.yaml", ")", "-print" }, max_command_bytes) catch |err| {
        const summary = try std.fmt.allocPrint(gpa, "compose discovery failed: {s}", .{@errorName(err)});
        defer gpa.free(summary);
        _ = try db.insertSnapshot("projects", "compose", projects_root, "error", summary, null, null);
        return;
    };
    defer find.deinit(gpa);

    const redacted = try core_redact.secrets(gpa, find.stdout);
    defer gpa.free(redacted);
    _ = try db.insertSnapshot("projects", "compose", projects_root, if (find.ok()) "ok" else "error", "compose files", null, redacted);
    var lines = std.mem.splitScalar(u8, redacted, '\n');
    while (lines.next()) |line| try persistComposePath(db, line);
}

fn persistComposePath(db: *Db, line: []const u8) !void {
    const path = trim(line);
    if (path.len == 0) return;
    const name = projectNameFromPath(path);
    try db.upsertProject(name, "compose", path, null, null, null, null, null);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn projectNameFromPath(path: []const u8) []const u8 {
    const dir = std.fs.path.dirname(path) orelse return path;
    return std.fs.path.basename(dir);
}

test "project name comes from compose file directory" {
    try std.testing.expectEqualStrings("app", projectNameFromPath("/srv/app/docker-compose.yml"));
    try std.testing.expectEqualStrings("nested", projectNameFromPath("/home/kid/Projects/foo/nested/compose.yaml"));
}

test "persists compose project paths" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/projects.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistComposePath(&db, "/srv/app/docker-compose.yml");

    try std.testing.expectEqual(@as(i64, 1), try db.countTable("projects"));
}
