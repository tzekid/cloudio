const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");
const models = @import("../models.zig");

const Allocator = std.mem.Allocator;
const DbError = models.DbError;
const SnapshotSummary = models.SnapshotSummary;
const SnapshotSummaries = models.SnapshotSummaries;
const NameValueRow = models.NameValueRow;
const NameValueRows = models.NameValueRows;
const InventoryFilter = models.InventoryFilter;
const InventoryItem = models.InventoryItem;
const InventoryItems = models.InventoryItems;
const InventoryFacet = models.InventoryFacet;
const InventoryFacets = models.InventoryFacets;
const ProjectDetails = models.ProjectDetails;
const ProjectCorrelation = models.ProjectCorrelation;
const ProjectCorrelations = models.ProjectCorrelations;
const TopologyRow = models.TopologyRow;
const TopologyRows = models.TopologyRows;
const SecretScanSurface = models.SecretScanSurface;
const secret_scan_surfaces = models.secret_scan_surfaces;
const MetricRow = models.MetricRow;
const MetricRows = models.MetricRows;
const CloudflareAccountRow = models.CloudflareAccountRow;
const CloudflareAccountRows = models.CloudflareAccountRows;
const CloudflareZoneRow = models.CloudflareZoneRow;
const CloudflareZoneRows = models.CloudflareZoneRows;
const CloudflareDnsRecordRow = models.CloudflareDnsRecordRow;
const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
const ContainerRow = models.ContainerRow;
const ContainerRows = models.ContainerRows;
const CloudflareKindCount = models.CloudflareKindCount;
const CloudflareKindCounts = models.CloudflareKindCounts;
const CloudflareResourceHintRow = models.CloudflareResourceHintRow;
const CloudflareResourceHintRows = models.CloudflareResourceHintRows;
const CloudflareInventoryHintRow = models.CloudflareInventoryHintRow;
const CloudflareInventoryHintRows = models.CloudflareInventoryHintRows;
const HostingerVpsRow = models.HostingerVpsRow;
const HostingerVpsRows = models.HostingerVpsRows;
const HostingerResourceHintRow = models.HostingerResourceHintRow;
const HostingerResourceHintRows = models.HostingerResourceHintRows;
const HostingerInventoryHintRow = models.HostingerInventoryHintRow;
const HostingerInventoryHintRows = models.HostingerInventoryHintRows;
const HostingerKindCount = models.HostingerKindCount;
const HostingerKindCounts = models.HostingerKindCounts;
const HostingerMetricSummary = models.HostingerMetricSummary;
const HostingerMetricSummaries = models.HostingerMetricSummaries;
const HostingerVpsFamilySummary = models.HostingerVpsFamilySummary;
const HostingerVpsFamilySummaries = models.HostingerVpsFamilySummaries;
const AuditEvent = models.AuditEvent;
const AuditEvents = models.AuditEvents;
const ProviderEvidenceFilter = models.ProviderEvidenceFilter;
const ProviderEvidenceEvent = models.ProviderEvidenceEvent;
const ProviderEvidenceEvents = models.ProviderEvidenceEvents;
const ProviderEvidenceSummaryRow = models.ProviderEvidenceSummaryRow;
const ProviderEvidenceSummaryRows = models.ProviderEvidenceSummaryRows;
const RouteCaptureEvidenceFilter = models.RouteCaptureEvidenceFilter;
const RouteCaptureEvidenceRow = models.RouteCaptureEvidenceRow;
const RouteCaptureEvidenceRows = models.RouteCaptureEvidenceRows;
const RouteSourceEvidenceRow = models.RouteSourceEvidenceRow;
const RouteSourceEvidenceRows = models.RouteSourceEvidenceRows;
const bindI64 = helpers.bindI64;
const bindI64Opt = helpers.bindI64Opt;
const bindBoolOpt = helpers.bindBoolOpt;
const bindText = helpers.bindText;
const bindTextOpt = helpers.bindTextOpt;
const stepDone = helpers.stepDone;
const deinitSnapshotList = helpers.deinitSnapshotList;
const deinitNameValueList = helpers.deinitNameValueList;
const deinitInventoryItemList = helpers.deinitInventoryItemList;
const deinitInventoryFacetList = helpers.deinitInventoryFacetList;
const deinitProjectCorrelationList = helpers.deinitProjectCorrelationList;
const deinitTopologyRowList = helpers.deinitTopologyRowList;
const deinitMetricList = helpers.deinitMetricList;
const deinitCloudflareAccountRowList = helpers.deinitCloudflareAccountRowList;
const deinitCloudflareZoneRowList = helpers.deinitCloudflareZoneRowList;
const deinitCloudflareDnsRecordRowList = helpers.deinitCloudflareDnsRecordRowList;
const deinitCloudflareKindCountList = helpers.deinitCloudflareKindCountList;
const deinitCloudflareResourceHintRowList = helpers.deinitCloudflareResourceHintRowList;
const deinitCloudflareInventoryHintRowList = helpers.deinitCloudflareInventoryHintRowList;
const deinitHostingerVpsRowList = helpers.deinitHostingerVpsRowList;
const deinitHostingerResourceHintRowList = helpers.deinitHostingerResourceHintRowList;
const deinitHostingerInventoryHintRowList = helpers.deinitHostingerInventoryHintRowList;
const deinitHostingerKindCountList = helpers.deinitHostingerKindCountList;
const deinitHostingerMetricSummaryList = helpers.deinitHostingerMetricSummaryList;
const deinitHostingerVpsFamilySummaryList = helpers.deinitHostingerVpsFamilySummaryList;
const deinitAuditEventList = helpers.deinitAuditEventList;
const deinitProviderEvidenceEventList = helpers.deinitProviderEvidenceEventList;
const deinitProviderEvidenceSummaryList = helpers.deinitProviderEvidenceSummaryList;
const deinitRouteCaptureEvidenceList = helpers.deinitRouteCaptureEvidenceList;
const deinitRouteSourceEvidenceList = helpers.deinitRouteSourceEvidenceList;
const snapshotSummaryFromStmt = helpers.snapshotSummaryFromStmt;
const auditEventFromStmt = helpers.auditEventFromStmt;
const providerEvidenceEventFromStmt = helpers.providerEvidenceEventFromStmt;
const providerEvidenceSummaryFromStmt = helpers.providerEvidenceSummaryFromStmt;
const routeCaptureEvidenceFromStmt = helpers.routeCaptureEvidenceFromStmt;
const routeSourceEvidenceFromStmt = helpers.routeSourceEvidenceFromStmt;
const metricRowFromStmt = helpers.metricRowFromStmt;
const cloudflareAccountRowFromStmt = helpers.cloudflareAccountRowFromStmt;
const cloudflareZoneRowFromStmt = helpers.cloudflareZoneRowFromStmt;
const cloudflareDnsRecordRowFromStmt = helpers.cloudflareDnsRecordRowFromStmt;
const cloudflareKindCountFromStmt = helpers.cloudflareKindCountFromStmt;
const cloudflareResourceHintRowFromStmt = helpers.cloudflareResourceHintRowFromStmt;
const cloudflareInventoryHintRowFromStmt = helpers.cloudflareInventoryHintRowFromStmt;
const hostingerVpsRowFromStmt = helpers.hostingerVpsRowFromStmt;
const hostingerResourceHintRowFromStmt = helpers.hostingerResourceHintRowFromStmt;
const hostingerInventoryHintRowFromStmt = helpers.hostingerInventoryHintRowFromStmt;
const hostingerKindCountFromStmt = helpers.hostingerKindCountFromStmt;
const hostingerMetricSummaryFromStmt = helpers.hostingerMetricSummaryFromStmt;
const hostingerVpsFamilySummaryFromStmt = helpers.hostingerVpsFamilySummaryFromStmt;
const nameValueRowFromStmt = helpers.nameValueRowFromStmt;
const inventoryItemFromStmt = helpers.inventoryItemFromStmt;
const inventoryFacetFromStmt = helpers.inventoryFacetFromStmt;
const projectDetailsFromStmt = helpers.projectDetailsFromStmt;
const projectCorrelationFromStmt = helpers.projectCorrelationFromStmt;
const topologyRowFromStmt = helpers.topologyRowFromStmt;
const dupeColumn = helpers.dupeColumn;
const positiveLimit = helpers.positiveLimit;
const columnText = helpers.columnText;
const provider_evidence_events_sql = helpers.provider_evidence_events_sql;
const provider_evidence_summary_sql = helpers.provider_evidence_summary_sql;
const route_capture_evidence_sql = helpers.route_capture_evidence_sql;
const isKnownTable = helpers.isKnownTable;
const secretScanSql = helpers.secretScanSql;

