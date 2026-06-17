const std = @import("std");
const sqlite = @import("sqlite");

pub const SchemaError = error{
    SqliteOpen,
    SqliteExec,
    SqlitePrepare,
    SqliteStep,
    SqliteBind,
};

pub const Migration = struct {
    version: i64,
    name: []const u8,
    sql: []const u8,
};

pub const migrations = [_]Migration{
    .{
        .version = 1,
        .name = "initial_poc_schema",
        .sql =
        \\CREATE TABLE IF NOT EXISTS settings (
        \\  key TEXT PRIMARY KEY,
        \\  value TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS snapshots (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  source TEXT NOT NULL,
        \\  kind TEXT NOT NULL,
        \\  target TEXT,
        \\  status TEXT NOT NULL,
        \\  summary TEXT,
        \\  raw_json TEXT,
        \\  raw_text TEXT,
        \\  captured_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS provider_raw (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  provider TEXT NOT NULL,
        \\  endpoint TEXT NOT NULL,
        \\  status INTEGER,
        \\  body_json TEXT,
        \\  captured_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS cloudflare_accounts (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT,
        \\  type TEXT,
        \\  status TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS cloudflare_zones (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT,
        \\  account_id TEXT,
        \\  status TEXT,
        \\  paused INTEGER,
        \\  type TEXT,
        \\  name_servers TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS cloudflare_dns_records (
        \\  id TEXT PRIMARY KEY,
        \\  zone_id TEXT,
        \\  name TEXT,
        \\  type TEXT,
        \\  content TEXT,
        \\  ttl INTEGER,
        \\  proxied INTEGER,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS hostinger_vps (
        \\  id TEXT PRIMARY KEY,
        \\  name TEXT,
        \\  status TEXT,
        \\  ipv4 TEXT,
        \\  plan TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS hostinger_metrics (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  vm_id TEXT,
        \\  metric TEXT,
        \\  value TEXT,
        \\  raw_json TEXT,
        \\  captured_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS caddy_sites (
        \\  host TEXT PRIMARY KEY,
        \\  source_path TEXT,
        \\  raw_block TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS caddy_upstreams (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  host TEXT,
        \\  route TEXT,
        \\  upstream TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS projects (
        \\  name TEXT PRIMARY KEY,
        \\  source TEXT,
        \\  path TEXT,
        \\  host TEXT,
        \\  upstream TEXT,
        \\  service TEXT,
        \\  container TEXT,
        \\  raw_text TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS system_metrics (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  metric TEXT NOT NULL,
        \\  value TEXT,
        \\  unit TEXT,
        \\  captured_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS services (
        \\  name TEXT PRIMARY KEY,
        \\  scope TEXT,
        \\  state TEXT,
        \\  sub_state TEXT,
        \\  description TEXT,
        \\  raw_text TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS sockets (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  proto TEXT,
        \\  state TEXT,
        \\  local_address TEXT,
        \\  process TEXT,
        \\  raw_text TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS containers (
        \\  name TEXT PRIMARY KEY,
        \\  image TEXT,
        \\  status TEXT,
        \\  ports TEXT,
        \\  raw_text TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS audit_events (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  action TEXT NOT NULL,
        \\  status TEXT NOT NULL,
        \\  detail TEXT,
        \\  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        ,
    },
    .{
        .version = 2,
        .name = "read_model_indexes",
        .sql =
        \\CREATE INDEX IF NOT EXISTS idx_snapshots_source_id ON snapshots(source, id DESC);
        \\CREATE INDEX IF NOT EXISTS idx_provider_raw_provider_id ON provider_raw(provider, id DESC);
        \\CREATE INDEX IF NOT EXISTS idx_audit_events_action_id ON audit_events(action, id DESC);
        ,
    },
    .{
        .version = 3,
        .name = "hostinger_resource_inventory",
        .sql =
        \\CREATE TABLE IF NOT EXISTS hostinger_resources (
        \\  key TEXT PRIMARY KEY,
        \\  kind TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  target TEXT,
        \\  name TEXT,
        \\  status TEXT,
        \\  domain TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_hostinger_resources_kind ON hostinger_resources(kind, updated_at DESC);
        ,
    },
    .{
        .version = 4,
        .name = "cloudflare_resource_inventory",
        .sql =
        \\CREATE TABLE IF NOT EXISTS cloudflare_resources (
        \\  key TEXT PRIMARY KEY,
        \\  kind TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  scope TEXT,
        \\  scope_id TEXT,
        \\  name TEXT,
        \\  status TEXT,
        \\  resource_type TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_resources_kind ON cloudflare_resources(kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_resources_scope ON cloudflare_resources(scope, scope_id, updated_at DESC);
        ,
    },
    .{
        .version = 5,
        .name = "hostinger_typed_inventory",
        .sql =
        \\CREATE TABLE IF NOT EXISTS hostinger_inventory_items (
        \\  key TEXT PRIMARY KEY,
        \\  kind TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  display_name TEXT,
        \\  status TEXT,
        \\  category TEXT,
        \\  domain TEXT,
        \\  username TEXT,
        \\  related_id TEXT,
        \\  flag TEXT,
        \\  created_at_source TEXT,
        \\  updated_at_source TEXT,
        \\  expires_at_source TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_hostinger_inventory_kind ON hostinger_inventory_items(kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_hostinger_inventory_domain ON hostinger_inventory_items(domain, kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_hostinger_inventory_status ON hostinger_inventory_items(status, kind, updated_at DESC);
        ,
    },
};

pub const latest_version = migrations[migrations.len - 1].version;

pub fn apply(handle: *sqlite.sqlite3) !void {
    try exec(handle,
        \\PRAGMA journal_mode=WAL;
        \\PRAGMA synchronous=NORMAL;
        \\CREATE TABLE IF NOT EXISTS schema_meta (
        \\  version INTEGER PRIMARY KEY,
        \\  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
    );

    for (migrations) |migration| {
        if (try isApplied(handle, migration.version)) continue;
        try exec(handle, "BEGIN IMMEDIATE");
        exec(handle, migration.sql) catch |err| {
            _ = exec(handle, "ROLLBACK") catch {};
            return err;
        };
        recordApplied(handle, migration.version) catch |err| {
            _ = exec(handle, "ROLLBACK") catch {};
            return err;
        };
        try exec(handle, "COMMIT");
    }
}

pub fn latestAppliedVersion(handle: *sqlite.sqlite3) !i64 {
    const stmt = try prepare(handle, "SELECT COALESCE(MAX(version), 0) FROM schema_meta");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return SchemaError.SqliteStep;
    return sqlite.sqlite3_column_int64(stmt, 0);
}

fn isApplied(handle: *sqlite.sqlite3, version: i64) !bool {
    const stmt = try prepare(handle, "SELECT 1 FROM schema_meta WHERE version = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, version);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_ROW) return true;
    if (rc == sqlite.SQLITE_DONE) return false;
    return SchemaError.SqliteStep;
}

fn recordApplied(handle: *sqlite.sqlite3, version: i64) !void {
    const stmt = try prepare(handle, "INSERT OR IGNORE INTO schema_meta(version) VALUES (?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, version);
    try stepDone(stmt);
}

fn exec(handle: *sqlite.sqlite3, sql: []const u8) !void {
    var err: [*c]u8 = null;
    const rc = sqlite.sqlite3_exec(handle, @ptrCast(sql.ptr), null, null, &err);
    if (rc != sqlite.SQLITE_OK) {
        if (err != null) sqlite.sqlite3_free(err);
        return SchemaError.SqliteExec;
    }
}

fn prepare(handle: *sqlite.sqlite3, sql: []const u8) !*sqlite.sqlite3_stmt {
    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
    if (rc != sqlite.SQLITE_OK) return SchemaError.SqlitePrepare;
    return stmt.?;
}

fn bindI64(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: i64) !void {
    if (sqlite.sqlite3_bind_int64(stmt, idx, value) != sqlite.SQLITE_OK) return SchemaError.SqliteBind;
}

fn stepDone(stmt: *sqlite.sqlite3_stmt) !void {
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return SchemaError.SqliteStep;
}

test "applies migrations idempotently" {
    var handle: ?*sqlite.sqlite3 = null;
    if (sqlite.sqlite3_open_v2(":memory:", &handle, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null) != sqlite.SQLITE_OK) {
        return SchemaError.SqliteOpen;
    }
    defer _ = sqlite.sqlite3_close(handle.?);

    try apply(handle.?);
    try apply(handle.?);

    try std.testing.expectEqual(latest_version, try latestAppliedVersion(handle.?));
    try std.testing.expect(try tableExists(handle.?, "snapshots"));
    try std.testing.expect(try tableExists(handle.?, "audit_events"));
}

fn tableExists(handle: *sqlite.sqlite3, table: []const u8) !bool {
    const stmt = try prepare(handle, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_text(stmt, 1, @ptrCast(table.ptr), @intCast(table.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return SchemaError.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_ROW) return true;
    if (rc == sqlite.SQLITE_DONE) return false;
    return SchemaError.SqliteStep;
}
