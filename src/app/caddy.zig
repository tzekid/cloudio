const std = @import("std");
const collector_caddy = @import("collector_caddy");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Output = collector_caddy.Output;
pub const Paths = collector_caddy.Paths;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: Paths,
    db: *Db,
};

pub fn writeSites(ctx: Context, writer: anytype) !void {
    var sites = try collector_caddy.parseSitesFromFile(ctx.io, ctx.gpa, ctx.paths.caddy_sites_path);
    defer sites.deinit(ctx.gpa);
    try writeSiteRows(sites.items, writer);
}

pub fn collectAndWriteUpstreams(ctx: Context, writer: anytype) !void {
    try collector_caddy.collect(ctx.io, ctx.gpa, ctx.paths, ctx.db);
    var rows = try ctx.db.caddyUpstreams(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try writeUpstreamRows(rows.items, writer);
}

pub fn render(ctx: Context) !Output {
    return try collector_caddy.render(ctx.io, ctx.gpa, ctx.paths);
}

pub fn diff(ctx: Context) !Output {
    return try collector_caddy.diff(ctx.io, ctx.gpa, ctx.paths);
}

pub fn validate(ctx: Context) !Output {
    return try collector_caddy.validate(ctx.io, ctx.gpa, ctx.paths);
}

fn writeSiteRows(sites: []const collector_caddy.Site, writer: anytype) !void {
    for (sites) |site| {
        try writer.writeAll(site.host);
        if (site.upstreams.items.len > 0) {
            try writer.writeAll(" -> ");
            for (site.upstreams.items, 0..) |upstream, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.writeAll(upstream);
            }
        }
        try writer.writeByte('\n');
    }
}

fn writeUpstreamRows(rows: []const db_store.NameValueRow, writer: anytype) !void {
    for (rows) |row| try writer.print("{s} -> {s}\n", .{ row.name, row.value });
}

test "caddy site and upstream rendering stays stable" {
    const allocator = std.testing.allocator;
    var parsed = try collector_caddy.parseSites(allocator,
        \\api.example.com {
        \\  reverse_proxy 127.0.0.1:9000
        \\}
        \\www.example.com {
        \\  redir https://example.com{uri} permanent
        \\}
    );
    defer parsed.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/caddy-app.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.insertCaddyUpstream("api.example.com", "", "127.0.0.1:9000");
    var upstreams = try db.caddyUpstreams(allocator);
    defer upstreams.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeSiteRows(parsed.items, &out.writer);
    try writeUpstreamRows(upstreams.items, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "api.example.com -> 127.0.0.1:9000\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "www.example.com\n") != null);
}
