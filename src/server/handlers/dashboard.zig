const std = @import("std");
const app_actions = @import("app_actions");
const app_dashboard = @import("app_dashboard");
const app_inventory = @import("app_inventory");
const app_topology = @import("app_topology");
const app_writes = @import("app_writes");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn dashboard(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_dashboard.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, common.dashboardOptions(request, ctx.dashboard), writer);
    return 200;
}

pub fn topology(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const options = common.dashboardOptions(request, ctx.dashboard);
    try app_topology.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .limit = options.limit }, writer);
    return 200;
}

pub fn topologyChanges(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_topology.writeChangesJson(.{ .gpa = ctx.gpa, .db = ctx.db }, common.intQuery(request, "limit", 100), writer);
    return 200;
}

pub fn inventory(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const options = common.dashboardOptions(request, ctx.dashboard);
    try app_inventory.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = options.domain, .limit = options.limit }, writer);
    return 200;
}

pub fn actionsPlan(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const options = common.dashboardOptions(request, ctx.dashboard);
    try app_actions.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = options.domain, .limit = options.limit }, writer);
    return 200;
}

pub fn audit(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_writes.writeAuditJson(ctx.gpa, ctx.db, common.intQuery(request, "limit", 200), writer);
    return 200;
}
