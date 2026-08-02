const std = @import("std");
const app_render = @import("app_render");
const collector_project_manifests = @import("collector_project_manifests");
const core_time = @import("core_time");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    gpa: Allocator,
    db: *db_store.Db,
};

pub const Details = struct {
    project: db_store.NobProject,
    resources: db_store.NobResources,
    actions: db_store.NobActions,

    pub fn deinit(self: *Details, allocator: Allocator) void {
        self.project.deinit(allocator);
        self.resources.deinit(allocator);
        self.actions.deinit(allocator);
    }
};

pub fn list(ctx: Context) !db_store.NobProjects {
    return try ctx.db.nob().listProjects(ctx.gpa);
}

pub fn find(ctx: Context, reference: []const u8) !?db_store.NobProject {
    return try resolve(ctx, reference);
}

pub fn scan(ctx: Context, io: std.Io, root_path: []const u8, scan_depth: u8) !collector_project_manifests.Result {
    return try collector_project_manifests.scan(io, ctx.gpa, ctx.db, root_path, .{ .scan_depth = scan_depth });
}

pub fn show(ctx: Context, reference: []const u8) !?Details {
    const project = (try resolve(ctx, reference)) orelse return null;
    errdefer project.deinit(ctx.gpa);
    var resources = try ctx.db.nob().listResources(ctx.gpa, project.id);
    errdefer resources.deinit(ctx.gpa);
    var actions = try ctx.db.nob().listActions(ctx.gpa, project.id);
    errdefer actions.deinit(ctx.gpa);
    return .{ .project = project, .resources = resources, .actions = actions };
}

