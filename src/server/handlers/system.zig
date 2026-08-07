const std = @import("std");
const app_system_control = @import("app_system_control");
const app_web_resources = @import("app_web_resources");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn containersGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try writeContainers(ctx, writer);
    return 200;
}

pub fn containersRefresh(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_system_control.refreshContainers(context.system(ctx));
    try writeContainers(ctx, writer);
    return 200;
}

pub fn containersAction(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const name = common.strField(parsed.value, "name") orelse return common.badRequest(writer);
    const action_text = common.strField(parsed.value, "action") orelse return common.badRequest(writer);
    const action = std.meta.stringToEnum(app_system_control.ContainerAction, action_text) orelse return common.badRequest(writer);
    try app_system_control.containerAction(context.system(ctx), name, action, writer);
    return 200;
}

pub fn containersLogs(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const name = request.query("name") orelse return common.badRequest(writer);
    const tail = if (request.query("tail")) |raw|
        std.fmt.parseInt(i64, raw, 10) catch return common.badRequest(writer)
    else
        100;
    try app_system_control.containerLogs(context.system(ctx), name, tail, writer);
    return 200;
}

fn writeContainers(ctx: context.Context, writer: *std.Io.Writer) !void {
    const refresh_seconds: i64 = @intCast(ctx.config.refresh_seconds);
    try app_web_resources.writeContainersJson(.{
        .gpa = ctx.gpa,
        .db = ctx.db,
        .fresh_after_seconds = @max(refresh_seconds * 2, 60),
    }, writer);
}
