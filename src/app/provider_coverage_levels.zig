const std = @import("std");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const containsIgnoreCase = app_provider_coverage_render.containsIgnoreCase;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;

pub const LevelProviderEvidence = struct {
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

    pub fn init(name: []const u8) LevelProviderEvidence {
        return .{ .name = name };
    }
};

pub const LevelTagOptions = struct {
    provider: ProviderFilter = .all,
    limit: usize = 25,
};

pub const LevelTagEvidence = struct {
    provider: []const u8,
    tag: []u8,
    evidence: LevelProviderEvidence,

    pub fn init(gpa: Allocator, provider: []const u8, tag: []const u8) !LevelTagEvidence {
        const tag_owned = try gpa.dupe(u8, tag);
        return .{
            .provider = provider,
            .tag = tag_owned,
            .evidence = LevelProviderEvidence.init(tag_owned),
        };
    }

    pub fn deinit(self: LevelTagEvidence, gpa: Allocator) void {
        gpa.free(self.tag);
    }

    pub fn priority(self: LevelTagEvidence) usize {
        return self.evidence.pending_reads +
            self.evidence.pending_mutation_dry_runs;
    }

    pub fn evidenceScore(self: LevelTagEvidence) usize {
        return self.evidence.l2_read_evidence +
            self.evidence.dry_run_evidence +
            self.evidence.l3_generic_inventory_candidates +
            self.evidence.l3_typed_table_evidence;
    }
};

pub const LevelTagReport = struct {
    items: []LevelTagEvidence,

    pub fn deinit(self: *LevelTagReport, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: LevelTagReport, writer: anytype, options: LevelTagOptions) !void {
        try writer.writeAll("Cloudio provider coverage levels by tag\n");
        try writer.writeAll("evidence: generated manifest + Cloudio support overlay, not final completion proof\n");
        try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n");
        try writer.print("filter={s} limit=", .{options.provider.name()});
        if (options.limit == 0) {
            try writer.writeAll("all\n");
        } else {
            try writer.print("{d}\n", .{options.limit});
        }

        var visible: usize = 0;
        var omitted: usize = 0;
        var hidden_closed: usize = 0;
        for (self.items) |row| {
            const priority = row.priority();
            if (options.limit != 0 and priority == 0) {
                hidden_closed += 1;
                continue;
            }
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writeLevelTagRow(row, writer);
        }

        if (visible == 0) {
            try writer.writeAll("no level tag rows for filter\n");
        } else {
            if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
            if (hidden_closed != 0) try writer.print("closed_or_evidence_only_rows_hidden={d}\n", .{hidden_closed});
        }
    }

    pub fn writeJson(self: LevelTagReport, writer: anytype, options: LevelTagOptions) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_level_tags", true);
        try writeJsonField(writer, "filter", options.provider.name(), true);
        try writeJsonCountField(writer, "limit", options.limit, true);
        try writeJsonField(writer, "evidence", "generated manifest + Cloudio support overlay, not final completion proof", true);
        try writeJsonField(writer, "rank", "pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence", true);
        try writer.writeAll("\"items\":[");

        var visible: usize = 0;
        var omitted: usize = 0;
        var hidden_closed: usize = 0;
        var first = true;
        for (self.items) |row| {
            const priority = row.priority();
            if (options.limit != 0 and priority == 0) {
                hidden_closed += 1;
                continue;
            }
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            try writeMaybeJsonComma(writer, &first);
            visible += 1;
            try writeLevelTagJson(row, writer);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "omitted", omitted, true);
        try writeJsonCountField(writer, "closed_or_evidence_only_rows_hidden", hidden_closed, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }
};

