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
    var server_ctx = ctx;
    server_ctx.dashboard = options.dashboard;
    server_ctx.trust_proxy_client_ip =
        std.mem.eql(u8, options.host, "127.0.0.1") or
        std.mem.eql(u8, options.host, "::1") or
        std.mem.eql(u8, options.host, "localhost");
    std.debug.print("cloudio serve http://{s}:{d}\n", .{ options.host, options.port });
    try http.server.run(Context, server_ctx, ctx.io, options.host, options.port, options.once, connection);
}

fn connection(ctx: Context, stream: std.Io.net.Stream) void {
    var db = db_store.Db.open(ctx.io, ctx.config.db_path) catch |err| {
        std.debug.print("cloudio serve db open failed: {s}\n", .{@errorName(err)});
        stream.close(ctx.io);
        return;
    };
    defer db.close();
    var thread_ctx = ctx;
    thread_ctx.db = &db;
    pipeline.handle(thread_ctx, stream) catch |err| {
        std.debug.print("cloudio serve request failed: {s}\n", .{@errorName(err)});
    };
}

test {
    _ = @import("auth.zig");
    _ = @import("routes.zig");
    _ = @import("handlers/authentication.zig");
}
