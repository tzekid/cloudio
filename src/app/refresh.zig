const std = @import("std");
const collector_caddy = @import("collector_caddy");
const collector_cloudflare = @import("collector_cloudflare");
const collector_hostinger = @import("collector_hostinger");
const collector_project_manifests = @import("collector_project_manifests");
const collector_projects = @import("collector_projects");
const collector_system = @import("collector_system");
const core_json = @import("core_json");
const core_log = @import("core_log");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
var refresh_mutex: std.atomic.Mutex = .unlocked;

pub const Outcome = enum {
    not_requested,
    ok,
    unavailable,
    err,

    fn status(self: Outcome) []const u8 {
        return switch (self) {
            .not_requested => "not_requested",
            .ok => "ok",
            .unavailable => "unavailable",
            .err => "error",
        };
    }

    fn snapshotStatus(self: Outcome) []const u8 {
        return switch (self) {
            .not_requested => "skipped",
            .ok => "ok",
            .unavailable => "skipped",
            .err => "error",
        };
    }
};

pub const SourceResult = struct {
    name: []const u8,
    outcome: Outcome = .not_requested,
    detail: []const u8 = "not requested",
};

pub const Result = struct {
    sources: [5]SourceResult = .{
        .{ .name = "cloudflare" },
        .{ .name = "hostinger" },
        .{ .name = "caddy" },
        .{ .name = "system" },
        .{ .name = "projects" },
    },

    pub fn successCount(self: Result) usize {
        var count: usize = 0;
        for (self.sources) |source| if (source.outcome == .ok) {
            count += 1;
        };
        return count;
    }

    pub fn failureCount(self: Result) usize {
        var count: usize = 0;
        for (self.sources) |source| if (source.outcome == .err or source.outcome == .unavailable) {
            count += 1;
        };
        return count;
    }

    pub fn statusCode(self: Result) u16 {
        if (self.failureCount() == 0) return 200;
        if (self.successCount() == 0) return 503;
        return 207;
    }

    pub fn writeJson(self: Result, gpa: Allocator, db: *Db, writer: anytype) !void {
        try writer.writeAll("{\"sources\":[");
        var first = true;
        for (self.sources) |source| {
            if (source.outcome == .not_requested) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.writeByte('{');
            try core_json.writeStringField(writer, "source", source.name, true);
            try core_json.writeStringField(writer, "result", source.outcome.status(), true);
            try core_json.writeStringField(writer, "detail", source.detail, true);
            const observation_optional = try db.latestObservation(gpa, "refresh", source.name);
            if (observation_optional) |observation_const| {
                var observation = observation_const;
                defer observation.deinit(gpa);
                try core_json.writeStringField(writer, "attempted_at", observation.attempted_at, true);
                try core_json.writeStringField(writer, "observed_at", observation.observed_at, false);
            } else {
                try core_json.writeStringField(writer, "attempted_at", "", true);
                try core_json.writeStringField(writer, "observed_at", "", false);
            }
            try writer.writeByte('}');
        }
        try writer.writeAll("],");
        try core_json.writeIntField(writer, "succeeded", @as(i64, @intCast(self.successCount())), true);
        try core_json.writeIntField(writer, "failed", @as(i64, @intCast(self.failureCount())), false);
        try writer.writeAll("}\n");
    }
};

pub const Selection = struct {
    cloudflare: bool = true,
    hostinger: bool = true,
    caddy: bool = true,
    system: bool = true,
    projects: bool = true,
    dashboard: bool = false,

    pub fn all() Selection {
        return .{};
    }

    pub fn dashboardProfile() Selection {
        return .{ .dashboard = true };
    }

    pub fn none() Selection {
        return .{
            .cloudflare = false,
            .hostinger = false,
            .caddy = false,
            .system = false,
            .projects = false,
        };
    }

    pub fn label(self: Selection) []const u8 {
        if (self.dashboard) return "dashboard";
        if (self.cloudflare and self.hostinger and self.caddy and self.system and self.projects) return "all";
        return "selected";
    }
};

