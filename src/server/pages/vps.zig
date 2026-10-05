const app_vps = @import("../../app/vps.zig");
const context = @import("../context.zig");
const form = @import("../form.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const url = @import("../../core/url.zig");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_vps.writeJson(context.vps(ctx), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const machines = html.arrayItems(html.member(parsed.value, "machines"));
    const collection = html.member(parsed.value, "collection") orelse .null;
    const capability = html.member(parsed.value, "capability") orelse .null;

    var freshness = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness.deinit();
    try html.writeStatus(&freshness.writer, html.freshnessLabel(html.strField(parsed.value, "freshness")));
    try html.replaceElementInner(ctx.gpa, main, "vps-freshness", "dd", freshness.written());
    const observed_at = html.nullableString(html.member(parsed.value, "observed_at"));
    try html.replaceEscapedElement(ctx.gpa, main, "vps-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt.deinit();
    try web_html.text(&attempt.writer, html.collectionStatusLabel(html.strField(collection, "status")));
    const attempted_at = html.nullableString(html.member(collection, "attempted_at"));
    if (attempted_at.len > 0) {
        try attempt.writer.writeAll(" · ");
        try web_html.text(&attempt.writer, attempted_at);
    }
    try html.replaceElementInner(ctx.gpa, main, "vps-attempt", "dd", attempt.written());
    try html.replaceEscapedElement(ctx.gpa, main, "vps-capability", "p", html.strField(capability, "reason"));

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try html.formIdempotencyKey(ctx.io, &refresh_key_buffer, "vps-refresh");
    try html.replaceHiddenInput(ctx.gpa, main, "vps-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "vps-refresh-idempotency", "idempotency_key", refresh_key);
    if (html.boolField(capability, "refresh")) try html.replaceExact(ctx.gpa, main, "<button class=\"button-primary\" type=\"submit\" disabled>Refresh machines</button>", "<button class=\"button-primary\" type=\"submit\">Refresh machines</button>");

    var cards = std.Io.Writer.Allocating.init(ctx.gpa);
    defer cards.deinit();
    try cards.writer.writeAll("<div id=\"machines\" class=\"resource-grid\">");
    if (machines.len == 0) {
        try cards.writer.writeAll("<div class=\"resource-card empty-state\">Refresh to observe Hostinger machines.</div>");
    } else for (machines) |machine| {
        const machine_id = html.strField(machine, "id");
        const actions = html.member(machine, "actions") orelse .null;
        try cards.writer.writeAll("<article class=\"resource-card\" data-vps-machine=\"");
        try web_html.attribute(&cards.writer, machine_id);
        try cards.writer.writeAll("\"><div class=\"resource-card-header\"><h3 class=\"resource-card-title\">");
        try web_html.text(&cards.writer, html.firstString(machine, &.{ "name", "id" }));
        try cards.writer.writeAll("</h3>");
        try html.writeStatus(&cards.writer, html.strField(machine, "status"));
        try cards.writer.writeAll("</div><dl class=\"kv-list\">");
        try html.definition(&cards.writer, "IPv4", html.strField(machine, "ipv4"));
        try html.definition(&cards.writer, "Plan", html.strField(machine, "plan"));
        try html.definition(&cards.writer, "ID", machine_id);
        try html.definition(&cards.writer, "Observed", html.strField(machine, "observed_at"));
        try cards.writer.writeAll("</dl><div class=\"resource-card-actions\">");
        var rendered_action = false;
        for ([_][]const u8{ "start", "stop", "restart" }) |action| {
            if (!html.boolField(actions, action)) continue;
            rendered_action = true;
            try writeVpsActionLink(&cards.writer, machine_id, action);
        }
        if (!rendered_action) {
            try cards.writer.writeAll("<span class=\"muted\">");
            try web_html.text(&cards.writer, html.strField(machine, "capability_reason"));
            try cards.writer.writeAll("</span>");
        }
        try cards.writer.writeAll("</div></article>");
    }
    try cards.writer.writeAll("</div>");
    try html.replaceExact(ctx.gpa, main, "<div id=\"machines\" class=\"resource-grid\">\n        <div class=\"resource-card empty-state loading-state\">Loading machines…</div>\n      </div>", cards.written());
    try html.replaceCountLabel(ctx.gpa, main, "machine-count", "p", machines.len, "machine", "machines");


    try injectVpsConfirmation(ctx, request, machines, main);
    if (vpsFeedback(request)) |feedback| {
        var message = std.Io.Writer.Allocating.init(ctx.gpa);
        defer message.deinit();
        try web_html.text(&message.writer, feedback.message);
        if (request.query("job")) |job| {
            try message.writer.writeAll(" Provider job: ");
            try web_html.text(&message.writer, job);
            try message.writer.writeByte('.');
        }
        try html.replaceElementInner(ctx.gpa, main, "vps-notice", "div", message.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"vps-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"vps-notice\" class=\"notice hidden\"", replacement);
    }
}
fn writeVpsActionLink(out: *std.Io.Writer, machine_id: []const u8, action: []const u8) !void {
    try out.writeAll("<a class=\"button button-small");
    if (std.mem.eql(u8, action, "stop")) try out.writeAll(" button-danger");
    try out.writeAll("\" href=\"/vps.html?confirm=");
    try url.writeComponent(out, action);
    try out.writeAll("&amp;machine=");
    try url.writeComponent(out, machine_id);
    try out.writeAll("\" data-vps-action=\"");
    try web_html.attribute(out, action);
    try out.writeAll("\" data-vps-id=\"");
    try web_html.attribute(out, machine_id);
    try out.writeAll("\">");
    if (action.len > 0) try out.writeByte(std.ascii.toUpper(action[0]));
    try web_html.text(out, action[1..]);
    try out.writeAll("</a>");
}
const VpsDraft = struct { machine: []const u8, action: []const u8, confirmation: []const u8 };
fn parseVpsDraft(arena: std.mem.Allocator, request: http.Request) ?VpsDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    return .{
        .machine = fields.get("machine") catch "",
        .action = fields.get("action") catch "",
        .confirmation = fields.get("confirmation") catch "",
    };
}
fn injectVpsConfirmation(ctx: context.Context, request: http.Request, machines: []const std.json.Value, main: *[]u8) !void {
    const action_text = request.query("confirm") orelse return;
    const machine_id = request.query("machine") orelse return;
    const action = std.meta.stringToEnum(app_vps.Action, action_text) orelse return;
    const machine = findJsonMachine(machines, machine_id) orelse return;
    const actions = html.member(machine, "actions") orelse .null;
    if (!html.boolField(actions, action_text)) return;

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    try summary.writer.writeAll("Confirm ");
    try web_html.text(&summary.writer, action_text);
    try summary.writer.writeAll(" for ");
    try web_html.text(&summary.writer, html.firstString(machine, &.{ "name", "id" }));
    try summary.writer.writeAll(". The current observed state is ");
    try web_html.text(&summary.writer, html.strField(machine, "status"));
    try summary.writer.writeByte('.');
    try html.replaceElementInner(ctx.gpa, main, "vps-confirmation-summary", "p", summary.written());

    var draft_arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer draft_arena_state.deinit();
    const draft = parseVpsDraft(draft_arena_state.allocator(), request);
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "vps-action");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"vps-action-form\" class=\"stack\" method=\"post\" action=\"/vps/action\">");
    try html.writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(&body.writer, "idempotency_key", key);
    try html.writeHiddenInput(&body.writer, "machine", machine_id);
    try html.writeHiddenInput(&body.writer, "action", action_text);
    try body.writer.writeAll("<div class=\"field\"><label for=\"vps-confirmation-value\">Type <code>");
    try web_html.text(&body.writer, machine_id);
    try body.writer.writeAll("</code> to confirm</label><input id=\"vps-confirmation-value\" name=\"confirmation\" type=\"text\" autocomplete=\"off\" required value=\"");
    if (draft) |value| if (std.mem.eql(u8, value.machine, machine_id) and std.mem.eql(u8, value.action, action_text)) try web_html.attribute(&body.writer, value.confirmation);
    try body.writer.writeAll("\"></div><div class=\"cluster\"><button type=\"submit\" class=\"button button-primary");
    if (action == .stop) try body.writer.writeAll(" button-danger");
    try body.writer.writeAll("\">");
    if (action_text.len > 0) try body.writer.writeByte(std.ascii.toUpper(action_text[0]));
    try web_html.text(&body.writer, action_text[1..]);
    try body.writer.writeAll(" machine</button><a class=\"button\" href=\"/vps.html\">Cancel</a></div></form>");
    try html.replaceElementInner(ctx.gpa, main, "vps-confirmation-body", "div", body.written());
    try html.replaceExact(ctx.gpa, main, "id=\"vps-confirmation\" class=\"panel hidden\"", "id=\"vps-confirmation\" class=\"panel\"");
}
fn findJsonMachine(machines: []const std.json.Value, machine_id: []const u8) ?std.json.Value {
    for (machines) |machine| if (std.mem.eql(u8, html.strField(machine, "id"), machine_id)) return machine;
    return null;
}
const VpsFeedback = struct { tone: []const u8, message: []const u8 };
fn vpsFeedback(request: http.Request) ?VpsFeedback {
    if (request.query("refreshed") != null) return .{ .tone = "success", .message = "Machine observation refreshed successfully." };
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "start")) return .{ .tone = "success", .message = "Machine start completed and the running state was confirmed." };
        if (std.mem.eql(u8, result, "stop")) return .{ .tone = "success", .message = "Machine stop completed and the stopped state was confirmed." };
        if (std.mem.eql(u8, result, "restart")) return .{ .tone = "success", .message = "Machine restart completed and the provider job plus running state were confirmed." };
        if (std.mem.eql(u8, result, "accepted_pending")) return .{ .tone = "warning", .message = "Hostinger accepted the action, but bounded reconciliation is still pending. This machine is read-only until Refresh succeeds." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The VPS request failed its Origin or CSRF check." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The form expired or its idempotency key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "Type the exact observed machine ID to confirm this lifecycle action." };
    if (std.mem.eql(u8, code, "invalid_vps_request")) return .{ .tone = "danger", .message = "The VPS request is invalid." };
    if (std.mem.eql(u8, code, "vps_not_observed")) return .{ .tone = "danger", .message = "That machine is not part of the current Hostinger observation." };
    if (std.mem.eql(u8, code, "vps_action_unavailable")) return .{ .tone = "warning", .message = "That action is not valid for the machine's observed state." };
    if (std.mem.eql(u8, code, "vps_write_unavailable")) return .{ .tone = "warning", .message = "Machine actions require a current successful observation with no pending reconciliation." };
    if (std.mem.eql(u8, code, "vps_provider_rejected")) return .{ .tone = "danger", .message = "Hostinger rejected the action or reported a failed job. The last observed state was retained." };
    if (std.mem.eql(u8, code, "vps_provider_unavailable")) return .{ .tone = "danger", .message = "Hostinger could not be reached. The last-good machine observation was retained." };
    return .{ .tone = "danger", .message = "The VPS request could not be completed." };
}
