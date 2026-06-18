const std = @import("std");
const app_projects = @import("app_projects");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    projects_root: []const u8,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .list => try commandList(ctx),
        .show => |name| try commandShow(ctx, name),
        .correlate => |rest| try commandCorrelate(ctx, rest),
        .show_missing_name => std.debug.print("projects show requires a project name\n", .{}),
        .unknown => |name| std.debug.print("unknown projects command: {s}\n", .{name}),
    }
}

fn commandList(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_projects.writeList(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandShow(ctx: Context, name: []const u8) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_projects.writeShow(ctx.gpa, ctx.db, name, &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandCorrelate(ctx: Context, args: []const []const u8) !void {
    const format = parseCorrelationFormat(args) catch |err| {
        std.debug.print("invalid projects correlate command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, format, app_projects.writeCorrelationsText, app_projects.writeCorrelationsJson, .{ appContext(ctx), app_projects.CorrelationOptions{} });
}

fn appContext(ctx: Context) app_projects.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .projects_root = ctx.projects_root,
        .db = ctx.db,
    };
}

const Command = union(enum) {
    list,
    show: []const u8,
    correlate: []const []const u8,
    show_missing_name,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "list")) return .list;
    if (std.mem.eql(u8, args[0], "show")) {
        if (args.len < 2) return .show_missing_name;
        return .{ .show = args[1] };
    }
    if (std.mem.eql(u8, args[0], "correlate") or std.mem.eql(u8, args[0], "correlations") or std.mem.eql(u8, args[0], "graph")) {
        return .{ .correlate = args[1..] };
    }
    return .{ .unknown = args[0] };
}

fn parseCorrelationFormat(args: []const []const u8) !cli_render.RenderFormat {
    var format: cli_render.RenderFormat = .text;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (cli_render.parseFormatArg(args, &index)) {
            .matched => |parsed| {
                format = parsed;
                continue;
            },
            .missing_value => return error.MissingFormat,
            .invalid_value => return error.InvalidFormat,
            .no_match => return error.UnexpectedProjectsCorrelateArgument,
        }
    }
    return format;
}

test "projects command parser maps list show and correlation commands" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.list, parseCommand(no_args[0..]));

    const list_args = [_][]const u8{"list"};
    try std.testing.expectEqual(Command.list, parseCommand(list_args[0..]));

    const show_args = [_][]const u8{ "show", "cloudio" };
    switch (parseCommand(show_args[0..])) {
        .show => |name| try std.testing.expectEqualStrings("cloudio", name),
        else => return error.ExpectedProjectsShow,
    }

    const correlate_args = [_][]const u8{ "correlate", "--json" };
    switch (parseCommand(correlate_args[0..])) {
        .correlate => |rest| try std.testing.expectEqualStrings("--json", rest[0]),
        else => return error.ExpectedProjectsCorrelate,
    }

    const missing_show_args = [_][]const u8{"show"};
    try std.testing.expectEqual(Command.show_missing_name, parseCommand(missing_show_args[0..]));

    const unknown_args = [_][]const u8{"delete"};
    switch (parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("delete", name),
        else => return error.ExpectedUnknownProjectsCommand,
    }

    const json_args = [_][]const u8{"--json"};
    try std.testing.expectEqual(cli_render.RenderFormat.json, try parseCorrelationFormat(json_args[0..]));

    const format_args = [_][]const u8{ "--format", "json" };
    try std.testing.expectEqual(cli_render.RenderFormat.json, try parseCorrelationFormat(format_args[0..]));

    const unexpected_args = [_][]const u8{"extra"};
    try std.testing.expectError(error.UnexpectedProjectsCorrelateArgument, parseCorrelationFormat(unexpected_args[0..]));
}
