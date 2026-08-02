const std = @import("std");
const app_nob_projects = @import("app_nob_projects");
const bootstrap = @import("nob_bootstrap");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const independent_observation = @import("nob_independent_observation");
const observation = @import("nob_observation");
const source = @import("nob_source");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    cloudio_version: []const u8,
};

pub const Outcome = struct {
    project_id: i64,
    runner_reused: bool,
    status: nob.types.Status,
};

pub fn prepareAndObserve(ctx: Context, reference: []const u8) !Outcome {
    const project = (try app_nob_projects.find(projectContext(ctx), reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const manifest_sha256 = try requireExecutableProject(project);
    const now = try nowSeconds();
    if (!try ctx.db.nob().markRunnerBuilding(project.id, manifest_sha256, now)) return error.ProjectStateChanged;

    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    var diagnostics = std.Io.Writer.Allocating.init(ctx.gpa);
    defer diagnostics.deinit();
    var built = bootstrap.ensure(ctx.io, ctx.gpa, .{
        .internal_id = project.id,
        .root_path = project.root_path,
        .manifest_sha256 = manifest_sha256,
    }, source_state, .{
        .cache_root = ctx.config.nob_cache_root,
        .toolchains_file = ctx.config.nob_toolchains_file,
        .runtime_environment = ctx.config.runtime_environment,
        .cloudio_version = ctx.cloudio_version,
    }, now, &diagnostics.writer) catch |err| {
        try recordBootstrapFailure(ctx, project.id, manifest_sha256, diagnostics.written(), err, now);
        return err;
    };
    defer built.deinit(ctx.gpa);

    var availability = std.ArrayList(db_store.NobActionAvailability).empty;
    defer availability.deinit(ctx.gpa);
    for (built.description.value().actions) |action| try availability.append(ctx.gpa, .{
        .action_id = action.id,
        .available = action.available,
        .reason = action.reason,
    });
    try ctx.db.nob().acceptRunner(.{
        .project_id = project.id,
        .manifest_sha256 = manifest_sha256,
        .runner_path = built.runner_path,
        .runner_sha256 = built.runner_sha256,
        .runner_detail = built.metadata_json,
        .repository_kind = source_state.repository_kind,
        .repository_identity = source_state.repository_identity,
        .head_revision = source_state.revision,
        .source_fingerprint = source_state.fingerprint,
        .source_dirty = source_state.dirty,
        .actions = availability.items,
        .now = now,
    });
    try audit(ctx, "nob.bootstrap", "ok", project.id, if (built.reused) "runner cache reused" else "runner built and validated");

    const status = try observeWith(ctx, project, manifest_sha256, built.runner_path, built.zig_path, source_state);
    return .{ .project_id = project.id, .runner_reused = built.reused, .status = status };
}

pub fn observe(ctx: Context, reference: []const u8) !Outcome {
    const project = (try app_nob_projects.find(projectContext(ctx), reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const manifest_sha256 = try requireExecutableProject(project);
    if (project.runner_state != .ready) return error.RunnerNotReady;
    const runner_path = project.runner_path orelse return error.RunnerNotReady;
    const runner_detail = project.runner_detail orelse return error.RunnerMetadataMissing;
    const zig_path = try zigPathFromMetadata(ctx.gpa, runner_detail);
    defer ctx.gpa.free(zig_path);
    const source_state = try source.inspect(ctx.io, ctx.gpa, project.root_path, manifest_sha256, ctx.config.runtime_environment);
    defer source_state.deinit(ctx.gpa);
    const status = try observeWith(ctx, project, manifest_sha256, runner_path, zig_path, source_state);
    return .{ .project_id = project.id, .runner_reused = true, .status = status };
}

fn observeWith(
    ctx: Context,
    project: db_store.NobProject,
    manifest_sha256: []const u8,
    runner_path: []const u8,
    zig_path: []const u8,
    source_state: source.State,
) !nob.types.Status {
    var diagnostics = std.Io.Writer.Allocating.init(ctx.gpa);
    defer diagnostics.deinit();
    var document = observation.run(ctx.io, ctx.gpa, runner_path, zig_path, project.root_path, manifest_sha256, source_state, .{
        .runtime_environment = ctx.config.runtime_environment,
        .cloudio_version = ctx.cloudio_version,
    }, &diagnostics.writer) catch |err| {
        const now = try nowSeconds();
        const detail = try failureDetail(ctx.gpa, diagnostics.written(), err);
        defer ctx.gpa.free(detail);
        try ctx.db.nob().markObservationFailed(project.id, detail, now);
        try audit(ctx, "nob.observe", "failed", project.id, @errorName(err));
        return err;
    };
    defer document.deinit();
    const value = document.value();
    var verified = try independent_observation.run(
        ctx.io,
        ctx.gpa,
        project.root_path,
        manifest_sha256,
        ctx.config.runtime_environment,
        value,
    );
    defer verified.deinit(ctx.gpa);

    var resources = std.ArrayList(db_store.NobResourceObservation).empty;
    defer {
        for (resources.items) |resource| if (resource.runner_observation_json) |bytes| ctx.gpa.free(bytes);
        resources.deinit(ctx.gpa);
    }
    for (verified.resources) |resource| {
        const runner_resource = findRunnerResource(value.resources, resource.resource_id);
        try resources.append(ctx.gpa, .{
            .resource_id = resource.resource_id,
            .status = @tagName(resource.status),
            .summary = resource.summary,
            .runner_observation_json = if (runner_resource) |present| try stringify(ctx.gpa, present) else null,
            .cloudio_observation_json = resource.observation_json,
        });
    }
    const now = try nowSeconds();
    try ctx.db.nob().acceptObservation(.{
        .project_id = project.id,
        .manifest_sha256 = manifest_sha256,
        .project_status = @tagName(verified.status),
        .project_summary = verified.summary,
        .repository_kind = source_state.repository_kind,
        .repository_identity = source_state.repository_identity,
        .head_revision = source_state.revision,
        .source_fingerprint = source_state.fingerprint,
        .source_dirty = source_state.dirty,
        .resources = resources.items,
        .now = now,
    });
    try audit(ctx, "nob.observe", "ok", project.id, @tagName(verified.status));
    return verified.status;
}

fn findRunnerResource(resources: []const nob.types.ResourceObservation, resource_id: []const u8) ?nob.types.ResourceObservation {
    for (resources) |resource| if (std.mem.eql(u8, resource.id, resource_id)) return resource;
    return null;
}

fn requireExecutableProject(project: db_store.NobProject) ![]const u8 {
    if (project.discovery_state != .valid) return error.ProjectManifestNotValid;
    if (project.trust_state != .trusted) return error.ProjectNotTrusted;
    const manifest_sha256 = project.manifest_sha256 orelse return error.ManifestUnavailable;
    const trusted_sha256 = project.trusted_manifest_sha256 orelse return error.ProjectNotTrusted;
    if (!std.mem.eql(u8, manifest_sha256, trusted_sha256)) return error.ManifestDigestMismatch;
    return manifest_sha256;
}

fn projectContext(ctx: Context) app_nob_projects.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

fn recordBootstrapFailure(
    ctx: Context,
    project_id: i64,
    manifest_sha256: []const u8,
    diagnostics: []const u8,
    err: anyerror,
    now: i64,
) !void {
    const detail = try failureDetail(ctx.gpa, diagnostics, err);
    defer ctx.gpa.free(detail);
    try ctx.db.nob().markRunnerFailed(project_id, manifest_sha256, detail, now);
    try audit(ctx, "nob.bootstrap", "failed", project_id, @errorName(err));
}

fn failureDetail(allocator: Allocator, diagnostics: []const u8, err: anyerror) ![]u8 {
    const max = 32 * 1024;
    if (diagnostics.len == 0) return try allocator.dupe(u8, @errorName(err));
    const tail = diagnostics[diagnostics.len - @min(diagnostics.len, max) ..];
    return try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(err), tail });
}

fn zigPathFromMetadata(allocator: Allocator, bytes: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.RunnerMetadataInvalid;
    const value = parsed.value.object.get("zig_path") orelse return error.RunnerMetadataInvalid;
    if (value != .string or !std.fs.path.isAbsolute(value.string)) return error.RunnerMetadataInvalid;
    return try allocator.dupe(u8, value.string);
}

fn stringify(allocator: Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return try output.toOwnedSlice();
}

fn audit(ctx: Context, action: []const u8, status: []const u8, project_id: i64, detail: []const u8) !void {
    const text = try std.fmt.allocPrint(ctx.gpa, "project={d} {s}", .{ project_id, detail });
    defer ctx.gpa.free(text);
    try ctx.db.insertAudit(action, status, text);
}

fn nowSeconds() !i64 {
    return @intCast(try core_time.currentEpochSeconds());
}
