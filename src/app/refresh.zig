const std = @import("std");
const collector_caddy = @import("collector_caddy");
const collector_cloudflare = @import("collector_cloudflare");
const collector_hostinger = @import("collector_hostinger");
const collector_projects = @import("collector_projects");
const collector_system = @import("collector_system");
const core_log = @import("core_log");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

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
    caddy_paths: collector_caddy.Paths,
    projects_root: []const u8,
    log: LogMetadata,
};

pub fn run(ctx: Context, selection: Selection) !void {
    const start_snapshot_id = try ctx.db.latestSnapshotId();
    if (selection.cloudflare) {
        if (selection.dashboard) {
            try collector_cloudflare.collectDashboard(ctx.io, ctx.gpa, ctx.cloudflare_auth, ctx.domains, ctx.db);
        } else {
            try collector_cloudflare.collectAll(ctx.io, ctx.gpa, ctx.cloudflare_auth, ctx.domains, ctx.db);
        }
    }
    if (selection.hostinger) {
        if (selection.dashboard) {
            try collector_hostinger.collectDashboard(ctx.io, ctx.gpa, ctx.hostinger_token, ctx.db);
        } else {
            try collector_hostinger.collectAll(ctx.io, ctx.gpa, ctx.hostinger_token, ctx.domains, ctx.db);
        }
    }
    if (selection.caddy) try collector_caddy.collect(ctx.io, ctx.gpa, ctx.caddy_paths, ctx.db);
    if (selection.system) try collector_system.collect(ctx.io, ctx.gpa, ctx.db);
    if (selection.projects) try collector_projects.collect(ctx.io, ctx.gpa, ctx.projects_root, ctx.db);
    try ctx.db.insertAudit("refresh", "ok", "read-only refresh complete");
    try writeRefreshLog(ctx, selection, start_snapshot_id);
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
