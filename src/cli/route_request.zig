const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_args = @import("cli_args");

const Allocator = std.mem.Allocator;

pub const ParsedPlan = struct {
    plan: app_coverage.RoutePlanInput,
    path_params: []app_coverage.PathParam,
    query_params: []app_coverage.QueryParam,
    header_params: []app_coverage.HeaderParam,

    pub fn deinit(self: ParsedPlan, gpa: Allocator) void {
        gpa.free(self.path_params);
        gpa.free(self.query_params);
        gpa.free(self.header_params);
    }
};

fn parseRouteValueArg(args: []const []const u8, index: *usize, comptime names: anytype) !?[]const u8 {
    return try cli_args.parseRequiredValueArg(args, index, names, error.MissingRouteRequestOptionValue);
}

pub fn parsePlan(gpa: Allocator, args: []const []const u8) !ParsedPlan {
    if (args.len == 0) return error.MissingRouteRequestProvider;

    var filter = app_coverage.RouteFilter{};
    filter.provider = app_coverage.ProviderFilter.parse(args[0]) orelse return error.InvalidRouteRequestProvider;

    var path_params = std.ArrayList(app_coverage.PathParam).empty;
    errdefer path_params.deinit(gpa);
    var query_params = std.ArrayList(app_coverage.QueryParam).empty;
    errdefer query_params.deinit(gpa);
    var header_params = std.ArrayList(app_coverage.HeaderParam).empty;
    errdefer header_params.deinit(gpa);
    var body = app_coverage.BodyInput{};

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (try parseRouteValueArg(args, &index, .{ "--operation", "--operation-id" })) |value| {
            filter.operation_id = value;
        } else if (try parseRouteValueArg(args, &index, .{"--method"})) |value| {
            filter.method = app_coverage.parseRouteMethod(value) orelse return error.InvalidRouteRequestMethod;
        } else if (try parseRouteValueArg(args, &index, .{ "--path", "--path-template" })) |value| {
            filter.path_template = value;
        } else if (try parseRouteValueArg(args, &index, .{"--tag"})) |value| {
            filter.tag_query = value;
        } else if (try parseRouteValueArg(args, &index, .{"--support"})) |value| {
            filter.support = app_coverage.SupportFilter.parse(value) orelse return error.InvalidRouteRequestSupport;
        } else if (try parseRouteValueArg(args, &index, .{"--mode"})) |value| {
            filter.mode = app_coverage.ModeFilter.parse(value) orelse return error.InvalidRouteRequestMode;
        } else if (try parseRouteValueArg(args, &index, .{ "--path-param", "--param" })) |value| {
            try path_params.append(gpa, try app_coverage.parsePathParamAssignment(value));
        } else if (try parseRouteValueArg(args, &index, .{ "--query-param", "--query" })) |value| {
            try query_params.append(gpa, try app_coverage.parseQueryParamAssignment(value));
        } else if (try parseRouteValueArg(args, &index, .{ "--header-param", "--header" })) |value| {
            try header_params.append(gpa, try app_coverage.parseHeaderParamAssignment(value));
        } else if (cli_args.matches(arg, .{"--body-present"})) {
            body.present = true;
        } else if (try parseRouteValueArg(args, &index, .{ "--body-content-type", "--content-type" })) |value| {
            body.present = true;
            body.content_type = value;
        } else {
            return error.UnknownRouteRequestOption;
        }
    }

    const path_owned = try path_params.toOwnedSlice(gpa);
    errdefer gpa.free(path_owned);
    const query_owned = try query_params.toOwnedSlice(gpa);
    errdefer gpa.free(query_owned);
    const header_owned = try header_params.toOwnedSlice(gpa);
    errdefer gpa.free(header_owned);

    return .{
        .plan = .{
            .filter = filter,
            .request = .{
                .path_params = path_owned,
                .query_params = query_owned,
                .header_params = header_owned,
                .body = body,
            },
        },
        .path_params = path_owned,
        .query_params = query_owned,
        .header_params = header_owned,
    };
}

test "route request parser builds reusable provider route requests" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{
        "cloudflare",
        "--operation",
        "worker-assets-upload",
        "--method=POST",
        "--path-param=account_id=acct/1",
        "--query",
        "base64=true",
        "--header-param",
        "CF-R2-Jurisdiction=eu",
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
    try std.testing.expectEqual(@as(usize, 1), parsed.plan.request.header_params.len);
    try std.testing.expectEqualStrings("CF-R2-Jurisdiction", parsed.plan.request.header_params[0].name);
    try std.testing.expectEqualStrings("eu", parsed.plan.request.header_params[0].value);
    try std.testing.expect(parsed.plan.request.body.present);
    try std.testing.expectEqualStrings("multipart/form-data; boundary=test", parsed.plan.request.body.content_type orelse "");
}

test "route request parser rejects invalid provider route options" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingRouteRequestProvider, parsePlan(allocator, &.{}));
    try std.testing.expectError(error.InvalidRouteRequestProvider, parsePlan(allocator, &.{"other"}));
    try std.testing.expectError(error.InvalidRouteRequestMethod, parsePlan(allocator, &.{ "cloudflare", "--method", "FETCH" }));
    try std.testing.expectError(error.MissingRouteRequestOptionValue, parsePlan(allocator, &.{ "hostinger", "--operation" }));
    try std.testing.expectError(error.UnknownRouteRequestOption, parsePlan(allocator, &.{ "hostinger", "--unknown" }));
}
