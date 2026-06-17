const std = @import("std");
const core_json = @import("core_json");
const net_http = @import("net_http");
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
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        if (!route.isRoutable()) return error.UnsupportedProviderRoute;
        if (route.method != .GET or route.mode != .read) return error.ProviderRouteRequiresDryRun;

        const url = try route.renderUrlWithQuery(gpa, self.baseUrl(route.provider), path_params, query_params);
        defer gpa.free(url);
        return switch (self.auth) {
            .cloudflare => |auth| try (provider_cloudflare.Client{
                .auth = auth,
                .base_url_override = self.cloudflare_base_url_override,
            }).get(io, gpa, url),
            .hostinger => |token| try (provider_hostinger.Client{
                .token = token,
                .base_url_override = self.hostinger_base_url_override,
            }).get(io, gpa, url),
        };
    }

    pub fn dryRunRoute(self: Client, gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
        return try self.dryRunRouteWithQuery(gpa, route, params, &.{});
    }

    pub fn dryRunRouteWithQuery(self: Client, gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
        if (route.provider != self.provider()) return error.ProviderRouteAuthMismatch;
        return try dryRunPlanJsonWithQuery(gpa, route, path_params, query_params);
    }

    fn baseUrl(self: Client, target_provider: provider_routes.Provider) ?[]const u8 {
        return switch (target_provider) {
            .cloudflare => self.cloudflare_base_url_override,
            .hostinger => self.hostinger_base_url_override,
        };
    }
};

pub fn dryRunPlanJson(gpa: Allocator, route: provider_routes.Route, params: []const provider_routes.PathParam) ![]u8 {
    return try dryRunPlanJsonWithQuery(gpa, route, params, &.{});
}

pub fn dryRunPlanJsonWithQuery(gpa: Allocator, route: provider_routes.Route, path_params: []const provider_routes.PathParam, query_params: []const provider_routes.QueryParam) ![]u8 {
    if (!route.isRoutable()) return error.UnsupportedProviderRoute;
    if (route.mode != .dry_run or route.method == .GET) return error.ProviderRouteIsNotMutation;

    const path = try route.renderPathWithQuery(gpa, path_params, query_params);
    defer gpa.free(path);

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
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeRequestBodyField(writer, "request_body", route.request_body, true);
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

fn writeResponsesField(writer: anytype, name: []const u8, responses: []const provider_routes.Response, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeAll(":[");
    for (responses, 0..) |response, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "status", response.status, true);
        try writeStringArrayField(writer, "content_types", response.content_types, true);
        try writeStringArrayField(writer, "schema_refs", response.schema_refs, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    if (trailing_comma) try writer.writeByte(',');
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
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body\":{\"required\":true") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"request_body\":{\"required\":true,\"content_types\":[\"multipart/form-data\"],\"schema_refs\":[]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"responses\":[{\"status\":\"201\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_completed-upload-assets-response\"]},{\"status\":\"202\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_upload-assets-response\"]},{\"status\":\"4XX\",\"content_types\":[\"application/json\"],\"schema_refs\":[\"#/components/schemas/workers_api-response-common-failure\"]}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
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

test "generic dispatch validates required read query parameters before HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(
        error.MissingRouteQueryParameter,
        client.callReadRouteWithQuery(
            std.testing.io,
            allocator,
            route,
            &.{.{ .name = "virtualMachineId", .value = "vm/1" }},
            &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
        ),
    );
}

test "generic dispatch validates mutation safety before HTTP" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_restartVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const client = Client.init(.{ .hostinger = "test-token" });
    try std.testing.expectError(error.ProviderRouteRequiresDryRun, client.callReadRoute(std.testing.io, allocator, route, &.{.{ .name = "virtualMachineId", .value = "vm/1" }}));
}
