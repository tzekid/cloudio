const std = @import("std");
const app_render = @import("app_render");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_manifest_bytes = 8 * 1024 * 1024;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;

pub const L1AuditFailures = struct {
    bad_path_params: usize = 0,
    missing_responses: usize = 0,
    missing_security: usize = 0,
    deprecated_support_mismatch: usize = 0,
    not_applicable_contract_mismatch: usize = 0,
    unexpected_write_mode: usize = 0,
    unsupported_mode: usize = 0,
    read_not_get: usize = 0,
    read_body_required: usize = 0,
    read_auth_unsupported: usize = 0,
    dry_run_method_invalid: usize = 0,
    dry_run_not_supported: usize = 0,
    method_mode_mismatch: usize = 0,
    unroutable_non_deprecated: usize = 0,

    pub fn total(self: L1AuditFailures) usize {
        return self.bad_path_params +
            self.missing_responses +
            self.missing_security +
            self.deprecated_support_mismatch +
            self.not_applicable_contract_mismatch +
            self.unexpected_write_mode +
            self.unsupported_mode +
            self.read_not_get +
            self.read_body_required +
            self.read_auth_unsupported +
            self.dry_run_method_invalid +
            self.dry_run_not_supported +
            self.method_mode_mismatch +
            self.unroutable_non_deprecated;
    }
};

pub const L1ProviderAudit = struct {
    name: []const u8,
    total: usize = 0,
    non_deprecated: usize = 0,
    deprecated: usize = 0,
    not_applicable: usize = 0,
    routable: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    live_read_supported: usize = 0,
    dry_run_supported: usize = 0,
    required_query_routes: usize = 0,
    required_header_routes: usize = 0,
    missing_operation_id: usize = 0,
    deprecated_routable: usize = 0,
    failures: L1AuditFailures = .{},

    pub fn init(provider: provider_routes.Provider) L1ProviderAudit {
        return .{ .name = provider.name() };
    }

    pub fn passed(self: L1ProviderAudit) bool {
        return self.failures.total() == 0;
    }
};

pub const L1Audit = struct {
    cloudflare: L1ProviderAudit,
    hostinger: L1ProviderAudit,

    pub fn init() L1Audit {
        return .{
            .cloudflare = L1ProviderAudit.init(.cloudflare),
            .hostinger = L1ProviderAudit.init(.hostinger),
        };
    }

    pub fn totalFailures(self: L1Audit, filter: ProviderFilter) usize {
        var count: usize = 0;
        if (filter.includesProvider(.cloudflare)) count += self.cloudflare.failures.total();
        if (filter.includesProvider(.hostinger)) count += self.hostinger.failures.total();
        return count;
    }

    pub fn writeText(self: L1Audit, filter: ProviderFilter, writer: anytype) !void {
        try writer.writeAll("Cloudio provider L1 routability audit\n");
        try writer.print("status: {s}\n", .{if (self.totalFailures(filter) == 0) "pass" else "fail"});
        if (filter.includesProvider(.cloudflare)) try writeL1ProviderAudit(self.cloudflare, writer);
        if (filter.includesProvider(.hostinger)) try writeL1ProviderAudit(self.hostinger, writer);
    }

    pub fn writeJson(self: L1Audit, filter: ProviderFilter, writer: anytype) !void {
        const total_failures = self.totalFailures(filter);
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "kind", "coverage_l1_audit", true);
        try app_render.writeJsonStringField(writer, "filter", filter.name(), true);
        try app_render.writeJsonStringField(writer, "status", if (total_failures == 0) "pass" else "fail", true);
        try app_render.writeJsonBoolField(writer, "passed", total_failures == 0, true);
        try app_render.writeJsonIntField(writer, "total_failures", total_failures, true);
        try app_render.writeJsonStringField(writer, "evidence", "generated manifest route contracts checked against Cloudio generic dispatch invariants", true);
        try writer.writeAll("\"providers\":[");
        var wrote_provider = false;
        if (filter.includesProvider(.cloudflare)) {
            try writeL1ProviderAuditJson(self.cloudflare, writer);
            wrote_provider = true;
        }
        if (filter.includesProvider(.hostinger)) {
            if (wrote_provider) try writer.writeByte(',');
            try writeL1ProviderAuditJson(self.hostinger, writer);
        }
        try writer.writeAll("]}");
    }
};

pub fn auditFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !L1Audit {
    var audit_value = L1Audit.init();
    if (filter.includesProvider(.cloudflare)) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try auditProvider(gpa, .cloudflare, text, &audit_value.cloudflare);
    }
    if (filter.includesProvider(.hostinger)) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try auditProvider(gpa, .hostinger, text, &audit_value.hostinger);
    }
    return audit_value;
}

