const std = @import("std");
const sqlite = @import("sqlite");
const models = @import("models.zig");

const Allocator = std.mem.Allocator;
const DbError = models.DbError;
const NameValueRow = models.NameValueRow;
const NameValueRows = models.NameValueRows;
const TopologyRow = models.TopologyRow;
const TopologyRows = models.TopologyRows;
const CloudflareAccountRow = models.CloudflareAccountRow;
const CloudflareAccountRows = models.CloudflareAccountRows;
const CloudflareZoneRow = models.CloudflareZoneRow;
const CloudflareZoneRows = models.CloudflareZoneRows;
const CloudflareDnsRecordRow = models.CloudflareDnsRecordRow;
const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
const ContainerRow = models.ContainerRow;
const ContainerRows = models.ContainerRows;
const HostingerVpsRow = models.HostingerVpsRow;
const HostingerVpsRows = models.HostingerVpsRows;

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

pub fn deinitNameValueList(rows: *std.ArrayList(NameValueRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

pub fn deinitTopologyRowList(rows: *std.ArrayList(TopologyRow), allocator: Allocator) void {
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

pub fn deinitHostingerVpsRowList(rows: *std.ArrayList(HostingerVpsRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
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

pub fn isKnownTable(table: []const u8) bool {
    const known = [_][]const u8{
        "snapshots",            "provider_raw",               "cloudflare_accounts",       "cloudflare_zones", "cloudflare_dns_records",
        "cloudflare_resources", "cloudflare_inventory_items", "cloudflare_security_items", "hostinger_vps",    "hostinger_metrics",
        "hostinger_resources",  "hostinger_inventory_items",  "caddy_sites",               "caddy_upstreams",  "projects",
        "system_metrics",       "services",                   "sockets",                   "containers",       "audit_events",
        "settings",             "mutation_requests",
    };
    for (known) |name| if (std.mem.eql(u8, table, name)) return true;
    return false;
}

