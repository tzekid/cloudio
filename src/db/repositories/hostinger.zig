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

    pub fn upsertHostingerVps(self: Repository, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_vps(id, name, status, ipv4, plan, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, status=excluded.status, ipv4=excluded.ipv4, plan=excluded.plan, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, status);
        try bindTextOpt(stmt, 4, ipv4);
        try bindTextOpt(stmt, 5, plan);
        try bindText(stmt, 6, raw);
        try stepDone(stmt);
    }

    pub fn insertHostingerMetric(self: Repository, vm_id: []const u8, metric: []const u8, value: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO hostinger_metrics(vm_id, metric, value, raw_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, vm_id);
        try bindText(stmt, 2, metric);
        try bindTextOpt(stmt, 3, value);
        try bindText(stmt, 4, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerResource(self: Repository, key: []const u8, kind: []const u8, resource_id: []const u8, target: ?[]const u8, name: ?[]const u8, status: ?[]const u8, domain: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_resources(key, kind, resource_id, target, name, status, domain, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, target=excluded.target, name=excluded.name, status=excluded.status, domain=excluded.domain, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, target);
        try bindTextOpt(stmt, 5, name);
        try bindTextOpt(stmt, 6, status);
        try bindTextOpt(stmt, 7, domain);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerInventoryItem(
        self: Repository,
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
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_inventory_items(key, kind, resource_id, display_name, status, category, domain, username, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, domain=excluded.domain, username=excluded.username, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, display_name);
        try bindTextOpt(stmt, 5, status);
        try bindTextOpt(stmt, 6, category);
        try bindTextOpt(stmt, 7, domain);
        try bindTextOpt(stmt, 8, username);
        try bindTextOpt(stmt, 9, related_id);
        try bindTextOpt(stmt, 10, flag);
        try bindTextOpt(stmt, 11, created_at_source);
        try bindTextOpt(stmt, 12, updated_at_source);
        try bindTextOpt(stmt, 13, expires_at_source);
        try bindText(stmt, 14, raw);
        try stepDone(stmt);
    }

    pub fn hostingerResourceList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(name,''))
            \\FROM hostinger_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerInventoryItemList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(username,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM hostinger_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerVpsRows(self: Repository, gpa: Allocator, limit: i64) !HostingerVpsRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(status,''), COALESCE(ipv4,''), COALESCE(plan,''), updated_at
            \\FROM hostinger_vps
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerVpsRow).empty;
        errdefer deinitHostingerVpsRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerVpsRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerResourceHints(self: Repository, gpa: Allocator, limit: i64) !HostingerResourceHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(target,''), COALESCE(name,''), COALESCE(status,''), COALESCE(domain,''), updated_at
            \\FROM hostinger_resources
            \\WHERE resource_id != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(HostingerResourceHintRow).empty;
        errdefer deinitHostingerResourceHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerResourceHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerInventoryHints(self: Repository, gpa: Allocator, limit: i64) !HostingerInventoryHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(display_name,''), COALESCE(status,''), COALESCE(category,''), COALESCE(domain,''), COALESCE(username,''), COALESCE(related_id,''), COALESCE(flag,''), updated_at
            \\FROM hostinger_inventory_items
            \\WHERE resource_id != '' OR COALESCE(domain,'') != '' OR COALESCE(username,'') != '' OR COALESCE(related_id,'') != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(HostingerInventoryHintRow).empty;
        errdefer deinitHostingerInventoryHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerInventoryHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerResourceKindCounts(self: Repository, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerInventoryKindCounts(self: Repository, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerMetricSummaries(self: Repository, gpa: Allocator, limit: i64) !HostingerMetricSummaries {
        const stmt = try self.prepare(
            \\SELECT COALESCE(vm_id,''), metric, COUNT(*) AS sample_count, COALESCE(MAX(captured_at), '') AS latest_captured
            \\FROM hostinger_metrics
            \\GROUP BY vm_id, metric
            \\ORDER BY latest_captured DESC, vm_id, metric
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerMetricSummary).empty;
        errdefer deinitHostingerMetricSummaryList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerMetricSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerVpsFamilySummaries(self: Repository, gpa: Allocator, limit: i64) !HostingerVpsFamilySummaries {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT v.id AS vm_id,
            \\         'resource' AS source,
            \\         r.kind AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(r.updated_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_resources r
            \\    ON r.target = v.id OR r.target LIKE v.id || '/%'
            \\  GROUP BY v.id, r.kind
            \\  UNION ALL
            \\  SELECT v.id AS vm_id,
            \\         'inventory' AS source,
            \\         i.kind AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(i.updated_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_inventory_items i
            \\    ON i.key LIKE i.kind || '|' || v.id || '|%'
            \\    OR i.key LIKE i.kind || '|' || v.id || '/%'
            \\  GROUP BY v.id, i.kind
            \\  UNION ALL
            \\  SELECT v.id AS vm_id,
            \\         'metric' AS source,
            \\         m.metric AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(m.captured_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_metrics m ON m.vm_id = v.id
            \\  GROUP BY v.id, m.metric
            \\)
            \\SELECT vm_id, source, kind, item_count, latest_updated
            \\FROM rows
            \\ORDER BY vm_id, source, kind
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerVpsFamilySummary).empty;
        errdefer deinitHostingerVpsFamilySummaryList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerVpsFamilySummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn hostingerKindCounts(self: Repository, gpa: Allocator, sql: []const u8, limit: i64) !HostingerKindCounts {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerKindCount).empty;
        errdefer deinitHostingerKindCountList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerKindCountFromStmt(gpa, stmt);
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
