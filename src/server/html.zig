//! Template splicing and table cell helpers shared by every page renderer.

const std = @import("std");
const url = @import("../core/url.zig");
const web_html = @import("web_html");

pub fn extractMain(gpa: std.mem.Allocator, template: []const u8) ![]u8 {
    const main_start = std.mem.indexOf(u8, template, "<main") orelse
        return error.InvalidPageTemplate;
    const main_end_start = std.mem.indexOfPos(u8, template, main_start, "</main>") orelse
        return error.InvalidPageTemplate;
    return gpa.dupe(u8, template[main_start .. main_end_start + "</main>".len]);
}
pub fn formIdempotencyKey(
    io: std.Io,
    buffer: *[80]u8,
    prefix: []const u8,
) ![]const u8 {
    var random: [24]u8 = undefined;
    try io.randomSecure(&random);
    var encoded: [std.base64.url_safe_no_pad.Encoder.calcSize(random.len)]u8 = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&encoded, &random);
    @memset(&random, 0);
    return std.fmt.bufPrint(buffer, "{s}-{s}", .{ prefix, encoded[0..] });
}
pub fn writeHiddenInput(out: *std.Io.Writer, name: []const u8, value: []const u8) !void {
    try out.writeAll("<input name=\"");
    try web_html.attribute(out, name);
    try out.writeAll("\" type=\"hidden\" value=\"");
    try web_html.attribute(out, value);
    try out.writeAll("\">");
}
pub fn replaceHiddenInput(
    gpa: std.mem.Allocator,
    main: *[]u8,
    id: []const u8,
    name: []const u8,
    value: []const u8,
) !void {
    const needle = try std.fmt.allocPrint(gpa, "<input id=\"{s}\" name=\"{s}\" type=\"hidden\" value=\"\">", .{ id, name });
    defer gpa.free(needle);
    var replacement = std.Io.Writer.Allocating.init(gpa);
    defer replacement.deinit();
    try replacement.writer.writeAll("<input id=\"");
    try web_html.attribute(&replacement.writer, id);
    try replacement.writer.writeAll("\" name=\"");
    try web_html.attribute(&replacement.writer, name);
    try replacement.writer.writeAll("\" type=\"hidden\" value=\"");
    try web_html.attribute(&replacement.writer, value);
    try replacement.writer.writeAll("\">");
    try replaceExact(gpa, main, needle, replacement.written());
}
pub fn replaceEscapedElement(
    gpa: std.mem.Allocator,
    main: *[]u8,
    id: []const u8,
    tag: []const u8,
    text: []const u8,
) !void {
    var escaped = std.Io.Writer.Allocating.init(gpa);
    defer escaped.deinit();
    try web_html.text(&escaped.writer, text);
    try replaceElementInner(gpa, main, id, tag, escaped.written());
}
pub fn member(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}
pub fn arrayItems(value: ?std.json.Value) []const std.json.Value {
    const present = value orelse return &.{};
    if (present != .array) return &.{};
    return present.array.items;
}
pub fn asString(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}
pub fn nullableString(value: ?std.json.Value) []const u8 {
    const present = value orelse return "";
    return asString(present);
}
pub fn strField(value: std.json.Value, name: []const u8) []const u8 {
    return asString(member(value, name) orelse .null);
}
pub fn firstString(value: std.json.Value, names: []const []const u8) []const u8 {
    for (names) |name| {
        const text = strField(value, name);
        if (text.len > 0) return text;
    }
    return "—";
}
pub fn asInt(value: std.json.Value) i64 {
    return switch (value) {
        .integer => |integer| integer,
        .float => |float| @intFromFloat(float),
        else => 0,
    };
}
pub fn intField(value: std.json.Value, name: []const u8) i64 {
    return asInt(member(value, name) orelse .null);
}
pub fn boolField(value: std.json.Value, name: []const u8) bool {
    const present = member(value, name) orelse return false;
    return present == .bool and present.bool;
}
pub fn freshnessLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "current")) return "Current";
    if (std.mem.eql(u8, value, "stale")) return "Stale";
    return "Unavailable";
}
pub fn collectionStatusLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "ok")) return "Succeeded";
    if (std.mem.eql(u8, value, "error")) return "Failed";
    if (std.mem.eql(u8, value, "skipped")) return "Unavailable";
    return "Not run";
}
pub fn dashboardCellText(
    out: *std.Io.Writer,
    label: []const u8,
    value: []const u8,
    class: []const u8,
    empty: []const u8,
) !void {
    try out.writeAll("<td data-label=\"");
    try web_html.attribute(out, label);
    try out.writeByte('"');
    if (class.len > 0) {
        try out.writeAll(" class=\"");
        try web_html.attribute(out, class);
        try out.writeByte('"');
    }
    try out.writeByte('>');
    try web_html.text(out, if (value.len > 0) value else empty);
    try out.writeAll("</td>");
}
pub fn cellText(out: *std.Io.Writer, value: []const u8, class: []const u8) !void {
    try out.writeAll("<td");
    if (class.len > 0) {
        try out.writeAll(" class=\"");
        try web_html.attribute(out, class);
        try out.writeByte('"');
    }
    try out.writeByte('>');
    try web_html.text(out, if (value.len > 0) value else "—");
    try out.writeAll("</td>");
}
pub fn cellValue(out: *std.Io.Writer, value: ?std.json.Value, class: []const u8) !void {
    try out.writeAll("<td");
    if (class.len > 0) try out.print(" class=\"{s}\"", .{class});
    try out.writeByte('>');
    if (value) |present| switch (present) {
        .string => |text| try web_html.text(out, text),
        .integer => |integer| try out.print("{d}", .{integer}),
        .float => |float| try out.print("{d}", .{float}),
        .bool => |boolean| try out.writeAll(if (boolean) "yes" else "no"),
        else => try out.writeAll("—"),
    } else try out.writeAll("—");
    try out.writeAll("</td>");
}
pub fn cellStatus(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<td>");
    try writeStatus(out, value);
    try out.writeAll("</td>");
}
pub fn writeStatus(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<span class=\"status");
    if (tone(value)) |class| try out.print(" tone-{s}", .{class});
    try out.writeAll("\">");
    try web_html.text(out, if (value.len > 0) value else "unknown");
    try out.writeAll("</span>");
}
pub fn cellBadge(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<td>");
    try writeBadge(out, value);
    try out.writeAll("</td>");
}
pub fn writeBadge(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<span class=\"badge");
    if (tone(value)) |class| try out.print(" tone-{s}", .{class});
    try out.writeAll("\">");
    try web_html.text(out, if (value.len > 0) value else "unknown");
    try out.writeAll("</span>");
}
pub fn tone(value: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(value, "healthy") or
        std.ascii.eqlIgnoreCase(value, "running") or
        std.ascii.eqlIgnoreCase(value, "active") or
        std.ascii.eqlIgnoreCase(value, "current") or
        std.ascii.eqlIgnoreCase(value, "ok") or
        std.ascii.eqlIgnoreCase(value, "available") or
        std.ascii.eqlIgnoreCase(value, "succeeded") or
        std.ascii.eqlIgnoreCase(value, "enabled"))
        return "success";
    if (std.ascii.eqlIgnoreCase(value, "degraded") or
        std.ascii.eqlIgnoreCase(value, "failed") or
        std.ascii.eqlIgnoreCase(value, "failure") or
        std.ascii.eqlIgnoreCase(value, "error") or
        std.ascii.eqlIgnoreCase(value, "permission") or
        std.ascii.eqlIgnoreCase(value, "denied") or
        std.ascii.eqlIgnoreCase(value, "rejected") or
        std.ascii.eqlIgnoreCase(value, "disabled"))
        return "danger";
    if (std.ascii.eqlIgnoreCase(value, "stopped") or
        std.ascii.eqlIgnoreCase(value, "stale") or
        std.ascii.eqlIgnoreCase(value, "skipped") or
        std.ascii.eqlIgnoreCase(value, "pending") or
        std.ascii.eqlIgnoreCase(value, "dns_only") or
        std.ascii.eqlIgnoreCase(value, "local_only"))
        return "warning";
    if (std.ascii.eqlIgnoreCase(value, "app") or
        std.ascii.eqlIgnoreCase(value, "proxied") or
        std.ascii.eqlIgnoreCase(value, "needs manifest") or
        std.ascii.eqlIgnoreCase(value, "synced"))
        return "info";
    if (std.ascii.eqlIgnoreCase(value, "unavailable")) return "danger";
    return null;
}
pub fn definition(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    try out.writeAll("<div class=\"kv-row\"><dt>");
    try web_html.text(out, label);
    try out.writeAll("</dt><dd class=\"mono\">");
    try web_html.text(out, if (value.len > 0) value else "—");
    try out.writeAll("</dd></div>");
}
pub fn detail(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try out.writeAll("<div class=\"detail-block\"><div class=\"detail-label\">");
    try web_html.text(out, label);
    try out.writeAll("</div><pre class=\"code-block\">");
    try web_html.text(out, value);
    try out.writeAll("</pre></div>");
}
pub fn emptyRow(out: *std.Io.Writer, columns: usize, message: []const u8) !void {
    try out.print("<tr><td class=\"empty-state\" colspan=\"{d}\">", .{columns});
    try web_html.text(out, message);
    try out.writeAll("</td></tr>");
}
pub fn replaceCountLabel(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    tag: []const u8,
    count: usize,
    singular: []const u8,
    plural: []const u8,
) !void {
    var buffer: [96]u8 = undefined;
    const label = try std.fmt.bufPrint(
        &buffer,
        "{d} {s}",
        .{ count, if (count == 1) singular else plural },
    );
    try replaceElementInner(gpa, source, id, tag, label);
}
pub fn replaceElementInner(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    tag: []const u8,
    replacement: []const u8,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const open_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const close_marker = try std.fmt.allocPrint(gpa, "</{s}>", .{tag});
    defer gpa.free(close_marker);
    const close_start = std.mem.indexOfPos(u8, source.*, open_end + 1, close_marker) orelse
        return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0 .. open_end + 1],
        replacement,
        source.*[close_start..],
    });
    gpa.free(source.*);
    source.* = next;
}
pub fn replaceExact(
    gpa: std.mem.Allocator,
    source: *[]u8,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const start = std.mem.indexOf(u8, source.*, needle) orelse return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0..start],
        replacement,
        source.*[start + needle.len ..],
    });
    gpa.free(source.*);
    source.* = next;
}
pub fn selectOption(
    gpa: std.mem.Allocator,
    source: *[]u8,
    select_id: []const u8,
    default_value: []const u8,
    selected_value: []const u8,
) !void {
    if (std.mem.eql(u8, default_value, selected_value)) return;
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{select_id});
    defer gpa.free(id_marker);
    const select_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const default_selected = try std.fmt.allocPrint(gpa, "<option value=\"{s}\" selected>", .{default_value});
    defer gpa.free(default_selected);
    const default_plain = try std.fmt.allocPrint(gpa, "<option value=\"{s}\">", .{default_value});
    defer gpa.free(default_plain);
    try replaceExactAfter(gpa, source, select_start, default_selected, default_plain);

    const selected_plain = try std.fmt.allocPrint(gpa, "<option value=\"{s}\">", .{selected_value});
    defer gpa.free(selected_plain);
    const selected_selected = try std.fmt.allocPrint(gpa, "<option value=\"{s}\" selected>", .{selected_value});
    defer gpa.free(selected_selected);
    try replaceExactAfter(gpa, source, select_start, selected_plain, selected_selected);
}
pub fn selectTextOption(
    gpa: std.mem.Allocator,
    source: *[]u8,
    select_id: []const u8,
    default_value: []const u8,
    selected_value: []const u8,
) !void {
    if (std.mem.eql(u8, default_value, selected_value)) return;
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{select_id});
    defer gpa.free(id_marker);
    const select_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const default_selected = try std.fmt.allocPrint(gpa, "<option selected>{s}</option>", .{default_value});
    defer gpa.free(default_selected);
    const default_plain = try std.fmt.allocPrint(gpa, "<option>{s}</option>", .{default_value});
    defer gpa.free(default_plain);
    try replaceExactAfter(gpa, source, select_start, default_selected, default_plain);

    const selected_plain = try std.fmt.allocPrint(gpa, "<option>{s}</option>", .{selected_value});
    defer gpa.free(selected_plain);
    const selected_selected = try std.fmt.allocPrint(gpa, "<option selected>{s}</option>", .{selected_value});
    defer gpa.free(selected_selected);
    try replaceExactAfter(gpa, source, select_start, selected_plain, selected_selected);
}
pub fn replaceExactAfter(
    gpa: std.mem.Allocator,
    source: *[]u8,
    start: usize,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const match_start = std.mem.indexOfPos(u8, source.*, start, needle) orelse return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0..match_start],
        replacement,
        source.*[match_start + needle.len ..],
    });
    gpa.free(source.*);
    source.* = next;
}
pub fn setInputValue(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    value: []const u8,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const input_start = std.mem.lastIndexOf(u8, source.*[0..id_start], "<input") orelse return error.InvalidPageTemplate;
    const input_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const opening = source.*[input_start..input_end];
    const marker = " value=\"";
    var escaped = std.Io.Writer.Allocating.init(gpa);
    defer escaped.deinit();
    try web_html.attribute(&escaped.writer, value);
    if (std.mem.indexOf(u8, opening, marker)) |relative| {
        const value_start = input_start + relative + marker.len;
        const value_end = std.mem.indexOfScalarPos(u8, source.*, value_start, '"') orelse return error.InvalidPageTemplate;
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..value_start], escaped.written(), source.*[value_end..] });
        gpa.free(source.*);
        source.* = next;
        return;
    }
    var attribute = std.Io.Writer.Allocating.init(gpa);
    defer attribute.deinit();
    try attribute.writer.writeAll(" value=\"");
    try attribute.writer.writeAll(escaped.written());
    try attribute.writer.writeByte('"');
    const next = try std.mem.concat(gpa, u8, &.{ source.*[0..input_end], attribute.written(), source.*[input_end..] });
    gpa.free(source.*);
    source.* = next;
}
pub fn setInputChecked(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    checked: bool,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const input_start = std.mem.lastIndexOf(u8, source.*[0..id_start], "<input") orelse return error.InvalidPageTemplate;
    const input_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const checked_marker = " checked";
    const present = std.mem.indexOf(u8, source.*[input_start..input_end], checked_marker);
    if (checked and present == null) {
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..input_end], checked_marker, source.*[input_end..] });
        gpa.free(source.*);
        source.* = next;
    } else if (!checked and present != null) {
        const start = input_start + present.?;
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..start], source.*[start + checked_marker.len ..] });
        gpa.free(source.*);
        source.* = next;
    }
}
pub fn replaceTextInputValue(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    name: []const u8,
    value: []const u8,
) !void {
    if (value.len == 0) return;
    const needle = try std.fmt.allocPrint(gpa, "<input id=\"{s}\" name=\"{s}\" type=\"text\" autocomplete=\"off\">", .{ id, name });
    defer gpa.free(needle);
    var replacement = std.Io.Writer.Allocating.init(gpa);
    defer replacement.deinit();
    try replacement.writer.writeAll("<input id=\"");
    try web_html.attribute(&replacement.writer, id);
    try replacement.writer.writeAll("\" name=\"");
    try web_html.attribute(&replacement.writer, name);
    try replacement.writer.writeAll("\" type=\"text\" autocomplete=\"off\" value=\"");
    try web_html.attribute(&replacement.writer, value);
    try replacement.writer.writeAll("\">");
    try replaceExact(gpa, source, needle, replacement.written());
}

pub fn link(
    out: *std.Io.Writer,
    path: []const u8,
    query_name: []const u8,
    query_value: []const u8,
    label: []const u8,
) !void {
    try out.writeAll("<a href=\"");
    try web_html.urlAttribute(out, path);
    if (query_value.len > 0) {
        try out.writeByte('?');
        try web_html.urlAttribute(out, query_name);
        try out.writeByte('=');
        try url.writeComponent(out, query_value);
    }
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</a>");
}
