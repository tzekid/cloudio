//! Shared write-action contract and normalized audit read model.
const std = @import("std");
const sqlite = @import("sqlite");
const core_json = @import("core_json");
const core_redact = @import("core_redact");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const WriteError = error{ SqliteBind, SqliteStep };

pub const Metadata = struct {
    actor: []const u8 = "platform",
    idempotency_key: ?[]const u8 = null,
};

pub const Result = enum {
    ok,
    err,

    pub fn text(self: Result) []const u8 {
        return switch (self) {
            .ok => "ok",
            .err => "error",
        };
    }
};

/// Record an executed write action. `request_json` is redacted before storage.
/// Returns the audit_actions row id.
pub fn record(gpa: Allocator, db: *Db, kind: []const u8, target: ?[]const u8, request_json: ?[]const u8, result: Result, detail: ?[]const u8) !i64 {
    return recordWithMetadata(gpa, db, .{}, kind, target, request_json, result, detail);
}

/// Record an executed write with request-scoped actor and idempotency
/// metadata. Callers outside an HTTP request can use `record`, which records
/// the actor as `platform`.
pub fn recordWithMetadata(gpa: Allocator, db: *Db, metadata: Metadata, kind: []const u8, target: ?[]const u8, request_json: ?[]const u8, result: Result, detail: ?[]const u8) !i64 {
    const redacted_request: ?[]u8 = if (request_json) |raw| try core_redact.secrets(gpa, raw) else null;
    defer if (redacted_request) |r| gpa.free(r);
    const redacted_detail: ?[]u8 = if (detail) |raw| try core_redact.secrets(gpa, raw) else null;
    defer if (redacted_detail) |r| gpa.free(r);

    const stmt = try db.prepare(
        \\INSERT INTO audit_actions(kind, target, request_json, result, detail, actor, idempotency_key)
        \\VALUES (?, ?, ?, ?, ?, ?, ?)
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, kind);
    try bindTextOpt(stmt, 2, target);
    try bindTextOpt(stmt, 3, if (redacted_request) |r| r else null);
    try bindText(stmt, 4, result.text());
    try bindTextOpt(stmt, 5, if (redacted_detail) |r| r else null);
    try bindText(stmt, 6, metadata.actor);
    try bindTextOpt(stmt, 7, metadata.idempotency_key);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return WriteError.SqliteStep;
    return sqlite.sqlite3_last_insert_rowid(db.handle);
}

pub const StoredResponse = struct {
    status: u16,
    body: []u8,

    pub fn deinit(self: StoredResponse, gpa: Allocator) void {
        gpa.free(self.body);
    }
};

pub const MutationClaim = union(enum) {
    execute,
    replay: StoredResponse,
    in_progress,
    conflict,
};

/// Atomically claims an idempotency key. A completed matching request is
/// replayed verbatim; reuse for different request bytes is rejected.
pub fn beginMutation(
    gpa: Allocator,
    db: *Db,
    key: []const u8,
    request_hash: []const u8,
    method: []const u8,
    target: []const u8,
    actor: []const u8,
) !MutationClaim {
    const insert = try db.prepare(
        \\INSERT OR IGNORE INTO mutation_requests(idempotency_key, request_hash, method, target, actor)
        \\VALUES (?, ?, ?, ?, ?)
    );
    defer _ = sqlite.sqlite3_finalize(insert);
    try bindText(insert, 1, key);
    try bindText(insert, 2, request_hash);
    try bindText(insert, 3, method);
    try bindText(insert, 4, target);
    try bindText(insert, 5, actor);
    if (sqlite.sqlite3_step(insert) != sqlite.SQLITE_DONE) return WriteError.SqliteStep;
    if (sqlite.sqlite3_changes(db.handle) == 1) return .execute;

    const query = try db.prepare(
        \\SELECT request_hash, state, http_status, response_json
        \\FROM mutation_requests WHERE idempotency_key = ?
    );
    defer _ = sqlite.sqlite3_finalize(query);
    try bindText(query, 1, key);
    if (sqlite.sqlite3_step(query) != sqlite.SQLITE_ROW) return WriteError.SqliteStep;
    const stored_hash = columnText(query, 0) orelse "";
    if (!std.mem.eql(u8, stored_hash, request_hash)) return .conflict;
    const state = columnText(query, 1) orelse "running";
    if (!std.mem.eql(u8, state, "completed")) return .in_progress;
    const status_raw = sqlite.sqlite3_column_int64(query, 2);
    const body = try gpa.dupe(u8, columnText(query, 3) orelse "");
    return .{ .replay = .{
        .status = if (status_raw >= 100 and status_raw <= 599) @intCast(status_raw) else 500,
        .body = body,
    } };
}

