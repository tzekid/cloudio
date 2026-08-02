const std = @import("std");
const app_nob_projects = @import("app_nob_projects");
const action_protocol = @import("nob_action_protocol");
const bootstrap = @import("nob_bootstrap");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const nob_id = @import("nob_id");
const source = @import("nob_source");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Plan = db_store.NobPlan;
pub const Run = db_store.NobRun;
pub const Runs = db_store.NobRuns;
pub const RunEvents = db_store.NobRunEvents;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    cloudio_version: []const u8,
};

pub const Approval = struct {
    confirmed: bool = false,
    typed_project_id: ?[]const u8 = null,
};

pub fn plan(
    ctx: Context,
    project_reference: []const u8,
    action_id: []const u8,
    parameters: std.json.Value,
    actor: []const u8,
) !db_store.NobPlan {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const binding = try executableBinding(project);
    const runner_detail = project.runner_detail orelse return error.RunnerMetadataMissing;
    const zig_path = try bootstrap.zigPathFromMetadata(ctx.gpa, runner_detail);
    defer ctx.gpa.free(zig_path);
    try verifyRunner(ctx, binding.runner_path, binding.runner_sha256);
    try requireActionAvailable(ctx, project.id, action_id);

    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, binding.manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    const now = try nowSeconds();
    const plan_id = nob_id.generate(ctx.io, @as(u64, @intCast(now)) * 1000);
    var diagnostics = std.Io.Writer.Allocating.init(ctx.gpa);
    defer diagnostics.deinit();
    var planned = action_protocol.createPlan(
        ctx.io,
        ctx.gpa,
        binding.runner_path,
        zig_path,
        project.root_path,
        binding.manifest_sha256,
        source_state,
        action_id,
        &plan_id,
        parameters,
        .{ .runtime_environment = ctx.config.runtime_environment, .cloudio_version = ctx.cloudio_version },
        &diagnostics.writer,
    ) catch |err| {
        try audit(ctx, "nob.plan", "failed", project.id, action_id, @errorName(err));
        return err;
    };
    defer planned.deinit(ctx.gpa);
    const value = planned.value();
    try ctx.db.nob().insertPlan(.{
        .id = &plan_id,
        .project_id = project.id,
        .action_id = action_id,
        .resource_id = null,
        .input_json = planned.request_json,
        .plan_json = planned.plan_json,
        .plan_sha256 = planned.plan_sha256,
        .manifest_sha256 = binding.manifest_sha256,
        .source_fingerprint = source_state.fingerprint,
        .effect = @tagName(value.effect),
        .confirmation = @tagName(value.confirmation),
        .requested_by = actor,
        .runner_sha256 = binding.runner_sha256,
        .source_revision = source_state.revision,
        .source_dirty = source_state.dirty,
        .created_at = now,
        .expires_at = now + ctx.config.nob_plan_ttl_seconds,
    });
    try audit(ctx, "nob.plan", "ok", project.id, action_id, &plan_id);
    return (try ctx.db.nob().getPlan(ctx.gpa, &plan_id)) orelse error.PlanNotFound;
}

