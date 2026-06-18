const std = @import("std");
const collector_route_capture = @import("collector_route_capture");
const app_provider_route_plan = @import("app_provider_route_plan");
const core_json = @import("core_json");
const db_store = @import("db_store");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Auth = provider_dispatch.Auth;
pub const Paths = provider_routes.Paths;
pub const Request = provider_routes.Request;
pub const RoutePlanInput = app_provider_route_plan.RoutePlanInput;
pub const CaptureOptions = collector_route_capture.CaptureOptions;
const CapturedRoutePage = collector_route_capture.CapturedRoutePage;

pub fn readMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    const route = try app_provider_route_plan.loadRoute(io, gpa, paths, input);
    defer route.deinit(gpa);
    const client = provider_dispatch.Client.init(auth);
    return try readRouteMetadataJson(io, gpa, db, client, route, input.request, options);
}

pub fn readRouteMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    if (options.paginate) return try paginatedReadMetadataJson(io, gpa, db, client, route, request, options);
    const result = try collector_route_capture.callReadRouteResultRequest(io, gpa, client, route, request, options);
    defer result.deinit(gpa);
    return try readResultJson(gpa, db, route, request, result, options);
}

pub fn readResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions) ![]u8 {
    const captured = try collector_route_capture.captureReadResult(gpa, db, route, request, result, options, null);
    defer captured.deinit(gpa);
    return try routeCaptureMetadataJson(gpa, route, result, captured.snapshot_id, captured.endpoint, options.kind orelse route.operation_id orelse route.path_template, options.target orelse captured.endpoint, captured.normalized_resources, captured.typed_rows);
}

pub fn paginatedReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    var pages = try collector_route_capture.readPaginatedRoute(io, gpa, db, client, route, request, options);
    defer pages.deinit(gpa);
    return try routePaginatedCaptureMetadataJson(gpa, route, pages.items, pages.max_pages);
}

pub fn callReadRouteResultRequest(io: Io, gpa: Allocator, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) !provider_dispatch.ReadRouteResult {
    return try collector_route_capture.callReadRouteResultRequest(io, gpa, client, route, request, options);
}

pub fn routeSupportsPageQuery(route: provider_routes.Route) bool {
    return collector_route_capture.routeSupportsPageQuery(route);
}

pub fn routeSupportsCursorQuery(route: provider_routes.Route) bool {
    return collector_route_capture.routeSupportsCursorQuery(route);
}

fn routeCaptureMetadataJson(gpa: Allocator, route: provider_routes.Route, result: provider_dispatch.ReadRouteResult, snapshot_id: i64, endpoint: []const u8, kind: []const u8, target: []const u8, normalized_resources: usize, typed_rows: usize) ![]u8 {
    const read_json = try provider_dispatch.readRouteResultMetadataJson(gpa, route, result);
    defer gpa.free(read_json);
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try writeJsonField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "endpoint", endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"captured\":true,");
    try writer.writeAll("\"provider_raw\":true,");
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{normalized_resources});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{typed_rows});
    try writer.writeByte(',');
    try writer.writeAll("\"snapshot\":{");
    try writeJsonField(writer, "source", route.provider.name(), true);
    try writeJsonField(writer, "kind", kind, true);
    try writeJsonField(writer, "target", target, false);
    try writer.writeAll("},");
    try writer.writeAll("\"read\":");
    try writer.writeAll(read_json);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn routePaginatedCaptureMetadataJson(gpa: Allocator, route: provider_routes.Route, pages: []const CapturedRoutePage, max_pages: usize) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try writeJsonField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try writeJsonField(writer, "method", route.method.name(), true);
    try writer.writeAll("\"paginated\":true,");
    try writer.writeAll("\"captured_pages\":");
    try writer.print("{d}", .{pages.len});
    try writer.writeByte(',');
    try writer.writeAll("\"max_pages\":");
    try writer.print("{d}", .{max_pages});
    try writer.writeByte(',');
    try writer.writeAll("\"truncated\":");
    try writer.writeAll(if (pages.len >= max_pages and pages.len != 0 and pages[pages.len - 1].has_next) "true" else "false");
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

fn writeCapturedPageJson(writer: anytype, page: CapturedRoutePage) !void {
    try writer.writeAll("{\"page\":");
    try writer.print("{d}", .{page.page});
    try writer.writeByte(',');
    try writeJsonField(writer, "endpoint", page.endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{page.snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"http_status\":");
    try writer.print("{d}", .{page.http_status});
    try writer.writeByte(',');
    try writeJsonField(writer, "status_text", page.status_text, true);
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
        try writeJsonField(writer, "pagination_envelope", envelope.name(), true);
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

fn normalizedResourceTotal(pages: []const CapturedRoutePage) usize {
    var total: usize = 0;
    for (pages) |page| total += page.normalized_resources;
    return total;
}

fn typedRowsTotal(pages: []const CapturedRoutePage) usize {
    var total: usize = 0;
    for (pages) |page| total += page.typed_rows;
    return total;
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

test "renders paginated route capture metadata without response bodies" {
    const allocator = std.testing.allocator;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Public Keys","method":"GET","path":"/api/vps/v1/public-keys","operation_id":"VPS_getPublicKeysV1","path_params":[],"query_params":[{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Common.Schema.PaginationMetaSchema","#/components/schemas/VPS.V1.PublicKey.PublicKeyCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC paginates public keys."}
        \\
    ;

    const route = (try provider_routes.findByOperationIdFromText(allocator, .hostinger, hostinger, "VPS_getPublicKeysV1")) orelse return error.ExpectedRoute;
    defer route.deinit(allocator);

    var page = CapturedRoutePage{
        .page = 1,
        .endpoint = try allocator.dupe(u8, "/api/vps/v1/public-keys?page=1"),
        .snapshot_id = 42,
        .http_status = 200,
        .status_text = "OK",
        .body_bytes = 128,
        .normalized_resources = 2,
        .typed_rows = 1,
        .pagination_envelope = null,
        .data_len = null,
        .has_next = false,
    };
    defer page.deinit(allocator);
    const pages = [_]CapturedRoutePage{page};
    const json = try routePaginatedCaptureMetadataJson(allocator, route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[42]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret") == null);
}
