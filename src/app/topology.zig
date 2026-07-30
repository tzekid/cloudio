const std = @import("std");
const sqlite = @import("sqlite");
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
        var rows = try ctx.db.topologyRows(ctx.gpa, normalized.limit);
        errdefer rows.deinit(ctx.gpa);
        try hydrateDerivedRuntime(ctx, &rows);
        return .{
            .options = normalized,
            .rows = rows,
        };
    }

    pub fn deinit(self: *Topology, gpa: Allocator) void {
        self.rows.deinit(gpa);
    }

    pub fn summary(self: Topology) Summary {
        return summarizeRows(self.rows.items);
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

pub const DeltaSummary = struct {
    added: usize = 0,
    changed: usize = 0,
    removed: usize = 0,
    unchanged: usize = 0,

    pub fn totalChanges(self: DeltaSummary) usize {
        return self.added + self.changed + self.removed;
    }
};

const PreviousState = struct {
    key: []u8,
    status: []u8,
    fingerprint: []u8,

    fn deinit(self: PreviousState, gpa: Allocator) void {
        gpa.free(self.key);
        gpa.free(self.status);
        gpa.free(self.fingerprint);
    }
};

/// Captures the current operational graph as a typed projection and records
/// only added, changed, and removed resources in topology_changes.
pub fn captureDeltas(ctx: Context, options: Options) !DeltaSummary {
    var topology = try Topology.load(ctx, options);
    defer topology.deinit(ctx.gpa);

    var current_keys = std.ArrayList([]u8).empty;
    defer {
        for (current_keys.items) |key| ctx.gpa.free(key);
        current_keys.deinit(ctx.gpa);
    }
    var summary = DeltaSummary{};

    try ctx.db.exec("BEGIN IMMEDIATE");
    errdefer ctx.db.exec("ROLLBACK") catch {};

    for (topology.rows.items) |row| {
        const key = try topologyResourceKey(ctx.gpa, row);
        try current_keys.append(ctx.gpa, key);
        const fingerprint = topologyFingerprint(row);
        const status = rowStatus(row).label();

        if (try readTopologyState(ctx, key)) |previous| {
            defer previous.deinit(ctx.gpa);
            if (std.mem.eql(u8, previous.fingerprint, &fingerprint)) {
                summary.unchanged += 1;
            } else {
                summary.changed += 1;
                try insertTopologyChange(ctx, key, "changed", previous.status, status, previous.fingerprint, &fingerprint);
            }
        } else {
            summary.added += 1;
            try insertTopologyChange(ctx, key, "added", null, status, null, &fingerprint);
        }
        try upsertTopologyState(ctx, key, status, &fingerprint);
    }

    var previous_rows = std.ArrayList(PreviousState).empty;
    defer {
        for (previous_rows.items) |row| row.deinit(ctx.gpa);
        previous_rows.deinit(ctx.gpa);
    }
    {
        const stmt = try ctx.db.prepare("SELECT resource_key, status, fingerprint FROM topology_state");
        defer _ = sqlite.sqlite3_finalize(stmt);
        while (true) {
            const rc = sqlite.sqlite3_step(stmt);
            if (rc == sqlite.SQLITE_DONE) break;
            if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
            const key = topologyColumnText(stmt, 0) orelse "";
            if (containsString(current_keys.items, key)) continue;
            try previous_rows.append(ctx.gpa, .{
                .key = try ctx.gpa.dupe(u8, key),
                .status = try ctx.gpa.dupe(u8, topologyColumnText(stmt, 1) orelse ""),
                .fingerprint = try ctx.gpa.dupe(u8, topologyColumnText(stmt, 2) orelse ""),
            });
        }
    }
    for (previous_rows.items) |previous| {
        summary.removed += 1;
        try insertTopologyChange(ctx, previous.key, "removed", previous.status, null, previous.fingerprint, null);
        const stmt = try ctx.db.prepare("DELETE FROM topology_state WHERE resource_key = ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try topologyBindText(stmt, 1, previous.key);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
    }

    try ctx.db.exec("COMMIT");
    return summary;
}

pub fn writeDeltaSummaryText(summary: DeltaSummary, writer: anytype) !void {
    try writer.print("topology changes added={d} changed={d} removed={d} unchanged={d}\n", .{
        summary.added,
        summary.changed,
        summary.removed,
        summary.unchanged,
    });
}

pub fn writeDeltaSummaryJson(summary: DeltaSummary, writer: anytype) !void {
    try writer.writeAll("{\"kind\":\"topology_delta_capture\",");
    try app_render.writeJsonIntField(writer, "added", summary.added, true);
    try app_render.writeJsonIntField(writer, "changed", summary.changed, true);
    try app_render.writeJsonIntField(writer, "removed", summary.removed, true);
    try app_render.writeJsonIntField(writer, "unchanged", summary.unchanged, true);
    try app_render.writeJsonIntField(writer, "total_changes", summary.totalChanges(), false);
    try writer.writeAll("}\n");
}

pub fn writeChangesJson(ctx: Context, limit: i64, writer: anytype) !void {
    const stmt = try ctx.db.prepare(
        \\SELECT id, resource_key, change_type, previous_status, current_status, observed_at
        \\FROM topology_changes ORDER BY id DESC LIMIT ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app_render.positiveLimit(limit, 100)) != sqlite.SQLITE_OK) return error.SqliteBind;
    try writer.writeAll("{\"kind\":\"topology_changes\",\"changes\":[");
    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try app_render.writeJsonIntField(writer, "id", sqlite.sqlite3_column_int64(stmt, 0), true);
        try app_render.writeJsonStringField(writer, "resource_key", topologyColumnText(stmt, 1) orelse "", true);
        try app_render.writeJsonStringField(writer, "change_type", topologyColumnText(stmt, 2) orelse "", true);
        try app_render.writeJsonStringField(writer, "previous_status", topologyColumnText(stmt, 3) orelse "", true);
        try app_render.writeJsonStringField(writer, "current_status", topologyColumnText(stmt, 4) orelse "", true);
        try app_render.writeJsonStringField(writer, "observed_at", topologyColumnText(stmt, 5) orelse "", false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeChangesText(ctx: Context, limit: i64, writer: anytype) !void {
    const stmt = try ctx.db.prepare(
        \\SELECT resource_key, change_type, previous_status, current_status, observed_at
        \\FROM topology_changes ORDER BY id DESC LIMIT ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app_render.positiveLimit(limit, 100)) != sqlite.SQLITE_OK) return error.SqliteBind;
    try writer.writeAll("Topology changes\n");
    var found = false;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
        found = true;
        try writer.print("{s}\t{s}\tprevious={s}\tcurrent={s}\tobserved={s}\n", .{
            topologyColumnText(stmt, 0) orelse "",
            topologyColumnText(stmt, 1) orelse "",
            topologyColumnText(stmt, 2) orelse "",
            topologyColumnText(stmt, 3) orelse "",
            topologyColumnText(stmt, 4) orelse "",
        });
    }
    if (!found) try writer.writeAll("none\n");
}

fn topologyResourceKey(gpa: Allocator, row: db_store.TopologyRow) ![]u8 {
    if (row.host.len != 0 and row.upstream.len != 0) {
        return std.fmt.allocPrint(gpa, "route:{s}|upstream:{s}|project:{s}", .{
            row.host,
            row.upstream,
            row.project,
        });
    }
    if (row.host.len != 0) return std.fmt.allocPrint(gpa, "host:{s}", .{row.host});
    if (row.project.len != 0) return std.fmt.allocPrint(gpa, "project:{s}", .{row.project});
    if (row.service.len != 0) return std.fmt.allocPrint(gpa, "service:{s}", .{row.service});
    if (row.container.len != 0) return std.fmt.allocPrint(gpa, "container:{s}", .{row.container});
    return std.fmt.allocPrint(gpa, "upstream:{s}", .{row.upstream});
}

fn topologyFingerprint(row: db_store.TopologyRow) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    inline for (.{
        rowStatus(row).label(),
        row.host,
        row.dns_name,
        row.dns_type,
        row.dns_content,
        row.dns_proxied,
        row.project,
        row.source,
        row.path,
        row.caddy_source,
        row.upstream,
        row.socket_state,
        row.socket_process,
        row.service,
        row.service_state,
        row.container,
        row.container_status,
    }) |field| {
        hasher.update(field);
        hasher.update(&.{0});
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn readTopologyState(ctx: Context, key: []const u8) !?PreviousState {
    const stmt = try ctx.db.prepare("SELECT resource_key, status, fingerprint FROM topology_state WHERE resource_key = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try topologyBindText(stmt, 1, key);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
    return .{
        .key = try ctx.gpa.dupe(u8, topologyColumnText(stmt, 0) orelse ""),
        .status = try ctx.gpa.dupe(u8, topologyColumnText(stmt, 1) orelse ""),
        .fingerprint = try ctx.gpa.dupe(u8, topologyColumnText(stmt, 2) orelse ""),
    };
}

fn upsertTopologyState(ctx: Context, key: []const u8, status: []const u8, fingerprint: []const u8) !void {
    const stmt = try ctx.db.prepare(
        \\INSERT INTO topology_state(resource_key, status, fingerprint)
        \\VALUES (?, ?, ?)
        \\ON CONFLICT(resource_key) DO UPDATE SET
        \\ status = excluded.status, fingerprint = excluded.fingerprint, observed_at = CURRENT_TIMESTAMP
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try topologyBindText(stmt, 1, key);
    try topologyBindText(stmt, 2, status);
    try topologyBindText(stmt, 3, fingerprint);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
}

fn insertTopologyChange(
    ctx: Context,
    key: []const u8,
    change_type: []const u8,
    previous_status: ?[]const u8,
    current_status: ?[]const u8,
    previous_fingerprint: ?[]const u8,
    current_fingerprint: ?[]const u8,
) !void {
    const stmt = try ctx.db.prepare(
        \\INSERT INTO topology_changes(
        \\ resource_key, change_type, previous_status, current_status, previous_fingerprint, current_fingerprint
        \\) VALUES (?, ?, ?, ?, ?, ?)
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try topologyBindText(stmt, 1, key);
    try topologyBindText(stmt, 2, change_type);
    try topologyBindTextOpt(stmt, 3, previous_status);
    try topologyBindTextOpt(stmt, 4, current_status);
    try topologyBindTextOpt(stmt, 5, previous_fingerprint);
    try topologyBindTextOpt(stmt, 6, current_fingerprint);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
}

fn containsString(items: []const []u8, value: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, value)) return true;
    return false;
}

fn topologyBindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return error.SqliteBind;
}

fn topologyBindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |text| return topologyBindText(stmt, idx, text);
    if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return error.SqliteBind;
}

fn topologyColumnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
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

pub fn summarizeRows(rows: []const db_store.TopologyRow) Summary {
    var out = Summary{ .total = rows.len };
    for (rows) |row| {
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

pub fn writeSummaryJson(summary: Summary, writer: anytype) !void {
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

pub fn writeRowJson(row: db_store.TopologyRow, writer: anytype) !void {
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

pub const RowStatus = enum {
    healthy,
    degraded,
    dns_only,
    local_only,
    project_only,

    pub fn label(self: RowStatus) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .degraded => "degraded",
            .dns_only => "dns_only",
            .local_only => "local_only",
            .project_only => "project_only",
        };
    }
};

pub const DnsMatch = enum {
    none,
    direct,
    wildcard,

    pub fn label(self: DnsMatch) []const u8 {
        return switch (self) {
            .none => "none",
            .direct => "direct",
            .wildcard => "wildcard",
        };
    }
};

pub fn hasDns(row: db_store.TopologyRow) bool {
    return row.dns_name.len != 0;
}

pub fn hasCaddy(row: db_store.TopologyRow) bool {
    return row.caddy_source.len != 0 or row.upstream.len != 0;
}

pub fn hasProject(row: db_store.TopologyRow) bool {
    return row.project.len != 0;
}

pub fn hasSocket(row: db_store.TopologyRow) bool {
    return row.socket_state.len != 0;
}

pub fn hasService(row: db_store.TopologyRow) bool {
    return row.service.len != 0;
}

pub fn hasContainer(row: db_store.TopologyRow) bool {
    return row.container.len != 0;
}

pub fn dnsMatch(row: db_store.TopologyRow) DnsMatch {
    if (row.dns_name.len == 0) return .none;
    if (std.mem.startsWith(u8, row.dns_name, "*.")) return .wildcard;
    return .direct;
}

pub fn rowExposure(row: db_store.TopologyRow) []const u8 {
    if (hasDns(row)) return "public";
    if (hasCaddy(row)) return "local";
    if (hasProject(row) or hasService(row) or hasContainer(row)) return "internal";
    return "unknown";
}

pub fn rowStatus(row: db_store.TopologyRow) RowStatus {
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
    return containsIgnoreCase(value, "running") or containsIgnoreCase(value, "active") or containsIgnoreCase(value, "up") or containsIgnoreCase(value, "observed");
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

pub fn rowHasIssues(row: db_store.TopologyRow) bool {
    return issueCount(row) != 0;
}

pub fn issueCount(row: db_store.TopologyRow) usize {
    var count: usize = 0;
    if (isDnsOnly(row)) count += 1;
    if (isCaddyWithoutDns(row)) count += 1;
    if (isUpstreamWithoutSocket(row)) count += 1;
    if (isProjectWithoutRuntime(row)) count += 1;
    if (isServiceNotRunning(row)) count += 1;
    if (isContainerNotRunning(row)) count += 1;
    return count;
}

fn hydrateDerivedRuntime(ctx: Context, rows: *db_store.TopologyRows) !void {
    var services = try ctx.db.serviceList(ctx.gpa);
    defer services.deinit(ctx.gpa);
    var containers = try ctx.db.containerList(ctx.gpa);
    defer containers.deinit(ctx.gpa);

    for (rows.items) |*row| {
        const socket_service = serviceNameFromSocketProcess(row.socket_process);
        if (row.service.len == 0) {
            if (socket_service) |inferred| {
                try replaceOwned(ctx.gpa, &row.service, inferred);
            } else if (try projectServiceState(ctx.gpa, services.items, row.project)) |match| {
                defer match.deinit(ctx.gpa);
                try replaceOwned(ctx.gpa, &row.service, match.name);
                try replaceOwned(ctx.gpa, &row.service_state, match.state);
            }
        }
        if (row.service_state.len == 0 and row.service.len != 0) {
            if (serviceStateFor(services.items, row.service)) |state| {
                try replaceOwned(ctx.gpa, &row.service_state, state);
            } else if (socket_service != null and std.mem.eql(u8, row.service, socket_service.?)) {
                try replaceOwned(ctx.gpa, &row.service_state, "observed");
            }
        }
        if (row.container.len == 0) {
            if (projectContainer(rows.items, containers.items, row.project)) |match| {
                try replaceOwned(ctx.gpa, &row.container, match.name);
                try replaceOwned(ctx.gpa, &row.container_status, match.value);
            }
        }
    }
}

const ServiceMatch = struct {
    name: []u8,
    state: []u8,

    fn deinit(self: ServiceMatch, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.state);
    }
};

fn projectServiceState(allocator: Allocator, rows: []const db_store.NameValueRow, project: []const u8) !?ServiceMatch {
    if (project.len == 0) return null;
    const candidate = try std.fmt.allocPrint(allocator, "{s}.service", .{project});
    errdefer allocator.free(candidate);
    if (serviceStateFor(rows, candidate)) |state| {
        return .{
            .name = candidate,
            .state = try allocator.dupe(u8, state),
        };
    }
    allocator.free(candidate);
    return null;
}

fn projectContainer(topology_rows: []const db_store.TopologyRow, containers: []const db_store.NameValueRow, project: []const u8) ?db_store.NameValueRow {
    if (project.len == 0) return null;
    var fallback: ?db_store.NameValueRow = null;
    for (containers) |container| {
        if (!containerOwnedByProject(topology_rows, container.name, project)) continue;
        if (stateLooksRunning(container.value)) return container;
        if (fallback == null) fallback = container;
    }
    return fallback;
}

fn containerOwnedByProject(rows: []const db_store.TopologyRow, container: []const u8, project: []const u8) bool {
    if (!containerNameMatchesProject(container, project)) return false;
    for (rows) |row| {
        if (std.mem.eql(u8, row.source, "docker")) continue;
        if (row.project.len <= project.len) continue;
        if (containerNameMatchesProject(container, row.project)) return false;
    }
    return true;
}

fn containerNameMatchesProject(container: []const u8, project: []const u8) bool {
    if (project.len == 0) return false;
    if (std.mem.eql(u8, container, project)) return true;
    if (container.len <= project.len) return false;
    if (!std.mem.startsWith(u8, container, project)) return false;
    const separator = container[project.len];
    return separator == '-' or separator == '_';
}

fn serviceStateFor(rows: []const db_store.NameValueRow, service: []const u8) ?[]const u8 {
    for (rows) |row| {
        if (std.mem.eql(u8, row.name, service)) return row.value;
    }
    return null;
}

fn replaceOwned(allocator: Allocator, field: *[]u8, value: []const u8) !void {
    const copy = try allocator.dupe(u8, value);
    allocator.free(field.*);
    field.* = copy;
}

fn serviceNameFromSocketProcess(value: []const u8) ?[]const u8 {
    const suffix = ".service";
    const suffix_start = std.mem.lastIndexOf(u8, value, suffix) orelse return null;
    var start = suffix_start;
    while (start > 0) {
        const previous = value[start - 1];
        if (previous == '/' or previous == ' ' or previous == '\t' or previous == '\r' or previous == '\n' or previous == ':' or previous == '(' or previous == ')') break;
        start -= 1;
    }
    const end = suffix_start + suffix.len;
    if (start >= end) return null;
    const service = value[start..end];
    if (!std.mem.endsWith(u8, service, suffix)) return null;
    return service;
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
    try db.upsertDnsRecord("record-0", "zone-1", "api.plosca.ru", "AAAA", "2001:db8::1", 1, false, "{}");
    try db.upsertDnsRecord("record-1", "zone-1", "api.plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertDnsRecord("record-2", "zone-1", "dns-only.plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertDnsRecord("record-3", "zone-1", "api.plosca.ru", "MX", "mail.example.com", 1, false, "{}");
    try db.upsertDnsRecord("record-4", "zone-1", "dns-only.plosca.ru", "TXT", "\"v=spf1 include:example.com ~all\"", 1, false, "{}");
    try db.upsertCaddySite("api.plosca.ru", "/etc/caddy/conf.d/sites.caddy", "api.plosca.ru { reverse_proxy 127.0.0.1:9000 }");
    try db.insertCaddyUpstream("api.plosca.ru", "", "127.0.0.1:9000");
    try db.insertCaddyUpstream("api.plosca.ru", "", "127.0.0.1:9000");
    try db.insertCaddyUpstream("local-only.plosca.ru", "", "127.0.0.1:9100");
    try db.insertCaddyUpstream("local-only.plosca.ru", "", "127.0.0.1:9100");
    try db.upsertProject("api", "compose", "/home/kid/Projects/api/compose.yaml", "api.plosca.ru", "127.0.0.1:9000", null, "api-1", null);
    try db.upsertProject("compose-only", "compose", "/home/kid/Projects/compose-only/compose.yaml", null, null, null, null, null);
    try db.upsertProject("worker", "systemd", "/home/kid/Projects/worker", null, null, "worker.service", "worker-1", null);
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9000", "users:((\"api\",pid=1,fd=3)) cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/api.service <->", "raw");
    try db.upsertService("api.service", "user", "active", "running", "API", "raw");
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
    try std.testing.expect(std.mem.indexOf(u8, text, "dns_type=AAAA") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dns_type=MX") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dns_type=TXT") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "socket=LISTEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "service=api.service\tservice_state=active") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"service\":\"api.service\",\"service_state\":\"active\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"issues\":[\"caddy_without_dns\",\"upstream_without_socket\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"issues\":[\"service_not_running\",\"container_not_running\"]") != null);
}

test "infers systemd service names from socket cgroup process text" {
    try std.testing.expectEqualStrings("plosca-webapp.service", serviceNameFromSocketProcess("users:((\"webapp\",pid=342665,fd=4)) uid:1001 cgroup:/user.slice/user-1001.slice/user@1001.service/app.slice/plosca-webapp.service <->").?);
    try std.testing.expectEqualStrings("docker.service", serviceNameFromSocketProcess("ino:19571 sk:3 cgroup:/system.slice/docker.service <->").?);
    try std.testing.expect(serviceNameFromSocketProcess("users:((\"caddy\",pid=1,fd=3))") == null);
}

test "topology delta capture records added changed and removed projections" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-topology-deltas.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    const ctx = Context{ .gpa = allocator, .db = &db };

    try db.upsertProject("demo", "systemd", "/srv/demo", null, null, null, null, null);
    const added = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 1), added.added);

    const unchanged = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 1), unchanged.unchanged);
    try std.testing.expectEqual(@as(usize, 0), unchanged.totalChanges());

    try db.upsertService("demo.service", "system", "active", "running", "Demo", "raw");
    const changed = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 1), changed.changed);

    try db.exec("DELETE FROM projects WHERE name = 'demo'");
    const removed = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 1), removed.removed);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeChangesJson(ctx, 10, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"change_type\":\"added\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"change_type\":\"changed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"change_type\":\"removed\"") != null);
}

