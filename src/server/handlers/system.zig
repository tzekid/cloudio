const std = @import("std");
const app_system_control = @import("app_system_control");
const app_web_resources = @import("app_web_resources");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn containersGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_web_resources.writeContainersJson(.{ .gpa = ctx.gpa, .db = ctx.db }, writer);
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
    try app_system_control.containerLogs(context.system(ctx), name, common.intQuery(request, "tail", 100), writer);
    return 200;
}
