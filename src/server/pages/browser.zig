const app_browser_run = @import("../../app/browser_run.zig");
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
    try app_browser_run.writeJson(context.browserRun(ctx), request.query("run"), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const capability = html.member(parsed.value, "capability") orelse .null;
    const accounts = html.arrayItems(html.member(parsed.value, "accounts"));
    const allowed_hosts = html.arrayItems(html.member(parsed.value, "allowed_hosts"));
    const recent = html.arrayItems(html.member(parsed.value, "recent"));

    var status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer status.deinit();
    try html.writeStatus(&status.writer, if (html.boolField(capability, "available")) "Available" else "Unavailable");
    try html.replaceElementInner(ctx.gpa, main, "browser-capability-status", "span", status.written());
    try html.replaceEscapedElement(ctx.gpa, main, "browser-token-status", "dd", if (html.boolField(capability, "token")) "Configured · permission checked on run" else "API token required");
    try html.replaceEscapedElement(ctx.gpa, main, "browser-capability-reason", "p", html.strField(capability, "reason"));

    var destinations = std.Io.Writer.Allocating.init(ctx.gpa);
    defer destinations.deinit();
    if (allowed_hosts.len == 0) {
        try destinations.writer.writeAll("None configured");
    } else for (allowed_hosts, 0..) |entry, index| {
        if (index != 0) try destinations.writer.writeAll(", ");
        try web_html.text(&destinations.writer, html.asString(entry));
    }
    try html.replaceElementInner(ctx.gpa, main, "browser-destinations", "dd", destinations.written());
    var retention_buffer: [64]u8 = undefined;
    const retention_hours = html.intField(parsed.value, "retention_hours");
    const retention = try std.fmt.bufPrint(&retention_buffer, "{d} {s}", .{ retention_hours, if (retention_hours == 1) "hour" else "hours" });
    try html.replaceEscapedElement(ctx.gpa, main, "browser-retention", "dd", retention);

    var account_options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer account_options.deinit();
    if (accounts.len == 0) {
        try account_options.writer.writeAll("<option value=\"\" selected>No observed accounts</option>");
    } else for (accounts, 0..) |account, index| {
        try account_options.writer.writeAll("<option value=\"");
        try web_html.attribute(&account_options.writer, html.strField(account, "id"));
        try account_options.writer.writeByte('"');
        if (index == 0) try account_options.writer.writeAll(" selected");
        try account_options.writer.writeByte('>');
        const name = html.strField(account, "name");
        try web_html.text(&account_options.writer, if (name.len > 0) name else html.strField(account, "id"));
        if (html.strField(account, "status").len > 0) {
            try account_options.writer.writeAll(" · ");
            try web_html.text(&account_options.writer, html.strField(account, "status"));
        }
        try account_options.writer.writeAll("</option>");
    }
    try html.replaceElementInner(ctx.gpa, main, "browser-account", "select", account_options.written());
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "browser-run");
    try html.replaceHiddenInput(ctx.gpa, main, "browser-run-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "browser-run-idempotency", "idempotency_key", key);
    if (html.boolField(capability, "available")) {
        const replacements = [_][2][]const u8{
            .{ "<select id=\"browser-account\" name=\"account_id\" required disabled>", "<select id=\"browser-account\" name=\"account_id\" required>" },
            .{ "<input id=\"browser-url\" name=\"url\" type=\"url\" inputmode=\"url\" placeholder=\"https://example.com/page\" maxlength=\"4096\" autocomplete=\"off\" required disabled>", "<input id=\"browser-url\" name=\"url\" type=\"url\" inputmode=\"url\" placeholder=\"https://example.com/page\" maxlength=\"4096\" autocomplete=\"off\" required>" },
            .{ "<button id=\"browser-content-submit\" class=\"button-primary\" type=\"submit\" name=\"action\" value=\"content\" disabled>", "<button id=\"browser-content-submit\" class=\"button-primary\" type=\"submit\" name=\"action\" value=\"content\">" },
            .{ "<button id=\"browser-screenshot-submit\" type=\"submit\" name=\"action\" value=\"screenshot\" disabled>", "<button id=\"browser-screenshot-submit\" type=\"submit\" name=\"action\" value=\"screenshot\">" },
        };
        for (replacements) |replacement| try html.replaceExact(ctx.gpa, main, replacement[0], replacement[1]);
    }

    if (browserFeedback(request)) |feedback| {
        try html.replaceEscapedElement(ctx.gpa, main, "browser-notice", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"browser-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"browser-notice\" class=\"notice hidden\"", replacement);
    }

    if (html.member(parsed.value, "selected")) |selected| {
        if (selected == .object) try injectBrowserResult(ctx, selected, main);
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (recent.len == 0) {
        try html.emptyRow(&rows.writer, 6, "No Browser Run results yet.");
    } else for (recent) |run_value| {
        const id = html.strField(run_value, "id");
        try rows.writer.writeAll("<tr><td data-label=\"Started\" class=\"mono cell-nowrap\">");
        try writeEpoch(&rows.writer, html.intField(run_value, "created_at"));
        try rows.writer.writeAll("</td><td data-label=\"Action\">");
        try html.writeBadge(&rows.writer, browserActionLabel(html.strField(run_value, "action")));
        try rows.writer.writeAll("</td>");
        try html.dashboardCellText(&rows.writer, "Target", html.strField(run_value, "target_host"), "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"Result\"><a href=\"/browser.html?run=");
        try url.writeComponent(&rows.writer, id);
        try rows.writer.writeAll("\">");
        try html.writeStatus(&rows.writer, html.strField(run_value, "state"));
        try rows.writer.writeAll("</a></td><td data-label=\"Usage\" class=\"mono\">");
        if (html.intField(run_value, "browser_ms_used") > 0) try rows.writer.print("{d} ms", .{html.intField(run_value, "browser_ms_used")}) else try rows.writer.writeAll("—");
        try rows.writer.writeAll("</td><td data-label=\"Artifact\">");
        if (html.boolField(run_value, "artifact") and !html.boolField(run_value, "expired")) {
            try rows.writer.writeAll("<a href=\"/browser/artifact?id=");
            try url.writeComponent(&rows.writer, id);
            try rows.writer.writeAll("&amp;download=1\">Download</a>");
        } else if (html.boolField(run_value, "expired")) {
            try rows.writer.writeAll("<span class=\"muted\">Expired</span>");
        } else {
            try rows.writer.writeAll("<span class=\"muted\">—</span>");
        }
        try rows.writer.writeAll("</td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "browser-runs-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "browser-run-count", "span", recent.len, "run", "runs");
}
fn injectBrowserResult(ctx: context.Context, run_value: std.json.Value, main: *[]u8) !void {
    try html.replaceExact(ctx.gpa, main, "id=\"browser-result-panel\" class=\"panel hidden\"", "id=\"browser-result-panel\" class=\"panel\"");
    const state = html.strField(run_value, "state");
    const summary = if (html.strField(run_value, "error_summary").len > 0)
        html.strField(run_value, "error_summary")
    else if (html.strField(run_value, "title").len > 0)
        html.strField(run_value, "title")
    else
        "The Browser Run result was persisted by Cloudio.";
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-summary", "p", summary);
    var status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer status.deinit();
    try html.writeStatus(&status.writer, state);
    try html.replaceElementInner(ctx.gpa, main, "browser-result-status", "span", status.written());
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-target", "dd", html.strField(run_value, "target_url"));
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-action", "dd", browserActionLabel(html.strField(run_value, "action")));
    var number_buffer: [64]u8 = undefined;
    const origin = if (html.intField(run_value, "origin_status") > 0) try std.fmt.bufPrint(&number_buffer, "HTTP {d}", .{html.intField(run_value, "origin_status")}) else "—";
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-origin", "dd", origin);
    var size_buffer: [64]u8 = undefined;
    const size = if (html.intField(run_value, "size_bytes") > 0) try formatBytes(&size_buffer, html.intField(run_value, "size_bytes")) else "—";
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-size", "dd", size);
    var usage_buffer: [64]u8 = undefined;
    const usage = if (html.intField(run_value, "browser_ms_used") > 0) try std.fmt.bufPrint(&usage_buffer, "{d} ms", .{html.intField(run_value, "browser_ms_used")}) else "Not reported";
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-usage", "dd", usage);
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-ray", "dd", if (html.strField(run_value, "cf_ray").len > 0) html.strField(run_value, "cf_ray") else "Not reported");
    try html.replaceEscapedElement(ctx.gpa, main, "browser-result-sha", "dd", if (html.strField(run_value, "artifact_sha256").len > 0) html.strField(run_value, "artifact_sha256") else "—");
    var expiry = std.Io.Writer.Allocating.init(ctx.gpa);
    defer expiry.deinit();
    try writeEpoch(&expiry.writer, html.intField(run_value, "expires_at"));
    try html.replaceElementInner(ctx.gpa, main, "browser-result-expiry", "dd", expiry.written());

    var output = std.Io.Writer.Allocating.init(ctx.gpa);
    defer output.deinit();
    const id = html.strField(run_value, "id");
    if (std.mem.eql(u8, state, "succeeded") and html.boolField(run_value, "artifact") and !html.boolField(run_value, "expired")) {
        if (std.mem.eql(u8, html.strField(run_value, "action"), "screenshot")) {
            try output.writer.writeAll("<figure class=\"browser-preview\"><img src=\"/browser/artifact?id=");
            try url.writeComponent(&output.writer, id);
            try output.writer.writeAll("\" alt=\"Screenshot captured by Kitesurf\"><figcaption><a href=\"/browser/artifact?id=");
            try url.writeComponent(&output.writer, id);
            try output.writer.writeAll("&amp;download=1\">Download PNG</a></figcaption></figure>");
        } else {
            try output.writer.writeAll("<div class=\"cluster\"><a class=\"button\" href=\"/browser/artifact?id=");
            try url.writeComponent(&output.writer, id);
            try output.writer.writeAll("&amp;download=1\">Download rendered HTML</a></div><pre class=\"log-viewer browser-html-preview\">");
            try web_html.text(&output.writer, html.strField(run_value, "preview"));
            try output.writer.writeAll("</pre>");
        }
    } else if (html.strField(run_value, "error_summary").len > 0) {
        try output.writer.writeAll("<div class=\"notice tone-danger\">");
        try web_html.text(&output.writer, html.strField(run_value, "error_summary"));
        if (html.intField(run_value, "retry_after_seconds") > 0) {
            try output.writer.print(" Retry after {d} seconds.", .{html.intField(run_value, "retry_after_seconds")});
        }
        try output.writer.writeAll("</div>");
    }
    try html.replaceElementInner(ctx.gpa, main, "browser-result-output", "div", output.written());
}
const BrowserFeedback = struct { tone: []const u8, message: []const u8 };
fn browserFeedback(request: http.Request) ?BrowserFeedback {
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The Browser Run request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The Browser Run form expired or its key was reused. Reload and try again." };
    if (std.mem.eql(u8, code, "invalid_request")) return .{ .tone = "danger", .message = "Choose an observed account, an allowed public URL, and one supported output." };
    if (std.mem.eql(u8, code, "token_required")) return .{ .tone = "warning", .message = "Browser Run requires a Cloudflare API token with Browser Rendering - Edit." };
    if (std.mem.eql(u8, code, "account_not_observed")) return .{ .tone = "warning", .message = "That Cloudflare account is not part of the current observation. Refresh Cloudflare first." };
    if (std.mem.eql(u8, code, "destination_denied")) return .{ .tone = "danger", .message = "That destination is outside the configured Browser Run host policy." };
    if (std.mem.eql(u8, code, "busy")) return .{ .tone = "warning", .message = "Another Browser Run is active. Wait for it to finish before starting another." };
    return .{ .tone = "danger", .message = "The Browser Run request could not be completed." };
}
fn browserActionLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "content")) return "Rendered HTML";
    if (std.mem.eql(u8, value, "screenshot")) return "Screenshot";
    return "Unknown";
}
fn formatBytes(buffer: *[64]u8, value: i64) ![]const u8 {
    if (value >= 1024 * 1024) return try std.fmt.bufPrint(buffer, "{d:.1} MiB", .{@as(f64, @floatFromInt(value)) / (1024 * 1024)});
    if (value >= 1024) return try std.fmt.bufPrint(buffer, "{d:.1} KiB", .{@as(f64, @floatFromInt(value)) / 1024});
    return try std.fmt.bufPrint(buffer, "{d} bytes", .{value});
}
fn writeEpoch(out: *std.Io.Writer, value: i64) !void {
    if (value <= 0) {
        try out.writeAll("—");
        return;
    }
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(value) };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    try out.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2} UTC", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
    });
}
