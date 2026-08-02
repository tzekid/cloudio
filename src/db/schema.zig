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
    .{
        .version = 6,
        .name = "cloudflare_typed_inventory",
        .sql =
        \\CREATE TABLE IF NOT EXISTS cloudflare_inventory_items (
        \\  key TEXT PRIMARY KEY,
        \\  kind TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  scope TEXT,
        \\  scope_id TEXT,
        \\  display_name TEXT,
        \\  status TEXT,
        \\  category TEXT,
        \\  domain TEXT,
        \\  account_id TEXT,
        \\  zone_id TEXT,
        \\  related_id TEXT,
        \\  flag TEXT,
        \\  created_at_source TEXT,
        \\  updated_at_source TEXT,
        \\  expires_at_source TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_inventory_kind ON cloudflare_inventory_items(kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_inventory_scope ON cloudflare_inventory_items(scope, scope_id, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_inventory_domain ON cloudflare_inventory_items(domain, kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_inventory_status ON cloudflare_inventory_items(status, kind, updated_at DESC);
        ,
    },
    .{
        .version = 7,
        .name = "cloudflare_security_typed_inventory",
        .sql =
        \\CREATE TABLE IF NOT EXISTS cloudflare_security_items (
        \\  key TEXT PRIMARY KEY,
        \\  kind TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  scope TEXT,
        \\  scope_id TEXT,
        \\  display_name TEXT,
        \\  status TEXT,
        \\  category TEXT,
        \\  severity TEXT,
        \\  action TEXT,
        \\  domain TEXT,
        \\  account_id TEXT,
        \\  zone_id TEXT,
        \\  related_id TEXT,
        \\  flag TEXT,
        \\  created_at_source TEXT,
        \\  updated_at_source TEXT,
        \\  expires_at_source TEXT,
        \\  raw_json TEXT,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_security_kind ON cloudflare_security_items(kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_security_scope ON cloudflare_security_items(scope, scope_id, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_security_domain ON cloudflare_security_items(domain, kind, updated_at DESC);
        \\CREATE INDEX IF NOT EXISTS idx_cloudflare_security_severity ON cloudflare_security_items(severity, kind, updated_at DESC);
        ,
    },
    .{
        .version = 8,
        .name = "platform_apps_and_writes",
        .sql =
        \\CREATE TABLE IF NOT EXISTS apps (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL UNIQUE,
        \\  repo_url TEXT,
        \\  workdir TEXT,
        \\  toolchain TEXT,
        \\  port INTEGER,
        \\  alias_host TEXT,
        \\  env_json TEXT,
        \\  status TEXT NOT NULL DEFAULT 'registered',
        \\  current_deploy_id INTEGER,
        \\  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS deploys (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  app_id INTEGER NOT NULL,
        \\  git_sha TEXT,
        \\  status TEXT NOT NULL DEFAULT 'pending',
        \\  log_path TEXT,
        \\  detail TEXT,
        \\  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  finished_at TEXT
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_deploys_app_id ON deploys(app_id, id DESC);
        \\CREATE TABLE IF NOT EXISTS caddy_desired_routes (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  host TEXT NOT NULL UNIQUE,
        \\  upstream TEXT,
        \\  kind TEXT NOT NULL DEFAULT 'manual',
        \\  extra_directives TEXT,
        \\  raw_block TEXT,
        \\  enabled INTEGER NOT NULL DEFAULT 1,
        \\  app_id INTEGER,
        \\  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS audit_actions (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  kind TEXT NOT NULL,
        \\  target TEXT,
        \\  request_json TEXT,
        \\  result TEXT NOT NULL DEFAULT 'pending',
        \\  detail TEXT,
        \\  actor TEXT,
        \\  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_audit_actions_kind_id ON audit_actions(kind, id DESC);
        ,
    },
    .{
        .version = 9,
        .name = "storage_lifecycle_indexes",
        .sql =
        \\CREATE INDEX IF NOT EXISTS idx_snapshots_captured_at ON snapshots(captured_at, id);
        \\CREATE INDEX IF NOT EXISTS idx_provider_raw_captured_at ON provider_raw(captured_at, id);
        \\CREATE INDEX IF NOT EXISTS idx_hostinger_metrics_captured_at ON hostinger_metrics(captured_at, id);
        \\CREATE INDEX IF NOT EXISTS idx_system_metrics_captured_at ON system_metrics(captured_at, id);
        ,
    },
    .{
        .version = 10,
        .name = "write_safety_and_deploy_locks",
        .sql =
        \\ALTER TABLE audit_actions ADD COLUMN idempotency_key TEXT;
        \\CREATE INDEX IF NOT EXISTS idx_audit_actions_idempotency_key ON audit_actions(idempotency_key);
        \\CREATE TABLE IF NOT EXISTS mutation_requests (
        \\  idempotency_key TEXT PRIMARY KEY,
        \\  request_hash TEXT NOT NULL,
        \\  method TEXT NOT NULL,
        \\  target TEXT NOT NULL,
        \\  actor TEXT NOT NULL,
        \\  state TEXT NOT NULL DEFAULT 'running',
        \\  http_status INTEGER,
        \\  response_json TEXT,
        \\  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  completed_at TEXT
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_mutation_requests_created_at ON mutation_requests(created_at);
        \\CREATE TABLE IF NOT EXISTS app_operation_locks (
        \\  app_id INTEGER PRIMARY KEY,
        \\  operation TEXT NOT NULL,
        \\  acquired_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE UNIQUE INDEX IF NOT EXISTS idx_apps_port_unique ON apps(port);
        ,
    },
    .{
        .version = 11,
        .name = "topology_change_history",
        .sql =
        \\CREATE TABLE IF NOT EXISTS topology_state (
        \\  resource_key TEXT PRIMARY KEY,
        \\  status TEXT NOT NULL,
        \\  fingerprint TEXT NOT NULL,
        \\  observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE TABLE IF NOT EXISTS topology_changes (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  resource_key TEXT NOT NULL,
        \\  change_type TEXT NOT NULL,
        \\  previous_status TEXT,
        \\  current_status TEXT,
        \\  previous_fingerprint TEXT,
        \\  current_fingerprint TEXT,
        \\  observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_topology_changes_observed_at ON topology_changes(observed_at, id);
        \\CREATE INDEX IF NOT EXISTS idx_topology_changes_resource_key ON topology_changes(resource_key, id DESC);
        ,
    },
    .{
        .version = 12,
        .name = "passkey_authentication",
        .sql =
        \\CREATE TABLE IF NOT EXISTS auth_users (
        \\  id TEXT PRIMARY KEY,
        \\  display_name TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS auth_credentials (
        \\  credential_id TEXT PRIMARY KEY,
        \\  user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
        \\  public_key TEXT NOT NULL,
        \\  algorithm INTEGER NOT NULL,
        \\  sign_count INTEGER NOT NULL DEFAULT 0,
        \\  transports TEXT NOT NULL DEFAULT '',
        \\  aaguid TEXT NOT NULL DEFAULT '',
        \\  backup_eligible INTEGER NOT NULL DEFAULT 0,
        \\  backup_state INTEGER NOT NULL DEFAULT 0,
        \\  label TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  last_used_at INTEGER,
        \\  revoked_at INTEGER
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_auth_credentials_user_active
        \\  ON auth_credentials(user_id, revoked_at);
        \\CREATE TABLE IF NOT EXISTS auth_challenges (
        \\  id TEXT PRIMARY KEY,
        \\  purpose TEXT NOT NULL,
        \\  challenge TEXT NOT NULL UNIQUE,
        \\  user_id TEXT,
        \\  binding_hash TEXT,
        \\  expires_at INTEGER NOT NULL,
        \\  used_at INTEGER,
        \\  created_at INTEGER NOT NULL
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_auth_challenges_expiry
        \\  ON auth_challenges(expires_at, used_at);
        \\CREATE TABLE IF NOT EXISTS auth_sessions (
        \\  token_hash TEXT PRIMARY KEY,
        \\  user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
        \\  csrf_token TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  expires_at INTEGER NOT NULL,
        \\  last_seen_at INTEGER NOT NULL,
        \\  revoked_at INTEGER
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_auth_sessions_expiry
        \\  ON auth_sessions(expires_at, revoked_at);
        \\CREATE TABLE IF NOT EXISTS auth_bootstrap (
        \\  id INTEGER PRIMARY KEY CHECK (id = 1),
        \\  token_hash TEXT NOT NULL,
        \\  expires_at INTEGER NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  consumed_at INTEGER
        \\);
        ,
    },
    .{
        .version = 13,
        .name = "nob_v1",
        .sql =
        \\CREATE TABLE managed_projects (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  declared_id TEXT,
        \\  display_name TEXT NOT NULL,
        \\  kind TEXT NOT NULL,
        \\  root_path TEXT NOT NULL UNIQUE,
        \\  manifest_path TEXT,
        \\  manifest_sha256 TEXT,
        \\  trusted_manifest_sha256 TEXT,
        \\  manifest_json TEXT,
        \\  discovery_state TEXT NOT NULL,
        \\  trust_state TEXT NOT NULL DEFAULT 'discovered',
        \\  status TEXT NOT NULL DEFAULT 'unknown',
        \\  status_summary TEXT,
        \\  repository_kind TEXT,
        \\  repository_identity TEXT,
        \\  head_revision TEXT,
        \\  source_fingerprint TEXT,
        \\  source_dirty INTEGER,
        \\  protocol_major INTEGER,
        \\  protocol_minor INTEGER,
        \\  runner_state TEXT NOT NULL DEFAULT 'not-built',
        \\  runner_path TEXT,
        \\  runner_sha256 TEXT,
        \\  runner_detail TEXT,
        \\  trusted_by TEXT,
        \\  trusted_at INTEGER,
        \\  last_seen_scan_id TEXT,
        \\  last_seen_at INTEGER NOT NULL,
        \\  last_observed_at INTEGER,
        \\  created_at INTEGER NOT NULL,
        \\  updated_at INTEGER NOT NULL
        \\);
        \\CREATE INDEX idx_managed_projects_declared_id
        \\  ON managed_projects(declared_id);
        \\CREATE INDEX idx_managed_projects_state
        \\  ON managed_projects(trust_state, discovery_state, status);
        \\CREATE TABLE systemd_units (
        \\  scope TEXT NOT NULL,
        \\  unit TEXT NOT NULL,
        \\  load_state TEXT,
        \\  active_state TEXT,
        \\  sub_state TEXT,
        \\  unit_file_state TEXT,
        \\  description TEXT,
        \\  fragment_path TEXT,
        \\  main_pid INTEGER,
        \\  raw_text TEXT,
        \\  observed_at INTEGER NOT NULL,
        \\  PRIMARY KEY (scope, unit)
        \\);
        \\CREATE INDEX idx_systemd_units_state
        \\  ON systemd_units(scope, active_state, sub_state);
        \\CREATE TABLE project_resources (
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  resource_id TEXT NOT NULL,
        \\  kind TEXT NOT NULL,
        \\  label TEXT NOT NULL,
        \\  ownership TEXT NOT NULL,
        \\  controls_json TEXT NOT NULL,
        \\  declaration_json TEXT NOT NULL,
        \\  runner_observation_json TEXT,
        \\  cloudio_observation_json TEXT,
        \\  effective_status TEXT NOT NULL DEFAULT 'unknown',
        \\  status_summary TEXT,
        \\  observed_at INTEGER,
        \\  PRIMARY KEY (project_id, resource_id)
        \\);
        \\CREATE INDEX idx_project_resources_kind_status
        \\  ON project_resources(kind, effective_status);
        \\CREATE TABLE project_actions (
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  action_id TEXT NOT NULL,
        \\  label TEXT NOT NULL,
        \\  effect TEXT NOT NULL,
        \\  confirmation TEXT NOT NULL,
        \\  declaration_json TEXT NOT NULL,
        \\  available INTEGER NOT NULL DEFAULT 0,
        \\  unavailable_reason TEXT,
        \\  described_at INTEGER,
        \\  PRIMARY KEY (project_id, action_id)
        \\);
        \\CREATE TABLE project_secret_bindings (
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  secret_id TEXT NOT NULL,
        \\  source_kind TEXT NOT NULL,
        \\  source_ref TEXT NOT NULL,
        \\  present INTEGER NOT NULL DEFAULT 0,
        \\  bound_by TEXT NOT NULL,
        \\  bound_at INTEGER NOT NULL,
        \\  checked_at INTEGER,
        \\  PRIMARY KEY (project_id, secret_id)
        \\);
        \\CREATE TABLE project_plans (
        \\  id TEXT PRIMARY KEY,
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  action_id TEXT NOT NULL,
        \\  resource_id TEXT,
        \\  input_json TEXT NOT NULL,
        \\  plan_json TEXT NOT NULL,
        \\  plan_sha256 TEXT NOT NULL,
        \\  manifest_sha256 TEXT NOT NULL,
        \\  source_fingerprint TEXT,
        \\  effect TEXT NOT NULL,
        \\  confirmation TEXT NOT NULL,
        \\  state TEXT NOT NULL DEFAULT 'ready',
        \\  requested_by TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  expires_at INTEGER NOT NULL,
        \\  consumed_at INTEGER
        \\);
        \\CREATE INDEX idx_project_plans_expiry
        \\  ON project_plans(state, expires_at);
        \\CREATE TABLE project_operations (
        \\  id TEXT PRIMARY KEY,
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  plan_id TEXT REFERENCES project_plans(id),
        \\  action_id TEXT NOT NULL,
        \\  resource_id TEXT,
        \\  state TEXT NOT NULL DEFAULT 'queued',
        \\  outcome TEXT,
        \\  effect TEXT NOT NULL,
        \\  requested_by TEXT NOT NULL,
        \\  idempotency_key TEXT,
        \\  runner_path TEXT,
        \\  log_path TEXT,
        \\  stderr_path TEXT,
        \\  summary TEXT,
        \\  error_code TEXT,
        \\  queued_at INTEGER NOT NULL,
        \\  started_at INTEGER,
        \\  finished_at INTEGER,
        \\  cancel_requested_at INTEGER,
        \\  heartbeat_at INTEGER
        \\);
        \\CREATE INDEX idx_project_operations_project_time
        \\  ON project_operations(project_id, queued_at DESC);
        \\CREATE INDEX idx_project_operations_queue
        \\  ON project_operations(state, queued_at);
        \\CREATE TABLE project_operation_events (
        \\  operation_id TEXT NOT NULL REFERENCES project_operations(id) ON DELETE CASCADE,
        \\  seq INTEGER NOT NULL,
        \\  event_type TEXT NOT NULL,
        \\  level TEXT,
        \\  payload_json TEXT NOT NULL,
        \\  received_at INTEGER NOT NULL,
        \\  PRIMARY KEY (operation_id, seq)
        \\);
        \\CREATE TABLE project_artifacts (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  operation_id TEXT NOT NULL REFERENCES project_operations(id) ON DELETE CASCADE,
        \\  project_id INTEGER NOT NULL REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  resource_id TEXT,
        \\  artifact_id TEXT NOT NULL,
        \\  role TEXT NOT NULL,
        \\  path TEXT,
        \\  sha256 TEXT NOT NULL,
        \\  size_bytes INTEGER,
        \\  metadata_json TEXT,
        \\  created_at INTEGER NOT NULL,
        \\  UNIQUE (operation_id, artifact_id)
        \\);
        \\CREATE TABLE project_operation_locks (
        \\  project_id INTEGER PRIMARY KEY REFERENCES managed_projects(id) ON DELETE CASCADE,
        \\  operation_id TEXT NOT NULL UNIQUE REFERENCES project_operations(id) ON DELETE CASCADE,
        \\  acquired_at INTEGER NOT NULL
        \\);
        ,
    },
    .{
        .version = 14,
        .name = "nob_run_bindings",
        .sql =
        \\ALTER TABLE project_plans ADD COLUMN runner_sha256 TEXT;
        \\ALTER TABLE project_plans ADD COLUMN source_revision TEXT;
        \\ALTER TABLE project_plans ADD COLUMN source_dirty INTEGER;
        \\ALTER TABLE project_operations ADD COLUMN manifest_sha256 TEXT;
        \\ALTER TABLE project_operations ADD COLUMN source_fingerprint TEXT;
        \\ALTER TABLE project_operations ADD COLUMN runner_sha256 TEXT;
        \\ALTER TABLE project_operations ADD COLUMN plan_sha256 TEXT;
        \\CREATE UNIQUE INDEX idx_project_operations_idempotency
        \\  ON project_operations(project_id, idempotency_key)
        \\  WHERE idempotency_key IS NOT NULL;
        \\CREATE TABLE project_broker_authorizations (
        \\  operation_id TEXT NOT NULL REFERENCES project_operations(id) ON DELETE CASCADE,
        \\  authorization_id TEXT NOT NULL,
        \\  capability TEXT NOT NULL,
        \\  resource_id TEXT NOT NULL,
        \\  operation TEXT NOT NULL,
        \\  metadata_json TEXT,
        \\  used_at INTEGER,
        \\  PRIMARY KEY (operation_id, authorization_id)
        \\);
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
    try std.testing.expect(try tableExists(handle.?, "cloudflare_security_items"));
    try std.testing.expect(try tableExists(handle.?, "apps"));
    try std.testing.expect(try tableExists(handle.?, "auth_credentials"));
    try std.testing.expect(try tableExists(handle.?, "auth_sessions"));
    try std.testing.expect(try tableExists(handle.?, "deploys"));
    try std.testing.expect(try tableExists(handle.?, "caddy_desired_routes"));
    try std.testing.expect(try tableExists(handle.?, "audit_actions"));
    try std.testing.expect(try tableExists(handle.?, "mutation_requests"));
    try std.testing.expect(try tableExists(handle.?, "app_operation_locks"));
    try std.testing.expect(try tableExists(handle.?, "topology_state"));
    try std.testing.expect(try tableExists(handle.?, "topology_changes"));
    try std.testing.expect(try tableExists(handle.?, "managed_projects"));
    try std.testing.expect(try tableExists(handle.?, "project_resources"));
    try std.testing.expect(try tableExists(handle.?, "project_actions"));
    try std.testing.expect(try tableExists(handle.?, "project_plans"));
    try std.testing.expect(try tableExists(handle.?, "project_operations"));
    try std.testing.expect(try tableExists(handle.?, "project_operation_events"));
    try std.testing.expect(try tableExists(handle.?, "project_artifacts"));
    try std.testing.expect(try tableExists(handle.?, "project_operation_locks"));
    try std.testing.expect(try tableExists(handle.?, "project_broker_authorizations"));
    try std.testing.expect(try tableExists(handle.?, "systemd_units"));
    try std.testing.expect(try indexExists(handle.?, "idx_snapshots_captured_at"));
    try std.testing.expect(try indexExists(handle.?, "idx_provider_raw_captured_at"));
    try std.testing.expect(try indexExists(handle.?, "idx_audit_actions_idempotency_key"));
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

fn indexExists(handle: *sqlite.sqlite3, index: []const u8) !bool {
    const stmt = try prepare(handle, "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_text(stmt, 1, @ptrCast(index.ptr), @intCast(index.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return SchemaError.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_ROW) return true;
    if (rc == sqlite.SQLITE_DONE) return false;
    return SchemaError.SqliteStep;
}
