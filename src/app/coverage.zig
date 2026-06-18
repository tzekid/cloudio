const std = @import("std");
const app_provider_l1 = @import("app_provider_l1");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const app_provider_route_capture = @import("app_provider_route_capture");
const app_provider_route_plan = @import("app_provider_route_plan");
const core_json = @import("core_json");
const core_time = @import("core_time");
const db_store = @import("db_store");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const max_manifest_bytes = 8 * 1024 * 1024;
const default_capture_max_pages = 25;
const actual_capture_load_limit: i64 = 100_000;
const actual_capture_cloudflare_scope_hint_limit: i64 = 200;
const actual_capture_cloudflare_resource_hint_limit: i64 = 5000;
const actual_capture_hostinger_vps_hint_limit: i64 = 50;
const actual_capture_hostinger_hint_limit: i64 = 5000;
const actual_capture_source_evidence_limit: i64 = 5000;

pub const support_names = [_][]const u8{
    "implemented",
    "partial",
    "planned",
    "blocked_permission",
    "unsafe_mutation",
    "deprecated",
    "not_applicable",
};

pub const mode_names = [_][]const u8{
    "read",
    "dry_run",
    "write",
    "none",
};

pub const PathParam = provider_routes.PathParam;
pub const QueryParam = provider_routes.QueryParam;
pub const HeaderParam = provider_routes.HeaderParam;
pub const Request = provider_routes.Request;
pub const BodyInput = provider_routes.BodyInput;
pub const Auth = provider_dispatch.Auth;
pub const CaptureOptions = app_provider_route_capture.CaptureOptions;
pub const DbHandle = Db;

pub const Paths = provider_routes.Paths;

pub const ProviderFilter = provider_routes.ProviderFilter;
pub const L1AuditFailures = app_provider_l1.L1AuditFailures;
pub const L1ProviderAudit = app_provider_l1.L1ProviderAudit;
pub const L1Audit = app_provider_l1.L1Audit;

pub const SupportFilter = app_provider_coverage_routes.SupportFilter;
pub const ModeFilter = app_provider_coverage_routes.ModeFilter;

pub const ProviderSummary = struct {
    name: []const u8,
    total: usize,
    deprecated: usize,
    support_counts: [support_names.len]usize,
    mode_counts: [mode_names.len]usize,

    pub fn init(name: []const u8) ProviderSummary {
        return .{
            .name = name,
            .total = 0,
            .deprecated = 0,
            .support_counts = [_]usize{0} ** support_names.len,
            .mode_counts = [_]usize{0} ** mode_names.len,
        };
    }
};

pub const TagSummary = struct {
    provider: []const u8,
    tag: []u8,
    total: usize,
    deprecated: usize,
    support_counts: [support_names.len]usize,
    mode_counts: [mode_names.len]usize,

    pub fn init(gpa: Allocator, provider: []const u8, tag: []const u8) !TagSummary {
        return .{
            .provider = provider,
            .tag = try gpa.dupe(u8, tag),
            .total = 0,
            .deprecated = 0,
            .support_counts = [_]usize{0} ** support_names.len,
            .mode_counts = [_]usize{0} ** mode_names.len,
        };
    }

    pub fn deinit(self: TagSummary, gpa: Allocator) void {
        gpa.free(self.tag);
    }
};

pub const TagSummaries = struct {
    items: []TagSummary,

    pub fn deinit(self: *TagSummaries, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: TagSummaries, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage by tag\n");
        var current_provider: ?[]const u8 = null;
        for (self.items) |row| {
            if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.provider)) {
                current_provider = row.provider;
                try writer.print("\n{s}\n", .{row.provider});
            }
            try writer.print("  {s}: total={d}", .{ row.tag, row.total });
            try writer.writeAll(" support:");
            for (support_names, 0..) |name, index| {
                const count = row.support_counts[index];
                if (count != 0) try writer.print(" {s}={d}", .{ name, count });
            }
            try writer.writeAll(" mode:");
            for (mode_names, 0..) |name, index| {
                const count = row.mode_counts[index];
                if (count != 0) try writer.print(" {s}={d}", .{ name, count });
            }
            if (row.deprecated != 0) try writer.print(" deprecated_flags={d}", .{row.deprecated});
            try writer.writeByte('\n');
        }
    }

    pub fn writeJson(self: TagSummaries, writer: anytype, filter: ProviderFilter) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_tags", true);
        try writeJsonField(writer, "filter", filter.name(), true);
        try writeJsonCountField(writer, "count", self.items.len, true);
        try writer.writeAll("\"tags\":[");
        var first = true;
        for (self.items) |row| {
            try writeMaybeJsonComma(writer, &first);
            try writeTagSummaryJson(row, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub const GapOptions = struct {
    provider: ProviderFilter = .all,
    limit: usize = 25,
};

pub const GapSummary = struct {
    provider: []const u8,
    tag: []u8,
    total: usize = 0,
    non_deprecated: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    partial_read: usize = 0,
    partial_dry_run: usize = 0,
    planned_read: usize = 0,
    blocked_read: usize = 0,
    unsafe_dry_run: usize = 0,
    pending_reads: usize = 0,
    diagnostic_blocked_reads: usize = 0,
    dry_run_evidence: usize = 0,
    generated_dry_run_policy_evidence: usize = 0,
    pending_mutation_dry_runs: usize = 0,
    routable: usize = 0,
    not_applicable: usize = 0,
    deprecated: usize = 0,

    pub fn init(gpa: Allocator, provider: []const u8, tag: []const u8) !GapSummary {
        return .{
            .provider = provider,
            .tag = try gpa.dupe(u8, tag),
        };
    }

    pub fn deinit(self: GapSummary, gpa: Allocator) void {
        gpa.free(self.tag);
    }

    pub fn priority(self: GapSummary) usize {
        return self.pending_reads + self.pending_mutation_dry_runs;
    }
};

pub const GapReport = struct {
    items: []GapSummary,

    pub fn deinit(self: *GapReport, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: GapReport, writer: anytype, options: GapOptions) !void {
        try writer.writeAll("Cloudio provider coverage gaps\n");
        try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads and generated dry-run policy are evidence\n");
        try writer.print("filter={s} limit=", .{options.provider.name()});
        if (options.limit == 0) {
            try writer.writeAll("all\n");
        } else {
            try writer.print("{d}\n", .{options.limit});
        }

        var visible: usize = 0;
        var omitted: usize = 0;
        for (self.items) |row| {
            const priority = row.priority();
            if (priority == 0) continue;
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writer.print("{s} | {s}: priority={d} total={d} non_deprecated={d} routable={d} read={d} dry_run={d}", .{
                row.provider,
                row.tag,
                priority,
                row.total,
                row.non_deprecated,
                row.routable,
                row.read_routes,
                row.dry_run_routes,
            });
            try writeGapField(writer, "pending_reads", row.pending_reads);
            try writeGapField(writer, "pending_mutation_dry_runs", row.pending_mutation_dry_runs);
            try writeGapField(writer, "diagnostic_blocked_reads", row.diagnostic_blocked_reads);
            try writeGapField(writer, "dry_run_evidence", row.dry_run_evidence);
            try writeGapField(writer, "generated_dry_run_policy_evidence", row.generated_dry_run_policy_evidence);
            try writeGapField(writer, "planned_read", row.planned_read);
            try writeGapField(writer, "blocked_read", row.blocked_read);
            try writeGapField(writer, "partial_read", row.partial_read);
            try writeGapField(writer, "partial_dry_run", row.partial_dry_run);
            try writeGapField(writer, "unsafe_dry_run", row.unsafe_dry_run);
            try writeGapField(writer, "not_applicable", row.not_applicable);
            try writeGapField(writer, "deprecated", row.deprecated);
            try writer.writeByte('\n');
        }

        if (visible == 0) {
            try writer.writeAll("no ranked gaps for filter\n");
        } else if (omitted != 0) {
            try writer.print("omitted={d}\n", .{omitted});
        }
    }

    pub fn writeJson(self: GapReport, writer: anytype, options: GapOptions) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_gaps", true);
        try writeJsonField(writer, "filter", options.provider.name(), true);
        try writeJsonCountField(writer, "limit", options.limit, true);
        try writeJsonField(writer, "rank", "pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads and generated dry-run policy are evidence", true);
        try writer.writeAll("\"items\":[");

        var visible: usize = 0;
        var omitted: usize = 0;
        var first = true;
        for (self.items) |row| {
            if (row.priority() == 0) continue;
            if (options.limit != 0 and visible >= options.limit) {
                omitted += 1;
                continue;
            }
            if (!first) try writer.writeByte(',');
            first = false;
            visible += 1;
            try writeGapJson(row, writer);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "omitted", omitted, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }
};

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

pub const FamilyOptions = struct {
    provider: ProviderFilter = .all,
    limit: usize = 25,
    focus: WorkplanFocus = .control_plane,
};

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

pub const WorkplanFamily = app_provider_coverage_routes.WorkplanFamily;

pub const WorkplanOptions = struct {
    provider: ProviderFilter = .all,
    limit: usize = 10,
    focus: WorkplanFocus = .all,
    family: WorkplanFamily = .all,
    include_plans: bool = false,
    bundle_candidates: bool = false,
    candidate_limit: usize = 25,
};

pub const TypedModelOptions = struct {
    provider: ProviderFilter = .all,
    family: WorkplanFamily = .all,
    limit: usize = 25,
    include_complete: bool = false,
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

pub const FamilyEvidence = struct {
    provider: []const u8,
    family: WorkplanFamily,
    tag_count: usize = 0,
    evidence: LevelProviderEvidence,

    pub fn init(provider: []const u8, family: WorkplanFamily) FamilyEvidence {
        return .{
            .provider = provider,
            .family = family,
            .evidence = LevelProviderEvidence.init(family.name()),
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
            if (!first) try writer.writeByte(',');
            first = false;
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

pub const RouteFilter = app_provider_coverage_routes.RouteFilter;

pub const CaptureCandidateOptions = app_provider_coverage_candidates.CaptureCandidateOptions;

pub const ActualCaptureOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
    configured_domains: []const []const u8 = &.{},
};

pub const ActualReadyCaptureOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    max_pages: usize = default_capture_max_pages,
    execute: bool = false,
    include_blocked: bool = false,
    diagnostic_only: bool = false,
    configured_domains: []const []const u8 = &.{},
};

pub const DryRunCandidateOptions = app_provider_coverage_candidates.DryRunCandidateOptions;

pub const RoutePlanInput = app_provider_coverage_routes.RoutePlanInput;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;
pub const parseRouteMethod = app_provider_coverage_routes.parseRouteMethod;
pub const parsePathParamAssignment = app_provider_coverage_routes.parsePathParamAssignment;
pub const parseQueryParamAssignment = app_provider_coverage_routes.parseQueryParamAssignment;
pub const parseHeaderParamAssignment = app_provider_coverage_routes.parseHeaderParamAssignment;

const ActualRouteStatus = struct {
    any: bool = false,
    ok: bool = false,
    err: bool = false,
    events: i64 = 0,
    latest_at: []const u8 = "",
};

const ActualCaptureState = enum {
    ok,
    missing,
    non_ok,

    fn name(self: ActualCaptureState) []const u8 {
        return switch (self) {
            .ok => "ok",
            .missing => "missing",
            .non_ok => "non_ok",
        };
    }
};

const ActualCaptureTotals = struct {
    official_read_routes: usize = 0,
    ok_read_routes: usize = 0,
    non_ok_read_routes: usize = 0,
    missing_read_routes: usize = 0,
    candidate_routes: usize = 0,
    ready_candidates: usize = 0,
    capture_events: i64 = 0,
};

const ActualCaptureSourceSummary = struct {
    total_sources: usize = 0,
    captured_with_hints: usize = 0,
    captured_empty: usize = 0,
    captured_without_hints: usize = 0,
    captured_unknown_body: usize = 0,
    ready_to_capture: usize = 0,
    waiting_for_inputs: usize = 0,
    diagnostic_blocked: usize = 0,
    captured_error: usize = 0,
    no_official_source: usize = 0,
    not_in_catalog: usize = 0,
    unmapped: usize = 0,
    not_eligible: usize = 0,
    body_array: usize = 0,
    body_data_array: usize = 0,
    body_error_object: usize = 0,
    body_no_evidence: usize = 0,
    body_other: usize = 0,
};

const ActualCaptureHints = struct {
    configured_domains: []const []const u8 = &.{},
    cloudflare_accounts: []const db_store.CloudflareAccountRow = &.{},
    cloudflare_zones: []const db_store.CloudflareZoneRow = &.{},
    cloudflare_resources: []const db_store.CloudflareResourceHintRow = &.{},
    cloudflare_inventory: []const db_store.CloudflareInventoryHintRow = &.{},
    hostinger_vps: []const db_store.HostingerVpsRow = &.{},
    hostinger_resources: []const db_store.HostingerResourceHintRow = &.{},
    hostinger_inventory: []const db_store.HostingerInventoryHintRow = &.{},
};

const ActualCaptureInputSource = struct {
    operation_id: []const u8,
    hint_kind: []const u8,
    purpose: []const u8,
};

const ActualCaptureSourceBodyEvidence = struct {
    shape: []const u8 = "no_evidence",
    item_count: ?usize = null,
    body_bytes: usize = 0,
};

const hostinger_domain_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "domains_getDomainListV1",
    .hint_kind = "domains_getDomainListV1",
    .purpose = "discover account domains",
}};

const hostinger_vps_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getVirtualMachinesV1",
    .hint_kind = "VPS_getVirtualMachinesV1",
    .purpose = "discover VPS ids",
}};

const hostinger_action_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getActionsV1",
    .hint_kind = "VPS_getActionsV1",
    .purpose = "discover VPS action ids",
}};

const hostinger_template_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getTemplatesV1",
    .hint_kind = "VPS_getTemplatesV1",
    .purpose = "discover VPS template ids",
}};

const hostinger_firewall_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getFirewallListV1",
    .hint_kind = "VPS_getFirewallListV1",
    .purpose = "discover VPS firewall ids",
}};

const hostinger_post_install_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getPostInstallScriptsV1",
    .hint_kind = "VPS_getPostInstallScriptsV1",
    .purpose = "discover post-install script ids",
}};

const hostinger_dns_snapshot_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "DNS_getDNSSnapshotListV1",
    .hint_kind = "DNS_getDNSSnapshotListV1",
    .purpose = "discover DNS snapshot ids for the selected domain",
}};

const hostinger_whois_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "domains_getWHOISProfileListV1",
    .hint_kind = "domains_getWHOISProfileListV1",
    .purpose = "discover WHOIS profile ids",
}};

const hostinger_username_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "hosting_listWebsitesV1",
    .hint_kind = "hosting_listWebsitesV1",
    .purpose = "discover hosting account usernames from websites",
}};

const hostinger_order_sources = [_]ActualCaptureInputSource{
    .{
        .operation_id = "hosting_listOrdersV1",
        .hint_kind = "hosting_listOrdersV1",
        .purpose = "discover hosting order ids",
    },
    .{
        .operation_id = "hosting_listWebsitesV1",
        .hint_kind = "hosting_listWebsitesV1",
        .purpose = "reuse website inventory related order ids",
    },
};

const hostinger_database_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "hosting_listAccountDatabasesV1",
    .hint_kind = "hosting_listAccountDatabasesV1",
    .purpose = "discover database names for a hosting account",
}};

const hostinger_nodejs_build_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "hosting_listNodeJSBuildsV1",
    .hint_kind = "hosting_listNodeJSBuildsV1",
    .purpose = "discover NodeJS build UUIDs for a website",
}};

const hostinger_docker_project_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "VPS_getProjectListV1",
    .hint_kind = "VPS_getProjectListV1",
    .purpose = "discover Docker Manager project names for a VPS",
}};

const hostinger_reach_profile_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "reach_listProfilesV1",
    .hint_kind = "reach_listProfilesV1",
    .purpose = "discover Reach profile UUIDs",
}};

const hostinger_reach_segment_sources = [_]ActualCaptureInputSource{.{
    .operation_id = "reach_listSegmentsV1",
    .hint_kind = "reach_listSegmentsV1",
    .purpose = "discover Reach segment UUIDs",
}};

const ActualCapturePlan = struct {
    options: ActualCaptureOptions,
    routes: CoverageRoutes,
    captures: db_store.RouteCaptureEvidenceRows,
    source_evidence: db_store.RouteSourceEvidenceRows,
    cloudflare_accounts: ?db_store.CloudflareAccountRows,
    cloudflare_zones: ?db_store.CloudflareZoneRows,
    cloudflare_resources: ?db_store.CloudflareResourceHintRows,
    cloudflare_inventory: ?db_store.CloudflareInventoryHintRows,
    hostinger_vps: ?db_store.HostingerVpsRows,
    hostinger_resources: ?db_store.HostingerResourceHintRows,
    hostinger_inventory: ?db_store.HostingerInventoryHintRows,

    fn deinit(self: *ActualCapturePlan, gpa: Allocator) void {
        if (self.hostinger_inventory) |*rows| rows.deinit(gpa);
        if (self.hostinger_resources) |*rows| rows.deinit(gpa);
        if (self.hostinger_vps) |*rows| rows.deinit(gpa);
        if (self.cloudflare_inventory) |*rows| rows.deinit(gpa);
        if (self.cloudflare_resources) |*rows| rows.deinit(gpa);
        if (self.cloudflare_zones) |*rows| rows.deinit(gpa);
        if (self.cloudflare_accounts) |*rows| rows.deinit(gpa);
        self.source_evidence.deinit(gpa);
        self.captures.deinit(gpa);
        self.routes.deinit(gpa);
    }

    fn cloudflareAccountRows(self: ActualCapturePlan) []const db_store.CloudflareAccountRow {
        if (self.cloudflare_accounts) |rows| return rows.items;
        return &.{};
    }

    fn cloudflareZoneRows(self: ActualCapturePlan) []const db_store.CloudflareZoneRow {
        if (self.cloudflare_zones) |rows| return rows.items;
        return &.{};
    }

    fn cloudflareResourceRows(self: ActualCapturePlan) []const db_store.CloudflareResourceHintRow {
        if (self.cloudflare_resources) |rows| return rows.items;
        return &.{};
    }

    fn cloudflareInventoryRows(self: ActualCapturePlan) []const db_store.CloudflareInventoryHintRow {
        if (self.cloudflare_inventory) |rows| return rows.items;
        return &.{};
    }

    fn hostingerVpsRows(self: ActualCapturePlan) []const db_store.HostingerVpsRow {
        if (self.hostinger_vps) |rows| return rows.items;
        return &.{};
    }

    fn hostingerResourceRows(self: ActualCapturePlan) []const db_store.HostingerResourceHintRow {
        if (self.hostinger_resources) |rows| return rows.items;
        return &.{};
    }

    fn hostingerInventoryRows(self: ActualCapturePlan) []const db_store.HostingerInventoryHintRow {
        if (self.hostinger_inventory) |rows| return rows.items;
        return &.{};
    }

    fn hints(self: ActualCapturePlan) ActualCaptureHints {
        return .{
            .configured_domains = self.options.configured_domains,
            .cloudflare_accounts = self.cloudflareAccountRows(),
            .cloudflare_zones = self.cloudflareZoneRows(),
            .cloudflare_resources = self.cloudflareResourceRows(),
            .cloudflare_inventory = self.cloudflareInventoryRows(),
            .hostinger_vps = self.hostingerVpsRows(),
            .hostinger_resources = self.hostingerResourceRows(),
            .hostinger_inventory = self.hostingerInventoryRows(),
        };
    }

    fn totals(self: ActualCapturePlan) ActualCaptureTotals {
        var out = ActualCaptureTotals{};
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            const status = actualCaptureState(row.route, self.captures.items) orelse continue;
            out.official_read_routes += 1;
            const route_status = actualRouteCaptureStatus(row.route.provider.name(), row.route.operation_id.?, self.captures.items);
            out.capture_events += route_status.events;
            switch (status) {
                .ok => out.ok_read_routes += 1,
                .missing => {
                    out.missing_read_routes += 1;
                    out.candidate_routes += 1;
                    if (actualCaptureReady(row.route, hints_value)) out.ready_candidates += 1;
                },
                .non_ok => {
                    out.non_ok_read_routes += 1;
                    out.candidate_routes += 1;
                    if (actualCaptureReady(row.route, hints_value)) out.ready_candidates += 1;
                },
            }
        }
        return out;
    }

    fn writeText(self: ActualCapturePlan, gpa: Allocator, writer: anytype) !void {
        const totals_value = self.totals();
        const source_summary = try self.sourceSummary(gpa);
        try writer.writeAll("Cloudio actual route capture plan\n");
        try writer.writeAll("rank: official GET/read routes missing an OK route.capture audit event\n");
        try writer.print("filter provider={s}", .{self.options.filter.provider.name()});
        if (self.options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
        if (self.options.filter.family != .all) try writer.print(" family={s}", .{self.options.filter.family.name()});
        if (self.options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
        if (self.options.include_plans) try writer.writeAll(" plans=true");
        try writer.writeAll(" limit=");
        if (self.options.limit == 0) {
            try writer.writeAll("all\n");
        } else {
            try writer.print("{d}\n", .{self.options.limit});
        }
        try writer.print("loaded_capture_operation_status_rows={d} loaded_source_evidence_rows={d} configured_domain_hints={d} cloudflare_account_hints={d} cloudflare_zone_hints={d} cloudflare_resource_hints={d} cloudflare_inventory_hints={d} hostinger_vps_hints={d} hostinger_resource_hints={d} hostinger_inventory_hints={d}\n", .{ self.captures.items.len, self.source_evidence.items.len, self.options.configured_domains.len, self.cloudflareAccountRows().len, self.cloudflareZoneRows().len, self.cloudflareResourceRows().len, self.cloudflareInventoryRows().len, self.hostingerVpsRows().len, self.hostingerResourceRows().len, self.hostingerInventoryRows().len });
        try writer.print("summary official_read_routes={d} ok_read_routes={d} non_ok_read_routes={d} missing_read_routes={d} candidate_routes={d} ready_candidates={d} capture_events={d}\n", .{
            totals_value.official_read_routes,
            totals_value.ok_read_routes,
            totals_value.non_ok_read_routes,
            totals_value.missing_read_routes,
            totals_value.candidate_routes,
            totals_value.ready_candidates,
            totals_value.capture_events,
        });
        try writer.print("source_summary total={d} captured_with_hints={d} captured_empty={d} captured_without_hints={d} captured_unknown_body={d} ready_to_capture={d} waiting_for_inputs={d} diagnostic_blocked={d} captured_error={d} no_official_source={d} not_in_catalog={d} unmapped={d} not_eligible={d} body_array={d} body_data_array={d} body_error_object={d} body_no_evidence={d} body_other={d}\n", .{
            source_summary.total_sources,
            source_summary.captured_with_hints,
            source_summary.captured_empty,
            source_summary.captured_without_hints,
            source_summary.captured_unknown_body,
            source_summary.ready_to_capture,
            source_summary.waiting_for_inputs,
            source_summary.diagnostic_blocked,
            source_summary.captured_error,
            source_summary.no_official_source,
            source_summary.not_in_catalog,
            source_summary.unmapped,
            source_summary.not_eligible,
            source_summary.body_array,
            source_summary.body_data_array,
            source_summary.body_error_object,
            source_summary.body_no_evidence,
            source_summary.body_other,
        });

        var visible: usize = 0;
        var omitted: usize = 0;
        var current_provider: ?[]const u8 = null;
        var current_tag: ?[]const u8 = null;
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            const state = actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            if (self.options.limit != 0 and visible >= self.options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            const provider_name = row.route.provider.name();
            if (current_provider == null or !std.mem.eql(u8, current_provider.?, provider_name)) {
                current_provider = provider_name;
                current_tag = null;
                try writer.print("\n{s}\n", .{provider_name});
            }
            if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
                current_tag = row.route.tag;
                try writer.print("  {s}\n", .{row.route.tag});
            }
            const route_status = actualRouteCaptureStatus(provider_name, row.route.operation_id.?, self.captures.items);
            try writer.print("    {s} {s} | state={s} support={s} op={s} events={d}", .{
                row.route.method.name(),
                row.route.path_template,
                state.name(),
                @tagName(row.route.support),
                row.route.operation_id.?,
                route_status.events,
            });
            if (route_status.latest_at.len != 0) try writer.print(" latest={s}", .{route_status.latest_at});
            try writer.writeByte('\n');
            try writer.writeAll("      required_path=");
            try writeRequiredParamNamesText(writer, row.route.path_params);
            try writer.writeAll(" required_query=");
            try writeRequiredParamNamesText(writer, row.route.query_params);
            try writer.writeAll(" required_header=");
            try writeRequiredParamNamesText(writer, row.route.header_params);
            try writer.print(" pagination={s}\n", .{routePaginationKind(row.route) orelse "none"});
            try writer.print("      ready={s} live_read_supported={s} missing_inputs=", .{
                if (actualCaptureReady(row.route, hints_value)) "true" else "false",
                if (provider_dispatch.routeLiveCallSupported(row.route)) "true" else "false",
            });
            try writeActualMissingInputsText(writer, row.route, hints_value);
            try writer.writeByte('\n');
            if (actualCaptureMissingInputCount(row.route, hints_value) != 0) {
                try writeActualMissingInputSourcesText(gpa, writer, row.route, self.routes.items, self.captures.items, self.source_evidence.items, hints_value);
            }
            const command = try actualCaptureCommand(gpa, row.route, hints_value);
            defer gpa.free(command);
            try writer.print("      capture: {s}\n", .{command});
            if (self.options.include_plans) {
                const plan = try routeReadPlanJson(gpa, row.route);
                defer gpa.free(plan);
                try writer.print("      read-plan: {s}\n", .{plan});
            }
        }

        if (totals_value.candidate_routes == 0) {
            try writer.writeAll("no actual capture gaps for filter\n");
        } else if (omitted != 0) {
            try writer.print("omitted={d}\n", .{omitted});
        }
    }

    fn writeJson(self: ActualCapturePlan, gpa: Allocator, writer: anytype) !void {
        const totals_value = self.totals();
        const source_summary = try self.sourceSummary(gpa);
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_actual_captures", true);
        try writer.writeAll("\"filter\":");
        try writeRouteFilterJson(actualCaptureRouteFilter(self.options.filter), writer);
        try writer.writeByte(',');
        try writeJsonCountField(writer, "limit", self.options.limit, true);
        try writeJsonBoolField(writer, "include_plans", self.options.include_plans, true);
        try writeJsonField(writer, "rank", "official GET/read routes missing an OK route.capture audit event", true);
        try writeJsonCountField(writer, "loaded_capture_operation_status_rows", self.captures.items.len, true);
        try writeJsonCountField(writer, "loaded_source_evidence_rows", self.source_evidence.items.len, true);
        try writeJsonCountField(writer, "configured_domain_hints", self.options.configured_domains.len, true);
        try writeJsonCountField(writer, "cloudflare_account_hints", self.cloudflareAccountRows().len, true);
        try writeJsonCountField(writer, "cloudflare_zone_hints", self.cloudflareZoneRows().len, true);
        try writeJsonCountField(writer, "cloudflare_resource_hints", self.cloudflareResourceRows().len, true);
        try writeJsonCountField(writer, "cloudflare_inventory_hints", self.cloudflareInventoryRows().len, true);
        try writeJsonCountField(writer, "hostinger_vps_hints", self.hostingerVpsRows().len, true);
        try writeJsonCountField(writer, "hostinger_resource_hints", self.hostingerResourceRows().len, true);
        try writeJsonCountField(writer, "hostinger_inventory_hints", self.hostingerInventoryRows().len, true);
        try writer.writeAll("\"summary\":");
        try writeActualCaptureTotalsJson(totals_value, writer);
        try writer.writeAll(",\"source_summary\":");
        try writeActualCaptureSourceSummaryJson(source_summary, writer);
        try writer.writeAll(",\"candidates\":[");

        var visible: usize = 0;
        var omitted: usize = 0;
        var first = true;
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            const state = actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            if (self.options.limit != 0 and visible >= self.options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writeMaybeJsonComma(writer, &first);
            try writeActualCaptureCandidateJson(gpa, row, state, self.routes.items, self.captures.items, self.source_evidence.items, hints_value, self.options, writer);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "visible", visible, true);
        try writeJsonCountField(writer, "omitted", omitted, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }

    fn sourceSummary(self: ActualCapturePlan, gpa: Allocator) !ActualCaptureSourceSummary {
        var out = ActualCaptureSourceSummary{};
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            const state = actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            try actualCaptureSummarizeMissingInputSources(gpa, &out, row.route, self.routes.items, self.captures.items, self.source_evidence.items, hints_value);
        }
        return out;
    }
};

