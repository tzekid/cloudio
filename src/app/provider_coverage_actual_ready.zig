const std = @import("std");
const app_provider_coverage_actual_commands = @import("app_provider_coverage_actual_commands");
const app_provider_coverage_actual_inputs = @import("app_provider_coverage_actual_inputs");
const app_provider_coverage_actual_plan = @import("app_provider_coverage_actual_plan");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const app_provider_route_capture = @import("app_provider_route_capture");
const db_store = @import("db_store");
const provider_auth = @import("provider_auth");
const provider_capabilities = @import("provider_capabilities");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

const default_capture_max_pages = 25;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const PathParam = provider_routes.PathParam;
pub const QueryParam = provider_routes.QueryParam;
pub const Request = provider_routes.Request;
pub const Auth = provider_auth.Auth;
pub const CaptureOptions = app_provider_route_capture.CaptureOptions;

const ActualCaptureState = app_provider_coverage_actual_inputs.CaptureState;
const ActualCaptureHints = app_provider_coverage_actual_inputs.Hints;
const ActualCaptureFocus = app_provider_coverage_actual_plan.ActualCaptureFocus;
const ActualCapturePlan = app_provider_coverage_actual_plan.ActualCapturePlan;
const ActualCaptureCandidateRank = app_provider_coverage_actual_plan.ActualCaptureCandidateRank;
const loadActualCapturePlanFromFiles = app_provider_coverage_actual_plan.loadActualCapturePlanFromFiles;
const loadActualCapturePlanFromText = app_provider_coverage_actual_plan.loadActualCapturePlanFromText;
const actualCaptureRouteFilter = app_provider_coverage_actual_inputs.actualCaptureRouteFilter;
const actualCaptureReadyWithPolicy = app_provider_coverage_actual_inputs.actualCaptureReadyWithPolicy;
const actualCaptureUsesDiagnosticRead = app_provider_coverage_actual_inputs.actualCaptureUsesDiagnosticRead;
const actualCapturePathParamHint = app_provider_coverage_actual_inputs.actualCapturePathParamHint;
const actualCaptureQueryParamHint = app_provider_coverage_actual_inputs.actualCaptureQueryParamHint;
const actualCaptureCommand = app_provider_coverage_actual_commands.actualCaptureCommand;

pub const ActualReadyCaptureOptions = struct {
    filter: RouteFilter = .{},
    focus: ActualCaptureFocus = .all,
    limit: usize = 25,
    max_pages: usize = default_capture_max_pages,
    execute: bool = false,
    include_blocked: bool = false,
    diagnostic_only: bool = false,
    configured_domains: []const []const u8 = &.{},
};

const ActualReadyCaptureSummary = struct {
    candidate_routes: usize = 0,
    ready_routes: usize = 0,
    skipped_unready: usize = 0,
    skipped_non_diagnostic: usize = 0,
    omitted_ready: usize = 0,
    planned: usize = 0,
    attempted: usize = 0,
    captured: usize = 0,
    failed: usize = 0,
};

const ActualReadyRequest = struct {
    request: Request,
    path_params: []PathParam,
    query_params: []QueryParam,
    query_values: [][]u8,

    fn deinit(self: ActualReadyRequest, gpa: Allocator) void {
        for (self.query_values) |value| gpa.free(value);
        gpa.free(self.query_values);
        gpa.free(self.query_params);
        gpa.free(self.path_params);
    }
};

pub fn actualReadyCaptureJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    try validateActualReadyCaptureProvider(auth, options.filter.provider);
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, .{
        .filter = options.filter,
        .focus = options.focus,
        .limit = 0,
        .include_plans = false,
        .configured_domains = options.configured_domains,
    });
    defer plan.deinit(gpa);
    return try actualReadyCaptureJson(io, gpa, db, auth, plan, options);
}

pub fn actualReadyCaptureJsonFromText(io: Io, gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    try validateActualReadyCaptureProvider(auth, options.filter.provider);
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, .{
        .filter = options.filter,
        .focus = options.focus,
        .limit = 0,
        .include_plans = false,
        .configured_domains = options.configured_domains,
    });
    defer plan.deinit(gpa);
    return try actualReadyCaptureJson(io, gpa, db, auth, plan, options);
}

