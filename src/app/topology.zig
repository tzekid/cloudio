const std = @import("std");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_limit = 200;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const Options = struct {
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{ .limit = app_render.positiveLimit(self.limit, default_limit) };
    }
};

pub const Summary = struct {
    total: usize = 0,
    dns: usize = 0,
    caddy: usize = 0,
    projects: usize = 0,
    sockets: usize = 0,
    services: usize = 0,
    containers: usize = 0,
    dns_only: usize = 0,
    caddy_without_dns: usize = 0,
    upstream_without_socket: usize = 0,
};

pub const Topology = struct {
    options: Options,
    rows: db_store.TopologyRows,

    pub fn load(ctx: Context, options: Options) !Topology {
        const normalized = options.normalized();
        return .{
            .options = normalized,
            .rows = try ctx.db.topologyRows(ctx.gpa, normalized.limit),
        };
    }

    pub fn deinit(self: *Topology, gpa: Allocator) void {
        self.rows.deinit(gpa);
    }

    pub fn summary(self: Topology) Summary {
        var out = Summary{ .total = self.rows.items.len };
        for (self.rows.items) |row| {
            if (row.dns_name.len != 0) out.dns += 1;
            if (row.caddy_source.len != 0 or row.upstream.len != 0) out.caddy += 1;
            if (row.project.len != 0) out.projects += 1;
            if (row.socket_state.len != 0) out.sockets += 1;
            if (row.service_state.len != 0) out.services += 1;
            if (row.container_status.len != 0) out.containers += 1;
            if (row.dns_name.len != 0 and row.upstream.len == 0 and row.project.len == 0) out.dns_only += 1;
            if (row.host.len != 0 and row.upstream.len != 0 and row.dns_name.len == 0) out.caddy_without_dns += 1;
            if (row.upstream.len != 0 and row.socket_state.len == 0) out.upstream_without_socket += 1;
        }
        return out;
    }

    pub fn writeText(self: Topology, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Cloudio topology\n");
        try writer.print("limit={d} total={d} dns={d} caddy={d} projects={d} sockets={d} services={d} containers={d} dns_only={d} caddy_without_dns={d} upstream_without_socket={d}\n", .{
            self.options.limit,
            counts.total,
            counts.dns,
            counts.caddy,
            counts.projects,
            counts.sockets,
            counts.services,
            counts.containers,
            counts.dns_only,
            counts.caddy_without_dns,
            counts.upstream_without_socket,
        });
        if (self.rows.items.len == 0) {
            try writer.writeAll("none\n");
            return;
        }
        for (self.rows.items) |row| try writeRowText(row, writer);
    }

    pub fn writeJson(self: Topology, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"topology\",");
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try writer.writeAll("\"summary\":");
        try writeSummaryJson(self.summary(), writer);
        try writer.writeAll(",\"items\":[");
        for (self.rows.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeRowJson(row, writer);
        }
        try writer.writeAll("]}\n");
    }
};

pub fn writeText(ctx: Context, options: Options, writer: anytype) !void {
    var topology = try Topology.load(ctx, options);
    defer topology.deinit(ctx.gpa);
    try topology.writeText(writer);
}

pub fn writeJson(ctx: Context, options: Options, writer: anytype) !void {
    var topology = try Topology.load(ctx, options);
    defer topology.deinit(ctx.gpa);
    try topology.writeJson(writer);
}

fn writeRowText(row: db_store.TopologyRow, writer: anytype) !void {
    try writer.print("{s}", .{row.host});
    try app_render.writeTextField(writer, "dns", row.dns_name);
    try app_render.writeTextField(writer, "dns_type", row.dns_type);
    try app_render.writeTextField(writer, "dns_content", row.dns_content);
    try app_render.writeTextField(writer, "proxied", row.dns_proxied);
    try app_render.writeTextField(writer, "project", row.project);
    try app_render.writeTextField(writer, "source", row.source);
    try app_render.writeTextField(writer, "path", row.path);
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

fn writeSummaryJson(summary: Summary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "total", summary.total, true);
    try app_render.writeJsonIntField(writer, "dns", summary.dns, true);
    try app_render.writeJsonIntField(writer, "caddy", summary.caddy, true);
    try app_render.writeJsonIntField(writer, "projects", summary.projects, true);
    try app_render.writeJsonIntField(writer, "sockets", summary.sockets, true);
    try app_render.writeJsonIntField(writer, "services", summary.services, true);
    try app_render.writeJsonIntField(writer, "containers", summary.containers, true);
    try app_render.writeJsonIntField(writer, "dns_only", summary.dns_only, true);
    try app_render.writeJsonIntField(writer, "caddy_without_dns", summary.caddy_without_dns, true);
    try app_render.writeJsonIntField(writer, "upstream_without_socket", summary.upstream_without_socket, false);
    try writer.writeByte('}');
}

fn writeRowJson(row: db_store.TopologyRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "host", row.host, true);
    try app_render.writeJsonStringField(writer, "dns_name", row.dns_name, true);
    try app_render.writeJsonStringField(writer, "dns_type", row.dns_type, true);
    try app_render.writeJsonStringField(writer, "dns_content", row.dns_content, true);
    try app_render.writeJsonStringField(writer, "dns_proxied", row.dns_proxied, true);
    try app_render.writeJsonStringField(writer, "project", row.project, true);
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "path", row.path, true);
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

test "topology read model connects DNS Caddy project and system state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-topology.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertCloudflareZone("zone-1", "plosca.ru", "account-1", "active", false, "full", "[]", "{}");
    try db.upsertDnsRecord("record-1", "zone-1", "api.plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertDnsRecord("record-2", "zone-1", "dns-only.plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertCaddySite("api.plosca.ru", "/etc/caddy/conf.d/sites.caddy", "api.plosca.ru { reverse_proxy 127.0.0.1:9000 }");
    try db.insertCaddyUpstream("api.plosca.ru", "", "127.0.0.1:9000");
    try db.insertCaddyUpstream("local-only.plosca.ru", "", "127.0.0.1:9100");
    try db.upsertProject("api", "compose", "/home/kid/Projects/api/compose.yaml", "api.plosca.ru", "127.0.0.1:9000", "api.service", "api-1", null);
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9000", "api", "raw");
    try db.upsertService("api.service", "user", "running", "running", "API", "raw");
    try db.upsertContainer("api-1", "api:latest", "Up", "9000/tcp", "raw");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var topology = try Topology.load(ctx, .{ .limit = 20 });
    defer topology.deinit(allocator);
    const summary = topology.summary();
    try std.testing.expectEqual(@as(usize, 3), summary.total);
    try std.testing.expectEqual(@as(usize, 2), summary.dns);
    try std.testing.expectEqual(@as(usize, 2), summary.caddy);
    try std.testing.expectEqual(@as(usize, 1), summary.projects);
    try std.testing.expectEqual(@as(usize, 1), summary.sockets);
    try std.testing.expectEqual(@as(usize, 1), summary.dns_only);
    try std.testing.expectEqual(@as(usize, 1), summary.caddy_without_dns);
    try std.testing.expectEqual(@as(usize, 1), summary.upstream_without_socket);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try topology.writeText(&text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio topology\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api.plosca.ru\tdns=api.plosca.ru\tdns_type=A\tdns_content=76.13.130.170") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "socket=LISTEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dns-only.plosca.ru\tdns=dns-only.plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "local-only.plosca.ru\tsource=caddy\tupstream=127.0.0.1:9100") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try topology.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("topology", parsed.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, 3), parsed.value.object.get("summary").?.object.get("total").?.integer);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.object.get("items").?.array.items.len);
}