pub fn trust(ctx: Context, reference: []const u8, expected_manifest_sha256: []const u8, actor: []const u8) !void {
    const project = (try resolve(ctx, reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const actual = project.manifest_sha256 orelse return error.ManifestUnavailable;
    if (!std.mem.eql(u8, actual, expected_manifest_sha256)) return error.ManifestDigestMismatch;
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    if (!try ctx.db.nob().trust(project.id, actual, actor, now)) return error.ProjectNotTrustable;
    const detail = try std.fmt.allocPrint(ctx.gpa, "project={d} manifest_sha256={s} actor={s}", .{ project.id, actual, actor });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.trust", "ok", detail);
}

pub fn revoke(ctx: Context, reference: []const u8, actor: []const u8) !void {
    const project = (try resolve(ctx, reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    if (!try ctx.db.nob().revoke(project.id, actor, now)) return error.ProjectNotFound;
    const detail = try std.fmt.allocPrint(ctx.gpa, "project={d} actor={s}", .{ project.id, actor });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.revoke", "ok", detail);
}

pub fn forget(ctx: Context, io: std.Io, cache_root: []const u8, reference: []const u8, actor: []const u8) !void {
    const project = (try resolve(ctx, reference)) orelse return error.ProjectNotFound;
    defer project.deinit(ctx.gpa);
    const cache_path = try resolveRunnerCachePath(ctx.gpa, io, cache_root, project.id);
    defer if (cache_path) |path| ctx.gpa.free(path);
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    if (!try ctx.db.nob().forget(project.id, actor, now)) return error.ProjectNotFound;
    if (cache_path) |path| {
        const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (stat) |value| {
            if (value.kind != .directory) return error.RunnerCachePathUnsafe;
            try std.Io.Dir.cwd().deleteTree(io, path);
        }
    }
    const detail = try std.fmt.allocPrint(ctx.gpa, "project={d} actor={s}; history and host resources retained", .{ project.id, actor });
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit("nob.forget", "ok", detail);
}

fn resolveRunnerCachePath(allocator: Allocator, io: std.Io, cache_root: []const u8, project_id: i64) !?[:0]u8 {
    const root_stat = std.Io.Dir.cwd().statFile(io, cache_root, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (root_stat.kind != .directory) return error.RunnerCacheRootUnsafe;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, cache_root, allocator);
    defer allocator.free(root);
    if (std.mem.eql(u8, root, "/")) return error.RunnerCacheRootUnsafe;
    const project_key = try std.fmt.allocPrint(allocator, "{d}", .{project_id});
    defer allocator.free(project_key);
    const candidate = try std.fs.path.join(allocator, &.{ root, project_key });
    defer allocator.free(candidate);
    const candidate_stat = std.Io.Dir.cwd().statFile(io, candidate, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (candidate_stat.kind != .directory) return error.RunnerCachePathUnsafe;
    const canonical = try std.Io.Dir.cwd().realPathFileAlloc(io, candidate, allocator);
    errdefer allocator.free(canonical);
    if (!strictDescendant(root, canonical)) return error.RunnerCachePathUnsafe;
    return canonical;
}

fn strictDescendant(root: []const u8, path: []const u8) bool {
    return path.len > root.len and std.mem.startsWith(u8, path, root) and path[root.len] == std.fs.path.sep;
}

pub fn writeListText(ctx: Context, writer: anytype) !void {
    var projects = try list(ctx);
    defer projects.deinit(ctx.gpa);
    if (projects.items.len == 0) {
        try writer.writeAll("no nob projects discovered\n");
        return;
    }
    for (projects.items) |project| {
        try writer.print("{d}\t{s}", .{ project.id, project.display_name });
        if (project.declared_id) |declared_id| try app_render.writeTextField(writer, "project_id", declared_id);
        try app_render.writeTextField(writer, "kind", project.kind);
        try app_render.writeTextField(writer, "discovery", project.discovery_state.text());
        try app_render.writeTextField(writer, "trust", project.trust_state.text());
        try app_render.writeTextField(writer, "status", project.status.text());
        try app_render.writeTextField(writer, "root", project.root_path);
        try writer.writeByte('\n');
    }
}

pub fn writeListJson(ctx: Context, writer: anytype) !void {
    var projects = try list(ctx);
    defer projects.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_projects\",\"items\":[");
    for (projects.items, 0..) |project, index| {
        if (index != 0) try writer.writeByte(',');
        try writeProjectJson(project, writer);
    }
    try writer.writeAll("]}\n");
}

pub fn writeShowText(ctx: Context, reference: []const u8, writer: anytype) !void {
    var details = (try show(ctx, reference)) orelse {
        try writer.print("nob project not found: {s}\n", .{reference});
        return;
    };
    defer details.deinit(ctx.gpa);
    const project = details.project;
    try writer.print("id: {d}\n", .{project.id});
    if (project.declared_id) |value| try writer.print("project_id: {s}\n", .{value});
    try writer.print(
        "name: {s}\nkind: {s}\nroot: {s}\ndiscovery: {s}\ntrust: {s}\nstatus: {s}\nrunner: {s}\n",
        .{
            project.display_name,
            project.kind,
            project.root_path,
            project.discovery_state.text(),
            project.trust_state.text(),
            project.status.text(),
            project.runner_state.text(),
        },
    );
    if (project.manifest_sha256) |value| try writer.print("manifest_sha256: {s}\n", .{value});
    if (project.status_summary) |value| try writer.print("detail: {s}\n", .{value});
    try writer.print("resources ({d})\n", .{details.resources.items.len});
    for (details.resources.items) |resource| {
        try writer.print("  {s}\t{s}\t{s}\t{s}\n", .{ resource.resource_id, resource.kind, resource.ownership, resource.effective_status.text() });
    }
    try writer.print("actions ({d})\n", .{details.actions.items.len});
    for (details.actions.items) |action| {
        try writer.print("  {s}\t{s}\t{s}\tavailable={s}\n", .{
            action.action_id,
            action.effect,
            action.confirmation,
            if (action.available) "yes" else "no",
        });
    }
}

pub fn writeShowJson(ctx: Context, reference: []const u8, writer: anytype) !void {
    var details = (try show(ctx, reference)) orelse return error.ProjectNotFound;
    defer details.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_project\",\"project\":");
    try writeProjectJson(details.project, writer);
    try writer.writeAll(",\"resources\":[");
    for (details.resources.items, 0..) |resource, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "id", resource.resource_id, true);
        try app_render.writeJsonStringField(writer, "kind", resource.kind, true);
        try app_render.writeJsonStringField(writer, "label", resource.label, true);
        try app_render.writeJsonStringField(writer, "ownership", resource.ownership, true);
        try app_render.writeJsonStringField(writer, "status", resource.effective_status.text(), true);
        try app_render.writeJsonNullableStringField(writer, "summary", resource.status_summary, true);
        try writer.writeAll("\"controls\":");
        try writer.writeAll(resource.controls_json);
        try writer.writeAll(",\"declaration\":");
        try writer.writeAll(resource.declaration_json);
        try writer.writeByte(',');
        try writer.writeAll("\"runner_evidence\":");
        try writer.writeAll(resource.runner_observation_json orelse "null");
        try writer.writeAll(",\"cloudio_evidence\":");
        try writer.writeAll(resource.cloudio_observation_json orelse "null");
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"actions\":[");
    for (details.actions.items, 0..) |action, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "id", action.action_id, true);
        try app_render.writeJsonStringField(writer, "label", action.label, true);
        try app_render.writeJsonStringField(writer, "effect", action.effect, true);
        try app_render.writeJsonStringField(writer, "confirmation", action.confirmation, true);
        try app_render.writeJsonBoolField(writer, "available", action.available, true);
        try app_render.writeJsonNullableStringField(writer, "unavailable_reason", action.unavailable_reason, true);
        try writer.writeAll("\"declaration\":");
        try writer.writeAll(action.declaration_json);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn resolve(ctx: Context, reference: []const u8) !?db_store.NobProject {
    if (std.fmt.parseInt(i64, reference, 10)) |project_id| {
        return try ctx.db.nob().getProject(ctx.gpa, project_id);
    } else |_| {}
    return try ctx.db.nob().getProjectByDeclaredId(ctx.gpa, reference);
}

fn writeProjectJson(project: db_store.NobProject, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "id", project.id, true);
    try app_render.writeJsonNullableStringField(writer, "project_id", project.declared_id, true);
    try app_render.writeJsonStringField(writer, "display_name", project.display_name, true);
    try app_render.writeJsonStringField(writer, "kind", project.kind, true);
    try app_render.writeJsonStringField(writer, "root_path", project.root_path, true);
    try app_render.writeJsonNullableStringField(writer, "manifest_sha256", project.manifest_sha256, true);
    try app_render.writeJsonNullableStringField(writer, "trusted_manifest_sha256", project.trusted_manifest_sha256, true);
    try app_render.writeJsonStringField(writer, "discovery_state", project.discovery_state.text(), true);
    try app_render.writeJsonStringField(writer, "last_scan_state", project.last_scan_state.text(), true);
    try app_render.writeJsonStringField(writer, "trust_state", project.trust_state.text(), true);
    try app_render.writeJsonStringField(writer, "status", project.status.text(), true);
    try app_render.writeJsonNullableStringField(writer, "status_summary", project.status_summary, true);
    try app_render.writeJsonStringField(writer, "runner_state", project.runner_state.text(), true);
    try app_render.writeJsonNullableStringField(writer, "runner_sha256", project.runner_sha256, true);
    try app_render.writeJsonNullableStringField(writer, "repository_kind", project.repository_kind, true);
    try app_render.writeJsonNullableStringField(writer, "repository_identity", project.repository_identity, true);
    try app_render.writeJsonNullableStringField(writer, "head_revision", project.head_revision, true);
    try app_render.writeJsonNullableStringField(writer, "source_fingerprint", project.source_fingerprint, true);
    if (project.source_dirty) |dirty| {
        try app_render.writeJsonBoolField(writer, "source_dirty", dirty, false);
    } else {
        try writer.writeAll("\"source_dirty\":null");
    }
    try writer.writeByte('}');
}

