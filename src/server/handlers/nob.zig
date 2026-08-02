const std = @import("std");
const app_nob_actions = @import("app_nob_actions");
const app_nob_projects = @import("app_nob_projects");
const app_nob_runtime = @import("app_nob_runtime");
const app_nob_secrets = @import("app_nob_secrets");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn list(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_nob_projects.writeListJson(context.nob(ctx), writer);
    return 200;
}

pub fn details(ctx: context.Context, _: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    try app_nob_projects.writeShowJson(context.nob(ctx), reference, writer);
    return 200;
}

pub fn secrets(ctx: context.Context, _: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    try app_nob_secrets.writeJson(context.nobSecrets(ctx), reference, writer);
    return 200;
}

pub fn bindSecret(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    const secret_id = params.get("secret") orelse return common.badRequest(writer);
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    if (!objectHasOnly(parsed.value.object, &.{ "source_kind", "source_ref" }) or parsed.value.object.count() != 2) {
        return common.badRequest(writer);
    }
    const source_kind = common.strField(parsed.value, "source_kind") orelse return common.badRequest(writer);
    const source_ref = common.strField(parsed.value, "source_ref") orelse return common.badRequest(writer);
    try app_nob_secrets.bind(
        context.nobSecrets(ctx),
        reference,
        secret_id,
        source_kind,
        source_ref,
        ctx.auth_user_id orelse "authenticated-web",
    );
    try app_nob_secrets.writeJson(context.nobSecrets(ctx), reference, writer);
    return 200;
}

pub fn unbindSecret(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    const secret_id = params.get("secret") orelse return common.badRequest(writer);
    if (!emptyObject(ctx.gpa, request.body)) return common.badRequest(writer);
    try app_nob_secrets.unbind(
        context.nobSecrets(ctx),
        reference,
        secret_id,
        ctx.auth_user_id orelse "authenticated-web",
    );
    try app_nob_secrets.writeJson(context.nobSecrets(ctx), reference, writer);
    return 200;
}

pub fn scan(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) {
        try writer.writeAll("{\"error\":\"nob_disabled\"}\n");
        return 409;
    }
    const result = try app_nob_projects.scan(context.nob(ctx), ctx.io, ctx.config.projects_root, ctx.config.nob_scan_depth);
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "kind", "nob_scan", true);
    try core_json.writeCountField(writer, "projects_seen", result.projects_seen, true);
    try core_json.writeCountField(writer, "valid", result.valid, true);
    try core_json.writeCountField(writer, "invalid", result.invalid, true);
    try core_json.writeCountField(writer, "candidates", result.candidates, true);
    try core_json.writeCountField(writer, "conflicts", result.conflicts, true);
    try core_json.writeCountField(writer, "missing", result.missing, false);
    try writer.writeAll("}\n");
    return 200;
}

pub fn trustProject(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    return projectAction(ctx, request, params, writer, "trust");
}

pub fn revokeProject(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    return projectAction(ctx, request, params, writer, "revoke");
}

pub fn prepareProject(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    return projectAction(ctx, request, params, writer, "prepare");
}

pub fn observeProject(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    return projectAction(ctx, request, params, writer, "observe");
}

fn projectAction(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, operation: []const u8) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    const actor = ctx.auth_user_id orelse "authenticated-web";
    if (std.mem.eql(u8, operation, "trust")) {
        var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
        defer parsed.deinit();
        if (!objectHasOnly(parsed.value.object, &.{ "manifest_sha256", "confirm_declared_id" })) return common.badRequest(writer);
        const digest = common.strField(parsed.value, "manifest_sha256") orelse return common.badRequest(writer);
        const confirmed_id = common.strField(parsed.value, "confirm_declared_id") orelse return common.badRequest(writer);
        const project = (try app_nob_projects.find(context.nob(ctx), reference)) orelse return error.ProjectNotFound;
        defer project.deinit(ctx.gpa);
        if (project.declared_id == null or !std.mem.eql(u8, project.declared_id.?, confirmed_id)) return error.ProjectConfirmationMismatch;
        try app_nob_projects.trust(context.nob(ctx), reference, digest, actor);
    } else if (std.mem.eql(u8, operation, "revoke")) {
        if (!emptyObject(ctx.gpa, request.body)) return common.badRequest(writer);
        try app_nob_projects.revoke(context.nob(ctx), reference, actor);
    } else if (std.mem.eql(u8, operation, "prepare")) {
        if (!emptyObject(ctx.gpa, request.body)) return common.badRequest(writer);
        if (!ctx.config.nob_enabled) return writeDisabled(writer);
        const outcome = try app_nob_runtime.prepareAndObserve(context.nobRuntime(ctx), reference);
        try writeRuntimeOutcome(writer, "prepare", outcome);
        return 200;
    } else if (std.mem.eql(u8, operation, "observe")) {
        if (!emptyObject(ctx.gpa, request.body)) return common.badRequest(writer);
        if (!ctx.config.nob_enabled) return writeDisabled(writer);
        const outcome = try app_nob_runtime.observe(context.nobRuntime(ctx), reference);
        try writeRuntimeOutcome(writer, "observe", outcome);
        return 200;
    } else {
        return error.UnknownRoute;
    }
    try app_nob_projects.writeShowJson(context.nob(ctx), reference, writer);
    return 200;
}

