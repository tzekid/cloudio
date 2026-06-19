const std = @import("std");
const app_coverage = @import("app_coverage");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const RenderFormat = cli_render.RenderFormat;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *app_coverage.DbHandle,
    domains: []const []const u8 = &.{},
    paths: app_coverage.Paths = .{},
};

const SummaryCommand = struct {
    format: RenderFormat = .text,
};

const SourceCommand = struct {
    options: app_coverage.SourceOptions = .{},
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

const FamilyCommand = struct {
    options: app_coverage.FamilyOptions = .{},
    format: RenderFormat = .text,
};

const TypedModelsCommand = struct {
    options: app_coverage.TypedModelOptions = .{},
    format: RenderFormat = .text,
};

const WorkplanCommand = struct {
    options: app_coverage.WorkplanOptions = .{},
    format: RenderFormat = .text,
};

const RouteCommand = struct {
    filter: app_coverage.RouteFilter = .{},
    format: RenderFormat = .text,
};

const CaptureCandidateCommand = struct {
    options: app_coverage.CaptureCandidateOptions = .{},
    format: RenderFormat = .text,
};

const ActualCaptureCommand = struct {
    options: app_coverage.ActualCaptureOptions = .{},
    format: RenderFormat = .text,
};

const DryRunCandidateCommand = struct {
    options: app_coverage.DryRunCandidateOptions = .{},
    format: RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
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

const Command = union(enum) {
    help,
    summary: SummaryCommand,
    sources: SourceCommand,
    tags: TagCommand,
    l1: L1Command,
    gaps: GapCommand,
    levels: LevelCommand,
    level_tags: LevelTagCommand,
    families: FamilyCommand,
    typed_models: TypedModelsCommand,
    workplan: WorkplanCommand,
    routes: RouteCommand,
    capture_candidates: CaptureCandidateCommand,
    actual_captures: ActualCaptureCommand,
    dry_run_candidates: DryRunCandidateCommand,
    plan: []const []const u8,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0) return .{ .summary = .{} };
    if (std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "usage")) return .help;
    if (std.mem.eql(u8, args[0], "summary")) return parseSummary(args[1..]);
    if (std.mem.eql(u8, args[0], "sources") or std.mem.eql(u8, args[0], "source") or std.mem.eql(u8, args[0], "provenance") or std.mem.eql(u8, args[0], "metadata")) {
        return parseSources(args[1..]);
    }
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
    if (std.mem.eql(u8, args[0], "families") or std.mem.eql(u8, args[0], "family-summary") or std.mem.eql(u8, args[0], "family-levels")) {
        return parseFamilies(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "typed-models") or std.mem.eql(u8, args[0], "typed-model-candidates") or std.mem.eql(u8, args[0], "l3-models")) {
        return parseTypedModels(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "workplan") or std.mem.eql(u8, args[0], "slice-plan") or std.mem.eql(u8, args[0], "slices")) {
        return parseWorkplan(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "routes")) {
        return parseRoutes(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "capture-candidates") or std.mem.eql(u8, args[0], "captures") or std.mem.eql(u8, args[0], "capture-plan")) {
        return parseCaptureCandidates(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "actual-captures") or std.mem.eql(u8, args[0], "actual-capture-plan") or std.mem.eql(u8, args[0], "missing-captures") or std.mem.eql(u8, args[0], "actual-workplan")) {
        return parseActualCaptures(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "dry-run-candidates") or std.mem.eql(u8, args[0], "dry-run-plan") or std.mem.eql(u8, args[0], "mutation-candidates")) {
        return parseDryRunCandidates(args[1..]);
    }
    if (std.mem.eql(u8, args[0], "plan")) {
        return .{ .plan = args[1..] };
    }
    return .{ .unknown = args[0] };
}

const CoverageArg = union(enum) {
    no_match,
    matched,
    unknown: []const u8,
};