pub fn completeMutation(db: *Db, key: []const u8, status: u16, response_json: []const u8) !void {
    const stmt = try db.prepare(
        \\UPDATE mutation_requests
        \\SET state = 'completed', http_status = ?, response_json = ?, completed_at = CURRENT_TIMESTAMP
        \\WHERE idempotency_key = ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, status) != sqlite.SQLITE_OK) return WriteError.SqliteBind;
    try bindText(stmt, 2, response_json);
    try bindText(stmt, 3, key);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return WriteError.SqliteStep;
}

pub const AuditView = enum {
    important,
    all,

    pub fn parse(value: []const u8) ?AuditView {
        if (std.mem.eql(u8, value, "important")) return .important;
        if (std.mem.eql(u8, value, "all")) return .all;
        return null;
    }
};

pub const AuditResultFilter = enum {
    all,
    success,
    failure,

    pub fn parse(value: []const u8) ?AuditResultFilter {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "success")) return .success;
        if (std.mem.eql(u8, value, "failure")) return .failure;
        return null;
    }
};

pub const AuditWindow = enum {
    hour,
    day,
    week,
    month,
    all,

    pub fn parse(text: []const u8) ?AuditWindow {
        if (std.mem.eql(u8, text, "1h")) return .hour;
        if (std.mem.eql(u8, text, "24h")) return .day;
        if (std.mem.eql(u8, text, "7d")) return .week;
        if (std.mem.eql(u8, text, "30d")) return .month;
        if (std.mem.eql(u8, text, "all")) return .all;
        return null;
    }

    pub fn value(self: AuditWindow) []const u8 {
        return switch (self) {
            .hour => "1h",
            .day => "24h",
            .week => "7d",
            .month => "30d",
            .all => "all",
        };
    }

    fn sqliteModifier(self: AuditWindow) []const u8 {
        return switch (self) {
            .hour => "-1 hour",
            .day => "-24 hours",
            .week => "-7 days",
            .month => "-30 days",
            .all => "",
        };
    }
};

pub const AuditOptions = struct {
    view: AuditView = .important,
    category: ?[]const u8 = null,
    result: AuditResultFilter = .all,
    target: ?[]const u8 = null,
    actor: ?[]const u8 = null,
    window: AuditWindow = .day,
    limit: i64 = 100,

    pub fn normalized(self: AuditOptions) AuditOptions {
        return .{
            .view = self.view,
            .category = normalizeAuditCategory(self.category),
            .result = self.result,
            .target = normalizeSearch(self.target),
            .actor = normalizeSearch(self.actor),
            .window = self.window,
            .limit = @min(@max(self.limit, 1), 500),
        };
    }
};

const audit_query_limit = 10_000;

