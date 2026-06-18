const std = @import("std");
const app_inventory = @import("app_inventory");
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

pub const RenderFormat = cli_render.RenderFormat;

pub const Parsed = struct {
    options: app_inventory.ListOptions = .{},
    format: RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parseCommand(args) catch |err| {
        std.debug.print("invalid inventory command: {s}\n", .{@errorName(err)});
        return err;
    };
    const app_ctx = app_inventory.Context{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
    switch (command) {
        .list => |parsed| return try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_inventory.writeText, app_inventory.writeJson, .{ app_ctx, parsed.options }),
        .summary => |parsed| return try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_inventory.writeSummaryText, app_inventory.writeSummaryJson, .{ app_ctx, parsed.options }),
    }
}

pub const Command = union(enum) {
    list: Parsed,
    summary: Parsed,
};

pub fn parseCommand(args: []const []const u8) !Command {
    if (args.len != 0 and (std.mem.eql(u8, args[0], "summary") or std.mem.eql(u8, args[0], "facets"))) {
        return .{ .summary = try parseParsed(args[1..]) };
    }
    return .{ .list = try parseParsed(args) };
}

pub fn parseOptions(args: []const []const u8) !app_inventory.ListOptions {
    return (try parseParsed(args)).options;
}

pub fn parseParsed(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var provider_seen = false;
    var query_seen = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (try cli_args.parseFormatOption(args, &i, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        const arg = args[i];
        if (try cli_args.parseProviderOption(args, &i, &parsed.options.provider, &provider_seen, app_inventory.Provider.parse, .{"--provider"}, error.MissingProvider, error.InvalidProvider)) {
            continue;
        } else if (try cli_args.parseRequiredValueArg(args, &i, .{"--domain"}, error.MissingDomain)) |value| {
            parsed.options.domain = value;
        } else if (try cli_args.parseQueryOption(args, &i, &parsed.options.query, &query_seen, .{"--query"}, error.MissingQuery)) {
            continue;
        } else if (try cli_args.parsePositiveI64Arg(args, &i, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            parsed.options.limit = limit;
        } else if (cli_args.parseProviderPositional(arg, &parsed.options.provider, &provider_seen, app_inventory.Provider.parse)) {
            continue;
        } else if (cli_args.parseQueryPositional(arg, &parsed.options.query, &query_seen)) {
            continue;
        } else {
            return error.UnexpectedArgument;
        }
    }
    return parsed;
}

test "inventory parser maps positional provider and filters" {
    const args = [_][]const u8{ "cloudflare", "--domain", "plosca.ru", "--query", "dns", "--limit", "25" };
    const options = try parseOptions(args[0..]);
    try std.testing.expectEqual(app_inventory.Provider.cloudflare, options.provider.?);
    try std.testing.expectEqualStrings("plosca.ru", options.domain.?);
    try std.testing.expectEqualStrings("dns", options.query.?);
    try std.testing.expectEqual(@as(i64, 25), options.limit);
}

test "inventory parser routes summary command with filters" {
    const args = [_][]const u8{ "summary", "hostinger", "--domain", "plosca.ru", "--limit", "10" };
    switch (try parseCommand(args[0..])) {
        .summary => |parsed| {
            try std.testing.expectEqual(app_inventory.Provider.hostinger, parsed.options.provider.?);
            try std.testing.expectEqualStrings("plosca.ru", parsed.options.domain.?);
            try std.testing.expectEqual(@as(i64, 10), parsed.options.limit);
            try std.testing.expectEqual(RenderFormat.text, parsed.format);
        },
        .list => return error.ExpectedInventorySummary,
    }

    const facets_args = [_][]const u8{ "facets", "--provider", "cloudflare", "dns", "--format=json" };
    switch (try parseCommand(facets_args[0..])) {
        .summary => |parsed| {
            try std.testing.expectEqual(app_inventory.Provider.cloudflare, parsed.options.provider.?);
            try std.testing.expectEqualStrings("dns", parsed.options.query.?);
            try std.testing.expectEqual(RenderFormat.json, parsed.format);
        },
        .list => return error.ExpectedInventorySummary,
    }
}

test "inventory parser accepts json output for list commands" {
    const args = [_][]const u8{ "hostinger", "--json", "--limit", "5" };
    switch (try parseCommand(args[0..])) {
        .list => |parsed| {
            try std.testing.expectEqual(app_inventory.Provider.hostinger, parsed.options.provider.?);
            try std.testing.expectEqual(RenderFormat.json, parsed.format);
            try std.testing.expectEqual(@as(i64, 5), parsed.options.limit);
        },
        .summary => return error.ExpectedInventoryList,
    }

    const inline_args = [_][]const u8{ "--provider=cloudflare", "--domain=plosca.ru", "--query=dns", "--limit=3" };
    switch (try parseCommand(inline_args[0..])) {
        .list => |parsed| {
            try std.testing.expectEqual(app_inventory.Provider.cloudflare, parsed.options.provider.?);
            try std.testing.expectEqualStrings("plosca.ru", parsed.options.domain.?);
            try std.testing.expectEqualStrings("dns", parsed.options.query.?);
            try std.testing.expectEqual(@as(i64, 3), parsed.options.limit);
        },
        .summary => return error.ExpectedInventoryList,
    }
}

test "inventory parser accepts provider flag and query positional" {
    const args = [_][]const u8{ "--provider", "hostinger", "u123" };
    const options = try parseOptions(args[0..]);
    try std.testing.expectEqual(app_inventory.Provider.hostinger, options.provider.?);
    try std.testing.expectEqualStrings("u123", options.query.?);
}

test "inventory parser rejects unknown providers and extra query terms" {
    const bad_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidProvider, parseOptions(bad_provider[0..]));

    const extra = [_][]const u8{ "cloudflare", "dns", "record" };
    try std.testing.expectError(error.UnexpectedArgument, parseOptions(extra[0..]));
}
