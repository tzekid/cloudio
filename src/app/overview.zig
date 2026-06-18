const std = @import("std");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_snapshot_limit = 12;

pub const Counts = struct {
    snapshots: i64,
    cloudflare_accounts: i64,
    cloudflare_zones: i64,
    cloudflare_dns_records: i64,
    cloudflare_resources: i64,
    cloudflare_inventory_items: i64,
    hostinger_vps: i64,
    hostinger_resources: i64,
    hostinger_inventory_items: i64,
    caddy_sites: i64,
    caddy_upstreams: i64,
    projects: i64,
    services: i64,
    sockets: i64,
    containers: i64,

    pub fn load(db: *Db) !Counts {
        return .{
            .snapshots = try db.countTable("snapshots"),
            .cloudflare_accounts = try db.countTable("cloudflare_accounts"),
            .cloudflare_zones = try db.countTable("cloudflare_zones"),
            .cloudflare_dns_records = try db.countTable("cloudflare_dns_records"),
            .cloudflare_resources = try db.countTable("cloudflare_resources"),
            .cloudflare_inventory_items = try db.countTable("cloudflare_inventory_items"),
            .hostinger_vps = try db.countTable("hostinger_vps"),
            .hostinger_resources = try db.countTable("hostinger_resources"),
            .hostinger_inventory_items = try db.countTable("hostinger_inventory_items"),
            .caddy_sites = try db.countTable("caddy_sites"),
            .caddy_upstreams = try db.countTable("caddy_upstreams"),
            .projects = try db.countTable("projects"),
            .services = try db.countTable("services"),
            .sockets = try db.countTable("sockets"),
            .containers = try db.countTable("containers"),
        };
    }
};

pub const Overview = struct {
    counts: Counts,
    snapshots: db_store.SnapshotSummaries,

    pub fn load(gpa: Allocator, db: *Db, snapshot_limit: i64) !Overview {
        return .{
            .counts = try Counts.load(db),
            .snapshots = try db.recentSnapshots(gpa, snapshot_limit),
        };
    }

    pub fn deinit(self: *Overview, gpa: Allocator) void {
        self.snapshots.deinit(gpa);
    }

    pub fn writeText(self: Overview, writer: anytype) !void {
        try writer.writeAll("Cloudio overview\n");
        try writeCounts(writer, self.counts);
        try writer.writeByte('\n');
        for (self.snapshots.items) |row| {
            try writer.print("{s}/{s} {s} [{s}] {s} {s}\n", .{
                row.source,
                row.kind,
                row.target,
                row.status,
                row.summary,
                row.captured_at,
            });
        }
    }

    pub fn writeJson(self: Overview, writer: anytype) !void {
        try writer.writeAll("{\"counts\":{");
        try app_render.writeJsonIntField(writer, "snapshots", self.counts.snapshots, true);
        try app_render.writeJsonIntField(writer, "cloudflare_accounts", self.counts.cloudflare_accounts, true);
        try app_render.writeJsonIntField(writer, "cloudflare_zones", self.counts.cloudflare_zones, true);
        try app_render.writeJsonIntField(writer, "cloudflare_dns_records", self.counts.cloudflare_dns_records, true);
        try app_render.writeJsonIntField(writer, "cloudflare_resources", self.counts.cloudflare_resources, true);
        try app_render.writeJsonIntField(writer, "cloudflare_inventory_items", self.counts.cloudflare_inventory_items, true);
        try app_render.writeJsonIntField(writer, "hostinger_vps", self.counts.hostinger_vps, true);
        try app_render.writeJsonIntField(writer, "hostinger_resources", self.counts.hostinger_resources, true);
        try app_render.writeJsonIntField(writer, "hostinger_inventory_items", self.counts.hostinger_inventory_items, true);
        try app_render.writeJsonIntField(writer, "caddy_sites", self.counts.caddy_sites, true);
        try app_render.writeJsonIntField(writer, "caddy_upstreams", self.counts.caddy_upstreams, true);
        try app_render.writeJsonIntField(writer, "projects", self.counts.projects, true);
        try app_render.writeJsonIntField(writer, "services", self.counts.services, true);
        try app_render.writeJsonIntField(writer, "sockets", self.counts.sockets, true);
        try app_render.writeJsonIntField(writer, "containers", self.counts.containers, false);
        try writer.writeAll("},\"recent_snapshots\":[");
        for (self.snapshots.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeSnapshotJson(row, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub fn writeText(gpa: Allocator, db: *Db, writer: anytype) !void {
    var overview = try Overview.load(gpa, db, default_snapshot_limit);
    defer overview.deinit(gpa);
    try overview.writeText(writer);
}

pub fn writeJson(gpa: Allocator, db: *Db, writer: anytype) !void {
    var overview = try Overview.load(gpa, db, default_snapshot_limit);
    defer overview.deinit(gpa);
    try overview.writeJson(writer);
}

fn writeCounts(writer: anytype, counts: Counts) !void {
    try writer.print("snapshots: {d}\n", .{counts.snapshots});
    try writer.print("cloudflare accounts: {d}\n", .{counts.cloudflare_accounts});
    try writer.print("cloudflare zones: {d}\n", .{counts.cloudflare_zones});
    try writer.print("cloudflare dns records: {d}\n", .{counts.cloudflare_dns_records});
    try writer.print("cloudflare resources: {d}\n", .{counts.cloudflare_resources});
    try writer.print("cloudflare inventory items: {d}\n", .{counts.cloudflare_inventory_items});
    try writer.print("hostinger vps: {d}\n", .{counts.hostinger_vps});
    try writer.print("hostinger resources: {d}\n", .{counts.hostinger_resources});
    try writer.print("hostinger inventory items: {d}\n", .{counts.hostinger_inventory_items});
    try writer.print("caddy sites: {d}\n", .{counts.caddy_sites});
    try writer.print("caddy upstreams: {d}\n", .{counts.caddy_upstreams});
    try writer.print("projects: {d}\n", .{counts.projects});
    try writer.print("services: {d}\n", .{counts.services});
    try writer.print("sockets: {d}\n", .{counts.sockets});
    try writer.print("containers: {d}\n", .{counts.containers});
}

fn writeSnapshotJson(row: db_store.SnapshotSummary, writer: anytype) !void {
    try app_render.writeSnapshotJson(writer, row, .{});
}

test "overview loads typed counts and renders recent snapshots" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    _ = try db.insertSnapshot("system", "uptime", null, "ok", "up 1 minute", null, null);

    var overview = try Overview.load(allocator, &db, 12);
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 1), overview.counts.snapshots);
    try std.testing.expectEqual(@as(usize, 1), overview.snapshots.items.len);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try overview.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "snapshots: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "system/uptime  [ok] up 1 minute") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try overview.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"counts\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":\"up 1 minute\"") != null);
}
