const std = @import("std");
const core_fs = @import("core_fs");
const sqlite = @import("sqlite");
const db_schema = @import("db_schema");
const models = @import("models.zig");
const captures_repository = @import("repositories/captures.zig");
const audit_repository = @import("repositories/audit.zig");
const maintenance_repository = @import("repositories/maintenance.zig");
const cloudflare_repository = @import("repositories/cloudflare.zig");
const hostinger_repository = @import("repositories/hostinger.zig");
const inventory_repository = @import("repositories/inventory.zig");
const system_repository = @import("repositories/system.zig");
const auth_repository = @import("repositories/auth.zig");
const nob_repository = @import("repositories/nob.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
pub const DbError = models.DbError;
const SecretScanSurface = models.SecretScanSurface;
const SnapshotSummaries = models.SnapshotSummaries;
const NameValueRows = models.NameValueRows;
const ProjectCorrelations = models.ProjectCorrelations;
const TopologyRows = models.TopologyRows;
const ContainerRows = models.ContainerRows;
const CloudflareAccountRows = models.CloudflareAccountRows;
const CloudflareZoneRows = models.CloudflareZoneRows;
const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
const CloudflareResourceHintRows = models.CloudflareResourceHintRows;
const CloudflareInventoryHintRows = models.CloudflareInventoryHintRows;
const CloudflareKindCounts = models.CloudflareKindCounts;
const HostingerVpsRows = models.HostingerVpsRows;
const HostingerResourceHintRows = models.HostingerResourceHintRows;
const HostingerInventoryHintRows = models.HostingerInventoryHintRows;
const HostingerKindCounts = models.HostingerKindCounts;
const HostingerMetricSummaries = models.HostingerMetricSummaries;
const HostingerVpsFamilySummaries = models.HostingerVpsFamilySummaries;
const InventoryFilter = models.InventoryFilter;
const InventoryItems = models.InventoryItems;
const InventoryFacets = models.InventoryFacets;
const MetricRows = models.MetricRows;
const AuditEvents = models.AuditEvents;
const ProviderEvidenceFilter = models.ProviderEvidenceFilter;
const ProviderEvidenceEvents = models.ProviderEvidenceEvents;
const ProviderEvidenceSummaryRows = models.ProviderEvidenceSummaryRows;
const RouteCaptureEvidenceFilter = models.RouteCaptureEvidenceFilter;
const RouteCaptureEvidenceRows = models.RouteCaptureEvidenceRows;
const RouteSourceEvidenceRows = models.RouteSourceEvidenceRows;
const ProjectDetails = models.ProjectDetails;

pub const Db = struct {
    handle: *sqlite.sqlite3,

    pub fn captures(self: *Db) captures_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn audit(self: *Db) audit_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn maintenance(self: *Db) maintenance_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn cloudflare(self: *Db) cloudflare_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn hostinger(self: *Db) hostinger_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn inventory(self: *Db) inventory_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn system(self: *Db) system_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn auth(self: *Db) auth_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn nob(self: *Db) nob_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn open(io: Io, path: []const u8) !Db {
        try core_fs.ensureParentDir(io, path);
        if (path.len >= std.fs.max_path_bytes) return error.NameTooLong;
        var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var handle: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open_v2(@ptrCast(&path_z), &handle, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqliteOpen;
        _ = sqlite.sqlite3_busy_timeout(handle.?, 5000);
        var foreign_key_error: [*c]u8 = null;
        if (sqlite.sqlite3_exec(handle.?, "PRAGMA foreign_keys=ON", null, null, &foreign_key_error) != sqlite.SQLITE_OK) {
            if (foreign_key_error != null) sqlite.sqlite3_free(foreign_key_error);
            _ = sqlite.sqlite3_close(handle.?);
            return DbError.SqliteExec;
        }
        return .{ .handle = handle.? };
    }

    pub fn close(self: *Db) void {
        _ = sqlite.sqlite3_close(self.handle);
    }

    pub fn initSchema(self: *Db) !void {
        try db_schema.apply(self.handle);
    }

    pub fn schemaVersion(self: *Db) !i64 {
        return try db_schema.latestAppliedVersion(self.handle);
    }

    pub fn exec(self: *Db, sql: []const u8) !void {
        var err: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err);
        if (rc != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return DbError.SqliteExec;
        }
    }

    pub fn prepare(self: *Db, sql: []const u8) !*sqlite.sqlite3_stmt {
        var stmt: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(self.handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqlitePrepare;
        return stmt.?;
    }

    pub fn insertSnapshot(self: *Db, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
        return self.captures().insertSnapshot(source, kind, target, status, summary, raw_json, raw_text);
    }
    pub fn insertProviderRaw(self: *Db, provider: []const u8, endpoint: []const u8, status: i64, body: []const u8) !void {
        return self.captures().insertProviderRaw(provider, endpoint, status, body);
    }
    pub fn insertAudit(self: *Db, action: []const u8, status: []const u8, detail: []const u8) !void {
        return self.audit().insertAudit(action, status, detail);
    }
    pub fn clear(self: *Db, table: []const u8) !void {
        return self.maintenance().clear(table);
    }
    pub fn countTable(self: *Db, table: []const u8) !i64 {
        return self.maintenance().countTable(table);
    }
    pub fn countSecretNeedle(self: *Db, surface: SecretScanSurface, needle: []const u8) !i64 {
        return self.maintenance().countSecretNeedle(surface, needle);
    }
    pub fn latestSnapshotId(self: *Db) !i64 {
        return self.captures().latestSnapshotId();
    }
    pub fn upsertCloudflareAccount(self: *Db, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
        return self.cloudflare().upsertCloudflareAccount(id, name, typ, status, raw);
    }
    pub fn upsertCloudflareZone(self: *Db, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
        return self.cloudflare().upsertCloudflareZone(id, name, account_id, status, paused, typ, name_servers, raw);
    }
    pub fn upsertDnsRecord(self: *Db, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
        return self.cloudflare().upsertDnsRecord(id, zone_id, name, typ, content, ttl, proxied, raw);
    }
    pub fn upsertCloudflareResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, name: ?[]const u8, status: ?[]const u8, resource_type: ?[]const u8, raw: []const u8) !void {
        return self.cloudflare().upsertCloudflareResource(key, kind, resource_id, scope, scope_id, name, status, resource_type, raw);
    }
    pub fn upsertCloudflareInventoryItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        scope: ?[]const u8,
        scope_id: ?[]const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        domain: ?[]const u8,
        account_id: ?[]const u8,
        zone_id: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        return self.cloudflare().upsertCloudflareInventoryItem(key, kind, resource_id, scope, scope_id, display_name, status, category, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw);
    }
    pub fn upsertCloudflareSecurityItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        scope: ?[]const u8,
        scope_id: ?[]const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        severity: ?[]const u8,
        action: ?[]const u8,
        domain: ?[]const u8,
        account_id: ?[]const u8,
        zone_id: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        return self.cloudflare().upsertCloudflareSecurityItem(key, kind, resource_id, scope, scope_id, display_name, status, category, severity, action, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw);
    }
    pub fn upsertHostingerVps(self: *Db, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
        return self.hostinger().upsertHostingerVps(id, name, status, ipv4, plan, raw);
    }
    pub fn insertHostingerMetric(self: *Db, vm_id: []const u8, metric: []const u8, value: ?[]const u8, raw: []const u8) !void {
        return self.hostinger().insertHostingerMetric(vm_id, metric, value, raw);
    }
    pub fn upsertHostingerResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, target: ?[]const u8, name: ?[]const u8, status: ?[]const u8, domain: ?[]const u8, raw: []const u8) !void {
        return self.hostinger().upsertHostingerResource(key, kind, resource_id, target, name, status, domain, raw);
    }
    pub fn upsertHostingerInventoryItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        domain: ?[]const u8,
        username: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        return self.hostinger().upsertHostingerInventoryItem(key, kind, resource_id, display_name, status, category, domain, username, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw);
    }
    pub fn upsertCaddySite(self: *Db, host: []const u8, source_path: []const u8, raw_block: ?[]const u8) !void {
        return self.system().upsertCaddySite(host, source_path, raw_block);
    }
    pub fn insertCaddyUpstream(self: *Db, host: []const u8, route: []const u8, upstream: []const u8) !void {
        return self.system().insertCaddyUpstream(host, route, upstream);
    }
    pub fn upsertProject(self: *Db, name: []const u8, source: []const u8, path: ?[]const u8, host: ?[]const u8, upstream: ?[]const u8, service: ?[]const u8, container: ?[]const u8, raw: ?[]const u8) !void {
        return self.system().upsertProject(name, source, path, host, upstream, service, container, raw);
    }
    pub fn insertSystemMetric(self: *Db, metric: []const u8, value: []const u8, unit: ?[]const u8) !void {
        return self.system().insertSystemMetric(metric, value, unit);
    }
    pub fn upsertService(self: *Db, name: []const u8, scope: []const u8, state: ?[]const u8, sub_state: ?[]const u8, description: ?[]const u8, raw: []const u8) !void {
        return self.system().upsertService(name, scope, state, sub_state, description, raw);
    }
    pub fn insertSocket(self: *Db, proto: ?[]const u8, state: ?[]const u8, local_address: ?[]const u8, process: ?[]const u8, raw: []const u8) !void {
        return self.system().insertSocket(proto, state, local_address, process, raw);
    }
    pub fn upsertContainer(self: *Db, name: []const u8, image: ?[]const u8, status: ?[]const u8, ports: ?[]const u8, raw: []const u8) !void {
        return self.system().upsertContainer(name, image, status, ports, raw);
    }
    pub fn writeOverviewCounts(self: *Db, writer: anytype) !void {
        return self.maintenance().writeOverviewCounts(writer);
    }
    pub fn recentSnapshots(self: *Db, gpa: Allocator, limit: i64) !SnapshotSummaries {
        return self.captures().recentSnapshots(gpa, limit);
    }
    pub fn snapshotsForSource(self: *Db, gpa: Allocator, source: []const u8, limit: i64) !SnapshotSummaries {
        return self.captures().snapshotsForSource(gpa, source, limit);
    }
    pub fn projectList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().projectList(gpa);
    }
    pub fn projectCorrelations(self: *Db, gpa: Allocator, limit: i64) !ProjectCorrelations {
        return self.system().projectCorrelations(gpa, limit);
    }
    pub fn topologyRows(self: *Db, gpa: Allocator, limit: i64) !TopologyRows {
        return self.system().topologyRows(gpa, limit);
    }
    pub fn serviceList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().serviceList(gpa);
    }
    pub fn socketList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().socketList(gpa);
    }
    pub fn containerRows(self: *Db, gpa: Allocator, limit: i64) !ContainerRows {
        return self.system().containerRows(gpa, limit);
    }
    pub fn containerList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().containerList(gpa);
    }
    pub fn cloudflareResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.cloudflare().cloudflareResourceList(gpa);
    }
    pub fn cloudflareInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.cloudflare().cloudflareInventoryItemList(gpa);
    }
    pub fn cloudflareAccountRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareAccountRows {
        return self.cloudflare().cloudflareAccountRows(gpa, limit);
    }
    pub fn cloudflareZoneRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareZoneRows {
        return self.cloudflare().cloudflareZoneRows(gpa, limit);
    }
    pub fn cloudflareDnsRecordRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
        return self.cloudflare().cloudflareDnsRecordRows(gpa, limit);
    }
    pub fn cloudflareResourceHints(self: *Db, gpa: Allocator, limit: i64) !CloudflareResourceHintRows {
        return self.cloudflare().cloudflareResourceHints(gpa, limit);
    }
    pub fn cloudflareInventoryHints(self: *Db, gpa: Allocator, limit: i64) !CloudflareInventoryHintRows {
        return self.cloudflare().cloudflareInventoryHints(gpa, limit);
    }
    pub fn cloudflareResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return self.cloudflare().cloudflareResourceKindCounts(gpa, limit);
    }
    pub fn cloudflareInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return self.cloudflare().cloudflareInventoryKindCounts(gpa, limit);
    }
    pub fn cloudflareSecurityKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return self.cloudflare().cloudflareSecurityKindCounts(gpa, limit);
    }
    pub fn hostingerResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.hostinger().hostingerResourceList(gpa);
    }
    pub fn hostingerInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.hostinger().hostingerInventoryItemList(gpa);
    }
    pub fn hostingerVpsRows(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsRows {
        return self.hostinger().hostingerVpsRows(gpa, limit);
    }
    pub fn hostingerResourceHints(self: *Db, gpa: Allocator, limit: i64) !HostingerResourceHintRows {
        return self.hostinger().hostingerResourceHints(gpa, limit);
    }
    pub fn hostingerInventoryHints(self: *Db, gpa: Allocator, limit: i64) !HostingerInventoryHintRows {
        return self.hostinger().hostingerInventoryHints(gpa, limit);
    }
    pub fn hostingerResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return self.hostinger().hostingerResourceKindCounts(gpa, limit);
    }
    pub fn hostingerInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return self.hostinger().hostingerInventoryKindCounts(gpa, limit);
    }
    pub fn hostingerMetricSummaries(self: *Db, gpa: Allocator, limit: i64) !HostingerMetricSummaries {
        return self.hostinger().hostingerMetricSummaries(gpa, limit);
    }
    pub fn hostingerVpsFamilySummaries(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsFamilySummaries {
        return self.hostinger().hostingerVpsFamilySummaries(gpa, limit);
    }
    pub fn inventoryItems(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryItems {
        return self.inventory().inventoryItems(gpa, filter);
    }
    pub fn inventoryFacets(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryFacets {
        return self.inventory().inventoryFacets(gpa, filter);
    }
    pub fn caddyUpstreams(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().caddyUpstreams(gpa);
    }
    pub fn recentMetrics(self: *Db, gpa: Allocator, limit: i64) !MetricRows {
        return self.system().recentMetrics(gpa, limit);
    }
    pub fn recentAuditEvents(self: *Db, gpa: Allocator, limit: i64) !AuditEvents {
        return self.audit().recentAuditEvents(gpa, limit);
    }
    pub fn providerEvidenceEvents(self: *Db, gpa: Allocator, filter: ProviderEvidenceFilter) !ProviderEvidenceEvents {
        return self.audit().providerEvidenceEvents(gpa, filter);
    }
    pub fn providerEvidenceSummary(self: *Db, gpa: Allocator, provider: ?[]const u8) !ProviderEvidenceSummaryRows {
        return self.audit().providerEvidenceSummary(gpa, provider);
    }
    pub fn routeCaptureEvidence(self: *Db, gpa: Allocator, filter: RouteCaptureEvidenceFilter) !RouteCaptureEvidenceRows {
        return self.audit().routeCaptureEvidence(gpa, filter);
    }
    pub fn routeSourceEvidence(self: *Db, gpa: Allocator, filter: RouteCaptureEvidenceFilter) !RouteSourceEvidenceRows {
        return self.audit().routeSourceEvidence(gpa, filter);
    }
    pub fn projectDetails(self: *Db, gpa: Allocator, name: []const u8) !?ProjectDetails {
        return self.system().projectDetails(gpa, name);
    }
    pub fn writeSnapshotsAfter(self: *Db, writer: anytype, after_id: i64) !void {
        return self.captures().writeSnapshotsAfter(writer, after_id);
    }
};
