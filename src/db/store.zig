const std = @import("std");
const core_fs = @import("core_fs");
const sqlite = @import("sqlite");
const db_schema = @import("db_schema");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const DbError = error{
    SqliteOpen,
    SqliteExec,
    SqlitePrepare,
    SqliteStep,
    SqliteBind,
};

pub const SnapshotSummary = struct {
    id: i64,
    source: []u8,
    kind: []u8,
    target: []u8,
    status: []u8,
    summary: []u8,
    captured_at: []u8,

    pub fn deinit(self: SnapshotSummary, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.kind);
        allocator.free(self.target);
        allocator.free(self.status);
        allocator.free(self.summary);
        allocator.free(self.captured_at);
    }
};

pub const SnapshotSummaries = struct {
    items: []SnapshotSummary,

    pub fn deinit(self: *SnapshotSummaries, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const NameValueRow = struct {
    name: []u8,
    value: []u8,

    pub fn deinit(self: NameValueRow, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const NameValueRows = struct {
    items: []NameValueRow,

    pub fn deinit(self: *NameValueRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const InventoryFilter = struct {
    provider: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    query: ?[]const u8 = null,
    limit: i64 = 200,
};

pub const InventoryItem = struct {
    provider: []u8,
    kind: []u8,
    resource_id: []u8,
    scope: []u8,
    scope_id: []u8,
    display_name: []u8,
    status: []u8,
    category: []u8,
    domain: []u8,
    username: []u8,
    account_id: []u8,
    zone_id: []u8,
    related_id: []u8,
    flag: []u8,
    created_at_source: []u8,
    updated_at_source: []u8,
    expires_at_source: []u8,
    updated_at: []u8,

    pub fn deinit(self: InventoryItem, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.scope);
        allocator.free(self.scope_id);
        allocator.free(self.display_name);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.domain);
        allocator.free(self.username);
        allocator.free(self.account_id);
        allocator.free(self.zone_id);
        allocator.free(self.related_id);
        allocator.free(self.flag);
        allocator.free(self.created_at_source);
        allocator.free(self.updated_at_source);
        allocator.free(self.expires_at_source);
        allocator.free(self.updated_at);
    }
};

pub const InventoryItems = struct {
    items: []InventoryItem,

    pub fn deinit(self: *InventoryItems, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const InventoryFacet = struct {
    provider: []u8,
    kind: []u8,
    status: []u8,
    category: []u8,
    count: i64,
    domains: i64,
    latest_updated: []u8,

    pub fn deinit(self: InventoryFacet, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.latest_updated);
    }
};

pub const InventoryFacets = struct {
    items: []InventoryFacet,

    pub fn deinit(self: *InventoryFacets, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ProjectDetails = struct {
    name: []u8,
    source: []u8,
    path: []u8,
    host: []u8,
    upstream: []u8,
    service: []u8,
    container: []u8,

    pub fn deinit(self: ProjectDetails, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.source);
        allocator.free(self.path);
        allocator.free(self.host);
        allocator.free(self.upstream);
        allocator.free(self.service);
        allocator.free(self.container);
    }
};

pub const MetricRow = struct {
    metric: []u8,
    value: []u8,
    unit: []u8,
    captured_at: []u8,

    pub fn deinit(self: MetricRow, allocator: Allocator) void {
        allocator.free(self.metric);
        allocator.free(self.value);
        allocator.free(self.unit);
        allocator.free(self.captured_at);
    }
};

pub const MetricRows = struct {
    items: []MetricRow,

    pub fn deinit(self: *MetricRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareAccountRow = struct {
    id: []u8,
    name: []u8,
    account_type: []u8,
    status: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareAccountRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.account_type);
        allocator.free(self.status);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareAccountRows = struct {
    items: []CloudflareAccountRow,

    pub fn deinit(self: *CloudflareAccountRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareZoneRow = struct {
    id: []u8,
    name: []u8,
    account_id: []u8,
    status: []u8,
    paused: []u8,
    zone_type: []u8,
    name_servers: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareZoneRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.account_id);
        allocator.free(self.status);
        allocator.free(self.paused);
        allocator.free(self.zone_type);
        allocator.free(self.name_servers);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareZoneRows = struct {
    items: []CloudflareZoneRow,

    pub fn deinit(self: *CloudflareZoneRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareDnsRecordRow = struct {
    id: []u8,
    zone_id: []u8,
    name: []u8,
    record_type: []u8,
    content: []u8,
    ttl: []u8,
    proxied: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareDnsRecordRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.zone_id);
        allocator.free(self.name);
        allocator.free(self.record_type);
        allocator.free(self.content);
        allocator.free(self.ttl);
        allocator.free(self.proxied);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareDnsRecordRows = struct {
    items: []CloudflareDnsRecordRow,

    pub fn deinit(self: *CloudflareDnsRecordRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareKindCount = struct {
    kind: []u8,
    count: i64,
    latest_updated: []u8,

    pub fn deinit(self: CloudflareKindCount, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.latest_updated);
    }
};

pub const CloudflareKindCounts = struct {
    items: []CloudflareKindCount,

    pub fn deinit(self: *CloudflareKindCounts, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerVpsRow = struct {
    id: []u8,
    name: []u8,
    status: []u8,
    ipv4: []u8,
    plan: []u8,
    updated_at: []u8,

    pub fn deinit(self: HostingerVpsRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.status);
        allocator.free(self.ipv4);
        allocator.free(self.plan);
        allocator.free(self.updated_at);
    }
};

pub const HostingerVpsRows = struct {
    items: []HostingerVpsRow,

    pub fn deinit(self: *HostingerVpsRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerKindCount = struct {
    kind: []u8,
    count: i64,
    latest_updated: []u8,

    pub fn deinit(self: HostingerKindCount, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.latest_updated);
    }
};

pub const HostingerKindCounts = struct {
    items: []HostingerKindCount,

    pub fn deinit(self: *HostingerKindCounts, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerMetricSummary = struct {
    vm_id: []u8,
    metric: []u8,
    count: i64,
    latest_captured: []u8,

    pub fn deinit(self: HostingerMetricSummary, allocator: Allocator) void {
        allocator.free(self.vm_id);
        allocator.free(self.metric);
        allocator.free(self.latest_captured);
    }
};

pub const HostingerMetricSummaries = struct {
    items: []HostingerMetricSummary,

    pub fn deinit(self: *HostingerMetricSummaries, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AuditEvent = struct {
    id: i64,
    action: []u8,
    status: []u8,
    detail: []u8,
    created_at: []u8,

    pub fn deinit(self: AuditEvent, allocator: Allocator) void {
        allocator.free(self.action);
        allocator.free(self.status);
        allocator.free(self.detail);
        allocator.free(self.created_at);
    }
};

pub const AuditEvents = struct {
    items: []AuditEvent,

    pub fn deinit(self: *AuditEvents, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Db = struct {
    handle: *sqlite.sqlite3,

    pub fn open(io: Io, path: []const u8) !Db {
        try core_fs.ensureParentDir(io, path);
        if (path.len >= std.fs.max_path_bytes) return error.NameTooLong;
        var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var handle: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open_v2(@ptrCast(&path_z), &handle, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqliteOpen;
        _ = sqlite.sqlite3_busy_timeout(handle.?, 5000);
        return .{ .handle = handle.? };
    }

    pub fn close(self: *Db) void {
        _ = sqlite.sqlite3_close(self.handle);
    }

    pub fn initSchema(self: *Db) !void {
        try db_schema.apply(self.handle);
    }

    pub fn schemaVersion(self: *Db) !i64 {
        return try db_schema.latestAppliedVersion(self.handle);
    }

    pub fn exec(self: *Db, sql: []const u8) !void {
        var err: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err);
        if (rc != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return DbError.SqliteExec;
        }
    }

    pub fn prepare(self: *Db, sql: []const u8) !*sqlite.sqlite3_stmt {
        var stmt: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(self.handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqlitePrepare;
        return stmt.?;
    }

    pub fn insertSnapshot(self: *Db, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
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

    pub fn insertProviderRaw(self: *Db, provider: []const u8, endpoint: []const u8, status: i64, body: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO provider_raw(provider, endpoint, status, body_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, provider);
        try bindText(stmt, 2, endpoint);
        try bindI64(stmt, 3, status);
        try bindText(stmt, 4, body);
        try stepDone(stmt);
    }

    pub fn insertAudit(self: *Db, action: []const u8, status: []const u8, detail: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO audit_events(action, status, detail) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, action);
        try bindText(stmt, 2, status);
        try bindText(stmt, 3, detail);
        try stepDone(stmt);
    }

    pub fn clear(self: *Db, table: []const u8) !void {
        if (!isKnownTable(table)) return error.InvalidTable;
        var buf: [128]u8 = undefined;
        const sql = try std.fmt.bufPrint(&buf, "DELETE FROM {s}", .{table});
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try stepDone(stmt);
    }

    pub fn countTable(self: *Db, table: []const u8) !i64 {
        if (!isKnownTable(table)) return error.InvalidTable;
        var buf: [160]u8 = undefined;
        const sql = try std.fmt.bufPrint(&buf, "SELECT COUNT(*) FROM {s}", .{table});
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn latestSnapshotId(self: *Db) !i64 {
        const stmt = try self.prepare("SELECT COALESCE(MAX(id), 0) FROM snapshots");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn upsertCloudflareAccount(self: *Db, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
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

    pub fn upsertCloudflareZone(self: *Db, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
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

    pub fn upsertDnsRecord(self: *Db, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
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

    pub fn upsertCloudflareResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, name: ?[]const u8, status: ?[]const u8, resource_type: ?[]const u8, raw: []const u8) !void {
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
        self: *Db,
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
        self: *Db,
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

    pub fn upsertHostingerVps(self: *Db, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
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

    pub fn insertHostingerMetric(self: *Db, vm_id: []const u8, metric: []const u8, value: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO hostinger_metrics(vm_id, metric, value, raw_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, vm_id);
        try bindText(stmt, 2, metric);
        try bindTextOpt(stmt, 3, value);
        try bindText(stmt, 4, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, target: ?[]const u8, name: ?[]const u8, status: ?[]const u8, domain: ?[]const u8, raw: []const u8) !void {
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
        self: *Db,
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

    pub fn upsertCaddySite(self: *Db, host: []const u8, source_path: []const u8, raw_block: ?[]const u8) !void {
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

    pub fn insertCaddyUpstream(self: *Db, host: []const u8, route: []const u8, upstream: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO caddy_upstreams(host, route, upstream) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, host);
        try bindText(stmt, 2, route);
        try bindText(stmt, 3, upstream);
        try stepDone(stmt);
    }

    pub fn upsertProject(self: *Db, name: []const u8, source: []const u8, path: ?[]const u8, host: ?[]const u8, upstream: ?[]const u8, service: ?[]const u8, container: ?[]const u8, raw: ?[]const u8) !void {
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

    pub fn insertSystemMetric(self: *Db, metric: []const u8, value: []const u8, unit: ?[]const u8) !void {
        const stmt = try self.prepare("INSERT INTO system_metrics(metric, value, unit) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, metric);
        try bindText(stmt, 2, value);
        try bindTextOpt(stmt, 3, unit);
        try stepDone(stmt);
    }

    pub fn upsertService(self: *Db, name: []const u8, scope: []const u8, state: ?[]const u8, sub_state: ?[]const u8, description: ?[]const u8, raw: []const u8) !void {
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

    pub fn insertSocket(self: *Db, proto: ?[]const u8, state: ?[]const u8, local_address: ?[]const u8, process: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO sockets(proto, state, local_address, process, raw_text) VALUES (?, ?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, proto);
        try bindTextOpt(stmt, 2, state);
        try bindTextOpt(stmt, 3, local_address);
        try bindTextOpt(stmt, 4, process);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertContainer(self: *Db, name: []const u8, image: ?[]const u8, status: ?[]const u8, ports: ?[]const u8, raw: []const u8) !void {
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

    pub fn writeOverviewCounts(self: *Db, writer: anytype) !void {
        try writer.print("snapshots={d}\n", .{try self.countTable("snapshots")});
        try writer.print("cloudflare_accounts={d}\n", .{try self.countTable("cloudflare_accounts")});
        try writer.print("cloudflare_zones={d}\n", .{try self.countTable("cloudflare_zones")});
        try writer.print("cloudflare_dns_records={d}\n", .{try self.countTable("cloudflare_dns_records")});
        try writer.print("cloudflare_resources={d}\n", .{try self.countTable("cloudflare_resources")});
        try writer.print("cloudflare_inventory_items={d}\n", .{try self.countTable("cloudflare_inventory_items")});
        try writer.print("cloudflare_security_items={d}\n", .{try self.countTable("cloudflare_security_items")});
        try writer.print("hostinger_vps={d}\n", .{try self.countTable("hostinger_vps")});
        try writer.print("hostinger_resources={d}\n", .{try self.countTable("hostinger_resources")});
        try writer.print("hostinger_inventory_items={d}\n", .{try self.countTable("hostinger_inventory_items")});
        try writer.print("caddy_sites={d}\n", .{try self.countTable("caddy_sites")});
        try writer.print("caddy_upstreams={d}\n", .{try self.countTable("caddy_upstreams")});
        try writer.print("projects={d}\n", .{try self.countTable("projects")});
        try writer.print("services={d}\n", .{try self.countTable("services")});
        try writer.print("sockets={d}\n", .{try self.countTable("sockets")});
        try writer.print("containers={d}\n", .{try self.countTable("containers")});
    }

    pub fn recentSnapshots(self: *Db, gpa: Allocator, limit: i64) !SnapshotSummaries {
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

    pub fn snapshotsForSource(self: *Db, gpa: Allocator, source: []const u8, limit: i64) !SnapshotSummaries {
        const stmt = try self.prepare(
            \\SELECT id, source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots WHERE source = ? ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindI64(stmt, 2, limit);
        return try self.snapshotRowsFromStmt(gpa, stmt);
    }

    pub fn projectList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT name, source FROM projects ORDER BY name LIMIT 200");
    }

    pub fn serviceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(state,'') FROM services ORDER BY 1 LIMIT 200");
    }

    pub fn socketList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(local_address,''), COALESCE(process,'') FROM sockets ORDER BY 1 LIMIT 200");
    }

    pub fn containerList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(status,'') FROM containers ORDER BY 1 LIMIT 200");
    }

    pub fn cloudflareResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(resource_type,'') || ' ' || COALESCE(name,''))
            \\FROM cloudflare_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn cloudflareInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM cloudflare_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn cloudflareAccountRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareAccountRows {
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

    pub fn cloudflareZoneRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareZoneRows {
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

    pub fn cloudflareDnsRecordRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
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

    pub fn cloudflareResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareSecurityKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_security_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(name,''))
            \\FROM hostinger_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(username,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM hostinger_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerVpsRows(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsRows {
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

    pub fn hostingerResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerMetricSummaries(self: *Db, gpa: Allocator, limit: i64) !HostingerMetricSummaries {
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

    pub fn inventoryItems(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryItems {
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

    fn cloudflareKindCounts(self: *Db, gpa: Allocator, sql: []const u8, limit: i64) !CloudflareKindCounts {
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

    fn hostingerKindCounts(self: *Db, gpa: Allocator, sql: []const u8, limit: i64) !HostingerKindCounts {
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

    pub fn inventoryFacets(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryFacets {
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

    pub fn caddyUpstreams(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT host, upstream FROM caddy_upstreams ORDER BY host, upstream");
    }

    pub fn recentMetrics(self: *Db, gpa: Allocator, limit: i64) !MetricRows {
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

    pub fn recentAuditEvents(self: *Db, gpa: Allocator, limit: i64) !AuditEvents {
        const stmt = try self.prepare(
            \\SELECT id, action, status, COALESCE(detail,''), created_at
            \\FROM audit_events ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(AuditEvent).empty;
        errdefer deinitAuditEventList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try auditEventFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn projectDetails(self: *Db, gpa: Allocator, name: []const u8) !?ProjectDetails {
        const stmt = try self.prepare(
            \\SELECT name, source, COALESCE(path,''), COALESCE(host,''), COALESCE(upstream,''), COALESCE(service,''), COALESCE(container,'')
            \\FROM projects WHERE name = ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try projectDetailsFromStmt(gpa, stmt);
    }

    fn nameValueRows(self: *Db, gpa: Allocator, sql: []const u8) !NameValueRows {
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

    fn snapshotRowsFromStmt(self: *Db, gpa: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummaries {
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

    pub fn writeSnapshotsAfter(self: *Db, writer: anytype, after_id: i64) !void {
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

fn bindI64(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: i64) !void {
    if (sqlite.sqlite3_bind_int64(stmt, idx, value) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindI64Opt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?i64) !void {
    if (value) |v| try bindI64(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindBoolOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?bool) !void {
    if (value) |v| try bindI64(stmt, idx, if (v) 1 else 0) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) {
        return DbError.SqliteBind;
    }
}

fn bindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |v| try bindText(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn stepDone(stmt: *sqlite.sqlite3_stmt) !void {
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return DbError.SqliteStep;
}

fn deinitSnapshotList(rows: *std.ArrayList(SnapshotSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitNameValueList(rows: *std.ArrayList(NameValueRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitInventoryItemList(rows: *std.ArrayList(InventoryItem), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitInventoryFacetList(rows: *std.ArrayList(InventoryFacet), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitMetricList(rows: *std.ArrayList(MetricRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareAccountRowList(rows: *std.ArrayList(CloudflareAccountRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareZoneRowList(rows: *std.ArrayList(CloudflareZoneRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareDnsRecordRowList(rows: *std.ArrayList(CloudflareDnsRecordRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareKindCountList(rows: *std.ArrayList(CloudflareKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerVpsRowList(rows: *std.ArrayList(HostingerVpsRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerKindCountList(rows: *std.ArrayList(HostingerKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerMetricSummaryList(rows: *std.ArrayList(HostingerMetricSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitAuditEventList(rows: *std.ArrayList(AuditEvent), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn snapshotSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummary {
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

fn auditEventFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !AuditEvent {
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

fn metricRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !MetricRow {
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

fn cloudflareAccountRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareAccountRow {
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

fn cloudflareZoneRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareZoneRow {
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

fn cloudflareDnsRecordRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareDnsRecordRow {
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

fn cloudflareKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareKindCount {
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

fn hostingerVpsRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerVpsRow {
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

fn hostingerKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerKindCount {
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

fn hostingerMetricSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerMetricSummary {
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

fn nameValueRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !NameValueRow {
    const name = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(name);
    const value = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(value);
    return .{
        .name = name,
        .value = value,
    };
}

fn inventoryItemFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryItem {
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

fn inventoryFacetFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryFacet {
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

fn projectDetailsFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProjectDetails {
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

fn dupeColumn(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, idx: c_int) ![]u8 {
    return try allocator.dupe(u8, columnText(stmt, idx) orelse "");
}

fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

pub fn columnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(stmt, idx) == sqlite.SQLITE_NULL) return null;
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

fn isKnownTable(table: []const u8) bool {
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

test "sqlite schema initializes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-store.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try std.testing.expectEqual(db_schema.latest_version, try db.schemaVersion());
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("snapshots"));
}

test "audit events can be inserted and queried as a read model" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-audit.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertAudit("caddy.diff", "dry_run", "rendered only");
    var rows = try db.recentAuditEvents(allocator, 10);
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("caddy.diff", rows.items[0].action);
    try std.testing.expectEqualStrings("dry_run", rows.items[0].status);
    try std.testing.expectEqualStrings("rendered only", rows.items[0].detail);
}

test "provider inventory read model joins and filters typed inventory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    var all = try db.inventoryItems(allocator, .{});
    defer all.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), all.items.len);

    var cloudflare = try db.inventoryItems(allocator, .{ .provider = "cloudflare" });
    defer cloudflare.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), cloudflare.items.len);
    try std.testing.expectEqualStrings("cloudflare", cloudflare.items[0].provider);
    try std.testing.expectEqualStrings("zone", cloudflare.items[0].scope);
    try std.testing.expectEqualStrings("zone-1", cloudflare.items[0].scope_id);

    var query = try db.inventoryItems(allocator, .{ .query = "u123" });
    defer query.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), query.items.len);
    try std.testing.expectEqualStrings("hostinger", query.items[0].provider);
    try std.testing.expectEqualStrings("u123", query.items[0].username);

    var facets = try db.inventoryFacets(allocator, .{ .domain = "plosca.ru" });
    defer facets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), facets.items.len);
    try std.testing.expectEqualStrings("cloudflare", facets.items[0].provider);
    try std.testing.expectEqualStrings("dns-records", facets.items[0].kind);
    try std.testing.expectEqualStrings("active", facets.items[0].status);
    try std.testing.expectEqualStrings("A", facets.items[0].category);
    try std.testing.expectEqual(@as(i64, 1), facets.items[0].count);
    try std.testing.expectEqual(@as(i64, 1), facets.items[0].domains);

    var hostinger_facets = try db.inventoryFacets(allocator, .{ .provider = "hostinger", .query = "u123" });
    defer hostinger_facets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), hostinger_facets.items.len);
    try std.testing.expectEqualStrings("hostinger-websites", hostinger_facets.items[0].kind);
    try std.testing.expectEqualStrings("enabled", hostinger_facets.items[0].status);
    try std.testing.expectEqualStrings("main", hostinger_facets.items[0].category);
}
