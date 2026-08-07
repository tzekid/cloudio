//! Observation-backed Hostinger virtual-machine lifecycle workflow.
const std = @import("std");
const app_provider_writes = @import("app_provider_writes");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_json = @import("core_json");
const core_redact = @import("core_redact");
const db_store = @import("db_store");
const net_http = @import("net_http");
const provider_hostinger = @import("provider_hostinger");
const provider_hostinger_models = @import("provider_hostinger_models");

const Allocator = std.mem.Allocator;
const reconcile_polls = 5;
var vps_mutex: std.atomic.Mutex = .unlocked;

pub const Action = app_provider_writes.VpsAction;

pub const Error = error{
    InvalidVpsRequest,
    VpsNotObserved,
    VpsActionUnavailable,
    VpsWriteUnavailable,
    VpsBusy,
    VpsProviderRejected,
    VpsProviderUnavailable,
    VpsActionFailed,
};

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: app_writes.Metadata = .{},
};

pub const MutationOutcome = enum {
    confirmed,
    accepted_pending,

    pub fn status(self: MutationOutcome) u16 {
        return if (self == .confirmed) 200 else 202;
    }
};

pub const MutationResult = struct {
    outcome: MutationOutcome,
    provider_job_id: ?[]u8 = null,
    observed_state: ?[]u8 = null,

    pub fn deinit(self: MutationResult, gpa: Allocator) void {
        if (self.provider_job_id) |value| gpa.free(value);
        if (self.observed_state) |value| gpa.free(value);
    }
};

const JobState = enum { pending, succeeded, failed };

