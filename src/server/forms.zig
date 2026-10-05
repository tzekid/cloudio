//! Native form mutations. Every page action shares one pipeline: exact
//! origin, urlencoded body, field allowlist, session CSRF, an idempotency
//! claim, then post/redirect/get or a re-rendered page with the outcome.

const std = @import("std");
const percent = @import("../core/url.zig");
const app_authentication = @import("../app/authentication.zig");
const app_browser_run = @import("../app/browser_run.zig");
const app_caddy_desired = @import("../app/caddy_desired.zig");
const app_dns = @import("../app/dns.zig");
const app_nob_actions = @import("../app/nob_actions.zig");
const app_nob_projects = @import("../app/nob_projects.zig");
const app_nob_runtime = @import("../app/nob_runtime.zig");
const app_nob_secrets = @import("../app/nob_secrets.zig");
const app_refresh = @import("../app/refresh.zig");
const app_system_control = @import("../app/system_control.zig");
const app_vps = @import("../app/vps.zig");
const app_writes = @import("../app/writes.zig");
const http = @import("../http/root.zig");
const auth = @import("auth.zig");
const common = @import("common.zig");
const context = @import("context.zig");
const form = @import("form.zig");
const pages = @import("pages.zig");
const theme = @import("theme.zig");

const Handler = *const fn (*Submission) anyerror!void;

const routes = [_]struct { path: []const u8, page: []const u8, handler: Handler }{
    .{ .path = "/settings/theme", .page = "/settings.html", .handler = themeSettings },
    .{ .path = "/security/logout", .page = "/security.html", .handler = logout },
    .{ .path = "/dashboard/refresh", .page = "/", .handler = dashboardRefresh },
    .{ .path = "/projects/scan", .page = "/projects.html", .handler = projects },
    .{ .path = "/projects/action", .page = "/projects.html", .handler = projects },
    .{ .path = "/routes/refresh", .page = "/routes.html", .handler = caddyRoutes },
    .{ .path = "/routes/route", .page = "/routes.html", .handler = caddyRoutes },
    .{ .path = "/routes/adopt", .page = "/routes.html", .handler = caddyRoutes },
    .{ .path = "/routes/apply", .page = "/routes.html", .handler = caddyRoutes },
    .{ .path = "/dns/refresh", .page = "/dns.html", .handler = dns },
    .{ .path = "/dns/record", .page = "/dns.html", .handler = dns },
    .{ .path = "/browser/run", .page = "/browser.html", .handler = browserRun },
    .{ .path = "/vps/refresh", .page = "/vps.html", .handler = vps },
    .{ .path = "/vps/action", .page = "/vps.html", .handler = vps },
    .{ .path = "/docker/refresh", .page = "/docker.html", .handler = docker },
    .{ .path = "/docker/action", .page = "/docker.html", .handler = docker },
};

pub fn isFormPath(path: []const u8) bool {
    for (routes) |route| if (std.mem.eql(u8, route.path, path)) return true;
    return false;
}

/// Handles a POST to a native form path. The caller has already
/// authenticated the session and checked `isFormPath`.
pub fn handle(ctx: context.Context, request: http.Request, preference: theme.Preference, secure_origin: bool, out: *std.Io.Writer) !void {
    const path = request.path();
    for (routes) |route| {
        if (!std.mem.eql(u8, route.path, path)) continue;
        var arena = std.heap.ArenaAllocator.init(ctx.gpa);
        defer arena.deinit();
        var submission: Submission = .{
            .ctx = ctx,
            .request = request,
            .preference = preference,
            .secure_origin = secure_origin,
            .out = out,
            .arena = arena.allocator(),
            .page = route.page,
            .actor = ctx.auth_user_id orelse "authenticated",
        };
        return route.handler(&submission);
    }
    unreachable;
}

