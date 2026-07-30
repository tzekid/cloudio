//! B3: Caddyfile desired state: import, render, validate, write, reload.
//!
//! cloudio owns the whole Caddyfile. Routes live in caddy_desired_routes;
//! the global options block and preserved top-level lines live in settings
//! (keys 'caddy_global_options' and 'caddy_top_level_lines').
//!
//! Import notes: `import /etc/caddy/conf.d/*.caddy` lines are preserved in
//! 'caddy_top_level_lines' but are NOT expanded; site blocks in included
//! files must be imported separately by calling importCaddyfile on that
//! path. After import the DB is the source of truth, so render() drops
//! import lines: everything is emitted from the DB.
const std = @import("std");
const sqlite = @import("sqlite");
const app_writes = @import("app_writes");
const core_fs = @import("core_fs");
const core_json = @import("core_json");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

const max_file_bytes = 8 * 1024 * 1024;
const max_command_bytes = 4 * 1024 * 1024;
const runCommand = core_process.run;

pub const Error = error{ SqliteBind, SqliteStep, ValidateFailed };

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    write_meta: app_writes.Metadata = .{},
};

pub const ImportSummary = struct {
    imported_manual: usize = 0,
    imported_raw: usize = 0,
    skipped_app: usize = 0,
};

pub const ApplyOptions = struct {
    validate_cmd: bool = true,
    reload: bool = true,
};

pub const ApplyResult = struct {
    validated: bool,
    reloaded: bool,
    bytes: usize,
    backup_path: ?[]u8,

    pub fn deinit(self: ApplyResult, gpa: Allocator) void {
        if (self.backup_path) |p| gpa.free(p);
    }
};

// --- Route CRUD ---

pub fn upsertRoute(ctx: Context, host: []const u8, upstream: ?[]const u8, kind: []const u8, extra_directives: ?[]const u8, raw_block: ?[]const u8, app_id: ?i64) !void {
    const stmt = try ctx.db.prepare(
        \\INSERT INTO caddy_desired_routes(host, upstream, kind, extra_directives, raw_block, app_id)
        \\VALUES (?, ?, ?, ?, ?, ?)
        \\ON CONFLICT(host) DO UPDATE SET
        \\  upstream = excluded.upstream,
        \\  kind = excluded.kind,
        \\  extra_directives = excluded.extra_directives,
        \\  raw_block = excluded.raw_block,
        \\  app_id = excluded.app_id,
        \\  updated_at = CURRENT_TIMESTAMP
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    try bindTextOpt(stmt, 2, upstream);
    try bindText(stmt, 3, kind);
    try bindTextOpt(stmt, 4, extra_directives);
    try bindTextOpt(stmt, 5, raw_block);
    if (app_id) |id| {
        if (sqlite.sqlite3_bind_int64(stmt, 6, id) != sqlite.SQLITE_OK) return Error.SqliteBind;
    } else {
        if (sqlite.sqlite3_bind_null(stmt, 6) != sqlite.SQLITE_OK) return Error.SqliteBind;
    }
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    const detail = try std.fmt.allocPrint(ctx.gpa, "kind={s}; upstream={s}; enabled=true", .{ kind, upstream orelse "" });
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "caddy.route.upsert", host, null, .ok, detail);
}