pub fn writeJson(ctx: Context, writer: anytype) !void {
    var machines = try ctx.db.hostinger().hostingerVpsRows(ctx.gpa, 200);
    defer machines.deinit(ctx.gpa);
    var metrics = try ctx.db.hostinger().hostingerMetricSummaries(ctx.gpa, 200);
    defer metrics.deinit(ctx.gpa);
    const observation_optional = try ctx.db.latestObservation(ctx.gpa, "hostinger", "vps");
    defer if (observation_optional) |observation| observation.deinit(ctx.gpa);
    const freshness = observationFreshness(observation_optional, freshAfterSeconds(ctx.config));
    const refresh_available = ctx.config.hasHostingerAuth();
    const write_available = refresh_available and observation_optional != null and
        observation_optional.?.hasSuccessfulObservation() and
        std.mem.eql(u8, observation_optional.?.attempt_status, "ok") and
        std.mem.eql(u8, freshness, "current");

    try writer.writeAll("{\"kind\":\"vps_observation\",\"source\":\"hostinger\",");
    try core_json.writeStringField(writer, "freshness", freshness, true);
    try writer.writeAll("\"observed_at\":");
    if (observation_optional) |observation| {
        if (observation.hasSuccessfulObservation()) try core_json.writeString(writer, observation.observed_at) else try writer.writeAll("null");
    } else try writer.writeAll("null");
    try writer.writeAll(",\"age_seconds\":");
    if (observation_optional) |observation| {
        if (observation.age_seconds >= 0) try writer.print("{d}", .{observation.age_seconds}) else try writer.writeAll("null");
    } else try writer.writeAll("null");
    try writer.writeAll(",\"collection\":{");
    if (observation_optional) |observation| {
        try core_json.writeStringField(writer, "status", observation.attempt_status, true);
        try core_json.writeStringField(writer, "attempted_at", observation.attempted_at, true);
        try core_json.writeStringField(writer, "summary", observation.attempt_summary, false);
    } else {
        try core_json.writeStringField(writer, "status", "unavailable", true);
        try core_json.writeNullableStringField(writer, "attempted_at", null, true);
        try core_json.writeStringField(writer, "summary", "Hostinger machines have not been refreshed.", false);
    }
    try writer.writeAll("},\"capability\":{");
    try core_json.writeBoolField(writer, "refresh", refresh_available, true);
    try core_json.writeBoolField(writer, "write", write_available, true);
    try core_json.writeStringField(writer, "reason", capabilityReason(ctx.config.hasHostingerAuth(), freshness, observation_optional), false);
    try writer.writeAll("},\"machines\":[");
    for (machines.items, 0..) |machine, index| {
        if (index != 0) try writer.writeByte(',');
        const target_observation = try ctx.db.latestObservationForTarget(ctx.gpa, "hostinger", "vps-detail", machine.id);
        defer if (target_observation) |observation| observation.deinit(ctx.gpa);
        const target_ready = target_observation == null or std.mem.eql(u8, target_observation.?.attempt_status, "ok");
        const actionable = write_available and target_ready;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", machine.id, true);
        try core_json.writeStringField(writer, "name", machine.name, true);
        try core_json.writeStringField(writer, "status", machine.status, true);
        try core_json.writeStringField(writer, "ipv4", machine.ipv4, true);
        try core_json.writeStringField(writer, "plan", machine.plan, true);
        try core_json.writeStringField(writer, "observed_at", machineObservedAt(machine, target_observation, observation_optional), true);
        try core_json.writeStringField(writer, "capability_reason", machineCapabilityReason(actionable, target_observation), true);
        try writer.writeAll("\"actions\":{");
        try core_json.writeBoolField(writer, "start", actionable and actionAllowed(machine.status, .start), true);
        try core_json.writeBoolField(writer, "stop", actionable and actionAllowed(machine.status, .stop), true);
        try core_json.writeBoolField(writer, "restart", actionable and actionAllowed(machine.status, .restart), false);
        try writer.writeAll("}}");
    }
    try writer.writeAll("],\"metrics\":[");
    for (metrics.items, 0..) |metric, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "vm_id", metric.vm_id, true);
        try core_json.writeStringField(writer, "metric", metric.metric, true);
        try core_json.writeIntField(writer, "count", metric.count, true);
        try core_json.writeStringField(writer, "latest_captured", metric.latest_captured, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn refresh(ctx: Context) !void {
    if (!vps_mutex.tryLock()) return error.VpsBusy;
    defer vps_mutex.unlock();
    try refreshLocked(ctx);
}

pub fn mutate(ctx: Context, vm_id: []const u8, action: Action) !MutationResult {
    if (!vps_mutex.tryLock()) return error.VpsBusy;
    defer vps_mutex.unlock();
    if (vm_id.len == 0 or vm_id.len > 128) return error.InvalidVpsRequest;
    if (!ctx.config.hasHostingerAuth()) return error.VpsWriteUnavailable;

    const observation_optional = try ctx.db.latestObservation(ctx.gpa, "hostinger", "vps");
    defer if (observation_optional) |observation| observation.deinit(ctx.gpa);
    if (observation_optional == null or
        !observation_optional.?.hasSuccessfulObservation() or
        !std.mem.eql(u8, observation_optional.?.attempt_status, "ok") or
        !std.mem.eql(u8, observationFreshness(observation_optional, freshAfterSeconds(ctx.config)), "current"))
        return error.VpsWriteUnavailable;

    var machines = try ctx.db.hostinger().hostingerVpsRows(ctx.gpa, 200);
    defer machines.deinit(ctx.gpa);
    const machine = findMachine(machines.items, vm_id) orelse return error.VpsNotObserved;
    const target_observation = try ctx.db.latestObservationForTarget(ctx.gpa, "hostinger", "vps-detail", machine.id);
    defer if (target_observation) |observation| observation.deinit(ctx.gpa);
    if (target_observation) |observation| if (!std.mem.eql(u8, observation.attempt_status, "ok")) return error.VpsWriteUnavailable;
    if (!actionAllowed(machine.status, action)) return error.VpsActionUnavailable;

    var provider_output = std.Io.Writer.Allocating.init(ctx.gpa);
    defer provider_output.deinit();
    try app_provider_writes.vpsAction(providerContext(ctx), machine.id, action, &provider_output.writer);
    const job_id = try acceptedJobId(ctx.gpa, provider_output.written());
    errdefer if (job_id) |value| ctx.gpa.free(value);

    var observed_state: ?[]u8 = null;
    errdefer if (observed_state) |value| ctx.gpa.free(value);
    const confirmed = if (job_id) |id|
        try reconcileWithJob(ctx, machine.id, action, id, &observed_state)
    else
        try reconcileWithoutJob(ctx, machine.id, action, &observed_state);
    if (confirmed) {
        const summary = try std.fmt.allocPrint(ctx.gpa, "Hostinger confirmed {s} for machine {s} in state {s}.", .{ @tagName(action), machine.id, observed_state orelse "unknown" });
        defer ctx.gpa.free(summary);
        try recordTargetAttempt(ctx, machine.id, "ok", summary, null);
        return .{ .outcome = .confirmed, .provider_job_id = job_id, .observed_state = observed_state };
    }

    const summary = try std.fmt.allocPrint(ctx.gpa, "Hostinger accepted {s} for machine {s}, but the bounded confirmation did not reach a terminal state.", .{ @tagName(action), machine.id });
    defer ctx.gpa.free(summary);
    try recordTargetAttempt(ctx, machine.id, "pending", summary, null);
    return .{ .outcome = .accepted_pending, .provider_job_id = job_id, .observed_state = observed_state };
}

pub fn writeMutationJson(result: MutationResult, writer: anytype) !void {
    try writer.writeAll("{\"ok\":true,");
    try core_json.writeStringField(writer, "result", if (result.outcome == .confirmed) "confirmed" else "accepted_pending", true);
    try core_json.writeBoolField(writer, "reconciled", result.outcome == .confirmed, true);
    try core_json.writeNullableStringField(writer, "provider_job_id", result.provider_job_id, true);
    try core_json.writeNullableStringField(writer, "state", result.observed_state, false);
    try writer.writeAll("}\n");
}

fn refreshLocked(ctx: Context) !void {
    const token = ctx.config.hostinger_api_token orelse {
        try recordListAttempt(ctx, "error", "Hostinger credentials are not configured.", null);
        return error.VpsProviderUnavailable;
    };
    var client = provider_hostinger.Client.init(token);
    client.base_url_override = ctx.config.hostinger_api_base;
    const response = client.getVirtualMachines(ctx.io, ctx.gpa) catch |err| {
        const summary = try std.fmt.allocPrint(ctx.gpa, "Hostinger machine refresh failed: {s}", .{@errorName(err)});
        defer ctx.gpa.free(summary);
        try recordListAttempt(ctx, "error", summary, null);
        return error.VpsProviderUnavailable;
    };
    defer response.deinit(ctx.gpa);
    const redacted = try core_redact.providerResponse(ctx.gpa, response.body);
    defer ctx.gpa.free(redacted);
    try ctx.db.insertProviderRaw("hostinger", provider_hostinger.virtual_machines_path, @backingInt(response.status), redacted);
    if (!net_http.isOk(response.status) or !validVpsCollection(ctx.gpa, redacted)) {
        try recordListAttempt(ctx, "error", "Hostinger rejected the machine inventory read.", redacted);
        return error.VpsProviderRejected;
    }
    var rows = try provider_hostinger_models.parseVpsRows(ctx.gpa, redacted);
    defer rows.deinit(ctx.gpa);

    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    try ctx.db.exec("DELETE FROM hostinger_vps");
    for (rows.items) |row| {
        try ctx.db.upsertHostingerVps(row.id, row.name, row.status, row.ipv4, row.plan, row.raw_json);
    }
    const summary = try std.fmt.allocPrint(ctx.gpa, "Observed {d} Hostinger {s}.", .{ rows.items.len, if (rows.items.len == 1) "machine" else "machines" });
    defer ctx.gpa.free(summary);
    _ = try ctx.db.insertSnapshot("hostinger", "vps", null, "ok", summary, redacted, null);
    for (rows.items) |row| {
        const target_summary = try std.fmt.allocPrint(ctx.gpa, "Machine {s} was present in the successful inventory refresh.", .{row.id});
        defer ctx.gpa.free(target_summary);
        _ = try ctx.db.insertSnapshot("hostinger", "vps-detail", row.id, "ok", target_summary, null, null);
    }
    try ctx.db.exec("COMMIT");
    committed = true;
    try ctx.db.insertAudit("hostinger.vps.refresh", "ok", summary);
}

fn reconcileWithJob(ctx: Context, vm_id: []const u8, action: Action, job_id: []const u8, observed_state: *?[]u8) !bool {
    var terminal = false;
    for (0..reconcile_polls) |_| {
        const state = readJobState(ctx, vm_id, job_id) catch return false;
        switch (state) {
            .pending => continue,
            .failed => {
                const summary = try std.fmt.allocPrint(ctx.gpa, "Hostinger job {s} failed for machine {s}.", .{ job_id, vm_id });
                defer ctx.gpa.free(summary);
                try recordTargetAttempt(ctx, vm_id, "error", summary, null);
                return error.VpsActionFailed;
            },
            .succeeded => {
                terminal = true;
                break;
            },
        }
    }
    if (!terminal) return false;
    for (0..reconcile_polls) |_| {
        const state = readMachineState(ctx, vm_id) catch return false;
        if (observed_state.*) |prior| ctx.gpa.free(prior);
        observed_state.* = state;
        if (actionReachedState(action, state)) return true;
    }
    return false;
}

fn reconcileWithoutJob(ctx: Context, vm_id: []const u8, action: Action, observed_state: *?[]u8) !bool {
    for (0..reconcile_polls) |_| {
        const state = readMachineState(ctx, vm_id) catch return false;
        if (observed_state.*) |prior| ctx.gpa.free(prior);
        observed_state.* = state;
        if (action != .restart and actionReachedState(action, state)) return true;
    }
    // A restart has the same before/after state; without a provider job there
    // is no evidence that it completed, so it remains explicitly pending.
    return false;
}

fn readJobState(ctx: Context, vm_id: []const u8, job_id: []const u8) !JobState {
    const token = ctx.config.hostinger_api_token orelse return error.VpsProviderUnavailable;
    var client = provider_hostinger.Client.init(token);
    client.base_url_override = ctx.config.hostinger_api_base;
    const response = try client.getActionDetails(ctx.io, ctx.gpa, vm_id, job_id);
    defer response.deinit(ctx.gpa);
    const redacted = try core_redact.providerResponse(ctx.gpa, response.body);
    defer ctx.gpa.free(redacted);
    const endpoint = try std.fmt.allocPrint(ctx.gpa, "{s}/{s}/actions/{s}", .{ provider_hostinger.virtual_machines_path, vm_id, job_id });
    defer ctx.gpa.free(endpoint);
    try ctx.db.insertProviderRaw("hostinger", endpoint, @backingInt(response.status), redacted);
    if (!net_http.isOk(response.status)) return error.VpsProviderRejected;
    return parseJobState(ctx.gpa, redacted) orelse error.VpsProviderRejected;
}

fn readMachineState(ctx: Context, vm_id: []const u8) ![]u8 {
    const token = ctx.config.hostinger_api_token orelse return error.VpsProviderUnavailable;
    var client = provider_hostinger.Client.init(token);
    client.base_url_override = ctx.config.hostinger_api_base;
    const response = try client.getVirtualMachineDetails(ctx.io, ctx.gpa, vm_id);
    defer response.deinit(ctx.gpa);
    const redacted = try core_redact.providerResponse(ctx.gpa, response.body);
    defer ctx.gpa.free(redacted);
    const endpoint = try std.fmt.allocPrint(ctx.gpa, "{s}/{s}", .{ provider_hostinger.virtual_machines_path, vm_id });
    defer ctx.gpa.free(endpoint);
    try ctx.db.insertProviderRaw("hostinger", endpoint, @backingInt(response.status), redacted);
    if (!net_http.isOk(response.status) or !validVpsDetail(ctx.gpa, redacted)) return error.VpsProviderRejected;
    var rows = try provider_hostinger_models.parseVpsRows(ctx.gpa, redacted);
    defer rows.deinit(ctx.gpa);
    if (rows.items.len != 1 or !std.mem.eql(u8, rows.items[0].id, vm_id)) return error.VpsProviderRejected;
    const row = rows.items[0];
    try ctx.db.upsertHostingerVps(row.id, row.name, row.status, row.ipv4, row.plan, row.raw_json);
    return try ctx.gpa.dupe(u8, row.status orelse "unknown");
}

fn acceptedJobId(gpa: Allocator, body: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return error.VpsProviderUnavailable;
    defer parsed.deinit();
    if (parsed.value != .object) return error.VpsProviderUnavailable;
    const ok = core_json.fieldBool(parsed.value, "ok") orelse false;
    const status = core_json.fieldInt(parsed.value, "status") orelse 0;
    if (!ok) return if (status == 0) error.VpsProviderUnavailable else error.VpsProviderRejected;
    const result = core_json.field(parsed.value, "result") orelse return null;
    if (result != .object) return null;
    if (core_json.fieldAnyString(gpa, result, "id")) |id| return id;
    const data = core_json.field(result, "data") orelse return null;
    if (data != .object) return null;
    if (core_json.fieldAnyString(gpa, data, "id")) |id| return id;
    const action = core_json.field(data, "action") orelse return null;
    if (action != .object) return null;
    return core_json.fieldAnyString(gpa, action, "id");
}

fn parseJobState(gpa: Allocator, body: []const u8) ?JobState {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const value = core_json.field(parsed.value, "data") orelse parsed.value;
    if (value != .object) return null;
    const raw = core_json.fieldString(value, "state") orelse core_json.fieldString(value, "status") orelse return null;
    if (equalsAnyIgnoreCase(raw, &.{ "done", "complete", "completed", "success", "succeeded" })) return .succeeded;
    if (equalsAnyIgnoreCase(raw, &.{ "failed", "error", "cancelled", "canceled" })) return .failed;
    return .pending;
}

fn validVpsCollection(gpa: Allocator, body: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return false;
    defer parsed.deinit();
    const items = switch (parsed.value) {
        .array => |array| array.items,
        .object => |object| blk: {
            const data = object.get("data") orelse return false;
            if (data != .array) return false;
            break :blk data.array.items;
        },
        else => return false,
    };
    for (items) |item| if (!validVpsValue(item)) return false;
    return true;
}

fn validVpsDetail(gpa: Allocator, body: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const value = parsed.value.object.get("data") orelse parsed.value;
    return validVpsValue(value);
}

fn validVpsValue(value: std.json.Value) bool {
    return value == .object and value.object.get("id") != null and
        value.object.get("hostname") != null and value.object.get("state") != null;
}

fn recordListAttempt(ctx: Context, status: []const u8, summary: []const u8, raw: ?[]const u8) !void {
    _ = try ctx.db.insertSnapshot("hostinger", "vps", null, status, summary, raw, null);
    try ctx.db.insertAudit("hostinger.vps.refresh", status, summary);
}

fn recordTargetAttempt(ctx: Context, vm_id: []const u8, status: []const u8, summary: []const u8, raw: ?[]const u8) !void {
    _ = try ctx.db.insertSnapshot("hostinger", "vps-detail", vm_id, status, summary, raw, null);
    try ctx.db.insertAudit("hostinger.vps.reconcile", status, summary);
}

fn providerContext(ctx: Context) app_provider_writes.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .write_meta = ctx.write_meta };
}

