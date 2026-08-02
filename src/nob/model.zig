const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DiscoveryState = enum {
    candidate,
    valid,
    invalid,
    conflict,
    missing,

    pub fn text(self: DiscoveryState) []const u8 {
        return @tagName(self);
    }
};

pub const TrustState = enum {
    discovered,
    trusted,
    @"review-required",
    revoked,

    pub fn text(self: TrustState) []const u8 {
        return @tagName(self);
    }
};

pub const ProjectStatus = enum {
    healthy,
    degraded,
    stopped,
    missing,
    unknown,

    pub fn text(self: ProjectStatus) []const u8 {
        return @tagName(self);
    }
};

pub const RunnerState = enum {
    @"not-built",
    building,
    ready,
    failed,

    pub fn text(self: RunnerState) []const u8 {
        return @tagName(self);
    }
};

pub const Project = struct {
    id: i64,
    declared_id: ?[]u8,
    display_name: []u8,
    kind: []u8,
    root_path: []u8,
    manifest_path: ?[]u8,
    manifest_sha256: ?[]u8,
    trusted_manifest_sha256: ?[]u8,
    discovery_state: DiscoveryState,
    trust_state: TrustState,
    status: ProjectStatus,
    status_summary: ?[]u8,
    protocol_major: ?i64,
    protocol_minor: ?i64,
    runner_state: RunnerState,
    runner_path: ?[]u8,
    runner_sha256: ?[]u8,
    runner_detail: ?[]u8,
    repository_kind: ?[]u8,
    repository_identity: ?[]u8,
    head_revision: ?[]u8,
    source_fingerprint: ?[]u8,
    source_dirty: ?bool,
    last_seen_at: i64,
    last_observed_at: ?i64,
    updated_at: i64,

    pub fn deinit(self: Project, allocator: Allocator) void {
        freeOptional(allocator, self.declared_id);
        allocator.free(self.display_name);
        allocator.free(self.kind);
        allocator.free(self.root_path);
        freeOptional(allocator, self.manifest_path);
        freeOptional(allocator, self.manifest_sha256);
        freeOptional(allocator, self.trusted_manifest_sha256);
        freeOptional(allocator, self.status_summary);
        freeOptional(allocator, self.runner_path);
        freeOptional(allocator, self.runner_sha256);
        freeOptional(allocator, self.runner_detail);
        freeOptional(allocator, self.repository_kind);
        freeOptional(allocator, self.repository_identity);
        freeOptional(allocator, self.head_revision);
        freeOptional(allocator, self.source_fingerprint);
    }
};

