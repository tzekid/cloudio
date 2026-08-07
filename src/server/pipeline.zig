const std = @import("std");
const app_authentication = @import("app_authentication");
const app_caddy_desired = @import("app_caddy_desired");
const app_browser_run = @import("app_browser_run");
const app_dns = @import("app_dns");
const app_nob_actions = @import("app_nob_actions");
const app_nob_projects = @import("app_nob_projects");
const app_nob_runtime = @import("app_nob_runtime");
const app_nob_secrets = @import("app_nob_secrets");
const app_refresh_cycle = @import("app_refresh_cycle");
const app_system_control = @import("app_system_control");
const app_vps = @import("app_vps");
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
        if (authenticated and std.mem.eql(u8, path, "/login.html")) {
            try http.response.write(
                out,
                302,
                "text/html; charset=utf-8",
                security_headers ++ "Location: /\r\n",
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
        if (std.mem.eql(u8, path, "/security/logout")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleSecurityLogout(request_ctx, request, secure_origin, out);
            return;
        }
        if (std.mem.eql(u8, path, "/dashboard/refresh")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleDashboardRefreshForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/projects/scan") or std.mem.eql(u8, path, "/projects/action")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleProjectsForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/routes/refresh") or
            std.mem.eql(u8, path, "/routes/route") or
            std.mem.eql(u8, path, "/routes/adopt") or
            std.mem.eql(u8, path, "/routes/apply"))
        {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleRoutesForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/docker/refresh") or std.mem.eql(u8, path, "/docker/action")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleDockerForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/dns/refresh") or std.mem.eql(u8, path, "/dns/record")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleDnsForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/browser/run")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleBrowserRunForm(request_ctx, request, preference, out);
            return;
        }
        if (std.mem.eql(u8, path, "/browser/artifact")) {
            if (!std.mem.eql(u8, request.method, "GET") and !std.mem.eql(u8, request.method, "HEAD")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleBrowserArtifact(request_ctx, request, out);
            return;
        }
        if (std.mem.eql(u8, path, "/vps/refresh") or std.mem.eql(u8, path, "/vps/action")) {
            if (!std.mem.eql(u8, request.method, "POST")) {
                try writeJson(out, 405, "{\"error\":\"method_not_allowed\"}\n");
                return;
            }
            try handleVpsForm(request_ctx, request, preference, out);
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
    const actor = request_ctx.auth_user_id orelse if (authenticated) "authenticated" else "public-auth";
    request_ctx.write_meta = .{
        .actor = actor,
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
            actor,
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

fn handleSecurityLogout(
    ctx: context.Context,
    request: http.Request,
    secure_origin: bool,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin) or !form.hasUrlEncodedBody(request)) {
        try writeJson(out, 403, "{\"error\":\"security_check_failed\"}\n");
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeJson(out, 400, "{\"error\":\"invalid_form\"}\n");
        return;
    };
    for (fields.entries) |field| {
        if (!std.mem.eql(u8, field.name, "csrf_token")) {
            try writeJson(out, 400, "{\"error\":\"invalid_form\"}\n");
            return;
        }
    }
    const csrf = fields.get("csrf_token") catch {
        try writeJson(out, 403, "{\"error\":\"csrf_denied\"}\n");
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeJson(out, 403, "{\"error\":\"csrf_denied\"}\n");
        return;
    }
    if (auth.sessionToken(request, secure_origin)) |token| {
        try app_authentication.revokeSession(appAuthContext(ctx), token);
    }
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    try auth.writeClearedSessionCookie(&headers.writer, secure_origin);
    try headers.writer.writeAll("Location: /login.html\r\n");
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

fn handleDashboardRefreshForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeDashboardFormResult(ctx, request, preference, 403, "/?refresh=security", false, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeDashboardFormResult(ctx, request, preference, 400, "/?refresh=request", false, out);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeDashboardFormResult(ctx, request, preference, 400, "/?refresh=request", false, out);
        return;
    };
    const allowed = [_][]const u8{ "csrf_token", "idempotency_key" };
    if (!formHasOnly(fields, &allowed)) {
        try writeDashboardFormResult(ctx, request, preference, 400, "/?refresh=request", false, out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeDashboardFormResult(ctx, request, preference, 403, "/?refresh=security", false, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeDashboardFormResult(ctx, request, preference, 403, "/?refresh=security", false, out);
        return;
    }
    const idempotency_key = fields.get("idempotency_key") catch {
        try writeDashboardFormResult(ctx, request, preference, 428, "/?refresh=idempotency", false, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeDashboardFormResult(ctx, request, preference, 428, "/?refresh=idempotency", false, out);
        return;
    }

    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(
        ctx.gpa,
        ctx.db,
        idempotency_key,
        &fingerprint,
        request.method,
        request.target,
        actor,
    );
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeDashboardFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeDashboardFormResult(ctx, request, preference, 409, "/?refresh=in_progress", false, out);
            return;
        },
        .conflict => {
            try writeDashboardFormResult(ctx, request, preference, 409, "/?refresh=idempotency", false, out);
            return;
        },
    }

    const result = app_refresh_cycle.runDashboard(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
    }) catch |err| {
        const status: u16 = if (err == error.RefreshInProgress) 409 else 500;
        const target = if (err == error.RefreshInProgress) "/?refresh=in_progress" else "/?refresh=failed";
        try app_writes.completeMutation(ctx.db, idempotency_key, status, target);
        try writeDashboardFormResult(ctx, request, preference, status, target, false, out);
        return;
    };
    const result_status = result.statusCode();
    const response_status: u16 = if (result_status == 200) 303 else result_status;
    const target: []const u8 = if (result_status == 200)
        "/?refresh=ok"
    else if (result_status == 207)
        "/?refresh=partial"
    else
        "/?refresh=failed";
    try app_writes.completeMutation(ctx.db, idempotency_key, response_status, target);
    try writeDashboardFormResult(ctx, request, preference, response_status, target, false, out);
}

fn writeDashboardFormResult(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    status: u16,
    target: []const u8,
    replayed: bool,
    out: *std.Io.Writer,
) !void {
    if (!std.mem.startsWith(u8, target, "/?refresh=")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }

    const page_request: http.Request = .{
        .method = "GET",
        .target = target,
        .headers = request.headers,
        .body = "",
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn handleProjectsForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeProjectsFormResult(ctx, request, preference, 403, "/projects.html?error=security", false, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    }

    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fields = form.parse(arena, request.body) catch {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    };
    const is_scan = std.mem.eql(u8, request.path(), "/projects/scan");
    const allowed_scan = [_][]const u8{ "csrf_token", "idempotency_key" };
    if (is_scan and !formHasOnly(fields, &allowed_scan)) {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    }
    const operation = if (is_scan) "scan" else fields.get("operation") catch {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    };
    if (!is_scan and !projectFormShapeValid(fields, operation)) {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeProjectsFormResult(ctx, request, preference, 403, "/projects.html?error=security", false, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeProjectsFormResult(ctx, request, preference, 403, "/projects.html?error=security", false, out);
        return;
    }
    const idempotency_key = fields.get("idempotency_key") catch {
        try writeProjectsFormResult(ctx, request, preference, 428, "/projects.html?error=idempotency", false, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeProjectsFormResult(ctx, request, preference, 428, "/projects.html?error=idempotency", false, out);
        return;
    }

    const project_reference: ?[]const u8 = if (is_scan) null else fields.get("project") catch {
        try writeProjectsFormResult(ctx, request, preference, 400, "/projects.html?error=request", false, out);
        return;
    };
    if (std.mem.eql(u8, operation, "revoke") or std.mem.eql(u8, operation, "forget")) {
        const confirmation = fields.get("confirmation") catch "";
        requireProjectFormConfirmation(ctx, project_reference.?, confirmation) catch {
            const target = try std.fmt.allocPrint(arena, "/projects.html?project={s}&error=confirmation", .{project_reference.?});
            try writeProjectsFormResult(ctx, request, preference, 428, target, false, out);
            return;
        };
    }

    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(
        ctx.gpa,
        ctx.db,
        idempotency_key,
        &fingerprint,
        request.method,
        request.target,
        actor,
    );
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeProjectsFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            const target = try projectFormTarget(arena, project_reference, null, null, "in_progress", false);
            try writeProjectsFormResult(ctx, request, preference, 409, target, false, out);
            return;
        },
        .conflict => {
            const target = try projectFormTarget(arena, project_reference, null, null, "idempotency", false);
            try writeProjectsFormResult(ctx, request, preference, 409, target, false, out);
            return;
        },
    }

    const target = executeProjectForm(ctx, arena, fields, operation, project_reference, actor, idempotency_key) catch |err| {
        const mapped = common.mapApiError(err);
        const error_target = try projectFormTarget(arena, project_reference, null, null, projectFormErrorCode(err), false);
        try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, error_target);
        try writeProjectsFormResult(ctx, request, preference, mapped.status, error_target, false, out);
        return;
    };
    try app_writes.completeMutation(ctx.db, idempotency_key, 303, target);
    try writeProjectsFormResult(ctx, request, preference, 303, target, false, out);
}

fn executeProjectForm(
    ctx: context.Context,
    arena: std.mem.Allocator,
    fields: form.Form,
    operation: []const u8,
    project_reference: ?[]const u8,
    actor: []const u8,
    idempotency_key: []const u8,
) ![]const u8 {
    if (std.mem.eql(u8, operation, "scan")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        _ = try app_nob_projects.scan(context.nob(ctx), ctx.io, ctx.config.projects_root, ctx.config.nob_scan_depth);
        return try arena.dupe(u8, "/projects.html?result=scanned");
    }
    const reference = project_reference orelse return error.InvalidProjectForm;
    if (std.mem.eql(u8, operation, "trust")) {
        try app_nob_projects.trust(context.nob(ctx), reference, try fields.get("manifest_sha256"), actor);
        return try projectFormTarget(arena, reference, null, null, "trusted", true);
    }
    if (std.mem.eql(u8, operation, "revoke")) {
        try app_nob_projects.revoke(context.nob(ctx), reference, actor);
        return try projectFormTarget(arena, reference, null, null, "revoked", true);
    }
    if (std.mem.eql(u8, operation, "forget")) {
        try app_nob_projects.forget(context.nob(ctx), ctx.io, ctx.config.nob_cache_root, reference, actor);
        return try arena.dupe(u8, "/projects.html?view=all&result=forgotten");
    }
    if (std.mem.eql(u8, operation, "prepare")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        _ = try app_nob_runtime.prepareAndObserve(context.nobRuntime(ctx), reference);
        return try projectFormTarget(arena, reference, null, null, "prepared", true);
    }
    if (std.mem.eql(u8, operation, "observe")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        _ = try app_nob_runtime.observe(context.nobRuntime(ctx), reference);
        return try projectFormTarget(arena, reference, null, null, "observed", true);
    }
    if (std.mem.eql(u8, operation, "secret-bind")) {
        try app_nob_secrets.bind(
            context.nobSecrets(ctx),
            reference,
            try fields.get("secret_id"),
            try fields.get("source_kind"),
            try fields.get("source_ref"),
            actor,
        );
        return try projectFormTarget(arena, reference, null, null, "secret_bound", true);
    }
    if (std.mem.eql(u8, operation, "secret-unbind")) {
        try app_nob_secrets.unbind(context.nobSecrets(ctx), reference, try fields.get("secret_id"), actor);
        return try projectFormTarget(arena, reference, null, null, "secret_unbound", true);
    }
    if (std.mem.eql(u8, operation, "plan")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        const action_id = try fields.get("action_id");
        var parameters = try projectFormParameters(ctx, arena, fields, reference, action_id);
        defer parameters.object.deinit(arena);
        var planned = try app_nob_actions.plan(context.nobActions(ctx), reference, action_id, parameters, actor);
        defer planned.deinit(ctx.gpa);
        return try projectFormTarget(arena, reference, planned.id, null, "planned", true);
    }
    if (std.mem.eql(u8, operation, "resource-plan")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        var planned = try app_nob_actions.planResourceControl(
            context.nobActions(ctx),
            reference,
            try fields.get("resource_id"),
            try fields.get("control_name"),
            actor,
        );
        defer planned.deinit(ctx.gpa);
        return try projectFormTarget(arena, reference, planned.id, null, "planned", true);
    }
    if (std.mem.eql(u8, operation, "run")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        const plan_id = try fields.get("plan_id");
        const action_id = try fields.get("action_id");
        const approval: app_nob_actions.Approval = .{
            .confirmed = std.mem.eql(u8, optionalFormField(fields, "confirmation") orelse "", "confirmed"),
            .typed_project_id = optionalFormField(fields, "confirm_project_id"),
        };
        var queued = if (optionalFormField(fields, "resource_id")) |resource_id|
            try app_nob_actions.queueResourceControl(
                context.nobActions(ctx),
                reference,
                resource_id,
                try fields.get("control_name"),
                plan_id,
                approval,
                actor,
                idempotency_key,
            )
        else
            try app_nob_actions.queueAction(
                context.nobActions(ctx),
                reference,
                action_id,
                plan_id,
                approval,
                actor,
                idempotency_key,
            );
        defer queued.deinit(ctx.gpa);
        return try projectFormTarget(arena, reference, null, queued.id, "queued", true);
    }
    if (std.mem.eql(u8, operation, "cancel")) {
        const run_id = try fields.get("run_id");
        const project = (try app_nob_projects.find(context.nob(ctx), reference)) orelse return error.ProjectNotFound;
        defer project.deinit(ctx.gpa);
        const run = (try app_nob_actions.getRun(context.nobActions(ctx), run_id)) orelse return error.RunNotFound;
        defer run.deinit(ctx.gpa);
        if (run.project_id != project.id) return error.PlanRouteMismatch;
        try app_nob_actions.cancel(context.nobActions(ctx), run_id, actor);
        return try projectFormTarget(arena, reference, null, run_id, "cancel_requested", true);
    }
    return error.InvalidProjectForm;
}

fn projectFormParameters(
    ctx: context.Context,
    arena: std.mem.Allocator,
    fields: form.Form,
    project_reference: []const u8,
    action_id: []const u8,
) !std.json.Value {
    var details = (try app_nob_projects.show(context.nob(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer details.deinit(ctx.gpa);
    const declaration_bytes = blk: {
        for (details.actions.items) |action| if (std.mem.eql(u8, action.action_id, action_id)) break :blk action.declaration_json;
        return error.UnknownAction;
    };
    var declaration = try std.json.parseFromSlice(std.json.Value, arena, declaration_bytes, .{});
    defer declaration.deinit();
    const parameter_declarations = jsonArray(jsonMember(declaration.value, "parameters"));
    var parameters: std.json.ObjectMap = .empty;
    errdefer parameters.deinit(arena);
    for (fields.entries) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "param.")) continue;
        const name = entry.name["param.".len..];
        if (parameters.contains(name)) return error.InvalidProjectForm;
        const parameter = findParameterDeclaration(parameter_declarations, name) orelse return error.InvalidProjectForm;
        const required = jsonBool(parameter, "required");
        if (entry.value.len == 0 and !required) continue;
        const parameter_type = jsonString(parameter, "type");
        const value: std.json.Value = if (std.mem.eql(u8, parameter_type, "integer"))
            .{ .integer = std.fmt.parseInt(i64, entry.value, 10) catch return error.InvalidProjectForm }
        else if (std.mem.eql(u8, parameter_type, "boolean"))
            .{ .bool = if (std.mem.eql(u8, entry.value, "true")) true else if (std.mem.eql(u8, entry.value, "false")) false else return error.InvalidProjectForm }
        else if (std.mem.eql(u8, parameter_type, "enum")) enum_value: {
            var allowed = false;
            for (jsonArray(jsonMember(parameter, "values"))) |candidate| if (candidate == .string and std.mem.eql(u8, candidate.string, entry.value)) {
                allowed = true;
                break;
            };
            if (!allowed) return error.InvalidProjectForm;
            break :enum_value .{ .string = entry.value };
        } else if (std.mem.eql(u8, parameter_type, "string"))
            .{ .string = entry.value }
        else
            return error.InvalidProjectForm;
        try parameters.put(arena, name, value);
    }
    for (parameter_declarations) |parameter| {
        if (jsonBool(parameter, "required") and !parameters.contains(jsonString(parameter, "name"))) return error.InvalidProjectForm;
    }
    return .{ .object = parameters };
}

fn findParameterDeclaration(parameters: []const std.json.Value, name: []const u8) ?std.json.Value {
    for (parameters) |parameter| if (std.mem.eql(u8, jsonString(parameter, "name"), name)) return parameter;
    return null;
}

fn projectFormShapeValid(fields: form.Form, operation: []const u8) bool {
    const base = [_][]const u8{ "csrf_token", "idempotency_key", "operation", "project" };
    const extras: []const []const u8 = if (std.mem.eql(u8, operation, "trust"))
        &.{"manifest_sha256"}
    else if (std.mem.eql(u8, operation, "revoke") or std.mem.eql(u8, operation, "forget"))
        &.{"confirmation"}
    else if (std.mem.eql(u8, operation, "prepare") or std.mem.eql(u8, operation, "observe"))
        &.{}
    else if (std.mem.eql(u8, operation, "plan"))
        &.{"action_id"}
    else if (std.mem.eql(u8, operation, "resource-plan"))
        &.{ "resource_id", "control_name" }
    else if (std.mem.eql(u8, operation, "secret-bind"))
        &.{ "secret_id", "source_kind", "source_ref" }
    else if (std.mem.eql(u8, operation, "secret-unbind"))
        &.{"secret_id"}
    else if (std.mem.eql(u8, operation, "run"))
        &.{ "action_id", "plan_id", "confirmation", "confirm_project_id", "resource_id", "control_name" }
    else if (std.mem.eql(u8, operation, "cancel"))
        &.{"run_id"}
    else
        return false;
    for (fields.entries) |entry| {
        var allowed = false;
        for (base) |name| if (std.mem.eql(u8, entry.name, name)) {
            allowed = true;
            break;
        };
        if (!allowed) for (extras) |name| if (std.mem.eql(u8, entry.name, name)) {
            allowed = true;
            break;
        };
        if (!allowed and std.mem.eql(u8, operation, "plan") and std.mem.startsWith(u8, entry.name, "param.") and entry.name.len > "param.".len) allowed = true;
        if (!allowed) return false;
    }
    return true;
}

fn requireProjectFormConfirmation(ctx: context.Context, reference: []const u8, confirmation: []const u8) !void {
    const project = (try app_nob_projects.find(context.nob(ctx), reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    var id_buffer: [32]u8 = undefined;
    const expected = project.declared_id orelse try std.fmt.bufPrint(&id_buffer, "{d}", .{project.id});
    if (!auth.constantTimeEqual(confirmation, expected)) return error.ProjectConfirmationMismatch;
}

fn optionalFormField(fields: form.Form, name: []const u8) ?[]const u8 {
    return fields.get(name) catch null;
}

fn projectFormTarget(
    allocator: std.mem.Allocator,
    project: ?[]const u8,
    plan: ?[]const u8,
    run: ?[]const u8,
    code: []const u8,
    success: bool,
) ![]const u8 {
    var target = std.Io.Writer.Allocating.init(allocator);
    defer target.deinit();
    try target.writer.writeAll("/projects.html?");
    if (project) |reference| try target.writer.print("project={s}&", .{reference});
    if (plan) |id| try target.writer.print("plan={s}&", .{id});
    if (run) |id| try target.writer.print("run={s}&", .{id});
    try target.writer.print("{s}={s}", .{ if (success) "result" else "error", code });
    return try target.toOwnedSlice();
}

fn projectFormErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.ProjectNotTrusted => "project_not_approved",
        error.RunnerNotReady, error.RunnerMetadataMissing => "runner_not_ready",
        error.PlanUnavailable, error.PlanBindingChanged, error.SourceChanged, error.RunnerDigestMismatch, error.PlanDigestMismatch, error.ManifestDigestMismatch => "plan_no_longer_current",
        error.RequiredSecretUnavailable, error.SecretSourceUnavailable, error.ProcessEnvironmentUnavailable => "required_secret_unavailable",
        error.ActionUnavailable, error.UnknownAction => "action_unavailable",
        error.SystemMutationDisabled => "system_mutation_disabled",
        error.RunnerBuildFailed, error.RunnerDescribeFailed, error.RunnerObserveFailed, error.RunnerPlanFailed => "project_runner_failed",
        error.ProjectBusy => "project_busy",
        error.ConfirmationRequired, error.ProjectConfirmationMismatch => "confirmation",
        error.NobDisabled => "nob_disabled",
        else => "request",
    };
}

fn writeProjectsFormResult(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    status: u16,
    target: []const u8,
    replayed: bool,
    out: *std.Io.Writer,
) !void {
    if (!std.mem.startsWith(u8, target, "/projects.html?")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    if (status == 303) {
        try headers.writer.print("Location: {s}\r\n", .{target});
        try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{
        .method = "GET",
        .target = target,
        .headers = request.headers,
        .body = "",
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/projects.html", preference, &body.writer);
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn jsonMember(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn jsonArray(value: ?std.json.Value) []const std.json.Value {
    const item = value orelse return &.{};
    if (item != .array) return &.{};
    return item.array.items;
}

fn jsonString(value: std.json.Value, name: []const u8) []const u8 {
    const item = jsonMember(value, name) orelse return "";
    return if (item == .string) item.string else "";
}

fn jsonBool(value: std.json.Value, name: []const u8) bool {
    const item = jsonMember(value, name) orelse return false;
    return item == .bool and item.bool;
}

fn handleDockerForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeDockerFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", null, null, out);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", null, null, out);
        return;
    };
    const is_refresh = std.mem.eql(u8, request.path(), "/docker/refresh");
    const allowed_refresh = [_][]const u8{ "csrf_token", "idempotency_key" };
    const allowed_action = [_][]const u8{ "csrf_token", "idempotency_key", "container", "action", "confirmation" };
    if (!formHasOnly(fields, if (is_refresh) &allowed_refresh else &allowed_action)) {
        try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", null, null, out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeDockerFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeDockerFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }

    var container_name: ?[]const u8 = null;
    var container_action: ?app_system_control.ContainerAction = null;
    if (!is_refresh) {
        const name = fields.get("container") catch {
            try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", null, null, out);
            return;
        };
        const action_text = fields.get("action") catch {
            try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", name, null, out);
            return;
        };
        const action = std.meta.stringToEnum(app_system_control.ContainerAction, action_text) orelse {
            try writeDockerFormError(ctx, request, preference, 400, "invalid_container_request", name, null, out);
            return;
        };
        const confirmation = fields.get("confirmation") catch {
            try writeDockerFormError(ctx, request, preference, 428, "confirmation", name, action, out);
            return;
        };
        if (!app_system_control.isSafeContainerName(name) or !auth.constantTimeEqual(confirmation, name)) {
            try writeDockerFormError(ctx, request, preference, 428, "confirmation", name, action, out);
            return;
        }
        container_name = name;
        container_action = action;
    }

    const idempotency_key = fields.get("idempotency_key") catch {
        try writeDockerFormError(ctx, request, preference, 428, "idempotency", container_name, container_action, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeDockerFormError(ctx, request, preference, 428, "idempotency", container_name, container_action, out);
        return;
    }
    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(
        ctx.gpa,
        ctx.db,
        idempotency_key,
        &fingerprint,
        request.method,
        request.target,
        actor,
    );
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeDockerFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeDockerFormError(ctx, request, preference, 409, "container_refresh_in_progress", container_name, container_action, out);
            return;
        },
        .conflict => {
            try writeDockerFormError(ctx, request, preference, 409, "idempotency", container_name, container_action, out);
            return;
        },
    }

    var action_json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer action_json.deinit();
    const mutation_error: ?anyerror = if (is_refresh) blk: {
        app_system_control.refreshContainers(context.system(ctx)) catch |err| break :blk err;
        break :blk null;
    } else blk: {
        app_system_control.containerAction(context.system(ctx), container_name.?, container_action.?, &action_json.writer) catch |err| break :blk err;
        break :blk null;
    };

    if (mutation_error) |err| {
        const mapped = common.mapApiError(err);
        const code = dockerErrorCode(err);
        var target_buffer: [512]u8 = undefined;
        const target = dockerTarget(&target_buffer, code, container_name, container_action);
        try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
        try writeDockerFormResult(ctx, request, preference, mapped.status, target, false, out);
        return;
    }

    var target_buffer: [512]u8 = undefined;
    const target = if (is_refresh)
        "/docker.html?refreshed=1"
    else
        std.fmt.bufPrint(&target_buffer, "/docker.html?result={s}&container={s}", .{
            @tagName(container_action.?),
            container_name.?,
        }) catch "/docker.html";
    try app_writes.completeMutation(ctx.db, idempotency_key, 303, target);
    try writeDockerFormResult(ctx, request, preference, 303, target, false, out);
}

fn formHasOnly(fields: form.Form, allowed: []const []const u8) bool {
    for (fields.entries) |field| {
        var known = false;
        for (allowed) |name| {
            if (std.mem.eql(u8, field.name, name)) {
                known = true;
                break;
            }
        }
        if (!known) return false;
    }
    return true;
}

fn handleRoutesForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeRoutesFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, null, out);
        return;
    }
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, null, out);
        return;
    };
    const path = request.path();
    const is_refresh = std.mem.eql(u8, path, "/routes/refresh");
    const is_apply = std.mem.eql(u8, path, "/routes/apply");
    const is_adopt = std.mem.eql(u8, path, "/routes/adopt");
    const refresh_allowed = [_][]const u8{ "csrf_token", "idempotency_key" };
    const apply_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "confirmation" };
    const adopt_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "host" };
    const route_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "action", "host", "upstream", "enabled", "confirmation" };
    const allowed: []const []const u8 = if (is_refresh) &refresh_allowed else if (is_apply) &apply_allowed else if (is_adopt) &adopt_allowed else &route_allowed;
    if (!formHasOnly(fields, allowed)) {
        try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, null, out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeRoutesFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeRoutesFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }
    const idempotency_key = fields.get("idempotency_key") catch {
        try writeRoutesFormError(ctx, request, preference, 428, "idempotency", null, null, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeRoutesFormError(ctx, request, preference, 428, "idempotency", null, null, out);
        return;
    }

    var host: ?[]const u8 = null;
    var action: ?app_caddy_desired.Action = null;
    var input = app_caddy_desired.RouteInput{ .host = "" };
    if (is_apply) {
        const confirmation = fields.get("confirmation") catch {
            try writeRoutesFormError(ctx, request, preference, 428, "confirmation", null, null, out);
            return;
        };
        if (!auth.constantTimeEqual(confirmation, "APPLY")) {
            try writeRoutesFormError(ctx, request, preference, 428, "confirmation", null, null, out);
            return;
        }
    } else if (is_adopt) {
        host = fields.get("host") catch {
            try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", .adopt, null, out);
            return;
        };
        action = .adopt;
        input.host = host.?;
    } else if (!is_refresh) {
        host = fields.get("host") catch {
            try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, null, out);
            return;
        };
        const action_text = fields.get("action") catch {
            try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, host, out);
            return;
        };
        action = std.meta.stringToEnum(app_caddy_desired.Action, action_text) orelse {
            try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", null, host, out);
            return;
        };
        if (action.? == .adopt) {
            try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", action, host, out);
            return;
        }
        input.host = host.?;
        if (action.? == .create or action.? == .update) {
            input.upstream = fields.get("upstream") catch {
                try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", action, host, out);
                return;
            };
        } else if (action.? == .toggle) {
            const value = fields.get("enabled") catch {
                try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", action, host, out);
                return;
            };
            input.enabled = if (std.mem.eql(u8, value, "1")) true else if (std.mem.eql(u8, value, "0")) false else {
                try writeRoutesFormError(ctx, request, preference, 400, "invalid_caddy_route", action, host, out);
                return;
            };
        } else if (action.? == .delete) {
            const confirmation = fields.get("confirmation") catch {
                try writeRoutesFormError(ctx, request, preference, 428, "confirmation", action, host, out);
                return;
            };
            if (!auth.constantTimeEqual(confirmation, host.?)) {
                try writeRoutesFormError(ctx, request, preference, 428, "confirmation", action, host, out);
                return;
            }
        }
    }

    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(ctx.gpa, ctx.db, idempotency_key, &fingerprint, request.method, request.target, actor);
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeRoutesFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeRoutesFormError(ctx, request, preference, 409, "caddy_write_unavailable", action, host, out);
            return;
        },
        .conflict => {
            try writeRoutesFormError(ctx, request, preference, 409, "idempotency", action, host, out);
            return;
        },
    }

    var caddy_ctx = context.caddy(ctx);
    caddy_ctx.write_meta = .{ .actor = actor, .idempotency_key = idempotency_key };
    if (is_refresh) {
        app_caddy_desired.refresh(caddy_ctx) catch |err| {
            try finishRoutesFormError(ctx, request, preference, idempotency_key, err, null, null, out);
            return;
        };
        try finishRoutesFormSuccess(ctx, request, preference, idempotency_key, "refresh", null, out);
        return;
    }
    if (is_apply) {
        const result = app_caddy_desired.apply(caddy_ctx, .{}) catch |err| {
            try finishRoutesFormError(ctx, request, preference, idempotency_key, err, null, null, out);
            return;
        };
        result.deinit(ctx.gpa);
        try finishRoutesFormSuccess(ctx, request, preference, idempotency_key, "apply", null, out);
        return;
    }
    app_caddy_desired.mutate(caddy_ctx, action.?, input) catch |err| {
        try finishRoutesFormError(ctx, request, preference, idempotency_key, err, action, host, out);
        return;
    };
    try finishRoutesFormSuccess(ctx, request, preference, idempotency_key, @tagName(action.?), host, out);
}