fn findMachine(rows: []const db_store.HostingerVpsRow, vm_id: []const u8) ?db_store.HostingerVpsRow {
    for (rows) |row| if (std.mem.eql(u8, row.id, vm_id)) return row;
    return null;
}

fn actionAllowed(status: []const u8, action: Action) bool {
    if (equalsAnyIgnoreCase(status, &.{ "running", "started", "online" })) return action == .stop or action == .restart;
    if (equalsAnyIgnoreCase(status, &.{ "stopped", "off", "offline", "powered_off" })) return action == .start;
    return false;
}

fn actionReachedState(action: Action, status: []const u8) bool {
    return switch (action) {
        .start, .restart => equalsAnyIgnoreCase(status, &.{ "running", "started", "online" }),
        .stop => equalsAnyIgnoreCase(status, &.{ "stopped", "off", "offline", "powered_off" }),
    };
}

fn equalsAnyIgnoreCase(value: []const u8, candidates: []const []const u8) bool {
    for (candidates) |candidate| if (std.ascii.eqlIgnoreCase(value, candidate)) return true;
    return false;
}

fn freshAfterSeconds(config: core_config.Config) i64 {
    return @max(@as(i64, config.refresh_seconds) * 2, 600);
}

fn observationFreshness(observation: ?db_store.Observation, fresh_after_seconds: i64) []const u8 {
    const value = observation orelse return "unavailable";
    if (!value.hasSuccessfulObservation()) return "unavailable";
    if (!std.mem.eql(u8, value.attempt_status, "ok")) return "stale";
    return if (value.age_seconds >= 0 and value.age_seconds <= fresh_after_seconds) "current" else "stale";
}