pub const LogMetadata = struct {
    version: []const u8,
    db_path: []const u8,
    config_path: []const u8,
    log_path: []const u8,
    loaded_dotenv: bool,
    loaded_fish_env: bool,
    cloudflare_auth: bool,
    hostinger_auth: bool,
};

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    domains: []const []const u8,
    cloudflare_auth: collector_cloudflare.Auth,
    hostinger_token: ?[]const u8,
    hostinger_api_base: []const u8,
    caddy_paths: collector_caddy.Paths,
    projects_root: []const u8,
    nob_enabled: bool,
    nob_scan_depth: u8,
    log: LogMetadata,
};

pub fn run(ctx: Context, selection: Selection) !Result {
    if (!refresh_mutex.tryLock()) return error.RefreshInProgress;
    defer refresh_mutex.unlock();

    var result = Result{};
    const start_snapshot_id = try ctx.db.latestSnapshotId();
    if (selection.cloudflare) {
        if (!ctx.cloudflare_auth.hasApiToken() and !ctx.cloudflare_auth.hasLegacy()) {
            result.sources[0] = .{ .name = "cloudflare", .outcome = .unavailable, .detail = "Cloudflare credentials are not configured" };
        } else {
            const collected = if (selection.dashboard)
                collector_cloudflare.collectDashboard(ctx.io, ctx.gpa, ctx.cloudflare_auth, ctx.domains, ctx.db)
            else
                collector_cloudflare.collectAll(ctx.io, ctx.gpa, ctx.cloudflare_auth, ctx.domains, ctx.db);
            if (collected) {
                result.sources[0] = .{ .name = "cloudflare", .outcome = .ok, .detail = "collection completed" };
            } else |err| {
                result.sources[0] = .{ .name = "cloudflare", .outcome = .err, .detail = @errorName(err) };
            }
        }
        try recordSource(ctx.db, result.sources[0]);
    }
    if (selection.hostinger) {
        if (ctx.hostinger_token == null or ctx.hostinger_token.?.len == 0) {
            result.sources[1] = .{ .name = "hostinger", .outcome = .unavailable, .detail = "Hostinger credentials are not configured" };
        } else {
            const collected = if (selection.dashboard)
                collectHostingerDashboard(ctx)
            else
                collector_hostinger.collectAll(ctx.io, ctx.gpa, ctx.hostinger_token, ctx.domains, ctx.db);
            if (collected) {
                result.sources[1] = .{ .name = "hostinger", .outcome = .ok, .detail = "collection completed" };
            } else |err| {
                result.sources[1] = .{ .name = "hostinger", .outcome = .err, .detail = @errorName(err) };
            }
        }
        try recordSource(ctx.db, result.sources[1]);
    }
    if (selection.caddy) {
        if (collector_caddy.collect(ctx.io, ctx.gpa, ctx.caddy_paths, ctx.db)) {
            result.sources[2] = .{ .name = "caddy", .outcome = .ok, .detail = "collection completed" };
        } else |err| {
            result.sources[2] = .{ .name = "caddy", .outcome = .err, .detail = @errorName(err) };
        }
        try recordSource(ctx.db, result.sources[2]);
    }
    if (selection.system) {
        if (collector_system.collect(ctx.io, ctx.gpa, ctx.db)) {
            result.sources[3] = .{ .name = "system", .outcome = .ok, .detail = "collection completed" };
        } else |err| {
            result.sources[3] = .{ .name = "system", .outcome = .err, .detail = @errorName(err) };
        }
        try recordSource(ctx.db, result.sources[3]);
    }
    if (selection.projects) {
        var project_error: ?anyerror = null;
        if (ctx.nob_enabled) {
            const scanned = collector_project_manifests.scan(ctx.io, ctx.gpa, ctx.db, ctx.projects_root, .{
                .scan_depth = ctx.nob_scan_depth,
            }) catch |err| blk: {
                project_error = err;
                break :blk null;
            };
            if (scanned) |scan_result| {
                const detail = try std.fmt.allocPrint(
                    ctx.gpa,
                    "seen={d} valid={d} invalid={d} candidates={d} conflicts={d} missing={d}",
                    .{ scan_result.projects_seen, scan_result.valid, scan_result.invalid, scan_result.candidates, scan_result.conflicts, scan_result.missing },
                );
                defer ctx.gpa.free(detail);
                try ctx.db.insertAudit("nob.scan", "ok", detail);
            }
        }
        collector_projects.collect(ctx.io, ctx.gpa, ctx.projects_root, ctx.db) catch |err| {
            if (project_error == null) project_error = err;
        };
        if (project_error) |err| {
            result.sources[4] = .{ .name = "projects", .outcome = .err, .detail = @errorName(err) };
        } else {
            result.sources[4] = .{ .name = "projects", .outcome = .ok, .detail = "collection completed" };
        }
        try recordSource(ctx.db, result.sources[4]);
    }
    try ctx.db.insertAudit(
        "refresh",
        if (result.failureCount() == 0) "ok" else "error",
        if (result.failureCount() == 0) "read-only refresh complete" else "read-only refresh completed with unavailable or failed sources",
    );
    try writeRefreshLog(ctx, selection, start_snapshot_id);
    return result;
}

