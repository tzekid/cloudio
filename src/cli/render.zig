const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const RenderFormat = enum {
    text,
    json,
};

pub fn parseFormat(value: []const u8) ?RenderFormat {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "json")) return .json;
    return null;
}

pub fn parseFormatStrict(value: []const u8) !RenderFormat {
    return parseFormat(value) orelse error.InvalidFormat;
}

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

test "render format parser accepts text and json" {
    try std.testing.expectEqual(RenderFormat.text, parseFormat("text").?);
    try std.testing.expectEqual(RenderFormat.json, parseFormat("json").?);
    try std.testing.expect(parseFormat("yaml") == null);
    try std.testing.expectError(error.InvalidFormat, parseFormatStrict("yaml"));
}
