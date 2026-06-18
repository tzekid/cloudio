const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_coverage = @import("cli_coverage");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    cloudflare_auth: app_coverage.Auth,
    hostinger_token: ?[]const u8,
    db: *app_coverage.DbHandle,
    domains: []const []const u8 = &.{},
    paths: app_coverage.Paths = .{},
};

const Action = enum {
    plan,
    read,
    capture,
    capture_ready,
    dry_run,

    fn parse(value: []const u8) ?Action {
        if (std.mem.eql(u8, value, "plan")) return .plan;
        if (std.mem.eql(u8, value, "read") or std.mem.eql(u8, value, "get")) return .read;
        if (std.mem.eql(u8, value, "capture") or std.mem.eql(u8, value, "collect")) return .capture;
        if (std.mem.eql(u8, value, "capture-ready") or std.mem.eql(u8, value, "capture_ready") or std.mem.eql(u8, value, "capture-actual-ready")) return .capture_ready;
        if (std.mem.eql(u8, value, "dry-run") or std.mem.eql(u8, value, "dry_run")) return .dry_run;
        return null;
    }

    fn name(self: Action) []const u8 {
        return switch (self) {
            .plan => "plan",
            .read => "read",
            .capture => "capture",
            .capture_ready => "capture-ready",
            .dry_run => "dry-run",
        };
    }
};

const ParsedCaptureArgs = struct {
    plan_args: []const []const u8,
    kind: ?[]const u8,
    target: ?[]const u8,
    paginate: bool = false,
    max_pages: usize = 25,
    diagnostic_read: bool = false,

    fn deinit(self: ParsedCaptureArgs, gpa: Allocator) void {
        gpa.free(self.plan_args);
    }
};

