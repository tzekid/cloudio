const std = @import("std");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;

pub const PageInfo = struct {
    envelope: Envelope,
    current_page: usize,
    per_page: usize,
    total: usize,
    data_len: usize,
    total_pages: ?usize = null,

    pub fn hasNext(self: PageInfo) bool {
        if (self.total_pages) |total_pages| return self.current_page < total_pages;
        return self.data_len > 0 and self.per_page > 0 and self.current_page * self.per_page < self.total;
    }
};

pub const Envelope = enum {
    data_meta,
    result_info,
    cursor_result_info,
    cursor_root,

    pub fn name(self: Envelope) []const u8 {
        return switch (self) {
            .data_meta => "data_meta",
            .result_info => "result_info",
            .cursor_result_info => "cursor_result_info",
            .cursor_root => "cursor_root",
        };
    }
};

pub const CursorInfo = struct {
    envelope: Envelope,
    data_len: usize,
    next_cursor: ?[]u8,
    complete: ?bool = null,
    is_truncated: ?bool = null,

    pub fn deinit(self: CursorInfo, gpa: Allocator) void {
        if (self.next_cursor) |cursor| gpa.free(cursor);
    }

    pub fn hasNext(self: CursorInfo) bool {
        const cursor = self.next_cursor orelse return false;
        if (cursor.len == 0) return false;
        if (self.complete) |complete| return !complete;
        if (self.is_truncated) |is_truncated| return is_truncated;
        return true;
    }
};

pub fn pageInfo(body: []const u8) ?PageInfo {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch return null;
    defer parsed.deinit();
    return pageInfoFromValue(parsed.value);
}

pub fn pageInfoFromValue(value: std.json.Value) ?PageInfo {
    return dataPageInfoFromValue(value) orelse resultInfoPageInfoFromValue(value);
}

pub fn cursorInfo(gpa: Allocator, body: []const u8) !?CursorInfo {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    return try cursorInfoFromValue(gpa, parsed.value);
}

pub fn cursorInfoFromValue(gpa: Allocator, value: std.json.Value) !?CursorInfo {
    if (try resultInfoCursorInfoFromValue(gpa, value)) |info| return info;
    if (try rootCursorInfoFromValue(gpa, value, .cursor_root)) |info| return info;
    if (core_json.field(value, "result")) |result| {
        if (result == .object) return try rootCursorInfoFromValue(gpa, result, .cursor_root);
    }
    return null;
}

pub fn dataPageInfo(body: []const u8) ?PageInfo {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch return null;
    defer parsed.deinit();
    return dataPageInfoFromValue(parsed.value);
}

