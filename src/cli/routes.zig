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

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid routes command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_route_catalog.writeText, app_route_catalog.writeJson, .{ ctx.io, ctx.gpa, ctx.paths, parsed.options });
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
    const defaults = try parse(no_args[0..]);
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.all, defaults.options.provider);
    try std.testing.expect(defaults.options.query == null);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);

    const args = [_][]const u8{ "hostinger", "vps", "--limit=7", "--json" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.hostinger, parsed.options.provider);
    try std.testing.expectEqualStrings("vps", parsed.options.query.?);
    try std.testing.expectEqual(@as(i64, 7), parsed.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);

    const flag_args = [_][]const u8{ "--provider", "cloudflare", "--query=dns", "--format", "json" };
    const flags = try parse(flag_args[0..]);
    try std.testing.expectEqual(app_route_catalog.ProviderFilter.cloudflare, flags.options.provider);
    try std.testing.expectEqualStrings("dns", flags.options.query.?);
    try std.testing.expectEqual(cli_render.RenderFormat.json, flags.format);
}

test "routes parser rejects invalid options" {
    const invalid_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidRoutesProvider, parse(invalid_provider[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidRoutesLimit, parse(invalid_limit[0..]));

    const extra = [_][]const u8{ "cloudflare", "dns", "extra" };
    try std.testing.expectError(error.UnexpectedRoutesArgument, parse(extra[0..]));
}
