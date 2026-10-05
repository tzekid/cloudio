const std = @import("std");
const builtin = @import("builtin");

pub const max_active_connections: usize = 64;
pub const socket_timeout_seconds: isize = 30;
var active_connections: std.atomic.Value(usize) = .init(0);

pub fn listen(io: std.Io, host: []const u8, port: u16) !std.Io.net.Server {
    var address = try std.Io.net.IpAddress.parse(host, port);
    return try address.listen(io, .{ .reuse_address = true });
}

/// Owns the accept and connection lifecycle; `handle` serves one stream on
/// its own thread, bounded by `max_active_connections`.
pub fn serve(
    comptime Context: type,
    ctx: Context,
    io: std.Io,
    listener: *std.Io.net.Server,
    comptime handle: anytype,
) !void {
    while (true) {
        const stream = try listener.accept(io);
        configureSocketTimeout(stream) catch {
            stream.close(io);
            continue;
        };
        if (!tryAcquireConnection()) {
            stream.close(io);
            continue;
        }
        const thread = std.Thread.spawn(.{}, connectionThread, .{ Context, ctx, stream, handle }) catch |err| {
            releaseConnection();
            std.debug.print("http connection thread spawn failed: {s}\n", .{@errorName(err)});
            stream.close(io);
            continue;
        };
        thread.detach();
    }
}

fn connectionThread(comptime Context: type, ctx: Context, stream: std.Io.net.Stream, comptime handle: anytype) void {
    defer releaseConnection();
    handle(ctx, stream);
}

fn tryAcquireConnection() bool {
    const previous = active_connections.fetchAdd(1, .monotonic);
    if (previous < max_active_connections) return true;
    _ = active_connections.fetchSub(1, .monotonic);
    return false;
}

fn releaseConnection() void {
    _ = active_connections.fetchSub(1, .monotonic);
}

fn configureSocketTimeout(stream: std.Io.net.Stream) !void {
    if (comptime builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        const timeout: std.posix.timeval = .{ .sec = socket_timeout_seconds, .usec = 0 };
        const bytes = std.mem.asBytes(&timeout);
        try std.posix.setsockopt(stream.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, bytes);
        try std.posix.setsockopt(stream.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, bytes);
    }
}
