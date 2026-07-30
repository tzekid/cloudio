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

    pub fn upsertCaddySite(self: Repository, host: []const u8, source_path: []const u8, raw_block: ?[]const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO caddy_sites(host, source_path, raw_block, updated_at)
            \\VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(host) DO UPDATE SET source_path=excluded.source_path, raw_block=excluded.raw_block, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, host);
        try bindText(stmt, 2, source_path);
        try bindTextOpt(stmt, 3, raw_block);
        try stepDone(stmt);
    }

    pub fn insertCaddyUpstream(self: Repository, host: []const u8, route: []const u8, upstream: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO caddy_upstreams(host, route, upstream) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, host);
        try bindText(stmt, 2, route);
        try bindText(stmt, 3, upstream);
        try stepDone(stmt);
    }

    pub fn upsertProject(self: Repository, name: []const u8, source: []const u8, path: ?[]const u8, host: ?[]const u8, upstream: ?[]const u8, service: ?[]const u8, container: ?[]const u8, raw: ?[]const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO projects(name, source, path, host, upstream, service, container, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET source=excluded.source, path=excluded.path, host=excluded.host, upstream=excluded.upstream, service=excluded.service, container=excluded.container, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindText(stmt, 2, source);
        try bindTextOpt(stmt, 3, path);
        try bindTextOpt(stmt, 4, host);
        try bindTextOpt(stmt, 5, upstream);
        try bindTextOpt(stmt, 6, service);
        try bindTextOpt(stmt, 7, container);
        try bindTextOpt(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn insertSystemMetric(self: Repository, metric: []const u8, value: []const u8, unit: ?[]const u8) !void {
        const stmt = try self.prepare("INSERT INTO system_metrics(metric, value, unit) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, metric);
        try bindText(stmt, 2, value);
        try bindTextOpt(stmt, 3, unit);
        try stepDone(stmt);
    }

    pub fn upsertService(self: Repository, name: []const u8, scope: []const u8, state: ?[]const u8, sub_state: ?[]const u8, description: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO services(name, scope, state, sub_state, description, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET scope=excluded.scope, state=excluded.state, sub_state=excluded.sub_state, description=excluded.description, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindText(stmt, 2, scope);
        try bindTextOpt(stmt, 3, state);
        try bindTextOpt(stmt, 4, sub_state);
        try bindTextOpt(stmt, 5, description);
        try bindText(stmt, 6, raw);
        try stepDone(stmt);
    }

    pub fn insertSocket(self: Repository, proto: ?[]const u8, state: ?[]const u8, local_address: ?[]const u8, process: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO sockets(proto, state, local_address, process, raw_text) VALUES (?, ?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, proto);
        try bindTextOpt(stmt, 2, state);
        try bindTextOpt(stmt, 3, local_address);
        try bindTextOpt(stmt, 4, process);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertContainer(self: Repository, name: []const u8, image: ?[]const u8, status: ?[]const u8, ports: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO containers(name, image, status, ports, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET image=excluded.image, status=excluded.status, ports=excluded.ports, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindTextOpt(stmt, 2, image);
        try bindTextOpt(stmt, 3, status);
        try bindTextOpt(stmt, 4, ports);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn projectList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT name, source FROM projects ORDER BY name LIMIT 200");
    }

    pub fn projectCorrelations(self: Repository, gpa: Allocator, limit: i64) !ProjectCorrelations {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT DISTINCT p.name AS project,
            \\         p.source AS source,
            \\         COALESCE(p.path, '') AS path,
            \\         COALESCE(NULLIF(p.host, ''), cu.host, '') AS host,
            \\         COALESCE(NULLIF(cu.upstream, ''), p.upstream, '') AS upstream,
            \\         COALESCE(p.service, '') AS service,
            \\         COALESCE(p.container, '') AS container
            \\  FROM projects p
            \\  LEFT JOIN caddy_upstreams cu
            \\    ON (p.host IS NOT NULL AND p.host != '' AND cu.host = p.host)
            \\    OR (p.upstream IS NOT NULL AND p.upstream != '' AND cu.upstream = p.upstream)
            \\  UNION ALL
            \\  SELECT DISTINCT '' AS project,
            \\         'caddy' AS source,
            \\         '' AS path,
            \\         cu.host AS host,
            \\         cu.upstream AS upstream,
            \\         '' AS service,
            \\         '' AS container
            \\  FROM caddy_upstreams cu
            \\  WHERE NOT EXISTS (
            \\    SELECT 1 FROM projects p
            \\    WHERE (p.host IS NOT NULL AND p.host != '' AND p.host = cu.host)
            \\       OR (p.upstream IS NOT NULL AND p.upstream != '' AND p.upstream = cu.upstream)
            \\  )
            \\)
            \\SELECT rows.project,
            \\       rows.source,
            \\       rows.path,
            \\       rows.host,
            \\       COALESCE(cs.source_path, '') AS caddy_source,
            \\       rows.upstream,
            \\       COALESCE(sock.state, '') AS socket_state,
            \\       COALESCE(sock.process, '') AS socket_process,
            \\       rows.service,
            \\       COALESCE(svc.state, '') AS service_state,
            \\       rows.container,
            \\       COALESCE(ct.status, '') AS container_status
            \\FROM rows
            \\LEFT JOIN caddy_sites cs ON cs.host = rows.host
            \\LEFT JOIN sockets sock
            \\  ON rows.upstream != ''
            \\ AND (sock.local_address = rows.upstream OR rows.upstream LIKE '%' || sock.local_address)
            \\LEFT JOIN services svc
            \\  ON rows.service != ''
            \\ AND svc.name = rows.service
            \\LEFT JOIN containers ct
            \\  ON rows.container != ''
            \\ AND ct.name = rows.container
            \\ORDER BY rows.project = '', rows.project, rows.host, rows.upstream
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(ProjectCorrelation).empty;
        errdefer deinitProjectCorrelationList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try projectCorrelationFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn topologyRows(self: Repository, gpa: Allocator, limit: i64) !TopologyRows {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT DISTINCT p.name AS project,
            \\         p.source AS source,
            \\         COALESCE(p.path, '') AS path,
            \\         COALESCE(NULLIF(p.host, ''), cu.host, '') AS host,
            \\         COALESCE(NULLIF(cu.upstream, ''), p.upstream, '') AS upstream,
            \\         COALESCE(p.service, '') AS service,
            \\         COALESCE(p.container, '') AS container
            \\  FROM projects p
            \\  LEFT JOIN caddy_upstreams cu
            \\    ON (p.host IS NOT NULL AND p.host != '' AND cu.host = p.host)
            \\    OR (p.upstream IS NOT NULL AND p.upstream != '' AND cu.upstream = p.upstream)
            \\  UNION ALL
            \\  SELECT DISTINCT '' AS project,
            \\         'caddy' AS source,
            \\         '' AS path,
            \\         cu.host AS host,
            \\         cu.upstream AS upstream,
            \\         '' AS service,
            \\         '' AS container
            \\  FROM caddy_upstreams cu
            \\  WHERE NOT EXISTS (
            \\    SELECT 1 FROM projects p
            \\    WHERE (p.host IS NOT NULL AND p.host != '' AND p.host = cu.host)
            \\       OR (p.upstream IS NOT NULL AND p.upstream != '' AND p.upstream = cu.upstream)
            \\  )
            \\),
            \\local_rows AS (
            \\  SELECT rows.project,
            \\         rows.source,
            \\         rows.path,
            \\         rows.host,
            \\         COALESCE(cs.source_path, '') AS caddy_source,
            \\         rows.upstream,
            \\         COALESCE(sock.state, '') AS socket_state,
            \\         COALESCE(sock.process, '') AS socket_process,
            \\         rows.service,
            \\         COALESCE(svc.state, '') AS service_state,
            \\         rows.container,
            \\         COALESCE(ct.status, '') AS container_status
            \\  FROM rows
            \\  LEFT JOIN caddy_sites cs ON cs.host = rows.host
            \\  LEFT JOIN sockets sock
            \\    ON rows.upstream != ''
            \\   AND (sock.local_address = rows.upstream OR rows.upstream LIKE '%' || sock.local_address)
            \\  LEFT JOIN services svc
            \\    ON rows.service != ''
            \\   AND svc.name = rows.service
            \\  LEFT JOIN containers ct
            \\    ON rows.container != ''
            \\   AND ct.name = rows.container
            \\),
            \\dns_local_target AS (
            \\  SELECT dns.id,
            \\         dns.name,
            \\         dns.type,
            \\         dns.content,
            \\         dns.proxied
            \\  FROM cloudflare_dns_records dns
            \\  WHERE dns.name IS NOT NULL
            \\    AND dns.name != ''
            \\    AND upper(COALESCE(dns.type, '')) IN ('A', 'AAAA')
            \\    AND NOT EXISTS (
            \\      SELECT 1 FROM cloudflare_dns_records better
            \\      WHERE better.name = dns.name
            \\        AND upper(COALESCE(better.type, '')) IN ('A', 'AAAA')
            \\        AND (
            \\          CASE upper(COALESCE(better.type, '')) WHEN 'A' THEN 0 ELSE 1 END <
            \\          CASE upper(COALESCE(dns.type, '')) WHEN 'A' THEN 0 ELSE 1 END
            \\          OR (
            \\            CASE upper(COALESCE(better.type, '')) WHEN 'A' THEN 0 ELSE 1 END =
            \\            CASE upper(COALESCE(dns.type, '')) WHEN 'A' THEN 0 ELSE 1 END
            \\            AND better.id < dns.id
            \\          )
            \\        )
            \\    )
            \\),
            \\combined AS (
            \\  SELECT COALESCE(NULLIF(local_rows.host, ''), direct_dns.name, wildcard_dns.name, '') AS host,
            \\         COALESCE(direct_dns.name, wildcard_dns.name, '') AS dns_name,
            \\         COALESCE(direct_dns.type, wildcard_dns.type, '') AS dns_type,
            \\         COALESCE(direct_dns.content, wildcard_dns.content, '') AS dns_content,
            \\         CASE
            \\           WHEN COALESCE(direct_dns.proxied, wildcard_dns.proxied) IS NULL THEN ''
            \\           WHEN COALESCE(direct_dns.proxied, wildcard_dns.proxied) != 0 THEN 'true'
            \\           ELSE 'false'
            \\         END AS dns_proxied,
            \\         local_rows.project,
            \\         local_rows.source,
            \\         local_rows.path,
            \\         local_rows.caddy_source,
            \\         local_rows.upstream,
            \\         local_rows.socket_state,
            \\         local_rows.socket_process,
            \\         local_rows.service,
            \\         local_rows.service_state,
            \\         local_rows.container,
            \\         local_rows.container_status
            \\  FROM local_rows
            \\  LEFT JOIN dns_local_target direct_dns
            \\    ON direct_dns.name = local_rows.host
            \\  LEFT JOIN dns_local_target wildcard_dns
            \\    ON direct_dns.name IS NULL
            \\   AND wildcard_dns.name LIKE '*.%'
            \\   AND local_rows.host LIKE '%' || substr(wildcard_dns.name, 2)
            \\  UNION ALL
            \\  SELECT dns.name AS host,
            \\         dns.name AS dns_name,
            \\         COALESCE(dns.type, '') AS dns_type,
            \\         COALESCE(dns.content, '') AS dns_content,
            \\         CASE WHEN dns.proxied IS NULL THEN '' WHEN dns.proxied != 0 THEN 'true' ELSE 'false' END AS dns_proxied,
            \\         '' AS project,
            \\         'cloudflare' AS source,
            \\         '' AS path,
            \\         '' AS caddy_source,
            \\         '' AS upstream,
            \\         '' AS socket_state,
            \\         '' AS socket_process,
            \\         '' AS service,
            \\         '' AS service_state,
            \\         '' AS container,
            \\         '' AS container_status
            \\  FROM dns_local_target dns
            \\  WHERE dns.name IS NOT NULL
            \\    AND dns.name != ''
            \\    AND NOT EXISTS (
            \\      SELECT 1 FROM local_rows
            \\      WHERE dns.name = local_rows.host
            \\         OR (dns.name LIKE '*.%' AND local_rows.host LIKE '%' || substr(dns.name, 2))
            \\    )
            \\)
            \\SELECT * FROM combined
            \\ORDER BY project = '', project, host, dns_type, upstream
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(TopologyRow).empty;
        errdefer deinitTopologyRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try topologyRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn serviceList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(state,'') FROM services ORDER BY 1 LIMIT 200");
    }

    pub fn socketList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(local_address,''), COALESCE(process,'') FROM sockets ORDER BY 1 LIMIT 200");
    }

    pub fn containerRows(self: Repository, gpa: Allocator, limit: i64) !ContainerRows {
        const stmt = try self.prepare(
            \\SELECT COALESCE(name,''), COALESCE(image,''), COALESCE(status,''), COALESCE(ports,''), updated_at
            \\FROM containers
            \\ORDER BY name
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(ContainerRow).empty;
        errdefer {
            for (rows.items) |row| row.deinit(gpa);
            rows.deinit(gpa);
        }
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = ContainerRow{
                .name = try dupeColumn(gpa, stmt, 0),
                .image = try dupeColumn(gpa, stmt, 1),
                .status = try dupeColumn(gpa, stmt, 2),
                .ports = try dupeColumn(gpa, stmt, 3),
                .updated_at = try dupeColumn(gpa, stmt, 4),
            };
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn containerList(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(status,'') FROM containers ORDER BY 1 LIMIT 200");
    }

    pub fn caddyUpstreams(self: Repository, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT DISTINCT host, upstream FROM caddy_upstreams ORDER BY host, upstream");
    }

    pub fn recentMetrics(self: Repository, gpa: Allocator, limit: i64) !MetricRows {
        const stmt = try self.prepare(
            \\SELECT metric, COALESCE(value,''), COALESCE(unit,''), captured_at
            \\FROM system_metrics WHERE value IS NOT NULL AND value != '' ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(MetricRow).empty;
        errdefer deinitMetricList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try metricRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn projectDetails(self: Repository, gpa: Allocator, name: []const u8) !?ProjectDetails {
        const stmt = try self.prepare(
            \\SELECT name, source, COALESCE(path,''), COALESCE(host,''), COALESCE(upstream,''), COALESCE(service,''), COALESCE(container,'')
            \\FROM projects WHERE name = ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try projectDetailsFromStmt(gpa, stmt);
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
