const std = @import("std");
const core_json = @import("core_json");
const db_store = @import("db_store");

pub const SnapshotJsonOptions = struct {
    include_id: bool = false,
};

pub const AuditEventJsonOptions = struct {
    include_id: bool = false,
};

pub fn writeJsonStringField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeStringField(writer, name, value, trailing_comma);
}

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
    try core_json.writeString(writer, value);
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

pub fn writeSnapshotJson(writer: anytype, row: db_store.SnapshotSummary, options: SnapshotJsonOptions) !void {
    try writer.writeByte('{');
    if (options.include_id) {
        try writeJsonIntField(writer, "id", row.id, true);
    }
    try writeJsonStringField(writer, "source", row.source, true);
    try writeJsonStringField(writer, "kind", row.kind, true);
    try writeJsonStringField(writer, "target", row.target, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "summary", row.summary, true);
    try writeJsonStringField(writer, "captured_at", row.captured_at, false);
    try writer.writeByte('}');
}

pub fn writeAuditEventJson(writer: anytype, row: db_store.AuditEvent, options: AuditEventJsonOptions) !void {
    try writer.writeByte('{');
    if (options.include_id) {
        try writeJsonIntField(writer, "id", row.id, true);
    }
    try writeJsonStringField(writer, "action", row.action, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "detail", row.detail, true);
    try writeJsonStringField(writer, "created_at", row.created_at, false);
    try writer.writeByte('}');
}

pub fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

