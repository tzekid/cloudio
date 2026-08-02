const std = @import("std");
const app_nob_worker = @import("app_nob_worker");
const core_config = @import("core_config");
const core_time = @import("core_time");
const core_version = @import("core_version");
const db_store = @import("db_store");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    config: core_config.Config,
};

pub fn start(ctx: Context) !void {
    if (!ctx.config.nob_enabled) return;
    try recover(ctx);
    var index: u16 = 0;
    while (index < ctx.config.nob_worker_count) : (index += 1) {
        const thread = try std.Thread.spawn(.{}, run, .{ctx});
        thread.detach();
    }
}

fn recover(ctx: Context) !void {
    var db = try db_store.Db.open(ctx.io, ctx.config.db_path);
    defer db.close();
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    const recovered = try db.nob().recoverStaleRuns(now, now);
    if (recovered != 0) {
        const detail = try std.fmt.allocPrint(ctx.gpa, "interrupted={d}", .{recovered});
        defer ctx.gpa.free(detail);
        try db.insertAudit("nob.worker.recover", "ok", detail);
    }
}

fn run(ctx: Context) void {
    var db = db_store.Db.open(ctx.io, ctx.config.db_path) catch |err| {
        std.debug.print("cloudio nob worker db open failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer db.close();
    const worker_context: app_nob_worker.Context = .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = &db,
        .config = ctx.config,
        .cloudio_version = core_version.value,
    };
    while (true) {
        const worked = app_nob_worker.processNext(worker_context) catch |err| {
            std.debug.print("cloudio nob worker cycle failed: {s}\n", .{@errorName(err)});
            ctx.io.sleep(.fromSeconds(1), .awake) catch return;
            continue;
        };
        if (!worked) ctx.io.sleep(.fromMilliseconds(250), .awake) catch return;
    }
}

test "disabled worker pool starts no threads" {
    try start(.{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .config = .{ .domains = &.{}, .nob_enabled = false },
    });
}
