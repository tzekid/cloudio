const std = @import("std");
const app_render = @import("app_render");
const collector_system = @import("collector_system");
const core_output = @import("core_output");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const snapshot_limit = 12;
const metric_limit = 30;

pub const Output = core_output.Output;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub fn collectAndWriteSummary(ctx: Context, writer: anytype) !void {
    try collector_system.collect(ctx.io, ctx.gpa, ctx.db);
    var rows = try ctx.db.snapshotsForSource(ctx.gpa, "system", snapshot_limit);
    defer rows.deinit(ctx.gpa);
    try app_render.writeSnapshotRows(rows.items, writer);
}

pub fn collectAndWriteServices(ctx: Context, writer: anytype) !void {
    try collector_system.collectServices(ctx.io, ctx.gpa, ctx.db);
    var rows = try ctx.db.serviceList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try app_render.writeNameValueRows(rows.items, writer);
}

pub fn collectAndWritePorts(ctx: Context, writer: anytype) !void {
    try collector_system.collectSockets(ctx.io, ctx.gpa, ctx.db);
    var rows = try ctx.db.socketList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try app_render.writeNameValueRows(rows.items, writer);
}

pub fn collectAndWriteContainers(ctx: Context, writer: anytype) !void {
    try collector_system.collectContainers(ctx.io, ctx.gpa, ctx.db);
    var rows = try ctx.db.containerList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try app_render.writeNameValueRows(rows.items, writer);
}

pub fn collectAndWriteMetrics(ctx: Context, writer: anytype) !void {
    try collector_system.collectMetrics(ctx.io, ctx.gpa, ctx.db);
    var rows = try ctx.db.recentMetrics(ctx.gpa, metric_limit);
    defer rows.deinit(ctx.gpa);
    try app_render.writeMetricRows(rows.items, writer);
}

pub fn logs(ctx: Context, unit: []const u8) !Output {
    return try collector_system.logs(ctx.io, ctx.gpa, ctx.db, unit);
}

test "system read models render snapshots, lists, and metrics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-system.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    _ = try db.insertSnapshot("system", "uptime", null, "ok", "up 1 minute", null, null);
    try db.upsertService("caddy.service", "system", "running", "running", "Caddy", "raw");
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:443", "caddy", "raw");
    try db.upsertContainer("plausible", "plausible:latest", "Up", "8000/tcp", "raw");
    try db.insertSystemMetric("loadavg", "0.12 0.15 0.20", null);

    var snapshots = try db.snapshotsForSource(allocator, "system", 12);
    defer snapshots.deinit(allocator);
    var services = try db.serviceList(allocator);
    defer services.deinit(allocator);
    var sockets = try db.socketList(allocator);
    defer sockets.deinit(allocator);
    var containers = try db.containerList(allocator);
    defer containers.deinit(allocator);
    var metrics = try db.recentMetrics(allocator, 30);
    defer metrics.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try app_render.writeSnapshotRows(snapshots.items, &out.writer);
    try app_render.writeNameValueRows(services.items, &out.writer);
    try app_render.writeNameValueRows(sockets.items, &out.writer);
    try app_render.writeNameValueRows(containers.items, &out.writer);
    try app_render.writeMetricRows(metrics.items, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "uptime  [ok] up 1 minute") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "caddy.service\trunning\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "127.0.0.1:443\tcaddy\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "plausible\tUp\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "loadavg\t0.12 0.15 0.20\t") != null);
}
