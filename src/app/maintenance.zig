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
    scheduled_retention_enabled: bool = false,
    database_path: []const u8 = ".cloudio/cloudio.db",
    backup_root: []const u8 = ".cloudio/backups",
    disk_budget_bytes: u64 = 0,
    log_path: []const u8 = ".cloudio/latest-run.log",
    snapshot_days: u32 = 14,
    provider_raw_days: u32 = 14,
    metrics_days: u32 = 30,
    nob_plan_days: u32 = 7,
    nob_operation_days: u32 = 30,
    nob_min_operations_per_project: u16 = 20,
    nob_state_root: []const u8 = ".cloudio/nob/operations",
    nob_cache_root: []const u8 = ".cloudio/nob/runners",
    batch_rows: u32 = 5000,

    pub fn fromConfig(config: core_config.Config) Policy {
        return .{
            .scheduled_retention_enabled = config.storage_auto_prune,
            .database_path = config.db_path,
            .backup_root = config.storage_backup_root,
            .disk_budget_bytes = config.storage_disk_budget_bytes,
            .log_path = config.log_path,
            .snapshot_days = config.snapshot_retention_days,
            .provider_raw_days = config.provider_raw_retention_days,
            .metrics_days = config.metrics_retention_days,
            .nob_plan_days = config.nob_plan_retention_days,
            .nob_operation_days = config.nob_operation_retention_days,
            .nob_min_operations_per_project = config.nob_min_operations_per_project,
            .nob_state_root = config.nob_state_root,
            .nob_cache_root = config.nob_cache_root,
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

pub const FileInventory = struct {
    files: i64 = 0,
    bytes: i64 = 0,
};

pub const Stats = struct {
    snapshots: TableStats = .{},
    provider_raw: TableStats = .{},
    hostinger_metrics: TableStats = .{},
    system_metrics: TableStats = .{},
    nob_plans: TableStats = .{},
    nob_operations: TableStats = .{},
    page_size: i64 = 0,
    page_count: i64 = 0,
    freelist_pages: i64 = 0,
    database_file_bytes: i64 = 0,
    wal_bytes: i64 = 0,
    shm_bytes: i64 = 0,
    log_bytes: i64 = 0,
    backups: FileInventory = .{},
    nob_operation_state: FileInventory = .{},
    nob_runner_cache: FileInventory = .{},
    disk_budget_bytes: i64 = 0,

    pub fn databaseBytes(self: Stats) i64 {
        return self.page_size * self.page_count;
    }

    pub fn reclaimableBytes(self: Stats) i64 {
        return self.page_size * self.freelist_pages;
    }

    pub fn managedBytes(self: Stats) i64 {
        var total = self.database_file_bytes;
        total +|= self.wal_bytes;
        total +|= self.shm_bytes;
        total +|= self.log_bytes;
        total +|= self.backups.bytes;
        total +|= self.nob_operation_state.bytes;
        total +|= self.nob_runner_cache.bytes;
        return total;
    }

    /// A maintenance run writes one verified database backup before VACUUM,
    /// which may itself need another database-sized temporary file. The WAL is
    /// included so the recommendation remains useful during active writes.
    pub fn maintenanceHeadroomBytes(self: Stats) i64 {
        const database = @max(self.database_file_bytes, self.databaseBytes());
        return (database *| 2) +| self.wal_bytes;
    }

    pub fn budgetWarning(self: Stats) bool {
        if (self.disk_budget_bytes <= 0) return false;
        const warning_threshold = self.disk_budget_bytes - @divTrunc(self.disk_budget_bytes, 5);
        return self.managedBytes() >= warning_threshold or
            self.managedBytes() +| self.maintenanceHeadroomBytes() > self.disk_budget_bytes;
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

    pub fn deletedNobPlans(self: Result) i64 {
        return self.before.nob_plans.total - self.after.nob_plans.total;
    }

    pub fn deletedNobOperations(self: Result) i64 {
        return self.before.nob_operations.total - self.after.nob_operations.total;
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
    NobStateRootUnsafe,
    NobOperationStatePathUnsafe,
    StorageRootUnsafe,
    StorageInventoryTooLarge,
    ScheduledRetentionDisabled,
};

pub fn execute(ctx: Context, policy: Policy, options: Options) !Result {
    const before = try inspect(ctx, policy);
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
        try prune(ctx, policy);
        result.pruned = true;
    }
    if (options.operation == .compact or options.operation == .run) {
        try compact(ctx.db);
        result.compacted = true;
    }
    result.after = try inspect(ctx, policy);
    return result;
}

pub fn inspect(ctx: Context, policy: Policy) !Stats {
    const db = ctx.db;
    var stats = Stats{
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
        .nob_plans = try nobPlanStats(db, policy.nob_plan_days),
        .nob_operations = try nobOperationStats(db, policy.nob_operation_days, policy.nob_min_operations_per_project),
        .page_size = try scalar(db, "PRAGMA page_size"),
        .page_count = try scalar(db, "PRAGMA page_count"),
        .freelist_pages = try scalar(db, "PRAGMA freelist_count"),
    };
    stats.database_file_bytes = try fileBytes(ctx.io, policy.database_path);
    const wal_path = try std.fmt.allocPrint(ctx.gpa, "{s}-wal", .{policy.database_path});
    defer ctx.gpa.free(wal_path);
    stats.wal_bytes = try fileBytes(ctx.io, wal_path);
    const shm_path = try std.fmt.allocPrint(ctx.gpa, "{s}-shm", .{policy.database_path});
    defer ctx.gpa.free(shm_path);
    stats.shm_bytes = try fileBytes(ctx.io, shm_path);
    stats.log_bytes = try fileBytes(ctx.io, policy.log_path);
    stats.backups = try inventory(ctx, policy.backup_root);
    stats.nob_operation_state = try inventory(ctx, policy.nob_state_root);
    stats.nob_runner_cache = try inventory(ctx, policy.nob_cache_root);
    stats.disk_budget_bytes = @intCast(@min(policy.disk_budget_bytes, @as(u64, std.math.maxInt(i64))));
    return stats;
}

/// The scheduler must use this guarded entry point. Merely calling the
/// scheduler cannot activate retention when no operator policy was enabled.
pub fn pruneScheduled(ctx: Context, policy: Policy) !void {
    if (!policy.scheduled_retention_enabled) return Error.ScheduledRetentionDisabled;
    try prune(ctx, policy);
}

/// Prune eligible rows in bounded transactions. Callers are responsible for
/// requiring a backup for manual runs or explicitly enabling scheduled prune.
pub fn prune(ctx: Context, policy: Policy) !void {
    const db = ctx.db;
    const canonical_state_root = try canonicalNobStateRoot(ctx, policy.nob_state_root);
    defer if (canonical_state_root) |path| ctx.gpa.free(path);
    try pruneBatches(
        db,
        "DELETE FROM snapshots WHERE id IN (SELECT id FROM snapshots WHERE captured_at < datetime('now', '-' || ? || ' days') LIMIT ?)",
        policy.snapshot_days,
        policy.batch_rows,
    );
    try pruneNobOperationBatches(ctx, policy, canonical_state_root);
    try expireReadyNobPlans(db);
    try pruneBatches(
        db,
        \\DELETE FROM project_plans WHERE id IN (
        \\  SELECT p.id FROM project_plans p
        \\  WHERE p.created_at < CAST(strftime('%s','now') AS INTEGER) - (? * 86400)
        \\    AND p.state != 'ready'
        \\    AND NOT EXISTS (SELECT 1 FROM project_operations o WHERE o.plan_id=p.id)
        \\  ORDER BY p.created_at, p.id LIMIT ?
        \\)
    ,
        policy.nob_plan_days,
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
    try file.setPermissions(ctx.io, @fromBackingInt(@intCast(0o600)));
}

pub fn writeText(result: Result, policy: Policy, writer: anytype) !void {
    try writer.print("maintenance {s}: {s}\n", .{ result.operation.text(), if (result.applied) "applied" else "preview" });
    try writer.print("storage policy: scheduled_retention={s} backup_retention=operator-managed backup_root={s} disk_budget_bytes={d}\n", .{
        if (policy.scheduled_retention_enabled) "enabled" else "disabled",
        policy.backup_root,
        policy.disk_budget_bytes,
    });
    try writer.print("retention: snapshots={d}d provider_raw={d}d metrics={d}d nob_plans={d}d nob_operations={d}d keep_operations={d} batch={d}\n", .{
        policy.snapshot_days,
        policy.provider_raw_days,
        policy.metrics_days,
        policy.nob_plan_days,
        policy.nob_operation_days,
        policy.nob_min_operations_per_project,
        policy.batch_rows,
    });
    if (result.backup_path) |path| try writer.print("backup: {s}\n", .{path});
    try writeStatsText("before", result.before, writer);
    if (result.applied) {
        try writeStatsText("after", result.after, writer);
        try writer.print("deleted: snapshots={d} provider_raw={d} hostinger_metrics={d} system_metrics={d} nob_plans={d} nob_operations={d}\n", .{
            result.deletedSnapshots(),
            result.deletedProviderRaw(),
            result.deletedHostingerMetrics(),
            result.deletedSystemMetrics(),
            result.deletedNobPlans(),
            result.deletedNobOperations(),
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
    try core_json.writeBoolField(writer, "scheduled_retention_enabled", policy.scheduled_retention_enabled, true);
    try core_json.writeStringField(writer, "backup_retention", "operator-managed", true);
    try core_json.writeStringField(writer, "backup_root", policy.backup_root, true);
    try core_json.writeIntField(writer, "disk_budget_bytes", policy.disk_budget_bytes, true);
    try core_json.writeIntField(writer, "snapshot_days", policy.snapshot_days, true);
    try core_json.writeIntField(writer, "provider_raw_days", policy.provider_raw_days, true);
    try core_json.writeIntField(writer, "metrics_days", policy.metrics_days, true);
    try core_json.writeIntField(writer, "nob_plan_days", policy.nob_plan_days, true);
    try core_json.writeIntField(writer, "nob_operation_days", policy.nob_operation_days, true);
    try core_json.writeIntField(writer, "nob_min_operations_per_project", policy.nob_min_operations_per_project, true);
    try core_json.writeIntField(writer, "batch_rows", policy.batch_rows, false);
    try writer.writeAll("},\"before\":");
    try writeStatsJson(result.before, writer);
    try writer.writeAll(",\"after\":");
    try writeStatsJson(result.after, writer);
    try writer.writeAll(",\"deleted\":{");
    try core_json.writeIntField(writer, "snapshots", result.deletedSnapshots(), true);
    try core_json.writeIntField(writer, "provider_raw", result.deletedProviderRaw(), true);
    try core_json.writeIntField(writer, "hostinger_metrics", result.deletedHostingerMetrics(), true);
    try core_json.writeIntField(writer, "system_metrics", result.deletedSystemMetrics(), true);
    try core_json.writeIntField(writer, "nob_plans", result.deletedNobPlans(), true);
    try core_json.writeIntField(writer, "nob_operations", result.deletedNobOperations(), false);
    try writer.writeAll("}}\n");
}

fn writeStatsText(label: []const u8, stats: Stats, writer: anytype) !void {
    try writer.print(
        "{s} storage: database_file_bytes={d} wal_bytes={d} shm_bytes={d} log_bytes={d} backups={d}/{d} nob_operation_state={d}/{d} nob_runner_cache={d}/{d} managed_bytes={d} maintenance_headroom_bytes={d} disk_budget_bytes={d} budget_warning={}\n",
        .{
            label,
            stats.database_file_bytes,
            stats.wal_bytes,
            stats.shm_bytes,
            stats.log_bytes,
            stats.backups.files,
            stats.backups.bytes,
            stats.nob_operation_state.files,
            stats.nob_operation_state.bytes,
            stats.nob_runner_cache.files,
            stats.nob_runner_cache.bytes,
            stats.managedBytes(),
            stats.maintenanceHeadroomBytes(),
            stats.disk_budget_bytes,
            stats.budgetWarning(),
        },
    );
    try writer.print(
        "{s} rows: db_logical_bytes={d} reclaimable_bytes={d} snapshots={d}/{d} provider_raw={d}/{d} hostinger_metrics={d}/{d} system_metrics={d}/{d} nob_plans={d}/{d} nob_operations={d}/{d}\n",
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
            stats.nob_plans.total,
            stats.nob_plans.eligible,
            stats.nob_operations.total,
            stats.nob_operations.eligible,
        },
    );
}

fn writeStatsJson(stats: Stats, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "database_bytes", stats.databaseBytes(), true);
    try core_json.writeIntField(writer, "database_file_bytes", stats.database_file_bytes, true);
    try core_json.writeIntField(writer, "wal_bytes", stats.wal_bytes, true);
    try core_json.writeIntField(writer, "shm_bytes", stats.shm_bytes, true);
    try core_json.writeIntField(writer, "log_bytes", stats.log_bytes, true);
    try core_json.writeIntField(writer, "managed_bytes", stats.managedBytes(), true);
    try core_json.writeIntField(writer, "maintenance_headroom_bytes", stats.maintenanceHeadroomBytes(), true);
    try core_json.writeIntField(writer, "disk_budget_bytes", stats.disk_budget_bytes, true);
    try core_json.writeBoolField(writer, "budget_warning", stats.budgetWarning(), true);
    try writer.writeAll("\"backups\":");
    try writeFileInventoryJson(stats.backups, writer);
    try writer.writeAll(",\"nob_operation_state\":");
    try writeFileInventoryJson(stats.nob_operation_state, writer);
    try writer.writeAll(",\"nob_runner_cache\":");
    try writeFileInventoryJson(stats.nob_runner_cache, writer);
    try writer.writeByte(',');
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
    try writer.writeAll(",\"nob_plans\":");
    try writeTableStatsJson(stats.nob_plans, writer);
    try writer.writeAll(",\"nob_operations\":");
    try writeTableStatsJson(stats.nob_operations, writer);
    try writer.writeByte('}');
}

fn writeFileInventoryJson(inventory_value: FileInventory, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "files", inventory_value.files, true);
    try core_json.writeIntField(writer, "bytes", inventory_value.bytes, false);
    try writer.writeByte('}');
}

fn writeTableStatsJson(stats: TableStats, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "total", stats.total, true);
    try core_json.writeIntField(writer, "eligible", stats.eligible, false);
    try writer.writeByte('}');
}

const nob_operation_ranked_sql =
    \\WITH ranked AS (
    \\  SELECT id,
    \\         ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY queued_at DESC, id DESC) AS retention_rank
    \\  FROM project_operations
    \\)
;

const nob_operation_eligible_where =
    \\ FROM project_operations operation
    \\ JOIN ranked ON ranked.id=operation.id
    \\ WHERE operation.state NOT IN ('queued','running')
    \\   AND operation.finished_at IS NOT NULL
    \\   AND operation.finished_at < CAST(strftime('%s','now') AS INTEGER) - (? * 86400)
    \\   AND ranked.retention_rank > ?
    \\   AND NOT EXISTS (
    \\     SELECT 1 FROM project_managed_units managed
    \\     WHERE managed.installed_operation_id=operation.id
    \\   )
    \\   AND NOT EXISTS (
    \\     SELECT 1 FROM project_managed_routes managed
    \\     WHERE managed.installed_operation_id=operation.id
    \\   )
;

fn nobPlanStats(db: *Db, days: u32) !TableStats {
    const stmt = try db.prepare(
        \\SELECT COUNT(*) FROM project_plans plan
        \\WHERE plan.created_at < CAST(strftime('%s','now') AS INTEGER) - (? * 86400)
        \\  AND (plan.state != 'ready' OR plan.expires_at <= CAST(strftime('%s','now') AS INTEGER))
        \\  AND NOT EXISTS (SELECT 1 FROM project_operations operation WHERE operation.plan_id=plan.id)
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, days) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return .{
        .total = try scalar(db, "SELECT COUNT(*) FROM project_plans"),
        .eligible = sqlite.sqlite3_column_int64(stmt, 0),
    };
}

fn nobOperationStats(db: *Db, days: u32, minimum_per_project: u16) !TableStats {
    const stmt = try db.prepare(nob_operation_ranked_sql ++ "SELECT COUNT(*)" ++ nob_operation_eligible_where);
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, days) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 2, minimum_per_project) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return .{
        .total = try scalar(db, "SELECT COUNT(*) FROM project_operations"),
        .eligible = sqlite.sqlite3_column_int64(stmt, 0),
    };
}

