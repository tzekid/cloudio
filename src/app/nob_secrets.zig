const std = @import("std");
const app_nob_projects = @import("app_nob_projects");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const max_secret_bytes = 64 * 1024;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
};

pub const SourceKind = enum { file, @"process-environment" };

pub const Item = struct {
    id: []u8,
    value: []u8,

    fn deinit(self: Item, allocator: Allocator) void {
        allocator.free(self.id);
        std.crypto.secureZero(u8, self.value);
        allocator.free(self.value);
    }
};

pub const Resolution = struct {
    items: []Item,
    available_csv: []u8,

    pub fn deinit(self: *Resolution, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
        allocator.free(self.available_csv);
    }

    pub fn find(self: *const Resolution, id: []const u8) ?[]const u8 {
        for (self.items) |item| if (std.mem.eql(u8, item.id, id)) return item.value;
        return null;
    }

    pub fn redactionValues(self: *const Resolution, allocator: Allocator) ![]const []const u8 {
        const result = try allocator.alloc([]const u8, self.items.len);
        for (self.items, 0..) |item, index| result[index] = item.value;
        return result;
    }
};

pub fn bind(
    ctx: Context,
    project_reference: []const u8,
    secret_id: []const u8,
    source_kind_text: []const u8,
    source_ref: []const u8,
    actor: []const u8,
) !void {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    var manifest_document = try trustedManifest(ctx, project);
    defer manifest_document.deinit();
    if (findSecret(manifest_document.value().secrets, secret_id) == null) return error.UndeclaredSecret;
    const source_kind = std.meta.stringToEnum(SourceKind, source_kind_text) orelse return error.InvalidSecretSourceKind;
    try validateSourceRef(source_kind, source_ref);
    const value = try readSource(ctx, source_kind, source_ref);
    defer {
        std.crypto.secureZero(u8, value);
        ctx.gpa.free(value);
    }
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    try ctx.db.nob().upsertSecretBinding(.{
        .project_id = project.id,
        .secret_id = secret_id,
        .source_kind = @tagName(source_kind),
        .source_ref = source_ref,
        .present = true,
        .bound_by = actor,
        .now = now,
    });
    const detail = try std.fmt.allocPrint(ctx.gpa, "project={d} secret={s} source={s} present={s}", .{
        project.id,
        secret_id,
        @tagName(source_kind),
        "yes",
    });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.secret.bind", "ok", detail);
}

pub fn unbind(ctx: Context, project_reference: []const u8, secret_id: []const u8, actor: []const u8) !void {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    if (!try ctx.db.nob().deleteSecretBinding(project.id, secret_id)) return error.SecretBindingNotFound;
    const detail = try std.fmt.allocPrint(ctx.gpa, "project={d} secret={s} actor={s}", .{ project.id, secret_id, actor });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.secret.unbind", "ok", detail);
}

