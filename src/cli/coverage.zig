const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: app_coverage.Paths = .{},
};

pub const RenderFormat = enum {
    text,
    json,
};

const SummaryCommand = struct {
    format: RenderFormat = .text,
};

const TagCommand = struct {
    provider: app_coverage.ProviderFilter = .all,
    format: RenderFormat = .text,
};

const GapCommand = struct {
    options: app_coverage.GapOptions = .{},
    format: RenderFormat = .text,
};

const LevelCommand = struct {
    provider: app_coverage.ProviderFilter = .all,
    format: RenderFormat = .text,
};

const L1Command = struct {
    provider: app_coverage.ProviderFilter = .all,
    format: RenderFormat = .text,
};

const LevelTagCommand = struct {
    options: app_coverage.LevelTagOptions = .{},
    format: RenderFormat = .text,
};

const RouteCommand = struct {
    filter: app_coverage.RouteFilter = .{},
    format: RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .summary => |command| try commandSummary(ctx, command),
        .tags => |command| try commandTags(ctx, command),
        .l1 => |filter| try commandL1(ctx, filter),
        .gaps => |command| try commandGaps(ctx, command),
        .levels => |command| try commandLevels(ctx, command),
        .level_tags => |command| try commandLevelTags(ctx, command),
        .routes => |command| try commandRoutes(ctx, command),
        .plan => |plan_args| try commandPlan(ctx, plan_args),
        .unknown => |name| std.debug.print("unknown coverage command: {s}\n", .{name}),
    }
}

const Command = union(enum) {
    summary: SummaryCommand,
    tags: TagCommand,
    l1: L1Command,
    gaps: GapCommand,
    levels: LevelCommand,
    level_tags: LevelTagCommand,
    routes: RouteCommand,
    plan: []const []const u8,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0) return .{ .summary = .{} };
    if (std.mem.eql(u8, args[0], "summary")) return parseSummary(args[1..]);
    if (std.mem.eql(u8, args[0], "--json") or std.mem.eql(u8, args[0], "--format") or std.mem.startsWith(u8, args[0], "--format=")) return parseSummary(args);
    if (std.mem.eql(u8, args[0], "tags")) {
        return parseTags(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "l1") or std.mem.eql(u8, args[0], "audit-l1")) {
        return parseL1(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "gaps") or std.mem.eql(u8, args[0], "priorities")) {
        return parseGaps(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "levels")) {
        return parseLevels(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "level-tags") or std.mem.eql(u8, args[0], "levels-by-tag") or std.mem.eql(u8, args[0], "evidence")) {
        return parseLevelTags(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "routes")) {
        return parseRoutes(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "plan")) {
        return .{ .plan = args[1..] };
    }
    return .{ .unknown = args[0] };
}

fn parseSummary(args: []const []const u8) Command {
    var command = SummaryCommand{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .summary = command };
}

fn parseTags(args: []const []const u8) Command {
    var command = TagCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            command.provider = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
            provider_set = true;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .tags = command };
}

fn parseL1(args: []const []const u8) Command {
    var command = L1Command{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            command.provider = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
            provider_set = true;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .l1 = command };
}

fn parseGaps(args: []const []const u8) Command {
    var command = GapCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--limit")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--limit" };
            command.options.limit = std.fmt.parseUnsigned(usize, args[index], 10) catch return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            const value = arg["--limit=".len..];
            command.options.limit = std.fmt.parseUnsigned(usize, value, 10) catch return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            command.options.provider = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
            provider_set = true;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .gaps = command };
}

fn parseLevels(args: []const []const u8) Command {
    var command = LevelCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            command.provider = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
            provider_set = true;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .levels = command };
}

fn parseLevelTags(args: []const []const u8) Command {
    var command = LevelTagCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--limit")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--limit" };
            command.options.limit = std.fmt.parseUnsigned(usize, args[index], 10) catch return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            const value = arg["--limit=".len..];
            command.options.limit = std.fmt.parseUnsigned(usize, value, 10) catch return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            command.options.provider = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
            provider_set = true;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .level_tags = command };
}