const OperationPrune = struct {
    id: []u8,
    state_path: ?[:0]u8,

    fn deinit(self: OperationPrune, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.state_path) |path| allocator.free(path);
    }
};

fn pruneNobOperationBatches(ctx: Context, policy: Policy, state_root: ?[:0]const u8) !void {
    while (true) {
        const batch = try loadNobOperationBatch(ctx, policy, state_root);
        defer {
            for (batch) |item| item.deinit(ctx.gpa);
            ctx.gpa.free(batch);
        }
        if (batch.len == 0) break;

        try ctx.db.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
        const stmt = try ctx.db.prepare("DELETE FROM project_operations WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        for (batch) |item| {
            _ = sqlite.sqlite3_reset(stmt);
            _ = sqlite.sqlite3_clear_bindings(stmt);
            try bindText(stmt, 1, item.id);
            if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
            if (sqlite.sqlite3_changes(ctx.db.handle) != 1) return Error.SqliteStep;
        }
        try ctx.db.exec("COMMIT");
        committed = true;

        for (batch) |item| if (item.state_path) |path| {
            try Io.Dir.cwd().deleteTree(ctx.io, path);
        };
    }
}

fn loadNobOperationBatch(ctx: Context, policy: Policy, state_root: ?[:0]const u8) ![]OperationPrune {
    const stmt = try ctx.db.prepare(
        nob_operation_ranked_sql ++ "SELECT operation.id" ++ nob_operation_eligible_where ++
            " ORDER BY operation.finished_at, operation.id LIMIT ?",
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, policy.nob_operation_days) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 2, policy.nob_min_operations_per_project) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 3, @max(policy.batch_rows, 1)) != sqlite.SQLITE_OK) return Error.SqliteBind;

    var items = std.ArrayList(OperationPrune).empty;
    errdefer {
        for (items.items) |item| item.deinit(ctx.gpa);
        items.deinit(ctx.gpa);
    }
    while (true) switch (sqlite.sqlite3_step(stmt)) {
        sqlite.SQLITE_ROW => {
            const id = try ctx.gpa.dupe(u8, columnText(stmt, 0) orelse return Error.SqliteStep);
            errdefer ctx.gpa.free(id);
            const state_path = if (state_root) |root| try nobOperationStatePath(ctx, root, id) else null;
            errdefer if (state_path) |path| ctx.gpa.free(path);
            try items.append(ctx.gpa, .{ .id = id, .state_path = state_path });
        },
        sqlite.SQLITE_DONE => break,
        else => return Error.SqliteStep,
    };
    return try items.toOwnedSlice(ctx.gpa);
}