/// Write one bounded, normalized history over mutations and control-plane
/// events. The existing stores keep their distinct write/retention behavior.
pub fn writeAuditJson(gpa: Allocator, db: *Db, options_input: AuditOptions, writer: anytype) !void {
    const options = options_input.normalized();
    const stmt = try db.prepare(
        \\SELECT source, row_id, action, target, request_json, result, detail, actor, idempotency_key, created_at
        \\FROM (
        \\  SELECT 'mutation' AS source, id AS row_id, kind AS action,
        \\         COALESCE(target,'') AS target,
        \\         COALESCE(request_json,'') AS request_json, result,
        \\         COALESCE(detail,'') AS detail,
        \\         COALESCE(actor,'platform') AS actor,
        \\         COALESCE(idempotency_key,'') AS idempotency_key, created_at
        \\  FROM audit_actions
        \\  UNION ALL
        \\  SELECT 'event' AS source, id AS row_id, action,
        \\         '', '', status, COALESCE(detail,''), 'system', '', created_at
        \\  FROM audit_events
        \\)
        \\WHERE (? = '' OR created_at >= datetime('now', ?))
        \\ORDER BY created_at DESC, source = 'mutation' DESC, row_id DESC
        \\LIMIT ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, options.window.sqliteModifier());
    try bindText(stmt, 2, options.window.sqliteModifier());
    if (sqlite.sqlite3_bind_int64(stmt, 3, audit_query_limit) != sqlite.SQLITE_OK) return WriteError.SqliteBind;

    try writer.writeAll("{\"kind\":\"audit\",\"filters\":{");
    try core_json.writeStringField(writer, "view", @tagName(options.view), true);
    try core_json.writeNullableStringField(writer, "category", options.category, true);
    try core_json.writeStringField(writer, "result", @tagName(options.result), true);
    try core_json.writeNullableStringField(writer, "target", options.target, true);
    try core_json.writeNullableStringField(writer, "actor", options.actor, true);
    try core_json.writeStringField(writer, "window", options.window.value(), true);
    try core_json.writeIntField(writer, "limit", options.limit, false);
    try writer.writeAll("},\"entries\":[");
    var first = true;
    var returned: i64 = 0;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return WriteError.SqliteStep;
        const source = columnText(stmt, 0) orelse "";
        const action = columnText(stmt, 2) orelse "";
        const result = columnText(stmt, 5) orelse "";
        const category = auditCategory(action);
        const target_raw = columnText(stmt, 3) orelse "";
        const actor = columnText(stmt, 7) orelse "";
        if (options.view == .important and std.mem.eql(u8, source, "event") and auditResultIsSuccess(result)) continue;
        if (options.category) |selected| if (!std.mem.eql(u8, selected, category)) continue;
        if (!auditResultMatches(result, options.result)) continue;
        if (options.target) |search| if (!containsIgnoreCase(target_raw, search)) continue;
        if (options.actor) |search| if (!containsIgnoreCase(actor, search)) continue;
        if (returned >= options.limit) break;

        const target = if (target_raw.len > 0) try redactAuditValue(gpa, target_raw) else null;
        defer if (target) |value| gpa.free(value);
        const request_raw = columnText(stmt, 4) orelse "";
        const request = if (request_raw.len > 0) try redactAuditValue(gpa, request_raw) else null;
        defer if (request) |value| gpa.free(value);
        const detail_raw = columnText(stmt, 6) orelse "";
        const redacted_detail = if (detail_raw.len > 0) try redactAuditValue(gpa, detail_raw) else null;
        defer if (redacted_detail) |value| gpa.free(value);

        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        var id_buffer: [64]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buffer, "{s}:{d}", .{ source, sqlite.sqlite3_column_int64(stmt, 1) });
        try core_json.writeStringField(writer, "id", id, true);
        try core_json.writeStringField(writer, "source", source, true);
        try core_json.writeStringField(writer, "category", category, true);
        try core_json.writeStringField(writer, "action", action, true);
        try core_json.writeNullableStringField(writer, "target", target, true);
        try core_json.writeNullableStringField(writer, "request", request, true);
        try core_json.writeStringField(writer, "result", result, true);
        try core_json.writeNullableStringField(writer, "detail", redacted_detail, true);
        try core_json.writeStringField(writer, "actor", actor, true);
        const idempotency_key = columnText(stmt, 8) orelse "";
        try core_json.writeNullableStringField(writer, "idempotency_key", if (idempotency_key.len > 0) idempotency_key else null, true);
        try core_json.writeStringField(writer, "created_at", columnText(stmt, 9) orelse "", false);
        try writer.writeByte('}');
        returned += 1;
    }
    try writer.writeAll("],");
    try core_json.writeIntField(writer, "returned", returned, false);
    try writer.writeAll("}\n");
}

fn normalizeAuditCategory(value: ?[]const u8) ?[]const u8 {
    const category = value orelse return null;
    const known = [_][]const u8{ "dashboard", "projects", "routes", "dns", "browser", "vps", "docker", "security", "settings", "other" };
    for (known) |item| if (std.mem.eql(u8, category, item)) return item;
    return null;
}

fn normalizeSearch(value: ?[]const u8) ?[]const u8 {
    const clean = std.mem.trim(u8, value orelse return null, " \t\r\n");
    if (clean.len == 0) return null;
    return clean[0..@min(clean.len, 128)];
}

fn redactAuditValue(gpa: Allocator, raw: []const u8) ![]u8 {
    const redacted = try core_redact.secrets(gpa, raw);
    defer gpa.free(redacted);
    return try gpa.dupe(u8, std.mem.trimEnd(u8, redacted, "\n"));
}