fn parseFormat(value: []const u8) ?RenderFormat {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "json")) return .json;
    return null;
}

fn parseRoutes(args: []const []const u8) Command {
    var command = RouteCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--support")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--support" };
            command.filter.support = app_coverage.SupportFilter.parse(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.eql(u8, arg, "--detail") or std.mem.eql(u8, arg, "--details")) {
            command.filter.detail = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            command.format = .json;
        } else if (std.mem.eql(u8, arg, "--format")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--format" };
            command.format = parseFormat(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            command.format = parseFormat(value) orelse return .{ .unknown = value };
        } else if (std.mem.startsWith(u8, arg, "--support=")) {
            const value = arg["--support=".len..];
            command.filter.support = app_coverage.SupportFilter.parse(value) orelse return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--operation") or std.mem.eql(u8, arg, "--operation-id")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--operation" };
            command.filter.operation_id = args[index];
        } else if (std.mem.startsWith(u8, arg, "--operation=")) {
            command.filter.operation_id = arg["--operation=".len..];
        } else if (std.mem.startsWith(u8, arg, "--operation-id=")) {
            command.filter.operation_id = arg["--operation-id=".len..];
        } else if (std.mem.eql(u8, arg, "--method")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--method" };
            command.filter.method = app_coverage.parseRouteMethod(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--method=")) {
            const value = arg["--method=".len..];
            command.filter.method = app_coverage.parseRouteMethod(value) orelse return .{ .unknown = value };
        } else if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "--path-template")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--path" };
            command.filter.path_template = args[index];
        } else if (std.mem.startsWith(u8, arg, "--path=")) {
            command.filter.path_template = arg["--path=".len..];
        } else if (std.mem.startsWith(u8, arg, "--path-template=")) {
            command.filter.path_template = arg["--path-template=".len..];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= args.len) return .{ .unknown = "--mode" };
            command.filter.mode = app_coverage.ModeFilter.parse(args[index]) orelse return .{ .unknown = args[index] };
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const value = arg["--mode=".len..];
            command.filter.mode = app_coverage.ModeFilter.parse(value) orelse return .{ .unknown = value };
        } else if (!provider_set) {
            if (app_coverage.ProviderFilter.parse(arg)) |provider| {
                command.filter.provider = provider;
                provider_set = true;
            } else if (command.filter.tag_query == null) {
                command.filter.tag_query = arg;
            } else {
                return .{ .unknown = arg };
            }
        } else if (command.filter.tag_query == null) {
            command.filter.tag_query = arg;
        } else {
            return .{ .unknown = arg };
        }
    }
    return .{ .routes = command };
}

