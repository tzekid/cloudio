const std = @import("std");

/// Percent-encodes everything except RFC 3986 unreserved characters, so the
/// value is safe in a path segment or a query component.
pub fn writeComponent(out: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_' or byte == '~') {
            try out.writeByte(byte);
        } else {
            try out.writeAll(&.{ '%', hex[byte >> 4], hex[byte & 0x0f] });
        }
    }
}

pub fn component(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    try writeComponent(&out.writer, value);
    return out.toOwnedSlice();
}

test "component encoding keeps unreserved characters only" {
    const encoded = try component(std.testing.allocator, "vm 1/a~b");
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("vm%201%2Fa~b", encoded);
}