fn emptyObject(allocator: std.mem.Allocator, body: []const u8) bool {
    var parsed = common.jsonBody(allocator, body) orelse return false;
    defer parsed.deinit();
    return parsed.value.object.count() == 0;
}

pub fn planAction(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) return writeDisabled(writer);
    const reference = params.get("id") orelse return common.badRequest(writer);
    const action_id = params.get("action") orelse return common.badRequest(writer);
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    if (!objectHasOnly(parsed.value.object, &.{"parameters"})) return common.badRequest(writer);
    const parameters = parsed.value.object.get("parameters") orelse return common.badRequest(writer);
    if (parameters != .object) return common.badRequest(writer);
    var planned = try app_nob_actions.plan(
        context.nobActions(ctx),
        reference,
        action_id,
        parameters,
        ctx.auth_user_id orelse "authenticated-web",
    );
    defer planned.deinit(ctx.gpa);
    try writePlan(writer, ctx.gpa, planned);
    return 200;
}

pub fn runAction(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, headers: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) return writeDisabled(writer);
    const reference = params.get("id") orelse return common.badRequest(writer);
    const action_id = params.get("action") orelse return common.badRequest(writer);
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    if (!objectHasOnly(parsed.value.object, &.{ "plan_id", "confirm_project_id" })) return common.badRequest(writer);
    const plan_id = common.strField(parsed.value, "plan_id") orelse return common.badRequest(writer);
    var queued = try app_nob_actions.queueAction(
        context.nobActions(ctx),
        reference,
        action_id,
        plan_id,
        .{
            .confirmed = true,
            .typed_project_id = common.strField(parsed.value, "confirm_project_id"),
        },
        ctx.auth_user_id orelse "authenticated-web",
        ctx.write_meta.idempotency_key,
    );
    defer queued.deinit(ctx.gpa);
    try headers.print("Location: /api/nob/operations/{s}\r\n", .{queued.id});
    try writer.writeAll("{\"kind\":\"nob_run\",\"operation\":");
    try std.json.Stringify.value(queued, .{}, writer);
    try writer.writeAll(",\"status_url\":");
    const status_url = try std.fmt.allocPrint(ctx.gpa, "/api/nob/operations/{s}", .{queued.id});
    defer ctx.gpa.free(status_url);
    try std.json.Stringify.value(status_url, .{}, writer);
    try writer.writeAll("}\n");
    return 202;
}

pub fn planResourceControl(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) return writeDisabled(writer);
    const reference = params.get("id") orelse return common.badRequest(writer);
    const resource_id = params.get("resource") orelse return common.badRequest(writer);
    const control_name = params.get("control") orelse return common.badRequest(writer);
    if (!emptyObject(ctx.gpa, request.body)) return common.badRequest(writer);
    var planned = try app_nob_actions.planResourceControl(
        context.nobActions(ctx),
        reference,
        resource_id,
        control_name,
        ctx.auth_user_id orelse "authenticated-web",
    );
    defer planned.deinit(ctx.gpa);
    try writePlan(writer, ctx.gpa, planned);
    return 200;
}