pub fn auditFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !L1Audit {
    var audit_value = L1Audit.init();
    if (filter.includesProvider(.cloudflare)) try auditProvider(gpa, .cloudflare, cloudflare_text, &audit_value.cloudflare);
    if (filter.includesProvider(.hostinger)) try auditProvider(gpa, .hostinger, hostinger_text, &audit_value.hostinger);
    return audit_value;
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const audit_value = try auditFromFiles(io, gpa, paths, filter);
    try audit_value.writeText(filter, writer);
}

pub fn writeJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const audit_value = try auditFromFiles(io, gpa, paths, filter);
    try audit_value.writeJson(filter, writer);
}

pub fn writeTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter, writer: anytype) !void {
    const audit_value = try auditFromText(gpa, cloudflare_text, hostinger_text, filter);
    try audit_value.writeText(filter, writer);
}

pub fn writeJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter, writer: anytype) !void {
    const audit_value = try auditFromText(gpa, cloudflare_text, hostinger_text, filter);
    try audit_value.writeJson(filter, writer);
}

fn auditProvider(gpa: Allocator, provider: provider_routes.Provider, text: []const u8, audit_value: *L1ProviderAudit) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const route = try provider_routes.Route.init(gpa, provider, parsed.value);
        defer route.deinit(gpa);
        try auditRoute(gpa, route, audit_value);
    }
}

fn auditRoute(gpa: Allocator, route: provider_routes.Route, audit_value: *L1ProviderAudit) !void {
    audit_value.total += 1;
    if (route.operation_id == null) audit_value.missing_operation_id += 1;
    if (route.hasRequiredQueryParameters()) audit_value.required_query_routes += 1;
    if (routeHasRequiredHeaderParameters(route)) audit_value.required_header_routes += 1;
    if (route.responses.len == 0) audit_value.failures.missing_responses += 1;
    if (route.security.required and route.security.alternatives.len == 0) audit_value.failures.missing_security += 1;
    if (!try routePathMetadataValid(gpa, route)) audit_value.failures.bad_path_params += 1;

    if (route.deprecated) {
        audit_value.deprecated += 1;
        if (route.support != .deprecated) audit_value.failures.deprecated_support_mismatch += 1;
        if (route.mode != .none or route.isRoutable()) audit_value.deprecated_routable += 1;
        return;
    }

    audit_value.non_deprecated += 1;
    if (route.support == .not_applicable) audit_value.not_applicable += 1;
    if (route.isRoutable()) audit_value.routable += 1;

    if (route.mode == .write) audit_value.failures.unexpected_write_mode += 1;

    switch (route.mode) {
        .read => {
            audit_value.read_routes += 1;
            if (route.method != .GET) audit_value.failures.read_not_get += 1;
            if (route.request_body.required) audit_value.failures.read_body_required += 1;
            if (provider_dispatch.routeLiveCallSupported(route)) {
                audit_value.live_read_supported += 1;
            } else if (!route.request_body.required and route.method == .GET and !provider_dispatch.cloudioSupportsRouteAuth(route)) {
                audit_value.failures.read_auth_unsupported += 1;
            }
        },
        .dry_run => {
            audit_value.dry_run_routes += 1;
            if (route.method == .GET or route.method == .HEAD) audit_value.failures.dry_run_method_invalid += 1;
            if (provider_dispatch.routeDryRunSupported(route)) {
                audit_value.dry_run_supported += 1;
            } else {
                audit_value.failures.dry_run_not_supported += 1;
            }
        },
        .none => {
            if (route.support != .not_applicable) audit_value.failures.unsupported_mode += 1;
        },
        .write => {},
    }

    if (route.support == .not_applicable) {
        if (route.mode != .none or route.isRoutable()) audit_value.failures.not_applicable_contract_mismatch += 1;
    } else if (!route.isRoutable()) {
        audit_value.failures.unroutable_non_deprecated += 1;
    }

    if (route.method == .GET) {
        if (route.request_body.required) {
            if (route.support != .not_applicable or route.mode != .none) audit_value.failures.method_mode_mismatch += 1;
        } else if (route.mode != .read) {
            audit_value.failures.method_mode_mismatch += 1;
        }
    } else if (route.mode != .dry_run) {
        audit_value.failures.method_mode_mismatch += 1;
    }
}