fn validateActualReadyCaptureProvider(auth: Auth, provider: ProviderFilter) !void {
    if (provider == .all) return error.ActualReadyCaptureProviderRequired;
    if (!provider.includes(auth.provider().name())) return error.ProviderRouteAuthMismatch;
}

fn actualReadyCaptureJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, plan: ActualCapturePlan, options: ActualReadyCaptureOptions) ![]u8 {
    const hints = plan.hints();
    var order = try plan.candidateOrder(gpa);
    defer order.deinit(gpa);
    var summary = ActualReadyCaptureSummary{};
    var items_out = std.Io.Writer.Allocating.init(gpa);
    defer items_out.deinit();
    const items_writer = &items_out.writer;
    try items_writer.writeByte('[');
    var first = true;

    for (order.items) |rank| {
        const row = plan.routes.items[rank.route_index];
        const state = rank.state;
        summary.candidate_routes += 1;
        if (!actualCaptureReadyWithPolicy(row.route, hints, options.include_blocked)) {
            summary.skipped_unready += 1;
            continue;
        }
        summary.ready_routes += 1;
        if (options.diagnostic_only and !actualCaptureUsesDiagnosticRead(row.route, options.include_blocked)) {
            summary.skipped_non_diagnostic += 1;
            continue;
        }
        if (options.limit != 0 and summary.planned + summary.attempted >= options.limit) {
            summary.omitted_ready += 1;
            continue;
        }
        try writeMaybeJsonComma(items_writer, &first);
        if (options.execute) {
            summary.attempted += 1;
        } else {
            summary.planned += 1;
        }
        try writeActualReadyCaptureItemJson(io, gpa, db, auth, row.route, state, rank, hints, options, &summary, items_writer);
    }

    try items_writer.writeByte(']');
    const items_json = try items_out.toOwnedSlice();
    defer gpa.free(items_json);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "actual_ready_capture_run", true);
    try writeJsonBoolField(writer, "execute", options.execute, true);
    try writeJsonBoolField(writer, "include_blocked", options.include_blocked, true);
    try writeJsonBoolField(writer, "diagnostic_only", options.diagnostic_only, true);
    try writeJsonField(writer, "focus", options.focus.name(), true);
    try writer.writeAll("\"filter\":");
    try app_provider_coverage_routes.writeRouteFilterJson(actualCaptureRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonCountField(writer, "max_pages", options.max_pages, true);
    try writer.writeAll("\"summary\":");
    try writeActualReadyCaptureSummaryJson(summary, writer);
    try writer.writeAll(",\"items\":");
    try writer.writeAll(items_json);
    try writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn writeActualReadyCaptureSummaryJson(summary: ActualReadyCaptureSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "candidate_routes", summary.candidate_routes, true);
    try writeJsonCountField(writer, "ready_routes", summary.ready_routes, true);
    try writeJsonCountField(writer, "skipped_unready", summary.skipped_unready, true);
    try writeJsonCountField(writer, "skipped_non_diagnostic", summary.skipped_non_diagnostic, true);
    try writeJsonCountField(writer, "omitted_ready", summary.omitted_ready, true);
    try writeJsonCountField(writer, "planned", summary.planned, true);
    try writeJsonCountField(writer, "attempted", summary.attempted, true);
    try writeJsonCountField(writer, "captured", summary.captured, true);
    try writeJsonCountField(writer, "failed", summary.failed, false);
    try writer.writeByte('}');
}

