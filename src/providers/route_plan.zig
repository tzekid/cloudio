const std = @import("std");
const core_json = @import("core_json");
const provider_capabilities = @import("provider_capabilities");
const provider_request_plan = @import("provider_request_plan");
const provider_route_safety = @import("provider_route_safety");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

pub fn dryRunPlanJson(gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
    return try dryRunPlanJsonWithQuery(gpa, route, params, &.{});
}

pub fn dryRunPlanJsonWithQuery(gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
    return try dryRunPlanJsonRequest(gpa, route, .{ .path_params = path_params, .query_params = query_params });
}

pub fn planRouteJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    var plan = try provider_request_plan.planRouteRequest(gpa, route, request);
    defer plan.deinit(gpa);
    return try requestPlanJson(gpa, plan);
}

pub fn dryRunPlanJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    return try dryRunPlanJsonRequestWithBase(gpa, route, request, null);
}

pub fn dryRunPlanJsonRequestWithBase(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, base_url_override: ?[]const u8) ![]u8 {
    var plan = try provider_request_plan.planDryRunMutationRequestWithBase(gpa, route, request, base_url_override);
    defer plan.deinit(gpa);
    return try requestPlanJson(gpa, plan);
}

pub fn requestPlanJson(gpa: Allocator, plan: provider_request_plan.RequestPlan) ![]u8 {
    const route = plan.route;
    const request = plan.request;
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "group", route.tag, true);
    try writeJsonField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try writeJsonField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path", plan.path, true);
    try writeJsonField(writer, "url", plan.url, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeSecurityField(writer, "security", route, true);
    try writeDispatchField(writer, "dispatch", route, true);
    try writeRouteParamShapeField(writer, "path_param_shapes", route.path_params, true);
    try writeRouteParamShapeField(writer, "query_param_shapes", route.query_params, true);
    try writeRouteParamShapeField(writer, "header_param_shapes", route.header_params, true);
    try writeRouteParamField(writer, "header_params", route.header_params, true);
    try writeHeaderInputField(writer, "header_params_input", request.header_params, true);
    try writeRequestBodyField(writer, "request_body", route.request_body, true);
    try writeRequestBodyInputField(writer, "request_body_input", route.request_body, request.body, true);
    try writeResponsesField(writer, "responses", route.responses, true);
    try writeJsonField(writer, "mode", plan.mode.name(), true);
    try writer.writeAll("\"will_execute\":");
    try writer.writeAll(if (plan.will_execute) "true," else "false,");
    try provider_route_safety.writeRouteSafetyPolicyJson(writer, "safety_policy", route, plan.safety_kind, true);
    try writeJsonField(writer, "safety", plan.safety, false);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn writeRequestBodyField(writer: anytype, name: []const u8, body: provider_routes.RequestBody, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":{");
    try writer.writeAll("\"required\":");
    try writer.writeAll(if (body.required) "true" else "false");
    try writer.writeByte(',');
    try writeStringArrayField(writer, "content_types", body.content_types, true);
    try writeStringArrayField(writer, "schema_refs", body.schema_refs, false);
    try writer.writeByte('}');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeRouteParamField(writer: anytype, name: []const u8, params: []const provider_routes.RouteParam, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "name", param.name, true);
        try writer.writeAll("\"required\":");
        try writer.writeAll(if (param.required) "true" else "false");
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeSecurityField(writer: anytype, name: []const u8, route: provider_routes.Route, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":{");
    try writer.writeAll("\"required\":");
    try writer.writeAll(if (route.security.required) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"cloudio_supported\":");
    try writer.writeAll(if (provider_capabilities.cloudioSupportsRouteAuth(route)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"alternatives\":[");
    for (route.security.alternatives, 0..) |alternative, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('[');
        for (alternative.schemes, 0..) |scheme, scheme_index| {
            if (scheme_index != 0) try writer.writeByte(',');
            try core_json.writeString(writer, scheme);
        }
        try writer.writeByte(']');
    }
    try writer.writeAll("]}");
    if (trailing_comma) try writer.writeByte(',');
}

