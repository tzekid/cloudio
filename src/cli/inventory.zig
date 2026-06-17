const std = @import("std");
const app_inventory = @import("app_inventory");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parseCommand(args) catch |err| {
        std.debug.print("invalid inventory command: {s}\n", .{@errorName(err)});
        return err;
    };
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    const app_ctx = app_inventory.Context{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
    switch (command) {
        .list => |options| try app_inventory.writeText(app_ctx, options, &out.writer),
        .summary => |options| try app_inventory.writeSummaryText(app_ctx, options, &out.writer),
    }
    const text = try out.toOwnedSlice();
    defer ctx.gpa.free(text);
    std.debug.print("{s}", .{text});
}

pub const Command = union(enum) {
    list: app_inventory.ListOptions,
    summary: app_inventory.ListOptions,
};

pub fn parseCommand(args: []const []const u8) !Command {
    if (args.len != 0 and (std.mem.eql(u8, args[0], "summary") or std.mem.eql(u8, args[0], "facets"))) {
        return .{ .summary = try parseOptions(args[1..]) };
    }
    return .{ .list = try parseOptions(args) };
}

pub fn parseOptions(args: []const []const u8) !app_inventory.ListOptions {
    var options = app_inventory.ListOptions{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) return error.MissingProvider;
            options.provider = try parseProvider(args[i]);
        } else if (std.mem.eql(u8, arg, "--domain")) {
            i += 1;
            if (i >= args.len) return error.MissingDomain;
            options.domain = args[i];
        } else if (std.mem.eql(u8, arg, "--query")) {
            i += 1;
            if (i >= args.len) return error.MissingQuery;
            options.query = args[i];
        } else if (std.mem.eql(u8, arg, "--limit")) {
            i += 1;
            if (i >= args.len) return error.MissingLimit;
            options.limit = try parseLimit(args[i]);
        } else if (isProvider(arg) and options.provider == null) {
            options.provider = arg;
        } else if (options.query == null) {
            options.query = arg;
        } else {
            return error.UnexpectedArgument;
        }
    }
    return options;
}

fn parseProvider(value: []const u8) ![]const u8 {
    if (!isProvider(value)) return error.InvalidProvider;
    return value;
}

fn isProvider(value: []const u8) bool {
    return std.mem.eql(u8, value, "cloudflare") or std.mem.eql(u8, value, "hostinger");
}

fn parseLimit(value: []const u8) !i64 {
    const parsed = try std.fmt.parseInt(i64, value, 10);
    if (parsed < 1) return error.InvalidLimit;
    return parsed;
}

test "inventory parser maps positional provider and filters" {
    const args = [_][]const u8{ "cloudflare", "--domain", "plosca.ru", "--query", "dns", "--limit", "25" };
    const options = try parseOptions(args[0..]);
    try std.testing.expectEqualStrings("cloudflare", options.provider.?);
    try std.testing.expectEqualStrings("plosca.ru", options.domain.?);
    try std.testing.expectEqualStrings("dns", options.query.?);
    try std.testing.expectEqual(@as(i64, 25), options.limit);
}

test "inventory parser routes summary command with filters" {
    const args = [_][]const u8{ "summary", "hostinger", "--domain", "plosca.ru", "--limit", "10" };
    switch (try parseCommand(args[0..])) {
        .summary => |options| {
            try std.testing.expectEqualStrings("hostinger", options.provider.?);
            try std.testing.expectEqualStrings("plosca.ru", options.domain.?);
            try std.testing.expectEqual(@as(i64, 10), options.limit);
        },
        .list => return error.ExpectedInventorySummary,
    }

    const facets_args = [_][]const u8{ "facets", "--provider", "cloudflare", "dns" };
    switch (try parseCommand(facets_args[0..])) {
        .summary => |options| {
            try std.testing.expectEqualStrings("cloudflare", options.provider.?);
            try std.testing.expectEqualStrings("dns", options.query.?);
        },
        .list => return error.ExpectedInventorySummary,
    }
}

test "inventory parser accepts provider flag and query positional" {
    const args = [_][]const u8{ "--provider", "hostinger", "u123" };
    const options = try parseOptions(args[0..]);
    try std.testing.expectEqualStrings("hostinger", options.provider.?);
    try std.testing.expectEqualStrings("u123", options.query.?);
}

test "inventory parser rejects unknown providers and extra query terms" {
    const bad_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidProvider, parseOptions(bad_provider[0..]));

    const extra = [_][]const u8{ "cloudflare", "dns", "record" };
    try std.testing.expectError(error.UnexpectedArgument, parseOptions(extra[0..]));
}
