const context = @import("../context.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const web_html = @import("web_html");

pub fn inject(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    main: *[]u8,
) !void {
    var csrf_input = std.Io.Writer.Allocating.init(ctx.gpa);
    defer csrf_input.deinit();
    try csrf_input.writer.writeAll(
        "<input id=\"settings-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"",
    );
    try web_html.attribute(&csrf_input.writer, ctx.auth_csrf_token orelse "");
    try csrf_input.writer.writeAll("\">");
    try html.replaceExact(
        ctx.gpa,
        main,
        "<input id=\"settings-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"\">",
        csrf_input.written(),
    );

    var selected = std.Io.Writer.Allocating.init(ctx.gpa);
    defer selected.deinit();
    try selected.writer.print(
        "<input id=\"theme-{s}\" name=\"theme\" type=\"radio\" value=\"{s}\" checked>",
        .{ preference.value(), preference.value() },
    );
    var unchecked: [96]u8 = undefined;
    const unchecked_input = try std.fmt.bufPrint(
        &unchecked,
        "<input id=\"theme-{s}\" name=\"theme\" type=\"radio\" value=\"{s}\">",
        .{ preference.value(), preference.value() },
    );
    try html.replaceExact(ctx.gpa, main, unchecked_input, selected.written());

    const notice: ?struct { tone: []const u8, text: []const u8 } = if (std.mem.eql(
        u8,
        request.query("saved") orelse "",
        "1",
    ))
        .{ .tone = "success", .text = "Appearance saved for this browser." }
    else if (request.query("error")) |code|
        if (std.mem.eql(u8, code, "request"))
            .{ .tone = "danger", .text = "The appearance request was invalid. Please try again." }
        else if (std.mem.eql(u8, code, "security"))
            .{ .tone = "danger", .text = "The security check failed. Reload the page and try again." }
        else
            .{ .tone = "danger", .text = "Choose Light, Dark, or Device." }
    else
        null;
    if (notice) |item| {
        var status = std.Io.Writer.Allocating.init(ctx.gpa);
        defer status.deinit();
        try status.writer.print(
            "<div id=\"settings-status\" class=\"notice tone-{s}\" role=\"{s}\" aria-live=\"polite\">",
            .{ item.tone, if (std.mem.eql(u8, item.tone, "danger")) "alert" else "status" },
        );
        try web_html.text(&status.writer, item.text);
        try status.writer.writeAll("</div>");
        try html.replaceExact(
            ctx.gpa,
            main,
            "<div id=\"settings-status\" class=\"notice hidden\" aria-live=\"polite\"></div>",
            status.written(),
        );
    }
}
