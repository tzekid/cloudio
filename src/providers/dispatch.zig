const std = @import("std");
const core_json = @import("core_json");
const net_http = @import("net_http");
const provider_capabilities = @import("provider_capabilities");
const provider_cloudflare = @import("provider_cloudflare");
const provider_hostinger = @import("provider_hostinger");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Auth = union(enum) {
    cloudflare: provider_cloudflare.Auth,
    hostinger: []const u8,

    pub fn provider(self: Auth) provider_routes.Provider {
        return switch (self) {
            .cloudflare => .cloudflare,
            .hostinger => .hostinger,
        };
    }
};

pub const Client = struct {
    auth: Auth,
    cloudflare_base_url_override: []const u8 = provider_routes.cloudflare_base_url,
    hostinger_base_url_override: []const u8 = provider_routes.hostinger_base_url,

    pub fn init(auth: Auth) Client {
        return .{ .auth = auth };
    }

    pub fn provider(self: Client) provider_routes.Provider {
        return self.auth.provider();
    }

    pub fn callReadRoute(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) !net_http.Response {
        return try self.callReadRouteWithQuery(io, gpa, route, params, &.{});
    }

    pub fn callReadRouteWithQuery(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) !net_http.Response {
        return try self.callReadRouteRequest(io, gpa, route, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn callReadRouteRequest(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !net_http.Response {
        return try self.callReadRouteRequestWithPolicy(io, gpa, route, request, false);
    }

    pub fn callDiagnosticReadRouteRequest(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !net_http.Response {
        return try self.callReadRouteRequestWithPolicy(io, gpa, route, request, true);
    }

    fn callReadRouteRequestWithPolicy(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, include_blocked_diagnostic: bool) !net_http.Response {
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        if (!route.isRoutable()) return error.UnsupportedProviderRoute;
        if (route.method != .GET or route.mode != .read) return error.ProviderRouteRequiresDryRun;
        if (!provider_capabilities.routeLiveReadSupported(route) and !(include_blocked_diagnostic and provider_capabilities.routeDiagnosticReadSupported(route))) return error.UnsupportedProviderRoute;
        if (request.body.present or request.body.content_type != null) return error.ProviderReadRouteIsBodyless;
        try route.validateRequestHeaders(request);
        try validateRouteAuth(route, self.auth);

        const url = try route.renderRequestUrl(gpa, self.baseUrl(route.provider), request);
        defer gpa.free(url);
        const headers = try requestHeaders(gpa, request.header_params);
        defer gpa.free(headers);
        return switch (self.auth) {
            .cloudflare => |auth| {
                const cloudflare = provider_cloudflare.Client{
                    .auth = auth,
                    .base_url_override = self.cloudflare_base_url_override,
                };
                if (!route.security.required) {
                    return try cloudflare.getPublicWithHeaders(io, gpa, url, headers);
                }
                return try cloudflare.getWithHeaders(io, gpa, url, headers);
            },
            .hostinger => |token| try (provider_hostinger.Client{
                .token = token,
                .base_url_override = self.hostinger_base_url_override,
            }).getWithHeaders(io, gpa, url, headers),
        };
    }

    pub fn callReadRouteResult(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) !ReadRouteResult {
        return try self.callReadRouteResultWithQuery(io, gpa, route, params, &.{});
    }

    pub fn callReadRouteResultWithQuery(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) !ReadRouteResult {
        return try self.callReadRouteResultRequest(io, gpa, route, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn callReadRouteResultRequest(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !ReadRouteResult {
        const response = try self.callReadRouteRequest(io, gpa, route, request);
        return matchReadRouteResponse(route, response);
    }

    pub fn callDiagnosticReadRouteResultRequest(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !ReadRouteResult {
        const response = try self.callDiagnosticReadRouteRequest(io, gpa, route, request);
        return matchReadRouteResponse(route, response);
    }

    pub fn dryRunRoute(self: Client, gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
        return try self.dryRunRouteWithQuery(gpa, route, params, &.{});
    }

    pub fn dryRunRouteWithQuery(self: Client, gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
        return try self.dryRunRouteRequest(gpa, route, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn dryRunRouteRequest(self: Client, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        return try dryRunPlanJsonRequestWithBase(gpa, route, request, self.baseUrl(route.provider));
    }

    fn baseUrl(self: Client, target_provider: provider_routes.Provider) ?[]const u8 {
        return switch (target_provider) {
            .cloudflare => self.cloudflare_base_url_override,
            .hostinger => self.hostinger_base_url_override,
        };
    }
};

pub const ReadRouteResult = struct {
    response: net_http.Response,
    matched_response: ?*const provider_routes.Response,

    pub fn deinit(self: ReadRouteResult, gpa: Allocator) void {
        self.response.deinit(gpa);
    }

    pub fn statusCode(self: ReadRouteResult) u16 {
        return @intFromEnum(self.response.status);
    }

    pub fn statusText(self: ReadRouteResult) []const u8 {
        return net_http.statusText(self.response.status);
    }
};

pub fn matchReadRouteResponse(route: provider_routes.Route, response: net_http.Response) ReadRouteResult {
    return .{
        .response = response,
        .matched_response = route.findResponseForStatus(response.status),
    };
}

pub fn readRouteResultMetadataJson(gpa: Allocator, route: provider_routes.Route, result: ReadRouteResult) ![]u8 {
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
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writer.writeAll("\"http_status\":");
    try writer.print("{d}", .{result.statusCode()});
    try writer.writeByte(',');
    try writeJsonField(writer, "status_text", result.statusText(), true);
    if (result.matched_response) |matched| {
        try writeResponseField(writer, "matched_response", matched.*, true);
    } else {
        try writer.writeAll("\"matched_response\":null,");
    }
    try writer.writeAll("\"body_bytes\":");
    try writer.print("{d}", .{result.response.body.len});
    try writer.writeByte(',');
    try writer.writeAll("\"body_included\":false");
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

pub fn dryRunPlanJson(gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
    return try dryRunPlanJsonWithQuery(gpa, route, params, &.{});
}

pub fn dryRunPlanJsonWithQuery(gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
    return try dryRunPlanJsonRequest(gpa, route, .{ .path_params = path_params, .query_params = query_params });
}

pub fn planRouteJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.isDryRunMutation()) return try dryRunPlanJsonRequest(gpa, route, request);
    if (route.mode != .read or route.method != .GET) return error.UnsupportedProviderRoutePlan;
    if (request.body.present or request.body.content_type != null) return error.ProviderReadRouteIsBodyless;
    try route.validateRequestHeaders(request);

    const path = try route.renderRequestPath(gpa, request);
    defer gpa.free(path);
    const url = try std.fmt.allocPrint(gpa, "{s}{s}", .{ route.provider.baseUrl(), path });
    defer gpa.free(url);

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
    try writeJsonField(writer, "path", path, true);
    try writeJsonField(writer, "url", url, true);
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
    try writer.writeAll("\"mode\":\"read\",");
    try writer.writeAll("\"will_execute\":false,");
    const safety = if (routeLiveCallSupported(route))
        "No provider API request is sent. This is a generic request plan for a live read route."
    else
        "No provider API request is sent. This read route is planned for metadata review, but Cloudio will not execute it live with the current support policy.";
    try writeJsonField(writer, "safety", safety, false);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

pub fn dryRunPlanJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    return try dryRunPlanJsonRequestWithBase(gpa, route, request, null);
}

fn dryRunPlanJsonRequestWithBase(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, base_url_override: ?[]const u8) ![]u8 {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.mode != .dry_run or route.method == .GET or route.method == .HEAD) return error.ProviderRouteIsNotMutation;
    try route.validateRequestHeaders(request);
    try route.validateProvidedBodyInput(request);

    const path = try route.renderRequestPath(gpa, request);
    defer gpa.free(path);
    const url = try std.fmt.allocPrint(gpa, "{s}{s}", .{ base_url_override orelse route.provider.baseUrl(), path });
    defer gpa.free(url);

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
    try writeJsonField(writer, "path", path, true);
    try writeJsonField(writer, "url", url, true);
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
    try writer.writeAll("\"mode\":\"dry_run\",");
    try writer.writeAll("\"will_execute\":false,");
    try writeJsonField(writer, "safety", "No provider API request is sent. This is a generic dry-run plan for a live mutation route.", false);
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
    try writer.writeAll(if (cloudioSupportsRouteAuth(route)) "true" else "false");
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
    try writer.writeAll(if (routeLiveCallSupported(route)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"diagnostic_read_supported\":");
    try writer.writeAll(if (routeDiagnosticReadSupported(route)) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"dry_run_supported\":");
    try writer.writeAll(if (routeDryRunSupported(route)) "true" else "false");
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

fn requestHeaders(gpa: Allocator, params: []const provider_routes.HeaderParam) ![]std.http.Header {
    const headers = try gpa.alloc(std.http.Header, params.len);
    for (params, 0..) |param, index| {
        headers[index] = .{ .name = param.name, .value = param.value };
    }
    return headers;
}

fn validateRouteAuth(route: provider_routes.Route, auth: Auth) !void {
    if (!route.security.required) return;
    return switch (auth) {
        .cloudflare => |cloudflare_auth| validateCloudflareRouteAuth(route.security, cloudflare_auth),
        .hostinger => |token| validateHostingerRouteAuth(route.security, token),
    };
}

fn validateCloudflareRouteAuth(security: provider_routes.Security, auth: provider_cloudflare.Auth) !void {
    if (auth.hasApiToken() and provider_capabilities.cloudflareSecurityAcceptsApiToken(security)) return;
    if (hasCloudflareLegacyAuth(auth) and provider_capabilities.cloudflareSecurityAcceptsLegacyAuth(security)) return;
    if (!auth.hasApiToken() and !hasCloudflareLegacyAuth(auth)) return error.MissingCloudflareAuth;
    return error.UnsupportedRouteAuthScheme;
}

fn validateHostingerRouteAuth(security: provider_routes.Security, token: []const u8) !void {
    if (token.len == 0) return error.MissingHostingerToken;
    if (security.acceptsSchemeSet(&.{"apiToken"})) return;
    return error.UnsupportedRouteAuthScheme;
}

pub fn cloudioSupportsRouteAuth(route: provider_routes.Route) bool {
    return provider_capabilities.cloudioSupportsRouteAuth(route);
}

pub fn routeLiveCallSupported(route: provider_routes.Route) bool {
    return provider_capabilities.routeLiveReadSupported(route);
}

pub fn routeDiagnosticReadSupported(route: provider_routes.Route) bool {
    return provider_capabilities.routeDiagnosticReadSupported(route);
}

pub fn routeDryRunSupported(route: provider_routes.Route) bool {
    return provider_capabilities.routeDryRunSupported(route);
}

fn hasCloudflareLegacyAuth(auth: provider_cloudflare.Auth) bool {
    const email = auth.email orelse return false;
    const key = auth.key orelse return false;
    return email.len != 0 and key.len != 0;
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

fn writeResponseField(writer: anytype, name: []const u8, response: provider_routes.Response, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writeResponseValue(writer, response);
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

test "generic dispatch renders dry-run plans without executing mutations" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-idp-federation-grants-create")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .cloudflare = .{ .token = "test-token" } });
    const plan = try client.dryRunRoute(allocator, route, &.{.{ .name = "account_id", .value = "acct/1" }});
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"group\":\"Access IdP federation grants\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"access-idp-federation-grants-create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path\":\"/accounts/acct%2F1/access/idp_federation_grants\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://api.cloudflare.com/client/v4/accounts/acct%2F1/access/idp_federation_grants\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body\":{\"required\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body_input\":{\"present\":false,\"content_type\":null,\"required_missing\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"responses\":[{\"status\":\"201\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/access_idp_federation_grant_response\"]},{\"status\":\"4XX\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/access_api-response-common-failure\"]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch renders query-aware dry-run plans" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .cloudflare = .{ .token = "test-token" } });
    const plan = try client.dryRunRouteWithQuery(
        allocator,
        route,
        &.{.{ .name = "account_id", .value = "acct/1" }},
        &.{.{ .name = "base64", .value = "true" }},
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"worker-assets-upload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path\":\"/accounts/acct%2F1/workers/assets/upload?base64=true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://api.cloudflare.com/client/v4/accounts/acct%2F1/workers/assets/upload?base64=true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body\":{\"required\":true,\"content_types\":[\"multipart/form-data\"],\"schema_refs\":[]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"responses\":[{\"status\":\"201\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_completed-upload-assets-response\"]},{\"status\":\"202\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_upload-assets-response\"]},{\"status\":\"4XX\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_api-response-common-failure\"]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch plans bodyless read routes without executing HTTP" {
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
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"method\":\"GET\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path\":\"/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://developers.hostinger.com/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"security\":{\"required\":true,\"cloudio_supported\":true,\"alternatives\":[[\"apiToken\"]]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"dispatch\":{\"live_call_supported\":true,\"diagnostic_read_supported\":false,\"dry_run_supported\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path_param_shapes\":[{\"name\":\"virtualMachineId\",\"required\":true,\"style\":null,\"explode\":null,\"schema\":{\"schema_refs\":[],\"types\":[\"integer\"],\"formats\":[],\"enum_values\":[]}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"query_param_shapes\":[{\"name\":\"date_from\",\"required\":true,\"style\":null,\"explode\":null,\"schema\":{\"schema_refs\":[],\"types\":[\"string\"],\"formats\":[\"date-time\"],\"enum_values\":[]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mode\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch route planner keeps mutation plans dry-run only" {
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
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"security\":{\"required\":true,\"cloudio_supported\":false,\"alternatives\":[[\"assets_jwt\"]]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"dispatch\":{\"live_call_supported\":false,\"diagnostic_read_supported\":false,\"dry_run_supported\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch route planner reports anonymous security metadata" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "cloudflare-ips-cloudflare-ip-details")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteJsonRequest(allocator, route, .{});
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"cloudflare-ips-cloudflare-ip-details\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"security\":{\"required\":false,\"cloudio_supported\":true,\"alternatives\":[[]]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch recognizes Cloudflare token or legacy auth bundles" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-list-access-applications")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try validateCloudflareRouteAuth(route.security, .{ .token = "test-token" });
    try validateCloudflareRouteAuth(route.security, .{ .email = "ops@example.test", .key = "global-key" });
    try std.testing.expectError(error.MissingCloudflareAuth, validateCloudflareRouteAuth(route.security, .{}));

    const plan = try planRouteJsonRequest(
        allocator,
        route,
        .{ .path_params = &.{.{ .name = "account_id", .value = "acct" }} },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"access-applications-list-access-applications\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"security\":{\"required\":true,\"cloudio_supported\":true,\"alternatives\":[[\"api_email\",\"api_key\",\"api_token\"]]}") != null);
}

test "generic dispatch route planner uses OpenAPI query array serialization" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "d1-get-database")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteJsonRequest(
        allocator,
        route,
        .{
            .path_params = &.{
                .{ .name = "account_id", .value = "acct" },
                .{ .name = "database_id", .value = "db" },
            },
            .query_params = &.{
                .{ .name = "fields", .value = "name" },
                .{ .name = "fields", .value = "uuid" },
            },
        },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path\":\"/accounts/acct/d1/database/db?fields=name,uuid\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"query_param_shapes\":[{\"name\":\"fields\",\"required\":false,\"style\":\"form\",\"explode\":false") != null);
}

test "generic dispatch route planner validates read route request input" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try std.testing.expectError(
        error.MissingRouteQueryParameter,
        planRouteJsonRequest(
            allocator,
            route,
            .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
            },
        ),
    );
    try std.testing.expectError(
        error.ProviderReadRouteIsBodyless,
        planRouteJsonRequest(
            allocator,
            route,
            .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{
                    .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                    .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
                },
                .body = .{ .present = true, .content_type = "application/json" },
            },
        ),
    );
}

test "generic dispatch route planner validates and hides header values" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "r2-get-event-notification-configs")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteJsonRequest(
        allocator,
        route,
        .{
            .path_params = &.{
                .{ .name = "account_id", .value = "acct/1" },
                .{ .name = "bucket_name", .value = "bucket" },
            },
            .header_params = &.{.{ .name = "CF-R2-Jurisdiction", .value = "eu" }},
        },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"header_params\":[{\"name\":\"cf-r2-jurisdiction\",\"required\":false}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"header_params_input\":[{\"name\":\"CF-R2-Jurisdiction\",\"provided\":true}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"header_param_shapes\":[{\"name\":\"cf-r2-jurisdiction\",\"required\":false,\"style\":null,\"explode\":null,\"schema\":{\"schema_refs\":[\"#/components/schemas/r2_jurisdiction\"],\"types\":[\"string\"],\"formats\":[],\"enum_values\":[\"default\",\"eu\",\"fedramp\"]}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"value\":\"eu\"") == null);

    try std.testing.expectError(
        error.UnknownRouteHeaderParameter,
        planRouteJsonRequest(
            allocator,
            route,
            .{
                .path_params = &.{
                    .{ .name = "account_id", .value = "acct/1" },
                    .{ .name = "bucket_name", .value = "bucket" },
                },
                .header_params = &.{.{ .name = "x-unknown", .value = "value" }},
            },
        ),
    );
}

test "generic dispatch matches read response metadata without owning route metadata" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const ok_body = try allocator.dupe(u8, "{\"ok\":true}");
    const ok_result = matchReadRouteResponse(route, .{ .status = .ok, .body = ok_body });
    defer ok_result.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), ok_result.statusCode());
    try std.testing.expectEqualStrings("ok", ok_result.statusText());
    const ok_match = ok_result.matched_response orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("200", ok_match.status);

    const ok_json = try readRouteResultMetadataJson(allocator, route, ok_result);
    defer allocator.free(ok_json);
    try std.testing.expect(std.mem.indexOf(u8, ok_json, "\"operation_id\":\"accounts-list-accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok_json, "\"http_status\":200") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok_json, "\"matched_response\":{\"status\":\"200\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok_json, "\"body_bytes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok_json, "\"body_included\":false") != null);

    const forbidden_body = try allocator.dupe(u8, "{\"error\":true}");
    const forbidden_result = matchReadRouteResponse(route, .{ .status = .forbidden, .body = forbidden_body });
    defer forbidden_result.deinit(allocator);
    const forbidden_match = forbidden_result.matched_response orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("4XX", forbidden_match.status);
}

