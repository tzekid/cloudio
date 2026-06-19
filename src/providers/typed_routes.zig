const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DryRunPlan = struct {
    group: []const u8,
    operation: []const u8,
    operation_id: []const u8,
    summary: []const u8,
    method: []const u8,
    path: []const u8,
    request_body_schema: ?[]const u8,
};

pub const QueryParam = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub fn pathEscape(gpa: Allocator, value: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try (std.Uri.Component{ .raw = value }).formatEscaped(&out.writer);
    return try out.toOwnedSlice();
}

pub fn appendQueryParam(gpa: Allocator, base: []const u8, key: []const u8, value: []const u8) ![]u8 {
    const escaped = try pathEscape(gpa, value);
    defer gpa.free(escaped);
    const sep: []const u8 = if (std.mem.indexOfScalar(u8, base, '?') == null) "?" else "&";
    return try std.fmt.allocPrint(gpa, "{s}{s}{s}={s}", .{ base, sep, key, escaped });
}

pub fn appendQuery(gpa: Allocator, base_path: []const u8, params: []const QueryParam) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.writeAll(base_path);
    var first = true;
    for (params) |param| {
        const value = param.value orelse continue;
        try out.writer.writeByte(if (first) '?' else '&');
        first = false;
        try out.writer.writeAll(param.name);
        try out.writer.writeByte('=');
        const escaped = try pathEscape(gpa, value);
        defer gpa.free(escaped);
        try out.writer.writeAll(escaped);
    }
    return try out.toOwnedSlice();
}

pub fn dryRunPlanJson(gpa: Allocator, provider: []const u8, safety: []const u8, plan: DryRunPlan) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", provider, true);
    try writeJsonField(writer, "group", plan.group, true);
    try writeJsonField(writer, "operation", plan.operation, true);
    try writeJsonField(writer, "operation_id", plan.operation_id, true);
    try writeJsonField(writer, "summary", plan.summary, true);
    try writeJsonField(writer, "method", plan.method, true);
    try writeJsonField(writer, "path", plan.path, true);
    if (plan.request_body_schema) |schema| {
        try writeJsonField(writer, "request_body_schema", schema, true);
    } else {
        try writer.writeAll("\"request_body_schema\":null,");
    }
    try writer.writeAll("\"mode\":\"dry_run\",");
    try writer.writeAll("\"will_execute\":false,");
    try writeJsonField(writer, "safety", safety, false);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try writeJsonString(writer, name);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
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

test "escapes provider path segments" {
    const allocator = std.testing.allocator;
    const escaped = try pathEscape(allocator, "team api/blue");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings("team%20api%2Fblue", escaped);
}

test "appends optional query parameters with path escaping" {
    const allocator = std.testing.allocator;
    const with_query = try appendQuery(allocator, "/accounts/acct/rules", &[_]QueryParam{
        .{ .name = "search", .value = "a b/c" },
        .{ .name = "empty", .value = null },
        .{ .name = "page", .value = "2" },
    });
    defer allocator.free(with_query);
    try std.testing.expectEqualStrings("/accounts/acct/rules?search=a%20b%2Fc&page=2", with_query);

    const extra = try appendQueryParam(allocator, "/api/items?sort=id", "filter", "x/y");
    defer allocator.free(extra);
    try std.testing.expectEqualStrings("/api/items?sort=id&filter=x%2Fy", extra);
}

test "renders typed mutation dry-run JSON without execution" {
    const allocator = std.testing.allocator;
    const json = try dryRunPlanJson(allocator, "provider", "No request is sent.", .{
        .group = "Group",
        .operation = "create",
        .operation_id = "provider-create",
        .summary = "Create \"thing\"",
        .method = "POST",
        .path = "/items",
        .request_body_schema = null,
    });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"provider\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":\"Create \\\"thing\\\"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_body_schema\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"safety\":\"No request is sent.\"") != null);
}
