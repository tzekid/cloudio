const std = @import("std");
const app_dashboard = @import("app_dashboard");
const db_store = @import("db_store");
const http = @import("http");
const context = @import("context.zig");
const pipeline = @import("pipeline.zig");

pub const default_host = "127.0.0.1";
pub const default_port: u16 = 9328;
pub const Context = context.Context;

pub const Options = struct {
    host: []const u8 = default_host,
    port: u16 = default_port,
    once: bool = false,
    dashboard: app_dashboard.Options = .{},
};

pub fn run(ctx: Context, options: Options) !void {
    var listener = try listen(ctx.io, options);
    defer listener.deinit(ctx.io);
    try runPrepared(ctx, options, &listener);
}

pub fn listen(io: std.Io, options: Options) !std.Io.net.Server {
    return try http.server.listen(io, options.host, options.port);
}

pub fn runPrepared(ctx: Context, options: Options, listener: *std.Io.net.Server) !void {
    var server_ctx = ctx;
    server_ctx.dashboard = options.dashboard;
    server_ctx.trust_proxy_client_ip =
        std.mem.eql(u8, options.host, "127.0.0.1") or
        std.mem.eql(u8, options.host, "::1") or
        std.mem.eql(u8, options.host, "localhost");
    std.debug.print("cloudio serve http://{s}:{d}\n", .{ options.host, options.port });
    try http.server.runPrepared(Context, server_ctx, ctx.io, listener, options.once, connection);
}

/// A small pool of long-lived handles for the request path. Opening a new
/// SQLite handle per connection paid page-cache warmup and schema parsing on
/// every request; with WAL these handles read concurrently.
const HandlePool = struct {
    const size = 8;
    var slots: [size]?db_store.Db = @splat(null);
    var used: [size]bool = @splat(false);
    var mutex: std.atomic.Mutex = .unlocked;

    fn acquire(ctx: Context) ?struct { db: *db_store.Db, index: usize } {
        while (!mutex.tryLock()) std.atomic.spinLoopHint();
        defer mutex.unlock();
        for (&slots, &used, 0..) |*slot, *slot_used, index| {
            if (slot_used.*) continue;
            if (slot.* == null) {
                slot.* = db_store.Db.open(ctx.io, ctx.config.db_path) catch return null;
            }
            slot_used.* = true;
            return .{ .db = &slot.*.?, .index = index };
        }
        return null;
    }

    fn release(index: usize) void {
        while (!mutex.tryLock()) std.atomic.spinLoopHint();
        defer mutex.unlock();
        used[index] = false;
    }
};

fn connection(ctx: Context, stream: std.Io.net.Stream) void {
    const pooled = HandlePool.acquire(ctx);
    var fresh: ?db_store.Db = null;
    const db: *db_store.Db = if (pooled) |entry| entry.db else blk: {
        // Pool exhausted (more concurrent connections than slots): fall back
        // to a per-connection handle rather than queueing behind the pool.
        fresh = db_store.Db.open(ctx.io, ctx.config.db_path) catch |err| {
            std.debug.print("cloudio serve db open failed: {s}\n", .{@errorName(err)});
            stream.close(ctx.io);
            return;
        };
        break :blk &fresh.?;
    };
    defer if (pooled) |entry| HandlePool.release(entry.index) else if (fresh) |*handle| handle.close();
    var thread_ctx = ctx;
    thread_ctx.db = db;
    pipeline.handle(thread_ctx, stream) catch |err| {
        std.debug.print("cloudio serve request failed: {s}\n", .{@errorName(err)});
    };
}

test {
    _ = @import("auth.zig");
    _ = @import("routes.zig");
    _ = @import("handlers/authentication.zig");
}
