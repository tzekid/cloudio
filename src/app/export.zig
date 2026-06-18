const std = @import("std");
const app_history = @import("app_history");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_snapshot_limit = 100;

pub fn writeRecentSnapshotsJson(gpa: Allocator, db: *Db, writer: anytype) !void {
    try writeRecentSnapshotsJsonWithLimit(gpa, db, default_snapshot_limit, writer);
}

pub fn writeRecentSnapshotsJsonWithLimit(gpa: Allocator, db: *Db, limit: i64, writer: anytype) !void {
    var snapshots = try db.recentSnapshots(gpa, app_render.positiveLimit(limit, default_snapshot_limit));
    defer snapshots.deinit(gpa);
    try writeSnapshotsJson(snapshots.items, writer);
}

pub fn writeSnapshotsJson(snapshots: []const db_store.SnapshotSummary, writer: anytype) !void {
    try app_render.writeSnapshotsJsonObject(writer, snapshots, .{ .include_id = true, .trailing_newline = true });
}

pub fn writeOperationalHistoryJson(gpa: Allocator, db: *Db, options: app_history.Options, writer: anytype) !void {
    try app_history.writeJson(gpa, db, options, writer);
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
    try db.insertAudit("export.history", "ok", "test event");

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

    var history_out = std.Io.Writer.Allocating.init(allocator);
    defer history_out.deinit();
    try writeOperationalHistoryJson(allocator, &db, .{ .audit_limit = 10, .snapshot_limit = 10 }, &history_out.writer);
    const history_json = try history_out.toOwnedSlice();
    defer allocator.free(history_json);
    var history = try std.json.parseFromSlice(std.json.Value, allocator, history_json, .{});
    defer history.deinit();
    try std.testing.expectEqualStrings("operational_history", history.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(usize, 1), history.value.object.get("audit_events").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), history.value.object.get("snapshots").?.array.items.len);
}
