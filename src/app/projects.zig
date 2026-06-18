const std = @import("std");
const app_render = @import("app_render");
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

pub const CorrelationOptions = struct {
    limit: i64 = 200,
};

pub fn writeList(ctx: Context, writer: anytype) !void {
    try collector_projects.collect(ctx.io, ctx.gpa, ctx.projects_root, ctx.db);
    var rows = try ctx.db.projectList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try app_render.writeNameValueRows(rows.items, writer);
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

pub fn writeCorrelationsText(ctx: Context, options: CorrelationOptions, writer: anytype) !void {
    var rows = try ctx.db.projectCorrelations(ctx.gpa, options.limit);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("project correlations\n");
    if (rows.items.len == 0) {
        try writer.writeAll("none\n");
        return;
    }
    for (rows.items) |row| try writeCorrelationText(row, writer);
}

pub fn writeCorrelationsJson(ctx: Context, options: CorrelationOptions, writer: anytype) !void {
    var rows = try ctx.db.projectCorrelations(ctx.gpa, options.limit);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"project_correlations\",\"items\":[");
    for (rows.items, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writeCorrelationJson(row, writer);
    }
    try writer.writeAll("]}\n");
}

fn writeCorrelationText(row: db_store.ProjectCorrelation, writer: anytype) !void {
    const label = if (row.project.len > 0) row.project else row.host;
    try writer.print("{s}", .{label});
    try app_render.writeTextField(writer, "source", row.source);
    try app_render.writeTextField(writer, "path", row.path);
    try app_render.writeTextField(writer, "host", row.host);
    try app_render.writeTextField(writer, "caddy", row.caddy_source);
    try app_render.writeTextField(writer, "upstream", row.upstream);
    try app_render.writeTextField(writer, "socket", row.socket_state);
    try app_render.writeTextField(writer, "process", row.socket_process);
    try app_render.writeTextField(writer, "service", row.service);
    try app_render.writeTextField(writer, "service_state", row.service_state);
    try app_render.writeTextField(writer, "container", row.container);
    try app_render.writeTextField(writer, "container_status", row.container_status);
    try writer.writeByte('\n');
}

fn writeCorrelationJson(row: db_store.ProjectCorrelation, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "project", row.project, true);
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "path", row.path, true);
    try app_render.writeJsonStringField(writer, "host", row.host, true);
    try app_render.writeJsonStringField(writer, "caddy_source", row.caddy_source, true);
    try app_render.writeJsonStringField(writer, "upstream", row.upstream, true);
    try app_render.writeJsonStringField(writer, "socket_state", row.socket_state, true);
    try app_render.writeJsonStringField(writer, "socket_process", row.socket_process, true);
    try app_render.writeJsonStringField(writer, "service", row.service, true);
    try app_render.writeJsonStringField(writer, "service_state", row.service_state, true);
    try app_render.writeJsonStringField(writer, "container", row.container, true);
    try app_render.writeJsonStringField(writer, "container_status", row.container_status, false);
    try writer.writeByte('}');
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

test "projects app correlates Caddy routes with system state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-project-correlations.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCaddySite("cloudio.local", "/etc/caddy/conf.d/sites.caddy", "cloudio.local { reverse_proxy 127.0.0.1:9000 }");
    try db.insertCaddyUpstream("cloudio.local", "", "127.0.0.1:9000");
    try db.upsertProject("cloudio", "compose", "/home/kid/Projects/cloudio/compose.yaml", "cloudio.local", "127.0.0.1:9000", "cloudio.service", "cloudio-1", null);
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9000", "cloudio", "raw");
    try db.upsertService("cloudio.service", "user", "running", "running", "Cloudio", "raw");
    try db.upsertContainer("cloudio-1", "cloudio:latest", "Up 2 minutes", "9000/tcp", "raw");
    try db.insertCaddyUpstream("orphan.local", "", "127.0.0.1:9100");

    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .projects_root = "/home/kid/Projects",
        .db = &db,
    };

    var rows = try db.projectCorrelations(allocator, 20);
    defer rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("cloudio", rows.items[0].project);
    try std.testing.expectEqualStrings("LISTEN", rows.items[0].socket_state);
    try std.testing.expectEqualStrings("running", rows.items[0].service_state);
    try std.testing.expectEqualStrings("Up 2 minutes", rows.items[0].container_status);
    try std.testing.expectEqualStrings("", rows.items[1].project);
    try std.testing.expectEqualStrings("orphan.local", rows.items[1].host);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeCorrelationsText(ctx, .{ .limit = 20 }, &out.writer);
    try writeCorrelationsJson(ctx, .{ .limit = 20 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "project correlations\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio\tsource=compose\tpath=/home/kid/Projects/cloudio/compose.yaml\thost=cloudio.local\tcaddy=/etc/caddy/conf.d/sites.caddy\tupstream=127.0.0.1:9000\tsocket=LISTEN\tprocess=cloudio\tservice=cloudio.service\tservice_state=running\tcontainer=cloudio-1\tcontainer_status=Up 2 minutes\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "orphan.local\tsource=caddy\thost=orphan.local\tupstream=127.0.0.1:9100\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"kind\":\"project_correlations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"project\":\"cloudio\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"socket_state\":\"LISTEN\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"container_status\":\"Up 2 minutes\"") != null);
}
