const std = @import("std");
const core_config = @import("core_config");
const protocol = @import("nob_protocol");
const source = @import("nob_source");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Options = struct {
    cache_root: []const u8,
    toolchains_file: []const u8,
    runtime_environment: core_config.RuntimeEnvironment,
    cloudio_version: []const u8,
    build_timeout_seconds: u32 = 300,
};

pub const Project = struct {
    internal_id: i64,
    root_path: []const u8,
    manifest_sha256: []const u8,
};

pub const Result = struct {
    runner_path: []u8,
    runner_sha256: []u8,
    metadata_json: []u8,
    zig_path: []u8,
    zig_version: []u8,
    reused: bool,
    description: protocol.DescriptionDocument,

    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.runner_path);
        allocator.free(self.runner_sha256);
        allocator.free(self.metadata_json);
        allocator.free(self.zig_path);
        allocator.free(self.zig_version);
        self.description.deinit();
    }
};

const Toolchain = struct {
    path: []u8,
    version: []u8,

    fn deinit(self: Toolchain, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.version);
    }
};

const RunnerMetadata = struct {
    schema: []const u8,
    project_id: []const u8,
    manifest_sha256: []const u8,
    source_fingerprint: []const u8,
    source_revision: ?[]const u8,
    source_dirty: bool,
    zig_path: []const u8,
    zig_version: []const u8,
    runner_sha256: []const u8,
    built_at: i64,
};