fn finishRoutesFormError(ctx: context.Context, request: http.Request, preference: theme.Preference, idempotency_key: []const u8, err: anyerror, action: ?app_caddy_desired.Action, host: ?[]const u8, out: *std.Io.Writer) !void {
    const mapped = common.mapApiError(err);
    const target = try routesTarget(ctx.gpa, "error", caddyErrorCode(err), action, host);
    defer ctx.gpa.free(target);
    try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
    try writeRoutesFormResult(ctx, request, preference, mapped.status, target, false, out);
}

fn finishRoutesFormSuccess(ctx: context.Context, request: http.Request, preference: theme.Preference, idempotency_key: []const u8, result: []const u8, host: ?[]const u8, out: *std.Io.Writer) !void {
    const target = try routesTarget(ctx.gpa, "result", result, null, host);
    defer ctx.gpa.free(target);
    try app_writes.completeMutation(ctx.db, idempotency_key, 303, target);
    try writeRoutesFormResult(ctx, request, preference, 303, target, false, out);
}

fn caddyErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidRouteRequest => "invalid_caddy_route",
        error.RouteNotObserved => "caddy_route_not_observed",
        error.RouteAlreadyExists => "caddy_route_exists",
        error.RouteNeedsAdoption => "caddy_adoption_required",
        error.RouteNotOwned => "caddy_route_not_owned",
        error.CaddyBusy, error.CaddyWriteUnavailable => "caddy_write_unavailable",
        error.CaddyObservationChanged => "caddy_observation_changed",
        error.CaddyFragmentInvalid, error.CaddyValidationFailed => "caddy_validation_failed",
        error.CaddyWriteFailed => "caddy_fragment_write_failed",
        error.CaddyReloadFailed => "caddy_reload_failed",
        error.CaddyVerificationFailed => "caddy_verification_failed",
        error.CaddyRecoveryFailed => "caddy_recovery_failed",
        else => "internal",
    };
}

