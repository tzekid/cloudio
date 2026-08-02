const std = @import("std");
const action_protocol = @import("nob_action_protocol");
const bootstrap = @import("nob_bootstrap");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const source = @import("nob_source");
const subprocess = @import("nob_subprocess");
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
            .state = "failed",
            .outcome = "failed",
            .summary = summary,
            .error_code = @errorName(err),
            .log_path = null,
            .stderr_path = null,
            .finished_at = try nowSeconds(),
        });
        try audit(ctx, "nob.run", "failed", run.id, @errorName(err));
        return true;
    };
    defer execution.deinit(ctx.gpa);
    try ctx.db.nob().finishRun(run.id, .{
        .state = @tagName(execution.outcome),
        .outcome = @tagName(execution.outcome),
        .summary = execution.summary,
        .error_code = execution.error_code,
        .log_path = execution.log_path,
        .stderr_path = execution.stderr_path,
        .finished_at = try nowSeconds(),
    });
    try audit(ctx, "nob.run", @tagName(execution.outcome), run.id, execution.summary);
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
    var parsed_plan = try action_protocol.validateStoredPlan(
        ctx.gpa,
        manifest_bytes,
        manifest_sha256,
        run.action_id,
        plan.plan_json,
        source_state,
    );
    defer parsed_plan.deinit();
    var manifest_document = try nob.parseManifest(ctx.gpa, manifest_bytes);
    defer manifest_document.deinit();
    const action = findAction(manifest_document.value().actions, run.action_id) orelse return error.UnknownAction;
    const runner_detail = project.runner_detail orelse return error.RunnerMetadataMissing;
    const zig_path = try bootstrap.zigPathFromMetadata(ctx.gpa, runner_detail);
    defer ctx.gpa.free(zig_path);

    var paths = try createRunPaths(ctx, run.id);
    defer paths.deinit(ctx.gpa);
    const extras = [_]subprocess.ExtraEnvironment{
        .{ .key = "NOB_PROJECT_ROOT", .value = project.root_path },
        .{ .key = "NOB_MANIFEST_SHA256", .value = manifest_sha256 },
        .{ .key = "NOB_SOURCE_FINGERPRINT", .value = source_state.fingerprint },
        .{ .key = "NOB_SOURCE_DIRTY", .value = if (source_state.dirty) "1" else "0" },
        .{ .key = "NOB_AVAILABLE_SECRETS", .value = "" },
        .{ .key = "NOB_ZIG", .value = zig_path },
        .{ .key = "NOB_CLOUDIO_VERSION", .value = ctx.cloudio_version },
        .{ .key = "NOB_OPERATION_DIR", .value = paths.operation_dir },
        .{ .key = "NOB_ARTIFACT_DIR", .value = paths.artifact_dir },
    };
    var environment = try subprocess.makeEnvironment(ctx.gpa, ctx.config.runtime_environment, &extras);
    defer environment.deinit();
    if (source_state.revision) |revision| try environment.put("NOB_SOURCE_REVISION", revision);
    const args = [_][]const u8{
        runner_path,
        "run",
        run.action_id,
        "--operation-id",
        run.id,
        "--plan-digest",
        plan_sha256,
    };
    var monitor_context = MonitorContext{ .db = ctx.db, .operation_id = run.id, .last_heartbeat = try nowSeconds() };
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
        .{ .context = &monitor_context, .poll = pollCancellation },
    );
    defer result.deinit(ctx.gpa);
    try writePrivateFile(ctx, paths.log_path, result.stdout);
    try writePrivateFile(ctx, paths.stderr_path, result.stderr);

    if (result.timed_out) return error.RunTimedOut;
    const exit_code = termExitCode(result.term);
    if (result.canceled) {
        if (nob.events.validateStream(ctx.gpa, result.stdout, run.action_id, exit_code)) |summary| {
            try persistEvents(ctx, run.id, result.stdout);
            return .{
                .outcome = summary.outcome,
                .summary = try terminalSummary(ctx.gpa, result.stdout, "run canceled"),
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
    const stream = try nob.events.validateStream(ctx.gpa, result.stdout, run.action_id, exit_code);
    try persistEvents(ctx, run.id, result.stdout);
    return .{
        .outcome = stream.outcome,
        .summary = try terminalSummary(ctx.gpa, result.stdout, "run completed"),
        .error_code = if (stream.outcome == .succeeded) null else "runner_reported_failure",
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
};

fn pollCancellation(context_ptr: *anyopaque) !bool {
    const monitor: *MonitorContext = @ptrCast(@alignCast(context_ptr));
    const now = try nowSeconds();
    if (now > monitor.last_heartbeat) {
        try monitor.db.nob().heartbeatRun(monitor.operation_id, now);
        monitor.last_heartbeat = now;
    }
    return try monitor.db.nob().runCancellationRequested(monitor.operation_id);
}

fn persistEvents(ctx: Context, operation_id: []const u8, bytes: []const u8) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidEvent;
        const seq = intField(parsed.value.object, "seq") orelse return error.InvalidEvent;
        const event_type = stringField(parsed.value.object, "type") orelse return error.InvalidEvent;
        try ctx.db.nob().appendRunEvent(.{
            .operation_id = operation_id,
            .seq = seq,
            .event_type = event_type,
            .level = stringField(parsed.value.object, "level"),
            .payload_json = line,
            .received_at = try nowSeconds(),
        });
    }
}

fn terminalSummary(allocator: Allocator, bytes: []const u8, fallback: []const u8) ![]u8 {
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
    return candidate orelse try allocator.dupe(u8, fallback);
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