pub fn writeJson(ctx: Context, project_reference: []const u8, writer: *std.Io.Writer) !void {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    var manifest_document = try trustedManifest(ctx, project);
    defer manifest_document.deinit();
    var bindings = try ctx.db.nob().listSecretBindings(ctx.gpa, project.id);
    defer bindings.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_secret_bindings\",\"items\":[");
    for (manifest_document.value().secrets, 0..) |secret, index| {
        if (index != 0) try writer.writeByte(',');
        const binding = findBinding(bindings.items, secret.id);
        try writer.writeAll("{\"secret_id\":");
        try std.json.Stringify.value(secret.id, .{}, writer);
        try writer.writeAll(",\"purpose\":");
        try std.json.Stringify.value(secret.purpose, .{}, writer);
        try writer.writeAll(",\"required_for\":");
        try std.json.Stringify.value(secret.required_for, .{}, writer);
        try writer.writeAll(",\"delivery\":\"file\",\"bound\":");
        try writer.writeAll(if (binding != null) "true" else "false");
        try writer.writeAll(",\"source_kind\":");
        try std.json.Stringify.value(if (binding) |value| value.source_kind else null, .{}, writer);
        try writer.writeAll(",\"present\":");
        try writer.writeAll(if (binding) |value| if (value.present) "true" else "false" else "false");
        try writer.writeAll(",\"checked_at\":");
        try std.json.Stringify.value(if (binding) |value| value.checked_at else null, .{}, writer);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeText(ctx: Context, project_reference: []const u8, writer: *std.Io.Writer) !void {
    const project = (try app_nob_projects.find(projectContext(ctx), project_reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    var manifest_document = try trustedManifest(ctx, project);
    defer manifest_document.deinit();
    var bindings = try ctx.db.nob().listSecretBindings(ctx.gpa, project.id);
    defer bindings.deinit(ctx.gpa);
    for (manifest_document.value().secrets) |secret| {
        const binding = findBinding(bindings.items, secret.id);
        try writer.print("{s}  {s}  {s}  {s}\n", .{
            secret.id,
            if (binding == null) "unbound" else if (binding.?.present) "present" else "unavailable",
            if (binding) |value| value.source_kind else "-",
            secret.purpose,
        });
    }
    if (manifest_document.value().secrets.len == 0) try writer.writeAll("this project declares no secrets\n");
}

pub fn resolve(ctx: Context, project_id: i64, manifest: *const nob.types.Manifest) !Resolution {
    var bindings = try ctx.db.nob().listSecretBindings(ctx.gpa, project_id);
    defer bindings.deinit(ctx.gpa);
    var items = std.ArrayList(Item).empty;
    errdefer {
        for (items.items) |item| item.deinit(ctx.gpa);
        items.deinit(ctx.gpa);
    }
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    for (bindings.items) |binding| {
        if (findSecret(manifest.secrets, binding.secret_id) == null) continue;
        const source_kind = std.meta.stringToEnum(SourceKind, binding.source_kind) orelse {
            try ctx.db.nob().updateSecretPresence(project_id, binding.secret_id, false, now);
            continue;
        };
        const value = readSource(ctx, source_kind, binding.source_ref) catch {
            try ctx.db.nob().updateSecretPresence(project_id, binding.secret_id, false, now);
            continue;
        };
        errdefer {
            std.crypto.secureZero(u8, value);
            ctx.gpa.free(value);
        }
        try ctx.db.nob().updateSecretPresence(project_id, binding.secret_id, true, now);
        try items.append(ctx.gpa, .{
            .id = try ctx.gpa.dupe(u8, binding.secret_id),
            .value = value,
        });
    }
    std.mem.sort(Item, items.items, {}, itemLessThan);
    var csv = std.Io.Writer.Allocating.init(ctx.gpa);
    errdefer csv.deinit();
    for (items.items, 0..) |item, index| {
        if (index != 0) try csv.writer.writeByte(',');
        try csv.writer.writeAll(item.id);
    }
    const available_csv = try csv.toOwnedSlice();
    errdefer ctx.gpa.free(available_csv);
    return .{ .items = try items.toOwnedSlice(ctx.gpa), .available_csv = available_csv };
}

pub fn materialize(
    ctx: Context,
    resolution: *const Resolution,
    manifest: *const nob.types.Manifest,
    action_id: []const u8,
    operation_dir: []const u8,
) !?[]u8 {
    var required_count: usize = 0;
    for (manifest.secrets) |secret| {
        if (containsString(secret.required_for, action_id)) required_count += 1;
    }
    if (required_count == 0) return null;
    const secret_dir = try std.fs.path.join(ctx.gpa, &.{ operation_dir, "secrets" });
    errdefer ctx.gpa.free(secret_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, secret_dir);
    var directory = try std.Io.Dir.cwd().openDir(ctx.io, secret_dir, .{ .iterate = true });
    defer directory.close(ctx.io);
    try directory.setPermissions(ctx.io, @fromBackingInt(@intCast(0o700)));
    errdefer std.Io.Dir.cwd().deleteTree(ctx.io, secret_dir) catch {};
    for (manifest.secrets) |secret| {
        if (!containsString(secret.required_for, action_id)) continue;
        const value = resolution.find(secret.id) orelse return error.RequiredSecretUnavailable;
        const path = try std.fs.path.join(ctx.gpa, &.{ secret_dir, secret.id });
        defer ctx.gpa.free(path);
        if (!strictDescendant(secret_dir, path)) return error.SecretPathEscapesRoot;
        const file = try std.Io.Dir.cwd().createFile(ctx.io, path, .{
            .exclusive = true,
            .permissions = @fromBackingInt(@intCast(0o400)),
        });
        defer file.close(ctx.io);
        try file.writeStreamingAll(ctx.io, value);
    }
    return secret_dir;
}

pub fn requireForAction(resolution: *const Resolution, manifest: *const nob.types.Manifest, action_id: []const u8) !void {
    for (manifest.secrets) |secret| {
        if (containsString(secret.required_for, action_id) and resolution.find(secret.id) == null) {
            return error.RequiredSecretUnavailable;
        }
    }
}

pub fn removeMaterialized(ctx: Context, secret_dir: ?[]const u8, operation_dir: []const u8) void {
    const path = secret_dir orelse return;
    if (strictDescendant(operation_dir, path)) std.Io.Dir.cwd().deleteTree(ctx.io, path) catch {};
}

fn trustedManifest(ctx: Context, project: db_store.NobProject) !nob.ManifestDocument {
    if (project.discovery_state != .valid or project.trust_state != .trusted) return error.ProjectNotTrusted;
    const expected = project.manifest_sha256 orelse return error.ManifestUnavailable;
    if (project.trusted_manifest_sha256 == null or !std.mem.eql(u8, expected, project.trusted_manifest_sha256.?)) return error.ManifestDigestMismatch;
    const path = try std.fs.path.join(ctx.gpa, &.{ project.root_path, "nob.json" });
    defer ctx.gpa.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.gpa, .limited(nob.manifest.max_manifest_bytes));
    defer ctx.gpa.free(bytes);
    var document = try nob.parseManifest(ctx.gpa, bytes);
    errdefer document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, document.sha256Hex(&digest_buffer), expected)) return error.ManifestDigestMismatch;
    return document;
}

