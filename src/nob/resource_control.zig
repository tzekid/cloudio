const std = @import("std");
const source = @import("nob_source");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Binding = struct {
    resource: *const nob.types.Resource,
    control: nob.types.Control,
};

pub const Planned = struct {
    action_id: []u8,
    plan_json: []u8,
    plan_sha256: []u8,

    pub fn deinit(self: Planned, allocator: Allocator) void {
        allocator.free(self.action_id);
        allocator.free(self.plan_json);
        allocator.free(self.plan_sha256);
    }
};

pub fn create(
    allocator: Allocator,
    manifest: *const nob.types.Manifest,
    manifest_sha256: []const u8,
    source_state: source.State,
    resource_id: []const u8,
    control_name: []const u8,
) !Planned {
    _ = try resolve(manifest, resource_id, control_name);
    const action_id = try actionId(allocator, resource_id, control_name);
    errdefer allocator.free(action_id);
    var parameters: std.json.ObjectMap = .empty;
    defer parameters.deinit(allocator);
    const preconditions = [_]nob.types.Precondition{.{
        .id = "resource-control-declared",
        .status = .satisfied,
        .summary = "The exact resource and control are present in the reviewed manifest",
    }};
    const affected = [_][]const u8{resource_id};
    const stages = [_]nob.types.Stage{.{
        .id = "control",
        .label = "Apply declared resource control",
        .reversible = true,
    }};
    const plan = nob.types.Plan{
        .schema = nob.plan.plan_schema,
        .project_id = manifest.project.id,
        .action_id = action_id,
        .manifest_sha256 = manifest_sha256,
        .source = .{
            .revision = source_state.revision,
            .dirty = source_state.dirty,
            .fingerprint = source_state.fingerprint,
        },
        .parameters = .{ .object = parameters },
        .effect = .@"runtime-change",
        .confirmation = .@"review-plan",
        .expected_downtime_seconds = 0,
        .preconditions = &preconditions,
        .affected_resources = &affected,
        .stages = &stages,
        .broker_requests = &.{},
        .rollback = .{ .mode = .none },
        .notes = &.{},
    };
    const plan_json = try stringify(allocator, plan);
    errdefer allocator.free(plan_json);
    const plan_sha256 = try hashBytes(allocator, plan_json);
    return .{ .action_id = action_id, .plan_json = plan_json, .plan_sha256 = plan_sha256 };
}

pub fn validate(
    allocator: Allocator,
    manifest: *const nob.types.Manifest,
    manifest_sha256: []const u8,
    source_state: source.State,
    resource_id: []const u8,
    control_name: []const u8,
    plan_bytes: []const u8,
) !std.json.Parsed(nob.types.Plan) {
    _ = try resolve(manifest, resource_id, control_name);
    var parsed = try std.json.parseFromSlice(nob.types.Plan, allocator, plan_bytes, .{
        .allocate = .alloc_always,
        .max_value_len = nob.json.max_plan_bytes,
    });
    errdefer parsed.deinit();
    const plan = &parsed.value;
    const expected_action = try actionId(allocator, resource_id, control_name);
    defer allocator.free(expected_action);
    if (!std.mem.eql(u8, plan.schema, nob.plan.plan_schema) or
        !std.mem.eql(u8, plan.project_id, manifest.project.id) or
        !std.mem.eql(u8, plan.action_id, expected_action) or
        !std.mem.eql(u8, plan.manifest_sha256, manifest_sha256)) return error.ResourcePlanIdentityMismatch;
    if (plan.source.dirty != source_state.dirty or
        !optionalEqual(plan.source.revision, source_state.revision) or
        !std.mem.eql(u8, plan.source.fingerprint, source_state.fingerprint)) return error.SourceChanged;
    if (plan.parameters != .object or plan.parameters.object.count() != 0 or
        plan.effect != .@"runtime-change" or plan.confirmation != .@"review-plan" or
        plan.expected_downtime_seconds != 0) return error.InvalidResourcePlan;
    if (plan.preconditions.len != 1 or
        !std.mem.eql(u8, plan.preconditions[0].id, "resource-control-declared") or
        plan.preconditions[0].status != .satisfied) return error.InvalidResourcePlan;
    if (plan.affected_resources.len != 1 or !std.mem.eql(u8, plan.affected_resources[0], resource_id)) return error.InvalidResourcePlan;
    if (plan.stages.len != 1 or !std.mem.eql(u8, plan.stages[0].id, "control") or !plan.stages[0].reversible) return error.InvalidResourcePlan;
    if (plan.broker_requests.len != 0 or plan.rollback.mode != .none or plan.notes.len != 0) return error.InvalidResourcePlan;
    return parsed;
}

