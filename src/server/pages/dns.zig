const app_dns = @import("../../app/dns.zig");
const observation = @import("../../app/observation.zig");
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
    const draft = parseDnsDraft(draft_arena.allocator(), request);
    var view = try app_dns.View.load(context.dns(ctx), request.query("domain"));
    defer view.deinit(ctx.gpa);
    const domain = view.domain;

    var zone_options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer zone_options.deinit();
    if (view.zones.len == 0) {
        try zone_options.writer.writeAll("<option value=\"\" selected>No configured zones</option>");
    } else for (view.zones) |zone| {
        const configured = zone.domain;
        try zone_options.writer.writeAll("<option value=\"");
        try web_html.attribute(&zone_options.writer, configured);
        try zone_options.writer.writeByte('"');
        if (std.mem.eql(u8, configured, domain)) try zone_options.writer.writeAll(" selected");
        try zone_options.writer.writeByte('>');
        try web_html.text(&zone_options.writer, configured);
        if (!zone.observed) try zone_options.writer.writeAll(" (not observed)");
        try zone_options.writer.writeAll("</option>");
    }
    try html.replaceElementInner(ctx.gpa, main, "domain", "select", zone_options.written());

    var source_note = std.Io.Writer.Allocating.init(ctx.gpa);
    defer source_note.deinit();
    if (domain.len == 0) {
        try source_note.writer.writeAll("No configured zone selected.");
    } else {
        try source_note.writer.writeAll("Stored Cloudflare observation for ");
        try web_html.text(&source_note.writer, domain);
        try source_note.writer.writeByte('.');
    }
    try html.replaceElementInner(ctx.gpa, main, "dns-source-note", "p", source_note.written());
    var freshness_status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness_status.deinit();
    try html.writeStatus(&freshness_status.writer, view.freshness.label());
    try html.replaceElementInner(ctx.gpa, main, "dns-freshness", "span", freshness_status.written());
    const observed_at = observation.observedAt(view.latest);
    try html.replaceEscapedElement(ctx.gpa, main, "dns-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt_text = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt_text.deinit();
    try web_html.text(&attempt_text.writer, html.collectionStatusLabel(if (view.latest) |value| value.attempt_status else ""));
    const attempted_at = if (view.latest) |value| value.attempted_at else "";
    if (attempted_at.len > 0) {
        try attempt_text.writer.writeAll(" · ");
        try web_html.text(&attempt_text.writer, attempted_at);
    }
    try html.replaceElementInner(ctx.gpa, main, "dns-attempt", "dd", attempt_text.written());
    try html.replaceEscapedElement(ctx.gpa, main, "dns-capability", "p", view.reason);

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try html.formIdempotencyKey(ctx.io, &refresh_key_buffer, "dns-refresh");
    try html.replaceHiddenInput(ctx.gpa, main, "dns-refresh-domain", "domain", domain);
    try html.replaceHiddenInput(ctx.gpa, main, "dns-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "dns-refresh-idempotency", "idempotency_key", refresh_key);
    if (view.can_refresh) {
        try html.replaceExact(ctx.gpa, main, "<button class=\"button-primary\" type=\"submit\" disabled>Refresh zone</button>", "<button class=\"button-primary\" type=\"submit\">Refresh zone</button>");
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (view.records.len == 0) {
        try html.emptyRow(&rows.writer, 6, if (domain.len == 0) "Choose a configured zone." else "No DNS records observed for this zone.");
    } else for (view.records) |record| {
        const record_id = record.row.id;
        try rows.writer.writeAll("<tr data-dns-record=\"");
        try web_html.attribute(&rows.writer, record_id);
        try rows.writer.writeAll("\">");
        try rows.writer.writeAll("<td data-label=\"Type\">");
        try html.writeBadge(&rows.writer, record.row.record_type);
        try rows.writer.writeAll("</td>");
        try html.dashboardCellText(&rows.writer, "Name", record.row.name, "mono breakable", "—");
        try html.dashboardCellText(&rows.writer, "Content", record.row.content, "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"TTL\" class=\"mono\">");
        try rows.writer.print("{d}", .{record.ttl});
        try rows.writer.writeAll("</td><td data-label=\"Proxy\">");
        try html.writeBadge(&rows.writer, if (record.proxied) "Proxied" else "DNS only");
        try rows.writer.writeAll("</td><td data-label=\"Actions\" class=\"cell-actions\"><div class=\"table-actions\">");
        if (record.can_edit) try writeDnsRecordLink(&rows.writer, domain, "edit", record_id, "Edit", false);
        if (record.can_toggle) {
            var toggle_key_buffer: [80]u8 = undefined;
            const toggle_key = try html.formIdempotencyKey(ctx.io, &toggle_key_buffer, "dns-toggle");
            try writeDnsInlineActionForm(&rows.writer, ctx.auth_csrf_token orelse "", toggle_key, domain, "toggle", record_id, if (record.proxied) "Set DNS only" else "Enable proxy", false);
        }
        if (record.can_delete) try writeDnsRecordLink(&rows.writer, domain, "confirm", record_id, "Delete", true);
        if (!record.can_edit and !record.can_toggle and !record.can_delete) try rows.writer.writeAll("<span class=\"muted\">Read-only</span>");
        try rows.writer.writeAll("</div></td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "records-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "record-count", "span", view.records.len, "record", "records");

    var create_key_buffer: [80]u8 = undefined;
    const create_key = try html.formIdempotencyKey(ctx.io, &create_key_buffer, "dns-create");
    try html.replaceHiddenInput(ctx.gpa, main, "dns-create-domain", "domain", domain);
    try html.replaceHiddenInput(ctx.gpa, main, "dns-create-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "dns-create-idempotency", "idempotency_key", create_key);
    if (view.can_write) try enableDnsCreateForm(ctx.gpa, main);
    if (draft) |value| if (std.mem.eql(u8, value.action, "create")) try applyDnsCreateDraft(ctx.gpa, main, value);

    try injectDnsEdit(ctx, request, view, draft, main);
    try injectDnsDelete(ctx, request, view, draft, main);
    if (dnsFeedback(request)) |feedback| {
        try html.replaceEscapedElement(ctx.gpa, main, "dns-notice", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"dns-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"dns-notice\" class=\"notice hidden\"", replacement);
    }
}
const DnsFeedback = struct { tone: []const u8, message: []const u8 };
fn dnsFeedback(request: http.Request) ?DnsFeedback {
    if (request.query("refreshed")) |value| if (std.mem.eql(u8, value, "1")) return .{ .tone = "success", .message = "The zone observation was refreshed from Cloudflare." };
    if (request.query("result")) |value| {
        if (std.mem.eql(u8, value, "create")) return .{ .tone = "success", .message = "The record was created and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "update")) return .{ .tone = "success", .message = "The record was updated and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "toggle")) return .{ .tone = "success", .message = "The proxy setting was changed and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "delete")) return .{ .tone = "success", .message = "The record deletion was confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "accepted_unconfirmed")) return .{ .tone = "warning", .message = "Cloudflare accepted the change, but the confirmation read failed. Retained records are read-only until Refresh succeeds." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The DNS request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The DNS form expired or its key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "invalid_dns_request")) return .{ .tone = "danger", .message = "The record input is invalid. Check its type, name, content, TTL, and proxy setting." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "The confirmation did not exactly match the observed record name." };
    if (std.mem.eql(u8, code, "dns_zone_not_observed")) return .{ .tone = "warning", .message = "That configured zone has not been observed. Refresh it before changing records." };
    if (std.mem.eql(u8, code, "dns_record_not_observed")) return .{ .tone = "danger", .message = "That record is not part of the current zone observation." };
    if (std.mem.eql(u8, code, "dns_write_unavailable")) return .{ .tone = "warning", .message = "Record changes are unavailable until this exact zone has a current successful refresh." };
    if (std.mem.eql(u8, code, "dns_provider_rejected")) return .{ .tone = "danger", .message = "Cloudflare rejected the request. Existing observed records were retained." };
    if (std.mem.eql(u8, code, "dns_provider_unavailable")) return .{ .tone = "danger", .message = "Cloudflare could not be reached. Existing observed records were retained." };
    return .{ .tone = "danger", .message = "The DNS request could not be completed." };
}
fn enableDnsCreateForm(gpa: std.mem.Allocator, main: *[]u8) !void {
    const replacements = [_][2][]const u8{
        .{ "<select id=\"record-type\" name=\"type\" disabled>", "<select id=\"record-type\" name=\"type\">" },
        .{ "<input id=\"record-name\" name=\"name\" type=\"text\" placeholder=\"www or @\" required autocomplete=\"off\" disabled>", "<input id=\"record-name\" name=\"name\" type=\"text\" placeholder=\"www or @\" required autocomplete=\"off\">" },
        .{ "<input id=\"record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\" disabled>", "<input id=\"record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\">" },
        .{ "<input id=\"record-ttl\" name=\"ttl\" type=\"number\" value=\"1\" min=\"1\" max=\"86400\" required disabled>", "<input id=\"record-ttl\" name=\"ttl\" type=\"number\" value=\"1\" min=\"1\" max=\"86400\" required>" },
        .{ "<input id=\"record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\" disabled>", "<input id=\"record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\">" },
        .{ "<button id=\"add-record\" class=\"button-primary\" type=\"submit\" disabled>Add record</button>", "<button id=\"add-record\" class=\"button-primary\" type=\"submit\">Add record</button>" },
    };
    for (replacements) |item| try html.replaceExact(gpa, main, item[0], item[1]);
}
const DnsDraft = struct {
    action: []const u8,
    record_id: []const u8,
    record_type: []const u8,
    name: []const u8,
    content: []const u8,
    ttl: []const u8,
    proxied: bool,
    confirmation: []const u8,
};
fn parseDnsDraft(arena: std.mem.Allocator, request: http.Request) ?DnsDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    const action = fields.get("action") catch return null;
    return .{
        .action = action,
        .record_id = fields.get("record_id") catch "",
        .record_type = fields.get("type") catch "A",
        .name = fields.get("name") catch "",
        .content = fields.get("content") catch "",
        .ttl = fields.get("ttl") catch "1",
        .proxied = if (fields.get("proxied")) |value| std.mem.eql(u8, value, "1") else |_| false,
        .confirmation = fields.get("confirmation") catch "",
    };
}
fn applyDnsCreateDraft(gpa: std.mem.Allocator, main: *[]u8, draft: DnsDraft) !void {
    if (isSupportedDnsType(draft.record_type)) try html.selectOption(gpa, main, "record-type", "A", draft.record_type);
    try html.setInputValue(gpa, main, "record-name", draft.name);
    try html.setInputValue(gpa, main, "record-content", draft.content);
    try html.setInputValue(gpa, main, "record-ttl", draft.ttl);
    try html.setInputChecked(gpa, main, "record-proxied", draft.proxied);
}
fn isSupportedDnsType(value: []const u8) bool {
    for ([_][]const u8{ "A", "AAAA", "CNAME", "TXT" }) |record_type| {
        if (std.mem.eql(u8, value, record_type)) return true;
    }
    return false;
}
fn writeDnsRecordLink(out: *std.Io.Writer, domain: []const u8, mode: []const u8, record_id: []const u8, label: []const u8, danger: bool) !void {
    try out.writeAll("<a class=\"button button-small");
    if (danger) try out.writeAll(" button-danger");
    try out.writeAll("\" href=\"/dns.html?domain=");
    try url.writeComponent(out, domain);
    try out.writeByte('&');
    try web_html.urlAttribute(out, mode);
    try out.writeByte('=');
    if (std.mem.eql(u8, mode, "confirm")) try out.writeAll("delete&record=");
    try url.writeComponent(out, record_id);
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</a>");
}
fn writeDnsInlineActionForm(out: *std.Io.Writer, csrf: []const u8, key: []const u8, domain: []const u8, action: []const u8, record_id: []const u8, label: []const u8, danger: bool) !void {
    try out.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/dns/record\">");
    try html.writeHiddenInput(out, "csrf_token", csrf);
    try html.writeHiddenInput(out, "idempotency_key", key);
    try html.writeHiddenInput(out, "domain", domain);
    try html.writeHiddenInput(out, "action", action);
    try html.writeHiddenInput(out, "record_id", record_id);
    try out.writeAll("<button type=\"submit\" class=\"button button-small");
    if (danger) try out.writeAll(" button-danger");
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</button></form>");
}
fn injectDnsEdit(ctx: context.Context, request: http.Request, view: app_dns.View, draft: ?DnsDraft, main: *[]u8) !void {
    const domain = view.domain;
    const record_id = request.query("edit") orelse return;
    const record = view.record(record_id) orelse return;
    if (!record.can_edit) return;
    const submitted = if (draft) |value| std.mem.eql(u8, value.action, "update") and std.mem.eql(u8, value.record_id, record_id) else false;
    const selected_record_type = if (submitted and isSupportedDnsType(draft.?.record_type)) draft.?.record_type else record.row.record_type;
    const name = if (submitted) draft.?.name else record.row.name;
    const content = if (submitted) draft.?.content else record.row.content;
    const ttl = if (submitted) draft.?.ttl else "";
    const proxied = if (submitted) draft.?.proxied else record.proxied;
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "dns-update");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"edit-record-form\" class=\"form-grid\" method=\"post\" action=\"/dns/record\">");
    try html.writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(&body.writer, "idempotency_key", key);
    try html.writeHiddenInput(&body.writer, "domain", domain);
    try html.writeHiddenInput(&body.writer, "action", "update");
    try html.writeHiddenInput(&body.writer, "record_id", record_id);
    try body.writer.writeAll("<div class=\"field span-2\"><label for=\"edit-record-type\">Type</label><select id=\"edit-record-type\" name=\"type\">");
    for ([_][]const u8{ "A", "AAAA", "CNAME", "TXT" }) |option_type| {
        try body.writer.writeAll("<option value=\"");
        try body.writer.writeAll(option_type);
        try body.writer.writeByte('"');
        if (std.mem.eql(u8, option_type, selected_record_type)) try body.writer.writeAll(" selected");
        try body.writer.writeByte('>');
        try body.writer.writeAll(option_type);
        try body.writer.writeAll("</option>");
    }
    try body.writer.writeAll("</select></div><div class=\"field span-3\"><label for=\"edit-record-name\">Name</label><input id=\"edit-record-name\" name=\"name\" type=\"text\" required autocomplete=\"off\" value=\"");
    try web_html.attribute(&body.writer, name);
    try body.writer.writeAll("\"></div><div class=\"field span-4\"><label for=\"edit-record-content\">Content</label><input id=\"edit-record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\" value=\"");
    try web_html.attribute(&body.writer, content);
    try body.writer.writeAll("\"></div><div class=\"field span-2\"><label for=\"edit-record-ttl\">TTL</label><input id=\"edit-record-ttl\" name=\"ttl\" type=\"number\" min=\"1\" max=\"86400\" required value=\"");
    if (submitted) try web_html.attribute(&body.writer, ttl) else try body.writer.print("{d}", .{record.ttl});
    try body.writer.writeAll("\"></div><label class=\"field-inline\" for=\"edit-record-proxied\"><input id=\"edit-record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\"");
    if (proxied) try body.writer.writeAll(" checked");
    try body.writer.writeAll("> Proxied</label><div class=\"span-12 cluster\"><button class=\"button-primary\" type=\"submit\">Save record</button><a class=\"button\" href=\"/dns.html?domain=");
    try url.writeComponent(&body.writer, domain);
    try body.writer.writeAll("\">Cancel</a></div></form>");
    try html.replaceElementInner(ctx.gpa, main, "edit-record-body", "div", body.written());
    try html.replaceExact(ctx.gpa, main, "id=\"edit-record-panel\" class=\"panel hidden\"", "id=\"edit-record-panel\" class=\"panel\"");
}
fn injectDnsDelete(ctx: context.Context, request: http.Request, view: app_dns.View, draft: ?DnsDraft, main: *[]u8) !void {
    const domain = view.domain;
    if (!std.mem.eql(u8, request.query("confirm") orelse "", "delete")) return;
    const record_id = request.query("record") orelse return;
    const record = view.record(record_id) orelse return;
    if (!record.can_delete) return;
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "dns-delete");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<p>Delete the ");
    try web_html.text(&body.writer, record.row.record_type);
    try body.writer.writeAll(" record <code>");
    try web_html.text(&body.writer, record.row.name);
    try body.writer.writeAll("</code>. This changes public DNS.</p><form id=\"delete-record-form\" class=\"stack\" method=\"post\" action=\"/dns/record\">");
    try html.writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(&body.writer, "idempotency_key", key);
    try html.writeHiddenInput(&body.writer, "domain", domain);
    try html.writeHiddenInput(&body.writer, "action", "delete");
    try html.writeHiddenInput(&body.writer, "record_id", record_id);
    try body.writer.writeAll("<div class=\"field\"><label for=\"dns-delete-confirmation\">Type <code>");
    try web_html.text(&body.writer, record.row.name);
    try body.writer.writeAll("</code> to confirm</label><input id=\"dns-delete-confirmation\" name=\"confirmation\" type=\"text\" required autocomplete=\"off\" value=\"");
    if (draft) |value| if (std.mem.eql(u8, value.action, "delete") and std.mem.eql(u8, value.record_id, record_id)) try web_html.attribute(&body.writer, value.confirmation);
    try body.writer.writeAll("\"></div><div class=\"cluster\"><button class=\"button button-danger\" type=\"submit\">Delete record</button><a class=\"button\" href=\"/dns.html?domain=");
    try url.writeComponent(&body.writer, domain);
    try body.writer.writeAll("\">Cancel</a></div></form>");
    try html.replaceElementInner(ctx.gpa, main, "delete-record-body", "div", body.written());
    try html.replaceExact(ctx.gpa, main, "id=\"delete-record-panel\" class=\"panel hidden\"", "id=\"delete-record-panel\" class=\"panel\"");
}