const Submission = struct {
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    secure_origin: bool,
    out: *std.Io.Writer,
    arena: std.mem.Allocator,
    /// Page rendered for every non-redirect outcome; stored targets must stay on it.
    page: []const u8,
    actor: []const u8,
    /// Query key carrying failure codes (`/?refresh=` on the dashboard).
    error_key: []const u8 = "error",
    /// Extra query appended to failure targets so the page reopens the same draft.
    error_context: []const u8 = "",
    fields: form.Form = .{ .entries = &.{} },
    idempotency_key: []const u8 = "",

    /// Checks origin, encoding, allowed field names, and CSRF. `allowed` is
    /// null when the handler validates its own field shape. Returns false
    /// after writing the rejection.
    fn begin(self: *Submission, allowed: ?[]const []const u8, invalid_code: []const u8) !bool {
        if (!auth.originMatches(self.request, self.ctx.config.auth_origin)) {
            try self.reject(403, "security");
            return false;
        }
        if (!form.hasUrlEncodedBody(self.request)) {
            try self.reject(400, invalid_code);
            return false;
        }
        self.fields = form.parse(self.arena, self.request.body) catch {
            try self.reject(400, invalid_code);
            return false;
        };
        if (allowed) |names| for (self.fields.entries) |entry| {
            if (!contains(&.{ "csrf_token", "idempotency_key" }, entry.name) and !contains(names, entry.name)) {
                try self.reject(400, invalid_code);
                return false;
            }
        };
        const csrf = self.fields.get("csrf_token") catch "";
        if (!auth.constantTimeEqual(csrf, self.ctx.auth_csrf_token orelse "") or csrf.len == 0) {
            try self.reject(403, "security");
            return false;
        }
        return true;
    }

    fn field(self: *Submission, name: []const u8) ?[]const u8 {
        return self.fields.get(name) catch null;
    }

    /// Claims the idempotency key. Returns false when the submission was
    /// answered by a stored response or blocked by a concurrent/conflicting one.
    fn claim(self: *Submission, busy_code: []const u8) !bool {
        self.idempotency_key = self.field("idempotency_key") orelse "";
        if (!auth.isValidIdempotencyKey(self.idempotency_key)) {
            try self.reject(428, "idempotency");
            return false;
        }
        const fingerprint = auth.mutationFingerprint(self.request);
        const claimed = try app_writes.beginMutation(
            self.ctx.gpa,
            self.ctx.db,
            self.idempotency_key,
            &fingerprint,
            self.request.method,
            self.request.target,
            self.actor,
        );
        switch (claimed) {
            .execute => return true,
            .replay => |stored| {
                defer stored.deinit(self.ctx.gpa);
                try self.write(stored.status, stored.body, true);
            },
            .in_progress => try self.reject(409, busy_code),
            .conflict => try self.reject(409, "idempotency"),
        }
        return false;
    }

    fn writeMeta(self: *Submission) app_writes.Metadata {
        return .{ .actor = self.actor, .idempotency_key = self.idempotency_key };
    }

    /// Answers without storing the outcome under the idempotency key, so a
    /// corrected resubmission with the same key can still run.
    fn reject(self: *Submission, status: u16, code: []const u8) !void {
        try self.write(status, try self.errorTarget(code), false);
    }

    /// Stores the outcome under the claimed key, then answers.
    fn finish(self: *Submission, status: u16, target: []const u8) !void {
        try app_writes.completeMutation(self.ctx.db, self.idempotency_key, status, target);
        try self.write(status, target, false);
    }

    fn fail(self: *Submission, err: anyerror) !void {
        const mapped = common.failure(err);
        if (mapped.status >= 500) std.debug.print("cloudio form {s} failed: {s}\n", .{ self.request.path(), @errorName(err) });
        try self.finish(mapped.status, try self.errorTarget(mapped.code));
    }

    fn errorTarget(self: *Submission, code: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.arena, "{s}?{s}={s}{s}", .{ self.page, self.error_key, code, self.error_context });
    }

    fn write(self: *Submission, status: u16, target: []const u8, replayed: bool) !void {
        if (!std.mem.startsWith(u8, target, self.page) or target.len <= self.page.len or target[self.page.len] != '?') {
            try http.response.write(self.out, 500, "application/json", self.ctx.response_headers, "{\"error\":\"invalid_stored_response\"}\n");
            return;
        }
        var headers = std.Io.Writer.Allocating.init(self.arena);
        try headers.writer.writeAll(self.ctx.response_headers);
        if (replayed) try headers.writer.writeAll("Idempotency-Replayed: true\r\n");
        if (status == 303) {
            try headers.writer.print("Location: {s}\r\n", .{target});
            try http.response.write(self.out, 303, "text/html; charset=utf-8", headers.written(), "");
            return;
        }
        var page_request = self.request;
        page_request.target = target;
        var body = std.Io.Writer.Allocating.init(self.arena);
        _ = try pages.render(self.ctx, page_request, self.page, self.preference, &body.writer);
        try http.response.write(self.out, status, "text/html; charset=utf-8", headers.written(), body.written());
    }

    fn redirect(self: *Submission, location: []const u8, extra_headers: []const u8) !void {
        var headers = std.Io.Writer.Allocating.init(self.arena);
        try headers.writer.print("{s}{s}Location: {s}\r\n", .{ self.ctx.response_headers, extra_headers, location });
        try http.response.write(self.out, 303, "text/html; charset=utf-8", headers.written(), "");
    }

    /// Formats a target, percent-encoding every `{s}` argument.
    fn url(self: *Submission, comptime fmt: []const u8, args: anytype) ![]const u8 {
        var escaped: @Tuple(&@as([args.len]type, @splat([]const u8))) = undefined;
        inline for (0..args.len) |index| escaped[index] = try escape(self.arena, args[index]);
        return std.fmt.allocPrint(self.arena, fmt, escaped);
    }
};

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