pub fn deleteRoute(ctx: Context, host: []const u8) !void {
    const stmt = try ctx.db.prepare("DELETE FROM caddy_desired_routes WHERE host = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "caddy.route.delete", host, null, .ok, "desired route removed");
}

pub fn setEnabled(ctx: Context, host: []const u8, enabled: bool) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE host = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    if (sqlite.sqlite3_bind_int64(stmt, 1, if (enabled) 1 else 0) != sqlite.SQLITE_OK) return Error.SqliteBind;
    try bindText(stmt, 2, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
    _ = try app_writes.recordWithMetadata(
        ctx.gpa,
        ctx.db,
        ctx.write_meta,
        "caddy.route.toggle",
        host,
        null,
        .ok,
        if (enabled) "enabled" else "disabled",
    );
}

pub fn writeRoutesJson(ctx: Context, writer: anytype) !void {
    const stmt = try ctx.db.prepare(
        \\SELECT host, upstream, kind, extra_directives, enabled, app_id, updated_at
        \\FROM caddy_desired_routes ORDER BY host
    );
    defer _ = sqlite.sqlite3_finalize(stmt);

    try writer.writeAll("{\"kind\":\"caddy_routes\",\"routes\":[");
    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "host", columnText(stmt, 0) orelse "", true);
        try core_json.writeNullableStringField(writer, "upstream", columnText(stmt, 1), true);
        try core_json.writeStringField(writer, "kind", columnText(stmt, 2) orelse "", true);
        try core_json.writeNullableStringField(writer, "extra_directives", columnText(stmt, 3), true);
        try core_json.writeBoolField(writer, "enabled", sqlite.sqlite3_column_int64(stmt, 4) != 0, true);
        if (sqlite.sqlite3_column_type(stmt, 5) == sqlite.SQLITE_NULL) {
            try writer.writeAll("\"app_id\":null,");
        } else {
            try core_json.writeIntField(writer, "app_id", sqlite.sqlite3_column_int64(stmt, 5), true);
        }
        try core_json.writeNullableStringField(writer, "updated_at", columnText(stmt, 6), false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

// --- Importer ---

pub fn importCaddyfile(ctx: Context, path: []const u8) !ImportSummary {
    const raw = try Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.gpa, .limited(max_file_bytes));
    defer ctx.gpa.free(raw);
    return importCaddyfileText(ctx, raw);
}

fn importCaddyfileText(ctx: Context, raw: []const u8) !ImportSummary {
    var summary = ImportSummary{};
    const gpa = ctx.gpa;

    var top_level_lines = std.ArrayList(u8).empty;
    defer top_level_lines.deinit(gpa);
    var block = std.ArrayList(u8).empty;
    defer block.deinit(gpa);

    var depth: i32 = 0;
    var in_block = false;
    var is_global_block = false;
    var host_label: ?[]u8 = null;
    defer if (host_label) |h| gpa.free(h);
    var seen_site_block = false;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = trim(line_raw);
        if (!in_block) {
            if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
            if (std.mem.endsWith(u8, line, "{")) {
                const label = trim(line[0 .. line.len - 1]);
                in_block = true;
                is_global_block = label.len == 0 and !seen_site_block;
                if (!is_global_block) {
                    seen_site_block = true;
                    host_label = try gpa.dupe(u8, label);
                }
                block.clearRetainingCapacity();
                try block.appendSlice(gpa, line_raw);
                try block.append(gpa, '\n');
                depth = @intCast(countByte(line, '{'));
                depth -= @intCast(countByte(line, '}'));
                if (depth == 0) {
                    try finishBlock(ctx, &summary, is_global_block, &host_label, block.items);
                    in_block = false;
                }
                continue;
            }
            // Top-level non-block line (e.g. `import /etc/caddy/conf.d/*.caddy`):
            // preserved verbatim, in order, in settings 'caddy_top_level_lines'.
            try top_level_lines.appendSlice(gpa, line_raw);
            try top_level_lines.append(gpa, '\n');
            continue;
        }
        try block.appendSlice(gpa, line_raw);
        try block.append(gpa, '\n');
        depth += @intCast(countByte(line, '{'));
        depth -= @intCast(countByte(line, '}'));
        if (depth <= 0) {
            try finishBlock(ctx, &summary, is_global_block, &host_label, block.items);
            in_block = false;
            depth = 0;
        }
    }

    if (top_level_lines.items.len > 0) {
        try setSetting(ctx, "caddy_top_level_lines", top_level_lines.items);
    }
    return summary;
}

fn finishBlock(ctx: Context, summary: *ImportSummary, is_global: bool, host_label: *?[]u8, block_text: []const u8) !void {
    if (is_global) {
        try setSetting(ctx, "caddy_global_options", block_text);
        return;
    }
    const host = host_label.* orelse return;
    defer {
        ctx.gpa.free(host);
        host_label.* = null;
    }

    if (try routeKind(ctx, host)) |existing_kind| {
        defer ctx.gpa.free(existing_kind);
        if (std.mem.eql(u8, existing_kind, "app")) {
            summary.skipped_app += 1;
            return;
        }
    }

    if (soleReverseProxyUpstream(block_text)) |upstream| {
        try upsertRoute(ctx, host, upstream, "manual", null, null, null);
        summary.imported_manual += 1;
    } else {
        try upsertRoute(ctx, host, null, "raw", null, block_text, null);
        summary.imported_raw += 1;
    }
}

