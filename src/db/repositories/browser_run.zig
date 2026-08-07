const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");

const Allocator = std.mem.Allocator;
const bindI64 = helpers.bindI64;
const bindI64Opt = helpers.bindI64Opt;
const bindText = helpers.bindText;
const bindTextOpt = helpers.bindTextOpt;
const columnText = helpers.columnText;
const stepDone = helpers.stepDone;

pub const NewRun = struct {
    id: []const u8,
    account_id: []const u8,
    action: []const u8,
    target_url: []const u8,
    target_host: []const u8,
    target_sha256: []const u8,
    requested_by: []const u8,
    idempotency_key: ?[]const u8,
    created_at: i64,
    expires_at: i64,
};

pub const Finish = struct {
    state: []const u8,
    origin_status: ?i64 = null,
    title: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    size_bytes: ?i64 = null,
    browser_ms_used: ?i64 = null,
    retry_after_seconds: ?i64 = null,
    cf_ray: ?[]const u8 = null,
    artifact_path: ?[]const u8 = null,
    artifact_sha256: ?[]const u8 = null,
    error_code: ?[]const u8 = null,
    error_summary: ?[]const u8 = null,
    finished_at: i64,
};

pub const Run = struct {
    id: []u8,
    account_id: []u8,
    action: []u8,
    engine: []u8,
    target_url: []u8,
    target_host: []u8,
    state: []u8,
    origin_status: ?i64,
    title: ?[]u8,
    content_type: ?[]u8,
    size_bytes: ?i64,
    browser_ms_used: ?i64,
    retry_after_seconds: ?i64,
    cf_ray: ?[]u8,
    artifact_path: ?[]u8,
    artifact_sha256: ?[]u8,
    error_code: ?[]u8,
    error_summary: ?[]u8,
    created_at: i64,
    finished_at: ?i64,
    expires_at: i64,

    pub fn deinit(self: Run, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.account_id);
        allocator.free(self.action);
        allocator.free(self.engine);
        allocator.free(self.target_url);
        allocator.free(self.target_host);
        allocator.free(self.state);
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.content_type);
        freeOptional(allocator, self.cf_ray);
        freeOptional(allocator, self.artifact_path);
        freeOptional(allocator, self.artifact_sha256);
        freeOptional(allocator, self.error_code);
        freeOptional(allocator, self.error_summary);
    }
};