fn escape(arena: std.mem.Allocator, value: []const u8) ![]const u8 {
    return percent.component(arena, value);
}

fn themeSettings(s: *Submission) !void {
    if (!try s.begin(&.{"theme"}, "request")) return;
    const next = theme.parse(s.field("theme") orelse "") orelse return s.reject(400, "theme");
    var cookie = std.Io.Writer.Allocating.init(s.arena);
    try theme.writeCookie(&cookie.writer, s.secure_origin, next);
    try s.redirect("/settings.html?saved=1", cookie.written());
}

fn logout(s: *Submission) !void {
    if (!try s.begin(&.{}, "request")) return;
    if (auth.sessionToken(s.request, s.secure_origin)) |token| {
        try app_authentication.revokeSession(.{
            .io = s.ctx.io,
            .gpa = s.ctx.gpa,
            .db = s.ctx.db,
            .origin = s.ctx.config.auth_origin,
            .rp_id = s.ctx.config.auth_rp_id,
        }, token);
    }
    var cookie = std.Io.Writer.Allocating.init(s.arena);
    try auth.writeClearedSessionCookie(&cookie.writer, s.secure_origin);
    try s.redirect("/login.html", cookie.written());
}

fn dashboardRefresh(s: *Submission) !void {
    s.error_key = "refresh";
    if (!try s.begin(&.{}, "request")) return;
    if (!try s.claim("in_progress")) return;
    const result = app_refresh.run(.{
        .io = s.ctx.io,
        .gpa = s.ctx.gpa,
        .db = s.ctx.db,
        .config = s.ctx.config,
    }) catch |err| {
        if (err == error.RefreshInProgress) return s.finish(409, "/?refresh=in_progress");
        std.debug.print("cloudio dashboard refresh failed: {s}\n", .{@errorName(err)});
        return s.finish(500, "/?refresh=failed");
    };
    return switch (result.statusCode()) {
        200 => s.finish(303, "/?refresh=ok"),
        207 => s.finish(207, "/?refresh=partial"),
        else => |status| s.finish(status, "/?refresh=failed"),
    };
}

fn projects(s: *Submission) !void {
    const is_scan = std.mem.eql(u8, s.request.path(), "/projects/scan");
    if (!try s.begin(if (is_scan) &.{} else null, "request")) return;
    const operation = if (is_scan) "scan" else s.field("operation") orelse return s.reject(400, "request");
    if (!is_scan and !projectFieldsValid(s.fields, operation)) return s.reject(400, "request");
    const reference: ?[]const u8 = if (is_scan) null else s.field("project") orelse return s.reject(400, "request");
    if (reference) |value| s.error_context = try s.url("&project={s}", .{value});
    if (std.mem.eql(u8, operation, "revoke") or std.mem.eql(u8, operation, "forget")) {
        confirmProject(s.ctx, reference.?, s.field("confirmation") orelse "") catch return s.reject(428, "confirmation");
    }
    if (!try s.claim("in_progress")) return;
    const success = runProjectOperation(s, operation, reference) catch |err| return s.fail(err);
    try s.finish(303, success);
}