pub fn resolve(manifest: *const nob.types.Manifest, resource_id: []const u8, control_name: []const u8) !Binding {
    const control = std.meta.stringToEnum(nob.types.Control, control_name) orelse return error.UnknownResourceControl;
    if (control == .logs) return error.ResourceControlIsReadOnly;
    for (manifest.resources) |*resource| {
        if (!std.mem.eql(u8, resource.id, resource_id)) continue;
        if (resource.kind != .@"systemd.service") return error.UnsupportedResourceControl;
        if (resource.ownership == .observed) return error.ResourceControlNotOwned;
        var declared = false;
        for (resource.controls) |candidate| if (candidate == control) {
            declared = true;
            break;
        };
        if (!declared) return error.UndeclaredResourceControl;
        const scope = resource.spec.object.get("scope") orelse return error.InvalidSystemdResource;
        if (scope != .string or !std.mem.eql(u8, scope.string, "user")) return error.UnsupportedPrivilege;
        return .{ .resource = resource, .control = control };
    }
    return error.UnknownResource;
}

pub fn actionId(allocator: Allocator, resource_id: []const u8, control_name: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "resource:{s}:{s}", .{ resource_id, control_name });
}

pub fn controlFromActionId(action_id: []const u8, resource_id: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, action_id, "resource:")) return null;
    const rest = action_id["resource:".len..];
    if (!std.mem.startsWith(u8, rest, resource_id) or rest.len <= resource_id.len or rest[resource_id.len] != ':') return null;
    const control = rest[resource_id.len + 1 ..];
    return if (control.len == 0 or std.mem.indexOfScalar(u8, control, ':') != null) null else control;
}

fn stringify(allocator: Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return try output.toOwnedSlice();
}

fn hashBytes(allocator: Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return try std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn optionalEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

test "direct controls are limited to declared adopted or managed user services" {
    var spec: std.json.ObjectMap = .empty;
    defer spec.deinit(std.testing.allocator);
    try spec.put(std.testing.allocator, "scope", .{ .string = "user" });
    try spec.put(std.testing.allocator, "unit", .{ .string = "demo.service" });
    const resources = [_]nob.types.Resource{.{
        .id = "service",
        .kind = .@"systemd.service",
        .label = "Service",
        .ownership = .adopted,
        .controls = &.{ .restart, .logs },
        .spec = .{ .object = spec },
    }};
    const manifest = nob.types.Manifest{
        .schema = nob.types.manifest_schema,
        .project = .{ .id = "dev.example.demo", .display_name = "Demo", .kind = .service },
        .runner = .{ .kind = .@"zig-build", .protocol = .{ .major = 1, .minor = 0 } },
        .resources = &resources,
        .actions = &.{},
    };
    try std.testing.expectEqual(nob.types.Control.restart, (try resolve(&manifest, "service", "restart")).control);
    try std.testing.expectError(error.UndeclaredResourceControl, resolve(&manifest, "service", "stop"));
    try std.testing.expectError(error.ResourceControlIsReadOnly, resolve(&manifest, "service", "logs"));
}
