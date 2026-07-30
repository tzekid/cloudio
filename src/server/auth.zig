const std = @import("std");
const http = @import("http");

pub const secure_cookie_name = "__Host-cloudio_session";
pub const local_cookie_name = "cloudio_session";

pub fn cookieName(secure_origin: bool) []const u8 {
    return if (secure_origin) secure_cookie_name else local_cookie_name;
}

pub fn sessionToken(request: http.Request, secure_origin: bool) ?[]const u8 {
    return cookieValue(
        request.header("cookie") orelse "",
        cookieName(secure_origin),
    );
}

pub fn writeSessionCookie(
    writer: anytype,
    secure_origin: bool,
    token: []const u8,
    max_age: i64,
) !void {
    try writer.print(
        "Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Strict; Max-Age={d}{s}\r\n",
        .{
            cookieName(secure_origin),
            token,
            max_age,
            if (secure_origin) "; Secure" else "",
        },
    );
}

pub fn writeClearedSessionCookie(writer: anytype, secure_origin: bool) !void {
    try writer.print(
        "Set-Cookie: {s}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0{s}\r\n",
        .{ cookieName(secure_origin), if (secure_origin) "; Secure" else "" },
    );
}

pub fn originMatches(request: http.Request, expected_origin: []const u8) bool {
    const provided = request.header("origin") orelse return false;
    return constantTimeEqual(provided, expected_origin);
}

pub fn isUnsafeMethod(method: []const u8) bool {
    return std.mem.eql(u8, method, "POST") or
        std.mem.eql(u8, method, "PUT") or
        std.mem.eql(u8, method, "PATCH") or
        std.mem.eql(u8, method, "DELETE");
}

pub fn hasJsonBody(request: http.Request) bool {
    if (request.body.len == 0) return true;
    const value = request.header("content-type") orelse return false;
    return std.ascii.startsWithIgnoreCase(value, "application/json");
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

pub fn constantTimeEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var difference: u8 = 0;
    for (a, b) |left, right| difference |= left ^ right;
    return difference == 0;
}

pub fn cookieValue(header: []const u8, name: []const u8) ?[]const u8 {
    var items = std.mem.splitScalar(u8, header, ';');
    while (items.next()) |raw| {
        const pair = std.mem.trim(u8, raw, " \t");
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, pair[0..equals], " \t"), name)) {
            const value = pair[equals + 1 ..];
            return if (value.len == 0) null else value;
        }
    }
    return null;
}

test "session cookie is host-only secure and never readable by script" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeSessionCookie(&out.writer, true, "opaque", 43200);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "__Host-cloudio_session=opaque") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "; Secure") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "; HttpOnly") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "; SameSite=Strict") != null);
}

test "authentication helpers validate metadata fingerprints and origins" {
    const request = http.Request{
        .method = "POST",
        .target = "/api/apps",
        .headers = &.{
            .{ .name = "Origin", .value = "https://cloudio.example.test" },
            .{ .name = "Cookie", .value = "__Host-cloudio_session=secret" },
            .{ .name = "Content-Type", .value = "application/json; charset=utf-8" },
        },
        .body = "{}",
    };
    try std.testing.expectEqualStrings("secret", sessionToken(request, true).?);
    try std.testing.expect(originMatches(request, "https://cloudio.example.test"));
    try std.testing.expect(hasJsonBody(request));
    const first = mutationFingerprint(request);
    const second = mutationFingerprint(request);
    try std.testing.expectEqualSlices(u8, &first, &second);
}
