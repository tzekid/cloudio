const std = @import("std");
const provider_dispatch = @import("provider_dispatch");
const provider_route_plan = @import("provider_route_plan");
const provider_route_result = @import("provider_route_result");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const Auth = provider_dispatch.Auth;
pub const PathParam = provider_routes.PathParam;
pub const QueryParam = provider_routes.QueryParam;
pub const HeaderParam = provider_routes.HeaderParam;
pub const Request = provider_routes.Request;
pub const BodyInput = provider_routes.BodyInput;

pub const SupportFilter = enum {
    implemented,
    partial,
    planned,
    blocked_permission,
    unsafe_mutation,
    deprecated,
    not_applicable,

    pub fn parse(value: []const u8) ?SupportFilter {
        if (std.mem.eql(u8, value, "implemented")) return .implemented;
        if (std.mem.eql(u8, value, "partial")) return .partial;
        if (std.mem.eql(u8, value, "planned")) return .planned;
        if (std.mem.eql(u8, value, "blocked_permission")) return .blocked_permission;
        if (std.mem.eql(u8, value, "unsafe_mutation")) return .unsafe_mutation;
        if (std.mem.eql(u8, value, "deprecated")) return .deprecated;
        if (std.mem.eql(u8, value, "not_applicable")) return .not_applicable;
        return null;
    }

    pub fn name(self: SupportFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: SupportFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }

    pub fn matchesRoute(self: SupportFilter, value: provider_routes.Support) bool {
        return self.matches(@tagName(value));
    }
};

pub const ModeFilter = enum {
    read,
    dry_run,
    write,
    none,

    pub fn parse(value: []const u8) ?ModeFilter {
        if (std.mem.eql(u8, value, "read")) return .read;
        if (std.mem.eql(u8, value, "dry_run")) return .dry_run;
        if (std.mem.eql(u8, value, "write")) return .write;
        if (std.mem.eql(u8, value, "none")) return .none;
        return null;
    }

    pub fn name(self: ModeFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: ModeFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }

    pub fn matchesRoute(self: ModeFilter, value: provider_routes.Mode) bool {
        return self.matches(@tagName(value));
    }
};

pub const RouteFilter = struct {
    provider: ProviderFilter = .all,
    tag_query: ?[]const u8 = null,
    operation_id: ?[]const u8 = null,
    method: ?provider_routes.Method = null,
    path_template: ?[]const u8 = null,
    support: ?SupportFilter = null,
    mode: ?ModeFilter = null,
};

pub const RoutePlanInput = struct {
    filter: RouteFilter,
    request: Request = .{},
};

pub fn parseRouteMethod(value: []const u8) ?provider_routes.Method {
    return provider_routes.Method.parse(value);
}

pub fn parsePathParamAssignment(value: []const u8) !PathParam {
    return provider_routes.parsePathParamAssignment(value);
}

pub fn parseQueryParamAssignment(value: []const u8) !QueryParam {
    return provider_routes.parseQueryParamAssignment(value);
}

pub fn parseHeaderParamAssignment(value: []const u8) !HeaderParam {
    return provider_routes.parseHeaderParamAssignment(value);
}

pub fn planJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput) ![]u8 {
    var routes = try loadCandidateRoutes(io, gpa, paths, input.filter.provider);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items, input.filter);
    return try provider_route_plan.planRouteJsonRequest(gpa, route.*, input.request);
}

pub fn loadRoute(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput) !provider_routes.Route {
    var routes = try loadCandidateRoutes(io, gpa, paths, input.filter.provider);
    errdefer routes.deinit(gpa);
    return try takeSingleRoute(gpa, &routes, input.filter);
}

pub fn planJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput) ![]u8 {
    var routes = try loadCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, input.filter.provider);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items, input.filter);
    return try provider_route_plan.planRouteJsonRequest(gpa, route.*, input.request);
}

pub fn loadRouteFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput) !provider_routes.Route {
    var routes = try loadCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, input.filter.provider);
    errdefer routes.deinit(gpa);
    return try takeSingleRoute(gpa, &routes, input.filter);
}

pub fn readMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadCandidateRoutes(io, gpa, paths, input.filter.provider);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items, input.filter);
    const client = provider_dispatch.Client.init(auth);
    const result = try client.callReadRouteResultRequest(io, gpa, route.*, input.request);
    defer result.deinit(gpa);
    return try provider_route_result.readRouteResultMetadataJson(gpa, route.*, result.view());
}

pub fn dryRunJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadCandidateRoutes(io, gpa, paths, input.filter.provider);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items, input.filter);
    const client = provider_dispatch.Client.init(auth);
    return try client.dryRunRouteRequest(gpa, route.*, input.request);
}

pub fn dryRunJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, input.filter.provider);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items, input.filter);
    const client = provider_dispatch.Client.init(auth);
    return try client.dryRunRouteRequest(gpa, route.*, input.request);
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, writer: anytype) !void {
    const json = try planJson(io, gpa, paths, input);
    defer gpa.free(json);
    try writer.writeAll(json);
    try writer.writeByte('\n');
}