pub const Summary = struct {
    cloudflare: ProviderSummary,
    hostinger: ProviderSummary,

    pub fn init() Summary {
        return .{
            .cloudflare = ProviderSummary.init("cloudflare"),
            .hostinger = ProviderSummary.init("hostinger"),
        };
    }

    pub fn total(self: Summary) usize {
        return self.cloudflare.total + self.hostinger.total;
    }

    pub fn writeText(self: Summary, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage\n");
        try writer.print("total operations: {d}\n\n", .{self.total()});
        try writeProvider(self.cloudflare, writer);
        try writer.writeByte('\n');
        try writeProvider(self.hostinger, writer);
    }

    pub fn writeJson(self: Summary, writer: anytype) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_summary", true);
        try writeJsonCountField(writer, "total_operations", self.total(), true);
        try writer.writeAll("\"providers\":[");
        try writeProviderSummaryJson(self.cloudflare, writer);
        try writer.writeByte(',');
        try writeProviderSummaryJson(self.hostinger, writer);
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub fn load(io: Io, gpa: Allocator, paths: Paths) !Summary {
    const cloudflare_text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(cloudflare_text);
    const hostinger_text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(hostinger_text);
    return try loadFromText(gpa, cloudflare_text, hostinger_text);
}

pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !Summary {
    var summary = Summary.init();
    try summarizeProvider(gpa, "cloudflare", cloudflare_text, &summary.cloudflare);
    try summarizeProvider(gpa, "hostinger", hostinger_text, &summary.hostinger);
    return summary;
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, writer: anytype) !void {
    const summary = try load(io, gpa, paths);
    try summary.writeText(writer);
}

pub fn writeJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, writer: anytype) !void {
    const summary = try load(io, gpa, paths);
    try summary.writeJson(writer);
}

pub fn loadTags(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !TagSummaries {
    var rows = std.ArrayList(TagSummary).empty;
    errdefer deinitTagList(&rows, gpa);

    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderTags(gpa, "cloudflare", text, &rows);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderTags(gpa, "hostinger", text, &rows);
    }

    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !TagSummaries {
    var rows = std.ArrayList(TagSummary).empty;
    errdefer deinitTagList(&rows, gpa);
    if (filter.includes("cloudflare")) try summarizeProviderTags(gpa, "cloudflare", cloudflare_text, &rows);
    if (filter.includes("hostinger")) try summarizeProviderTags(gpa, "hostinger", hostinger_text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeTagsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    var rows = try loadTags(io, gpa, paths, filter);
    defer rows.deinit(gpa);
    try rows.writeText(writer);
}

pub fn writeTagsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    var rows = try loadTags(io, gpa, paths, filter);
    defer rows.deinit(gpa);
    try rows.writeJson(writer, filter);
}

pub fn loadGaps(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !GapReport {
    var rows = std.ArrayList(GapSummary).empty;
    errdefer deinitGapList(&rows, gpa);

    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderGaps(gpa, "cloudflare", text, &rows);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderGaps(gpa, "hostinger", text, &rows);
    }

    std.mem.sort(GapSummary, rows.items, {}, gapLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadGapsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !GapReport {
    var rows = std.ArrayList(GapSummary).empty;
    errdefer deinitGapList(&rows, gpa);
    if (filter.includes("cloudflare")) try summarizeProviderGaps(gpa, "cloudflare", cloudflare_text, &rows);
    if (filter.includes("hostinger")) try summarizeProviderGaps(gpa, "hostinger", hostinger_text, &rows);
    std.mem.sort(GapSummary, rows.items, {}, gapLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeGapsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: GapOptions, writer: anytype) !void {
    var gaps = try loadGaps(io, gpa, paths, options.provider);
    defer gaps.deinit(gpa);
    try gaps.writeText(writer, options);
}

pub fn writeGapsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: GapOptions, writer: anytype) !void {
    var gaps = try loadGaps(io, gpa, paths, options.provider);
    defer gaps.deinit(gpa);
    try gaps.writeJson(writer, options);
}

pub fn loadLevels(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !LevelReport {
    var report = LevelReport.init();
    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderLevels(gpa, "cloudflare", text, &report.cloudflare);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderLevels(gpa, "hostinger", text, &report.hostinger);
    }
    return report;
}

pub fn loadLevelsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelReport {
    var report = LevelReport.init();
    if (filter.includes("cloudflare")) try summarizeProviderLevels(gpa, "cloudflare", cloudflare_text, &report.cloudflare);
    if (filter.includes("hostinger")) try summarizeProviderLevels(gpa, "hostinger", hostinger_text, &report.hostinger);
    return report;
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
    var rows = std.ArrayList(LevelTagEvidence).empty;
    errdefer deinitLevelTagList(&rows, gpa);

    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderLevelTags(gpa, "cloudflare", text, &rows);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderLevelTags(gpa, "hostinger", text, &rows);
    }

    std.mem.sort(LevelTagEvidence, rows.items, {}, levelTagLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadLevelTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelTagReport {
    var rows = std.ArrayList(LevelTagEvidence).empty;
    errdefer deinitLevelTagList(&rows, gpa);
    if (filter.includes("cloudflare")) try summarizeProviderLevelTags(gpa, "cloudflare", cloudflare_text, &rows);
    if (filter.includes("hostinger")) try summarizeProviderLevelTags(gpa, "hostinger", hostinger_text, &rows);
    std.mem.sort(LevelTagEvidence, rows.items, {}, levelTagLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
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

pub fn loadFamilies(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions) !FamilyReport {
    var tags = try loadLevelTags(io, gpa, paths, options.provider);
    defer tags.deinit(gpa);
    return try buildFamilyReport(gpa, tags.items, options);
}

pub fn loadFamiliesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions) !FamilyReport {
    var tags = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer tags.deinit(gpa);
    return try buildFamilyReport(gpa, tags.items, options);
}

pub fn writeFamiliesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamilies(io, gpa, paths, options);
    defer report.deinit(gpa);
    try report.writeText(writer, options);
}

pub fn writeFamiliesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamilies(io, gpa, paths, options);
    defer report.deinit(gpa);
    try report.writeJson(writer, options);
}

pub fn writeFamiliesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamiliesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer report.deinit(gpa);
    try report.writeText(writer, options);
}

pub fn writeFamiliesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamiliesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer report.deinit(gpa);
    try report.writeJson(writer, options);
}

pub fn writeTypedModelsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try writeTypedModelsText(gpa, report.items, options, writer);
}

pub fn writeTypedModelsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try writeTypedModelsJson(gpa, report.items, options, writer);
}

pub fn writeTypedModelsTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    try writeTypedModelsText(gpa, report.items, options, writer);
}

pub fn writeTypedModelsJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    try writeTypedModelsJson(gpa, report.items, options, writer);
}

pub fn writeWorkplanTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try loadWorkplanBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try writeWorkplanText(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try loadWorkplanBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try writeWorkplanJson(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try loadWorkplanBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try writeWorkplanText(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try loadWorkplanBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try writeWorkplanJson(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

fn loadWorkplanBundleRoutesFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try loadRoutes(io, gpa, paths, .{
        .provider = options.provider,
        .family = options.family,
    });
}

fn loadWorkplanBundleRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions) !?CoverageRoutes {
    if (!options.bundle_candidates) return null;
    return try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{
        .provider = options.provider,
        .family = options.family,
    });
}

pub fn auditL1(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !L1Audit {
    return try app_provider_l1.auditFromFiles(io, gpa, paths, filter);
}

pub fn auditL1FromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !L1Audit {
    return try app_provider_l1.auditFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeL1AuditTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_l1.writeTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeL1AuditJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_l1.writeJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn loadRoutes(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter) !CoverageRoutes {
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, filter);
}

pub fn loadRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: RouteFilter) !CoverageRoutes {
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeRoutesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRoutesTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeRoutesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRoutesJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeCaptureCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeCaptureCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn writeCaptureCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesTextFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeCaptureCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesJsonFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeActualCapturesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, options);
    defer plan.deinit(gpa);
    try plan.writeText(gpa, writer);
}

pub fn writeActualCapturesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, options);
    defer plan.deinit(gpa);
    try plan.writeJson(gpa, writer);
}

pub fn writeActualCapturesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, options);
    defer plan.deinit(gpa);
    try plan.writeText(gpa, writer);
}

pub fn writeActualCapturesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, options);
    defer plan.deinit(gpa);
    try plan.writeJson(gpa, writer);
}

pub fn actualReadyCaptureJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    try validateActualReadyCaptureProvider(auth, options.filter.provider);
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, .{
        .filter = options.filter,
        .limit = 0,
        .include_plans = false,
        .configured_domains = options.configured_domains,
    });
    defer plan.deinit(gpa);
    return try actualReadyCaptureJson(io, gpa, db, auth, plan, options);
}

pub fn actualReadyCaptureJsonFromText(io: Io, gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    try validateActualReadyCaptureProvider(auth, options.filter.provider);
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, .{
        .filter = options.filter,
        .limit = 0,
        .include_plans = false,
        .configured_domains = options.configured_domains,
    });
    defer plan.deinit(gpa);
    return try actualReadyCaptureJson(io, gpa, db, auth, plan, options);
}

pub fn writeDryRunCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeDryRunCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn writeDryRunCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesTextFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeDryRunCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesJsonFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

fn loadActualCapturePlanFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions) !ActualCapturePlan {
    var routes = try loadRoutes(io, gpa, paths, actualCaptureRouteFilter(options.filter));
    errdefer routes.deinit(gpa);
    var captures = try db.routeCaptureEvidence(gpa, .{
        .provider = actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_load_limit,
    });
    errdefer captures.deinit(gpa);
    var source_evidence = try db.routeSourceEvidence(gpa, .{
        .provider = actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_source_evidence_limit,
    });
    errdefer source_evidence.deinit(gpa);
    var cloudflare_accounts = try loadActualCaptureCloudflareAccountHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_accounts) |*rows| rows.deinit(gpa);
    var cloudflare_zones = try loadActualCaptureCloudflareZoneHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_zones) |*rows| rows.deinit(gpa);
    var cloudflare_resources = try loadActualCaptureCloudflareResourceHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_resources) |*rows| rows.deinit(gpa);
    var cloudflare_inventory = try loadActualCaptureCloudflareInventoryHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_inventory) |*rows| rows.deinit(gpa);
    var hostinger_vps = try loadActualCaptureHostingerHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_vps) |*rows| rows.deinit(gpa);
    var hostinger_resources = try loadActualCaptureHostingerResourceHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_resources) |*rows| rows.deinit(gpa);
    var hostinger_inventory = try loadActualCaptureHostingerInventoryHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_inventory) |*rows| rows.deinit(gpa);
    return .{
        .options = options,
        .routes = routes,
        .captures = captures,
        .source_evidence = source_evidence,
        .cloudflare_accounts = cloudflare_accounts,
        .cloudflare_zones = cloudflare_zones,
        .cloudflare_resources = cloudflare_resources,
        .cloudflare_inventory = cloudflare_inventory,
        .hostinger_vps = hostinger_vps,
        .hostinger_resources = hostinger_resources,
        .hostinger_inventory = hostinger_inventory,
    };
}

fn loadActualCapturePlanFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions) !ActualCapturePlan {
    var routes = try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, actualCaptureRouteFilter(options.filter));
    errdefer routes.deinit(gpa);
    var captures = try db.routeCaptureEvidence(gpa, .{
        .provider = actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_load_limit,
    });
    errdefer captures.deinit(gpa);
    var source_evidence = try db.routeSourceEvidence(gpa, .{
        .provider = actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_source_evidence_limit,
    });
    errdefer source_evidence.deinit(gpa);
    var cloudflare_accounts = try loadActualCaptureCloudflareAccountHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_accounts) |*rows| rows.deinit(gpa);
    var cloudflare_zones = try loadActualCaptureCloudflareZoneHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_zones) |*rows| rows.deinit(gpa);
    var cloudflare_resources = try loadActualCaptureCloudflareResourceHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_resources) |*rows| rows.deinit(gpa);
    var cloudflare_inventory = try loadActualCaptureCloudflareInventoryHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_inventory) |*rows| rows.deinit(gpa);
    var hostinger_vps = try loadActualCaptureHostingerHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_vps) |*rows| rows.deinit(gpa);
    var hostinger_resources = try loadActualCaptureHostingerResourceHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_resources) |*rows| rows.deinit(gpa);
    var hostinger_inventory = try loadActualCaptureHostingerInventoryHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_inventory) |*rows| rows.deinit(gpa);
    return .{
        .options = options,
        .routes = routes,
        .captures = captures,
        .source_evidence = source_evidence,
        .cloudflare_accounts = cloudflare_accounts,
        .cloudflare_zones = cloudflare_zones,
        .cloudflare_resources = cloudflare_resources,
        .cloudflare_inventory = cloudflare_inventory,
        .hostinger_vps = hostinger_vps,
        .hostinger_resources = hostinger_resources,
        .hostinger_inventory = hostinger_inventory,
    };
}

fn loadActualCaptureCloudflareAccountHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareAccountRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareAccountRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

fn loadActualCaptureCloudflareZoneHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareZoneRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareZoneRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

fn loadActualCaptureCloudflareResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareResourceHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareResourceHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

fn loadActualCaptureCloudflareInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareInventoryHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareInventoryHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

fn loadActualCaptureHostingerHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerVpsRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerVpsRows(gpa, actual_capture_hostinger_vps_hint_limit);
}

fn loadActualCaptureHostingerResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerResourceHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerResourceHints(gpa, actual_capture_hostinger_hint_limit);
}

fn loadActualCaptureHostingerInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerInventoryHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerInventoryHints(gpa, actual_capture_hostinger_hint_limit);
}

fn actualCaptureProviderDbValue(provider: ProviderFilter) ?[]const u8 {
    return switch (provider) {
        .all => null,
        .cloudflare => "cloudflare",
        .hostinger => "hostinger",
    };
}

pub fn routePlanJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput) ![]u8 {
    return try app_provider_route_plan.planJson(io, gpa, paths, routePlanInput(input));
}

pub fn routeReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.readMetadataJson(io, gpa, paths, routePlanInput(input), auth);
}

pub fn routeCaptureReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    return try app_provider_route_capture.readMetadataJson(io, gpa, paths, routePlanInput(input), auth, db, options);
}

pub fn routeDryRunJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.dryRunJson(io, gpa, paths, routePlanInput(input), auth);
}

pub fn routeDryRunJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.dryRunJsonFromText(gpa, cloudflare_text, hostinger_text, routePlanInput(input), auth);
}

pub fn routePlanJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput) ![]u8 {
    return try app_provider_route_plan.planJsonFromText(gpa, cloudflare_text, hostinger_text, routePlanInput(input));
}

fn routePlanInput(input: RoutePlanInput) app_provider_route_plan.RoutePlanInput {
    return .{
        .filter = routePlanFilter(input.filter),
        .request = input.request,
    };
}

fn routePlanFilter(filter: RouteFilter) app_provider_route_plan.RouteFilter {
    return .{
        .provider = filter.provider,
        .tag_query = filter.tag_query,
        .operation_id = filter.operation_id,
        .method = filter.method,
        .path_template = filter.path_template,
        .support = if (filter.support) |support| routePlanSupportFilter(support) else null,
        .mode = if (filter.mode) |mode| routePlanModeFilter(mode) else null,
    };
}

fn routePlanSupportFilter(support: SupportFilter) app_provider_route_plan.SupportFilter {
    return switch (support) {
        .implemented => .implemented,
        .partial => .partial,
        .planned => .planned,
        .blocked_permission => .blocked_permission,
        .unsafe_mutation => .unsafe_mutation,
        .deprecated => .deprecated,
        .not_applicable => .not_applicable,
    };
}

fn routePlanModeFilter(mode: ModeFilter) app_provider_route_plan.ModeFilter {
    return switch (mode) {
        .read => .read,
        .dry_run => .dry_run,
        .write => .write,
        .none => .none,
    };
}

pub fn captureRouteReadResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions) ![]u8 {
    return try app_provider_route_capture.readResultJson(gpa, db, route, request, result, options);
}

pub fn writeRoutePlanTextFromFiles(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, writer: anytype) !void {
    try app_provider_route_plan.writeTextFromFiles(io, gpa, paths, routePlanInput(input), writer);
}

fn selectSingleRoute(routes: []const CoverageRoute) !CoverageRoute {
    if (routes.len == 0) return error.ProviderRoutePlanNotFound;
    if (routes.len != 1) return error.ProviderRoutePlanAmbiguous;
    return routes[0];
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn actualCaptureRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

fn captureCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    return app_provider_coverage_candidates.captureCandidateRouteFilter(filter);
}