fn expireReadyNobPlans(db: *Db) !void {
    const stmt = try db.prepare(
        "UPDATE project_plans SET state='expired' WHERE state='ready' AND expires_at<=CAST(strftime('%s','now') AS INTEGER)",
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
}

fn canonicalNobStateRoot(ctx: Context, configured: []const u8) !?[:0]u8 {
    const stat = Io.Dir.cwd().statFile(ctx.io, configured, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (stat.kind != .directory) return Error.NobStateRootUnsafe;
    const canonical = try Io.Dir.cwd().realPathFileAlloc(ctx.io, configured, ctx.gpa);
    errdefer ctx.gpa.free(canonical);
    if (std.mem.eql(u8, canonical, "/")) return Error.NobStateRootUnsafe;
    return canonical;
}

fn nobOperationStatePath(ctx: Context, state_root: []const u8, operation_id: []const u8) !?[:0]u8 {
    if (!safeOperationId(operation_id)) return null;
    const candidate = try std.fs.path.join(ctx.gpa, &.{ state_root, operation_id });
    defer ctx.gpa.free(candidate);
    const stat = Io.Dir.cwd().statFile(ctx.io, candidate, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (stat.kind != .directory) return Error.NobOperationStatePathUnsafe;
    const canonical = try Io.Dir.cwd().realPathFileAlloc(ctx.io, candidate, ctx.gpa);
    errdefer ctx.gpa.free(canonical);
    if (!strictDescendant(state_root, canonical)) return Error.NobOperationStatePathUnsafe;
    return canonical;
}

fn safeOperationId(value: []const u8) bool {
    if (value.len != 26) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte) and !(byte >= 'A' and byte <= 'Z')) return false;
    return true;
}

fn strictDescendant(root: []const u8, path: []const u8) bool {
    return path.len > root.len and std.mem.startsWith(u8, path, root) and path[root.len] == std.fs.path.sep;
}

fn bindText(stmt: *sqlite.sqlite3_stmt, index: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, index, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) {
        return Error.SqliteBind;
    }
}

