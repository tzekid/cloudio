//! Dashboard read model: every observed host reconciled across DNS, Caddy,
//! listening sockets, services, containers, and projects, plus the freshness
//! of each source that feeds it.

const std = @import("std");
const db_store = @import("../db/store.zig");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Row = db_store.TopologyRow;

const row_limit = 200;

pub const Options = struct {
    domain: ?[]const u8 = null,
    issues_only: bool = false,
};

pub const Status = enum { healthy, degraded, dns_only, local_only, project_only };

pub const Issue = enum {
    dns_without_local_target,
    caddy_without_dns,
    upstream_without_socket,
    project_without_runtime,
    service_not_running,
    container_not_running,

    /// A discovered project without a runtime is inventory awaiting
    /// enrollment, not a failed workload.
    pub fn isIncident(self: Issue) bool {
        return self != .project_without_runtime;
    }
};

pub const Freshness = enum { current, stale, unavailable };

pub const Source = struct {
    name: []const u8,
    label: []const u8,
    local: bool,
    freshness: Freshness = .unavailable,
    observation: ?db_store.Observation = null,
};

pub const Summary = struct {
    hosts: usize = 0,
    healthy: usize = 0,
    degraded: usize = 0,
    dns_only: usize = 0,
    local_only: usize = 0,
    project_only: usize = 0,
    incidents: usize = 0,
};

pub const Dashboard = struct {
    all: db_store.TopologyRows,
    rows: []const Row,
    summary: Summary,
    sources: [5]Source,

    pub fn load(gpa: Allocator, db: *Db, options: Options, fresh_after_seconds: i64) !Dashboard {
        var all = try db.topologyRows(gpa, row_limit);
        errdefer all.deinit(gpa);
        try hydrateDerivedRuntime(gpa, db, &all);

        var rows: std.ArrayList(Row) = .empty;
        errdefer rows.deinit(gpa);
        var summary: Summary = .{};
        for (all.items) |row| {
            const row_issues = issues(row);
            var incidents: usize = 0;
            var it = row_issues.iterator();
            while (it.next()) |issue| incidents += @intFromBool(issue.isIncident());
            if (options.issues_only and incidents == 0) continue;
            if (options.domain) |domain| if (!domainMatches(row.host, domain) and !domainMatches(row.dns_name, domain)) continue;
            try rows.append(gpa, row);
            summary.hosts += 1;
            summary.incidents += incidents;
            switch (status(row)) {
                .healthy => summary.healthy += 1,
                .degraded => summary.degraded += 1,
                .dns_only => summary.dns_only += 1,
                .local_only => summary.local_only += 1,
                .project_only => summary.project_only += 1,
            }
        }

        var sources = [_]Source{
            .{ .name = "cloudflare", .label = "Cloudflare", .local = false },
            .{ .name = "hostinger", .label = "Hostinger", .local = false },
            .{ .name = "caddy", .label = "Caddy", .local = true },
            .{ .name = "system", .label = "System", .local = true },
            .{ .name = "projects", .label = "Projects", .local = true },
        };
        errdefer for (sources) |source| if (source.observation) |observation| observation.deinit(gpa);
        for (&sources) |*source| {
            source.observation = try db.latestObservation(gpa, "refresh", source.name);
            source.freshness = freshness(source.observation, fresh_after_seconds);
        }
        return .{ .all = all, .rows = try rows.toOwnedSlice(gpa), .summary = summary, .sources = sources };
    }

    pub fn deinit(self: *Dashboard, gpa: Allocator) void {
        for (self.sources) |source| if (source.observation) |observation| observation.deinit(gpa);
        gpa.free(self.rows);
        self.all.deinit(gpa);
    }
};

pub fn freshness(observation: ?db_store.Observation, fresh_after_seconds: i64) Freshness {
    const value = observation orelse return .unavailable;
    if (!value.hasSuccessfulObservation()) return .unavailable;
    if (!std.mem.eql(u8, value.attempt_status, "ok")) return .stale;
    return if (value.age_seconds >= 0 and value.age_seconds <= @max(fresh_after_seconds, 1)) .current else .stale;
}

