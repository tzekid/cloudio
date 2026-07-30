const std = @import("std");
const app_deploy = @import("app_deploy");
const core_json = @import("core_json");
const http = @import("http");
const runtime_events = @import("runtime_events");
const context = @import("../context.zig");

pub fn ping(ctx: context.Context, _: http.Request, _: http.Params, out: *std.Io.Writer) !void {
    const stream = try http.SseStream.beginWithHeaders(out, ctx.response_headers);
    try stream.writeEvent(null, "{\"ok\":true}");
}

pub fn changes(ctx: context.Context, _: http.Request, _: http.Params, out: *std.Io.Writer) !void {
    const stream = try http.SseStream.beginWithHeaders(out, ctx.response_headers);
    var last = runtime_events.current();
    var payload: [64]u8 = undefined;
    try stream.writeEvent("epoch", std.fmt.bufPrint(&payload, "{{\"epoch\":{d}}}", .{last}) catch unreachable);
    var iterations: usize = 0;
    while (iterations < 150) : (iterations += 1) {
        ctx.io.sleep(.fromNanoseconds(2 * std.time.ns_per_s), .awake) catch return;
        const current = runtime_events.current();
        if (current == last) continue;
        last = current;
        try stream.writeEvent("refresh", std.fmt.bufPrint(&payload, "{{\"epoch\":{d}}}", .{current}) catch unreachable);
    }
}

pub fn deploy(ctx: context.Context, _: http.Request, params: http.Params, out: *std.Io.Writer) !void {
    const stream = try http.SseStream.beginWithHeaders(out, ctx.response_headers);
    const name = params.get("name") orelse {
        try stream.writeEvent("error", "{\"error\":\"bad_app_name\"}");
        return;
    };
    if (!app_deploy.isValidAppName(name)) {
        try stream.writeEvent("error", "{\"error\":\"bad_app_name\"}");
        return;
    }
    var offset: usize = 0;
    var iterations: usize = 0;
    while (iterations < 1200) : (iterations += 1) {
        const status = app_deploy.latestDeployStatus(context.deploy(ctx), name) catch null;
        const chunk = app_deploy.readDeployLogTailFrom(context.deploy(ctx), name, &offset) catch null;
        if (chunk) |body| {
            defer ctx.gpa.free(body);
            if (body.len > 0) {
                var lines = std.mem.splitScalar(u8, body, '\n');
                while (lines.next()) |line| {
                    if (line.len == 0) continue;
                    var encoded = std.Io.Writer.Allocating.init(ctx.gpa);
                    defer encoded.deinit();
                    try core_json.writeString(&encoded.writer, line);
                    try stream.writeEvent("log", encoded.written());
                }
            }
        }
        const status_text = status orelse "unknown";
        if (!std.mem.eql(u8, status_text, "running")) {
            var payload = std.Io.Writer.Allocating.init(ctx.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"status\":");
            try core_json.writeString(&payload.writer, status_text);
            try payload.writer.writeByte('}');
            try stream.writeEvent("done", payload.written());
            return;
        }
        ctx.io.sleep(.fromNanoseconds(500 * std.time.ns_per_ms), .awake) catch return;
    }
}
