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
    const redacted_request: ?[]u8 = if (request_json) |raw| try core_redact.secrets(gpa, raw) else null;
    defer if (redacted_request) |r| gpa.free(r);
    const redacted_detail: ?[]u8 = if (detail) |raw| try core_redact.secrets(gpa, raw) else null;
    defer if (redacted_detail) |r| gpa.free(r);

    const stmt = try db.prepare(
        \\INSERT INTO audit_actions(kind, target, request_json, result, detail, actor)
        \\VALUES (?, ?, ?, ?, ?, 'platform')
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, kind);
    try bindTextOpt(stmt, 2, target);
    try bindTextOpt(stmt, 3, if (redacted_request) |r| r else null);
    try bindText(stmt, 4, result.text());
    try bindTextOpt(stmt, 5, if (redacted_detail) |r| r else null);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return WriteError.SqliteStep;
    return sqlite.sqlite3_last_insert_rowid(db.handle);
}

/// Write recent audit actions as a JSON object for the UI audit page.
pub fn writeAuditJson(gpa: Allocator, db: *Db, limit: i64, writer: anytype) !void {
    _ = gpa;
    const effective_limit: i64 = if (limit <= 0) 200 else limit;
    const stmt = try db.prepare(
        \\SELECT id, kind, target, request_json, result, detail, actor, created_at
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

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeAuditJson(allocator, &db, 10, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "caddy.reload") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "supersecret") == null);
}