pub const LevelReport = struct {
    cloudflare: LevelProviderEvidence,
    hostinger: LevelProviderEvidence,

    pub fn init() LevelReport {
        return .{
            .cloudflare = LevelProviderEvidence.init("cloudflare"),
            .hostinger = LevelProviderEvidence.init("hostinger"),
        };
    }

    pub fn writeText(self: LevelReport, filter: ProviderFilter, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage levels\n");
        try writer.writeAll("evidence: generated manifest + Cloudio support overlay, not final completion proof\n");
        if (filter.includes("cloudflare")) try writeLevelProviderEvidence(self.cloudflare, writer);
        if (filter.includes("hostinger")) try writeLevelProviderEvidence(self.hostinger, writer);
    }

    pub fn writeJson(self: LevelReport, filter: ProviderFilter, writer: anytype) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_levels", true);
        try writeJsonField(writer, "filter", filter.name(), true);
        try writeJsonField(writer, "evidence", "generated manifest + Cloudio support overlay, not final completion proof", true);
        try writer.writeAll("\"providers\":[");
        var first = true;
        if (filter.includes("cloudflare")) {
            try writeMaybeJsonComma(writer, &first);
            try writeLevelProviderEvidenceJson(self.cloudflare, writer);
        }
        if (filter.includes("hostinger")) {
            try writeMaybeJsonComma(writer, &first);
            try writeLevelProviderEvidenceJson(self.hostinger, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub fn loadLevels(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !LevelReport {
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{ .provider = filter });
    defer routes.deinit(gpa);
    return buildLevelReport(routes.items);
}

pub fn loadLevelsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelReport {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{ .provider = filter });
    defer routes.deinit(gpa);
    return buildLevelReport(routes.items);
}

pub fn writeLevelsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const report = try loadLevels(io, gpa, paths, filter);
    try report.writeText(filter, writer);
}

pub fn writeLevelsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const report = try loadLevels(io, gpa, paths, filter);
    try report.writeJson(filter, writer);
}

pub fn loadLevelTags(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !LevelTagReport {
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildLevelTagReport(gpa, routes.items);
}

pub fn loadLevelTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelTagReport {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildLevelTagReport(gpa, routes.items);
}

pub fn writeLevelTagsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: LevelTagOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try report.writeText(writer, options);
}

pub fn writeLevelTagsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: LevelTagOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try report.writeJson(writer, options);
}

pub fn buildLevelReport(routes: []const CoverageRoute) LevelReport {
    var report = LevelReport.init();
    for (routes) |row| {
        const provider = row.route.provider.name();
        if (std.mem.eql(u8, provider, "cloudflare")) {
            updateLevelEvidence(&report.cloudflare, row);
        } else if (std.mem.eql(u8, provider, "hostinger")) {
            updateLevelEvidence(&report.hostinger, row);
        }
    }
    return report;
}

pub fn buildLevelTagReport(gpa: Allocator, routes: []const CoverageRoute) !LevelTagReport {
    var rows = std.ArrayList(LevelTagEvidence).empty;
    errdefer deinitLevelTagList(&rows, gpa);

    for (routes) |coverage_row| {
        const row = try levelTagRow(gpa, &rows, coverage_row.route.provider.name(), coverage_row.route.tag);
        updateLevelEvidence(&row.evidence, coverage_row);
    }

    std.mem.sort(LevelTagEvidence, rows.items, {}, levelTagLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn levelTagRow(gpa: Allocator, rows: *std.ArrayList(LevelTagEvidence), provider: []const u8, tag: []const u8) !*LevelTagEvidence {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.tag, tag)) return row;
    }
    const row = try LevelTagEvidence.init(gpa, provider, tag);
    errdefer row.deinit(gpa);
    try rows.append(gpa, row);
    return &rows.items[rows.items.len - 1];
}

