const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const core_json = @import("core_json");
const provider_capabilities = @import("provider_capabilities");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeJsonStringArray = app_provider_coverage_render.writeJsonStringArray;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

pub const Paths = provider_routes.Paths;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;

pub const CaptureCandidateOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
};

pub const DryRunCandidateOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
};

pub fn writeCaptureCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesJson(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesJson(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesJson(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesJson(gpa, routes.items, options, writer);
}

pub fn loadCaptureCandidateRoutes(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions) !CoverageRoutes {
    const filter = captureCandidateRouteFilter(options.filter);
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, filter);
}

pub fn loadCaptureCandidateRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions) !CoverageRoutes {
    const filter = captureCandidateRouteFilter(options.filter);
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn loadDryRunCandidateRoutes(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions) !CoverageRoutes {
    const filter = dryRunCandidateRouteFilter(options.filter);
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, filter);
}

pub fn loadDryRunCandidateRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions) !CoverageRoutes {
    const filter = dryRunCandidateRouteFilter(options.filter);
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn captureCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

pub fn dryRunCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.mode = .dry_run;
    if (next.support == null) next.support = .unsafe_mutation;
    next.detail = false;
    return next;
}

pub fn isCaptureCandidate(row: CoverageRoute, options: CaptureCandidateOptions) bool {
    const route = row.route;
    if (route.deprecated or !route.isRoutable()) return false;
    if (route.method != .GET or route.mode != .read) return false;
    if (route.request_body.required) return false;
    if (!std.mem.eql(u8, row.tests, "missing")) return false;
    if (options.filter.support != null) return true;
    return route.support == .planned or route.support == .blocked_permission;
}

pub fn isDryRunCandidate(row: CoverageRoute, options: DryRunCandidateOptions) bool {
    const route = row.route;
    if (route.deprecated or !route.isRoutable()) return false;
    if (!route.isDryRunMutation()) return false;
    if (!std.mem.eql(u8, row.tests, "missing")) return false;
    if (hasGeneratedDryRunPolicyEvidence(row)) return false;
    if (options.filter.support != null) return true;
    return route.support == .unsafe_mutation;
}

pub fn hasGeneratedDryRunPolicyEvidence(row: CoverageRoute) bool {
    const route = row.route;
    if (!std.mem.eql(u8, route.provider.name(), "cloudflare")) return false;
    if (route.deprecated or !route.isRoutable()) return false;
    if (!route.isDryRunMutation()) return false;
    if (route.support != .unsafe_mutation) return false;
    return true;
}