pub fn zigPathFromMetadata(allocator: Allocator, bytes: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(RunnerMetadata, allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (!std.fs.path.isAbsolute(parsed.value.zig_path)) return error.RunnerMetadataInvalid;
    return try allocator.dupe(u8, parsed.value.zig_path);
}

pub fn ensure(
    io: Io,
    allocator: Allocator,
    project: Project,
    source_state: source.State,
    options: Options,
    now: i64,
    diagnostics: *std.Io.Writer,
) !Result {
    try validateDigest(project.manifest_sha256);
    try Io.Dir.cwd().createDirPath(io, options.cache_root);
    const cache_root_z = try Io.Dir.cwd().realPathFileAlloc(io, options.cache_root, allocator);
    defer allocator.free(cache_root_z);
    const cache_root: []const u8 = cache_root_z;

    const manifest_path = try std.fs.path.join(allocator, &.{ project.root_path, "nob.json" });
    defer allocator.free(manifest_path);
    const manifest_bytes = try Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(nob.manifest.max_manifest_bytes));
    defer allocator.free(manifest_bytes);
    var manifest_document = try nob.parseManifest(allocator, manifest_bytes);
    defer manifest_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    const actual_digest = manifest_document.sha256Hex(&digest_buffer);
    if (!std.mem.eql(u8, actual_digest, project.manifest_sha256)) return error.ManifestDigestMismatch;
    const manifest = manifest_document.value();

    const toolchain = try resolveToolchain(io, allocator, project.root_path, manifest, options);
    defer toolchain.deinit(allocator);
    try diagnostics.print("zig {s} ({s})\n", .{ toolchain.version, toolchain.path });

    const source_key = try cacheSourceKey(io, allocator, source_state);
    defer allocator.free(source_key);
    const project_key = try std.fmt.allocPrint(allocator, "{d}", .{project.internal_id});
    defer allocator.free(project_key);
    const final_dir = try std.fs.path.join(allocator, &.{ cache_root, project_key, project.manifest_sha256, source_key });
    defer allocator.free(final_dir);
    const runner_path = try std.fs.path.join(allocator, &.{ final_dir, "bin", "nob" });
    defer allocator.free(runner_path);
    const metadata_path = try std.fs.path.join(allocator, &.{ final_dir, "runner.json" });
    defer allocator.free(metadata_path);

    const identity = try identityForManifest(allocator, manifest, project.manifest_sha256);
    defer identity.deinit(allocator);
    if (!source_state.dirty) {
        if (try reuseIfValid(io, allocator, runner_path, metadata_path, project, source_state, toolchain, identity.value, options, diagnostics)) |reused| {
            return reused;
        }
    }

    var random: [8]u8 = undefined;
    io.random(&random);
    const partial_dir = try std.fmt.allocPrint(allocator, "{s}.partial-{x}", .{ final_dir, random });
    defer allocator.free(partial_dir);
    Io.Dir.cwd().deleteTree(io, partial_dir) catch {};
    errdefer Io.Dir.cwd().deleteTree(io, partial_dir) catch {};
    try Io.Dir.cwd().createDirPath(io, partial_dir);
    const cache_dir = try std.fs.path.join(allocator, &.{ partial_dir, ".zig-cache" });
    defer allocator.free(cache_dir);

    var environment = try subprocess.makeEnvironment(allocator, options.runtime_environment, &.{});
    defer environment.deinit();
    const build_args = [_][]const u8{
        toolchain.path,
        "build",
        "nob",
        "-Doptimize=ReleaseSafe",
        "--prefix",
        partial_dir,
        "--cache-dir",
        cache_dir,
    };
    const build_result = try subprocess.run(allocator, io, &build_args, project.root_path, &environment, .{
        .stdout_bytes = 1024 * 1024,
        .stderr_bytes = 256 * 1024,
        .timeout_seconds = options.build_timeout_seconds,
    });
    defer build_result.deinit(allocator);
    if (build_result.stdout.len != 0) try diagnostics.print("build stdout:\n{s}\n", .{build_result.stdout});
    if (build_result.stderr.len != 0) try diagnostics.print("build stderr:\n{s}\n", .{build_result.stderr});
    if (!build_result.successful()) return error.RunnerBuildFailed;

    const partial_runner = try std.fs.path.join(allocator, &.{ partial_dir, "bin", "nob" });
    defer allocator.free(partial_runner);
    try validateRunnerFile(io, partial_runner);
    const runner_sha256 = try hashFile(io, allocator, partial_runner);
    errdefer allocator.free(runner_sha256);
    var description = try describeRunner(
        io,
        allocator,
        partial_runner,
        project.root_path,
        project.manifest_sha256,
        source_state,
        toolchain,
        identity.value,
        options,
        diagnostics,
    );
    errdefer description.deinit();

    const metadata_json = try stringifyMetadata(allocator, .{
        .schema = "nob.zig/runner-cache/v1",
        .project_id = manifest.project.id,
        .manifest_sha256 = project.manifest_sha256,
        .source_fingerprint = source_state.fingerprint,
        .source_revision = source_state.revision,
        .source_dirty = source_state.dirty,
        .zig_path = toolchain.path,
        .zig_version = toolchain.version,
        .runner_sha256 = runner_sha256,
        .built_at = now,
    });
    errdefer allocator.free(metadata_json);
    const partial_metadata = try std.fs.path.join(allocator, &.{ partial_dir, "runner.json" });
    defer allocator.free(partial_metadata);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = partial_metadata, .data = metadata_json });

    if (try directoryExists(io, final_dir)) try Io.Dir.cwd().deleteTree(io, final_dir);
    try Io.Dir.renameAbsolute(partial_dir, final_dir, io);
    return .{
        .runner_path = try allocator.dupe(u8, runner_path),
        .runner_sha256 = runner_sha256,
        .metadata_json = metadata_json,
        .zig_path = try allocator.dupe(u8, toolchain.path),
        .zig_version = try allocator.dupe(u8, toolchain.version),
        .reused = false,
        .description = description,
    };
}

fn reuseIfValid(
    io: Io,
    allocator: Allocator,
    runner_path: []const u8,
    metadata_path: []const u8,
    project: Project,
    source_state: source.State,
    toolchain: Toolchain,
    identity: protocol.Identity,
    options: Options,
    diagnostics: *std.Io.Writer,
) !?Result {
    validateRunnerFile(io, runner_path) catch return null;
    const metadata_bytes = Io.Dir.cwd().readFileAlloc(io, metadata_path, allocator, .limited(64 * 1024)) catch return null;
    defer allocator.free(metadata_bytes);
    var metadata = std.json.parseFromSlice(RunnerMetadata, allocator, metadata_bytes, .{ .allocate = .alloc_always }) catch return null;
    defer metadata.deinit();
    const value = metadata.value;
    if (!std.mem.eql(u8, value.schema, "nob.zig/runner-cache/v1") or
        !std.mem.eql(u8, value.project_id, identity.project_id) or
        !std.mem.eql(u8, value.manifest_sha256, project.manifest_sha256) or
        !std.mem.eql(u8, value.source_fingerprint, source_state.fingerprint) or
        !std.mem.eql(u8, value.zig_path, toolchain.path) or
        !std.mem.eql(u8, value.zig_version, toolchain.version)) return null;
    const actual_sha256 = try hashFile(io, allocator, runner_path);
    errdefer allocator.free(actual_sha256);
    if (!std.mem.eql(u8, actual_sha256, value.runner_sha256)) {
        allocator.free(actual_sha256);
        return null;
    }
    var description = describeRunner(
        io,
        allocator,
        runner_path,
        project.root_path,
        project.manifest_sha256,
        source_state,
        toolchain,
        identity,
        options,
        diagnostics,
    ) catch {
        allocator.free(actual_sha256);
        return null;
    };
    errdefer description.deinit();
    try diagnostics.writeAll("reused validated runner cache\n");
    return .{
        .runner_path = try allocator.dupe(u8, runner_path),
        .runner_sha256 = actual_sha256,
        .metadata_json = try allocator.dupe(u8, metadata_bytes),
        .zig_path = try allocator.dupe(u8, toolchain.path),
        .zig_version = try allocator.dupe(u8, toolchain.version),
        .reused = true,
        .description = description,
    };
}

