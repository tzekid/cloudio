const std = @import("std");
const core_config = @import("core_config");
const core_redact = @import("core_redact");
const protocol = @import("nob_protocol");
const source = @import("nob_source");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

pub const Options = struct {
    runtime_environment: core_config.RuntimeEnvironment,
    cloudio_version: []const u8,
    available_secrets: []const u8 = "",
    redaction_values: []const []const u8 = &.{},
};

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    runner_path: []const u8,
    zig_path: []const u8,
    root_path: []const u8,
    manifest_sha256: []const u8,
    source_state: source.State,
    options: Options,
    diagnostics: *std.Io.Writer,
) !protocol.ObservationDocument {
    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "nob.json" });
    defer allocator.free(manifest_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(nob.manifest.max_manifest_bytes));
    defer allocator.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(allocator, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, manifest_document.sha256Hex(&digest_buffer), manifest_sha256)) return error.ManifestDigestMismatch;
    const manifest = manifest_document.value();

    const action_ids = try allocator.alloc([]const u8, manifest.actions.len);
    defer allocator.free(action_ids);
    for (manifest.actions, 0..) |action, index| action_ids[index] = action.id;
    const resource_ids = try allocator.alloc([]const u8, manifest.resources.len);
    defer allocator.free(resource_ids);
    for (manifest.resources, 0..) |resource, index| resource_ids[index] = resource.id;
    const identity = protocol.Identity{
        .project_id = manifest.project.id,
        .manifest_sha256 = manifest_sha256,
        .action_ids = action_ids,
        .resource_ids = resource_ids,
    };

    const extras = [_]subprocess.ExtraEnvironment{
        .{ .key = "NOB_PROJECT_ROOT", .value = root_path },
        .{ .key = "NOB_MANIFEST_SHA256", .value = manifest_sha256 },
        .{ .key = "NOB_SOURCE_FINGERPRINT", .value = source_state.fingerprint },
        .{ .key = "NOB_SOURCE_DIRTY", .value = if (source_state.dirty) "1" else "0" },
        .{ .key = "NOB_AVAILABLE_SECRETS", .value = options.available_secrets },
        .{ .key = "NOB_ZIG", .value = zig_path },
        .{ .key = "NOB_CLOUDIO_VERSION", .value = options.cloudio_version },
    };
    var environment = try subprocess.makeEnvironment(allocator, options.runtime_environment, &extras);
    defer environment.deinit();
    if (source_state.revision) |revision| try environment.put("NOB_SOURCE_REVISION", revision);

    const args = [_][]const u8{ runner_path, "observe" };
    const result = try subprocess.run(allocator, io, &args, root_path, &environment, .{
        .stdout_bytes = protocol.max_stdout_bytes,
        .stderr_bytes = 256 * 1024,
        .timeout_seconds = 60,
    });
    defer result.deinit(allocator);
    const redacted_stdout = try core_redact.sensitive(allocator, result.stdout, options.redaction_values);
    defer allocator.free(redacted_stdout);
    const redacted_stderr = try core_redact.sensitive(allocator, result.stderr, options.redaction_values);
    defer allocator.free(redacted_stderr);
    if (redacted_stderr.len != 0) try diagnostics.print("observe stderr:\n{s}\n", .{redacted_stderr});
    if (!result.successful()) return error.RunnerObserveFailed;
    var document = try protocol.parseObservation(allocator, redacted_stdout, identity);
    errdefer document.deinit();
    const value = document.value();
    if (!std.mem.eql(u8, @tagName(value.source.kind), source_state.repository_kind) or
        value.source.dirty != source_state.dirty or
        !std.mem.eql(u8, value.source.fingerprint, source_state.fingerprint) or
        !optionalEqual(value.source.revision, source_state.revision))
    {
        return error.SourceIdentityMismatch;
    }
    return document;
}

fn optionalEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}
