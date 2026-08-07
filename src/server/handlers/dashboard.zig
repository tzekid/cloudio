const std = @import("std");
const app_dashboard = @import("app_dashboard");
const app_inventory = @import("app_inventory");
const app_writes = @import("app_writes");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn dashboard(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const refresh_seconds: i64 = @intCast(ctx.config.refresh_seconds);
    try app_dashboard.writeJson(.{
        .gpa = ctx.gpa,
        .db = ctx.db,
        .fresh_after_seconds = @max(refresh_seconds * 2, 60),
    }, common.dashboardOptions(request, ctx.dashboard), writer);
    return 200;
}

pub fn inventory(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const options = common.dashboardOptions(request, ctx.dashboard);
    try app_inventory.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = options.domain, .limit = options.limit }, writer);
    return 200;
}

pub fn audit(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_writes.writeAuditJson(ctx.gpa, ctx.db, common.auditOptions(request), writer);
    return 200;
}