pub fn writeCaptureCandidatesText(gpa: Allocator, routes: []const CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try writer.writeAll("Cloudio route capture candidates\n");
    try writer.writeAll("rank: generated bodyless GET/read routes missing L2 capture evidence\n");
    try writer.print("filter provider={s}", .{options.filter.provider.name()});
    if (options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
    if (options.filter.family != .all) try writer.print(" family={s}", .{options.filter.family.name()});
    if (options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
    if (options.include_plans) try writer.writeAll(" plans=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var current_provider: ?[]const u8 = null;
    var current_tag: ?[]const u8 = null;
    for (routes) |row| {
        if (!isCaptureCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.route.provider.name())) {
            current_provider = row.route.provider.name();
            current_tag = null;
            try writer.print("\n{s}\n", .{row.route.provider.name()});
        }
        if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
            current_tag = row.route.tag;
            try writer.print("  {s}\n", .{row.route.tag});
        }
        try writer.print("    {s} {s} | support={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support) });
        if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
        try writer.writeByte('\n');
        try writer.writeAll("      required_path=");
        try writeRequiredParamNamesText(writer, row.route.path_params);
        try writer.writeAll(" required_query=");
        try writeRequiredParamNamesText(writer, row.route.query_params);
        try writer.writeAll(" required_header=");
        try writeRequiredParamNamesText(writer, row.route.header_params);
        try writer.print(" pagination={s}\n", .{paginationKind(row.route) orelse "none"});
        const command = try captureCommand(gpa, row.route);
        defer gpa.free(command);
        try writer.print("      capture: {s}\n", .{command});
        if (options.include_plans) {
            const plan = try readPlanJson(gpa, row.route);
            defer gpa.free(plan);
            try writer.print("      read-plan: {s}\n", .{plan});
        }
    }

    if (total == 0) {
        try writer.writeAll("no capture candidates for filter\n");
    } else if (omitted != 0) {
        try writer.print("omitted={d}\n", .{omitted});
    }
}

pub fn writeCaptureCandidatesJson(gpa: Allocator, routes: []const CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_capture_candidates", true);
    try writer.writeAll("\"filter\":");
    try app_provider_coverage_routes.writeRouteFilterJson(captureCandidateRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeJsonField(writer, "rank", "generated bodyless GET/read routes missing L2 capture evidence", true);
    try writer.writeAll("\"candidates\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var first = true;
    for (routes) |row| {
        if (!isCaptureCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeCaptureCandidateJson(gpa, row, options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "total_candidates", total, true);
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

pub fn writeDryRunCandidatesText(gpa: Allocator, routes: []const CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try writer.writeAll("Cloudio route dry-run candidates\n");
    try writer.writeAll("rank: generated mutation routes missing dry-run review evidence\n");
    try writer.print("filter provider={s}", .{options.filter.provider.name()});
    if (options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
    if (options.filter.family != .all) try writer.print(" family={s}", .{options.filter.family.name()});
    if (options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
    if (options.include_plans) try writer.writeAll(" plans=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var current_provider: ?[]const u8 = null;
    var current_tag: ?[]const u8 = null;
    for (routes) |row| {
        if (!isDryRunCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.route.provider.name())) {
            current_provider = row.route.provider.name();
            current_tag = null;
            try writer.print("\n{s}\n", .{row.route.provider.name()});
        }
        if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
            current_tag = row.route.tag;
            try writer.print("  {s}\n", .{row.route.tag});
        }
        try writer.print("    {s} {s} | support={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support) });
        if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
        try writer.writeByte('\n');
        try writer.writeAll("      required_path=");
        try writeRequiredParamNamesText(writer, row.route.path_params);
        try writer.writeAll(" required_query=");
        try writeRequiredParamNamesText(writer, row.route.query_params);
        try writer.writeAll(" required_header=");
        try writeRequiredParamNamesText(writer, row.route.header_params);
        try writer.print(" body_required={}", .{row.route.request_body.required});
        try writer.print(" body_content_type={s}", .{primaryRequestBodyContentType(row.route.request_body) orelse "none"});
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, row.route.request_body.schema_refs);
        try writer.writeByte('\n');
        const command = try dryRunCommand(gpa, row.route);
        defer gpa.free(command);
        try writer.print("      dry-run: {s}\n", .{command});
        if (options.include_plans) {
            const plan = try dryRunPlanJson(gpa, row.route);
            defer gpa.free(plan);
            try writer.print("      dry-run-plan: {s}\n", .{plan});
        }
    }

    if (total == 0) {
        try writer.writeAll("no dry-run candidates for filter\n");
    } else if (omitted != 0) {
        try writer.print("omitted={d}\n", .{omitted});
    }
}

pub fn writeDryRunCandidatesJson(gpa: Allocator, routes: []const CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_dry_run_candidates", true);
    try writer.writeAll("\"filter\":");
    try app_provider_coverage_routes.writeRouteFilterJson(dryRunCandidateRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeJsonField(writer, "rank", "generated mutation routes missing dry-run review evidence", true);
    try writer.writeAll("\"candidates\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var first = true;
    for (routes) |row| {
        if (!isDryRunCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeDryRunCandidateJson(gpa, row, options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "total_candidates", total, true);
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

pub fn writeDryRunCandidateJson(gpa: Allocator, row: CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    const route = row.route;
    const command = try dryRunCommand(gpa, route);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "tests", row.tests, true);
    try writer.writeAll("\"required_path_params\":");
    try writeRequiredParamNamesJson(writer, route.path_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_query_params\":");
    try writeRequiredParamNamesJson(writer, route.query_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_header_params\":");
    try writeRequiredParamNamesJson(writer, route.header_params);
    try writer.writeByte(',');
    try writeJsonBoolField(writer, "body_required", route.request_body.required, true);
    try writeJsonNullableStringField(writer, "body_content_type", primaryRequestBodyContentType(route.request_body), true);
    try writer.writeAll("\"request_body_schema_refs\":");
    try writeJsonStringArray(writer, route.request_body.schema_refs);
    try writer.writeByte(',');
    try writeJsonField(writer, "dry_run_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try dryRunPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"dry_run_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

pub fn writeCaptureCandidateJson(gpa: Allocator, row: CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    const route = row.route;
    const command = try captureCommand(gpa, route);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "tests", row.tests, true);
    try writeJsonNullableStringField(writer, "pagination", paginationKind(route), true);
    try writer.writeAll("\"required_path_params\":");
    try writeRequiredParamNamesJson(writer, route.path_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_query_params\":");
    try writeRequiredParamNamesJson(writer, route.query_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_header_params\":");
    try writeRequiredParamNamesJson(writer, route.header_params);
    try writer.writeByte(',');
    try writeJsonField(writer, "capture_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try readPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"read_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

pub fn dryRunPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    const example = try route.exampleRequest(gpa);
    defer example.deinit(gpa);
    return try provider_dispatch.dryRunPlanJsonRequest(gpa, route, example.request);
}

pub fn readPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    const example = try route.exampleRequest(gpa);
    defer example.deinit(gpa);
    return try provider_dispatch.planRouteJsonRequest(gpa, route, example.request);
}

pub fn captureCommand(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route capture {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path {s}", .{ route.method.name(), route.path_template });
    }
    try writeRequiredParamPlaceholders(writer, "--path-param", route.path_params);
    try writeRequiredParamPlaceholders(writer, "--query-param", route.query_params);
    try writeRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (paginationKind(route) != null) try writer.writeAll(" --paginate");
    return try out.toOwnedSlice();
}

pub fn dryRunCommand(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route dry-run {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path {s}", .{ route.method.name(), route.path_template });
    }
    try writeRequiredParamPlaceholders(writer, "--path-param", route.path_params);
    try writeRequiredParamPlaceholders(writer, "--query-param", route.query_params);
    try writeRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (primaryRequestBodyContentType(route.request_body)) |content_type| {
        try writer.print(" --body-content-type {s}", .{content_type});
    }
    return try out.toOwnedSlice();
}

pub fn primaryRequestBodyContentType(body: provider_routes.RequestBody) ?[]const u8 {
    if (body.content_types.len == 0) return null;
    return body.content_types[0];
}

pub fn paginationKind(route: provider_routes.Route) ?[]const u8 {
    return provider_capabilities.routePaginationName(route);
}

fn writeRequiredParamPlaceholders(writer: anytype, option: []const u8, params: []const provider_routes.RouteParam) !void {
    for (params) |param| {
        if (!param.required) continue;
        try writer.print(" {s} {s}=<{s}>", .{ option, param.name, param.name });
    }
}

fn writeRequiredParamNamesText(writer: anytype, params: []const provider_routes.RouteParam) !void {
    var wrote = false;
    for (params) |param| {
        if (!param.required) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.writeAll(param.name);
    }
    if (!wrote) try writer.writeAll("-");
}

fn writeRequiredParamNamesJson(writer: anytype, params: []const provider_routes.RouteParam) !void {
    try writer.writeByte('[');
    var first = true;
    for (params) |param| {
        if (!param.required) continue;
        try writeMaybeJsonComma(writer, &first);
        try core_json.writeString(writer, param.name);
    }
    try writer.writeByte(']');
}

fn writeStringList(writer: anytype, values: anytype) !void {
    if (values.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(value);
    }
}

test "renders capture candidates with read plans and pagination" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records for a Zone","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true}],"query_params":[{"name":"page","required":false}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"candidate"}
        \\{"provider":"cloudflare","tag":"DNS Records for a Zone","method":"GET","path":"/zones/{zone_id}/dns_records/{id}","operation_id":"dns-record-detail","path_params":[{"name":"zone_id","required":true},{"name":"id","required":true}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"done"}
        \\
    ;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, "", .{
        .filter = .{ .provider = .cloudflare },
        .include_plans = true,
    }, &out.writer);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_capture_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "--paginate") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"read_plan\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "dns-record-detail") == null);
}

test "renders dry-run candidates and suppresses generated Cloudflare policy evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records for a Zone","method":"DELETE","path":"/zones/{zone_id}/dns_records/{id}","operation_id":"dns-record-delete","path_params":[{"name":"zone_id","required":true},{"name":"id","required":true}],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated evidence"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"candidate"}
        \\
    ;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{ .include_plans = true }, &out.writer);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_dry_run_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "VPS_purchaseNewVirtualMachineV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "dns-record-delete") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_plan\"") != null);
}
