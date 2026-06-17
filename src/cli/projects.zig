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
    show_missing_name,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "list")) return .list;
    if (std.mem.eql(u8, args[0], "show")) {
        if (args.len < 2) return .show_missing_name;
        return .{ .show = args[1] };
    }
    return .{ .unknown = args[0] };
}

test "projects command parser maps list and show commands" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.list, parseCommand(no_args[0..]));

    const list_args = [_][]const u8{"list"};
    try std.testing.expectEqual(Command.list, parseCommand(list_args[0..]));

    const show_args = [_][]const u8{ "show", "cloudio" };
    switch (parseCommand(show_args[0..])) {
        .show => |name| try std.testing.expectEqualStrings("cloudio", name),
        else => return error.ExpectedProjectsShow,
    }

    const missing_show_args = [_][]const u8{"show"};
    try std.testing.expectEqual(Command.show_missing_name, parseCommand(missing_show_args[0..]));

    const unknown_args = [_][]const u8{"delete"};
    switch (parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("delete", name),
        else => return error.ExpectedUnknownProjectsCommand,
    }
}
