const std = @import("std");
const core_time = @import("core_time");
const db_store = @import("db_store");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Options = struct {
    scan_depth: u8 = 3,
};

pub const Result = struct {
    scan_id: [32]u8,
    projects_seen: usize = 0,
    valid: usize = 0,
    invalid: usize = 0,
    candidates: usize = 0,
    conflicts: usize = 0,
    missing: usize = 0,
    unreadable_directories: usize = 0,
    skipped_symlinks: usize = 0,
};

const ScanContext = struct {
    io: Io,
    arena: Allocator,
    db: *db_store.Db,
    options: Options,
    scan_id: []const u8,
    now: i64,
    result: *Result,
};

pub fn scan(io: Io, allocator: Allocator, db: *db_store.Db, root_path: []const u8, options: Options) !Result {
    const epoch = try core_time.currentEpochSeconds();
    return scanAt(io, allocator, db, root_path, options, @intCast(epoch));
}

pub fn scanAt(
    io: Io,
    allocator: Allocator,
    db: *db_store.Db,
    root_path: []const u8,
    options: Options,
    now: i64,
) !Result {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const canonical_root_z = try Io.Dir.cwd().realPathFileAlloc(io, root_path, arena);
    const canonical_root: []const u8 = canonical_root_z;

    var result = Result{ .scan_id = undefined };
    var random: [16]u8 = undefined;
    io.random(&random);
    _ = try std.fmt.bufPrint(&result.scan_id, "{x}", .{random});

    var ctx = ScanContext{
        .io = io,
        .arena = arena,
        .db = db,
        .options = options,
        .scan_id = &result.scan_id,
        .now = now,
        .result = &result,
    };
    try scanDirectory(&ctx, canonical_root, 0, true);
    result.missing = try db.nob().markMissing(canonical_root, ctx.scan_id, now);
    result.conflicts = try db.nob().markDeclaredIdConflicts(ctx.scan_id, now);
    return result;
}

fn scanDirectory(ctx: *ScanContext, dir_path: []const u8, depth: u8, is_root: bool) !void {
    var dir = Io.Dir.cwd().openDir(ctx.io, dir_path, .{ .iterate = true }) catch |err| {
        if (is_root) return err;
        ctx.result.unreadable_directories += 1;
        return;
    };
    defer dir.close(ctx.io);

    var has_manifest = false;
    var manifest_regular = false;
    var is_candidate = false;
    var children = std.ArrayList([]const u8).empty;
    defer children.deinit(ctx.arena);

    var iterator = dir.iterate();
    while (try iterator.next(ctx.io)) |entry| {
        if (std.mem.eql(u8, entry.name, "nob.json")) {
            has_manifest = true;
            manifest_regular = entry.kind == .file;
            continue;
        }
        if (isCandidateMarker(entry.name, entry.kind)) is_candidate = true;
        if (entry.kind == .sym_link) {
            ctx.result.skipped_symlinks += 1;
            continue;
        }
        if (entry.kind != .directory or depth >= ctx.options.scan_depth or shouldSkipDirectory(entry.name)) continue;
        try children.append(ctx.arena, try std.fs.path.join(ctx.arena, &.{ dir_path, entry.name }));
    }

    if (has_manifest) {
        try recordManifest(ctx, dir_path, manifest_regular);
        return;
    }
    if (is_candidate) try recordCandidate(ctx, dir_path);

    for (children.items) |child| try scanDirectory(ctx, child, depth + 1, false);
}

