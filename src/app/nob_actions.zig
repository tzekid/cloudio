const std = @import("std");
const app_nob_projects = @import("app_nob_projects");
const app_nob_secrets = @import("app_nob_secrets");
const action_protocol = @import("nob_action_protocol");
const bootstrap = @import("nob_bootstrap");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const nob_id = @import("nob_id");
const resource_control = @import("nob_resource_control");
const source = @import("nob_source");
const systemd = @import("nob_systemd");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Plan = db_store.NobPlan;
pub const Run = db_store.NobRun;
pub const Runs = db_store.NobRuns;
pub const RunEvents = db_store.NobRunEvents;
pub const RunEvent = db_store.NobRunEvent;
pub const Artifacts = db_store.NobArtifacts;

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
    try requireActionAvailable(ctx, project.id, action_id);
    const runner_detail = project.runner_detail orelse return error.RunnerMetadataMissing;
    const zig_path = try bootstrap.zigPathFromMetadata(ctx.gpa, runner_detail);
    defer ctx.gpa.free(zig_path);
    try verifyRunner(ctx, binding.runner_path, binding.runner_sha256);
    var manifest_document = try loadManifest(ctx, project.root_path, binding.manifest_sha256);
    defer manifest_document.deinit();
    var resolved_secrets = try app_nob_secrets.resolve(secretContext(ctx), project.id, manifest_document.value());
    defer resolved_secrets.deinit(ctx.gpa);
    try app_nob_secrets.requireForAction(&resolved_secrets, manifest_document.value(), action_id);
    const redaction_values = try resolved_secrets.redactionValues(ctx.gpa);
    defer ctx.gpa.free(redaction_values);

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
        .{
            .runtime_environment = ctx.config.runtime_environment,
            .cloudio_version = ctx.cloudio_version,
            .available_secrets = resolved_secrets.available_csv,
            .redaction_values = redaction_values,
        },
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

pub fn planResourceControl(
    ctx: Context,
    project_reference: []const u8,
    resource_id: []const u8,
    control_name: []const u8,
    actor: []const u8,
) !db_store.NobPlan {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const binding = try executableBinding(project);
    try verifyRunner(ctx, binding.runner_path, binding.runner_sha256);
    const manifest_path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, manifest_path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(ctx.gpa, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, manifest_document.sha256Hex(&digest_buffer), binding.manifest_sha256)) return error.ManifestDigestMismatch;
    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, binding.manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    const now = try nowSeconds();
    const plan_id = nob_id.generate(ctx.io, @as(u64, @intCast(now)) * 1000);
    const planned = try resource_control.create(
        ctx.gpa,
        manifest_document.value(),
        binding.manifest_sha256,
        source_state,
        resource_id,
        control_name,
    );
    defer planned.deinit(ctx.gpa);
    if (!ctx.config.nob_allow_system_mutation) return error.SystemMutationDisabled;
    try ctx.db.nob().insertPlan(.{
        .id = &plan_id,
        .project_id = project.id,
        .action_id = planned.action_id,
        .resource_id = resource_id,
        .input_json = "{}",
        .plan_json = planned.plan_json,
        .plan_sha256 = planned.plan_sha256,
        .manifest_sha256 = binding.manifest_sha256,
        .source_fingerprint = source_state.fingerprint,
        .effect = "runtime-change",
        .confirmation = "review-plan",
        .requested_by = actor,
        .runner_sha256 = binding.runner_sha256,
        .source_revision = source_state.revision,
        .source_dirty = source_state.dirty,
        .created_at = now,
        .expires_at = now + ctx.config.nob_plan_ttl_seconds,
    });
    try audit(ctx, "nob.resource.plan", "ok", project.id, planned.action_id, &plan_id);
    return (try ctx.db.nob().getPlan(ctx.gpa, &plan_id)) orelse error.PlanNotFound;
}

pub fn queue(
    ctx: Context,
    plan_id: []const u8,
    approval: Approval,
    actor: []const u8,
    idempotency_key: ?[]const u8,
) !db_store.NobRun {
    return queueBound(ctx, plan_id, approval, actor, idempotency_key, null, null, null);
}

pub fn queueAction(
    ctx: Context,
    project_reference: []const u8,
    action_id: []const u8,
    plan_id: []const u8,
    approval: Approval,
    actor: []const u8,
    idempotency_key: ?[]const u8,
) !db_store.NobRun {
    const expected = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer expected.deinit(ctx.gpa);
    return queueBound(ctx, plan_id, approval, actor, idempotency_key, expected.id, action_id, null);
}

