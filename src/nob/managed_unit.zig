const std = @import("std");
const core_config = @import("core_config");
const db_store = @import("db_store");
const systemd = @import("nob_systemd");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const max_unit_bytes = nob.systemd_unit.max_rendered_bytes;

pub const Existing = struct {
    path: []u8,
    bytes: ?[]u8,
    sha256: ?[64]u8,

    pub fn deinit(self: Existing, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.bytes) |bytes| allocator.free(bytes);
    }

    pub fn digest(self: *const Existing) ?[]const u8 {
        return if (self.sha256) |*value| value else null;
    }
};

pub const Result = struct {
    before_sha256: ?[64]u8,
    after_sha256: ?[64]u8,
    fragment_path: []u8,

    pub fn deinit(self: Result, allocator: Allocator) void {
        allocator.free(self.fragment_path);
    }

    pub fn beforeDigest(self: *const Result) ?[]const u8 {
        return if (self.before_sha256) |*value| value else null;
    }

    pub fn afterDigest(self: *const Result) ?[]const u8 {
        return if (self.after_sha256) |*value| value else null;
    }
};

pub const Context = struct {
    io: std.Io,
    allocator: Allocator,
    config: core_config.Config,
    operation_id: []const u8,
    operation_dir: []const u8,
    artifact_dir: []const u8,
    project_id: []const u8,
    resource_id: []const u8,
    unit: systemd.Unit,
};

pub fn install(
    ctx: Context,
    artifact_path: []const u8,
    expected_rendered: []const u8,
    expected_sha256: []const u8,
    managed: ?*const db_store.NobManagedUnit,
) !Result {
    if (!ctx.config.nob_allow_system_mutation) return error.SystemMutationDisabled;
    if (ctx.unit.scope != .user) return error.UnsupportedPrivilege;
    if (expected_rendered.len == 0 or expected_rendered.len > max_unit_bytes) return error.InvalidUnitContent;
    try validateSha256(expected_sha256);
    try validateOwnershipMarker(expected_rendered, ctx.project_id, ctx.resource_id);

    const artifact = try readArtifact(ctx, artifact_path);
    defer ctx.allocator.free(artifact);
    if (!std.mem.eql(u8, artifact, expected_rendered)) return error.UnitArtifactContentMismatch;
    var artifact_digest: [64]u8 = undefined;
    hashBytes(artifact, &artifact_digest);
    if (!std.mem.eql(u8, &artifact_digest, expected_sha256)) return error.UnitArtifactDigestMismatch;

    var existing = try inspectExisting(ctx);
    defer existing.deinit(ctx.allocator);
    try validateExistingOwnership(ctx, &existing, managed);
    if (managed == null and existing.bytes != null and !std.mem.eql(u8, existing.bytes.?, expected_rendered)) {
        return error.ManagedUnitOwnershipUnrecorded;
    }
    if (existing.bytes) |bytes| {
        if (std.mem.eql(u8, bytes, expected_rendered)) {
            var controller = try systemd.Controller.init(ctx.io, ctx.allocator, ctx.config, ctx.operation_dir);
            defer controller.deinit();
            try controller.daemonReload(.user);
            return .{
                .before_sha256 = existing.sha256,
                .after_sha256 = artifact_digest,
                .fragment_path = try ctx.allocator.dupe(u8, existing.path),
            };
        }
    }

    const temporary_path = try temporaryPath(ctx, existing.path, "install");
    defer ctx.allocator.free(temporary_path);
    const backup_path = try temporaryPath(ctx, existing.path, "backup");
    defer ctx.allocator.free(backup_path);
    try writeExclusive(ctx, temporary_path, artifact, 0o644);
    var moved_existing = false;
    if (existing.bytes != null) {
        try std.Io.Dir.cwd().rename(existing.path, std.Io.Dir.cwd(), backup_path, ctx.io);
        moved_existing = true;
    }
    errdefer {
        std.Io.Dir.cwd().deleteFile(ctx.io, temporary_path) catch {};
        if (moved_existing) std.Io.Dir.cwd().rename(backup_path, std.Io.Dir.cwd(), existing.path, ctx.io) catch {};
    }
    try std.Io.Dir.cwd().rename(temporary_path, std.Io.Dir.cwd(), existing.path, ctx.io);

    var controller = try systemd.Controller.init(ctx.io, ctx.allocator, ctx.config, ctx.operation_dir);
    defer controller.deinit();
    controller.daemonReload(.user) catch |err| {
        std.Io.Dir.cwd().deleteFile(ctx.io, existing.path) catch {};
        if (moved_existing) std.Io.Dir.cwd().rename(backup_path, std.Io.Dir.cwd(), existing.path, ctx.io) catch {};
        controller.daemonReload(.user) catch {};
        return err;
    };
    if (moved_existing) try std.Io.Dir.cwd().deleteFile(ctx.io, backup_path);
    return .{
        .before_sha256 = existing.sha256,
        .after_sha256 = artifact_digest,
        .fragment_path = try ctx.allocator.dupe(u8, existing.path),
    };
}

