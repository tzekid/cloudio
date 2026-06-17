const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn writeAll(io: Io, text: []const u8) !void {
    try Io.File.writeStreamingAll(Io.File.stdout(), io, text);
}

pub fn writeLine(io: Io, text: []const u8) !void {
    try writeAll(io, text);
    try writeAll(io, "\n");
}

pub fn printOutput(io: Io, gpa: Allocator, output: anytype) !void {
    defer output.deinit(gpa);
    if (output.text) |text| try writeLine(io, text);
}

pub fn printOwned(io: Io, gpa: Allocator, out: *std.Io.Writer.Allocating) !void {
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    try writeAll(io, text);
}