pub fn runResourceControl(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, headers: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) return writeDisabled(writer);
    const reference = params.get("id") orelse return common.badRequest(writer);
    const resource_id = params.get("resource") orelse return common.badRequest(writer);
    const control_name = params.get("control") orelse return common.badRequest(writer);
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    if (!objectHasOnly(parsed.value.object, &.{"plan_id"})) return common.badRequest(writer);
    const plan_id = common.strField(parsed.value, "plan_id") orelse return common.badRequest(writer);
    var queued = try app_nob_actions.queueResourceControl(
        context.nobActions(ctx),
        reference,
        resource_id,
        control_name,
        plan_id,
        .{ .confirmed = true },
        ctx.auth_user_id orelse "authenticated-web",
        ctx.write_meta.idempotency_key,
    );
    defer queued.deinit(ctx.gpa);
    try headers.print("Location: /api/nob/operations/{s}\r\n", .{queued.id});
    try writer.writeAll("{\"kind\":\"nob_run\",\"operation\":");
    try std.json.Stringify.value(queued, .{}, writer);
    try writer.writeAll("}\n");
    return 202;
}

pub fn resourceLogs(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    const resource_id = params.get("resource") orelse return common.badRequest(writer);
    const lines: u16 = @intCast(@min(@max(common.intQuery(request, "tail", 200), 1), 2000));
    const bytes = try app_nob_actions.resourceLogs(context.nobActions(ctx), reference, resource_id, lines);
    defer ctx.gpa.free(bytes);
    try writer.writeAll("{\"kind\":\"nob_resource_logs\",\"text\":");
    try std.json.Stringify.value(bytes, .{}, writer);
    try writer.writeAll("}\n");
    return 200;
}

pub fn operations(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const limit = @min(@max(common.intQuery(request, "limit", 50), 1), 200);
    var runs = try app_nob_actions.listRuns(context.nobActions(ctx), null, limit);
    defer runs.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_runs\",\"items\":");
    try std.json.Stringify.value(runs.items, .{}, writer);
    try writer.writeAll("}\n");
    return 200;
}

pub fn operationDetails(ctx: context.Context, _: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const operation_id = params.get("id") orelse return common.badRequest(writer);
    const run_value = (try app_nob_actions.getRun(context.nobActions(ctx), operation_id)) orelse return error.RunNotFound;
    defer run_value.deinit(ctx.gpa);
    var events = try app_nob_actions.listRecentEvents(context.nobActions(ctx), operation_id, 200);
    defer events.deinit(ctx.gpa);
    var artifacts = try app_nob_actions.listArtifacts(context.nobActions(ctx), operation_id);
    defer artifacts.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_run\",\"operation\":");
    try std.json.Stringify.value(run_value, .{}, writer);
    try writer.writeAll(",\"events\":");
    try std.json.Stringify.value(events.items, .{}, writer);
    try writer.writeAll(",\"artifacts\":");
    try std.json.Stringify.value(artifacts.items, .{}, writer);
    try writer.writeAll("}\n");
    return 200;
}

pub fn operationEvents(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const operation_id = params.get("id") orelse return common.badRequest(writer);
    const after_seq = @max(common.intQuery(request, "after_seq", 0), 0);
    const limit: usize = @intCast(@min(@max(common.intQuery(request, "limit", 200), 1), 500));
    const run_value = (try app_nob_actions.getRun(context.nobActions(ctx), operation_id)) orelse return error.RunNotFound;
    defer run_value.deinit(ctx.gpa);
    var events = try app_nob_actions.listEventsAfter(context.nobActions(ctx), operation_id, after_seq, @intCast(limit + 1));
    defer events.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"nob_run_events\",\"items\":[");
    const written = @min(events.items.len, limit);
    var index: usize = 0;
    while (index < written) : (index += 1) {
        const event = events.items[index];
        if (index != 0) try writer.writeByte(',');
        try std.json.Stringify.value(event, .{}, writer);
    }
    const next_seq = if (written == 0) after_seq else events.items[written - 1].seq;
    try writer.print("],\"next_seq\":{d},\"terminal\":{s},\"truncated\":{s}}}\n", .{
        next_seq,
        if (terminalState(run_value.state)) "true" else "false",
        if (events.items.len > limit) "true" else "false",
    });
    return 200;
}

