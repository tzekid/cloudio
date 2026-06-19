const std = @import("std");
const core_json = @import("core_json");
const provider_route_result = @import("provider_route_result");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

pub const CaptureMetadataView = struct {
    endpoint: []const u8,
    snapshot_id: i64,
    kind: []const u8,
    target: []const u8,
    normalized_resources: usize,
    typed_rows: usize,
    read: provider_route_result.ReadRouteResultView,
};

pub const CapturedPageView = struct {
    page: usize,
    endpoint: []const u8,
    snapshot_id: i64,
    http_status: u16,
    status_text: []const u8,
    body_bytes: usize,
    normalized_resources: usize,
    typed_rows: usize,
    pagination_envelope: ?[]const u8,
    data_len: ?usize,
    has_next: bool,
};

pub fn captureMetadataJson(gpa: Allocator, route: provider_routes.Route, capture: CaptureMetadataView) ![]u8 {
    const read_json = try provider_route_result.readRouteResultMetadataJson(gpa, route, capture.read);
    defer gpa.free(read_json);
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try core_json.writeStringField(writer, "provider", route.provider.name(), true);
    try core_json.writeStringField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try core_json.writeStringField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try core_json.writeStringField(writer, "method", route.method.name(), true);
    try core_json.writeStringField(writer, "endpoint", capture.endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{capture.snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"captured\":true,");
    try writer.writeAll("\"provider_raw\":true,");
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{capture.normalized_resources});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{capture.typed_rows});
    try writer.writeByte(',');
    try writer.writeAll("\"snapshot\":{");
    try core_json.writeStringField(writer, "source", route.provider.name(), true);
    try core_json.writeStringField(writer, "kind", capture.kind, true);
    try core_json.writeStringField(writer, "target", capture.target, false);
    try writer.writeAll("},");
    try writer.writeAll("\"read\":");
    try writer.writeAll(read_json);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

pub fn paginatedCaptureMetadataJson(gpa: Allocator, route: provider_routes.Route, pages: []const CapturedPageView, max_pages: usize) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try core_json.writeStringField(writer, "provider", route.provider.name(), true);
    try core_json.writeStringField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try core_json.writeStringField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try core_json.writeStringField(writer, "method", route.method.name(), true);
    try writer.writeAll("\"paginated\":true,");
    try writer.writeAll("\"captured_pages\":");
    try writer.print("{d}", .{pages.len});
    try writer.writeByte(',');
    try writer.writeAll("\"max_pages\":");
    try writer.print("{d}", .{max_pages});
    try writer.writeByte(',');
    try writer.writeAll("\"truncated\":");
    try writer.writeAll(if (isTruncated(pages, max_pages)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{normalizedResourceTotal(pages)});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{typedRowsTotal(pages)});
    try writer.writeByte(',');
    try writer.writeAll("\"body_included\":false,");
    try writer.writeAll("\"snapshots\":[");
    for (pages, 0..) |page, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{d}", .{page.snapshot_id});
    }
    try writer.writeAll("],\"pages\":[");
    for (pages, 0..) |page, index| {
        if (index != 0) try writer.writeByte(',');
        try writeCapturedPageJson(writer, page);
    }
    try writer.writeAll("]}");
    return try out.toOwnedSlice();
}

fn writeCapturedPageJson(writer: anytype, page: CapturedPageView) !void {
    try writer.writeAll("{\"page\":");
    try writer.print("{d}", .{page.page});
    try writer.writeByte(',');
    try core_json.writeStringField(writer, "endpoint", page.endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{page.snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"http_status\":");
    try writer.print("{d}", .{page.http_status});
    try writer.writeByte(',');
    try core_json.writeStringField(writer, "status_text", page.status_text, true);
    try writer.writeAll("\"body_bytes\":");
    try writer.print("{d}", .{page.body_bytes});
    try writer.writeByte(',');
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{page.normalized_resources});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{page.typed_rows});
    try writer.writeByte(',');
    if (page.pagination_envelope) |envelope| {
        try core_json.writeStringField(writer, "pagination_envelope", envelope, true);
    } else {
        try writer.writeAll("\"pagination_envelope\":null,");
    }
    if (page.data_len) |data_len| {
        try writer.writeAll("\"data_len\":");
        try writer.print("{d}", .{data_len});
        try writer.writeByte(',');
    } else {
        try writer.writeAll("\"data_len\":null,");
    }
    try writer.writeAll("\"has_next\":");
    try writer.writeAll(if (page.has_next) "true" else "false");
    try writer.writeByte('}');
}

fn isTruncated(pages: []const CapturedPageView, max_pages: usize) bool {
    return pages.len >= max_pages and pages.len != 0 and pages[pages.len - 1].has_next;
}

fn normalizedResourceTotal(pages: []const CapturedPageView) usize {
    var total: usize = 0;
    for (pages) |page| total += page.normalized_resources;
    return total;
}

fn typedRowsTotal(pages: []const CapturedPageView) usize {
    var total: usize = 0;
    for (pages) |page| total += page.typed_rows;
    return total;
}

test "renders route capture metadata with nested read metadata and no body content" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getPublicKeysV1")) orelse return error.ExpectedRoute;
    defer route.deinit(allocator);

    const json = try captureMetadataJson(allocator, route, .{
        .endpoint = "/api/vps/v1/public-keys",
        .snapshot_id = 42,
        .kind = "VPS_getPublicKeysV1",
        .target = "/api/vps/v1/public-keys",
        .normalized_resources = 2,
        .typed_rows = 1,
        .read = .{
            .status = .ok,
            .body_bytes = 128,
            .matched_response = route.findResponseForStatus(.ok),
        },
    });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider_raw\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshot\":{\"source\":\"hostinger\",\"kind\":\"VPS_getPublicKeysV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"read\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret") == null);
}

test "renders paginated route capture metadata without response bodies" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getPublicKeysV1")) orelse return error.ExpectedRoute;
    defer route.deinit(allocator);

    const pages = [_]CapturedPageView{.{
        .page = 1,
        .endpoint = "/api/vps/v1/public-keys?page=1",
        .snapshot_id = 42,
        .http_status = 200,
        .status_text = "ok",
        .body_bytes = 128,
        .normalized_resources = 2,
        .typed_rows = 1,
        .pagination_envelope = "data_meta",
        .data_len = 2,
        .has_next = false,
    }};
    const json = try paginatedCaptureMetadataJson(allocator, route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"data_meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[42]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret") == null);
}