fn columnText(stmt: *sqlite.sqlite3_stmt, index: c_int) ?[]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, index) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, index));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
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

const max_inventory_files: i64 = 100_000;
const max_inventory_depth: u8 = 32;

fn fileBytes(io: Io, path: []const u8) !i64 {
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    if (stat.kind != .file) return 0;
    return @intCast(@min(stat.size, @as(u64, std.math.maxInt(i64))));
}

fn inventory(ctx: Context, root: []const u8) !FileInventory {
    const stat = Io.Dir.cwd().statFile(ctx.io, root, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    if (stat.kind != .directory) return Error.StorageRootUnsafe;
    var result = FileInventory{};
    try inventoryDirectory(ctx, root, 0, &result);
    return result;
}

fn inventoryDirectory(ctx: Context, path: []const u8, depth: u8, result: *FileInventory) !void {
    if (depth >= max_inventory_depth) return Error.StorageInventoryTooLarge;
    var directory = try Io.Dir.cwd().openDir(ctx.io, path, .{ .iterate = true });
    defer directory.close(ctx.io);
    var iterator = directory.iterate();
    while (try iterator.next(ctx.io)) |entry| {
        const child = try std.fs.path.join(ctx.gpa, &.{ path, entry.name });
        defer ctx.gpa.free(child);
        const stat = try Io.Dir.cwd().statFile(ctx.io, child, .{ .follow_symlinks = false });
        if (stat.kind == .directory) {
            try inventoryDirectory(ctx, child, depth + 1, result);
        } else if (stat.kind == .file) {
            if (result.files >= max_inventory_files) return Error.StorageInventoryTooLarge;
            result.files += 1;
            result.bytes +|= @intCast(@min(stat.size, @as(u64, std.math.maxInt(i64))));
        }
        // Symlinks and special files are never followed or counted.
    }
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
    const backup_root = try std.fmt.allocPrint(allocator, "{s}/backups", .{base});
    defer allocator.free(backup_root);
    const backup_path = try std.fmt.allocPrint(allocator, "{s}/before-maintenance.db", .{backup_root});
    defer allocator.free(backup_path);
    const retained_backup = try std.fmt.allocPrint(allocator, "{s}/retained.db", .{backup_root});
    defer allocator.free(retained_backup);
    const nob_state_root = try std.fmt.allocPrint(allocator, "{s}/operations", .{base});
    defer allocator.free(nob_state_root);
    const nob_cache_root = try std.fmt.allocPrint(allocator, "{s}/runner-cache", .{base});
    defer allocator.free(nob_cache_root);
    const cache_marker = try std.fmt.allocPrint(allocator, "{s}/runner.bin", .{nob_cache_root});
    defer allocator.free(cache_marker);
    const log_path = try std.fmt.allocPrint(allocator, "{s}/cloudio.log", .{base});
    defer allocator.free(log_path);
    const operation_prefix = "01ARZ3NDEKTSV4RRFFQ69G5F";
    const retained_operation = operation_prefix ++ "01";
    const pruned_operation = operation_prefix ++ "02";
    const retained_state = try std.fs.path.join(allocator, &.{ nob_state_root, retained_operation });
    defer allocator.free(retained_state);
    const pruned_state = try std.fs.path.join(allocator, &.{ nob_state_root, pruned_operation });
    defer allocator.free(pruned_state);
    try Io.Dir.cwd().createDirPath(std.testing.io, retained_state);
    try Io.Dir.cwd().createDirPath(std.testing.io, pruned_state);
    const retained_marker = try std.fs.path.join(allocator, &.{ retained_state, "events.ndjson" });
    defer allocator.free(retained_marker);
    const pruned_marker = try std.fs.path.join(allocator, &.{ pruned_state, "events.ndjson" });
    defer allocator.free(pruned_marker);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = retained_marker, .data = "retained" });
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = pruned_marker, .data = "pruned" });
    try core_fs.ensureParentDir(std.testing.io, retained_backup);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = retained_backup, .data = "operator-owned-backup" });
    try core_fs.ensureParentDir(std.testing.io, cache_marker);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = cache_marker, .data = "runner-cache" });
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = log_path, .data = "latest log" });

    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.exec(
        \\INSERT INTO snapshots(source,kind,status,captured_at) VALUES ('system','old','ok','2020-01-01'),('system','new','ok',CURRENT_TIMESTAMP);
        \\INSERT INTO provider_raw(provider,endpoint,captured_at) VALUES ('cloudflare','old','2020-01-01'),('cloudflare','new',CURRENT_TIMESTAMP);
        \\INSERT INTO hostinger_metrics(vm_id,metric,captured_at) VALUES ('1','old','2020-01-01'),('1','new',CURRENT_TIMESTAMP);
        \\INSERT INTO system_metrics(metric,value,captured_at) VALUES ('old','1','2020-01-01'),('new','1',CURRENT_TIMESTAMP);
        \\INSERT INTO audit_actions(kind,result,created_at) VALUES ('fixture.required','ok','2020-01-01');
        \\INSERT INTO audit_events(action,status,created_at) VALUES ('fixture.required','error','2020-01-01');
        \\INSERT INTO managed_projects(
        \\  id, declared_id, display_name, kind, root_path, discovery_state,
        \\  trust_state, last_seen_at, created_at, updated_at
        \\) VALUES(1, 'dev.example.retention', 'Retention', 'service', '/srv/retention',
        \\  'valid', 'trusted', 1, 1, 1);
        \\INSERT INTO project_plans(
        \\  id, project_id, action_id, input_json, plan_json, plan_sha256,
        \\  manifest_sha256, source_fingerprint, effect, confirmation, state,
        \\  requested_by, created_at, expires_at, consumed_at
        \\) VALUES
        \\  ('plan-protected',1,'deploy','{}','{}','digest','digest','source','runtime-change','review-plan','consumed','test',1,2,2),
        \\  ('plan-pruned',1,'deploy','{}','{}','digest','digest','source','runtime-change','review-plan','consumed','test',1,2,2),
        \\  ('plan-unreferenced',1,'deploy','{}','{}','digest','digest','source','runtime-change','review-plan','expired','test',1,2,NULL);
    );
    var operation_index: u8 = 1;
    while (operation_index <= 22) : (operation_index += 1) {
        var operation_id: [26]u8 = undefined;
        @memcpy(operation_id[0..operation_prefix.len], operation_prefix);
        operation_id[24] = '0' + operation_index / 10;
        operation_id[25] = '0' + operation_index % 10;
        const plan_id = if (operation_index == 1) "'plan-protected'" else if (operation_index == 2) "'plan-pruned'" else "NULL";
        var insert_buffer: [1024:0]u8 = undefined;
        const insert = try std.fmt.bufPrint(
            insert_buffer[0..insert_buffer.len],
            "INSERT INTO project_operations(id,project_id,plan_id,action_id,state,outcome,effect,requested_by,queued_at,finished_at) VALUES('{s}',1,{s},'deploy','succeeded','succeeded','runtime-change','test',{d},1)",
            .{ &operation_id, plan_id, operation_index },
        );
        insert_buffer[insert.len] = 0;
        try db.exec(insert_buffer[0..insert.len :0]);
    }
    try db.exec(
        \\INSERT INTO project_managed_units(
        \\  project_id, resource_id, scope, unit, fragment_path, sha256,
        \\  installed_operation_id, updated_at
        \\) VALUES(1, 'service', 'user', 'retention.service',
        \\  '/home/test/.config/systemd/user/retention.service', 'digest',
        \\  '01ARZ3NDEKTSV4RRFFQ69G5F01', 2);
    );
    try db.nob().appendRunEvent(.{
        .operation_id = pruned_operation,
        .seq = 1,
        .event_type = "log",
        .level = "info",
        .payload_json = "{}",
        .received_at = 1,
    });
    try db.nob().appendArtifact(.{
        .operation_id = pruned_operation,
        .resource_id = null,
        .artifact_id = "old-artifact",
        .role = "test",
        .path = pruned_marker,
        .sha256 = "digest",
        .size_bytes = 6,
        .metadata_json = null,
        .created_at = 1,
    });

    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .db = &db };
    const policy = Policy{
        .database_path = db_path,
        .backup_root = backup_root,
        .disk_budget_bytes = 1,
        .log_path = log_path,
        .snapshot_days = 7,
        .provider_raw_days = 7,
        .metrics_days = 7,
        .nob_plan_days = 7,
        .nob_operation_days = 7,
        .nob_min_operations_per_project = 20,
        .nob_state_root = nob_state_root,
        .nob_cache_root = nob_cache_root,
        .batch_rows = 1,
    };
    const preview = try execute(ctx, policy, .{ .operation = .run });
    try std.testing.expect(!preview.applied);
    try std.testing.expectEqual(@as(i64, 1), preview.before.snapshots.eligible);
    try std.testing.expectEqual(@as(i64, 2), preview.after.snapshots.total);
    try std.testing.expectEqual(@as(i64, 1), preview.before.nob_plans.eligible);
    try std.testing.expectEqual(@as(i64, 1), preview.before.nob_operations.eligible);
    try std.testing.expectEqual(@as(i64, 1), preview.before.backups.files);
    try std.testing.expect(preview.before.nob_operation_state.bytes > 0);
    try std.testing.expect(preview.before.nob_runner_cache.bytes > 0);
    try std.testing.expect(preview.before.log_bytes > 0);
    try std.testing.expect(preview.before.budgetWarning());
    try std.testing.expectError(Error.ScheduledRetentionDisabled, pruneScheduled(ctx, policy));

    try std.testing.expectError(Error.ApplyRequiresBackup, execute(ctx, policy, .{ .operation = .prune, .apply = true }));
    const applied = try execute(ctx, policy, .{ .operation = .run, .apply = true, .backup_path = backup_path });
    try std.testing.expect(applied.pruned);
    try std.testing.expect(applied.compacted);
    try std.testing.expectEqual(@as(i64, 1), applied.after.snapshots.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.provider_raw.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.hostinger_metrics.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.system_metrics.total);
    try std.testing.expectEqual(@as(i64, 1), applied.after.nob_plans.total);
    try std.testing.expectEqual(@as(i64, 21), applied.after.nob_operations.total);
    try std.testing.expectEqual(@as(i64, 1), try scalar(&db, "SELECT COUNT(*) FROM audit_actions"));
    try std.testing.expectEqual(@as(i64, 1), try scalar(&db, "SELECT COUNT(*) FROM audit_events"));
    try std.testing.expectEqual(@as(i64, 2), applied.deletedNobPlans());
    try std.testing.expectEqual(@as(i64, 1), applied.deletedNobOperations());
    try std.testing.expect(try core_fs.fileExists(std.testing.io, retained_marker));
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().statFile(std.testing.io, pruned_state, .{ .follow_symlinks = false }));
    var deleted_events = try db.nob().listRunEvents(allocator, pruned_operation);
    defer deleted_events.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), deleted_events.items.len);
    var deleted_artifacts = try db.nob().listArtifacts(allocator, pruned_operation);
    defer deleted_artifacts.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), deleted_artifacts.items.len);
    try std.testing.expect(try core_fs.fileExists(std.testing.io, backup_path));
    try std.testing.expect(try core_fs.fileExists(std.testing.io, retained_backup));
    try std.testing.expectEqual(@as(i64, 2), applied.after.backups.files);
    try std.testing.expectError(Error.BackupAlreadyExists, backup(ctx, backup_path));

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJson(applied, policy, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"deleted\":{\"snapshots\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"compacted\":true") != null);
}