pub fn mergeDataPages(gpa: Allocator, bodies: []const []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();

    try out.writer.writeAll("{\"data\":[");
    var first = true;
    var last_info: ?PageInfo = null;
    var page_count: usize = 0;
    for (bodies) |body| {
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch continue;
        defer parsed.deinit();
        const data = core_json.field(parsed.value, "data") orelse continue;
        if (data != .array) continue;
        page_count += 1;
        if (dataPageInfoFromValue(parsed.value)) |info| last_info = info;
        for (data.array.items) |item| {
            if (!first) try out.writer.writeByte(',');
            first = false;
            try std.json.Stringify.value(item, .{}, &out.writer);
        }
    }
    try out.writer.writeAll("],\"meta\":");
    if (last_info) |info| {
        try out.writer.print("{{\"current_page\":{d},\"per_page\":{d},\"total\":{d},\"pages\":{d}}}", .{ info.current_page, info.per_page, info.total, page_count });
    } else {
        try out.writer.print("{{\"current_page\":0,\"per_page\":0,\"total\":0,\"pages\":{d}}}", .{page_count});
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

pub fn dataPageInfoFromValue(value: std.json.Value) ?PageInfo {
    const data = core_json.field(value, "data") orelse return null;
    if (data != .array) return null;
    const meta = core_json.field(value, "meta") orelse return null;
    const current_page = positiveInt(meta, "current_page") orelse return null;
    const per_page = positiveInt(meta, "per_page") orelse return null;
    const total = positiveInt(meta, "total") orelse return null;
    return .{
        .envelope = .data_meta,
        .current_page = current_page,
        .per_page = per_page,
        .total = total,
        .data_len = data.array.items.len,
    };
}

pub fn resultInfoPageInfoFromValue(value: std.json.Value) ?PageInfo {
    const result = core_json.field(value, "result") orelse return null;
    if (result != .array) return null;
    const result_info = core_json.field(value, "result_info") orelse return null;
    const current_page = positiveInt(result_info, "page") orelse return null;
    const per_page = positiveInt(result_info, "per_page") orelse return null;
    const total = positiveInt(result_info, "total_count") orelse return null;
    const count = positiveInt(result_info, "count") orelse result.array.items.len;
    return .{
        .envelope = .result_info,
        .current_page = current_page,
        .per_page = per_page,
        .total = total,
        .data_len = count,
        .total_pages = positiveInt(result_info, "total_pages"),
    };
}

fn resultInfoCursorInfoFromValue(gpa: Allocator, value: std.json.Value) !?CursorInfo {
    const result_info = core_json.field(value, "result_info") orelse return null;
    const next_cursor = try cursorFromResultInfo(gpa, result_info);
    errdefer if (next_cursor) |cursor| gpa.free(cursor);
    if (next_cursor == null and core_json.field(result_info, "cursor") == null and core_json.field(result_info, "next") == null and core_json.field(result_info, "cursors") == null) return null;
    return .{
        .envelope = .cursor_result_info,
        .data_len = positiveAnyInt(result_info, "count") orelse dataLenFromResult(value) orelse 0,
        .next_cursor = next_cursor,
        .is_truncated = core_json.fieldBool(result_info, "is_truncated"),
    };
}

fn rootCursorInfoFromValue(gpa: Allocator, value: std.json.Value, envelope: Envelope) !?CursorInfo {
    const next_cursor = try cursorValueFromField(gpa, value, "cursor");
    errdefer if (next_cursor) |cursor| gpa.free(cursor);
    const has_cursor_shape = next_cursor != null or core_json.field(value, "cursor") != null or core_json.field(value, "list_complete") != null;
    if (!has_cursor_shape) return null;
    return .{
        .envelope = envelope,
        .data_len = dataLenFromCursorRoot(value) orelse 0,
        .next_cursor = next_cursor,
        .complete = core_json.fieldBool(value, "list_complete"),
        .is_truncated = core_json.fieldBool(value, "is_truncated"),
    };
}

fn cursorFromResultInfo(gpa: Allocator, result_info: std.json.Value) !?[]u8 {
    if (try cursorValueFromField(gpa, result_info, "cursor")) |cursor| return cursor;
    if (try cursorValueFromField(gpa, result_info, "next")) |cursor| return cursor;
    if (core_json.field(result_info, "cursors")) |cursors| {
        if (try cursorValueFromField(gpa, cursors, "after")) |cursor| return cursor;
    }
    return null;
}

fn cursorValueFromField(gpa: Allocator, value: std.json.Value, name: []const u8) !?[]u8 {
    const field_value = core_json.field(value, name) orelse return null;
    return try cursorValue(gpa, field_value);
}

fn cursorValue(gpa: Allocator, value: std.json.Value) !?[]u8 {
    return switch (value) {
        .string => |text| if (text.len == 0) null else try cursorText(gpa, text),
        .integer => |number| try std.fmt.allocPrint(gpa, "{d}", .{number}),
        else => null,
    };
}

fn cursorText(gpa: Allocator, text: []const u8) ![]u8 {
    const buffer = try gpa.dupe(u8, text);
    errdefer gpa.free(buffer);
    if (std.mem.indexOfScalar(u8, buffer, '%') == null) return buffer;
    const decoded = std.Uri.percentDecodeInPlace(buffer);
    if (decoded.len == buffer.len) return buffer;
    const owned = try gpa.dupe(u8, decoded);
    gpa.free(buffer);
    return owned;
}

fn dataLenFromResult(value: std.json.Value) ?usize {
    const result = core_json.field(value, "result") orelse return null;
    return dataLenFromCollectionValue(result);
}

fn dataLenFromCursorRoot(value: std.json.Value) ?usize {
    if (dataLenFromCollectionField(value, "keys")) |len| return len;
    if (dataLenFromCollectionField(value, "items")) |len| return len;
    if (dataLenFromCollectionField(value, "objects")) |len| return len;
    if (dataLenFromCollectionField(value, "vectors")) |len| return len;
    if (dataLenFromCollectionField(value, "data")) |len| return len;
    return null;
}

fn dataLenFromCollectionField(value: std.json.Value, name: []const u8) ?usize {
    const field_value = core_json.field(value, name) orelse return null;
    return dataLenFromCollectionValue(field_value);
}

fn dataLenFromCollectionValue(value: std.json.Value) ?usize {
    return switch (value) {
        .array => |array| array.items.len,
        .object => dataLenFromCursorRoot(value),
        else => null,
    };
}

fn positiveInt(value: std.json.Value, name: []const u8) ?usize {
    const int_value = core_json.fieldInt(value, name) orelse return null;
    if (int_value < 0) return null;
    return @intCast(int_value);
}

fn positiveAnyInt(value: std.json.Value, name: []const u8) ?usize {
    const field_value = core_json.field(value, name) orelse return null;
    return switch (field_value) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        .string => |text| std.fmt.parseInt(usize, text, 10) catch null,
        else => null,
    };
}

test "parses data pagination envelopes" {
    const info = dataPageInfo(
        \\{"data":[{"id": 1}, {"id": 2}], "meta": {"current_page": 1, "per_page": 2, "total": 5}}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expectEqual(Envelope.data_meta, info.envelope);
    try std.testing.expectEqual(@as(usize, 1), info.current_page);
    try std.testing.expectEqual(@as(usize, 2), info.per_page);
    try std.testing.expectEqual(@as(usize, 5), info.total);
    try std.testing.expectEqual(@as(usize, 2), info.data_len);
    try std.testing.expect(info.hasNext());

    const last = dataPageInfo(
        \\{"data":[{"id": 5}], "meta": {"current_page": 3, "per_page": 2, "total": 5}}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expect(!last.hasNext());
    try std.testing.expect(dataPageInfo("[{\"id\": 1}]") == null);
}

test "parses result_info pagination envelopes" {
    const info = pageInfo(
        \\{"result":[{"id": "one"}, {"id": "two"}], "result_info": {"page": 1, "per_page": 2, "total_pages": 3, "count": 2, "total_count": 5}, "success": true}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expectEqual(Envelope.result_info, info.envelope);
    try std.testing.expectEqual(@as(usize, 1), info.current_page);
    try std.testing.expectEqual(@as(usize, 2), info.per_page);
    try std.testing.expectEqual(@as(usize, 5), info.total);
    try std.testing.expectEqual(@as(usize, 2), info.data_len);
    try std.testing.expectEqual(@as(?usize, 3), info.total_pages);
    try std.testing.expect(info.hasNext());

    const last = pageInfo(
        \\{"result":[{"id": "five"}], "result_info": {"page": 3, "per_page": 2, "total_pages": 3, "count": 1, "total_count": 5}, "success": true}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expect(!last.hasNext());

    const fallback = pageInfo(
        \\{"result":[{"id": "five"}], "result_info": {"page": 3, "per_page": 2, "count": 1, "total_count": 5}, "success": true}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expect(!fallback.hasNext());
    try std.testing.expect(pageInfo("{\"result\":[],\"success\":true}") == null);
}

test "parses cursor result_info envelopes" {
    const allocator = std.testing.allocator;
    var info = (try cursorInfo(allocator,
        \\{"result":[{"id":"one"},{"id":"two"}],"result_info":{"count":"2","cursor":"next-cursor"},"success":true}
    )) orelse return error.TestExpectedPagination;
    defer info.deinit(allocator);
    try std.testing.expectEqual(Envelope.cursor_result_info, info.envelope);
    try std.testing.expectEqual(@as(usize, 2), info.data_len);
    try std.testing.expectEqualStrings("next-cursor", info.next_cursor orelse "");
    try std.testing.expect(info.hasNext());

    var nested = (try cursorInfo(allocator,
        \\{"result":[{"id":"one"}],"result_info":{"cursors":{"after":"after-cursor"}},"success":true}
    )) orelse return error.TestExpectedPagination;
    defer nested.deinit(allocator);
    try std.testing.expectEqualStrings("after-cursor", nested.next_cursor orelse "");
    try std.testing.expect(nested.hasNext());

    var encoded = (try cursorInfo(allocator,
        \\{"result":[],"result_info":{"cursors":{"after":"a%2Fb%2Bc"}},"success":true}
    )) orelse return error.TestExpectedPagination;
    defer encoded.deinit(allocator);
    try std.testing.expectEqualStrings("a/b+c", encoded.next_cursor orelse "");

    var last = (try cursorInfo(allocator,
        \\{"result":[{"id":"one"}],"result_info":{"count":1,"cursor":""},"success":true}
    )) orelse return error.TestExpectedPagination;
    defer last.deinit(allocator);
    try std.testing.expect(!last.hasNext());
}

test "parses root cursor envelopes" {
    const allocator = std.testing.allocator;
    var info = (try cursorInfo(allocator,
        \\{"keys":[{"name":"a"}],"list_complete":false,"cursor":"next-root"}
    )) orelse return error.TestExpectedPagination;
    defer info.deinit(allocator);
    try std.testing.expectEqual(Envelope.cursor_root, info.envelope);
    try std.testing.expectEqual(@as(usize, 1), info.data_len);
    try std.testing.expectEqualStrings("next-root", info.next_cursor orelse "");
    try std.testing.expect(info.hasNext());

    var done = (try cursorInfo(allocator,
        \\{"keys":[],"list_complete":true,"cursor":"ignored"}
    )) orelse return error.TestExpectedPagination;
    defer done.deinit(allocator);
    try std.testing.expect(!done.hasNext());
}

test "merges data pagination envelopes" {
    const allocator = std.testing.allocator;
    const bodies = [_][]const u8{
        \\{"data":[{"id": 1}, {"id": 2}], "meta": {"current_page": 1, "per_page": 2, "total": 3}}
        ,
        \\{"data":[{"id": 3}], "meta": {"current_page": 2, "per_page": 2, "total": 3}}
        ,
    };
    const merged = try mergeDataPages(allocator, &bodies);
    defer allocator.free(merged);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"id\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"pages\":2") != null);
}
