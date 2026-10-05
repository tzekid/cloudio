//! The single request-policy boundary: sessions, the anonymous allowlist,
//! page rendering, native form dispatch, and the passkey JSON API.

const std = @import("std");
const app_authentication = @import("../app/authentication.zig");
const app_browser_run = @import("../app/browser_run.zig");
const http = @import("../http/root.zig");
const auth = @import("auth.zig");
const common = @import("common.zig");
const context = @import("context.zig");
const forms = @import("forms.zig");
const pages = @import("pages.zig");
const rate_limit = @import("rate_limit.zig");
const api = @import("api.zig");
const theme = @import("theme.zig");

const web_root = "web";

pub const security_headers =
    "Cache-Control: no-store\r\n" ++
    "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'\r\n" ++
    "X-Content-Type-Options: nosniff\r\n" ++
    "Referrer-Policy: same-origin\r\n" ++
    "X-Frame-Options: DENY\r\n" ++
    "Cross-Origin-Opener-Policy: same-origin\r\n" ++
    "Permissions-Policy: camera=(), geolocation=(), microphone=(), payment=(), publickey-credentials-create=(self), publickey-credentials-get=(self), usb=()\r\n";

pub fn handle(ctx: context.Context, stream: std.Io.net.Stream) !void {
    defer stream.close(ctx.io);
    var read_buffer: [8192]u8 = undefined;
    var reader = stream.reader(ctx.io, &read_buffer);
    var write_buffer: [8192]u8 = undefined;
    var stream_writer = stream.writer(ctx.io, &write_buffer);
    const out = &stream_writer.interface;

    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const request = (http.request.read(arena_state.allocator(), &reader.interface, .{}) catch |err| switch (err) {
        error.BodyTooLarge => return writeJson(out, 413, "{\"error\":\"payload_too_large\"}\n"),
        error.BadRequest, error.TooManyHeaders, error.StreamTooLong => return writeJson(out, 400, "{\"error\":\"bad_request\"}\n"),
        else => return err,
    }) orelse return;

    app_authentication.validatePolicy(ctx.config.auth_origin, ctx.config.auth_rp_id) catch |err| {
        std.debug.print("cloudio auth policy invalid: {s}\n", .{@errorName(err)});
        return writeJson(out, 500, "{\"error\":\"auth_policy_invalid\"}\n");
    };

    const secure_origin = std.mem.startsWith(u8, ctx.config.auth_origin, "https://");
    const session: ?app_authentication.Session = if (auth.sessionToken(request, secure_origin)) |token|
        try app_authentication.validateSession(appAuthContext(ctx), token)
    else
        null;
    defer if (session) |value| value.deinit(ctx.gpa);
    var request_ctx = ctx;
    request_ctx.response_headers = security_headers;
    if (session) |value| {
        request_ctx.auth_user_id = value.user_id;
        request_ctx.auth_csrf_token = value.csrf_token;
    }

    const path = request.path();
    if (std.mem.startsWith(u8, path, "/api/")) return handleApi(request_ctx, request, session != null, out);
    try handlePage(request_ctx, request, session != null, secure_origin, out);
}

fn handlePage(ctx: context.Context, request: http.Request, authenticated: bool, secure_origin: bool, out: *std.Io.Writer) !void {
    const path = request.path();
    const head = std.mem.eql(u8, request.method, "HEAD");
    const readable = head or std.mem.eql(u8, request.method, "GET");
    if (!authenticated and !staticPathIsPublic(path, try ctx.db.auth().bootstrapActive(nowSeconds()))) {
        return http.response.write(out, 302, "text/html; charset=utf-8", security_headers ++ "Location: /login.html\r\n", "");
    }
    if (authenticated and std.mem.eql(u8, path, "/login.html")) {
        return http.response.write(out, 302, "text/html; charset=utf-8", security_headers ++ "Location: /\r\n", "");
    }

    const preference = theme.fromRequest(request, secure_origin);
    if (forms.isFormPath(path)) {
        if (!std.mem.eql(u8, request.method, "POST")) return writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
        return forms.handle(ctx, request, preference, secure_origin, out);
    }
    if (std.mem.eql(u8, path, "/browser/artifact")) {
        if (!readable) return writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
        return handleBrowserArtifact(ctx, request, out);
    }

    const public_page = pages.isPublicPagePath(path);
    if (public_page or (authenticated and pages.isPagePath(path))) {
        if (!readable) return writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
        var body = std.Io.Writer.Allocating.init(ctx.gpa);
        defer body.deinit();
        const rendered = if (public_page)
            pages.renderPublic(ctx, path, preference, &body.writer)
        else
            pages.render(ctx, request, path, preference, &body.writer);
        _ = rendered catch |err| {
            std.debug.print("cloudio page {s} failed: {s}\n", .{ path, @errorName(err) });
            return writeJson(out, 500, "{\"error\":\"page_unavailable\"}\n");
        };
        return http.response.writeRepresentation(out, 200, "text/html; charset=utf-8", security_headers, body.written(), head);
    }
    try http.static.serveWithHeaders(ctx.io, ctx.gpa, web_root, path, http.static.default_max_file_bytes, security_headers, head, out);
}