fn routesTarget(gpa: std.mem.Allocator, key: []const u8, value: []const u8, action: ?app_caddy_desired.Action, host: ?[]const u8) ![]u8 {
    var target = std.Io.Writer.Allocating.init(gpa);
    defer target.deinit();
    try target.writer.writeAll("/routes.html?");
    try target.writer.writeAll(key);
    try target.writer.writeByte('=');
    try writeQueryComponent(&target.writer, value);
    if (action) |present| {
        try target.writer.writeAll("&action=");
        try writeQueryComponent(&target.writer, @tagName(present));
    }
    if (host) |value_host| {
        try target.writer.writeAll("&host=");
        try writeQueryComponent(&target.writer, value_host);
    }
    return try target.toOwnedSlice();
}

fn writeRoutesFormError(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, code: []const u8, action: ?app_caddy_desired.Action, host: ?[]const u8, out: *std.Io.Writer) !void {
    const target = try routesTarget(ctx.gpa, "error", code, action, host);
    defer ctx.gpa.free(target);
    try writeRoutesFormResult(ctx, request, preference, status, target, false, out);
}

fn writeRoutesFormResult(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, target: []const u8, replayed: bool, out: *std.Io.Writer) !void {
    if (!std.mem.startsWith(u8, target, "/routes.html?")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{ .method = request.method, .target = target, .headers = request.headers, .body = request.body };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/routes.html", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn handleDnsForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeDnsFormError(ctx, request, preference, 403, "security", null, null, null, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", null, null, null, out);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", null, null, null, out);
        return;
    };
    const is_refresh = std.mem.eql(u8, request.path(), "/dns/refresh");
    const refresh_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "domain" };
    const record_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "domain", "action", "record_id", "type", "name", "content", "ttl", "proxied", "confirmation" };
    if (!formHasOnly(fields, if (is_refresh) &refresh_allowed else &record_allowed)) {
        try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", null, null, null, out);
        return;
    }
    const domain = fields.get("domain") catch {
        try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", null, null, null, out);
        return;
    };
    const csrf = fields.get("csrf_token") catch {
        try writeDnsFormError(ctx, request, preference, 403, "security", domain, null, null, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeDnsFormError(ctx, request, preference, 403, "security", domain, null, null, out);
        return;
    }
    const idempotency_key = fields.get("idempotency_key") catch {
        try writeDnsFormError(ctx, request, preference, 428, "idempotency", domain, null, null, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeDnsFormError(ctx, request, preference, 428, "idempotency", domain, null, null, out);
        return;
    }

    var action: ?app_dns.Action = null;
    var record_id: ?[]const u8 = null;
    var input: ?app_dns.RecordInput = null;
    if (!is_refresh) {
        const action_text = fields.get("action") catch {
            try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, null, null, out);
            return;
        };
        action = std.meta.stringToEnum(app_dns.Action, action_text) orelse {
            try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, null, null, out);
            return;
        };
        if (action.? != .create) {
            record_id = fields.get("record_id") catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, null, out);
                return;
            };
        }
        if (action.? == .create or action.? == .update) {
            const record_type = fields.get("type") catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, record_id, out);
                return;
            };
            const name = fields.get("name") catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, record_id, out);
                return;
            };
            const content = fields.get("content") catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, record_id, out);
                return;
            };
            const ttl_text = fields.get("ttl") catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, record_id, out);
                return;
            };
            const ttl = std.fmt.parseInt(i64, ttl_text, 10) catch {
                try writeDnsFormError(ctx, request, preference, 400, "invalid_dns_request", domain, action, record_id, out);
                return;
            };
            const proxied = if (fields.get("proxied")) |value|
                std.mem.eql(u8, value, "1")
            else |_|
                false;
            input = .{ .record_type = record_type, .name = name, .content = content, .ttl = ttl, .proxied = proxied };
        }
        if (action.? == .delete) {
            const confirmation = fields.get("confirmation") catch {
                try writeDnsFormError(ctx, request, preference, 428, "confirmation", domain, action, record_id, out);
                return;
            };
            const observed_name = app_dns.observedRecordName(context.dns(ctx), domain, record_id.?) catch |err| {
                const mapped = common.mapApiError(err);
                try writeDnsFormError(ctx, request, preference, mapped.status, dnsErrorCode(err), domain, action, record_id, out);
                return;
            };
            defer if (observed_name) |name| ctx.gpa.free(name);
            if (observed_name == null or !auth.constantTimeEqual(confirmation, observed_name.?)) {
                try writeDnsFormError(ctx, request, preference, 428, "confirmation", domain, action, record_id, out);
                return;
            }
        }
    }

    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(ctx.gpa, ctx.db, idempotency_key, &fingerprint, request.method, request.target, actor);
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeDnsFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeDnsFormError(ctx, request, preference, 409, "dns_write_unavailable", domain, action, record_id, out);
            return;
        },
        .conflict => {
            try writeDnsFormError(ctx, request, preference, 409, "idempotency", domain, action, record_id, out);
            return;
        },
    }

    var dns_ctx = context.dns(ctx);
    dns_ctx.write_meta = .{ .actor = actor, .idempotency_key = idempotency_key };
    if (is_refresh) {
        app_dns.refresh(dns_ctx, domain) catch |err| {
            const mapped = common.mapApiError(err);
            const target = try dnsTarget(ctx.gpa, domain, "error", dnsErrorCode(err), null, null);
            defer ctx.gpa.free(target);
            try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
            try writeDnsFormResult(ctx, request, preference, mapped.status, target, false, out);
            return;
        };
        const target = try dnsTarget(ctx.gpa, domain, "refreshed", "1", null, null);
        defer ctx.gpa.free(target);
        try app_writes.completeMutation(ctx.db, idempotency_key, 303, target);
        try writeDnsFormResult(ctx, request, preference, 303, target, false, out);
        return;
    }

    const outcome = app_dns.mutate(dns_ctx, action.?, domain, record_id, input) catch |err| {
        const mapped = common.mapApiError(err);
        const target = try dnsTarget(ctx.gpa, domain, "error", dnsErrorCode(err), action, record_id);
        defer ctx.gpa.free(target);
        try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
        try writeDnsFormResult(ctx, request, preference, mapped.status, target, false, out);
        return;
    };
    const result_value = if (outcome == .confirmed) @tagName(action.?) else "accepted_unconfirmed";
    const target = try dnsTarget(ctx.gpa, domain, "result", result_value, null, null);
    defer ctx.gpa.free(target);
    const status: u16 = if (outcome == .confirmed) 303 else 202;
    try app_writes.completeMutation(ctx.db, idempotency_key, status, target);
    try writeDnsFormResult(ctx, request, preference, status, target, false, out);
}

