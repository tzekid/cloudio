const std = @import("std");
const db_store = @import("db_store");

pub const Db = db_store.Db;

pub fn openInitialized(io: std.Io, path: []const u8) !Db {
    var db = try Db.open(io, path);
    errdefer db.close();
    try db.initSchema();
    return db;
}

test "openInitialized opens the store and applies migrations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-database.db", .{tmp.sub_path});
    defer allocator.free(db_path);

    var db = try openInitialized(std.testing.io, db_path);
    defer db.close();

    try db.insertAudit("database", "initialized", "ok");
    var events = try db.recentAuditEvents(allocator, 1);
    defer events.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("database", events.items[0].action);
}
