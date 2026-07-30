const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn resultArray(value: std.json.Value) ?std.json.Array {
    if (value != .object) return null;
    const result = value.object.get("result") orelse return null;
    if (result != .array) return null;
    return result.array;
}

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

pub fn firstAddress(value: std.json.Value, name: []const u8) ?[]const u8 {
    const address_field = field(value, name) orelse return null;
    return switch (address_field) {
        .array => |array| {
            for (array.items) |item| {
                if (fieldString(item, "address")) |address| return address;
                if (fieldString(item, "ip")) |ip| return ip;
            }
            return null;
        },
        .object => fieldString(address_field, "address") orelse fieldString(address_field, "ip"),
        else => null,
    };
}

pub fn stringifyValue(gpa: Allocator, value: std.json.Value) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
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

pub fn writeCountField(writer: anytype, name: []const u8, value: usize, trailing_comma: bool) !void {
    try writeIntField(writer, name, value, trailing_comma);
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

pub fn writeNullableCountField(writer: anytype, name: []const u8, value: ?usize, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    if (value) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeNullableBoolField(writer: anytype, name: []const u8, value: ?bool, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    if (value) |flag| {
        try writer.writeAll(if (flag) "true" else "false");
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

pub fn writeStringArrayField(writer: anytype, name: []const u8, values: []const []const u8, trailing_comma: bool) !void {
    try writeString(writer, name);
    try writer.writeByte(':');
    try writeStringArray(writer, values);
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeMaybeComma(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(',');
    }
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

    const items = resultArray(parsed.value) orelse return error.TestExpectedResultArray;
    try std.testing.expectEqual(@as(usize, 1), items.items.len);
    const item = items.items[0];
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", fieldString(item, "name") orelse "");
    try std.testing.expectEqual(false, fieldBool(item, "paused") orelse true);
    try std.testing.expectEqual(@as(i64, 1), fieldInt(item, "ttl") orelse -1);
    try std.testing.expectEqualStrings("76.13.130.170", firstAddress(item, "ipv4") orelse "");

    const id = fieldAnyString(allocator, item, "id") orelse return error.TestExpectedId;
    defer allocator.free(id);
    try std.testing.expectEqualStrings("1307809", id);
}

test "stringifies json values" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"name":"plosca.ru","proxied":true}
    , .{});
    defer parsed.deinit();

    const text = try stringifyValue(allocator, parsed.value);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"plosca.ru\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"proxied\":true") != null);
}

test "writes escaped json strings and fields" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeString(&out.writer, "quote \" and\nnewline");
    try out.writer.writeByte(' ');
    try out.writer.writeByte('{');
    try writeStringField(&out.writer, "name", "plosca.ru", true);
    try writeIntField(&out.writer, "ttl", @as(i64, 1), true);
    try writeCountField(&out.writer, "count", @as(usize, 2), true);
    try writeBoolField(&out.writer, "proxied", false, true);
    try writeNullableStringField(&out.writer, "maybe", null, true);
    try writeNullableCountField(&out.writer, "maybe_count", @as(?usize, 3), true);
    try writeNullableBoolField(&out.writer, "maybe_bool", @as(?bool, true), true);
    const values = [_][]const u8{ "A", "AAAA" };
    try writeStringArrayField(&out.writer, "types", values[0..], false);
    try out.writer.writeByte('}');
    var first = true;
    try out.writer.writeByte(' ');
    try writeMaybeComma(&out.writer, &first);
    try out.writer.writeAll("a");
    try writeMaybeComma(&out.writer, &first);
    try out.writer.writeAll("b");
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\"quote \\\" and\\nnewline\" {\"name\":\"plosca.ru\",\"ttl\":1,\"count\":2,\"proxied\":false,\"maybe\":null,\"maybe_count\":3,\"maybe_bool\":true,\"types\":[\"A\",\"AAAA\"]} a,b", text);
}