fn recordManifest(ctx: *ScanContext, root_path: []const u8, regular: bool) !void {
    ctx.result.projects_seen += 1;
    const manifest_path = try std.fs.path.join(ctx.arena, &.{ root_path, "nob.json" });
    if (!regular) {
        ctx.result.invalid += 1;
        _ = try ctx.db.nob().recordDiscovery(.{
            .declared_id = null,
            .display_name = candidateName(root_path),
            .kind = "unknown",
            .root_path = root_path,
            .manifest_path = manifest_path,
            .manifest_sha256 = null,
            .manifest_json = null,
            .discovery_state = .invalid,
            .diagnosis = "nob.json is not a regular file",
            .scan_id = ctx.scan_id,
            .seen_at = ctx.now,
        });
        return;
    }

    const bytes = Io.Dir.cwd().readFileAlloc(
        ctx.io,
        manifest_path,
        ctx.arena,
        .limited(nob.manifest.max_manifest_bytes),
    ) catch |err| {
        ctx.result.invalid += 1;
        const diagnosis = try std.fmt.allocPrint(ctx.arena, "manifest read failed: {s}", .{@errorName(err)});
        _ = try ctx.db.nob().recordDiscovery(.{
            .declared_id = null,
            .display_name = candidateName(root_path),
            .kind = "unknown",
            .root_path = root_path,
            .manifest_path = manifest_path,
            .manifest_sha256 = null,
            .manifest_json = null,
            .discovery_state = .invalid,
            .diagnosis = diagnosis,
            .scan_id = ctx.scan_id,
            .seen_at = ctx.now,
        });
        return;
    };

    var digest_bytes: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest_bytes, .{});
    const digest = try std.fmt.allocPrint(ctx.arena, "{x}", .{digest_bytes});

    var document = nob.parseManifest(ctx.arena, bytes) catch |err| {
        ctx.result.invalid += 1;
        const diagnosis = try std.fmt.allocPrint(ctx.arena, "manifest validation failed: {s}", .{@errorName(err)});
        _ = try ctx.db.nob().recordDiscovery(.{
            .declared_id = null,
            .display_name = candidateName(root_path),
            .kind = "unknown",
            .root_path = root_path,
            .manifest_path = manifest_path,
            .manifest_sha256 = digest,
            .manifest_json = bytes,
            .discovery_state = .invalid,
            .diagnosis = diagnosis,
            .scan_id = ctx.scan_id,
            .seen_at = ctx.now,
        });
        return;
    };
    defer document.deinit();
    const manifest = document.value();

    var resources = std.ArrayList(db_store.NobResourceDeclaration).empty;
    defer resources.deinit(ctx.arena);
    for (manifest.resources) |resource| {
        try resources.append(ctx.arena, .{
            .resource_id = resource.id,
            .kind = @tagName(resource.kind),
            .label = resource.label,
            .ownership = @tagName(resource.ownership),
            .controls_json = try stringify(ctx.arena, resource.controls),
            .declaration_json = try stringify(ctx.arena, resource),
        });
    }

    var actions = std.ArrayList(db_store.NobActionDeclaration).empty;
    defer actions.deinit(ctx.arena);
    for (manifest.actions) |action| {
        try actions.append(ctx.arena, .{
            .action_id = action.id,
            .label = action.label,
            .effect = @tagName(action.effect),
            .confirmation = @tagName(action.confirmation),
            .declaration_json = try stringify(ctx.arena, action),
        });
    }

    _ = try ctx.db.nob().recordDiscovery(.{
        .declared_id = manifest.project.id,
        .display_name = manifest.project.display_name,
        .kind = @tagName(manifest.project.kind),
        .root_path = root_path,
        .manifest_path = manifest_path,
        .manifest_sha256 = digest,
        .manifest_json = bytes,
        .discovery_state = .valid,
        .protocol_major = manifest.runner.protocol.major,
        .protocol_minor = manifest.runner.protocol.minor,
        .scan_id = ctx.scan_id,
        .seen_at = ctx.now,
        .replace_declarations = true,
        .resources = resources.items,
        .actions = actions.items,
    });
    ctx.result.valid += 1;
}

fn recordCandidate(ctx: *ScanContext, root_path: []const u8) !void {
    ctx.result.projects_seen += 1;
    ctx.result.candidates += 1;
    _ = try ctx.db.nob().recordDiscovery(.{
        .declared_id = null,
        .display_name = candidateName(root_path),
        .kind = "unknown",
        .root_path = root_path,
        .manifest_path = null,
        .manifest_sha256 = null,
        .manifest_json = null,
        .discovery_state = .candidate,
        .diagnosis = "project marker found; add nob.json to enroll",
        .scan_id = ctx.scan_id,
        .seen_at = ctx.now,
    });
}

