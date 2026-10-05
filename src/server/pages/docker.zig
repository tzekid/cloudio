const app_system_control = @import("../../app/system_control.zig");
const observation = @import("../../app/observation.zig");
const context = @import("../context.zig");
const form = @import("../form.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var view = try app_system_control.View.load(context.system(ctx), ctx.config);
    defer view.deinit(ctx.gpa);

    try html.replaceEscapedElement(ctx.gpa, main, "docker-freshness", "dd", @tagName(view.freshness));
    const observed_at = observation.observedAt(view.latest);
    try html.replaceEscapedElement(ctx.gpa, main, "docker-observed-at", "dd", if (observed_at.len == 0) "Never" else observed_at);
    var collection_text = std.Io.Writer.Allocating.init(ctx.gpa);
    defer collection_text.deinit();
    const collection_status = if (view.latest) |value| value.attempt_status else "unavailable";
    const attempted_at = if (view.latest) |value| value.attempted_at else "";
    const collection_summary = if (view.latest) |value| value.attempt_summary else "No collection has run.";
    try web_html.text(&collection_text.writer, collection_status);
    if (attempted_at.len > 0) {
        try collection_text.writer.writeAll(" at ");
        try web_html.text(&collection_text.writer, attempted_at);
    }
    if (collection_summary.len > 0) {
        try collection_text.writer.writeAll(" — ");
        try web_html.text(&collection_text.writer, collection_summary);
    }
    try html.replaceElementInner(ctx.gpa, main, "docker-collection", "dd", collection_text.written());
    try html.replaceEscapedElement(ctx.gpa, main, "docker-capability", "p", view.reason);
    if (view.can_act) {
        try html.replaceExact(
            ctx.gpa,
            main,
            "id=\"docker-capability\" class=\"notice tone-warning\"",
            "id=\"docker-capability\" class=\"notice tone-success\"",
        );
    }

    const csrf = ctx.auth_csrf_token orelse "";
    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try html.formIdempotencyKey(ctx.io, &refresh_key_buffer, "docker-refresh");
    try html.replaceHiddenInput(ctx.gpa, main, "docker-refresh-csrf", "csrf_token", csrf);
    try html.replaceHiddenInput(ctx.gpa, main, "docker-refresh-idempotency", "idempotency_key", refresh_key);

    if (dockerFeedback(request)) |feedback| {
        var escaped = std.Io.Writer.Allocating.init(ctx.gpa);
        defer escaped.deinit();
        try web_html.text(&escaped.writer, feedback.message);
        try html.replaceElementInner(ctx.gpa, main, "docker-feedback", "div", escaped.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"docker-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"docker-feedback\" class=\"notice hidden\"", replacement);
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (view.containers.len == 0) {
        try html.emptyRow(&rows.writer, 5, if (observed_at.len == 0) "Refresh to observe local containers." else "No containers were observed.");
    } else for (view.containers) |container| {
        const container_name = container.row.name;
        try rows.writer.writeAll("<tr><td><a class=\"button-link mono\" data-select-container=\"");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\" href=\"/docker.html?container=");
        try web_html.urlAttribute(&rows.writer, container_name);
        try rows.writer.writeAll("&amp;tail=200\" aria-label=\"View logs for container ");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, container_name);
        try rows.writer.writeAll("</a></td>");
        try html.cellText(&rows.writer, container.row.image, "mono breakable");
        try rows.writer.writeAll("<td>");
        try html.writeStatus(&rows.writer, container.state.label());
        try rows.writer.writeAll("<div class=\"muted\">");
        try web_html.text(&rows.writer, container.row.status);
        try rows.writer.writeAll("</div></td>");
        try html.cellText(&rows.writer, container.row.ports, "mono breakable");
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\">");
        var rendered_action = false;
        var actions = container.actions.iterator();
        while (actions.next()) |action_tag| {
            const action = @tagName(action_tag);
            rendered_action = true;
            try rows.writer.writeAll("<a class=\"button button-small");
            if (std.mem.eql(u8, action, "stop")) try rows.writer.writeAll(" button-danger");
            try rows.writer.writeAll("\" href=\"/docker.html?confirm=");
            try web_html.urlAttribute(&rows.writer, action);
            try rows.writer.writeAll("&amp;container=");
            try web_html.urlAttribute(&rows.writer, container_name);
            try rows.writer.writeAll("\" data-container-action=\"");
            try web_html.attribute(&rows.writer, action);
            try rows.writer.writeAll("\" data-container-name=\"");
            try web_html.attribute(&rows.writer, container_name);
            try rows.writer.writeAll("\">");
            if (action.len > 0) try rows.writer.writeByte(std.ascii.toUpper(action[0]));
            try web_html.text(&rows.writer, action[1..]);
            try rows.writer.writeAll("</a>");
        }
        if (!rendered_action) try rows.writer.writeAll("<span class=\"muted\">Read-only</span>");
        try rows.writer.writeAll("</div></td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "containers-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "containers-count", "p", view.containers.len, "container", "containers");

    try injectDockerConfirmation(ctx, request, view, csrf, main);
    try injectDockerLogs(ctx, request, view, main);
}
const DockerFeedback = struct { tone: []const u8, message: []const u8 };
fn dockerFeedback(request: http.Request) ?DockerFeedback {
    if (request.query("refreshed") != null) return .{
        .tone = "success",
        .message = "Container observation refreshed successfully.",
    };
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "start")) return .{ .tone = "success", .message = "Container start completed and the running state was confirmed." };
        if (std.mem.eql(u8, result, "stop")) return .{ .tone = "success", .message = "Container stop completed and the stopped state was confirmed." };
        if (std.mem.eql(u8, result, "restart")) return .{ .tone = "success", .message = "Container restart completed and the running state was confirmed." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "invalid_container_request")) return .{ .tone = "danger", .message = "The container request was invalid. Check the selected target, action, confirmation, and log tail." };
    if (std.mem.eql(u8, code, "container_not_observed")) return .{ .tone = "danger", .message = "That container is not present in the last successful observation." };
    if (std.mem.eql(u8, code, "container_action_unavailable")) return .{ .tone = "warning", .message = "That action is not valid for the container's observed state." };
    if (std.mem.eql(u8, code, "container_refresh_in_progress")) return .{ .tone = "warning", .message = "A container refresh is already in progress." };
    if (std.mem.eql(u8, code, "container_command_failed")) return .{ .tone = "danger", .message = "The container command failed. The last-good observation was retained; see Audit for the redacted command result." };
    if (std.mem.eql(u8, code, "container_state_unconfirmed")) return .{ .tone = "danger", .message = "The command returned successfully, but the requested state could not be confirmed." };
    if (std.mem.eql(u8, code, "container_runtime_unavailable")) return .{ .tone = "danger", .message = "The local container runtime is unavailable. Last-good rows remain read-only." };
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The request failed its Origin or CSRF check." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The form expired or its idempotency key was already used for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "Type the exact observed container name to confirm this lifecycle action." };
    return .{ .tone = "danger", .message = "The container request failed." };
}
fn injectDockerConfirmation(
    ctx: context.Context,
    request: http.Request,
    view: app_system_control.View,
    csrf: []const u8,
    main: *[]u8,
) !void {
    const action_text = request.query("confirm") orelse return;
    const name = request.query("container") orelse return;
    const action = std.meta.stringToEnum(app_system_control.ContainerAction, action_text) orelse return;
    const container = view.container(name) orelse return;
    if (!container.actions.contains(action)) return;

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    try summary.writer.writeAll("Confirm ");
    try web_html.text(&summary.writer, action_text);
    try summary.writer.writeAll(" for ");
    try web_html.text(&summary.writer, name);
    try summary.writer.writeAll(". The current observed state is ");
    try web_html.text(&summary.writer, container.state.label());
    try summary.writer.writeByte('.');
    try html.replaceElementInner(ctx.gpa, main, "container-confirmation-summary", "p", summary.written());

    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "docker-action");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"docker-action-form\" class=\"stack\" method=\"post\" action=\"/docker/action\">");
    try html.writeHiddenInput(&body.writer, "csrf_token", csrf);
    try html.writeHiddenInput(&body.writer, "idempotency_key", key);
    try html.writeHiddenInput(&body.writer, "container", name);
    try html.writeHiddenInput(&body.writer, "action", action_text);
    try body.writer.writeAll("<div class=\"field\"><label for=\"container-confirmation-value\">Type <code>");
    try web_html.text(&body.writer, name);
    try body.writer.writeAll("</code> to confirm</label><input id=\"container-confirmation-value\" name=\"confirmation\" type=\"text\" autocomplete=\"off\" required></div><div class=\"cluster\"><button type=\"submit\" class=\"button button-primary");
    if (action == .stop) try body.writer.writeAll(" button-danger");
    try body.writer.writeAll("\">");
    if (action_text.len > 0) try body.writer.writeByte(std.ascii.toUpper(action_text[0]));
    try web_html.text(&body.writer, action_text[1..]);
    try body.writer.writeAll(" container</button><a class=\"button\" href=\"/docker.html\">Cancel</a></div></form>");
    try html.replaceElementInner(ctx.gpa, main, "container-confirmation-body", "div", body.written());
    try html.replaceExact(
        ctx.gpa,
        main,
        "id=\"container-confirmation\" class=\"panel hidden\"",
        "id=\"container-confirmation\" class=\"panel\"",
    );
}
fn injectDockerLogs(
    ctx: context.Context,
    request: http.Request,
    view: app_system_control.View,
    main: *[]u8,
) !void {
    const selected_name = request.query("container") orelse "";
    var selected_observed = false;
    var options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer options.deinit();
    try options.writer.writeAll("<option value=\"\"");
    if (selected_name.len == 0) try options.writer.writeAll(" selected");
    try options.writer.writeAll(">Select a container</option>");
    for (view.containers) |container| {
        const name = container.row.name;
        const selected = std.mem.eql(u8, name, selected_name);
        selected_observed = selected_observed or selected;
        try options.writer.writeAll("<option value=\"");
        try web_html.attribute(&options.writer, name);
        try options.writer.writeByte('"');
        if (selected) try options.writer.writeAll(" selected");
        try options.writer.writeByte('>');
        try web_html.text(&options.writer, name);
        try options.writer.writeAll("</option>");
    }
    try html.replaceElementInner(ctx.gpa, main, "log-container", "select", options.written());

    const raw_tail = request.query("tail");
    const parsed_tail = if (raw_tail) |raw| std.fmt.parseInt(i64, raw, 10) catch -1 else 200;
    const valid_tail_choice = parsed_tail == 100 or parsed_tail == 200 or parsed_tail == 500;
    const tail: i64 = if (valid_tail_choice) parsed_tail else 200;
    try html.replaceExact(ctx.gpa, main, "<option selected>200</option>", "<option>200</option>");
    var plain_buffer: [32]u8 = undefined;
    const plain = try std.fmt.bufPrint(&plain_buffer, "<option>{d}</option>", .{tail});
    var selected_buffer: [48]u8 = undefined;
    const selected = try std.fmt.bufPrint(&selected_buffer, "<option selected>{d}</option>", .{tail});
    try html.replaceExact(ctx.gpa, main, plain, selected);

    if (selected_name.len > 0) {
        var target = std.Io.Writer.Allocating.init(ctx.gpa);
        defer target.deinit();
        try target.writer.writeAll("Container: ");
        try web_html.text(&target.writer, selected_name);
        try html.replaceElementInner(ctx.gpa, main, "logs-target", "p", target.written());
    }
    if (raw_tail == null) return;

    if (!valid_tail_choice or !selected_observed) {
        try html.replaceEscapedElement(ctx.gpa, main, "logs-status", "span", if (!selected_observed) "Container is not observed." else "Tail must be 100, 200, or 500 lines.");
        try html.replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", "Logs were not read.");
        try html.replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"error\"");
        return;
    }

    const logs = app_system_control.containerLogs(context.system(ctx), selected_name, parsed_tail) catch |err| {
        const message: []const u8 = switch (err) {
            error.ContainerLogsFailed => "The runtime rejected the bounded log read.",
            error.ContainerRuntimeUnavailable => "The local container runtime is unavailable.",
            error.ContainerNotObserved => "Container is not observed.",
            else => "Logs are unavailable.",
        };
        try html.replaceEscapedElement(ctx.gpa, main, "logs-status", "span", message);
        try html.replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", message);
        try html.replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"error\"");
        return;
    };
    defer ctx.gpa.free(logs);
    try html.replaceEscapedElement(ctx.gpa, main, "logs-status", "span", "Logs updated.");
    try html.replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", if (logs.len == 0) "(empty log)" else logs);
    try html.replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"ready\"");
}