pub const Repository = struct {
    handle: *sqlite.sqlite3,

    fn prepare(self: Repository, sql: []const u8) !*sqlite.sqlite3_stmt {
        return helpers.prepare(self.handle, sql);
    }

    pub fn upsertCloudflareAccount(self: Repository, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_accounts(id, name, type, status, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, type=excluded.type, status=excluded.status, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, typ);
        try bindTextOpt(stmt, 4, status);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareZone(self: Repository, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_zones(id, name, account_id, status, paused, type, name_servers, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, account_id=excluded.account_id, status=excluded.status, paused=excluded.paused, type=excluded.type, name_servers=excluded.name_servers, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, account_id);
        try bindTextOpt(stmt, 4, status);
        try bindBoolOpt(stmt, 5, paused);
        try bindTextOpt(stmt, 6, typ);
        try bindTextOpt(stmt, 7, name_servers);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertDnsRecord(self: Repository, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_dns_records(id, zone_id, name, type, content, ttl, proxied, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET zone_id=excluded.zone_id, name=excluded.name, type=excluded.type, content=excluded.content, ttl=excluded.ttl, proxied=excluded.proxied, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindText(stmt, 2, zone_id);
        try bindTextOpt(stmt, 3, name);
        try bindTextOpt(stmt, 4, typ);
        try bindTextOpt(stmt, 5, content);
        try bindI64Opt(stmt, 6, ttl);
        try bindBoolOpt(stmt, 7, proxied);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn deleteDnsRecordsForZone(self: Repository, zone_id: []const u8) !void {
        const stmt = try self.prepare("DELETE FROM cloudflare_dns_records WHERE zone_id = ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, zone_id);
        try stepDone(stmt);
    }

    pub fn cloudflareAccountRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareAccountRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(type,''), COALESCE(status,''), updated_at
            \\FROM cloudflare_accounts
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareAccountRow).empty;
        errdefer deinitCloudflareAccountRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareAccountRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareZoneRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareZoneRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(account_id,''), COALESCE(status,''),
            \\       CASE WHEN paused IS NULL THEN '' WHEN paused != 0 THEN 'true' ELSE 'false' END,
            \\       COALESCE(type,''), COALESCE(name_servers,''), updated_at
            \\FROM cloudflare_zones
            \\ORDER BY updated_at DESC, name, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareZoneRow).empty;
        errdefer deinitCloudflareZoneRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareZoneRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareDnsRecordRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(zone_id,''), COALESCE(name,''), COALESCE(type,''), COALESCE(content,''),
            \\       COALESCE(CAST(ttl AS TEXT), ''),
            \\       CASE WHEN proxied IS NULL THEN '' WHEN proxied != 0 THEN 'true' ELSE 'false' END,
            \\       updated_at
            \\FROM cloudflare_dns_records
            \\ORDER BY updated_at DESC, name, type, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareDnsRecordRow).empty;
        errdefer deinitCloudflareDnsRecordRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareDnsRecordRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn nameValueRows(self: Repository, gpa: Allocator, sql: []const u8) !NameValueRows {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        var rows = std.ArrayList(NameValueRow).empty;
        errdefer deinitNameValueList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try nameValueRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }
};
