const std = @import("std");
const provider_capabilities = @import("provider_capabilities");
const provider_route_safety = @import("provider_route_safety");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

pub const PlanMode = enum {
    read,
    dry_run,

    pub fn name(self: PlanMode) []const u8 {
        return @tagName(self);
    }
};

pub const RequestPlan = struct {
    route: provider_routes.Route,
    request: provider_routes.Request,
    path: []u8,
    url: []u8,
    mode: PlanMode,
    safety_kind: provider_route_safety.PlanKind,
    safety_policy: provider_route_safety.RouteSafetyPolicy,
    safety: []const u8,
    cloudio_auth_supported: bool,
    live_call_supported: bool,
    diagnostic_read_supported: bool,
    dry_run_supported: bool,
    will_execute: bool = false,

    pub fn deinit(self: RequestPlan, gpa: Allocator) void {
        gpa.free(self.path);
        gpa.free(self.url);
    }
};

pub const LiveReadPlan = struct {
    route: provider_routes.Route,
    request: provider_routes.Request,
    path: []u8,
    url: []u8,
    diagnostic: bool,

    pub fn deinit(self: LiveReadPlan, gpa: Allocator) void {
        gpa.free(self.path);
        gpa.free(self.url);
    }
};

pub fn planRouteRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !RequestPlan {
    return try planRouteRequestWithBase(gpa, route, request, null);
}

pub fn planRouteRequestWithBase(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, base_url_override: ?[]const u8) !RequestPlan {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.isDryRunMutation()) return try planDryRunMutationRequestWithBase(gpa, route, request, base_url_override);
    if (route.mode != .read or route.method != .GET) return error.UnsupportedProviderRoutePlan;
    try validateBodylessReadRequest(request);
    try route.validateRequestHeaders(request);

    const path = try route.renderRequestPath(gpa, request);
    errdefer gpa.free(path);
    const url = try renderUrl(gpa, route, path, base_url_override);
    errdefer gpa.free(url);

    return .{
        .route = route,
        .request = request,
        .path = path,
        .url = url,
        .mode = .read,
        .safety_kind = .read_plan,
        .safety_policy = provider_route_safety.routePolicy(route, .read_plan),
        .safety = if (provider_capabilities.routeLiveReadSupported(route))
            "No provider API request is sent. This is a generic request plan for a live read route."
        else
            "No provider API request is sent. This read route is planned for metadata review, but Cloudio will not execute it live with the current support policy.",
        .cloudio_auth_supported = provider_capabilities.cloudioSupportsRouteAuth(route),
        .live_call_supported = provider_capabilities.routeLiveReadSupported(route),
        .diagnostic_read_supported = provider_capabilities.routeDiagnosticReadSupported(route),
        .dry_run_supported = provider_capabilities.routeDryRunSupported(route),
    };
}

pub fn planDryRunMutationRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !RequestPlan {
    return try planDryRunMutationRequestWithBase(gpa, route, request, null);
}

pub fn planDryRunMutationRequestWithBase(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, base_url_override: ?[]const u8) !RequestPlan {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.mode != .dry_run or route.method == .GET or route.method == .HEAD) return error.ProviderRouteIsNotMutation;
    try route.validateRequestHeaders(request);
    try route.validateProvidedBodyInput(request);

    const path = try route.renderRequestPath(gpa, request);
    errdefer gpa.free(path);
    const url = try renderUrl(gpa, route, path, base_url_override);
    errdefer gpa.free(url);

    return .{
        .route = route,
        .request = request,
        .path = path,
        .url = url,
        .mode = .dry_run,
        .safety_kind = .dry_run_mutation,
        .safety_policy = provider_route_safety.routePolicy(route, .dry_run_mutation),
        .safety = "No provider API request is sent. This is a generic dry-run plan for a live mutation route.",
        .cloudio_auth_supported = provider_capabilities.cloudioSupportsRouteAuth(route),
        .live_call_supported = provider_capabilities.routeLiveReadSupported(route),
        .diagnostic_read_supported = provider_capabilities.routeDiagnosticReadSupported(route),
        .dry_run_supported = provider_capabilities.routeDryRunSupported(route),
    };
}

pub fn planLiveReadRequest(gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, include_blocked_diagnostic: bool, base_url_override: ?[]const u8) !LiveReadPlan {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.method != .GET or route.mode != .read) return error.ProviderRouteRequiresDryRun;
    if (!provider_capabilities.routeLiveReadSupported(route) and !(include_blocked_diagnostic and provider_capabilities.routeDiagnosticReadSupported(route))) return error.UnsupportedProviderRoute;
    try validateBodylessReadRequest(request);
    try route.validateRequestHeaders(request);

    const path = try route.renderRequestPath(gpa, request);
    errdefer gpa.free(path);
    const url = try renderUrl(gpa, route, path, base_url_override);
    errdefer gpa.free(url);

    return .{
        .route = route,
        .request = request,
        .path = path,
        .url = url,
        .diagnostic = include_blocked_diagnostic and !provider_capabilities.routeLiveReadSupported(route),
    };
}

fn validateBodylessReadRequest(request: provider_routes.Request) !void {
    if (request.body.present or request.body.content_type != null) return error.ProviderReadRouteIsBodyless;
}

fn renderUrl(gpa: Allocator, route: provider_routes.Route, path: []const u8, base_url_override: ?[]const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ base_url_override orelse route.provider.baseUrl(), path });
}

test "request planner returns structured read plans without provider execution" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteRequest(
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
    defer plan.deinit(allocator);

    try std.testing.expectEqual(PlanMode.read, plan.mode);
    try std.testing.expectEqual(provider_route_safety.PlanKind.read_plan, plan.safety_kind);
    try std.testing.expect(!plan.will_execute);
    try std.testing.expect(plan.live_call_supported);
    try std.testing.expect(!plan.dry_run_supported);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", plan.path);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", plan.url);
}

test "request planner returns structured dry-run mutation plans" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const plan = try planRouteRequestWithBase(
        allocator,
        route,
        .{
            .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
            .query_params = &.{.{ .name = "base64", .value = "true" }},
            .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" },
        },
        "https://fixture.cloudflare.test",
    );
    defer plan.deinit(allocator);

    try std.testing.expectEqual(PlanMode.dry_run, plan.mode);
    try std.testing.expectEqual(provider_route_safety.PlanKind.dry_run_mutation, plan.safety_kind);
    try std.testing.expect(plan.safety_policy.mutation);
    try std.testing.expect(plan.dry_run_supported);
    try std.testing.expect(!plan.will_execute);
    try std.testing.expectEqualStrings("https://fixture.cloudflare.test/accounts/acct%2F1/workers/assets/upload?base64=true", plan.url);
}

test "live read planner shares request validation and URL rendering" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const missing_query = provider_routes.Request{
        .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
        .query_params = &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
    };
    try std.testing.expectError(error.MissingRouteQueryParameter, planLiveReadRequest(allocator, route, missing_query, false, null));

    const plan = try planLiveReadRequest(
        allocator,
        route,
        .{
            .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
            .query_params = &.{
                .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
            },
        },
        false,
        "https://fixture.hostinger.test",
    );
    defer plan.deinit(allocator);

    try std.testing.expect(!plan.diagnostic);
    try std.testing.expectEqualStrings("https://fixture.hostinger.test/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", plan.url);
}