fn dnsErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidDnsRequest => "invalid_dns_request",
        error.DnsZoneNotConfigured, error.DnsZoneNotObserved => "dns_zone_not_observed",
        error.DnsRecordNotObserved => "dns_record_not_observed",
        error.DnsWriteUnavailable, error.DnsBusy => "dns_write_unavailable",
        error.DnsProviderRejected => "dns_provider_rejected",
        error.DnsProviderUnavailable => "dns_provider_unavailable",
        else => "internal",
    };
}

fn dnsTarget(gpa: std.mem.Allocator, domain: []const u8, key: []const u8, value: []const u8, action: ?app_dns.Action, record_id: ?[]const u8) ![]u8 {
    var target = std.Io.Writer.Allocating.init(gpa);
    defer target.deinit();
    try target.writer.writeAll("/dns.html?domain=");
    try writeQueryComponent(&target.writer, domain);
    try target.writer.writeByte('&');
    try target.writer.writeAll(key);
    try target.writer.writeByte('=');
    try writeQueryComponent(&target.writer, value);
    if (action) |present| {
        if (present == .update and record_id != null) {
            try target.writer.writeAll("&edit=");
            try writeQueryComponent(&target.writer, record_id.?);
        } else if (present == .delete and record_id != null) {
            try target.writer.writeAll("&confirm=delete&record=");
            try writeQueryComponent(&target.writer, record_id.?);
        }
    }
    return try target.toOwnedSlice();
}