fn runProjectOperation(s: *Submission, operation: []const u8, project_reference: ?[]const u8) ![]const u8 {
    const ctx = s.ctx;
    if (std.mem.eql(u8, operation, "scan")) {
        if (!ctx.config.nob_enabled) return error.NobDisabled;
        _ = try app_nob_projects.scan(context.nob(ctx), ctx.io, ctx.config.projects_root, ctx.config.nob_scan_depth);
        return "/projects.html?result=scanned";
    }
    const reference = project_reference.?;
    if (std.mem.eql(u8, operation, "trust")) {
        try app_nob_projects.trust(context.nob(ctx), reference, try s.fields.get("manifest_sha256"), s.actor);
        return s.url("/projects.html?project={s}&result=trusted", .{reference});
    }
    if (std.mem.eql(u8, operation, "revoke")) {
        try app_nob_projects.revoke(context.nob(ctx), reference, s.actor);
        return s.url("/projects.html?project={s}&result=revoked", .{reference});
    }
    if (std.mem.eql(u8, operation, "forget")) {
        try app_nob_projects.forget(context.nob(ctx), ctx.io, ctx.config.nob_cache_root, reference, s.actor);
        return "/projects.html?view=all&result=forgotten";
    }
    if (std.mem.eql(u8, operation, "secret-bind")) {
        try app_nob_secrets.bind(context.nobSecrets(ctx), reference, try s.fields.get("secret_id"), try s.fields.get("source_kind"), try s.fields.get("source_ref"), s.actor);
        return s.url("/projects.html?project={s}&result=secret_bound", .{reference});
    }
    if (std.mem.eql(u8, operation, "secret-unbind")) {
        try app_nob_secrets.unbind(context.nobSecrets(ctx), reference, try s.fields.get("secret_id"), s.actor);
        return s.url("/projects.html?project={s}&result=secret_unbound", .{reference});
    }
    if (std.mem.eql(u8, operation, "cancel")) {
        const run_id = try s.fields.get("run_id");
        const project = (try app_nob_projects.find(context.nob(ctx), reference)) orelse return error.ProjectNotFound;
        defer project.deinit(ctx.gpa);
        const run = (try app_nob_actions.getRun(context.nobActions(ctx), run_id)) orelse return error.RunNotFound;
        defer run.deinit(ctx.gpa);
        if (run.project_id != project.id) return error.PlanRouteMismatch;
        try app_nob_actions.cancel(context.nobActions(ctx), run_id, s.actor);
        return s.url("/projects.html?project={s}&run={s}&result=cancel_requested", .{ reference, run_id });
    }

    // The remaining operations execute or plan project code.
    if (!ctx.config.nob_enabled) return error.NobDisabled;
    if (std.mem.eql(u8, operation, "prepare")) {
        _ = try app_nob_runtime.prepareAndObserve(context.nobRuntime(ctx), reference);
        return s.url("/projects.html?project={s}&result=prepared", .{reference});
    }
    if (std.mem.eql(u8, operation, "observe")) {
        _ = try app_nob_runtime.observe(context.nobRuntime(ctx), reference);
        return s.url("/projects.html?project={s}&result=observed", .{reference});
    }
    if (std.mem.eql(u8, operation, "plan")) {
        const action_id = try s.fields.get("action_id");
        const parameters = try projectParameters(s, reference, action_id);
        var planned = try app_nob_actions.plan(context.nobActions(ctx), reference, action_id, parameters, s.actor);
        defer planned.deinit(ctx.gpa);
        return s.url("/projects.html?project={s}&plan={s}&result=planned", .{ reference, planned.id });
    }
    if (std.mem.eql(u8, operation, "resource-plan")) {
        var planned = try app_nob_actions.planResourceControl(context.nobActions(ctx), reference, try s.fields.get("resource_id"), try s.fields.get("control_name"), s.actor);
        defer planned.deinit(ctx.gpa);
        return s.url("/projects.html?project={s}&plan={s}&result=planned", .{ reference, planned.id });
    }
    if (std.mem.eql(u8, operation, "run")) {
        const plan_id = try s.fields.get("plan_id");
        const approval: app_nob_actions.Approval = .{
            .confirmed = std.mem.eql(u8, s.field("confirmation") orelse "", "confirmed"),
            .typed_project_id = s.field("confirm_project_id"),
        };
        var queued = if (s.field("resource_id")) |resource_id|
            try app_nob_actions.queueResourceControl(context.nobActions(ctx), reference, resource_id, try s.fields.get("control_name"), plan_id, approval, s.actor, s.idempotency_key)
        else
            try app_nob_actions.queueAction(context.nobActions(ctx), reference, try s.fields.get("action_id"), plan_id, approval, s.actor, s.idempotency_key);
        defer queued.deinit(ctx.gpa);
        return s.url("/projects.html?project={s}&run={s}&result=queued", .{ reference, queued.id });
    }
    return error.InvalidProjectForm;
}