fn parseCoverageArg(args: []const []const u8, index: *usize, format: *RenderFormat) CoverageArg {
    return switch (cli_render.parseFormatArg(args, index)) {
        .no_match => .no_match,
        .matched => |parsed| blk: {
            format.* = parsed;
            break :blk .matched;
        },
        .missing_value => .{ .unknown = "--format" },
        .invalid_value => |value| .{ .unknown = value },
    };
}

const CoverageValueArg = union(enum) {
    no_match,
    matched: []const u8,
    unknown: []const u8,
};

fn parseCoverageValueArg(args: []const []const u8, index: *usize, comptime names: anytype) CoverageValueArg {
    return switch (cli_args.parseValueArg(args, index, names)) {
        .no_match => .no_match,
        .matched => |value| .{ .matched = value },
        .missing_value => |name| .{ .unknown = name },
    };
}

fn parseCoverageUnsignedArg(args: []const []const u8, index: *usize, comptime names: anytype, value_out: *usize) CoverageArg {
    return switch (parseCoverageValueArg(args, index, names)) {
        .no_match => .no_match,
        .matched => |value| blk: {
            value_out.* = cli_args.parseUnsignedUsize(value, error.InvalidCoverageUnsigned) catch return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageFocusArg(args: []const []const u8, index: *usize, focus: *app_coverage.WorkplanFocus) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{"--focus"})) {
        .no_match => .no_match,
        .matched => |value| blk: {
            focus.* = app_coverage.WorkplanFocus.parse(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseActualCaptureFocusArg(args: []const []const u8, index: *usize, focus: *app_coverage.ActualCaptureFocus) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{"--focus"})) {
        .no_match => .no_match,
        .matched => |value| blk: {
            focus.* = app_coverage.ActualCaptureFocus.parse(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageFamilyArg(args: []const []const u8, index: *usize, family: *app_coverage.WorkplanFamily) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{ "--family", "--control-plane-family", "--focus-family" })) {
        .no_match => .no_match,
        .matched => |value| blk: {
            family.* = app_coverage.WorkplanFamily.parse(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageSupportArg(args: []const []const u8, index: *usize, support: *?app_coverage.SupportFilter) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{"--support"})) {
        .no_match => .no_match,
        .matched => |value| blk: {
            support.* = app_coverage.SupportFilter.parse(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageOperationArg(args: []const []const u8, index: *usize, operation_id: *?[]const u8) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{ "--operation", "--operation-id" })) {
        .no_match => .no_match,
        .matched => |value| blk: {
            operation_id.* = value;
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageMethodArg(args: []const []const u8, index: *usize, method: anytype) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{"--method"})) {
        .no_match => .no_match,
        .matched => |value| blk: {
            method.* = app_coverage.parseRouteMethod(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoveragePathArg(args: []const []const u8, index: *usize, path_template: *?[]const u8) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{ "--path", "--path-template" })) {
        .no_match => .no_match,
        .matched => |value| blk: {
            path_template.* = value;
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageModeArg(args: []const []const u8, index: *usize, mode: *?app_coverage.ModeFilter) CoverageArg {
    return switch (parseCoverageValueArg(args, index, .{"--mode"})) {
        .no_match => .no_match,
        .matched => |value| blk: {
            mode.* = app_coverage.ModeFilter.parse(value) orelse return .{ .unknown = value };
            break :blk .matched;
        },
        .unknown => |value| .{ .unknown = value },
    };
}

fn parseCoverageProviderPositional(arg: []const u8, provider: *app_coverage.ProviderFilter, provider_set: *bool) CoverageArg {
    if (provider_set.*) return .{ .unknown = arg };
    provider.* = app_coverage.ProviderFilter.parse(arg) orelse return .{ .unknown = arg };
    provider_set.* = true;
    return .matched;
}

fn parseCoverageProviderOrTag(arg: []const u8, provider: *app_coverage.ProviderFilter, provider_set: *bool, tag_query: *?[]const u8) CoverageArg {
    if (!provider_set.*) {
        if (app_coverage.ProviderFilter.parse(arg)) |parsed| {
            provider.* = parsed;
            provider_set.* = true;
            return .matched;
        }
    }
    if (tag_query.* == null) {
        tag_query.* = arg;
        return .matched;
    }
    return .{ .unknown = arg };
}

fn parseSummary(args: []const []const u8) Command {
    var command = SummaryCommand{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        return .{ .unknown = arg };
    }
    return .{ .summary = command };
}

fn parseTags(args: []const []const u8) Command {
    var command = TagCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .tags = command };
}

fn parseSources(args: []const []const u8) Command {
    var command = SourceCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .sources = command };
}

fn parseL1(args: []const []const u8) Command {
    var command = L1Command{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .l1 = command };
}

fn parseGaps(args: []const []const u8) Command {
    var command = GapCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .gaps = command };
}

fn parseLevels(args: []const []const u8) Command {
    var command = LevelCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .levels = command };
}

fn parseLevelTags(args: []const []const u8) Command {
    var command = LevelTagCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => unreachable,
        }
    }
    return .{ .level_tags = command };
}

fn parseFamilies(args: []const []const u8) Command {
    var command = FamilyCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--candidate-limit"}, &command.options.candidate_limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFocusArg(args, &index, &command.options.focus)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--control-plane") or std.mem.eql(u8, arg, "--cloudio-relevant")) {
            command.options.focus = .control_plane;
        } else if (std.mem.eql(u8, arg, "--plans") or std.mem.eql(u8, arg, "--include-plans") or std.mem.eql(u8, arg, "--with-plans")) {
            command.options.include_plans = true;
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "--include-candidates") or std.mem.eql(u8, arg, "--with-candidates")) {
            command.options.bundle_candidates = true;
        } else if (app_coverage.WorkplanFocus.parse(arg)) |focus| {
            command.options.focus = focus;
        } else {
            switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .families = command };
}

