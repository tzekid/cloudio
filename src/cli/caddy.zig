const std = @import("std");
const app_caddy = @import("app_caddy");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: app_caddy.Paths,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .sites => try commandSites(ctx),
        .upstreams => try commandUpstreams(ctx),
        .render => cli_render.printOutput(ctx.gpa, try app_caddy.render(appContext(ctx))),
        .diff => cli_render.printOutput(ctx.gpa, try app_caddy.diff(appContext(ctx))),
        .validate => cli_render.printOutput(ctx.gpa, try app_caddy.validate(appContext(ctx))),
        .unknown => |name| std.debug.print("unknown caddy command: {s}\n", .{name}),
    }
}

const Command = union(enum) {
    sites,
    upstreams,
    render,
    diff,
    validate,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "sites")) return .sites;
    if (std.mem.eql(u8, args[0], "upstreams")) return .upstreams;
    if (std.mem.eql(u8, args[0], "render")) return .render;
    if (std.mem.eql(u8, args[0], "diff")) return .diff;
    if (std.mem.eql(u8, args[0], "validate")) return .validate;
    return .{ .unknown = args[0] };
}

fn commandSites(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy.writeSites(appContext(ctx), &out.writer);
    try printOwned(ctx.gpa, &out);
}

fn commandUpstreams(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy.collectAndWriteUpstreams(appContext(ctx), &out.writer);
    try printOwned(ctx.gpa, &out);
}

fn appContext(ctx: Context) app_caddy.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .paths = ctx.paths,
        .db = ctx.db,
    };
}

fn printOwned(gpa: Allocator, out: *std.Io.Writer.Allocating) !void {
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

test "caddy command parser defaults to sites and recognizes dry-run commands" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.sites, parseCommand(no_args[0..]));

    const sites_args = [_][]const u8{"sites"};
    try std.testing.expectEqual(Command.sites, parseCommand(sites_args[0..]));

    const upstreams_args = [_][]const u8{"upstreams"};
    try std.testing.expectEqual(Command.upstreams, parseCommand(upstreams_args[0..]));

    const render_args = [_][]const u8{"render"};
    try std.testing.expectEqual(Command.render, parseCommand(render_args[0..]));

    const diff_args = [_][]const u8{"diff"};
    try std.testing.expectEqual(Command.diff, parseCommand(diff_args[0..]));

    const validate_args = [_][]const u8{"validate"};
    try std.testing.expectEqual(Command.validate, parseCommand(validate_args[0..]));

    const unknown_args = [_][]const u8{"reload"};
    switch (parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("reload", name),
        else => return error.ExpectedUnknownCaddyCommand,
    }
}
