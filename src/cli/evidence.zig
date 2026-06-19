const std = @import("std");
const app_evidence = @import("app_evidence");
const app_evidence_routes = @import("app_evidence_routes");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const app_database = @import("app_database");

const Allocator = std.mem.Allocator;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

const Parsed = struct {
    options: app_evidence.Options = .{},
    format: cli_render.RenderFormat = .text,
};

const Command = union(enum) {
    events: Parsed,
    matrix: Parsed,
    routes: Parsed,
    coverage: Parsed,
    capture_summary: Parsed,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parseCommand(args) catch |err| {
        std.debug.print("invalid evidence command: {s}\n", .{@errorName(err)});
        return err;
    };
    switch (command) {
        .events => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence.writeText, app_evidence.writeJson, .{ appContext(ctx), parsed.options }),
        .matrix => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence.writeMatrixText, app_evidence.writeMatrixJson, .{ appContext(ctx), parsed.options }),
        .routes => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence_routes.writeRouteCapturesText, app_evidence_routes.writeRouteCapturesJson, .{ appContext(ctx), parsed.options }),
        .coverage => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence_routes.writeRouteCoverageText, app_evidence_routes.writeRouteCoverageJson, .{ appContext(ctx), parsed.options }),
        .capture_summary => |parsed| try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence_routes.writeRouteCaptureSummaryText, app_evidence_routes.writeRouteCaptureSummaryJson, .{ appContext(ctx), parsed.options }),
    }
}

fn appContext(ctx: Context) app_evidence.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

fn parseCommand(args: []const []const u8) !Command {
    if (args.len != 0) {
        if (std.mem.eql(u8, args[0], "matrix") or std.mem.eql(u8, args[0], "families")) {
            return .{ .matrix = try parseOptions(args[1..]) };
        }
        if (std.mem.eql(u8, args[0], "routes") or std.mem.eql(u8, args[0], "route-captures") or std.mem.eql(u8, args[0], "captures")) {
            return .{ .routes = try parseOptions(args[1..]) };
        }
        if (std.mem.eql(u8, args[0], "coverage") or std.mem.eql(u8, args[0], "route-coverage") or std.mem.eql(u8, args[0], "covered-routes")) {
            return .{ .coverage = try parseOptions(args[1..]) };
        }
        if (std.mem.eql(u8, args[0], "capture-summary") or std.mem.eql(u8, args[0], "actual") or std.mem.eql(u8, args[0], "actual-routes") or std.mem.eql(u8, args[0], "route-summary") or std.mem.eql(u8, args[0], "read-coverage")) {
            return .{ .capture_summary = try parseOptions(args[1..]) };
        }
        if (std.mem.eql(u8, args[0], "events") or std.mem.eql(u8, args[0], "recent")) {
            return .{ .events = try parseOptions(args[1..]) };
        }
    }
    return .{ .events = try parseOptions(args) };
}

fn parseOptions(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var provider_seen = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parseProviderOption(args, &index, &parsed.options.provider, &provider_seen, app_evidence.ProviderFilter.parse, .{"--provider"}, error.MissingEvidenceProvider, error.InvalidEvidenceProvider)) continue;
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--limit"}, error.MissingEvidenceLimit)) |value| {
            const limit = try cli_args.parseSignedI64(value, error.InvalidEvidenceLimit);
            if (limit < 0) return error.InvalidEvidenceLimit;
            parsed.options.limit = limit;
            continue;
        }

        const arg = args[index];
        if (cli_args.parseProviderPositional(arg, &parsed.options.provider, &provider_seen, app_evidence.ProviderFilter.parse)) continue;
        return error.UnexpectedEvidenceArgument;
    }
    return parsed;
}

test "evidence parser accepts provider limit and format" {
    const defaults_args = [_][]const u8{};
    const defaults = (try parseCommand(defaults_args[0..])).events;
    try std.testing.expectEqual(app_evidence.ProviderFilter.all, defaults.options.provider);
    try std.testing.expectEqual(@as(i64, app_evidence.default_limit), defaults.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);

    const args = [_][]const u8{ "hostinger", "--limit=5", "--json" };
    const parsed = (try parseCommand(args[0..])).events;
    try std.testing.expectEqual(app_evidence.ProviderFilter.hostinger, parsed.options.provider);
    try std.testing.expectEqual(@as(i64, 5), parsed.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);

    const flag_args = [_][]const u8{ "--provider", "cloudflare", "--format", "json" };
    const flags = (try parseCommand(flag_args[0..])).events;
    try std.testing.expectEqual(app_evidence.ProviderFilter.cloudflare, flags.options.provider);
    try std.testing.expectEqual(cli_render.RenderFormat.json, flags.format);

    const matrix_args = [_][]const u8{ "matrix", "cloudflare", "--limit=7", "--json" };
    const matrix = (try parseCommand(matrix_args[0..])).matrix;
    try std.testing.expectEqual(app_evidence.ProviderFilter.cloudflare, matrix.options.provider);
    try std.testing.expectEqual(@as(i64, 7), matrix.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, matrix.format);

    const route_args = [_][]const u8{ "routes", "--provider", "hostinger", "--format=json" };
    const routes = (try parseCommand(route_args[0..])).routes;
    try std.testing.expectEqual(app_evidence.ProviderFilter.hostinger, routes.options.provider);
    try std.testing.expectEqual(cli_render.RenderFormat.json, routes.format);

    const coverage_args = [_][]const u8{ "coverage", "cloudflare", "--limit=9", "--json" };
    const coverage = (try parseCommand(coverage_args[0..])).coverage;
    try std.testing.expectEqual(app_evidence.ProviderFilter.cloudflare, coverage.options.provider);
    try std.testing.expectEqual(@as(i64, 9), coverage.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, coverage.format);

    const summary_args = [_][]const u8{ "capture-summary", "hostinger", "--limit=4", "--json" };
    const summary = (try parseCommand(summary_args[0..])).capture_summary;
    try std.testing.expectEqual(app_evidence.ProviderFilter.hostinger, summary.options.provider);
    try std.testing.expectEqual(@as(i64, 4), summary.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, summary.format);

    const all_summary_args = [_][]const u8{ "capture-summary", "hostinger", "--limit=0", "--json" };
    const all_summary = (try parseCommand(all_summary_args[0..])).capture_summary;
    try std.testing.expectEqual(app_evidence.ProviderFilter.hostinger, all_summary.options.provider);
    try std.testing.expectEqual(@as(i64, 0), all_summary.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, all_summary.format);
}

test "evidence parser rejects invalid options" {
    const invalid_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidEvidenceProvider, parseCommand(invalid_provider[0..]));

    const invalid_limit = [_][]const u8{"--limit=-1"};
    try std.testing.expectError(error.InvalidEvidenceLimit, parseCommand(invalid_limit[0..]));

    const unexpected = [_][]const u8{"extra"};
    try std.testing.expectError(error.UnexpectedEvidenceArgument, parseCommand(unexpected[0..]));
}