fn parseTypedModels(args: []const []const u8) Command {
    var command = TypedModelsCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.options.family)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--include-complete") or std.mem.eql(u8, arg, "--include-typed") or std.mem.eql(u8, arg, "--all")) {
            command.options.include_complete = true;
        } else {
            switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .typed_models = command };
}

fn parseWorkplan(args: []const []const u8) Command {
    var command = WorkplanCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--candidate-limit"}, &command.options.candidate_limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFocusArg(args, &index, &command.options.focus)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.options.family)) {
            .matched => {
                if (command.options.family != .all) command.options.focus = .control_plane;
                continue;
            },
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--plans") or std.mem.eql(u8, arg, "--include-plans") or std.mem.eql(u8, arg, "--with-plans")) {
            command.options.include_plans = true;
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "--include-candidates") or std.mem.eql(u8, arg, "--with-candidates")) {
            command.options.bundle_candidates = true;
        } else if (std.mem.eql(u8, arg, "--control-plane") or std.mem.eql(u8, arg, "--cloudio-relevant")) {
            command.options.focus = .control_plane;
        } else if (app_coverage.WorkplanFocus.parse(arg)) |focus| {
            command.options.focus = focus;
        } else if (app_coverage.WorkplanFamily.parse(arg)) |family| {
            command.options.family = family;
            if (command.options.family != .all) command.options.focus = .control_plane;
        } else {
            switch (parseCoverageProviderPositional(arg, &command.options.provider, &provider_set)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .workplan = command };
}

