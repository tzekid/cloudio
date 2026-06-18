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
    healthy: usize = 0,
    degraded: usize = 0,
    local_only: usize = 0,
    project_only: usize = 0,
    dns: usize = 0,
    caddy: usize = 0,
    projects: usize = 0,
    sockets: usize = 0,
    services: usize = 0,
    containers: usize = 0,
    direct_dns: usize = 0,
    wildcard_dns: usize = 0,
    dns_only: usize = 0,
    caddy_without_dns: usize = 0,
    upstream_without_socket: usize = 0,
    project_without_runtime: usize = 0,
    service_not_running: usize = 0,
    container_not_running: usize = 0,
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
            switch (rowStatus(row)) {
                .healthy => out.healthy += 1,
                .degraded => out.degraded += 1,
                .dns_only => out.dns_only += 1,
                .local_only => out.local_only += 1,
                .project_only => out.project_only += 1,
            }
            if (row.dns_name.len != 0) out.dns += 1;
            if (row.caddy_source.len != 0 or row.upstream.len != 0) out.caddy += 1;
            if (row.project.len != 0) out.projects += 1;
            if (row.socket_state.len != 0) out.sockets += 1;
            if (row.service_state.len != 0) out.services += 1;
            if (row.container_status.len != 0) out.containers += 1;
            switch (dnsMatch(row)) {
                .direct => out.direct_dns += 1,
                .wildcard => out.wildcard_dns += 1,
                .none => {},
            }
            if (isCaddyWithoutDns(row)) out.caddy_without_dns += 1;
            if (isUpstreamWithoutSocket(row)) out.upstream_without_socket += 1;
            if (isProjectWithoutRuntime(row)) out.project_without_runtime += 1;
            if (isServiceNotRunning(row)) out.service_not_running += 1;
            if (isContainerNotRunning(row)) out.container_not_running += 1;
        }
        return out;
    }

    pub fn writeText(self: Topology, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Cloudio topology\n");
        try writer.print("limit={d} total={d} healthy={d} degraded={d} dns_only={d} local_only={d} project_only={d} dns={d} caddy={d} projects={d} sockets={d} services={d} containers={d} direct_dns={d} wildcard_dns={d} caddy_without_dns={d} upstream_without_socket={d} project_without_runtime={d} service_not_running={d} container_not_running={d}\n", .{
            self.options.limit,
            counts.total,
            counts.healthy,
            counts.degraded,
            counts.dns_only,
            counts.local_only,
            counts.project_only,
            counts.dns,
            counts.caddy,
            counts.projects,
            counts.sockets,
            counts.services,
            counts.containers,
            counts.direct_dns,
            counts.wildcard_dns,
            counts.caddy_without_dns,
            counts.upstream_without_socket,
            counts.project_without_runtime,
            counts.service_not_running,
            counts.container_not_running,
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
    try app_render.writeTextField(writer, "status", rowStatus(row).label());
    try app_render.writeTextField(writer, "exposure", rowExposure(row));
    try app_render.writeTextField(writer, "dns_match", dnsMatch(row).label());
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
    try writeIssuesText(row, writer);
    try writer.writeByte('\n');
}

fn writeSummaryJson(summary: Summary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "total", summary.total, true);
    try writer.writeAll("\"statuses\":{");
    try app_render.writeJsonIntField(writer, "healthy", summary.healthy, true);
    try app_render.writeJsonIntField(writer, "degraded", summary.degraded, true);
    try app_render.writeJsonIntField(writer, "dns_only", summary.dns_only, true);
    try app_render.writeJsonIntField(writer, "local_only", summary.local_only, true);
    try app_render.writeJsonIntField(writer, "project_only", summary.project_only, false);
    try writer.writeAll("},");
    try app_render.writeJsonIntField(writer, "dns", summary.dns, true);
    try app_render.writeJsonIntField(writer, "caddy", summary.caddy, true);
    try app_render.writeJsonIntField(writer, "projects", summary.projects, true);
    try app_render.writeJsonIntField(writer, "sockets", summary.sockets, true);
    try app_render.writeJsonIntField(writer, "services", summary.services, true);
    try app_render.writeJsonIntField(writer, "containers", summary.containers, true);
    try writer.writeAll("\"dns_matches\":{");
    try app_render.writeJsonIntField(writer, "direct", summary.direct_dns, true);
    try app_render.writeJsonIntField(writer, "wildcard", summary.wildcard_dns, false);
    try writer.writeAll("},\"issues\":{");
    try app_render.writeJsonIntField(writer, "dns_only", summary.dns_only, true);
    try app_render.writeJsonIntField(writer, "caddy_without_dns", summary.caddy_without_dns, true);
    try app_render.writeJsonIntField(writer, "upstream_without_socket", summary.upstream_without_socket, true);
    try app_render.writeJsonIntField(writer, "project_without_runtime", summary.project_without_runtime, true);
    try app_render.writeJsonIntField(writer, "service_not_running", summary.service_not_running, true);
    try app_render.writeJsonIntField(writer, "container_not_running", summary.container_not_running, false);
    try writer.writeByte('}');
    try writer.writeByte('}');
}

fn writeRowJson(row: db_store.TopologyRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "host", row.host, true);
    try app_render.writeJsonStringField(writer, "status", rowStatus(row).label(), true);
    try app_render.writeJsonStringField(writer, "exposure", rowExposure(row), true);
    try app_render.writeJsonStringField(writer, "dns_match", dnsMatch(row).label(), true);
    try writer.writeAll("\"capabilities\":{");
    try app_render.writeJsonBoolField(writer, "dns", hasDns(row), true);
    try app_render.writeJsonBoolField(writer, "caddy", hasCaddy(row), true);
    try app_render.writeJsonBoolField(writer, "project", hasProject(row), true);
    try app_render.writeJsonBoolField(writer, "socket", hasSocket(row), true);
    try app_render.writeJsonBoolField(writer, "service", hasService(row), true);
    try app_render.writeJsonBoolField(writer, "container", hasContainer(row), false);
    try writer.writeAll("},\"issues\":");
    try writeIssuesJson(row, writer);
    try writer.writeByte(',');
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

const RowStatus = enum {
    healthy,
    degraded,
    dns_only,
    local_only,
    project_only,

    fn label(self: RowStatus) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .degraded => "degraded",
            .dns_only => "dns_only",
            .local_only => "local_only",
            .project_only => "project_only",
        };
    }
};