fn loadCandidateRoutes(io: Io, gpa: Allocator, paths: Paths, provider: ProviderFilter) !provider_routes.RouteSet {
    return switch (provider) {
        .all => try provider_routes.loadAll(io, gpa, paths),
        .cloudflare => try provider_routes.loadProvider(io, gpa, paths, .cloudflare),
        .hostinger => try provider_routes.loadProvider(io, gpa, paths, .hostinger),
    };
}

fn loadCandidateRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, provider: ProviderFilter) !provider_routes.RouteSet {
    return switch (provider) {
        .all => try provider_routes.loadAllFromText(gpa, cloudflare_text, hostinger_text),
        .cloudflare => try provider_routes.loadProviderFromText(gpa, .cloudflare, cloudflare_text),
        .hostinger => try provider_routes.loadProviderFromText(gpa, .hostinger, hostinger_text),
    };
}

fn selectSingleRoute(routes: []const provider_routes.Route, filter: RouteFilter) !*const provider_routes.Route {
    var selected: ?*const provider_routes.Route = null;
    for (routes) |*route| {
        if (!routeMatchesFilter(route.*, filter)) continue;
        if (selected != null) return error.ProviderRoutePlanAmbiguous;
        selected = route;
    }
    return selected orelse error.ProviderRoutePlanNotFound;
}

fn takeSingleRoute(gpa: Allocator, routes: *provider_routes.RouteSet, filter: RouteFilter) !provider_routes.Route {
    var selected_index: ?usize = null;
    for (routes.items, 0..) |route, index| {
        if (!routeMatchesFilter(route, filter)) continue;
        if (selected_index != null) return error.ProviderRoutePlanAmbiguous;
        selected_index = index;
    }
    const index = selected_index orelse return error.ProviderRoutePlanNotFound;
    const selected = routes.items[index];
    for (routes.items, 0..) |route, route_index| {
        if (route_index == index) continue;
        route.deinit(gpa);
    }
    gpa.free(routes.items);
    routes.items = &.{};
    return selected;
}

fn routeMatchesFilter(route: provider_routes.Route, filter: RouteFilter) bool {
    if (!filter.provider.includesProvider(route.provider)) return false;
    if (filter.tag_query) |query| {
        if (!containsIgnoreCase(route.tag, query)) return false;
    }
    if (filter.operation_id) |expected| {
        const actual = route.operation_id orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    if (filter.method) |expected| {
        if (route.method != expected) return false;
    }
    if (filter.path_template) |expected| {
        if (!std.mem.eql(u8, route.path_template, expected)) return false;
    }
    if (filter.support) |expected| {
        if (!expected.matchesRoute(route.support)) return false;
    }
    if (filter.mode) |expected| {
        if (!expected.matchesRoute(route.mode)) return false;
    }
    return true;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

test "plans exact provider routes without live provider calls" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Worker Script","method":"POST","path":"/accounts/{account_id}/workers/assets/upload","operation_id":"worker-assets-upload","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"base64","required":true}],"request_body":{"required":true,"content_types":["multipart/form-data"],"schema_refs":[]},"responses":[{"status":"201","content_types":["application/json"],"schema_refs":[]}],"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.MetricsResource"]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads metrics."}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads billing catalog."}
        \\
    ;

    const read_plan = try planJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .hostinger, .operation_id = "VPS_getMetricsV1" },
            .request = .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{
                    .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                    .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
                },
            },
        },
    );
    defer allocator.free(read_plan);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"url\":\"https://developers.hostinger.com/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"will_execute\":false") != null);

    const mutation_plan = try planJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .cloudflare, .operation_id = "worker-assets-upload" },
            .request = .{
                .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
                .query_params = &.{.{ .name = "base64", .value = "true" }},
                .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" },
            },
        },
    );
    defer allocator.free(mutation_plan);
    try std.testing.expect(std.mem.indexOf(u8, mutation_plan, "\"operation_id\":\"worker-assets-upload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mutation_plan, "\"mode\":\"dry_run\"") != null);

    try std.testing.expectError(
        error.ProviderRoutePlanAmbiguous,
        planJsonFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .hostinger } }),
    );
    try std.testing.expectError(
        error.ProviderRoutePlanNotFound,
        planJsonFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .hostinger, .operation_id = "missing" } }),
    );
}

test "renders exact provider route dry-runs through the shared route contract" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_email","api_key"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Order.VirtualMachineOrderResource"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes in POC."}
        \\
    ;

    const plan = try dryRunJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .hostinger, .operation_id = "VPS_purchaseNewVirtualMachineV1" },
            .request = .{ .body = .{ .present = true, .content_type = "application/json" } },
        },
        .{ .hostinger = "test-token" },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://developers.hostinger.com/api/vps/v1/virtual-machines\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mode\":\"dry_run\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "test-token") == null);

    try std.testing.expectError(
        error.ProviderRouteAuthMismatch,
        dryRunJsonFromText(
            allocator,
            cloudflare,
            hostinger,
            .{ .filter = .{ .provider = .hostinger, .operation_id = "VPS_purchaseNewVirtualMachineV1" } },
            .{ .cloudflare = .{ .token = "test-token" } },
        ),
    );
}