fn dryRunCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    return app_provider_coverage_candidates.dryRunCandidateRouteFilter(filter);
}

fn routeIsCaptureCandidate(row: CoverageRoute, options: CaptureCandidateOptions) bool {
    return app_provider_coverage_candidates.isCaptureCandidate(row, options);
}

fn routeIsDryRunCandidate(row: CoverageRoute, options: DryRunCandidateOptions) bool {
    return app_provider_coverage_candidates.isDryRunCandidate(row, options);
}

fn actualCaptureState(route: provider_routes.Route, captures: []const db_store.RouteCaptureEvidenceRow) ?ActualCaptureState {
    if (route.deprecated or !route.isRoutable()) return null;
    if (route.method != .GET or route.mode != .read) return null;
    if (route.request_body.required) return null;
    const operation_id = route.operation_id orelse return null;
    const status = actualRouteCaptureStatus(route.provider.name(), operation_id, captures);
    if (status.ok) return .ok;
    if (status.any) return .non_ok;
    return .missing;
}

fn actualRouteCaptureStatus(provider: []const u8, operation_id: []const u8, captures: []const db_store.RouteCaptureEvidenceRow) ActualRouteStatus {
    var out = ActualRouteStatus{};
    for (captures) |capture| {
        if (!std.mem.eql(u8, capture.provider, provider)) continue;
        if (!std.mem.eql(u8, capture.operation_id, operation_id)) continue;
        out.any = true;
        out.events += capture.count;
        if (actualStatusIsOk(capture.status)) out.ok = true;
        if (actualStatusIsError(capture.status)) out.err = true;
        if (capture.latest_at.len != 0 and actualLatestAtLessThan(out.latest_at, capture.latest_at)) out.latest_at = capture.latest_at;
    }
    return out;
}

fn actualStatusIsOk(status: []const u8) bool {
    return std.mem.eql(u8, status, "ok") or
        std.mem.eql(u8, status, "success") or
        std.mem.eql(u8, status, "done") or
        actualHttpStatusIsSuccess(status);
}

fn actualStatusIsError(status: []const u8) bool {
    return actualHttpStatusIsError(status) or
        std.mem.indexOf(u8, status, "error") != null or
        std.mem.indexOf(u8, status, "fail") != null or
        std.mem.indexOf(u8, status, "denied") != null or
        std.mem.indexOf(u8, status, "blocked") != null or
        std.mem.indexOf(u8, status, "permission") != null or
        std.mem.indexOf(u8, status, "not_found") != null or
        std.mem.indexOf(u8, status, "missing") != null;
}

fn actualHttpStatusIsSuccess(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 200 and value < 300;
}

fn actualHttpStatusIsError(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 400;
}

fn actualLatestAtLessThan(current: []const u8, candidate: []const u8) bool {
    if (current.len == 0) return true;
    return std.mem.order(u8, current, candidate) == .lt;
}

fn actualCaptureReady(route: provider_routes.Route, hints: ActualCaptureHints) bool {
    return actualCaptureReadyWithPolicy(route, hints, false);
}

fn actualCaptureReadyWithPolicy(route: provider_routes.Route, hints: ActualCaptureHints, include_blocked: bool) bool {
    return actualCaptureRouteExecutable(route, include_blocked) and actualCaptureMissingInputCount(route, hints) == 0;
}

fn actualCaptureRouteExecutable(route: provider_routes.Route, include_blocked: bool) bool {
    return provider_dispatch.routeLiveCallSupported(route) or (include_blocked and provider_dispatch.routeDiagnosticReadSupported(route));
}

fn actualCaptureUsesDiagnosticRead(route: provider_routes.Route, include_blocked: bool) bool {
    return include_blocked and !provider_dispatch.routeLiveCallSupported(route) and provider_dispatch.routeDiagnosticReadSupported(route);
}

fn actualCaptureMissingInputCount(route: provider_routes.Route, hints: ActualCaptureHints) usize {
    var count: usize = 0;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) == null) count += 1;
    }
    for (route.query_params) |param| {
        if (param.required and !actualCaptureHasQueryParamHint(route, param.name, hints)) count += 1;
    }
    for (route.header_params) |param| {
        if (param.required) count += 1;
    }
    return count;
}

fn actualCapturePathParamHint(route: provider_routes.Route, name: []const u8, hints: ActualCaptureHints) ?[]const u8 {
    return switch (route.provider) {
        .cloudflare => actualCaptureCloudflarePathParamHint(route, name, hints),
        .hostinger => actualCaptureHostingerPathParamHint(route, name, hints),
    };
}

fn actualCaptureCloudflarePathParamHint(route: provider_routes.Route, name: []const u8, hints: ActualCaptureHints) ?[]const u8 {
    if (std.mem.eql(u8, name, "account_id") or std.mem.eql(u8, name, "account_identifier")) return actualCaptureCloudflareAccountIdHint(hints);
    if (std.mem.eql(u8, name, "zone_id") or std.mem.eql(u8, name, "zone_identifier")) return actualCaptureCloudflareZoneIdHint(hints);
    if (std.mem.eql(u8, name, "dns_record_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "route-cloudflare-dns", "route-cloudflare-dns-typed-smoke", "dns", "dns-records" });
    if (std.mem.eql(u8, name, "ruleset_id")) return actualCaptureCloudflareRulesetIdHint(route, hints);
    if (std.mem.eql(u8, name, "ruleset_phase")) return actualCaptureCloudflareRulesetPhaseHint(route, hints);
    if (std.mem.eql(u8, name, "identifier") and actualCaptureRoutePathContains(route, "/custom_pages/")) return actualCaptureCloudflareCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "custom_page_id")) return actualCaptureCloudflareAccessCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "certificate_pack_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "tls-zone-certificate-packs", "tls-zone-certificate-pack" });
    if (std.mem.eql(u8, name, "identity_provider_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "idp_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "member_id") and containsIgnoreCase(route.tag, "Account Members")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-members"});
    if (std.mem.eql(u8, name, "role_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-roles"});
    if (std.mem.eql(u8, name, "token_id")) return actualCaptureCloudflareTokenIdHint(route, hints);
    if (std.mem.eql(u8, name, "permission_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-permission-groups", "account-token-permission-groups", "user-token-permission-groups" });
    if (std.mem.eql(u8, name, "resource_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-resource-groups"});
    if (std.mem.eql(u8, name, "client_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-client-certificates", "api-shield-client-certificates", "api-shield-client-certificates-for-a-zone" });
    if (std.mem.eql(u8, name, "certificate_id") and actualCaptureRoutePathContains(route, "/origin_ca/certificates/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "tls-origin-ca-certificates", "tls-origin-ca-certificate" });
    if (std.mem.eql(u8, name, "plan_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-available-plans", "zone-available-rate-plans" });
    if (std.mem.eql(u8, name, "rule_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-rules", "email-routing-rules" });
    if (std.mem.eql(u8, name, "destination_address_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-destination-addresses", "email-routing-destination-addresses" });
    if (std.mem.eql(u8, name, "name") and containsIgnoreCase(route.tag, "API Shield Labels")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"zone-api-shield-labels"});
    return null;
}

fn actualCaptureCloudflareAccountIdHint(hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneAccountId(hints)) |account_id| return account_id;
    for (hints.cloudflare_accounts) |row| {
        if (row.id.len != 0) return row.id;
    }
    for (hints.cloudflare_zones) |row| {
        if (row.account_id.len != 0) return row.account_id;
    }
    return null;
}

fn actualCaptureCloudflareZoneIdHint(hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneId(hints)) |zone_id| return zone_id;
    for (hints.cloudflare_zones) |row| {
        if (row.id.len != 0) return row.id;
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneId(hints: ActualCaptureHints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneAccountId(hints: ActualCaptureHints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.account_id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.account_id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareDomain(hints: ActualCaptureHints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.cloudflare_zones) |row| {
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
    }
    return null;
}

fn actualCaptureCloudflareRulesetIdHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareRulesetPhaseHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareCustomPageIdHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-custom-pages", "account-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-custom-pages", "zone-custom-page" });
    }
    return null;
}

fn actualCaptureCloudflareAccessCustomPageIdHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access custom pages")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-custom-pages", "access-account-custom-page", "access-custom-pages", "access-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-zone-custom-pages", "access-zone-custom-page", "access-custom-pages", "access-custom-page" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-custom-pages", "access-zone-custom-pages", "access-custom-pages", "access-custom-page" });
}

fn actualCaptureCloudflareAccessIdentityProviderIdHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access identity providers") and !containsIgnoreCase(route.tag, "Access SCIM update")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-identity-providers", "access-account-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-zone-identity-providers", "access-zone-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-identity-providers", "access-zone-identity-providers", "access-identity-providers", "access-identity-provider" });
}

fn actualCaptureCloudflareTokenIdHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens" });
    }
    if (actualCaptureRoutePathContains(route, "/user/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user-tokens", "user-api-tokens" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens", "user-tokens", "user-api-tokens" });
}

fn actualCaptureCloudflareResourceIdHint(route: provider_routes.Route, hints: ActualCaptureHints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_id;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    return null;
}

fn actualCaptureCloudflareResourceTypeHint(route: provider_routes.Route, hints: ActualCaptureHints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_type.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_type;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.category.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.category;
    }
    return null;
}

fn actualCaptureCloudflareResourceMatchesRouteScope(route: provider_routes.Route, hints: ActualCaptureHints, scope: []const u8, scope_id: []const u8) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    if (!account_scoped and !zone_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(scope, "account") and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareInventoryMatchesRouteScope(route: provider_routes.Route, hints: ActualCaptureHints, row: db_store.CloudflareInventoryHintRow) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    if (!account_scoped and !zone_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(row.account_id, account_id)) return true;
            if (eqlIgnoreCase(row.scope, "account") and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(row.zone_id, zone_id)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareRouteAccountScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/accounts/");
}

fn actualCaptureCloudflareRouteZoneScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/zones/");
}

fn actualCaptureRoutePathContains(route: provider_routes.Route, needle: []const u8) bool {
    return std.mem.indexOf(u8, route.path_template, needle) != null;
}

fn actualCaptureScopeIdHasParent(scope_id: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(scope_id, parent)) return true;
    if (scope_id.len <= parent.len) return false;
    if (scope_id[parent.len] != '/') return false;
    return eqlIgnoreCase(scope_id[0..parent.len], parent);
}

fn actualCaptureKindIn(kind: []const u8, kinds: []const []const u8) bool {
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
}

fn actualCaptureHostingerPathParamHint(route: provider_routes.Route, name: []const u8, hints: ActualCaptureHints) ?[]const u8 {
    if (std.mem.eql(u8, name, "virtualMachineId") and hints.hostinger_vps.len != 0) return hints.hostinger_vps[0].id;
    if (std.mem.eql(u8, name, "domain")) return actualCaptureHostingerDomainHint(route, hints);
    if (std.mem.eql(u8, name, "username")) return actualCaptureHostingerUsernameHint(route, hints);
    if (std.mem.eql(u8, name, "actionId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getActionDetailsV1", "VPS_getActionsV1");
    if (std.mem.eql(u8, name, "templateId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getTemplateDetailsV1", "VPS_getTemplatesV1");
    if (std.mem.eql(u8, name, "postInstallScriptId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getPostInstallScriptV1", "VPS_getPostInstallScriptsV1");
    if (std.mem.eql(u8, name, "firewallId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getFirewallDetailsV1", "VPS_getFirewallListV1");
    if (std.mem.eql(u8, name, "snapshotId")) return actualCaptureHostingerResourceHint(route, hints, "DNS_getDNSSnapshotV1", "DNS_getDNSSnapshotListV1");
    if (std.mem.eql(u8, name, "whoisId")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "domains_getWHOISProfileV1", "domains_getWHOISProfileUsageV1" }, "domains_getWHOISProfileListV1");
    if (std.mem.eql(u8, name, "websiteId")) return actualCaptureHostingerResourceHint(route, hints, "horizons_getWebsiteV1", "horizons_getWebsitesV1");
    if (std.mem.eql(u8, name, "name")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getPhpMyAdminLinkV1", "hosting_listAccountDatabasesV1");
    if (std.mem.eql(u8, name, "uuid")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getNodeJSBuildLogsV1", "hosting_listNodeJSBuildsV1");
    if (std.mem.eql(u8, name, "projectName")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "VPS_getProjectContentsV1", "VPS_getProjectContainersV1", "VPS_getProjectLogsV1" }, "VPS_getProjectListV1");
    if (std.mem.eql(u8, name, "profileUuid")) return actualCaptureHostingerResourceHint(route, hints, "reach_listProfileSegmentContactsV1", "reach_listProfilesV1");
    if (std.mem.eql(u8, name, "segmentUuid")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "reach_getSegmentDetailsV1", "reach_listSegmentContactsV1", "reach_listProfileSegmentContactsV1" }, "reach_listSegmentsV1");
    return null;
}

fn actualCaptureHostingerResourceHint(route: provider_routes.Route, hints: ActualCaptureHints, detail_operation_id: []const u8, list_kind: []const u8) ?[]const u8 {
    if (route.operation_id == null or !std.mem.eql(u8, route.operation_id.?, detail_operation_id)) return null;
    return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
}

fn actualCaptureHostingerResourceHintForAny(route: provider_routes.Route, hints: ActualCaptureHints, detail_operation_ids: []const []const u8, list_kind: []const u8) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    for (detail_operation_ids) |detail_operation_id| {
        if (std.mem.eql(u8, operation_id, detail_operation_id)) return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
    }
    return null;
}

fn actualCaptureHostingerScopedResourceKindHint(route: provider_routes.Route, hints: ActualCaptureHints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerResourceMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    if (!actualCaptureHostingerUnscopedFallbackAllowed(route, hints, list_kind)) return null;
    return actualCaptureHostingerResourceKindHint(hints, list_kind);
}

fn actualCaptureHostingerResourceKindHint(hints: ActualCaptureHints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerResourceMatchesRouteScope(route: provider_routes.Route, hints: ActualCaptureHints, row: db_store.HostingerResourceHintRow) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        const vm_id = actualCaptureHostingerVpsIdHint(hints) orelse return false;
        return actualCaptureHostingerTargetHasParent(row.target, vm_id);
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerInventoryMatchesRouteScope(route: provider_routes.Route, hints: ActualCaptureHints, row: db_store.HostingerInventoryHintRow) bool {
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (eqlIgnoreCase(row.username, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.display_name, domain)) return true;
            if (eqlIgnoreCase(row.resource_id, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerUnscopedFallbackAllowed(route: provider_routes.Route, hints: ActualCaptureHints, list_kind: []const u8) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        if (actualCaptureHostingerVpsIdHint(hints)) |vm_id| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, vm_id)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0 or row.username.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.username, username)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len != 0) {
                    saw_scoped_row = true;
                    if (eqlIgnoreCase(row.domain, domain)) return true;
                }
                if (!actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) {
                    saw_scoped_row = true;
                    if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
                }
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len == 0 and row.display_name.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.display_name, domain)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    return true;
}

fn actualCaptureHostingerDomainHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    _ = route;
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.hostinger_inventory) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.display_name)) return row.display_name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    for (hints.hostinger_resources) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerUsernameHint(route: provider_routes.Route, hints: ActualCaptureHints) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    if (!containsIgnoreCase(operation_id, "hosting_")) return null;
    if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
        for (hints.hostinger_inventory) |row| {
            if (row.username.len == 0) continue;
            if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.resource_id, domain) or eqlIgnoreCase(row.display_name, domain)) return row.username;
        }
    }
    for (hints.hostinger_inventory) |row| {
        if (row.username.len != 0) return row.username;
    }
    return null;
}

fn actualCaptureHostingerOrderIdHint(hints: ActualCaptureHints) ?[]const u8 {
    if (actualCaptureHostingerResourceKindHint(hints, "hosting_listOrdersV1")) |value| return value;
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, "hosting_listWebsitesV1") and row.related_id.len != 0) return row.related_id;
    }
    return null;
}

fn actualCaptureHostingerKindCanCarryDomain(kind: []const u8) bool {
    return std.mem.startsWith(u8, kind, "DNS_") or
        std.mem.startsWith(u8, kind, "domains_") or
        std.mem.startsWith(u8, kind, "hosting_") or
        std.mem.startsWith(u8, kind, "horizons_") or
        containsIgnoreCase(kind, "domain") or
        containsIgnoreCase(kind, "website") or
        containsIgnoreCase(kind, "wordpress");
}

fn actualCaptureHostingerVpsIdHint(hints: ActualCaptureHints) ?[]const u8 {
    if (hints.hostinger_vps.len != 0 and hints.hostinger_vps[0].id.len != 0) return hints.hostinger_vps[0].id;
    return actualCaptureHostingerResourceKindHint(hints, "VPS_getVirtualMachinesV1") orelse
        actualCaptureHostingerResourceKindHint(hints, "vps") orelse
        actualCaptureHostingerResourceKindHint(hints, "route-hostinger-vps");
}

fn actualCaptureHostingerRouteNeedsVps(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{virtualMachineId}");
}

fn actualCaptureHostingerRouteNeedsUsername(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{username}");
}

fn actualCaptureHostingerRouteNeedsDomain(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{domain}");
}

fn actualCaptureHostingerTargetHasParent(target: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(target, parent)) return true;
    if (target.len <= parent.len) return false;
    if (target[parent.len] != '/') return false;
    return eqlIgnoreCase(target[0..parent.len], parent);
}

fn actualCaptureHostingerTargetLooksUnscoped(target: []const u8, list_kind: []const u8) bool {
    return target.len == 0 or eqlIgnoreCase(target, list_kind);
}

fn actualCaptureLooksLikeDomain(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.endsWith(u8, value, ".hstgr.cloud")) return false;
    if (value[0] == '.' or value[value.len - 1] == '.') return false;
    if (std.mem.indexOfScalar(u8, value, '.') == null) return false;
    for (value) |byte| {
        if (byte == '/' or byte == ':' or byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') return false;
    }
    return true;
}

fn actualCaptureHasQueryParamHint(route: provider_routes.Route, name: []const u8, hints: ActualCaptureHints) bool {
    if (route.provider != .hostinger or route.operation_id == null) return false;
    if (std.mem.eql(u8, route.operation_id.?, "VPS_getMetricsV1") and
        (std.mem.eql(u8, name, "date_from") or std.mem.eql(u8, name, "date_to")))
    {
        return true;
    }
    return std.mem.eql(u8, route.operation_id.?, "hosting_listAvailableDatacentersV1") and
        std.mem.eql(u8, name, "order_id") and
        actualCaptureHostingerOrderIdHint(hints) != null;
}

fn actualCaptureQueryParamHint(gpa: Allocator, route: provider_routes.Route, name: []const u8, hints: ActualCaptureHints) !?[]u8 {
    if (!actualCaptureHasQueryParamHint(route, name, hints)) return null;
    if (std.mem.eql(u8, route.operation_id.?, "hosting_listAvailableDatacentersV1") and std.mem.eql(u8, name, "order_id")) {
        if (actualCaptureHostingerOrderIdHint(hints)) |order_id| return try gpa.dupe(u8, order_id);
        return null;
    }
    const now = core_time.currentEpochSeconds() catch return null;
    const day: u64 = 24 * 60 * 60;
    const timestamp = if (std.mem.eql(u8, name, "date_from") and now > day) now - day else now;
    var buf: [17]u8 = undefined;
    const formatted = try core_time.formatUtcMinute(&buf, timestamp);
    return try gpa.dupe(u8, formatted);
}

fn writeActualMissingInputsText(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    var wrote = false;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("path:{s}", .{param.name});
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("query:{s}", .{param.name});
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("header:{s}", .{param.name});
    }
    if (!wrote) try writer.writeAll("-");
}

fn writeActualMissingInputsJson(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    try writer.writeByte('[');
    var first = true;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "path", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "query", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "header", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeActualMissingInputSourcesText(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !void {
    var wrote = false;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "path", param.name, &wrote);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "query", param.name, &wrote);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "header", param.name, &wrote);
    }
    if (!wrote) try writer.writeAll("      source: -\n");
}

fn actualCaptureSummarizeMissingInputSources(
    gpa: Allocator,
    summary: *ActualCaptureSourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "path", param.name);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "query", param.name);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "header", param.name);
    }
}

fn actualCaptureSummarizeMissingInputSourceRows(
    gpa: Allocator,
    summary: *ActualCaptureSourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        actualCaptureAddSourceSummary(summary, actualCaptureUnmappedSourceResult(route, input_source, input_name), .{});
        return;
    }
    for (sources) |source| {
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
        const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
        const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
        const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
        actualCaptureAddSourceSummary(summary, actualCaptureSourceResult(source_route, source_state, hints, hint_count, body), body);
    }
}

fn actualCaptureAddSourceSummary(summary: *ActualCaptureSourceSummary, result: []const u8, body: ActualCaptureSourceBodyEvidence) void {
    summary.total_sources += 1;
    if (std.mem.eql(u8, result, "captured_with_hints")) {
        summary.captured_with_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_empty")) {
        summary.captured_empty += 1;
    } else if (std.mem.eql(u8, result, "captured_without_hints")) {
        summary.captured_without_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_unknown_body")) {
        summary.captured_unknown_body += 1;
    } else if (std.mem.eql(u8, result, "ready_to_capture")) {
        summary.ready_to_capture += 1;
    } else if (std.mem.eql(u8, result, "waiting_for_inputs")) {
        summary.waiting_for_inputs += 1;
    } else if (std.mem.eql(u8, result, "diagnostic_blocked")) {
        summary.diagnostic_blocked += 1;
    } else if (std.mem.eql(u8, result, "captured_error")) {
        summary.captured_error += 1;
    } else if (std.mem.eql(u8, result, "no_official_source")) {
        summary.no_official_source += 1;
    } else if (std.mem.eql(u8, result, "not_in_catalog")) {
        summary.not_in_catalog += 1;
    } else if (std.mem.eql(u8, result, "unmapped")) {
        summary.unmapped += 1;
    } else if (std.mem.eql(u8, result, "not_eligible")) {
        summary.not_eligible += 1;
    }

    if (std.mem.eql(u8, body.shape, "array")) {
        summary.body_array += 1;
    } else if (std.mem.eql(u8, body.shape, "data_array")) {
        summary.body_data_array += 1;
    } else if (std.mem.eql(u8, body.shape, "error_object")) {
        summary.body_error_object += 1;
    } else if (std.mem.eql(u8, body.shape, "no_evidence")) {
        summary.body_no_evidence += 1;
    } else {
        summary.body_other += 1;
    }
}

