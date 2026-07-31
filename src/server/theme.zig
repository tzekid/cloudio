//! Server-owned appearance preference for every HTML response.

const std = @import("std");
const http = @import("http");

pub const secure_cookie_name = "__Host-cloudio_theme";
pub const local_cookie_name = "cloudio_theme";
pub const max_age_seconds: i64 = 365 * 24 * 60 * 60;

pub const Preference = enum {
    light,
    dark,
    system,

    pub fn value(self: Preference) []const u8 {
        return @tagName(self);
    }

    pub fn rootClass(self: Preference) []const u8 {
        return switch (self) {
            .light => "theme-light",
            .dark => "theme-dark",
            .system => "theme-system",
        };
    }
};

pub fn parse(value: []const u8) ?Preference {
    if (std.mem.eql(u8, value, "light")) return .light;
    if (std.mem.eql(u8, value, "dark")) return .dark;
    if (std.mem.eql(u8, value, "system")) return .system;
    return null;
}

pub fn cookieName(secure_origin: bool) []const u8 {
    return if (secure_origin) secure_cookie_name else local_cookie_name;
}

pub fn fromRequest(request: http.Request, secure_origin: bool) Preference {
    const header = request.header("cookie") orelse return .light;
    const expected_name = cookieName(secure_origin);
    var found: ?Preference = null;
    var items = std.mem.splitScalar(u8, header, ';');
    while (items.next()) |raw| {
        const pair = std.mem.trim(u8, raw, " \t");
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, pair[0..equals], " \t"), expected_name)) continue;
        if (found != null) return .light;
        found = parse(pair[equals + 1 ..]) orelse return .light;
    }
    return found orelse .light;
}

pub fn writeCookie(
    writer: anytype,
    secure_origin: bool,
    preference: Preference,
) !void {
    try writer.print(
        "Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Strict; Max-Age={d}{s}\r\n",
        .{
            cookieName(secure_origin),
            preference.value(),
            max_age_seconds,
            if (secure_origin) "; Secure" else "",
        },
    );
}

test "appearance preference is a closed enum with a light fallback" {
    try std.testing.expectEqual(Preference.light, parse("light").?);
    try std.testing.expectEqual(Preference.dark, parse("dark").?);
    try std.testing.expectEqual(Preference.system, parse("system").?);
    try std.testing.expect(parse("Dark") == null);
    try std.testing.expect(parse("dark%00") == null);

    const invalid: http.Request = .{
        .method = "GET",
        .target = "/",
        .headers = &.{.{ .name = "Cookie", .value = "cloudio_theme=unknown" }},
        .body = "",
    };
    try std.testing.expectEqual(Preference.light, fromRequest(invalid, false));
    const duplicated: http.Request = .{
        .method = "GET",
        .target = "/",
        .headers = &.{.{
            .name = "Cookie",
            .value = "cloudio_theme=dark; cloudio_theme=dark",
        }},
        .body = "",
    };
    try std.testing.expectEqual(Preference.light, fromRequest(duplicated, false));
}

test "appearance cookie is host-only secure and unavailable to scripts" {
    var secure = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer secure.deinit();
    try writeCookie(&secure.writer, true, .dark);
    try std.testing.expectEqualStrings(
        "Set-Cookie: __Host-cloudio_theme=dark; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000; Secure\r\n",
        secure.written(),
    );

    var local = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer local.deinit();
    try writeCookie(&local.writer, false, .system);
    try std.testing.expectEqualStrings(
        "Set-Cookie: cloudio_theme=system; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000\r\n",
        local.written(),
    );
}
