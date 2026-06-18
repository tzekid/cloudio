const std = @import("std");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const app_provider_coverage_workplan = @import("app_provider_coverage_workplan");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

pub const WorkplanFocus = app_provider_coverage_workplan.WorkplanFocus;
pub const WorkplanFamily = app_provider_coverage_workplan.WorkplanFamily;
pub const Paths = provider_routes.Paths;
pub const CoverageRoute = app_provider_coverage_workplan.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_workplan.CoverageRoutes;

pub const FamilyOptions = struct {
    provider: provider_routes.ProviderFilter = .all,
    limit: usize = 25,
    focus: WorkplanFocus = .control_plane,
    include_plans: bool = false,
    bundle_candidates: bool = false,
    candidate_limit: usize = 25,
};

pub const ProviderEvidence = struct {
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

    pub fn init(name: []const u8) ProviderEvidence {
        return .{ .name = name };
    }
};

pub const FamilyEvidence = struct {
    provider: []const u8,
    family: WorkplanFamily,
    tag_count: usize = 0,
    evidence: ProviderEvidence,

    pub fn init(provider: []const u8, family: WorkplanFamily) FamilyEvidence {
        return .{
            .provider = provider,
            .family = family,
            .evidence = ProviderEvidence.init(family.name()),
        };
    }

    pub fn priority(self: FamilyEvidence) usize {
        return self.evidence.pending_reads +
            self.evidence.pending_mutation_dry_runs;
    }

    pub fn evidenceScore(self: FamilyEvidence) usize {
        return self.evidence.l2_read_evidence +
            self.evidence.dry_run_evidence +
            self.evidence.l3_generic_inventory_candidates +
            self.evidence.l3_typed_table_evidence;
    }
};

pub const FamilyReport = struct {
    items: []FamilyEvidence,

    pub fn deinit(self: *FamilyReport, gpa: Allocator) void {
        gpa.free(self.items);
    }

    pub fn writeText(self: FamilyReport, gpa: Allocator, writer: anytype, bundle_routes: ?[]const CoverageRoute, options: FamilyOptions) !void {
        try writer.writeAll("Cloudio provider coverage families\n");
        try writer.writeAll("evidence: generated manifest + Cloudio support overlay, not final completion proof\n");
        try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n");
        try writer.writeAll("scope: control-plane provider families for broad implementation slices\n");
        try writer.print("filter={s} focus={s}", .{ options.provider.name(), options.focus.name() });
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
        for (self.items) |row| {
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writeFamilyRowText(gpa, row, writer, bundle_routes, options);
        }

        if (visible == 0) {
            try writer.writeAll("no provider families for filter\n");
        } else if (omitted != 0) {
            try writer.print("omitted={d}\n", .{omitted});
        }
    }

    pub fn writeJson(self: FamilyReport, gpa: Allocator, writer: anytype, bundle_routes: ?[]const CoverageRoute, options: FamilyOptions) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_families", true);
        try writeJsonField(writer, "filter", options.provider.name(), true);
        try writeJsonField(writer, "focus", options.focus.name(), true);
        try writeJsonCountField(writer, "limit", options.limit, true);
        try app_provider_coverage_render.writeJsonBoolField(writer, "include_plans", options.include_plans, true);
        try app_provider_coverage_render.writeJsonBoolField(writer, "bundle_candidates", options.bundle_candidates, true);
        try writeJsonCountField(writer, "candidate_limit", options.candidate_limit, true);
        try writeJsonField(writer, "evidence", "generated manifest + Cloudio support overlay, not final completion proof", true);
        try writeJsonField(writer, "rank", "pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence", true);
        try writeJsonField(writer, "scope", "control-plane provider families for broad implementation slices", true);
        try writer.writeAll("\"items\":[");

        var visible: usize = 0;
        var omitted: usize = 0;
        var first = true;
        for (self.items) |row| {
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            try writeMaybeJsonComma(writer, &first);
            visible += 1;
            try writeFamilyRowJson(gpa, row, writer, bundle_routes, options);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "visible", visible, true);
        try writeJsonCountField(writer, "omitted", omitted, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }
};