/// If the block body is exactly one `reverse_proxy <upstream>` directive
/// (ignoring blank lines and comments), return the upstream token.
fn soleReverseProxyUpstream(block_text: []const u8) ?[]const u8 {
    var upstream: ?[]const u8 = null;
    var body_lines: usize = 0;
    var lines = std.mem.splitScalar(u8, block_text, '\n');
    var index: usize = 0;
    while (lines.next()) |line_raw| : (index += 1) {
        const line = trim(line_raw);
        if (index == 0) continue; // host line with `{`
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        if (std.mem.eql(u8, line, "}")) continue;
        body_lines += 1;
        if (std.mem.startsWith(u8, line, "reverse_proxy")) {
            const rest = trim(line["reverse_proxy".len..]);
            const token = firstToken(rest);
            if (token.len > 0 and !std.mem.eql(u8, token, "{") and std.mem.indexOfScalar(u8, rest, '{') == null) {
                if (std.mem.eql(u8, rest, token)) upstream = token;
            }
        }
    }
    if (body_lines == 1) return upstream;
    return null;
}

fn routeKind(ctx: Context, host: []const u8) !?[]u8 {
    const stmt = try ctx.db.prepare("SELECT kind FROM caddy_desired_routes WHERE host = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    return try ctx.gpa.dupe(u8, columnText(stmt, 0) orelse "");
}

// --- Renderer ---

/// Deterministic full Caddyfile from the DB: global options block (if
/// imported), preserved top-level lines except `import` lines (the DB is
/// the source of truth after import), then every enabled route ordered by
/// host. Raw rows are emitted verbatim; app/manual rows get a generated
/// block with tab-indented directives.
pub fn render(ctx: Context, gpa: Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    if (try getSetting(ctx, "caddy_global_options")) |global_block| {
        defer ctx.gpa.free(global_block);
        try w.writeAll(global_block);
        if (!std.mem.endsWith(u8, global_block, "\n")) try w.writeByte('\n');
        try w.writeByte('\n');
    }

    if (try getSetting(ctx, "caddy_top_level_lines")) |top_lines| {
        defer ctx.gpa.free(top_lines);
        var wrote_any = false;
        var lines = std.mem.splitScalar(u8, top_lines, '\n');
        while (lines.next()) |line_raw| {
            const line = trim(line_raw);
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "import ")) continue;
            try w.writeAll(line_raw);
            try w.writeByte('\n');
            wrote_any = true;
        }
        if (wrote_any) try w.writeByte('\n');
    }

    const stmt = try ctx.db.prepare(
        \\SELECT host, upstream, kind, extra_directives, raw_block
        \\FROM caddy_desired_routes WHERE enabled = 1 ORDER BY host
    );
    defer _ = sqlite.sqlite3_finalize(stmt);

    var first = true;
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
        if (!first) try w.writeByte('\n');
        first = false;

        const host = columnText(stmt, 0) orelse "";
        const kind = columnText(stmt, 2) orelse "";
        if (std.mem.eql(u8, kind, "raw")) {
            const raw_block = columnText(stmt, 4) orelse "";
            try w.writeAll(raw_block);
            if (!std.mem.endsWith(u8, raw_block, "\n")) try w.writeByte('\n');
            continue;
        }
        try w.writeAll(host);
        try w.writeAll(" {\n");
        if (columnText(stmt, 1)) |upstream| {
            try w.writeAll("\treverse_proxy ");
            try w.writeAll(upstream);
            try w.writeByte('\n');
        }
        if (columnText(stmt, 3)) |extra| {
            var extra_lines = std.mem.splitScalar(u8, extra, '\n');
            while (extra_lines.next()) |extra_line| {
                const trimmed = trim(extra_line);
                if (trimmed.len == 0) continue;
                try w.writeByte('\t');
                try w.writeAll(trimmed);
                try w.writeByte('\n');
            }
        }
        try w.writeAll("}\n");
    }

    return try out.toOwnedSlice();
}

// --- Apply ---