fn stringify(allocator: Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return try output.toOwnedSlice();
}

fn candidateName(path: []const u8) []const u8 {
    const name = std.fs.path.basename(path);
    return if (name.len == 0) path else name;
}

fn isCandidateMarker(name: []const u8, kind: std.Io.File.Kind) bool {
    if (std.mem.eql(u8, name, ".git")) return kind == .directory or kind == .file;
    if (kind != .file) return false;
    return std.mem.eql(u8, name, "build.zig") or
        std.mem.eql(u8, name, "compose.yml") or
        std.mem.eql(u8, name, "compose.yaml") or
        std.mem.eql(u8, name, "docker-compose.yml") or
        std.mem.eql(u8, name, "docker-compose.yaml");
}

fn shouldSkipDirectory(name: []const u8) bool {
    if (name.len != 0 and name[0] == '.') return true;
    const skipped = [_][]const u8{
        "zig-cache",
        "zig-out",
        "node_modules",
        "target",
        "vendor",
        "zig-pkg",
    };
    for (skipped) |item| if (std.mem.eql(u8, name, item)) return true;
    return false;
}

test "candidate markers are conservative and cache directories are skipped" {
    try std.testing.expect(isCandidateMarker("build.zig", .file));
    try std.testing.expect(isCandidateMarker(".git", .directory));
    try std.testing.expect(!isCandidateMarker("build.zig", .directory));
    try std.testing.expect(shouldSkipDirectory(".zig-cache"));
    try std.testing.expect(shouldSkipDirectory("node_modules"));
    try std.testing.expect(!shouldSkipDirectory("src"));
}