pub const usage_text =
    \\cloudio coverage
    \\
    \\Usage:
    \\  cloudio coverage [summary] [--json|--format json]
    \\  cloudio coverage sources|provenance [all|cloudflare|hostinger] [--json|--format json]
    \\  cloudio coverage tags [all|cloudflare|hostinger] [--json|--format json]
    \\  cloudio coverage l1 [all|cloudflare|hostinger] [--json|--format json]
    \\  cloudio coverage gaps|levels|level-tags [all|cloudflare|hostinger] [--limit <n>] [--json|--format json]
    \\  cloudio coverage families [all|cloudflare|hostinger] [--focus all|control-plane] [--limit <n>] [--bundle] [--plans] [--candidate-limit <n>] [--json|--format json]
    \\  cloudio coverage typed-models [all|cloudflare|hostinger] [--family <family>] [--limit <n>] [--include-complete] [--json|--format json]
    \\  cloudio coverage workplan [all|cloudflare|hostinger] [all|control-plane|<family>] [--focus all|control-plane] [--family <family>] [--limit <n>] [--plans] [--bundle] [--candidate-limit <n>] [--json|--format json]
    \\  cloudio coverage capture-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>] [--plans] [--json|--format json]
    \\  cloudio coverage actual-captures [all|cloudflare|hostinger] [all|control-plane] [tag-query] [--focus all|control-plane] [--family <family>] [--support <status>] [--operation <id>] [--limit <n>] [--plans] [--json|--format json]
    \\  cloudio coverage dry-run-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>] [--plans] [--json|--format json]
    \\  cloudio coverage routes [all|cloudflare|hostinger] [tag-query] [--family <family>] [--operation <id>] [--method <method>] [--path <template>] [--support <status>] [--mode <mode>] [--detail] [--json|--format json]
    \\  cloudio coverage plan <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-content-type <type>]
    \\
    \\Broad-slice shortcuts:
    \\  cloudio coverage sources --json
    \\  cloudio coverage workplan control-plane --limit 0
    \\  cloudio coverage workplan security --plans --json
    \\  cloudio coverage workplan hostinger hostinger-vps --bundle --plans --json
    \\  cloudio coverage actual-captures hostinger --family hostinger-vps --limit 20 --json
    \\  cloudio coverage families control-plane --limit 0 --bundle --plans --json
    \\
    \\Families include accounts, zones, dns, ssl-tls, access, tunnels, rulesets, logs, cache, security, tokens, memberships, billing, domains, hosting, docker, reach, ecommerce, horizons, verification, hostinger-vps, public-keys, custom-pages, healthchecks, and load-balancing.
    \\
;

fn commandHelp(ctx: Context) !void {
    try cli_render.writeAll(ctx.io, usage_text);
}

fn parseRoutes(args: []const []const u8) Command {
    var command = RouteCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageSupportArg(args, &index, &command.filter.support)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.filter.family)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageOperationArg(args, &index, &command.filter.operation_id)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageMethodArg(args, &index, &command.filter.method)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoveragePathArg(args, &index, &command.filter.path_template)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageModeArg(args, &index, &command.filter.mode)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--detail") or std.mem.eql(u8, arg, "--details")) {
            command.filter.detail = true;
        } else {
            switch (parseCoverageProviderOrTag(arg, &command.filter.provider, &provider_set, &command.filter.tag_query)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .routes = command };
}

fn parseCaptureCandidates(args: []const []const u8) Command {
    var command = CaptureCandidateCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageSupportArg(args, &index, &command.options.filter.support)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.options.filter.family)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageOperationArg(args, &index, &command.options.filter.operation_id)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoveragePathArg(args, &index, &command.options.filter.path_template)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--plans") or std.mem.eql(u8, arg, "--include-plans") or std.mem.eql(u8, arg, "--with-plans")) {
            command.options.include_plans = true;
        } else {
            switch (parseCoverageProviderOrTag(arg, &command.options.filter.provider, &provider_set, &command.options.filter.tag_query)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .capture_candidates = command };
}

