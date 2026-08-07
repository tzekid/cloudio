const std = @import("std");
const app_maintenance = @import("app_maintenance");
const app_refresh_cycle = @import("app_refresh_cycle");
const core_config = @import("core_config");
const db_store = @import("db_store");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    config: core_config.Config,
};

pub fn start(ctx: Context) !void {
    const thread = try std.Thread.spawn(.{}, run, .{ctx});
    thread.detach();
}

fn run(ctx: Context) void {
    var maintenance_elapsed_seconds: u64 = 0;
    while (true) {
        const seconds: u64 = @max(ctx.config.refresh_seconds, 30);
        ctx.io.sleep(.fromNanoseconds(seconds * std.time.ns_per_s), .awake) catch return;
        maintenance_elapsed_seconds +|= seconds;
        var db = db_store.Db.open(ctx.io, ctx.config.db_path) catch |err| {
            std.debug.print("cloudio scheduler db open failed: {s}\n", .{@errorName(err)});
            continue;
        };
        defer db.close();
        _ = app_refresh_cycle.run(.{ .io = ctx.io, .gpa = ctx.gpa, .db = &db, .config = ctx.config }) catch |err| {
            std.debug.print("cloudio scheduled refresh failed: {s}\n", .{@errorName(err)});
            continue;
        };
        if (!ctx.config.storage_auto_prune) continue;
        const interval_seconds: u64 = @as(u64, ctx.config.maintenance_interval_hours) * 60 * 60;
        if (maintenance_elapsed_seconds < interval_seconds) continue;
        app_maintenance.pruneScheduled(.{ .io = ctx.io, .gpa = ctx.gpa, .db = &db }, app_maintenance.Policy.fromConfig(ctx.config)) catch |err| {
            std.debug.print("cloudio scheduled maintenance failed: {s}\n", .{@errorName(err)});
            continue;
        };
        maintenance_elapsed_seconds = 0;
    }
}