test "nob project reads and trust mutations require the current digest" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/nob-projects.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try db_store.Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    _ = try db.nob().recordDiscovery(.{
        .declared_id = "dev.example.app",
        .display_name = "Example app",
        .kind = "service",
        .root_path = "/srv/example-app",
        .manifest_path = "/srv/example-app/nob.json",
        .manifest_sha256 = digest,
        .manifest_json = "{}",
        .discovery_state = .valid,
        .protocol_major = 1,
        .protocol_minor = 0,
        .scan_id = "scan-1",
        .seen_at = 10,
        .replace_declarations = true,
    });

    const ctx = Context{ .gpa = allocator, .db = &db };
    try std.testing.expectError(error.ManifestDigestMismatch, trust(ctx, "dev.example.app", "stale", "test"));
    try trust(ctx, "dev.example.app", digest, "test");

    var project = (try db.nob().getProjectByDeclaredId(allocator, "dev.example.app")).?;
    defer project.deinit(allocator);
    try std.testing.expectEqual(db_store.NobTrustState.trusted, project.trust_state);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeListText(ctx, &out.writer);
    try writeListJson(ctx, &out.writer);
    try writeShowText(ctx, "dev.example.app", &out.writer);
    try writeShowJson(ctx, "dev.example.app", &out.writer);
    const rendered = try out.toOwnedSlice();
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Example app") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"trust_state\":\"trusted\"") != null);

    try revoke(ctx, "dev.example.app", "test");
    project.deinit(allocator);
    project = (try db.nob().getProjectByDeclaredId(allocator, "dev.example.app")).?;
    try std.testing.expectEqual(db_store.NobTrustState.revoked, project.trust_state);
}

