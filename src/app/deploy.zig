//! C1: git-build deploy pipeline for binary apps.
//!
//! Layout per app under config.apps_root/<name>:
//!   src/                    git checkout (repo_url apps only)
//!   releases/<sha|deploy-N>/<binary>
//!   current -> releases/<label>   (relative symlink, atomically swapped)
//!   deploy-<id>.log
//!
//! Node apps are the exception: no binary artifact is produced, so `current`
//! points directly at the source checkout and the unit runs `node <dir>`.
const std = @import("std");
const sqlite = @import("sqlite");
const app_caddy_desired = @import("app_caddy_desired");
const app_system_control = @import("app_system_control");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_fs = @import("core_fs");
const core_json = @import("core_json");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

const max_command_bytes = 4 * 1024 * 1024;
const max_log_tail_bytes = 512 * 1024;
const max_name_len = 32;
const health_check_tries = 10;

pub const Error = error{
    SqliteBind,
    SqliteStep,
    InvalidName,
    AppNotFound,
    AppExists,
    SourceRequired,
    SourceConflict,
    WorkdirMissing,
    NoFreePort,
    UnknownToolchain,
    CommandFailed,
    ArtifactNotFound,
    ArtifactAmbiguous,
    DeployNotFound,
    NoRollbackTarget,
    ReleaseMissing,
    AppBusy,
    UnsafeCleanupPath,
};

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: app_writes.Metadata = .{},
};

pub const DeployOptions = struct {
    unit_dir: []const u8 = "/etc/systemd/system",
    run_systemd: bool = true,
    health_check: bool = true,
    health_check_tries: usize = health_check_tries,
    auto_rollback: bool = true,
};

pub const DeleteOptions = struct {
    unit_dir: []const u8 = "/etc/systemd/system",
    run_systemd: bool = true,
    remove_files: bool = true,
};

pub const Toolchain = enum {
    zig,
    go,
    rust,
    node,
    prebuilt,

    pub fn parse(text: []const u8) ?Toolchain {
        return std.meta.stringToEnum(Toolchain, text);
    }
};

const AppRow = struct {
    id: i64,
    name: []const u8,
    repo_url: ?[]const u8,
    workdir: ?[]const u8,
    toolchain: ?[]const u8,
    port: i64,
    alias_host: []const u8,
    env_json: ?[]const u8,
    status: []const u8,
    current_deploy_id: ?i64,
};

fn caddyCtx(ctx: Context) app_caddy_desired.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .write_meta = ctx.write_meta };
}

fn systemCtx(ctx: Context) app_system_control.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .write_meta = ctx.write_meta };
}

// --- App CRUD ---

/// App names are stricter than unit names: lowercase [a-z0-9-], max 32 chars,
/// so they can be embedded in hostnames.
pub fn isValidAppName(name: []const u8) bool {
    if (name.len == 0 or name.len > max_name_len) return false;
    for (name) |ch| {
        switch (ch) {
            'a'...'z', '0'...'9', '-' => {},
            else => return false,
        }
    }
    return true;
}

pub fn registerApp(ctx: Context, name: []const u8, repo_url: ?[]const u8, workdir: ?[]const u8, writer: anytype) !void {
    if (!isValidAppName(name)) return Error.InvalidName;
    if (repo_url == null and workdir == null) return Error.SourceRequired;
    if (repo_url != null and workdir != null) return Error.SourceConflict;
    if (workdir) |dir| {
        if (!try dirExists(ctx.io, dir)) return Error.WorkdirMissing;
    }

    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    if (try loadApp(ctx, a, name) != null) return Error.AppExists;

    const primary_domain = if (ctx.config.domains.len > 0) ctx.config.domains[0] else "localhost";
    const alias_host = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, primary_domain });
    const port = try assignPort(ctx);

    const stmt = try ctx.db.prepare(
        \\INSERT INTO apps(name, repo_url, workdir, port, alias_host, status)
        \\VALUES (?, ?, ?, ?, ?, 'registered')
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, name);
    try bindTextOpt(stmt, 2, repo_url);
    try bindTextOpt(stmt, 3, workdir);
    if (sqlite.sqlite3_bind_int64(stmt, 4, port) != sqlite.SQLITE_OK) return Error.SqliteBind;
    try bindText(stmt, 5, alias_host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;

    const detail = try std.fmt.allocPrint(a, "registered; port={d}; alias={s}; source={s}", .{
        port,
        alias_host,
        if (repo_url) |u| u else workdir.?,
    });
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "app.register", name, null, .ok, detail);

    try writeAppsJson(ctx, writer);
}