test "generic dispatch reports unmatched read response metadata" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const body = try allocator.dupe(u8, "{}");
    const result = matchReadRouteResponse(route, .{ .status = .not_found, .body = body });
    defer result.deinit(allocator);
    try std.testing.expect(result.matched_response == null);

    const json = try readRouteResultMetadataJson(allocator, route, result);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"http_status\":404") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status_text\":\"not_found\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"matched_response\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_bytes\":2") != null);
}

test "generic dispatch accepts route request objects" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client{
        .auth = .{ .cloudflare = .{ .token = "test-token" } },
        .cloudflare_base_url_override = "https://fixture.cloudflare.test",
    };
    const plan = try client.dryRunRouteRequest(
        allocator,
        route,
        .{
            .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
            .query_params = &.{.{ .name = "base64", .value = "true" }},
            .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" },
        },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"path\":\"/accounts/acct%2F1/workers/assets/upload?base64=true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://fixture.cloudflare.test/accounts/acct%2F1/workers/assets/upload?base64=true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body_input\":{\"present\":true,\"content_type\":\"multipart/form-data; boundary=test\",\"required_missing\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch validates request body input metadata" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try std.testing.expectError(
        error.UnsupportedRouteRequestBodyContentType,
        dryRunPlanJsonRequest(
            allocator,
            route,
            .{
                .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
                .body = .{ .present = true, .content_type = "application/json" },
            },
        ),
    );
}