pub fn status(row: Row) Status {
    const found = issues(row);
    if (found.contains(.upstream_without_socket) or found.contains(.service_not_running) or found.contains(.container_not_running)) return .degraded;
    if (found.contains(.dns_without_local_target)) return .dns_only;
    if (found.contains(.caddy_without_dns)) return .local_only;
    if (found.contains(.project_without_runtime)) return .project_only;
    return .healthy;
}

pub fn issues(row: Row) std.EnumSet(Issue) {
    const has_dns = row.dns_name.len != 0;
    const has_caddy = row.caddy_source.len != 0 or row.upstream.len != 0;
    const has_project = row.project.len != 0;
    return .init(.{
        .dns_without_local_target = has_dns and !has_caddy and !has_project,
        .caddy_without_dns = row.host.len != 0 and has_caddy and !has_dns,
        .upstream_without_socket = row.upstream.len != 0 and row.socket_state.len == 0,
        .project_without_runtime = has_project and row.host.len == 0 and row.upstream.len == 0 and row.service.len == 0 and row.container.len == 0,
        .service_not_running = row.service.len != 0 and !looksRunning(row.service_state),
        .container_not_running = row.container.len != 0 and !looksRunning(row.container_status),
    });
}

/// How the host is reached: a public DNS name, a local route, or neither.
pub fn exposure(row: Row) []const u8 {
    if (row.dns_name.len != 0) return "public";
    if (row.caddy_source.len != 0 or row.upstream.len != 0) return "local";
    if (row.project.len != 0 or row.service.len != 0 or row.container.len != 0) return "internal";
    return "unknown";
}

pub fn dnsMatch(row: Row) []const u8 {
    if (row.dns_name.len == 0) return "none";
    return if (std.mem.startsWith(u8, row.dns_name, "*.")) "wildcard" else "direct";
}

fn domainMatches(value: []const u8, domain: []const u8) bool {
    if (domain.len == 0 or std.ascii.eqlIgnoreCase(value, domain)) return true;
    return value.len > domain.len and std.ascii.endsWithIgnoreCase(value, domain) and value[value.len - domain.len - 1] == '.';
}

fn looksRunning(value: []const u8) bool {
    for ([_][]const u8{ "running", "active", "up", "observed" }) |word| {
        if (std.ascii.findIgnoreCase(value, word) != null) return true;
    }
    return false;
}

/// Fills service and container links the observations imply but do not
/// record directly: a socket's systemd cgroup, `<project>.service`, and
/// containers named after their project.
fn hydrateDerivedRuntime(gpa: Allocator, db: *Db, rows: *db_store.TopologyRows) !void {
    var services = try db.serviceList(gpa);
    defer services.deinit(gpa);
    var containers = try db.containerList(gpa);
    defer containers.deinit(gpa);

    for (rows.items) |*row| {
        const socket_service = serviceNameFromSocketProcess(row.socket_process);
        if (row.service.len == 0) {
            if (socket_service) |inferred| {
                try replaceOwned(gpa, &row.service, inferred);
            } else if (row.project.len != 0) {
                const candidate = try std.fmt.allocPrint(gpa, "{s}.service", .{row.project});
                defer gpa.free(candidate);
                if (valueFor(services.items, candidate)) |state| {
                    try replaceOwned(gpa, &row.service, candidate);
                    try replaceOwned(gpa, &row.service_state, state);
                }
            }
        }
        if (row.service_state.len == 0 and row.service.len != 0) {
            if (valueFor(services.items, row.service)) |state| {
                try replaceOwned(gpa, &row.service_state, state);
            } else if (socket_service != null and std.mem.eql(u8, row.service, socket_service.?)) {
                try replaceOwned(gpa, &row.service_state, "observed");
            }
        }
        if (row.container.len == 0) {
            if (projectContainer(rows.items, containers.items, row.project)) |match| {
                try replaceOwned(gpa, &row.container, match.name);
                try replaceOwned(gpa, &row.container_status, match.value);
            }
        }
    }
}