/// Converts `param.<name>` fields into typed values using the action's
/// declared parameters. Undeclared, mistyped, or missing required values fail.
/// An undeclared action yields no parameters so planning reports why it is
/// unavailable (approval, runner readiness, or the action itself).
fn projectParameters(s: *Submission, reference: []const u8, action_id: []const u8) !std.json.Value {
    var details = (try app_nob_projects.show(context.nob(s.ctx), reference)) orelse return error.ProjectNotFound;
    defer details.deinit(s.ctx.gpa);
    const declaration_bytes = for (details.actions.items) |action| {
        if (std.mem.eql(u8, action.action_id, action_id)) break try s.arena.dupe(u8, action.declaration_json);
    } else return .{ .object = .empty };
    const declaration = try std.json.parseFromSliceLeaky(std.json.Value, s.arena, declaration_bytes, .{});
    const declared = jsonArray(jsonMember(declaration, "parameters"));
    var parameters: std.json.ObjectMap = .empty;
    for (s.fields.entries) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "param.")) continue;
        const name = entry.name["param.".len..];
        if (parameters.contains(name)) return error.InvalidProjectForm;
        const parameter = for (declared) |candidate| {
            if (std.mem.eql(u8, jsonString(candidate, "name"), name)) break candidate;
        } else return error.InvalidProjectForm;
        if (entry.value.len == 0 and !jsonBool(parameter, "required")) continue;
        const kind = jsonString(parameter, "type");
        const value: std.json.Value = if (std.mem.eql(u8, kind, "integer"))
            .{ .integer = std.fmt.parseInt(i64, entry.value, 10) catch return error.InvalidProjectForm }
        else if (std.mem.eql(u8, kind, "boolean"))
            .{ .bool = if (std.mem.eql(u8, entry.value, "true")) true else if (std.mem.eql(u8, entry.value, "false")) false else return error.InvalidProjectForm }
        else if (std.mem.eql(u8, kind, "enum")) blk: {
            for (jsonArray(jsonMember(parameter, "values"))) |candidate| {
                if (candidate == .string and std.mem.eql(u8, candidate.string, entry.value)) break :blk .{ .string = entry.value };
            }
            return error.InvalidProjectForm;
        } else if (std.mem.eql(u8, kind, "string"))
            .{ .string = entry.value }
        else
            return error.InvalidProjectForm;
        try parameters.put(s.arena, name, value);
    }
    for (declared) |parameter| {
        if (jsonBool(parameter, "required") and !parameters.contains(jsonString(parameter, "name"))) return error.InvalidProjectForm;
    }
    return .{ .object = parameters };
}

fn projectFieldsValid(fields: form.Form, operation: []const u8) bool {
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
        if (contains(&.{ "csrf_token", "idempotency_key", "operation", "project" }, entry.name) or contains(extras, entry.name)) continue;
        const parameter = std.mem.eql(u8, operation, "plan") and std.mem.startsWith(u8, entry.name, "param.") and entry.name.len > "param.".len;
        if (!parameter) return false;
    }
    return true;
}