test "generic dispatch reports request body schema refs in dry-run plans" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_purchaseNewVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    const plan = try client.dryRunRoute(allocator, route, &.{});
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body\":{\"required\":true,\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest\"]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body_input\":{\"present\":false,\"content_type\":null,\"required_missing\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"responses\":[{\"status\":\"200\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/Billing.V1.Order.VirtualMachineOrderResource\"]},{\"status\":\"401\",\"content_types\":[\"application/json\"],\"schema_refs\":[]},{\"status\":\"422\",\"content_types\":[\"application/json\"],\"schema_refs\":[]},{\"status\":\"500\",\"content_types\":[\"application/json\"],\"schema_refs\":[]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
}

test "generic dispatch rejects read routes as dry-run mutations" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try std.testing.expectError(error.ProviderRouteIsNotMutation, dryRunPlanJson(allocator, route, &.{}));
}

test "generic dispatch validates auth provider and read safety before HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-list-access-applications")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const hostinger_client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(error.ProviderRouteAuthMismatch, hostinger_client.callReadRoute(std.testing.io, allocator, route, &.{.{ .name = "account_id", .value = "acct/1" }}));

    const cloudflare_client = Client.init(.{ .cloudflare = .{} });
    try std.testing.expectError(error.MissingCloudflareAuth, cloudflare_client.callReadRoute(std.testing.io, allocator, route, &.{.{ .name = "account_id", .value = "acct/1" }}));
}

