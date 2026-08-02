const std = @import("std");
const app_database = @import("app_database");
const app_nob_projects = @import("app_nob_projects");
const app_nob_runtime = @import("app_nob_runtime");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const core_config = @import("core_config");
const core_version = @import("core_version");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *app_database.Db,
    config: core_config.Config,
};

const ReferenceArgs = struct {
    reference: []const u8,
    rest: []const []const u8,
};

const TrustArgs = struct {
    reference: []const u8,
    digest: []const u8,
};

const Command = union(enum) {
    list: []const []const u8,
    show: ReferenceArgs,
    scan,
    trust: TrustArgs,
    revoke: []const u8,
    prepare: []const u8,
    observe: []const u8,
    missing: []const u8,
    unknown: []const u8,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (parseCommand(args)) {
        .list => |rest| try renderList(ctx, try parseFormat(rest)),
        .show => |show_args| try renderShow(ctx, show_args.reference, try parseFormat(show_args.rest)),
        .scan => try commandScan(ctx),
        .trust => |trust_args| {
            try app_nob_projects.trust(appContext(ctx), trust_args.reference, trust_args.digest, "local-cli");
            try cli_render.writeAll(ctx.io, "nob project trusted\n");
        },
        .revoke => |reference| {
            try app_nob_projects.revoke(appContext(ctx), reference, "local-cli");
            try cli_render.writeAll(ctx.io, "nob project trust revoked\n");
        },
        .prepare => |reference| try commandRuntime(ctx, "prepare", reference),
        .observe => |reference| try commandRuntime(ctx, "observe", reference),
        .missing => |command| {
            std.debug.print("nob {s} is missing required arguments\n", .{command});
            return error.MissingNobArgument;
        },
        .unknown => |command| {
            std.debug.print("unknown nob command: {s}\n", .{command});
            return error.UnknownNobCommand;
        },
    }
}

fn renderList(ctx: Context, format: cli_render.RenderFormat) !void {
    try cli_render.printFormatted(
        ctx.io,
        ctx.gpa,
        format,
        app_nob_projects.writeListText,
        app_nob_projects.writeListJson,
        .{appContext(ctx)},
    );
}

fn renderShow(ctx: Context, reference: []const u8, format: cli_render.RenderFormat) !void {
    try cli_render.printFormatted(
        ctx.io,
        ctx.gpa,
        format,
        app_nob_projects.writeShowText,
        app_nob_projects.writeShowJson,
        .{ appContext(ctx), reference },
    );
}

fn commandScan(ctx: Context) !void {
    const result = try app_nob_projects.scan(appContext(ctx), ctx.io, ctx.config.projects_root, ctx.config.nob_scan_depth);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "nob scan complete: seen={d} valid={d} invalid={d} candidates={d} conflicts={d} missing={d}\n",
        .{ result.projects_seen, result.valid, result.invalid, result.candidates, result.conflicts, result.missing },
    );
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandRuntime(ctx: Context, operation: []const u8, reference: []const u8) !void {
    if (!ctx.config.nob_enabled) return error.NobDisabled;
    const runtime_ctx: app_nob_runtime.Context = .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .cloudio_version = core_version.value,
    };
    const outcome = if (std.mem.eql(u8, operation, "prepare"))
        try app_nob_runtime.prepareAndObserve(runtime_ctx, reference)
    else
        try app_nob_runtime.observe(runtime_ctx, reference);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "nob {s} complete: project={d} status={s} runner={s}\n",
        .{ operation, outcome.project_id, @tagName(outcome.status), if (outcome.runner_reused) "reused" else "built" },
    );
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn appContext(ctx: Context) app_nob_projects.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

fn parseCommand(args: []const []const u8) Command {
    if (args.len == 0) return .{ .list = &.{} };
    if (std.mem.eql(u8, args[0], "list")) return .{ .list = args[1..] };
    if (std.mem.eql(u8, args[0], "show")) {
        if (args.len < 2) return .{ .missing = "show" };
        return .{ .show = .{ .reference = args[1], .rest = args[2..] } };
    }
    if (std.mem.eql(u8, args[0], "scan")) return .scan;
    if (std.mem.eql(u8, args[0], "trust")) {
        if (args.len < 3) return .{ .missing = "trust" };
        return .{ .trust = .{ .reference = args[1], .digest = args[2] } };
    }
    if (std.mem.eql(u8, args[0], "revoke")) {
        if (args.len < 2) return .{ .missing = "revoke" };
        return .{ .revoke = args[1] };
    }
    if (std.mem.eql(u8, args[0], "prepare")) {
        if (args.len < 2) return .{ .missing = "prepare" };
        return .{ .prepare = args[1] };
    }
    if (std.mem.eql(u8, args[0], "observe")) {
        if (args.len < 2) return .{ .missing = "observe" };
        return .{ .observe = args[1] };
    }
    return .{ .unknown = args[0] };
}

fn parseFormat(args: []const []const u8) !cli_render.RenderFormat {
    return try cli_args.parseFormatOnly(args, error.UnexpectedNobFormatArgument);
}

test "nob command parser requires an exact digest for trust" {
    const empty = [_][]const u8{};
    switch (parseCommand(empty[0..])) {
        .list => {},
        else => return error.ExpectedList,
    }

    const trust_args = [_][]const u8{ "trust", "dev.example.service", "abcd" };
    switch (parseCommand(trust_args[0..])) {
        .trust => |value| {
            try std.testing.expectEqualStrings("dev.example.service", value.reference);
            try std.testing.expectEqualStrings("abcd", value.digest);
        },
        else => return error.ExpectedTrust,
    }

    const missing_args = [_][]const u8{ "trust", "dev.example.service" };
    switch (parseCommand(missing_args[0..])) {
        .missing => |name| try std.testing.expectEqualStrings("trust", name),
        else => return error.ExpectedMissing,
    }
}