/// Stops/removes the app unit, removes its release tree, then removes all DB
/// state. Cleanup paths are resolved and required to be strict descendants of
/// apps_root before recursive deletion.
pub fn deleteApp(ctx: Context, name: []const u8, opts: DeleteOptions, writer: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const app = (try loadApp(ctx, a, name)) orelse return Error.AppNotFound;
    try acquireAppLock(ctx, app.id, "delete");
    defer releaseAppLock(ctx, app.id);

    const unit_removed = try app_system_control.removeUnit(systemCtx(ctx), app.name, opts.unit_dir, opts.run_systemd);
    var files_removed = false;
    if (opts.remove_files) {
        const app_dir = try safeAppDirectory(ctx, a, app.name);
        if (try dirExists(ctx.io, app_dir)) {
            try Io.Dir.cwd().deleteTree(ctx.io, app_dir);
            files_removed = true;
        }
    }
    app_caddy_desired.deleteRoute(caddyCtx(ctx), app.alias_host) catch {};

    {
        const stmt = try ctx.db.prepare("DELETE FROM deploys WHERE app_id = ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    }

    const stmt = try ctx.db.prepare("DELETE FROM apps WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;

    const detail = try std.fmt.allocPrint(a, "app, deploy history, and caddy route removed; unit_removed={}; files_removed={}", .{ unit_removed, files_removed });
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "app.delete", name, null, .ok, detail);

    try writer.writeAll("{\"ok\":true,");
    try core_json.writeStringField(writer, "deleted", name, true);
    try core_json.writeBoolField(writer, "unit_removed", unit_removed, true);
    try core_json.writeBoolField(writer, "files_removed", files_removed, true);
    try core_json.writeStringField(writer, "detail", detail, false);
    try writer.writeAll("}\n");
}

pub fn writeAppsJson(ctx: Context, writer: anytype) !void {
    const stmt = try ctx.db.prepare(
        \\SELECT a.id, a.name, a.repo_url, a.workdir, a.toolchain, a.port, a.alias_host,
        \\       a.status, a.current_deploy_id, a.updated_at,
        \\       d.id, d.status, d.git_sha, d.started_at, d.finished_at
        \\FROM apps a
        \\LEFT JOIN deploys d ON d.id = (SELECT id FROM deploys WHERE app_id = a.id ORDER BY id DESC LIMIT 1)
        \\ORDER BY a.name
    );
    defer _ = sqlite.sqlite3_finalize(stmt);

    try writer.writeAll("{\"kind\":\"apps\",\"apps\":[");
    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeIntField(writer, "id", sqlite.sqlite3_column_int64(stmt, 0), true);
        try core_json.writeStringField(writer, "name", columnText(stmt, 1) orelse "", true);
        try core_json.writeNullableStringField(writer, "repo_url", columnText(stmt, 2), true);
        try core_json.writeNullableStringField(writer, "workdir", columnText(stmt, 3), true);
        try core_json.writeNullableStringField(writer, "toolchain", columnText(stmt, 4), true);
        try writeNullableIntColumn(writer, stmt, 5, "port", true);
        try core_json.writeNullableStringField(writer, "alias_host", columnText(stmt, 6), true);
        try core_json.writeStringField(writer, "status", columnText(stmt, 7) orelse "", true);
        try writeNullableIntColumn(writer, stmt, 8, "current_deploy_id", true);
        try core_json.writeNullableStringField(writer, "updated_at", columnText(stmt, 9), true);
        try core_json.writeString(writer, "last_deploy");
        try writer.writeByte(':');
        if (sqlite.sqlite3_column_type(stmt, 10) == sqlite.SQLITE_NULL) {
            try writer.writeAll("null");
        } else {
            try writer.writeByte('{');
            try core_json.writeIntField(writer, "id", sqlite.sqlite3_column_int64(stmt, 10), true);
            try core_json.writeStringField(writer, "status", columnText(stmt, 11) orelse "", true);
            try core_json.writeNullableStringField(writer, "git_sha", columnText(stmt, 12), true);
            try core_json.writeNullableStringField(writer, "started_at", columnText(stmt, 13), true);
            try core_json.writeNullableStringField(writer, "finished_at", columnText(stmt, 14), false);
            try writer.writeByte('}');
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeDeploysJson(ctx: Context, app_name: []const u8, limit: i64, writer: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const app = (try loadApp(ctx, arena_state.allocator(), app_name)) orelse return Error.AppNotFound;

    const stmt = try ctx.db.prepare(
        \\SELECT id, git_sha, status, log_path, detail, started_at, finished_at
        \\FROM deploys WHERE app_id = ? ORDER BY id DESC LIMIT ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    const effective_limit: i64 = if (limit <= 0) 50 else limit;
    if (sqlite.sqlite3_bind_int64(stmt, 2, effective_limit) != sqlite.SQLITE_OK) return Error.SqliteBind;

    try writer.writeAll("{\"kind\":\"deploys\",");
    try core_json.writeStringField(writer, "app", app_name, true);
    try writer.writeAll("\"deploys\":[");
    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeIntField(writer, "id", sqlite.sqlite3_column_int64(stmt, 0), true);
        try core_json.writeNullableStringField(writer, "git_sha", columnText(stmt, 1), true);
        try core_json.writeStringField(writer, "status", columnText(stmt, 2) orelse "", true);
        try core_json.writeNullableStringField(writer, "log_path", columnText(stmt, 3), true);
        try core_json.writeNullableStringField(writer, "detail", columnText(stmt, 4), true);
        try core_json.writeNullableStringField(writer, "started_at", columnText(stmt, 5), true);
        try core_json.writeNullableStringField(writer, "finished_at", columnText(stmt, 6), false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

// --- Port assignment ---

/// Lowest port in [port_min, port_max] not held by another app row and not
/// present in the sockets inventory (collector snapshot of listening ports).
fn assignPort(ctx: Context) !i64 {
    const app_stmt = try ctx.db.prepare("SELECT 1 FROM apps WHERE port = ? LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(app_stmt);
    const sock_stmt = try ctx.db.prepare("SELECT 1 FROM sockets WHERE local_address LIKE ? LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(sock_stmt);

    var port: i64 = ctx.config.port_min;
    while (port <= ctx.config.port_max) : (port += 1) {
        _ = sqlite.sqlite3_reset(app_stmt);
        if (sqlite.sqlite3_bind_int64(app_stmt, 1, port) != sqlite.SQLITE_OK) return Error.SqliteBind;
        const app_rc = sqlite.sqlite3_step(app_stmt);
        if (app_rc == sqlite.SQLITE_ROW) continue;
        if (app_rc != sqlite.SQLITE_DONE) return Error.SqliteStep;

        var pattern_buf: [16]u8 = undefined;
        const pattern = std.fmt.bufPrint(&pattern_buf, "%:{d}", .{port}) catch unreachable;
        _ = sqlite.sqlite3_reset(sock_stmt);
        try bindText(sock_stmt, 1, pattern);
        const sock_rc = sqlite.sqlite3_step(sock_stmt);
        if (sock_rc == sqlite.SQLITE_ROW) continue;
        if (sock_rc != sqlite.SQLITE_DONE) return Error.SqliteStep;

        return port;
    }
    return Error.NoFreePort;
}

// --- Toolchain detection ---

/// Marker-file toolchain detection on a checkout directory. `prebuilt` is
/// never detected; it must be set explicitly on apps.toolchain.
pub fn detectToolchain(io: Io, dir: []const u8) !Toolchain {
    if (try markerExists(io, dir, "build.zig")) return .zig;
    if (try markerExists(io, dir, "go.mod")) return .go;
    if (try markerExists(io, dir, "Cargo.toml")) return .rust;
    if (try markerExists(io, dir, "package.json")) return .node;
    return Error.UnknownToolchain;
}

fn markerExists(io: Io, dir: []const u8, marker: []const u8) !bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, marker }) catch return false;
    return core_fs.fileExists(io, path);
}

/// Pick the artifact from a build output dir: the single executable regular
/// file, or on ambiguity the one matching the app name.
fn pickExecutable(io: Io, a: Allocator, dir_path: []const u8, app_name: []const u8) ![]const u8 {
    var dir = Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return Error.ArtifactNotFound;
    defer dir.close(io);

    var found: ?[]const u8 = null;
    var name_match: ?[]const u8 = null;
    var count: usize = 0;

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const st = dir.statFile(io, entry.name, .{}) catch continue;
        if (@intFromEnum(st.permissions) & 0o111 == 0) continue;
        count += 1;
        const copy = try a.dupe(u8, entry.name);
        found = copy;
        if (std.mem.eql(u8, entry.name, app_name)) name_match = copy;
    }

    if (count == 0) return Error.ArtifactNotFound;
    if (count == 1) return found.?;
    return name_match orelse Error.ArtifactAmbiguous;
}

// --- Deploy pipeline ---

const PipelineState = struct {
    sha: ?[]const u8 = null,
    release_label: ?[]const u8 = null,
    health_ok: ?bool = null,
    err_detail: ?[]const u8 = null,
    release_installed: bool = false,
    caddy_updated: bool = false,
    /// When set, runLogged flushes the accumulated log here after every step
    /// so SSE tailing sees progress while the deploy is still running.
    log_path: ?[]const u8 = null,
};

pub fn deploy(ctx: Context, app_name: []const u8, opts: DeployOptions, writer: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const app = (try loadApp(ctx, a, app_name)) orelse return Error.AppNotFound;
    try acquireAppLock(ctx, app.id, "deploy");
    defer releaseAppLock(ctx, app.id);

    const app_dir = try std.fmt.allocPrint(a, "{s}/{s}", .{ ctx.config.apps_root, app.name });
    try Io.Dir.cwd().createDirPath(ctx.io, app_dir);

    const deploy_id = try insertDeploy(ctx, app.id);
    const log_path = try std.fmt.allocPrint(a, "{s}/deploy-{d}.log", .{ app_dir, deploy_id });
    try execBindTextInt(ctx, "UPDATE deploys SET log_path = ? WHERE id = ?", log_path, deploy_id);

    var log = std.Io.Writer.Allocating.init(a);

    var state = PipelineState{ .log_path = log_path };
    var status: []const u8 = "ok";
    var detail: []const u8 = "deployed";
    var recovered = false;
    var recovery_deploy_id: ?i64 = null;

    runPipeline(ctx, a, app, app_dir, deploy_id, opts, &log, &state) catch |err| {
        status = "error";
        detail = state.err_detail orelse @errorName(err);
    };
    if (std.mem.eql(u8, status, "ok")) {
        if (state.health_ok) |ok| {
            if (ok) {
                detail = "deployed; health check ok";
            } else {
                status = "unhealthy";
                detail = "deployed; health check failed: port never accepted a TCP connection";
            }
        } else {
            detail = "deployed; health check skipped";
        }
    }

    if (opts.auto_rollback and !std.mem.eql(u8, status, "ok") and state.release_installed) {
        if (app.current_deploy_id) |previous_id| {
            if (restoreDeployRelease(ctx, a, app, app_dir, previous_id, opts)) |release| {
                recovered = true;
                recovery_deploy_id = previous_id;
                const failed_status = status;
                status = if (std.mem.eql(u8, failed_status, "unhealthy")) "unhealthy_rolled_back" else "error_rolled_back";
                detail = try std.fmt.allocPrint(a, "{s}; automatically rolled back to deploy {d} ({s})", .{ detail, previous_id, release });
                log.writer.print("== recovery: restored deploy {d} ({s})\n", .{ previous_id, release }) catch {};
            } else |err| {
                detail = try std.fmt.allocPrint(a, "{s}; automatic rollback failed: {s}", .{ detail, @errorName(err) });
                log.writer.print("!! recovery failed: {s}\n", .{@errorName(err)}) catch {};
            }
        }
    }

    log.writer.print("== result: {s}: {s}\n", .{ status, detail }) catch {};
    flushLog(ctx, log_path, log.written());

    // Finalize deploys row.
    {
        const stmt = try ctx.db.prepare(
            \\UPDATE deploys SET status = ?, detail = ?, git_sha = ?, finished_at = CURRENT_TIMESTAMP WHERE id = ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, status);
        try bindText(stmt, 2, detail);
        try bindTextOpt(stmt, 3, state.sha);
        if (sqlite.sqlite3_bind_int64(stmt, 4, deploy_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    }

    // Keep the DB pointer aligned with the atomic `current` symlink, including
    // automatic recovery to the prior deploy.
    const deploy_ok = std.mem.eql(u8, status, "ok");
    const installed_current = state.release_installed and !recovered;
    {
        const app_status: []const u8 = if (deploy_ok)
            "deployed"
        else if (recovered)
            "recovered"
        else if (std.mem.eql(u8, status, "unhealthy"))
            "unhealthy"
        else
            "deploy_failed";
        const current_id = recovery_deploy_id orelse if (installed_current) deploy_id else null;
        if (current_id) |id| {
            const stmt = try ctx.db.prepare("UPDATE apps SET current_deploy_id = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?");
            defer _ = sqlite.sqlite3_finalize(stmt);
            if (sqlite.sqlite3_bind_int64(stmt, 1, id) != sqlite.SQLITE_OK) return Error.SqliteBind;
            try bindText(stmt, 2, app_status);
            if (sqlite.sqlite3_bind_int64(stmt, 3, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
            if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
        } else {
            const stmt = try ctx.db.prepare("UPDATE apps SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?");
            defer _ = sqlite.sqlite3_finalize(stmt);
            try bindText(stmt, 1, app_status);
            if (sqlite.sqlite3_bind_int64(stmt, 2, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
            if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
        }
    }

    const audit_detail = try std.fmt.allocPrint(a, "deploy {d}: {s}; sha={s}; log={s}", .{
        deploy_id, detail, state.sha orelse "none", log_path,
    });
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "app.deploy", app.name, null, if (deploy_ok) .ok else .err, audit_detail);

    try writer.writeByte('{');
    try core_json.writeBoolField(writer, "ok", std.mem.eql(u8, status, "ok"), true);
    try core_json.writeIntField(writer, "deploy_id", deploy_id, true);
    try core_json.writeStringField(writer, "app", app.name, true);
    try core_json.writeNullableStringField(writer, "sha", state.sha, true);
    try core_json.writeStringField(writer, "status", status, true);
    try core_json.writeBoolField(writer, "recovered", recovered, true);
    if (recovery_deploy_id) |id| {
        try core_json.writeIntField(writer, "rollback_deploy_id", id, true);
    } else {
        try writer.writeAll("\"rollback_deploy_id\":null,");
    }
    try core_json.writeStringField(writer, "log_path", log_path, true);
    try core_json.writeIntField(writer, "port", app.port, true);
    try core_json.writeStringField(writer, "alias_host", app.alias_host, true);
    try core_json.writeBoolField(writer, "caddy_route_updated", state.caddy_updated, false);
    try writer.writeAll("}\n");
}

fn runPipeline(
    ctx: Context,
    a: Allocator,
    app: AppRow,
    app_dir: []const u8,
    deploy_id: i64,
    opts: DeployOptions,
    log: *std.Io.Writer.Allocating,
    state: *PipelineState,
) !void {
    // a. Source sync.
    var src_dir: []const u8 = undefined;
    if (app.repo_url) |url| {
        src_dir = try std.fmt.allocPrint(a, "{s}/src", .{app_dir});
        if (!try dirExists(ctx.io, src_dir)) {
            try runLogged(ctx, a, log, state, null, &.{ "git", "clone", url, src_dir });
        } else {
            try runLogged(ctx, a, log, state, src_dir, &.{ "git", "fetch", "--all" });
            try runLogged(ctx, a, log, state, src_dir, &.{ "git", "reset", "--hard", "origin/HEAD" });
        }
        state.sha = try captureSha(ctx, a, src_dir) orelse return Error.CommandFailed;
    } else {
        src_dir = app.workdir.?;
        state.sha = try captureSha(ctx, a, src_dir);
    }

    // b. Toolchain + build.
    const toolchain: Toolchain = blk: {
        if (app.toolchain) |text| {
            if (text.len > 0) break :blk Toolchain.parse(text) orelse return Error.UnknownToolchain;
        }
        break :blk try detectToolchain(ctx.io, src_dir);
    };
    try log.writer.print("== toolchain: {s}\n", .{@tagName(toolchain)});

    var artifact_path: ?[]const u8 = null; // absolute or cwd-relative path to built binary
    switch (toolchain) {
        .zig => {
            try runLogged(ctx, a, log, state, src_dir, &.{ "zig", "build", "-Doptimize=ReleaseSafe" });
            const out_dir = try std.fmt.allocPrint(a, "{s}/zig-out/bin", .{src_dir});
            const bin = try pickExecutable(ctx.io, a, out_dir, app.name);
            artifact_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ out_dir, bin });
        },
        .go => {
            const out_path = try std.fmt.allocPrint(a, "{s}/.cloudio-out/{s}", .{ src_dir, app.name });
            try core_fs.ensureParentDir(ctx.io, out_path);
            try runLogged(ctx, a, log, state, src_dir, &.{ "go", "build", "-o", out_path, "." });
            artifact_path = out_path;
        },
        .rust => {
            try runLogged(ctx, a, log, state, src_dir, &.{ "cargo", "build", "--release" });
            const out_dir = try std.fmt.allocPrint(a, "{s}/target/release", .{src_dir});
            const bin = try pickExecutable(ctx.io, a, out_dir, app.name);
            artifact_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ out_dir, bin });
        },
        .node => {
            try runLogged(ctx, a, log, state, src_dir, &.{ "npm", "ci", "--omit=dev" });
        },
        .prebuilt => {
            const candidate = try std.fmt.allocPrint(a, "{s}/{s}", .{ src_dir, app.name });
            if (!try core_fs.fileExists(ctx.io, candidate)) {
                state.err_detail = try std.fmt.allocPrint(a, "prebuilt artifact missing: {s}", .{candidate});
                return Error.ArtifactNotFound;
            }
            artifact_path = candidate;
        },
    }

    // c. Install release + swap `current` symlink.
    const label = state.sha orelse try std.fmt.allocPrint(a, "deploy-{d}", .{deploy_id});
    state.release_label = label;
    const current_link = try std.fmt.allocPrint(a, "{s}/current", .{app_dir});
    var exec_binary: []const u8 = undefined;

    if (toolchain == .node) {
        // Node MVP: no artifact copy; `current` points at the source checkout.
        // Rollback is not supported for node apps (no per-deploy snapshot).
        try Io.Dir.cwd().symLinkAtomic(ctx.io, "src", current_link, .{});
        state.release_installed = true;
        exec_binary = "";
    } else {
        const artifact = artifact_path.?;
        const binary_name = std.fs.path.basename(artifact);
        const release_dir = try std.fmt.allocPrint(a, "{s}/releases/{s}", .{ app_dir, label });
        try Io.Dir.cwd().createDirPath(ctx.io, release_dir);
        const dest = try std.fmt.allocPrint(a, "{s}/{s}", .{ release_dir, binary_name });
        try Io.Dir.cwd().copyFile(artifact, Io.Dir.cwd(), dest, ctx.io, .{});
        const rel_target = try std.fmt.allocPrint(a, "releases/{s}", .{label});
        try Io.Dir.cwd().symLinkAtomic(ctx.io, rel_target, current_link, .{});
        state.release_installed = true;
        exec_binary = binary_name;
        try log.writer.print("== installed {s} -> {s}\n", .{ dest, rel_target });
    }

    // d. Render + install systemd unit.
    const abs_current = try absPath(ctx.io, a, current_link);
    const exec_path = if (toolchain == .node)
        try std.fmt.allocPrint(a, "/usr/bin/node {s}", .{abs_current})
    else
        try std.fmt.allocPrint(a, "{s}/{s}", .{ abs_current, exec_binary });
    const env_pairs = try parseEnvPairs(a, app.env_json);

    const unit_text = try app_system_control.renderUnit(a, .{
        .name = app.name,
        .exec_path = exec_path,
        .workdir = abs_current,
        .port = @intCast(app.port),
        .env = env_pairs,
    });
    try app_system_control.installUnit(systemCtx(ctx), app.name, unit_text, opts.unit_dir);
    try log.writer.print("== unit installed into {s}\n", .{opts.unit_dir});

    if (opts.run_systemd) {
        try app_system_control.enableAndRestart(systemCtx(ctx), app.name, &log.writer);
    } else {
        try log.writer.writeAll("== systemd enable/restart skipped\n");
    }

    // e. Health check.
    if (opts.health_check) {
        state.health_ok = try healthCheck(ctx, @intCast(app.port), opts.health_check_tries);
        try log.writer.print("== health check: {s}\n", .{if (state.health_ok.?) "ok" else "failed"});
    }

    // f. Caddy desired route (no apply/reload here; HTTP layer decides).
    const upstream = try std.fmt.allocPrint(a, "127.0.0.1:{d}", .{app.port});
    try app_caddy_desired.upsertRoute(caddyCtx(ctx), app.alias_host, upstream, "app", null, null, app.id);
    state.caddy_updated = true;
    try log.writer.print("== caddy route upserted: {s} -> {s}\n", .{ app.alias_host, upstream });
}

fn healthCheck(ctx: Context, port: u16, max_tries: usize) !bool {
    var tries: usize = 0;
    while (tries < @max(max_tries, 1)) : (tries += 1) {
        var address = std.Io.net.IpAddress.parse("127.0.0.1", port) catch unreachable;
        if (address.connect(ctx.io, .{ .mode = .stream })) |stream| {
            stream.close(ctx.io);
            return true;
        } else |_| {}
        ctx.io.sleep(.fromNanoseconds(300 * std.time.ns_per_ms), .awake) catch return false;
    }
    return false;
}

fn restoreDeployRelease(
    ctx: Context,
    a: Allocator,
    app: AppRow,
    app_dir: []const u8,
    target_id: i64,
    opts: DeployOptions,
) ![]const u8 {
    const stmt = try ctx.db.prepare("SELECT git_sha FROM deploys WHERE id = ? AND app_id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, target_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 2, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return Error.DeployNotFound;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    const sha = try dupeOpt(a, columnText(stmt, 0));
    const label = sha orelse try std.fmt.allocPrint(a, "deploy-{d}", .{target_id});
    const release_dir = try std.fmt.allocPrint(a, "{s}/releases/{s}", .{ app_dir, label });
    if (!try dirExists(ctx.io, release_dir)) return Error.ReleaseMissing;

    const current_link = try std.fmt.allocPrint(a, "{s}/current", .{app_dir});
    const rel_target = try std.fmt.allocPrint(a, "releases/{s}", .{label});
    try Io.Dir.cwd().symLinkAtomic(ctx.io, rel_target, current_link, .{});

    if (opts.run_systemd) {
        var discard = std.Io.Writer.Allocating.init(a);
        const service_name = try app_system_control.unitName(a, app.name);
        try app_system_control.serviceAction(systemCtx(ctx), service_name, .restart, &discard.writer);
    }
    return label;
}

// --- Rollback ---

pub fn rollback(ctx: Context, app_name: []const u8, deploy_id: ?i64, opts: DeployOptions, writer: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const app = (try loadApp(ctx, a, app_name)) orelse return Error.AppNotFound;
    try acquireAppLock(ctx, app.id, "rollback");
    defer releaseAppLock(ctx, app.id);
    const app_dir = try std.fmt.allocPrint(a, "{s}/{s}", .{ ctx.config.apps_root, app.name });

    var target_id: i64 = undefined;
    if (deploy_id) |id| {
        const stmt = try ctx.db.prepare("SELECT id FROM deploys WHERE id = ? AND app_id = ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_bind_int64(stmt, 1, id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_bind_int64(stmt, 2, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) return Error.DeployNotFound;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        target_id = sqlite.sqlite3_column_int64(stmt, 0);
    } else {
        const stmt = try ctx.db.prepare(
            \\SELECT id FROM deploys
            \\WHERE app_id = ? AND status IN ('ok', 'unhealthy') AND (? IS NULL OR id != ?)
            \\ORDER BY id DESC LIMIT 1
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        const current = app.current_deploy_id orelse -1;
        if (sqlite.sqlite3_bind_int64(stmt, 2, current) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_bind_int64(stmt, 3, current) != sqlite.SQLITE_OK) return Error.SqliteBind;
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) return Error.NoRollbackTarget;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        target_id = sqlite.sqlite3_column_int64(stmt, 0);
    }

    const label = try restoreDeployRelease(ctx, a, app, app_dir, target_id, opts);

    try execBindIntInt(ctx, "UPDATE apps SET current_deploy_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", target_id, app.id);

    const detail = try std.fmt.allocPrint(a, "rolled back to deploy {d} (release {s}); restart={s}", .{
        target_id, label, if (opts.run_systemd) "yes" else "skipped",
    });
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "app.rollback", app.name, null, .ok, detail);

    try writer.writeAll("{\"ok\":true,");
    try core_json.writeStringField(writer, "app", app.name, true);
    try core_json.writeIntField(writer, "deploy_id", target_id, true);
    try core_json.writeStringField(writer, "release", label, false);
    try writer.writeAll("}\n");
}

// --- Deploy log ---

pub fn readDeployLog(ctx: Context, app_name: []const u8, deploy_id: i64, writer: anytype) !void {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const app = (try loadApp(ctx, a, app_name)) orelse return Error.AppNotFound;

    const stmt = try ctx.db.prepare("SELECT log_path FROM deploys WHERE id = ? AND app_id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, deploy_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 2, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return Error.DeployNotFound;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    const log_path = columnText(stmt, 0) orelse "";

    var contents: []const u8 = "";
    if (log_path.len > 0) {
        contents = Io.Dir.cwd().readFileAlloc(ctx.io, log_path, a, .limited(8 * 1024 * 1024)) catch "";
    }
    if (contents.len > max_log_tail_bytes) contents = contents[contents.len - max_log_tail_bytes ..];

    try writer.writeAll("{\"kind\":\"deploy_log\",");
    try core_json.writeIntField(writer, "deploy_id", deploy_id, true);
    try core_json.writeStringField(writer, "log", contents, false);
    try writer.writeAll("}\n");
}

/// Status of the most recent deploy for an app as a static string
/// ("running", "ok", ...); null when the app has no deploys.
pub fn latestDeployStatus(ctx: Context, app_name: []const u8) !?[]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const app = (try loadApp(ctx, a, app_name)) orelse return null;
    const stmt = try ctx.db.prepare("SELECT status FROM deploys WHERE app_id = ? ORDER BY id DESC LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return statusSlice(columnText(stmt, 0) orelse "unknown");
}

/// Reads log content of the latest deploy starting at *offset, advancing the
/// offset. Returns gpa-owned bytes (may be empty). Null when no log exists yet.
pub fn readDeployLogTailFrom(ctx: Context, app_name: []const u8, offset: *usize) !?[]u8 {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const app = (try loadApp(ctx, a, app_name)) orelse return null;
    const stmt = try ctx.db.prepare("SELECT log_path FROM deploys WHERE app_id = ? ORDER BY id DESC LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app.id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    const log_path = columnText(stmt, 0) orelse return null;
    if (log_path.len == 0) return null;
    const contents = Io.Dir.cwd().readFileAlloc(ctx.io, log_path, a, .limited(8 * 1024 * 1024)) catch return null;
    if (offset.* >= contents.len) return try ctx.gpa.dupe(u8, "");
    const chunk = contents[offset.*..];
    offset.* = contents.len;
    return try ctx.gpa.dupe(u8, chunk);
}

/// Maps a status column value to a static string so callers need no free.
fn statusSlice(text: []const u8) []const u8 {
    const known = [_][]const u8{ "pending", "running", "ok", "error", "unhealthy", "error_rolled_back", "unhealthy_rolled_back", "interrupted" };
    for (known) |k| {
        if (std.mem.eql(u8, text, k)) return k;
    }
    return "unknown";
}

// --- Internal helpers ---

fn loadApp(ctx: Context, a: Allocator, name: []const u8) !?AppRow {
    const stmt = try ctx.db.prepare(
        \\SELECT id, name, repo_url, workdir, toolchain, port, alias_host, env_json, status, current_deploy_id
        \\FROM apps WHERE name = ?
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, name);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return .{
        .id = sqlite.sqlite3_column_int64(stmt, 0),
        .name = try a.dupe(u8, columnText(stmt, 1) orelse ""),
        .repo_url = try dupeOpt(a, columnText(stmt, 2)),
        .workdir = try dupeOpt(a, columnText(stmt, 3)),
        .toolchain = try dupeOpt(a, columnText(stmt, 4)),
        .port = sqlite.sqlite3_column_int64(stmt, 5),
        .alias_host = try a.dupe(u8, columnText(stmt, 6) orelse ""),
        .env_json = try dupeOpt(a, columnText(stmt, 7)),
        .status = try a.dupe(u8, columnText(stmt, 8) orelse ""),
        .current_deploy_id = if (sqlite.sqlite3_column_type(stmt, 9) == sqlite.SQLITE_NULL) null else sqlite.sqlite3_column_int64(stmt, 9),
    };
}

fn insertDeploy(ctx: Context, app_id: i64) !i64 {
    const stmt = try ctx.db.prepare("INSERT INTO deploys(app_id, status) VALUES (?, 'running')");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    return sqlite.sqlite3_last_insert_rowid(ctx.db.handle);
}

fn acquireAppLock(ctx: Context, app_id: i64, operation: []const u8) !void {
    // A process crash cannot run a defer. Reclaim only operations old enough
    // that a normal build/deploy should have completed.
    {
        const stale = try ctx.db.prepare(
            \\DELETE FROM app_operation_locks
            \\WHERE app_id = ? AND acquired_at < datetime('now', '-6 hours')
        );
        defer _ = sqlite.sqlite3_finalize(stale);
        if (sqlite.sqlite3_bind_int64(stale, 1, app_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_step(stale) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    }
    {
        const interrupted = try ctx.db.prepare(
            \\UPDATE deploys
            \\SET status = 'interrupted', detail = 'stale running deployment recovered by operation lock',
            \\    finished_at = CURRENT_TIMESTAMP
            \\WHERE app_id = ? AND status = 'running' AND started_at < datetime('now', '-6 hours')
        );
        defer _ = sqlite.sqlite3_finalize(interrupted);
        if (sqlite.sqlite3_bind_int64(interrupted, 1, app_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
        if (sqlite.sqlite3_step(interrupted) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    }
    const stmt = try ctx.db.prepare(
        \\INSERT OR IGNORE INTO app_operation_locks(app_id, operation) VALUES (?, ?)
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app_id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    try bindText(stmt, 2, operation);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    if (sqlite.sqlite3_changes(ctx.db.handle) != 1) return Error.AppBusy;
}

fn releaseAppLock(ctx: Context, app_id: i64) void {
    const stmt = ctx.db.prepare("DELETE FROM app_operation_locks WHERE app_id = ?") catch return;
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, app_id) != sqlite.SQLITE_OK) return;
    _ = sqlite.sqlite3_step(stmt);
}

fn safeAppDirectory(ctx: Context, a: Allocator, app_name: []const u8) ![]const u8 {
    if (!isValidAppName(app_name)) return Error.InvalidName;
    const root = try std.fs.path.resolve(a, &.{ctx.config.apps_root});
    const app_dir = try std.fs.path.resolve(a, &.{ ctx.config.apps_root, app_name });
    if (std.mem.eql(u8, root, "/") or std.mem.eql(u8, root, ".") or root.len == 0) return Error.UnsafeCleanupPath;
    if (app_dir.len <= root.len or !std.mem.startsWith(u8, app_dir, root) or app_dir[root.len] != std.fs.path.sep) {
        return Error.UnsafeCleanupPath;
    }
    return app_dir;
}

/// Run a command (optionally in `cwd`), append command line, exit status and
/// output tail to the deploy log; failure sets err_detail and errors out.
fn runLogged(ctx: Context, a: Allocator, log: *std.Io.Writer.Allocating, state: *PipelineState, cwd: ?[]const u8, argv: []const []const u8) !void {
    try log.writer.writeAll("$ ");
    for (argv, 0..) |arg, idx| {
        if (idx != 0) try log.writer.writeByte(' ');
        try log.writer.writeAll(arg);
    }
    if (cwd) |dir| try log.writer.print("  (cwd={s})", .{dir});
    try log.writer.writeByte('\n');
    if (state.log_path) |path| flushLog(ctx, path, log.written());

    const result = std.process.run(a, ctx.io, .{
        .argv = argv,
        .cwd = if (cwd) |dir| .{ .path = dir } else .inherit,
        .stdout_limit = .limited(max_command_bytes),
        .stderr_limit = .limited(max_command_bytes),
    }) catch |err| {
        state.err_detail = try std.fmt.allocPrint(a, "{s} could not run: {s}", .{ argv[0], @errorName(err) });
        try log.writer.print("!! {s}\n", .{state.err_detail.?});
        return Error.CommandFailed;
    };

    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    try log.writer.print("exit: {s}\n", .{if (ok) "0" else "nonzero"});
    try log.writer.print("{s}{s}\n", .{ tail(result.stdout, 4096), tail(result.stderr, 4096) });
    if (state.log_path) |path| flushLog(ctx, path, log.written());
    if (!ok) {
        state.err_detail = try std.fmt.allocPrint(a, "{s} failed: {s}", .{ argv[0], tail(result.stderr, 512) });
        return Error.CommandFailed;
    }
}

fn captureSha(ctx: Context, a: Allocator, dir: []const u8) !?[]const u8 {
    // Only treat `dir` as a repo when it has its own .git; otherwise
    // rev-parse would walk up and report an enclosing repo's HEAD.
    const git_marker = try std.fmt.allocPrint(a, "{s}/.git", .{dir});
    const has_git = (try dirExists(ctx.io, git_marker)) or (try core_fs.fileExists(ctx.io, git_marker));
    if (!has_git) return null;
    const result = std.process.run(a, ctx.io, .{
        .argv = &.{ "git", "-C", dir, "rev-parse", "HEAD" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return null;
    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok) return null;
    const sha = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (sha.len == 0) return null;
    return try a.dupe(u8, sha);
}

fn parseEnvPairs(a: Allocator, env_json: ?[]const u8) ![]const app_system_control.EnvPair {
    const raw = env_json orelse return &.{};
    if (raw.len == 0) return &.{};
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, raw, .{}) catch return &.{};
    if (parsed != .object) return &.{};
    var list = std.ArrayList(app_system_control.EnvPair).empty;
    var it = parsed.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;
        try list.append(a, .{
            .key = try a.dupe(u8, entry.key_ptr.*),
            .value = try a.dupe(u8, entry.value_ptr.string),
        });
    }
    return try list.toOwnedSlice(a);
}

fn flushLog(ctx: Context, log_path: []const u8, contents: []const u8) void {
    core_fs.ensureParentDir(ctx.io, log_path) catch return;
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = log_path, .data = contents }) catch {};
}

fn absPath(io: Io, a: Allocator, path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(path)) return path;
    const cwd_path = try std.process.currentPathAlloc(io, a);
    return std.fmt.allocPrint(a, "{s}/{s}", .{ cwd_path, path });
}

fn dirExists(io: Io, path: []const u8) !bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |e| return e,
    };
    dir.close(io);
    return true;
}

fn tail(text: []const u8, max: usize) []const u8 {
    if (text.len <= max) return text;
    return text[text.len - max ..];
}

fn dupeOpt(a: Allocator, value: ?[]const u8) !?[]const u8 {
    const v = value orelse return null;
    return try a.dupe(u8, v);
}

fn execBindTextInt(ctx: Context, sql: []const u8, text: []const u8, num: i64) !void {
    const stmt = try ctx.db.prepare(sql);
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, text);
    if (sqlite.sqlite3_bind_int64(stmt, 2, num) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
}

fn execBindIntInt(ctx: Context, sql: []const u8, first: i64, second: i64) !void {
    const stmt = try ctx.db.prepare(sql);
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, first) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_bind_int64(stmt, 2, second) != sqlite.SQLITE_OK) return Error.SqliteBind;
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
}

fn writeNullableIntColumn(writer: anytype, stmt: *sqlite.sqlite3_stmt, idx: c_int, name: []const u8, trailing_comma: bool) !void {
    if (sqlite.sqlite3_column_type(stmt, idx) == sqlite.SQLITE_NULL) {
        try core_json.writeString(writer, name);
        try writer.writeAll(":null");
        if (trailing_comma) try writer.writeByte(',');
    } else {
        try core_json.writeIntField(writer, name, sqlite.sqlite3_column_int64(stmt, idx), trailing_comma);
    }
}

fn bindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return Error.SqliteBind;
}

fn bindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |v| return bindText(stmt, idx, v);
    if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return Error.SqliteBind;
}

fn columnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

// --- Tests ---

const TestEnv = struct {
    tmp: std.testing.TmpDir,
    db: Db,
    base: []u8,
    db_path: []u8,
    apps_root: []u8,

    fn init(gpa: Allocator) !TestEnv {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const base = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
        errdefer gpa.free(base);
        const db_path = try std.fmt.allocPrint(gpa, "{s}/deploy.db", .{base});
        errdefer gpa.free(db_path);
        const apps_root = try std.fmt.allocPrint(gpa, "{s}/apps", .{base});
        errdefer gpa.free(apps_root);
        var db = try Db.open(std.testing.io, db_path);
        errdefer db.close();
        try db.initSchema();
        return .{ .tmp = tmp, .db = db, .base = base, .db_path = db_path, .apps_root = apps_root };
    }

    fn ctx(self: *TestEnv) Context {
        return .{
            .io = std.testing.io,
            .gpa = std.testing.allocator,
            .db = &self.db,
            .config = .{ .domains = &.{"example.com"}, .apps_root = self.apps_root },
        };
    }

    fn deinit(self: *TestEnv, gpa: Allocator) void {
        self.db.close();
        gpa.free(self.apps_root);
        gpa.free(self.db_path);
        gpa.free(self.base);
        self.tmp.cleanup();
    }
};

fn testSetToolchain(db: *Db, name: []const u8, toolchain: []const u8) !void {
    const stmt = try db.prepare("UPDATE apps SET toolchain = ? WHERE name = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, toolchain);
    try bindText(stmt, 2, name);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
}

fn testWriteExecutable(gpa: Allocator, dir: []const u8, name: []const u8, contents: []const u8) !void {
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir, name });
    defer gpa.free(path);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = contents });
    const f = try Io.Dir.cwd().openFile(std.testing.io, path, .{});
    defer f.close(std.testing.io);
    try f.setPermissions(std.testing.io, @enumFromInt(0o755));
}

fn testQueryInt(db: *Db, sql: []const u8) !i64 {
    const stmt = try db.prepare(sql);
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return sqlite.sqlite3_column_int64(stmt, 0);
}

test "app name validation" {
    const too_long: [33]u8 = @splat('a');
    try std.testing.expect(isValidAppName("demo"));
    try std.testing.expect(isValidAppName("my-app-2"));
    try std.testing.expect(!isValidAppName(""));
    try std.testing.expect(!isValidAppName("Upper"));
    try std.testing.expect(!isValidAppName("a_b"));
    try std.testing.expect(!isValidAppName("a b"));
    try std.testing.expect(!isValidAppName(&too_long));
}

test "registerApp assigns lowest free ports and rejects duplicates" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const workdir = try std.fmt.allocPrint(allocator, "{s}/work", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "alpha", null, workdir, &out.writer);
    try registerApp(ctx, "beta", null, workdir, &out.writer);

    try std.testing.expectEqual(@as(i64, 42000), try testQueryInt(&env.db, "SELECT port FROM apps WHERE name = 'alpha'"));
    try std.testing.expectEqual(@as(i64, 42001), try testQueryInt(&env.db, "SELECT port FROM apps WHERE name = 'beta'"));

    // A socket occupying 42002 skips that port for the next app.
    const sock_stmt = try env.db.prepare("INSERT INTO sockets(proto, state, local_address) VALUES ('tcp', 'LISTEN', '0.0.0.0:42002')");
    defer _ = sqlite.sqlite3_finalize(sock_stmt);
    try std.testing.expect(sqlite.sqlite3_step(sock_stmt) == sqlite.SQLITE_DONE);
    try registerApp(ctx, "gamma", null, workdir, &out.writer);
    try std.testing.expectEqual(@as(i64, 42003), try testQueryInt(&env.db, "SELECT port FROM apps WHERE name = 'gamma'"));

    try std.testing.expectError(Error.AppExists, registerApp(ctx, "alpha", null, workdir, &out.writer));
    try std.testing.expectError(Error.InvalidName, registerApp(ctx, "Bad Name", null, workdir, &out.writer));
    try std.testing.expectError(Error.SourceRequired, registerApp(ctx, "nosrc", null, null, &out.writer));
    try std.testing.expectError(Error.SourceConflict, registerApp(ctx, "both", "https://example.com/r.git", workdir, &out.writer));
    try std.testing.expectError(Error.WorkdirMissing, registerApp(ctx, "nodir", null, "/definitely/missing/dir", &out.writer));

    // alias_host derives from the primary domain.
    var apps_out = std.Io.Writer.Allocating.init(allocator);
    defer apps_out.deinit();
    try writeAppsJson(ctx, &apps_out.writer);
    try std.testing.expect(std.mem.indexOf(u8, apps_out.written(), "\"alias_host\":\"alpha.example.com\"") != null);
}

