const std = @import("std");
const net_http = @import("net_http");
const provider_auth = @import("provider_auth");
const provider_capabilities = @import("provider_capabilities");
const provider_cloudflare = @import("provider_cloudflare");
const provider_hostinger = @import("provider_hostinger");
const provider_route_plan = @import("provider_route_plan");
const provider_route_result = @import("provider_route_result");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Auth = provider_auth.Auth;
pub const ReadRouteResult = provider_route_result.ReadRouteResult;

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
        try provider_auth.validateRouteAuth(route, self.auth);

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
        return provider_route_result.matchReadRouteResponse(route, response);
    }

    pub fn callDiagnosticReadRouteResultRequest(self: Client, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !ReadRouteResult {
        const response = try self.callDiagnosticReadRouteRequest(io, gpa, route, request);
        return provider_route_result.matchReadRouteResponse(route, response);
    }

    pub fn dryRunRoute(self: Client, gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
        return try self.dryRunRouteWithQuery(gpa, route, params, &.{});
    }

    pub fn dryRunRouteWithQuery(self: Client, gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
        return try self.dryRunRouteRequest(gpa, route, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn dryRunRouteRequest(self: Client, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        return try provider_route_plan.dryRunPlanJsonRequestWithBase(gpa, route, request, self.baseUrl(route.provider));
    }

    fn baseUrl(self: Client, target_provider: provider_routes.Provider) ?[]const u8 {
        return switch (target_provider) {
            .cloudflare => self.cloudflare_base_url_override,
            .hostinger => self.hostinger_base_url_override,
        };
    }
};

pub fn matchReadRouteResponse(route: provider_routes.Route, response: net_http.Response) ReadRouteResult {
    return provider_route_result.matchReadRouteResponse(route, response);
}

pub fn readRouteResultMetadataJson(gpa: Allocator, route: provider_routes.Route, result: ReadRouteResult) ![]u8 {
    return try provider_route_result.readRouteResultMetadataJsonFromResult(gpa, route, result);
}

pub fn dryRunPlanJson(gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
    return try provider_route_plan.dryRunPlanJson(gpa, route, params);
}

pub fn dryRunPlanJsonWithQuery(gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
    return try provider_route_plan.dryRunPlanJsonWithQuery(gpa, route, path_params, query_params);
}

pub fn planRouteJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    return try provider_route_plan.planRouteJsonRequest(gpa, route, request);
}

pub fn dryRunPlanJsonRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) ![]u8 {
    return try provider_route_plan.dryRunPlanJsonRequest(gpa, route, request);
}

fn requestHeaders(gpa: Allocator, params: []const provider_routes.HeaderParam) ![]std.http.Header {
    const headers = try gpa.alloc(std.http.Header, params.len);
    for (params, 0..) |param, index| {
        headers[index] = .{ .name = param.name, .value = param.value };
    }
    return headers;
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
    try provider_auth.validateCloudflareRouteAuth(bearer_route.security, .{ .token = "test-token" });
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, provider_auth.validateCloudflareRouteAuth(bearer_route.security, .{ .email = "ops@example.test", .key = "global-key" }));

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
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, provider_auth.validateCloudflareRouteAuth(assets_route.security, .{ .token = "test-token" }));
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