fn writeDispatchField(writer: anytype, name: []const u8, route: provider_routes.Route, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":{");
    try writer.writeAll("\"live_call_supported\":");
    try writer.writeAll(if (provider_capabilities.routeLiveReadSupported(route)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"diagnostic_read_supported\":");
    try writer.writeAll(if (provider_capabilities.routeDiagnosticReadSupported(route)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"dry_run_supported\":");
    try writer.writeAll(if (provider_capabilities.routeDryRunSupported(route)) "true" else "false");
    try writer.writeByte('}');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeRouteParamShapeField(writer: anytype, name: []const u8, params: []const provider_routes.RouteParam, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "name", param.name, true);
        try writer.writeAll("\"required\":");
        try writer.writeAll(if (param.required) "true" else "false");
        try writer.writeByte(',');
        if (param.style) |style| {
            try writeJsonField(writer, "style", style, true);
        } else {
            try writer.writeAll("\"style\":null,");
        }
        if (param.explode) |explode| {
            try writer.writeAll("\"explode\":");
            try writer.writeAll(if (explode) "true" else "false");
            try writer.writeByte(',');
        } else {
            try writer.writeAll("\"explode\":null,");
        }
        try writer.writeAll("\"schema\":{");
        try writeStringArrayField(writer, "schema_refs", param.schema.schema_refs, true);
        try writeStringArrayField(writer, "types", param.schema.types, true);
        try writeStringArrayField(writer, "formats", param.schema.formats, true);
        try writeStringArrayField(writer, "enum_values", param.schema.enum_values, false);
        try writer.writeAll("}}");
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeHeaderInputField(writer: anytype, name: []const u8, params: []const provider_routes.HeaderParam, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "name", param.name, true);
        try writer.writeAll("\"provided\":true}");
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeRequestBodyInputField(writer: anytype, name: []const u8, body: provider_routes.RequestBody, input: provider_routes.BodyInput, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":{");
    try writer.writeAll("\"present\":");
    try writer.writeAll(if (input.present) "true" else "false");
    try writer.writeByte(',');
    if (input.content_type) |content_type| {
        try writeJsonField(writer, "content_type", content_type, true);
    } else {
        try writer.writeAll("\"content_type\":null,");
    }
    try writer.writeAll("\"required_missing\":");
    try writer.writeAll(if (body.required and !input.present) "true" else "false");
    try writer.writeByte('}');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeResponsesField(writer: anytype, name: []const u8, responses: []const provider_routes.Response, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (responses, 0..) |response, index| {
        if (index != 0) try writer.writeByte(',');
        try writeResponseValue(writer, response);
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
}

fn writeResponseValue(writer: anytype, response: provider_routes.Response) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "status", response.status, true);
    try writeStringArrayField(writer, "content_types", response.content_types, true);
    try writeStringArrayField(writer, "schema_refs", response.schema_refs, false);
    try writer.writeByte('}');
}

fn writeStringArrayField(writer: anytype, name: []const u8, values: []const []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try core_json.writeString(writer, value);
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
}

test "plans bodyless read routes without executing HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteJsonRequest(
        allocator,
        route,
        .{
            .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
            .query_params = &.{
                .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
            },
        },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mode\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"safety_policy\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"execution\":\"plan_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_policy\":\"no_live_mutations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"live_provider_request\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mutation\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_blocked\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"dry_run_only\":false") != null);
}

test "keeps mutation plans dry-run only" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteJsonRequest(
        allocator,
        route,
        .{
            .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
            .query_params = &.{.{ .name = "base64", .value = "true" }},
            .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" },
        },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"worker-assets-upload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mode\":\"dry_run\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"safety_policy\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"execution\":\"dry_run_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_policy\":\"no_live_mutations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"live_provider_request\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mutation\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"write_blocked\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"dry_run_only\":true") != null);
}