fn describeRunner(
    io: Io,
    allocator: Allocator,
    runner_path: []const u8,
    root_path: []const u8,
    manifest_sha256: []const u8,
    source_state: source.State,
    toolchain: Toolchain,
    identity: protocol.Identity,
    options: Options,
    diagnostics: *std.Io.Writer,
) !protocol.DescriptionDocument {
    const extras = [_]subprocess.ExtraEnvironment{
        .{ .key = "NOB_PROJECT_ROOT", .value = root_path },
        .{ .key = "NOB_MANIFEST_SHA256", .value = manifest_sha256 },
        .{ .key = "NOB_SOURCE_FINGERPRINT", .value = source_state.fingerprint },
        .{ .key = "NOB_SOURCE_DIRTY", .value = if (source_state.dirty) "1" else "0" },
        .{ .key = "NOB_AVAILABLE_SECRETS", .value = "" },
        .{ .key = "NOB_ZIG", .value = toolchain.path },
        .{ .key = "NOB_CLOUDIO_VERSION", .value = options.cloudio_version },
    };
    var environment = try subprocess.makeEnvironment(allocator, options.runtime_environment, &extras);
    defer environment.deinit();
    if (source_state.revision) |revision| try environment.put("NOB_SOURCE_REVISION", revision);
    const args = [_][]const u8{ runner_path, "describe" };
    const result = try subprocess.run(allocator, io, &args, root_path, &environment, .{
        .stdout_bytes = protocol.max_stdout_bytes,
        .stderr_bytes = 256 * 1024,
        .timeout_seconds = 30,
    });
    defer result.deinit(allocator);
    if (result.stderr.len != 0) try diagnostics.print("describe stderr:\n{s}\n", .{result.stderr});
    if (!result.successful()) return error.RunnerDescribeFailed;
    return try protocol.parseDescription(allocator, result.stdout, identity);
}

fn resolveToolchain(
    io: Io,
    allocator: Allocator,
    root_path: []const u8,
    manifest: *const nob.types.Manifest,
    options: Options,
) !Toolchain {
    var expected_version: ?[]u8 = null;
    defer if (expected_version) |value| allocator.free(value);
    const executable = if (manifest.runner.zig_version_file) |relative| executable: {
        const version_path = try std.fs.path.join(allocator, &.{ root_path, relative });
        defer allocator.free(version_path);
        const version_bytes = try Io.Dir.cwd().readFileAlloc(io, version_path, allocator, .limited(256));
        defer allocator.free(version_bytes);
        const trimmed = std.mem.trim(u8, version_bytes, " \t\r\n");
        if (trimmed.len == 0 or trimmed.len > 128 or std.mem.indexOfAny(u8, trimmed, "\r\n") != null) return error.InvalidZigVersionFile;
        expected_version = try allocator.dupe(u8, trimmed);
        break :executable try mappedToolchain(io, allocator, options.toolchains_file, trimmed);
    } else try subprocess.resolveExecutable(io, allocator, "zig", options.runtime_environment.path);
    errdefer allocator.free(executable);
    try validateRunnerFile(io, executable);
    var environment = try subprocess.makeEnvironment(allocator, options.runtime_environment, &.{});
    defer environment.deinit();
    const args = [_][]const u8{ executable, "version" };
    const result = try subprocess.run(allocator, io, &args, root_path, &environment, .{
        .stdout_bytes = 4096,
        .stderr_bytes = 4096,
        .timeout_seconds = 15,
    });
    defer result.deinit(allocator);
    if (!result.successful()) return error.ZigVersionFailed;
    const version = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (version.len == 0 or version.len > 128) return error.InvalidZigVersion;
    if (expected_version) |expected| if (!std.mem.eql(u8, version, expected)) return error.ZigVersionMismatch;
    return .{ .path = executable, .version = try allocator.dupe(u8, version) };
}