fn readSource(ctx: Context, source_kind: SourceKind, source_ref: []const u8) ![]u8 {
    try validateSourceRef(source_kind, source_ref);
    return switch (source_kind) {
        .file => readSecretFile(ctx, source_ref),
        .@"process-environment" => {
            const environment = ctx.config.process_environment orelse return error.ProcessEnvironmentUnavailable;
            const value = environment.get(source_ref) orelse return error.SecretSourceUnavailable;
            if (value.len == 0 or value.len > max_secret_bytes) return error.InvalidSecretValue;
            return try ctx.gpa.dupe(u8, value);
        },
    };
}

fn readSecretFile(ctx: Context, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(ctx.io, path, .{ .follow_symlinks = false });
    defer file.close(ctx.io);
    const stat = try file.stat(ctx.io);
    if (stat.kind != .file or stat.size == 0 or stat.size > max_secret_bytes) return error.InvalidSecretFile;
    if (@backingInt(stat.permissions) & 0o077 != 0) return error.SecretFilePermissionsTooBroad;
    if (comptime @import("builtin").os.tag == .linux) {
        var metadata: std.os.linux.Statx = undefined;
        const rc = std.os.linux.statx(
            file.handle,
            "",
            std.os.linux.AT.EMPTY_PATH,
            .{ .TYPE = true, .MODE = true, .UID = true },
            &metadata,
        );
        if (std.os.linux.errno(rc) != .SUCCESS) return error.SecretSourceMetadataUnavailable;
        if (metadata.uid != std.os.linux.geteuid()) return error.SecretFileOwnerMismatch;
    } else return error.SecretSourceMetadataUnavailable;
    var buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(ctx.io, &buffer);
    return try reader.interface.allocRemaining(ctx.gpa, .limited(max_secret_bytes));
}