fn writeQueryComponent(out: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_' or byte == '~') {
            try out.writeByte(byte);
        } else {
            try out.writeByte('%');
            try out.writeByte(hex[byte >> 4]);
            try out.writeByte(hex[byte & 0x0f]);
        }
    }
}

fn writeDnsFormError(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, code: []const u8, domain: ?[]const u8, action: ?app_dns.Action, record_id: ?[]const u8, out: *std.Io.Writer) !void {
    const target = try dnsTarget(ctx.gpa, domain orelse "", "error", code, action, record_id);
    defer ctx.gpa.free(target);
    try writeDnsFormResult(ctx, request, preference, status, target, false, out);
}

fn writeDnsFormResult(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, target: []const u8, replayed: bool, out: *std.Io.Writer) !void {
    if (!std.mem.startsWith(u8, target, "/dns.html?")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{
        .method = request.method,
        .target = target,
        .headers = request.headers,
        .body = request.body,
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/dns.html", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn handleBrowserRunForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeBrowserFormError(ctx, request, preference, 403, "security", out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    }
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    };
    const allowed = [_][]const u8{ "csrf_token", "idempotency_key", "account_id", "url", "action" };
    if (!formHasOnly(fields, &allowed)) {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeBrowserFormError(ctx, request, preference, 403, "security", out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeBrowserFormError(ctx, request, preference, 403, "security", out);
        return;
    }
    const idempotency_key = fields.get("idempotency_key") catch {
        try writeBrowserFormError(ctx, request, preference, 428, "idempotency", out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeBrowserFormError(ctx, request, preference, 428, "idempotency", out);
        return;
    }
    const account_id = fields.get("account_id") catch {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    };
    const url = fields.get("url") catch {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    };
    const action_text = fields.get("action") catch {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    };
    const action = std.meta.stringToEnum(app_browser_run.Action, action_text) orelse {
        try writeBrowserFormError(ctx, request, preference, 400, "invalid_request", out);
        return;
    };

    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(ctx.gpa, ctx.db, idempotency_key, &fingerprint, request.method, request.target, actor);
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeBrowserFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeBrowserFormError(ctx, request, preference, 409, "busy", out);
            return;
        },
        .conflict => {
            try writeBrowserFormError(ctx, request, preference, 409, "idempotency", out);
            return;
        },
    }

    var browser_ctx = context.browserRun(ctx);
    browser_ctx.write_meta = .{ .actor = actor, .idempotency_key = idempotency_key };
    const outcome = app_browser_run.run(browser_ctx, .{
        .account_id = account_id,
        .url = url,
        .action = action,
    }) catch |err| {
        const mapped = browserError(err);
        const target = try std.fmt.allocPrint(ctx.gpa, "/browser.html?error={s}", .{mapped.code});
        defer ctx.gpa.free(target);
        try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
        try writeBrowserFormResult(ctx, request, preference, mapped.status, target, false, out);
        return;
    };
    defer outcome.deinit(ctx.gpa);
    var target = std.Io.Writer.Allocating.init(ctx.gpa);
    defer target.deinit();
    try target.writer.writeAll("/browser.html?run=");
    try writeQueryComponent(&target.writer, outcome.id);
    try app_writes.completeMutation(ctx.db, idempotency_key, outcome.status, target.written());
    try writeBrowserFormResult(ctx, request, preference, outcome.status, target.written(), false, out);
}

const BrowserErrorMapping = struct { status: u16, code: []const u8 };

fn browserError(err: anyerror) BrowserErrorMapping {
    return switch (err) {
        error.InvalidBrowserRunRequest => .{ .status = 400, .code = "invalid_request" },
        error.BrowserRunTokenRequired => .{ .status = 409, .code = "token_required" },
        error.BrowserRunAccountNotObserved => .{ .status = 404, .code = "account_not_observed" },
        error.BrowserRunDestinationPolicyRequired, error.BrowserRunDestinationDenied => .{ .status = 403, .code = "destination_denied" },
        error.BrowserRunBusy => .{ .status = 409, .code = "busy" },
        else => .{ .status = 500, .code = "internal" },
    };
}

fn writeBrowserFormError(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, code: []const u8, out: *std.Io.Writer) !void {
    const target = try std.fmt.allocPrint(ctx.gpa, "/browser.html?error={s}", .{code});
    defer ctx.gpa.free(target);
    try writeBrowserFormResult(ctx, request, preference, status, target, false, out);
}

fn writeBrowserFormResult(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, target: []const u8, replayed: bool, out: *std.Io.Writer) !void {
    if (!std.mem.startsWith(u8, target, "/browser.html?")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{ .method = "GET", .target = target, .headers = request.headers, .body = "" };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/browser.html", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn handleBrowserArtifact(ctx: context.Context, request: http.Request, out: *std.Io.Writer) !void {
    const id = request.query("id") orelse {
        try writeJson(out, 404, "{\"error\":\"not_found\"}\n");
        return;
    };
    const artifact_value = app_browser_run.artifact(context.browserRun(ctx), id) catch |err| switch (err) {
        error.BrowserRunArtifactExpired => {
            try http.response.write(out, 410, "application/json", security_headers, "{\"error\":\"artifact_expired\"}\n");
            return;
        },
        error.BrowserRunArtifactNotFound, error.BrowserRunArtifactUnsafe => {
            try writeJson(out, 404, "{\"error\":\"not_found\"}\n");
            return;
        },
        else => |other| return other,
    };
    defer artifact_value.deinit(ctx.gpa);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (artifact_value.attachment_only or std.mem.eql(u8, request.query("download") orelse "", "1")) {
        try headers.writer.writeAll("Content-Disposition: attachment; filename=\"");
        try headers.writer.writeAll(artifact_value.filename);
        try headers.writer.writeAll("\"\r\n");
    }
    try http.response.writeFile(
        ctx.io,
        out,
        200,
        artifact_value.content_type,
        headers.written(),
        artifact_value.path,
        std.mem.eql(u8, request.method, "HEAD"),
    );
}

fn handleVpsForm(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !void {
    if (!auth.originMatches(request, ctx.config.auth_origin)) {
        try writeVpsFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }
    if (!form.hasUrlEncodedBody(request)) {
        try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", null, null, out);
        return;
    }
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const fields = form.parse(arena.allocator(), request.body) catch {
        try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", null, null, out);
        return;
    };
    const is_refresh = std.mem.eql(u8, request.path(), "/vps/refresh");
    const refresh_allowed = [_][]const u8{ "csrf_token", "idempotency_key" };
    const action_allowed = [_][]const u8{ "csrf_token", "idempotency_key", "machine", "action", "confirmation" };
    if (!formHasOnly(fields, if (is_refresh) &refresh_allowed else &action_allowed)) {
        try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", null, null, out);
        return;
    }
    const csrf = fields.get("csrf_token") catch {
        try writeVpsFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    };
    if (!auth.constantTimeEqual(csrf, ctx.auth_csrf_token orelse "")) {
        try writeVpsFormError(ctx, request, preference, 403, "security", null, null, out);
        return;
    }

    var machine_id: ?[]const u8 = null;
    var action: ?app_vps.Action = null;
    if (!is_refresh) {
        machine_id = fields.get("machine") catch {
            try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", null, null, out);
            return;
        };
        const action_text = fields.get("action") catch {
            try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", machine_id, null, out);
            return;
        };
        action = std.meta.stringToEnum(app_vps.Action, action_text) orelse {
            try writeVpsFormError(ctx, request, preference, 400, "invalid_vps_request", machine_id, null, out);
            return;
        };
        const confirmation = fields.get("confirmation") catch {
            try writeVpsFormError(ctx, request, preference, 428, "confirmation", machine_id, action, out);
            return;
        };
        if (!auth.constantTimeEqual(confirmation, machine_id.?)) {
            try writeVpsFormError(ctx, request, preference, 428, "confirmation", machine_id, action, out);
            return;
        }
    }

    const idempotency_key = fields.get("idempotency_key") catch {
        try writeVpsFormError(ctx, request, preference, 428, "idempotency", machine_id, action, out);
        return;
    };
    if (!auth.isValidIdempotencyKey(idempotency_key)) {
        try writeVpsFormError(ctx, request, preference, 428, "idempotency", machine_id, action, out);
        return;
    }
    const actor = ctx.auth_user_id orelse "authenticated";
    const fingerprint = auth.mutationFingerprint(request);
    const claim = try app_writes.beginMutation(ctx.gpa, ctx.db, idempotency_key, &fingerprint, request.method, request.target, actor);
    switch (claim) {
        .execute => {},
        .replay => |stored| {
            defer stored.deinit(ctx.gpa);
            try writeVpsFormResult(ctx, request, preference, stored.status, stored.body, true, out);
            return;
        },
        .in_progress => {
            try writeVpsFormError(ctx, request, preference, 409, "vps_write_unavailable", machine_id, action, out);
            return;
        },
        .conflict => {
            try writeVpsFormError(ctx, request, preference, 409, "idempotency", machine_id, action, out);
            return;
        },
    }

    var vps_ctx = context.vps(ctx);
    vps_ctx.write_meta = .{ .actor = actor, .idempotency_key = idempotency_key };
    if (is_refresh) {
        app_vps.refresh(vps_ctx) catch |err| {
            const mapped = common.mapApiError(err);
            const target = try vpsTarget(ctx.gpa, "error", vpsErrorCode(err), null, null, null);
            defer ctx.gpa.free(target);
            try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
            try writeVpsFormResult(ctx, request, preference, mapped.status, target, false, out);
            return;
        };
        const target = "/vps.html?refreshed=1";
        try app_writes.completeMutation(ctx.db, idempotency_key, 303, target);
        try writeVpsFormResult(ctx, request, preference, 303, target, false, out);
        return;
    }

    const result = app_vps.mutate(vps_ctx, machine_id.?, action.?) catch |err| {
        const mapped = common.mapApiError(err);
        const target = try vpsTarget(ctx.gpa, "error", vpsErrorCode(err), machine_id, action, null);
        defer ctx.gpa.free(target);
        try app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, target);
        try writeVpsFormResult(ctx, request, preference, mapped.status, target, false, out);
        return;
    };
    defer result.deinit(ctx.gpa);
    const target = try vpsTarget(
        ctx.gpa,
        "result",
        if (result.outcome == .confirmed) @tagName(action.?) else "accepted_pending",
        machine_id,
        null,
        result.provider_job_id,
    );
    defer ctx.gpa.free(target);
    const status: u16 = if (result.outcome == .confirmed) 303 else 202;
    try app_writes.completeMutation(ctx.db, idempotency_key, status, target);
    try writeVpsFormResult(ctx, request, preference, status, target, false, out);
}

fn vpsErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidVpsRequest => "invalid_vps_request",
        error.VpsNotObserved => "vps_not_observed",
        error.VpsActionUnavailable => "vps_action_unavailable",
        error.VpsWriteUnavailable, error.VpsBusy => "vps_write_unavailable",
        error.VpsProviderRejected, error.VpsActionFailed => "vps_provider_rejected",
        error.VpsProviderUnavailable => "vps_provider_unavailable",
        else => "internal",
    };
}

