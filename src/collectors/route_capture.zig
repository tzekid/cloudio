const std = @import("std");
const collector_capture = @import("collector_capture");
const collector_capture_normalize = @import("collector_capture_normalize");
const db_store = @import("db_store");
const net_pagination = @import("net_pagination");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const default_capture_max_pages = 25;

pub const Auth = provider_dispatch.Auth;
pub const Request = provider_routes.Request;

pub const CaptureOptions = struct {
    kind: ?[]const u8 = null,
    target: ?[]const u8 = null,
    paginate: bool = false,
    max_pages: usize = default_capture_max_pages,
    diagnostic_read: bool = false,
};

pub const CapturedRoutePage = struct {
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

    pub fn deinit(self: CapturedRoutePage, gpa: Allocator) void {
        gpa.free(self.endpoint);
    }
};

pub const CapturedRoutePages = struct {
    items: []CapturedRoutePage,
    max_pages: usize,

    pub fn deinit(self: *CapturedRoutePages, gpa: Allocator) void {
        for (self.items) |page| page.deinit(gpa);
        gpa.free(self.items);
    }
};

pub const CapturePageRef = union(enum) {
    page: usize,
    cursor: usize,

    pub fn index(self: CapturePageRef) usize {
        return switch (self) {
            .page => |value| value,
            .cursor => |value| value,
        };
    }
};

pub fn readRoute(
    io: Io,
    gpa: Allocator,
    db: *Db,
    client: provider_dispatch.Client,
    route: provider_routes.Route,
    request: Request,
    options: CaptureOptions,
) !CapturedRoutePage {
    const result = try callReadRouteResultRequest(io, gpa, client, route, request, options);
    defer result.deinit(gpa);
    return try captureReadResult(gpa, db, route, request, result, options, null);
}

pub fn readPaginatedRoute(
    io: Io,
    gpa: Allocator,
    db: *Db,
    client: provider_dispatch.Client,
    route: provider_routes.Route,
    request: Request,
    options: CaptureOptions,
) !CapturedRoutePages {
    if (routeSupportsPageQuery(route)) return try capturePagePaginatedRouteRead(io, gpa, db, client, route, request, options);
    if (routeSupportsCursorQuery(route)) return try captureCursorPaginatedRouteRead(io, gpa, db, client, route, request, options);
    return error.RoutePaginationUnsupported;
}

pub fn captureReadResult(
    gpa: Allocator,
    db: *Db,
    route: provider_routes.Route,
    request: Request,
    result: provider_dispatch.ReadRouteResult,
    options: CaptureOptions,
    page_ref: ?CapturePageRef,
) !CapturedRoutePage {
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

pub fn callReadRouteResultRequest(
    io: Io,
    gpa: Allocator,
    client: provider_dispatch.Client,
    route: provider_routes.Route,
    request: Request,
    options: CaptureOptions,
) !provider_dispatch.ReadRouteResult {
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

fn capturePagePaginatedRouteRead(
    io: Io,
    gpa: Allocator,
    db: *Db,
    client: provider_dispatch.Client,
    route: provider_routes.Route,
    request: Request,
    options: CaptureOptions,
) !CapturedRoutePages {
    const max_pages = effectiveMaxPages(options);
    var pages = std.ArrayList(CapturedRoutePage).empty;
    errdefer deinitCapturedPageList(&pages, gpa);

    var page: usize = 1;
    while (page <= max_pages) : (page += 1) {
        const page_request = try requestWithPage(gpa, request, page);
        defer page_request.deinit(gpa);
        const result = try callReadRouteResultRequest(io, gpa, client, route, page_request.request, options);
        defer result.deinit(gpa);
        const captured = try captureReadResult(gpa, db, route, page_request.request, result, options, .{ .page = page });
        pages.append(gpa, captured) catch |err| {
            captured.deinit(gpa);
            return err;
        };

        const status = result.statusCode();
        if (status < 200 or status >= 300) break;
        const pagination = net_pagination.pageInfo(result.response.body) orelse break;
        if (!pagination.hasNext()) break;
    }

    return .{ .items = try pages.toOwnedSlice(gpa), .max_pages = max_pages };
}

fn captureCursorPaginatedRouteRead(
    io: Io,
    gpa: Allocator,
    db: *Db,
    client: provider_dispatch.Client,
    route: provider_routes.Route,
    request: Request,
    options: CaptureOptions,
) !CapturedRoutePages {
    const max_pages = effectiveMaxPages(options);
    var pages = std.ArrayList(CapturedRoutePage).empty;
    errdefer deinitCapturedPageList(&pages, gpa);

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
        const captured = try captureReadResult(gpa, db, route, effective_request, result, options, .{ .cursor = page_index });
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

    return .{ .items = try pages.toOwnedSlice(gpa), .max_pages = max_pages };
}

fn effectiveMaxPages(options: CaptureOptions) usize {
    return if (options.max_pages == 0) default_capture_max_pages else options.max_pages;
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

test "captures paginated Hostinger route pages into snapshots and normalized rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-paged-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Public Keys","method":"GET","path":"/api/vps/v1/public-keys","operation_id":"VPS_getPublicKeysV1","path_params":[],"query_params":[{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Common.Schema.PaginationMetaSchema","#/components/schemas/VPS.V1.PublicKey.PublicKeyCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC paginates public keys."}
        \\
    ;

    const route = (try provider_routes.findByOperationIdFromText(allocator, .hostinger, hostinger, "VPS_getPublicKeysV1")) orelse return error.ExpectedRoute;
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
    const first_page = try captureReadResult(
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
    const second_page = try captureReadResult(
        allocator,
        &db,
        route,
        second_request.request,
        second_result,
        .{ .kind = "route-public-keys", .target = "public-keys" },
        .{ .page = 2 },
    );
    defer second_page.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1), first_page.snapshot_id);
    try std.testing.expectEqual(@as(i64, 2), second_page.snapshot_id);
    try std.testing.expect(first_page.pagination_envelope != null);
    try std.testing.expectEqual(@as(?usize, 1), first_page.data_len);
    try std.testing.expect(first_page.has_next);
    try std.testing.expect(!second_page.has_next);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_inventory_items"));
}
