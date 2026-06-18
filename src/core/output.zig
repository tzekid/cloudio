const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Output = struct {
    text: ?[]u8 = null,

    pub fn deinit(self: Output, allocator: Allocator) void {
        if (self.text) |value| allocator.free(value);
    }
};

pub fn text(allocator: Allocator, value: []const u8) !Output {
    return .{ .text = try allocator.dupe(u8, value) };
}

pub fn maybeText(allocator: Allocator, enabled: bool, value: []const u8) !Output {
    if (!enabled) return .{};
    return try text(allocator, value);
}

test "output owns optional text" {
    const allocator = std.testing.allocator;
    const out = try text(allocator, "ok");
    defer out.deinit(allocator);
    try std.testing.expectEqualStrings("ok", out.text.?);
}
