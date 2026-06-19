const std = @import("std");
const core_json = @import("core_json");
const net_http = @import("net_http");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

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

    pub fn view(self: ReadRouteResult) ReadRouteResultView {
        return .{
            .status = self.response.status,
            .body_bytes = self.response.body.len,
            .matched_response = self.matched_response,
        };
    }
};

pub const ReadRouteResultView = struct {
    status: std.http.Status,
    body_bytes: usize,
    matched_response: ?*const provider_routes.Response,

    pub fn statusCode(self: ReadRouteResultView) u16 {
        return @intFromEnum(self.status);
    }

    pub fn statusText(self: ReadRouteResultView) []const u8 {
        return net_http.statusText(self.status);
    }
};

pub fn matchReadRouteResponse(route: provider_routes.Route, response: net_http.Response) ReadRouteResult {
    return .{
        .response = response,
        .matched_response = route.findResponseForStatus(response.status),
    };
}

pub fn readRouteResultMetadataJsonFromResult(gpa: Allocator, route: provider_routes.Route, result: ReadRouteResult) ![]u8 {
    return try readRouteResultMetadataJson(gpa, route, result.view());
}

pub fn readRouteResultMetadataJson(gpa: Allocator, route: provider_routes.Route, result: ReadRouteResultView) ![]u8 {
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
    try writer.print("{d}", .{result.body_bytes});
    try writer.writeByte(',');
    try writer.writeAll("\"body_included\":false");
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
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

test "route result metadata renders matched read response without body content" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const json = try readRouteResultMetadataJson(allocator, route, .{
        .status = .ok,
        .body_bytes = 11,
        .matched_response = route.findResponseForStatus(.ok),
    });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"accounts-list-accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"http_status\":200") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"matched_response\":{\"status\":\"200\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_bytes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
}

test "route result metadata renders unmatched read response" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const json = try readRouteResultMetadataJson(allocator, route, .{
        .status = .not_found,
        .body_bytes = 2,
        .matched_response = null,
    });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"http_status\":404") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status_text\":\"not_found\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"matched_response\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_bytes\":2") != null);
}

test "route result owns response matching and metadata conversion" {
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

    const ok_json = try readRouteResultMetadataJsonFromResult(allocator, route, ok_result);
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

test "route result reports unmatched response metadata from owned result" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const body = try allocator.dupe(u8, "{}");
    const result = matchReadRouteResponse(route, .{ .status = .not_found, .body = body });
    defer result.deinit(allocator);
    try std.testing.expect(result.matched_response == null);

    const json = try readRouteResultMetadataJsonFromResult(allocator, route, result);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"http_status\":404") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status_text\":\"not_found\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"matched_response\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_bytes\":2") != null);
}
