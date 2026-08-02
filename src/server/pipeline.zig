const std = @import("std");
const app_authentication = @import("app_authentication");
const app_writes = @import("app_writes");
const http = @import("http");
const auth = @import("auth.zig");
const common = @import("common.zig");
const context = @import("context.zig");
const form = @import("form.zig");
const pages = @import("pages.zig");
const rate_limit = @import("rate_limit.zig");
const routes = @import("routes.zig");
const theme = @import("theme.zig");
const types = @import("types.zig");

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
        error.BodyTooLarge => {
            try writeJson(out, 413, "{\"error\":\"payload_too_large\"}\n");
            return;
        },
        error.BadRequest, error.TooManyHeaders => {
            try writeJson(out, 400, "{\"error\":\"bad_request\"}\n");
            return;
        },
        else => return err,
    }) orelse return;

    app_authentication.validatePolicy(ctx.config.auth_origin, ctx.config.auth_rp_id) catch |err| {
        std.debug.print("cloudio auth policy invalid: {s}\n", .{@errorName(err)});
        try writeJson(out, 500, "{\"error\":\"auth_policy_invalid\"}\n");
        return;
    };

    const secure_origin = std.mem.startsWith(u8, ctx.config.auth_origin, "https://");
    const preference = theme.fromRequest(request, secure_origin);
    const raw_session_token = auth.sessionToken(request, secure_origin);
    const session_value: ?app_authentication.Session = if (raw_session_token) |token|
        try app_authentication.validateSession(appAuthContext(ctx), token)
    else
        null;
    defer if (session_value) |session| session.deinit(ctx.gpa);
    const authenticated = session_value != null;
    const path = request.path();
    var request_ctx = ctx;
    request_ctx.response_headers = security_headers;
    if (session_value) |session| {
        request_ctx.auth_user_id = session.user_id;
        request_ctx.auth_csrf_token = session.csrf_token;
    }

    if (!std.mem.startsWith(u8, path, "/api/")) {
        const bootstrap_active = try ctx.db.auth().bootstrapActive(nowSeconds());
        if (!authenticated and !staticPathIsPublic(path, bootstrap_active)) {
            try http.response.write(
                out,
                302,
                "text/html; charset=utf-8",
                security_headers ++ "Location: /login.html\r\n",
                "",
            );
            return;
        }
        if (pages.isPublicPagePath(path)) {
            if (!std.mem.eql(u8, request.method, "GET") and !std.mem.eql(u8, request.method, "HEAD")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            var page_body = std.Io.Writer.Allocating.init(ctx.gpa);
            defer page_body.deinit();
            _ = pages.renderPublic(request_ctx, path, preference, &page_body.writer) catch |err| {
                std.debug.print("cloudio public page {s} failed: {s}\n", .{ path, @errorName(err) });
                try writeJson(out, 500, "{\"error\":\"page_unavailable\"}\n");
                return;
            };
            try http.response.write(
                out,
                200,
                "text/html; charset=utf-8",
                security_headers,
                if (std.mem.eql(u8, request.method, "HEAD")) "" else page_body.written(),
            );
            return;
        }
        if (std.mem.eql(u8, path, "/settings/theme")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleThemeSettings(request_ctx, request, secure_origin, preference, out);
            return;
        }
        if (authenticated and pages.isPagePath(path)) {
            if (!std.mem.eql(u8, request.method, "GET") and !std.mem.eql(u8, request.method, "HEAD")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            var page_body = std.Io.Writer.Allocating.init(ctx.gpa);
            defer page_body.deinit();
            _ = pages.render(request_ctx, request, path, preference, &page_body.writer) catch |err| {
                std.debug.print("cloudio page {s} failed: {s}\n", .{ path, @errorName(err) });
                try writeJson(out, 500, "{\"error\":\"page_unavailable\"}\n");
                return;
            };
            try http.response.write(
                out,
                200,
                "text/html; charset=utf-8",
                security_headers,
                if (std.mem.eql(u8, request.method, "HEAD")) "" else page_body.written(),
            );
            return;
        }
        try http.static.serveWithHeaders(
            ctx.io,
            ctx.gpa,
            web_root,
            path,
            http.static.default_max_file_bytes,
            security_headers,
            out,
        );
        return;
    }

    // Default deny happens before route discovery: anonymous callers cannot
    // use status codes to enumerate private endpoints.
    if (!authenticated and !publicApiPath(path)) {
        try writeJson(out, 401, "{\"error\":\"unauthorized\"}\n");
        return;
    }

    const matched = http.router.match(types.Route, &routes.all, request.method, path) orelse {
        if (http.router.pathExists(types.Route, &routes.all, path)) {
            try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
        } else {
            try writeJson(out, 404, "{\"error\":\"not_found\"}\n");
        }
        return;
    };
    const route = matched.route;
    if (route.access == .authenticated and !authenticated) {
        try writeJson(out, 401, "{\"error\":\"unauthorized\"}\n");
        return;
    }

    if (auth.isUnsafeMethod(request.method)) {
        if (!auth.originMatches(request, ctx.config.auth_origin)) {
            try writeJson(out, 403, "{\"error\":\"origin_denied\"}\n");
            return;
        }
        if (!auth.hasJsonBody(request)) {
            try writeJson(out, 400, "{\"error\":\"json_content_type_required\"}\n");
            return;
        }
        if (route.access == .authenticated) {
            const session = session_value.?;
            const csrf = request.header("x-cloudio-csrf") orelse "";
            if (!auth.constantTimeEqual(csrf, session.csrf_token)) {
                try writeJson(out, 403, "{\"error\":\"csrf_denied\"}\n");
                return;
            }
        }
    }

    if (route.access == .public and !allowAuthRequest(ctx, request, path)) {
        try http.response.write(
            out,
            429,
            "application/json",
            security_headers ++ "Retry-After: 60\r\n",
            "{\"error\":\"rate_limited\"}\n",
        );
        return;
    }

    if (route.mutation == .destructive and
        !std.mem.eql(u8, request.header("x-cloudio-confirm") orelse "", "confirmed"))
    {
        try writeJson(
            out,
            428,
            "{\"error\":\"confirmation_required\",\"required_header\":\"X-Cloudio-Confirm: confirmed\"}\n",
        );
        return;
    }

    const idempotency_key = request.header("idempotency-key") orelse "";
    request_ctx.write_meta = .{
        .actor = if (authenticated) "passkey" else "public-auth",
        .idempotency_key = if (idempotency_key.len == 0) null else idempotency_key,
    };

    if (route.mutation != .none) {
        if (!auth.isValidIdempotencyKey(idempotency_key)) {
            try writeJson(
                out,
                428,
                "{\"error\":\"idempotency_key_required\",\"required_header\":\"Idempotency-Key\"}\n",
            );
            return;
        }
        const fingerprint = auth.mutationFingerprint(request);
        const claim = try app_writes.beginMutation(
            ctx.gpa,
            ctx.db,
            idempotency_key,
            &fingerprint,
            request.method,
            request.target,
            "passkey",
        );
        switch (claim) {
            .execute => {},
            .replay => |stored| {
                defer stored.deinit(ctx.gpa);
                try http.response.write(
                    out,
                    stored.status,
                    "application/json",
                    security_headers ++ "Idempotency-Replayed: true\r\n",
                    stored.body,
                );
                return;
            },
            .in_progress => {
                try writeJson(out, 409, "{\"error\":\"request_in_progress\"}\n");
                return;
            },
            .conflict => {
                try writeJson(out, 409, "{\"error\":\"idempotency_key_reused\"}\n");
                return;
            },
        }
    }

    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    var extra_headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer extra_headers.deinit();
    try extra_headers.writer.writeAll(security_headers);
    const status_code = route.handler(
        request_ctx,
        request,
        matched.params,
        &body.writer,
        &extra_headers.writer,
    ) catch |err| {
        const mapped = common.mapApiError(err);
        if (mapped.status >= 500) {
            std.debug.print("cloudio handler {s} failed: {s}\n", .{ route.pattern, @errorName(err) });
        }
        if (route.mutation != .none) {
            app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, mapped.body) catch |complete_err| {
                std.debug.print("cloudio idempotency completion failed: {s}\n", .{@errorName(complete_err)});
            };
        }
        try http.response.write(
            out,
            mapped.status,
            "application/json",
            security_headers,
            mapped.body,
        );
        return;
    };
    if (route.mutation != .none) {
        try app_writes.completeMutation(ctx.db, idempotency_key, status_code, body.written());
    }
    try http.response.write(
        out,
        status_code,
        "application/json",
        extra_headers.written(),
        body.written(),
    );
}

