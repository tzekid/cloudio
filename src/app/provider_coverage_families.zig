const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_workplan = @import("app_provider_coverage_workplan");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

pub const WorkplanFocus = app_provider_coverage_workplan.WorkplanFocus;
pub const WorkplanFamily = app_provider_coverage_workplan.WorkplanFamily;

pub const FamilyOptions = struct {
    provider: provider_routes.ProviderFilter = .all,
    limit: usize = 25,
    focus: WorkplanFocus = .control_plane,
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

    pub fn writeText(self: FamilyReport, writer: anytype, options: FamilyOptions) !void {
        try writer.writeAll("Cloudio provider coverage families\n");
        try writer.writeAll("evidence: generated manifest + Cloudio support overlay, not final completion proof\n");
        try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n");
        try writer.writeAll("scope: control-plane provider families for broad implementation slices\n");
        try writer.print("filter={s} focus={s} limit=", .{ options.provider.name(), options.focus.name() });
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
            try writeFamilyRowText(row, writer);
        }

        if (visible == 0) {
            try writer.writeAll("no provider families for filter\n");
        } else if (omitted != 0) {
            try writer.print("omitted={d}\n", .{omitted});
        }
    }

    pub fn writeJson(self: FamilyReport, writer: anytype, options: FamilyOptions) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_families", true);
        try writeJsonField(writer, "filter", options.provider.name(), true);
        try writeJsonField(writer, "focus", options.focus.name(), true);
        try writeJsonCountField(writer, "limit", options.limit, true);
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
            try writeFamilyRowJson(row, writer);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "visible", visible, true);
        try writeJsonCountField(writer, "omitted", omitted, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }
};

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

fn writeFamilyRowText(row: FamilyEvidence, writer: anytype) !void {
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
    try writer.print("  workplan: cloudio coverage workplan {s} --family {s} --limit 25\n", .{ row.provider, row.family.name() });
}

fn writeFamilyRowJson(row: FamilyEvidence, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "family", row.family.name(), true);
    try writeJsonCountField(writer, "tag_count", row.tag_count, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writer.writeAll("\"evidence\":");
    try writeProviderEvidenceJson(row.evidence, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"commands\":[{\"kind\":\"workplan\",\"command\":\"cloudio coverage workplan ");
    try writer.writeAll(row.provider);
    try writer.writeAll(" --family ");
    try writer.writeAll(row.family.name());
    try writer.writeAll(" --limit 25\"}]}");
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
    try report.writeText(&text_out.writer, .{ .provider = .all, .limit = 0 });
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | dns: priority=1 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workplan: cloudio coverage workplan cloudflare --family dns --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Catalog") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(&json_out.writer, .{ .provider = .all, .limit = 1 });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_families\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage workplan cloudflare --family dns --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visible\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":1") != null);
}
