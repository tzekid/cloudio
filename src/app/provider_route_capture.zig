const std = @import("std");
const collector_capture = @import("collector_capture");
const collector_capture_normalize = @import("collector_capture_normalize");
const app_provider_route_plan = @import("app_provider_route_plan");
const core_json = @import("core_json");
const db_store = @import("db_store");
const net_pagination = @import("net_pagination");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const default_capture_max_pages = 25;

pub const Auth = provider_dispatch.Auth;
pub const Paths = provider_routes.Paths;
pub const Request = provider_routes.Request;
pub const RoutePlanInput = app_provider_route_plan.RoutePlanInput;

pub const CaptureOptions = struct {
    kind: ?[]const u8 = null,
    target: ?[]const u8 = null,
    paginate: bool = false,
    max_pages: usize = default_capture_max_pages,
    diagnostic_read: bool = false,
};

const CapturedRoutePage = struct {
    page: usize,
    endpoint: []u8,
    snapshot_id: i64,
    http_status: u16,
    status_text: []const u8,
    body_bytes: usize,
    normalized_resources: usize,
    typed_rows: usize,
    pagination_envelope: ?net_pagination.Envelope,
    data_len: ?usize,
    has_next: bool,

    fn deinit(self: CapturedRoutePage, gpa: Allocator) void {
        gpa.free(self.endpoint);
    }
};

const CapturePageRef = union(enum) {
    page: usize,
    cursor: usize,

    fn index(self: CapturePageRef) usize {
        return switch (self) {
            .page => |value| value,
            .cursor => |value| value,
        };
    }
};

pub fn readMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    const route = try app_provider_route_plan.loadRoute(io, gpa, paths, input);
    defer route.deinit(gpa);
    const client = provider_dispatch.Client.init(auth);
    return try readRouteMetadataJson(io, gpa, db, client, route, input.request, options);
}

pub fn readRouteMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    if (options.paginate) return try paginatedReadMetadataJson(io, gpa, db, client, route, request, options);
    const result = try callReadRouteResultRequest(io, gpa, client, route, request, options);
    defer result.deinit(gpa);
    return try readResultJson(gpa, db, route, request, result, options);
}

pub fn readResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions) ![]u8 {
    const captured = try captureRouteReadPageResult(gpa, db, route, request, result, options, null);
    defer captured.deinit(gpa);
    return try routeCaptureMetadataJson(gpa, route, result, captured.snapshot_id, captured.endpoint, options.kind orelse route.operation_id orelse route.path_template, options.target orelse captured.endpoint, captured.normalized_resources, captured.typed_rows);
}

pub fn paginatedReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    if (routeSupportsPageQuery(route)) return try capturePagePaginatedRouteReadMetadataJson(io, gpa, db, client, route, request, options);
    if (routeSupportsCursorQuery(route)) return try captureCursorPaginatedRouteReadMetadataJson(io, gpa, db, client, route, request, options);
    return error.RoutePaginationUnsupported;
}

pub fn callReadRouteResultRequest(io: Io, gpa: Allocator, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) !provider_dispatch.ReadRouteResult {
    if (options.diagnostic_read) return try client.callDiagnosticReadRouteResultRequest(io, gpa, route, request);
    return try client.callReadRouteResultRequest(io, gpa, route, request);
}

pub fn routeSupportsPageQuery(route: provider_routes.Route) bool {
    for (route.query_params) |param| {
        if (std.mem.eql(u8, param.name, "page")) return true;
    }
    return false;
}

pub fn routeSupportsCursorQuery(route: provider_routes.Route) bool {
    for (route.query_params) |param| {
        if (std.mem.eql(u8, param.name, "cursor")) return true;
    }
    return false;
}

fn capturePagePaginatedRouteReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    const max_pages = if (options.max_pages == 0) default_capture_max_pages else options.max_pages;
    var pages = std.ArrayList(CapturedRoutePage).empty;
    defer deinitCapturedPageList(&pages, gpa);

    var page: usize = 1;
    while (page <= max_pages) : (page += 1) {
        const page_request = try requestWithPage(gpa, request, page);
        defer page_request.deinit(gpa);
        const result = try callReadRouteResultRequest(io, gpa, client, route, page_request.request, options);
        defer result.deinit(gpa);
        const captured = try captureRouteReadPageResult(gpa, db, route, page_request.request, result, options, .{ .page = page });
        pages.append(gpa, captured) catch |err| {
            captured.deinit(gpa);
            return err;
        };

        const status = result.statusCode();
        if (status < 200 or status >= 300) break;
        const pagination = net_pagination.pageInfo(result.response.body) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try routePaginatedCaptureMetadataJson(gpa, route, pages.items, max_pages);
}

fn captureCursorPaginatedRouteReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    const max_pages = if (options.max_pages == 0) default_capture_max_pages else options.max_pages;
    var pages = std.ArrayList(CapturedRoutePage).empty;
    defer deinitCapturedPageList(&pages, gpa);

    var page_index: usize = 1;
    var next_cursor: ?[]u8 = null;
    defer if (next_cursor) |cursor| gpa.free(cursor);

    while (page_index <= max_pages) : (page_index += 1) {
        var owned_request: ?OwnedQueryRequest = null;
        defer if (owned_request) |owned| owned.deinit(gpa);
        const effective_request = if (next_cursor) |cursor| blk: {
            owned_request = try requestWithCursor(gpa, request, cursor);
            break :blk owned_request.?.request;
        } else request;

        const result = try callReadRouteResultRequest(io, gpa, client, route, effective_request, options);
        defer result.deinit(gpa);
        const captured = try captureRouteReadPageResult(gpa, db, route, effective_request, result, options, .{ .cursor = page_index });
        pages.append(gpa, captured) catch |err| {
            captured.deinit(gpa);
            return err;
        };

        const status = result.statusCode();
        if (status < 200 or status >= 300) break;
        var cursor_info = (try net_pagination.cursorInfo(gpa, result.response.body)) orelse break;
        defer cursor_info.deinit(gpa);
        if (!cursor_info.hasNext()) break;
        const cursor_value = cursor_info.next_cursor orelse break;
        if (next_cursor) |old| gpa.free(old);
        next_cursor = try gpa.dupe(u8, cursor_value);
    }

    return try routePaginatedCaptureMetadataJson(gpa, route, pages.items, max_pages);
}