fn mappedToolchain(io: Io, allocator: Allocator, file_path: []const u8, version: []const u8) ![]u8 {
    const stat = try Io.Dir.cwd().statFile(io, file_path, .{ .follow_symlinks = false });
    if (stat.kind != .file or @backingInt(stat.permissions) & 0o022 != 0) return error.InsecureToolchainsFile;
    const bytes = try Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(256 * 1024));
    defer allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (parsed.value != .object or parsed.value.object.count() != 2) return error.InvalidToolchainsFile;
    const schema = parsed.value.object.get("schema") orelse return error.InvalidToolchainsFile;
    const zig = parsed.value.object.get("zig") orelse return error.InvalidToolchainsFile;
    if (schema != .string or !std.mem.eql(u8, schema.string, "nob.zig/toolchains/v1") or zig != .object) return error.InvalidToolchainsFile;
    const path_value = zig.object.get(version) orelse return error.ToolchainMappingMissing;
    if (path_value != .string or !std.fs.path.isAbsolute(path_value.string)) return error.InvalidToolchainPath;
    const canonical = try Io.Dir.cwd().realPathFileAlloc(io, path_value.string, allocator);
    defer allocator.free(canonical);
    return try allocator.dupe(u8, canonical);
}

const OwnedIdentity = struct {
    value: protocol.Identity,
    actions: [][]const u8,
    resources: [][]const u8,

    fn deinit(self: OwnedIdentity, allocator: Allocator) void {
        allocator.free(self.actions);
        allocator.free(self.resources);
    }
};

fn identityForManifest(allocator: Allocator, manifest: *const nob.types.Manifest, digest: []const u8) !OwnedIdentity {
    const actions = try allocator.alloc([]const u8, manifest.actions.len);
    errdefer allocator.free(actions);
    for (manifest.actions, 0..) |action, index| actions[index] = action.id;
    const resources = try allocator.alloc([]const u8, manifest.resources.len);
    errdefer allocator.free(resources);
    for (manifest.resources, 0..) |resource, index| resources[index] = resource.id;
    return .{
        .value = .{
            .project_id = manifest.project.id,
            .manifest_sha256 = digest,
            .action_ids = actions,
            .resource_ids = resources,
        },
        .actions = actions,
        .resources = resources,
    };
}

fn cacheSourceKey(io: Io, allocator: Allocator, state: source.State) ![]u8 {
    if (!state.dirty and state.revision != null) return try allocator.dupe(u8, state.revision.?);
    var random: [16]u8 = undefined;
    io.random(&random);
    return try std.fmt.allocPrint(allocator, "dirty-{x}", .{random});
}

fn validateRunnerFile(io: Io, path: []const u8) !void {
    const stat = try Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    if (stat.kind != .file) return error.InvalidRunnerFile;
    if (@backingInt(stat.permissions) & 0o111 == 0) return error.RunnerNotExecutable;
}

fn hashFile(io: Io, allocator: Allocator, path: []const u8) ![]u8 {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024));
    defer allocator.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return try std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn stringifyMetadata(allocator: Allocator, metadata: RunnerMetadata) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(metadata, .{}, &output.writer);
    try output.writer.writeByte('\n');
    return try output.toOwnedSlice();
}

fn validateDigest(value: []const u8) !void {
    if (value.len != 64) return error.InvalidDigest;
    for (value) |byte| if (!std.ascii.isHex(byte)) return error.InvalidDigest;
}

fn directoryExists(io: Io, path: []const u8) !bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |other| return other,
    };
    dir.close(io);
    return true;
}

test "cache source keys only reuse clean revisions" {
    const allocator = std.testing.allocator;
    const clean = source.State{
        .repository_kind = @constCast("git"),
        .repository_identity = @constCast("repo"),
        .revision = @constCast("0123456789abcdef"),
        .dirty = false,
        .fingerprint = @constCast("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    };
    const key = try cacheSourceKey(std.testing.io, allocator, clean);
    defer allocator.free(key);
    try std.testing.expectEqualStrings("0123456789abcdef", key);
}
