const std = @import("std");
const app_topology = @import("app_topology");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

const Parsed = struct {
    options: app_topology.Options = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid topology command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_topology.writeText, app_topology.writeJson, .{ appContext(ctx), parsed.options });
}

fn appContext(ctx: Context) app_topology.Context {
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingTopologyLimit, error.InvalidTopologyLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        return error.UnexpectedTopologyArgument;
    }
    return parsed;
}

test "topology parser accepts format and limit" {
    const no_args = [_][]const u8{};
    const defaults = try parse(no_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);
    try std.testing.expectEqual(@as(i64, app_topology.default_limit), defaults.options.limit);

    const args = [_][]const u8{ "--json", "--limit=25" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqual(@as(i64, 25), parsed.options.limit);

    const split_args = [_][]const u8{ "--format", "json", "--limit", "3" };
    const split = try parse(split_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, split.format);
    try std.testing.expectEqual(@as(i64, 3), split.options.limit);
}

test "topology parser rejects invalid values" {
    const missing_limit = [_][]const u8{"--limit"};
    try std.testing.expectError(error.MissingTopologyLimit, parse(missing_limit[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidTopologyLimit, parse(invalid_limit[0..]));

    const unexpected = [_][]const u8{"extra"};
    try std.testing.expectError(error.UnexpectedTopologyArgument, parse(unexpected[0..]));
}
