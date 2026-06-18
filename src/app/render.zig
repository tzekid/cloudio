const std = @import("std");
const core_json = @import("core_json");

pub fn writeJsonStringField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeJsonIntField(writer: anytype, name: []const u8, value: anytype, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
    if (trailing_comma) try writer.writeByte(',');
}

pub fn writeTextField(writer: anytype, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try writer.print("\t{s}={s}", .{ label, value });
}

pub fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

test "app render helpers write strings integers and optional text fields" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    try out.writer.writeByte('{');
    try writeJsonStringField(&out.writer, "name", "quote \" and\nnewline", true);
    try writeJsonIntField(&out.writer, "count", @as(i64, 42), false);
    try out.writer.writeByte('}');
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expectEqualStrings("{\"name\":\"quote \\\" and\\nnewline\",\"count\":42}", json);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeTextField(&text_out.writer, "empty", "");
    try writeTextField(&text_out.writer, "name", "plosca.ru");
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expectEqualStrings("\tname=plosca.ru", text);

    try std.testing.expectEqual(@as(i64, 10), positiveLimit(10, 20));
    try std.testing.expectEqual(@as(i64, 20), positiveLimit(0, 20));
}