const ParsedCaptureReadyArgs = struct {
    options: app_coverage.ActualReadyCaptureOptions = .{},
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

    if (action == .capture) {
        var capture_args = parseCaptureArgs(ctx.gpa, args[1..]) catch |err| {
            std.debug.print("invalid route capture arguments: {s}\n", .{@errorName(err)});
            return;
        };
        defer capture_args.deinit(ctx.gpa);
        const parsed = cli_coverage.parsePlan(ctx.gpa, capture_args.plan_args) catch |err| {
            std.debug.print("invalid route capture arguments: {s}\n", .{@errorName(err)});
            return;
        };
        defer parsed.deinit(ctx.gpa);
        const json = app_coverage.routeCaptureReadMetadataJson(
            ctx.io,
            ctx.gpa,
            ctx.paths,
            parsed.plan,
            authFor(ctx, parsed.plan.filter.provider) catch |err| {
                std.debug.print("route capture failed: {s}\n", .{@errorName(err)});
                return;
            },
            ctx.db,
            .{
                .kind = capture_args.kind,
                .target = capture_args.target,
                .paginate = capture_args.paginate,
                .max_pages = capture_args.max_pages,
                .diagnostic_read = capture_args.diagnostic_read,
            },
        ) catch |err| {
            std.debug.print("route capture failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer ctx.gpa.free(json);
        try cli_render.writeLine(ctx.io, json);
        return;
    }

    if (action == .capture_ready) {
        var parsed = parseCaptureReadyArgs(args[1..]) catch |err| {
            std.debug.print("invalid route capture-ready arguments: {s}\n", .{@errorName(err)});
            return;
        };
        parsed.options.configured_domains = ctx.domains;
        const json = app_coverage.actualReadyCaptureJsonFromFiles(
            ctx.io,
            ctx.gpa,
            ctx.paths,
            ctx.db,
            authFor(ctx, parsed.options.filter.provider) catch |err| {
                std.debug.print("route capture-ready failed: {s}\n", .{@errorName(err)});
                return;
            },
            parsed.options,
        ) catch |err| {
            std.debug.print("route capture-ready failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer ctx.gpa.free(json);
        try cli_render.writeLine(ctx.io, json);
        return;
    }

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
        .capture => unreachable,
        .capture_ready => unreachable,
        .dry_run => app_coverage.routeDryRunJson(ctx.io, ctx.gpa, ctx.paths, parsed.plan, authFor(ctx, parsed.plan.filter.provider) catch |err| {
            std.debug.print("route dry-run failed: {s}\n", .{@errorName(err)});
            return;
        }),
    } catch |err| {
        std.debug.print("route {s} failed: {s}\n", .{ action.name(), @errorName(err) });
        return;
    };
    defer ctx.gpa.free(json);
    try cli_render.writeLine(ctx.io, json);
}

fn authFor(ctx: Context, provider: app_coverage.ProviderFilter) !app_coverage.Auth {
    return switch (provider) {
        .cloudflare => ctx.cloudflare_auth,
        .hostinger => .{ .hostinger = ctx.hostinger_token orelse "" },
        .all => error.RouteProviderRequired,
    };
}

fn parseCaptureReadyArgs(args: []const []const u8) !ParsedCaptureReadyArgs {
    var parsed = ParsedCaptureReadyArgs{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--execute")) {
            parsed.options.execute = true;
        } else if (std.mem.eql(u8, arg, "--include-blocked") or std.mem.eql(u8, arg, "--diagnostic-blocked")) {
            parsed.options.include_blocked = true;
        } else if (std.mem.eql(u8, arg, "--diagnostic-only") or std.mem.eql(u8, arg, "--only-diagnostic")) {
            parsed.options.include_blocked = true;
            parsed.options.diagnostic_only = true;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "--plan-only")) {
            parsed.options.execute = false;
        } else if (try parseCaptureReadyValue(args, &index, .{"--limit"})) |value| {
            parsed.options.limit = try cli_args.parseUnsignedUsize(value, error.InvalidRouteCaptureReadyLimit);
        } else if (try parseCaptureReadyValue(args, &index, .{"--max-pages"})) |value| {
            parsed.options.max_pages = try cli_args.parsePositiveUsize(value, error.InvalidRouteCaptureReadyMaxPages);
        } else if (try parseCaptureReadyValue(args, &index, .{ "--family", "--control-plane-family" })) |value| {
            parsed.options.filter.family = app_coverage.WorkplanFamily.parse(value) orelse return error.InvalidRouteCaptureReadyFamily;
        } else if (try parseCaptureReadyValue(args, &index, .{ "--operation", "--operation-id" })) |value| {
            parsed.options.filter.operation_id = value;
        } else if (try parseCaptureReadyValue(args, &index, .{ "--path", "--path-template" })) |value| {
            parsed.options.filter.path_template = value;
        } else if (try parseCaptureReadyValue(args, &index, .{"--support"})) |value| {
            parsed.options.filter.support = app_coverage.SupportFilter.parse(value) orelse return error.InvalidRouteCaptureReadySupport;
        } else if (!provider_set) {
            if (app_coverage.ProviderFilter.parse(arg)) |provider| {
                parsed.options.filter.provider = provider;
                provider_set = true;
            } else if (parsed.options.filter.tag_query == null) {
                parsed.options.filter.tag_query = arg;
            } else {
                return error.UnknownRouteCaptureReadyArgument;
            }
        } else if (parsed.options.filter.tag_query == null) {
            parsed.options.filter.tag_query = arg;
        } else {
            return error.UnknownRouteCaptureReadyArgument;
        }
    }
    return parsed;
}

fn parseCaptureReadyValue(args: []const []const u8, index: *usize, comptime names: anytype) !?[]const u8 {
    return try cli_args.parseRequiredValueArg(args, index, names, error.MissingRouteCaptureReadyOptionValue);
}

fn parseCaptureArgs(gpa: Allocator, args: []const []const u8) !ParsedCaptureArgs {
    var plan_args = std.ArrayList([]const u8).empty;
    errdefer plan_args.deinit(gpa);
    var kind: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var paginate = false;
    var max_pages: usize = 25;
    var diagnostic_read = false;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--paginate")) {
            paginate = true;
        } else if (std.mem.eql(u8, arg, "--diagnostic")) {
            diagnostic_read = true;
        } else if (try cli_args.parsePositiveUsizeArg(args, &index, .{"--max-pages"}, error.MissingRouteCaptureOptionValue, error.InvalidRouteCaptureMaxPages)) |value| {
            max_pages = value;
        } else if (try cli_args.parseRequiredValueArg(args, &index, .{ "--kind", "--snapshot-kind" }, error.MissingRouteCaptureOptionValue)) |value| {
            kind = value;
        } else if (try cli_args.parseRequiredValueArg(args, &index, .{ "--target", "--snapshot-target" }, error.MissingRouteCaptureOptionValue)) |value| {
            target = value;
        } else {
            try plan_args.append(gpa, arg);
        }
    }

    return .{
        .plan_args = try plan_args.toOwnedSlice(gpa),
        .kind = kind,
        .target = target,
        .paginate = paginate,
        .max_pages = max_pages,
        .diagnostic_read = diagnostic_read,
    };
}

fn usage() void {
    std.debug.print(
        \\Usage:
        \\  cloudio route plan <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-present|--body-content-type <type>]
        \\  cloudio route read <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value]
        \\  cloudio route capture <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--kind <snapshot-kind>] [--target <snapshot-target>] [--paginate] [--max-pages <n>] [--diagnostic]
        \\  cloudio route capture-ready <cloudflare|hostinger> [tag-query] [--family <family>] [--operation <id>] [--limit <n>] [--max-pages <n>] [--include-blocked|--diagnostic-only] [--execute]
        \\  cloudio route dry-run <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-present|--body-content-type <type>]
        \\
    , .{});
}

