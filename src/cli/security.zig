const std = @import("std");
const app_database = @import("app_database");
const app_security = @import("app_security");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const core_config = @import("core_config");

const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    config: Config,
    db: *Db,
};

const Parsed = struct {
    options: app_security.Options = .{},
    format: cli_render.RenderFormat = .text,
};

const Command = union(enum) {
    redaction: Parsed,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parseCommand(args) catch |err| {
        std.debug.print("invalid security command: {s}\n", .{@errorName(err)});
        return err;
    };
    switch (command) {
        .redaction => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_security.writeText, app_security.writeJson, .{ appContext(ctx), parsed.options }),
    }
}

fn appContext(ctx: Context) app_security.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .config = ctx.config,
        .db = ctx.db,
    };
}

fn parseCommand(args: []const []const u8) !Command {
    if (args.len != 0 and (std.mem.eql(u8, args[0], "redaction") or std.mem.eql(u8, args[0], "secrets") or std.mem.eql(u8, args[0], "audit"))) {
        return .{ .redaction = try parseOptions(args[1..]) };
    }
    return .{ .redaction = try parseOptions(args) };
}

fn parseOptions(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        return error.UnexpectedSecurityArgument;
    }
    return parsed;
}

test "security parser accepts redaction aliases and format" {
    const defaults_args = [_][]const u8{};
    const defaults = (try parseCommand(defaults_args[0..])).redaction;
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);

    const args = [_][]const u8{ "secrets", "--json" };
    const parsed = (try parseCommand(args[0..])).redaction;
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);

    const split_args = [_][]const u8{ "redaction", "--format", "json" };
    const split = (try parseCommand(split_args[0..])).redaction;
    try std.testing.expectEqual(cli_render.RenderFormat.json, split.format);
}

test "security parser rejects unexpected args" {
    const args = [_][]const u8{"extra"};
    try std.testing.expectError(error.UnexpectedSecurityArgument, parseCommand(args[0..]));
}