fn collectHostingerDashboard(ctx: Context) !void {
    var output = try collector_hostinger.collectVpsAt(
        ctx.io,
        ctx.gpa,
        ctx.hostinger_token,
        ctx.hostinger_api_base,
        ctx.db,
        false,
    );
    output.deinit(ctx.gpa);
}

fn recordSource(db: *Db, result: SourceResult) !void {
    _ = try db.insertSnapshot("refresh", result.name, null, result.outcome.snapshotStatus(), result.detail, null, null);
}

fn writeRefreshLog(ctx: Context, selection: Selection, start_snapshot_id: i64) !void {
    var out = core_log.Buffer.init(ctx.gpa);
    defer out.deinit();

    try core_log.writeRefreshHeader(out.writer(), .{
        .version = ctx.log.version,
        .selection = selection.label(),
        .db_path = ctx.log.db_path,
        .config_path = ctx.log.config_path,
        .loaded_dotenv = ctx.log.loaded_dotenv,
        .loaded_fish_env = ctx.log.loaded_fish_env,
        .cloudflare_auth = ctx.log.cloudflare_auth,
        .hostinger_auth = ctx.log.hostinger_auth,
    });
    try out.writer().writeAll("\ncounts\n");
    try ctx.db.writeOverviewCounts(out.writer());
    try out.writer().writeAll("\nrun_snapshots\n");
    try ctx.db.writeSnapshotsAfter(out.writer(), start_snapshot_id);

    const bytes = try out.toOwnedSlice();
    defer ctx.gpa.free(bytes);
    try core_log.writeRedactedFile(ctx.io, ctx.gpa, ctx.log.log_path, bytes);
}

test "refresh selection labels all versus selected" {
    try std.testing.expectEqualStrings("all", Selection.all().label());
    try std.testing.expectEqualStrings("dashboard", Selection.dashboardProfile().label());
    try std.testing.expectEqualStrings("selected", Selection.none().label());
    try std.testing.expectEqualStrings("selected", (Selection{ .projects = false }).label());
}

test "refresh result status distinguishes success partial and unavailable" {
    var success = Result{};
    for (&success.sources) |*source| source.outcome = .ok;
    try std.testing.expectEqual(@as(u16, 200), success.statusCode());

    var partial = success;
    partial.sources[0].outcome = .unavailable;
    try std.testing.expectEqual(@as(u16, 207), partial.statusCode());

    var unavailable = Result{};
    for (&unavailable.sources) |*source| source.outcome = .err;
    try std.testing.expectEqual(@as(u16, 503), unavailable.statusCode());
}
