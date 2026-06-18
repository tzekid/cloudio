const std = @import("std");
const core_json = @import("core_json");
const provider_capabilities = @import("provider_capabilities");
const provider_routes = @import("provider_routes");

pub const PlanKind = enum {
    read_plan,
    dry_run_mutation,
};

pub const RouteSafetyPolicy = struct {
    execution: []const u8,
    write_policy: []const u8,
    live_provider_request: bool,
    mutation: bool,
    write_enabled: bool,
    write_blocked: bool,
    dry_run_only: bool,
    live_read_supported: bool,
    diagnostic_read_supported: bool,
    dry_run_supported: bool,
    reason: []const u8,
};

pub fn routePolicy(route: provider_routes.Route, kind: PlanKind) RouteSafetyPolicy {
    const mutation = routeIsMutation(route);
    const dry_run_supported = provider_capabilities.routeDryRunSupported(route);

    return switch (kind) {
        .read_plan => .{
            .execution = "plan_only",
            .write_policy = "no_live_mutations",
            .live_provider_request = false,
            .mutation = mutation,
            .write_enabled = false,
            .write_blocked = true,
            .dry_run_only = false,
            .live_read_supported = provider_capabilities.routeLiveReadSupported(route),
            .diagnostic_read_supported = provider_capabilities.routeDiagnosticReadSupported(route),
            .dry_run_supported = dry_run_supported,
            .reason = if (provider_capabilities.routeLiveReadSupported(route))
                "read route is render-planned only; no provider API request is sent"
            else
                "read route is metadata-planned only because the current support policy does not allow a live read",
        },
        .dry_run_mutation => .{
            .execution = "dry_run_only",
            .write_policy = "no_live_mutations",
            .live_provider_request = false,
            .mutation = mutation,
            .write_enabled = false,
            .write_blocked = true,
            .dry_run_only = true,
            .live_read_supported = provider_capabilities.routeLiveReadSupported(route),
            .diagnostic_read_supported = provider_capabilities.routeDiagnosticReadSupported(route),
            .dry_run_supported = dry_run_supported,
            .reason = "mutation route is rendered as reviewable dry-run data only; no provider API request is sent",
        },
    };
}

pub fn routeIsMutation(route: provider_routes.Route) bool {
    return route.method != .GET and route.method != .HEAD;
}

pub fn writeRouteSafetyPolicyJson(writer: anytype, name: []const u8, route: provider_routes.Route, kind: PlanKind, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writePolicyValueJson(writer, routePolicy(route, kind));
    if (trailing_comma) try writer.writeByte(',');
}

fn writePolicyValueJson(writer: anytype, value: RouteSafetyPolicy) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "execution", value.execution, true);
    try writeJsonField(writer, "write_policy", value.write_policy, true);
    try writeBoolField(writer, "live_provider_request", value.live_provider_request, true);
    try writeBoolField(writer, "mutation", value.mutation, true);
    try writeBoolField(writer, "write_enabled", value.write_enabled, true);
    try writeBoolField(writer, "write_blocked", value.write_blocked, true);
    try writeBoolField(writer, "dry_run_only", value.dry_run_only, true);
    try writeBoolField(writer, "live_read_supported", value.live_read_supported, true);
    try writeBoolField(writer, "diagnostic_read_supported", value.diagnostic_read_supported, true);
    try writeBoolField(writer, "dry_run_supported", value.dry_run_supported, true);
    try writeJsonField(writer, "reason", value.reason, false);
    try writer.writeByte('}');
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn writeBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
    if (trailing_comma) try writer.writeByte(',');
}

test "classifies live read plans as non-mutating plan-only output" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const policy = routePolicy(route, .read_plan);
    try std.testing.expect(!policy.mutation);
    try std.testing.expect(!policy.live_provider_request);
    try std.testing.expect(!policy.write_enabled);
    try std.testing.expect(policy.write_blocked);
    try std.testing.expect(!policy.dry_run_only);
    try std.testing.expect(policy.live_read_supported);
    try std.testing.expectEqualStrings("plan_only", policy.execution);
    try std.testing.expectEqualStrings("no_live_mutations", policy.write_policy);
}

test "classifies mutation routes as dry-run only and write blocked" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_purchaseNewVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const policy = routePolicy(route, .dry_run_mutation);
    try std.testing.expect(policy.mutation);
    try std.testing.expect(!policy.live_provider_request);
    try std.testing.expect(!policy.write_enabled);
    try std.testing.expect(policy.write_blocked);
    try std.testing.expect(policy.dry_run_only);
    try std.testing.expect(policy.dry_run_supported);
    try std.testing.expectEqualStrings("dry_run_only", policy.execution);
}

test "renders route safety policy as stable json fields" {
    const allocator = std.testing.allocator;
    const route = (try provider_routes.findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRouteSafetyPolicyJson(&out.writer, "safety_policy", route, .dry_run_mutation, false);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"safety_policy\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"execution\":\"dry_run_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"write_policy\":\"no_live_mutations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"live_provider_request\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mutation\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"write_enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"write_blocked\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_only\":true") != null);
}