fn validateSourceRef(source_kind: SourceKind, value: []const u8) !void {
    if (value.len == 0 or value.len > 4096 or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidSecretSourceRef;
    switch (source_kind) {
        .file => if (!std.fs.path.isAbsolute(value)) return error.SecretSourcePathNotAbsolute,
        .@"process-environment" => {
            if (value.len > 128 or (!std.ascii.isAlphabetic(value[0]) and value[0] != '_')) return error.InvalidEnvironmentName;
            for (value[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return error.InvalidEnvironmentName;
            if (std.mem.startsWith(u8, value, "NOB_") or std.mem.startsWith(u8, value, "CLOUDIO_NOB_")) return error.ReservedEnvironmentName;
        },
    }
}

fn findSecret(secrets: []const nob.types.Secret, id: []const u8) ?*const nob.types.Secret {
    for (secrets) |*secret| if (std.mem.eql(u8, secret.id, id)) return secret;
    return null;
}

fn findBinding(bindings: []const db_store.NobSecretBinding, id: []const u8) ?*const db_store.NobSecretBinding {
    for (bindings) |*binding| if (std.mem.eql(u8, binding.secret_id, id)) return binding;
    return null;
}

fn containsString(values: []const []const u8, candidate: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, candidate)) return true;
    return false;
}

fn itemLessThan(_: void, left: Item, right: Item) bool {
    return std.mem.order(u8, left.id, right.id) == .lt;
}

fn strictDescendant(root: []const u8, path: []const u8) bool {
    if (path.len <= root.len or !std.mem.startsWith(u8, path, root)) return false;
    return root[root.len - 1] == std.fs.path.sep or path[root.len] == std.fs.path.sep;
}

fn projectContext(ctx: Context) app_nob_projects.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

test "secret source references are typed and bounded" {
    try validateSourceRef(.file, "/run/secrets/example");
    try validateSourceRef(.@"process-environment", "EXAMPLE_TOKEN");
    try std.testing.expectError(error.SecretSourcePathNotAbsolute, validateSourceRef(.file, "relative"));
    try std.testing.expectError(error.InvalidEnvironmentName, validateSourceRef(.@"process-environment", "BAD-NAME"));
    try std.testing.expectError(error.ReservedEnvironmentName, validateSourceRef(.@"process-environment", "NOB_BROKER_TOKEN_FILE"));
}

test "logical bindings never disclose sources and materialize only read-only action files" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const secret_value = "test-database-token-value";
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    const base_relative = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{temporary.sub_path});
    defer allocator.free(base_relative);
    const projects_root = try std.fs.path.join(allocator, &.{ base_relative, "projects" });
    defer allocator.free(projects_root);
    const project_root = try std.fs.path.join(allocator, &.{ projects_root, "service" });
    defer allocator.free(project_root);
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "nob.json" });
    defer allocator.free(manifest_path);
    const secret_relative = try std.fs.path.join(allocator, &.{ base_relative, "database-token" });
    defer allocator.free(secret_relative);
    const operation_dir = try std.fs.path.join(allocator, &.{ base_relative, "operation" });
    defer allocator.free(operation_dir);
    const db_path = try std.fs.path.join(allocator, &.{ base_relative, "cloudio.db" });
    defer allocator.free(db_path);
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "vendor/nob/schema/fixtures/manifest-service-valid.json",
        allocator,
        .limited(nob.manifest.max_manifest_bytes),
    );
    defer allocator.free(manifest_bytes);
    try std.Io.Dir.cwd().createDirPath(io, project_root);
    try std.Io.Dir.cwd().createDirPath(io, operation_dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = manifest_path, .data = manifest_bytes });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = secret_relative, .data = secret_value });
    try std.Io.Dir.cwd().setFilePermissions(io, secret_relative, @fromBackingInt(@intCast(0o600)), .{ .follow_symlinks = false });
    const secret_path = try std.Io.Dir.cwd().realPathFileAlloc(io, secret_relative, allocator);
    defer allocator.free(secret_path);

    var db = try db_store.Db.open(io, db_path);
    defer db.close();
    try db.initSchema();
    _ = try app_nob_projects.scan(projectContext(.{
        .io = io,
        .gpa = allocator,
        .db = &db,
        .config = .{ .domains = &.{} },
    }), io, projects_root, 4);
    var trust_document = try nob.parseManifest(allocator, manifest_bytes);
    defer trust_document.deinit();
    var digest_buffer: [64]u8 = undefined;
    try app_nob_projects.trust(
        .{ .gpa = allocator, .db = &db },
        "dev.example.service",
        trust_document.sha256Hex(&digest_buffer),
        "test",
    );

    const ctx = Context{ .io = io, .gpa = allocator, .db = &db, .config = .{ .domains = &.{} } };
    try bind(ctx, "dev.example.service", "database-token", "file", secret_path, "test");

    var rendered = std.Io.Writer.Allocating.init(allocator);
    defer rendered.deinit();
    try writeJson(ctx, "dev.example.service", &rendered.writer);
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), secret_path) == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), secret_value) == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.written(), "\"present\":true") != null);

    const project = (try app_nob_projects.find(.{ .gpa = allocator, .db = &db }, "dev.example.service")).?;
    defer project.deinit(allocator);
    var manifest = try nob.parseManifest(allocator, manifest_bytes);
    defer manifest.deinit();
    var resolution = try resolve(ctx, project.id, manifest.value());
    defer resolution.deinit(allocator);
    try requireForAction(&resolution, manifest.value(), "deploy");
    const secret_dir = (try materialize(ctx, &resolution, manifest.value(), "deploy", operation_dir)).?;
    defer allocator.free(secret_dir);
    defer removeMaterialized(ctx, secret_dir, operation_dir);
    const delivered_path = try std.fs.path.join(allocator, &.{ secret_dir, "database-token" });
    defer allocator.free(delivered_path);
    const delivered = try std.Io.Dir.cwd().readFileAlloc(io, delivered_path, allocator, .limited(max_secret_bytes));
    defer allocator.free(delivered);
    try std.testing.expectEqualStrings(secret_value, delivered);
    const delivered_file = try std.Io.Dir.cwd().openFile(io, delivered_path, .{ .follow_symlinks = false });
    defer delivered_file.close(io);
    const delivered_stat = try delivered_file.stat(io);
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o400), @backingInt(delivered_stat.permissions) & 0o777);
}
