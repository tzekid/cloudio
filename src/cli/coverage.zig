const std = @import("std");
const app_coverage = @import("app_coverage");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: app_coverage.Paths = .{},
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .summary => try commandSummary(ctx),
        .tags => |filter| try commandTags(ctx, filter),
        .routes => |filter| try commandRoutes(ctx, filter),
        .unknown => |name| std.debug.print("unknown coverage command: {s}\n", .{name}),
    }
}

const Command = union(enum) {
    summary,
    tags: app_coverage.ProviderFilter,
    routes: app_coverage.RouteFilter,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "summary")) return .summary;
    if (std.mem.eql(u8, args[0], "tags")) {
        if (args.len < 2) return .{ .tags = .all };
        const filter = app_coverage.ProviderFilter.parse(args[1]) orelse return .{ .unknown = args[1] };
        return .{ .tags = filter };
    }
    if (std.mem.eql(u8, args[0], "routes")) {
        return parseRoutes(args[1..]);
    }
    return .{ .unknown = args[0] };
}

fn parseRoutes(args: []const []const u8) Command {
    var filter = app_coverage.RouteFilter{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--support")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--support" };
            filter.support = app_coverage.SupportFilter.parse(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.eql(u8, arg, "--detail") or std.mem.eql(u8, arg, "--details")) {
            filter.detail = true;
        } else if (std.mem.startsWith(u8, arg, "--support=")) {
            const value = arg["--support=".len..];
            filter.support = app_coverage.SupportFilter.parse(value) orelse return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--mode" };
            filter.mode = app_coverage.ModeFilter.parse(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const value = arg["--mode=".len..];
            filter.mode = app_coverage.ModeFilter.parse(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            if (app_coverage.ProviderFilter.parse(arg)) |provider| {
                filter.provider = provider;
                provider_set = true;
            } else if (filter.tag_query == null) {
                filter.tag_query = arg;
            } else {
                return .{ .unknown = arg };
            }
        } else if (filter.tag_query == null) {
            filter.tag_query = arg;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .routes = filter };
}

fn commandSummary(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_coverage.writeTextFromFiles(ctx.io, ctx.gpa, ctx.paths, &out.writer);
    const text = try out.toOwnedSlice();
    defer ctx.gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn commandTags(ctx: Context, filter: app_coverage.ProviderFilter) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_coverage.writeTagsTextFromFiles(ctx.io, ctx.gpa, ctx.paths, filter, &out.writer);
    const text = try out.toOwnedSlice();
    defer ctx.gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn commandRoutes(ctx: Context, filter: app_coverage.RouteFilter) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_coverage.writeRoutesTextFromFiles(ctx.io, ctx.gpa, ctx.paths, filter, &out.writer);
    const text = try out.toOwnedSlice();
    defer ctx.gpa.free(text);
    std.debug.print("{s}", .{text});
}

test "coverage command parser defaults to summary" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.summary, parseCommand(no_args[0..]));

    const summary_args = [_][]const u8{"summary"};
    try std.testing.expectEqual(Command.summary, parseCommand(summary_args[0..]));

    const tags_args = [_][]const u8{"tags"};
    try std.testing.expectEqual(Command{ .tags = .all }, parseCommand(tags_args[0..]));

    const hostinger_tags_args = [_][]const u8{ "tags", "hostinger" };
    try std.testing.expectEqual(Command{ .tags = .hostinger }, parseCommand(hostinger_tags_args[0..]));

    const routes_args = [_][]const u8{"routes"};
    switch (parseCommand(routes_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expect(filter.tag_query == null);
            try std.testing.expect(filter.support == null);
            try std.testing.expect(filter.mode == null);
            try std.testing.expect(!filter.detail);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const hostinger_routes_args = [_][]const u8{ "routes", "hostinger", "VPS", "--support", "partial", "--mode=read", "--detail" };
    switch (parseCommand(hostinger_routes_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, filter.provider);
            try std.testing.expectEqualStrings("VPS", filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.partial, filter.support.?);
            try std.testing.expectEqual(app_coverage.ModeFilter.read, filter.mode.?);
            try std.testing.expect(filter.detail);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const query_routes_args = [_][]const u8{ "routes", "--support=planned", "Zone Settings" };
    switch (parseCommand(query_routes_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expectEqualStrings("Zone Settings", filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.planned, filter.support.?);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const explicit_all_args = [_][]const u8{ "routes", "all", "hostinger" };
    switch (parseCommand(explicit_all_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expectEqualStrings("hostinger", filter.tag_query orelse "");
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const unknown_args = [_][]const u8{"refresh"};
    switch (parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("refresh", name),
        else => return error.ExpectedUnknownCoverageCommand,
    }

    const unknown_filter_args = [_][]const u8{ "tags", "bad-provider" };
    switch (parseCommand(unknown_filter_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("bad-provider", name),
        else => return error.ExpectedUnknownCoverageCommand,
    }

    const unknown_support_args = [_][]const u8{ "routes", "--support", "maybe" };
    switch (parseCommand(unknown_support_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("maybe", name),
        else => return error.ExpectedUnknownCoverageCommand,
    }
}
