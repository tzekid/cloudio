const std = @import("std");
const provider_capabilities = @import("provider_capabilities");
const provider_cloudflare = @import("provider_cloudflare");
const provider_routes = @import("provider_routes");

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

pub fn validateRouteAuth(route: provider_routes.Route, auth: Auth) !void {
    if (!route.security.required) return;
    return switch (auth) {
        .cloudflare => |cloudflare_auth| validateCloudflareRouteAuth(route.security, cloudflare_auth),
        .hostinger => |token| validateHostingerRouteAuth(route.security, token),
    };
}

pub fn validateCloudflareRouteAuth(security: provider_routes.Security, auth: provider_cloudflare.Auth) !void {
    if (auth.hasApiToken() and provider_capabilities.cloudflareSecurityAcceptsApiToken(security)) return;
    if (hasCloudflareLegacyAuth(auth) and provider_capabilities.cloudflareSecurityAcceptsLegacyAuth(security)) return;
    if (!auth.hasApiToken() and !hasCloudflareLegacyAuth(auth)) return error.MissingCloudflareAuth;
    return error.UnsupportedRouteAuthScheme;
}

pub fn validateHostingerRouteAuth(security: provider_routes.Security, token: []const u8) !void {
    if (token.len == 0) return error.MissingHostingerToken;
    if (security.acceptsSchemeSet(&.{"apiToken"})) return;
    return error.UnsupportedRouteAuthScheme;
}

pub fn hasCloudflareLegacyAuth(auth: provider_cloudflare.Auth) bool {
    const email = auth.email orelse return false;
    const key = auth.key orelse return false;
    return email.len != 0 and key.len != 0;
}

test "provider auth maps Cloudflare token legacy and unsupported schemes" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-list-access-applications")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try validateRouteAuth(route, .{ .cloudflare = .{ .token = "test-token" } });
    try validateRouteAuth(route, .{ .cloudflare = .{ .email = "ops@example.test", .key = "global-key" } });
    try std.testing.expectError(error.MissingCloudflareAuth, validateRouteAuth(route, .{ .cloudflare = .{} }));

    const bearer_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "get_publicListSuppressionRouting")) orelse return error.TestExpectedRoute;
    defer bearer_route.deinit(allocator);
    try validateCloudflareRouteAuth(bearer_route.security, .{ .token = "test-token" });
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, validateCloudflareRouteAuth(bearer_route.security, .{ .email = "ops@example.test", .key = "global-key" }));

    const assets_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer assets_route.deinit(allocator);
    try std.testing.expectError(error.UnsupportedRouteAuthScheme, validateCloudflareRouteAuth(assets_route.security, .{ .token = "test-token" }));
}

test "provider auth maps Hostinger apiToken routes" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try validateRouteAuth(route, .{ .hostinger = "test-token" });
    try std.testing.expectError(error.MissingHostingerToken, validateRouteAuth(route, .{ .hostinger = "" }));
}
