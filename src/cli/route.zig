const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_coverage = @import("cli_coverage");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    cloudflare_auth: app_coverage.Auth,
    hostinger_token: ?[]const u8,
    paths: app_coverage.Paths = .{},
};

const Action = enum {
    plan,
    read,
    dry_run,

    fn parse(value: []const u8) ?Action {
        if (std.mem.eql(u8, value, "plan")) return .plan;
        if (std.mem.eql(u8, value, "read") or std.mem.eql(u8, value, "get")) return .read;
        if (std.mem.eql(u8, value, "dry-run") or std.mem.eql(u8, value, "dry_run")) return .dry_run;
        return null;
    }

    fn name(self: Action) []const u8 {
        return switch (self) {
            .plan => "plan",
            .read => "read",
            .dry_run => "dry-run",
        };
    }
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    if (args.len == 0) {
        usage();
        return;
    }

    const action = Action.parse(args[0]) orelse {
        std.debug.print("unknown route command: {s}\n", .{args[0]});
        usage();
        return;
    };
    const parsed = cli_coverage.parsePlan(ctx.gpa, args[1..]) catch |err| {
        std.debug.print("invalid route {s} arguments: {s}\n", .{ action.name(), @errorName(err) });
        return;
    };
    defer parsed.deinit(ctx.gpa);

    const json = switch (action) {
        .plan => app_coverage.routePlanJson(ctx.io, ctx.gpa, ctx.paths, parsed.plan),
        .read => app_coverage.routeReadMetadataJson(ctx.io, ctx.gpa, ctx.paths, parsed.plan, authFor(ctx, parsed.plan.filter.provider) catch |err| {
            std.debug.print("route read failed: {s}\n", .{@errorName(err)});
            return;
        }),
        .dry_run => app_coverage.routeDryRunJson(ctx.io, ctx.gpa, ctx.paths, parsed.plan, authFor(ctx, parsed.plan.filter.provider) catch |err| {
            std.debug.print("route dry-run failed: {s}\n", .{@errorName(err)});
            return;
        }),
    } catch |err| {
        std.debug.print("route {s} failed: {s}\n", .{ action.name(), @errorName(err) });
        return;
    };
    defer ctx.gpa.free(json);
    std.debug.print("{s}\n", .{json});
}

fn authFor(ctx: Context, provider: app_coverage.ProviderFilter) !app_coverage.Auth {
    return switch (provider) {
        .cloudflare => ctx.cloudflare_auth,
        .hostinger => .{ .hostinger = ctx.hostinger_token orelse "" },
        .all => error.RouteProviderRequired,
    };
}

fn usage() void {
    std.debug.print(
        \\Usage:
        \\  cloudio route plan <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-present|--body-content-type <type>]
        \\  cloudio route read <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value]
        \\  cloudio route dry-run <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-present|--body-content-type <type>]
        \\
    , .{});
}

test "route action parser accepts stable command names" {
    try std.testing.expectEqual(Action.plan, Action.parse("plan").?);
    try std.testing.expectEqual(Action.read, Action.parse("read").?);
    try std.testing.expectEqual(Action.read, Action.parse("get").?);
    try std.testing.expectEqual(Action.dry_run, Action.parse("dry-run").?);
    try std.testing.expectEqual(Action.dry_run, Action.parse("dry_run").?);
    try std.testing.expect(Action.parse("write") == null);
}

test "route auth selection requires an exact provider" {
    const ctx = Context{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .cloudflare_auth = .{ .cloudflare = .{} },
        .hostinger_token = "token",
    };
    switch (try authFor(ctx, .cloudflare)) {
        .cloudflare => |auth| try std.testing.expect(!auth.hasApiToken()),
        else => return error.ExpectedCloudflareAuth,
    }
    switch (try authFor(ctx, .hostinger)) {
        .hostinger => |token| try std.testing.expectEqualStrings("token", token),
        else => return error.ExpectedHostingerAuth,
    }
    try std.testing.expectError(error.RouteProviderRequired, authFor(ctx, .all));
}
