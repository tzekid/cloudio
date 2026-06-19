const std = @import("std");
const collector_route_capture = @import("collector_route_capture");
const app_provider_route_capture_result = @import("app_provider_route_capture_result");
const app_provider_route_plan = @import("app_provider_route_plan");
const db_store = @import("db_store");
const provider_capabilities = @import("provider_capabilities");
const provider_route_result = @import("provider_route_result");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Auth = app_provider_route_plan.Auth;
pub const Paths = provider_routes.Paths;
pub const Request = provider_routes.Request;
pub const RoutePlanInput = app_provider_route_plan.RoutePlanInput;
pub const CaptureOptions = collector_route_capture.CaptureOptions;
pub const CaptureMetadataView = app_provider_route_capture_result.CaptureMetadataView;
pub const CapturedPageView = app_provider_route_capture_result.CapturedPageView;
const CapturedRoutePage = collector_route_capture.CapturedRoutePage;

pub fn readMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    const route = try app_provider_route_plan.loadRoute(io, gpa, paths, input);
    defer route.deinit(gpa);
    return try readRouteMetadataJson(io, gpa, db, auth, route, input.request, options);
}

pub fn readRouteMetadataJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    if (options.paginate) return try paginatedReadMetadataJson(io, gpa, db, auth, route, request, options);
    const result = try collector_route_capture.callReadRouteResultRequest(io, gpa, auth, route, request, options);
    defer result.deinit(gpa);
    return try readResultJson(gpa, db, route, request, result, options);
}

pub fn readResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_route_result.ReadRouteResult, options: CaptureOptions) ![]u8 {
    const captured = try collector_route_capture.captureReadResult(gpa, db, route, request, result, options, null);
    defer captured.deinit(gpa);
    return try app_provider_route_capture_result.captureMetadataJson(gpa, route, .{
        .endpoint = captured.endpoint,
        .snapshot_id = captured.snapshot_id,
        .kind = options.kind orelse route.operation_id orelse route.path_template,
        .target = options.target orelse captured.endpoint,
        .normalized_resources = captured.normalized_resources,
        .typed_rows = captured.typed_rows,
        .read = result.view(),
    });
}

pub fn paginatedReadMetadataJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    var pages = try collector_route_capture.readPaginatedRoute(io, gpa, db, auth, route, request, options);
    defer pages.deinit(gpa);
    const views = try capturedPageViews(gpa, pages.items);
    defer gpa.free(views);
    return try app_provider_route_capture_result.paginatedCaptureMetadataJson(gpa, route, views, pages.max_pages);
}

pub fn callReadRouteResultRequest(io: Io, gpa: Allocator, auth: Auth, route: provider_routes.Route, request: Request, options: CaptureOptions) !provider_route_result.ReadRouteResult {
    return try collector_route_capture.callReadRouteResultRequest(io, gpa, auth, route, request, options);
}

pub fn routeSupportsPageQuery(route: provider_routes.Route) bool {
    return provider_capabilities.routePaginationKind(route) == .page;
}

pub fn routeSupportsCursorQuery(route: provider_routes.Route) bool {
    return provider_capabilities.routePaginationKind(route) == .cursor;
}

fn capturedPageViews(gpa: Allocator, pages: []const CapturedRoutePage) ![]CapturedPageView {
    const views = try gpa.alloc(CapturedPageView, pages.len);
    for (pages, 0..) |page, index| {
        views[index] = capturedPageView(page);
    }
    return views;
}

fn capturedPageView(page: CapturedRoutePage) CapturedPageView {
    return .{
        .page = page.page,
        .endpoint = page.endpoint,
        .snapshot_id = page.snapshot_id,
        .http_status = page.http_status,
        .status_text = page.status_text,
        .body_bytes = page.body_bytes,
        .normalized_resources = page.normalized_resources,
        .typed_rows = page.typed_rows,
        .pagination_envelope = if (page.pagination_envelope) |envelope| envelope.name() else null,
        .data_len = page.data_len,
        .has_next = page.has_next,
    };
}
