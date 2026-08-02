const std = @import("std");
const action_protocol = @import("nob_action_protocol");
const app_nob_runtime = @import("app_nob_runtime");
const app_nob_secrets = @import("app_nob_secrets");
const bootstrap = @import("nob_bootstrap");
const broker = @import("nob_broker");
const core_config = @import("core_config");
const core_redact = @import("core_redact");
const core_time = @import("core_time");
const db_store = @import("db_store");
const resource_control = @import("nob_resource_control");
const source = @import("nob_source");
const subprocess = @import("nob_subprocess");
const systemd = @import("nob_systemd");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    cloudio_version: []const u8,
};

const Execution = struct {
    outcome: nob.types.OperationOutcome,
    summary: []u8,
    error_code: ?[]const u8,
    log_path: []u8,
    stderr_path: []u8,

    fn deinit(self: Execution, allocator: Allocator) void {
        allocator.free(self.summary);
        allocator.free(self.log_path);
        allocator.free(self.stderr_path);
    }
};

pub fn processNext(ctx: Context) !bool {
    const now = try nowSeconds();
    var run = (try ctx.db.nob().claimNextRun(ctx.gpa, now)) orelse return false;
    defer run.deinit(ctx.gpa);
    const execution = execute(ctx, run) catch |err| {
        const summary = try std.fmt.allocPrint(ctx.gpa, "run failed before a valid terminal event: {s}", .{@errorName(err)});
        defer ctx.gpa.free(summary);
        try ctx.db.nob().finishRun(run.id, .{
            .state = failureState(err),
            .outcome = failureState(err),
            .summary = summary,
            .error_code = @errorName(err),
            .log_path = null,
            .stderr_path = null,
            .finished_at = try nowSeconds(),
        });
        try audit(ctx, "nob.run", "failed", run.id, @errorName(err));
        observeAfter(ctx, run.project_id, run.id);
        return true;
    };
    defer execution.deinit(ctx.gpa);
    try ctx.db.nob().finishRun(run.id, .{
        .state = stateForOutcome(execution.outcome),
        .outcome = @tagName(execution.outcome),
        .summary = execution.summary,
        .error_code = execution.error_code,
        .log_path = execution.log_path,
        .stderr_path = execution.stderr_path,
        .finished_at = try nowSeconds(),
    });
    try audit(ctx, "nob.run", @tagName(execution.outcome), run.id, execution.summary);
    observeAfter(ctx, run.project_id, run.id);
    return true;
}