pub fn queueResourceControl(
    ctx: Context,
    project_reference: []const u8,
    resource_id: []const u8,
    control_name: []const u8,
    plan_id: []const u8,
    approval: Approval,
    actor: []const u8,
    idempotency_key: ?[]const u8,
) !db_store.NobRun {
    const expected = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer expected.deinit(ctx.gpa);
    const expected_action = try resource_control.actionId(ctx.gpa, resource_id, control_name);
    defer ctx.gpa.free(expected_action);
    return queueBound(ctx, plan_id, approval, actor, idempotency_key, expected.id, expected_action, resource_id);
}

fn queueBound(
    ctx: Context,
    plan_id: []const u8,
    approval: Approval,
    actor: []const u8,
    idempotency_key: ?[]const u8,
    expected_project_id: ?i64,
    expected_action_id: ?[]const u8,
    expected_resource_id: ?[]const u8,
) !db_store.NobRun {
    if (idempotency_key) |key| try validateIdempotencyKey(key);
    const now = try nowSeconds();
    _ = try ctx.db.nob().expirePlans(now);
    const stored = (try ctx.db.nob().getPlan(ctx.gpa, plan_id)) orelse return error.PlanNotFound;
    defer stored.deinit(ctx.gpa);
    if (!std.mem.eql(u8, stored.state, "ready") or stored.expires_at <= now) return error.PlanUnavailable;
    if (expected_project_id) |expected| if (stored.project_id != expected) return error.PlanRouteMismatch;
    if (expected_action_id) |expected| if (!std.mem.eql(u8, stored.action_id, expected)) return error.PlanRouteMismatch;
    if (expected_resource_id) |expected| {
        if (stored.resource_id == null or !std.mem.eql(u8, stored.resource_id.?, expected)) return error.PlanRouteMismatch;
    }
    if (!std.mem.eql(u8, stored.requested_by, actor)) return error.PlanActorMismatch;
    const project = (try ctx.db.nob().getProject(ctx.gpa, stored.project_id)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const binding = try executableBinding(project);
    try requireConfirmation(project, stored.confirmation, approval);
    if (!std.mem.eql(u8, binding.manifest_sha256, stored.manifest_sha256) or
        !std.mem.eql(u8, binding.runner_sha256, stored.runner_sha256 orelse return error.PlanBindingMissing))
    {
        try ctx.db.nob().invalidatePlan(stored.id);
        return error.PlanBindingChanged;
    }
    try verifyRunner(ctx, binding.runner_path, binding.runner_sha256);
    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, binding.manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    if (!std.mem.eql(u8, source_state.fingerprint, stored.source_fingerprint orelse return error.PlanBindingMissing) or
        source_state.dirty != (stored.source_dirty orelse return error.PlanBindingMissing) or
        !optionalEqual(source_state.revision, stored.source_revision))
    {
        try ctx.db.nob().invalidatePlan(stored.id);
        return error.SourceChanged;
    }
    const actual_plan_sha256 = try action_protocol.hashBytes(ctx.gpa, stored.plan_json);
    defer ctx.gpa.free(actual_plan_sha256);
    if (!std.mem.eql(u8, actual_plan_sha256, stored.plan_sha256)) return error.PlanDigestMismatch;
    const manifest_path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, manifest_path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(ctx.gpa, manifest_bytes);
    defer manifest_document.deinit();
    var parsed = if (stored.resource_id) |resource_id| direct: {
        const control_name = resource_control.controlFromActionId(stored.action_id, resource_id) orelse return error.InvalidResourcePlan;
        break :direct try resource_control.validate(
            ctx.gpa,
            manifest_document.value(),
            binding.manifest_sha256,
            source_state,
            resource_id,
            control_name,
            stored.plan_json,
        );
    } else try action_protocol.validateStoredPlan(
        ctx.gpa,
        manifest_bytes,
        binding.manifest_sha256,
        stored.action_id,
        stored.plan_json,
        source_state,
    );
    defer parsed.deinit();

    if (!ctx.config.nob_allow_system_mutation and
        (stored.resource_id != null or parsed.value.broker_requests.len != 0))
    {
        return error.SystemMutationDisabled;
    }

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

pub fn getPlan(ctx: Context, plan_id: []const u8) !?db_store.NobPlan {
    return try ctx.db.nob().getPlan(ctx.gpa, plan_id);
}

pub fn listRuns(ctx: Context, project_id: ?i64, limit: i64) !db_store.NobRuns {
    return try ctx.db.nob().listRuns(ctx.gpa, project_id, @min(@max(limit, 1), 200));
}

pub fn listEvents(ctx: Context, operation_id: []const u8) !db_store.NobRunEvents {
    return try ctx.db.nob().listRunEvents(ctx.gpa, operation_id);
}

pub fn listEventsAfter(ctx: Context, operation_id: []const u8, after_seq: i64, limit: i64) !db_store.NobRunEvents {
    return try ctx.db.nob().listRunEventsAfter(ctx.gpa, operation_id, @max(after_seq, 0), @min(@max(limit, 1), 501));
}

pub fn listRecentEvents(ctx: Context, operation_id: []const u8, limit: i64) !db_store.NobRunEvents {
    return try ctx.db.nob().listRecentRunEvents(ctx.gpa, operation_id, @min(@max(limit, 1), 500));
}

pub fn listArtifacts(ctx: Context, operation_id: []const u8) !db_store.NobArtifacts {
    return try ctx.db.nob().listArtifacts(ctx.gpa, operation_id);
}

pub fn readRunLog(ctx: Context, operation_id: []const u8, requested_tail_bytes: usize) ![]u8 {
    const tail_bytes = @min(@max(requested_tail_bytes, 1), 1024 * 1024);
    const run_value = (try getRun(ctx, operation_id)) orelse return error.RunNotFound;
    defer run_value.deinit(ctx.gpa);
    const path = run_value.log_path orelse return ctx.gpa.dupe(u8, "");
    const state_root = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, ctx.config.nob_state_root, ctx.gpa);
    defer ctx.gpa.free(state_root);
    const expected_dir = try std.fs.path.join(ctx.gpa, &.{ state_root, operation_id });
    defer ctx.gpa.free(expected_dir);
    const expected_path = try std.fs.path.join(ctx.gpa, &.{ expected_dir, "events.ndjson" });
    defer ctx.gpa.free(expected_path);
    if (!std.mem.eql(u8, path, expected_path)) return error.InvalidOperationLogPath;
    const file = try std.Io.Dir.cwd().openFile(ctx.io, path, .{ .follow_symlinks = false });
    defer file.close(ctx.io);
    const length = try file.length(ctx.io);
    const amount: usize = @intCast(@min(length, tail_bytes));
    const bytes = try ctx.gpa.alloc(u8, amount);
    errdefer ctx.gpa.free(bytes);
    const read = try file.readPositionalAll(ctx.io, bytes, length - amount);
    if (read == bytes.len) return bytes;
    return try ctx.gpa.realloc(bytes, read);
}

pub fn resourceLogs(ctx: Context, project_reference: []const u8, resource_id: []const u8, lines: u16) ![]u8 {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const binding = try executableBinding(project);
    const manifest_path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, manifest_path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(ctx.gpa, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, manifest_document.sha256Hex(&digest_buffer), binding.manifest_sha256)) return error.ManifestDigestMismatch;
    for (manifest_document.value().resources) |*resource| {
        if (!std.mem.eql(u8, resource.id, resource_id)) continue;
        var allowed = false;
        for (resource.controls) |control| if (control == .logs) {
            allowed = true;
            break;
        };
        if (!allowed) return error.UndeclaredResourceControl;
        const unit = try systemd.Unit.fromResource(resource);
        var controller = try systemd.Controller.init(ctx.io, ctx.gpa, ctx.config, project.root_path);
        defer controller.deinit();
        return try controller.logs(unit, lines);
    }
    return error.UnknownResource;
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

fn secretContext(ctx: Context) app_nob_secrets.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config };
}

fn loadManifest(ctx: Context, root_path: []const u8, manifest_sha256: []const u8) !nob.ManifestDocument {
    const path = try std.fs.path.join(ctx.gpa, &.{ root_path, "nob.json" });
    defer ctx.gpa.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(bytes);
    var document = try nob.parseManifest(ctx.gpa, bytes);
    errdefer document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, document.sha256Hex(&digest_buffer), manifest_sha256)) return error.ManifestDigestMismatch;
    return document;
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
