const std = @import("std");
const app_deploy = @import("app_deploy");
const app_system_control = @import("app_system_control");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn list(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_deploy.writeAppsJson(context.deploy(ctx), writer);
    return 200;
}

pub fn register(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const name = common.strField(parsed.value, "name") orelse return common.badRequest(writer);
    try app_deploy.registerApp(context.deploy(ctx), name, common.strField(parsed.value, "repo_url"), common.strField(parsed.value, "workdir"), writer);
    return 200;
}

pub fn details(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const name = params.get("name") orelse return common.badRequest(writer);
    const operation = params.get("action") orelse return common.badRequest(writer);
    if (std.mem.eql(u8, operation, "deploys")) {
        try app_deploy.writeDeploysJson(context.deploy(ctx), name, common.intQuery(request, "limit", 50), writer);
        return 200;
    }
    if (std.mem.eql(u8, operation, "log")) {
        if (request.query("deploy_id")) |raw| {
            const deploy_id = std.fmt.parseInt(i64, raw, 10) catch return common.badRequest(writer);
            try app_deploy.readDeployLog(context.deploy(ctx), name, deploy_id, writer);
        } else {
            try app_deploy.readLatestDeployLog(context.deploy(ctx), name, writer);
        }
        return 200;
    }
    return error.UnknownRoute;
}

pub fn action(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const name = params.get("name") orelse return common.badRequest(writer);
    const operation = params.get("action") orelse return common.badRequest(writer);
    if (std.mem.eql(u8, operation, "deploy")) {
        try app_deploy.deploy(context.deploy(ctx), name, .{}, writer);
        return 200;
    }
    if (std.mem.eql(u8, operation, "rollback")) {
        var deploy_id: ?i64 = null;
        if (common.jsonBody(ctx.gpa, request.body)) |parsed_const| {
            var parsed = parsed_const;
            defer parsed.deinit();
            deploy_id = core_json.fieldInt(parsed.value, "deploy_id");
        }
        try app_deploy.rollback(context.deploy(ctx), name, deploy_id, .{}, writer);
        return 200;
    }
    if (std.mem.eql(u8, operation, "service")) {
        var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
        defer parsed.deinit();
        const action_text = common.strField(parsed.value, "action") orelse return common.badRequest(writer);
        const service_action = std.meta.stringToEnum(app_system_control.ServiceAction, action_text) orelse return common.badRequest(writer);
        const unit = app_system_control.unitName(ctx.gpa, name) catch return common.badRequest(writer);
        defer ctx.gpa.free(unit);
        try app_system_control.serviceAction(context.system(ctx), unit, service_action, writer);
        return 200;
    }
    return error.UnknownRoute;
}

pub fn delete(ctx: context.Context, _: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const name = params.get("name") orelse return common.badRequest(writer);
    try app_deploy.deleteApp(context.deploy(ctx), name, .{}, writer);
    return 200;
}
