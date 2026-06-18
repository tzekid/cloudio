pub const value = "0.1.0-poc";

test "version is non-empty" {
    const std = @import("std");
    try std.testing.expect(value.len > 0);
}
