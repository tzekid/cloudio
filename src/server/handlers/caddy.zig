const std = @import("std");
const app_caddy_desired = @import("app_caddy_desired");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn routesGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_caddy_desired.writeJson(context.caddy(ctx), writer);
    return 200;
}

pub fn routesPost(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const host = common.strField(parsed.value, "host") orelse return common.badRequest(writer);
    const action = common.strField(parsed.value, "action") orelse "create";
    try app_caddy_desired.mutate(
        context.caddy(ctx),
        if (std.mem.eql(u8, action, "update")) .update else if (std.mem.eql(u8, action, "create")) .create else return common.badRequest(writer),
        .{ .host = host, .upstream = common.strField(parsed.value, "upstream") },
    );
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn routesDelete(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const host = request.query("host") orelse return common.badRequest(writer);
    try app_caddy_desired.mutate(context.caddy(ctx), .delete, .{ .host = host });
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn routesToggle(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const host = common.strField(parsed.value, "host") orelse return common.badRequest(writer);
    const enabled = common.boolField(parsed.value, "enabled") orelse return common.badRequest(writer);
    try app_caddy_desired.mutate(context.caddy(ctx), .toggle, .{ .host = host, .enabled = enabled });
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn preview(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_caddy_desired.writePreviewJson(context.caddy(ctx), writer);
    return 200;
}

pub fn apply(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const result = try app_caddy_desired.apply(context.caddy(ctx), .{});
    defer result.deinit(ctx.gpa);
    try writer.writeAll("{\"ok\":true,");
    try core_json.writeBoolField(writer, "validated", result.validated, true);
    try core_json.writeBoolField(writer, "reloaded", result.reloaded, true);
    try core_json.writeBoolField(writer, "verified", result.verified, true);
    try core_json.writeIntField(writer, "bytes", result.bytes, true);
    try core_json.writeNullableStringField(writer, "backup_path", result.backup_path, false);
    try writer.writeAll("}\n");
    return 200;
}

pub fn refresh(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_caddy_desired.refresh(context.caddy(ctx));
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn adopt(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const host = common.strField(parsed.value, "host") orelse return common.badRequest(writer);
    try app_caddy_desired.mutate(context.caddy(ctx), .adopt, .{ .host = host });
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}