fn projectContainer(rows: []const Row, containers: []const db_store.NameValueRow, project: []const u8) ?db_store.NameValueRow {
    if (project.len == 0) return null;
    var fallback: ?db_store.NameValueRow = null;
    for (containers) |container| {
        if (!containerOwnedByProject(rows, container.name, project)) continue;
        if (looksRunning(container.value)) return container;
        if (fallback == null) fallback = container;
    }
    return fallback;
}

/// A container belongs to the most specific project whose name prefixes it.
fn containerOwnedByProject(rows: []const Row, container: []const u8, project: []const u8) bool {
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
    if (container.len <= project.len or !std.mem.startsWith(u8, container, project)) return false;
    return container[project.len] == '-' or container[project.len] == '_';
}

fn valueFor(rows: []const db_store.NameValueRow, name: []const u8) ?[]const u8 {
    for (rows) |row| if (std.mem.eql(u8, row.name, name)) return row.value;
    return null;
}

fn replaceOwned(gpa: Allocator, field: *[]u8, value: []const u8) !void {
    const copy = try gpa.dupe(u8, value);
    gpa.free(field.*);
    field.* = copy;
}

fn serviceNameFromSocketProcess(value: []const u8) ?[]const u8 {
    const suffix = ".service";
    const suffix_start = std.mem.lastIndexOf(u8, value, suffix) orelse return null;
    var start = suffix_start;
    while (start > 0) : (start -= 1) {
        switch (value[start - 1]) {
            '/', ' ', '\t', '\r', '\n', ':', '(', ')' => break,
            else => {},
        }
    }
    if (start == suffix_start) return null;
    return value[start .. suffix_start + suffix.len];
}

test "infers systemd service names from socket cgroup process text" {
    try std.testing.expectEqualStrings("plosca-webapp.service", serviceNameFromSocketProcess("users:((\"webapp\",pid=342665,fd=4)) uid:1001 cgroup:/user.slice/user-1001.slice/user@1001.service/app.slice/plosca-webapp.service <->").?);
    try std.testing.expectEqualStrings("docker.service", serviceNameFromSocketProcess("ino:19571 sk:3 cgroup:/system.slice/docker.service <->").?);
    try std.testing.expect(serviceNameFromSocketProcess("users:((\"caddy\",pid=1,fd=3))") == null);
}

test "dashboard reconciles hosts filters incidents and reports source freshness" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-dashboard.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    _ = try db.insertSnapshot("refresh", "cloudflare", null, "ok", "collection completed", null, null);
    try db.upsertCloudflareZone("zone-1", "plosca.ru", "acct-1", "active", false, "full", "[]", "{}");
    try db.upsertDnsRecord("record-1", "zone-1", "plosca.ru", "A", "192.0.2.1", 1, false, "{}");
    try db.upsertDnsRecord("record-2", "zone-1", "orphan.plosca.ru", "A", "192.0.2.1", 1, false, "{}");
    try db.upsertCaddySite("plosca.ru", "/etc/caddy/Caddyfile", "plosca.ru { reverse_proxy 127.0.0.1:9327 }");
    try db.insertCaddyUpstream("plosca.ru", "", "127.0.0.1:9327");
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9327", "plosca.service", "raw");

    var all = try Dashboard.load(allocator, &db, .{}, 120);
    defer all.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), all.summary.dns_only);
    try std.testing.expectEqual(Freshness.current, all.sources[0].freshness);
    try std.testing.expectEqual(Freshness.unavailable, all.sources[1].freshness);

    var incidents = try Dashboard.load(allocator, &db, .{ .issues_only = true }, 120);
    defer incidents.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), incidents.rows.len);
    try std.testing.expectEqualStrings("orphan.plosca.ru", incidents.rows[0].dns_name);
    try std.testing.expect(issues(incidents.rows[0]).contains(.dns_without_local_target));
}