fn captureRouteReadPageResult(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions, page_ref: ?CapturePageRef) !CapturedRoutePage {
    const endpoint = try captureEndpoint(gpa, route, request);
    errdefer gpa.free(endpoint);
    const operation = route.operation_id orelse route.path_template;
    const kind = options.kind orelse operation;
    const target = try captureTarget(gpa, options.target, endpoint, page_ref);
    defer if (target.owned) |owned| gpa.free(owned);
    const summary_label = try captureSummaryLabel(gpa, operation, page_ref);
    defer gpa.free(summary_label);
    const stored = try collector_capture.storeResponseWithSnapshotId(gpa, db, .{
        .provider = route.provider.name(),
        .kind = kind,
        .target = target.value,
        .summary_label = summary_label,
        .endpoint = endpoint,
        .status = result.response.status,
        .body = result.response.body,
    });
    defer stored.deinit(gpa);
    const normalized = try collector_capture_normalize.normalizeRouteCapture(gpa, db, route, request, kind, options.target, result.statusCode(), stored.redacted);
    const audit_detail = try std.fmt.allocPrint(gpa, "{s}/{s} {s}", .{ route.provider.name(), operation, endpoint });
    defer gpa.free(audit_detail);
    try db.insertAudit("route.capture", result.statusText(), audit_detail);
    const pagination = net_pagination.pageInfo(result.response.body);
    const cursor_info = try net_pagination.cursorInfo(gpa, result.response.body);
    defer if (cursor_info) |info| info.deinit(gpa);
    return .{
        .page = if (page_ref) |ref| ref.index() else 1,
        .endpoint = endpoint,
        .snapshot_id = stored.snapshot_id,
        .http_status = result.statusCode(),
        .status_text = result.statusText(),
        .body_bytes = result.response.body.len,
        .normalized_resources = normalized.resources,
        .typed_rows = normalized.typed_rows,
        .pagination_envelope = if (pagination) |info| info.envelope else if (cursor_info) |info| info.envelope else null,
        .data_len = if (pagination) |info| info.data_len else if (cursor_info) |info| info.data_len else null,
        .has_next = if (pagination) |info| info.hasNext() else if (cursor_info) |info| info.hasNext() else false,
    };
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

const CaptureTarget = struct {
    value: []const u8,
    owned: ?[]u8 = null,
};

fn captureTarget(gpa: Allocator, base_target: ?[]const u8, endpoint: []const u8, page_ref: ?CapturePageRef) !CaptureTarget {
    const ref = page_ref orelse return .{ .value = base_target orelse endpoint };
    if (base_target) |target| {
        const owned = switch (ref) {
            .page => |page_value| try std.fmt.allocPrint(gpa, "{s}?page={d}", .{ target, page_value }),
            .cursor => |page_value| try std.fmt.allocPrint(gpa, "{s}?cursor_page={d}", .{ target, page_value }),
        };
        return .{ .value = owned, .owned = owned };
    }
    return .{ .value = endpoint };
}

fn captureSummaryLabel(gpa: Allocator, operation: []const u8, page_ref: ?CapturePageRef) ![]u8 {
    const ref = page_ref orelse return try gpa.dupe(u8, operation);
    return switch (ref) {
        .page => |page_value| try std.fmt.allocPrint(gpa, "{s} page {d}", .{ operation, page_value }),
        .cursor => |page_value| try std.fmt.allocPrint(gpa, "{s} cursor page {d}", .{ operation, page_value }),
    };
}

const OwnedQueryRequest = struct {
    request: Request,
    query_params: []provider_routes.QueryParam,
    value: []u8,

    fn deinit(self: OwnedQueryRequest, gpa: Allocator) void {
        gpa.free(self.query_params);
        gpa.free(self.value);
    }
};

fn requestWithPage(gpa: Allocator, request: Request, page: usize) !OwnedQueryRequest {
    const page_value = try std.fmt.allocPrint(gpa, "{d}", .{page});
    return try requestWithQueryOverrideOwned(gpa, request, "page", page_value);
}

fn requestWithCursor(gpa: Allocator, request: Request, cursor: []const u8) !OwnedQueryRequest {
    const cursor_value = try gpa.dupe(u8, cursor);
    return try requestWithQueryOverrideOwned(gpa, request, "cursor", cursor_value);
}

fn requestWithQueryOverrideOwned(gpa: Allocator, request: Request, name: []const u8, owned_value: []u8) !OwnedQueryRequest {
    errdefer gpa.free(owned_value);
    var query_count: usize = 1;
    for (request.query_params) |param| {
        if (!std.mem.eql(u8, param.name, name)) query_count += 1;
    }
    const query_params = try gpa.alloc(provider_routes.QueryParam, query_count);
    errdefer gpa.free(query_params);
    var index: usize = 0;
    for (request.query_params) |param| {
        if (std.mem.eql(u8, param.name, name)) continue;
        query_params[index] = param;
        index += 1;
    }
    query_params[index] = .{ .name = name, .value = owned_value };
    return .{
        .request = .{
            .path_params = request.path_params,
            .query_params = query_params,
            .header_params = request.header_params,
            .body = request.body,
        },
        .query_params = query_params,
        .value = owned_value,
    };
}

fn captureEndpoint(gpa: Allocator, route: provider_routes.Route, request: Request) ![]u8 {
    const endpoint = try route.renderRequestPath(gpa, request);
    errdefer gpa.free(endpoint);
    if (!requestHasQueryParam(request, "cursor")) return endpoint;
    const sanitized = try redactedCursorEndpoint(gpa, endpoint);
    gpa.free(endpoint);
    return sanitized;
}

fn requestHasQueryParam(request: Request, name: []const u8) bool {
    for (request.query_params) |param| {
        if (std.mem.eql(u8, param.name, name)) return true;
    }
    return false;
}

fn redactedCursorEndpoint(gpa: Allocator, endpoint: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    var first = true;
    var parts = std.mem.splitScalar(u8, endpoint, '&');
    while (parts.next()) |part| {
        if (!first) try out.writer.writeByte('&');
        first = false;
        if (isCursorQueryPart(part)) {
            const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
            try out.writer.writeAll(part[0..eq]);
            try out.writer.writeAll("=<redacted-cursor>");
        } else {
            try out.writer.writeAll(part);
        }
    }
    return try out.toOwnedSlice();
}

fn isCursorQueryPart(part: []const u8) bool {
    if (std.mem.startsWith(u8, part, "cursor=")) return true;
    if (std.mem.endsWith(u8, part, "?cursor")) return true;
    if (std.mem.indexOf(u8, part, "?cursor=")) |_| return true;
    return false;
}

fn deinitCapturedPageList(pages: *std.ArrayList(CapturedRoutePage), gpa: Allocator) void {
    for (pages.items) |page| page.deinit(gpa);
    pages.deinit(gpa);
}

test "captures paginated Hostinger route pages into snapshots and metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-paged-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Public Keys","method":"GET","path":"/api/vps/v1/public-keys","operation_id":"VPS_getPublicKeysV1","path_params":[],"query_params":[{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Common.Schema.PaginationMetaSchema","#/components/schemas/VPS.V1.PublicKey.PublicKeyCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC paginates public keys."}
        \\
    ;

    const route = try app_provider_route_plan.loadRouteFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .hostinger, .operation_id = "VPS_getPublicKeysV1" } });
    defer route.deinit(allocator);
    try std.testing.expect(routeSupportsPageQuery(route));

    const base_request = Request{
        .query_params = &.{
            .{ .name = "page", .value = "99" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const first_request = try requestWithPage(allocator, base_request, 1);
    defer first_request.deinit(allocator);
    const first_path = try route.renderRequestPath(allocator, first_request.request);
    defer allocator.free(first_path);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=99") == null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=1") != null);

    const first_body = try allocator.dupe(u8,
        \\{"data":[{"id":1,"password":"secret-one"}],"meta":{"current_page":1,"per_page":1,"total":2}}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        first_request.request,
        first_result,
        .{ .kind = "route-public-keys", .target = "public-keys" },
        .{ .page = 1 },
    );
    defer first_page.deinit(allocator);

    const second_request = try requestWithPage(allocator, base_request, 2);
    defer second_request.deinit(allocator);
    const second_body = try allocator.dupe(u8,
        \\{"data":[{"id":2,"password":"secret-two"}],"meta":{"current_page":2,"per_page":1,"total":2}}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        second_request.request,
        second_result,
        .{ .kind = "route-public-keys", .target = "public-keys" },
        .{ .page = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[1,2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"data_meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"data_len\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_inventory_items"));
}

test "captures Cloudflare result_info paginated generic route pages" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-paged-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list-accounts","path_params":[],"query_params":[{"name":"direction","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":["asc","desc"]}},{"name":"name","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":[]}},{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["number"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["number"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/iam_response_collection_accounts"]}],"security":{"required":true,"alternatives":[["api_email","api_key"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC lists accounts and stores raw/account summary data."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    const route = try app_provider_route_plan.loadRouteFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .cloudflare, .operation_id = "accounts-list-accounts" } });
    defer route.deinit(allocator);
    try std.testing.expect(routeSupportsPageQuery(route));

    const base_request = Request{
        .query_params = &.{
            .{ .name = "page", .value = "7" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const first_request = try requestWithPage(allocator, base_request, 1);
    defer first_request.deinit(allocator);
    const first_path = try route.renderRequestPath(allocator, first_request.request);
    defer allocator.free(first_path);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=7") == null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=1") != null);

    const first_body = try allocator.dupe(u8,
        \\{"result":[{"id":"account-one","token":"secret-one"}],"result_info":{"page":1,"per_page":1,"total_pages":2,"count":1,"total_count":2},"success":true,"errors":[],"messages":[]}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        first_request.request,
        first_result,
        .{ .kind = "route-cloudflare-accounts", .target = "accounts" },
        .{ .page = 1 },
    );
    defer first_page.deinit(allocator);

    const second_request = try requestWithPage(allocator, base_request, 2);
    defer second_request.deinit(allocator);
    const second_body = try allocator.dupe(u8,
        \\{"result":[{"id":"account-two","token":"secret-two"}],"result_info":{"page":2,"per_page":1,"total_pages":2,"count":1,"total_count":2},"success":true,"errors":[],"messages":[]}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        second_request.request,
        second_result,
        .{ .kind = "route-cloudflare-accounts", .target = "accounts" },
        .{ .page = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[1,2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"result_info\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"data_len\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_accounts"));
}

test "captures Cloudflare cursor paginated generic route pages without leaking cursors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-cursor-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Zone Rulesets","method":"GET","path":"/zones/{zone_id}/rulesets","operation_id":"listZoneRulesets","path_params":[{"name":"zone_id","required":true,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_ZoneId"],"types":["string"],"formats":[],"enum_values":[]}}],"query_params":[{"name":"cursor","required":false,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_Cursor"],"types":["string"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_PerPage"],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/rulesets_Response","#/components/schemas/rulesets_ResultInfo","#/components/schemas/rulesets_Ruleset"]}],"security":{"required":true,"alternatives":[["api_email","api_key"],["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads zone ruleset lists by explicit zone ID and during configured-domain refresh as redacted raw provider data."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    const route = try app_provider_route_plan.loadRouteFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .cloudflare, .operation_id = "listZoneRulesets" } });
    defer route.deinit(allocator);
    try std.testing.expect(!routeSupportsPageQuery(route));
    try std.testing.expect(routeSupportsCursorQuery(route));

    const base_request = Request{
        .path_params = &.{.{ .name = "zone_id", .value = "zone-one" }},
        .query_params = &.{
            .{ .name = "cursor", .value = "old-cursor" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const cursor_request = try requestWithCursor(allocator, base_request, "opaque-next-cursor");
    defer cursor_request.deinit(allocator);
    const cursor_path = try route.renderRequestPath(allocator, cursor_request.request);
    defer allocator.free(cursor_path);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "old-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "cursor=opaque-next-cursor") != null);

    const first_body = try allocator.dupe(u8,
        \\{"result":[{"id":"ruleset-one","token":"secret-one"}],"result_info":{"cursors":{"after":"opaque-next-cursor"}},"success":true,"errors":[],"messages":[]}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        base_request,
        first_result,
        .{ .kind = "route-cloudflare-rulesets", .target = "rulesets" },
        .{ .cursor = 1 },
    );
    defer first_page.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, first_page.endpoint, "old-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, first_page.endpoint, "<redacted-cursor>") != null);

    const second_body = try allocator.dupe(u8,
        \\{"result":[{"id":"ruleset-two","token":"secret-two"}],"result_info":{"cursors":{}},"success":true,"errors":[],"messages":[]}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route,
        cursor_request.request,
        second_result,
        .{ .kind = "route-cloudflare-rulesets", .target = "rulesets" },
        .{ .cursor = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"cursor_result_info\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "opaque-next-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "old-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "<redacted-cursor>") != null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_inventory_items"));
}
