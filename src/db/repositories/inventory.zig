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

    pub fn inventoryItems(self: Repository, gpa: Allocator, filter: InventoryFilter) !InventoryItems {
        const stmt = try self.prepare(
            \\SELECT provider, kind, resource_id, scope, scope_id, display_name, status, category, domain, username, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, updated_at
            \\FROM (
            \\  SELECT 'cloudflare' AS provider,
            \\         kind,
            \\         resource_id,
            \\         COALESCE(scope, '') AS scope,
            \\         COALESCE(scope_id, '') AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         '' AS username,
            \\         COALESCE(account_id, '') AS account_id,
            \\         COALESCE(zone_id, '') AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         COALESCE(created_at_source, '') AS created_at_source,
            \\         COALESCE(updated_at_source, '') AS updated_at_source,
            \\         COALESCE(expires_at_source, '') AS expires_at_source,
            \\         updated_at
            \\  FROM cloudflare_inventory_items
            \\  UNION ALL
            \\  SELECT 'hostinger' AS provider,
            \\         kind,
            \\         resource_id,
            \\         '' AS scope,
            \\         '' AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         COALESCE(username, '') AS username,
            \\         '' AS account_id,
            \\         '' AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         COALESCE(created_at_source, '') AS created_at_source,
            \\         COALESCE(updated_at_source, '') AS updated_at_source,
            \\         COALESCE(expires_at_source, '') AS expires_at_source,
            \\         updated_at
            \\  FROM hostinger_inventory_items
            \\)
            \\WHERE (? IS NULL OR provider = ?)
            \\  AND (? IS NULL OR domain = ?)
            \\  AND (? IS NULL OR lower(provider || ' ' || kind || ' ' || resource_id || ' ' || scope || ' ' || scope_id || ' ' || display_name || ' ' || status || ' ' || category || ' ' || domain || ' ' || username || ' ' || account_id || ' ' || zone_id || ' ' || related_id || ' ' || flag) LIKE '%' || lower(?) || '%')
            \\ORDER BY updated_at DESC, provider, kind, resource_id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindTextOpt(stmt, 3, filter.domain);
        try bindTextOpt(stmt, 4, filter.domain);
        try bindTextOpt(stmt, 5, filter.query);
        try bindTextOpt(stmt, 6, filter.query);
        try bindI64(stmt, 7, if (filter.limit > 0) filter.limit else 200);

        var rows = std.ArrayList(InventoryItem).empty;
        errdefer deinitInventoryItemList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try inventoryItemFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn inventoryFacets(self: Repository, gpa: Allocator, filter: InventoryFilter) !InventoryFacets {
        const stmt = try self.prepare(
            \\WITH inventory AS (
            \\  SELECT 'cloudflare' AS provider,
            \\         kind,
            \\         COALESCE(resource_id, '') AS resource_id,
            \\         COALESCE(scope, '') AS scope,
            \\         COALESCE(scope_id, '') AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         '' AS username,
            \\         COALESCE(account_id, '') AS account_id,
            \\         COALESCE(zone_id, '') AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         updated_at
            \\  FROM cloudflare_inventory_items
            \\  UNION ALL
            \\  SELECT 'hostinger' AS provider,
            \\         kind,
            \\         COALESCE(resource_id, '') AS resource_id,
            \\         '' AS scope,
            \\         '' AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         COALESCE(username, '') AS username,
            \\         '' AS account_id,
            \\         '' AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         updated_at
            \\  FROM hostinger_inventory_items
            \\)
            \\SELECT provider,
            \\       kind,
            \\       status,
            \\       category,
            \\       COUNT(*) AS item_count,
            \\       COUNT(DISTINCT NULLIF(domain, '')) AS domain_count,
            \\       COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM inventory
            \\WHERE (? IS NULL OR provider = ?)
            \\  AND (? IS NULL OR domain = ?)
            \\  AND (? IS NULL OR lower(provider || ' ' || kind || ' ' || resource_id || ' ' || scope || ' ' || scope_id || ' ' || display_name || ' ' || status || ' ' || category || ' ' || domain || ' ' || username || ' ' || account_id || ' ' || zone_id || ' ' || related_id || ' ' || flag) LIKE '%' || lower(?) || '%')
            \\GROUP BY provider, kind, status, category
            \\ORDER BY item_count DESC, provider, kind, status, category
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindTextOpt(stmt, 3, filter.domain);
        try bindTextOpt(stmt, 4, filter.domain);
        try bindTextOpt(stmt, 5, filter.query);
        try bindTextOpt(stmt, 6, filter.query);
        try bindI64(stmt, 7, if (filter.limit > 0) filter.limit else 200);

        var rows = std.ArrayList(InventoryFacet).empty;
        errdefer deinitInventoryFacetList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try inventoryFacetFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

};
