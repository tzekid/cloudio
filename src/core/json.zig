const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn field(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

pub fn fieldString(value: std.json.Value, name: []const u8) ?[]const u8 {
    const v = field(value, name) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

pub fn fieldAnyString(gpa: Allocator, value: std.json.Value, name: []const u8) ?[]u8 {
    const v = field(value, name) orelse return null;
    return switch (v) {
        .string => |s| gpa.dupe(u8, s) catch null,
        .integer => |n| std.fmt.allocPrint(gpa, "{d}", .{n}) catch null,
        else => null,
    };
}

pub fn fieldBool(value: std.json.Value, name: []const u8) ?bool {
    const v = field(value, name) orelse return null;
    return switch (v) {
        .bool => |b| b,
        else => null,
    };
}

pub fn fieldInt(value: std.json.Value, name: []const u8) ?i64 {
    const v = field(value, name) orelse return null;
    return switch (v) {
        .integer => |n| n,
        else => null,
    };
}

pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => if (ch < 0x20)
                try writer.print("\\u00{x:0>2}", .{ch})
            else
                try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

test "writeString escapes every JSON control byte" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try writeString(&output.writer, "a\x00\x01\x08\x0c\n\rb");
    try std.testing.expectEqualStrings("\"a\\u0000\\u0001\\b\\f\\n\\rb\"", output.written());
}

pub fn writeStringField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    try writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeIntField(writer: anytype, name: []const u8, value: anytype, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeNullableStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    if (value) |text| {
        try writeString(writer, text);
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writeString(writer, value);
    }
    try writer.writeByte(']');
}

test "extracts fields and envelope arrays" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{
        \\  "result": [
        \\    {
        \\      "id": 1307809,
        \\      "name": "srv1307809.hstgr.cloud",
        \\      "paused": false,
        \\      "ttl": 1,
        \\      "ipv4": [{"address": "76.13.130.170"}]
        \\    }
        \\  ]
        \\}
    , .{});
    defer parsed.deinit();

    const item = field(parsed.value, "result").?.array.items[0];
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", fieldString(item, "name") orelse "");
    try std.testing.expectEqual(false, fieldBool(item, "paused") orelse true);
    try std.testing.expectEqual(@as(i64, 1), fieldInt(item, "ttl") orelse -1);

    const id = fieldAnyString(allocator, item, "id") orelse return error.TestExpectedId;
    defer allocator.free(id);
    try std.testing.expectEqualStrings("1307809", id);
}

test "writes escaped json strings and fields" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeString(&out.writer, "quote \" and\nnewline");
    try out.writer.writeAll(" {");
    try writeStringField(&out.writer, "name", "plosca.ru", true);
    try writeIntField(&out.writer, "ttl", @as(i64, 1), true);
    try writeBoolField(&out.writer, "proxied", false, true);
    try writeNullableStringField(&out.writer, "maybe", null, false);
    try out.writer.writeByte('}');
    try std.testing.expectEqualStrings("\"quote \\\" and\\nnewline\" {\"name\":\"plosca.ru\",\"ttl\":1,\"proxied\":false,\"maybe\":null}", out.written());
}