pub fn loadBundleRoutesFromFiles(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{
        .provider = options.provider,
    });
}

pub fn loadBundleRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{
        .provider = options.provider,
    });
}

pub fn buildReport(gpa: Allocator, rows: anytype, options: FamilyOptions) !FamilyReport {
    validateRowsSlice(@TypeOf(rows));

    var families = std.ArrayList(FamilyEvidence).empty;
    errdefer families.deinit(gpa);

    for (rows) |row| {
        if (!options.provider.includes(row.provider)) continue;
        if (!app_provider_coverage_workplan.focusIncludes(options.focus, row)) continue;
        const family = app_provider_coverage_workplan.tagFamily(row.provider, row.tag) orelse continue;
        const family_row = try familyEvidenceRow(gpa, &families, row.provider, family);
        family_row.tag_count += 1;
        addProviderEvidence(&family_row.evidence, row.evidence);
    }

    sortFamilies(families.items);
    return .{ .items = try families.toOwnedSlice(gpa) };
}

fn validateRowsSlice(comptime Rows: type) void {
    const pointer = switch (@typeInfo(Rows)) {
        .pointer => |value| value,
        else => @compileError("family coverage rows must be a slice"),
    };
    if (pointer.size != .slice) @compileError("family coverage rows must be a slice");
}

fn familyEvidenceRow(gpa: Allocator, rows: *std.ArrayList(FamilyEvidence), provider: []const u8, family: WorkplanFamily) !*FamilyEvidence {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and row.family == family) return row;
    }
    try rows.append(gpa, FamilyEvidence.init(provider, family));
    return &rows.items[rows.items.len - 1];
}

fn addProviderEvidence(dest: *ProviderEvidence, src: anytype) void {
    dest.total += src.total;
    dest.deprecated += src.deprecated;
    dest.not_applicable += src.not_applicable;
    dest.non_deprecated += src.non_deprecated;
    dest.routable += src.routable;
    dest.read_routes += src.read_routes;
    dest.dry_run_routes += src.dry_run_routes;
    dest.l2_read_evidence += src.l2_read_evidence;
    dest.l2_partial_reads += src.l2_partial_reads;
    dest.l2_diagnostic_reads += src.l2_diagnostic_reads;
    dest.pending_reads += src.pending_reads;
    dest.read_missing_tests += src.read_missing_tests;
    dest.dry_run_evidence += src.dry_run_evidence;
    dest.generated_dry_run_policy_evidence += src.generated_dry_run_policy_evidence;
    dest.pending_mutation_dry_runs += src.pending_mutation_dry_runs;
    dest.l3_generic_inventory_candidates += src.l3_generic_inventory_candidates;
    dest.l3_typed_table_evidence += src.l3_typed_table_evidence;
}

fn sortFamilies(rows: []FamilyEvidence) void {
    var index: usize = 1;
    while (index < rows.len) : (index += 1) {
        var cursor = index;
        while (cursor > 0 and familyLessThan(rows[cursor], rows[cursor - 1])) : (cursor -= 1) {
            const tmp = rows[cursor - 1];
            rows[cursor - 1] = rows[cursor];
            rows[cursor] = tmp;
        }
    }
}

fn familyLessThan(lhs: FamilyEvidence, rhs: FamilyEvidence) bool {
    const lhs_priority = lhs.priority();
    const rhs_priority = rhs.priority();
    if (lhs_priority != rhs_priority) return lhs_priority > rhs_priority;
    if (lhs.evidence.pending_reads != rhs.evidence.pending_reads) return lhs.evidence.pending_reads > rhs.evidence.pending_reads;
    if (lhs.evidence.pending_mutation_dry_runs != rhs.evidence.pending_mutation_dry_runs) return lhs.evidence.pending_mutation_dry_runs > rhs.evidence.pending_mutation_dry_runs;
    if (lhs.evidence.l2_diagnostic_reads != rhs.evidence.l2_diagnostic_reads) return lhs.evidence.l2_diagnostic_reads > rhs.evidence.l2_diagnostic_reads;
    const lhs_evidence = lhs.evidenceScore();
    const rhs_evidence = rhs.evidenceScore();
    if (lhs_evidence != rhs_evidence) return lhs_evidence > rhs_evidence;
    if (lhs.tag_count != rhs.tag_count) return lhs.tag_count > rhs.tag_count;
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, lhs.family.name(), rhs.family.name()) == .lt;
}

