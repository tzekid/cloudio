const std = @import("std");
const http = @import("http");

pub const cookie_name = "cloudio_token";

pub fn isAuthorized(request: http.Request, token: []const u8) bool {
    if (bearerToken(request.header("authorization") orelse "")) |candidate| {
        if (tokenEquals(candidate, token)) return true;
    }
    if (cookieValue(request.header("cookie") orelse "", cookie_name)) |candidate| {
        if (tokenEquals(candidate, token)) return true;
    }
    return false;
}

pub fn actor(request: http.Request, auth_enabled: bool) ?[]const u8 {
    if (request.header("x-cloudio-actor")) |value| {
        if (!isValidActor(value)) return null;
        return value;
    }
    if (request.header("authorization") != null) return "api";
    if (request.header("cookie") != null) return "web";
    return if (auth_enabled) "api" else "local";
}

pub fn isValidIdempotencyKey(value: []const u8) bool {
    if (value.len < 8 or value.len > 128) return false;
    for (value) |ch| {
        switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '-', '.', ':', '/' => {},
            else => return false,
        }
    }
    return true;
}

pub fn mutationFingerprint(request: http.Request) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(request.method);
    hasher.update("\n");
    hasher.update(request.target);
    hasher.update("\n");
    hasher.update(request.body);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn tokenEquals(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var difference: u8 = 0;
    for (a, b) |left, right| difference |= left ^ right;
    return difference == 0;
}

fn bearerToken(authorization: []const u8) ?[]const u8 {
    const prefix = "Bearer ";
    if (!std.mem.startsWith(u8, authorization, prefix)) return null;
    const token = std.mem.trim(u8, authorization[prefix.len..], " \t");
    return if (token.len == 0) null else token;
}

fn cookieValue(header: []const u8, name: []const u8) ?[]const u8 {
    var items = std.mem.splitScalar(u8, header, ';');
    while (items.next()) |raw| {
        const pair = std.mem.trim(u8, raw, " \t");
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, pair[0..equals], " \t"), name)) return pair[equals + 1 ..];
    }
    return null;
}

fn isValidActor(value: []const u8) bool {
    if (value.len == 0 or value.len > 64) return false;
    for (value) |ch| {
        switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '-', '.', '@', ':' => {},
            else => return false,
        }
    }
    return true;
}

test "authentication helpers validate tokens metadata and fingerprints" {
    const request = http.Request{
        .method = "POST",
        .target = "/api/apps",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer secret" },
            .{ .name = "Idempotency-Key", .value = "request-1234" },
        },
        .body = "{}",
    };
    try std.testing.expect(isAuthorized(request, "secret"));
    try std.testing.expect(isValidIdempotencyKey(request.header("idempotency-key").?));
    try std.testing.expectEqualStrings("api", actor(request, true).?);
    const first = mutationFingerprint(request);
    const second = mutationFingerprint(request);
    try std.testing.expectEqualSlices(u8, &first, &second);
}