fn execute(ctx: Context, run: db_store.NobRun) !Execution {
    const plan_id = run.plan_id orelse return error.PlanBindingMissing;
    const plan = (try ctx.db.nob().getPlan(ctx.gpa, plan_id)) orelse return error.PlanNotFound;
    defer plan.deinit(ctx.gpa);
    const project = (try ctx.db.nob().getProject(ctx.gpa, run.project_id)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const manifest_sha256 = run.manifest_sha256 orelse return error.PlanBindingMissing;
    const runner_sha256 = run.runner_sha256 orelse return error.PlanBindingMissing;
    const source_fingerprint = run.source_fingerprint orelse return error.PlanBindingMissing;
    const plan_sha256 = run.plan_sha256 orelse return error.PlanBindingMissing;
    const runner_path = run.runner_path orelse return error.RunnerNotReady;
    if (project.discovery_state != .valid or project.trust_state != .trusted or project.runner_state != .ready) return error.ProjectStateChanged;
    if (!optionalMatches(project.manifest_sha256, manifest_sha256) or
        !optionalMatches(project.trusted_manifest_sha256, manifest_sha256) or
        !optionalMatches(project.runner_sha256, runner_sha256) or
        !optionalMatches(project.runner_path, runner_path))
    {
        return error.PlanBindingChanged;
    }
    const actual_runner_sha256 = try action_protocol.hashFile(ctx.io, ctx.gpa, runner_path);
    defer ctx.gpa.free(actual_runner_sha256);
    if (!std.mem.eql(u8, actual_runner_sha256, runner_sha256)) return error.RunnerDigestMismatch;
    const actual_plan_sha256 = try action_protocol.hashBytes(ctx.gpa, plan.plan_json);
    defer ctx.gpa.free(actual_plan_sha256);
    if (!std.mem.eql(u8, actual_plan_sha256, plan_sha256)) return error.PlanDigestMismatch;

    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    if (!std.mem.eql(u8, source_state.fingerprint, source_fingerprint)) return error.SourceChanged;
    const manifest_path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, manifest_path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(ctx.gpa, manifest_bytes);
    defer manifest_document.deinit();
    if (run.resource_id) |resource_id| {
        const control_name = resource_control.controlFromActionId(run.action_id, resource_id) orelse return error.InvalidResourcePlan;
        var parsed_resource_plan = try resource_control.validate(
            ctx.gpa,
            manifest_document.value(),
            manifest_sha256,
            source_state,
            resource_id,
            control_name,
            plan.plan_json,
        );
        defer parsed_resource_plan.deinit();
        return executeResourceControl(ctx, run, manifest_document.value(), resource_id, control_name);
    }
    var parsed_plan = try action_protocol.validateStoredPlan(
        ctx.gpa,
        manifest_bytes,
        manifest_sha256,
        run.action_id,
        plan.plan_json,
        source_state,
    );
    defer parsed_plan.deinit();
    const action = findAction(manifest_document.value().actions, run.action_id) orelse return error.UnknownAction;
    var resolved_secrets = try app_nob_secrets.resolve(secretContext(ctx), project.id, manifest_document.value());
    defer resolved_secrets.deinit(ctx.gpa);
    try app_nob_secrets.requireForAction(&resolved_secrets, manifest_document.value(), run.action_id);
    const redaction_values = try resolved_secrets.redactionValues(ctx.gpa);
    defer ctx.gpa.free(redaction_values);
    const runner_detail = project.runner_detail orelse return error.RunnerMetadataMissing;
    const zig_path = try bootstrap.zigPathFromMetadata(ctx.gpa, runner_detail);
    defer ctx.gpa.free(zig_path);

    var paths = try createRunPaths(ctx, run.id);
    defer paths.deinit(ctx.gpa);
    const secret_dir = try app_nob_secrets.materialize(
        secretContext(ctx),
        &resolved_secrets,
        manifest_document.value(),
        run.action_id,
        paths.operation_dir,
    );
    defer if (secret_dir) |path| ctx.gpa.free(path);
    var secrets_removed = false;
    defer if (!secrets_removed) app_nob_secrets.removeMaterialized(secretContext(ctx), secret_dir, paths.operation_dir);
    var broker_server: ?broker.Server = if (parsed_plan.value.broker_requests.len == 0)
        null
    else
        try broker.Server.start(.{
            .io = ctx.io,
            .gpa = ctx.gpa,
            .config = ctx.config,
            .operation_id = run.id,
            .actor = run.requested_by,
            .idempotency_key = run.idempotency_key,
            .operation_dir = paths.operation_dir,
            .artifact_dir = paths.artifact_dir,
            .manifest = manifest_document.value(),
            .plan = &parsed_plan.value,
        });
    defer if (broker_server) |*server| server.deinit();
    const extras = [_]subprocess.ExtraEnvironment{
        .{ .key = "NOB_PROJECT_ROOT", .value = project.root_path },
        .{ .key = "NOB_MANIFEST_SHA256", .value = manifest_sha256 },
        .{ .key = "NOB_SOURCE_FINGERPRINT", .value = source_state.fingerprint },
        .{ .key = "NOB_SOURCE_DIRTY", .value = if (source_state.dirty) "1" else "0" },
        .{ .key = "NOB_AVAILABLE_SECRETS", .value = resolved_secrets.available_csv },
        .{ .key = "NOB_ZIG", .value = zig_path },
        .{ .key = "NOB_CLOUDIO_VERSION", .value = ctx.cloudio_version },
        .{ .key = "NOB_OPERATION_DIR", .value = paths.operation_dir },
        .{ .key = "NOB_ARTIFACT_DIR", .value = paths.artifact_dir },
    };
    var environment = try subprocess.makeEnvironment(ctx.gpa, ctx.config.runtime_environment, &extras);
    defer environment.deinit();
    if (source_state.revision) |revision| try environment.put("NOB_SOURCE_REVISION", revision);
    if (secret_dir) |path| try environment.put("NOB_SECRET_DIR", path);
    if (broker_server) |*server| {
        try environment.put("NOB_BROKER_SOCKET", server.socketPath());
        try environment.put("NOB_BROKER_TOKEN_FILE", server.tokenPath());
    }
    const args = [_][]const u8{
        runner_path,
        "run",
        run.action_id,
        "--operation-id",
        run.id,
        "--plan-digest",
        plan_sha256,
    };
    var monitor_context = MonitorContext{
        .db = ctx.db,
        .operation_id = run.id,
        .last_heartbeat = try nowSeconds(),
        .broker_server = if (broker_server) |*server| server else null,
    };
    const max_stdout: usize = @intCast(@min(ctx.config.nob_max_run_log_bytes, nob.events.max_retained_stream_bytes));
    const result = try subprocess.runWithInput(
        ctx.gpa,
        ctx.io,
        &args,
        project.root_path,
        &environment,
        plan.plan_json,
        .{
            .stdout_bytes = max_stdout,
            .stderr_bytes = 1024 * 1024,
            .timeout_seconds = action.timeout_seconds,
        },
        .{ .context = &monitor_context, .poll = pollCancellation, .started = childStarted },
    );
    defer result.deinit(ctx.gpa);
    app_nob_secrets.removeMaterialized(secretContext(ctx), secret_dir, paths.operation_dir);
    secrets_removed = true;
    if (broker_server) |*server| try server.stop();
    const redacted_stdout = try core_redact.sensitive(ctx.gpa, result.stdout, redaction_values);
    defer ctx.gpa.free(redacted_stdout);
    const redacted_stderr = try core_redact.sensitive(ctx.gpa, result.stderr, redaction_values);
    defer ctx.gpa.free(redacted_stderr);
    try writePrivateFile(ctx, paths.log_path, redacted_stdout);
    try writePrivateFile(ctx, paths.stderr_path, redacted_stderr);

    if (result.timed_out) return error.RunTimedOut;
    const exit_code = termExitCode(result.term);
    if (result.canceled) {
        if (nob.events.validateStream(ctx.gpa, redacted_stdout, run.action_id, exit_code)) |summary| {
            const dropped_logs = try persistEvents(ctx, run.id, redacted_stdout, paths.artifact_dir);
            return .{
                .outcome = summary.outcome,
                .summary = try terminalSummary(ctx.gpa, redacted_stdout, "run canceled", dropped_logs),
                .error_code = if (summary.outcome == .canceled) null else "cancellation_outcome_mismatch",
                .log_path = try ctx.gpa.dupe(u8, paths.log_path),
                .stderr_path = try ctx.gpa.dupe(u8, paths.stderr_path),
            };
        } else |_| {
            return .{
                .outcome = .canceled,
                .summary = try ctx.gpa.dupe(u8, "run canceled before the helper emitted a terminal event"),
                .error_code = "forced_cancellation",
                .log_path = try ctx.gpa.dupe(u8, paths.log_path),
                .stderr_path = try ctx.gpa.dupe(u8, paths.stderr_path),
            };
        }
    }
    const stream = try nob.events.validateStream(ctx.gpa, redacted_stdout, run.action_id, exit_code);
    const dropped_logs = try persistEvents(ctx, run.id, redacted_stdout, paths.artifact_dir);
    return .{
        .outcome = stream.outcome,
        .summary = try terminalSummary(ctx.gpa, redacted_stdout, "run completed", dropped_logs),
        .error_code = if (stream.outcome == .succeeded) null else "runner_reported_failure",
        .log_path = try ctx.gpa.dupe(u8, paths.log_path),
        .stderr_path = try ctx.gpa.dupe(u8, paths.stderr_path),
    };
}

fn executeResourceControl(
    ctx: Context,
    run: db_store.NobRun,
    manifest: *const nob.types.Manifest,
    resource_id: []const u8,
    control_name: []const u8,
) !Execution {
    const binding = try resource_control.resolve(manifest, resource_id, control_name);
    const unit = try systemd.Unit.fromResource(binding.resource);
    const operation = try systemd.operationFromControl(binding.control);
    var paths = try createRunPaths(ctx, run.id);
    defer paths.deinit(ctx.gpa);
    var output = std.Io.Writer.Allocating.init(ctx.gpa);
    defer output.deinit();
    var events = nob.events.Writer.init(ctx.gpa, &output.writer);
    try events.operationStarted(run.action_id);
    try events.stageStarted("control", "Apply declared resource control");

    var operation_error: ?anyerror = null;
    control: {
        var controller = systemd.Controller.init(ctx.io, ctx.gpa, ctx.config, paths.operation_dir) catch |err| {
            operation_error = err;
            break :control;
        };
        defer controller.deinit();
        const transition = controller.control(unit, operation) catch |err| {
            operation_error = err;
            break :control;
        };
        defer transition.deinit(ctx.gpa);
        const message = try std.fmt.allocPrint(ctx.gpa, "systemd user unit {s}: {s}", .{ unit.name, control_name });
        defer ctx.gpa.free(message);
        try events.log(.info, "control", message);
        try events.resourceState(
            resource_id,
            if (std.mem.eql(u8, transition.after.active_state, "active")) .healthy else .stopped,
            if (std.mem.eql(u8, transition.after.active_state, "active")) "unit is active" else "unit is not active",
        );
    }

    const outcome: nob.types.OperationOutcome = if (operation_error == null) .succeeded else .failed;
    const summary = if (operation_error) |err|
        try std.fmt.allocPrint(ctx.gpa, "{s} {s} failed: {s}", .{ control_name, resource_id, @errorName(err) })
    else
        try std.fmt.allocPrint(ctx.gpa, "{s} {s} completed", .{ control_name, resource_id });
    errdefer ctx.gpa.free(summary);
    if (operation_error) |err| {
        const message = try std.fmt.allocPrint(ctx.gpa, "resource control failed: {s}", .{@errorName(err)});
        defer ctx.gpa.free(message);
        try events.log(.@"error", "control", message);
        try events.stageFinished("control", .failed);
    } else {
        try events.stageFinished("control", .succeeded);
    }
    try events.finish(outcome, summary);
    const bytes = output.written();
    _ = try nob.events.validateStream(ctx.gpa, bytes, run.action_id, nob.events.exitCode(outcome));
    try writePrivateFile(ctx, paths.log_path, bytes);
    try writePrivateFile(ctx, paths.stderr_path, if (operation_error) |err| @errorName(err) else "");
    _ = try persistEvents(ctx, run.id, bytes, paths.artifact_dir);
    return .{
        .outcome = outcome,
        .summary = summary,
        .error_code = if (operation_error) |err| @errorName(err) else null,
        .log_path = try ctx.gpa.dupe(u8, paths.log_path),
        .stderr_path = try ctx.gpa.dupe(u8, paths.stderr_path),
    };
}

const RunPaths = struct {
    operation_dir: []u8,
    artifact_dir: []u8,
    log_path: []u8,
    stderr_path: []u8,

    fn deinit(self: *RunPaths, allocator: Allocator) void {
        allocator.free(self.operation_dir);
        allocator.free(self.artifact_dir);
        allocator.free(self.log_path);
        allocator.free(self.stderr_path);
    }
};

fn createRunPaths(ctx: Context, operation_id: []const u8) !RunPaths {
    try std.Io.Dir.cwd().createDirPath(ctx.io, ctx.config.nob_state_root);
    const root_z = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, ctx.config.nob_state_root, ctx.gpa);
    defer ctx.gpa.free(root_z);
    const operation_dir = try std.fs.path.join(ctx.gpa, &.{ root_z, operation_id });
    errdefer ctx.gpa.free(operation_dir);
    if (std.Io.Dir.cwd().statFile(ctx.io, operation_dir, .{ .follow_symlinks = false })) |_| {
        return error.OperationDirectoryExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |other| return other,
    }
    try std.Io.Dir.cwd().createDirPath(ctx.io, operation_dir);
    var operation_handle = try std.Io.Dir.cwd().openDir(ctx.io, operation_dir, .{ .iterate = true });
    defer operation_handle.close(ctx.io);
    try operation_handle.setPermissions(ctx.io, @fromBackingInt(@intCast(0o700)));
    const artifact_dir = try std.fs.path.join(ctx.gpa, &.{ operation_dir, "artifacts" });
    errdefer ctx.gpa.free(artifact_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, artifact_dir);
    const log_path = try std.fs.path.join(ctx.gpa, &.{ operation_dir, "events.ndjson" });
    errdefer ctx.gpa.free(log_path);
    const stderr_path = try std.fs.path.join(ctx.gpa, &.{ operation_dir, "stderr.log" });
    return .{
        .operation_dir = operation_dir,
        .artifact_dir = artifact_dir,
        .log_path = log_path,
        .stderr_path = stderr_path,
    };
}

