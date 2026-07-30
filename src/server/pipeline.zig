const std = @import("std");
const app_writes = @import("app_writes");
const http = @import("http");
const auth = @import("auth.zig");
const common = @import("common.zig");
const context = @import("context.zig");
const routes = @import("routes.zig");
const types = @import("types.zig");

const web_root = "web";

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
            try http.response.write(out, 413, "application/json", "", "{\"error\":\"payload_too_large\"}\n");
            return;
        },
        error.BadRequest, error.TooManyHeaders => {
            try http.response.write(out, 400, "application/json", "", "{\"error\":\"bad_request\"}\n");
            return;
        },
        else => return err,
    }) orelse return;

    const path = request.path();
    const authorized = if (ctx.config.platform_token) |token| auth.isAuthorized(request, token) else true;
    if (!std.mem.startsWith(u8, path, "/api/")) {
        if (!authorized and !staticPathIsPublic(path)) {
            try http.response.write(out, 302, "text/html", "Location: /login.html\r\n", "");
            return;
        }
        try http.static.serve(ctx.io, ctx.gpa, web_root, path, http.static.default_max_file_bytes, out);
        return;
    }

    const matched = http.router.match(types.Route, &routes.all, request.method, path) orelse {
        if (http.router.pathExists(types.Route, &routes.all, path)) {
            try http.response.write(out, 405, "application/json", "", "{\"error\":\"method_not_allowed\"}\n");
        } else {
            try http.response.write(out, 404, "application/json", "", "{\"error\":\"not_found\"}\n");
        }
        return;
    };
    const route = matched.route;
    if (route.access == .authenticated and !authorized) {
        try http.response.write(out, 401, "application/json", "", "{\"error\":\"unauthorized\"}\n");
        return;
    }
    if (route.mutation == .destructive and !std.mem.eql(u8, request.header("x-cloudio-confirm") orelse "", "confirmed")) {
        try http.response.write(out, 428, "application/json", "", "{\"error\":\"confirmation_required\",\"required_header\":\"X-Cloudio-Confirm: confirmed\"}\n");
        return;
    }
    const actor = auth.actor(request, ctx.config.platform_token != null) orelse {
        try http.response.write(out, 400, "application/json", "", "{\"error\":\"invalid_actor\"}\n");
        return;
    };
    const idempotency_key = request.header("idempotency-key") orelse "";
    var request_ctx = ctx;
    request_ctx.write_meta = .{
        .actor = actor,
        .idempotency_key = if (idempotency_key.len == 0) null else idempotency_key,
    };

    if (route.mutation != .none) {
        if (!auth.isValidIdempotencyKey(idempotency_key)) {
            try http.response.write(out, 428, "application/json", "", "{\"error\":\"idempotency_key_required\",\"required_header\":\"Idempotency-Key\"}\n");
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
                try http.response.write(out, stored.status, "application/json", "Idempotency-Replayed: true\r\n", stored.body);
                return;
            },
            .in_progress => {
                try http.response.write(out, 409, "application/json", "", "{\"error\":\"request_in_progress\"}\n");
                return;
            },
            .conflict => {
                try http.response.write(out, 409, "application/json", "", "{\"error\":\"idempotency_key_reused\"}\n");
                return;
            },
        }
    }

    switch (route.handler) {
        .stream => |handler| {
            handler(request_ctx, request, matched.params, out) catch |err| {
                std.debug.print("cloudio stream {s} failed: {s}\n", .{ route.pattern, @errorName(err) });
            };
        },
        .buffered => |handler| {
            var body = std.Io.Writer.Allocating.init(ctx.gpa);
            defer body.deinit();
            var extra_headers = std.Io.Writer.Allocating.init(ctx.gpa);
            defer extra_headers.deinit();
            const status = handler(request_ctx, request, matched.params, &body.writer, &extra_headers.writer) catch |err| {
                std.debug.print("cloudio handler {s} failed: {s}\n", .{ route.pattern, @errorName(err) });
                const mapped = common.mapApiError(err);
                if (route.mutation != .none) {
                    app_writes.completeMutation(ctx.db, idempotency_key, mapped.status, mapped.body) catch |complete_err| {
                        std.debug.print("cloudio idempotency completion failed: {s}\n", .{@errorName(complete_err)});
                    };
                }
                try http.response.write(out, mapped.status, "application/json", "", mapped.body);
                return;
            };
            if (route.mutation != .none) {
                try app_writes.completeMutation(ctx.db, idempotency_key, status, body.written());
            }
            try http.response.write(out, status, "application/json", extra_headers.written(), body.written());
        },
    }
}

fn staticPathIsPublic(path: []const u8) bool {
    return std.mem.eql(u8, path, "/login.html") or std.mem.startsWith(u8, path, "/assets/");
}
