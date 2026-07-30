const std = @import("std");
const sqlite = @import("sqlite");
const models = @import("models.zig");

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

pub fn prepare(handle: *sqlite.sqlite3, sql: []const u8) !*sqlite.sqlite3_stmt {
    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
    if (rc != sqlite.SQLITE_OK) return DbError.SqlitePrepare;
    return stmt.?;
}

pub fn bindI64(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: i64) !void {
    if (sqlite.sqlite3_bind_int64(stmt, idx, value) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

pub fn bindI64Opt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?i64) !void {
    if (value) |v| try bindI64(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

pub fn bindBoolOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?bool) !void {
    if (value) |v| try bindI64(stmt, idx, if (v) 1 else 0) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

pub fn bindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) {
        return DbError.SqliteBind;
    }
}

pub fn bindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |v| try bindText(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

pub fn stepDone(stmt: *sqlite.sqlite3_stmt) !void {
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return DbError.SqliteStep;
}

pub fn deinitSnapshotList(rows: *std.ArrayList(SnapshotSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitNameValueList(rows: *std.ArrayList(NameValueRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitInventoryItemList(rows: *std.ArrayList(InventoryItem), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitInventoryFacetList(rows: *std.ArrayList(InventoryFacet), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitProjectCorrelationList(rows: *std.ArrayList(ProjectCorrelation), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitTopologyRowList(rows: *std.ArrayList(TopologyRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitMetricList(rows: *std.ArrayList(MetricRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareAccountRowList(rows: *std.ArrayList(CloudflareAccountRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareZoneRowList(rows: *std.ArrayList(CloudflareZoneRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareDnsRecordRowList(rows: *std.ArrayList(CloudflareDnsRecordRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareKindCountList(rows: *std.ArrayList(CloudflareKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareResourceHintRowList(rows: *std.ArrayList(CloudflareResourceHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitCloudflareInventoryHintRowList(rows: *std.ArrayList(CloudflareInventoryHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerVpsRowList(rows: *std.ArrayList(HostingerVpsRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerResourceHintRowList(rows: *std.ArrayList(HostingerResourceHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerInventoryHintRowList(rows: *std.ArrayList(HostingerInventoryHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerKindCountList(rows: *std.ArrayList(HostingerKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerMetricSummaryList(rows: *std.ArrayList(HostingerMetricSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitHostingerVpsFamilySummaryList(rows: *std.ArrayList(HostingerVpsFamilySummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitAuditEventList(rows: *std.ArrayList(AuditEvent), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitProviderEvidenceEventList(rows: *std.ArrayList(ProviderEvidenceEvent), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitProviderEvidenceSummaryList(rows: *std.ArrayList(ProviderEvidenceSummaryRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitRouteCaptureEvidenceList(rows: *std.ArrayList(RouteCaptureEvidenceRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitRouteSourceEvidenceList(rows: *std.ArrayList(RouteSourceEvidenceRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn snapshotSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummary {
    const id = sqlite.sqlite3_column_int64(stmt, 0);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const target = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(target);
    const status = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(status);
    const summary = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(summary);
    const captured_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(captured_at);
    return .{
        .id = id,
        .source = source,
        .kind = kind,
        .target = target,
        .status = status,
        .summary = summary,
        .captured_at = captured_at,
    };
}

pub fn auditEventFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !AuditEvent {
    const id = sqlite.sqlite3_column_int64(stmt, 0);
    const action = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(action);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const detail = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(detail);
    const created_at = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(created_at);
    return .{
        .id = id,
        .action = action,
        .status = status,
        .detail = detail,
        .created_at = created_at,
    };
}

pub fn providerEvidenceEventFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProviderEvidenceEvent {
    const row_id = sqlite.sqlite3_column_int64(stmt, 0);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const provider = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(kind);
    const target = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(target);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const detail = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(detail);
    const recorded_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(recorded_at);
    return .{
        .row_id = row_id,
        .source = source,
        .provider = provider,
        .kind = kind,
        .target = target,
        .status = status,
        .detail = detail,
        .recorded_at = recorded_at,
    };
}

pub fn providerEvidenceSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProviderEvidenceSummaryRow {
    const source = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(source);
    const provider = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const latest_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(latest_at);
    return .{
        .source = source,
        .provider = provider,
        .kind = kind,
        .status = status,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .latest_at = latest_at,
    };
}

pub fn routeCaptureEvidenceFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !RouteCaptureEvidenceRow {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const operation_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(operation_id);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const endpoint_sample = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(endpoint_sample);
    const latest_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(latest_at);
    return .{
        .provider = provider,
        .operation_id = operation_id,
        .status = status,
        .endpoint_sample = endpoint_sample,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .latest_at = latest_at,
    };
}

pub fn routeSourceEvidenceFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !RouteSourceEvidenceRow {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const operation_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(operation_id);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const target = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(target);
    const summary = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(summary);
    const raw_json = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(raw_json);
    const captured_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(captured_at);
    return .{
        .provider = provider,
        .operation_id = operation_id,
        .status = status,
        .target = target,
        .summary = summary,
        .raw_json = raw_json,
        .captured_at = captured_at,
    };
}

pub fn metricRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !MetricRow {
    const metric = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(metric);
    const value = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(value);
    const unit = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(unit);
    const captured_at = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(captured_at);
    return .{
        .metric = metric,
        .value = value,
        .unit = unit,
        .captured_at = captured_at,
    };
}

pub fn cloudflareAccountRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareAccountRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const account_type = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(account_type);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const updated_at = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .account_type = account_type,
        .status = status,
        .updated_at = updated_at,
    };
}

pub fn cloudflareZoneRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareZoneRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const account_id = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(account_id);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const paused = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(paused);
    const zone_type = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(zone_type);
    const name_servers = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(name_servers);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .account_id = account_id,
        .status = status,
        .paused = paused,
        .zone_type = zone_type,
        .name_servers = name_servers,
        .updated_at = updated_at,
    };
}

pub fn cloudflareDnsRecordRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareDnsRecordRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const zone_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(zone_id);
    const name = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(name);
    const record_type = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(record_type);
    const content = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(content);
    const ttl = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(ttl);
    const proxied = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(proxied);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .zone_id = zone_id,
        .name = name,
        .record_type = record_type,
        .content = content,
        .ttl = ttl,
        .proxied = proxied,
        .updated_at = updated_at,
    };
}

pub fn cloudflareKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareKindCount {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(latest_updated);
    return .{
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 1),
        .latest_updated = latest_updated,
    };
}

pub fn cloudflareResourceHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareResourceHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope_id);
    const name = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const resource_type = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(resource_type);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .name = name,
        .status = status,
        .resource_type = resource_type,
        .updated_at = updated_at,
    };
}

pub fn cloudflareInventoryHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareInventoryHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope_id);
    const display_name = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(domain);
    const account_id = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(account_id);
    const zone_id = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(zone_id);
    const related_id = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(flag);
    const updated_at = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .updated_at = updated_at,
    };
}

pub fn hostingerVpsRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerVpsRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const ipv4 = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(ipv4);
    const plan = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(plan);
    const updated_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .status = status,
        .ipv4 = ipv4,
        .plan = plan,
        .updated_at = updated_at,
    };
}

pub fn hostingerResourceHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerResourceHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const target = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(target);
    const name = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(status);
    const domain = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(domain);
    const updated_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .target = target,
        .name = name,
        .status = status,
        .domain = domain,
        .updated_at = updated_at,
    };
}

pub fn hostingerInventoryHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerInventoryHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const display_name = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(domain);
    const username = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(username);
    const related_id = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(flag);
    const updated_at = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .username = username,
        .related_id = related_id,
        .flag = flag,
        .updated_at = updated_at,
    };
}

pub fn hostingerKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerKindCount {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(latest_updated);
    return .{
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 1),
        .latest_updated = latest_updated,
    };
}

pub fn hostingerMetricSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerMetricSummary {
    const vm_id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(vm_id);
    const metric = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(metric);
    const latest_captured = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(latest_captured);
    return .{
        .vm_id = vm_id,
        .metric = metric,
        .count = sqlite.sqlite3_column_int64(stmt, 2),
        .latest_captured = latest_captured,
    };
}

pub fn hostingerVpsFamilySummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerVpsFamilySummary {
    const vm_id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(vm_id);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(latest_updated);
    return .{
        .vm_id = vm_id,
        .source = source,
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 3),
        .latest_updated = latest_updated,
    };
}

pub fn nameValueRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !NameValueRow {
    const name = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(name);
    const value = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(value);
    return .{
        .name = name,
        .value = value,
    };
}

pub fn inventoryItemFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryItem {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(scope_id);
    const display_name = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(domain);
    const username = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(username);
    const account_id = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(account_id);
    const zone_id = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(zone_id);
    const related_id = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 13);
    errdefer allocator.free(flag);
    const created_at_source = try dupeColumn(allocator, stmt, 14);
    errdefer allocator.free(created_at_source);
    const updated_at_source = try dupeColumn(allocator, stmt, 15);
    errdefer allocator.free(updated_at_source);
    const expires_at_source = try dupeColumn(allocator, stmt, 16);
    errdefer allocator.free(expires_at_source);
    const updated_at = try dupeColumn(allocator, stmt, 17);
    errdefer allocator.free(updated_at);
    return .{
        .provider = provider,
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .username = username,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .created_at_source = created_at_source,
        .updated_at_source = updated_at_source,
        .expires_at_source = expires_at_source,
        .updated_at = updated_at,
    };
}

pub fn inventoryFacetFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryFacet {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(kind);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(category);
    const latest_updated = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(latest_updated);
    return .{
        .provider = provider,
        .kind = kind,
        .status = status,
        .category = category,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .domains = sqlite.sqlite3_column_int64(stmt, 5),
        .latest_updated = latest_updated,
    };
}

pub fn projectDetailsFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProjectDetails {
    const name = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(name);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(path);
    const host = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(host);
    const upstream = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(upstream);
    const service = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(service);
    const container = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(container);
    return .{
        .name = name,
        .source = source,
        .path = path,
        .host = host,
        .upstream = upstream,
        .service = service,
        .container = container,
    };
}

pub fn projectCorrelationFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProjectCorrelation {
    const project = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(project);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(path);
    const host = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(host);
    const caddy_source = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(caddy_source);
    const upstream = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(upstream);
    const socket_state = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(socket_state);
    const socket_process = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(socket_process);
    const service = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(service);
    const service_state = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(service_state);
    const container = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(container);
    const container_status = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(container_status);
    return .{
        .project = project,
        .source = source,
        .path = path,
        .host = host,
        .caddy_source = caddy_source,
        .upstream = upstream,
        .socket_state = socket_state,
        .socket_process = socket_process,
        .service = service,
        .service_state = service_state,
        .container = container,
        .container_status = container_status,
    };
}

pub fn topologyRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !TopologyRow {
    const host = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(host);
    const dns_name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(dns_name);
    const dns_type = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(dns_type);
    const dns_content = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(dns_content);
    const dns_proxied = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(dns_proxied);
    const project = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(project);
    const source = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(path);
    const caddy_source = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(caddy_source);
    const upstream = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(upstream);
    const socket_state = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(socket_state);
    const socket_process = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(socket_process);
    const service = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(service);
    const service_state = try dupeColumn(allocator, stmt, 13);
    errdefer allocator.free(service_state);
    const container = try dupeColumn(allocator, stmt, 14);
    errdefer allocator.free(container);
    const container_status = try dupeColumn(allocator, stmt, 15);
    errdefer allocator.free(container_status);
    return .{
        .host = host,
        .dns_name = dns_name,
        .dns_type = dns_type,
        .dns_content = dns_content,
        .dns_proxied = dns_proxied,
        .project = project,
        .source = source,
        .path = path,
        .caddy_source = caddy_source,
        .upstream = upstream,
        .socket_state = socket_state,
        .socket_process = socket_process,
        .service = service,
        .service_state = service_state,
        .container = container,
        .container_status = container_status,
    };
}

pub fn dupeColumn(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, idx: c_int) ![]u8 {
    return try allocator.dupe(u8, columnText(stmt, idx) orelse "");
}

pub fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

pub fn columnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(stmt, idx) == sqlite.SQLITE_NULL) return null;
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

pub const provider_evidence_cte =
    \\WITH evidence AS (
    \\  SELECT id AS row_id,
    \\         'provider_raw' AS source,
    \\         provider AS provider,
    \\         'http' AS kind,
    \\         endpoint AS target,
    \\         COALESCE(CAST(status AS TEXT), '') AS status,
    \\         'body_bytes=' || length(COALESCE(body_json, '')) AS detail,
    \\         captured_at AS recorded_at
    \\  FROM provider_raw
    \\  UNION ALL
    \\  SELECT id AS row_id,
    \\         'snapshot' AS source,
    \\         source AS provider,
    \\         kind AS kind,
    \\         COALESCE(target, '') AS target,
    \\         status AS status,
    \\         COALESCE(summary, '') AS detail,
    \\         captured_at AS recorded_at
    \\  FROM snapshots
    \\  UNION ALL
    \\  SELECT id AS row_id,
    \\         'audit' AS source,
    \\         CASE
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%cloudflare%' THEN 'cloudflare'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%hostinger%' THEN 'hostinger'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%caddy%' THEN 'caddy'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%system%' THEN 'system'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%project%' THEN 'projects'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%route%' THEN 'route'
    \\           ELSE ''
    \\         END AS provider,
    \\         action AS kind,
    \\         '' AS target,
    \\         status AS status,
    \\         COALESCE(detail, '') AS detail,
    \\         created_at AS recorded_at
    \\  FROM audit_events
    \\)
;

pub const provider_evidence_events_sql = provider_evidence_cte ++
    \\SELECT row_id, source, provider, kind, target, status, detail, recorded_at
    \\FROM evidence
    \\WHERE (? IS NULL OR provider = ?)
    \\ORDER BY recorded_at DESC, row_id DESC
    \\LIMIT ?
;

pub const provider_evidence_summary_sql = provider_evidence_cte ++
    \\SELECT source,
    \\       provider,
    \\       kind,
    \\       status,
    \\       COUNT(*) AS event_count,
    \\       COALESCE(MAX(recorded_at), '') AS latest_at
    \\FROM evidence
    \\WHERE (? IS NULL OR provider = ?)
    \\GROUP BY source, provider, kind, status
    \\ORDER BY latest_at DESC, event_count DESC, source, provider, kind, status
;

pub const route_capture_evidence_sql =
    \\WITH parsed AS (
    \\  SELECT status,
    \\         created_at,
    \\         detail,
    \\         instr(detail, '/') AS slash_pos
    \\  FROM audit_events
    \\  WHERE action = 'route.capture'
    \\),
    \\provider_rows AS (
    \\  SELECT status,
    \\         created_at,
    \\         detail,
    \\         CASE WHEN slash_pos > 1 THEN substr(detail, 1, slash_pos - 1) ELSE '' END AS provider,
    \\         CASE WHEN slash_pos > 0 THEN substr(detail, slash_pos + 1) ELSE detail END AS rest
    \\  FROM parsed
    \\),
    \\route_rows AS (
    \\  SELECT provider,
    \\         CASE
    \\           WHEN instr(rest, ' ') > 1 THEN substr(rest, 1, instr(rest, ' ') - 1)
    \\           ELSE rest
    \\         END AS operation_id,
    \\         status,
    \\         CASE
    \\           WHEN instr(rest, ' ') > 0 THEN substr(rest, instr(rest, ' ') + 1)
    \\           ELSE ''
    \\         END AS endpoint,
    \\         created_at
    \\  FROM provider_rows
    \\)
    \\SELECT provider,
    \\       operation_id,
    \\       status,
    \\       COALESCE(MAX(endpoint), '') AS endpoint_sample,
    \\       COUNT(*) AS event_count,
    \\       COALESCE(MAX(created_at), '') AS latest_at
    \\FROM route_rows
    \\WHERE (? IS NULL OR provider = ?)
    \\GROUP BY provider, operation_id, status
    \\ORDER BY latest_at DESC, event_count DESC, provider, operation_id, status
    \\LIMIT ?
;

pub fn isKnownTable(table: []const u8) bool {
    const known = [_][]const u8{
        "snapshots",            "provider_raw",               "cloudflare_accounts",       "cloudflare_zones", "cloudflare_dns_records",
        "cloudflare_resources", "cloudflare_inventory_items", "cloudflare_security_items", "hostinger_vps",    "hostinger_metrics",
        "hostinger_resources",  "hostinger_inventory_items",  "caddy_sites",               "caddy_upstreams",  "projects",
        "system_metrics",       "services",                   "sockets",                   "containers",       "audit_events",
        "settings",
    };
    for (known) |name| if (std.mem.eql(u8, table, name)) return true;
    return false;
}

pub fn secretScanSql(surface: SecretScanSurface) []const u8 {
    return switch (surface) {
        .settings_value => "SELECT COUNT(*) FROM settings WHERE instr(COALESCE(value, ''), ?) > 0",
        .snapshots_target => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(target, ''), ?) > 0",
        .snapshots_summary => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(summary, ''), ?) > 0",
        .snapshots_raw_json => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .snapshots_raw_text => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .provider_raw_endpoint => "SELECT COUNT(*) FROM provider_raw WHERE instr(COALESCE(endpoint, ''), ?) > 0",
        .provider_raw_body_json => "SELECT COUNT(*) FROM provider_raw WHERE instr(COALESCE(body_json, ''), ?) > 0",
        .cloudflare_accounts_raw_json => "SELECT COUNT(*) FROM cloudflare_accounts WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_zones_raw_json => "SELECT COUNT(*) FROM cloudflare_zones WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_dns_records_raw_json => "SELECT COUNT(*) FROM cloudflare_dns_records WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_resources_raw_json => "SELECT COUNT(*) FROM cloudflare_resources WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_inventory_items_raw_json => "SELECT COUNT(*) FROM cloudflare_inventory_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_security_items_raw_json => "SELECT COUNT(*) FROM cloudflare_security_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_vps_raw_json => "SELECT COUNT(*) FROM hostinger_vps WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_metrics_raw_json => "SELECT COUNT(*) FROM hostinger_metrics WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_resources_raw_json => "SELECT COUNT(*) FROM hostinger_resources WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_inventory_items_raw_json => "SELECT COUNT(*) FROM hostinger_inventory_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .caddy_sites_raw_block => "SELECT COUNT(*) FROM caddy_sites WHERE instr(COALESCE(raw_block, ''), ?) > 0",
        .projects_raw_text => "SELECT COUNT(*) FROM projects WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .services_raw_text => "SELECT COUNT(*) FROM services WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .sockets_raw_text => "SELECT COUNT(*) FROM sockets WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .containers_raw_text => "SELECT COUNT(*) FROM containers WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .audit_events_detail => "SELECT COUNT(*) FROM audit_events WHERE instr(COALESCE(detail, ''), ?) > 0",
    };
}
