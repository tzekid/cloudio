const app_authentication = @import("../../app/authentication.zig");
const context = @import("../context.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var all = try ctx.db.auth().listCredentials(ctx.gpa);
    defer all.deinit(ctx.gpa);
    var active: usize = 0;

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    for (all.items) |credential| {
        if (credential.revoked_at != null) continue;
        active += 1;
        try rows.writer.writeAll("<tr><td><strong>");
        try web_html.text(&rows.writer, credential.label);
        try rows.writer.writeAll("</strong></td>");
        try html.cellBadge(&rows.writer, if (credential.backup_eligible) "Synced" else "Security key");
        try rows.writer.print("<td class=\"mono\">{d}</td>", .{credential.created_at});
        if (credential.last_used_at) |last_used| {
            try rows.writer.print("<td class=\"mono\">{d}</td>", .{last_used});
        } else try html.cellText(&rows.writer, "Never", "muted");
        const credential_id = credential.credential_id;
        const credential_label = credential.label;
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\"><button type=\"button\" class=\"button button-small\" data-action=\"rename\" data-id=\"");
        try web_html.attribute(&rows.writer, credential_id);
        try rows.writer.writeAll("\">Rename</button><button type=\"button\" class=\"button button-small button-danger\" data-action=\"revoke\" data-id=\"");
        try web_html.attribute(&rows.writer, credential_id);
        try rows.writer.writeAll("\" data-label=\"");
        try web_html.attribute(&rows.writer, credential_label);
        try rows.writer.writeAll("\">Revoke</button></div></td></tr>");
    }
    if (active == 0) try html.emptyRow(&rows.writer, 5, "No passkeys are enrolled.");
    try html.replaceElementInner(ctx.gpa, main, "passkeys-body", "tbody", rows.written());
    var count_buffer: [32]u8 = undefined;
    const count = try std.fmt.bufPrint(&count_buffer, "{d}", .{active});
    try html.replaceElementInner(ctx.gpa, main, "passkey-count", "div", count);

    var csrf_input = std.Io.Writer.Allocating.init(ctx.gpa);
    defer csrf_input.deinit();
    try csrf_input.writer.writeAll(
        "<input id=\"security-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"",
    );
    try web_html.attribute(&csrf_input.writer, ctx.auth_csrf_token orelse "");
    try csrf_input.writer.writeAll("\">");
    try html.replaceExact(
        ctx.gpa,
        main,
        "<input id=\"security-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"\">",
        csrf_input.written(),
    );

    const result = request.query("result") orelse "";
    const notice: ?struct { tone: []const u8, text: []const u8 } =
        if (std.mem.eql(u8, result, "added"))
            .{ .tone = "success", .text = "Passkey added." }
        else if (std.mem.eql(u8, result, "renamed"))
            .{ .tone = "success", .text = "Passkey renamed." }
        else if (std.mem.eql(u8, result, "revoked"))
            .{ .tone = "success", .text = "Passkey revoked." }
        else if (active < 2)
            .{ .tone = "warning", .text = "Add a second passkey before you need it. A phone plus a laptop or hardware key is a practical recovery pair." }
        else
            null;
    if (notice) |item| {
        var notice_html = std.Io.Writer.Allocating.init(ctx.gpa);
        defer notice_html.deinit();
        try notice_html.writer.print(
            "<div id=\"security-notice\" class=\"notice tone-{s}\" role=\"status\" aria-live=\"polite\">",
            .{item.tone},
        );
        try web_html.text(&notice_html.writer, item.text);
        try notice_html.writer.writeAll("</div>");
        try html.replaceExact(
            ctx.gpa,
            main,
            "<div id=\"security-notice\" class=\"notice hidden\" aria-live=\"polite\"></div>",
            notice_html.written(),
        );
    }
}
