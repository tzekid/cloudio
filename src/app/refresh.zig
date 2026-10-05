//! Observes every source the pages read. Each source keeps its last-good
//! rows when collection fails, and records the attempt for freshness.

const std = @import("std");
const app_browser_run = @import("browser_run.zig");
const app_dns = @import("dns.zig");
const app_vps = @import("vps.zig");
const collector_caddy = @import("../collectors/caddy.zig");
const collector_project_manifests = @import("../collectors/project_manifests.zig");
const collector_projects = @import("../collectors/projects.zig");
const collector_system = @import("../collectors/system.zig");
const core_config = @import("../core/config.zig");
const core_json = @import("../core/json.zig");
const db_store = @import("../db/store.zig");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
var refresh_mutex: std.atomic.Mutex = .unlocked;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *Db,
    config: core_config.Config,
};

pub const Outcome = enum {
    ok,
    unavailable,
    err,

    fn status(self: Outcome) []const u8 {
        return switch (self) {
            .ok => "ok",
            .unavailable => "unavailable",
            .err => "error",
        };
    }
};

pub const SourceResult = struct {
    name: []const u8,
    outcome: Outcome = .ok,
    detail: []const u8 = "collection completed",
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
        for (self.sources) |source| count += @intFromBool(source.outcome == .ok);
        return count;
    }

    pub fn failureCount(self: Result) usize {
        return self.sources.len - self.successCount();
    }

    pub fn statusCode(self: Result) u16 {
        if (self.failureCount() == 0) return 200;
        if (self.successCount() == 0) return 503;
        return 207;
    }

    pub fn writeJson(self: Result, writer: anytype) !void {
        try writer.writeAll("{\"sources\":[");
        for (self.sources, 0..) |source, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try core_json.writeStringField(writer, "source", source.name, true);
            try core_json.writeStringField(writer, "result", source.outcome.status(), true);
            try core_json.writeStringField(writer, "detail", source.detail, false);
            try writer.writeByte('}');
        }
        try writer.print("],\"succeeded\":{d},\"failed\":{d}}}\n", .{ self.successCount(), self.failureCount() });
    }
};

pub fn run(ctx: Context) !Result {
    if (!refresh_mutex.tryLock()) return error.RefreshInProgress;
    defer refresh_mutex.unlock();

    var result = Result{};
    result.sources[0] = cloudflare(ctx);
    result.sources[1] = hostinger(ctx);
    result.sources[2] = local("caddy", collector_caddy.collect(ctx.io, ctx.gpa, caddyPaths(ctx.config), ctx.db));
    result.sources[3] = local("system", collector_system.collect(ctx.io, ctx.gpa, ctx.db));
    result.sources[4] = local("projects", projects(ctx));
    for (result.sources) |source| {
        const status = if (source.outcome == .ok) "ok" else if (source.outcome == .err) "error" else "skipped";
        _ = try ctx.db.insertSnapshot("refresh", source.name, null, status, source.detail, null, null);
    }
    try ctx.db.insertAudit(
        "refresh",
        if (result.failureCount() == 0) "ok" else "error",
        if (result.failureCount() == 0) "read-only refresh complete" else "read-only refresh completed with unavailable or failed sources",
    );
    return result;
}

fn cloudflare(ctx: Context) SourceResult {
    if (!ctx.config.hasCloudflareAuth()) {
        return .{ .name = "cloudflare", .outcome = .unavailable, .detail = "Cloudflare credentials are not configured" };
    }
    app_browser_run.refreshAccounts(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config }) catch |err| {
        return .{ .name = "cloudflare", .outcome = .err, .detail = @errorName(err) };
    };
    for (ctx.config.domains) |domain| {
        app_dns.refresh(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config }, domain) catch |err| {
            return .{ .name = "cloudflare", .outcome = .err, .detail = @errorName(err) };
        };
    }
    return .{ .name = "cloudflare" };
}

fn hostinger(ctx: Context) SourceResult {
    if (!ctx.config.hasHostingerAuth()) {
        return .{ .name = "hostinger", .outcome = .unavailable, .detail = "Hostinger credentials are not configured" };
    }
    app_vps.refresh(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config }) catch |err| {
        return .{ .name = "hostinger", .outcome = .err, .detail = @errorName(err) };
    };
    return .{ .name = "hostinger" };
}

/// Project correlation runs even when manifest discovery fails so the
/// dashboard keeps current service and route links.
fn projects(ctx: Context) !void {
    const scanned = if (ctx.config.nob_enabled) scanManifests(ctx) else {};
    try collector_projects.collect(ctx.io, ctx.gpa, ctx.config.projects_root, ctx.db);
    try scanned;
}

fn scanManifests(ctx: Context) !void {
    const scan = try collector_project_manifests.scan(ctx.io, ctx.gpa, ctx.db, ctx.config.projects_root, .{
        .scan_depth = ctx.config.nob_scan_depth,
    });
    var detail_buffer: [160]u8 = undefined;
    const detail = try std.fmt.bufPrint(&detail_buffer, "seen={d} valid={d} invalid={d} candidates={d} conflicts={d} missing={d}", .{
        scan.projects_seen, scan.valid, scan.invalid, scan.candidates, scan.conflicts, scan.missing,
    });
    try ctx.db.insertAudit("nob.scan", "ok", detail);
}

fn local(name: []const u8, collected: anyerror!void) SourceResult {
    collected catch |err| return .{ .name = name, .outcome = .err, .detail = @errorName(err) };
    return .{ .name = name };
}

fn caddyPaths(config: core_config.Config) collector_caddy.Paths {
    return .{
        .caddyfile_path = config.caddyfile_path,
        .caddy_sites_path = config.caddy_sites_path,
        .caddy_owned_path = config.caddy_owned_path,
        .caddy_admin_socket = config.caddy_admin_socket,
    };
}

test "refresh result status distinguishes success partial and unavailable" {
    const success = Result{};
    try std.testing.expectEqual(@as(u16, 200), success.statusCode());

    var partial = success;
    partial.sources[0].outcome = .unavailable;
    try std.testing.expectEqual(@as(u16, 207), partial.statusCode());

    var unavailable = Result{};
    for (&unavailable.sources) |*source| source.outcome = .err;
    try std.testing.expectEqual(@as(u16, 503), unavailable.statusCode());
}