fn writePrivateFile(ctx: Context, path: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = bytes });
    const file = try std.Io.Dir.cwd().openFile(ctx.io, path, .{});
    defer file.close(ctx.io);
    try file.setPermissions(ctx.io, @fromBackingInt(@intCast(0o600)));
}

const MonitorContext = struct {
    db: *db_store.Db,
    operation_id: []const u8,
    last_heartbeat: i64,
    broker_server: ?*broker.Server,
};

fn childStarted(context_ptr: *anyopaque, child_id: std.process.Child.Id) !void {
    const monitor: *MonitorContext = @ptrCast(@alignCast(context_ptr));
    if (monitor.broker_server) |server| server.childStarted(child_id);
}

fn pollCancellation(context_ptr: *anyopaque) !bool {
    const monitor: *MonitorContext = @ptrCast(@alignCast(context_ptr));
    const now = try nowSeconds();
    if (now > monitor.last_heartbeat) {
        try monitor.db.nob().heartbeatRun(monitor.operation_id, now);
        monitor.last_heartbeat = now;
    }
    return try monitor.db.nob().runCancellationRequested(monitor.operation_id);
}

fn persistEvents(ctx: Context, operation_id: []const u8, bytes: []const u8, artifact_dir: []const u8) !usize {
    var retained_logs: usize = 0;
    var dropped_logs: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidEvent;
        const seq = intField(parsed.value.object, "seq") orelse return error.InvalidEvent;
        const event_type = stringField(parsed.value.object, "type") orelse return error.InvalidEvent;
        if (std.mem.eql(u8, event_type, "log")) {
            if (retained_logs >= 1000) {
                dropped_logs += 1;
                continue;
            }
            retained_logs += 1;
        }
        if (std.mem.eql(u8, event_type, "artifact")) try persistArtifact(ctx, operation_id, artifact_dir, parsed.value.object, line);
        try ctx.db.nob().appendRunEvent(.{
            .operation_id = operation_id,
            .seq = seq,
            .event_type = event_type,
            .level = stringField(parsed.value.object, "level"),
            .payload_json = line,
            .received_at = try nowSeconds(),
        });
    }
    return dropped_logs;
}