fn writeActualReadyCaptureItemJson(
    io: Io,
    gpa: Allocator,
    db: *Db,
    auth: Auth,
    route: provider_routes.Route,
    state: ActualCaptureState,
    rank: ActualCaptureCandidateRank,
    hints: ActualCaptureHints,
    options: ActualReadyCaptureOptions,
    summary: *ActualReadyCaptureSummary,
    writer: anytype,
) !void {
    const command = try actualCaptureCommand(gpa, route, hints);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (rank.focus_family) |family| family.name() else null, true);
    try writeJsonCountField(writer, "family_priority", rank.familyPriority(), true);
    try writeJsonCountField(writer, "family_candidate_routes", rank.family_candidate_routes, true);
    try writeJsonCountField(writer, "family_ready_candidates", rank.family_ready_candidates, true);
    try writeJsonCountField(writer, "family_pending_read_gaps", rank.family_pending_read_gaps, true);
    try writeJsonCountField(writer, "family_missing_tests", rank.family_missing_tests, true);
    try writeJsonField(writer, "operation_id", route.operation_id orelse route.path_template, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonField(writer, "actual_state", state.name(), true);
    try writeJsonNullableStringField(writer, "pagination", routePaginationKind(route), true);
    try writeJsonBoolField(writer, "live_read_supported", provider_capabilities.routeLiveReadSupported(route), true);
    try writeJsonBoolField(writer, "diagnostic_read", actualCaptureUsesDiagnosticRead(route, options.include_blocked), true);
    try writeJsonField(writer, "capture_command", command, true);
    if (!options.execute) {
        try writeJsonField(writer, "status", "planned", false);
        try writer.writeByte('}');
        return;
    }

    const result_json = actualReadyCaptureRouteJson(io, gpa, db, auth, route, hints, options) catch |err| {
        summary.failed += 1;
        try writeJsonField(writer, "status", "error", true);
        try writeJsonField(writer, "error", @errorName(err), false);
        try writer.writeByte('}');
        return;
    };
    defer gpa.free(result_json);
    summary.captured += 1;
    try writeJsonField(writer, "status", "captured", true);
    try writer.writeAll("\"capture_result\":");
    try writer.writeAll(result_json);
    try writer.writeByte('}');
}

fn actualReadyCaptureRouteJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, route: provider_routes.Route, hints: ActualCaptureHints, options: ActualReadyCaptureOptions) ![]u8 {
    if (!actualCaptureReadyWithPolicy(route, hints, options.include_blocked)) return error.ActualCaptureRouteNotReady;
    const owned_request = try actualReadyCaptureRequest(gpa, route, hints);
    defer owned_request.deinit(gpa);
    const client = provider_dispatch.Client.init(auth);
    const capture_options = CaptureOptions{
        .paginate = routePaginationKind(route) != null,
        .max_pages = options.max_pages,
        .diagnostic_read = actualCaptureUsesDiagnosticRead(route, options.include_blocked),
    };
    return try app_provider_route_capture.readRouteMetadataJson(io, gpa, db, client, route, owned_request.request, capture_options);
}

fn actualReadyCaptureRequest(gpa: Allocator, route: provider_routes.Route, hints: ActualCaptureHints) !ActualReadyRequest {
    var path_params = std.ArrayList(PathParam).empty;
    errdefer path_params.deinit(gpa);
    for (route.path_params) |param| {
        if (!param.required) continue;
        const value = actualCapturePathParamHint(route, param.name, hints) orelse return error.ActualCaptureRouteNotReady;
        try path_params.append(gpa, .{ .name = param.name, .value = value });
    }
    var query_params = std.ArrayList(QueryParam).empty;
    errdefer query_params.deinit(gpa);
    var query_values = std.ArrayList([]u8).empty;
    errdefer {
        for (query_values.items) |value| gpa.free(value);
        query_values.deinit(gpa);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        const value = (try actualCaptureQueryParamHint(gpa, route, param.name, hints)) orelse return error.ActualCaptureRouteNotReady;
        try query_values.append(gpa, value);
        try query_params.append(gpa, .{ .name = param.name, .value = value });
    }
    const owned_path_params = try path_params.toOwnedSlice(gpa);
    errdefer gpa.free(owned_path_params);
    const owned_query_params = try query_params.toOwnedSlice(gpa);
    errdefer gpa.free(owned_query_params);
    const owned_query_values = try query_values.toOwnedSlice(gpa);
    return .{
        .request = .{
            .path_params = owned_path_params,
            .query_params = owned_query_params,
            .header_params = &.{},
            .body = .{},
        },
        .path_params = owned_path_params,
        .query_params = owned_query_params,
        .query_values = owned_query_values,
    };
}

fn routePaginationKind(route: provider_routes.Route) ?[]const u8 {
    return provider_capabilities.routePaginationName(route);
}