fn vpsTarget(
    gpa: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
    machine_id: ?[]const u8,
    action: ?app_vps.Action,
    job_id: ?[]const u8,
) ![]u8 {
    var target = std.Io.Writer.Allocating.init(gpa);
    defer target.deinit();
    try target.writer.writeAll("/vps.html?");
    try target.writer.writeAll(key);
    try target.writer.writeByte('=');
    try writeQueryComponent(&target.writer, value);
    if (machine_id) |machine| {
        try target.writer.writeAll("&machine=");
        try writeQueryComponent(&target.writer, machine);
    }
    if (action) |present| {
        try target.writer.writeAll("&confirm=");
        try writeQueryComponent(&target.writer, @tagName(present));
    }
    if (job_id) |job| {
        try target.writer.writeAll("&job=");
        try writeQueryComponent(&target.writer, job);
    }
    return try target.toOwnedSlice();
}

fn writeVpsFormError(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, code: []const u8, machine_id: ?[]const u8, action: ?app_vps.Action, out: *std.Io.Writer) !void {
    const target = try vpsTarget(ctx.gpa, "error", code, machine_id, action, null);
    defer ctx.gpa.free(target);
    try writeVpsFormResult(ctx, request, preference, status, target, false, out);
}

fn writeVpsFormResult(ctx: context.Context, request: http.Request, preference: theme.Preference, status: u16, target: []const u8, replayed: bool, out: *std.Io.Writer) !void {
    if (!std.mem.startsWith(u8, target, "/vps.html?")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{
        .method = request.method,
        .target = target,
        .headers = request.headers,
        .body = request.body,
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/vps.html", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
}

fn dockerErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidContainerName, error.InvalidContainerLogTail, error.ContainerObservationInvalid => "invalid_container_request",
        error.ContainerNotObserved => "container_not_observed",
        error.ContainerActionUnavailable => "container_action_unavailable",
        error.ContainerRefreshInProgress => "container_refresh_in_progress",
        error.ContainerCommandFailed => "container_command_failed",
        error.ContainerStateUnconfirmed => "container_state_unconfirmed",
        error.ContainerRuntimeUnavailable, error.ContainerLogsFailed => "container_runtime_unavailable",
        else => "internal",
    };
}

