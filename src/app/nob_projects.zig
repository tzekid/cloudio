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
        try app_render.writeJsonNullableStringField(writer, "summary", resource.status_summary, false);
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
        try app_render.writeJsonNullableStringField(writer, "unavailable_reason", action.unavailable_reason, false);
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
    try app_render.writeJsonStringField(writer, "trust_state", project.trust_state.text(), true);
    try app_render.writeJsonStringField(writer, "status", project.status.text(), true);
    try app_render.writeJsonNullableStringField(writer, "status_summary", project.status_summary, true);
    try app_render.writeJsonStringField(writer, "runner_state", project.runner_state.text(), false);
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