test "toolchain detection from marker files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(base);

    const markers = [_]struct { file: []const u8, expected: Toolchain }{
        .{ .file = "build.zig", .expected = .zig },
        .{ .file = "go.mod", .expected = .go },
        .{ .file = "Cargo.toml", .expected = .rust },
        .{ .file = "package.json", .expected = .node },
    };
    for (markers, 0..) |marker, idx| {
        const dir = try std.fmt.allocPrint(allocator, "{s}/tc{d}", .{ base, idx });
        defer allocator.free(dir);
        try Io.Dir.cwd().createDirPath(std.testing.io, dir);
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, marker.file });
        defer allocator.free(path);
        try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "x" });
        try std.testing.expectEqual(marker.expected, try detectToolchain(std.testing.io, dir));
    }

    const empty_dir = try std.fmt.allocPrint(allocator, "{s}/empty", .{base});
    defer allocator.free(empty_dir);
    try Io.Dir.cwd().createDirPath(std.testing.io, empty_dir);
    try std.testing.expectError(Error.UnknownToolchain, detectToolchain(std.testing.io, empty_dir));

    // build.zig wins over package.json.
    const both_dir = try std.fmt.allocPrint(allocator, "{s}/both", .{base});
    defer allocator.free(both_dir);
    try Io.Dir.cwd().createDirPath(std.testing.io, both_dir);
    inline for (.{ "build.zig", "package.json" }) |file| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ both_dir, file });
        defer allocator.free(path);
        try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "x" });
    }
    try std.testing.expectEqual(Toolchain.zig, try detectToolchain(std.testing.io, both_dir));

    try std.testing.expectEqual(@as(?Toolchain, .prebuilt), Toolchain.parse("prebuilt"));
    try std.testing.expectEqual(@as(?Toolchain, null), Toolchain.parse("makefile"));
}

