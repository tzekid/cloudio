const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn printOutput(gpa: Allocator, output: anytype) void {
    defer output.deinit(gpa);
    if (output.text) |text| std.debug.print("{s}\n", .{text});
}