test "generic dispatch plans but does not execute policy-blocked read routes" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "brapi-get_DevtoolsJsonClose")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    var planned_route = route;
    planned_route.support = .planned;
    try std.testing.expect(routeLiveCallSupported(planned_route));

    var blocked_route = route;
    blocked_route.support = .blocked_permission;
    try std.testing.expect(!routeLiveCallSupported(blocked_route));
    try std.testing.expect(routeDiagnosticReadSupported(blocked_route));

    const request = provider_routes.Request{
        .path_params = &.{
            .{ .name = "account_id", .value = "acct/1" },
            .{ .name = "session_id", .value = "00000000-0000-0000-0000-000000000000" },
            .{ .name = "target_id", .value = "target-1" },
        },
    };

    const plan = try planRouteJsonRequest(allocator, blocked_route, request);
    defer allocator.free(plan);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"support\":\"blocked_permission\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"dispatch\":{\"live_call_supported\":false,\"diagnostic_read_supported\":true,\"dry_run_supported\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "Cloudio will not execute it live with the current support policy") != null);

    const client = Client.init(.{ .cloudflare = .{ .token = "test-token" } });
    try std.testing.expectError(error.UnsupportedProviderRoute, client.callReadRouteRequest(std.testing.io, allocator, blocked_route, request));

    const missing_auth_client = Client.init(.{ .cloudflare = .{} });
    try std.testing.expectError(error.MissingCloudflareAuth, missing_auth_client.callDiagnosticReadRouteRequest(std.testing.io, allocator, blocked_route, request));
}

