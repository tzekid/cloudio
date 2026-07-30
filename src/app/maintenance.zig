//! Storage lifecycle management for append-only operational history.
//!
//! Preview is the default. Manual destructive runs require an online SQLite
//! backup path before pruning or compaction. The server scheduler may call
//! `prune` directly only when the operator explicitly enables auto-prune.
const std = @import("std");
const sqlite = @import("sqlite");
const core_config = @import("core_config");
const core_fs = @import("core_fs");
const core_json = @import("core_json");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Policy = struct {
    snapshot_days: u32 = 14,
    provider_raw_days: u32 = 14,
    metrics_days: u32 = 30,
    batch_rows: u32 = 5000,

    pub fn fromConfig(config: core_config.Config) Policy {
        return .{
            .snapshot_days = config.snapshot_retention_days,
            .provider_raw_days = config.provider_raw_retention_days,
            .metrics_days = config.metrics_retention_days,
            .batch_rows = config.maintenance_batch_rows,
        };
    }
};

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub const TableStats = struct {
    total: i64 = 0,
    eligible: i64 = 0,
};

pub const Stats = struct {
    snapshots: TableStats = .{},
    provider_raw: TableStats = .{},
    hostinger_metrics: TableStats = .{},
    system_metrics: TableStats = .{},
    page_size: i64 = 0,
    page_count: i64 = 0,
    freelist_pages: i64 = 0,

    pub fn databaseBytes(self: Stats) i64 {
        return self.page_size * self.page_count;
    }

    pub fn reclaimableBytes(self: Stats) i64 {
        return self.page_size * self.freelist_pages;
    }
};

pub const Operation = enum {
    status,
    backup,
    prune,
    compact,
    run,

    pub fn text(self: Operation) []const u8 {
        return @tagName(self);
    }
};

pub const Options = struct {
    operation: Operation = .status,
    apply: bool = false,
    backup_path: ?[]const u8 = null,
};

pub const Result = struct {
    operation: Operation,
    applied: bool,
    backup_path: ?[]const u8,
    pruned: bool,
    compacted: bool,
    before: Stats,
    after: Stats,

    pub fn deletedSnapshots(self: Result) i64 {
        return self.before.snapshots.total - self.after.snapshots.total;
    }

    pub fn deletedProviderRaw(self: Result) i64 {
        return self.before.provider_raw.total - self.after.provider_raw.total;
    }

    pub fn deletedHostingerMetrics(self: Result) i64 {
        return self.before.hostinger_metrics.total - self.after.hostinger_metrics.total;
    }

    pub fn deletedSystemMetrics(self: Result) i64 {
        return self.before.system_metrics.total - self.after.system_metrics.total;
    }
};

pub const Error = error{
    ApplyRequiresBackup,
    BackupPathRequired,
    BackupAlreadyExists,
    BackupOpenFailed,
    BackupInitFailed,
    BackupStepFailed,
    BackupFinishFailed,
    BackupVerifyFailed,
    SqliteBind,
    SqliteStep,
};

pub fn execute(ctx: Context, policy: Policy, options: Options) !Result {
    const before = try inspect(ctx.db, policy);
    var result = Result{
        .operation = options.operation,
        .applied = options.apply,
        .backup_path = options.backup_path,
        .pruned = false,
        .compacted = false,
        .before = before,
        .after = before,
    };

    switch (options.operation) {
        .status => return result,
        .backup => {
            const path = options.backup_path orelse return Error.BackupPathRequired;
            try backup(ctx, path);
            result.applied = true;
            return result;
        },
        .prune, .compact, .run => {},
    }

    if (!options.apply) return result;
    const path = options.backup_path orelse return Error.ApplyRequiresBackup;
    try backup(ctx, path);

    if (options.operation == .prune or options.operation == .run) {
        try prune(ctx.db, policy);
        result.pruned = true;
    }
    if (options.operation == .compact or options.operation == .run) {
        try compact(ctx.db);
        result.compacted = true;
    }
    result.after = try inspect(ctx.db, policy);
    return result;
}

