const std = @import("std");
const core_json = @import("core_json");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_snapshot_limit = 100;

pub fn writeRecentSnapshotsJson(gpa: Allocator, db: *Db, writer: anytype) !void {
    var snapshots = try db.recentSnapshots(gpa, default_snapshot_limit);
    defer snapshots.deinit(gpa);
    try writeSnapshotsJson(snapshots.items, writer);
}

pub fn writeSnapshotsJson(snapshots: []const db_store.SnapshotSummary, writer: anytype) !void {
    try writer.writeAll("{\"snapshots\":[");
    for (snapshots, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{{\"id\":{d},\"source\":", .{row.id});
        try core_json.writeString(writer, row.source);
        try writer.writeAll(",\"kind\":");
        try core_json.writeString(writer, row.kind);
        try writer.writeAll(",\"target\":");
        try core_json.writeString(writer, row.target);
        try writer.writeAll(",\"status\":");
        try core_json.writeString(writer, row.status);
        try writer.writeAll(",\"summary\":");
        try core_json.writeString(writer, row.summary);
        try writer.writeAll(",\"captured_at\":");
        try core_json.writeString(writer, row.captured_at);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

test "export writes recent snapshots json through app service" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-export.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    _ = try db.insertSnapshot("system", "logs", "unit", "ok", "line \"one\"\nline two", null, null);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRecentSnapshotsJson(allocator, &db, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const snapshots = parsed.value.object.get("snapshots") orelse return error.TestExpectedSnapshots;
    try std.testing.expectEqual(@as(usize, 1), snapshots.array.items.len);
    const item = snapshots.array.items[0];
    try std.testing.expectEqualStrings("system", item.object.get("source").?.string);
    try std.testing.expectEqualStrings("line \"one\"\nline two", item.object.get("summary").?.string);
}