fn writeActualMissingInputSourceRowsText(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    wrote: *bool,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        wrote.* = true;
        const result = actualCaptureUnmappedSourceResult(route, input_source, input_name);
        try writer.print("      source: {s}:{s} <- {s} result={s} evidence=no_evidence items=- bytes=0 next=\"{s}\" purpose=", .{
            input_source,
            input_name,
            result,
            result,
            actualCaptureUnmappedSourceNextAction(route, input_source, input_name),
        });
        try writer.writeAll(actualCaptureUnmappedSourcePurpose(route, input_source, input_name));
        try writer.writeByte('\n');
        return;
    }
    for (sources) |source| {
        wrote.* = true;
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        if (source_route) |found| {
            const source_state = actualCaptureState(found, captures);
            const command = try actualCaptureCommand(gpa, found, hints);
            defer gpa.free(command);
            const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
            const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
            const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
            try writer.print("      source: {s}:{s} <- {s} state={s} result={s} ready={s} diagnostic_ready={s} hint_count={d} evidence={s} items=", .{
                input_source,
                input_name,
                source.operation_id,
                if (source_state) |state| state.name() else "unknown",
                actualCaptureSourceResult(found, source_state, hints, hint_count, body),
                if (actualCaptureReady(found, hints)) "true" else "false",
                if (actualCaptureReadyWithPolicy(found, hints, true)) "true" else "false",
                hint_count,
                body.shape,
            });
            if (body.item_count) |count| try writer.print("{d}", .{count}) else try writer.writeAll("-");
            try writer.print(" bytes={d} next=\"{s}\" capture: {s}\n", .{
                body.body_bytes,
                actualCaptureSourceNextAction(found, source_state, hints, hint_count, body),
                command,
            });
        } else {
            const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
            const body = ActualCaptureSourceBodyEvidence{};
            try writer.print("      source: {s}:{s} <- {s} state=not_in_catalog result=not_in_catalog hint_kind={s} hint_count={d} evidence={s} items=- bytes=0 next=\"{s}\" purpose=", .{
                input_source,
                input_name,
                source.operation_id,
                source.hint_kind,
                hint_count,
                body.shape,
                actualCaptureSourceNextAction(null, null, hints, hint_count, body),
            });
            try writer.writeAll(source.purpose);
            try writer.writeByte('\n');
        }
    }
}

fn writeActualMissingInputSourcesJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !void {
    try writer.writeByte('[');
    var first = true;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "path", param.name, &first);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "query", param.name, &first);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "header", param.name, &first);
    }
    try writer.writeByte(']');
}

fn writeActualMissingInputSourceRowsJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    first: *bool,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        const result = actualCaptureUnmappedSourceResult(route, input_source, input_name);
        try writeMaybeJsonComma(writer, first);
        try writer.writeByte('{');
        try writeJsonField(writer, "input_source", input_source, true);
        try writeJsonField(writer, "input_name", input_name, true);
        try writeJsonNullableStringField(writer, "source_operation_id", null, true);
        try writeJsonNullableStringField(writer, "hint_kind", null, true);
        try writeJsonCountField(writer, "hint_count", 0, true);
        try writeJsonField(writer, "result", result, true);
        try writeJsonField(writer, "next_action", actualCaptureUnmappedSourceNextAction(route, input_source, input_name), true);
        try writeJsonNullableStringField(writer, "source_status", null, true);
        try writeJsonNullableStringField(writer, "source_target", null, true);
        try writeJsonNullableStringField(writer, "source_captured_at", null, true);
        try writeJsonField(writer, "body_shape", "no_evidence", true);
        try writeJsonNullableCountField(writer, "body_item_count", null, true);
        try writeJsonCountField(writer, "body_bytes", 0, true);
        try writeJsonField(writer, "purpose", actualCaptureUnmappedSourcePurpose(route, input_source, input_name), true);
        try writeJsonField(writer, "catalog_state", result, true);
        try writeJsonNullableStringField(writer, "actual_state", null, true);
        try writeJsonNullableBoolField(writer, "ready", null, true);
        try writeJsonNullableBoolField(writer, "diagnostic_ready", null, true);
        try writeJsonNullableBoolField(writer, "live_read_supported", null, true);
        try writeJsonNullableBoolField(writer, "diagnostic_read_supported", null, true);
        try writeJsonNullableStringField(writer, "capture_command", null, false);
        try writer.writeByte('}');
        return;
    }

    for (sources) |source| {
        try writeMaybeJsonComma(writer, first);
        try writeActualMissingInputSourceJson(gpa, writer, route, routes, captures, source_evidence, hints, input_source, input_name, source);
    }
}

fn writeActualMissingInputSourceJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    source: ActualCaptureInputSource,
) !void {
    const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
    var command: ?[]u8 = null;
    defer if (command) |owned| gpa.free(owned);
    if (source_route) |found| command = try actualCaptureCommand(gpa, found, hints);
    const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
    const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
    const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
    const body = try actualCaptureSourceBodyEvidence(gpa, evidence);

    try writer.writeByte('{');
    try writeJsonField(writer, "input_source", input_source, true);
    try writeJsonField(writer, "input_name", input_name, true);
    try writeJsonNullableStringField(writer, "source_operation_id", source.operation_id, true);
    try writeJsonNullableStringField(writer, "hint_kind", source.hint_kind, true);
    try writeJsonCountField(writer, "hint_count", hint_count, true);
    try writeJsonField(writer, "result", actualCaptureSourceResult(source_route, source_state, hints, hint_count, body), true);
    try writeJsonField(writer, "next_action", actualCaptureSourceNextAction(source_route, source_state, hints, hint_count, body), true);
    try writeJsonNullableStringField(writer, "source_status", if (evidence) |row| row.status else null, true);
    try writeJsonNullableStringField(writer, "source_target", if (evidence) |row| row.target else null, true);
    try writeJsonNullableStringField(writer, "source_captured_at", if (evidence) |row| row.captured_at else null, true);
    try writeJsonField(writer, "body_shape", body.shape, true);
    try writeJsonNullableCountField(writer, "body_item_count", body.item_count, true);
    try writeJsonCountField(writer, "body_bytes", body.body_bytes, true);
    try writeJsonField(writer, "purpose", source.purpose, true);
    try writeJsonField(writer, "catalog_state", if (source_route != null) "present" else "not_in_catalog", true);
    try writeJsonNullableStringField(writer, "actual_state", if (source_state) |state| state.name() else null, true);
    try writeJsonNullableBoolField(writer, "ready", if (source_route) |found| actualCaptureReady(found, hints) else null, true);
    try writeJsonNullableBoolField(writer, "diagnostic_ready", if (source_route) |found| actualCaptureReadyWithPolicy(found, hints, true) else null, true);
    try writeJsonNullableBoolField(writer, "live_read_supported", if (source_route) |found| provider_dispatch.routeLiveCallSupported(found) else null, true);
    try writeJsonNullableBoolField(writer, "diagnostic_read_supported", if (source_route) |found| provider_dispatch.routeDiagnosticReadSupported(found) else null, true);
    try writeJsonNullableStringField(writer, "capture_command", command, false);
    try writer.writeByte('}');
}

fn actualCaptureFindRouteByOperationId(routes: []const CoverageRoute, provider: provider_routes.Provider, operation_id: []const u8) ?provider_routes.Route {
    for (routes) |row| {
        if (row.route.provider != provider) continue;
        if (row.route.operation_id == null) continue;
        if (std.mem.eql(u8, row.route.operation_id.?, operation_id)) return row.route;
    }
    return null;
}

fn actualCaptureUnmappedSourceResult(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "no_official_source";
    return "unmapped";
}

fn actualCaptureUnmappedSourceNextAction(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "provide the identifier through config or another collected official surface";
    return "add a source mapping before this input can be planned";
}

fn actualCaptureUnmappedSourcePurpose(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "current Hostinger OpenAPI exposes only the Horizons website detail route, not a list route";
    return "no source mapping";
}

fn actualCaptureHostingerNoOfficialSource(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) bool {
    if (route.provider != .hostinger) return false;
    const operation_id = route.operation_id orelse return false;
    return std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "websiteId") and
        std.mem.eql(u8, operation_id, "horizons_getWebsiteV1");
}

fn actualCaptureFindSourceEvidence(source_evidence: []const db_store.RouteSourceEvidenceRow, provider: []const u8, operation_id: []const u8) ?db_store.RouteSourceEvidenceRow {
    for (source_evidence) |row| {
        if (!std.mem.eql(u8, row.provider, provider)) continue;
        if (!std.mem.eql(u8, row.operation_id, operation_id)) continue;
        return row;
    }
    return null;
}

fn actualCaptureSourceBodyEvidence(gpa: Allocator, evidence: ?db_store.RouteSourceEvidenceRow) !ActualCaptureSourceBodyEvidence {
    const row = evidence orelse return .{};
    if (row.raw_json.len == 0) return .{ .shape = "no_body" };
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, row.raw_json, .{}) catch return .{
        .shape = "invalid_json",
        .body_bytes = row.raw_json.len,
    };
    defer parsed.deinit();
    return actualCaptureSourceBodyEvidenceFromValue(parsed.value, row.raw_json.len);
}

fn actualCaptureSourceBodyEvidenceFromValue(value: std.json.Value, body_bytes: usize) ActualCaptureSourceBodyEvidence {
    return switch (value) {
        .array => |array| .{ .shape = "array", .item_count = array.items.len, .body_bytes = body_bytes },
        .object => |object| blk: {
            if (object.get("data")) |data| {
                break :blk switch (data) {
                    .array => |array| .{ .shape = "data_array", .item_count = array.items.len, .body_bytes = body_bytes },
                    .object => .{ .shape = "data_object", .item_count = 1, .body_bytes = body_bytes },
                    else => .{ .shape = "data_scalar", .body_bytes = body_bytes },
                };
            }
            if (object.get("message") != null or object.get("error") != null) {
                break :blk .{ .shape = "error_object", .body_bytes = body_bytes };
            }
            break :blk .{ .shape = "object", .item_count = 1, .body_bytes = body_bytes };
        },
        else => .{ .shape = "scalar", .body_bytes = body_bytes },
    };
}

fn actualCaptureSourceBodyIsEmptyCollection(body: ActualCaptureSourceBodyEvidence) bool {
    if (body.item_count == null or body.item_count.? != 0) return false;
    return std.mem.eql(u8, body.shape, "array") or std.mem.eql(u8, body.shape, "data_array");
}

fn actualCaptureSourceBodyHasItems(body: ActualCaptureSourceBodyEvidence) bool {
    if (body.item_count) |count| return count > 0;
    return false;
}

fn actualCaptureSourceResult(route: ?provider_routes.Route, state: ?ActualCaptureState, hints: ActualCaptureHints, hint_count: usize, body: ActualCaptureSourceBodyEvidence) []const u8 {
    const source_route = route orelse return "not_in_catalog";
    const source_state = state orelse return "not_eligible";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "captured_with_hints"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "captured_empty"
        else if (actualCaptureSourceBodyHasItems(body))
            "captured_without_hints"
        else
            "captured_unknown_body",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true)) "ready_to_capture" else "waiting_for_inputs",
        .non_ok => if (!provider_dispatch.routeLiveCallSupported(source_route) and provider_dispatch.routeDiagnosticReadSupported(source_route)) "diagnostic_blocked" else "captured_error",
    };
}

fn actualCaptureSourceNextAction(route: ?provider_routes.Route, state: ?ActualCaptureState, hints: ActualCaptureHints, hint_count: usize, body: ActualCaptureSourceBodyEvidence) []const u8 {
    const source_route = route orelse return "update the route catalog or remove the stale hint mapping";
    const source_state = state orelse return "source route is not an eligible read route";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "use collected identifiers for child captures"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "source collection is empty; no child identifiers are available"
        else if (actualCaptureSourceBodyHasItems(body))
            "extend normalization for this non-empty source response"
        else
            "inspect raw source evidence; body shape does not prove an empty collection",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true))
            "capture the source route to discover identifiers"
        else
            "capture the source route prerequisites first",
        .non_ok => if (!provider_dispatch.routeLiveCallSupported(source_route) and provider_dispatch.routeDiagnosticReadSupported(source_route))
            "diagnostic-only source is blocked; child identifiers are unavailable"
        else
            "inspect source capture error before child captures",
    };
}

fn actualCaptureSourceHintCount(
    route: provider_routes.Route,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    source: ActualCaptureInputSource,
) usize {
    if (route.provider != .hostinger) return 0;
    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) {
            var count = hints.configured_domains.len;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.display_name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            return count;
        }
        if (std.mem.eql(u8, input_name, "virtualMachineId")) {
            var count = hints.hostinger_vps.len;
            count += actualCaptureHostingerKindHintCount(hints, source.hint_kind);
            return count;
        }
        if (std.mem.eql(u8, input_name, "username")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.username.len != 0) count += 1;
            }
            return count;
        }
    }

    if (std.mem.eql(u8, input_source, "query") and std.mem.eql(u8, input_name, "order_id")) {
        if (std.mem.eql(u8, source.hint_kind, "hosting_listWebsitesV1")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.related_id.len != 0) count += 1;
            }
            return count;
        }
    }

    return actualCaptureHostingerKindHintCount(hints, source.hint_kind);
}

fn actualCaptureHostingerKindHintCount(hints: ActualCaptureHints, kind: []const u8) usize {
    var count: usize = 0;
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    return count;
}

fn actualCaptureMissingInputSources(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const ActualCaptureInputSource {
    if (route.provider != .hostinger) return &.{};
    const operation_id = route.operation_id orelse return &.{};

    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) return hostinger_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "virtualMachineId")) return hostinger_vps_sources[0..];
        if (std.mem.eql(u8, input_name, "actionId")) return hostinger_action_sources[0..];
        if (std.mem.eql(u8, input_name, "templateId")) return hostinger_template_sources[0..];
        if (std.mem.eql(u8, input_name, "firewallId")) return hostinger_firewall_sources[0..];
        if (std.mem.eql(u8, input_name, "postInstallScriptId")) return hostinger_post_install_sources[0..];
        if (std.mem.eql(u8, input_name, "snapshotId") and std.mem.eql(u8, operation_id, "DNS_getDNSSnapshotV1")) return hostinger_dns_snapshot_sources[0..];
        if (std.mem.eql(u8, input_name, "whoisId") and (std.mem.eql(u8, operation_id, "domains_getWHOISProfileV1") or std.mem.eql(u8, operation_id, "domains_getWHOISProfileUsageV1"))) return hostinger_whois_sources[0..];
        if (std.mem.eql(u8, input_name, "username") and std.mem.startsWith(u8, operation_id, "hosting_")) return hostinger_username_sources[0..];
        if (std.mem.eql(u8, input_name, "name") and std.mem.eql(u8, operation_id, "hosting_getPhpMyAdminLinkV1")) return hostinger_database_sources[0..];
        if (std.mem.eql(u8, input_name, "uuid") and std.mem.eql(u8, operation_id, "hosting_getNodeJSBuildLogsV1")) return hostinger_nodejs_build_sources[0..];
        if (std.mem.eql(u8, input_name, "projectName") and std.mem.startsWith(u8, operation_id, "VPS_getProject")) return hostinger_docker_project_sources[0..];
        if (std.mem.eql(u8, input_name, "profileUuid") and std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1")) return hostinger_reach_profile_sources[0..];
        if (std.mem.eql(u8, input_name, "segmentUuid") and (std.mem.eql(u8, operation_id, "reach_getSegmentDetailsV1") or std.mem.eql(u8, operation_id, "reach_listSegmentContactsV1") or std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1"))) return hostinger_reach_segment_sources[0..];
    }

    if (std.mem.eql(u8, input_source, "query")) {
        if (std.mem.eql(u8, input_name, "order_id") and std.mem.eql(u8, operation_id, "hosting_listAvailableDatacentersV1")) return hostinger_order_sources[0..];
    }

    return &.{};
}

fn writeActualCaptureTotalsJson(totals_value: ActualCaptureTotals, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "official_read_routes", totals_value.official_read_routes, true);
    try writeJsonCountField(writer, "ok_read_routes", totals_value.ok_read_routes, true);
    try writeJsonCountField(writer, "non_ok_read_routes", totals_value.non_ok_read_routes, true);
    try writeJsonCountField(writer, "missing_read_routes", totals_value.missing_read_routes, true);
    try writeJsonCountField(writer, "candidate_routes", totals_value.candidate_routes, true);
    try writeJsonCountField(writer, "ready_candidates", totals_value.ready_candidates, true);
    try core_json.writeString(writer, "capture_events");
    try writer.print(":{d}", .{totals_value.capture_events});
    try writer.writeByte('}');
}

fn writeActualCaptureSourceSummaryJson(summary: ActualCaptureSourceSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "total_sources", summary.total_sources, true);
    try writeJsonCountField(writer, "captured_with_hints", summary.captured_with_hints, true);
    try writeJsonCountField(writer, "captured_empty", summary.captured_empty, true);
    try writeJsonCountField(writer, "captured_without_hints", summary.captured_without_hints, true);
    try writeJsonCountField(writer, "captured_unknown_body", summary.captured_unknown_body, true);
    try writeJsonCountField(writer, "ready_to_capture", summary.ready_to_capture, true);
    try writeJsonCountField(writer, "waiting_for_inputs", summary.waiting_for_inputs, true);
    try writeJsonCountField(writer, "diagnostic_blocked", summary.diagnostic_blocked, true);
    try writeJsonCountField(writer, "captured_error", summary.captured_error, true);
    try writeJsonCountField(writer, "no_official_source", summary.no_official_source, true);
    try writeJsonCountField(writer, "not_in_catalog", summary.not_in_catalog, true);
    try writeJsonCountField(writer, "unmapped", summary.unmapped, true);
    try writeJsonCountField(writer, "not_eligible", summary.not_eligible, true);
    try writer.writeAll("\"body_shapes\":{");
    try writeJsonCountField(writer, "array", summary.body_array, true);
    try writeJsonCountField(writer, "data_array", summary.body_data_array, true);
    try writeJsonCountField(writer, "error_object", summary.body_error_object, true);
    try writeJsonCountField(writer, "no_evidence", summary.body_no_evidence, true);
    try writeJsonCountField(writer, "other", summary.body_other, false);
    try writer.writeAll("}}");
}

fn writeActualCaptureCandidateJson(
    gpa: Allocator,
    row: CoverageRoute,
    state: ActualCaptureState,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    options: ActualCaptureOptions,
    writer: anytype,
) !void {
    const route = row.route;
    const command = try actualCaptureCommand(gpa, route, hints);
    defer gpa.free(command);
    const status = actualRouteCaptureStatus(route.provider.name(), route.operation_id.?, captures);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonField(writer, "operation_id", route.operation_id.?, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "actual_state", state.name(), true);
    try writeJsonCountField(writer, "capture_events", @intCast(@max(status.events, 0)), true);
    try writeJsonNullableStringField(writer, "latest_capture_at", if (status.latest_at.len == 0) null else status.latest_at, true);
    try writeJsonNullableStringField(writer, "pagination", routePaginationKind(route), true);
    try writer.writeAll("\"required_path_params\":");
    try writeRequiredParamNamesJson(writer, route.path_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_query_params\":");
    try writeRequiredParamNamesJson(writer, route.query_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_header_params\":");
    try writeRequiredParamNamesJson(writer, route.header_params);
    try writer.writeByte(',');
    try writeJsonBoolField(writer, "ready", actualCaptureReady(route, hints), true);
    try writeJsonBoolField(writer, "live_read_supported", provider_dispatch.routeLiveCallSupported(route), true);
    try writeJsonBoolField(writer, "diagnostic_read_supported", provider_dispatch.routeDiagnosticReadSupported(route), true);
    try writer.writeAll("\"missing_inputs\":");
    try writeActualMissingInputsJson(writer, route, hints);
    try writer.writeByte(',');
    try writer.writeAll("\"missing_input_sources\":");
    try writeActualMissingInputSourcesJson(gpa, writer, route, routes, captures, source_evidence, hints);
    try writer.writeByte(',');
    try writeJsonField(writer, "capture_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try routeReadPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"read_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

fn actualCaptureCommand(gpa: Allocator, route: provider_routes.Route, hints: ActualCaptureHints) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route capture {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path ", .{route.method.name()});
        try writeShellArg(writer, route.path_template);
    }
    try writeActualPathParams(writer, route, hints);
    try writeActualQueryParams(gpa, writer, route, hints);
    try writeActualRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (routePaginationKind(route) != null) try writer.writeAll(" --paginate");
    if (provider_dispatch.routeDiagnosticReadSupported(route)) try writer.writeAll(" --diagnostic");
    return try out.toOwnedSlice();
}

fn writeActualPathParams(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        try writer.print(" --path-param {s}=", .{param.name});
        if (actualCapturePathParamHint(route, param.name, hints)) |hint| {
            try writeShellArg(writer, hint);
        } else {
            try writer.print("REPLACE_{s}", .{param.name});
        }
    }
}

fn writeActualQueryParams(gpa: Allocator, writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    for (route.query_params) |param| {
        if (!param.required) continue;
        try writer.print(" --query-param {s}=", .{param.name});
        if (try actualCaptureQueryParamHint(gpa, route, param.name, hints)) |hint| {
            defer gpa.free(hint);
            try writeShellArg(writer, hint);
        } else {
            try writer.print("REPLACE_{s}", .{param.name});
        }
    }
}

fn writeActualRequiredParamPlaceholders(writer: anytype, option: []const u8, params: []const provider_routes.RouteParam) !void {
    for (params) |param| {
        if (!param.required) continue;
        try writer.print(" {s} {s}=REPLACE_{s}", .{ option, param.name, param.name });
    }
}

const ActualReadyCaptureSummary = struct {
    candidate_routes: usize = 0,
    ready_routes: usize = 0,
    skipped_unready: usize = 0,
    skipped_non_diagnostic: usize = 0,
    omitted_ready: usize = 0,
    planned: usize = 0,
    attempted: usize = 0,
    captured: usize = 0,
    failed: usize = 0,
};

const ActualReadyRequest = struct {
    request: Request,
    path_params: []PathParam,
    query_params: []QueryParam,
    query_values: [][]u8,

    fn deinit(self: ActualReadyRequest, gpa: Allocator) void {
        for (self.query_values) |value| gpa.free(value);
        gpa.free(self.query_values);
        gpa.free(self.query_params);
        gpa.free(self.path_params);
    }
};

fn validateActualReadyCaptureProvider(auth: Auth, provider: ProviderFilter) !void {
    if (provider == .all) return error.ActualReadyCaptureProviderRequired;
    if (!provider.includes(auth.provider().name())) return error.ProviderRouteAuthMismatch;
}

