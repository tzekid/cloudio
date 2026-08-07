const std = @import("std");
const net_http = @import("net_http");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Auth = struct {
    token: ?[]const u8 = null,
    email: ?[]const u8 = null,
    key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,

    pub fn isConfigured(self: Auth) bool {
        return self.token != null or (self.email != null and self.key != null);
    }

    pub fn hasApiToken(self: Auth) bool {
        const token = self.token orelse return false;
        return token.len != 0;
    }

    pub fn hasLegacy(self: Auth) bool {
        const email = self.email orelse return false;
        const key = self.key orelse return false;
        return email.len != 0 and key.len != 0;
    }
};

pub fn get(io: Io, gpa: Allocator, auth: Auth, url: []const u8) !net_http.Response {
    return try getWithHeaders(io, gpa, auth, url, &.{});
}

pub fn getLegacy(io: Io, gpa: Allocator, auth: Auth, url: []const u8) !net_http.Response {
    return try getWithLegacyHeaders(io, gpa, auth, url, &.{});
}

pub fn getWithHeaders(io: Io, gpa: Allocator, auth: Auth, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
    const common = jsonHeaders();
    if (auth.token) |token| {
        if (token.len == 0) return error.MissingCloudflareAuth;
        const auth_header = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
        defer gpa.free(auth_header);
        const privileged = [_]std.http.Header{.{ .name = "Authorization", .value = auth_header }};
        const headers = try mergeHeaders(gpa, &common, route_headers);
        defer gpa.free(headers);
        return try net_http.get(gpa, io, url, headers, &privileged);
    }
    return try getWithLegacyHeaders(io, gpa, auth, url, route_headers);
}

pub fn getWithLegacyHeaders(io: Io, gpa: Allocator, auth: Auth, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
    const email = auth.email orelse return error.MissingCloudflareAuth;
    const key = auth.key orelse return error.MissingCloudflareAuth;
    if (email.len == 0 or key.len == 0) return error.MissingCloudflareAuth;
    const legacy = [_]std.http.Header{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-Auth-Email", .value = email },
        .{ .name = "X-Auth-Key", .value = key },
    };
    const headers = try mergeHeaders(gpa, &legacy, route_headers);
    defer gpa.free(headers);
    return try net_http.get(gpa, io, url, headers, &.{});
}

pub fn requestJson(io: Io, gpa: Allocator, auth: Auth, method: std.http.Method, url: []const u8, body: ?[]const u8) !net_http.Response {
    const common = jsonHeaders();
    if (auth.token) |token| {
        if (token.len == 0) return error.MissingCloudflareAuth;
        const auth_header = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
        defer gpa.free(auth_header);
        const privileged = [_]std.http.Header{.{ .name = "Authorization", .value = auth_header }};
        return try net_http.request(gpa, io, method, url, body, &common, &privileged);
    }
    const email = auth.email orelse return error.MissingCloudflareAuth;
    const key = auth.key orelse return error.MissingCloudflareAuth;
    if (email.len == 0 or key.len == 0) return error.MissingCloudflareAuth;
    const legacy = [_]std.http.Header{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "X-Auth-Email", .value = email },
        .{ .name = "X-Auth-Key", .value = key },
    };
    return try net_http.request(gpa, io, method, url, body, &legacy, &.{});
}

pub fn getPublic(io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
    return try getPublicWithHeaders(io, gpa, url, &.{});
}

pub fn getPublicWithHeaders(io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
    const common = jsonHeaders();
    const headers = try mergeHeaders(gpa, &common, route_headers);
    defer gpa.free(headers);
    return try net_http.get(gpa, io, url, headers, &.{});
}

fn jsonHeaders() [2]std.http.Header {
    return .{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    };
}

fn mergeHeaders(gpa: Allocator, base: []const std.http.Header, extra: []const std.http.Header) ![]std.http.Header {
    const merged = try gpa.alloc(std.http.Header, base.len + extra.len);
    @memcpy(merged[0..base.len], base);
    @memcpy(merged[base.len..], extra);
    return merged;
}

test "auth detects token and legacy credentials" {
    try std.testing.expect(!(Auth{}).isConfigured());
    try std.testing.expect((Auth{ .token = "tok" }).isConfigured());
    try std.testing.expect((Auth{ .token = "tok" }).hasApiToken());
    try std.testing.expect(!(Auth{ .token = "" }).hasApiToken());
    try std.testing.expect((Auth{ .email = "a@example.com", .key = "key" }).hasLegacy());
    try std.testing.expect(!(Auth{ .email = "a@example.com" }).hasLegacy());
}

test "merges Cloudflare public route headers after JSON defaults" {
    const allocator = std.testing.allocator;
    const extra = [_]std.http.Header{.{ .name = "CF-Test", .value = "value" }};
    const merged = try mergeHeaders(allocator, &jsonHeaders(), &extra);
    defer allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 3), merged.len);
    try std.testing.expectEqualStrings("Accept", merged[0].name);
    try std.testing.expectEqualStrings("application/json", merged[0].value);
    try std.testing.expectEqualStrings("Content-Type", merged[1].name);
    try std.testing.expectEqualStrings("CF-Test", merged[2].name);
}
