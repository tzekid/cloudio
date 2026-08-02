const std = @import("std");
const app_nob_actions = @import("app_nob_actions");
const app_database = @import("app_database");
const app_nob_projects = @import("app_nob_projects");
const app_nob_runtime = @import("app_nob_runtime");
const app_nob_secrets = @import("app_nob_secrets");
const app_nob_worker = @import("app_nob_worker");
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

const ActionArgs = struct {
    reference: []const u8,
    action_id: []const u8,
    rest: []const []const u8,
};

const ValueArgs = struct {
    value: []const u8,
    rest: []const []const u8,
};

const ResourceArgs = struct {
    reference: []const u8,
    resource_id: []const u8,
    control_name: []const u8,
    rest: []const []const u8,
};

const SecretBindArgs = struct {
    reference: []const u8,
    secret_id: []const u8,
    source_kind: []const u8,
    source_ref: []const u8,
    rest: []const []const u8,
};

const SecretUnbindArgs = struct {
    reference: []const u8,
    secret_id: []const u8,
    rest: []const []const u8,
};

const Command = union(enum) {
    list: []const []const u8,
    show: ReferenceArgs,
    scan,
    trust: TrustArgs,
    revoke: []const u8,
    prepare: []const u8,
    observe: []const u8,
    plan: ActionArgs,
    execute: ValueArgs,
    resource: ResourceArgs,
    secrets: ReferenceArgs,
    secret_bind: SecretBindArgs,
    secret_unbind: SecretUnbindArgs,
    runs: []const []const u8,
    operation: ValueArgs,
    cancel: []const u8,
    work,
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
        .plan => |value| try commandPlan(ctx, value),
        .execute => |value| try commandExecute(ctx, value),
        .resource => |value| try commandResource(ctx, value),
        .secrets => |value| try commandSecrets(ctx, value.reference, try parseFormat(value.rest)),
        .secret_bind => |value| try commandSecretBind(ctx, value),
        .secret_unbind => |value| try commandSecretUnbind(ctx, value),
        .runs => |rest| try commandRuns(ctx, rest),
        .operation => |value| try commandOperation(ctx, value.value, try parseFormat(value.rest)),
        .cancel => |operation_id| {
            try app_nob_actions.cancel(actionsContext(ctx), operation_id, "local-cli");
            try cli_render.writeAll(ctx.io, "nob run cancellation requested\n");
        },
        .work => {
            const worked = try app_nob_worker.processNext(workerContext(ctx));
            try cli_render.writeAll(ctx.io, if (worked) "nob worker processed one run\n" else "nob worker queue is empty\n");
        },
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

fn commandSecrets(ctx: Context, reference: []const u8, format: cli_render.RenderFormat) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    if (format == .json) {
        try app_nob_secrets.writeJson(secretsContext(ctx), reference, &out.writer);
    } else {
        try app_nob_secrets.writeText(secretsContext(ctx), reference, &out.writer);
    }
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandSecretBind(ctx: Context, args: SecretBindArgs) !void {
    if (args.rest.len != 1 or !std.mem.eql(u8, args.rest[0], "--yes")) return error.ConfirmationRequired;
    try app_nob_secrets.bind(
        secretsContext(ctx),
        args.reference,
        args.secret_id,
        args.source_kind,
        args.source_ref,
        "local-cli",
    );
    try cli_render.writeAll(ctx.io, "nob secret binding saved; source reference and value are hidden\n");
}

fn commandSecretUnbind(ctx: Context, args: SecretUnbindArgs) !void {
    if (args.rest.len != 1 or !std.mem.eql(u8, args.rest[0], "--yes")) return error.ConfirmationRequired;
    try app_nob_secrets.unbind(secretsContext(ctx), args.reference, args.secret_id, "local-cli");
    try cli_render.writeAll(ctx.io, "nob secret binding removed\n");
}

fn commandResource(ctx: Context, args: ResourceArgs) !void {
    if (!ctx.config.nob_enabled) return error.NobDisabled;
    var confirmed = false;
    var follow = false;
    var json = false;
    for (args.rest) |argument| {
        if (std.mem.eql(u8, argument, "--yes")) {
            confirmed = true;
        } else if (std.mem.eql(u8, argument, "--follow")) {
            follow = true;
        } else if (std.mem.eql(u8, argument, "--json") or std.mem.eql(u8, argument, "--format=json")) {
            json = true;
        } else return error.UnexpectedNobResourceArgument;
    }
    if (!confirmed) return error.ConfirmationRequired;
    var planned = try app_nob_actions.planResourceControl(
        actionsContext(ctx),
        args.reference,
        args.resource_id,
        args.control_name,
        "local-cli",
    );
    defer planned.deinit(ctx.gpa);
    var queued = try app_nob_actions.queueResourceControl(
        actionsContext(ctx),
        args.reference,
        args.resource_id,
        args.control_name,
        planned.id,
        .{ .confirmed = true },
        "local-cli",
        null,
    );
    defer queued.deinit(ctx.gpa);
    if (follow) {
        while (std.mem.eql(u8, queued.state, "queued") or std.mem.eql(u8, queued.state, "running")) {
            _ = try app_nob_worker.processNext(workerContext(ctx));
            const refreshed = (try app_nob_actions.getRun(actionsContext(ctx), queued.id)) orelse return error.RunNotFound;
            queued.deinit(ctx.gpa);
            queued = refreshed;
        }
    }
    try writeRun(ctx, queued, json);
}

fn commandPlan(ctx: Context, args: ActionArgs) !void {
    if (!ctx.config.nob_enabled) return error.NobDisabled;
    var parameters: std.json.ObjectMap = .empty;
    defer parameters.deinit(ctx.gpa);
    var json = false;
    var index: usize = 0;
    while (index < args.rest.len) : (index += 1) {
        const argument = args.rest[index];
        if (std.mem.eql(u8, argument, "--json") or std.mem.eql(u8, argument, "--format=json")) {
            json = true;
            continue;
        }
        var encoded: []const u8 = undefined;
        if (std.mem.eql(u8, argument, "--param")) {
            index += 1;
            if (index >= args.rest.len) return error.MissingNobParameter;
            encoded = args.rest[index];
        } else if (std.mem.startsWith(u8, argument, "--param=")) {
            encoded = argument["--param=".len..];
        } else return error.UnexpectedNobPlanArgument;
        const separator = std.mem.indexOfScalar(u8, encoded, '=') orelse return error.InvalidNobParameter;
        const name = encoded[0..separator];
        if (name.len == 0 or parameters.contains(name)) return error.InvalidNobParameter;
        try parameters.put(ctx.gpa, name, parseParameterValue(encoded[separator + 1 ..]));
    }
    var planned = try app_nob_actions.plan(
        actionsContext(ctx),
        args.reference,
        args.action_id,
        .{ .object = parameters },
        "local-cli",
    );
    defer planned.deinit(ctx.gpa);
    if (json) return writePlanJson(ctx, planned);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "Plan {s}\nProject: {d}\nAction: {s}\nEffect: {s}\nConfirmation: {s}\nExpires: {d}\n\n{s}",
        .{ planned.id, planned.project_id, planned.action_id, planned.effect, planned.confirmation, planned.expires_at, planned.plan_json },
    );
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandExecute(ctx: Context, args: ValueArgs) !void {
    if (!ctx.config.nob_enabled) return error.NobDisabled;
    var approval = app_nob_actions.Approval{};
    var idempotency_key: ?[]const u8 = null;
    var follow = false;
    var json = false;
    var index: usize = 0;
    while (index < args.rest.len) : (index += 1) {
        const argument = args.rest[index];
        if (std.mem.eql(u8, argument, "--yes")) {
            approval.confirmed = true;
        } else if (std.mem.eql(u8, argument, "--follow")) {
            follow = true;
        } else if (std.mem.eql(u8, argument, "--json") or std.mem.eql(u8, argument, "--format=json")) {
            json = true;
        } else if (std.mem.eql(u8, argument, "--confirm-project")) {
            index += 1;
            if (index >= args.rest.len) return error.MissingConfirmProject;
            approval.typed_project_id = args.rest[index];
        } else if (std.mem.startsWith(u8, argument, "--confirm-project=")) {
            approval.typed_project_id = argument["--confirm-project=".len..];
        } else if (std.mem.eql(u8, argument, "--idempotency-key")) {
            index += 1;
            if (index >= args.rest.len) return error.MissingIdempotencyKey;
            idempotency_key = args.rest[index];
        } else if (std.mem.startsWith(u8, argument, "--idempotency-key=")) {
            idempotency_key = argument["--idempotency-key=".len..];
        } else return error.UnexpectedNobRunArgument;
    }
    var queued = try app_nob_actions.queue(actionsContext(ctx), args.value, approval, "local-cli", idempotency_key);
    defer queued.deinit(ctx.gpa);
    if (follow) {
        while (std.mem.eql(u8, queued.state, "queued") or std.mem.eql(u8, queued.state, "running")) {
            _ = try app_nob_worker.processNext(workerContext(ctx));
            const refreshed = (try app_nob_actions.getRun(actionsContext(ctx), queued.id)) orelse return error.RunNotFound;
            queued.deinit(ctx.gpa);
            queued = refreshed;
        }
    }
    try writeRun(ctx, queued, json);
}

fn commandRuns(ctx: Context, args: []const []const u8) !void {
    var format: cli_render.RenderFormat = .text;
    var project_id: ?i64 = null;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--json") or std.mem.eql(u8, args[index], "--format=json")) {
            format = .json;
            continue;
        }
        if (project_id != null) return error.UnexpectedNobRunsArgument;
        const project = (try app_nob_projects.find(appContext(ctx), args[index])) orelse return error.ProjectNotFound;
        defer project.deinit(ctx.gpa);
        project_id = project.id;
    }
    var runs = try app_nob_actions.listRuns(actionsContext(ctx), project_id, 100);
    defer runs.deinit(ctx.gpa);
    if (format == .json) return writeRunsJson(ctx, runs.items);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    for (runs.items) |item| try out.writer.print(
        "{s}  project={d}  action={s}  state={s}  queued={d}  {s}\n",
        .{ item.id, item.project_id, item.action_id, item.state, item.queued_at, item.summary orelse "" },
    );
    if (runs.items.len == 0) try out.writer.writeAll("no nob runs\n");
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandOperation(ctx: Context, operation_id: []const u8, format: cli_render.RenderFormat) !void {
    const run_value = (try app_nob_actions.getRun(actionsContext(ctx), operation_id)) orelse return error.RunNotFound;
    defer run_value.deinit(ctx.gpa);
    try writeRun(ctx, run_value, format == .json);
    if (format == .json) return;
    var events = try app_nob_actions.listEvents(actionsContext(ctx), operation_id);
    defer events.deinit(ctx.gpa);
    if (events.items.len == 0) return;
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.writeAll("Events:\n");
    for (events.items) |event| try out.writer.print("  {d}: {s}\n", .{ event.seq, event.payload_json });
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn writePlanJson(ctx: Context, planned: app_nob_actions.Plan) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, planned.plan_json, .{});
    defer parsed.deinit();
    const View = struct {
        id: []const u8,
        project_id: i64,
        action_id: []const u8,
        effect: []const u8,
        confirmation: []const u8,
        state: []const u8,
        expires_at: i64,
        plan: std.json.Value,
    };
    try writeJson(ctx, View{
        .id = planned.id,
        .project_id = planned.project_id,
        .action_id = planned.action_id,
        .effect = planned.effect,
        .confirmation = planned.confirmation,
        .state = planned.state,
        .expires_at = planned.expires_at,
        .plan = parsed.value,
    });
}