pub fn apply(ctx: Context, caddyfile_path: []const u8, opts: ApplyOptions) !ApplyResult {
    const gpa = ctx.gpa;
    const rendered = try render(ctx, gpa);
    defer gpa.free(rendered);

    const tmp_path = try std.fmt.allocPrint(gpa, "{s}.cloudio.tmp", .{caddyfile_path});
    defer gpa.free(tmp_path);
    try core_fs.ensureParentDir(ctx.io, caddyfile_path);
    try Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = tmp_path, .data = rendered });

    var validated = false;
    if (opts.validate_cmd) {
        const result = runCommand(gpa, ctx.io, &.{ "caddy", "validate", "--config", tmp_path }, max_command_bytes) catch |err| {
            const detail = try std.fmt.allocPrint(gpa, "caddy validate could not run: {s}", .{@errorName(err)});
            defer gpa.free(detail);
            _ = try app_writes.recordWithMetadata(gpa, ctx.db, ctx.write_meta, "caddy.apply", caddyfile_path, null, .err, detail);
            Io.Dir.cwd().deleteFile(ctx.io, tmp_path) catch {};
            return Error.ValidateFailed;
        };
        defer result.deinit(gpa);
        if (!result.ok()) {
            const detail = try std.fmt.allocPrint(gpa, "caddy validate failed: {s}", .{result.stderr});
            defer gpa.free(detail);
            _ = try app_writes.recordWithMetadata(gpa, ctx.db, ctx.write_meta, "caddy.apply", caddyfile_path, null, .err, detail);
            Io.Dir.cwd().deleteFile(ctx.io, tmp_path) catch {};
            return Error.ValidateFailed;
        }
        validated = true;
    }

    var backup_path: ?[]u8 = null;
    errdefer if (backup_path) |p| gpa.free(p);
    if (try core_fs.fileExists(ctx.io, caddyfile_path)) {
        const existing = try Io.Dir.cwd().readFileAlloc(ctx.io, caddyfile_path, gpa, .limited(max_file_bytes));
        defer gpa.free(existing);
        const ts = try epochSeconds();
        const bak = try std.fmt.allocPrint(gpa, "{s}.bak.{d}", .{ caddyfile_path, ts });
        try Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = bak, .data = existing });
        backup_path = bak;
    }

    try Io.Dir.cwd().rename(tmp_path, Io.Dir.cwd(), caddyfile_path, ctx.io);

    var reloaded = false;
    var reload_status: []const u8 = "skipped";
    var reload_stderr: []u8 = &.{};
    defer if (reload_stderr.len > 0) gpa.free(reload_stderr);
    if (opts.reload) {
        if (runCommand(gpa, ctx.io, &.{ "systemctl", "reload", "caddy" }, max_command_bytes)) |result| {
            defer result.deinit(gpa);
            reloaded = result.ok();
            reload_status = result.statusText();
            if (!result.ok()) reload_stderr = try gpa.dupe(u8, result.stderr);
        } else |err| {
            reload_status = @errorName(err);
        }
    }

    const detail = try std.fmt.allocPrint(gpa, "wrote {d} bytes; validate={s}; reload={s}{s}{s}", .{
        rendered.len,
        if (validated) "ok" else "skipped",
        reload_status,
        if (reload_stderr.len > 0) "; reload stderr: " else "",
        reload_stderr,
    });
    defer gpa.free(detail);
    const result_state: app_writes.Result = if (opts.reload and !reloaded) .err else .ok;
    _ = try app_writes.recordWithMetadata(gpa, ctx.db, ctx.write_meta, "caddy.apply", caddyfile_path, null, result_state, detail);

    return .{
        .validated = validated,
        .reloaded = reloaded,
        .bytes = rendered.len,
        .backup_path = backup_path,
    };
}

// --- Preview ---

pub fn writePreviewJson(ctx: Context, writer: anytype) !void {
    const rendered = try render(ctx, ctx.gpa);
    defer ctx.gpa.free(rendered);
    try writer.writeAll("{\"kind\":\"caddy_preview\",");
    try core_json.writeStringField(writer, "rendered", rendered, false);
    try writer.writeAll("}\n");
}

// --- Settings helpers ---

fn setSetting(ctx: Context, key: []const u8, value: []const u8) !void {
    const stmt = try ctx.db.prepare(
        \\INSERT INTO settings(key, value) VALUES (?, ?)
        \\ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, key);
    try bindText(stmt, 2, value);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return Error.SqliteStep;
}

fn getSetting(ctx: Context, key: []const u8) !?[]u8 {
    const stmt = try ctx.db.prepare("SELECT value FROM settings WHERE key = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, key);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return Error.SqliteStep;
    const text = columnText(stmt, 0) orelse return null;
    return try ctx.gpa.dupe(u8, text);
}

// --- Small helpers ---

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

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn firstToken(value: []const u8) []const u8 {
    var it = std.mem.tokenizeAny(u8, value, " \t\r\n");
    return it.next() orelse "";
}

fn countByte(value: []const u8, needle: u8) usize {
    var count: usize = 0;
    for (value) |ch| {
        if (ch == needle) count += 1;
    }
    return count;
}

fn epochSeconds() !u64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (std.os.linux.errno(rc) != .SUCCESS) return error.ClockGettimeFailed;
    if (ts.sec < 0) return error.ClockGettimeFailed;
    return @intCast(ts.sec);
}