pub const Runs = struct {
    items: []Run,

    pub fn deinit(self: *Runs, allocator: Allocator) void {
        for (self.items) |run| run.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Repository = struct {
    handle: *sqlite.sqlite3,

    pub fn insert(self: Repository, run: NewRun) !void {
        const stmt = try helpers.prepare(self.handle,
            \\INSERT INTO browser_runs(
            \\  id, account_id, action, engine, target_url, target_host,
            \\  target_sha256, state, requested_by, idempotency_key,
            \\  created_at, started_at, expires_at
            \\) VALUES (?, ?, ?, 'kitesurf', ?, ?, ?, 'running', ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, run.id);
        try bindText(stmt, 2, run.account_id);
        try bindText(stmt, 3, run.action);
        try bindText(stmt, 4, run.target_url);
        try bindText(stmt, 5, run.target_host);
        try bindText(stmt, 6, run.target_sha256);
        try bindText(stmt, 7, run.requested_by);
        try bindTextOpt(stmt, 8, run.idempotency_key);
        try bindI64(stmt, 9, run.created_at);
        try bindI64(stmt, 10, run.created_at);
        try bindI64(stmt, 11, run.expires_at);
        try stepDone(stmt);
    }

    pub fn finish(self: Repository, id: []const u8, value: Finish) !void {
        const stmt = try helpers.prepare(self.handle,
            \\UPDATE browser_runs SET
            \\  state=?, origin_status=?, title=?, content_type=?, size_bytes=?,
            \\  browser_ms_used=?, retry_after_seconds=?, cf_ray=?, artifact_path=?,
            \\  artifact_sha256=?, error_code=?, error_summary=?, finished_at=?
            \\WHERE id=? AND state='running'
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, value.state);
        try bindI64Opt(stmt, 2, value.origin_status);
        try bindTextOpt(stmt, 3, value.title);
        try bindTextOpt(stmt, 4, value.content_type);
        try bindI64Opt(stmt, 5, value.size_bytes);
        try bindI64Opt(stmt, 6, value.browser_ms_used);
        try bindI64Opt(stmt, 7, value.retry_after_seconds);
        try bindTextOpt(stmt, 8, value.cf_ray);
        try bindTextOpt(stmt, 9, value.artifact_path);
        try bindTextOpt(stmt, 10, value.artifact_sha256);
        try bindTextOpt(stmt, 11, value.error_code);
        try bindTextOpt(stmt, 12, value.error_summary);
        try bindI64(stmt, 13, value.finished_at);
        try bindText(stmt, 14, id);
        try stepDone(stmt);
    }

    pub fn get(self: Repository, allocator: Allocator, id: []const u8) !?Run {
        const stmt = try helpers.prepare(self.handle, select_columns ++ " WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try runFromStmt(allocator, stmt);
    }

    pub fn recent(self: Repository, allocator: Allocator, limit: i64) !Runs {
        const stmt = try helpers.prepare(self.handle, select_columns ++ " ORDER BY created_at DESC, id DESC LIMIT ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, @min(@max(limit, 1), 100));
        var runs = std.ArrayList(Run).empty;
        errdefer deinitRunList(&runs, allocator);
        while (true) {
            const rc = sqlite.sqlite3_step(stmt);
            if (rc == sqlite.SQLITE_DONE) break;
            if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
            var run = try runFromStmt(allocator, stmt);
            runs.append(allocator, run) catch |err| {
                run.deinit(allocator);
                return err;
            };
        }
        return .{ .items = try runs.toOwnedSlice(allocator) };
    }

    pub fn expired(self: Repository, allocator: Allocator, now: i64, limit: i64) !Runs {
        const stmt = try helpers.prepare(self.handle, select_columns ++ " WHERE expires_at <= ? ORDER BY expires_at, id LIMIT ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindI64(stmt, 2, @min(@max(limit, 1), 100));
        var runs = std.ArrayList(Run).empty;
        errdefer deinitRunList(&runs, allocator);
        while (true) {
            const rc = sqlite.sqlite3_step(stmt);
            if (rc == sqlite.SQLITE_DONE) break;
            if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
            var run = try runFromStmt(allocator, stmt);
            runs.append(allocator, run) catch |err| {
                run.deinit(allocator);
                return err;
            };
        }
        return .{ .items = try runs.toOwnedSlice(allocator) };
    }

    pub fn deleteExpired(self: Repository, id: []const u8, now: i64) !bool {
        const stmt = try helpers.prepare(self.handle, "DELETE FROM browser_runs WHERE id=? AND expires_at <= ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindI64(stmt, 2, now);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn abandonStale(self: Repository, before: i64, finished_at: i64) !usize {
        const stmt = try helpers.prepare(self.handle,
            \\UPDATE browser_runs
            \\SET state='abandoned', error_code='interrupted',
            \\    error_summary='Cloudio stopped before the run completed.', finished_at=?
            \\WHERE state='running' AND started_at < ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, finished_at);
        try bindI64(stmt, 2, before);
        try stepDone(stmt);
        return @intCast(sqlite.sqlite3_changes(self.handle));
    }
};

const select_columns =
    \\SELECT id, account_id, action, engine, target_url, target_host, state,
    \\       origin_status, title, content_type, size_bytes, browser_ms_used,
    \\       retry_after_seconds, cf_ray, artifact_path, artifact_sha256,
    \\       error_code, error_summary, created_at, finished_at, expires_at
    \\FROM browser_runs
;

fn runFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !Run {
    var run = Run{
        .id = try dupeColumn(allocator, stmt, 0),
        .account_id = undefined,
        .action = undefined,
        .engine = undefined,
        .target_url = undefined,
        .target_host = undefined,
        .state = undefined,
        .origin_status = columnI64Opt(stmt, 7),
        .title = null,
        .content_type = null,
        .size_bytes = columnI64Opt(stmt, 10),
        .browser_ms_used = columnI64Opt(stmt, 11),
        .retry_after_seconds = columnI64Opt(stmt, 12),
        .cf_ray = null,
        .artifact_path = null,
        .artifact_sha256 = null,
        .error_code = null,
        .error_summary = null,
        .created_at = sqlite.sqlite3_column_int64(stmt, 18),
        .finished_at = columnI64Opt(stmt, 19),
        .expires_at = sqlite.sqlite3_column_int64(stmt, 20),
    };
    errdefer allocator.free(run.id);
    run.account_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(run.account_id);
    run.action = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(run.action);
    run.engine = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(run.engine);
    run.target_url = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(run.target_url);
    run.target_host = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(run.target_host);
    run.state = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(run.state);
    run.title = try dupeColumnOpt(allocator, stmt, 8);
    errdefer freeOptional(allocator, run.title);
    run.content_type = try dupeColumnOpt(allocator, stmt, 9);
    errdefer freeOptional(allocator, run.content_type);
    run.cf_ray = try dupeColumnOpt(allocator, stmt, 13);
    errdefer freeOptional(allocator, run.cf_ray);
    run.artifact_path = try dupeColumnOpt(allocator, stmt, 14);
    errdefer freeOptional(allocator, run.artifact_path);
    run.artifact_sha256 = try dupeColumnOpt(allocator, stmt, 15);
    errdefer freeOptional(allocator, run.artifact_sha256);
    run.error_code = try dupeColumnOpt(allocator, stmt, 16);
    errdefer freeOptional(allocator, run.error_code);
    run.error_summary = try dupeColumnOpt(allocator, stmt, 17);
    return run;
}

fn columnI64Opt(stmt: *sqlite.sqlite3_stmt, index: c_int) ?i64 {
    if (sqlite.sqlite3_column_type(stmt, index) == sqlite.SQLITE_NULL) return null;
    return sqlite.sqlite3_column_int64(stmt, index);
}

fn dupeColumn(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, index: c_int) ![]u8 {
    return try allocator.dupe(u8, columnText(stmt, index) orelse "");
}

fn dupeColumnOpt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, index: c_int) !?[]u8 {
    const value = columnText(stmt, index) orelse return null;
    return try allocator.dupe(u8, value);
}

fn freeOptional(allocator: Allocator, value: ?[]u8) void {
    if (value) |present| allocator.free(present);
}

fn deinitRunList(runs: *std.ArrayList(Run), allocator: Allocator) void {
    for (runs.items) |run| run.deinit(allocator);
    runs.deinit(allocator);
}