pub fn auditCategory(action: []const u8) []const u8 {
    if (startsWithAny(action, &.{ "docker.", "container." })) return "docker";
    if (startsWithAny(action, &.{ "nob.", "project." })) return "projects";
    if (startsWithAny(action, &.{ "caddy.", "route." })) return "routes";
    if (startsWithAny(action, &.{"browser."})) return "browser";
    if (startsWithAny(action, &.{ "cf.", "cloudflare.", "dns.", "cache.", "zone." })) return "dns";
    if (startsWithAny(action, &.{ "hostinger.", "vps.", "firewall." })) return "vps";
    if (startsWithAny(action, &.{ "auth.", "passkey." })) return "security";
    if (startsWithAny(action, &.{ "settings.", "theme." })) return "settings";
    if (startsWithAny(action, &.{ "refresh", "system.", "topology." })) return "dashboard";
    return "other";
}

fn startsWithAny(value: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| if (std.mem.startsWith(u8, value, prefix)) return true;
    return false;
}

fn auditResultIsSuccess(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "ok") or
        std.ascii.eqlIgnoreCase(value, "success") or
        std.ascii.eqlIgnoreCase(value, "succeeded") or
        std.ascii.eqlIgnoreCase(value, "accepted");
}

fn auditResultMatches(value: []const u8, filter: AuditResultFilter) bool {
    return switch (filter) {
        .all => true,
        .success => auditResultIsSuccess(value),
        .failure => !auditResultIsSuccess(value),
    };
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn columnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

fn bindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return WriteError.SqliteBind;
}

fn bindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |v| return bindText(stmt, idx, v);
    if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return WriteError.SqliteBind;
}

test "record inserts redacted audit action and lists it" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/writes.db", .{tmp.sub_path});
    defer allocator.free(db_path);

    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const id = try record(allocator, &db, "caddy.reload", "Caddyfile", "{\"api_token\":\"supersecret\"}", .ok, null);
    try std.testing.expect(id > 0);
    _ = try recordWithMetadata(
        allocator,
        &db,
        .{ .actor = "ops@example", .idempotency_key = "request-1234" },
        "docker.restart",
        "demo",
        null,
        .ok,
        "done",
    );
    try db.insertAudit("cloudflare.collect", "ok", "provider refresh succeeded");
    try db.insertAudit("cloudflare.collect", "error", "{\"api_token\":\"event-secret\",\"reason\":\"permission denied\"}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeAuditJson(allocator, &db, .{ .window = .all, .limit = 10 }, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "caddy.reload") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "supersecret") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "event-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "permission denied") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"actor\":\"ops@example\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"idempotency_key\":\"request-1234\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"event\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "provider refresh succeeded") == null);

    var filtered = std.Io.Writer.Allocating.init(allocator);
    defer filtered.deinit();
    try writeAuditJson(allocator, &db, .{
        .view = .all,
        .category = "docker",
        .result = .success,
        .target = "DEMO",
        .actor = "OPS@",
        .window = .all,
        .limit = 1_000,
    }, &filtered.writer);
    try std.testing.expect(std.mem.indexOf(u8, filtered.written(), "docker.restart") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered.written(), "caddy.reload") == null);
    try std.testing.expect(std.mem.indexOf(u8, filtered.written(), "\"limit\":500") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered.written(), "\"returned\":1") != null);
}

test "mutation idempotency claims replays and rejects key reuse" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/idempotency.db", .{tmp.sub_path});
    defer allocator.free(db_path);

    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const first = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/containers/refresh", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).execute, std.meta.activeTag(first));
    const pending = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/containers/refresh", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).in_progress, std.meta.activeTag(pending));
    try completeMutation(&db, "request-1", 200, "{\"ok\":true}\n");

    var replay = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/containers/refresh", "test");
    defer if (std.meta.activeTag(replay) == .replay) replay.replay.deinit(allocator);
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).replay, std.meta.activeTag(replay));
    try std.testing.expectEqual(@as(u16, 200), replay.replay.status);
    try std.testing.expectEqualStrings("{\"ok\":true}\n", replay.replay.body);
    const conflict = try beginMutation(allocator, &db, "request-1", "hash-b", "POST", "/api/containers/refresh", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).conflict, std.meta.activeTag(conflict));
}