test "verified backup and maintenance survive interruption and database reopen" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(base);
    const db_path = try std.fmt.allocPrint(allocator, "{s}/reopen.db", .{base});
    defer allocator.free(db_path);
    const backup_root = try std.fmt.allocPrint(allocator, "{s}/backups", .{base});
    defer allocator.free(backup_root);
    const interrupted_backup = try std.fmt.allocPrint(allocator, "{s}/before-interruption.db", .{backup_root});
    defer allocator.free(interrupted_backup);
    const maintenance_backup = try std.fmt.allocPrint(allocator, "{s}/before-run.db", .{backup_root});
    defer allocator.free(maintenance_backup);
    const missing_state = try std.fmt.allocPrint(allocator, "{s}/operations", .{base});
    defer allocator.free(missing_state);
    const missing_cache = try std.fmt.allocPrint(allocator, "{s}/cache", .{base});
    defer allocator.free(missing_cache);

    var database = try Db.open(std.testing.io, db_path);
    try database.initSchema();
    try database.exec(
        "INSERT INTO snapshots(source,kind,status,captured_at) VALUES ('system','old','ok','2020-01-01'),('system','new','ok',CURRENT_TIMESTAMP)",
    );
    const policy = Policy{
        .database_path = db_path,
        .backup_root = backup_root,
        .snapshot_days = 1,
        .provider_raw_days = 1,
        .metrics_days = 1,
        .nob_plan_days = 1,
        .nob_operation_days = 1,
        .nob_state_root = missing_state,
        .nob_cache_root = missing_cache,
    };
    try backup(.{ .io = std.testing.io, .gpa = allocator, .db = &database }, interrupted_backup);
    // Closing here models a process interruption after the required recovery
    // point exists but before any prune or VACUUM starts.
    database.close();

    var recovery = try Db.open(std.testing.io, interrupted_backup);
    try std.testing.expectEqual(@as(i64, 2), try scalar(&recovery, "SELECT COUNT(*) FROM snapshots"));
    recovery.close();

    var reopened = try Db.open(std.testing.io, db_path);
    const applied = try execute(
        .{ .io = std.testing.io, .gpa = allocator, .db = &reopened },
        policy,
        .{ .operation = .run, .apply = true, .backup_path = maintenance_backup },
    );
    try std.testing.expect(applied.pruned and applied.compacted);
    reopened.close();

    var verified = try Db.open(std.testing.io, db_path);
    defer verified.close();
    try std.testing.expectEqual(@as(i64, 1), try scalar(&verified, "SELECT COUNT(*) FROM snapshots"));
    try std.testing.expect(try core_fs.fileExists(std.testing.io, interrupted_backup));
    try std.testing.expect(try core_fs.fileExists(std.testing.io, maintenance_backup));
}
