const std = @import("std");
const app_refresh_cycle = @import("app_refresh_cycle");
const http = @import("http");
const runtime_events = @import("runtime_events");
const context = @import("../context.zig");

pub fn now(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_refresh_cycle.run(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config });
    _ = runtime_events.publishRefresh();
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}