test "full prebuilt deploy: releases, symlink, unit, deploys row, caddy route" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const workdir = try std.fmt.allocPrint(allocator, "{s}/work", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);
    try testWriteExecutable(allocator, workdir, "demo", "#!/bin/sh\necho hi\n");

    const unit_dir = try std.fmt.allocPrint(allocator, "{s}/units", .{env.base});
    defer allocator.free(unit_dir);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "demo", null, workdir, &out.writer);
    try testSetToolchain(&env.db, "demo", "prebuilt");

    out.clearRetainingCapacity();
    try deploy(ctx, "demo", .{ .unit_dir = unit_dir, .run_systemd = false, .health_check = false }, &out.writer);
    const result_json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, result_json, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result_json, "\"status\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result_json, "\"caddy_route_updated\":true") != null);

    // Release binary exists and current symlink resolves to it (workdir is
    // not a git repo, so the release label is deploy-<id>).
    const release_bin = try std.fmt.allocPrint(allocator, "{s}/demo/releases/deploy-1/demo", .{env.apps_root});
    defer allocator.free(release_bin);
    try std.testing.expect(try core_fs.fileExists(std.testing.io, release_bin));
    const current_bin = try std.fmt.allocPrint(allocator, "{s}/demo/current/demo", .{env.apps_root});
    defer allocator.free(current_bin);
    try std.testing.expect(try core_fs.fileExists(std.testing.io, current_bin));

    // Unit file written into the overridden unit_dir with an absolute ExecStart.
    const unit_path = try std.fmt.allocPrint(allocator, "{s}/cloudio-demo.service", .{unit_dir});
    defer allocator.free(unit_path);
    const unit_text = try Io.Dir.cwd().readFileAlloc(std.testing.io, unit_path, allocator, .limited(64 * 1024));
    defer allocator.free(unit_text);
    try std.testing.expect(std.mem.indexOf(u8, unit_text, "ExecStart=/") != null);
    try std.testing.expect(std.mem.indexOf(u8, unit_text, "current/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, unit_text, "Environment=PORT=42000") != null);

    // DB state: deploys row ok, app points at it, caddy route exists.
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT COUNT(*) FROM deploys WHERE status = 'ok' AND finished_at IS NOT NULL"));
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT current_deploy_id FROM apps WHERE name = 'demo'"));
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT COUNT(*) FROM caddy_desired_routes WHERE host = 'demo.example.com' AND kind = 'app' AND upstream = '127.0.0.1:42000'"));
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT COUNT(*) FROM audit_actions WHERE kind = 'app.deploy' AND result = 'ok'"));

    // Deploy log is written and readable through the JSON endpoint.
    out.clearRetainingCapacity();
    try readDeployLog(ctx, "demo", 1, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"kind\":\"deploy_log\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "toolchain: prebuilt") != null);

    // Deploy history endpoint sees the deploy.
    out.clearRetainingCapacity();
    try writeDeploysJson(ctx, "demo", 10, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"status\":\"ok\"") != null);

    // deleteApp removes the row, route, deploy history, unit, and release tree.
    out.clearRetainingCapacity();
    try deleteApp(ctx, "demo", .{ .unit_dir = unit_dir, .run_systemd = false }, &out.writer);
    try std.testing.expectEqual(@as(i64, 0), try testQueryInt(&env.db, "SELECT COUNT(*) FROM apps"));
    try std.testing.expectEqual(@as(i64, 0), try testQueryInt(&env.db, "SELECT COUNT(*) FROM deploys"));
    try std.testing.expectEqual(@as(i64, 0), try testQueryInt(&env.db, "SELECT COUNT(*) FROM caddy_desired_routes"));
    try std.testing.expect(!(try core_fs.fileExists(std.testing.io, release_bin)));
    try std.testing.expect(!(try core_fs.fileExists(std.testing.io, unit_path)));
}

test "rollback repoints current symlink and current_deploy_id" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const workdir = try std.fmt.allocPrint(allocator, "{s}/work", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);
    try testWriteExecutable(allocator, workdir, "roll", "#!/bin/sh\necho v1\n");

    const unit_dir = try std.fmt.allocPrint(allocator, "{s}/units", .{env.base});
    defer allocator.free(unit_dir);
    const opts = DeployOptions{ .unit_dir = unit_dir, .run_systemd = false, .health_check = false };

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "roll", null, workdir, &out.writer);
    try testSetToolchain(&env.db, "roll", "prebuilt");

    out.clearRetainingCapacity();
    try deploy(ctx, "roll", opts, &out.writer);
    try testWriteExecutable(allocator, workdir, "roll", "#!/bin/sh\necho v2\n");
    out.clearRetainingCapacity();
    try deploy(ctx, "roll", opts, &out.writer);

    try std.testing.expectEqual(@as(i64, 2), try testQueryInt(&env.db, "SELECT current_deploy_id FROM apps WHERE name = 'roll'"));

    const current_link = try std.fmt.allocPrint(allocator, "{s}/roll/current", .{env.apps_root});
    defer allocator.free(current_link);
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    var n = try Io.Dir.cwd().readLink(std.testing.io, current_link, &link_buf);
    try std.testing.expectEqualStrings("releases/deploy-2", link_buf[0..n]);

    out.clearRetainingCapacity();
    try rollback(ctx, "roll", null, opts, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"deploy_id\":1") != null);

    n = try Io.Dir.cwd().readLink(std.testing.io, current_link, &link_buf);
    try std.testing.expectEqualStrings("releases/deploy-1", link_buf[0..n]);
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT current_deploy_id FROM apps WHERE name = 'roll'"));
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT COUNT(*) FROM audit_actions WHERE kind = 'app.rollback' AND result = 'ok'"));

    // Rolled-back binary content is v1 again.
    const current_bin = try std.fmt.allocPrint(allocator, "{s}/roll/current/roll", .{env.apps_root});
    defer allocator.free(current_bin);
    const contents = try Io.Dir.cwd().readFileAlloc(std.testing.io, current_bin, allocator, .limited(1024));
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "echo v1") != null);

    // Explicit rollback to a missing deploy id errors.
    try std.testing.expectError(Error.DeployNotFound, rollback(ctx, "roll", 99, opts, &out.writer));
}

