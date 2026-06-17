const std = @import("std");
const app_system = @import("app_system");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .summary => try commandSummary(ctx),
        .services => try commandServices(ctx),
        .ports => try commandPorts(ctx),
        .containers => try commandContainers(ctx),
        .metrics => try commandMetrics(ctx),
        .logs => |unit| try cli_render.printOutput(ctx.io, ctx.gpa, try app_system.logs(appContext(ctx), unit)),
        .unknown => |name| std.debug.print("unknown system command: {s}\n", .{name}),
    }
}

fn commandSummary(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_system.collectAndWriteSummary(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandServices(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_system.collectAndWriteServices(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandPorts(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_system.collectAndWritePorts(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandContainers(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_system.collectAndWriteContainers(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandMetrics(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_system.collectAndWriteMetrics(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn appContext(ctx: Context) app_system.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

const Command = union(enum) {
    summary,
    services,
    ports,
    containers,
    metrics,
    logs: []const u8,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "summary")) return .summary;
    if (std.mem.eql(u8, args[0], "services")) return .services;
    if (std.mem.eql(u8, args[0], "ports")) return .ports;
    if (std.mem.eql(u8, args[0], "containers")) return .containers;
    if (std.mem.eql(u8, args[0], "metrics")) return .metrics;
    if (std.mem.eql(u8, args[0], "logs")) return .{ .logs = if (args.len > 1) args[1] else "caddy" };
    return .{ .unknown = args[0] };
}

test "system command parser maps subcommands and defaults logs to caddy" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.summary, parseCommand(no_args[0..]));

    const summary_args = [_][]const u8{"summary"};
    try std.testing.expectEqual(Command.summary, parseCommand(summary_args[0..]));

    const services_args = [_][]const u8{"services"};
    try std.testing.expectEqual(Command.services, parseCommand(services_args[0..]));

    const ports_args = [_][]const u8{"ports"};
    try std.testing.expectEqual(Command.ports, parseCommand(ports_args[0..]));

    const containers_args = [_][]const u8{"containers"};
    try std.testing.expectEqual(Command.containers, parseCommand(containers_args[0..]));

    const metrics_args = [_][]const u8{"metrics"};
    try std.testing.expectEqual(Command.metrics, parseCommand(metrics_args[0..]));

    const logs_default_args = [_][]const u8{"logs"};
    switch (parseCommand(logs_default_args[0..])) {
        .logs => |unit| try std.testing.expectEqualStrings("caddy", unit),
        else => return error.ExpectedSystemLogs,
    }

    const logs_explicit_args = [_][]const u8{ "logs", "ssh" };
    switch (parseCommand(logs_explicit_args[0..])) {
        .logs => |unit| try std.testing.expectEqualStrings("ssh", unit),
        else => return error.ExpectedSystemLogs,
    }

    const unknown_args = [_][]const u8{"reboot"};
    switch (parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("reboot", name),
        else => return error.ExpectedUnknownSystemCommand,
    }
}