fn writeRunsJson(ctx: Context, runs: []const app_nob_actions.Run) !void {
    try writeJson(ctx, runs);
}

fn writeRun(ctx: Context, value: app_nob_actions.Run, json: bool) !void {
    if (json) return writeJson(ctx, value);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "Run {s}\nProject: {d}\nAction: {s}\nState: {s}\nOutcome: {s}\nSummary: {s}\n",
        .{ value.id, value.project_id, value.action_id, value.state, value.outcome orelse "-", value.summary orelse "-" },
    );
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn writeJson(ctx: Context, value: anytype) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn parseParameterValue(value: []const u8) std.json.Value {
    if (std.mem.eql(u8, value, "true")) return .{ .bool = true };
    if (std.mem.eql(u8, value, "false")) return .{ .bool = false };
    if (std.fmt.parseInt(i64, value, 10)) |integer| return .{ .integer = integer } else |_| {}
    return .{ .string = value };
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

fn actionsContext(ctx: Context) app_nob_actions.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .cloudio_version = core_version.value };
}

fn workerContext(ctx: Context) app_nob_worker.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .cloudio_version = core_version.value };
}

fn secretsContext(ctx: Context) app_nob_secrets.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config };
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
    if (std.mem.eql(u8, args[0], "plan")) {
        if (args.len < 3) return .{ .missing = "plan" };
        return .{ .plan = .{ .reference = args[1], .action_id = args[2], .rest = args[3..] } };
    }
    if (std.mem.eql(u8, args[0], "run")) {
        if (args.len < 2) return .{ .missing = "run" };
        return .{ .execute = .{ .value = args[1], .rest = args[2..] } };
    }
    if (std.mem.eql(u8, args[0], "resource")) {
        if (args.len < 4) return .{ .missing = "resource" };
        return .{ .resource = .{
            .reference = args[1],
            .resource_id = args[2],
            .control_name = args[3],
            .rest = args[4..],
        } };
    }
    if (std.mem.eql(u8, args[0], "secrets")) {
        if (args.len < 2) return .{ .missing = "secrets" };
        return .{ .secrets = .{ .reference = args[1], .rest = args[2..] } };
    }
    if (std.mem.eql(u8, args[0], "secret-bind")) {
        if (args.len < 5) return .{ .missing = "secret-bind" };
        return .{ .secret_bind = .{
            .reference = args[1],
            .secret_id = args[2],
            .source_kind = args[3],
            .source_ref = args[4],
            .rest = args[5..],
        } };
    }
    if (std.mem.eql(u8, args[0], "secret-unbind")) {
        if (args.len < 3) return .{ .missing = "secret-unbind" };
        return .{ .secret_unbind = .{
            .reference = args[1],
            .secret_id = args[2],
            .rest = args[3..],
        } };
    }
    if (std.mem.eql(u8, args[0], "runs")) return .{ .runs = args[1..] };
    if (std.mem.eql(u8, args[0], "operation")) {
        if (args.len < 2) return .{ .missing = "operation" };
        return .{ .operation = .{ .value = args[1], .rest = args[2..] } };
    }
    if (std.mem.eql(u8, args[0], "cancel")) {
        if (args.len < 2) return .{ .missing = "cancel" };
        return .{ .cancel = args[1] };
    }
    if (std.mem.eql(u8, args[0], "work")) return .work;
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

test "nob secret commands retain typed source arguments" {
    const list_args = [_][]const u8{ "secrets", "dev.example.service", "--json" };
    switch (parseCommand(&list_args)) {
        .secrets => |value| {
            try std.testing.expectEqualStrings("dev.example.service", value.reference);
            try std.testing.expectEqual(@as(usize, 1), value.rest.len);
        },
        else => return error.ExpectedSecrets,
    }
    const bind_args = [_][]const u8{ "secret-bind", "dev.example.service", "database-token", "file", "/run/secrets/database", "--yes" };
    switch (parseCommand(&bind_args)) {
        .secret_bind => |value| {
            try std.testing.expectEqualStrings("database-token", value.secret_id);
            try std.testing.expectEqualStrings("file", value.source_kind);
            try std.testing.expectEqualStrings("/run/secrets/database", value.source_ref);
            try std.testing.expectEqualStrings("--yes", value.rest[0]);
        },
        else => return error.ExpectedSecretBind,
    }
}