fn writeFamilyRowText(gpa: Allocator, row: FamilyEvidence, writer: anytype, bundle_routes: ?[]const CoverageRoute, options: FamilyOptions) !void {
    const evidence = row.evidence;
    try writer.print("{s} | {s}: priority={d} tags={d} L0={d} non_deprecated={d} deprecated={d} not_applicable={d} L1_routable={d} read={d} dry_run={d}", .{
        row.provider,
        row.family.name(),
        row.priority(),
        row.tag_count,
        evidence.total,
        evidence.non_deprecated,
        evidence.deprecated,
        evidence.not_applicable,
        evidence.routable,
        evidence.read_routes,
        evidence.dry_run_routes,
    });
    try writer.print(" L2_read_evidence={d} partial_reads={d} diagnostic_blocked_reads={d} pending_reads={d} read_missing_tests={d}", .{
        evidence.l2_read_evidence,
        evidence.l2_partial_reads,
        evidence.l2_diagnostic_reads,
        evidence.pending_reads,
        evidence.read_missing_tests,
    });
    try writer.print(" dry_run_evidence={d} generated_dry_run_policy_evidence={d} pending_mutation_dry_runs={d}", .{
        evidence.dry_run_evidence,
        evidence.generated_dry_run_policy_evidence,
        evidence.pending_mutation_dry_runs,
    });
    try writer.print(" L3_generic={d} typed={d}\n", .{
        evidence.l3_generic_inventory_candidates,
        evidence.l3_typed_table_evidence,
    });
    const readiness = familyReadiness(row);
    try writer.print("  readiness: l1={s} l2={s} l3={s} dry_run={s} next={s}\n", .{
        readiness.l1,
        readiness.l2,
        readiness.l3,
        readiness.dry_run,
        readiness.next_action,
    });
    const workplan = try familyCommand(gpa, row, .workplan, options);
    defer gpa.free(workplan);
    try writer.print("  workplan: {s}\n", .{workplan});
    if (needsCapture(row)) {
        const capture = try familyCommand(gpa, row, .capture_candidates, options);
        defer gpa.free(capture);
        try writer.print("  capture-candidates: {s}\n", .{capture});
        const actual = try familyCommand(gpa, row, .actual_captures, options);
        defer gpa.free(actual);
        try writer.print("  actual-captures: {s}\n", .{actual});
    }
    if (needsDryRun(row)) {
        const dry_run = try familyCommand(gpa, row, .dry_run_candidates, options);
        defer gpa.free(dry_run);
        try writer.print("  dry-run-candidates: {s}\n", .{dry_run});
    }
    if (needsTypedModelReview(row)) {
        const typed = try familyCommand(gpa, row, .typed_models, options);
        defer gpa.free(typed);
        try writer.print("  typed-models: {s}\n", .{typed});
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

fn writeFamilyRowJson(gpa: Allocator, row: FamilyEvidence, writer: anytype, bundle_routes: ?[]const CoverageRoute, options: FamilyOptions) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "family", row.family.name(), true);
    try writeJsonCountField(writer, "tag_count", row.tag_count, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writer.writeAll("\"evidence\":");
    try writeProviderEvidenceJson(row.evidence, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"readiness\":");
    try writeFamilyReadinessJson(row, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"commands\":[{\"kind\":\"workplan\",\"command\":\"cloudio coverage workplan ");
    try writer.writeAll(row.provider);
    try writer.writeAll(" --family ");
    try writer.writeAll(row.family.name());
    try writer.writeAll(" --limit 25\"}]");
    try writer.writeByte(',');
    try writer.writeAll("\"slice_commands\":[");
    try writeSliceCommandsJson(gpa, row, options, writer);
    try writer.writeByte(']');
    if (options.bundle_candidates) {
        try writer.writeByte(',');
        try writeCandidateBundleJson(gpa, row, bundle_routes orelse &.{}, options, writer);
    }
    try writer.writeByte('}');
}

const FamilyReadiness = struct {
    l1: []const u8,
    l2: []const u8,
    l3: []const u8,
    dry_run: []const u8,
    next_action: []const u8,
};

fn familyReadiness(row: FamilyEvidence) FamilyReadiness {
    const evidence = row.evidence;
    return .{
        .l1 = familyL1Status(evidence),
        .l2 = familyL2Status(evidence),
        .l3 = familyL3Status(evidence),
        .dry_run = familyDryRunStatus(evidence),
        .next_action = familyNextAction(evidence),
    };
}

fn familyL1Status(evidence: ProviderEvidence) []const u8 {
    if (evidence.non_deprecated == 0) return "not_applicable";
    if (evidence.routable + evidence.not_applicable >= evidence.non_deprecated) return "complete";
    if (evidence.routable != 0) return "partial";
    return "pending";
}

fn familyL2Status(evidence: ProviderEvidence) []const u8 {
    if (evidence.read_routes == 0) return "not_applicable";
    if (evidence.pending_reads == 0) return "complete";
    if (evidence.l2_read_evidence != 0 or evidence.l2_partial_reads != 0 or evidence.l2_diagnostic_reads != 0) return "partial";
    return "pending";
}

fn familyL3Status(evidence: ProviderEvidence) []const u8 {
    if (evidence.read_routes == 0) return "not_applicable";
    if (evidence.l3_typed_table_evidence != 0) return "typed";
    if (evidence.l3_generic_inventory_candidates != 0) return "generic";
    return "pending";
}

fn familyDryRunStatus(evidence: ProviderEvidence) []const u8 {
    if (evidence.dry_run_routes == 0) return "not_applicable";
    if (evidence.pending_mutation_dry_runs == 0) return "complete";
    if (evidence.dry_run_evidence != 0 or evidence.generated_dry_run_policy_evidence != 0) return "partial";
    return "pending";
}

fn familyNextAction(evidence: ProviderEvidence) []const u8 {
    if (evidence.pending_reads != 0 and evidence.pending_mutation_dry_runs != 0) return "capture_reads_and_review_dry_runs";
    if (evidence.pending_reads != 0) return "capture_reads";
    if (evidence.pending_mutation_dry_runs != 0) return "review_dry_runs";
    if (evidence.l3_generic_inventory_candidates != 0 and evidence.l3_typed_table_evidence == 0) return "promote_generic_inventory_to_typed_models";
    return "review_evidence";
}

fn writeFamilyReadinessJson(row: FamilyEvidence, writer: anytype) !void {
    const readiness = familyReadiness(row);
    try writer.writeByte('{');
    try writeJsonField(writer, "l1", readiness.l1, true);
    try writeJsonField(writer, "l2", readiness.l2, true);
    try writeJsonField(writer, "l3", readiness.l3, true);
    try writeJsonField(writer, "dry_run", readiness.dry_run, true);
    try writeJsonField(writer, "next_action", readiness.next_action, false);
    try writer.writeByte('}');
}

const SliceCommandKind = enum {
    routes_detail,
    workplan,
    capture_candidates,
    actual_captures,
    dry_run_candidates,
    typed_models,
};

fn writeSliceCommandsJson(gpa: Allocator, row: FamilyEvidence, options: FamilyOptions, writer: anytype) !void {
    var first = true;
    try writeSliceCommandJson(gpa, row, .routes_detail, options, writer, &first);
    try writeSliceCommandJson(gpa, row, .workplan, options, writer, &first);
    if (needsCapture(row)) {
        try writeSliceCommandJson(gpa, row, .capture_candidates, options, writer, &first);
        try writeSliceCommandJson(gpa, row, .actual_captures, options, writer, &first);
    }
    if (needsDryRun(row)) try writeSliceCommandJson(gpa, row, .dry_run_candidates, options, writer, &first);
    if (needsTypedModelReview(row)) try writeSliceCommandJson(gpa, row, .typed_models, options, writer, &first);
}

fn writeSliceCommandJson(gpa: Allocator, row: FamilyEvidence, kind: SliceCommandKind, options: FamilyOptions, writer: anytype, first: *bool) !void {
    const command = try familyCommand(gpa, row, kind, options);
    defer gpa.free(command);
    try writeMaybeJsonComma(writer, first);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", sliceCommandKindName(kind), true);
    try writeJsonField(writer, "command", command, false);
    try writer.writeByte('}');
}

fn familyCommand(gpa: Allocator, row: FamilyEvidence, kind: SliceCommandKind, options: FamilyOptions) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    switch (kind) {
        .routes_detail => try writer.print("cloudio coverage routes {s} --family {s} --detail", .{ row.provider, row.family.name() }),
        .workplan => {
            try writer.print("cloudio coverage workplan {s} --family {s} --limit 0", .{ row.provider, row.family.name() });
            if (options.bundle_candidates) try writer.writeAll(" --bundle");
            if (options.include_plans) try writer.writeAll(" --plans");
            if (options.candidate_limit != 25) try writer.print(" --candidate-limit {d}", .{options.candidate_limit});
        },
        .capture_candidates => {
            try writer.print("cloudio coverage capture-candidates {s} --family {s} --limit ", .{ row.provider, row.family.name() });
            try writeLimit(writer, options.candidate_limit);
            if (options.include_plans) try writer.writeAll(" --plans");
        },
        .actual_captures => {
            try writer.print("cloudio coverage actual-captures {s} --family {s} --limit ", .{ row.provider, row.family.name() });
            try writeLimit(writer, options.candidate_limit);
            if (options.include_plans) try writer.writeAll(" --plans");
        },
        .dry_run_candidates => {
            try writer.print("cloudio coverage dry-run-candidates {s} --family {s} --limit ", .{ row.provider, row.family.name() });
            try writeLimit(writer, options.candidate_limit);
            if (options.include_plans) try writer.writeAll(" --plans");
        },
        .typed_models => {
            try writer.print("cloudio coverage typed-models {s} --family {s} --limit ", .{ row.provider, row.family.name() });
            try writeLimit(writer, options.candidate_limit);
        },
    }
    return try out.toOwnedSlice();
}