fn actualReadyCaptureJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, plan: ActualCapturePlan, options: ActualReadyCaptureOptions) ![]u8 {
    const hints = plan.hints();
    var summary = ActualReadyCaptureSummary{};
    var items_out = std.Io.Writer.Allocating.init(gpa);
    defer items_out.deinit();
    const items_writer = &items_out.writer;
    try items_writer.writeByte('[');
    var first = true;

    for (plan.routes.items) |row| {
        const state = actualCaptureState(row.route, plan.captures.items) orelse continue;
        if (state == .ok) continue;
        summary.candidate_routes += 1;
        if (!actualCaptureReadyWithPolicy(row.route, hints, options.include_blocked)) {
            summary.skipped_unready += 1;
            continue;
        }
        summary.ready_routes += 1;
        if (options.diagnostic_only and !actualCaptureUsesDiagnosticRead(row.route, options.include_blocked)) {
            summary.skipped_non_diagnostic += 1;
            continue;
        }
        if (options.limit != 0 and summary.planned + summary.attempted >= options.limit) {
            summary.omitted_ready += 1;
            continue;
        }
        try writeMaybeJsonComma(items_writer, &first);
        if (options.execute) {
            summary.attempted += 1;
        } else {
            summary.planned += 1;
        }
        try writeActualReadyCaptureItemJson(io, gpa, db, auth, row.route, state, hints, options, &summary, items_writer);
    }

    try items_writer.writeByte(']');
    const items_json = try items_out.toOwnedSlice();
    defer gpa.free(items_json);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "actual_ready_capture_run", true);
    try writeJsonBoolField(writer, "execute", options.execute, true);
    try writeJsonBoolField(writer, "include_blocked", options.include_blocked, true);
    try writeJsonBoolField(writer, "diagnostic_only", options.diagnostic_only, true);
    try writer.writeAll("\"filter\":");
    try writeRouteFilterJson(actualCaptureRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonCountField(writer, "max_pages", options.max_pages, true);
    try writer.writeAll("\"summary\":");
    try writeActualReadyCaptureSummaryJson(summary, writer);
    try writer.writeAll(",\"items\":");
    try writer.writeAll(items_json);
    try writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn writeActualReadyCaptureSummaryJson(summary: ActualReadyCaptureSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "candidate_routes", summary.candidate_routes, true);
    try writeJsonCountField(writer, "ready_routes", summary.ready_routes, true);
    try writeJsonCountField(writer, "skipped_unready", summary.skipped_unready, true);
    try writeJsonCountField(writer, "skipped_non_diagnostic", summary.skipped_non_diagnostic, true);
    try writeJsonCountField(writer, "omitted_ready", summary.omitted_ready, true);
    try writeJsonCountField(writer, "planned", summary.planned, true);
    try writeJsonCountField(writer, "attempted", summary.attempted, true);
    try writeJsonCountField(writer, "captured", summary.captured, true);
    try writeJsonCountField(writer, "failed", summary.failed, false);
    try writer.writeByte('}');
}

fn writeActualReadyCaptureItemJson(
    io: Io,
    gpa: Allocator,
    db: *Db,
    auth: Auth,
    route: provider_routes.Route,
    state: ActualCaptureState,
    hints: ActualCaptureHints,
    options: ActualReadyCaptureOptions,
    summary: *ActualReadyCaptureSummary,
    writer: anytype,
) !void {
    const command = try actualCaptureCommand(gpa, route, hints);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "operation_id", route.operation_id orelse route.path_template, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonField(writer, "actual_state", state.name(), true);
    try writeJsonNullableStringField(writer, "pagination", routePaginationKind(route), true);
    try writeJsonBoolField(writer, "live_read_supported", provider_dispatch.routeLiveCallSupported(route), true);
    try writeJsonBoolField(writer, "diagnostic_read", actualCaptureUsesDiagnosticRead(route, options.include_blocked), true);
    try writeJsonField(writer, "capture_command", command, true);
    if (!options.execute) {
        try writeJsonField(writer, "status", "planned", false);
        try writer.writeByte('}');
        return;
    }

    const result_json = actualReadyCaptureRouteJson(io, gpa, db, auth, route, hints, options) catch |err| {
        summary.failed += 1;
        try writeJsonField(writer, "status", "error", true);
        try writeJsonField(writer, "error", @errorName(err), false);
        try writer.writeByte('}');
        return;
    };
    defer gpa.free(result_json);
    summary.captured += 1;
    try writeJsonField(writer, "status", "captured", true);
    try writer.writeAll("\"capture_result\":");
    try writer.writeAll(result_json);
    try writer.writeByte('}');
}

fn actualReadyCaptureRouteJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, route: provider_routes.Route, hints: ActualCaptureHints, options: ActualReadyCaptureOptions) ![]u8 {
    if (!actualCaptureReadyWithPolicy(route, hints, options.include_blocked)) return error.ActualCaptureRouteNotReady;
    const owned_request = try actualReadyCaptureRequest(gpa, route, hints);
    defer owned_request.deinit(gpa);
    const client = provider_dispatch.Client.init(auth);
    const capture_options = CaptureOptions{
        .paginate = routePaginationKind(route) != null,
        .max_pages = options.max_pages,
        .diagnostic_read = actualCaptureUsesDiagnosticRead(route, options.include_blocked),
    };
    return try app_provider_route_capture.readRouteMetadataJson(io, gpa, db, client, route, owned_request.request, capture_options);
}

fn actualReadyCaptureRequest(gpa: Allocator, route: provider_routes.Route, hints: ActualCaptureHints) !ActualReadyRequest {
    var path_params = std.ArrayList(PathParam).empty;
    errdefer path_params.deinit(gpa);
    for (route.path_params) |param| {
        if (!param.required) continue;
        const value = actualCapturePathParamHint(route, param.name, hints) orelse return error.ActualCaptureRouteNotReady;
        try path_params.append(gpa, .{ .name = param.name, .value = value });
    }
    var query_params = std.ArrayList(QueryParam).empty;
    errdefer query_params.deinit(gpa);
    var query_values = std.ArrayList([]u8).empty;
    errdefer {
        for (query_values.items) |value| gpa.free(value);
        query_values.deinit(gpa);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        const value = (try actualCaptureQueryParamHint(gpa, route, param.name, hints)) orelse return error.ActualCaptureRouteNotReady;
        try query_values.append(gpa, value);
        try query_params.append(gpa, .{ .name = param.name, .value = value });
    }
    const owned_path_params = try path_params.toOwnedSlice(gpa);
    errdefer gpa.free(owned_path_params);
    const owned_query_params = try query_params.toOwnedSlice(gpa);
    errdefer gpa.free(owned_query_params);
    const owned_query_values = try query_values.toOwnedSlice(gpa);
    return .{
        .request = .{
            .path_params = owned_path_params,
            .query_params = owned_query_params,
            .header_params = &.{},
            .body = .{},
        },
        .path_params = owned_path_params,
        .query_params = owned_query_params,
        .query_values = owned_query_values,
    };
}

fn buildFamilyReport(gpa: Allocator, rows: []const LevelTagEvidence, options: FamilyOptions) !FamilyReport {
    var families = std.ArrayList(FamilyEvidence).empty;
    errdefer families.deinit(gpa);

    for (rows) |row| {
        if (!workplanFocusIncludes(options.focus, row)) continue;
        const family = workplanTagFamily(row.provider, row.tag) orelse continue;
        const family_row = try familyEvidenceRow(gpa, &families, row.provider, family);
        family_row.tag_count += 1;
        addLevelProviderEvidence(&family_row.evidence, row.evidence);
    }

    std.mem.sort(FamilyEvidence, families.items, {}, familyLessThan);
    return .{ .items = try families.toOwnedSlice(gpa) };
}

fn familyEvidenceRow(gpa: Allocator, rows: *std.ArrayList(FamilyEvidence), provider: []const u8, family: WorkplanFamily) !*FamilyEvidence {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and row.family == family) return row;
    }
    try rows.append(gpa, FamilyEvidence.init(provider, family));
    return &rows.items[rows.items.len - 1];
}

fn addLevelProviderEvidence(dest: *LevelProviderEvidence, src: LevelProviderEvidence) void {
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
    try writeLevelProviderEvidenceJson(row.evidence, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"commands\":[{\"kind\":\"workplan\",\"command\":\"cloudio coverage workplan ");
    try writer.writeAll(row.provider);
    try writer.writeAll(" --family ");
    try writer.writeAll(row.family.name());
    try writer.writeAll(" --limit 25\"}]}");
}

fn writeTypedModelsText(gpa: Allocator, rows: []LevelTagEvidence, options: TypedModelOptions, writer: anytype) !void {
    std.mem.sort(LevelTagEvidence, rows, {}, typedModelLessThan);
    try writer.writeAll("Cloudio typed model candidates\n");
    try writer.writeAll("evidence: L3 generic inventory rows with missing or thin typed-table projections\n");
    try writer.writeAll("rank: typed_gap + generic_inventory_candidates, grouped by provider family\n");
    try writer.print("filter={s} family={s}", .{ options.provider.name(), options.family.name() });
    if (options.include_complete) try writer.writeAll(" include_complete=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_complete: usize = 0;
    var hidden_family: usize = 0;
    for (rows) |row| {
        if (!workplanFamilyIncludes(options.family, row)) {
            if (row.evidence.l3_generic_inventory_candidates != 0) hidden_family += 1;
            continue;
        }
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!options.include_complete and typedModelGap(row) == 0) {
            hidden_complete += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeTypedModelTextRow(gpa, row, writer);
    }

    if (visible == 0) {
        try writer.writeAll("no typed model candidates for filter\n");
    } else {
        if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
        if (hidden_family != 0) try writer.print("family_filtered_rows_hidden={d}\n", .{hidden_family});
        if (hidden_complete != 0) try writer.print("typed_or_complete_rows_hidden={d}\n", .{hidden_complete});
    }
}

fn writeTypedModelsJson(gpa: Allocator, rows: []LevelTagEvidence, options: TypedModelOptions, writer: anytype) !void {
    std.mem.sort(LevelTagEvidence, rows, {}, typedModelLessThan);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_typed_model_candidates", true);
    try writeJsonField(writer, "filter", options.provider.name(), true);
    try writeJsonField(writer, "family", options.family.name(), true);
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_complete", options.include_complete, true);
    try writeJsonField(writer, "evidence", "L3 generic inventory rows with missing or thin typed-table projections", true);
    try writeJsonField(writer, "rank", "typed_gap + generic_inventory_candidates, grouped by provider family", true);
    try writer.writeAll("\"items\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_complete: usize = 0;
    var hidden_family: usize = 0;
    var first = true;
    for (rows) |row| {
        if (!workplanFamilyIncludes(options.family, row)) {
            if (row.evidence.l3_generic_inventory_candidates != 0) hidden_family += 1;
            continue;
        }
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!options.include_complete and typedModelGap(row) == 0) {
            hidden_complete += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeTypedModelJsonRow(gpa, row, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, true);
    try writeJsonCountField(writer, "family_filtered_rows_hidden", hidden_family, true);
    try writeJsonCountField(writer, "typed_or_complete_rows_hidden", hidden_complete, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

fn writeTypedModelTextRow(gpa: Allocator, row: LevelTagEvidence, writer: anytype) !void {
    const family = workplanTagFamily(row.provider, row.tag);
    try writer.print("{s} | {s}: typed_gap={d} L3_generic={d} typed={d} L2_read_evidence={d} family={s}\n", .{
        row.provider,
        row.tag,
        typedModelGap(row),
        row.evidence.l3_generic_inventory_candidates,
        row.evidence.l3_typed_table_evidence,
        row.evidence.l2_read_evidence,
        if (family) |value| value.name() else "-",
    });
    const routes = try typedModelRoutesCommand(gpa, row);
    defer gpa.free(routes);
    try writer.print("  routes: {s}\n", .{routes});
    const workplan = try typedModelWorkplanCommand(gpa, row);
    defer gpa.free(workplan);
    try writer.print("  review-bundle: {s}\n", .{workplan});
}

fn writeTypedModelJsonRow(gpa: Allocator, row: LevelTagEvidence, writer: anytype) !void {
    const family = workplanTagFamily(row.provider, row.tag);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (family) |value| value.name() else null, true);
    try writeJsonCountField(writer, "typed_gap", typedModelGap(row), true);
    try writeJsonCountField(writer, "l3_generic_inventory_candidates", row.evidence.l3_generic_inventory_candidates, true);
    try writeJsonCountField(writer, "l3_typed_table_evidence", row.evidence.l3_typed_table_evidence, true);
    try writeJsonCountField(writer, "l2_read_evidence", row.evidence.l2_read_evidence, true);
    try writeJsonField(writer, "status", if (typedModelGap(row) == 0) "typed" else "candidate", true);
    try writer.writeAll("\"commands\":[");
    var first = true;
    const routes = try typedModelRoutesCommand(gpa, row);
    defer gpa.free(routes);
    try writeWorkplanCommandJson(writer, &first, "routes_detail", routes);
    const workplan = try typedModelWorkplanCommand(gpa, row);
    defer gpa.free(workplan);
    try writeWorkplanCommandJson(writer, &first, "review_bundle", workplan);
    try writer.writeAll("]}");
}

fn typedModelRoutesCommand(gpa: Allocator, row: LevelTagEvidence) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage routes {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --support partial --mode read --detail");
    return try out.toOwnedSlice();
}

fn typedModelWorkplanCommand(gpa: Allocator, row: LevelTagEvidence) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage workplan {s}", .{row.provider});
    if (workplanTagFamily(row.provider, row.tag)) |family| {
        try out.writer.print(" --family {s}", .{family.name()});
    }
    try out.writer.writeAll(" --limit 5 --candidate-limit 10 --bundle --plans --json");
    return try out.toOwnedSlice();
}

fn typedModelGap(row: LevelTagEvidence) usize {
    if (row.evidence.l3_generic_inventory_candidates <= row.evidence.l3_typed_table_evidence) return 0;
    return row.evidence.l3_generic_inventory_candidates - row.evidence.l3_typed_table_evidence;
}

fn typedModelLessThan(_: void, lhs: LevelTagEvidence, rhs: LevelTagEvidence) bool {
    const lhs_gap = typedModelGap(lhs);
    const rhs_gap = typedModelGap(rhs);
    if (lhs_gap != rhs_gap) return lhs_gap > rhs_gap;
    if (lhs.evidence.l3_generic_inventory_candidates != rhs.evidence.l3_generic_inventory_candidates) {
        return lhs.evidence.l3_generic_inventory_candidates > rhs.evidence.l3_generic_inventory_candidates;
    }
    if (lhs.evidence.l3_typed_table_evidence != rhs.evidence.l3_typed_table_evidence) {
        return lhs.evidence.l3_typed_table_evidence < rhs.evidence.l3_typed_table_evidence;
    }
    const lhs_family = workplanTagFamily(lhs.provider, lhs.tag);
    const rhs_family = workplanTagFamily(rhs.provider, rhs.tag);
    const lhs_family_name = if (lhs_family) |family| family.name() else "";
    const rhs_family_name = if (rhs_family) |family| family.name() else "";
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    const family_order = std.mem.order(u8, lhs_family_name, rhs_family_name);
    if (family_order != .eq) return family_order == .lt;
    return std.mem.order(u8, lhs.tag, rhs.tag) == .lt;
}

fn writeWorkplanText(gpa: Allocator, rows: []const LevelTagEvidence, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const effective_focus = workplanEffectiveFocus(options);
    try writer.writeAll("Cloudio provider coverage workplan\n");
    try writer.writeAll("rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n");
    try writer.writeAll("scope: broad provider tag slices with exact no-execute planning commands\n");
    try writer.print("filter={s} focus={s} family={s}", .{ options.provider.name(), effective_focus.name(), options.family.name() });
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
        if (!workplanFocusIncludes(effective_focus, row)) {
            hidden_focus += 1;
            continue;
        }
        if (!workplanFamilyIncludes(options.family, row)) {
            hidden_family += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeWorkplanTextRow(gpa, row, bundle_routes, options, writer);
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

fn writeWorkplanJson(gpa: Allocator, rows: []const LevelTagEvidence, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const effective_focus = workplanEffectiveFocus(options);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_workplan", true);
    try writeJsonField(writer, "filter", options.provider.name(), true);
    try writeJsonField(writer, "focus", effective_focus.name(), true);
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
        if (!workplanFocusIncludes(effective_focus, row)) {
            hidden_focus += 1;
            continue;
        }
        if (!workplanFamilyIncludes(options.family, row)) {
            hidden_family += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeWorkplanRowJson(gpa, row, bundle_routes, options, writer);
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

fn writeWorkplanTextRow(gpa: Allocator, row: LevelTagEvidence, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const evidence = row.evidence;
    const family = workplanTagFamily(row.provider, row.tag);
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
    const routes = try workplanRoutesCommand(gpa, row);
    defer gpa.free(routes);
    try writer.print("  routes: {s}\n", .{routes});
    if (workplanNeedsCapture(row)) {
        const capture = try workplanCaptureCommand(gpa, row, options.include_plans);
        defer gpa.free(capture);
        try writer.print("  capture-candidates: {s}\n", .{capture});
    }
    if (workplanNeedsDryRun(row)) {
        const dry_run = try workplanDryRunCommand(gpa, row, options.include_plans);
        defer gpa.free(dry_run);
        try writer.print("  dry-run-candidates: {s}\n", .{dry_run});
    }
    if (options.bundle_candidates) {
        const counts = workplanCandidateBundleCounts(row, bundle_routes orelse &.{}, options);
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

fn writeWorkplanRowJson(gpa: Allocator, row: LevelTagEvidence, bundle_routes: ?[]const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    const family = workplanTagFamily(row.provider, row.tag);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (family) |value| value.name() else null, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writer.writeAll("\"evidence\":");
    try writeLevelProviderEvidenceJson(row.evidence, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"commands\":[");
    var first = true;
    const routes = try workplanRoutesCommand(gpa, row);
    defer gpa.free(routes);
    try writeWorkplanCommandJson(writer, &first, "routes_detail", routes);
    if (workplanNeedsCapture(row)) {
        const capture = try workplanCaptureCommand(gpa, row, options.include_plans);
        defer gpa.free(capture);
        try writeWorkplanCommandJson(writer, &first, "capture_candidates", capture);
    }
    if (workplanNeedsDryRun(row)) {
        const dry_run = try workplanDryRunCommand(gpa, row, options.include_plans);
        defer gpa.free(dry_run);
        try writeWorkplanCommandJson(writer, &first, "dry_run_candidates", dry_run);
    }
    try writer.writeByte(']');
    if (options.bundle_candidates) {
        try writer.writeByte(',');
        try writeWorkplanCandidateBundleJson(gpa, row, bundle_routes orelse &.{}, options, writer);
    }
    try writer.writeByte('}');
}

fn writeWorkplanCommandJson(writer: anytype, first: *bool, kind: []const u8, command: []const u8) !void {
    try writeMaybeJsonComma(writer, first);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", kind, true);
    try writeJsonField(writer, "command", command, false);
    try writer.writeByte('}');
}

const WorkplanCandidateKind = enum {
    capture,
    dry_run,
};

const WorkplanCandidateSetCounts = struct {
    total: usize = 0,
    visible: usize = 0,
    omitted: usize = 0,
};

const WorkplanCandidateBundleCounts = struct {
    capture: WorkplanCandidateSetCounts = .{},
    dry_run: WorkplanCandidateSetCounts = .{},
};

fn writeWorkplanCandidateBundleJson(gpa: Allocator, row: LevelTagEvidence, routes: []const CoverageRoute, options: WorkplanOptions, writer: anytype) !void {
    try writer.writeAll("\"candidate_bundle\":{");
    try writeJsonCountField(writer, "candidate_limit", options.candidate_limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeWorkplanCandidateSetJson(gpa, row, routes, options, .capture, writer);
    try writer.writeByte(',');
    try writeWorkplanCandidateSetJson(gpa, row, routes, options, .dry_run, writer);
    try writer.writeByte('}');
}

fn writeWorkplanCandidateSetJson(gpa: Allocator, row: LevelTagEvidence, routes: []const CoverageRoute, options: WorkplanOptions, kind: WorkplanCandidateKind, writer: anytype) !void {
    const counts = workplanCandidateSetCounts(row, routes, options, kind);
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
        if (!routeMatchesWorkplanRow(route_row, row)) continue;
        if (!routeIsWorkplanCandidate(route_row, options, kind)) continue;
        if (options.candidate_limit != 0 and visible >= options.candidate_limit) continue;
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        switch (kind) {
            .capture => try writeCaptureCandidateJson(gpa, route_row, .{
                .filter = .{},
                .limit = options.candidate_limit,
                .include_plans = options.include_plans,
            }, writer),
            .dry_run => try writeDryRunCandidateJson(gpa, route_row, .{
                .filter = .{},
                .limit = options.candidate_limit,
                .include_plans = options.include_plans,
            }, writer),
        }
    }
    try writer.writeAll("]}");
}

fn workplanCandidateBundleCounts(row: LevelTagEvidence, routes: []const CoverageRoute, options: WorkplanOptions) WorkplanCandidateBundleCounts {
    return .{
        .capture = workplanCandidateSetCounts(row, routes, options, .capture),
        .dry_run = workplanCandidateSetCounts(row, routes, options, .dry_run),
    };
}

fn workplanCandidateSetCounts(row: LevelTagEvidence, routes: []const CoverageRoute, options: WorkplanOptions, kind: WorkplanCandidateKind) WorkplanCandidateSetCounts {
    var counts = WorkplanCandidateSetCounts{};
    for (routes) |route_row| {
        if (!routeMatchesWorkplanRow(route_row, row)) continue;
        if (!routeIsWorkplanCandidate(route_row, options, kind)) continue;
        counts.total += 1;
        if (options.candidate_limit == 0 or counts.visible < options.candidate_limit) {
            counts.visible += 1;
        } else {
            counts.omitted += 1;
        }
    }
    return counts;
}

fn routeIsWorkplanCandidate(route_row: CoverageRoute, options: WorkplanOptions, kind: WorkplanCandidateKind) bool {
    return switch (kind) {
        .capture => routeIsCaptureCandidate(route_row, .{
            .filter = .{},
            .limit = options.candidate_limit,
            .include_plans = options.include_plans,
        }),
        .dry_run => routeIsDryRunCandidate(route_row, .{
            .filter = .{},
            .limit = options.candidate_limit,
            .include_plans = options.include_plans,
        }),
    };
}

fn routeMatchesWorkplanRow(route_row: CoverageRoute, row: LevelTagEvidence) bool {
    return std.mem.eql(u8, route_row.route.provider.name(), row.provider) and
        std.mem.eql(u8, route_row.route.tag, row.tag);
}

fn workplanNeedsCapture(row: LevelTagEvidence) bool {
    return row.evidence.pending_reads != 0;
}

fn workplanNeedsDryRun(row: LevelTagEvidence) bool {
    return row.evidence.pending_mutation_dry_runs != 0;
}

fn workplanEffectiveFocus(options: WorkplanOptions) WorkplanFocus {
    if (options.family != .all) return .control_plane;
    return options.focus;
}

fn workplanFocusIncludes(focus: WorkplanFocus, row: LevelTagEvidence) bool {
    return switch (focus) {
        .all => true,
        .control_plane => workplanTagIsControlPlane(row.provider, row.tag),
    };
}

fn workplanFamilyIncludes(family: WorkplanFamily, row: LevelTagEvidence) bool {
    if (family == .all) return true;
    return (workplanTagFamily(row.provider, row.tag) orelse return false) == family;
}

fn workplanTagIsControlPlane(provider: []const u8, tag: []const u8) bool {
    return app_provider_coverage_routes.tagIsControlPlane(provider, tag);
}

fn workplanTagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    return app_provider_coverage_routes.tagFamily(provider, tag);
}

fn workplanRoutesCommand(gpa: Allocator, row: LevelTagEvidence) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage routes {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --detail");
    return try out.toOwnedSlice();
}

fn workplanCaptureCommand(gpa: Allocator, row: LevelTagEvidence, include_plans: bool) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage capture-candidates {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --limit 25");
    if (include_plans) try out.writer.writeAll(" --plans");
    return try out.toOwnedSlice();
}

fn workplanDryRunCommand(gpa: Allocator, row: LevelTagEvidence, include_plans: bool) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage dry-run-candidates {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --limit 25");
    if (include_plans) try out.writer.writeAll(" --plans");
    return try out.toOwnedSlice();
}

fn writeDryRunCandidateJson(gpa: Allocator, row: CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidateJson(gpa, row, options, writer);
}

fn routeDryRunPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    return try app_provider_coverage_candidates.dryRunPlanJson(gpa, route);
}

fn writeCaptureCandidateJson(gpa: Allocator, row: CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidateJson(gpa, row, options, writer);
}

fn routeReadPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    return try app_provider_coverage_candidates.readPlanJson(gpa, route);
}

fn routePaginationKind(route: provider_routes.Route) ?[]const u8 {
    return app_provider_coverage_candidates.paginationKind(route);
}

fn writeRequiredParamNamesText(writer: anytype, params: []const provider_routes.RouteParam) !void {
    var wrote = false;
    for (params) |param| {
        if (!param.required) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.writeAll(param.name);
    }
    if (!wrote) try writer.writeAll("-");
}

fn writeRequiredParamNamesJson(writer: anytype, params: []const provider_routes.RouteParam) !void {
    try writer.writeByte('[');
    var first = true;
    for (params) |param| {
        if (!param.required) continue;
        try writeMaybeJsonComma(writer, &first);
        try core_json.writeString(writer, param.name);
    }
    try writer.writeByte(']');
}

fn summarizeProvider(gpa: Allocator, provider: []const u8, text: []const u8, summary: *ProviderSummary) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        const deprecated = core_json.fieldBool(parsed.value, "deprecated") orelse return error.InvalidCoverageRow;

        summary.total += 1;
        summary.support_counts[indexOfName(support_names[0..], support) orelse return error.InvalidCoverageSupport] += 1;
        summary.mode_counts[indexOfName(mode_names[0..], mode) orelse return error.InvalidCoverageMode] += 1;
        if (deprecated) summary.deprecated += 1;
    }
}

fn summarizeProviderTags(gpa: Allocator, provider: []const u8, text: []const u8, rows: *std.ArrayList(TagSummary)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const tag = core_json.fieldString(parsed.value, "tag") orelse return error.InvalidCoverageRow;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        const deprecated = core_json.fieldBool(parsed.value, "deprecated") orelse return error.InvalidCoverageRow;

        const row = try tagRow(gpa, rows, provider, tag);
        row.total += 1;
        row.support_counts[indexOfName(support_names[0..], support) orelse return error.InvalidCoverageSupport] += 1;
        row.mode_counts[indexOfName(mode_names[0..], mode) orelse return error.InvalidCoverageMode] += 1;
        if (deprecated) row.deprecated += 1;
    }
}

fn summarizeProviderGaps(gpa: Allocator, provider: []const u8, text: []const u8, rows: *std.ArrayList(GapSummary)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        var route = try CoverageRoute.init(gpa, provider, parsed.value);
        defer route.deinit(gpa);

        const row = try gapRow(gpa, rows, provider, route.route.tag);
        const has_evidence = hasCoverageEvidence(route.tests);
        row.total += 1;
        if (route.route.deprecated) {
            row.deprecated += 1;
            continue;
        }

        row.non_deprecated += 1;
        if (route.route.isRoutable()) row.routable += 1;
        switch (route.route.mode) {
            .read => row.read_routes += 1,
            .dry_run => row.dry_run_routes += 1,
            .write, .none => {},
        }
        switch (route.route.support) {
            .partial => switch (route.route.mode) {
                .read => row.partial_read += 1,
                .dry_run => {
                    row.partial_dry_run += 1;
                    if (has_evidence) row.dry_run_evidence += 1;
                },
                .write, .none => {},
            },
            .planned => {
                if (route.route.mode == .read) {
                    row.planned_read += 1;
                    row.pending_reads += 1;
                }
            },
            .blocked_permission => {
                if (route.route.mode == .read) {
                    row.blocked_read += 1;
                    if (has_evidence) {
                        row.diagnostic_blocked_reads += 1;
                    } else {
                        row.pending_reads += 1;
                    }
                }
            },
            .unsafe_mutation => {
                if (route.route.mode == .dry_run) {
                    row.unsafe_dry_run += 1;
                    if (hasGeneratedDryRunPolicyEvidence(route)) {
                        row.dry_run_evidence += 1;
                        row.generated_dry_run_policy_evidence += 1;
                    } else {
                        row.pending_mutation_dry_runs += 1;
                    }
                }
            },
            .not_applicable => row.not_applicable += 1,
            .implemented, .deprecated => {},
        }
    }
}

fn summarizeProviderLevels(gpa: Allocator, provider: []const u8, text: []const u8, evidence: *LevelProviderEvidence) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        var row = try CoverageRoute.init(gpa, provider, parsed.value);
        defer row.deinit(gpa);

        updateLevelEvidence(evidence, row);
    }
}

