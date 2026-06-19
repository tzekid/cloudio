const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_coverage_parse = @import("cli_coverage_parse");
const cli_render = @import("cli_render");
const cli_route_request = @import("cli_route_request");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const RenderFormat = cli_coverage_parse.RenderFormat;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *app_coverage.DbHandle,
    domains: []const []const u8 = &.{},
    paths: app_coverage.Paths = .{},
};

const SummaryCommand = cli_coverage_parse.SummaryCommand;
const SourceCommand = cli_coverage_parse.SourceCommand;
const TagCommand = cli_coverage_parse.TagCommand;
const GapCommand = cli_coverage_parse.GapCommand;
const LevelCommand = cli_coverage_parse.LevelCommand;
const L1Command = cli_coverage_parse.L1Command;
const LevelTagCommand = cli_coverage_parse.LevelTagCommand;
const FamilyCommand = cli_coverage_parse.FamilyCommand;
const TypedModelsCommand = cli_coverage_parse.TypedModelsCommand;
const WorkplanCommand = cli_coverage_parse.WorkplanCommand;
const RouteCommand = cli_coverage_parse.RouteCommand;
const CaptureCandidateCommand = cli_coverage_parse.CaptureCandidateCommand;
const ActualCaptureCommand = cli_coverage_parse.ActualCaptureCommand;
const DryRunCandidateCommand = cli_coverage_parse.DryRunCandidateCommand;

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (cli_coverage_parse.parseCommand(args)) {
        .help => try commandHelp(ctx),
        .summary => |command| try commandSummary(ctx, command),
        .sources => |command| try commandSources(ctx, command),
        .tags => |command| try commandTags(ctx, command),
        .l1 => |filter| try commandL1(ctx, filter),
        .gaps => |command| try commandGaps(ctx, command),
        .levels => |command| try commandLevels(ctx, command),
        .level_tags => |command| try commandLevelTags(ctx, command),
        .families => |command| try commandFamilies(ctx, command),
        .typed_models => |command| try commandTypedModels(ctx, command),
        .workplan => |command| try commandWorkplan(ctx, command),
        .routes => |command| try commandRoutes(ctx, command),
        .capture_candidates => |command| try commandCaptureCandidates(ctx, command),
        .actual_captures => |command| try commandActualCaptures(ctx, command),
        .dry_run_candidates => |command| try commandDryRunCandidates(ctx, command),
        .plan => |plan_args| try commandPlan(ctx, plan_args),
        .unknown => |name| std.debug.print("unknown coverage command: {s}\n", .{name}),
    }
}

fn commandHelp(ctx: Context) !void {
    try cli_render.writeAll(ctx.io, cli_coverage_parse.usage_text);
}

fn commandSummary(ctx: Context, command: SummaryCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeTextFromFiles, app_coverage.writeJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths });
}

fn commandSources(ctx: Context, command: SourceCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeSourcesTextFromFiles, app_coverage.writeSourcesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandTags(ctx: Context, command: TagCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeTagsTextFromFiles, app_coverage.writeTagsJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.provider });
}

fn commandL1(ctx: Context, command: L1Command) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeL1AuditTextFromFiles, app_coverage.writeL1AuditJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.provider });
}

fn commandGaps(ctx: Context, command: GapCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeGapsTextFromFiles, app_coverage.writeGapsJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandLevels(ctx: Context, command: LevelCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeLevelsTextFromFiles, app_coverage.writeLevelsJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.provider });
}

fn commandLevelTags(ctx: Context, command: LevelTagCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeLevelTagsTextFromFiles, app_coverage.writeLevelTagsJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandFamilies(ctx: Context, command: FamilyCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeFamiliesTextFromFiles, app_coverage.writeFamiliesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandTypedModels(ctx: Context, command: TypedModelsCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeTypedModelsTextFromFiles, app_coverage.writeTypedModelsJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandWorkplan(ctx: Context, command: WorkplanCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeWorkplanTextFromFiles, app_coverage.writeWorkplanJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandRoutes(ctx: Context, command: RouteCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeRoutesTextFromFiles, app_coverage.writeRoutesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.filter });
}

fn commandCaptureCandidates(ctx: Context, command: CaptureCandidateCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeCaptureCandidatesTextFromFiles, app_coverage.writeCaptureCandidatesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandActualCaptures(ctx: Context, command: ActualCaptureCommand) !void {
    var options = command.options;
    options.configured_domains = ctx.domains;
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeActualCapturesTextFromFiles, app_coverage.writeActualCapturesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, ctx.db, options });
}

fn commandDryRunCandidates(ctx: Context, command: DryRunCandidateCommand) !void {
    try cli_render.printFormatted(ctx.io, ctx.gpa, command.format, app_coverage.writeDryRunCandidatesTextFromFiles, app_coverage.writeDryRunCandidatesJsonFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, command.options });
}

fn commandPlan(ctx: Context, args: []const []const u8) !void {
    const input = cli_route_request.parsePlan(ctx.gpa, args) catch |err| {
        std.debug.print("invalid coverage plan arguments: {s}\n", .{@errorName(err)});
        return;
    };
    defer input.deinit(ctx.gpa);

    cli_render.printRendered(ctx.io, ctx.gpa, app_coverage.writeRoutePlanTextFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, input.plan }) catch |err| {
        std.debug.print("coverage plan failed: {s}\n", .{@errorName(err)});
        return;
    };
}