fn dockerTarget(
    buffer: *[512]u8,
    code: []const u8,
    container_name: ?[]const u8,
    action: ?app_system_control.ContainerAction,
) []const u8 {
    if (container_name) |name| {
        if (app_system_control.isSafeContainerName(name)) {
            if (action) |present| {
                return std.fmt.bufPrint(buffer, "/docker.html?error={s}&confirm={s}&container={s}", .{ code, @tagName(present), name }) catch "/docker.html?error=internal";
            }
        }
    }
    return std.fmt.bufPrint(buffer, "/docker.html?error={s}", .{code}) catch "/docker.html?error=internal";
}

fn writeDockerFormError(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    status: u16,
    code: []const u8,
    container_name: ?[]const u8,
    action: ?app_system_control.ContainerAction,
    out: *std.Io.Writer,
) !void {
    var target_buffer: [512]u8 = undefined;
    const target = dockerTarget(&target_buffer, code, container_name, action);
    try writeDockerFormResult(ctx, request, preference, status, target, false, out);
}

fn writeDockerFormResult(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    status: u16,
    target: []const u8,
    replayed: bool,
    out: *std.Io.Writer,
) !void {
    if (!std.mem.startsWith(u8, target, "/docker.html")) {
        try writeJson(out, 500, "{\"error\":\"invalid_stored_response\"}\n");
        return;
    }
    if (status == 303) {
        var headers = std.Io.Writer.Allocating.init(ctx.gpa);
        defer headers.deinit();
        try headers.writer.writeAll(security_headers);
        try headers.writer.writeAll("Location: ");
        try headers.writer.writeAll(target);
        try headers.writer.writeAll("\r\n");
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        try http.response.write(out, 303, "text/html; charset=utf-8", headers.written(), "");
        return;
    }
    const page_request: http.Request = .{
        .method = "GET",
        .target = target,
        .headers = request.headers,
        .body = "",
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    _ = try pages.render(ctx, page_request, "/docker.html", preference, &body.writer);
    var headers = std.Io.Writer.Allocating.init(ctx.gpa);
    defer headers.deinit();
    try headers.writer.writeAll(security_headers);
    if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
    try http.response.write(out, status, "text/html; charset=utf-8", headers.written(), body.written());
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

test "Dashboard native refresh rejects wrong origin unknown fields and bad csrf before collection" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/pipeline-dashboard.db", .{tmp.sub_path});
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
    const base: http.Request = .{
        .method = "POST",
        .target = "/dashboard/refresh",
        .headers = &.{
            .{ .name = "Origin", .value = "https://cloudio.example.test" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        },
        .body = "csrf_token=known-csrf&idempotency_key=dashboard-refresh-test-0001",
    };

    var wrong_origin = base;
    wrong_origin.headers = &.{
        .{ .name = "Origin", .value = "https://wrong.example.test" },
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
    };
    var denied = std.Io.Writer.Allocating.init(allocator);
    defer denied.deinit();
    try handleDashboardRefreshForm(ctx, wrong_origin, .light, &denied.writer);
    try std.testing.expect(std.mem.startsWith(u8, denied.written(), "HTTP/1.1 403 Forbidden\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, denied.written(), "failed its Origin or CSRF check") != null);

    var unknown = base;
    unknown.body = "csrf_token=known-csrf&idempotency_key=dashboard-refresh-test-0002&surprise=1";
    var unknown_response = std.Io.Writer.Allocating.init(allocator);
    defer unknown_response.deinit();
    try handleDashboardRefreshForm(ctx, unknown, .light, &unknown_response.writer);
    try std.testing.expect(std.mem.startsWith(u8, unknown_response.written(), "HTTP/1.1 400 Bad Request\r\n"));

    var bad_csrf = base;
    bad_csrf.body = "csrf_token=wrong&idempotency_key=dashboard-refresh-test-0003";
    var csrf_response = std.Io.Writer.Allocating.init(allocator);
    defer csrf_response.deinit();
    try handleDashboardRefreshForm(ctx, bad_csrf, .light, &csrf_response.writer);
    try std.testing.expect(std.mem.startsWith(u8, csrf_response.written(), "HTTP/1.1 403 Forbidden\r\n"));
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("mutation_requests"));
}

test "Docker native forms enforce origin fields csrf and exact confirmation before commands" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/pipeline-docker.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try @import("db_store").Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertContainer("fixture-stopped", "example.invalid/test", "Exited (0)", "", "fixture");
    _ = try db.insertSnapshot("system", "containers", null, "ok", "observed 1 container", null, null);

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

    const wrong_confirmation: http.Request = .{
        .method = "POST",
        .target = "/docker/action",
        .headers = &.{
            .{ .name = "Origin", .value = "https://cloudio.example.test" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        },
        .body = "csrf_token=known-csrf&idempotency_key=test-native-key-0001&container=fixture-stopped&action=start&confirmation=wrong",
    };
    var confirmation_response = std.Io.Writer.Allocating.init(allocator);
    defer confirmation_response.deinit();
    try handleDockerForm(ctx, wrong_confirmation, .light, &confirmation_response.writer);
    try std.testing.expect(std.mem.startsWith(u8, confirmation_response.written(), "HTTP/1.1 428 Precondition Required\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, confirmation_response.written(), "Type the exact observed container name") != null);
    try std.testing.expect(std.mem.indexOf(u8, confirmation_response.written(), "id=\"docker-action-form\"") != null);

    var denied = wrong_confirmation;
    denied.target = "/docker/refresh";
    denied.headers = &.{
        .{ .name = "Origin", .value = "https://wrong.example.test" },
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
    };
    denied.body = "csrf_token=known-csrf&idempotency_key=test-native-key-0002";
    var denied_response = std.Io.Writer.Allocating.init(allocator);
    defer denied_response.deinit();
    try handleDockerForm(ctx, denied, .light, &denied_response.writer);
    try std.testing.expect(std.mem.startsWith(u8, denied_response.written(), "HTTP/1.1 403 Forbidden\r\n"));

    var unknown_field = wrong_confirmation;
    unknown_field.target = "/docker/refresh";
    unknown_field.body = "csrf_token=known-csrf&idempotency_key=test-native-key-0003&surprise=1";
    var unknown_response = std.Io.Writer.Allocating.init(allocator);
    defer unknown_response.deinit();
    try handleDockerForm(ctx, unknown_field, .light, &unknown_response.writer);
    try std.testing.expect(std.mem.startsWith(u8, unknown_response.written(), "HTTP/1.1 400 Bad Request\r\n"));
}