fn persistArtifact(
    ctx: Context,
    operation_id: []const u8,
    artifact_dir: []const u8,
    object: std.json.ObjectMap,
    metadata_json: []const u8,
) !void {
    const artifact_id = stringField(object, "artifact_id") orelse return error.InvalidArtifactEvent;
    const role = stringField(object, "role") orelse return error.InvalidArtifactEvent;
    const declared_path = stringField(object, "path") orelse return error.InvalidArtifactEvent;
    const declared_sha256 = stringField(object, "sha256") orelse return error.InvalidArtifactEvent;
    const declared_size = intField(object, "size_bytes") orelse return error.InvalidArtifactEvent;
    if (declared_size < 0 or !std.fs.path.isAbsolute(declared_path)) return error.InvalidArtifactEvent;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, artifact_dir, ctx.gpa);
    defer ctx.gpa.free(root);
    const path = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, declared_path, ctx.gpa);
    defer ctx.gpa.free(path);
    if (!strictDescendant(root, path)) return error.ArtifactOutsideOperation;
    const stat = try std.Io.Dir.cwd().statFile(ctx.io, path, .{ .follow_symlinks = false });
    if (stat.kind != .file or stat.size != @as(u64, @intCast(declared_size))) return error.ArtifactMetadataMismatch;
    const actual_sha256 = try action_protocol.hashFile(ctx.io, ctx.gpa, path);
    defer ctx.gpa.free(actual_sha256);
    if (!std.mem.eql(u8, actual_sha256, declared_sha256)) return error.ArtifactMetadataMismatch;
    try ctx.db.nob().appendArtifact(.{
        .operation_id = operation_id,
        .resource_id = stringField(object, "resource_id"),
        .artifact_id = artifact_id,
        .role = role,
        .path = path,
        .sha256 = actual_sha256,
        .size_bytes = declared_size,
        .metadata_json = metadata_json,
        .created_at = try nowSeconds(),
    });
}

