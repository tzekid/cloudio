const app_caddy_desired = @import("../../app/caddy_desired.zig");
const context = @import("../context.zig");
const form = @import("../form.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const url = @import("../../core/url.zig");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var draft_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer draft_arena.deinit();
    const draft = parseRoutesDraft(draft_arena.allocator(), request);
    var view = try app_caddy_desired.View.load(context.caddy(ctx));
    defer view.deinit(ctx.gpa);
    const capability = view.capability;

    try html.replaceEscapedElement(ctx.gpa, main, "routes-root", "dd", ctx.config.caddyfile_path);
    try html.replaceEscapedElement(ctx.gpa, main, "routes-fragment", "dd", ctx.config.caddy_owned_path);
    var freshness = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness.deinit();
    try html.writeStatus(&freshness.writer, view.freshness.label());
    try html.replaceElementInner(ctx.gpa, main, "routes-freshness", "dd", freshness.written());
    const observed_at = if (view.latest) |value| value.observed_at else "";
    try html.replaceEscapedElement(ctx.gpa, main, "routes-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt.deinit();
    try web_html.text(&attempt.writer, html.collectionStatusLabel(if (view.latest) |value| value.attempt_status else ""));
    const attempted_at = if (view.latest) |value| value.attempted_at else "";
    if (attempted_at.len > 0) {
        try attempt.writer.writeAll(" · ");
        try web_html.text(&attempt.writer, attempted_at);
    }
    try html.replaceElementInner(ctx.gpa, main, "routes-attempt", "dd", attempt.written());
    const capability_ready = std.mem.eql(u8, capability.code, "ready");
    try html.replaceEscapedElement(ctx.gpa, main, "caddy-apply-capability", "p", if (capability_ready) "Ready to manage routes." else capability.reason);
    if (capability_ready) {
        try html.replaceExact(ctx.gpa, main, "id=\"caddy-apply-capability\" class=\"notice tone-warning\"", "id=\"caddy-apply-capability\" class=\"notice tone-success\"");
    }

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try html.formIdempotencyKey(ctx.io, &refresh_key_buffer, "routes-refresh");
    try html.replaceHiddenInput(ctx.gpa, main, "routes-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "routes-refresh-idempotency", "idempotency_key", refresh_key);

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (view.routes.len != 0) {
        for (view.routes) |route| {
            const host = route.host;
            const enabled = route.enabled;
            const editable = route.editable;
            const state = route.state;
            try rows.writer.writeAll("<tr data-route-host=\"");
            try web_html.attribute(&rows.writer, host);
            try rows.writer.writeAll("\"><td data-label=\"State\">");
            try html.writeBadge(&rows.writer, state);
            try rows.writer.writeAll("</td>");
            try html.cellText(&rows.writer, host, "mono breakable");
            try html.cellText(&rows.writer, route.upstream, "mono breakable");
            try html.cellBadge(&rows.writer, route.ownership);
            try html.cellText(&rows.writer, route.updated_at, "muted");
            try rows.writer.writeAll("<td data-label=\"Actions\" class=\"cell-actions\"><div class=\"cluster\">");
            if (editable) {
                var toggle_key_buffer: [80]u8 = undefined;
                const toggle_key = try html.formIdempotencyKey(ctx.io, &toggle_key_buffer, "route-toggle");
                try rows.writer.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/routes/route\">");
                try html.writeHiddenInput(&rows.writer, "csrf_token", ctx.auth_csrf_token orelse "");
                try html.writeHiddenInput(&rows.writer, "idempotency_key", toggle_key);
                try html.writeHiddenInput(&rows.writer, "action", "toggle");
                try html.writeHiddenInput(&rows.writer, "host", host);
                try html.writeHiddenInput(&rows.writer, "enabled", if (enabled) "0" else "1");
                try rows.writer.writeAll("<button class=\"button button-small\" type=\"submit\">");
                try web_html.text(&rows.writer, if (enabled) "Disable" else "Enable");
                try rows.writer.writeAll("</button></form><a class=\"button button-small\" href=\"/routes.html?edit=");
                try url.writeComponent(&rows.writer, host);
                try rows.writer.writeAll("\">Edit</a><a class=\"button button-small button-danger\" href=\"/routes.html?confirm=delete&amp;host=");
                try url.writeComponent(&rows.writer, host);
                try rows.writer.writeAll("\">Remove</a>");
            } else if (std.mem.eql(u8, state, "pending_delete")) {
                try rows.writer.writeAll("<span class=\"muted\">Pending removal</span>");
            } else {
                try rows.writer.writeAll("<span class=\"muted\">Project-managed</span>");
            }
            try rows.writer.writeAll("</div></td></tr>");
        }
    }
    try html.replaceElementInner(ctx.gpa, main, "routes-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "routes-count", "span", view.routes.len, "route", "routes");
    if (view.routes.len != 0) {
        try html.replaceExact(ctx.gpa, main, "id=\"routes-empty\" class=\"panel-body route-empty-state\"", "id=\"routes-empty\" class=\"panel-body route-empty-state hidden\"");
        try html.replaceExact(ctx.gpa, main, "id=\"routes-table\" class=\"table-scroll hidden\"", "id=\"routes-table\" class=\"table-scroll\"");
    }

    var route_key_buffer: [80]u8 = undefined;
    const route_key = try html.formIdempotencyKey(ctx.io, &route_key_buffer, "route-save");
    try html.replaceHiddenInput(ctx.gpa, main, "route-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "route-idempotency", "idempotency_key", route_key);
    const edit_host = request.query("edit") orelse if (std.mem.eql(u8, request.query("action") orelse "", "update")) request.query("host") orelse "" else "";
    const edit_route = view.route(edit_host);
    if (edit_route) |route| {
        try html.replaceEscapedElement(ctx.gpa, main, "route-form-title", "h2", "Edit route");
        try html.setInputValue(ctx.gpa, main, "route-action", "update");
        try html.setInputValue(ctx.gpa, main, "route-host", edit_host);
        try html.setInputValue(ctx.gpa, main, "route-upstream", if (draft) |value| if (std.mem.eql(u8, value.action, "update")) value.upstream else route.upstream else route.upstream);
        try html.replaceExact(ctx.gpa, main, "id=\"route-form-cancel\" class=\"button hidden\"", "id=\"route-form-cancel\" class=\"button\"");
    } else if (draft) |value| if (std.mem.eql(u8, value.action, "create")) {
        try html.setInputValue(ctx.gpa, main, "route-host", value.host);
        try html.setInputValue(ctx.gpa, main, "route-upstream", value.upstream);
    };
    if (capability.write) {
        try html.replaceExact(ctx.gpa, main, "<button id=\"add-route\" class=\"button-primary\" type=\"submit\" disabled>Save route</button>", "<button id=\"add-route\" class=\"button-primary\" type=\"submit\">Save route</button>");
    }

    var adoption = std.Io.Writer.Allocating.init(ctx.gpa);
    defer adoption.deinit();
    if (view.candidates.len != 0) {
        for (view.candidates) |candidate| {
            var adopt_key_buffer: [80]u8 = undefined;
            const adopt_key = try html.formIdempotencyKey(ctx.io, &adopt_key_buffer, "route-adopt");
            try adoption.writer.writeAll("<form class=\"toolbar\" method=\"post\" action=\"/routes/adopt\"><span><code>");
            try web_html.text(&adoption.writer, candidate.host);
            try adoption.writer.writeAll("</code> → <code>");
            try web_html.text(&adoption.writer, candidate.upstream);
            try adoption.writer.writeAll("</code></span>");
            try html.writeHiddenInput(&adoption.writer, "csrf_token", ctx.auth_csrf_token orelse "");
            try html.writeHiddenInput(&adoption.writer, "idempotency_key", adopt_key);
            try html.writeHiddenInput(&adoption.writer, "host", candidate.host);
            try adoption.writer.writeAll("<button class=\"button-primary\" type=\"submit\">Adopt exact route</button></form>");
        }
    }
    try html.replaceElementInner(ctx.gpa, main, "adopt-routes", "div", adoption.written());
    if (view.candidates.len != 0) {
        try html.replaceExact(ctx.gpa, main, "id=\"routes-adoption-panel\" class=\"panel hidden\"", "id=\"routes-adoption-panel\" class=\"panel\"");
    }

    var diff_rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer diff_rows.deinit();
    if (view.diff.len != 0) {
        for (view.diff) |item| {
            try diff_rows.writer.writeAll("<tr><td data-label=\"Change\">");
            try html.writeBadge(&diff_rows.writer, @tagName(item.kind));
            try diff_rows.writer.writeAll("</td>");
            try html.dashboardCellText(&diff_rows.writer, "Host", item.host, "mono breakable", "—");
            try html.dashboardCellText(&diff_rows.writer, "Desired", item.desired_upstream, "mono breakable", "—");
            try html.dashboardCellText(&diff_rows.writer, "Observed", item.observed_upstream, "mono breakable", "—");
            try html.dashboardCellText(&diff_rows.writer, "Ownership", item.ownership, "", "—");
            try diff_rows.writer.writeAll("</tr>");
        }
    }
    try html.replaceElementInner(ctx.gpa, main, "routes-diff-body", "tbody", diff_rows.written());
    const counts = view.summary;
    const has_pending_changes = counts.pending();
    if (has_pending_changes) {
        try html.replaceExact(ctx.gpa, main, "id=\"routes-preview-panel\" class=\"panel hidden\"", "id=\"routes-preview-panel\" class=\"panel\"");
    }
    var diff_summary_buffer: [192]u8 = undefined;
    const diff_summary = try std.fmt.bufPrint(&diff_summary_buffer, "{d} additions · {d} changes · {d} removals · {d} unchanged · {d} requiring adoption", .{
        counts.additions, counts.changes, counts.removals, counts.unchanged, counts.unadopted,
    });
    try html.replaceEscapedElement(ctx.gpa, main, "routes-diff-summary", "p", diff_summary);
    const rendered = try app_caddy_desired.render(context.caddy(ctx), ctx.gpa);
    defer ctx.gpa.free(rendered);
    try html.replaceEscapedElement(ctx.gpa, main, "preview-output", "pre", rendered);
    if (!capability.apply) {
        try html.replaceExact(ctx.gpa, main, "<a id=\"apply-btn\" class=\"button button-primary\" href=\"/routes.html?confirm=apply\" aria-describedby=\"caddy-apply-capability\">Review Apply</a>", "<span id=\"apply-btn\" class=\"button button-primary\" aria-disabled=\"true\" aria-describedby=\"caddy-apply-capability\">Review Apply</span>");
    }

    try injectRouteDeleteConfirmation(ctx, request, view, draft, main);
    try injectRouteApplyConfirmation(ctx, request, draft, capability, has_pending_changes, main);
    if (routesFeedback(request)) |feedback| {
        try html.replaceEscapedElement(ctx.gpa, main, "routes-feedback", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"routes-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"routes-feedback\" class=\"notice hidden\"", replacement);
    }
}
const RoutesDraft = struct { action: []const u8, host: []const u8, upstream: []const u8, confirmation: []const u8 };
fn parseRoutesDraft(arena: std.mem.Allocator, request: http.Request) ?RoutesDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    return .{
        .action = fields.get("action") catch "",
        .host = fields.get("host") catch "",
        .upstream = fields.get("upstream") catch "",
        .confirmation = fields.get("confirmation") catch "",
    };
}
fn injectRouteDeleteConfirmation(ctx: context.Context, request: http.Request, view: app_caddy_desired.View, draft: ?RoutesDraft, main: *[]u8) !void {
    if (!std.mem.eql(u8, request.query("confirm") orelse request.query("action") orelse "", "delete")) return;
    const host = request.query("host") orelse return;
    const route = view.route(host) orelse return;
    if (!route.editable) return;
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "route-delete");
    try html.replaceHiddenInput(ctx.gpa, main, "route-delete-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "route-delete-idempotency", "idempotency_key", key);
    try html.replaceHiddenInput(ctx.gpa, main, "route-delete-host", "host", host);
    try html.replaceEscapedElement(ctx.gpa, main, "route-confirmation-target", "code", host);
    if (draft) |value| if (std.mem.eql(u8, value.action, "delete") and std.mem.eql(u8, value.host, host)) try html.setInputValue(ctx.gpa, main, "route-delete-confirmation", value.confirmation);
    try html.replaceExact(ctx.gpa, main, "id=\"route-confirmation-panel\" class=\"panel hidden\"", "id=\"route-confirmation-panel\" class=\"panel\"");
}
fn injectRouteApplyConfirmation(ctx: context.Context, request: http.Request, draft: ?RoutesDraft, capability: app_caddy_desired.Capability, has_pending_changes: bool, main: *[]u8) !void {
    const requested = std.mem.eql(u8, request.query("confirm") orelse "", "apply") or
        (std.mem.eql(u8, request.query("error") orelse "", "confirmation") and request.query("host") == null);
    if (!requested or !has_pending_changes or !capability.apply) return;
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "routes-apply");
    try html.replaceHiddenInput(ctx.gpa, main, "routes-apply-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "routes-apply-idempotency", "idempotency_key", key);
    if (draft) |value| if (value.action.len == 0) try html.setInputValue(ctx.gpa, main, "routes-apply-confirmation", value.confirmation);
    try html.replaceExact(ctx.gpa, main, "id=\"apply-confirmation-panel\" class=\"panel hidden\"", "id=\"apply-confirmation-panel\" class=\"panel\"");
}
const RoutesFeedback = struct { tone: []const u8, message: []const u8 };
fn routesFeedback(request: http.Request) ?RoutesFeedback {
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "refresh")) return .{ .tone = "success", .message = "The owned fragment observation was refreshed." };
        if (std.mem.eql(u8, result, "create")) return .{ .tone = "success", .message = "The route was added to desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "update")) return .{ .tone = "success", .message = "The route change is pending in desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "toggle")) return .{ .tone = "success", .message = "The route state changed in desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "delete")) return .{ .tone = "success", .message = "The route is marked for removal. It remains active until Apply succeeds." };
        if (std.mem.eql(u8, result, "adopt")) return .{ .tone = "success", .message = "The exact observed route is now part of Cloudio desired state." };
        if (std.mem.eql(u8, result, "apply")) return .{ .tone = "success", .message = "The owned fragment was validated, atomically replaced, reloaded, and verified." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The Routes request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The Routes form expired or its key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "The typed confirmation did not exactly match the required value." };
    if (std.mem.eql(u8, code, "invalid_caddy_route")) return .{ .tone = "danger", .message = "Use one lowercase hostname and a loopback upstream such as 127.0.0.1:9000." };
    if (std.mem.eql(u8, code, "caddy_adoption_required")) return .{ .tone = "warning", .message = "That observed route must be adopted explicitly before it can be changed." };
    if (std.mem.eql(u8, code, "caddy_observation_changed")) return .{ .tone = "warning", .message = "The fragment changed after observation. Refresh before retrying." };
    if (std.mem.eql(u8, code, "caddy_validation_failed")) return .{ .tone = "danger", .message = "Caddy rejected the candidate. The previous fragment remains active." };
    if (std.mem.eql(u8, code, "caddy_fragment_write_failed")) return .{ .tone = "danger", .message = "Cloudio could not atomically replace its fragment. The previous fragment remains active." };
    if (std.mem.eql(u8, code, "caddy_reload_failed")) return .{ .tone = "danger", .message = "Caddy reload failed. Cloudio restored and reloaded the previous fragment." };
    if (std.mem.eql(u8, code, "caddy_verification_failed")) return .{ .tone = "danger", .message = "Runtime verification failed. Cloudio restored and reloaded the previous fragment." };
    if (std.mem.eql(u8, code, "caddy_recovery_failed")) return .{ .tone = "danger", .message = "Automatic Caddy recovery failed. Follow the Routes recovery runbook immediately." };
    if (std.mem.eql(u8, code, "caddy_route_not_observed") or std.mem.eql(u8, code, "caddy_route_not_owned")) return .{ .tone = "danger", .message = "That exact route is not owned by the Routes workflow." };
    return .{ .tone = "warning", .message = "Routes changes are unavailable until the owned-fragment capability is current." };
}
