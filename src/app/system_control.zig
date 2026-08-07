//! Explicit Docker controls for exact observed local containers.
//!
//! Commands are executed directly as argv. Availability comes from the
//! process identity and runtime socket permissions; there is no sudo fallback.
const std = @import("std");
const app_writes = @import("app_writes");
const collector_system = @import("collector_system");
const core_json = @import("core_json");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;

const max_command_bytes = 1024 * 1024;

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    write_meta: app_writes.Metadata = .{},
};

pub const ContainerAction = collector_system.ContainerAction;
pub const ContainerState = collector_system.ContainerState;

pub fn containerState(status: []const u8) ContainerState {
    return collector_system.classifyContainerStatus(status);
}

pub fn containerActionAllowed(state: ContainerState, action: ContainerAction) bool {
    return collector_system.containerActionAllowed(state, action);
}

pub fn isSafeContainerName(name: []const u8) bool {
    return collector_system.isSafeContainerName(name);
}

pub fn containerAction(ctx: Context, name: []const u8, action: ContainerAction, writer: anytype) !void {
    if (!collector_system.isSafeContainerName(name)) return error.InvalidContainerName;
    var before = try ctx.db.containerRow(ctx.gpa, name) orelse return error.ContainerNotObserved;
    defer before.deinit(ctx.gpa);
    const before_state = collector_system.classifyContainerStatus(before.status);
    if (!collector_system.containerActionAllowed(before_state, action)) {
        try auditContainerFailure(ctx, name, action, "action is not valid for the observed container state");
        return error.ContainerActionUnavailable;
    }
    const action_text = @tagName(action);

    const result = core_process.run(ctx.gpa, ctx.io, &.{ "docker", action_text, name }, max_command_bytes) catch |err| {
        const detail = try std.fmt.allocPrint(ctx.gpa, "container runtime unavailable: {s}", .{@errorName(err)});
        defer ctx.gpa.free(detail);
        try auditContainerFailure(ctx, name, action, detail);
        return error.ContainerRuntimeUnavailable;
    };
    defer result.deinit(ctx.gpa);

    if (!result.ok()) {
        const detail = try combineOutput(ctx.gpa, result);
        defer ctx.gpa.free(detail);
        try auditContainerFailure(ctx, name, action, if (detail.len == 0) "container command failed" else detail);
        return error.ContainerCommandFailed;
    }

    collector_system.collectContainers(ctx.io, ctx.gpa, ctx.db) catch |err| {
        const detail = try std.fmt.allocPrint(ctx.gpa, "command accepted but reconciliation failed: {s}", .{@errorName(err)});
        defer ctx.gpa.free(detail);
        try auditContainerFailure(ctx, name, action, detail);
        return error.ContainerStateUnconfirmed;
    };

    var after = try ctx.db.containerRow(ctx.gpa, name) orelse {
        try auditContainerFailure(ctx, name, action, "container disappeared during reconciliation");
        return error.ContainerStateUnconfirmed;
    };
    defer after.deinit(ctx.gpa);
    const after_state = collector_system.classifyContainerStatus(after.status);
    if (!actionReachedState(action, after_state)) {
        const detail = try std.fmt.allocPrint(ctx.gpa, "state not confirmed after command: {s}", .{after_state.label()});
        defer ctx.gpa.free(detail);
        try auditContainerFailure(ctx, name, action, detail);
        return error.ContainerStateUnconfirmed;
    }

    const kind = try std.fmt.allocPrint(ctx.gpa, "docker.{s}", .{action_text});
    defer ctx.gpa.free(kind);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, kind, name, null, .ok, after.status);

    try writer.writeByte('{');
    try core_json.writeStringField(writer, "container", name, true);
    try core_json.writeStringField(writer, "action", action_text, true);
    try core_json.writeStringField(writer, "state", after_state.label(), true);
    try core_json.writeStringField(writer, "status", after.status, true);
    try core_json.writeStringField(writer, "observed_at", after.updated_at, false);
    try writer.writeAll("}\n");
}

pub fn refreshContainers(ctx: Context) !void {
    return collector_system.collectContainers(ctx.io, ctx.gpa, ctx.db);
}

/// Reads bounded logs for an exact observed container; no audit row because
/// this is a read.
pub fn containerLogs(ctx: Context, name: []const u8, tail: i64, writer: anytype) !void {
    if (!collector_system.isSafeContainerName(name)) return error.InvalidContainerName;
    var observed = try ctx.db.containerRow(ctx.gpa, name) orelse return error.ContainerNotObserved;
    defer observed.deinit(ctx.gpa);
    const effective_tail = try validateTail(tail);
    var tail_buf: [20]u8 = undefined;
    const tail_text = std.fmt.bufPrint(&tail_buf, "{d}", .{effective_tail}) catch unreachable;

    const result = core_process.run(ctx.gpa, ctx.io, &.{ "docker", "logs", "--tail", tail_text, name }, max_command_bytes) catch
        return error.ContainerRuntimeUnavailable;
    defer result.deinit(ctx.gpa);

    const combined = try combineOutput(ctx.gpa, result);
    defer ctx.gpa.free(combined);
    if (!result.ok()) return error.ContainerLogsFailed;

    try writer.writeByte('{');
    try core_json.writeStringField(writer, "container", name, true);
    try core_json.writeIntField(writer, "tail", effective_tail, true);
    try core_json.writeStringField(writer, "logs", combined, false);
    try writer.writeAll("}\n");
}

pub fn validateTail(tail: i64) !i64 {
    if (tail < 1 or tail > 500) return error.InvalidContainerLogTail;
    return tail;
}

fn actionReachedState(action: ContainerAction, state: ContainerState) bool {
    return switch (action) {
        .start, .restart => state == .running or state == .unhealthy,
        .stop => state == .stopped or state == .exited,
    };
}

fn auditContainerFailure(ctx: Context, name: []const u8, action: ContainerAction, detail: []const u8) !void {
    const kind = try std.fmt.allocPrint(ctx.gpa, "docker.{s}", .{@tagName(action)});
    defer ctx.gpa.free(kind);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, kind, name, null, .err, detail);
}

fn combineOutput(gpa: Allocator, result: core_process.CommandResult) ![]u8 {
    const joined = try std.fmt.allocPrint(gpa, "{s}{s}", .{ result.stdout, result.stderr });
    defer gpa.free(joined);
    return gpa.dupe(u8, trimmed(joined));
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

test "container log tail is bounded and invalid values are rejected" {
    try std.testing.expectError(error.InvalidContainerLogTail, validateTail(0));
    try std.testing.expectError(error.InvalidContainerLogTail, validateTail(-5));
    try std.testing.expectEqual(@as(i64, 42), try validateTail(42));
    try std.testing.expectEqual(@as(i64, 500), try validateTail(500));
    try std.testing.expectError(error.InvalidContainerLogTail, validateTail(501));
}