fn commandSummary(ctx: Context, command: SummaryCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeTextFromFiles(ctx.io, ctx.gpa, ctx.paths, &out.writer),
        .json => try app_coverage.writeJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandTags(ctx: Context, command: TagCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeTagsTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
        .json => try app_coverage.writeTagsJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandL1(ctx: Context, command: L1Command) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeL1AuditTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
        .json => try app_coverage.writeL1AuditJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandGaps(ctx: Context, command: GapCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeGapsTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.options, &out.writer),
        .json => try app_coverage.writeGapsJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.options, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandLevels(ctx: Context, command: LevelCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeLevelsTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
        .json => try app_coverage.writeLevelsJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.provider, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandLevelTags(ctx: Context, command: LevelTagCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeLevelTagsTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.options, &out.writer),
        .json => try app_coverage.writeLevelTagsJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.options, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandRoutes(ctx: Context, command: RouteCommand) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (command.format) {
        .text => try app_coverage.writeRoutesTextFromFiles(ctx.io, ctx.gpa, ctx.paths, command.filter, &out.writer),
        .json => try app_coverage.writeRoutesJsonFromFiles(ctx.io, ctx.gpa, ctx.paths, command.filter, &out.writer),
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandPlan(ctx: Context, args: []const []const u8) !void {
    const input = parsePlan(ctx.gpa, args) catch |err| {
        std.debug.print("invalid coverage plan arguments: {s}\n", .{@errorName(err)});
        return;
    };
    defer input.deinit(ctx.gpa);

    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    app_coverage.writeRoutePlanTextFromFiles(ctx.io, ctx.gpa, ctx.paths, input.plan, &out.writer) catch |err| {
        std.debug.print("coverage plan failed: {s}\n", .{@errorName(err)});
        return;
    };
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

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

pub fn parsePlan(gpa: Allocator, args: []const []const u8) !ParsedPlan {
    if (args.len == 0) return error.MissingCoveragePlanProvider;

    var filter = app_coverage.RouteFilter{};
    filter.provider = app_coverage.ProviderFilter.parse(args[0]) orelse return error.InvalidCoveragePlanProvider;

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
        } else if (std.mem.eql(u8, arg, "--header-param") or std.mem.eql(u8, arg, "--header")) {
            index += 1;
            if (index >= args.len) return error.MissingCoveragePlanOptionValue;
            try header_params.append(gpa, try app_coverage.parseHeaderParamAssignment(args[index]));
        } else if (std.mem.startsWith(u8, arg, "--header-param=")) {
            try header_params.append(gpa, try app_coverage.parseHeaderParamAssignment(arg["--header-param=".len..]));
        } else if (std.mem.startsWith(u8, arg, "--header=")) {
            try header_params.append(gpa, try app_coverage.parseHeaderParamAssignment(arg["--header=".len..]));
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

test "coverage command parser defaults to summary" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command{ .summary = .{} }, parseCommand(no_args[0..]));

    const summary_args = [_][]const u8{"summary"};
    try std.testing.expectEqual(Command{ .summary = .{} }, parseCommand(summary_args[0..]));

    const summary_json_args = [_][]const u8{ "summary", "--json" };
    try std.testing.expectEqual(Command{ .summary = .{ .format = .json } }, parseCommand(summary_json_args[0..]));

    const default_summary_json_args = [_][]const u8{"--format=json"};
    try std.testing.expectEqual(Command{ .summary = .{ .format = .json } }, parseCommand(default_summary_json_args[0..]));

    const tags_args = [_][]const u8{"tags"};
    try std.testing.expectEqual(Command{ .tags = .{} }, parseCommand(tags_args[0..]));

    const hostinger_tags_args = [_][]const u8{ "tags", "hostinger" };
    try std.testing.expectEqual(Command{ .tags = .{ .provider = .hostinger } }, parseCommand(hostinger_tags_args[0..]));

    const cloudflare_tags_json_args = [_][]const u8{ "tags", "cloudflare", "--json" };
    try std.testing.expectEqual(Command{ .tags = .{ .provider = .cloudflare, .format = .json } }, parseCommand(cloudflare_tags_json_args[0..]));

    const l1_args = [_][]const u8{ "l1", "cloudflare" };
    try std.testing.expectEqual(Command{ .l1 = .{ .provider = .cloudflare } }, parseCommand(l1_args[0..]));

    const l1_default_args = [_][]const u8{"audit-l1"};
    try std.testing.expectEqual(Command{ .l1 = .{} }, parseCommand(l1_default_args[0..]));

    const l1_json_args = [_][]const u8{ "audit-l1", "hostinger", "--format=json" };
    try std.testing.expectEqual(Command{ .l1 = .{ .provider = .hostinger, .format = .json } }, parseCommand(l1_json_args[0..]));

    const gaps_args = [_][]const u8{ "gaps", "hostinger", "--limit", "7" };
    switch (parseCommand(gaps_args[0..])) {
        .gaps => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expectEqual(@as(usize, 7), command.options.limit);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageGaps,
    }

    const priorities_args = [_][]const u8{ "priorities", "--limit=0", "--json" };
    switch (parseCommand(priorities_args[0..])) {
        .gaps => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageGaps,
    }

    const levels_args = [_][]const u8{ "levels", "cloudflare", "--format=json" };
    switch (parseCommand(levels_args[0..])) {
        .levels => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.provider);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageLevels,
    }

    const levels_default_args = [_][]const u8{"levels"};
    switch (parseCommand(levels_default_args[0..])) {
        .levels => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.provider);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageLevels,
    }

    const level_tags_args = [_][]const u8{ "level-tags", "cloudflare", "--limit", "9", "--format", "json" };
    switch (parseCommand(level_tags_args[0..])) {
        .level_tags => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(@as(usize, 9), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageLevelTags,
    }

    const evidence_args = [_][]const u8{ "evidence", "hostinger", "--limit=0" };
    switch (parseCommand(evidence_args[0..])) {
        .level_tags => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageLevelTags,
    }

    const routes_args = [_][]const u8{"routes"};
    switch (parseCommand(routes_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expect(filter.tag_query == null);
            try std.testing.expect(filter.support == null);
            try std.testing.expect(filter.mode == null);
            try std.testing.expect(!filter.detail);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const plan_args = [_][]const u8{ "plan", "hostinger", "--operation=VPS_getMetricsV1", "--path-param", "virtualMachineId=123", "--query=date_from=2026-06-16T00:00:00Z", "--query-param", "date_to=2026-06-17T00:00:00Z" };
    switch (parseCommand(plan_args[0..])) {
        .plan => |values| {
            try std.testing.expectEqual(@as(usize, plan_args.len - 1), values.len);
            try std.testing.expectEqualStrings("hostinger", values[0]);
        },
        else => return error.ExpectedCoveragePlan,
    }

    const hostinger_routes_args = [_][]const u8{ "routes", "hostinger", "VPS", "--support", "partial", "--mode=read", "--detail" };
    switch (parseCommand(hostinger_routes_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, filter.provider);
            try std.testing.expectEqualStrings("VPS", filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.partial, filter.support.?);
            try std.testing.expectEqual(app_coverage.ModeFilter.read, filter.mode.?);
            try std.testing.expect(filter.detail);
            try std.testing.expectEqual(RenderFormat.text, command.format);
            try std.testing.expect(filter.operation_id == null);
            try std.testing.expect(filter.method == null);
            try std.testing.expect(filter.path_template == null);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const query_routes_args = [_][]const u8{ "routes", "--support=planned", "Zone Settings", "--json" };
    switch (parseCommand(query_routes_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expectEqualStrings("Zone Settings", filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.planned, filter.support.?);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const explicit_all_args = [_][]const u8{ "routes", "all", "hostinger" };
    switch (parseCommand(explicit_all_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, filter.provider);
            try std.testing.expectEqualStrings("hostinger", filter.tag_query orelse "");
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const exact_operation_args = [_][]const u8{ "routes", "cloudflare", "--operation", "accounts-list-accounts", "--method=GET", "--path=/accounts", "--format=json" };
    switch (parseCommand(exact_operation_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, filter.provider);
            try std.testing.expectEqualStrings("accounts-list-accounts", filter.operation_id orelse "");
            try std.testing.expectEqual(app_coverage.parseRouteMethod("GET").?, filter.method.?);
            try std.testing.expectEqualStrings("/accounts", filter.path_template orelse "");
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageRoutes,
    }

    const alias_args = [_][]const u8{ "routes", "hostinger", "--operation-id=VPS_getVirtualMachinesV1", "--path-template", "/api/vps/v1/virtual-machines" };
    switch (parseCommand(alias_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
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

    const unknown_gap_limit_args = [_][]const u8{ "gaps", "--limit", "many" };
    switch (parseCommand(unknown_gap_limit_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("many", name),
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
