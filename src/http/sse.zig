const std = @import("std");

pub const Stream = struct {
    out: *std.Io.Writer,

    pub fn begin(out: *std.Io.Writer) !Stream {
        try out.writeAll("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n");
        try out.flush();
        return .{ .out = out };
    }

    pub fn writeEvent(self: Stream, event_name: ?[]const u8, payload: []const u8) !void {
        if (event_name) |name| try self.out.print("event: {s}\n", .{name});
        try self.out.print("data: {s}\n\n", .{payload});
        try self.out.flush();
    }
};