test "route action parser accepts stable command names" {
    try std.testing.expectEqual(Action.plan, Action.parse("plan").?);
    try std.testing.expectEqual(Action.read, Action.parse("read").?);
    try std.testing.expectEqual(Action.read, Action.parse("get").?);
    try std.testing.expectEqual(Action.capture, Action.parse("capture").?);
    try std.testing.expectEqual(Action.capture, Action.parse("collect").?);
    try std.testing.expectEqual(Action.capture_ready, Action.parse("capture-ready").?);
    try std.testing.expectEqual(Action.capture_ready, Action.parse("capture_ready").?);
    try std.testing.expectEqual(Action.dry_run, Action.parse("dry-run").?);
    try std.testing.expectEqual(Action.dry_run, Action.parse("dry_run").?);
    try std.testing.expect(Action.parse("write") == null);
}

test "route capture-ready parser builds provider family execution options" {
    const args = [_][]const u8{
        "hostinger",
        "--family",
        "hostinger-vps",
        "--limit=0",
        "--max-pages",
        "3",
        "--operation",
        "VPS_getBackupsV1",
        "--diagnostic-only",
        "--execute",
    };
    const parsed = try parseCaptureReadyArgs(args[0..]);
    try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, parsed.options.filter.provider);
    try std.testing.expectEqual(app_coverage.WorkplanFamily.hostinger_vps, parsed.options.filter.family);
    try std.testing.expectEqualStrings("VPS_getBackupsV1", parsed.options.filter.operation_id orelse "");
    try std.testing.expectEqual(@as(usize, 0), parsed.options.limit);
    try std.testing.expectEqual(@as(usize, 3), parsed.options.max_pages);
    try std.testing.expect(parsed.options.include_blocked);
    try std.testing.expect(parsed.options.diagnostic_only);
    try std.testing.expect(parsed.options.execute);

    const tag_args = [_][]const u8{ "cloudflare", "Logs", "--support=partial", "--plan-only" };
    const tag = try parseCaptureReadyArgs(tag_args[0..]);
    try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, tag.options.filter.provider);
    try std.testing.expectEqualStrings("Logs", tag.options.filter.tag_query orelse "");
    try std.testing.expectEqual(app_coverage.SupportFilter.partial, tag.options.filter.support.?);
    try std.testing.expect(!tag.options.execute);

    try std.testing.expectError(error.InvalidRouteCaptureReadyMaxPages, parseCaptureReadyArgs(&.{ "--max-pages", "0" }));
    try std.testing.expectError(error.MissingRouteCaptureReadyOptionValue, parseCaptureReadyArgs(&.{"--family"}));
}

test "route capture parser separates snapshot labels from route request arguments" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{
        "hostinger",
        "--operation=VPS_getMetricsV1",
        "--path-param",
        "virtualMachineId=123",
        "--target=vps-123",
        "--kind",
        "route-vps-metrics",
        "--paginate",
        "--max-pages=3",
        "--diagnostic",
        "--query-param=date_from=2026-06-16T00:00:00Z",
    };
    const parsed = try parseCaptureArgs(allocator, args[0..]);
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("route-vps-metrics", parsed.kind orelse "");
    try std.testing.expectEqualStrings("vps-123", parsed.target orelse "");
    try std.testing.expect(parsed.paginate);
    try std.testing.expectEqual(@as(usize, 3), parsed.max_pages);
    try std.testing.expect(parsed.diagnostic_read);
    try std.testing.expectEqual(@as(usize, 5), parsed.plan_args.len);
    try std.testing.expectEqualStrings("hostinger", parsed.plan_args[0]);
    try std.testing.expectEqualStrings("--operation=VPS_getMetricsV1", parsed.plan_args[1]);
    try std.testing.expectEqualStrings("--path-param", parsed.plan_args[2]);
    try std.testing.expectEqualStrings("virtualMachineId=123", parsed.plan_args[3]);
    try std.testing.expectEqualStrings("--query-param=date_from=2026-06-16T00:00:00Z", parsed.plan_args[4]);

    try std.testing.expectError(error.MissingRouteCaptureOptionValue, parseCaptureArgs(allocator, &.{"--target"}));
    try std.testing.expectError(error.InvalidRouteCaptureMaxPages, parseCaptureArgs(allocator, &.{ "--max-pages", "0" }));
}

test "route auth selection requires an exact provider" {
    var db: app_coverage.DbHandle = undefined;
    const ctx = Context{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .cloudflare_auth = .{ .cloudflare = .{} },
        .hostinger_token = "token",
        .db = &db,
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