fn routePathMetadataValid(gpa: Allocator, route: provider_routes.Route) !bool {
    const names = route.parameterNames(gpa) catch |err| switch (err) {
        error.InvalidRouteTemplate => return false,
        else => return err,
    };
    defer provider_routes.freeParameterNames(gpa, names);
    for (route.path_params) |param| {
        if (!param.required or !containsOwnedName(names, param.name)) return false;
    }
    for (names) |name| {
        if (!containsRouteParam(route.path_params, name)) return false;
    }
    return true;
}

fn containsOwnedName(names: []const []u8, candidate: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn containsRouteParam(params: []const provider_routes.RouteParam, candidate: []const u8) bool {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, candidate)) return true;
    }
    return false;
}

fn routeHasRequiredHeaderParameters(route: provider_routes.Route) bool {
    for (route.header_params) |param| {
        if (param.required) return true;
    }
    return false;
}

fn writeL1ProviderAudit(audit_value: L1ProviderAudit, writer: anytype) !void {
    try writer.print("\n{s}: {s}\n", .{ audit_value.name, if (audit_value.passed()) "pass" else "fail" });
    try writer.print("  total={d} non_deprecated={d} deprecated={d} not_applicable={d} routable={d}\n", .{
        audit_value.total,
        audit_value.non_deprecated,
        audit_value.deprecated,
        audit_value.not_applicable,
        audit_value.routable,
    });
    try writer.print("  read_routes={d} live_read_supported={d} dry_run_routes={d} dry_run_supported={d}\n", .{
        audit_value.read_routes,
        audit_value.live_read_supported,
        audit_value.dry_run_routes,
        audit_value.dry_run_supported,
    });
    try writer.print("  required_query_routes={d} required_header_routes={d} missing_operation_id={d} deprecated_routable={d}\n", .{
        audit_value.required_query_routes,
        audit_value.required_header_routes,
        audit_value.missing_operation_id,
        audit_value.deprecated_routable,
    });
    try writer.print("  failures={d}", .{audit_value.failures.total()});
    try writeFailureField(writer, "bad_path_params", audit_value.failures.bad_path_params);
    try writeFailureField(writer, "missing_responses", audit_value.failures.missing_responses);
    try writeFailureField(writer, "missing_security", audit_value.failures.missing_security);
    try writeFailureField(writer, "deprecated_support_mismatch", audit_value.failures.deprecated_support_mismatch);
    try writeFailureField(writer, "not_applicable_contract_mismatch", audit_value.failures.not_applicable_contract_mismatch);
    try writeFailureField(writer, "unexpected_write_mode", audit_value.failures.unexpected_write_mode);
    try writeFailureField(writer, "unsupported_mode", audit_value.failures.unsupported_mode);
    try writeFailureField(writer, "read_not_get", audit_value.failures.read_not_get);
    try writeFailureField(writer, "read_body_required", audit_value.failures.read_body_required);
    try writeFailureField(writer, "read_auth_unsupported", audit_value.failures.read_auth_unsupported);
    try writeFailureField(writer, "dry_run_method_invalid", audit_value.failures.dry_run_method_invalid);
    try writeFailureField(writer, "dry_run_not_supported", audit_value.failures.dry_run_not_supported);
    try writeFailureField(writer, "method_mode_mismatch", audit_value.failures.method_mode_mismatch);
    try writeFailureField(writer, "unroutable_non_deprecated", audit_value.failures.unroutable_non_deprecated);
    try writer.writeByte('\n');
}

fn writeL1ProviderAuditJson(audit_value: L1ProviderAudit, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "name", audit_value.name, true);
    try app_render.writeJsonStringField(writer, "status", if (audit_value.passed()) "pass" else "fail", true);
    try app_render.writeJsonBoolField(writer, "passed", audit_value.passed(), true);
    try app_render.writeJsonIntField(writer, "total", audit_value.total, true);
    try app_render.writeJsonIntField(writer, "non_deprecated", audit_value.non_deprecated, true);
    try app_render.writeJsonIntField(writer, "deprecated", audit_value.deprecated, true);
    try app_render.writeJsonIntField(writer, "not_applicable", audit_value.not_applicable, true);
    try app_render.writeJsonIntField(writer, "routable", audit_value.routable, true);
    try app_render.writeJsonIntField(writer, "read_routes", audit_value.read_routes, true);
    try app_render.writeJsonIntField(writer, "live_read_supported", audit_value.live_read_supported, true);
    try app_render.writeJsonIntField(writer, "dry_run_routes", audit_value.dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "dry_run_supported", audit_value.dry_run_supported, true);
    try app_render.writeJsonIntField(writer, "required_query_routes", audit_value.required_query_routes, true);
    try app_render.writeJsonIntField(writer, "required_header_routes", audit_value.required_header_routes, true);
    try app_render.writeJsonIntField(writer, "missing_operation_id", audit_value.missing_operation_id, true);
    try app_render.writeJsonIntField(writer, "deprecated_routable", audit_value.deprecated_routable, true);
    try app_render.writeJsonIntField(writer, "failures_total", audit_value.failures.total(), true);
    try writer.writeAll("\"failures\":");
    try writeL1AuditFailuresJson(audit_value.failures, writer);
    try writer.writeByte('}');
}