test "passive scan persists declarations and enforces trust digest transitions" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/projects", .{tmp.sub_path});
    defer allocator.free(root);
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/scan.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    try Io.Dir.cwd().createDirPath(io, root);

    const valid_fixture = try Io.Dir.cwd().readFileAlloc(
        io,
        "vendor/nob/schema/fixtures/manifest-service-valid.json",
        allocator,
        .limited(nob.manifest.max_manifest_bytes),
    );
    defer allocator.free(valid_fixture);
    const invalid_fixture = try Io.Dir.cwd().readFileAlloc(
        io,
        "vendor/nob/schema/fixtures/manifest-duplicate-key-invalid.json",
        allocator,
        .limited(nob.manifest.max_manifest_bytes),
    );
    defer allocator.free(invalid_fixture);

    const good_dir = try std.fs.path.join(allocator, &.{ root, "good" });
    defer allocator.free(good_dir);
    const invalid_dir = try std.fs.path.join(allocator, &.{ root, "invalid" });
    defer allocator.free(invalid_dir);
    const candidate_dir = try std.fs.path.join(allocator, &.{ root, "candidate" });
    defer allocator.free(candidate_dir);
    const skipped_dir = try std.fs.path.join(allocator, &.{ root, "vendor", "ignored" });
    defer allocator.free(skipped_dir);
    try Io.Dir.cwd().createDirPath(io, good_dir);
    try Io.Dir.cwd().createDirPath(io, invalid_dir);
    try Io.Dir.cwd().createDirPath(io, candidate_dir);
    try Io.Dir.cwd().createDirPath(io, skipped_dir);

    const good_manifest = try std.fs.path.join(allocator, &.{ good_dir, "nob.json" });
    defer allocator.free(good_manifest);
    const invalid_manifest = try std.fs.path.join(allocator, &.{ invalid_dir, "nob.json" });
    defer allocator.free(invalid_manifest);
    const poison_build = try std.fs.path.join(allocator, &.{ candidate_dir, "build.zig" });
    defer allocator.free(poison_build);
    const skipped_manifest = try std.fs.path.join(allocator, &.{ skipped_dir, "nob.json" });
    defer allocator.free(skipped_manifest);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = good_manifest, .data = valid_fixture });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = invalid_manifest, .data = invalid_fixture });
    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = poison_build,
        .data = "comptime { @compileError(\"passive scanner executed project code\"); }",
    });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = skipped_manifest, .data = valid_fixture });

    var db = try db_store.Db.open(io, db_path);
    defer db.close();
    try db.initSchema();

    const first = try scanAt(io, allocator, &db, root, .{}, 100);
    try std.testing.expectEqual(@as(usize, 3), first.projects_seen);
    try std.testing.expectEqual(@as(usize, 1), first.valid);
    try std.testing.expectEqual(@as(usize, 1), first.invalid);
    try std.testing.expectEqual(@as(usize, 1), first.candidates);

    const canonical_good_z = try Io.Dir.cwd().realPathFileAlloc(io, good_dir, allocator);
    defer allocator.free(canonical_good_z);
    var project = (try db.nob().getProjectByRoot(allocator, canonical_good_z)).?;
    defer project.deinit(allocator);
    try std.testing.expectEqual(db_store.NobDiscoveryState.valid, project.discovery_state);
    try std.testing.expectEqual(db_store.NobTrustState.discovered, project.trust_state);
    try std.testing.expectEqualStrings("dev.example.service", project.declared_id.?);

    var resources = try db.nob().listResources(allocator, project.id);
    defer resources.deinit(allocator);
    var actions = try db.nob().listActions(allocator, project.id);
    defer actions.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), resources.items.len);
    try std.testing.expectEqual(@as(usize, 2), actions.items.len);
    try std.testing.expectEqualStrings("systemd.service", resources.items[1].kind);

    try std.testing.expect(try db.nob().trust(project.id, project.manifest_sha256.?, "test-user", 101));
    const changed_manifest = try std.fmt.allocPrint(allocator, "{s}\n", .{valid_fixture});
    defer allocator.free(changed_manifest);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = good_manifest, .data = changed_manifest });
    _ = try scanAt(io, allocator, &db, root, .{}, 102);

    project.deinit(allocator);
    project = (try db.nob().getProjectByRoot(allocator, canonical_good_z)).?;
    try std.testing.expectEqual(db_store.NobTrustState.@"review-required", project.trust_state);
    try std.testing.expect(try db.nob().trust(project.id, project.manifest_sha256.?, "test-user", 103));

    const duplicate_dir = try std.fs.path.join(allocator, &.{ root, "duplicate" });
    defer allocator.free(duplicate_dir);
    const duplicate_manifest = try std.fs.path.join(allocator, &.{ duplicate_dir, "nob.json" });
    defer allocator.free(duplicate_manifest);
    try Io.Dir.cwd().createDirPath(io, duplicate_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = duplicate_manifest, .data = changed_manifest });
    const duplicate_scan = try scanAt(io, allocator, &db, root, .{}, 104);
    try std.testing.expectEqual(@as(usize, 2), duplicate_scan.conflicts);

    project.deinit(allocator);
    project = (try db.nob().getProjectByRoot(allocator, canonical_good_z)).?;
    try std.testing.expectEqual(db_store.NobDiscoveryState.conflict, project.discovery_state);

    try Io.Dir.cwd().deleteFile(io, duplicate_manifest);
    _ = try scanAt(io, allocator, &db, root, .{}, 105);
    project.deinit(allocator);
    project = (try db.nob().getProjectByRoot(allocator, canonical_good_z)).?;
    try std.testing.expectEqual(db_store.NobDiscoveryState.valid, project.discovery_state);

    try Io.Dir.cwd().deleteFile(io, good_manifest);
    _ = try scanAt(io, allocator, &db, root, .{}, 106);
    project.deinit(allocator);
    project = (try db.nob().getProjectByRoot(allocator, canonical_good_z)).?;
    try std.testing.expectEqual(db_store.NobDiscoveryState.missing, project.discovery_state);
    try std.testing.expectEqualStrings("missing", project.status.text());
}
