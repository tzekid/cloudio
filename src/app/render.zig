const std = @import("std");
const core_json = @import("../core/json.zig");
const db_store = @import("../db/store.zig");

pub fn writeJsonStringField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeStringField(writer, name, value, trailing_comma);
}

pub fn writeJsonIntField(writer: anytype, name: []const u8, value: anytype, trailing_comma: bool) !void {
    try core_json.writeIntField(writer, name, value, trailing_comma);
}

pub fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try core_json.writeBoolField(writer, name, value, trailing_comma);
}

pub fn writeJsonNullableStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try core_json.writeNullableStringField(writer, name, value, trailing_comma);
}

pub fn writeJsonStringArray(writer: anytype, values: []const []const u8) !void {
    try core_json.writeStringArray(writer, values);
}

pub fn writeTextField(writer: anytype, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try writer.print("\t{s}={s}", .{ label, value });
}

pub fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

