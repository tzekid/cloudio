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

    pub fn name(self: Envelope) []const u8 {
        return switch (self) {
            .data_meta => "data_meta",
            .result_info => "result_info",
        };
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

fn positiveInt(value: std.json.Value, name: []const u8) ?usize {
    const int_value = core_json.fieldInt(value, name) orelse return null;
    if (int_value < 0) return null;
    return @intCast(int_value);
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