fn strictDescendant(root: []const u8, candidate: []const u8) bool {
    if (candidate.len <= root.len or !std.mem.startsWith(u8, candidate, root)) return false;
    return candidate[root.len] == std.fs.path.sep;
}

fn terminalSummary(allocator: Allocator, bytes: []const u8, fallback: []const u8, dropped_logs: usize) ![]u8 {
    var candidate: ?[]u8 = null;
    errdefer if (candidate) |value| allocator.free(value);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const event_type = stringField(parsed.value.object, "type") orelse continue;
        if (!std.mem.eql(u8, event_type, "operation-finished")) continue;
        const summary = stringField(parsed.value.object, "summary") orelse continue;
        if (candidate) |old| allocator.free(old);
        candidate = try allocator.dupe(u8, summary);
    }
    const summary = candidate orelse try allocator.dupe(u8, fallback);
    if (dropped_logs == 0) return summary;
    defer allocator.free(summary);
    return try std.fmt.allocPrint(allocator, "{s} ({d} additional log events retained only in the NDJSON file)", .{ summary, dropped_logs });
}

fn stateForOutcome(outcome: nob.types.OperationOutcome) []const u8 {
    return switch (outcome) {
        .succeeded => "succeeded",
        .canceled => "canceled",
        .interrupted => "interrupted",
        .failed, .@"failed-rolled-back", .@"failed-rollback-failed" => "failed",
    };
}

