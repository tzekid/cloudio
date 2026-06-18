const std = @import("std");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;
const writeShellArg = app_provider_coverage_render.writeShellArg;

pub const Paths = provider_routes.Paths;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const WorkplanFamily = app_provider_coverage_routes.WorkplanFamily;

pub const WorkplanFocus = enum {
    all,
    control_plane,

    pub fn parse(value: []const u8) ?WorkplanFocus {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "control-plane") or std.mem.eql(u8, value, "control_plane")) return .control_plane;
        if (std.mem.eql(u8, value, "cloudio") or std.mem.eql(u8, value, "cloudio-relevant")) return .control_plane;
        return null;
    }

    pub fn name(self: WorkplanFocus) []const u8 {
        return switch (self) {
            .all => "all",
            .control_plane => "control-plane",
        };
    }
};

pub const WorkplanOptions = struct {
    provider: provider_routes.ProviderFilter = .all,
    limit: usize = 10,
    focus: WorkplanFocus = .all,
    family: WorkplanFamily = .all,
    include_plans: bool = false,
    bundle_candidates: bool = false,
    candidate_limit: usize = 25,
};

pub fn loadBundleRoutesFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{
        .provider = options.provider,
        .family = options.family,
    });
}

pub fn loadBundleRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{
        .provider = options.provider,
        .family = options.family,
    });
}

