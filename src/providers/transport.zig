const std = @import("std");
const net_http = @import("net_http");
const provider_auth = @import("provider_auth");
const provider_cloudflare = @import("provider_cloudflare");
const provider_hostinger = @import("provider_hostinger");
const provider_request_plan = @import("provider_request_plan");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const ReadTransport = struct {
    auth: provider_auth.Auth,
    cloudflare_base_url_override: []const u8 = provider_routes.cloudflare_base_url,
    hostinger_base_url_override: []const u8 = provider_routes.hostinger_base_url,

    pub fn init(auth: provider_auth.Auth) ReadTransport {
        return .{ .auth = auth };
    }

    pub fn provider(self: ReadTransport) provider_routes.Provider {
        return self.auth.provider();
    }

    pub fn callReadRouteRequest(self: ReadTransport, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !net_http.Response {
        return try self.callReadRouteRequestWithPolicy(io, gpa, route, request, false);
    }

    pub fn callDiagnosticReadRouteRequest(self: ReadTransport, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request) !net_http.Response {
        return try self.callReadRouteRequestWithPolicy(io, gpa, route, request, true);
    }

    pub fn baseUrl(self: ReadTransport, target_provider: provider_routes.Provider) ?[]const u8 {
        return switch (target_provider) {
            .cloudflare => self.cloudflare_base_url_override,
            .hostinger => self.hostinger_base_url_override,
        };
    }

    fn callReadRouteRequestWithPolicy(self: ReadTransport, io: Io, gpa: Allocator, route: provider_routes.Route, request: provider_routes.Request, include_blocked_diagnostic: bool) !net_http.Response {
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        var plan = try provider_request_plan.planLiveReadRequest(gpa, route, request, include_blocked_diagnostic, self.baseUrl(route.provider));
        defer plan.deinit(gpa);
        try provider_auth.validateRouteAuth(route, self.auth);

        const headers = try requestHeaders(gpa, request.header_params);
        defer gpa.free(headers);
        return switch (self.auth) {
            .cloudflare => |auth| {
                const cloudflare = provider_cloudflare.Client{
                    .auth = auth,
                    .base_url_override = self.cloudflare_base_url_override,
                };
                if (!route.security.required) {
                    return try cloudflare.getPublicWithHeaders(io, gpa, plan.url, headers);
                }
                return try cloudflare.getWithHeaders(io, gpa, plan.url, headers);
            },
            .hostinger => |token| try (provider_hostinger.Client{
                .token = token,
                .base_url_override = self.hostinger_base_url_override,
            }).getWithHeaders(io, gpa, plan.url, headers),
        };
    }
};

pub fn requestHeaders(gpa: Allocator, params: []const provider_routes.HeaderParam) ![]std.http.Header {
    const headers = try gpa.alloc(std.http.Header, params.len);
    for (params, 0..) |param, index| {
        headers[index] = .{ .name = param.name, .value = param.value };
    }
    return headers;
}

test "provider transport validates provider auth and read policy before HTTP" {
    const allocator = std.testing.allocator;
    const read_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-list-access-applications")) orelse return error.TestExpectedRoute;
    defer read_route.deinit(allocator);

    const hostinger_transport = ReadTransport.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.ProviderRouteAuthMismatch,
        hostinger_transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            read_route,
            .{ .path_params = &.{.{ .name = "account_id", .value = "acct/1" }} },
        ),
    );

    const missing_auth_transport = ReadTransport.init(.{ .cloudflare = .{} });
    try std.testing.expectError(
        error.MissingCloudflareAuth,
        missing_auth_transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            read_route,
            .{ .path_params = &.{.{ .name = "account_id", .value = "acct/1" }} },
        ),
    );

    const mutation_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_restartVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer mutation_route.deinit(allocator);
    const hostinger_read_transport = ReadTransport.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.ProviderRouteRequiresDryRun,
        hostinger_read_transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            mutation_route,
            .{ .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }} },
        ),
    );
}

test "provider transport validates request shape before HTTP" {
    const allocator = std.testing.allocator;
    const hostinger_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);

    const transport = ReadTransport.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.ProviderReadRouteIsBodyless,
        transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            hostinger_route,
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
    try std.testing.expectError(
        error.MissingRouteQueryParameter,
        transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            hostinger_route,
            .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
            },
        ),
    );

    const cloudflare_route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "r2-get-event-notification-configs")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    const cloudflare_transport = ReadTransport.init(.{ .cloudflare = .{ .token = "test-token" } });
    try std.testing.expectError(
        error.UnknownRouteHeaderParameter,
        cloudflare_transport.callReadRouteRequest(
            std.testing.io,
            allocator,
            cloudflare_route,
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

test "provider transport exposes provider-specific base urls" {
    const transport = ReadTransport{
        .auth = .{ .cloudflare = .{ .token = "test-token" } },
        .cloudflare_base_url_override = "https://fixture.cloudflare.test",
        .hostinger_base_url_override = "https://fixture.hostinger.test",
    };
    try std.testing.expectEqualStrings("https://fixture.cloudflare.test", transport.baseUrl(.cloudflare).?);
    try std.testing.expectEqualStrings("https://fixture.hostinger.test", transport.baseUrl(.hostinger).?);
}