test "topology delta capture distinguishes multiple upstreams for one host" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-topology-multiple-upstreams.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    const ctx = Context{ .gpa = allocator, .db = &db };

    try db.upsertCaddySite("example.com", "/etc/caddy/Caddyfile", null);
    try db.insertCaddyUpstream("example.com", "", "127.0.0.1:9000");
    try db.insertCaddyUpstream("example.com", "", "127.0.0.1:9001");

    const added = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 2), added.added);
    try std.testing.expectEqual(@as(usize, 0), added.changed);

    const unchanged = try captureDeltas(ctx, .{ .limit = 20 });
    try std.testing.expectEqual(@as(usize, 2), unchanged.unchanged);
    try std.testing.expectEqual(@as(usize, 0), unchanged.totalChanges());
}

test "topology hydrates project runtime from services and compose containers" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-topology-runtime.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertProject("plausible", "compose", "/home/kid/Projects/plausible/compose.yml", null, null, null, null, null);
    try db.upsertProject("plausible-ce", "compose", "/home/kid/Projects/plausible-ce/compose.yml", null, null, null, null, null);
    try db.upsertProject("plausible-ce-plausible-1", "docker", null, null, null, null, "plausible-ce-plausible-1", null);
    try db.upsertProject("zeroclaw", "compose", "/home/kid/Projects/zeroclaw/docker-compose.yml", null, null, null, null, null);
    try db.upsertContainer("plausible-ce-plausible-1", "plausible:latest", "Up 2 hours", "127.0.0.1:4248->8000/tcp", "raw");
    try db.upsertService("zeroclaw.service", "user", "active", "running", "Zeroclaw", "raw");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var topology = try Topology.load(ctx, .{ .limit = 20 });
    defer topology.deinit(allocator);

    const plausible = findProject(topology.rows.items, "plausible").?;
    try std.testing.expectEqual(RowStatus.project_only, rowStatus(plausible));
    try std.testing.expectEqualStrings("", plausible.container);

    const plausible_ce = findProject(topology.rows.items, "plausible-ce").?;
    try std.testing.expectEqual(RowStatus.healthy, rowStatus(plausible_ce));
    try std.testing.expectEqualStrings("plausible-ce-plausible-1", plausible_ce.container);
    try std.testing.expectEqualStrings("Up 2 hours", plausible_ce.container_status);

    const zeroclaw = findProject(topology.rows.items, "zeroclaw").?;
    try std.testing.expectEqual(RowStatus.healthy, rowStatus(zeroclaw));
    try std.testing.expectEqualStrings("zeroclaw.service", zeroclaw.service);
    try std.testing.expectEqualStrings("active", zeroclaw.service_state);
}

fn findProject(rows: []const db_store.TopologyRow, project: []const u8) ?db_store.TopologyRow {
    for (rows) |row| {
        if (std.mem.eql(u8, row.project, project)) return row;
    }
    return null;
}
