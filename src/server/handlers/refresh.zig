const std = @import("std");
const app_refresh_cycle = @import("app_refresh_cycle");
const http = @import("http");
const context = @import("../context.zig");

pub fn now(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const result = try app_refresh_cycle.run(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config });
    try result.writeJson(ctx.gpa, ctx.db, writer);
    return result.statusCode();
}