fn failureState(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidEventStream,
        error.EventTooLarge,
        error.InvalidEvent,
        error.InvalidEventSchema,
        error.EventSequenceMismatch,
        error.EventAfterTerminal,
        error.InvalidEventState,
        error.StageMismatch,
        error.UnknownEventType,
        error.MissingTerminalEvent,
        error.ExitOutcomeMismatch,
        error.StreamTooLong,
        => "protocol-error",
        else => "failed",
    };
}

fn observeAfter(ctx: Context, project_id: i64, operation_id: []const u8) void {
    const reference = std.fmt.allocPrint(ctx.gpa, "{d}", .{project_id}) catch return;
    defer ctx.gpa.free(reference);
    _ = app_nob_runtime.observe(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .cloudio_version = ctx.cloudio_version,
    }, reference) catch |err| {
        audit(ctx, "nob.run.observe", "failed", operation_id, @errorName(err)) catch {};
    };
}

fn secretContext(ctx: Context) app_nob_secrets.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config };
}

fn findAction(actions: []const nob.types.Action, id: []const u8) ?*const nob.types.Action {
    for (actions) |*action| if (std.mem.eql(u8, action.id, id)) return action;
    return null;
}

fn termExitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 10,
    };
}

fn optionalMatches(value: ?[]const u8, expected: []const u8) bool {
    return value != null and std.mem.eql(u8, value.?, expected);
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return if (value == .string) value.string else null;
}

fn intField(object: std.json.ObjectMap, name: []const u8) ?i64 {
    const value = object.get(name) orelse return null;
    return if (value == .integer) value.integer else null;
}

fn audit(ctx: Context, action: []const u8, status: []const u8, operation_id: []const u8, detail: []const u8) !void {
    const text = try std.fmt.allocPrint(ctx.gpa, "run={s} {s}", .{ operation_id, detail });
    defer ctx.gpa.free(text);
    try ctx.db.insertAudit(action, status, text);
}

fn nowSeconds() !i64 {
    return @intCast(try core_time.currentEpochSeconds());
}
