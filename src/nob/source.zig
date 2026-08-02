const std = @import("std");
const core_config = @import("core_config");
const subprocess = @import("nob_subprocess");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const State = struct {
    repository_kind: []u8,
    repository_identity: []u8,
    revision: ?[]u8,
    dirty: bool,
    fingerprint: []u8,

    pub fn deinit(self: State, allocator: Allocator) void {
        allocator.free(self.repository_kind);
        allocator.free(self.repository_identity);
        if (self.revision) |revision| allocator.free(revision);
        allocator.free(self.fingerprint);
    }
};

pub fn inspect(
    io: Io,
    allocator: Allocator,
    root: []const u8,
    manifest_sha256: []const u8,
    runtime: core_config.RuntimeEnvironment,
) !State {
    const git = subprocess.resolveExecutable(io, allocator, "git", runtime.path) catch
        return filesystemState(allocator, root, manifest_sha256);
    defer allocator.free(git);
    var environment = try subprocess.makeEnvironment(allocator, runtime, &.{});
    defer environment.deinit();

    const revision_result = try runGit(allocator, io, git, root, &.{ "rev-parse", "--verify", "HEAD" }, &environment, 4096);
    defer revision_result.deinit(allocator);
    if (!revision_result.successful()) return filesystemState(allocator, root, manifest_sha256);
    const revision_text = std.mem.trim(u8, revision_result.stdout, " \t\r\n");
    if (revision_text.len < 7 or revision_text.len > 128) return error.InvalidGitRevision;
    const revision = try allocator.dupe(u8, revision_text);
    errdefer allocator.free(revision);

    const diff = try runGit(allocator, io, git, root, &.{ "diff", "--binary", "--no-ext-diff", "HEAD", "--" }, &environment, 16 * 1024 * 1024);
    defer diff.deinit(allocator);
    if (!diff.successful()) return error.GitInspectionFailed;
    const untracked = try runGit(allocator, io, git, root, &.{ "ls-files", "--others", "--exclude-standard", "-z" }, &environment, 16 * 1024 * 1024);
    defer untracked.deinit(allocator);
    if (!untracked.successful()) return error.GitInspectionFailed;

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("nob-source-v1\x00git\x00");
    hasher.update(revision);
    hasher.update("\x00manifest\x00");
    hasher.update(manifest_sha256);
    hasher.update("\x00diff\x00");
    hasher.update(diff.stdout);
    var paths = std.mem.splitScalar(u8, untracked.stdout, 0);
    while (paths.next()) |path| {
        if (path.len == 0) continue;
        try validateGitPath(path);
        const joined = try std.fs.path.join(allocator, &.{ root, path });
        defer allocator.free(joined);
        const contents = Io.Dir.cwd().readFileAlloc(io, joined, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.IsDir => continue,
            else => |other| return other,
        };
        defer allocator.free(contents);
        hasher.update("\x00untracked\x00");
        hasher.update(path);
        hasher.update("\x00");
        hasher.update(contents);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const fingerprint = try std.fmt.allocPrint(allocator, "{x}", .{digest});
    errdefer allocator.free(fingerprint);

    const remote_result = try runGit(allocator, io, git, root, &.{ "config", "--get", "remote.origin.url" }, &environment, 4096);
    defer remote_result.deinit(allocator);
    const remote = std.mem.trim(u8, remote_result.stdout, " \t\r\n");
    const identity = try allocator.dupe(u8, if (remote_result.successful() and remote.len != 0) remote else root);
    errdefer allocator.free(identity);

    return .{
        .repository_kind = try allocator.dupe(u8, "git"),
        .repository_identity = identity,
        .revision = revision,
        .dirty = diff.stdout.len != 0 or untracked.stdout.len != 0,
        .fingerprint = fingerprint,
    };
}

fn filesystemState(allocator: Allocator, root: []const u8, manifest_sha256: []const u8) !State {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("nob-source-v1\x00filesystem\x00");
    hasher.update(root);
    hasher.update("\x00manifest\x00");
    hasher.update(manifest_sha256);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{
        .repository_kind = try allocator.dupe(u8, "filesystem"),
        .repository_identity = try allocator.dupe(u8, root),
        .revision = null,
        .dirty = true,
        .fingerprint = try std.fmt.allocPrint(allocator, "{x}", .{digest}),
    };
}

fn runGit(
    allocator: Allocator,
    io: Io,
    git: []const u8,
    root: []const u8,
    args: []const []const u8,
    environment: *const std.process.Environ.Map,
    stdout_limit: usize,
) !subprocess.Result {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, git);
    try argv.appendSlice(allocator, args);
    return try subprocess.run(allocator, io, argv.items, root, environment, .{
        .stdout_bytes = stdout_limit,
        .stderr_bytes = 64 * 1024,
        .timeout_seconds = 30,
    });
}

fn validateGitPath(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null) return error.InvalidGitPath;
    var segments = std.mem.splitScalar(u8, path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return error.InvalidGitPath;
    }
}

test "filesystem source fingerprints are stable and manifest-bound" {
    const allocator = std.testing.allocator;
    const first = try filesystemState(allocator, "/srv/project", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    defer first.deinit(allocator);
    const second = try filesystemState(allocator, "/srv/project", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    defer second.deinit(allocator);
    try std.testing.expectEqualStrings(first.fingerprint, second.fingerprint);
    try std.testing.expect(first.dirty);
    try std.testing.expectEqualStrings("filesystem", first.repository_kind);
}