test "forget tombstones rescans and retains history and host resources" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/forget", .{tmp.sub_path});
    defer allocator.free(base_path);
    const db_path = try std.fs.path.join(allocator, &.{ base_path, "cloudio.db" });
    defer allocator.free(db_path);
    const cache_root = try std.fs.path.join(allocator, &.{ base_path, "runners" });
    defer allocator.free(cache_root);
    const cache_project = try std.fs.path.join(allocator, &.{ cache_root, "1" });
    defer allocator.free(cache_project);
    try std.Io.Dir.cwd().createDirPath(io, cache_project);
    const cached_runner = try std.fs.path.join(allocator, &.{ cache_project, "cached-runner" });
    defer allocator.free(cached_runner);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = cached_runner, .data = "runner" });

    var db = try db_store.Db.open(io, db_path);
    defer db.close();
    try db.initSchema();
    const digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const project_id = try db.nob().recordDiscovery(.{
        .declared_id = "dev.example.forgotten",
        .display_name = "Forgotten service",
        .kind = "service",
        .root_path = "/srv/forgotten-service",
        .manifest_path = "/srv/forgotten-service/nob.json",
        .manifest_sha256 = digest,
        .manifest_json = "{}",
        .discovery_state = .valid,
        .protocol_major = 1,
        .protocol_minor = 0,
        .scan_id = "scan-before-forget",
        .seen_at = 10,
        .replace_declarations = true,
        .actions = &.{.{
            .action_id = "deploy",
            .label = "Deploy",
            .effect = "runtime-change",
            .confirmation = "review-plan",
            .declaration_json = "{}",
        }},
    });
    try std.testing.expectEqual(@as(i64, 1), project_id);
    try db.nob().insertPlan(.{
        .id = "01ARZ3NDEKTSV4RRFFQ69G5FAX",
        .project_id = project_id,
        .action_id = "deploy",
        .resource_id = null,
        .input_json = "{}",
        .plan_json = "{}",
        .plan_sha256 = digest,
        .manifest_sha256 = digest,
        .source_fingerprint = "source",
        .effect = "runtime-change",
        .confirmation = "review-plan",
        .requested_by = "test",
        .runner_sha256 = digest,
        .source_revision = null,
        .source_dirty = false,
        .created_at = 11,
        .expires_at = 100,
    });
    try db.nob().upsertSecretBinding(.{
        .project_id = project_id,
        .secret_id = "token",
        .source_kind = "process-environment",
        .source_ref = "FORGET_TEST_TOKEN",
        .present = true,
        .bound_by = "test",
        .now = 11,
    });
    try db.exec(
        \\INSERT INTO project_operations(
        \\  id, project_id, action_id, state, outcome, effect, requested_by, queued_at, finished_at
        \\) VALUES('01ARZ3NDEKTSV4RRFFQ69G5FAY', 1, 'deploy', 'succeeded', 'succeeded',
        \\  'runtime-change', 'test', 11, 12);
    );
    try db.nob().upsertManagedUnit(.{
        .operation_id = "01ARZ3NDEKTSV4RRFFQ69G5FAY",
        .resource_id = "service",
        .scope = "user",
        .unit = "forgotten.service",
        .fragment_path = "/home/test/.config/systemd/user/forgotten.service",
        .sha256 = digest,
        .updated_at = 12,
    });

    const ctx = Context{ .gpa = allocator, .db = &db };
    try forget(ctx, io, cache_root, "1", "test");
    var project = (try db.nob().getProject(allocator, project_id)).?;
    defer project.deinit(allocator);
    try std.testing.expectEqual(db_store.NobDiscoveryState.ignored, project.discovery_state);
    try std.testing.expectEqual(db_store.NobDiscoveryState.valid, project.last_scan_state);
    try std.testing.expectEqual(db_store.NobTrustState.revoked, project.trust_state);
    try std.testing.expectEqual(db_store.NobRunnerState.@"not-built", project.runner_state);
    var plan = (try db.nob().getPlan(allocator, "01ARZ3NDEKTSV4RRFFQ69G5FAX")).?;
    defer plan.deinit(allocator);
    try std.testing.expectEqualStrings("invalidated", plan.state);
    var secrets = try db.nob().listSecretBindings(allocator, project_id);
    defer secrets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), secrets.items.len);
    var runs = try db.nob().listRuns(allocator, project_id, 10);
    defer runs.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), runs.items.len);
    var unit = (try db.nob().getManagedUnitForOperation(allocator, runs.items[0].id, "service")).?;
    defer unit.deinit(allocator);
    try std.testing.expectEqualStrings("forgotten.service", unit.unit);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, cache_project, .{ .follow_symlinks = false }));

    _ = try db.nob().recordDiscovery(.{
        .declared_id = "dev.example.forgotten",
        .display_name = "Forgotten service",
        .kind = "service",
        .root_path = "/srv/forgotten-service",
        .manifest_path = "/srv/forgotten-service/nob.json",
        .manifest_sha256 = digest,
        .manifest_json = "{}",
        .discovery_state = .valid,
        .protocol_major = 1,
        .protocol_minor = 0,
        .scan_id = "scan-after-forget",
        .seen_at = 20,
    });
    project.deinit(allocator);
    project = (try db.nob().getProject(allocator, project_id)).?;
    try std.testing.expectEqual(db_store.NobDiscoveryState.ignored, project.discovery_state);
    try std.testing.expect((try db.nob().getProjectByDeclaredId(allocator, "dev.example.forgotten")) == null);
    try trust(ctx, "1", digest, "test");
    project.deinit(allocator);
    project = (try db.nob().getProject(allocator, project_id)).?;
    try std.testing.expectEqual(db_store.NobDiscoveryState.valid, project.discovery_state);
    try std.testing.expectEqual(db_store.NobTrustState.trusted, project.trust_state);
}
