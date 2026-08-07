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

    pub fn upsertCloudflareResource(self: Repository, key: []const u8, kind: []const u8, resource_id: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, name: ?[]const u8, status: ?[]const u8, resource_type: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_resources(key, kind, resource_id, scope, scope_id, name, status, resource_type, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, name=excluded.name, status=excluded.status, resource_type=excluded.resource_type, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, resource_type);
        try bindText(stmt, 9, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareInventoryItem(
        self: Repository,
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
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_inventory_items(key, kind, resource_id, scope, scope_id, display_name, status, category, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, domain=excluded.domain, account_id=excluded.account_id, zone_id=excluded.zone_id, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, display_name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, category);
        try bindTextOpt(stmt, 9, domain);
        try bindTextOpt(stmt, 10, account_id);
        try bindTextOpt(stmt, 11, zone_id);
        try bindTextOpt(stmt, 12, related_id);
        try bindTextOpt(stmt, 13, flag);
        try bindTextOpt(stmt, 14, created_at_source);
        try bindTextOpt(stmt, 15, updated_at_source);
        try bindTextOpt(stmt, 16, expires_at_source);
        try bindText(stmt, 17, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareSecurityItem(
        self: Repository,
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
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_security_items(key, kind, resource_id, scope, scope_id, display_name, status, category, severity, action, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, severity=excluded.severity, action=excluded.action, domain=excluded.domain, account_id=excluded.account_id, zone_id=excluded.zone_id, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, display_name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, category);
        try bindTextOpt(stmt, 9, severity);
        try bindTextOpt(stmt, 10, action);
        try bindTextOpt(stmt, 11, domain);
        try bindTextOpt(stmt, 12, account_id);
        try bindTextOpt(stmt, 13, zone_id);
        try bindTextOpt(stmt, 14, related_id);
        try bindTextOpt(stmt, 15, flag);
        try bindTextOpt(stmt, 16, created_at_source);
        try bindTextOpt(stmt, 17, updated_at_source);
        try bindTextOpt(stmt, 18, expires_at_source);
        try bindText(stmt, 19, raw);
        try stepDone(stmt);
    }

    pub fn cloudflareResourceList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(resource_type,'') || ' ' || COALESCE(name,''))
            \\FROM cloudflare_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn cloudflareInventoryItemList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM cloudflare_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
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

    pub fn cloudflareResourceHints(self: Repository, gpa: Allocator, limit: i64) !CloudflareResourceHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(scope,''), COALESCE(scope_id,''), COALESCE(name,''), COALESCE(status,''), COALESCE(resource_type,''), updated_at
            \\FROM cloudflare_resources
            \\WHERE resource_id != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(CloudflareResourceHintRow).empty;
        errdefer deinitCloudflareResourceHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareResourceHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareInventoryHints(self: Repository, gpa: Allocator, limit: i64) !CloudflareInventoryHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(scope,''), COALESCE(scope_id,''), COALESCE(display_name,''), COALESCE(status,''), COALESCE(category,''), COALESCE(domain,''), COALESCE(account_id,''), COALESCE(zone_id,''), COALESCE(related_id,''), COALESCE(flag,''), COALESCE(updated_at_source, updated_at)
            \\FROM cloudflare_inventory_items
            \\WHERE resource_id != '' OR COALESCE(scope_id,'') != '' OR COALESCE(domain,'') != '' OR COALESCE(account_id,'') != '' OR COALESCE(zone_id,'') != '' OR COALESCE(related_id,'') != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(CloudflareInventoryHintRow).empty;
        errdefer deinitCloudflareInventoryHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareInventoryHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareResourceKindCounts(self: Repository, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareInventoryKindCounts(self: Repository, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareSecurityKindCounts(self: Repository, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_security_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    fn cloudflareKindCounts(self: Repository, gpa: Allocator, sql: []const u8, limit: i64) !CloudflareKindCounts {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareKindCount).empty;
        errdefer deinitCloudflareKindCountList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareKindCountFromStmt(gpa, stmt);
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
