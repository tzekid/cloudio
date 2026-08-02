const std = @import("std");
const nob = @import("nob_sdk");

pub const max_stdout_bytes = 1024 * 1024;
pub const max_resource_facts_bytes = 64 * 1024;

pub const Identity = struct {
    project_id: []const u8,
    manifest_sha256: []const u8,
    action_ids: []const []const u8,
    resource_ids: []const []const u8,
};

pub const DescriptionDocument = struct {
    parsed: std.json.Parsed(nob.types.Description),

    pub fn deinit(self: *DescriptionDocument) void {
        self.parsed.deinit();
    }

    pub fn value(self: *const DescriptionDocument) *const nob.types.Description {
        return &self.parsed.value;
    }
};

pub const ObservationDocument = struct {
    parsed: std.json.Parsed(nob.types.Observation),

    pub fn deinit(self: *ObservationDocument) void {
        self.parsed.deinit();
    }

    pub fn value(self: *const ObservationDocument) *const nob.types.Observation {
        return &self.parsed.value;
    }
};

pub fn parseDescription(allocator: std.mem.Allocator, bytes: []const u8, identity: Identity) !DescriptionDocument {
    try validateDocumentBytes(bytes);
    var parsed = try std.json.parseFromSlice(nob.types.Description, allocator, bytes, .{
        .allocate = .alloc_always,
        .max_value_len = max_stdout_bytes,
    });
    errdefer parsed.deinit();
    const description = &parsed.value;
    if (!std.mem.eql(u8, description.schema, "nob.zig/describe/v1")) return error.InvalidSchema;
    if (description.protocol.major != nob.types.protocol_major) return error.UnsupportedProtocol;
    if (!std.mem.eql(u8, description.project_id, identity.project_id)) return error.ProjectIdentityMismatch;
    if (!std.mem.eql(u8, description.manifest_sha256, identity.manifest_sha256)) return error.ManifestIdentityMismatch;
    if (description.protocol.features.len > 32 or description.actions.len > 64 or description.resources.len > 128) return error.ProtocolLimitExceeded;
    try validateText(description.runner.sdk_version, 128);
    try validateText(description.runner.build_id, 256);
    try validateText(description.runner.zig_version, 128);
    for (description.protocol.features, 0..) |feature, index| {
        try validateText(feature, 64);
        try requireUniqueStrings(description.protocol.features[0..index], feature);
    }
    for (description.actions, 0..) |action, index| {
        if (!contains(identity.action_ids, action.id)) return error.UnknownAction;
        for (description.actions[0..index]) |prior| if (std.mem.eql(u8, prior.id, action.id)) return error.DuplicateId;
        if (action.reason) |reason| try validateText(reason, 512);
        if (action.available and action.reason != null) return error.InvalidAvailability;
    }
    for (description.resources, 0..) |resource, index| {
        if (!contains(identity.resource_ids, resource.id)) return error.UnknownResource;
        for (description.resources[0..index]) |prior| if (std.mem.eql(u8, prior.id, resource.id)) return error.DuplicateId;
    }
    return .{ .parsed = parsed };
}

pub fn parseObservation(allocator: std.mem.Allocator, bytes: []const u8, identity: Identity) !ObservationDocument {
    try validateDocumentBytes(bytes);
    var parsed = try std.json.parseFromSlice(nob.types.Observation, allocator, bytes, .{
        .allocate = .alloc_always,
        .max_value_len = max_stdout_bytes,
    });
    errdefer parsed.deinit();
    const observation = &parsed.value;
    if (!std.mem.eql(u8, observation.schema, "nob.zig/observe/v1")) return error.InvalidSchema;
    if (!std.mem.eql(u8, observation.project_id, identity.project_id)) return error.ProjectIdentityMismatch;
    if (!std.mem.eql(u8, observation.manifest_sha256, identity.manifest_sha256)) return error.ManifestIdentityMismatch;
    try validateText(observation.summary, 2048);
    try validateDigest(observation.source.fingerprint);
    if (observation.source.revision) |revision| try validateText(revision, 256);
    if (observation.resources.len > 128) return error.ProtocolLimitExceeded;
    for (observation.resources, 0..) |resource, index| {
        if (!contains(identity.resource_ids, resource.id)) return error.UnknownResource;
        for (observation.resources[0..index]) |prior| if (std.mem.eql(u8, prior.id, resource.id)) return error.DuplicateId;
        try validateText(resource.summary, 2048);
        var encoded = std.Io.Writer.Allocating.init(allocator);
        defer encoded.deinit();
        try std.json.Stringify.value(resource.facts, .{}, &encoded.writer);
        if (encoded.written().len > max_resource_facts_bytes) return error.ResourceFactsTooLarge;
    }
    return .{ .parsed = parsed };
}

fn validateDocumentBytes(bytes: []const u8) !void {
    if (bytes.len == 0) return error.EmptyProtocolDocument;
    if (bytes.len > max_stdout_bytes) return error.ProtocolDocumentTooLarge;
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
}

fn validateText(value: []const u8, max: usize) !void {
    if (value.len == 0 or value.len > max or !std.unicode.utf8ValidateSlice(value)) return error.InvalidProtocolText;
    for (value) |byte| if (byte == 0 or (byte < 0x20 and byte != '\t')) return error.InvalidProtocolText;
}

fn validateDigest(value: []const u8) !void {
    if (value.len != 64) return error.InvalidDigest;
    for (value) |byte| if (!std.ascii.isHex(byte)) return error.InvalidDigest;
}

fn contains(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, needle)) return true;
    return false;
}

fn requireUniqueStrings(values: []const []const u8, needle: []const u8) !void {
    if (contains(values, needle)) return error.DuplicateValue;
}

test "description and observation fixtures validate against reviewed identities" {
    const allocator = std.testing.allocator;
    const actions = [_][]const u8{ "check", "deploy" };
    const resources = [_][]const u8{ "web-service", "health" };
    const identity = Identity{
        .project_id = "dev.example.service",
        .manifest_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        .action_ids = &actions,
        .resource_ids = &resources,
    };
    const description_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "vendor/nob/schema/fixtures/describe-valid.json",
        allocator,
        .limited(max_stdout_bytes),
    );
    defer allocator.free(description_bytes);
    var description = try parseDescription(allocator, description_bytes, identity);
    defer description.deinit();
    try std.testing.expectEqual(@as(usize, 2), description.value().actions.len);

    const observation_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "vendor/nob/schema/fixtures/observe-valid.json",
        allocator,
        .limited(max_stdout_bytes),
    );
    defer allocator.free(observation_bytes);
    var observation = try parseObservation(allocator, observation_bytes, identity);
    defer observation.deinit();
    try std.testing.expectEqual(nob.types.Status.healthy, observation.value().status);

    const restricted = Identity{
        .project_id = identity.project_id,
        .manifest_sha256 = identity.manifest_sha256,
        .action_ids = &actions,
        .resource_ids = &.{"web-service"},
    };
    try std.testing.expectError(error.UnknownResource, parseObservation(allocator, observation_bytes, restricted));
}