fn capabilityReason(has_auth: bool, freshness: []const u8, observation: ?db_store.Observation) []const u8 {
    if (!has_auth) return "Hostinger credentials are not configured; stored machines are read-only.";
    if (observation == null or !observation.?.hasSuccessfulObservation()) return "Refresh successfully before controlling a machine.";
    if (!std.mem.eql(u8, observation.?.attempt_status, "ok")) return "The latest refresh failed; retained machines are read-only.";
    if (!std.mem.eql(u8, freshness, "current")) return "The machine observation is stale; refresh before controlling a machine.";
    return "Hostinger access and the exact observed machine identities were confirmed.";
}

fn machineObservedAt(machine: db_store.HostingerVpsRow, target: ?db_store.Observation, list: ?db_store.Observation) []const u8 {
    if (target) |observation| if (observation.hasSuccessfulObservation()) return observation.observed_at;
    if (list) |observation| if (observation.hasSuccessfulObservation()) return observation.observed_at;
    return machine.updated_at;
}

fn machineCapabilityReason(actionable: bool, target: ?db_store.Observation) []const u8 {
    if (actionable) return "State-aware lifecycle actions are available for this observed machine.";
    if (target) |observation| if (std.mem.eql(u8, observation.attempt_status, "pending")) return "A provider action is accepted but not yet confirmed; refresh to reconcile it.";
    return "Lifecycle actions require a current successful machine observation.";
}