fn summarizeProviderLevelTags(gpa: Allocator, provider: []const u8, text: []const u8, rows: *std.ArrayList(LevelTagEvidence)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        var coverage_row = try CoverageRoute.init(gpa, provider, parsed.value);
        defer coverage_row.deinit(gpa);

        const row = try levelTagRow(gpa, rows, provider, coverage_row.route.tag);
        updateLevelEvidence(&row.evidence, coverage_row);
    }
}

fn tagRow(gpa: Allocator, rows: *std.ArrayList(TagSummary), provider: []const u8, tag: []const u8) !*TagSummary {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.tag, tag)) return row;
    }
    const row = try TagSummary.init(gpa, provider, tag);
    errdefer row.deinit(gpa);
    try rows.append(gpa, row);
    return &rows.items[rows.items.len - 1];
}

fn gapRow(gpa: Allocator, rows: *std.ArrayList(GapSummary), provider: []const u8, tag: []const u8) !*GapSummary {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.tag, tag)) return row;
    }
    const row = try GapSummary.init(gpa, provider, tag);
    errdefer row.deinit(gpa);
    try rows.append(gpa, row);
    return &rows.items[rows.items.len - 1];
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

fn deinitTagList(rows: *std.ArrayList(TagSummary), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitGapList(rows: *std.ArrayList(GapSummary), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitLevelTagList(rows: *std.ArrayList(LevelTagEvidence), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

fn writeProvider(summary: ProviderSummary, writer: anytype) !void {
    try writer.print("{s}: {d} operations\n", .{ summary.name, summary.total });
    try writer.writeAll("  support:");
    for (support_names, 0..) |name, index| {
        try writer.print(" {s}={d}", .{ name, summary.support_counts[index] });
    }
    try writer.writeByte('\n');
    try writer.writeAll("  mode:");
    for (mode_names, 0..) |name, index| {
        try writer.print(" {s}={d}", .{ name, summary.mode_counts[index] });
    }
    try writer.print("\n  upstream deprecated flags={d}\n", .{summary.deprecated});
}

fn writeProviderSummaryJson(summary: ProviderSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "name", summary.name, true);
    try writeJsonCountField(writer, "total", summary.total, true);
    try writeJsonCountField(writer, "deprecated", summary.deprecated, true);
    try writer.writeAll("\"support\":");
    try writeNamedCountMap(writer, support_names[0..], summary.support_counts[0..]);
    try writer.writeByte(',');
    try writer.writeAll("\"mode\":");
    try writeNamedCountMap(writer, mode_names[0..], summary.mode_counts[0..]);
    try writer.writeByte('}');
}

fn writeTagSummaryJson(row: TagSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonCountField(writer, "total", row.total, true);
    try writeJsonCountField(writer, "deprecated", row.deprecated, true);
    try writer.writeAll("\"support\":");
    try writeNamedCountMap(writer, support_names[0..], row.support_counts[0..]);
    try writer.writeByte(',');
    try writer.writeAll("\"mode\":");
    try writeNamedCountMap(writer, mode_names[0..], row.mode_counts[0..]);
    try writer.writeByte('}');
}

fn writeNamedCountMap(writer: anytype, names: []const []const u8, counts: []const usize) !void {
    try writer.writeByte('{');
    for (names, 0..) |name, index| {
        if (index != 0) try writer.writeByte(',');
        try core_json.writeString(writer, name);
        try writer.print(":{d}", .{counts[index]});
    }
    try writer.writeByte('}');
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

fn writeGapJson(row: GapSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonCountField(writer, "priority", row.priority(), true);
    try writeJsonCountField(writer, "total", row.total, true);
    try writeJsonCountField(writer, "non_deprecated", row.non_deprecated, true);
    try writeJsonCountField(writer, "routable", row.routable, true);
    try writeJsonCountField(writer, "read_routes", row.read_routes, true);
    try writeJsonCountField(writer, "dry_run_routes", row.dry_run_routes, true);
    try writeJsonCountField(writer, "pending_reads", row.pending_reads, true);
    try writeJsonCountField(writer, "pending_mutation_dry_runs", row.pending_mutation_dry_runs, true);
    try writeJsonCountField(writer, "diagnostic_blocked_reads", row.diagnostic_blocked_reads, true);
    try writeJsonCountField(writer, "dry_run_evidence", row.dry_run_evidence, true);
    try writeJsonCountField(writer, "generated_dry_run_policy_evidence", row.generated_dry_run_policy_evidence, true);
    try writeJsonCountField(writer, "planned_read", row.planned_read, true);
    try writeJsonCountField(writer, "blocked_read", row.blocked_read, true);
    try writeJsonCountField(writer, "partial_read", row.partial_read, true);
    try writeJsonCountField(writer, "partial_dry_run", row.partial_dry_run, true);
    try writeJsonCountField(writer, "unsafe_dry_run", row.unsafe_dry_run, true);
    try writeJsonCountField(writer, "not_applicable", row.not_applicable, true);
    try writeJsonCountField(writer, "deprecated", row.deprecated, false);
    try writer.writeByte('}');
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

fn writeRouteFilterJson(filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRouteFilterJson(filter, writer);
}

fn writeJsonStringArray(writer: anytype, values: anytype) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try core_json.writeString(writer, value);
    }
    try writer.writeByte(']');
}

fn writeMaybeJsonComma(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(',');
    }
}

fn writeJsonCountField(writer: anytype, name: []const u8, value: usize, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.print(":{d}", .{value});
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonNullableCountField(writer: anytype, name: []const u8, value: ?usize, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonNullableStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |text| {
        try core_json.writeString(writer, text);
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonNullableBoolField(writer: anytype, name: []const u8, value: ?bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |flag| {
        try writer.writeAll(if (flag) "true" else "false");
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

fn writeGapField(writer: anytype, name: []const u8, count: usize) !void {
    if (count == 0) return;
    try writer.print(" {s}={d}", .{ name, count });
}

fn gapLessThan(_: void, lhs: GapSummary, rhs: GapSummary) bool {
    const lhs_priority = lhs.priority();
    const rhs_priority = rhs.priority();
    if (lhs_priority != rhs_priority) return lhs_priority > rhs_priority;
    if (lhs.pending_reads != rhs.pending_reads) return lhs.pending_reads > rhs.pending_reads;
    if (lhs.pending_mutation_dry_runs != rhs.pending_mutation_dry_runs) return lhs.pending_mutation_dry_runs > rhs.pending_mutation_dry_runs;
    if (lhs.planned_read != rhs.planned_read) return lhs.planned_read > rhs.planned_read;
    if (lhs.blocked_read != rhs.blocked_read) return lhs.blocked_read > rhs.blocked_read;
    if (lhs.unsafe_dry_run != rhs.unsafe_dry_run) return lhs.unsafe_dry_run > rhs.unsafe_dry_run;
    if (lhs.non_deprecated != rhs.non_deprecated) return lhs.non_deprecated > rhs.non_deprecated;
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, lhs.tag, rhs.tag) == .lt;
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

fn familyLessThan(_: void, lhs: FamilyEvidence, rhs: FamilyEvidence) bool {
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
            if (hasGeneratedDryRunPolicyEvidence(row)) {
                evidence.dry_run_evidence += 1;
                evidence.generated_dry_run_policy_evidence += 1;
            } else {
                evidence.pending_mutation_dry_runs += 1;
            }
        },
        .implemented, .planned, .blocked_permission, .deprecated, .not_applicable => {},
    }
}

fn hasGeneratedDryRunPolicyEvidence(row: CoverageRoute) bool {
    return app_provider_coverage_candidates.hasGeneratedDryRunPolicyEvidence(row);
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

fn indexOfName(names: []const []const u8, value: []const u8) ?usize {
    for (names, 0..) |name, index| {
        if (std.mem.eql(u8, name, value)) return index;
    }
    return null;
}

fn writeStringList(writer: anytype, values: anytype) !void {
    if (values.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(value);
    }
}

fn writeShellArg(writer: anytype, value: []const u8) !void {
    try writer.writeByte('\'');
    for (value) |byte| {
        if (byte == '\'') {
            try writer.writeAll("'\\''");
        } else {
            try writer.writeByte(byte);
        }
    }
    try writer.writeByte('\'');
}

test "summarizes provider coverage jsonl by status and mode" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"cloudflare","tag":"Zone Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":null,"support":"deprecated","mode":"read","tests":"fixture","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"no write"}
        \\
    ;

    const summary = try loadFromText(allocator, cloudflare, hostinger);
    try std.testing.expectEqual(@as(usize, 4), summary.total());
    try std.testing.expectEqual(@as(usize, 2), summary.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.deprecated);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.support_counts[indexOfName(support_names[0..], "partial").?]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.support_counts[indexOfName(support_names[0..], "unsafe_mutation").?]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.mode_counts[indexOfName(mode_names[0..], "dry_run").?]);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try summary.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: 2 operations\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unsafe_mutation=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try summary.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_operations\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"deprecated\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"unsafe_mutation\":1") != null);
}

test "summarizes provider coverage by tag with provider filters" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"POST","path":"/accounts","operation_id":null,"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"no write"}
        \\{"provider":"cloudflare","tag":"Zone Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":null,"support":"deprecated","mode":"read","tests":"fixture","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var rows = try loadTagsFromText(allocator, cloudflare, hostinger, .cloudflare);
    defer rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("cloudflare", rows.items[0].provider);
    try std.testing.expectEqualStrings("Accounts", rows.items[0].tag);
    try std.testing.expectEqual(@as(usize, 2), rows.items[0].total);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[indexOfName(support_names[0..], "partial").?]);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[indexOfName(support_names[0..], "unsafe_mutation").?]);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try rows.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage by tag\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Accounts: total=2 support: partial=1 unsafe_mutation=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try rows.writeJson(&json_out.writer, .cloudflare);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_tags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"filter\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"unsafe_mutation\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"hostinger\"") == null);
}

test "ranks provider coverage gaps by broad unresolved tag groups" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"AI Gateway","method":"GET","path":"/accounts/{account_id}/ai-gateway","operation_id":"ai-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"planned"}
        \\{"provider":"cloudflare","tag":"AI Gateway","method":"GET","path":"/accounts/{account_id}/ai-gateway/{id}","operation_id":"ai-get","path_params":[{"name":"account_id","required":true},{"name":"id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"planned"}
        \\{"provider":"cloudflare","tag":"AI Gateway","method":"POST","path":"/accounts/{account_id}/ai-gateway","operation_id":"ai-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Domains","method":"GET","path":"/api/domains/v1/portfolio","operation_id":"domains-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"missing","deprecated":false,"notes":"token lacks permission"}
        \\{"provider":"hostinger","tag":"Domains","method":"POST","path":"/api/domains/v1/portfolio","operation_id":"domains-create","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\{"provider":"hostinger","tag":"Billing","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"diagnostic evidence"}
        \\
    ;

    var gaps = try loadGapsFromText(allocator, cloudflare, hostinger, .all);
    defer gaps.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), gaps.items.len);
    try std.testing.expectEqualStrings("cloudflare", gaps.items[0].provider);
    try std.testing.expectEqualStrings("AI Gateway", gaps.items[0].tag);
    try std.testing.expectEqual(@as(usize, 2), gaps.items[0].priority());
    try std.testing.expectEqual(@as(usize, 2), gaps.items[0].planned_read);
    try std.testing.expectEqual(@as(usize, 2), gaps.items[0].pending_reads);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].unsafe_dry_run);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), gaps.items[0].pending_mutation_dry_runs);
    try std.testing.expectEqualStrings("hostinger", gaps.items[1].provider);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].blocked_read);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].pending_reads);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].partial_dry_run);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].dry_run_evidence);
    try std.testing.expectEqualStrings("hostinger", gaps.items[2].provider);
    try std.testing.expectEqualStrings("Billing", gaps.items[2].tag);
    try std.testing.expectEqual(@as(usize, 0), gaps.items[2].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[2].diagnostic_blocked_reads);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try gaps.writeText(&out.writer, .{ .provider = .all, .limit = 1 });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage gaps\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads and generated dry-run policy are evidence\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | AI Gateway: priority=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "pending_reads=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "generated_dry_run_policy_evidence=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "pending_mutation_dry_runs=1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "planned_read=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unsafe_dry_run=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try gaps.writeJson(&json_out.writer, .{ .provider = .all, .limit = 1 });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_gaps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"filter\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"items\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"AI Gateway\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"priority\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"generated_dry_run_policy_evidence\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_mutation_dry_runs\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":1") != null);
}

test "lists route capture candidates for missing L2 read evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs","operation_id":"logs-list","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs/blocked","operation_id":"logs-blocked","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"blocked_permission","mode":"read","tests":"missing","deprecated":false,"notes":"needs diagnostic"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs/ready","operation_id":"logs-ready","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"already captured"}
        \\{"provider":"cloudflare","tag":"Logs","method":"POST","path":"/accounts/{account_id}/logs","operation_id":"logs-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"mutation"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"other provider"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeCaptureCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Logs" },
        .limit = 1,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route capture candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /accounts/{account_id}/logs | support=planned op=logs-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "required_path=account_id required_query=- required_header=- pagination=page") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio route capture cloudflare --operation logs-list --path-param account_id=<account_id> --paginate") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "logs-ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Logs" },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_capture_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"logs-blocked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"required_query_params\":[\"since\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"capture_command\":\"cloudio route capture cloudflare --operation logs-blocked --path-param account_id=<account_id> --query-param since=<since>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "logs-ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "VPS_getVirtualMachinesV1") == null);

    var family_json_out = std.Io.Writer.Allocating.init(allocator);
    defer family_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .all, .family = .logs },
        .limit = 0,
    }, &family_json_out.writer);
    const family_json = try family_json_out.toOwnedSlice();
    defer allocator.free(family_json);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"family\":\"logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "VPS_getVirtualMachinesV1") == null);

    var plan_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plan_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .family = .logs },
        .limit = 1,
        .include_plans = true,
    }, &plan_json_out.writer);
    const plan_json = try plan_json_out.toOwnedSlice();
    defer allocator.free(plan_json);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"read_plan\":{\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"path\":\"/accounts/example/logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"request_body_input\":{\"present\":false,\"content_type\":null,\"required_missing\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"mode\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"will_execute\":false") != null);
}

test "plans actual Hostinger VPS captures from audit evidence and DB hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-captures.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.insertAudit("route.capture", "ok", "hostinger/VPS_getVirtualMachinesV1 /api/vps/v1/virtual-machines");
    try db.insertAudit("route.capture", "http_error", "hostinger/VPS_getBackupsV1 /api/vps/v1/virtual-machines/12345/backups");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"already captured"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}","operation_id":"VPS_getVirtualMachineDetailsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"needs actual capture"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/backups","operation_id":"VPS_getBackupsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"error-only capture should retry"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires date range"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_actual_captures\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok_read_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"non_ok_read_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_read_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachinesV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachineDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"actual_state\":\"non_ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getVirtualMachineDetailsV1 --path-param virtualMachineId='12345'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId='12345' --query-param date_from='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "--query-param date_to='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_date_from") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_virtualMachineId") == null);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeActualCapturesTextFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 2,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio actual route capture plan\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "state=missing support=partial op=VPS_getVirtualMachineDetailsV1 events=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "state=non_ok support=partial op=VPS_getBackupsV1 events=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ready=true live_read_supported=true missing_inputs=-") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);
}

