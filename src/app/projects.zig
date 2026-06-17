const std = @import("std");
const collector_projects = @import("collector_projects");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    projects_root: []const u8,
    db: *Db,
};

pub fn writeList(ctx: Context, writer: anytype) !void {
    try collector_projects.collect(ctx.io, ctx.gpa, ctx.projects_root, ctx.db);
    var rows = try ctx.db.projectList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try writeNameValueRows(rows.items, writer);
}

pub fn writeShow(gpa: Allocator, db: *Db, name: []const u8, writer: anytype) !void {
    var details = try db.projectDetails(gpa, name) orelse {
        try writer.print("project not found: {s}\n", .{name});
        return;
    };
    defer details.deinit(gpa);
    try writer.print("name: {s}\nsource: {s}\npath: {s}\nhost: {s}\nupstream: {s}\nservice: {s}\ncontainer: {s}\n", .{
        details.name,
        details.source,
        details.path,
        details.host,
        details.upstream,
        details.service,
        details.container,
    });
}

fn writeNameValueRows(rows: []const db_store.NameValueRow, writer: anytype) !void {
    for (rows) |row| try writer.print("{s}\t{s}\n", .{ row.name, row.value });
}

test "projects show renders project details and not-found states" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-projects.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertProject("cloudio", "compose", "/home/kid/Projects/cloudio", "cloudio.local", "127.0.0.1:9000", "cloudio.service", "cloudio-1", null);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeShow(allocator, &db, "cloudio", &out.writer);
    try writeShow(allocator, &db, "missing", &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "name: cloudio\nsource: compose\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "upstream: 127.0.0.1:9000\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "project not found: missing\n") != null);
}
