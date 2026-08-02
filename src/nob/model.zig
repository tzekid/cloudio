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
