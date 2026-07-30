const std = @import("std");
const app_caddy_desired = @import("app_caddy_desired");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn routesGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_caddy_desired.writeRoutesJson(context.caddy(ctx), writer);
    return 200;
}

pub fn routesPost(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const host = common.strField(parsed.value, "host") orelse return common.badRequest(writer);
    try app_caddy_desired.upsertRoute(context.caddy(ctx), host, common.strField(parsed.value, "upstream"), "manual", common.strField(parsed.value, "extra_directives"), null, null);
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn routesDelete(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const host = request.query("host") orelse return common.badRequest(writer);
    try app_caddy_desired.deleteRoute(context.caddy(ctx), host);
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn routesToggle(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const host = common.strField(parsed.value, "host") orelse return common.badRequest(writer);
    const enabled = common.boolField(parsed.value, "enabled") orelse return common.badRequest(writer);
    try app_caddy_desired.setEnabled(context.caddy(ctx), host, enabled);
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn preview(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_caddy_desired.writePreviewJson(context.caddy(ctx), writer);
    return 200;
}

pub fn apply(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const result = app_caddy_desired.apply(context.caddy(ctx), ctx.config.caddyfile_path, .{}) catch |err| switch (err) {
        error.ValidateFailed => {
            try writer.writeAll("{\"ok\":false,\"error\":\"validate_failed\"}\n");
            return 422;
        },
        else => return err,
    };
    defer result.deinit(ctx.gpa);
    try writer.writeAll("{\"ok\":true,");
    try core_json.writeBoolField(writer, "validated", result.validated, true);
    try core_json.writeBoolField(writer, "reloaded", result.reloaded, true);
    try core_json.writeIntField(writer, "bytes", result.bytes, true);
    try core_json.writeNullableStringField(writer, "backup_path", result.backup_path, false);
    try writer.writeAll("}\n");
    return 200;
}

pub fn importRoutes(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const summary = try app_caddy_desired.importCaddyfile(context.caddy(ctx), ctx.config.caddyfile_path);
    try writer.writeAll("{\"ok\":true,");
    try core_json.writeIntField(writer, "imported_manual", summary.imported_manual, true);
    try core_json.writeIntField(writer, "imported_raw", summary.imported_raw, true);
    try core_json.writeIntField(writer, "skipped_app", summary.skipped_app, false);
    try writer.writeAll("}\n");
    return 200;
}