test "VPS state transitions expose only meaningful actions" {
    try std.testing.expect(actionAllowed("running", .stop));
    try std.testing.expect(actionAllowed("running", .restart));
    try std.testing.expect(!actionAllowed("running", .start));
    try std.testing.expect(actionAllowed("stopped", .start));
    try std.testing.expect(!actionAllowed("stopped", .stop));
    try std.testing.expect(!actionAllowed("starting", .restart));
}

test "Hostinger VPS envelopes reject malformed and partial resources" {
    const allocator = std.testing.allocator;
    try std.testing.expect(validVpsCollection(allocator, "{\"data\":[]}"));
    try std.testing.expect(validVpsCollection(allocator, "{\"data\":[{\"id\":1,\"hostname\":\"vm\",\"state\":\"running\"}]}"));
    try std.testing.expect(!validVpsCollection(allocator, "{\"data\":[{\"id\":1}]}"));
    try std.testing.expect(!validVpsCollection(allocator, "not-json"));
    try std.testing.expect(validVpsDetail(allocator, "{\"data\":{\"id\":1,\"hostname\":\"vm\",\"state\":\"stopped\"}}"));
}

test "Hostinger job states distinguish terminal success and failure" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(JobState.succeeded, parseJobState(allocator, "{\"data\":{\"state\":\"completed\"}}").?);
    try std.testing.expectEqual(JobState.failed, parseJobState(allocator, "{\"data\":{\"state\":\"failed\"}}").?);
    try std.testing.expectEqual(JobState.pending, parseJobState(allocator, "{\"data\":{\"state\":\"running\"}}").?);
}
