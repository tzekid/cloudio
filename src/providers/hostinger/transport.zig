const std = @import("std");
const net_http = @import("net_http");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn get(io: Io, gpa: Allocator, token: []const u8, url: []const u8) !net_http.Response {
    return try getWithHeaders(io, gpa, token, url, &.{});
}

pub fn getWithHeaders(io: Io, gpa: Allocator, token: []const u8, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
    if (token.len == 0) return error.MissingHostingerToken;
    const auth = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
    defer gpa.free(auth);
    const base_headers = [_]std.http.Header{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth },
    };
    const headers = try mergeHeaders(gpa, &base_headers, route_headers);
    defer gpa.free(headers);
    return try net_http.get(gpa, io, url, headers, &.{});
}

pub fn requestJson(io: Io, gpa: Allocator, token: []const u8, method: std.http.Method, url: []const u8, body: ?[]const u8) !net_http.Response {
    if (token.len == 0) return error.MissingHostingerToken;
    const auth = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
    defer gpa.free(auth);
    const headers = [_]std.http.Header{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth },
    };
    return try net_http.request(gpa, io, method, url, body, &headers, &.{});
}

fn mergeHeaders(gpa: Allocator, base: []const std.http.Header, extra: []const std.http.Header) ![]std.http.Header {
    const merged = try gpa.alloc(std.http.Header, base.len + extra.len);
    @memcpy(merged[0..base.len], base);
    @memcpy(merged[base.len..], extra);
    return merged;
}

test "rejects empty Hostinger token before HTTP dispatch" {
    try std.testing.expectError(error.MissingHostingerToken, getWithHeaders(std.testing.io, std.testing.allocator, "", "https://example.invalid", &.{}));
}

test "merges Hostinger route headers after auth defaults" {
    const allocator = std.testing.allocator;
    const base_headers = [_]std.http.Header{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = "Bearer token" },
    };
    const extra = [_]std.http.Header{.{ .name = "X-Request-Id", .value = "route" }};
    const merged = try mergeHeaders(allocator, &base_headers, &extra);
    defer allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 4), merged.len);
    try std.testing.expectEqualStrings("Accept", merged[0].name);
    try std.testing.expectEqualStrings("application/json", merged[0].value);
    try std.testing.expectEqualStrings("Content-Type", merged[1].name);
    try std.testing.expectEqualStrings("Authorization", merged[2].name);
    try std.testing.expectEqualStrings("X-Request-Id", merged[3].name);
}
