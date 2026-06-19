const std = @import("std");
const app_dashboard = @import("app_dashboard");
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
    options: app_dashboard.Options = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid dashboard command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_dashboard.writeText, app_dashboard.writeJson, .{ appContext(ctx), parsed.options });
}

fn appContext(ctx: Context) app_dashboard.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

pub fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--domain"}, error.MissingDomain)) |value| {
            parsed.options.domain = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--section"}, error.MissingSection)) |value| {
            parsed.options.section = app_dashboard.Section.parse(value) orelse return error.InvalidSection;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        if (std.mem.eql(u8, args[index], "--issues")) {
            parsed.options.issues_only = true;
            continue;
        }
        return error.UnexpectedDashboardArgument;
    }
    return parsed;
}

test "dashboard parser accepts requested UI flags" {
    const args = [_][]const u8{ "--domain", "plosca.ru", "--issues", "--section=projects", "--json", "--limit", "25" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqualStrings("plosca.ru", parsed.options.domain.?);
    try std.testing.expect(parsed.options.issues_only);
    try std.testing.expectEqual(app_dashboard.Section.projects, parsed.options.section);
    try std.testing.expectEqual(@as(i64, 25), parsed.options.limit);
}

test "dashboard parser rejects invalid sections" {
    const args = [_][]const u8{ "--section", "coverage" };
    try std.testing.expectError(error.InvalidSection, parse(args[0..]));
}