test "end-to-end deploy health failure automatically restores the prior release" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);

    var port: u16 = 45000;
    var listener: ?std.Io.net.Server = null;
    while (port < 45100) : (port += 1) {
        var address = try std.Io.net.IpAddress.parse("127.0.0.1", port);
        listener = address.listen(std.testing.io, .{ .reuse_address = true }) catch |err| switch (err) {
            error.AddressInUse => continue,
            else => |e| return e,
        };
        break;
    }
    if (listener == null) return error.SkipZigTest;
    defer if (listener) |*server| server.deinit(std.testing.io);

    var ctx = env.ctx();
    ctx.config.port_min = port;
    ctx.config.port_max = port;

    const workdir = try std.fmt.allocPrint(allocator, "{s}/work", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);
    try testWriteExecutable(allocator, workdir, "recover", "#!/bin/sh\necho v1\n");
    const unit_dir = try std.fmt.allocPrint(allocator, "{s}/units", .{env.base});
    defer allocator.free(unit_dir);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "recover", null, workdir, &out.writer);
    try testSetToolchain(&env.db, "recover", "prebuilt");

    // A real TCP listener makes the first release pass its health probe.
    out.clearRetainingCapacity();
    try deploy(ctx, "recover", .{
        .unit_dir = unit_dir,
        .run_systemd = false,
        .health_check = true,
        .health_check_tries = 1,
    }, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"status\":\"ok\"") != null);
    listener.?.deinit(std.testing.io);
    listener = null;

    // The next release cannot connect; Cloudio marks it failed and atomically
    // restores deploy 1 instead of leaving the unhealthy release active.
    try testWriteExecutable(allocator, workdir, "recover", "#!/bin/sh\necho v2\n");
    out.clearRetainingCapacity();
    try deploy(ctx, "recover", .{
        .unit_dir = unit_dir,
        .run_systemd = false,
        .health_check = true,
        .health_check_tries = 1,
    }, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"status\":\"unhealthy_rolled_back\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"recovered\":true") != null);
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT current_deploy_id FROM apps WHERE name = 'recover'"));
    try std.testing.expectEqual(@as(i64, 1), try testQueryInt(&env.db, "SELECT COUNT(*) FROM deploys WHERE status = 'unhealthy_rolled_back'"));

    const current_bin = try std.fmt.allocPrint(allocator, "{s}/recover/current/recover", .{env.apps_root});
    defer allocator.free(current_bin);
    const contents = try Io.Dir.cwd().readFileAlloc(std.testing.io, current_bin, allocator, .limited(1024));
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "echo v1") != null);
}