pub fn remove(
    ctx: Context,
    expected_current_sha256: []const u8,
    managed: *const db_store.NobManagedUnit,
) !Result {
    if (!ctx.config.nob_allow_system_mutation) return error.SystemMutationDisabled;
    if (ctx.unit.scope != .user) return error.UnsupportedPrivilege;
    try validateSha256(expected_current_sha256);
    var existing = try inspectExisting(ctx);
    defer existing.deinit(ctx.allocator);
    try validateExistingOwnership(ctx, &existing, managed);
    const before = existing.sha256 orelse return error.ManagedUnitMissing;
    if (!std.mem.eql(u8, &before, expected_current_sha256)) return error.ManagedUnitChanged;

    const backup_path = try temporaryPath(ctx, existing.path, "remove");
    defer ctx.allocator.free(backup_path);
    try std.Io.Dir.cwd().rename(existing.path, std.Io.Dir.cwd(), backup_path, ctx.io);
    errdefer std.Io.Dir.cwd().rename(backup_path, std.Io.Dir.cwd(), existing.path, ctx.io) catch {};
    var controller = try systemd.Controller.init(ctx.io, ctx.allocator, ctx.config, ctx.operation_dir);
    defer controller.deinit();
    controller.daemonReload(.user) catch |err| {
        std.Io.Dir.cwd().rename(backup_path, std.Io.Dir.cwd(), existing.path, ctx.io) catch {};
        controller.daemonReload(.user) catch {};
        return err;
    };
    try std.Io.Dir.cwd().deleteFile(ctx.io, backup_path);
    return .{
        .before_sha256 = before,
        .after_sha256 = null,
        .fragment_path = try ctx.allocator.dupe(u8, existing.path),
    };
}

fn inspectExisting(ctx: Context) !Existing {
    const config_home = try configHome(ctx);
    defer ctx.allocator.free(config_home);
    const unit_directory = try std.fs.path.join(ctx.allocator, &.{ config_home, "systemd", "user" });
    defer ctx.allocator.free(unit_directory);
    try std.Io.Dir.cwd().createDirPath(ctx.io, config_home);
    const canonical_config_home = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, config_home, ctx.allocator);
    defer ctx.allocator.free(canonical_config_home);
    try std.Io.Dir.cwd().createDirPath(ctx.io, unit_directory);
    const canonical_directory = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, unit_directory, ctx.allocator);
    defer ctx.allocator.free(canonical_directory);
    if (!strictDescendant(canonical_config_home, canonical_directory)) return error.UnitDirectoryEscapesConfigHome;
    const path = try std.fs.path.join(ctx.allocator, &.{ canonical_directory, ctx.unit.name });
    errdefer ctx.allocator.free(path);
    if (!strictDescendant(canonical_directory, path)) return error.UnitPathEscapesRoot;
    const bytes = readRegularFile(ctx.io, ctx.allocator, path, max_unit_bytes) catch |err| switch (err) {
        error.FileNotFound => return .{ .path = path, .bytes = null, .sha256 = null },
        else => |other| return other,
    };
    var digest: [64]u8 = undefined;
    hashBytes(bytes, &digest);
    return .{ .path = path, .bytes = bytes, .sha256 = digest };
}

fn validateExistingOwnership(ctx: Context, existing: *const Existing, managed: ?*const db_store.NobManagedUnit) !void {
    if (managed) |record| {
        if (!std.mem.eql(u8, record.scope, "user") or
            !std.mem.eql(u8, record.unit, ctx.unit.name) or
            !std.mem.eql(u8, record.fragment_path, existing.path)) return error.ManagedUnitIdentityMismatch;
        const digest = existing.digest() orelse return error.ManagedUnitMissing;
        if (!std.mem.eql(u8, digest, record.sha256)) return error.ManagedUnitChanged;
        try validateOwnershipMarker(existing.bytes.?, ctx.project_id, ctx.resource_id);
        return;
    }
    if (existing.bytes != null) {
        try validateOwnershipMarker(existing.bytes.?, ctx.project_id, ctx.resource_id);
    }
}