const DnsMatch = enum {
    none,
    direct,
    wildcard,

    fn label(self: DnsMatch) []const u8 {
        return switch (self) {
            .none => "none",
            .direct => "direct",
            .wildcard => "wildcard",
        };
    }
};

fn hasDns(row: db_store.TopologyRow) bool {
    return row.dns_name.len != 0;
}

fn hasCaddy(row: db_store.TopologyRow) bool {
    return row.caddy_source.len != 0 or row.upstream.len != 0;
}

fn hasProject(row: db_store.TopologyRow) bool {
    return row.project.len != 0;
}

fn hasSocket(row: db_store.TopologyRow) bool {
    return row.socket_state.len != 0;
}

fn hasService(row: db_store.TopologyRow) bool {
    return row.service.len != 0;
}

fn hasContainer(row: db_store.TopologyRow) bool {
    return row.container.len != 0;
}

fn dnsMatch(row: db_store.TopologyRow) DnsMatch {
    if (row.dns_name.len == 0) return .none;
    if (std.mem.startsWith(u8, row.dns_name, "*.")) return .wildcard;
    return .direct;
}

fn rowExposure(row: db_store.TopologyRow) []const u8 {
    if (hasDns(row)) return "public";
    if (hasCaddy(row)) return "local";
    if (hasProject(row) or hasService(row) or hasContainer(row)) return "internal";
    return "unknown";
}

fn rowStatus(row: db_store.TopologyRow) RowStatus {
    if (isUpstreamWithoutSocket(row) or isServiceNotRunning(row) or isContainerNotRunning(row)) return .degraded;
    if (isDnsOnly(row)) return .dns_only;
    if (isCaddyWithoutDns(row)) return .local_only;
    if (isProjectWithoutRuntime(row)) return .project_only;
    return .healthy;
}