fn confirmProject(ctx: context.Context, reference: []const u8, confirmation: []const u8) !void {
    const project = (try app_nob_projects.find(context.nob(ctx), reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    var id_buffer: [32]u8 = undefined;
    const expected = project.declared_id orelse try std.fmt.bufPrint(&id_buffer, "{d}", .{project.id});
    if (!auth.constantTimeEqual(confirmation, expected)) return error.ProjectConfirmationMismatch;
}

fn jsonMember(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn jsonArray(value: ?std.json.Value) []const std.json.Value {
    const item = value orelse return &.{};
    return if (item == .array) item.array.items else &.{};
}

fn jsonString(value: std.json.Value, name: []const u8) []const u8 {
    const item = jsonMember(value, name) orelse return "";
    return if (item == .string) item.string else "";
}

fn jsonBool(value: std.json.Value, name: []const u8) bool {
    const item = jsonMember(value, name) orelse return false;
    return item == .bool and item.bool;
}

fn caddyRoutes(s: *Submission) !void {
    const path = s.request.path();
    const is_refresh = std.mem.eql(u8, path, "/routes/refresh");
    const is_apply = std.mem.eql(u8, path, "/routes/apply");
    const is_adopt = std.mem.eql(u8, path, "/routes/adopt");
    const allowed: []const []const u8 = if (is_refresh)
        &.{}
    else if (is_apply)
        &.{"confirmation"}
    else if (is_adopt)
        &.{"host"}
    else
        &.{ "action", "host", "upstream", "enabled", "confirmation" };
    if (!try s.begin(allowed, "invalid_caddy_route")) return;

    var action: ?app_caddy_desired.Action = null;
    var input = app_caddy_desired.RouteInput{ .host = "" };
    if (is_apply) {
        if (!auth.constantTimeEqual(s.field("confirmation") orelse "", "APPLY")) return s.reject(428, "confirmation");
    } else if (!is_refresh) {
        input.host = s.field("host") orelse return s.reject(400, "invalid_caddy_route");
        s.error_context = try s.url("&host={s}", .{input.host});
        action = if (is_adopt) .adopt else std.meta.stringToEnum(app_caddy_desired.Action, s.field("action") orelse "") orelse
            return s.reject(400, "invalid_caddy_route");
        s.error_context = try s.url("&action={s}&host={s}", .{ @tagName(action.?), input.host });
        switch (action.?) {
            .adopt => if (!is_adopt) return s.reject(400, "invalid_caddy_route"),
            .create, .update => input.upstream = s.field("upstream") orelse return s.reject(400, "invalid_caddy_route"),
            .toggle => {
                const enabled = s.field("enabled") orelse "";
                input.enabled = if (std.mem.eql(u8, enabled, "1")) true else if (std.mem.eql(u8, enabled, "0")) false else return s.reject(400, "invalid_caddy_route");
            },
            .delete => if (!auth.constantTimeEqual(s.field("confirmation") orelse "", input.host)) return s.reject(428, "confirmation"),
        }
    }
    if (!try s.claim("caddy_write_unavailable")) return;

    var caddy_ctx = context.caddy(s.ctx);
    caddy_ctx.write_meta = s.writeMeta();
    if (is_refresh) {
        app_caddy_desired.refresh(caddy_ctx) catch |err| return s.fail(err);
        return s.finish(303, "/routes.html?result=refresh");
    }
    if (is_apply) {
        const result = app_caddy_desired.apply(caddy_ctx, .{}) catch |err| return s.fail(err);
        result.deinit(s.ctx.gpa);
        return s.finish(303, "/routes.html?result=apply");
    }
    app_caddy_desired.mutate(caddy_ctx, action.?, input) catch |err| return s.fail(err);
    try s.finish(303, try s.url("/routes.html?result={s}&host={s}", .{ @tagName(action.?), input.host }));
}

fn dns(s: *Submission) !void {
    const is_refresh = std.mem.eql(u8, s.request.path(), "/dns/refresh");
    const allowed: []const []const u8 = if (is_refresh)
        &.{"domain"}
    else
        &.{ "domain", "action", "record_id", "type", "name", "content", "ttl", "proxied", "confirmation" };
    if (!try s.begin(allowed, "invalid_dns_request")) return;
    const domain = s.field("domain") orelse return s.reject(400, "invalid_dns_request");
    s.error_context = try s.url("&domain={s}", .{domain});

    var dns_ctx = context.dns(s.ctx);
    if (is_refresh) {
        if (!try s.claim("dns_write_unavailable")) return;
        dns_ctx.write_meta = s.writeMeta();
        app_dns.refresh(dns_ctx, domain) catch |err| return s.fail(err);
        return s.finish(303, try s.url("/dns.html?domain={s}&refreshed=1", .{domain}));
    }

    const action = std.meta.stringToEnum(app_dns.Action, s.field("action") orelse "") orelse return s.reject(400, "invalid_dns_request");
    const record_id: ?[]const u8 = if (action == .create) null else s.field("record_id") orelse return s.reject(400, "invalid_dns_request");
    if (action == .update) s.error_context = try s.url("&domain={s}&edit={s}", .{ domain, record_id.? });
    if (action == .delete) s.error_context = try s.url("&domain={s}&confirm=delete&record={s}", .{ domain, record_id.? });
    var input: ?app_dns.RecordInput = null;
    if (action == .create or action == .update) {
        input = .{
            .record_type = s.field("type") orelse return s.reject(400, "invalid_dns_request"),
            .name = s.field("name") orelse return s.reject(400, "invalid_dns_request"),
            .content = s.field("content") orelse return s.reject(400, "invalid_dns_request"),
            .ttl = std.fmt.parseInt(i64, s.field("ttl") orelse "", 10) catch return s.reject(400, "invalid_dns_request"),
            .proxied = std.mem.eql(u8, s.field("proxied") orelse "", "1"),
        };
    }
    if (action == .delete) {
        const observed_name = app_dns.observedRecordName(dns_ctx, domain, record_id.?) catch |err| {
            const mapped = common.failure(err);
            return s.reject(mapped.status, mapped.code);
        };
        defer if (observed_name) |name| s.ctx.gpa.free(name);
        if (observed_name == null or !auth.constantTimeEqual(s.field("confirmation") orelse "", observed_name.?)) return s.reject(428, "confirmation");
    }
    if (!try s.claim("dns_write_unavailable")) return;
    dns_ctx.write_meta = s.writeMeta();
    const outcome = app_dns.mutate(dns_ctx, action, domain, record_id, input) catch |err| return s.fail(err);
    if (outcome == .confirmed) return s.finish(303, try s.url("/dns.html?domain={s}&result={s}", .{ domain, @tagName(action) }));
    try s.finish(202, try s.url("/dns.html?domain={s}&result=accepted_unconfirmed", .{domain}));
}

fn browserRun(s: *Submission) !void {
    if (!try s.begin(&.{ "account_id", "url", "action" }, "invalid_request")) return;
    const account_id = s.field("account_id") orelse return s.reject(400, "invalid_request");
    const url = s.field("url") orelse return s.reject(400, "invalid_request");
    const action = std.meta.stringToEnum(app_browser_run.Action, s.field("action") orelse "") orelse return s.reject(400, "invalid_request");
    if (!try s.claim("busy")) return;
    var browser_ctx = context.browserRun(s.ctx);
    browser_ctx.write_meta = s.writeMeta();
    const outcome = app_browser_run.run(browser_ctx, .{ .account_id = account_id, .url = url, .action = action }) catch |err| return s.fail(err);
    defer outcome.deinit(s.ctx.gpa);
    try s.finish(outcome.status, try s.url("/browser.html?run={s}", .{outcome.id}));
}

fn vps(s: *Submission) !void {
    const is_refresh = std.mem.eql(u8, s.request.path(), "/vps/refresh");
    if (!try s.begin(if (is_refresh) &.{} else &.{ "machine", "action", "confirmation" }, "invalid_vps_request")) return;
    var vps_ctx = context.vps(s.ctx);
    if (is_refresh) {
        if (!try s.claim("vps_write_unavailable")) return;
        vps_ctx.write_meta = s.writeMeta();
        app_vps.refresh(vps_ctx) catch |err| return s.fail(err);
        return s.finish(303, "/vps.html?refreshed=1");
    }

    const machine = s.field("machine") orelse return s.reject(400, "invalid_vps_request");
    s.error_context = try s.url("&machine={s}", .{machine});
    const action = std.meta.stringToEnum(app_vps.Action, s.field("action") orelse "") orelse return s.reject(400, "invalid_vps_request");
    s.error_context = try s.url("&machine={s}&confirm={s}", .{ machine, @tagName(action) });
    if (!auth.constantTimeEqual(s.field("confirmation") orelse "", machine)) return s.reject(428, "confirmation");
    if (!try s.claim("vps_write_unavailable")) return;
    vps_ctx.write_meta = s.writeMeta();
    const result = app_vps.mutate(vps_ctx, machine, action) catch |err| return s.fail(err);
    defer result.deinit(s.ctx.gpa);
    const confirmed = result.outcome == .confirmed;
    var success = try s.url("/vps.html?result={s}&machine={s}", .{ if (confirmed) @tagName(action) else "accepted_pending", machine });
    if (result.provider_job_id) |job| success = try std.fmt.allocPrint(s.arena, "{s}{s}", .{ success, try s.url("&job={s}", .{job}) });
    try s.finish(if (confirmed) 303 else 202, success);
}

fn docker(s: *Submission) !void {
    const is_refresh = std.mem.eql(u8, s.request.path(), "/docker/refresh");
    if (!try s.begin(if (is_refresh) &.{} else &.{ "container", "action", "confirmation" }, "invalid_container_request")) return;
    var system_ctx = context.system(s.ctx);
    if (is_refresh) {
        if (!try s.claim("container_refresh_in_progress")) return;
        system_ctx.write_meta = s.writeMeta();
        app_system_control.refreshContainers(system_ctx) catch |err| return s.fail(err);
        return s.finish(303, "/docker.html?refreshed=1");
    }

    const name = s.field("container") orelse return s.reject(400, "invalid_container_request");
    const action = std.meta.stringToEnum(app_system_control.ContainerAction, s.field("action") orelse "") orelse return s.reject(400, "invalid_container_request");
    if (!app_system_control.isSafeContainerName(name)) return s.reject(428, "confirmation");
    s.error_context = try s.url("&confirm={s}&container={s}", .{ @tagName(action), name });
    if (!auth.constantTimeEqual(s.field("confirmation") orelse "", name)) return s.reject(428, "confirmation");
    if (!try s.claim("container_refresh_in_progress")) return;
    system_ctx.write_meta = s.writeMeta();
    app_system_control.containerAction(system_ctx, name, action) catch |err| return s.fail(err);
    try s.finish(303, try s.url("/docker.html?result={s}&container={s}", .{ @tagName(action), name }));
}

fn testContext(db: *@import("../db/store.zig").Db) context.Context {
    return .{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .db = db,
        .config = .{
            .domains = &.{},
            .auth_origin = "https://cloudio.example.test",
            .auth_rp_id = "cloudio.example.test",
        },
        .auth_user_id = "owner",
        .auth_csrf_token = "known-csrf",
    };
}

fn testPost(target: []const u8, origin: []const u8, body: []const u8) http.Request {
    return .{
        .method = "POST",
        .target = target,
        .headers = if (std.mem.eql(u8, origin, "https://cloudio.example.test")) &.{
            .{ .name = "Origin", .value = "https://cloudio.example.test" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        } else &.{
            .{ .name = "Origin", .value = "https://wrong.example.test" },
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        },
        .body = body,
    };
}

fn testDb(name: []const u8) !struct { tmp: std.testing.TmpDir, db: @import("../db/store.zig").Db } {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();
    var path_buffer: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
    var db = try @import("../db/store.zig").Db.open(std.testing.io, path);
    try db.initSchema();
    return .{ .tmp = tmp, .db = db };
}

fn expectResponse(ctx: context.Context, request: http.Request, status_line: []const u8, contains_text: ?[]const u8) !void {
    var response = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer response.deinit();
    try handle(ctx, request, .light, true, &response.writer);
    try std.testing.expect(std.mem.startsWith(u8, response.written(), status_line));
    if (contains_text) |text| try std.testing.expect(std.mem.indexOf(u8, response.written(), text) != null);
}

test "theme settings post enforces security and returns native PRG" {
    var fixture = try testDb("forms-theme.db");
    defer fixture.tmp.cleanup();
    defer fixture.db.close();
    const ctx = testContext(&fixture.db);
    const good = "https://cloudio.example.test";
    try expectResponse(ctx, testPost("/settings/theme", good, "csrf_token=known-csrf&theme=dark"), "HTTP/1.1 303 See Other\r\n", "Set-Cookie: __Host-cloudio_theme=dark; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000; Secure\r\n");
    try expectResponse(ctx, testPost("/settings/theme", "wrong", "csrf_token=known-csrf&theme=dark"), "HTTP/1.1 403 Forbidden\r\n", "class=\"theme-light\"");
    try expectResponse(ctx, testPost("/settings/theme", good, "csrf_token=known-csrf&theme=neon"), "HTTP/1.1 400 Bad Request\r\n", null);
}

test "dashboard refresh rejects wrong origin unknown fields and bad csrf before collection" {
    var fixture = try testDb("forms-dashboard.db");
    defer fixture.tmp.cleanup();
    defer fixture.db.close();
    const ctx = testContext(&fixture.db);
    const good = "https://cloudio.example.test";
    try expectResponse(ctx, testPost("/dashboard/refresh", "wrong", "csrf_token=known-csrf&idempotency_key=dashboard-refresh-test-0001"), "HTTP/1.1 403 Forbidden\r\n", "failed its Origin or CSRF check");
    try expectResponse(ctx, testPost("/dashboard/refresh", good, "csrf_token=known-csrf&idempotency_key=dashboard-refresh-test-0002&surprise=1"), "HTTP/1.1 400 Bad Request\r\n", null);
    try expectResponse(ctx, testPost("/dashboard/refresh", good, "csrf_token=wrong&idempotency_key=dashboard-refresh-test-0003"), "HTTP/1.1 403 Forbidden\r\n", null);
    try std.testing.expectEqual(@as(i64, 0), try fixture.db.countTable("mutation_requests"));
}

test "docker forms enforce origin fields csrf and exact confirmation before commands" {
    var fixture = try testDb("forms-docker.db");
    defer fixture.tmp.cleanup();
    defer fixture.db.close();
    try fixture.db.upsertContainer("fixture-stopped", "example.invalid/test", "Exited (0)", "", "fixture");
    _ = try fixture.db.insertSnapshot("system", "containers", null, "ok", "observed 1 container", null, null);
    const ctx = testContext(&fixture.db);
    const good = "https://cloudio.example.test";
    try expectResponse(ctx, testPost("/docker/action", good, "csrf_token=known-csrf&idempotency_key=test-native-key-0001&container=fixture-stopped&action=start&confirmation=wrong"), "HTTP/1.1 428 Precondition Required\r\n", "Type the exact observed container name");
    try expectResponse(ctx, testPost("/docker/refresh", "wrong", "csrf_token=known-csrf&idempotency_key=test-native-key-0002"), "HTTP/1.1 403 Forbidden\r\n", null);
    try expectResponse(ctx, testPost("/docker/refresh", good, "csrf_token=known-csrf&idempotency_key=test-native-key-0003&surprise=1"), "HTTP/1.1 400 Bad Request\r\n", null);
    try std.testing.expectEqual(@as(i64, 0), try fixture.db.countTable("mutation_requests"));
}