fn handleThemeSettings(
    ctx: context.Context,
    request: http.Request,
    secure_origin: bool,
    current: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeSettingsError(ctx, request, current, 403, "security", out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeSettingsError(ctx, request, current, 400, "request", out);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeSettingsError(ctx, request, current, 400, "request", out);
        return;
    };
    for (fields.entries) |field| {
        if (!std.mem.eql(u8, field.name, "csrf_token") and
            !std.mem.eql(u8, field.name, "theme"))
        {
            try writeSettingsError(ctx, request, current, 400, "request", out);
            return;
        }
    }
    const csrf = fields.get("csrf_token") catch {
        try writeSettingsError(ctx, request, current, 403, "security", out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeSettingsError(ctx, request, current, 403, "security", out);
        return;
    }
    const raw_preference = fields.get("theme") catch {
        try writeSettingsError(ctx, request, current, 400, "theme", out);
        return;
    };
    const next = theme.parse(raw_preference) orelse {
        try writeSettingsError(ctx, request, current, 400, "theme", out);
        return;
    };

    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    try theme.writeCookie(&headers.writer, secure_origin, next);
    try headers.writer.writeAll("Location: /settings.html?saved=1\r\n");
    try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
}

fn writeSettingsError(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    status: u16,
    code: []const u8,
    out: *std.Io.Writer,
) !void {
    var target_buffer: [64]u8 = undefined;
    const target = try std.fmt.bufPrint(&target_buffer, "/settings.html?error={s}", .{code});
    const page_request: http.Request = .{
        .method = "GET",
        .target = target,
        .headers = request.headers,
        .body = "",
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/settings.html", preference, &body.writer);
    try http.response.write(
        out,
        status,
        "text/html; charset=utf-8",
        security_headers,
        body.written(),
    );
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
    const category: []const u8 = if (std.mem.startsWith(u8, path, "/api/auth/setup/"))
        "setup"
    else if (std.mem.endsWith(u8, path, "/verify"))
        "verify"
    else
        "options";
    const global_limit: u32 = if (std.mem.eql(u8, category, "setup")) 40 else 100;
    if (!rate_limit.allow(category, global_limit, 5 * 60, now)) return false;

    if (!ctx.trust_proxy_client_ip) return true;
    const forwarded = request.header("x-forwarded-for") orelse return true;
    const first = std.mem.trim(
        u8,
        if (std.mem.indexOfScalar(u8, forwarded, ',')) |comma| forwarded[0..comma] else forwarded,
        " \t",
    );
    if (first.len == 0 or first.len > 64) return false;
    var key_buffer: [80]u8 = undefined;
    const client_key = std.fmt.bufPrint(&key_buffer, "{s}:{s}", .{ category, first }) catch return false;
    if (std.mem.startsWith(u8, path, "/api/auth/setup/")) {
        return rate_limit.allow(client_key, 12, 10 * 60, now);
    }
    if (std.mem.endsWith(u8, path, "/verify")) {
        return rate_limit.allow(client_key, 20, 5 * 60, now);
    }
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
    try std.testing.expect(!publicApiPath("/api/dashboard"));
}

test "theme settings post enforces security and returns native PRG" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/pipeline-theme.db",
        .{tmp.sub_path},
    );
    defer allocator.free(db_path);
    var db = try @import("db_store").Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const ctx: context.Context = .{
        .io = std.testing.io,
        .gpa = allocator,
        .db = &db,
        .config = .{
            .domains = &.{},
            .auth_origin = "https://cloudio.example.test",
            .auth_rp_id = "cloudio.example.test",
        },
        .auth_user_id = "owner",
        .auth_csrf_token = "known-csrf",
    };
    const request: http.Request = .{
        .method = "POST",
        .target = "/settings/theme",
        .headers = &.{
            .{ .name = "Origin", .value = "https://cloudio.example.test" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        },
        .body = "csrf_token=known-csrf&theme=dark",
    };
    var success = std.Io.Writer.Allocating.init(allocator);
    defer success.deinit();
    try handleThemeSettings(ctx, request, true, .light, &success.writer);
    try std.testing.expect(std.mem.startsWith(u8, success.written(), "HTTP/1.1 303 See Other\r\n"));
    try std.testing.expect(std.mem.indexOf(
        u8,
        success.written(),
        "Set-Cookie: __Host-cloudio_theme=dark; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000; Secure\r\n",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, success.written(), "Location: /settings.html?saved=1\r\n") != null);

    var denied_request = request;
    denied_request.headers = &.{
        .{ .name = "Origin", .value = "https://wrong.example.test" },
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
    };
    var denied = std.Io.Writer.Allocating.init(allocator);
    defer denied.deinit();
    try handleThemeSettings(ctx, denied_request, true, .light, &denied.writer);
    try std.testing.expect(std.mem.startsWith(u8, denied.written(), "HTTP/1.1 403 Forbidden\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, denied.written(), "Set-Cookie:") == null);
    try std.testing.expect(std.mem.indexOf(u8, denied.written(), "class=\"theme-light\"") != null);
}
