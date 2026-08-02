const std = @import("std");
const app_database = @import("app_database");
const app_dashboard = @import("app_dashboard");
const app_serve = @import("app_serve");
const cli_args = @import("cli_args");
const core_config = @import("core_config");
const runtime_nob_workers = @import("runtime_nob_workers");
const runtime_scheduler = @import("runtime_scheduler");

const Allocator = std.mem.Allocator;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    config: core_config.Config,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const options = parse(args) catch |err| {
        std.debug.print("invalid serve command: {s}\n", .{@errorName(err)});
        return err;
    };
    if (!options.once and ctx.config.refresh_seconds > 0) {
        runtime_scheduler.start(.{ .io = ctx.io, .gpa = ctx.gpa, .config = ctx.config }) catch |err| {
            std.debug.print("cloudio scheduler spawn failed: {s}\n", .{@errorName(err)});
        };
    }
    if (!options.once) {
        runtime_nob_workers.start(.{ .io = ctx.io, .gpa = ctx.gpa, .config = ctx.config }) catch |err| {
            std.debug.print("cloudio nob worker spawn failed: {s}\n", .{@errorName(err)});
        };
    }
    try app_serve.run(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config }, options);
}

pub fn parse(args: []const []const u8) !app_serve.Options {
    var options = app_serve.Options{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--host"}, error.MissingHost)) |value| {
            options.host = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--port"}, error.MissingPort)) |value| {
            const parsed = std.fmt.parseInt(u16, value, 10) catch return error.InvalidPort;
            if (parsed == 0) return error.InvalidPort;
            options.port = parsed;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--domain"}, error.MissingDomain)) |value| {
            options.dashboard.domain = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--section"}, error.MissingSection)) |value| {
            options.dashboard.section = app_dashboard.Section.parse(value) orelse return error.InvalidSection;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            options.dashboard.limit = limit;
            continue;
        }
        if (std.mem.eql(u8, args[index], "--issues")) {
            options.dashboard.issues_only = true;
            continue;
        }
        if (std.mem.eql(u8, args[index], "--once")) {
            options.once = true;
            continue;
        }
        return error.UnexpectedServeArgument;
    }
    return options;
}

test "serve parser accepts local server and dashboard filters" {
    const args = [_][]const u8{ "--host=127.0.0.1", "--port", "9330", "--domain", "plosca.ru", "--section", "projects", "--once" };
    const options = try parse(args[0..]);
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(@as(u16, 9330), options.port);
    try std.testing.expectEqualStrings("plosca.ru", options.dashboard.domain.?);
    try std.testing.expectEqual(app_dashboard.Section.projects, options.dashboard.section);
    try std.testing.expect(options.once);
}
