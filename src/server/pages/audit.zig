const app_writes = @import("../../app/writes.zig");
const common = @import("../common.zig");
const context = @import("../context.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    const options = common.auditOptions(request);
    try html.selectOption(ctx.gpa, main, "audit-view", "important", @tagName(options.view));
    try html.selectOption(ctx.gpa, main, "audit-category", "", options.category orelse "");
    try html.selectOption(ctx.gpa, main, "audit-result", "all", @tagName(options.result));
    try html.selectOption(ctx.gpa, main, "audit-window", "24h", options.window.value());
    var default_limit_buffer: [32]u8 = undefined;
    const default_limit = try std.fmt.bufPrint(&default_limit_buffer, "{d}", .{@as(i64, 100)});
    var limit_buffer: [32]u8 = undefined;
    const limit = try std.fmt.bufPrint(&limit_buffer, "{d}", .{options.limit});
    try html.selectTextOption(ctx.gpa, main, "audit-limit", default_limit, limit);
    try html.replaceTextInputValue(ctx.gpa, main, "audit-target", "target", options.target orelse "");
    try html.replaceTextInputValue(ctx.gpa, main, "audit-actor", "actor", options.actor orelse "");

    var audit = try app_writes.auditEntries(ctx.gpa, ctx.db, options);
    defer audit.deinit();
    const entries = audit.items;

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (entries.len == 0) {
        try html.emptyRow(&rows.writer, 6, "No entries match this view.");
    } else for (entries) |entry| {
        try rows.writer.writeAll("<tr data-audit-source=\"");
        try web_html.attribute(&rows.writer, entry.source);
        try rows.writer.writeAll("\" data-audit-category=\"");
        try web_html.attribute(&rows.writer, entry.category);
        try rows.writer.writeAll("\">");
        try html.dashboardCellText(&rows.writer, "Time", entry.created_at, "mono cell-nowrap", "—");
        try html.dashboardCellText(&rows.writer, "Actor", entry.actor, "mono", "system");
        try rows.writer.writeAll("<td data-label=\"Action\"><div>");
        try writeAuditOwnerLink(&rows.writer, entry);
        try rows.writer.writeAll("</div><span class=\"muted\">");
        try web_html.text(&rows.writer, auditCategoryLabel(entry.category));
        try rows.writer.writeAll(" · ");
        try web_html.text(&rows.writer, if (std.mem.eql(u8, entry.source, "mutation")) "Mutation" else "Event");
        try rows.writer.writeAll("</span></td>");
        try html.dashboardCellText(&rows.writer, "Target", entry.target, "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"Result\">");
        try html.writeStatus(&rows.writer, entry.result);
        try rows.writer.writeAll("</td><td data-label=\"Detail\"><details><summary>View details</summary>");
        try html.detail(&rows.writer, "Request", entry.request);
        try html.detail(&rows.writer, "Detail", entry.detail);
        try html.detail(&rows.writer, "Idempotency key", entry.idempotency_key);
        try html.detail(&rows.writer, "Entry identity", entry.id);
        try rows.writer.writeAll("</details></td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "audit-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "audit-count", "span", entries.len, "entry", "entries");
}
fn writeAuditOwnerLink(out: *std.Io.Writer, entry: app_writes.AuditEntry) !void {
    const action = entry.action;
    const target = entry.target;
    const category = entry.category;
    if (std.mem.eql(u8, category, "dashboard"))
        return html.link(out, "/", "", "", action);
    if (std.mem.eql(u8, category, "projects"))
        return html.link(out, "/projects.html", "query", target, action);
    if (std.mem.eql(u8, category, "routes")) {
        if (std.mem.startsWith(u8, action, "caddy.route."))
            return html.link(out, "/routes.html", "host", target, action);
        return html.link(out, "/routes.html", "", "", action);
    }
    if (std.mem.eql(u8, category, "dns"))
        return html.link(out, "/dns.html", "", "", action);
    if (std.mem.eql(u8, category, "browser"))
        return html.link(out, "/browser.html", "", "", action);
    if (std.mem.eql(u8, category, "vps"))
        return html.link(out, "/vps.html", "", "", action);
    if (std.mem.eql(u8, category, "docker"))
        return html.link(out, "/docker.html", "container", target, action);
    if (std.mem.eql(u8, category, "security"))
        return html.link(out, "/security.html", "", "", action);
    if (std.mem.eql(u8, category, "settings"))
        return html.link(out, "/settings.html", "", "", action);
    try web_html.text(out, action);
}
fn auditCategoryLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "dashboard")) return "Dashboard";
    if (std.mem.eql(u8, value, "projects")) return "Projects";
    if (std.mem.eql(u8, value, "routes")) return "Routes";
    if (std.mem.eql(u8, value, "dns")) return "DNS";
    if (std.mem.eql(u8, value, "browser")) return "Browser";
    if (std.mem.eql(u8, value, "vps")) return "VPS";
    if (std.mem.eql(u8, value, "docker")) return "Docker";
    if (std.mem.eql(u8, value, "security")) return "Security";
    if (std.mem.eql(u8, value, "settings")) return "Settings";
    return "Other";
}