fn deinitLevelTagList(rows: *std.ArrayList(LevelTagEvidence), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn writeLevelProviderEvidence(evidence: LevelProviderEvidence, writer: anytype) !void {
    try writer.print("\n{s}\n", .{evidence.name});
    try writer.print("  L0 classified={d} non_deprecated={d} deprecated={d} not_applicable={d}\n", .{
        evidence.total,
        evidence.non_deprecated,
        evidence.deprecated,
        evidence.not_applicable,
    });
    try writer.print("  L1 routable={d} read_routes={d} dry_run_routes={d}\n", .{
        evidence.routable,
        evidence.read_routes,
        evidence.dry_run_routes,
    });
    try writer.print("  L2 read_evidence={d} partial_reads={d} diagnostic_blocked_reads={d} pending_reads={d} read_missing_tests={d}\n", .{
        evidence.l2_read_evidence,
        evidence.l2_partial_reads,
        evidence.l2_diagnostic_reads,
        evidence.pending_reads,
        evidence.read_missing_tests,
    });
    try writer.print("  dry_run evidence={d} generated_policy={d} pending_mutation_dry_runs={d}\n", .{
        evidence.dry_run_evidence,
        evidence.generated_dry_run_policy_evidence,
        evidence.pending_mutation_dry_runs,
    });
    try writer.print("  L3 evidence generic_inventory_candidates={d} typed_table_evidence={d}\n", .{
        evidence.l3_generic_inventory_candidates,
        evidence.l3_typed_table_evidence,
    });
}

fn writeLevelTagRow(row: LevelTagEvidence, writer: anytype) !void {
    const evidence = row.evidence;
    try writer.print("{s} | {s}: priority={d} L0={d} non_deprecated={d} deprecated={d} not_applicable={d} L1_routable={d} read={d} dry_run={d}", .{
        row.provider,
        row.tag,
        row.priority(),
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
}

fn writeLevelTagJson(row: LevelTagEvidence, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writer.writeAll("\"evidence\":");
    try writeLevelProviderEvidenceJson(row.evidence, writer);
    try writer.writeByte('}');
}

fn writeLevelProviderEvidenceJson(evidence: LevelProviderEvidence, writer: anytype) !void {
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

fn levelTagLessThan(_: void, lhs: LevelTagEvidence, rhs: LevelTagEvidence) bool {
    const lhs_priority = lhs.priority();
    const rhs_priority = rhs.priority();
    if (lhs_priority != rhs_priority) return lhs_priority > rhs_priority;
    if (lhs.evidence.pending_reads != rhs.evidence.pending_reads) return lhs.evidence.pending_reads > rhs.evidence.pending_reads;
    if (lhs.evidence.pending_mutation_dry_runs != rhs.evidence.pending_mutation_dry_runs) return lhs.evidence.pending_mutation_dry_runs > rhs.evidence.pending_mutation_dry_runs;
    if (lhs.evidence.l2_diagnostic_reads != rhs.evidence.l2_diagnostic_reads) return lhs.evidence.l2_diagnostic_reads > rhs.evidence.l2_diagnostic_reads;
    const lhs_evidence = lhs.evidenceScore();
    const rhs_evidence = rhs.evidenceScore();
    if (lhs_evidence != rhs_evidence) return lhs_evidence > rhs_evidence;
    if (lhs.evidence.non_deprecated != rhs.evidence.non_deprecated) return lhs.evidence.non_deprecated > rhs.evidence.non_deprecated;
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, lhs.tag, rhs.tag) == .lt;
}

fn updateLevelEvidence(evidence: *LevelProviderEvidence, row: CoverageRoute) void {
    evidence.total += 1;
    if (row.route.deprecated) {
        evidence.deprecated += 1;
        return;
    }
    evidence.non_deprecated += 1;
    if (row.route.support == .not_applicable) {
        evidence.not_applicable += 1;
        return;
    }
    if (row.route.isRoutable()) evidence.routable += 1;

    switch (row.route.mode) {
        .read => updateReadLevelEvidence(evidence, row),
        .dry_run => updateDryRunLevelEvidence(evidence, row),
        .write, .none => {},
    }
}

fn updateReadLevelEvidence(evidence: *LevelProviderEvidence, row: CoverageRoute) void {
    evidence.read_routes += 1;
    const has_evidence = hasCoverageEvidence(row.tests);
    if (!has_evidence) evidence.read_missing_tests += 1;

    switch (row.route.support) {
        .partial => {
            evidence.l2_partial_reads += 1;
            if (has_evidence) {
                evidence.l2_read_evidence += 1;
                evidence.l3_generic_inventory_candidates += 1;
                if (isTypedTableCoverageCandidate(row.route.provider.name(), row.route.tag)) evidence.l3_typed_table_evidence += 1;
            }
        },
        .blocked_permission => {
            if (has_evidence) {
                evidence.l2_read_evidence += 1;
                evidence.l2_diagnostic_reads += 1;
            }
        },
        .planned => evidence.pending_reads += 1,
        .implemented, .unsafe_mutation, .deprecated, .not_applicable => {},
    }
}

fn updateDryRunLevelEvidence(evidence: *LevelProviderEvidence, row: CoverageRoute) void {
    evidence.dry_run_routes += 1;
    switch (row.route.support) {
        .partial => {
            if (hasCoverageEvidence(row.tests)) evidence.dry_run_evidence += 1;
        },
        .unsafe_mutation => {
            if (app_provider_coverage_candidates.hasGeneratedDryRunPolicyEvidence(row)) {
                evidence.dry_run_evidence += 1;
                evidence.generated_dry_run_policy_evidence += 1;
            } else {
                evidence.pending_mutation_dry_runs += 1;
            }
        },
        .implemented, .planned, .blocked_permission, .deprecated, .not_applicable => {},
    }
}

fn hasCoverageEvidence(tests: []const u8) bool {
    return tests.len != 0 and !std.mem.eql(u8, tests, "missing");
}

fn isTypedTableCoverageCandidate(provider: []const u8, tag: []const u8) bool {
    if (std.mem.eql(u8, provider, "hostinger")) {
        return isHostingerTypedInventoryTag(tag);
    }
    if (std.mem.eql(u8, provider, "cloudflare")) {
        return std.mem.eql(u8, tag, "Accounts") or
            std.mem.eql(u8, tag, "Zone") or
            std.mem.eql(u8, tag, "DNS Records for a Zone") or
            isCloudflareSecurityTypedTableTag(tag) or
            isCloudflareTypedInventoryTag(tag);
    }
    return false;
}

fn tagContainsAny(tag: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (containsIgnoreCase(tag, needle)) return true;
    }
    return false;
}

fn isHostingerTypedInventoryTag(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "Billing:",
        "DNS:",
        "Domains:",
        "Hosting:",
        "Ecommerce:",
        "Horizons:",
        "VPS:",
        "Docker",
        "Monarx",
        "Malware",
    });
}