test "plans derived Hostinger VPS detail captures from captured resource hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerResource("VPS_getActionsV1/99", "VPS_getActionsV1", "99", "VPS_getActionsV1", "backup_create", "success", null, "{\"id\":99}");
    try db.upsertHostingerResource("VPS_getTemplatesV1/1002", "VPS_getTemplatesV1", "1002", "VPS_getTemplatesV1", "Ubuntu 24.04", null, null, "{\"id\":1002}");
    try db.upsertHostingerResource("VPS_getFirewallListV1/55", "VPS_getFirewallListV1", "55", "VPS_getFirewallListV1", "default firewall", "active", null, "{\"id\":55}");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/actions/{actionId}","operation_id":"VPS_getActionDetailsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"actionId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/templates/{templateId}","operation_id":"VPS_getTemplateDetailsV1","path_params":[{"name":"templateId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/post-install-scripts/{postInstallScriptId}","operation_id":"VPS_getPostInstallScriptV1","path_params":[{"name":"postInstallScriptId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires script list resource"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires explicit date window"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/firewall/{firewallId}","operation_id":"VPS_getFirewallDetailsV1","path_params":[{"name":"firewallId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_vps_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getActionDetailsV1 --path-param virtualMachineId='12345' --path-param actionId='99'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getTemplateDetailsV1 --path-param templateId='1002'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getFirewallDetailsV1 --path-param firewallId='55'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId='12345' --query-param date_from='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_inputs\":[{\"source\":\"path\",\"name\":\"postInstallScriptId\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_date_to") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"skipped_unready\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"attempted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getActionDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getTemplateDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getFirewallDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getPostInstallScriptV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans blocked Hostinger diagnostic captures only when explicitly included" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-blocked-diagnostics.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");

    const hostinger =
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"live_read_supported\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"diagnostic_read_supported\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectListV1 --path-param virtualMachineId='1307809' --diagnostic") != null);

    const normal_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(normal_plan);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"include_blocked\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"ready_routes\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"planned\":0") != null);

    const diagnostic_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
    });
    defer allocator.free(diagnostic_plan);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"include_blocked\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"planned\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"diagnostic_read\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"operation_id\":\"VPS_getProjectListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "test-token") == null);
}

test "filters Hostinger capture-ready runs to diagnostic reads only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-diagnostic-only.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const hostinger =
        \\{"provider":"hostinger","tag":"Domains: Portfolio","method":"GET","path":"/api/domains/v1/portfolio/{domain}","operation_id":"domains_getDomainDetailsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain detail"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    const mixed_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(mixed_plan);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"skipped_non_diagnostic\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"planned\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"operation_id\":\"domains_getDomainDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"operation_id\":\"reach_listProfilesV1\"") != null);

    const diagnostic_only = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
        .diagnostic_only = true,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(diagnostic_only);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"diagnostic_only\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"skipped_non_diagnostic\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"planned\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"operation_id\":\"domains_getDomainDetailsV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "test-token") == null);
}

test "plans Cloudflare account and zone captures from configured scope hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-scope-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-other", "sparkdate.love", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-other\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts Logs Audit","method":"GET","path":"/accounts/{account_id}/logs/audit","operation_id":"audit-logs-get-account-audit-logs","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account scoped"}
        \\{"provider":"cloudflare","tag":"Custom pages for an account","method":"GET","path":"/accounts/{account_identifier}/custom_pages","operation_id":"custom-pages-for-an-account-list-custom-pages","path_params":[{"name":"account_identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account identifier spelling"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone scoped"}
        \\{"provider":"cloudflare","tag":"Zones Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":"zone-settings-get-all","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone settings"}
        \\{"provider":"cloudflare","tag":"Cache Cache Reserve","method":"GET","path":"/zones/{zone_id}/cache/cache_reserve","operation_id":"cache-cache-reserve-get-cache-reserve-setting","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"cache setting"}
        \\{"provider":"cloudflare","tag":"SSL Universal","method":"GET","path":"/zones/{zone_id}/ssl/universal/settings","operation_id":"universal-ssl-settings-for-a-zone-get-universal-ssl-settings","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ssl setting"}
        \\{"provider":"cloudflare","tag":"Custom pages for a zone","method":"GET","path":"/zones/{zone_identifier}/custom_pages","operation_id":"custom-pages-for-a-zone-list-custom-pages","path_params":[{"name":"zone_identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone identifier spelling"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"configured_domain_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_account_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_zone_hints\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation audit-logs-get-account-audit-logs --path-param account_id='acct-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-an-account-list-custom-pages --path-param account_identifier='acct-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation dns-records-for-a-zone-list-dns-records --path-param zone_id='zone-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-a-zone-list-custom-pages --path-param zone_identifier='zone-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zone-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, cloudflare, "", &db, .{ .cloudflare = .{ .token = "test-token" } }, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"cache-cache-reserve-get-cache-reserve-setting\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"universal-ssl-settings-for-a-zone-get-universal-ssl-settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans Cloudflare child resource captures from resource and inventory hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-child-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-other", "sparkdate.love", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-other\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");
    try db.upsertCloudflareResource("dns|zone-other|record-other", "route-cloudflare-dns", "record-other", "zone", "zone-other", "sparkdate.love", "active", "A", "{\"id\":\"record-other\"}");
    try db.upsertCloudflareResource("dns|zone-plosca|record-plosca", "route-cloudflare-dns", "record-plosca", "zone", "zone-plosca", "plosca.ru", "active", "A", "{\"id\":\"record-plosca\"}");
    try db.upsertCloudflareResource("zone-rulesets|plosca|ruleset", "zone-rulesets", "zone-ruleset-1", "zone", "plosca.ru", "default", "active", "http_request_cache_settings", "{\"id\":\"zone-ruleset-1\"}");
    try db.upsertCloudflareResource("account-rulesets|acct|ruleset", "account-rulesets", "account-ruleset-1", "account", "acct-1", "managed", "active", "http_request_firewall_custom", "{\"id\":\"account-ruleset-1\"}");
    try db.upsertCloudflareResource("zone-custom-pages|plosca|1000", "zone-custom-pages", "1000_errors", "zone", "plosca.ru", "1000 Errors", "default", null, "{\"id\":\"1000_errors\"}");
    try db.upsertCloudflareResource("account-custom-pages|acct|500", "account-custom-pages", "500_errors", "account", "acct-1", "500 Errors", "default", null, "{\"id\":\"500_errors\"}");
    try db.upsertCloudflareResource("tls-zone-certificate-packs|plosca|certpack", "tls-zone-certificate-packs", "certpack-1", "zone", "plosca.ru", "Universal SSL", "active", "universal", "{\"id\":\"certpack-1\"}");
    try db.upsertCloudflareResource("access-zone-identity-providers|plosca|idp", "access-zone-identity-providers", "idp-1", "zone", "plosca.ru", "One-time PIN", "active", "onetimepin", "{\"id\":\"idp-1\"}");
    try db.upsertCloudflareResource("account-members|acct|member", "account-members", "member-1", "account", "acct-1", "Alice", "accepted", null, "{\"id\":\"member-1\"}");
    try db.upsertCloudflareResource("account-roles|acct|role", "account-roles", "role-1", "account", "acct-1", "Administrator", "active", null, "{\"id\":\"role-1\"}");
    try db.upsertCloudflareResource("account-tokens|acct|token", "account-tokens", "token-1", "account", "acct-1", "Read token", "active", null, "{\"id\":\"token-1\"}");
    try db.upsertCloudflareResource("account-permission-groups|acct|permission", "account-permission-groups", "permission-1", "account", "acct-1", "Zone Read", "active", null, "{\"id\":\"permission-1\"}");
    try db.upsertCloudflareInventoryItem("account-resource-groups|acct|rg", "account-resource-groups", "resource-group-1", "account", "acct-1", "All zones", "active", "iam", null, "acct-1", null, null, null, null, null, null, "{\"id\":\"resource-group-1\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records/{dns_record_id}","operation_id":"dns-records-for-a-zone-dns-record-details","path_params":[{"name":"zone_id","required":true},{"name":"dns_record_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"dns record detail"}
        \\{"provider":"cloudflare","tag":"Zone Rulesets","method":"GET","path":"/zones/{zone_id}/rulesets/{ruleset_id}","operation_id":"getZoneRuleset","path_params":[{"name":"zone_id","required":true},{"name":"ruleset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone ruleset detail"}
        \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/{ruleset_id}","operation_id":"getAccountRuleset","path_params":[{"name":"account_id","required":true},{"name":"ruleset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account ruleset detail"}
        \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/phases/{ruleset_phase}/entrypoint","operation_id":"getAccountEntrypointRuleset","path_params":[{"name":"account_id","required":true},{"name":"ruleset_phase","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account ruleset phase"}
        \\{"provider":"cloudflare","tag":"Custom pages for a zone","method":"GET","path":"/zones/{zone_identifier}/custom_pages/{identifier}","operation_id":"custom-pages-for-a-zone-get-custom-page","path_params":[{"name":"zone_identifier","required":true},{"name":"identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone custom page detail"}
        \\{"provider":"cloudflare","tag":"Custom pages for an account","method":"GET","path":"/accounts/{account_identifier}/custom_pages/{identifier}","operation_id":"custom-pages-for-an-account-get-custom-page","path_params":[{"name":"account_identifier","required":true},{"name":"identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account custom page detail"}
        \\{"provider":"cloudflare","tag":"SSL Certificate Packs","method":"GET","path":"/zones/{zone_id}/ssl/certificate_packs/{certificate_pack_id}","operation_id":"certificate-packs-get-certificate-pack","path_params":[{"name":"zone_id","required":true},{"name":"certificate_pack_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"certificate pack detail"}
        \\{"provider":"cloudflare","tag":"Access identity providers","method":"GET","path":"/zones/{zone_id}/access/identity_providers/{identity_provider_id}","operation_id":"access-identity-providers-get-an-access-identity-provider","path_params":[{"name":"zone_id","required":true},{"name":"identity_provider_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone access idp detail"}
        \\{"provider":"cloudflare","tag":"Account Members","method":"GET","path":"/accounts/{account_id}/members/{member_id}","operation_id":"account-members-member-details","path_params":[{"name":"account_id","required":true},{"name":"member_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"member detail"}
        \\{"provider":"cloudflare","tag":"Account Roles","method":"GET","path":"/accounts/{account_id}/roles/{role_id}","operation_id":"account-roles-role-details","path_params":[{"name":"account_id","required":true},{"name":"role_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"role detail"}
        \\{"provider":"cloudflare","tag":"Account Owned API Tokens","method":"GET","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"account-api-tokens-token-details","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account token detail"}
        \\{"provider":"cloudflare","tag":"Account Permission Groups","method":"GET","path":"/accounts/{account_id}/iam/permission_groups/{permission_group_id}","operation_id":"account-permission-group-details","path_params":[{"name":"account_id","required":true},{"name":"permission_group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"permission group detail"}
        \\{"provider":"cloudflare","tag":"Account Resource Groups","method":"GET","path":"/accounts/{account_id}/iam/resource_groups/{resource_group_id}","operation_id":"account-resource-group-details","path_params":[{"name":"account_id","required":true},{"name":"resource_group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"inventory-backed resource group detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_resource_hints\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_inventory_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation dns-records-for-a-zone-dns-record-details --path-param zone_id='zone-plosca' --path-param dns_record_id='record-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation getZoneRuleset --path-param zone_id='zone-plosca' --path-param ruleset_id='zone-ruleset-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation getAccountEntrypointRuleset --path-param account_id='acct-1' --path-param ruleset_phase='http_request_firewall_custom'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-a-zone-get-custom-page --path-param zone_identifier='zone-plosca' --path-param identifier='1000_errors'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation certificate-packs-get-certificate-pack --path-param zone_id='zone-plosca' --path-param certificate_pack_id='certpack-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation access-identity-providers-get-an-access-identity-provider --path-param zone_id='zone-plosca' --path-param identity_provider_id='idp-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation account-api-tokens-token-details --path-param account_id='acct-1' --path-param token_id='token-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation account-resource-group-details --path-param account_id='acct-1' --path-param resource_group_id='resource-group-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "record-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zone-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, cloudflare, "", &db, .{ .cloudflare = .{ .token = "test-token" } }, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"account-resource-group-details\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans Hostinger DNS domain hosting and Horizons captures from domain and inventory hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hosting-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerInventoryItem("hosting_listWebsitesV1/plosca.ru", "hosting_listWebsitesV1", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "order-123", null, null, null, null, "{\"domain\":\"plosca.ru\"}");
    try db.upsertHostingerInventoryItem("hosting_listOrdersV1/order-123", "hosting_listOrdersV1", "order-123", "Premium Web Hosting", "active", "hosting", null, "u123", null, null, null, null, null, "{\"id\":\"order-123\"}");
    try db.upsertHostingerResource("DNS_getDNSSnapshotListV1/snap-1", "DNS_getDNSSnapshotListV1", "snap-1", "plosca.ru", "Before deploy", null, "plosca.ru", "{\"id\":\"snap-1\"}");
    try db.upsertHostingerResource("domains_getWHOISProfileListV1/whois-77", "domains_getWHOISProfileListV1", "whois-77", "domains_getWHOISProfileListV1", "Registrant", "active", null, "{\"id\":\"whois-77\"}");
    try db.upsertHostingerResource("hosting_listAccountDatabasesV1/db_main", "hosting_listAccountDatabasesV1", "db_main", "u123", "db_main", "active", "plosca.ru", "{\"name\":\"db_main\"}");
    try db.upsertHostingerResource("hosting_listNodeJSBuildsV1/build-abc", "hosting_listNodeJSBuildsV1", "build-abc", "u123/plosca.ru", "build-abc", "finished", "plosca.ru", "{\"uuid\":\"build-abc\"}");
    try db.upsertHostingerResource("horizons_getWebsitesV1/site-42", "horizons_getWebsitesV1", "site-42", "horizons_getWebsitesV1", "plosca.ru", "active", "plosca.ru", "{\"id\":\"site-42\"}");

    const hostinger =
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}","operation_id":"DNS_getDNSSnapshotListV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain read"}
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}/{snapshotId}","operation_id":"DNS_getDNSSnapshotV1","path_params":[{"name":"domain","required":true},{"name":"snapshotId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"snapshot detail"}
        \\{"provider":"hostinger","tag":"DNS: Zone","method":"GET","path":"/api/dns/v1/zones/{domain}","operation_id":"DNS_getDNSRecordsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone detail"}
        \\{"provider":"hostinger","tag":"Domains: Portfolio","method":"GET","path":"/api/domains/v1/portfolio/{domain}","operation_id":"domains_getDomainDetailsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain detail"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois/{whoisId}","operation_id":"domains_getWHOISProfileV1","path_params":[{"name":"whoisId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois detail"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases","operation_id":"hosting_listAccountDatabasesV1","path_params":[{"name":"username","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database list"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases/{name}/phpmyadmin-link","operation_id":"hosting_getPhpMyAdminLinkV1","path_params":[{"name":"username","required":true},{"name":"name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database detail"}
        \\{"provider":"hostinger","tag":"Hosting: Datacenters","method":"GET","path":"/api/hosting/v1/datacenters","operation_id":"hosting_listAvailableDatacentersV1","path_params":[],"query_params":[{"name":"order_id","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"order scoped"}
        \\{"provider":"hostinger","tag":"Hosting: Domains","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/subdomains","operation_id":"hosting_listWebsiteSubdomainsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website child list"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds/{uuid}/logs","operation_id":"hosting_getNodeJSBuildLogsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true},{"name":"uuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"node build logs"}
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites/{websiteId}","operation_id":"horizons_getWebsiteV1","path_params":[{"name":"websiteId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"configured_domain_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_inventory_hints\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation DNS_getDNSSnapshotV1 --path-param domain='plosca.ru' --path-param snapshotId='snap-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation domains_getWHOISProfileV1 --path-param whoisId='whois-77'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_getPhpMyAdminLinkV1 --path-param username='u123' --path-param name='db_main'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_listAvailableDatacentersV1 --query-param order_id='order-123'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_getNodeJSBuildLogsV1 --path-param username='u123' --path-param domain='plosca.ru' --path-param uuid='build-abc'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation horizons_getWebsiteV1 --path-param websiteId='site-42'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"hosting_listWebsiteSubdomainsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"horizons_getWebsiteV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans Hostinger Docker and Reach child captures from scoped resource hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-child-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try db.upsertHostingerResource("VPS_getProjectListV1/999999/wrong-project", "VPS_getProjectListV1", "wrong-project", "999999", "wrong-project", "running", null, "{\"projectName\":\"wrong-project\"}");
    try db.upsertHostingerResource("VPS_getProjectListV1/1307809/cloudio-stack", "VPS_getProjectListV1", "cloudio-stack", "1307809", "cloudio-stack", "running", null, "{\"projectName\":\"cloudio-stack\"}");
    try db.upsertHostingerResource("reach_listProfilesV1/profile-1", "reach_listProfilesV1", "profile-1", "reach_listProfilesV1", "Main profile", "active", null, "{\"profileUuid\":\"profile-1\"}");
    try db.upsertHostingerResource("reach_listSegmentsV1/segment-1", "reach_listSegmentsV1", "segment-1", "reach_listSegmentsV1", "Customers", "enabled", null, "{\"segmentUuid\":\"segment-1\"}");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project list"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}","operation_id":"VPS_getProjectContentsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project contents"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}/containers","operation_id":"VPS_getProjectContainersV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project containers"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}/logs","operation_id":"VPS_getProjectLogsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project logs"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"profile list"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments","operation_id":"reach_listSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment list"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments/{segmentUuid}","operation_id":"reach_getSegmentDetailsV1","path_params":[{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment detail"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listSegmentContactsV1","path_params":[{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment contacts"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/profiles/{profileUuid}/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listProfileSegmentContactsV1","path_params":[{"name":"profileUuid","required":true},{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"profile segment contacts"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_vps_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectContentsV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectContainersV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectLogsV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation reach_getSegmentDetailsV1 --path-param segmentUuid='segment-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation reach_listProfileSegmentContactsV1 --path-param profileUuid='profile-1' --path-param segmentUuid='segment-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "wrong-project") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getProjectContentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"reach_listProfileSegmentContactsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "wrong-project") == null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);

    const wrong_db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-wrong-child-hints.db", .{tmp.sub_path});
    defer allocator.free(wrong_db_path);
    var wrong_db = try Db.open(std.testing.io, wrong_db_path);
    defer wrong_db.close();
    try wrong_db.initSchema();
    try wrong_db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try wrong_db.upsertHostingerResource("VPS_getProjectListV1/999999/wrong-project", "VPS_getProjectListV1", "wrong-project", "999999", "wrong-project", "running", null, "{\"projectName\":\"wrong-project\"}");

    var wrong_json_out = std.Io.Writer.Allocating.init(allocator);
    defer wrong_json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &wrong_db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &wrong_json_out.writer);
    const wrong_json = try wrong_json_out.toOwnedSlice();
    defer allocator.free(wrong_json);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"candidate_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"ready_candidates\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"operation_id\":\"VPS_getProjectContentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"missing_inputs\":[{\"source\":\"path\",\"name\":\"projectName\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "cloudio route capture hostinger --operation VPS_getProjectContentsV1 --path-param virtualMachineId='1307809' --path-param projectName='wrong-project'") == null);
}

test "explains Hostinger missing input source routes for broad child groups" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-source-plan.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try db.insertAudit("route.capture", "ok", "hostinger/domains_getWHOISProfileListV1 /api/domains/v1/whois");
    _ = try db.insertSnapshot("hostinger", "domains_getWHOISProfileListV1", "/api/domains/v1/whois", "ok", "domains_getWHOISProfileListV1 HTTP 200", "[]", null);
    try db.insertAudit("route.capture", "ok", "hostinger/hosting_listAccountDatabasesV1 /api/hosting/v1/accounts/u123/databases");
    _ = try db.insertSnapshot("hostinger", "hosting_listAccountDatabasesV1", "/api/hosting/v1/accounts/u123/databases", "ok", "hosting_listAccountDatabasesV1 HTTP 200", "{\"data\":[{\"unsupported\":\"db-main\"}],\"meta\":{\"total\":1}}", null);
    try db.insertAudit("route.capture", "permission", "hostinger/reach_listProfilesV1 /api/reach/v1/profiles");
    try db.insertAudit("route.capture", "http_error", "hostinger/VPS_getProjectListV1 /api/vps/v1/virtual-machines/1307809/docker");

    const hostinger =
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}","operation_id":"DNS_getDNSSnapshotListV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain read"}
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}/{snapshotId}","operation_id":"DNS_getDNSSnapshotV1","path_params":[{"name":"domain","required":true},{"name":"snapshotId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"snapshot detail"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois","operation_id":"domains_getWHOISProfileListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois list"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois/{whoisId}","operation_id":"domains_getWHOISProfileV1","path_params":[{"name":"whoisId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois detail"}
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites/{websiteId}","operation_id":"horizons_getWebsiteV1","path_params":[{"name":"websiteId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website detail"}
        \\{"provider":"hostinger","tag":"Hosting: Websites","method":"GET","path":"/api/hosting/v1/websites","operation_id":"hosting_listWebsitesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website list"}
        \\{"provider":"hostinger","tag":"Hosting: Orders","method":"GET","path":"/api/hosting/v1/orders","operation_id":"hosting_listOrdersV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"orders"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases","operation_id":"hosting_listAccountDatabasesV1","path_params":[{"name":"username","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database list"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases/{name}/phpmyadmin-link","operation_id":"hosting_getPhpMyAdminLinkV1","path_params":[{"name":"username","required":true},{"name":"name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database detail"}
        \\{"provider":"hostinger","tag":"Hosting: Datacenters","method":"GET","path":"/api/hosting/v1/datacenters","operation_id":"hosting_listAvailableDatacentersV1","path_params":[],"query_params":[{"name":"order_id","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"order-scoped"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds","operation_id":"hosting_listNodeJSBuildsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"build list"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds/{uuid}/logs","operation_id":"hosting_getNodeJSBuildLogsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true},{"name":"uuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"build logs"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/segmentation/segments","operation_id":"reach_listSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/profiles/{profileUuid}/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listProfileSegmentContactsV1","path_params":[{"name":"profileUuid","required":true},{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked child"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}","operation_id":"VPS_getProjectContentsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"project detail"}
        \\{"provider":"hostinger","tag":"VPS: Firewall","method":"GET","path":"/api/vps/v1/firewall","operation_id":"VPS_getFirewallListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"firewall list"}
        \\{"provider":"hostinger","tag":"VPS: Firewall","method":"GET","path":"/api/vps/v1/firewall/{firewallId}","operation_id":"VPS_getFirewallDetailsV1","path_params":[{"name":"firewallId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"firewall detail"}
        \\{"provider":"hostinger","tag":"VPS: Post-install scripts","method":"GET","path":"/api/vps/v1/post-install-scripts","operation_id":"VPS_getPostInstallScriptsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"scripts"}
        \\{"provider":"hostinger","tag":"VPS: Post-install scripts","method":"GET","path":"/api/vps/v1/post-install-scripts/{postInstallScriptId}","operation_id":"VPS_getPostInstallScriptV1","path_params":[{"name":"postInstallScriptId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"script detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source_summary\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"no_official_source\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shapes\":{\"array\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_input_sources\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"snapshotId\",\"source_operation_id\":\"DNS_getDNSSnapshotListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"ready_to_capture\",\"next_action\":\"capture the source route to discover identifiers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"whoisId\",\"source_operation_id\":\"domains_getWHOISProfileListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"captured_empty\",\"next_action\":\"source collection is empty; no child identifiers are available\",\"source_status\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shape\":\"array\",\"body_item_count\":0,\"body_bytes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"websiteId\",\"source_operation_id\":null,\"hint_kind\":null,\"hint_count\":0,\"result\":\"no_official_source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "horizons_getWebsitesV1") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"username\",\"source_operation_id\":\"hosting_listWebsitesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"name\",\"source_operation_id\":\"hosting_listAccountDatabasesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"captured_without_hints\",\"next_action\":\"extend normalization for this non-empty source response\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shape\":\"data_array\",\"body_item_count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"order_id\",\"source_operation_id\":\"hosting_listOrdersV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"uuid\",\"source_operation_id\":\"hosting_listNodeJSBuildsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"profileUuid\",\"source_operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"segmentUuid\",\"source_operation_id\":\"reach_listSegmentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"projectName\",\"source_operation_id\":\"VPS_getProjectListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"diagnostic_blocked\",\"next_action\":\"diagnostic-only source is blocked; child identifiers are unavailable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"firewallId\",\"source_operation_id\":\"VPS_getFirewallListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"postInstallScriptId\",\"source_operation_id\":\"VPS_getPostInstallScriptsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_listWebsitesV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectListV1 --path-param virtualMachineId='1307809' --diagnostic") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"diagnostic_ready\":true") != null);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeActualCapturesTextFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "source_summary total=") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "no_official_source=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:snapshotId <- DNS_getDNSSnapshotListV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:websiteId <- no_official_source result=no_official_source") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:projectName <- VPS_getProjectListV1 state=non_ok result=diagnostic_blocked ready=false diagnostic_ready=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:whoisId <- domains_getWHOISProfileListV1 state=ok result=captured_empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:name <- hosting_listAccountDatabasesV1 state=ok result=captured_without_hints") != null);
}

test "closed Cloudflare security read slice has no capture candidates" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Radar Bots","method":"GET","path":"/radar/bots","operation_id":"radar-get-bots","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Radar bot telemetry capture"}
        \\{"provider":"cloudflare","tag":"Email Security","method":"GET","path":"/accounts/{account_id}/email-security/investigate","operation_id":"email_security_investigate","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"cursor","required":false},{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Email Security capture"}
        \\{"provider":"cloudflare","tag":"Security Center Scans","method":"GET","path":"/zones/{zone_id}/security-center/insights/scans","operation_id":"get-security-center-zone-scans","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Security Center scan capture"}
        \\{"provider":"cloudflare","tag":"security.txt","method":"GET","path":"/zones/{zone_id}/security-center/securitytxt","operation_id":"get-security-txt","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic security.txt capture"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not a control-plane security family"}
        \\
    ;

    var candidates_json_out = std.Io.Writer.Allocating.init(allocator);
    defer candidates_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, "", .{
        .filter = .{ .provider = .cloudflare, .family = .security },
        .limit = 0,
    }, &candidates_json_out.writer);
    const candidates_json = try candidates_json_out.toOwnedSlice();
    defer allocator.free(candidates_json);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"family\":\"security\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "radar-get-bots") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "email_security_investigate") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "get-security-center-zone-scans") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "get-security-txt") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "workers-list") == null);

    var families_json_out = std.Io.Writer.Allocating.init(allocator);
    defer families_json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, "", .{
        .provider = .cloudflare,
        .limit = 0,
    }, &families_json_out.writer);
    const families_json = try families_json_out.toOwnedSlice();
    defer allocator.free(families_json);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"family\":\"security\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"priority\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l2_read_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"pending_reads\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l3_typed_table_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "Workers") == null);
}

test "closed Cloudflare accounts read slice has no capture candidates" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Organizations","method":"GET","path":"/organizations","operation_id":"Organization_listOrganizations","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic organization capture"}
        \\{"provider":"cloudflare","tag":"OrganizationMembers","method":"GET","path":"/organizations/{organization_id}/members","operation_id":"Members_list","path_params":[{"name":"organization_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic organization members capture"}
        \\{"provider":"cloudflare","tag":"SCIM Users","method":"GET","path":"/accounts/{account_id}/scim/v2/Users","operation_id":"scim-users-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic SCIM Resources capture"}
        \\{"provider":"cloudflare","tag":"Worker Account Settings","method":"GET","path":"/accounts/{account_id}/workers/account-settings","operation_id":"worker-account-settings-fetch-worker-account-settings","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic worker account settings capture"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs","operation_id":"logs-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not an account-family row"}
        \\
    ;

    var candidates_json_out = std.Io.Writer.Allocating.init(allocator);
    defer candidates_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, "", .{
        .filter = .{ .provider = .cloudflare, .family = .accounts },
        .limit = 0,
    }, &candidates_json_out.writer);
    const candidates_json = try candidates_json_out.toOwnedSlice();
    defer allocator.free(candidates_json);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"family\":\"accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "Organization_listOrganizations") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "Members_list") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "scim-users-list") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "worker-account-settings-fetch-worker-account-settings") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "logs-list") == null);

    var families_json_out = std.Io.Writer.Allocating.init(allocator);
    defer families_json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, "", .{
        .provider = .cloudflare,
        .limit = 0,
    }, &families_json_out.writer);
    const families_json = try families_json_out.toOwnedSlice();
    defer allocator.free(families_json);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"family\":\"accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"priority\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l2_read_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"pending_reads\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l3_typed_table_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "Logs") == null);
}

test "lists route dry-run candidates for missing mutation review evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/WorkerCreateRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Workers","method":"DELETE","path":"/accounts/{account_id}/workers/{worker_id}","operation_id":"workers-delete","path_params":[{"name":"account_id","required":true},{"name":"worker_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"read"}
        \\{"provider":"cloudflare","tag":"Workers","method":"PATCH","path":"/accounts/{account_id}/workers/{worker_id}","operation_id":"workers-patch","path_params":[{"name":"account_id","required":true},{"name":"worker_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"already reviewed"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers/old","operation_id":"workers-old","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"deprecated","mode":"none","tests":"generated","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VpsPurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"hostinger","tag":"VPS","method":"DELETE","path":"/api/vps/v1/virtual-machines/{virtualMachineId}","operation_id":"VPS_deleteVirtualMachineV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeDryRunCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 1,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route dry-run candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines | support=unsafe_mutation op=VPS_purchaseNewVirtualMachineV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "required_path=- required_query=- required_header=- body_required=true body_content_type=application/json schema_refs=#/components/schemas/VpsPurchaseRequest") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workers-create") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_dry_run_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_deleteVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_required\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_content_type\":\"application/json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_body_schema_refs\":[\"#/components/schemas/VpsPurchaseRequest\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_command\":\"cloudio route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "workers-create") == null);

    var family_text_out = std.Io.Writer.Allocating.init(allocator);
    defer family_text_out.deinit();
    try writeDryRunCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 0,
    }, &family_text_out.writer);
    const family_text = try family_text_out.toOwnedSlice();
    defer allocator.free(family_text);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "filter provider=hostinger tag_query=VPS limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "VPS_purchaseNewVirtualMachineV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "workers-create") == null);

    var plan_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plan_json_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 1,
        .include_plans = true,
    }, &plan_json_out.writer);
    const plan_json = try plan_json_out.toOwnedSlice();
    defer allocator.free(plan_json);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"dry_run_plan\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"path\":\"/api/vps/v1/virtual-machines\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"request_body_input\":{\"present\":true,\"content_type\":\"application/json\",\"required_missing\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"will_execute\":false") != null);
}

test "counts generated Cloudflare mutation dry-runs as review evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"POST","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-create","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"hostinger remains pending"}
        \\
    ;

    const levels = try loadLevelsFromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.dry_run_routes);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.dry_run_evidence);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), levels.cloudflare.pending_mutation_dry_runs);
    try std.testing.expectEqual(@as(usize, 0), levels.hostinger.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.pending_mutation_dry_runs);

    var dns_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer dns_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .family = .dns },
        .limit = 0,
        .include_plans = true,
    }, &dns_candidates_out.writer);
    const dns_candidates = try dns_candidates_out.toOwnedSlice();
    defer allocator.free(dns_candidates);
    try std.testing.expect(std.mem.indexOf(u8, dns_candidates, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, dns_candidates, "dns-records-create") == null);

    var cloudflare_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer cloudflare_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Workers" },
        .limit = 0,
    }, &cloudflare_candidates_out.writer);
    const cloudflare_candidates = try cloudflare_candidates_out.toOwnedSlice();
    defer allocator.free(cloudflare_candidates);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare_candidates, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare_candidates, "workers-create") == null);

    var pending_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer pending_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .all },
        .limit = 0,
    }, &pending_candidates_out.writer);
    const pending_candidates = try pending_candidates_out.toOwnedSlice();
    defer allocator.free(pending_candidates);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"total_candidates\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"operation_id\":\"workers-create\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "dns-records-create") == null);
}

test "summarizes manifest-backed provider coverage levels" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
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
    try levels.writeText(.all, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage levels\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "L2 read_evidence=1 partial_reads=1 diagnostic_blocked_reads=0 pending_reads=1 read_missing_tests=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "L3 evidence generic_inventory_candidates=1 typed_table_evidence=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try levels.writeJson(.all, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_levels\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"providers\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"l2_diagnostic_reads\":1") != null);
}

test "ranks manifest-backed provider coverage levels by tag" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
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
    try std.testing.expectEqual(@as(usize, 0), report.items[2].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[2].evidence.l3_typed_table_evidence);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer, .{ .provider = .all, .limit = 1 });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage levels by tag\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Workers: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "pending_reads=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=2") != null);

    var full_out = std.Io.Writer.Allocating.init(allocator);
    defer full_out.deinit();
    try report.writeText(&full_out.writer, .{ .provider = .all, .limit = 0 });
    const full_text = try full_out.toOwnedSlice();
    defer allocator.free(full_text);
    try std.testing.expect(std.mem.indexOf(u8, full_text, "cloudflare | Accounts: priority=0") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(&json_out.writer, .{ .provider = .all, .limit = 1 });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_level_tags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"items\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"closed_or_evidence_only_rows_hidden\":2") != null);

    var full_json_out = std.Io.Writer.Allocating.init(allocator);
    defer full_json_out.deinit();
    try report.writeJson(&full_json_out.writer, .{ .provider = .all, .limit = 0 });
    const full_json = try full_json_out.toOwnedSlice();
    defer allocator.free(full_json);
    try std.testing.expect(std.mem.indexOf(u8, full_json, "\"tag\":\"Accounts\"") != null);
}

test "ranks typed model candidates from L3 generic inventory evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Security Center Insights","method":"GET","path":"/accounts/{account_id}/security-center/insights","operation_id":"security-insights-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"generic inventory only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"generic inventory only"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"typed account rows"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites","operation_id":"Horizons_getWebsitesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"generic inventory only"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeTypedModelsTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .cloudflare,
        .family = .security,
        .limit = 10,
        .include_complete = true,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio typed model candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Security Center Insights: typed_gap=0 L3_generic=1 typed=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "routes: cloudio coverage routes cloudflare 'Security Center Insights' --support partial --mode read --detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "review-bundle: cloudio coverage workplan cloudflare --family security --limit 5 --candidate-limit 10 --bundle --plans --json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Accounts") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeTypedModelsJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 10,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_typed_model_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"focus_family\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_gap\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"routes_detail\",\"command\":\"cloudio coverage routes cloudflare 'Workers' --support partial --mode read --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Horizons: Websites\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Security Center Insights\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Accounts\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_or_complete_rows_hidden\":3") != null);

    var complete_json_out = std.Io.Writer.Allocating.init(allocator);
    defer complete_json_out.deinit();
    try writeTypedModelsJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .cloudflare,
        .limit = 0,
        .include_complete = true,
    }, &complete_json_out.writer);
    const complete_json = try complete_json_out.toOwnedSlice();
    defer allocator.free(complete_json);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"tag\":\"Accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"tag\":\"Security Center Insights\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"status\":\"typed\"") != null);
}

test "renders broad provider coverage workplan commands by tag" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"closed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/segments","operation_id":"Reach_getSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeWorkplanTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 2,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage workplan\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Workers: priority=1 pending_reads=1 diagnostic_blocked_reads=0 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "routes: cloudio coverage routes cloudflare 'Workers' --detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "capture-candidates: cloudio coverage capture-candidates cloudflare 'Workers' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dry-run-candidates: cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | DNS Records: priority=1 pending_reads=1 diagnostic_blocked_reads=0 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio coverage capture-candidates cloudflare 'DNS Records' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Tokens: priority=1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=3") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_workplan\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"routes_detail\",\"command\":\"cloudio coverage routes cloudflare 'Workers' --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"capture_candidates\",\"command\":\"cloudio coverage capture-candidates cloudflare 'Workers' --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"dry_run_candidates\",\"command\":\"cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Reach: Segments\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"closed_or_evidence_only_rows_hidden\":3") != null);

    var plans_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plans_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 1,
        .include_plans = true,
    }, &plans_json_out.writer);
    const plans_json = try plans_json_out.toOwnedSlice();
    defer allocator.free(plans_json);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage routes cloudflare 'Workers' --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage capture-candidates cloudflare 'Workers' --limit 25 --plans\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25 --plans\"") == null);

    var bundle_json_out = std.Io.Writer.Allocating.init(allocator);
    defer bundle_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 1,
        .include_plans = true,
        .bundle_candidates = true,
        .candidate_limit = 1,
    }, &bundle_json_out.writer);
    const bundle_json = try bundle_json_out.toOwnedSlice();
    defer allocator.free(bundle_json);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"bundle_candidates\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"candidate_limit\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"candidate_bundle\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"capture\":{\"total\":1,\"visible\":1,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run\":{\"total\":0,\"visible\":0,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"capture_command\":\"cloudio route capture cloudflare --operation workers-list --path-param account_id=<account_id>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"read_plan\":{\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run_command\":\"cloudio route dry-run cloudflare --operation workers-create --path-param account_id=<account_id> --body-content-type application/json\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run_plan\":{\"provider\":\"cloudflare\"") == null);

    var focused_out = std.Io.Writer.Allocating.init(allocator);
    defer focused_out.deinit();
    try writeWorkplanTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
        .focus = .control_plane,
    }, &focused_out.writer);
    const focused_text = try focused_out.toOwnedSlice();
    defer allocator.free(focused_text);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "filter=all focus=control-plane family=all limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | DNS Records: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "family=dns") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | Tokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "Reach: Segments") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "focus_filtered_rows_hidden=1") != null);

    var focused_json_out = std.Io.Writer.Allocating.init(allocator);
    defer focused_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
        .focus = .control_plane,
    }, &focused_json_out.writer);
    const focused_json = try focused_json_out.toOwnedSlice();
    defer allocator.free(focused_json);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"family\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus_family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"Workers\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"Tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus_filtered_rows_hidden\":1") != null);

    const family_cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\
    ;

    var family_text_out = std.Io.Writer.Allocating.init(allocator);
    defer family_text_out.deinit();
    try writeWorkplanTextFromText(allocator, family_cloudflare, "", .{
        .provider = .all,
        .limit = 0,
        .family = .dns,
    }, &family_text_out.writer);
    const family_text = try family_text_out.toOwnedSlice();
    defer allocator.free(family_text);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "filter=all focus=control-plane family=dns limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | DNS Records: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | Tokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "focus_filtered_rows_hidden=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "closed_or_evidence_only_rows_hidden=1") != null);

    var family_json_out = std.Io.Writer.Allocating.init(allocator);
    defer family_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, family_cloudflare, "", .{
        .provider = .all,
        .limit = 0,
        .family = .dns,
    }, &family_json_out.writer);
    const family_json = try family_json_out.toOwnedSlice();
    defer allocator.free(family_json);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"tag\":\"Tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"closed_or_evidence_only_rows_hidden\":1") != null);
}