pub fn queue(
    ctx: Context,
    plan_id: []const u8,
    approval: Approval,
    actor: []const u8,
    idempotency_key: ?[]const u8,
) !db_store.NobRun {
    if (idempotency_key) |key| try validateIdempotencyKey(key);
    const now = try nowSeconds();
    _ = try ctx.db.nob().expirePlans(now);
    const stored = (try ctx.db.nob().getPlan(ctx.gpa, plan_id)) orelse return error.PlanNotFound;
    defer stored.deinit(ctx.gpa);
    if (!std.mem.eql(u8, stored.state, "ready") or stored.expires_at <= now) return error.PlanUnavailable;
    const project = (try ctx.db.nob().getProject(ctx.gpa, stored.project_id)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const binding = try executableBinding(project);
    try requireConfirmation(project, stored.confirmation, approval);
    if (!std.mem.eql(u8, binding.manifest_sha256, stored.manifest_sha256) or
        !std.mem.eql(u8, binding.runner_sha256, stored.runner_sha256 orelse return error.PlanBindingMissing))
    {
        return error.PlanBindingChanged;
    }
    try verifyRunner(ctx, binding.runner_path, binding.runner_sha256);
    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, binding.manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    if (!std.mem.eql(u8, source_state.fingerprint, stored.source_fingerprint orelse return error.PlanBindingMissing) or
        source_state.dirty != (stored.source_dirty orelse return error.PlanBindingMissing) or
        !optionalEqual(source_state.revision, stored.source_revision))
    {
        return error.SourceChanged;
    }
    const actual_plan_sha256 = try action_protocol.hashBytes(ctx.gpa, stored.plan_json);
    defer ctx.gpa.free(actual_plan_sha256);
    if (!std.mem.eql(u8, actual_plan_sha256, stored.plan_sha256)) return error.PlanDigestMismatch;
    const manifest_path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, manifest_path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(manifest_bytes);
    var parsed = try action_protocol.validateStoredPlan(
        ctx.gpa,
        manifest_bytes,
        binding.manifest_sha256,
        stored.action_id,
        stored.plan_json,
        source_state,
    );
    defer parsed.deinit();

    var authorizations = std.ArrayList(db_store.NobBrokerAuthorization).empty;
    defer {
        for (authorizations.items) |authorization| if (authorization.metadata_json) |bytes| ctx.gpa.free(bytes);
        authorizations.deinit(ctx.gpa);
    }
    for (parsed.value.broker_requests) |request| try authorizations.append(ctx.gpa, .{
        .authorization_id = request.id,
        .capability = @tagName(request.capability),
        .resource_id = request.resource_id,
        .operation = request.operation,
        .metadata_json = if (request.metadata) |metadata| try stringify(ctx.gpa, metadata) else null,
    });
    const operation_id = nob_id.generate(ctx.io, @as(u64, @intCast(now)) * 1000);
    try ctx.db.nob().queueRun(.{
        .id = &operation_id,
        .plan_id = stored.id,
        .project_id = project.id,
        .action_id = stored.action_id,
        .resource_id = stored.resource_id,
        .effect = stored.effect,
        .requested_by = actor,
        .idempotency_key = idempotency_key,
        .runner_path = binding.runner_path,
        .manifest_sha256 = binding.manifest_sha256,
        .source_fingerprint = source_state.fingerprint,
        .runner_sha256 = binding.runner_sha256,
        .plan_sha256 = stored.plan_sha256,
        .authorizations = authorizations.items,
        .queued_at = now,
    });
    try audit(ctx, "nob.run.queue", "ok", project.id, stored.action_id, &operation_id);
    return (try ctx.db.nob().getRun(ctx.gpa, &operation_id)) orelse error.RunNotFound;
}

pub fn cancel(ctx: Context, operation_id: []const u8, actor: []const u8) !void {
    const now = try nowSeconds();
    if (!try ctx.db.nob().requestRunCancellation(operation_id, now)) return error.RunNotCancelable;
    const detail = try std.fmt.allocPrint(ctx.gpa, "run={s} actor={s}", .{ operation_id, actor });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.run.cancel", "ok", detail);
}

pub fn getRun(ctx: Context, operation_id: []const u8) !?db_store.NobRun {
    return try ctx.db.nob().getRun(ctx.gpa, operation_id);
}

pub fn listRuns(ctx: Context, project_id: ?i64, limit: i64) !db_store.NobRuns {
    return try ctx.db.nob().listRuns(ctx.gpa, project_id, @min(@max(limit, 1), 200));
}

pub fn listEvents(ctx: Context, operation_id: []const u8) !db_store.NobRunEvents {
    return try ctx.db.nob().listRunEvents(ctx.gpa, operation_id);
}

const Binding = struct {
    manifest_sha256: []const u8,
    runner_path: []const u8,
    runner_sha256: []const u8,
};

fn executableBinding(project: db_store.NobProject) !Binding {
    if (project.discovery_state != .valid) return error.ProjectManifestNotValid;
    if (project.trust_state != .trusted) return error.ProjectNotTrusted;
    if (project.runner_state != .ready) return error.RunnerNotReady;
    const manifest_sha256 = project.manifest_sha256 orelse return error.ManifestUnavailable;
    if (!std.mem.eql(u8, manifest_sha256, project.trusted_manifest_sha256 orelse return error.ProjectNotTrusted)) return error.ManifestDigestMismatch;
    return .{
        .manifest_sha256 = manifest_sha256,
        .runner_path = project.runner_path orelse return error.RunnerNotReady,
        .runner_sha256 = project.runner_sha256 orelse return error.RunnerNotReady,
    };
}

fn verifyRunner(ctx: Context, path: []const u8, expected_sha256: []const u8) !void {
    const actual = try action_protocol.hashFile(ctx.io, ctx.gpa, path);
    defer ctx.gpa.free(actual);
    if (!std.mem.eql(u8, actual, expected_sha256)) return error.RunnerDigestMismatch;
}

fn requireActionAvailable(ctx: Context, project_id: i64, action_id: []const u8) !void {
    var actions = try ctx.db.nob().listActions(ctx.gpa, project_id);
    defer actions.deinit(ctx.gpa);
    for (actions.items) |action| {
        if (!std.mem.eql(u8, action.action_id, action_id)) continue;
        if (!action.available) return error.ActionUnavailable;
        return;
    }
    return error.UnknownAction;
}

fn requireConfirmation(project: db_store.NobProject, confirmation: []const u8, approval: Approval) !void {
    if (std.mem.eql(u8, confirmation, "none")) return;
    if (std.mem.eql(u8, confirmation, "review-plan")) {
        if (!approval.confirmed) return error.ConfirmationRequired;
        return;
    }
    if (std.mem.eql(u8, confirmation, "type-project-id")) {
        const declared_id = project.declared_id orelse return error.ConfirmationRequired;
        if (approval.typed_project_id == null or !std.mem.eql(u8, approval.typed_project_id.?, declared_id)) return error.ConfirmationRequired;
        return;
    }
    return error.InvalidConfirmation;
}

fn validateIdempotencyKey(value: []const u8) !void {
    if (value.len == 0 or value.len > 128) return error.InvalidIdempotencyKey;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_' and byte != '.' and byte != ':') return error.InvalidIdempotencyKey;
}

fn projectContext(ctx: Context) app_nob_projects.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

fn optionalEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn stringify(allocator: Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return try output.toOwnedSlice();
}

fn audit(ctx: Context, action: []const u8, status: []const u8, project_id: i64, action_id: []const u8, detail: []const u8) !void {
    const text = try std.fmt.allocPrint(ctx.gpa, "project={d} action={s} detail={s}", .{ project_id, action_id, detail });
    defer ctx.gpa.free(text);
    try ctx.db.insertAudit(action, status, text);
}

fn nowSeconds() !i64 {
    return @intCast(try core_time.currentEpochSeconds());
}