// --- Tests ---

const TestEnv = struct {
    tmp: std.testing.TmpDir,
    db: Db,
    db_path: []u8,

    fn init(gpa: Allocator) !TestEnv {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const db_path = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}/caddy_desired.db", .{tmp.sub_path});
        errdefer gpa.free(db_path);
        var db = try Db.open(std.testing.io, db_path);
        errdefer db.close();
        try db.initSchema();
        return .{ .tmp = tmp, .db = db, .db_path = db_path };
    }

    fn ctx(self: *TestEnv) Context {
        return .{ .io = std.testing.io, .gpa = std.testing.allocator, .db = &self.db };
    }

    fn deinit(self: *TestEnv, gpa: Allocator) void {
        self.db.close();
        gpa.free(self.db_path);
        self.tmp.cleanup();
    }

    fn subPath(self: *TestEnv, gpa: Allocator, name: []const u8) ![]u8 {
        return std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}/{s}", .{ self.tmp.sub_path, name });
    }
};

const synthetic_caddyfile =
    "{\n" ++
    "\tadmin unix//run/caddy/admin.socket|0660\n" ++
    "\t# admin 127.0.0.1:2019\n" ++
    "}\n" ++
    "\n" ++
    "import /etc/caddy/conf.d/*.caddy\n" ++
    "\n" ++
    "simple.example.com {\n" ++
    "\treverse_proxy 127.0.0.1:3000\n" ++
    "}\n" ++
    "\n" ++
    "multi.example.com {\n" ++
    "\tencode zstd gzip\n" ++
    "\treverse_proxy 127.0.0.1:4000\n" ++
    "}\n" ++
    "\n" ++
    "a.example.com, b.example.com {\n" ++
    "\t# both hosts proxied\n" ++
    "\treverse_proxy 127.0.0.1:5000\n" ++
    "}\n";

test "importer classifies blocks and is idempotent" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    const caddyfile_path = try env.subPath(allocator, "Caddyfile");
    defer allocator.free(caddyfile_path);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = caddyfile_path, .data = synthetic_caddyfile });

    const summary = try importCaddyfile(ctx, caddyfile_path);
    try std.testing.expectEqual(@as(usize, 2), summary.imported_manual);
    try std.testing.expectEqual(@as(usize, 1), summary.imported_raw);
    try std.testing.expectEqual(@as(usize, 0), summary.skipped_app);

    // Comma host label kept as full label string, single reverse_proxy => manual.
    const comma_kind = (try routeKind(ctx, "a.example.com, b.example.com")).?;
    defer allocator.free(comma_kind);
    try std.testing.expectEqualStrings("manual", comma_kind);

    const multi_kind = (try routeKind(ctx, "multi.example.com")).?;
    defer allocator.free(multi_kind);
    try std.testing.expectEqualStrings("raw", multi_kind);

    const global = (try getSetting(ctx, "caddy_global_options")).?;
    defer allocator.free(global);
    try std.testing.expect(std.mem.indexOf(u8, global, "admin unix//run/caddy/admin.socket|0660") != null);

    const top_lines = (try getSetting(ctx, "caddy_top_level_lines")).?;
    defer allocator.free(top_lines);
    try std.testing.expect(std.mem.indexOf(u8, top_lines, "import /etc/caddy/conf.d/*.caddy") != null);

    // App-owned rows survive re-import.
    try upsertRoute(ctx, "simple.example.com", "127.0.0.1:9999", "app", null, null, 7);
    const again = try importCaddyfile(ctx, caddyfile_path);
    try std.testing.expectEqual(@as(usize, 1), again.imported_manual);
    try std.testing.expectEqual(@as(usize, 1), again.imported_raw);
    try std.testing.expectEqual(@as(usize, 1), again.skipped_app);
    const count_stmt = try env.db.prepare("SELECT COUNT(*) FROM caddy_desired_routes");
    defer _ = sqlite.sqlite3_finalize(count_stmt);
    try std.testing.expect(sqlite.sqlite3_step(count_stmt) == sqlite.SQLITE_ROW);
    try std.testing.expectEqual(@as(i64, 3), sqlite.sqlite3_column_int64(count_stmt, 0));

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRoutesJson(ctx, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"caddy_routes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"upstream\":\"127.0.0.1:9999\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"app_id\":7") != null);
}

