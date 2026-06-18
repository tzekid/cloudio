const std = @import("std");
const provider_routes = @import("provider_routes");

pub const PaginationKind = enum {
    page,
    cursor,

    pub fn name(self: PaginationKind) []const u8 {
        return @tagName(self);
    }
};

pub const RouteCapabilities = struct {
    routable: bool,
    live_read_supported: bool,
    diagnostic_read_supported: bool,
    dry_run_supported: bool,
    cloudio_auth_supported: bool,
    pagination: ?PaginationKind,
};

pub fn routeCapabilities(route: provider_routes.Route) RouteCapabilities {
    return .{
        .routable = route.isRoutable(),
        .live_read_supported = routeLiveReadSupported(route),
        .diagnostic_read_supported = routeDiagnosticReadSupported(route),
        .dry_run_supported = routeDryRunSupported(route),
        .cloudio_auth_supported = cloudioSupportsRouteAuth(route),
        .pagination = routePaginationKind(route),
    };
}

pub fn cloudioSupportsRouteAuth(route: provider_routes.Route) bool {
    if (!route.security.required) return true;
    return switch (route.provider) {
        .cloudflare => cloudflareSecurityAcceptsApiToken(route.security) or cloudflareSecurityAcceptsLegacyAuth(route.security),
        .hostinger => route.security.acceptsSchemeSet(&.{"apiToken"}),
    };
}

pub fn routeLiveReadSupported(route: provider_routes.Route) bool {
    return routeSupportAllowsLiveRead(route) and route.isRoutable() and route.mode == .read and route.method == .GET and !route.request_body.required and cloudioSupportsRouteAuth(route);
}

pub fn routeDiagnosticReadSupported(route: provider_routes.Route) bool {
    return routeSupportAllowsBlockedDiagnosticRead(route) and route.isRoutable() and route.mode == .read and route.method == .GET and !route.request_body.required and cloudioSupportsRouteAuth(route);
}

pub fn routeDryRunSupported(route: provider_routes.Route) bool {
    return route.isRoutable() and route.isDryRunMutation();
}

pub fn routePaginationKind(route: provider_routes.Route) ?PaginationKind {
    if (routeHasQueryParam(route, "page")) return .page;
    if (routeHasQueryParam(route, "cursor")) return .cursor;
    return null;
}

pub fn routePaginationName(route: provider_routes.Route) ?[]const u8 {
    const kind = routePaginationKind(route) orelse return null;
    return kind.name();
}

pub fn routeHasQueryParam(route: provider_routes.Route, name: []const u8) bool {
    for (route.query_params) |param| {
        if (std.mem.eql(u8, param.name, name)) return true;
    }
    return false;
}

fn routeSupportAllowsLiveRead(route: provider_routes.Route) bool {
    return switch (route.support) {
        .planned, .partial, .implemented => true,
        .blocked_permission, .unsafe_mutation, .deprecated, .not_applicable => false,
    };
}

fn routeSupportAllowsBlockedDiagnosticRead(route: provider_routes.Route) bool {
    return route.support == .blocked_permission;
}

pub fn cloudflareSecurityAcceptsApiToken(security: provider_routes.Security) bool {
    return security.acceptsSchemeSet(&.{"api_token"}) or security.acceptsSchemeSet(&.{"bearerAuth"}) or cloudflareSecurityHasTokenOrLegacyBundle(security);
}

pub fn cloudflareSecurityAcceptsLegacyAuth(security: provider_routes.Security) bool {
    return security.acceptsSchemeSet(&.{ "api_email", "api_key" }) or cloudflareSecurityHasTokenOrLegacyBundle(security);
}

fn cloudflareSecurityHasTokenOrLegacyBundle(security: provider_routes.Security) bool {
    return security.hasAlternativeContainingSchemes(&.{ "api_email", "api_key", "api_token" });
}

test "classifies route capabilities for reads diagnostics dry runs and pagination" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Rulesets","method":"GET","path":"/zones/{zone_id}/rulesets","operation_id":"listZoneRulesets","path_params":[{"name":"zone_id","required":true}],"query_params":[{"name":"cursor","required":false}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const read_route = (try provider_routes.findByOperationIdFromText(allocator, .cloudflare, cloudflare, "listZoneRulesets")) orelse return error.ExpectedRoute;
    defer read_route.deinit(allocator);
    const read_caps = routeCapabilities(read_route);
    try std.testing.expect(read_caps.routable);
    try std.testing.expect(read_caps.live_read_supported);
    try std.testing.expect(!read_caps.diagnostic_read_supported);
    try std.testing.expect(!read_caps.dry_run_supported);
    try std.testing.expectEqual(PaginationKind.cursor, read_caps.pagination.?);

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/public-keys","operation_id":"VPS_getAttachedPublicKeysV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"page","required":false}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture","deprecated":false,"notes":"diagnostic only"}
        \\
    ;
    const blocked_route = (try provider_routes.findByOperationIdFromText(allocator, .hostinger, hostinger, "VPS_getAttachedPublicKeysV1")) orelse return error.ExpectedRoute;
    defer blocked_route.deinit(allocator);
    const blocked_caps = routeCapabilities(blocked_route);
    try std.testing.expect(!blocked_caps.live_read_supported);
    try std.testing.expect(blocked_caps.diagnostic_read_supported);
    try std.testing.expectEqual(PaginationKind.page, blocked_caps.pagination.?);

    const mutation =
        \\{"provider":"hostinger","tag":"Billing","method":"POST","path":"/api/billing/v1/orders","operation_id":"billing_createOrderV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry run only"}
        \\
    ;
    const dry_run_route = (try provider_routes.findByOperationIdFromText(allocator, .hostinger, mutation, "billing_createOrderV1")) orelse return error.ExpectedRoute;
    defer dry_run_route.deinit(allocator);
    const dry_run_caps = routeCapabilities(dry_run_route);
    try std.testing.expect(!dry_run_caps.live_read_supported);
    try std.testing.expect(dry_run_caps.dry_run_supported);
    try std.testing.expect(dry_run_caps.pagination == null);
}