fn isDnsOnly(row: db_store.TopologyRow) bool {
    return hasDns(row) and !hasCaddy(row) and !hasProject(row);
}

fn isCaddyWithoutDns(row: db_store.TopologyRow) bool {
    return row.host.len != 0 and hasCaddy(row) and !hasDns(row);
}

fn isUpstreamWithoutSocket(row: db_store.TopologyRow) bool {
    return row.upstream.len != 0 and !hasSocket(row);
}

fn isProjectWithoutRuntime(row: db_store.TopologyRow) bool {
    return hasProject(row) and row.host.len == 0 and row.upstream.len == 0 and row.service.len == 0 and row.container.len == 0;
}

fn isServiceNotRunning(row: db_store.TopologyRow) bool {
    return hasService(row) and !stateLooksRunning(row.service_state);
}

fn isContainerNotRunning(row: db_store.TopologyRow) bool {
    return hasContainer(row) and !stateLooksRunning(row.container_status);
}

fn stateLooksRunning(value: []const u8) bool {
    return containsIgnoreCase(value, "running") or containsIgnoreCase(value, "active") or containsIgnoreCase(value, "up");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn writeIssuesText(row: db_store.TopologyRow, writer: anytype) !void {
    if (issueCount(row) == 0) return;
    try writer.writeAll("\tissues=");
    var first = true;
    try writeIssueText(writer, &first, isDnsOnly(row), "dns_without_local_target");
    try writeIssueText(writer, &first, isCaddyWithoutDns(row), "caddy_without_dns");
    try writeIssueText(writer, &first, isUpstreamWithoutSocket(row), "upstream_without_socket");
    try writeIssueText(writer, &first, isProjectWithoutRuntime(row), "project_without_runtime");
    try writeIssueText(writer, &first, isServiceNotRunning(row), "service_not_running");
    try writeIssueText(writer, &first, isContainerNotRunning(row), "container_not_running");
}

fn writeIssueText(writer: anytype, first: *bool, present: bool, label: []const u8) !void {
    if (!present) return;
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeAll(label);
}

fn writeIssuesJson(row: db_store.TopologyRow, writer: anytype) !void {
    try writer.writeByte('[');
    var first = true;
    try writeIssueJson(writer, &first, isDnsOnly(row), "dns_without_local_target");
    try writeIssueJson(writer, &first, isCaddyWithoutDns(row), "caddy_without_dns");
    try writeIssueJson(writer, &first, isUpstreamWithoutSocket(row), "upstream_without_socket");
    try writeIssueJson(writer, &first, isProjectWithoutRuntime(row), "project_without_runtime");
    try writeIssueJson(writer, &first, isServiceNotRunning(row), "service_not_running");
    try writeIssueJson(writer, &first, isContainerNotRunning(row), "container_not_running");
    try writer.writeByte(']');
}

fn writeIssueJson(writer: anytype, first: *bool, present: bool, label: []const u8) !void {
    if (!present) return;
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try app_render.writeJsonString(writer, label);
}

fn issueCount(row: db_store.TopologyRow) usize {
    var count: usize = 0;
    if (isDnsOnly(row)) count += 1;
    if (isCaddyWithoutDns(row)) count += 1;
    if (isUpstreamWithoutSocket(row)) count += 1;
    if (isProjectWithoutRuntime(row)) count += 1;
    if (isServiceNotRunning(row)) count += 1;
    if (isContainerNotRunning(row)) count += 1;
    return count;
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
    try db.upsertProject("compose-only", "compose", "/home/kid/Projects/compose-only/compose.yaml", null, null, null, null, null);
    try db.upsertProject("worker", "systemd", "/home/kid/Projects/worker", null, null, "worker.service", "worker-1", null);
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9000", "api", "raw");
    try db.upsertService("api.service", "user", "running", "running", "API", "raw");
    try db.upsertService("worker.service", "user", "failed", "failed", "Worker", "raw");
    try db.upsertContainer("api-1", "api:latest", "Up", "9000/tcp", "raw");
    try db.upsertContainer("worker-1", "worker:latest", "Exited (1)", "", "raw");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var topology = try Topology.load(ctx, .{ .limit = 20 });
    defer topology.deinit(allocator);
    const summary = topology.summary();
    try std.testing.expectEqual(@as(usize, 5), summary.total);
    try std.testing.expectEqual(@as(usize, 1), summary.healthy);
    try std.testing.expectEqual(@as(usize, 2), summary.degraded);
    try std.testing.expectEqual(@as(usize, 1), summary.dns_only);
    try std.testing.expectEqual(@as(usize, 0), summary.local_only);
    try std.testing.expectEqual(@as(usize, 1), summary.project_only);
    try std.testing.expectEqual(@as(usize, 2), summary.dns);
    try std.testing.expectEqual(@as(usize, 2), summary.caddy);
    try std.testing.expectEqual(@as(usize, 3), summary.projects);
    try std.testing.expectEqual(@as(usize, 1), summary.sockets);
    try std.testing.expectEqual(@as(usize, 2), summary.services);
    try std.testing.expectEqual(@as(usize, 2), summary.containers);
    try std.testing.expectEqual(@as(usize, 2), summary.direct_dns);
    try std.testing.expectEqual(@as(usize, 0), summary.wildcard_dns);
    try std.testing.expectEqual(@as(usize, 1), summary.dns_only);
    try std.testing.expectEqual(@as(usize, 1), summary.caddy_without_dns);
    try std.testing.expectEqual(@as(usize, 1), summary.upstream_without_socket);
    try std.testing.expectEqual(@as(usize, 1), summary.project_without_runtime);
    try std.testing.expectEqual(@as(usize, 1), summary.service_not_running);
    try std.testing.expectEqual(@as(usize, 1), summary.container_not_running);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try topology.writeText(&text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio topology\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "healthy=1 degraded=2 dns_only=1 local_only=0 project_only=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api.plosca.ru\tstatus=healthy\texposure=public\tdns_match=direct\tdns=api.plosca.ru\tdns_type=A\tdns_content=76.13.130.170") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "socket=LISTEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dns-only.plosca.ru\tstatus=dns_only\texposure=public\tdns_match=direct\tdns=dns-only.plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "local-only.plosca.ru\tstatus=degraded\texposure=local\tdns_match=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "issues=caddy_without_dns,upstream_without_socket") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "status=project_only\texposure=internal\tdns_match=none\tproject=compose-only") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "status=degraded\texposure=internal\tdns_match=none\tproject=worker") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "issues=service_not_running,container_not_running") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try topology.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("topology", parsed.value.object.get("kind").?.string);
    const summary_json = parsed.value.object.get("summary").?.object;
    try std.testing.expectEqual(@as(i64, 5), summary_json.get("total").?.integer);
    try std.testing.expectEqual(@as(i64, 1), summary_json.get("statuses").?.object.get("healthy").?.integer);
    try std.testing.expectEqual(@as(i64, 2), summary_json.get("statuses").?.object.get("degraded").?.integer);
    try std.testing.expectEqual(@as(i64, 1), summary_json.get("statuses").?.object.get("project_only").?.integer);
    try std.testing.expectEqual(@as(i64, 2), summary_json.get("dns_matches").?.object.get("direct").?.integer);
    try std.testing.expectEqual(@as(i64, 1), summary_json.get("issues").?.object.get("upstream_without_socket").?.integer);
    try std.testing.expectEqual(@as(i64, 1), summary_json.get("issues").?.object.get("service_not_running").?.integer);
    try std.testing.expectEqual(@as(usize, 5), parsed.value.object.get("items").?.array.items.len);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"healthy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"exposure\":\"public\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dns_match\":\"direct\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"capabilities\":{\"dns\":true,\"caddy\":true,\"project\":true,\"socket\":true,\"service\":true,\"container\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"issues\":[\"caddy_without_dns\",\"upstream_without_socket\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"issues\":[\"service_not_running\",\"container_not_running\"]") != null);
}
