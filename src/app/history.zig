const std = @import("std");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_audit_limit = 100;
pub const default_snapshot_limit = 100;

pub const Options = struct {
    audit_limit: i64 = default_audit_limit,
    snapshot_limit: i64 = default_snapshot_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .audit_limit = app_render.positiveLimit(self.audit_limit, default_audit_limit),
            .snapshot_limit = app_render.positiveLimit(self.snapshot_limit, default_snapshot_limit),
        };
    }
};

pub const History = struct {
    options: Options,
    audit_events: db_store.AuditEvents,
    snapshots: db_store.SnapshotSummaries,

    pub fn load(gpa: Allocator, db: *Db, options: Options) !History {
        const normalized = options.normalized();
        var audit_events = try db.recentAuditEvents(gpa, normalized.audit_limit);
        errdefer audit_events.deinit(gpa);
        return .{
            .options = normalized,
            .audit_events = audit_events,
            .snapshots = try db.recentSnapshots(gpa, normalized.snapshot_limit),
        };
    }

    pub fn deinit(self: *History, gpa: Allocator) void {
        self.audit_events.deinit(gpa);
        self.snapshots.deinit(gpa);
    }

    pub fn writeText(self: History, writer: anytype) !void {
        try writer.writeAll("Cloudio operational history\n");
        try writer.print("limits: audit_events={d} snapshots={d}\n\n", .{
            self.options.audit_limit,
            self.options.snapshot_limit,
        });
        try writer.writeAll("audit events:\n");
        if (self.audit_events.items.len == 0) {
            try writer.writeAll("\t(none)\n");
        } else {
            for (self.audit_events.items) |row| {
                try writer.print("\t#{d} {s} [{s}] {s} {s}\n", .{
                    row.id,
                    row.action,
                    row.status,
                    row.detail,
                    row.created_at,
                });
            }
        }
        try writer.writeAll("\nsnapshots:\n");
        if (self.snapshots.items.len == 0) {
            try writer.writeAll("\t(none)\n");
        } else {
            for (self.snapshots.items) |row| {
                try writer.print("\t#{d} {s}/{s} {s} [{s}] {s} {s}\n", .{
                    row.id,
                    row.source,
                    row.kind,
                    row.target,
                    row.status,
                    row.summary,
                    row.captured_at,
                });
            }
        }
    }

    pub fn writeJson(self: History, writer: anytype) !void {
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "kind", "operational_history", true);
        try writer.writeAll("\"limits\":{");
        try app_render.writeJsonIntField(writer, "audit_events", self.options.audit_limit, true);
        try app_render.writeJsonIntField(writer, "snapshots", self.options.snapshot_limit, false);
        try writer.writeAll("},\"audit_events\":");
        try app_render.writeAuditEventArrayJson(writer, self.audit_events.items, .{ .include_id = true });
        try writer.writeAll(",\"snapshots\":");
        try app_render.writeSnapshotArrayJson(writer, self.snapshots.items, .{ .include_id = true });
        try writer.writeAll("}\n");
    }
};

pub fn writeText(gpa: Allocator, db: *Db, options: Options, writer: anytype) !void {
    var history = try History.load(gpa, db, options);
    defer history.deinit(gpa);
    try history.writeText(writer);
}

pub fn writeJson(gpa: Allocator, db: *Db, options: Options, writer: anytype) !void {
    var history = try History.load(gpa, db, options);
    defer history.deinit(gpa);
    try history.writeJson(writer);
}

test "history read model renders audit events and snapshots" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-history.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    _ = try db.insertSnapshot("system", "uptime", null, "ok", "up 1 minute", null, null);
    _ = try db.insertSnapshot("hostinger", "vps", "vm-1", "ok", "running", null, null);
    try db.insertAudit("route.capture", "ok", "hostinger vps captured");
    try db.insertAudit("caddy.diff", "dry_run", "rendered only");

    var history = try History.load(allocator, &db, .{ .audit_limit = 1, .snapshot_limit = 1 });
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), history.audit_events.items.len);
    try std.testing.expectEqual(@as(usize, 1), history.snapshots.items.len);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try history.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio operational history\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "audit events:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "snapshots:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "caddy.diff [dry_run] rendered only") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/vps vm-1 [ok] running") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try history.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("operational_history", parsed.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("limits").?.object.get("audit_events").?.integer);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("audit_events").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("snapshots").?.array.items.len);
}
