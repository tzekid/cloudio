//! Shared write-action contract: every mutation (Caddy, provider, systemd,
//! Docker, deploy) records an audit_actions row through this module.
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

/// Write recent audit actions as a JSON object for the UI audit page.
pub fn writeAuditJson(gpa: Allocator, db: *Db, limit: i64, writer: anytype) !void {
    _ = gpa;
    const effective_limit: i64 = if (limit <= 0) 200 else limit;
    const stmt = try db.prepare(
        \\SELECT id, kind, target, request_json, result, detail, actor, created_at, idempotency_key
        \\FROM audit_actions ORDER BY id DESC LIMIT ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, effective_limit) != sqlite.SQLITE_OK) return WriteError.SqliteBind;

    try writer.writeAll("{\"kind\":\"audit_actions\",\"actions\":[");
    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return WriteError.SqliteStep;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try writer.print("\"id\":{d},", .{sqlite.sqlite3_column_int64(stmt, 0)});
        try core_json.writeStringField(writer, "action", columnText(stmt, 1) orelse "", true);
        try core_json.writeNullableStringField(writer, "target", columnText(stmt, 2), true);
        try core_json.writeNullableStringField(writer, "request", columnText(stmt, 3), true);
        try core_json.writeStringField(writer, "result", columnText(stmt, 4) orelse "", true);
        try core_json.writeNullableStringField(writer, "detail", columnText(stmt, 5), true);
        try core_json.writeStringField(writer, "actor", columnText(stmt, 6) orelse "", true);
        try core_json.writeNullableStringField(writer, "idempotency_key", columnText(stmt, 8), true);
        try core_json.writeStringField(writer, "created_at", columnText(stmt, 7) orelse "", false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
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
        "app.deploy",
        "demo",
        null,
        .ok,
        "done",
    );

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeAuditJson(allocator, &db, 10, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "caddy.reload") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "supersecret") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"actor\":\"ops@example\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"idempotency_key\":\"request-1234\"") != null);
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

    const first = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/apps", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).execute, std.meta.activeTag(first));
    const pending = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/apps", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).in_progress, std.meta.activeTag(pending));
    try completeMutation(&db, "request-1", 200, "{\"ok\":true}\n");

    var replay = try beginMutation(allocator, &db, "request-1", "hash-a", "POST", "/api/apps", "test");
    defer if (std.meta.activeTag(replay) == .replay) replay.replay.deinit(allocator);
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).replay, std.meta.activeTag(replay));
    try std.testing.expectEqual(@as(u16, 200), replay.replay.status);
    try std.testing.expectEqualStrings("{\"ok\":true}\n", replay.replay.body);
    const conflict = try beginMutation(allocator, &db, "request-1", "hash-b", "POST", "/api/apps", "test");
    try std.testing.expectEqual(std.meta.Tag(MutationClaim).conflict, std.meta.activeTag(conflict));
}
