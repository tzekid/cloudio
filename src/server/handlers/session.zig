const std = @import("std");
const http = @import("http");
const auth = @import("../auth.zig");
const context = @import("../context.zig");

pub fn login(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, extra_headers: *std.Io.Writer) !u16 {
    const token = ctx.config.platform_token orelse {
        try writer.writeAll("{\"error\":\"login_disabled\"}\n");
        return 400;
    };
    const provided = loginTokenFromBody(ctx.gpa, request.body) orelse {
        try writer.writeAll("{\"error\":\"bad_request\"}\n");
        return 400;
    };
    defer ctx.gpa.free(provided);
    if (!auth.tokenEquals(provided, token)) {
        try writer.writeAll("{\"error\":\"unauthorized\"}\n");
        return 401;
    }
    try extra_headers.print(
        "Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Strict\r\n",
        .{ auth.cookie_name, token },
    );
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

fn loginTokenFromBody(gpa: std.mem.Allocator, body: []const u8) ?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const value = parsed.value.object.get("token") orelse return null;
    if (value != .string) return null;
    return gpa.dupe(u8, value.string) catch null;
}

test "login token body parser rejects malformed payloads" {
    const gpa = std.testing.allocator;
    const token = loginTokenFromBody(gpa, "{\"token\":\"abc\"}").?;
    defer gpa.free(token);
    try std.testing.expectEqualStrings("abc", token);
    try std.testing.expect(loginTokenFromBody(gpa, "{}") == null);
}
