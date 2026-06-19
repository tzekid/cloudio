const std = @import("std");
const app_actions = @import("app_actions");
const app_dashboard = @import("app_dashboard");
const app_inventory = @import("app_inventory");
const app_topology = @import("app_topology");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const default_host = "127.0.0.1";
pub const default_port: u16 = 9328;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub const Options = struct {
    host: []const u8 = default_host,
    port: u16 = default_port,
    once: bool = false,
    dashboard: app_dashboard.Options = .{},
};

pub fn run(ctx: Context, options: Options) !void {
    var address = try std.Io.net.IpAddress.parse(options.host, options.port);
    var server = try address.listen(ctx.io, .{ .reuse_address = true });
    defer server.deinit(ctx.io);
    std.debug.print("cloudio serve http://{s}:{d}\n", .{ options.host, options.port });
    while (true) {
        const stream = try server.accept(ctx.io);
        handleConnection(ctx, stream, options.dashboard) catch |err| {
            std.debug.print("cloudio serve request failed: {s}\n", .{@errorName(err)});
        };
        if (options.once) break;
    }
}

fn handleConnection(ctx: Context, stream: std.Io.net.Stream, dashboard_options: app_dashboard.Options) !void {
    defer stream.close(ctx.io);
    var read_buffer: [8192]u8 = undefined;
    var reader = stream.reader(ctx.io, &read_buffer);
    const request_line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return,
        else => return err,
    };
    try discardHeaders(&reader.interface);
    const parsed = parseRequestLine(request_line) orelse {
        try writeJsonResponse(ctx, stream, 400, "{\"error\":\"bad_request\"}\n");
        return;
    };
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    const status: u16 = routeRequest(ctx, parsed, dashboard_options, &body.writer) catch |err| switch (err) {
        error.UnknownRoute => blk: {
            try body.writer.writeAll("{\"error\":\"not_found\"}\n");
            break :blk 404;
        },
        error.MethodNotAllowed => blk: {
            try body.writer.writeAll("{\"error\":\"method_not_allowed\"}\n");
            break :blk 405;
        },
        else => return err,
    };
    const bytes = try body.toOwnedSlice();
    defer ctx.gpa.free(bytes);
    try writeJsonResponse(ctx, stream, status, bytes);
}

fn routeRequest(ctx: Context, request: RequestLine, dashboard_options: app_dashboard.Options, writer: anytype) !u16 {
    const path = pathOnly(request.target);
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, path, "/api/dashboard")) {
        const options = dashboardOptionsFromQuery(request.target, dashboard_options);
        try app_dashboard.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, options, writer);
        return 200;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, path, "/api/topology")) {
        try app_topology.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .limit = dashboard_options.limit }, writer);
        return 200;
    }
    if (std.mem.eql(u8, request.method, "GET") and std.mem.eql(u8, path, "/api/inventory")) {
        try app_inventory.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = dashboard_options.domain, .limit = dashboard_options.limit }, writer);
        return 200;
    }
    if (std.mem.eql(u8, request.method, "POST") and std.mem.eql(u8, path, "/api/actions/plan")) {
        try app_actions.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .domain = dashboard_options.domain, .limit = dashboard_options.limit }, writer);
        return 200;
    }
    if (std.mem.eql(u8, path, "/api/actions/plan")) return error.MethodNotAllowed;
    return error.UnknownRoute;
}

fn writeJsonResponse(ctx: Context, stream: std.Io.net.Stream, status: u16, body: []const u8) !void {
    var write_buffer: [8192]u8 = undefined;
    var writer = stream.writer(ctx.io, &write_buffer);
    const status_text = switch (status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        else => "Error",
    };
    try writer.interface.print("HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, status_text, body.len });
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

fn discardHeaders(reader: *std.Io.Reader) !void {
    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const trimmed = trimLineEnding(line);
        if (trimmed.len == 0) return;
    }
}

const RequestLine = struct {
    method: []const u8,
    target: []const u8,
};

fn parseRequestLine(line: []const u8) ?RequestLine {
    const trimmed = trimLineEnding(line);
    var it = std.mem.splitScalar(u8, trimmed, ' ');
    const method = it.next() orelse return null;
    const target = it.next() orelse return null;
    if (method.len == 0 or target.len == 0) return null;
    return .{ .method = method, .target = target };
}

fn pathOnly(target: []const u8) []const u8 {
    const index = std.mem.indexOfScalar(u8, target, '?') orelse return target;
    return target[0..index];
}

fn trimLineEnding(line: []const u8) []const u8 {
    if (line.len != 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn dashboardOptionsFromQuery(target: []const u8, defaults: app_dashboard.Options) app_dashboard.Options {
    var out = defaults;
    const query_start = std.mem.indexOfScalar(u8, target, '?') orelse return out;
    var it = std.mem.splitScalar(u8, target[query_start + 1 ..], '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const key = pair[0..equals];
        const value = if (equals < pair.len) pair[equals + 1 ..] else "";
        if (std.mem.eql(u8, key, "domain")) out.domain = value;
        if (std.mem.eql(u8, key, "issues")) out.issues_only = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
        if (std.mem.eql(u8, key, "section")) out.section = app_dashboard.Section.parse(value) orelse out.section;
        if (std.mem.eql(u8, key, "limit")) out.limit = std.fmt.parseInt(i64, value, 10) catch out.limit;
    }
    return out.normalized();
}

test "serve request parser maps request targets" {
    const line = "GET /api/dashboard?domain=plosca.ru HTTP/1.1\r";
    const parsed = parseRequestLine(line).?;
    try std.testing.expectEqualStrings("GET", parsed.method);
    try std.testing.expectEqualStrings("/api/dashboard?domain=plosca.ru", parsed.target);
    try std.testing.expectEqualStrings("/api/dashboard", pathOnly(parsed.target));
    const options = dashboardOptionsFromQuery(parsed.target, .{});
    try std.testing.expectEqualStrings("plosca.ru", options.domain.?);
}