fn writeLimit(writer: anytype, limit: usize) !void {
    if (limit == 0) {
        try writer.writeAll("0");
    } else {
        try writer.print("{d}", .{limit});
    }
}

fn sliceCommandKindName(kind: SliceCommandKind) []const u8 {
    return switch (kind) {
        .routes_detail => "routes_detail",
        .workplan => "workplan",
        .capture_candidates => "capture_candidates",
        .actual_captures => "actual_captures",
        .dry_run_candidates => "dry_run_candidates",
        .typed_models => "typed_models",
    };
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

fn writeCandidateBundleJson(gpa: Allocator, row: FamilyEvidence, routes: []const CoverageRoute, options: FamilyOptions, writer: anytype) !void {
    try writer.writeAll("\"candidate_bundle\":{");
    try writeJsonCountField(writer, "candidate_limit", options.candidate_limit, true);
    try app_provider_coverage_render.writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeCandidateSetJson(gpa, row, routes, options, .capture, writer);
    try writer.writeByte(',');
    try writeCandidateSetJson(gpa, row, routes, options, .dry_run, writer);
    try writer.writeByte('}');
}

fn writeCandidateSetJson(gpa: Allocator, row: FamilyEvidence, routes: []const CoverageRoute, options: FamilyOptions, kind: CandidateKind, writer: anytype) !void {
    const counts = candidateSetCounts(row, routes, options, kind);
    try writer.writeByte('"');
    try writer.writeAll(candidateKindName(kind));
    try writer.writeAll("\":{");
    try writeJsonCountField(writer, "total", counts.total, true);
    try writeJsonCountField(writer, "visible", counts.visible, true);
    try writeJsonCountField(writer, "omitted", counts.omitted, true);
    try writer.writeAll("\"candidates\":[");
    var first = true;
    var visible: usize = 0;
    for (routes) |route_row| {
        if (!routeMatchesFamily(route_row, row)) continue;
        if (!routeIsCandidate(route_row, options, kind)) continue;
        if (options.candidate_limit != 0 and visible >= options.candidate_limit) continue;
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        switch (kind) {
            .capture => try app_provider_coverage_candidates.writeCaptureCandidateJson(gpa, route_row, captureCandidateOptions(options), writer),
            .dry_run => try app_provider_coverage_candidates.writeDryRunCandidateJson(gpa, route_row, dryRunCandidateOptions(options), writer),
        }
    }
    try writer.writeAll("]}");
}

fn candidateBundleCounts(row: FamilyEvidence, routes: []const CoverageRoute, options: FamilyOptions) CandidateBundleCounts {
    return .{
        .capture = candidateSetCounts(row, routes, options, .capture),
        .dry_run = candidateSetCounts(row, routes, options, .dry_run),
    };
}

fn candidateSetCounts(row: FamilyEvidence, routes: []const CoverageRoute, options: FamilyOptions, kind: CandidateKind) CandidateSetCounts {
    var counts = CandidateSetCounts{};
    for (routes) |route_row| {
        if (!routeMatchesFamily(route_row, row)) continue;
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

fn routeMatchesFamily(route_row: CoverageRoute, row: FamilyEvidence) bool {
    if (!std.mem.eql(u8, route_row.route.provider.name(), row.provider)) return false;
    return (app_provider_coverage_workplan.tagFamily(row.provider, route_row.route.tag) orelse return false) == row.family;
}

fn routeIsCandidate(route_row: CoverageRoute, options: FamilyOptions, kind: CandidateKind) bool {
    return switch (kind) {
        .capture => app_provider_coverage_candidates.isCaptureCandidate(route_row, captureCandidateOptions(options)),
        .dry_run => app_provider_coverage_candidates.isDryRunCandidate(route_row, dryRunCandidateOptions(options)),
    };
}

fn captureCandidateOptions(options: FamilyOptions) app_provider_coverage_candidates.CaptureCandidateOptions {
    return .{
        .filter = .{},
        .limit = options.candidate_limit,
        .include_plans = options.include_plans,
    };
}

fn dryRunCandidateOptions(options: FamilyOptions) app_provider_coverage_candidates.DryRunCandidateOptions {
    return .{
        .filter = .{},
        .limit = options.candidate_limit,
        .include_plans = options.include_plans,
    };
}

fn candidateKindName(kind: CandidateKind) []const u8 {
    return switch (kind) {
        .capture => "capture",
        .dry_run => "dry_run",
    };
}

fn needsCapture(row: FamilyEvidence) bool {
    return row.evidence.pending_reads != 0;
}

fn needsDryRun(row: FamilyEvidence) bool {
    return row.evidence.pending_mutation_dry_runs != 0;
}

fn needsTypedModelReview(row: FamilyEvidence) bool {
    return row.evidence.l3_generic_inventory_candidates != 0 or row.evidence.l2_read_evidence != 0;
}

fn writeProviderEvidenceJson(evidence: ProviderEvidence, writer: anytype) !void {
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

test "builds and renders provider family coverage rollups" {
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
                .dry_run_routes = 1,
                .l2_read_evidence = 1,
                .pending_reads = 1,
                .read_missing_tests = 1,
                .dry_run_evidence = 1,
                .generated_dry_run_policy_evidence = 1,
                .l3_generic_inventory_candidates = 1,
                .l3_typed_table_evidence = 1,
            },
        },
        .{
            .provider = "hostinger",
            .tag = "VPS: Virtual machine",
            .evidence = .{
                .name = "VPS: Virtual machine",
                .total = 1,
                .non_deprecated = 1,
                .routable = 1,
                .read_routes = 1,
                .l2_diagnostic_reads = 1,
                .l3_generic_inventory_candidates = 1,
                .l3_typed_table_evidence = 1,
            },
        },
        .{
            .provider = "cloudflare",
            .tag = "Catalog Sync",
            .evidence = .{
                .name = "Catalog Sync",
                .total = 1,
                .non_deprecated = 1,
                .routable = 1,
                .read_routes = 1,
                .l2_read_evidence = 1,
            },
        },
        .{
            .provider = "cloudflare",
            .tag = "Workers",
            .evidence = .{
                .name = "Workers",
                .total = 1,
                .non_deprecated = 1,
                .routable = 1,
                .pending_reads = 1,
            },
        },
    };

    const slice: []const TestRow = rows[0..];
    var report = try buildReport(allocator, slice, .{ .provider = .all, .limit = 0 });
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), report.items.len);
    try std.testing.expectEqualStrings("cloudflare", report.items[0].provider);
    try std.testing.expectEqual(WorkplanFamily.dns, report.items[0].family);
    try std.testing.expectEqual(@as(usize, 1), report.items[0].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[0].tag_count);
    try std.testing.expectEqualStrings("hostinger", report.items[1].provider);
    try std.testing.expectEqual(WorkplanFamily.hostinger_vps, report.items[1].family);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try report.writeText(allocator, &text_out.writer, null, .{ .provider = .all, .limit = 0 });
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | dns: priority=1 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "readiness: l1=complete l2=partial l3=typed dry_run=complete next=capture_reads") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workplan: cloudio coverage workplan cloudflare --family dns --limit 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "capture-candidates: cloudio coverage capture-candidates cloudflare --family dns --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "typed-models: cloudio coverage typed-models cloudflare --family dns --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Catalog") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(allocator, &json_out.writer, null, .{ .provider = .all, .limit = 1 });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed_json.deinit();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_families\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"readiness\":{\"l1\":\"complete\",\"l2\":\"partial\",\"l3\":\"typed\",\"dry_run\":\"complete\",\"next_action\":\"capture_reads\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage workplan cloudflare --family dns --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"slice_commands\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage routes cloudflare --family dns --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visible\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":1") != null);
}