test "aggregates provider coverage evidence by control-plane family" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"POST","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-create","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not a control-plane family"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"diagnostic read"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeFamiliesTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "filter=all focus=control-plane limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | dns: priority=1 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dry_run_evidence=1 generated_dry_run_policy_evidence=1 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workplan: cloudio coverage workplan cloudflare --family dns --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | tokens: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger | hostinger-vps: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger | docker: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Workers") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 2,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_families\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag_count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"generated_dry_run_policy_evidence\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_mutation_dry_runs\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage workplan cloudflare --family dns --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"hostinger-vps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"docker\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visible\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":2") != null);
}

test "classifies Cloudflare logs without catalog or logo substring noise" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "AI Gateway Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Logpush jobs for a zone"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Logcontrol CMB config for an account"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Worker Tail Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Magic Network Monitoring VPC Flow logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "Catalog Sync"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "R2 Catalog Management"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "logo_match"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "Changelog"));
}

test "classifies broad Cloudflare control-plane read groups" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), workplanTagFamily("cloudflare", "Radar Certificate Transparency"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), workplanTagFamily("cloudflare", "mTLS Certificate Management"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .zones), workplanTagFamily("cloudflare", "Custom Hostname for a Zone"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .zones), workplanTagFamily("cloudflare", "Zone Snippets"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tunnels), workplanTagFamily("cloudflare", "Magic GRE tunnels"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tunnels), workplanTagFamily("cloudflare", "Magic IPsec tunnels"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), workplanTagFamily("cloudflare", "AI Search Tokens"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), workplanTagFamily("cloudflare", "Token Validation Token Rules"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .dns), workplanTagFamily("cloudflare", "DNS Internal Views for an Account"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .access), workplanTagFamily("cloudflare", "Infrastructure Access Targets"));
}

test "lists provider coverage routes by provider and tag query" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.MetricsResource"]},{"status":"401","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads VPS metrics."}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Catalog.CatalogItemCollection"]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads billing catalog."}
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Order.VirtualMachineOrderResource"]}],"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes in POC."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .tag_query = "vps", .support = .partial, .mode = .read });
    defer routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), routes.items.len);
    try std.testing.expectEqualStrings("hostinger", routes.items[0].route.provider.name());
    try std.testing.expectEqualStrings("VPS: Virtual machine", routes.items[0].route.tag);
    try std.testing.expectEqual(provider_routes.Method.GET, routes.items[0].route.method);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try routes.writeText(&out.writer, false);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage routes\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /api/vps/v1/virtual-machines/{virtualMachineId}/metrics | support=partial mode=read") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Billing: Catalog") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines") == null);

    var detail_out = std.Io.Writer.Allocating.init(allocator);
    defer detail_out.deinit();
    try routes.writeText(&detail_out.writer, true);
    const detail_text = try detail_out.toOwnedSlice();
    defer allocator.free(detail_text);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "path_params: virtualMachineId(required)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "query_params: date_from(required), date_to(required)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "request_body: required=false content_types=none schema_refs=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "200 content_types=application/json schema_refs=#/components/schemas/VPS.V1.VirtualMachine.MetricsResource") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try routes.writeJson(&json_out.writer, .{ .provider = .hostinger, .tag_query = "vps", .support = .partial, .mode = .read });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_routes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"filter\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path_params\":[{\"name\":\"virtualMachineId\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"query_params\":[{\"name\":\"date_from\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_body\":{\"required\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"responses\":[{\"status\":\"200\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"security\":{\"required\":false") != null);

    var mutations = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .support = .unsafe_mutation, .mode = .dry_run });
    defer mutations.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), mutations.items.len);
    try std.testing.expectEqual(provider_routes.Method.POST, mutations.items[0].route.method);

    var family_routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .family = .hostinger_vps });
    defer family_routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), family_routes.items.len);
    for (family_routes.items) |row| {
        try std.testing.expectEqualStrings("VPS: Virtual machine", row.route.tag);
    }

    var exact_operation = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .operation_id = "VPS_getMetricsV1" });
    defer exact_operation.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), exact_operation.items.len);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines/{virtualMachineId}/metrics", exact_operation.items[0].route.path_template);

    var exact_method_path = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .method = .GET, .path_template = "/api/billing/v1/catalog" });
    defer exact_method_path.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), exact_method_path.items.len);
    try std.testing.expectEqualStrings("billing_getCatalogItemListV1", exact_method_path.items[0].route.operation_id.?);

    var mismatched_method = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .method = .POST, .path_template = "/api/billing/v1/catalog" });
    defer mismatched_method.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), mismatched_method.items.len);
}

test "captures generic route read results into snapshots and provider raw" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.VirtualMachineCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC lists VPS."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .operation_id = "VPS_getVirtualMachinesV1" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8, "{\"password\":\"super-secret-password\",\"data\":[{\"id\":1307809,\"hostname\":\"srv1307809.hstgr.cloud\",\"state\":\"running\"}]}");
    const result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{},
        result,
        .{ .kind = "route-vps-inventory", .target = "test-vps-list" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider_raw\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshot_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"route-vps-inventory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"target\":\"test-vps-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "super-secret-password") == null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_vps"));
    var resource_rows = try db.hostingerResourceList(allocator);
    defer resource_rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), resource_rows.items.len);
    try std.testing.expectEqualStrings("route-vps-inventory/1307809", resource_rows.items[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resource_rows.items[0].value, "running srv1307809.hstgr.cloud") != null);
}

test "captures Cloudflare DNS route into typed records table" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-dns-records.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records for a Zone","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":[]}}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "dns-records-for-a-zone-list-dns-records" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8,
        \\{"result":[{"id":"dns-1","name":"plosca.ru","type":"A","content":"76.13.130.170","ttl":1,"proxied":false}],"success":true,"errors":[],"messages":[]}
    );
    const result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{ .path_params = &.{.{ .name = "zone_id", .value = "zone-1" }} },
        result,
        .{ .kind = "route-cloudflare-dns-records", .target = "zone-1" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_dns_records"));
}

test "captures Cloudflare security route into typed security table" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-security.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/allow_policies","operation_id":"email-security-list-allow-policies","path_params":[{"name":"account_id","required":true}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "email-security-list-allow-policies" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8,
        \\{"result":[{"policy_id":"policy-1","name":"Trusted sender","is_enabled":true,"action":"allow","pattern":"*@example.com","domain":"example.com","created_at":"2026-06-17T00:00:00Z"}],"success":true,"errors":[],"messages":[]}
    );
    const result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{ .path_params = &.{.{ .name = "account_id", .value = "acct-1" }} },
        result,
        .{ .kind = "route-cloudflare-email-security", .target = "acct-1" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_security_items"));
}