test "generic dispatch validates Cloudflare auth scheme compatibility before HTTP" {
    const allocator = std.testing.allocator;

    const legacy_only_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer legacy_only_route.deinit(allocator);
    const token_client = Client.init(.{ .cloudflare = .{ .token = "test-token" } });
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, token_client.callReadRoute(std.testing.io, allocator, legacy_only_route, &.{}));

    const bearer_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "get_publicListSuppressionRouting")) orelse return error.TestExpectedRoute;
    defer bearer_route.deinit(allocator);
    try validateCloudflareRouteAuth(bearer_route.security, .{ .token = "test-token" });
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, validateCloudflareRouteAuth(bearer_route.security, .{ .email = "ops@example.test", .key = "global-key" }));

    const bearer_plan = try planRouteJsonRequest(
        allocator,
        bearer_route,
        .{ .path_params = &.{.{ .name = "account_id", .value = "acct/1" }} },
    );
    defer allocator.free(bearer_plan);
    try std.testing.expect(std.mem.indexOf(u8, bearer_plan, "\"security\":{\"required\":true,\"cloudio_supported\":true,\"alternatives\":[[\"bearerAuth\"]]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bearer_plan, "\"dispatch\":{\"live_call_supported\":true,\"diagnostic_read_supported\":false,\"dry_run_supported\":false}") != null);

    const assets_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer assets_route.deinit(allocator);
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, validateCloudflareRouteAuth(assets_route.security, .{ .token = "test-token" }));
}

test "generic dispatch validates required read query parameters before HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.MissingRouteQueryParameter,
        client.callReadRouteRequest(
            std.testing.io,
            allocator,
            route,
            .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
            },
        ),
    );
}

test "generic dispatch rejects body input for bodyless read calls" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.ProviderReadRouteIsBodyless,
        client.callReadRouteRequest(
            std.testing.io,
            allocator,
            route,
            .{ .body = .{ .present = true, .content_type = "application/json" } },
        ),
    );
}

test "generic dispatch validates mutation safety before HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_restartVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(error.ProviderRouteRequiresDryRun, client.callReadRoute(std.testing.io, allocator, route, &.{.{ .name = "virtualMachineId", .value = "123" }}));
}