fn isCloudflareSecurityTypedTableTag(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "Email Security",
        "Security Center",
        "Leaked Credential",
        "Page Shield",
        "Bot",
        "Botnet",
        "DNS Firewall",
        "IP Access",
        "WAF",
        "Firewall",
        "API Gateway",
        "Schema Validation",
        "Token Validation",
        "Vulnerability Scanner",
        "AI Security",
        "security.txt",
    });
}

fn isCloudflareTypedInventoryTag(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "Tunnel",
        "Account",
        "User",
        "Rules",
        "Ruleset",
        "Rules List",
        "API Shield",
        "Access",
        "Zero Trust",
        "DNS",
        "Log",
        "Zone",
        "Zone Settings",
        "Zone Cache Settings",
        "Cache",
        "Argo",
        "Smart Routing",
        "Tiered Caching",
        "Smart Shield",
        "Content Scanning",
        "CSAM Scanner",
        "CT Alerting",
        "Cloudflare IPs",
        "Fraud Detection",
        "Load Balancer",
        "Health Checks",
        "Resource Tagging",
        "API Tokens",
        "Token",
        "Membership",
        "IAM",
        "Custom Pages",
        "Email Auth",
        "Email Routing",
        "Email Sending",
        "Authenticated Origin Pull",
        "Certificate",
        "Origin CA",
        "Origin Post-Quantum",
        "Custom Origin Trust Store",
        "SSL",
        "TLS",
        "Organization",
        "Invite",
        "Subscription",
        "Worker Account Settings",
        "R2",
        "AI Gateway",
        "SCIM",
        "Magic",
    });
}

test "summarizes provider coverage levels from route manifests" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    const levels = try loadLevelsFromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 3), levels.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.read_routes);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.l2_read_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.pending_reads);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.dry_run_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), levels.cloudflare.pending_mutation_dry_runs);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.l3_typed_table_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.l2_diagnostic_reads);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.dry_run_evidence);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try levels.writeJson(.all, &out.writer);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_levels\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"l2_diagnostic_reads\":1") != null);
}

test "ranks provider coverage level tag rows" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    var report = try loadLevelTagsFromText(allocator, cloudflare, hostinger, .all);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.items.len);
    try std.testing.expectEqualStrings("cloudflare", report.items[0].provider);
    try std.testing.expectEqualStrings("Workers", report.items[0].tag);
    try std.testing.expectEqual(@as(usize, 1), report.items[0].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[0].evidence.pending_reads);
    try std.testing.expectEqual(@as(usize, 1), report.items[0].evidence.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), report.items[0].evidence.pending_mutation_dry_runs);
    try std.testing.expectEqualStrings("hostinger", report.items[1].provider);
    try std.testing.expectEqualStrings("VPS: Docker Manager", report.items[1].tag);
    try std.testing.expectEqual(@as(usize, 0), report.items[1].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[1].evidence.l2_diagnostic_reads);
    try std.testing.expectEqual(@as(usize, 1), report.items[1].evidence.dry_run_evidence);
    try std.testing.expectEqualStrings("Accounts", report.items[2].tag);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer, .{ .provider = .all, .limit = 1 });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage levels by tag\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Workers: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=2") != null);
}