pub fn inspect(db: *Db, policy: Policy) !Stats {
    return .{
        .snapshots = try tableStats(
            db,
            "SELECT COUNT(*) FROM snapshots",
            "SELECT COUNT(*) FROM snapshots WHERE captured_at < datetime('now', '-' || ? || ' days')",
            policy.snapshot_days,
        ),
        .provider_raw = try tableStats(
            db,
            "SELECT COUNT(*) FROM provider_raw",
            "SELECT COUNT(*) FROM provider_raw WHERE captured_at < datetime('now', '-' || ? || ' days')",
            policy.provider_raw_days,
        ),
        .hostinger_metrics = try tableStats(
            db,
            "SELECT COUNT(*) FROM hostinger_metrics",
            "SELECT COUNT(*) FROM hostinger_metrics WHERE captured_at < datetime('now', '-' || ? || ' days')",
            policy.metrics_days,
        ),
        .system_metrics = try tableStats(
            db,
            "SELECT COUNT(*) FROM system_metrics",
            "SELECT COUNT(*) FROM system_metrics WHERE captured_at < datetime('now', '-' || ? || ' days')",
            policy.metrics_days,
        ),
        .page_size = try scalar(db, "PRAGMA page_size"),
        .page_count = try scalar(db, "PRAGMA page_count"),
        .freelist_pages = try scalar(db, "PRAGMA freelist_count"),
    };
}

/// Prune eligible rows in bounded transactions. Callers are responsible for
/// requiring a backup for manual runs or explicitly enabling scheduled prune.
pub fn prune(db: *Db, policy: Policy) !void {
    try pruneBatches(
        db,
        "DELETE FROM snapshots WHERE id IN (SELECT id FROM snapshots WHERE captured_at < datetime('now', '-' || ? || ' days') LIMIT ?)",
        policy.snapshot_days,
        policy.batch_rows,
    );
    try pruneBatches(
        db,
        "DELETE FROM provider_raw WHERE id IN (SELECT id FROM provider_raw WHERE captured_at < datetime('now', '-' || ? || ' days') LIMIT ?)",
        policy.provider_raw_days,
        policy.batch_rows,
    );
    try pruneBatches(
        db,
        "DELETE FROM hostinger_metrics WHERE id IN (SELECT id FROM hostinger_metrics WHERE captured_at < datetime('now', '-' || ? || ' days') LIMIT ?)",
        policy.metrics_days,
        policy.batch_rows,
    );
    try pruneBatches(
        db,
        "DELETE FROM system_metrics WHERE id IN (SELECT id FROM system_metrics WHERE captured_at < datetime('now', '-' || ? || ' days') LIMIT ?)",
        policy.metrics_days,
        policy.batch_rows,
    );
    // Checkpointing bounds the WAL after a large batch run. A busy reader may
    // prevent truncation, in which case the next normal checkpoint can retry.
    db.exec("PRAGMA wal_checkpoint(PASSIVE)") catch {};
}

pub fn compact(db: *Db) !void {
    db.exec("PRAGMA wal_checkpoint(TRUNCATE)") catch {};
    try db.exec("VACUUM");
    try db.exec("PRAGMA optimize");
}

/// Create a consistent online SQLite backup without stopping readers.
/// Existing paths are rejected so a previous recovery point is never replaced.
pub fn backup(ctx: Context, path: []const u8) !void {
    if (try core_fs.fileExists(ctx.io, path)) return Error.BackupAlreadyExists;
    try core_fs.ensureParentDir(ctx.io, path);
    if (path.len >= std.fs.max_path_bytes) return error.NameTooLong;

    var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;

    var destination: ?*sqlite.sqlite3 = null;
    if (sqlite.sqlite3_open_v2(@ptrCast(&path_z), &destination, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null) != sqlite.SQLITE_OK) {
        return Error.BackupOpenFailed;
    }
    defer _ = sqlite.sqlite3_close(destination.?);

    const handle = sqlite.sqlite3_backup_init(destination.?, "main", ctx.db.handle, "main") orelse {
        Io.Dir.cwd().deleteFile(ctx.io, path) catch {};
        return Error.BackupInitFailed;
    };

    var step_error = false;
    while (true) {
        const rc = sqlite.sqlite3_backup_step(handle, 1024);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc == sqlite.SQLITE_OK) continue;
        if (rc == sqlite.SQLITE_BUSY or rc == sqlite.SQLITE_LOCKED) {
            ctx.io.sleep(.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
            continue;
        }
        step_error = true;
        break;
    }
    const finish_rc = sqlite.sqlite3_backup_finish(handle);
    if (step_error) {
        Io.Dir.cwd().deleteFile(ctx.io, path) catch {};
        return Error.BackupStepFailed;
    }
    if (finish_rc != sqlite.SQLITE_OK) {
        Io.Dir.cwd().deleteFile(ctx.io, path) catch {};
        return Error.BackupFinishFailed;
    }
    if (!verifyDatabase(destination.?)) {
        Io.Dir.cwd().deleteFile(ctx.io, path) catch {};
        return Error.BackupVerifyFailed;
    }
    const file = try Io.Dir.cwd().openFile(ctx.io, path, .{});
    defer file.close(ctx.io);
    try file.setPermissions(ctx.io, @enumFromInt(0o600));
}