fn writeL1AuditFailuresJson(failures: L1AuditFailures, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "bad_path_params", failures.bad_path_params, true);
    try app_render.writeJsonIntField(writer, "missing_responses", failures.missing_responses, true);
    try app_render.writeJsonIntField(writer, "missing_security", failures.missing_security, true);
    try app_render.writeJsonIntField(writer, "deprecated_support_mismatch", failures.deprecated_support_mismatch, true);
    try app_render.writeJsonIntField(writer, "not_applicable_contract_mismatch", failures.not_applicable_contract_mismatch, true);
    try app_render.writeJsonIntField(writer, "unexpected_write_mode", failures.unexpected_write_mode, true);
    try app_render.writeJsonIntField(writer, "unsupported_mode", failures.unsupported_mode, true);
    try app_render.writeJsonIntField(writer, "read_not_get", failures.read_not_get, true);
    try app_render.writeJsonIntField(writer, "read_body_required", failures.read_body_required, true);
    try app_render.writeJsonIntField(writer, "read_auth_unsupported", failures.read_auth_unsupported, true);
    try app_render.writeJsonIntField(writer, "dry_run_method_invalid", failures.dry_run_method_invalid, true);
    try app_render.writeJsonIntField(writer, "dry_run_not_supported", failures.dry_run_not_supported, true);
    try app_render.writeJsonIntField(writer, "method_mode_mismatch", failures.method_mode_mismatch, true);
    try app_render.writeJsonIntField(writer, "unroutable_non_deprecated", failures.unroutable_non_deprecated, false);
    try writer.writeByte('}');
}

fn writeFailureField(writer: anytype, name: []const u8, count: usize) !void {
    if (count == 0) return;
    try writer.print(" {s}={d}", .{ name, count });
}

test "audits L1 routability invariants across provider manifests" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Tokens","method":"GET","path":"/accounts/{account_id}/tokens","operation_id":"account-tokens-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_email","api_key","api_token"]]},"support":"planned","mode":"read","tests":"generated","deprecated":false,"notes":"read"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"account-tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_email","api_key","api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"generated","deprecated":false,"notes":"dry-run"}
        \\{"provider":"cloudflare","tag":"Old","method":"GET","path":"/old","operation_id":"old-route","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":false,"alternatives":[[]]},"support":"deprecated","mode":"none","tests":"generated","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"generated","deprecated":false,"notes":"dry-run"}
        \\{"provider":"hostinger","tag":"Verifications","method":"GET","path":"/api/v2/direct/verifications/active","operation_id":"v2_getDomainVerificationsDIRECT","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"not_applicable","mode":"none","tests":"generated","deprecated":false,"notes":"GET body"}
        \\
    ;

    const audit_value = try auditFromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 0), audit_value.totalFailures(.all));
    try std.testing.expectEqual(@as(usize, 3), audit_value.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 2), audit_value.cloudflare.routable);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.live_read_supported);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.dry_run_supported);
    try std.testing.expectEqual(@as(usize, 1), audit_value.hostinger.not_applicable);
    try std.testing.expectEqual(@as(usize, 1), audit_value.hostinger.dry_run_supported);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try audit_value.writeText(.all, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider L1 routability audit\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "status: pass\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: pass\n") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try audit_value.writeJson(.all, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_l1_audit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"pass\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"passed\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_failures\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"providers\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"live_read_supported\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"unroutable_non_deprecated\":0") != null);
}

test "L1 audit reports broad manifest contract failures" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Broken","method":"GET","path":"/accounts/{account_id}","operation_id":null,"path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[],"security":{"required":true,"alternatives":[]},"support":"planned","mode":"read","tests":"generated","deprecated":false,"notes":"bad"}
        \\
    ;
    const hostinger = "";

    const audit_value = try auditFromText(allocator, cloudflare, hostinger, .cloudflare);
    try std.testing.expect(audit_value.totalFailures(.cloudflare) >= 4);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.missing_operation_id);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.failures.bad_path_params);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.failures.missing_responses);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.failures.missing_security);
    try std.testing.expectEqual(@as(usize, 1), audit_value.cloudflare.failures.read_auth_unsupported);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try audit_value.writeJson(.cloudflare, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"fail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"passed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bad_path_params\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_responses\":1") != null);
}