test "renderer is deterministic, honors raw and disabled rows" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    try upsertRoute(ctx, "b.app.example", "127.0.0.1:3001", "app", "encode zstd gzip\nheader X-Test on", null, 1);
    try upsertRoute(ctx, "c.manual.example", "127.0.0.1:3002", "manual", null, null, null);
    const raw_block = "a.raw.example {\n\trespond \"hi\" 200\n}\n";
    try upsertRoute(ctx, "a.raw.example", null, "raw", null, raw_block, null);
    try upsertRoute(ctx, "d.disabled.example", "127.0.0.1:3003", "manual", null, null, null);
    try setEnabled(ctx, "d.disabled.example", false);

    const rendered = try render(ctx, allocator);
    defer allocator.free(rendered);
    const expected =
        "a.raw.example {\n\trespond \"hi\" 200\n}\n" ++
        "\nb.app.example {\n\treverse_proxy 127.0.0.1:3001\n\tencode zstd gzip\n\theader X-Test on\n}\n" ++
        "\nc.manual.example {\n\treverse_proxy 127.0.0.1:3002\n}\n";
    try std.testing.expectEqualStrings(expected, rendered);

    const rendered_again = try render(ctx, allocator);
    defer allocator.free(rendered_again);
    try std.testing.expectEqualStrings(rendered, rendered_again);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writePreviewJson(ctx, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\"kind\":\"caddy_preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "a.raw.example {\\n") != null);

    try deleteRoute(ctx, "a.raw.example");
    const after_delete = try render(ctx, allocator);
    defer allocator.free(after_delete);
    try std.testing.expect(std.mem.indexOf(u8, after_delete, "a.raw.example") == null);
}

test "apply writes file, backs up, records audit; no validate or reload" {
    const allocator = std.testing.allocator;
    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    try upsertRoute(ctx, "site.example.com", "127.0.0.1:8000", "manual", null, null, null);

    const target = try env.subPath(allocator, "Caddyfile.out");
    defer allocator.free(target);

    const first = try apply(ctx, target, .{ .validate_cmd = false, .reload = false });
    defer first.deinit(allocator);
    try std.testing.expect(!first.validated);
    try std.testing.expect(!first.reloaded);
    try std.testing.expect(first.bytes > 0);
    try std.testing.expect(first.backup_path == null);

    const written = try Io.Dir.cwd().readFileAlloc(std.testing.io, target, allocator, .limited(max_file_bytes));
    defer allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "site.example.com {") != null);
    try std.testing.expectEqual(first.bytes, written.len);

    const second = try apply(ctx, target, .{ .validate_cmd = false, .reload = false });
    defer second.deinit(allocator);
    try std.testing.expect(second.backup_path != null);
    try std.testing.expect(try core_fs.fileExists(std.testing.io, second.backup_path.?));

    const stmt = try env.db.prepare("SELECT COUNT(*) FROM audit_actions WHERE kind = 'caddy.apply' AND result = 'ok'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try std.testing.expect(sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW);
    try std.testing.expectEqual(@as(i64, 2), sqlite.sqlite3_column_int64(stmt, 0));
}

test "round-trips real /etc/caddy/Caddyfile when readable" {
    const allocator = std.testing.allocator;
    const real = Io.Dir.cwd().readFileAlloc(std.testing.io, "/etc/caddy/Caddyfile", allocator, .limited(max_file_bytes)) catch return;
    defer allocator.free(real);

    var env = try TestEnv.init(allocator);
    defer env.deinit(allocator);
    const ctx = env.ctx();

    _ = try importCaddyfileText(ctx, real);
    const rendered = try render(ctx, allocator);
    defer allocator.free(rendered);

    const stmt = try env.db.prepare("SELECT host FROM caddy_desired_routes ORDER BY host");
    defer _ = sqlite.sqlite3_finalize(stmt);
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        try std.testing.expect(rc == sqlite.SQLITE_ROW);
        const host = columnText(stmt, 0) orelse "";
        try std.testing.expect(std.mem.indexOf(u8, rendered, host) != null);
    }
}