pub fn writeText(result: Result, policy: Policy, writer: anytype) !void {
    try writer.print("maintenance {s}: {s}\n", .{ result.operation.text(), if (result.applied) "applied" else "preview" });
    try writer.print("retention: snapshots={d}d provider_raw={d}d metrics={d}d batch={d}\n", .{
        policy.snapshot_days,
        policy.provider_raw_days,
        policy.metrics_days,
        policy.batch_rows,
    });
    if (result.backup_path) |path| try writer.print("backup: {s}\n", .{path});
    try writeStatsText("before", result.before, writer);
    if (result.applied) {
        try writeStatsText("after", result.after, writer);
        try writer.print("deleted: snapshots={d} provider_raw={d} hostinger_metrics={d} system_metrics={d}\n", .{
            result.deletedSnapshots(),
            result.deletedProviderRaw(),
            result.deletedHostingerMetrics(),
            result.deletedSystemMetrics(),
        });
        try writer.print("pruned={} compacted={}\n", .{ result.pruned, result.compacted });
    }
}

pub fn writeJson(result: Result, policy: Policy, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "kind", "maintenance", true);
    try core_json.writeStringField(writer, "operation", result.operation.text(), true);
    try core_json.writeBoolField(writer, "applied", result.applied, true);
    try core_json.writeBoolField(writer, "pruned", result.pruned, true);
    try core_json.writeBoolField(writer, "compacted", result.compacted, true);
    try core_json.writeNullableStringField(writer, "backup_path", result.backup_path, true);
    try writer.writeAll("\"policy\":{");
    try core_json.writeIntField(writer, "snapshot_days", policy.snapshot_days, true);
    try core_json.writeIntField(writer, "provider_raw_days", policy.provider_raw_days, true);
    try core_json.writeIntField(writer, "metrics_days", policy.metrics_days, true);
    try core_json.writeIntField(writer, "batch_rows", policy.batch_rows, false);
    try writer.writeAll("},\"before\":");
    try writeStatsJson(result.before, writer);
    try writer.writeAll(",\"after\":");
    try writeStatsJson(result.after, writer);
    try writer.writeAll(",\"deleted\":{");
    try core_json.writeIntField(writer, "snapshots", result.deletedSnapshots(), true);
    try core_json.writeIntField(writer, "provider_raw", result.deletedProviderRaw(), true);
    try core_json.writeIntField(writer, "hostinger_metrics", result.deletedHostingerMetrics(), true);
    try core_json.writeIntField(writer, "system_metrics", result.deletedSystemMetrics(), false);
    try writer.writeAll("}}\n");
}

fn writeStatsText(label: []const u8, stats: Stats, writer: anytype) !void {
    try writer.print(
        "{s}: db_bytes={d} reclaimable_bytes={d} snapshots={d}/{d} provider_raw={d}/{d} hostinger_metrics={d}/{d} system_metrics={d}/{d}\n",
        .{
            label,
            stats.databaseBytes(),
            stats.reclaimableBytes(),
            stats.snapshots.total,
            stats.snapshots.eligible,
            stats.provider_raw.total,
            stats.provider_raw.eligible,
            stats.hostinger_metrics.total,
            stats.hostinger_metrics.eligible,
            stats.system_metrics.total,
            stats.system_metrics.eligible,
        },
    );
}

fn writeStatsJson(stats: Stats, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "database_bytes", stats.databaseBytes(), true);
    try core_json.writeIntField(writer, "reclaimable_bytes", stats.reclaimableBytes(), true);
    try core_json.writeIntField(writer, "page_size", stats.page_size, true);
    try core_json.writeIntField(writer, "page_count", stats.page_count, true);
    try core_json.writeIntField(writer, "freelist_pages", stats.freelist_pages, true);
    try writer.writeAll("\"snapshots\":");
    try writeTableStatsJson(stats.snapshots, writer);
    try writer.writeAll(",\"provider_raw\":");
    try writeTableStatsJson(stats.provider_raw, writer);
    try writer.writeAll(",\"hostinger_metrics\":");
    try writeTableStatsJson(stats.hostinger_metrics, writer);
    try writer.writeAll(",\"system_metrics\":");
    try writeTableStatsJson(stats.system_metrics, writer);
    try writer.writeByte('}');
}

