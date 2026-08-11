const std = @import("std");

/// Owns the socket accept/connection lifecycle while leaving application
/// request handling to a caller-provided callback.
pub fn run(
    comptime Context: type,
    ctx: Context,
    io: std.Io,
    host: []const u8,
    port: u16,
    once: bool,
    comptime handle: anytype,
) !void {
    var listener = try listen(io, host, port);
    defer listener.deinit(io);
    try runPrepared(Context, ctx, io, &listener, once, handle);
}

pub fn listen(io: std.Io, host: []const u8, port: u16) !std.Io.net.Server {
    var address = try std.Io.net.IpAddress.parse(host, port);
    return try address.listen(io, .{ .reuse_address = true });
}

pub fn runPrepared(
    comptime Context: type,
    ctx: Context,
    io: std.Io,
    listener: *std.Io.net.Server,
    once: bool,
    comptime handle: anytype,
) !void {
    while (true) {
        const stream = try listener.accept(io);
        if (once) {
            handle(ctx, stream);
            return;
        }
        const thread = std.Thread.spawn(.{}, handle, .{ ctx, stream }) catch |err| {
            std.debug.print("http connection thread spawn failed: {s}\n", .{@errorName(err)});
            stream.close(io);
            continue;
        };
        thread.detach();
    }
}