pub const Projects = struct {
    items: []Project,

    pub fn deinit(self: *Projects, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Resource = struct {
    resource_id: []u8,
    kind: []u8,
    label: []u8,
    ownership: []u8,
    controls_json: []u8,
    declaration_json: []u8,
    runner_observation_json: ?[]u8,
    cloudio_observation_json: ?[]u8,
    effective_status: ProjectStatus,
    status_summary: ?[]u8,
    observed_at: ?i64,

    pub fn deinit(self: Resource, allocator: Allocator) void {
        allocator.free(self.resource_id);
        allocator.free(self.kind);
        allocator.free(self.label);
        allocator.free(self.ownership);
        allocator.free(self.controls_json);
        allocator.free(self.declaration_json);
        freeOptional(allocator, self.runner_observation_json);
        freeOptional(allocator, self.cloudio_observation_json);
        freeOptional(allocator, self.status_summary);
    }
};

pub const Resources = struct {
    items: []Resource,

    pub fn deinit(self: *Resources, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Action = struct {
    action_id: []u8,
    label: []u8,
    effect: []u8,
    confirmation: []u8,
    declaration_json: []u8,
    available: bool,
    unavailable_reason: ?[]u8,

    pub fn deinit(self: Action, allocator: Allocator) void {
        allocator.free(self.action_id);
        allocator.free(self.label);
        allocator.free(self.effect);
        allocator.free(self.confirmation);
        allocator.free(self.declaration_json);
        freeOptional(allocator, self.unavailable_reason);
    }
};

pub const Actions = struct {
    items: []Action,

    pub fn deinit(self: *Actions, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Plan = struct {
    id: []u8,
    project_id: i64,
    action_id: []u8,
    resource_id: ?[]u8,
    input_json: []u8,
    plan_json: []u8,
    plan_sha256: []u8,
    manifest_sha256: []u8,
    source_fingerprint: ?[]u8,
    effect: []u8,
    confirmation: []u8,
    state: []u8,
    requested_by: []u8,
    runner_sha256: ?[]u8,
    source_revision: ?[]u8,
    source_dirty: ?bool,
    created_at: i64,
    expires_at: i64,
    consumed_at: ?i64,

    pub fn deinit(self: Plan, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.action_id);
        freeOptional(allocator, self.resource_id);
        allocator.free(self.input_json);
        allocator.free(self.plan_json);
        allocator.free(self.plan_sha256);
        allocator.free(self.manifest_sha256);
        freeOptional(allocator, self.source_fingerprint);
        allocator.free(self.effect);
        allocator.free(self.confirmation);
        allocator.free(self.state);
        allocator.free(self.requested_by);
        freeOptional(allocator, self.runner_sha256);
        freeOptional(allocator, self.source_revision);
    }
};

pub const Run = struct {
    id: []u8,
    project_id: i64,
    plan_id: ?[]u8,
    action_id: []u8,
    resource_id: ?[]u8,
    state: []u8,
    outcome: ?[]u8,
    effect: []u8,
    requested_by: []u8,
    idempotency_key: ?[]u8,
    runner_path: ?[]u8,
    log_path: ?[]u8,
    stderr_path: ?[]u8,
    summary: ?[]u8,
    error_code: ?[]u8,
    manifest_sha256: ?[]u8,
    source_fingerprint: ?[]u8,
    runner_sha256: ?[]u8,
    plan_sha256: ?[]u8,
    queued_at: i64,
    started_at: ?i64,
    finished_at: ?i64,
    cancel_requested_at: ?i64,
    heartbeat_at: ?i64,

    pub fn deinit(self: Run, allocator: Allocator) void {
        allocator.free(self.id);
        freeOptional(allocator, self.plan_id);
        allocator.free(self.action_id);
        freeOptional(allocator, self.resource_id);
        allocator.free(self.state);
        freeOptional(allocator, self.outcome);
        allocator.free(self.effect);
        allocator.free(self.requested_by);
        freeOptional(allocator, self.idempotency_key);
        freeOptional(allocator, self.runner_path);
        freeOptional(allocator, self.log_path);
        freeOptional(allocator, self.stderr_path);
        freeOptional(allocator, self.summary);
        freeOptional(allocator, self.error_code);
        freeOptional(allocator, self.manifest_sha256);
        freeOptional(allocator, self.source_fingerprint);
        freeOptional(allocator, self.runner_sha256);
        freeOptional(allocator, self.plan_sha256);
    }
};

pub const Runs = struct {
    items: []Run,

    pub fn deinit(self: *Runs, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const RunEvent = struct {
    operation_id: []u8,
    seq: i64,
    event_type: []u8,
    level: ?[]u8,
    payload_json: []u8,
    received_at: i64,

    pub fn deinit(self: RunEvent, allocator: Allocator) void {
        allocator.free(self.operation_id);
        allocator.free(self.event_type);
        freeOptional(allocator, self.level);
        allocator.free(self.payload_json);
    }
};

pub const RunEvents = struct {
    items: []RunEvent,

    pub fn deinit(self: *RunEvents, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub fn parseDiscoveryState(text: []const u8) !DiscoveryState {
    return std.meta.stringToEnum(DiscoveryState, text) orelse error.InvalidDatabaseValue;
}

pub fn parseTrustState(text: []const u8) !TrustState {
    return std.meta.stringToEnum(TrustState, text) orelse error.InvalidDatabaseValue;
}

pub fn parseProjectStatus(text: []const u8) !ProjectStatus {
    return std.meta.stringToEnum(ProjectStatus, text) orelse error.InvalidDatabaseValue;
}

pub fn parseRunnerState(text: []const u8) !RunnerState {
    return std.meta.stringToEnum(RunnerState, text) orelse error.InvalidDatabaseValue;
}

fn freeOptional(allocator: Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}

test "database state names are protocol-stable" {
    try std.testing.expectEqualStrings("review-required", TrustState.@"review-required".text());
    try std.testing.expectEqualStrings("not-built", RunnerState.@"not-built".text());
    try std.testing.expectEqual(DiscoveryState.conflict, try parseDiscoveryState("conflict"));
}