fn writeTableStatsJson(stats: TableStats, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "total", stats.total, true);
    try core_json.writeIntField(writer, "eligible", stats.eligible, false);
    try writer.writeByte('}');
}

fn tableStats(db: *Db, total_sql: []const u8, eligible_sql: []const u8, days: u32) !TableStats {
    const stmt = try db.prepare(eligible_sql);
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, days) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return .{
        .total = try scalar(db, total_sql),
        .eligible = sqlite.sqlite3_column_int64(stmt, 0),
    };
}

fn scalar(db: *Db, sql: []const u8) !i64 {
    const stmt = try db.prepare(sql);
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return sqlite.sqlite3_column_int64(stmt, 0);
}

fn pruneBatches(db: *Db, sql: []const u8, days: u32, batch_rows: u32) !void {
    while (true) {
        const stmt = try db.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_bind_int64(stmt, 1, days) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_bind_int64(stmt, 2, @max(batch_rows, 1)) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
        if (sqlite.sqlite3_changes(db.handle) == 0) break;
    }
}

fn verifyDatabase(handle: *sqlite.sqlite3) bool {
    const sql = "PRAGMA integrity_check";
    var stmt: ?*sqlite.sqlite3_stmt = null;
    if (sqlite.sqlite3_prepare_v2(handle, sql, @intCast(sql.len), &stmt, null) != sqlite.SQLITE_OK) return false;
    defer _ = sqlite.sqlite3_finalize(stmt.?);
    if (sqlite.sqlite3_step(stmt.?) != sqlite.SQLITE_ROW) return false;
    const ptr = sqlite.sqlite3_column_text(stmt.?, 0) orelse return false;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt.?, 0));
    return std.mem.eql(u8, @as([*]const u8, @ptrCast(ptr))[0..len], "ok");
}

test "maintenance previews, backs up, prunes, and compacts safely" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(base);
    const db_path = try std.fmt.allocPrint(allocator, "{s}/maintenance.db", .{base});
    defer allocator.free(db_path);
    const backup_path = try std.fmt.allocPrint(allocator, "{s}/backup.db", .{base});
    defer allocator.free(backup_path);

    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.exec(
        \\INSERT INTO snapshots(source,kind,status,captured_at) VALUES ('system','old','ok','2020-01-01'),('system','new','ok',CURRENT_TIMESTAMP);
        \\INSERT INTO provider_raw(provider,endpoint,captured_at) VALUES ('cloudflare','old','2020-01-01'),('cloudflare','new',CURRENT_TIMESTAMP);
        \\INSERT INTO hostinger_metrics(vm_id,metric,captured_at) VALUES ('1','old','2020-01-01'),('1','new',CURRENT_TIMESTAMP);
        \\INSERT INTO system_metrics(metric,value,captured_at) VALUES ('old','1','2020-01-01'),('new','1',CURRENT_TIMESTAMP);
    );

    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .db = &db };
    const policy = Policy{ .snapshot_days = 7, .provider_raw_days = 7, .metrics_days = 7, .batch_rows = 1 };
    const preview = try execute(ctx, policy, .{ .operation = .run });
    try std.testing.expect(!preview.applied);
    try std.testing.expectEqual(@as(i64, 1), preview.before.snapshots.eligible);
    try std.testing.expectEqual(@as(i64, 2), preview.after.snapshots.total);

    try std.testing.expectError(Error.ApplyRequiresBackup, execute(ctx, policy, .{ .operation = .prune, .apply = true }));
    const applied = try execute(ctx, policy, .{ .operation = .run, .apply = true, .backup_path = backup_path });
    try std.testing.expect(applied.pruned);
    try std.testing.expect(applied.compacted);
    try std.testing.expectEqual(@as(i64, 1), applied.after.snapshots.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.provider_raw.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.hostinger_metrics.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.system_metrics.total);
    try std.testing.expect(try core_fs.fileExists(std.testing.io, backup_path));
    try std.testing.expectError(Error.BackupAlreadyExists, backup(ctx, backup_path));

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJson(applied, policy, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"deleted\":{\"snapshots\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"compacted\":true") != null);
}