fn handleApi(ctx: context.Context, request: http.Request, authenticated: bool, out: *std.Io.Writer) !void {
    const path = request.path();
    // Default deny happens before route discovery: anonymous callers cannot
    // use status codes to enumerate private endpoints.
    if (!authenticated and !publicApiPath(path)) return writeJson(out, 401, "{\"error\":\"unauthorized\"}\n");

    const matched = http.router.match(api.Route, &api.all, request.method, path) orelse {
        if (http.router.pathExists(api.Route, &api.all, path)) return writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
        return writeJson(out, 404, "{\"error\":\"not_found\"}\n");
    };
    const route = matched.route;
    if (!auth.originMatches(request, ctx.config.auth_origin)) return writeJson(out, 403, "{\"error\":\"origin_denied\"}\n");
    if (!auth.hasJsonBody(request)) return writeJson(out, 400, "{\"error\":\"json_content_type_required\"}\n");
    if (route.public) {
        if (!allowAuthRequest(ctx, request, path)) {
            return http.response.write(out, 429, "application/json", security_headers ++ "Retry-After: 60\r\n", "{\"error\":\"rate_limited\"}\n");
        }
    } else if (!auth.constantTimeEqual(request.header("x-cloudio-csrf") orelse "", ctx.auth_csrf_token.?)) {
        return writeJson(out, 403, "{\"error\":\"csrf_denied\"}\n");
    }

    var request_ctx = ctx;
    request_ctx.write_meta = .{ .actor = ctx.auth_user_id orelse "public-auth" };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    const status = route.handler(request_ctx, request, matched.params, &body.writer, &headers.writer) catch |err| {
        const mapped = common.failure(err);
        if (mapped.status >= 500) std.debug.print("cloudio handler {s} failed: {s}\n", .{ route.pattern, @errorName(err) });
        var error_body: [96]u8 = undefined;
        return writeJson(out, mapped.status, try std.fmt.bufPrint(&error_body, "{{\"error\":\"{s}\"}}\n", .{mapped.code}));
    };
    try http.response.write(out, status, "application/json", headers.written(), body.written());
}

fn handleBrowserArtifact(ctx: context.Context, request: http.Request, out: *std.Io.Writer) !void {
    const id = request.query("id") orelse return writeJson(out, 404, "{\"error\":\"not_found\"}\n");
    const artifact = app_browser_run.artifact(context.browserRun(ctx), id) catch |err| switch (err) {
        error.BrowserRunArtifactExpired => return writeJson(out, 410, "{\"error\":\"artifact_expired\"}\n"),
        error.BrowserRunArtifactNotFound, error.BrowserRunArtifactUnsafe => return writeJson(out, 404, "{\"error\":\"not_found\"}\n"),
        else => |other| return other,
    };
    defer artifact.deinit(ctx.gpa);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (artifact.attachment_only or std.mem.eql(u8, request.query("download") orelse "", "1")) {
        try headers.writer.print("Content-Disposition: attachment; filename=\"{s}\"\r\n", .{artifact.filename});
    }
    try http.response.writeFile(ctx.io, out, 200, artifact.content_type, headers.written(), artifact.path, std.mem.eql(u8, request.method, "HEAD"));
}

fn appAuthContext(ctx: context.Context) app_authentication.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .origin = ctx.config.auth_origin,
        .rp_id = ctx.config.auth_rp_id,
    };
}

fn staticPathIsPublic(path: []const u8, bootstrap_active: bool) bool {
    if (std.mem.eql(u8, path, "/login.html") or
        std.mem.eql(u8, path, "/assets/app.css") or
        std.mem.eql(u8, path, "/assets/passkeys.js") or
        std.mem.eql(u8, path, "/assets/pages/login.js"))
    {
        return true;
    }
    return bootstrap_active and
        (std.mem.eql(u8, path, "/setup.html") or
            std.mem.eql(u8, path, "/assets/pages/setup.js"));
}

fn publicApiPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "/api/auth/setup/options") or
        std.mem.eql(u8, path, "/api/auth/setup/verify") or
        std.mem.eql(u8, path, "/api/auth/login/options") or
        std.mem.eql(u8, path, "/api/auth/login/verify");
}

fn allowAuthRequest(ctx: context.Context, request: http.Request, path: []const u8) bool {
    const now = nowSeconds();
    const setup = std.mem.startsWith(u8, path, "/api/auth/setup/");
    const verify = std.mem.endsWith(u8, path, "/verify");
    const category: []const u8 = if (setup) "setup" else if (verify) "verify" else "options";
    if (!rate_limit.allow(category, if (setup) 40 else 100, 5 * 60, now)) return false;

    if (!ctx.trust_proxy_client_ip) return true;
    const forwarded = request.header("x-forwarded-for") orelse return true;
    const first = std.mem.trim(u8, forwarded[0 .. std.mem.indexOfScalar(u8, forwarded, ',') orelse forwarded.len], " \t");
    if (first.len == 0 or first.len > 64) return false;
    var key_buffer: [80]u8 = undefined;
    const client_key = std.fmt.bufPrint(&key_buffer, "{s}:{s}", .{ category, first }) catch return false;
    if (setup) return rate_limit.allow(client_key, 12, 10 * 60, now);
    if (verify) return rate_limit.allow(client_key, 20, 5 * 60, now);
    return rate_limit.allow(client_key, 30, 5 * 60, now);
}

fn nowSeconds() i64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (std.os.linux.errno(rc) != .SUCCESS or ts.sec < 0) return 0;
    return @intCast(ts.sec);
}

fn writeJson(out: *std.Io.Writer, status_code: u16, body: []const u8) !void {
    try http.response.write(out, status_code, "application/json", security_headers, body);
}

test "anonymous surface is an explicit allowlist" {
    try std.testing.expect(staticPathIsPublic("/login.html", false));
    try std.testing.expect(!staticPathIsPublic("/assets/app.js", false));
    try std.testing.expect(!staticPathIsPublic("/setup.html", false));
    try std.testing.expect(!staticPathIsPublic("/settings.html", true));
    try std.testing.expect(!staticPathIsPublic("/settings/theme", true));
    try std.testing.expect(staticPathIsPublic("/setup.html", true));
    try std.testing.expect(publicApiPath("/api/auth/login/options"));
    try std.testing.expect(!publicApiPath("/api/auth/credentials/options"));
}
