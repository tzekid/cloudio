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

pub const FormatArg = union(enum) {
    no_match,
    matched: RenderFormat,
    missing_value,
    invalid_value: []const u8,
};

pub fn parseFormatArg(args: []const []const u8, index: *usize) FormatArg {
    const arg = args[index.*];
    if (std.mem.eql(u8, arg, "--json")) return .{ .matched = .json };
    if (std.mem.eql(u8, arg, "--format")) {
        index.* += 1;
        if (index.* >= args.len) return .missing_value;
        const value = args[index.*];
        return .{ .matched = parseFormat(value) orelse return .{ .invalid_value = value } };
    }
    if (std.mem.startsWith(u8, arg, "--format=")) {
        const value = arg["--format=".len..];
        return .{ .matched = parseFormat(value) orelse return .{ .invalid_value = value } };
    }
    return .no_match;
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

pub fn renderToOwned(gpa: Allocator, comptime render: anytype, args: anytype) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    try @call(.auto, render, args ++ .{&out.writer});
    return try out.toOwnedSlice();
}

pub fn printRendered(io: Io, gpa: Allocator, comptime render: anytype, args: anytype) !void {
    const text = try renderToOwned(gpa, render, args);
    defer gpa.free(text);
    try writeAll(io, text);
}

pub fn printFormatted(
    io: Io,
    gpa: Allocator,
    format: RenderFormat,
    comptime render_text: anytype,
    comptime render_json: anytype,
    args: anytype,
) !void {
    switch (format) {
        .text => try printRendered(io, gpa, render_text, args),
        .json => try printRendered(io, gpa, render_json, args),
    }
}

test "render format parser accepts text and json" {
    try std.testing.expectEqual(RenderFormat.text, parseFormat("text").?);
    try std.testing.expectEqual(RenderFormat.json, parseFormat("json").?);
    try std.testing.expect(parseFormat("yaml") == null);
    try std.testing.expectError(error.InvalidFormat, parseFormatStrict("yaml"));
}

test "format argument parser handles flags and values" {
    var index: usize = 0;
    const json_args = [_][]const u8{"--json"};
    try std.testing.expectEqual(RenderFormat.json, parseFormatArg(json_args[0..], &index).matched);
    try std.testing.expectEqual(@as(usize, 0), index);

    index = 0;
    const value_args = [_][]const u8{ "--format", "json" };
    try std.testing.expectEqual(RenderFormat.json, parseFormatArg(value_args[0..], &index).matched);
    try std.testing.expectEqual(@as(usize, 1), index);

    index = 0;
    const inline_args = [_][]const u8{"--format=text"};
    try std.testing.expectEqual(RenderFormat.text, parseFormatArg(inline_args[0..], &index).matched);
    try std.testing.expectEqual(@as(usize, 0), index);

    index = 0;
    const missing_args = [_][]const u8{"--format"};
    try std.testing.expectEqual(FormatArg.missing_value, parseFormatArg(missing_args[0..], &index));

    index = 0;
    const invalid_args = [_][]const u8{ "--format", "yaml" };
    switch (parseFormatArg(invalid_args[0..], &index)) {
        .invalid_value => |value| try std.testing.expectEqualStrings("yaml", value),
        else => return error.ExpectedInvalidFormatValue,
    }

    index = 0;
    const other_args = [_][]const u8{"cloudflare"};
    try std.testing.expectEqual(FormatArg.no_match, parseFormatArg(other_args[0..], &index));
    try std.testing.expectEqual(@as(usize, 0), index);
}

fn writeFixture(label: []const u8, suffix: []const u8, writer: anytype) !void {
    try writer.writeAll(label);
    try writer.writeAll(":");
    try writer.writeAll(suffix);
}

fn writeFixtureText(label: []const u8, writer: anytype) !void {
    try writeFixture(label, "text", writer);
}

fn writeFixtureJson(label: []const u8, writer: anytype) !void {
    try writeFixture(label, "json", writer);
}

test "render helpers own allocating writer lifecycle" {
    const allocator = std.testing.allocator;

    const text = try renderToOwned(allocator, writeFixtureText, .{"example"});
    defer allocator.free(text);
    try std.testing.expectEqualStrings("example:text", text);

    const json = try renderToOwned(allocator, writeFixtureJson, .{"example"});
    defer allocator.free(json);
    try std.testing.expectEqualStrings("example:json", json);
}