pub fn operationLog(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const operation_id = params.get("id") orelse return common.badRequest(writer);
    const tail_bytes: usize = @intCast(@min(@max(common.intQuery(request, "tail_bytes", 64 * 1024), 1), 1024 * 1024));
    const run_value = (try app_nob_actions.getRun(context.nobActions(ctx), operation_id)) orelse return error.RunNotFound;
    defer run_value.deinit(ctx.gpa);
    const path = run_value.log_path orelse {
        try writer.writeAll("{\"kind\":\"nob_run_log\",\"text\":\"\"}\n");
        return 200;
    };
    const state_root = try std.Io.Dir.cwd().realPathFileAlloc(ctx.io, ctx.config.nob_state_root, ctx.gpa);
    defer ctx.gpa.free(state_root);
    const expected_dir = try std.fs.path.join(ctx.gpa, &.{ state_root, operation_id });
    defer ctx.gpa.free(expected_dir);
    const expected_path = try std.fs.path.join(ctx.gpa, &.{ expected_dir, "events.ndjson" });
    defer ctx.gpa.free(expected_path);
    if (!std.mem.eql(u8, path, expected_path)) return error.InvalidOperationLogPath;
    const file = try std.Io.Dir.cwd().openFile(ctx.io, path, .{ .follow_symlinks = false });
    defer file.close(ctx.io);
    const length = try file.length(ctx.io);
    const amount: usize = @intCast(@min(length, tail_bytes));
    const bytes = try ctx.gpa.alloc(u8, amount);
    defer ctx.gpa.free(bytes);
    const read = try file.readPositionalAll(ctx.io, bytes, length - amount);
    try writer.writeAll("{\"kind\":\"nob_run_log\",\"text\":");
    try std.json.Stringify.value(bytes[0..read], .{}, writer);
    try writer.writeAll("}\n");
    return 200;
}

pub fn cancelOperation(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const operation_id = params.get("id") orelse return common.badRequest(writer);
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    if (parsed.value.object.count() != 0) return common.badRequest(writer);
    try app_nob_actions.cancel(context.nobActions(ctx), operation_id, ctx.auth_user_id orelse "authenticated-web");
    try writer.writeAll("{\"kind\":\"nob_run_cancel\",\"status\":\"requested\"}\n");
    return 202;
}

fn writePlan(writer: *std.Io.Writer, allocator: std.mem.Allocator, planned: app_nob_actions.Plan) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, planned.plan_json, .{});
    defer parsed.deinit();
    try writer.writeAll("{\"kind\":\"nob_plan\",\"id\":");
    try std.json.Stringify.value(planned.id, .{}, writer);
    try writer.print(",\"project_id\":{d},\"action_id\":", .{planned.project_id});
    try std.json.Stringify.value(planned.action_id, .{}, writer);
    try writer.writeAll(",\"effect\":");
    try std.json.Stringify.value(planned.effect, .{}, writer);
    try writer.writeAll(",\"confirmation\":");
    try std.json.Stringify.value(planned.confirmation, .{}, writer);
    try writer.print(",\"expires_at\":{d},\"plan\":", .{planned.expires_at});
    try std.json.Stringify.value(parsed.value, .{}, writer);
    try writer.writeAll("}\n");
}

fn objectHasOnly(object: std.json.ObjectMap, allowed: []const []const u8) bool {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var found = false;
        for (allowed) |name| if (std.mem.eql(u8, entry.key_ptr.*, name)) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn terminalState(state: []const u8) bool {
    return !std.mem.eql(u8, state, "queued") and !std.mem.eql(u8, state, "running");
}

fn writeDisabled(writer: *std.Io.Writer) !u16 {
    try writer.writeAll("{\"error\":\"nob_disabled\"}\n");
    return 409;
}

fn writeRuntimeOutcome(writer: *std.Io.Writer, operation: []const u8, outcome: app_nob_runtime.Outcome) !void {
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "kind", "nob_runtime", true);
    try core_json.writeStringField(writer, "operation", operation, true);
    try core_json.writeIntField(writer, "project_id", outcome.project_id, true);
    try core_json.writeBoolField(writer, "runner_reused", outcome.runner_reused, true);
    try core_json.writeStringField(writer, "status", @tagName(outcome.status), false);
    try writer.writeAll("}\n");
}
