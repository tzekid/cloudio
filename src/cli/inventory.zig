const std = @import("std");
const app_inventory = @import("app_inventory");
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
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) return error.MissingProvider;
            parsed.options.provider = try parseProvider(args[i]);
        } else if (std.mem.eql(u8, arg, "--domain")) {
            i += 1;
            if (i >= args.len) return error.MissingDomain;
            parsed.options.domain = args[i];
        } else if (std.mem.eql(u8, arg, "--query")) {
            i += 1;
            if (i >= args.len) return error.MissingQuery;
            parsed.options.query = args[i];
        } else if (std.mem.eql(u8, arg, "--limit")) {
            i += 1;
            if (i >= args.len) return error.MissingLimit;
            parsed.options.limit = try parseLimit(args[i]);
        } else if (std.mem.eql(u8, arg, "--json")) {
            parsed.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return error.MissingFormat;
            parsed.format = try cli_render.parseFormatStrict(args[i]);
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            parsed.format = try cli_render.parseFormatStrict(arg["--format=".len..]);
        } else if (isProvider(arg) and parsed.options.provider == null) {
            parsed.options.provider = try parseProvider(arg);
        } else if (parsed.options.query == null) {
            parsed.options.query = arg;
        } else {
            return error.UnexpectedArgument;
        }
    }
    return parsed;
}

fn parseProvider(value: []const u8) !app_inventory.Provider {
    return app_inventory.Provider.parse(value) orelse error.InvalidProvider;
}

fn isProvider(value: []const u8) bool {
    return app_inventory.Provider.parse(value) != null;
}

fn parseLimit(value: []const u8) !i64 {
    const parsed = try std.fmt.parseInt(i64, value, 10);
    if (parsed < 1) return error.InvalidLimit;
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