test "renders bundled family capture and dry-run candidates" {
    const allocator = std.testing.allocator;
    const rows = [_]TestRow{
        .{
            .provider = "hostinger",
            .tag = "VPS: Virtual machine",
            .evidence = .{
                .name = "VPS: Virtual machine",
                .total = 2,
                .non_deprecated = 2,
                .routable = 2,
                .read_routes = 1,
                .dry_run_routes = 1,
                .pending_reads = 1,
                .pending_mutation_dry_runs = 1,
            },
        },
    };
    const slice: []const TestRow = rows[0..];
    var report = try buildReport(allocator, slice, .{ .provider = .hostinger, .limit = 0 });
    defer report.deinit(allocator);

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VpsPurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending mutation review"}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"different family"}
        \\
    ;
    var bundle_routes = (try loadBundleRoutesFromText(allocator, "", hostinger, .{
        .provider = .hostinger,
        .limit = 0,
        .include_plans = true,
        .bundle_candidates = true,
        .candidate_limit = 1,
    })).?;
    defer bundle_routes.deinit(allocator);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(allocator, &json_out.writer, bundle_routes.items, .{
        .provider = .hostinger,
        .limit = 0,
        .include_plans = true,
        .bundle_candidates = true,
        .candidate_limit = 1,
    });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed_json.deinit();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"bundle_candidates\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_bundle\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"capture\":{\"total\":1,\"visible\":1,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run\":{\"total\":1,\"visible\":1,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachinesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"read_plan\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_plan\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"safety_policy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "billing_getCatalogItemListV1") == null);
}
