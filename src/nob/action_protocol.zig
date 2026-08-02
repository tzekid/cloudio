const std = @import("std");
const core_config = @import("core_config");
const source = @import("nob_source");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Options = struct {
    runtime_environment: core_config.RuntimeEnvironment,
    cloudio_version: []const u8,
};

pub const Planned = struct {
    request_json: []u8,
    plan_json: []u8,
    plan_sha256: []u8,
    parsed: std.json.Parsed(nob.types.Plan),

    pub fn deinit(self: *Planned, allocator: Allocator) void {
        allocator.free(self.request_json);
        allocator.free(self.plan_json);
        allocator.free(self.plan_sha256);
        self.parsed.deinit();
    }

    pub fn value(self: *const Planned) *const nob.types.Plan {
        return &self.parsed.value;
    }
};

pub fn createPlan(
    io: Io,
    allocator: Allocator,
    runner_path: []const u8,
    zig_path: []const u8,
    root_path: []const u8,
    manifest_sha256: []const u8,
    source_state: source.State,
    action_id: []const u8,
    plan_id: []const u8,
    parameters: std.json.Value,
    options: Options,
    diagnostics: *std.Io.Writer,
) !Planned {
    if (parameters != .object) return error.InvalidParameters;
    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "nob.json" });
    defer allocator.free(manifest_path);
    const manifest_bytes = try Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(nob.manifest.max_manifest_bytes));
    defer allocator.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(allocator, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, manifest_document.sha256Hex(&digest_buffer), manifest_sha256)) return error.ManifestDigestMismatch;
    const manifest = manifest_document.value();
    const action = findAction(manifest.actions, action_id) orelse return error.UnknownAction;

    const request_json = try stringify(allocator, nob.types.ActionRequest{
        .schema = nob.plan.action_request_schema,
        .plan_id = plan_id,
        .project_id = manifest.project.id,
        .action_id = action_id,
        .parameters = parameters,
    });
    errdefer allocator.free(request_json);
    const extras = [_]subprocess.ExtraEnvironment{
        .{ .key = "NOB_PROJECT_ROOT", .value = root_path },
        .{ .key = "NOB_MANIFEST_SHA256", .value = manifest_sha256 },
        .{ .key = "NOB_SOURCE_FINGERPRINT", .value = source_state.fingerprint },
        .{ .key = "NOB_SOURCE_DIRTY", .value = if (source_state.dirty) "1" else "0" },
        .{ .key = "NOB_AVAILABLE_SECRETS", .value = "" },
        .{ .key = "NOB_ZIG", .value = zig_path },
        .{ .key = "NOB_CLOUDIO_VERSION", .value = options.cloudio_version },
    };
    var environment = try subprocess.makeEnvironment(allocator, options.runtime_environment, &extras);
    defer environment.deinit();
    if (source_state.revision) |revision| try environment.put("NOB_SOURCE_REVISION", revision);
    const args = [_][]const u8{ runner_path, "plan", action_id };
    const result = try subprocess.runWithInput(
        allocator,
        io,
        &args,
        root_path,
        &environment,
        request_json,
        .{ .stdout_bytes = nob.json.max_plan_bytes, .stderr_bytes = 256 * 1024, .timeout_seconds = 60 },
        null,
    );
    defer result.deinit(allocator);
    if (result.stderr.len != 0) try diagnostics.print("plan stderr:\n{s}\n", .{result.stderr});
    if (!result.term.success()) return error.RunnerPlanFailed;
    const plan_json = try allocator.dupe(u8, result.stdout);
    errdefer allocator.free(plan_json);
    var parsed = try std.json.parseFromSlice(nob.types.Plan, allocator, plan_json, .{
        .allocate = .alloc_always,
        .max_value_len = nob.json.max_plan_bytes,
    });
    errdefer parsed.deinit();
    try nob.plan.validateApproved(&parsed.value, manifest, action, manifest_sha256, .{
        .revision = source_state.revision,
        .dirty = source_state.dirty,
        .fingerprint = source_state.fingerprint,
    });
    const plan_sha256 = try hashBytes(allocator, plan_json);
    return .{
        .request_json = request_json,
        .plan_json = plan_json,
        .plan_sha256 = plan_sha256,
        .parsed = parsed,
    };
}

pub fn validateStoredPlan(
    allocator: Allocator,
    manifest_bytes: []const u8,
    manifest_sha256: []const u8,
    action_id: []const u8,
    plan_bytes: []const u8,
    source_state: source.State,
) !std.json.Parsed(nob.types.Plan) {
    var manifest_document = try nob.parseManifest(allocator, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, manifest_document.sha256Hex(&digest_buffer), manifest_sha256)) return error.ManifestDigestMismatch;
    const action = findAction(manifest_document.value().actions, action_id) orelse return error.UnknownAction;
    var parsed = try std.json.parseFromSlice(nob.types.Plan, allocator, plan_bytes, .{
        .allocate = .alloc_always,
        .max_value_len = nob.json.max_plan_bytes,
    });
    errdefer parsed.deinit();
    try nob.plan.validateApproved(&parsed.value, manifest_document.value(), action, manifest_sha256, .{
        .revision = source_state.revision,
        .dirty = source_state.dirty,
        .fingerprint = source_state.fingerprint,
    });
    return parsed;
}

pub fn hashBytes(allocator: Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return try std.fmt.allocPrint(allocator, "{x}", .{digest});
}

pub fn hashFile(io: Io, allocator: Allocator, path: []const u8) ![]u8 {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024));
    defer allocator.free(bytes);
    return try hashBytes(allocator, bytes);
}

fn stringify(allocator: Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    try output.writer.writeByte('\n');
    return try output.toOwnedSlice();
}

fn findAction(actions: []const nob.types.Action, id: []const u8) ?*const nob.types.Action {
    for (actions) |*action| if (std.mem.eql(u8, action.id, id)) return action;
    return null;
}
