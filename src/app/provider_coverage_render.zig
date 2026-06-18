const std = @import("std");
const core_json = @import("core_json");

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

pub fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonCountField(writer: anytype, name: []const u8, value: usize, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.print(":{d}", .{value});
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonNullableCountField(writer: anytype, name: []const u8, value: ?usize, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonNullableStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |text| {
        try core_json.writeString(writer, text);
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonNullableBoolField(writer: anytype, name: []const u8, value: ?bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |flag| {
        try writer.writeAll(if (flag) "true" else "false");
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonStringArray(writer: anytype, values: anytype) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try core_json.writeString(writer, value);
    }
    try writer.writeByte(']');
}

pub fn writeMaybeJsonComma(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(',');
    }
}

pub fn writeShellArg(writer: anytype, value: []const u8) !void {
    try writer.writeByte('\'');
    for (value) |c| {
        if (c == '\'') {
            try writer.writeAll("'\\''");
        } else {
            try writer.writeByte(c);
        }
    }
    try writer.writeByte('\'');
}

test "writes shared json and shell-safe fields" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeJsonField(&out.writer, "name", "value", true);
    try writeJsonNullableCountField(&out.writer, "count", null, true);
    try writeJsonNullableBoolField(&out.writer, "flag", true, true);
    const values = [_][]const u8{ "a", "b" };
    try writeJsonStringArray(&out.writer, values[0..]);
    try out.writer.writeByte(' ');
    try writeShellArg(&out.writer, "it's");
    const text = try out.toOwnedSlice();
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("\"name\":\"value\",\"count\":null,\"flag\":true,[\"a\",\"b\"] 'it'\\''s'", text);
    try std.testing.expect(containsIgnoreCase("Cloudflare DNS", "dns"));
    try std.testing.expect(eqlIgnoreCase("Hostinger", "hostinger"));
}
