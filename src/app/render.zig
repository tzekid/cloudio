const std = @import("std");
const core_json = @import("core_json");
const db_store = @import("db_store");

pub const SnapshotJsonOptions = struct {
    include_id: bool = false,
};

pub const SnapshotListJsonOptions = struct {
    include_id: bool = false,
    trailing_newline: bool = false,
};

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

pub fn writeNameValueRows(rows: []const db_store.NameValueRow, writer: anytype) !void {
    for (rows) |row| try writer.print("{s}\t{s}\n", .{ row.name, row.value });
}

pub fn writeArrowNameValueRows(rows: []const db_store.NameValueRow, writer: anytype) !void {
    for (rows) |row| try writer.print("{s} -> {s}\n", .{ row.name, row.value });
}

pub fn writeMetricRows(rows: []const db_store.MetricRow, writer: anytype) !void {
    for (rows) |row| try writer.print("{s}\t{s}\t{s}\t{s}\n", .{ row.metric, row.value, row.unit, row.captured_at });
}

pub fn writeSnapshotRows(rows: []const db_store.SnapshotSummary, writer: anytype) !void {
    for (rows) |row| {
        try writer.print("{s} {s} [{s}] {s} {s}\n", .{
            row.kind,
            row.target,
            row.status,
            row.summary,
            row.captured_at,
        });
    }
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

pub fn writeSnapshotArrayJson(writer: anytype, snapshots: []const db_store.SnapshotSummary, options: SnapshotJsonOptions) !void {
    try writer.writeByte('[');
    for (snapshots, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writeSnapshotJson(writer, row, options);
    }
    try writer.writeByte(']');
}

pub fn writeSnapshotsJsonObject(writer: anytype, snapshots: []const db_store.SnapshotSummary, options: SnapshotListJsonOptions) !void {
    try writer.writeAll("{\"snapshots\":");
    try writeSnapshotArrayJson(writer, snapshots, .{ .include_id = options.include_id });
    try writer.writeByte('}');
    if (options.trailing_newline) try writer.writeByte('\n');
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

test "app render helpers write common database rows" {
    var name = [_]u8{ 's', 'v', 'c' };
    var value = [_]u8{ 'o', 'k' };
    const name_rows = [_]db_store.NameValueRow{.{ .name = name[0..], .value = value[0..] }};

    var metric = [_]u8{ 'l', 'o', 'a', 'd' };
    var metric_value = [_]u8{ '0', '.', '1', '2' };
    var unit = [_]u8{};
    var captured_at = [_]u8{ '2', '0', '2', '6' };
    const metric_rows = [_]db_store.MetricRow{.{ .metric = metric[0..], .value = metric_value[0..], .unit = unit[0..], .captured_at = captured_at[0..] }};

    var source = [_]u8{ 's', 'y', 's', 't', 'e', 'm' };
    var kind = [_]u8{ 'u', 'p', 't', 'i', 'm', 'e' };
    var target = [_]u8{};
    var status = [_]u8{ 'o', 'k' };
    var summary = [_]u8{ 'u', 'p' };
    var snapshot_at = [_]u8{ 'n', 'o', 'w' };
    const snapshots = [_]db_store.SnapshotSummary{.{
        .id = 7,
        .source = source[0..],
        .kind = kind[0..],
        .target = target[0..],
        .status = status[0..],
        .summary = summary[0..],
        .captured_at = snapshot_at[0..],
    }};

    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeNameValueRows(name_rows[0..], &out.writer);
    try writeArrowNameValueRows(name_rows[0..], &out.writer);
    try writeMetricRows(metric_rows[0..], &out.writer);
    try writeSnapshotRows(snapshots[0..], &out.writer);
    try writeSnapshotsJsonObject(&out.writer, snapshots[0..], .{ .include_id = true, .trailing_newline = true });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "svc\tok\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "svc -> ok\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "load\t0.12\t\t2026\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "uptime  [ok] up now\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"snapshots\":[{\"id\":7,\"source\":\"system\"") != null);
}
