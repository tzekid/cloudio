const std = @import("std");
const app_route_catalog = @import("app_route_catalog");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: app_route_catalog.Paths = .{},
};

const Parsed = struct {
    options: app_route_catalog.Options = .{},
    format: cli_render.RenderFormat = .text,
};

const Command = union(enum) {
    catalog: Parsed,
    groups: Parsed,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parseCommand(args) catch |err| {
        std.debug.print("invalid routes command: {s}\n", .{@errorName(err)});
        return err;
    };
    switch (command) {
        .catalog => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_route_catalog.writeText, app_route_catalog.writeJson, .{ ctx.io, ctx.gpa, ctx.paths, parsed.options }),
        .groups => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_route_catalog.writeGroupsText, app_route_catalog.writeGroupsJson, .{ ctx.io, ctx.gpa, ctx.paths, parsed.options }),
    }
}

fn parseCommand(args: []const []const u8) !Command {
    if (args.len != 0) {
        if (std.mem.eql(u8, args[0], "groups") or std.mem.eql(u8, args[0], "families") or std.mem.eql(u8, args[0], "summary") or std.mem.eql(u8, args[0], "tags")) {
            return .{ .groups = try parse(args[1..]) };
        }
        if (std.mem.eql(u8, args[0], "list") or std.mem.eql(u8, args[0], "catalog")) {
            return .{ .catalog = try parse(args[1..]) };
        }
    }
    return .{ .catalog = try parse(args) };
}

fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var provider_seen = false;
    var query_seen = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingRoutesLimit, error.InvalidRoutesLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--provider"}, error.MissingRoutesProvider)) |value| {
            parsed.options.provider = app_route_catalog.ProviderFilter.parse(value) orelse return error.InvalidRoutesProvider;
            provider_seen = true;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--query"}, error.MissingRoutesQuery)) |value| {
            parsed.options.query = value;
            query_seen = true;
            continue;
        }

        const arg = args[index];
        if (!provider_seen) {
            if (app_route_catalog.ProviderFilter.parse(arg)) |provider| {
                parsed.options.provider = provider;
                provider_seen = true;
                continue;
            }
        }
        if (!query_seen) {
            parsed.options.query = arg;
            query_seen = true;
            continue;
        }
        return error.UnexpectedRoutesArgument;
    }
    return parsed;
}

test "routes parser accepts provider query limit and format" {
    const no_args = [_][]const u8{};
    const defaults = (try parseCommand(no_args[0..])).catalog;
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.all, defaults.options.provider);
    try std.testing.expect(defaults.options.query == null);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);

    const args = [_][]const u8{ "hostinger", "vps", "--limit=7", "--json" };
    const parsed = (try parseCommand(args[0..])).catalog;
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.hostinger, parsed.options.provider);
    try std.testing.expectEqualStrings("vps", parsed.options.query.?);
    try std.testing.expectEqual(@as(i64, 7), parsed.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);

    const flag_args = [_][]const u8{ "--provider", "cloudflare", "--query=dns", "--format", "json" };
    const flags = (try parseCommand(flag_args[0..])).catalog;
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.cloudflare, flags.options.provider);
    try std.testing.expectEqualStrings("dns", flags.options.query.?);
    try std.testing.expectEqual(cli_render.RenderFormat.json, flags.format);

    const groups_args = [_][]const u8{ "groups", "cloudflare", "dns", "--limit=3", "--json" };
    const groups = (try parseCommand(groups_args[0..])).groups;
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.cloudflare, groups.options.provider);
    try std.testing.expectEqualStrings("dns", groups.options.query.?);
    try std.testing.expectEqual(@as(i64, 3), groups.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, groups.format);

    const catalog_args = [_][]const u8{ "catalog", "hostinger", "--query=vps" };
    const catalog = (try parseCommand(catalog_args[0..])).catalog;
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.hostinger, catalog.options.provider);
    try std.testing.expectEqualStrings("vps", catalog.options.query.?);
}

test "routes parser rejects invalid options" {
    const invalid_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidRoutesProvider, parseCommand(invalid_provider[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidRoutesLimit, parseCommand(invalid_limit[0..]));

    const extra = [_][]const u8{ "cloudflare", "dns", "extra" };
    try std.testing.expectError(error.UnexpectedRoutesArgument, parseCommand(extra[0..]));

    const invalid_groups = [_][]const u8{ "groups", "--provider", "other" };
    try std.testing.expectError(error.InvalidRoutesProvider, parseCommand(invalid_groups[0..]));
}
