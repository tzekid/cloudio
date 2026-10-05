const std = @import("std");
const db_store = @import("../db/store.zig");
const http = @import("../http/root.zig");
const context = @import("context.zig");
const pipeline = @import("pipeline.zig");

pub const Context = context.Context;

pub const Options = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 9331,
};

pub fn listen(io: std.Io, options: Options) !std.Io.net.Server {
    return try http.server.listen(io, options.host, options.port);
}

pub fn serve(ctx: Context, options: Options, listener: *std.Io.net.Server) !void {
    var server_ctx = ctx;
    server_ctx.trust_proxy_client_ip =
        std.mem.eql(u8, options.host, "127.0.0.1") or
        std.mem.eql(u8, options.host, "::1") or
        std.mem.eql(u8, options.host, "localhost");
    std.debug.print("cloudio serve http://{s}:{d}\n", .{ options.host, options.port });
    try http.server.serve(Context, server_ctx, ctx.io, listener, connection);
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
    _ = @import("api.zig");
    _ = @import("auth.zig");
    _ = @import("forms.zig");
}