fn parseActualCaptures(args: []const []const u8) Command {
    var command = ActualCaptureCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageSupportArg(args, &index, &command.options.filter.support)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.options.filter.family)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseActualCaptureFocusArg(args, &index, &command.options.focus)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageOperationArg(args, &index, &command.options.filter.operation_id)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoveragePathArg(args, &index, &command.options.filter.path_template)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--plans") or std.mem.eql(u8, arg, "--include-plans") or std.mem.eql(u8, arg, "--with-plans")) {
            command.options.include_plans = true;
        } else if (std.mem.eql(u8, arg, "--control-plane") or std.mem.eql(u8, arg, "--cloudio-relevant")) {
            command.options.focus = .control_plane;
        } else if (app_coverage.ActualCaptureFocus.parse(arg)) |focus| {
            command.options.focus = focus;
        } else {
            switch (parseCoverageProviderOrTag(arg, &command.options.filter.provider, &provider_set, &command.options.filter.tag_query)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .actual_captures = command };
}

fn parseDryRunCandidates(args: []const []const u8) Command {
    var command = DryRunCandidateCommand{};
    var provider_set = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        switch (parseCoverageArg(args, &index, &command.format)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageUnsignedArg(args, &index, .{"--limit"}, &command.options.limit)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageSupportArg(args, &index, &command.options.filter.support)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageFamilyArg(args, &index, &command.options.filter.family)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageOperationArg(args, &index, &command.options.filter.operation_id)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoverageMethodArg(args, &index, &command.options.filter.method)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        switch (parseCoveragePathArg(args, &index, &command.options.filter.path_template)) {
            .matched => continue,
            .unknown => |value| return .{ .unknown = value },
            .no_match => {},
        }
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--plans") or std.mem.eql(u8, arg, "--include-plans") or std.mem.eql(u8, arg, "--with-plans")) {
            command.options.include_plans = true;
        } else {
            switch (parseCoverageProviderOrTag(arg, &command.options.filter.provider, &provider_set, &command.options.filter.tag_query)) {
                .matched => continue,
                .unknown => |value| return .{ .unknown = value },
                .no_match => unreachable,
            }
        }
    }
    return .{ .dry_run_candidates = command };
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
    const input = parsePlan(ctx.gpa, args) catch |err| {
        std.debug.print("invalid coverage plan arguments: {s}\n", .{@errorName(err)});
        return;
    };
    defer input.deinit(ctx.gpa);

    cli_render.printRendered(ctx.io, ctx.gpa, app_coverage.writeRoutePlanTextFromFiles, .{ ctx.io, ctx.gpa, ctx.paths, input.plan }) catch |err| {
        std.debug.print("coverage plan failed: {s}\n", .{@errorName(err)});
        return;
    };
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

