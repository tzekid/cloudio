const std = @import("std");

pub const Stream = struct {
    out: *std.Io.Writer,

    pub fn begin(out: *std.Io.Writer) !Stream {
        return beginWithHeaders(out, "");
    }

    pub fn beginWithHeaders(out: *std.Io.Writer, extra_headers: []const u8) !Stream {
        try out.print(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n{s}Connection: close\r\n\r\n",
            .{extra_headers},
        );
        try out.flush();
        return .{ .out = out };
    }

    pub fn writeEvent(self: Stream, event_name: ?[]const u8, payload: []const u8) !void {
        if (event_name) |name| try self.out.print("event: {s}\n", .{name});
        try self.out.print("data: {s}\n\n", .{payload});
        try self.out.flush();
    }
};
