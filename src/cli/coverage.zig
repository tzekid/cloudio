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
        .plan => |plan_args| try commandPlan(ctx, plan_args),
        .unknown => |name| std.debug.print("unknown coverage command: {s}\n", .{name}),
    }
}

const Command = union(enum) {
    summary,
    tags: app_coverage.ProviderFilter,
    routes: app_coverage.RouteFilter,
    plan: []const []const u8,
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
    if (std.mem.eql(u8, args[0], "plan")) {
        return .{ .plan = args[1..] };
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
        } else if (std.mem.eql(u8, arg, "--operation") or std.mem.eql(u8, arg, "--operation-id")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--operation" };
            filter.operation_id = args[index];
        } else if (std.mem.startsWith(u8, arg, "--operation=")) {
            filter.operation_id = arg["--operation=".len..];
        } else if (std.mem.startsWith(u8, arg, "--operation-id=")) {
            filter.operation_id = arg["--operation-id=".len..];
        } else if (std.mem.eql(u8, arg, "--method")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--method" };
            filter.method = app_coverage.parseRouteMethod(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--method=")) {
            const value = arg["--method=".len..];
            filter.method = app_coverage.parseRouteMethod(value) orelse return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "--path-template")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--path" };
            filter.path_template = args[index];
        } else if (std.mem.startsWith(u8, arg, "--path=")) {
            filter.path_template = arg["--path=".len..];
        } else if (std.mem.startsWith(u8, arg, "--path-template=")) {
            filter.path_template = arg["--path-template=".len..];
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

fn commandPlan(ctx: Context, args: []const []const u8) !void {
    const input = parsePlan(ctx.gpa, args) catch |err| {
        std.debug.print("invalid coverage plan arguments: {s}\n", .{@errorName(err)});
        return;
    };
    defer input.deinit(ctx.gpa);

    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_coverage.writeRoutePlanTextFromFiles(ctx.io, ctx.gpa, ctx.paths, input.plan, &out.writer);
    const text = try out.toOwnedSlice();
    defer ctx.gpa.free(text);
    std.debug.print("{s}", .{text});
}

const ParsedPlan = struct {
    plan: app_coverage.RoutePlanInput,
    path_params: []app_coverage.PathParam,
    query_params: []app_coverage.QueryParam,

    fn deinit(self: ParsedPlan, gpa: Allocator) void {
        gpa.free(self.path_params);
        gpa.free(self.query_params);
    }
};

fn parsePlan(gpa: Allocator, args: []const []const u8) !ParsedPlan {
    if (args.len == 0) return error.MissingCoveragePlanProvider;

    var filter = app_coverage.RouteFilter{};
    filter.provider = app_coverage.ProviderFilter.parse(args[0]) orelse return error.InvalidCoveragePlanProvider;

    var path_params = std.ArrayList(app_coverage.PathParam).empty;
    errdefer path_params.deinit(gpa);
    var query_params = std.ArrayList(app_coverage.QueryParam).empty;
    errdefer query_params.deinit(gpa);
    var body = app_coverage.BodyInput{};

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--operation") or std.mem.eql(u8, arg, "--operation-id")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.operation_id = args[index];
        } else if (std.mem.startsWith(u8, arg, "--operation=")) {
            filter.operation_id = arg["--operation=".len..];
        } else if (std.mem.startsWith(u8, arg, "--operation-id=")) {
            filter.operation_id = arg["--operation-id=".len..];
        } else if (std.mem.eql(u8, arg, "--method")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.method = app_coverage.parseRouteMethod(args[index]) orelse return error.InvalidCoveragePlanMethod;
        } else if (std.mem.startsWith(u8, arg, "--method=")) {
            const value = arg["--method=".len..];
            filter.method = app_coverage.parseRouteMethod(value) orelse return error.InvalidCoveragePlanMethod;
        } else if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "--path-template")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.path_template = args[index];
        } else if (std.mem.startsWith(u8, arg, "--path=")) {
            filter.path_template = arg["--path=".len..];
        } else if (std.mem.startsWith(u8, arg, "--path-template=")) {
            filter.path_template = arg["--path-template=".len..];
        } else if (std.mem.eql(u8, arg, "--tag")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.tag_query = args[index];
        } else if (std.mem.startsWith(u8, arg, "--tag=")) {
            filter.tag_query = arg["--tag=".len..];
        } else if (std.mem.eql(u8, arg, "--support")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.support = app_coverage.SupportFilter.parse(args[index]) orelse return error.InvalidCoveragePlanSupport;
        } else if (std.mem.startsWith(u8, arg, "--support=")) {
            const value = arg["--support=".len..];
            filter.support = app_coverage.SupportFilter.parse(value) orelse return error.InvalidCoveragePlanSupport;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            filter.mode = app_coverage.ModeFilter.parse(args[index]) orelse return error.InvalidCoveragePlanMode;
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const value = arg["--mode=".len..];
            filter.mode = app_coverage.ModeFilter.parse(value) orelse return error.InvalidCoveragePlanMode;
        } else if (std.mem.eql(u8, arg, "--path-param") or std.mem.eql(u8, arg, "--param")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            try path_params.append(gpa, try app_coverage.parsePathParamAssignment(args[index]));
        } else if (std.mem.startsWith(u8, arg, "--path-param=")) {
            try path_params.append(gpa, try app_coverage.parsePathParamAssignment(arg["--path-param=".len..]));
        } else if (std.mem.startsWith(u8, arg, "--param=")) {
            try path_params.append(gpa, try app_coverage.parsePathParamAssignment(arg["--param=".len..]));
        } else if (std.mem.eql(u8, arg, "--query-param") or std.mem.eql(u8, arg, "--query")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            try query_params.append(gpa, try app_coverage.parseQueryParamAssignment(args[index]));
        } else if (std.mem.startsWith(u8, arg, "--query-param=")) {
            try query_params.append(gpa, try app_coverage.parseQueryParamAssignment(arg["--query-param=".len..]));
        } else if (std.mem.startsWith(u8, arg, "--query=")) {
            try query_params.append(gpa, try app_coverage.parseQueryParamAssignment(arg["--query=".len..]));
        } else if (std.mem.eql(u8, arg, "--body-present")) {
            body.present = true;
        } else if (std.mem.eql(u8, arg, "--body-content-type") or std.mem.eql(u8, arg, "--content-type")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            body.present = true;
            body.content_type = args[index];
        } else if (std.mem.startsWith(u8, arg, "--body-content-type=")) {
            body.present = true;
            body.content_type = arg["--body-content-type=".len..];
        } else if (std.mem.startsWith(u8, arg, "--content-type=")) {
            body.present = true;
            body.content_type = arg["--content-type=".len..];
        } else {
            return error.UnknownCoveragePlanOption;
        }
    }

    const path_owned = try path_params.toOwnedSlice(gpa);
    errdefer gpa.free(path_owned);
    const query_owned = try query_params.toOwnedSlice(gpa);
    errdefer gpa.free(query_owned);

    return .{
        .plan = .{
            .filter = filter,
            .request = .{
                .path_params = path_owned,
                .query_params = query_owned,
                .body = body,
            },
        },
        .path_params = path_owned,
        .query_params = query_owned,
    };
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

    const plan_args = [_][]const u8{ "plan", "hostinger", "--operation=VPS_getMetricsV1", "--path-param", "virtualMachineId=vm/1", "--query=date_from=2026-06-16T00:00:00Z", "--query-param", "date_to=2026-06-17T00:00:00Z" };
    switch (parseCommand(plan_args[0..])) {
        .plan => |values| {
            try std.testing.expectEqual(@as(usize, plan_args.len - 1), values.len);
            try std.testing.expectEqualStrings("hostinger", values[0]);
        },
        else => return error.ExpectedCoveragePlan,
    }

    const hostinger_routes_args = [_][]const u8{ "routes", "hostinger", "VPS", "--support", "partial", "--mode=read", "--detail" };
    switch (parseCommand(hostinger_routes_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, filter.provider);
            try std.testing.expectEqualStrings("VPS", filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.partial, filter.support.?);
            try std.testing.expectEqual(app_coverage.ModeFilter.read, filter.mode.?);
            try std.testing.expect(filter.detail);
            try std.testing.expect(filter.operation_id == null);
            try std.testing.expect(filter.method == null);
            try std.testing.expect(filter.path_template == null);
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

    const exact_operation_args = [_][]const u8{ "routes", "cloudflare", "--operation", "accounts-list-accounts", "--method=GET", "--path=/accounts" };
    switch (parseCommand(exact_operation_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, filter.provider);
            try std.testing.expectEqualStrings("accounts-list-accounts", filter.operation_id orelse "");
            try std.testing.expectEqual(app_coverage.parseRouteMethod("GET").?, filter.method.?);
            try std.testing.expectEqualStrings("/accounts", filter.path_template orelse "");
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const alias_args = [_][]const u8{ "routes", "hostinger", "--operation-id=VPS_getVirtualMachinesV1", "--path-template", "/api/vps/v1/virtual-machines" };
    switch (parseCommand(alias_args[0..])) {
        .routes => |filter| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, filter.provider);
            try std.testing.expectEqualStrings("VPS_getVirtualMachinesV1", filter.operation_id orelse "");
            try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines", filter.path_template orelse "");
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

    const unknown_method_args = [_][]const u8{ "routes", "--method", "FETCH" };
    switch (parseCommand(unknown_method_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("FETCH", name),
        else => return error.ExpectedUnknownCoverageCommand,
    }
}

test "coverage plan parser builds reusable provider route requests" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{
        "cloudflare",
        "--operation",
        "worker-assets-upload",
        "--method=POST",
        "--path-param=account_id=acct/1",
        "--query",
        "base64=true",
        "--content-type",
        "multipart/form-data; boundary=test",
    };

    const parsed = try parsePlan(allocator, args[0..]);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, parsed.plan.filter.provider);
    try std.testing.expectEqualStrings("worker-assets-upload", parsed.plan.filter.operation_id orelse "");
    try std.testing.expectEqual(app_coverage.parseRouteMethod("POST").?, parsed.plan.filter.method.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.plan.request.path_params.len);
    try std.testing.expectEqualStrings("account_id", parsed.plan.request.path_params[0].name);
    try std.testing.expectEqualStrings("acct/1", parsed.plan.request.path_params[0].value);
    try std.testing.expectEqual(@as(usize, 1), parsed.plan.request.query_params.len);
    try std.testing.expectEqualStrings("base64", parsed.plan.request.query_params[0].name);
    try std.testing.expectEqualStrings("true", parsed.plan.request.query_params[0].value);
    try std.testing.expect(parsed.plan.request.body.present);
    try std.testing.expectEqualStrings("multipart/form-data; boundary=test", parsed.plan.request.body.content_type orelse "");
}
