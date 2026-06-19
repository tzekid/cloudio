const std = @import("std");
const app_actions = @import("app_actions");
const app_database = @import("app_database");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub const Parsed = struct {
    options: app_actions.Options = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid actions command: {s}\n", .{@errorName(err)});
        return err;
    };
    if (parsed.format != .json) return error.ActionsRequireJson;
    try cli_render.printRendered(ctx.io, ctx.gpa, app_actions.writeJson, .{ appContext(ctx), parsed.options });
}

fn appContext(ctx: Context) app_actions.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

pub fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var index: usize = 0;
    if (args.len != 0 and std.mem.eql(u8, args[0], "plan")) index = 1;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--domain"}, error.MissingDomain)) |value| {
            parsed.options.domain = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--provider"}, error.MissingProvider)) |value| {
            parsed.options.provider = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--target"}, error.MissingTarget)) |value| {
            parsed.options.target = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--action"}, error.MissingAction)) |value| {
            parsed.options.action = value;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        return error.UnexpectedActionsArgument;
    }
    return parsed;
}

test "actions parser accepts plan filters" {
    const args = [_][]const u8{ "plan", "--provider", "cloudflare", "--domain=plosca.ru", "--target", "record", "--json" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqualStrings("cloudflare", parsed.options.provider.?);
    try std.testing.expectEqualStrings("plosca.ru", parsed.options.domain.?);
    try std.testing.expectEqualStrings("record", parsed.options.target.?);
}
