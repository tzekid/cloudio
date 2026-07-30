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

    pub fn insertSnapshot(self: Repository, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
        const stmt = try self.prepare(
            \\INSERT INTO snapshots(source, kind, target, status, summary, raw_json, raw_text)
            \\VALUES (?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindText(stmt, 2, kind);
        try bindTextOpt(stmt, 3, target);
        try bindText(stmt, 4, status);
        try bindTextOpt(stmt, 5, summary);
        try bindTextOpt(stmt, 6, raw_json);
        try bindTextOpt(stmt, 7, raw_text);
        try stepDone(stmt);
        return sqlite.sqlite3_last_insert_rowid(self.handle);
    }

    pub fn insertProviderRaw(self: Repository, provider: []const u8, endpoint: []const u8, status: i64, body: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO provider_raw(provider, endpoint, status, body_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, provider);
        try bindText(stmt, 2, endpoint);
        try bindI64(stmt, 3, status);
        try bindText(stmt, 4, body);
        try stepDone(stmt);
    }

    pub fn latestSnapshotId(self: Repository) !i64 {
        const stmt = try self.prepare("SELECT COALESCE(MAX(id), 0) FROM snapshots");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn recentSnapshots(self: Repository, gpa: Allocator, limit: i64) !SnapshotSummaries {
        const stmt = try self.prepare(
            \\SELECT id, source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(SnapshotSummary).empty;
        errdefer deinitSnapshotList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try snapshotSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn snapshotsForSource(self: Repository, gpa: Allocator, source: []const u8, limit: i64) !SnapshotSummaries {
        const stmt = try self.prepare(
            \\SELECT id, source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots WHERE source = ? ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindI64(stmt, 2, limit);
        return try self.snapshotRowsFromStmt(gpa, stmt);
    }

    fn snapshotRowsFromStmt(self: Repository, gpa: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummaries {
        _ = self;
        var rows = std.ArrayList(SnapshotSummary).empty;
        errdefer deinitSnapshotList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try snapshotSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn writeSnapshotsAfter(self: Repository, writer: anytype, after_id: i64) !void {
        const stmt = try self.prepare(
            \\SELECT source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots WHERE id > ? ORDER BY id DESC
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, after_id);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            try writer.print("{s}/{s}\t{s}\t[{s}]\t{s}\t{s}\n", .{
                columnText(stmt, 0) orelse "",
                columnText(stmt, 1) orelse "",
                columnText(stmt, 2) orelse "",
                columnText(stmt, 3) orelse "",
                columnText(stmt, 4) orelse "",
                columnText(stmt, 5) orelse "",
            });
        }
    }

};