pub fn writeText(gpa: Allocator, rows: anytype, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const active_focus = effectiveFocus(options);
    try writer.writeAll("Cloudio provider coverage workplan\n");
    try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n");
    try writer.writeAll("scope: broad provider tag slices with exact no-execute planning commands\n");
    try writer.print("filter={s} focus={s} family={s}", .{ options.provider.name(), active_focus.name(), options.family.name() });
    if (options.include_plans) try writer.writeAll(" plans=true");
    if (options.bundle_candidates) try writer.writeAll(" bundle_candidates=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_closed: usize = 0;
    var hidden_focus: usize = 0;
    var hidden_family: usize = 0;
    for (rows) |row| {
        const priority = row.priority();
        if (priority == 0) {
            hidden_closed += 1;
            continue;
        }
        if (!focusIncludes(active_focus, row)) {
            hidden_focus += 1;
            continue;
        }
        if (!familyIncludes(options.family, row)) {
            hidden_family += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeTextRow(gpa, row, bundle_routes, options, writer);
    }

    if (visible == 0) {
        try writer.writeAll("no unresolved provider tag slices for filter\n");
    } else {
        if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
        if (hidden_focus != 0) try writer.print("focus_filtered_rows_hidden={d}\n", .{hidden_focus});
        if (hidden_family != 0) try writer.print("family_filtered_rows_hidden={d}\n", .{hidden_family});
        if (hidden_closed != 0) try writer.print("closed_or_evidence_only_rows_hidden={d}\n", .{hidden_closed});
    }
}

pub fn writeJson(gpa: Allocator, rows: anytype, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const active_focus = effectiveFocus(options);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_workplan", true);
    try writeJsonField(writer, "filter", options.provider.name(), true);
    try writeJsonField(writer, "focus", active_focus.name(), true);
    try writeJsonField(writer, "family", options.family.name(), true);
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeJsonBoolField(writer, "bundle_candidates", options.bundle_candidates, true);
    try writeJsonCountField(writer, "candidate_limit", options.candidate_limit, true);
    try writeJsonField(writer, "rank", "pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence", true);
    try writeJsonField(writer, "scope", "broad provider tag slices with exact no-execute planning commands", true);
    try writer.writeAll("\"items\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_closed: usize = 0;
    var hidden_focus: usize = 0;
    var hidden_family: usize = 0;
    var first = true;
    for (rows) |row| {
        const priority = row.priority();
        if (priority == 0) {
            hidden_closed += 1;
            continue;
        }
        if (!focusIncludes(active_focus, row)) {
            hidden_focus += 1;
            continue;
        }
        if (!familyIncludes(options.family, row)) {
            hidden_family += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeRowJson(gpa, row, bundle_routes, options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, true);
    try writeJsonCountField(writer, "focus_filtered_rows_hidden", hidden_focus, true);
    try writeJsonCountField(writer, "family_filtered_rows_hidden", hidden_family, true);
    try writeJsonCountField(writer, "closed_or_evidence_only_rows_hidden", hidden_closed, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

pub fn writeCommandJson(writer: anytype, first: *bool, kind: []const u8, command: []const u8) !void {
    try writeMaybeJsonComma(writer, first);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", kind, true);
    try writeJsonField(writer, "command", command, false);
    try writer.writeByte('}');
}

pub fn routesCommand(gpa: Allocator, row: anytype) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage routes {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --detail");
    return try out.toOwnedSlice();
}

pub fn captureCommand(gpa: Allocator, row: anytype, include_plans: bool) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage capture-candidates {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --limit 25");
    if (include_plans) try out.writer.writeAll(" --plans");
    return try out.toOwnedSlice();
}

pub fn dryRunCommand(gpa: Allocator, row: anytype, include_plans: bool) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage dry-run-candidates {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --limit 25");
    if (include_plans) try out.writer.writeAll(" --plans");
    return try out.toOwnedSlice();
}

pub fn effectiveFocus(options: WorkplanOptions) WorkplanFocus {
    if (options.family != .all) return .control_plane;
    return options.focus;
}

pub fn focusIncludes(focus: WorkplanFocus, row: anytype) bool {
    return switch (focus) {
        .all => true,
        .control_plane => tagIsControlPlane(row.provider, row.tag),
    };
}

pub fn familyIncludes(family: WorkplanFamily, row: anytype) bool {
    if (family == .all) return true;
    return (tagFamily(row.provider, row.tag) orelse return false) == family;
}

pub fn tagIsControlPlane(provider: []const u8, tag: []const u8) bool {
    return app_provider_coverage_routes.tagIsControlPlane(provider, tag);
}

pub fn tagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    return app_provider_coverage_routes.tagFamily(provider, tag);
}

fn writeTextRow(gpa: Allocator, row: anytype, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const evidence = row.evidence;
    const family = tagFamily(row.provider, row.tag);
    try writer.print("{s} | {s}: priority={d} pending_reads={d} diagnostic_blocked_reads={d} pending_mutation_dry_runs={d} L2_read_evidence={d} dry_run_evidence={d} generated_dry_run_policy_evidence={d} L3_generic={d} typed={d} family={s}\n", .{
        row.provider,
        row.tag,
        row.priority(),
        evidence.pending_reads,
        evidence.l2_diagnostic_reads,
        evidence.pending_mutation_dry_runs,
        evidence.l2_read_evidence,
        evidence.dry_run_evidence,
        evidence.generated_dry_run_policy_evidence,
        evidence.l3_generic_inventory_candidates,
        evidence.l3_typed_table_evidence,
        if (family) |value| value.name() else "-",
    });
    const routes = try routesCommand(gpa, row);
    defer gpa.free(routes);
    try writer.print("  routes: {s}\n", .{routes});
    if (needsCapture(row)) {
        const capture = try captureCommand(gpa, row, options.include_plans);
        defer gpa.free(capture);
        try writer.print("  capture-candidates: {s}\n", .{capture});
    }
    if (needsDryRun(row)) {
        const dry_run = try dryRunCommand(gpa, row, options.include_plans);
        defer gpa.free(dry_run);
        try writer.print("  dry-run-candidates: {s}\n", .{dry_run});
    }
    if (options.bundle_candidates) {
        const counts = candidateBundleCounts(row, bundle_routes orelse &.{}, options);
        try writer.writeAll("  candidate-bundle: candidate_limit=");
        if (options.candidate_limit == 0) {
            try writer.writeAll("all");
        } else {
            try writer.print("{d}", .{options.candidate_limit});
        }
        try writer.print(" capture_visible={d} capture_omitted={d} dry_run_visible={d} dry_run_omitted={d}\n", .{
            counts.capture.visible,
            counts.capture.omitted,
            counts.dry_run.visible,
            counts.dry_run.omitted,
        });
    }
}

fn writeRowJson(gpa: Allocator, row: anytype, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const family = tagFamily(row.provider, row.tag);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (family) |value| value.name() else null, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writer.writeAll("\"evidence\":");
    try writeEvidenceJson(row.evidence, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"commands\":[");
    var first = true;
    const routes = try routesCommand(gpa, row);
    defer gpa.free(routes);
    try writeCommandJson(writer, &first, "routes_detail", routes);
    if (needsCapture(row)) {
        const capture = try captureCommand(gpa, row, options.include_plans);
        defer gpa.free(capture);
        try writeCommandJson(writer, &first, "capture_candidates", capture);
    }
    if (needsDryRun(row)) {
        const dry_run = try dryRunCommand(gpa, row, options.include_plans);
        defer gpa.free(dry_run);
        try writeCommandJson(writer, &first, "dry_run_candidates", dry_run);
    }
    try writer.writeByte(']');
    if (options.bundle_candidates) {
        try writer.writeByte(',');
        try writeCandidateBundleJson(gpa, row, bundle_routes orelse &.{}, options, writer);
    }
    try writer.writeByte('}');
}

const CandidateKind = enum {
    capture,
    dry_run,
};

const CandidateSetCounts = struct {
    total: usize = 0,
    visible: usize = 0,
    omitted: usize = 0,
};

const CandidateBundleCounts = struct {
    capture: CandidateSetCounts = .{},
    dry_run: CandidateSetCounts = .{},
};

fn writeCandidateBundleJson(gpa: Allocator, row: anytype, routes: []const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    try writer.writeAll("\"candidate_bundle\":{");
    try writeJsonCountField(writer, "candidate_limit", options.candidate_limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeCandidateSetJson(gpa, row, routes, options, .capture, writer);
    try writer.writeByte(',');
    try writeCandidateSetJson(gpa, row, routes, options, .dry_run, writer);
    try writer.writeByte('}');
}

fn writeCandidateSetJson(gpa: Allocator, row: anytype, routes: []const CoverageRoute, options: WorkplanOptions, kind: CandidateKind, writer: anytype) !void {
    const counts = candidateSetCounts(row, routes, options, kind);
    try core_json.writeString(writer, switch (kind) {
        .capture => "capture",
        .dry_run => "dry_run",
    });
    try writer.writeAll(":{");
    try writeJsonCountField(writer, "total", counts.total, true);
    try writeJsonCountField(writer, "visible", counts.visible, true);
    try writeJsonCountField(writer, "omitted", counts.omitted, true);
    try writer.writeAll("\"candidates\":[");
    var first = true;
    var visible: usize = 0;
    for (routes) |route_row| {
        if (!routeMatchesRow(route_row, row)) continue;
        if (!routeIsCandidate(route_row, options, kind)) continue;
        if (options.candidate_limit != 0 and visible >= options.candidate_limit) continue;
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        switch (kind) {
            .capture => try app_provider_coverage_candidates.writeCaptureCandidateJson(gpa, route_row, .{
                .filter = .{},
                .limit = options.candidate_limit,
                .include_plans = options.include_plans,
            }, writer),
            .dry_run => try app_provider_coverage_candidates.writeDryRunCandidateJson(gpa, route_row, .{
                .filter = .{},
                .limit = options.candidate_limit,
                .include_plans = options.include_plans,
            }, writer),
        }
    }
    try writer.writeAll("]}");
}

fn candidateBundleCounts(row: anytype, routes: []const CoverageRoute, options: WorkplanOptions) CandidateBundleCounts {
    return .{
        .capture = candidateSetCounts(row, routes, options, .capture),
        .dry_run = candidateSetCounts(row, routes, options, .dry_run),
    };
}

fn candidateSetCounts(row: anytype, routes: []const CoverageRoute, options: WorkplanOptions, kind: CandidateKind) CandidateSetCounts {
    var counts = CandidateSetCounts{};
    for (routes) |route_row| {
        if (!routeMatchesRow(route_row, row)) continue;
        if (!routeIsCandidate(route_row, options, kind)) continue;
        counts.total += 1;
        if (options.candidate_limit == 0 or counts.visible < options.candidate_limit) {
            counts.visible += 1;
        } else {
            counts.omitted += 1;
        }
    }
    return counts;
}

fn routeIsCandidate(route_row: CoverageRoute, options: WorkplanOptions, kind: CandidateKind) bool {
    return switch (kind) {
        .capture => app_provider_coverage_candidates.isCaptureCandidate(route_row, .{
            .filter = .{},
            .limit = options.candidate_limit,
            .include_plans = options.include_plans,
        }),
        .dry_run => app_provider_coverage_candidates.isDryRunCandidate(route_row, .{
            .filter = .{},
            .limit = options.candidate_limit,
            .include_plans = options.include_plans,
        }),
    };
}

fn routeMatchesRow(route_row: CoverageRoute, row: anytype) bool {
    return std.mem.eql(u8, route_row.route.provider.name(), row.provider) and
        std.mem.eql(u8, route_row.route.tag, row.tag);
}

fn needsCapture(row: anytype) bool {
    return row.evidence.pending_reads != 0;
}

fn needsDryRun(row: anytype) bool {
    return row.evidence.pending_mutation_dry_runs != 0;
}

fn writeEvidenceJson(evidence: anytype, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "name", evidence.name, true);
    try writeJsonCountField(writer, "total", evidence.total, true);
    try writeJsonCountField(writer, "deprecated", evidence.deprecated, true);
    try writeJsonCountField(writer, "not_applicable", evidence.not_applicable, true);
    try writeJsonCountField(writer, "non_deprecated", evidence.non_deprecated, true);
    try writeJsonCountField(writer, "routable", evidence.routable, true);
    try writeJsonCountField(writer, "read_routes", evidence.read_routes, true);
    try writeJsonCountField(writer, "dry_run_routes", evidence.dry_run_routes, true);
    try writeJsonCountField(writer, "l2_read_evidence", evidence.l2_read_evidence, true);
    try writeJsonCountField(writer, "l2_partial_reads", evidence.l2_partial_reads, true);
    try writeJsonCountField(writer, "l2_diagnostic_reads", evidence.l2_diagnostic_reads, true);
    try writeJsonCountField(writer, "pending_reads", evidence.pending_reads, true);
    try writeJsonCountField(writer, "read_missing_tests", evidence.read_missing_tests, true);
    try writeJsonCountField(writer, "dry_run_evidence", evidence.dry_run_evidence, true);
    try writeJsonCountField(writer, "generated_dry_run_policy_evidence", evidence.generated_dry_run_policy_evidence, true);
    try writeJsonCountField(writer, "pending_mutation_dry_runs", evidence.pending_mutation_dry_runs, true);
    try writeJsonCountField(writer, "l3_generic_inventory_candidates", evidence.l3_generic_inventory_candidates, true);
    try writeJsonCountField(writer, "l3_typed_table_evidence", evidence.l3_typed_table_evidence, false);
    try writer.writeByte('}');
}

const TestEvidence = struct {
    name: []const u8,
    total: usize = 0,
    deprecated: usize = 0,
    not_applicable: usize = 0,
    non_deprecated: usize = 0,
    routable: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    l2_read_evidence: usize = 0,
    l2_partial_reads: usize = 0,
    l2_diagnostic_reads: usize = 0,
    pending_reads: usize = 0,
    read_missing_tests: usize = 0,
    dry_run_evidence: usize = 0,
    generated_dry_run_policy_evidence: usize = 0,
    pending_mutation_dry_runs: usize = 0,
    l3_generic_inventory_candidates: usize = 0,
    l3_typed_table_evidence: usize = 0,
};

const TestRow = struct {
    provider: []const u8,
    tag: []const u8,
    evidence: TestEvidence,

    fn priority(self: TestRow) usize {
        return self.evidence.pending_reads + self.evidence.pending_mutation_dry_runs;
    }
};

test "renders coverage workplan rows and commands" {
    const allocator = std.testing.allocator;
    const rows = [_]TestRow{
        .{
            .provider = "cloudflare",
            .tag = "DNS Records",
            .evidence = .{
                .name = "DNS Records",
                .total = 2,
                .non_deprecated = 2,
                .routable = 2,
                .read_routes = 1,
                .pending_reads = 1,
                .pending_mutation_dry_runs = 1,
                .l3_generic_inventory_candidates = 1,
            },
        },
        .{
            .provider = "cloudflare",
            .tag = "Workers",
            .evidence = .{ .name = "Workers", .total = 1 },
        },
    };

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeText(allocator, rows[0..], null, .{ .provider = .cloudflare, .limit = 5 }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage workplan\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio coverage routes cloudflare 'DNS Records' --detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "capture-candidates: cloudio coverage capture-candidates cloudflare 'DNS Records' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dry-run-candidates: cloudio coverage dry-run-candidates cloudflare 'DNS Records' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeJson(allocator, rows[0..], null, .{ .provider = .cloudflare, .limit = 5, .include_plans = true }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_workplan\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"capture_candidates\",\"command\":\"cloudio coverage capture-candidates cloudflare 'DNS Records' --limit 25 --plans\"") != null);
}

test "classifies provider workplan families through route metadata" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .dns), tagFamily("cloudflare", "DNS Records"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .hostinger_vps), tagFamily("hostinger", "VPS: Virtual machine"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), tagFamily("cloudflare", "R2 Catalog Management"));
    try std.testing.expect(tagIsControlPlane("cloudflare", "Access Applications"));
    try std.testing.expect(!tagIsControlPlane("cloudflare", "R2 Catalog Management"));
}