fn readArtifact(ctx: Context, path: []const u8) ![]u8 {
    if (!std.fs.path.isAbsolute(path)) return error.InvalidUnitArtifactPath;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, ctx.artifact_dir, ctx.allocator);
    defer ctx.allocator.free(root);
    const canonical = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, path, ctx.allocator);
    defer ctx.allocator.free(canonical);
    if (!strictDescendant(root, canonical)) return error.UnitArtifactOutsideOperation;
    return try readRegularFile(ctx.io, ctx.allocator, canonical, max_unit_bytes);
}

fn readRegularFile(io: std.Io, allocator: Allocator, path: []const u8, maximum: usize) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{ .follow_symlinks = false });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > maximum) return error.InvalidUnitFile;
    var buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return try reader.interface.allocRemaining(allocator, .limited(maximum));
}

fn writeExclusive(ctx: Context, path: []const u8, bytes: []const u8, mode: u16) !void {
    const file = try std.Io.Dir.cwd().createFile(ctx.io, path, .{
        .exclusive = true,
        .permissions = @fromBackingInt(@intCast(mode)),
    });
    defer file.close(ctx.io);
    try file.writeStreamingAll(ctx.io, bytes);
}

fn temporaryPath(ctx: Context, target: []const u8, suffix: []const u8) ![]u8 {
    return try std.fmt.allocPrint(ctx.allocator, "{s}.nob-{s}-{s}", .{ target, ctx.operation_id, suffix });
}

fn configHome(ctx: Context) ![]u8 {
    if (ctx.config.runtime_environment.xdg_config_home) |path| {
        if (!std.fs.path.isAbsolute(path)) return error.InvalidConfigHome;
        return try ctx.allocator.dupe(u8, path);
    }
    const home = ctx.config.runtime_environment.home orelse return error.ConfigHomeUnavailable;
    if (!std.fs.path.isAbsolute(home)) return error.InvalidConfigHome;
    return try std.fs.path.join(ctx.allocator, &.{ home, ".config" });
}

fn validateOwnershipMarker(rendered: []const u8, project_id: []const u8, resource_id: []const u8) !void {
    var section = false;
    var project = false;
    var resource = false;
    var version = false;
    var manager = false;
    var lines = std.mem.splitScalar(u8, rendered, '\n');
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '[') {
            section = std.mem.eql(u8, line, "[X-Nob]");
            continue;
        }
        if (!section) continue;
        if (std.mem.startsWith(u8, line, "ProjectID=")) project = std.mem.eql(u8, line["ProjectID=".len..], project_id);
        if (std.mem.startsWith(u8, line, "ResourceID=")) resource = std.mem.eql(u8, line["ResourceID=".len..], resource_id);
        if (std.mem.startsWith(u8, line, "ManifestVersion=")) version = std.mem.eql(u8, line["ManifestVersion=".len..], "1");
        if (std.mem.startsWith(u8, line, "ManagedBy=")) manager = std.mem.eql(u8, line["ManagedBy=".len..], "cloudio");
    }
    if (!project or !resource or !version or !manager) return error.InvalidOwnershipMarker;
}

fn hashBytes(bytes: []const u8, output: *[64]u8) void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    _ = std.fmt.bufPrint(output, "{x}", .{digest}) catch unreachable;
}

fn validateSha256(value: []const u8) !void {
    if (value.len != 64) return error.InvalidUnitDigest;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return error.InvalidUnitDigest;
}

fn strictDescendant(root: []const u8, path: []const u8) bool {
    if (path.len <= root.len or !std.mem.startsWith(u8, path, root)) return false;
    return root[root.len - 1] == std.fs.path.sep or path[root.len] == std.fs.path.sep;
}

test "ownership marker validation requires all exact identities" {
    const valid = "[Unit]\nDescription=Demo\n\n[X-Nob]\nProjectID=dev.example.demo\nResourceID=service\nManifestVersion=1\nManagedBy=cloudio\n";
    try validateOwnershipMarker(valid, "dev.example.demo", "service");
    try std.testing.expectError(error.InvalidOwnershipMarker, validateOwnershipMarker(valid, "dev.example.other", "service"));
}