fn parsePlanValueArg(args: []const []const u8, index: *usize, comptime names: anytype) !?[]const u8 {
    return try cli_args.parseRequiredValueArg(args, index, names, error.MissingCoveragePlanOptionValue);
}

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
        if (try parsePlanValueArg(args, &index, .{ "--operation", "--operation-id" })) |value| {
            filter.operation_id = value;
        } else if (try parsePlanValueArg(args, &index, .{"--method"})) |value| {
            filter.method = app_coverage.parseRouteMethod(value) orelse return error.InvalidCoveragePlanMethod;
        } else if (try parsePlanValueArg(args, &index, .{ "--path", "--path-template" })) |value| {
            filter.path_template = value;
        } else if (try parsePlanValueArg(args, &index, .{"--tag"})) |value| {
            filter.tag_query = value;
        } else if (try parsePlanValueArg(args, &index, .{"--support"})) |value| {
            filter.support = app_coverage.SupportFilter.parse(value) orelse return error.InvalidCoveragePlanSupport;
        } else if (try parsePlanValueArg(args, &index, .{"--mode"})) |value| {
            filter.mode = app_coverage.ModeFilter.parse(value) orelse return error.InvalidCoveragePlanMode;
        } else if (try parsePlanValueArg(args, &index, .{ "--path-param", "--param" })) |value| {
            try path_params.append(gpa, try app_coverage.parsePathParamAssignment(value));
        } else if (try parsePlanValueArg(args, &index, .{ "--query-param", "--query" })) |value| {
            try query_params.append(gpa, try app_coverage.parseQueryParamAssignment(value));
        } else if (try parsePlanValueArg(args, &index, .{ "--header-param", "--header" })) |value| {
            try header_params.append(gpa, try app_coverage.parseHeaderParamAssignment(value));
        } else if (cli_args.matches(arg, .{"--body-present"})) {
            body.present = true;
        } else if (try parsePlanValueArg(args, &index, .{ "--body-content-type", "--content-type" })) |value| {
            body.present = true;
            body.content_type = value;
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

    const help_args = [_][]const u8{"help"};
    switch (parseCommand(help_args[0..])) {
        .help => {},
        else => return error.ExpectedCoverageHelp,
    }

    const help_flag_args = [_][]const u8{"--help"};
    switch (parseCommand(help_flag_args[0..])) {
        .help => {},
        else => return error.ExpectedCoverageHelp,
    }

    const summary_args = [_][]const u8{"summary"};
    try std.testing.expectEqual(Command{ .summary = .{} }, parseCommand(summary_args[0..]));

    const summary_json_args = [_][]const u8{ "summary", "--json" };
    try std.testing.expectEqual(Command{ .summary = .{ .format = .json } }, parseCommand(summary_json_args[0..]));

    const default_summary_json_args = [_][]const u8{"--format=json"};
    try std.testing.expectEqual(Command{ .summary = .{ .format = .json } }, parseCommand(default_summary_json_args[0..]));

    const sources_args = [_][]const u8{"sources"};
    switch (parseCommand(sources_args[0..])) {
        .sources => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageSources,
    }

    const hostinger_sources_args = [_][]const u8{ "provenance", "hostinger", "--json" };
    switch (parseCommand(hostinger_sources_args[0..])) {
        .sources => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageSources,
    }

    const cloudflare_metadata_args = [_][]const u8{ "metadata", "cloudflare", "--format", "json" };
    switch (parseCommand(cloudflare_metadata_args[0..])) {
        .sources => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageSources,
    }

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

    const families_args = [_][]const u8{ "families", "cloudflare", "--focus=control-plane", "--limit=7", "--json" };
    switch (parseCommand(families_args[0..])) {
        .families => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(@as(usize, 7), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageFamilies,
    }

    const family_summary_args = [_][]const u8{ "family-summary", "--focus", "all", "--limit", "0" };
    switch (parseCommand(family_summary_args[0..])) {
        .families => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.all, command.options.focus);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageFamilies,
    }

    const focused_families_args = [_][]const u8{ "families", "control-plane", "--limit", "0", "--json" };
    switch (parseCommand(focused_families_args[0..])) {
        .families => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageFamilies,
    }

    const provider_focused_families_args = [_][]const u8{ "families", "hostinger", "control-plane" };
    switch (parseCommand(provider_focused_families_args[0..])) {
        .families => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
        },
        else => return error.ExpectedCoverageFamilies,
    }

    const bundled_families_args = [_][]const u8{ "families", "hostinger", "--bundle", "--plans", "--candidate-limit=3", "--json" };
    switch (parseCommand(bundled_families_args[0..])) {
        .families => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expect(command.options.bundle_candidates);
            try std.testing.expect(command.options.include_plans);
            try std.testing.expectEqual(@as(usize, 3), command.options.candidate_limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageFamilies,
    }

    const typed_models_args = [_][]const u8{ "typed-models", "cloudflare", "--family", "security", "--limit=7", "--include-complete", "--json" };
    switch (parseCommand(typed_models_args[0..])) {
        .typed_models => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.security, command.options.family);
            try std.testing.expectEqual(@as(usize, 7), command.options.limit);
            try std.testing.expect(command.options.include_complete);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageTypedModels,
    }

    const workplan_args = [_][]const u8{ "workplan", "cloudflare", "--limit=6", "--json" };
    switch (parseCommand(workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(@as(usize, 6), command.options.limit);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.all, command.options.focus);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const focused_workplan_args = [_][]const u8{ "slices", "cloudflare", "--focus=control-plane", "--limit", "4" };
    switch (parseCommand(focused_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(@as(usize, 4), command.options.limit);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.all, command.options.family);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const positional_focus_workplan_args = [_][]const u8{ "workplan", "control-plane", "--limit=0", "--json" };
    switch (parseCommand(positional_focus_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.all, command.options.family);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const positional_family_workplan_args = [_][]const u8{ "workplan", "security", "--plans" };
    switch (parseCommand(positional_family_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.security, command.options.family);
            try std.testing.expect(command.options.include_plans);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const provider_family_workplan_args = [_][]const u8{ "workplan", "hostinger", "vps", "--bundle", "--plans", "--json" };
    switch (parseCommand(provider_family_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.hostinger_vps, command.options.family);
            try std.testing.expect(command.options.bundle_candidates);
            try std.testing.expect(command.options.include_plans);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const family_workplan_args = [_][]const u8{ "workplan", "cloudflare", "--family", "security", "--limit=4", "--json" };
    switch (parseCommand(family_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.provider);
            try std.testing.expectEqual(@as(usize, 4), command.options.limit);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.security, command.options.family);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const family_alias_workplan_args = [_][]const u8{ "workplan", "--control-plane-family=hostinger-vps" };
    switch (parseCommand(family_alias_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.hostinger_vps, command.options.family);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const relevant_workplan_args = [_][]const u8{ "workplan", "--cloudio-relevant", "--with-plans", "--bundle", "--candidate-limit=3", "--json" };
    switch (parseCommand(relevant_workplan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.all, command.options.family);
            try std.testing.expect(command.options.include_plans);
            try std.testing.expect(command.options.bundle_candidates);
            try std.testing.expectEqual(@as(usize, 3), command.options.candidate_limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
    }

    const slice_plan_args = [_][]const u8{ "slice-plan", "--limit", "0" };
    switch (parseCommand(slice_plan_args[0..])) {
        .workplan => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.provider);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expectEqual(RenderFormat.text, command.format);
        },
        else => return error.ExpectedCoverageWorkplan,
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

    const capture_candidates_args = [_][]const u8{ "capture-candidates", "cloudflare", "Logs", "--limit=8", "--json" };
    switch (parseCommand(capture_candidates_args[0..])) {
        .capture_candidates => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.filter.provider);
            try std.testing.expectEqualStrings("Logs", command.options.filter.tag_query orelse "");
            try std.testing.expectEqual(@as(usize, 8), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageCaptureCandidates,
    }

    const capture_candidates_support_args = [_][]const u8{ "captures", "--support", "blocked_permission", "--operation=logs-list" };
    switch (parseCommand(capture_candidates_support_args[0..])) {
        .capture_candidates => |command| {
            try std.testing.expectEqual(app_coverage.SupportFilter.blocked_permission, command.options.filter.support.?);
            try std.testing.expectEqualStrings("logs-list", command.options.filter.operation_id orelse "");
        },
        else => return error.ExpectedCoverageCaptureCandidates,
    }

    const capture_candidates_family_args = [_][]const u8{ "capture-plan", "cloudflare", "--family=dns", "--limit", "0", "--plans" };
    switch (parseCommand(capture_candidates_family_args[0..])) {
        .capture_candidates => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.dns, command.options.filter.family);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expect(command.options.include_plans);
        },
        else => return error.ExpectedCoverageCaptureCandidates,
    }

    const actual_captures_args = [_][]const u8{ "actual-captures", "hostinger", "--family", "hostinger-vps", "--limit=10", "--operation", "VPS_getVirtualMachineDetailsV1", "--json" };
    switch (parseCommand(actual_captures_args[0..])) {
        .actual_captures => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, command.options.filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.hostinger_vps, command.options.filter.family);
            try std.testing.expectEqual(app_coverage.ActualCaptureFocus.all, command.options.focus);
            try std.testing.expectEqualStrings("VPS_getVirtualMachineDetailsV1", command.options.filter.operation_id orelse "");
            try std.testing.expectEqual(@as(usize, 10), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageActualCaptures,
    }

    const focused_actual_captures_args = [_][]const u8{ "actual-captures", "control-plane", "--limit=0", "--plans", "--json" };
    switch (parseCommand(focused_actual_captures_args[0..])) {
        .actual_captures => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.all, command.options.filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.all, command.options.filter.family);
            try std.testing.expectEqual(app_coverage.ActualCaptureFocus.control_plane, command.options.focus);
            try std.testing.expectEqual(@as(usize, 0), command.options.limit);
            try std.testing.expect(command.options.include_plans);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageActualCaptures,
    }

    const focused_actual_captures_flag_args = [_][]const u8{ "missing-captures", "--focus=control-plane", "cloudflare", "--family=ssl-tls" };
    switch (parseCommand(focused_actual_captures_flag_args[0..])) {
        .actual_captures => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.ssl_tls, command.options.filter.family);
            try std.testing.expectEqual(app_coverage.ActualCaptureFocus.control_plane, command.options.focus);
        },
        else => return error.ExpectedCoverageActualCaptures,
    }

    const missing_captures_args = [_][]const u8{ "missing-captures", "VPS", "--support=partial", "--plans" };
    switch (parseCommand(missing_captures_args[0..])) {
        .actual_captures => |command| {
            try std.testing.expectEqualStrings("VPS", command.options.filter.tag_query orelse "");
            try std.testing.expectEqual(app_coverage.SupportFilter.partial, command.options.filter.support.?);
            try std.testing.expect(command.options.include_plans);
        },
        else => return error.ExpectedCoverageActualCaptures,
    }

    const dry_run_candidates_args = [_][]const u8{ "dry-run-candidates", "cloudflare", "AI Gateway", "--limit=8", "--json" };
    switch (parseCommand(dry_run_candidates_args[0..])) {
        .dry_run_candidates => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.filter.provider);
            try std.testing.expectEqualStrings("AI Gateway", command.options.filter.tag_query orelse "");
            try std.testing.expectEqual(@as(usize, 8), command.options.limit);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageDryRunCandidates,
    }

    const mutation_candidates_args = [_][]const u8{ "mutation-candidates", "--support", "unsafe_mutation", "--operation=logs-create", "--method=POST" };
    switch (parseCommand(mutation_candidates_args[0..])) {
        .dry_run_candidates => |command| {
            try std.testing.expectEqual(app_coverage.SupportFilter.unsafe_mutation, command.options.filter.support.?);
            try std.testing.expectEqualStrings("logs-create", command.options.filter.operation_id orelse "");
            try std.testing.expectEqual(app_coverage.parseRouteMethod("POST").?, command.options.filter.method.?);
        },
        else => return error.ExpectedCoverageDryRunCandidates,
    }

    const dry_run_candidates_family_args = [_][]const u8{ "dry-run-plan", "cloudflare", "--control-plane-family", "security", "--plans", "--json" };
    switch (parseCommand(dry_run_candidates_family_args[0..])) {
        .dry_run_candidates => |command| {
            try std.testing.expectEqual(app_coverage.ProviderFilter.cloudflare, command.options.filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.security, command.options.filter.family);
            try std.testing.expect(command.options.include_plans);
            try std.testing.expectEqual(RenderFormat.json, command.format);
        },
        else => return error.ExpectedCoverageDryRunCandidates,
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
            try std.testing.expectEqual(app_coverage.WorkplanFamily.all, filter.family);
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

    const family_routes_args = [_][]const u8{ "routes", "hostinger", "--family", "hostinger-vps", "--json" };
    switch (parseCommand(family_routes_args[0..])) {
        .routes => |command| {
            const filter = command.filter;
            try std.testing.expectEqual(app_coverage.ProviderFilter.hostinger, filter.provider);
            try std.testing.expectEqual(app_coverage.WorkplanFamily.hostinger_vps, filter.family);
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
