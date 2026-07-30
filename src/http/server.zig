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
    var address = try std.Io.net.IpAddress.parse(host, port);
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);
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