test "app operation lock rejects concurrent deployment" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const workdir = try std.fmt.allocPrint(allocator, "{s}/work", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);
    try testWriteExecutable(allocator, workdir, "locked", "#!/bin/sh\necho locked\n");
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "locked", null, workdir, &out.writer);
    try testSetToolchain(&env.db, "locked", "prebuilt");
    const app_id = try testQueryInt(&env.db, "SELECT id FROM apps WHERE name = 'locked'");
    try acquireAppLock(ctx, app_id, "test");
    defer releaseAppLock(ctx, app_id);
    try std.testing.expectError(Error.AppBusy, deploy(ctx, "locked", .{
        .unit_dir = env.base,
        .run_systemd = false,
        .health_check = false,
    }, &out.writer));
}

test "deploy captures git sha from a local repo workdir" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const workdir = try std.fmt.allocPrint(allocator, "{s}/gitwork", .{env.base});
    defer allocator.free(workdir);
    try Io.Dir.cwd().createDirPath(std.testing.io, workdir);
    try testWriteExecutable(allocator, workdir, "shaapp", "#!/bin/sh\necho sha\n");

    // Local tmp git repo; skip the test when git is unavailable.
    const init_result = std.process.run(allocator, std.testing.io, .{
        .argv = &.{ "git", "init", "-q" },
        .cwd = .{ .path = workdir },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return;
    allocator.free(init_result.stdout);
    allocator.free(init_result.stderr);
    inline for (.{
        [_][]const u8{ "git", "add", "." },
        [_][]const u8{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "init" },
    }) |argv| {
        const r = try std.process.run(allocator, std.testing.io, .{
            .argv = &argv,
            .cwd = .{ .path = workdir },
            .stdout_limit = .limited(65536),
            .stderr_limit = .limited(65536),
        });
        allocator.free(r.stdout);
        allocator.free(r.stderr);
    }

    const unit_dir = try std.fmt.allocPrint(allocator, "{s}/units", .{env.base});
    defer allocator.free(unit_dir);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try registerApp(ctx, "shaapp", null, workdir, &out.writer);
    try testSetToolchain(&env.db, "shaapp", "prebuilt");

    out.clearRetainingCapacity();
    try deploy(ctx, "shaapp", .{ .unit_dir = unit_dir, .run_systemd = false, .health_check = false }, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok\":true") != null);
    // sha is a 40-char hex string, not null; release dir is named after it.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sha\":null") == null);
    const sha_count = try testQueryInt(&env.db, "SELECT COUNT(*) FROM deploys WHERE git_sha IS NOT NULL AND LENGTH(git_sha) = 40");
    try std.testing.expectEqual(@as(i64, 1), sha_count);
}
