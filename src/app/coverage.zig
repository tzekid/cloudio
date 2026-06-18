const std = @import("std");
const collector_capture = @import("collector_capture");
const collector_capture_normalize = @import("collector_capture_normalize");
const core_json = @import("core_json");
const db_store = @import("db_store");
const net_pagination = @import("net_pagination");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const max_manifest_bytes = 8 * 1024 * 1024;
const default_capture_max_pages = 25;
const actual_capture_load_limit: i64 = 100_000;
const actual_capture_hostinger_vps_hint_limit: i64 = 50;

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
pub const CaptureOptions = struct {
    kind: ?[]const u8 = null,
    target: ?[]const u8 = null,
    paginate: bool = false,
    max_pages: usize = default_capture_max_pages,
};
pub const DbHandle = Db;

const CapturedRoutePage = struct {
    page: usize,
    endpoint: []u8,
    snapshot_id: i64,
    http_status: u16,
    status_text: []const u8,
    body_bytes: usize,
    normalized_resources: usize,
    typed_rows: usize,
    pagination_envelope: ?net_pagination.Envelope,
    data_len: ?usize,
    has_next: bool,

    fn deinit(self: CapturedRoutePage, gpa: Allocator) void {
        gpa.free(self.endpoint);
    }
};

const CapturePageRef = union(enum) {
    page: usize,
    cursor: usize,

    fn index(self: CapturePageRef) usize {
        return switch (self) {
            .page => |value| value,
            .cursor => |value| value,
        };
    }
};

pub const Paths = struct {
    cloudflare_manifest: []const u8 = "coverage/generated/cloudflare.jsonl",
    hostinger_manifest: []const u8 = "coverage/generated/hostinger.jsonl",
};

pub const ProviderFilter = provider_routes.ProviderFilter;

pub const SupportFilter = enum {
    implemented,
    partial,
    planned,
    blocked_permission,
    unsafe_mutation,
    deprecated,
    not_applicable,

    pub fn parse(value: []const u8) ?SupportFilter {
        if (std.mem.eql(u8, value, "implemented")) return .implemented;
        if (std.mem.eql(u8, value, "partial")) return .partial;
        if (std.mem.eql(u8, value, "planned")) return .planned;
        if (std.mem.eql(u8, value, "blocked_permission")) return .blocked_permission;
        if (std.mem.eql(u8, value, "unsafe_mutation")) return .unsafe_mutation;
        if (std.mem.eql(u8, value, "deprecated")) return .deprecated;
        if (std.mem.eql(u8, value, "not_applicable")) return .not_applicable;
        return null;
    }

    pub fn name(self: SupportFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: SupportFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }
};

pub const ModeFilter = enum {
    read,
    dry_run,
    write,
    none,

    pub fn parse(value: []const u8) ?ModeFilter {
        if (std.mem.eql(u8, value, "read")) return .read;
        if (std.mem.eql(u8, value, "dry_run")) return .dry_run;
        if (std.mem.eql(u8, value, "write")) return .write;
        if (std.mem.eql(u8, value, "none")) return .none;
        return null;
    }

    pub fn name(self: ModeFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: ModeFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }
};

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

pub const WorkplanFamily = enum {
    all,
    accounts,
    memberships,
    iam,
    tokens,
    zones,
    dns,
    ssl_tls,
    access,
    tunnels,
    rulesets,
    logs,
    cache,
    security,
    billing,
    domains,
    hosting,
    docker,
    hostinger_vps,
    public_keys,
    custom_pages,
    healthchecks,
    load_balancing,

    pub fn parse(value: []const u8) ?WorkplanFamily {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "accounts") or std.mem.eql(u8, value, "account")) return .accounts;
        if (std.mem.eql(u8, value, "memberships") or std.mem.eql(u8, value, "membership")) return .memberships;
        if (std.mem.eql(u8, value, "iam")) return .iam;
        if (std.mem.eql(u8, value, "tokens") or std.mem.eql(u8, value, "token")) return .tokens;
        if (std.mem.eql(u8, value, "zones") or std.mem.eql(u8, value, "zone")) return .zones;
        if (std.mem.eql(u8, value, "dns")) return .dns;
        if (std.mem.eql(u8, value, "ssl-tls") or std.mem.eql(u8, value, "ssl_tls") or std.mem.eql(u8, value, "ssl") or std.mem.eql(u8, value, "tls")) return .ssl_tls;
        if (std.mem.eql(u8, value, "access")) return .access;
        if (std.mem.eql(u8, value, "tunnels") or std.mem.eql(u8, value, "tunnel")) return .tunnels;
        if (std.mem.eql(u8, value, "rulesets") or std.mem.eql(u8, value, "ruleset") or std.mem.eql(u8, value, "rules-lists") or std.mem.eql(u8, value, "rules_lists")) return .rulesets;
        if (std.mem.eql(u8, value, "logs") or std.mem.eql(u8, value, "log")) return .logs;
        if (std.mem.eql(u8, value, "cache") or std.mem.eql(u8, value, "caching")) return .cache;
        if (std.mem.eql(u8, value, "security") or std.mem.eql(u8, value, "security-posture") or std.mem.eql(u8, value, "security_posture")) return .security;
        if (std.mem.eql(u8, value, "billing")) return .billing;
        if (std.mem.eql(u8, value, "domains") or std.mem.eql(u8, value, "domain")) return .domains;
        if (std.mem.eql(u8, value, "hosting")) return .hosting;
        if (std.mem.eql(u8, value, "docker")) return .docker;
        if (std.mem.eql(u8, value, "hostinger-vps") or std.mem.eql(u8, value, "hostinger_vps") or std.mem.eql(u8, value, "vps")) return .hostinger_vps;
        if (std.mem.eql(u8, value, "public-keys") or std.mem.eql(u8, value, "public_keys") or std.mem.eql(u8, value, "keys")) return .public_keys;
        if (std.mem.eql(u8, value, "custom-pages") or std.mem.eql(u8, value, "custom_pages")) return .custom_pages;
        if (std.mem.eql(u8, value, "healthchecks") or std.mem.eql(u8, value, "healthcheck")) return .healthchecks;
        if (std.mem.eql(u8, value, "load-balancing") or std.mem.eql(u8, value, "load_balancing") or std.mem.eql(u8, value, "load-balancers") or std.mem.eql(u8, value, "load_balancers")) return .load_balancing;
        return null;
    }

    pub fn name(self: WorkplanFamily) []const u8 {
        return switch (self) {
            .all => "all",
            .accounts => "accounts",
            .memberships => "memberships",
            .iam => "iam",
            .tokens => "tokens",
            .zones => "zones",
            .dns => "dns",
            .ssl_tls => "ssl-tls",
            .access => "access",
            .tunnels => "tunnels",
            .rulesets => "rulesets",
            .logs => "logs",
            .cache => "cache",
            .security => "security",
            .billing => "billing",
            .domains => "domains",
            .hosting => "hosting",
            .docker => "docker",
            .hostinger_vps => "hostinger-vps",
            .public_keys => "public-keys",
            .custom_pages => "custom-pages",
            .healthchecks => "healthchecks",
            .load_balancing => "load-balancing",
        };
    }
};

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

pub const RouteFilter = struct {
    provider: ProviderFilter = .all,
    tag_query: ?[]const u8 = null,
    family: WorkplanFamily = .all,
    operation_id: ?[]const u8 = null,
    method: ?provider_routes.Method = null,
    path_template: ?[]const u8 = null,
    support: ?SupportFilter = null,
    mode: ?ModeFilter = null,
    detail: bool = false,
};

pub const CaptureCandidateOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
};

pub const ActualCaptureOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
};

pub const ActualReadyCaptureOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    max_pages: usize = default_capture_max_pages,
    execute: bool = false,
};

pub const DryRunCandidateOptions = struct {
    filter: RouteFilter = .{},
    limit: usize = 25,
    include_plans: bool = false,
};

pub fn parseRouteMethod(value: []const u8) ?provider_routes.Method {
    return provider_routes.Method.parse(value);
}

pub fn parsePathParamAssignment(value: []const u8) !PathParam {
    return provider_routes.parsePathParamAssignment(value);
}

pub fn parseQueryParamAssignment(value: []const u8) !QueryParam {
    return provider_routes.parseQueryParamAssignment(value);
}

pub fn parseHeaderParamAssignment(value: []const u8) !HeaderParam {
    return provider_routes.parseHeaderParamAssignment(value);
}

pub const RoutePlanInput = struct {
    filter: RouteFilter,
    request: Request = .{},
};

pub const CoverageRoute = struct {
    route: provider_routes.Route,
    tests: []u8,
    notes: []u8,

    pub fn init(gpa: Allocator, provider: []const u8, value: std.json.Value) !CoverageRoute {
        const expected_provider = provider_routes.Provider.parse(provider) orelse return error.InvalidCoverageProvider;
        const route = try provider_routes.Route.init(gpa, expected_provider, value);
        errdefer route.deinit(gpa);
        const tests = core_json.fieldString(value, "tests") orelse return error.InvalidCoverageRow;
        const notes = core_json.fieldString(value, "notes") orelse return error.InvalidCoverageRow;
        const tests_owned = try gpa.dupe(u8, tests);
        errdefer gpa.free(tests_owned);
        const notes_owned = try gpa.dupe(u8, notes);
        errdefer gpa.free(notes_owned);

        return .{
            .route = route,
            .tests = tests_owned,
            .notes = notes_owned,
        };
    }

    pub fn deinit(self: CoverageRoute, gpa: Allocator) void {
        self.route.deinit(gpa);
        gpa.free(self.tests);
        gpa.free(self.notes);
    }
};

pub const CoverageRoutes = struct {
    items: []CoverageRoute,

    pub fn deinit(self: *CoverageRoutes, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: CoverageRoutes, writer: anytype, detail: bool) !void {
        try writer.writeAll("Cloudio provider coverage routes\n");
        if (self.items.len == 0) {
            try writer.writeAll("no matching routes\n");
            return;
        }

        var current_provider: ?[]const u8 = null;
        var current_tag: ?[]const u8 = null;
        for (self.items) |row| {
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
            try writer.print("    {s} {s} | support={s} mode={s} tests={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support), @tagName(row.route.mode), row.tests });
            if (row.route.deprecated) try writer.writeAll(" deprecated=true");
            if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
            try writer.writeByte('\n');
            if (detail) try writeRouteDetail(writer, row.route);
            if (row.notes.len != 0) try writer.print("      notes: {s}\n", .{row.notes});
        }
    }

    pub fn writeJson(self: CoverageRoutes, writer: anytype, filter: RouteFilter) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_routes", true);
        try writer.writeAll("\"filter\":");
        try writeRouteFilterJson(filter, writer);
        try writer.writeByte(',');
        try writeJsonCountField(writer, "count", self.items.len, true);
        try writer.writeAll("\"routes\":[");
        var first = true;
        for (self.items) |row| {
            try writeMaybeJsonComma(writer, &first);
            try writeCoverageRouteJson(row, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

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

const ActualCapturePlan = struct {
    options: ActualCaptureOptions,
    routes: CoverageRoutes,
    captures: db_store.RouteCaptureEvidenceRows,
    hostinger_vps: ?db_store.HostingerVpsRows,

    fn deinit(self: *ActualCapturePlan, gpa: Allocator) void {
        if (self.hostinger_vps) |*rows| rows.deinit(gpa);
        self.captures.deinit(gpa);
        self.routes.deinit(gpa);
    }

    fn hostingerRows(self: ActualCapturePlan) []const db_store.HostingerVpsRow {
        if (self.hostinger_vps) |rows| return rows.items;
        return &.{};
    }

    fn totals(self: ActualCapturePlan) ActualCaptureTotals {
        var out = ActualCaptureTotals{};
        const hostinger_rows = self.hostingerRows();
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
                    if (actualCaptureReady(row.route, hostinger_rows)) out.ready_candidates += 1;
                },
                .non_ok => {
                    out.non_ok_read_routes += 1;
                    out.candidate_routes += 1;
                    if (actualCaptureReady(row.route, hostinger_rows)) out.ready_candidates += 1;
                },
            }
        }
        return out;
    }

    fn writeText(self: ActualCapturePlan, gpa: Allocator, writer: anytype) !void {
        const totals_value = self.totals();
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
        try writer.print("loaded_capture_operation_status_rows={d} hostinger_vps_hints={d}\n", .{ self.captures.items.len, self.hostingerRows().len });
        try writer.print("summary official_read_routes={d} ok_read_routes={d} non_ok_read_routes={d} missing_read_routes={d} candidate_routes={d} ready_candidates={d} capture_events={d}\n", .{
            totals_value.official_read_routes,
            totals_value.ok_read_routes,
            totals_value.non_ok_read_routes,
            totals_value.missing_read_routes,
            totals_value.candidate_routes,
            totals_value.ready_candidates,
            totals_value.capture_events,
        });

        var visible: usize = 0;
        var omitted: usize = 0;
        var current_provider: ?[]const u8 = null;
        var current_tag: ?[]const u8 = null;
        const hostinger_rows = self.hostingerRows();
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
                if (actualCaptureReady(row.route, hostinger_rows)) "true" else "false",
                if (provider_dispatch.routeLiveCallSupported(row.route)) "true" else "false",
            });
            try writeActualMissingInputsText(writer, row.route, hostinger_rows);
            try writer.writeByte('\n');
            const command = try actualCaptureCommand(gpa, row.route, hostinger_rows);
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
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_actual_captures", true);
        try writer.writeAll("\"filter\":");
        try writeRouteFilterJson(actualCaptureRouteFilter(self.options.filter), writer);
        try writer.writeByte(',');
        try writeJsonCountField(writer, "limit", self.options.limit, true);
        try writeJsonBoolField(writer, "include_plans", self.options.include_plans, true);
        try writeJsonField(writer, "rank", "official GET/read routes missing an OK route.capture audit event", true);
        try writeJsonCountField(writer, "loaded_capture_operation_status_rows", self.captures.items.len, true);
        try writeJsonCountField(writer, "hostinger_vps_hints", self.hostingerRows().len, true);
        try writer.writeAll("\"summary\":");
        try writeActualCaptureTotalsJson(totals_value, writer);
        try writer.writeAll(",\"candidates\":[");

        var visible: usize = 0;
        var omitted: usize = 0;
        var first = true;
        const hostinger_rows = self.hostingerRows();
        for (self.routes.items) |row| {
            const state = actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            if (self.options.limit != 0 and visible >= self.options.limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writeMaybeJsonComma(writer, &first);
            try writeActualCaptureCandidateJson(gpa, row, state, self.captures.items, hostinger_rows, self.options, writer);
        }

        try writer.writeAll("],");
        try writeJsonCountField(writer, "visible", visible, true);
        try writeJsonCountField(writer, "omitted", omitted, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
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

    pub fn init(name: []const u8) L1ProviderAudit {
        return .{ .name = name };
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
            .cloudflare = L1ProviderAudit.init("cloudflare"),
            .hostinger = L1ProviderAudit.init("hostinger"),
        };
    }

    pub fn totalFailures(self: L1Audit, filter: ProviderFilter) usize {
        var count: usize = 0;
        if (filter.includes("cloudflare")) count += self.cloudflare.failures.total();
        if (filter.includes("hostinger")) count += self.hostinger.failures.total();
        return count;
    }

    pub fn writeText(self: L1Audit, filter: ProviderFilter, writer: anytype) !void {
        try writer.writeAll("Cloudio provider L1 routability audit\n");
        try writer.print("status: {s}\n", .{if (self.totalFailures(filter) == 0) "pass" else "fail"});
        if (filter.includes("cloudflare")) try writeL1ProviderAudit(self.cloudflare, writer);
        if (filter.includes("hostinger")) try writeL1ProviderAudit(self.hostinger, writer);
    }

    pub fn writeJson(self: L1Audit, filter: ProviderFilter, writer: anytype) !void {
        const total_failures = self.totalFailures(filter);
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_l1_audit", true);
        try writeJsonField(writer, "filter", filter.name(), true);
        try writeJsonField(writer, "status", if (total_failures == 0) "pass" else "fail", true);
        try writeJsonBoolField(writer, "passed", total_failures == 0, true);
        try writeJsonCountField(writer, "total_failures", total_failures, true);
        try writeJsonField(writer, "evidence", "generated manifest route contracts checked against Cloudio generic dispatch invariants", true);
        try writer.writeAll("\"providers\":[");
        var wrote_provider = false;
        if (filter.includes("cloudflare")) {
            try writeL1ProviderAuditJson(self.cloudflare, writer);
            wrote_provider = true;
        }
        if (filter.includes("hostinger")) {
            if (wrote_provider) try writer.writeByte(',');
            try writeL1ProviderAuditJson(self.hostinger, writer);
        }
        try writer.writeAll("]}");
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
    var audit = L1Audit.init();
    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try auditProviderL1(gpa, "cloudflare", text, &audit.cloudflare);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try auditProviderL1(gpa, "hostinger", text, &audit.hostinger);
    }
    return audit;
}

pub fn auditL1FromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !L1Audit {
    var audit = L1Audit.init();
    if (filter.includes("cloudflare")) try auditProviderL1(gpa, "cloudflare", cloudflare_text, &audit.cloudflare);
    if (filter.includes("hostinger")) try auditProviderL1(gpa, "hostinger", hostinger_text, &audit.hostinger);
    return audit;
}

pub fn writeL1AuditTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const audit = try auditL1(io, gpa, paths, filter);
    try audit.writeText(filter, writer);
}

pub fn writeL1AuditJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    const audit = try auditL1(io, gpa, paths, filter);
    try audit.writeJson(filter, writer);
}

pub fn loadRoutes(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter) !CoverageRoutes {
    var rows = std.ArrayList(CoverageRoute).empty;
    errdefer deinitRouteList(&rows, gpa);

    if (filter.provider.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try appendProviderRoutes(gpa, "cloudflare", text, filter, &rows);
    }
    if (filter.provider.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try appendProviderRoutes(gpa, "hostinger", text, filter, &rows);
    }

    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: RouteFilter) !CoverageRoutes {
    var rows = std.ArrayList(CoverageRoute).empty;
    errdefer deinitRouteList(&rows, gpa);
    if (filter.provider.includes("cloudflare")) try appendProviderRoutes(gpa, "cloudflare", cloudflare_text, filter, &rows);
    if (filter.provider.includes("hostinger")) try appendProviderRoutes(gpa, "hostinger", hostinger_text, filter, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeRoutesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    var routes = try loadRoutes(io, gpa, paths, filter);
    defer routes.deinit(gpa);
    try routes.writeText(writer, filter.detail);
}

pub fn writeRoutesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    var routes = try loadRoutes(io, gpa, paths, filter);
    defer routes.deinit(gpa);
    try routes.writeJson(writer, filter);
}

pub fn writeCaptureCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesJson(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeCaptureCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    var routes = try loadCaptureCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeCaptureCandidatesJson(gpa, routes.items, options, writer);
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
    });
    defer plan.deinit(gpa);
    return try actualReadyCaptureJson(io, gpa, db, auth, plan, options);
}

pub fn writeDryRunCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutes(io, gpa, paths, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesJson(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesText(gpa, routes.items, options, writer);
}

pub fn writeDryRunCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    var routes = try loadDryRunCandidateRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer routes.deinit(gpa);
    try writeDryRunCandidatesJson(gpa, routes.items, options, writer);
}

fn loadCaptureCandidateRoutes(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions) !CoverageRoutes {
    const filter = captureCandidateRouteFilter(options.filter);
    return try loadRoutes(io, gpa, paths, filter);
}

fn loadCaptureCandidateRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions) !CoverageRoutes {
    const filter = captureCandidateRouteFilter(options.filter);
    return try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

fn loadActualCapturePlanFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions) !ActualCapturePlan {
    var routes = try loadRoutes(io, gpa, paths, actualCaptureRouteFilter(options.filter));
    errdefer routes.deinit(gpa);
    var captures = try db.routeCaptureEvidence(gpa, .{
        .provider = actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_load_limit,
    });
    errdefer captures.deinit(gpa);
    var hostinger_vps = try loadActualCaptureHostingerHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_vps) |*rows| rows.deinit(gpa);
    return .{
        .options = options,
        .routes = routes,
        .captures = captures,
        .hostinger_vps = hostinger_vps,
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
    var hostinger_vps = try loadActualCaptureHostingerHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_vps) |*rows| rows.deinit(gpa);
    return .{
        .options = options,
        .routes = routes,
        .captures = captures,
        .hostinger_vps = hostinger_vps,
    };
}

fn loadActualCaptureHostingerHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerVpsRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerVpsRows(gpa, actual_capture_hostinger_vps_hint_limit);
}

fn actualCaptureProviderDbValue(provider: ProviderFilter) ?[]const u8 {
    return switch (provider) {
        .all => null,
        .cloudflare => "cloudflare",
        .hostinger => "hostinger",
    };
}

fn loadDryRunCandidateRoutes(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions) !CoverageRoutes {
    const filter = dryRunCandidateRouteFilter(options.filter);
    return try loadRoutes(io, gpa, paths, filter);
}

fn loadDryRunCandidateRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions) !CoverageRoutes {
    const filter = dryRunCandidateRouteFilter(options.filter);
    return try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn routePlanJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput) ![]u8 {
    var routes = try loadRoutes(io, gpa, paths, input.filter);
    defer routes.deinit(gpa);
    return try routePlanJsonFromRoutes(gpa, routes.items, input.request);
}

pub fn routeReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadRoutes(io, gpa, paths, input.filter);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items);
    const client = provider_dispatch.Client.init(auth);
    const result = try client.callReadRouteResultRequest(io, gpa, route.route, input.request);
    defer result.deinit(gpa);
    return try provider_dispatch.readRouteResultMetadataJson(gpa, route.route, result);
}

pub fn routeCaptureReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    var routes = try loadRoutes(io, gpa, paths, input.filter);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items);
    const client = provider_dispatch.Client.init(auth);
    if (options.paginate) return try capturePaginatedRouteReadMetadataJson(io, gpa, db, client, route.route, input.request, options);
    const result = try client.callReadRouteResultRequest(io, gpa, route.route, input.request);
    defer result.deinit(gpa);
    return try captureRouteReadResultJson(gpa, db, route.route, input.request, result, options);
}

pub fn routeDryRunJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadRoutes(io, gpa, paths, input.filter);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items);
    const client = provider_dispatch.Client.init(auth);
    return try client.dryRunRouteRequest(gpa, route.route, input.request);
}

pub fn routeDryRunJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput, auth: Auth) ![]u8 {
    var routes = try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, input.filter);
    defer routes.deinit(gpa);
    const route = try selectSingleRoute(routes.items);
    const client = provider_dispatch.Client.init(auth);
    return try client.dryRunRouteRequest(gpa, route.route, input.request);
}

pub fn routePlanJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput) ![]u8 {
    var routes = try loadRoutesFromText(gpa, cloudflare_text, hostinger_text, input.filter);
    defer routes.deinit(gpa);
    return try routePlanJsonFromRoutes(gpa, routes.items, input.request);
}

pub fn captureRouteReadResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions) ![]u8 {
    const captured = try captureRouteReadPageResult(gpa, db, route, request, result, options, null);
    defer captured.deinit(gpa);
    return try routeCaptureMetadataJson(gpa, route, result, captured.snapshot_id, captured.endpoint, options.kind orelse route.operation_id orelse route.path_template, options.target orelse captured.endpoint, captured.normalized_resources, captured.typed_rows);
}

fn capturePaginatedRouteReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    if (routeSupportsPageQuery(route)) return try capturePagePaginatedRouteReadMetadataJson(io, gpa, db, client, route, request, options);
    if (routeSupportsCursorQuery(route)) return try captureCursorPaginatedRouteReadMetadataJson(io, gpa, db, client, route, request, options);
    return error.RoutePaginationUnsupported;
}

fn capturePagePaginatedRouteReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    const max_pages = if (options.max_pages == 0) default_capture_max_pages else options.max_pages;
    var pages = std.ArrayList(CapturedRoutePage).empty;
    defer deinitCapturedPageList(&pages, gpa);

    var page: usize = 1;
    while (page <= max_pages) : (page += 1) {
        const page_request = try requestWithPage(gpa, request, page);
        defer page_request.deinit(gpa);
        const result = try client.callReadRouteResultRequest(io, gpa, route, page_request.request);
        defer result.deinit(gpa);
        const captured = try captureRouteReadPageResult(gpa, db, route, page_request.request, result, options, .{ .page = page });
        pages.append(gpa, captured) catch |err| {
            captured.deinit(gpa);
            return err;
        };

        const status = result.statusCode();
        if (status < 200 or status >= 300) break;
        const pagination = net_pagination.pageInfo(result.response.body) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try routePaginatedCaptureMetadataJson(gpa, route, pages.items, max_pages);
}

fn captureCursorPaginatedRouteReadMetadataJson(io: Io, gpa: Allocator, db: *Db, client: provider_dispatch.Client, route: provider_routes.Route, request: Request, options: CaptureOptions) ![]u8 {
    const max_pages = if (options.max_pages == 0) default_capture_max_pages else options.max_pages;
    var pages = std.ArrayList(CapturedRoutePage).empty;
    defer deinitCapturedPageList(&pages, gpa);

    var page_index: usize = 1;
    var next_cursor: ?[]u8 = null;
    defer if (next_cursor) |cursor| gpa.free(cursor);

    while (page_index <= max_pages) : (page_index += 1) {
        var owned_request: ?OwnedQueryRequest = null;
        defer if (owned_request) |owned| owned.deinit(gpa);
        const effective_request = if (next_cursor) |cursor| blk: {
            owned_request = try requestWithCursor(gpa, request, cursor);
            break :blk owned_request.?.request;
        } else request;

        const result = try client.callReadRouteResultRequest(io, gpa, route, effective_request);
        defer result.deinit(gpa);
        const captured = try captureRouteReadPageResult(gpa, db, route, effective_request, result, options, .{ .cursor = page_index });
        pages.append(gpa, captured) catch |err| {
            captured.deinit(gpa);
            return err;
        };

        const status = result.statusCode();
        if (status < 200 or status >= 300) break;
        var cursor_info = (try net_pagination.cursorInfo(gpa, result.response.body)) orelse break;
        defer cursor_info.deinit(gpa);
        if (!cursor_info.hasNext()) break;
        const cursor_value = cursor_info.next_cursor orelse break;
        if (next_cursor) |old| gpa.free(old);
        next_cursor = try gpa.dupe(u8, cursor_value);
    }

    return try routePaginatedCaptureMetadataJson(gpa, route, pages.items, max_pages);
}

fn captureRouteReadPageResult(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_dispatch.ReadRouteResult, options: CaptureOptions, page_ref: ?CapturePageRef) !CapturedRoutePage {
    const endpoint = try captureEndpoint(gpa, route, request);
    errdefer gpa.free(endpoint);
    const operation = route.operation_id orelse route.path_template;
    const kind = options.kind orelse operation;
    const target = try captureTarget(gpa, options.target, endpoint, page_ref);
    defer if (target.owned) |owned| gpa.free(owned);
    const summary_label = try captureSummaryLabel(gpa, operation, page_ref);
    defer gpa.free(summary_label);
    const stored = try collector_capture.storeResponseWithSnapshotId(gpa, db, .{
        .provider = route.provider.name(),
        .kind = kind,
        .target = target.value,
        .summary_label = summary_label,
        .endpoint = endpoint,
        .status = result.response.status,
        .body = result.response.body,
    });
    defer stored.deinit(gpa);
    const normalized = try collector_capture_normalize.normalizeRouteCapture(gpa, db, route, request, kind, options.target, result.statusCode(), stored.redacted);
    const audit_detail = try std.fmt.allocPrint(gpa, "{s}/{s} {s}", .{ route.provider.name(), operation, endpoint });
    defer gpa.free(audit_detail);
    try db.insertAudit("route.capture", result.statusText(), audit_detail);
    const pagination = net_pagination.pageInfo(result.response.body);
    const cursor_info = try net_pagination.cursorInfo(gpa, result.response.body);
    defer if (cursor_info) |info| info.deinit(gpa);
    return .{
        .page = if (page_ref) |ref| ref.index() else 1,
        .endpoint = endpoint,
        .snapshot_id = stored.snapshot_id,
        .http_status = result.statusCode(),
        .status_text = result.statusText(),
        .body_bytes = result.response.body.len,
        .normalized_resources = normalized.resources,
        .typed_rows = normalized.typed_rows,
        .pagination_envelope = if (pagination) |info| info.envelope else if (cursor_info) |info| info.envelope else null,
        .data_len = if (pagination) |info| info.data_len else if (cursor_info) |info| info.data_len else null,
        .has_next = if (pagination) |info| info.hasNext() else if (cursor_info) |info| info.hasNext() else false,
    };
}

pub fn writeRoutePlanTextFromFiles(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, writer: anytype) !void {
    const json = try routePlanJson(io, gpa, paths, input);
    defer gpa.free(json);
    try writer.writeAll(json);
    try writer.writeByte('\n');
}

fn routePlanJsonFromRoutes(gpa: Allocator, routes: []const CoverageRoute, request: Request) ![]u8 {
    const route = try selectSingleRoute(routes);
    return try provider_dispatch.planRouteJsonRequest(gpa, route.route, request);
}

fn selectSingleRoute(routes: []const CoverageRoute) !CoverageRoute {
    if (routes.len == 0) return error.ProviderRoutePlanNotFound;
    if (routes.len != 1) return error.ProviderRoutePlanAmbiguous;
    return routes[0];
}

fn routeCaptureMetadataJson(gpa: Allocator, route: provider_routes.Route, result: provider_dispatch.ReadRouteResult, snapshot_id: i64, endpoint: []const u8, kind: []const u8, target: []const u8, normalized_resources: usize, typed_rows: usize) ![]u8 {
    const read_json = try provider_dispatch.readRouteResultMetadataJson(gpa, route, result);
    defer gpa.free(read_json);
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try writeJsonField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "endpoint", endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"captured\":true,");
    try writer.writeAll("\"provider_raw\":true,");
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{normalized_resources});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{typed_rows});
    try writer.writeByte(',');
    try writer.writeAll("\"snapshot\":{");
    try writeJsonField(writer, "source", route.provider.name(), true);
    try writeJsonField(writer, "kind", kind, true);
    try writeJsonField(writer, "target", target, false);
    try writer.writeAll("},");
    try writer.writeAll("\"read\":");
    try writer.writeAll(read_json);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn routePaginatedCaptureMetadataJson(gpa: Allocator, route: provider_routes.Route, pages: []const CapturedRoutePage, max_pages: usize) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "operation", route.operation_id orelse route.path_template, true);
    if (route.operation_id) |id| {
        try writeJsonField(writer, "operation_id", id, true);
    } else {
        try writer.writeAll("\"operation_id\":null,");
    }
    try writeJsonField(writer, "method", route.method.name(), true);
    try writer.writeAll("\"paginated\":true,");
    try writer.writeAll("\"captured_pages\":");
    try writer.print("{d}", .{pages.len});
    try writer.writeByte(',');
    try writer.writeAll("\"max_pages\":");
    try writer.print("{d}", .{max_pages});
    try writer.writeByte(',');
    try writer.writeAll("\"truncated\":");
    try writer.writeAll(if (pages.len >= max_pages and pages.len != 0 and pages[pages.len - 1].has_next) "true" else "false");
    try writer.writeByte(',');
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{normalizedResourceTotal(pages)});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{typedRowsTotal(pages)});
    try writer.writeByte(',');
    try writer.writeAll("\"body_included\":false,");
    try writer.writeAll("\"snapshots\":[");
    for (pages, 0..) |page, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{d}", .{page.snapshot_id});
    }
    try writer.writeAll("],\"pages\":[");
    for (pages, 0..) |page, index| {
        if (index != 0) try writer.writeByte(',');
        try writeCapturedPageJson(writer, page);
    }
    try writer.writeAll("]}");
    return try out.toOwnedSlice();
}

fn writeCapturedPageJson(writer: anytype, page: CapturedRoutePage) !void {
    try writer.writeAll("{\"page\":");
    try writer.print("{d}", .{page.page});
    try writer.writeByte(',');
    try writeJsonField(writer, "endpoint", page.endpoint, true);
    try writer.writeAll("\"snapshot_id\":");
    try writer.print("{d}", .{page.snapshot_id});
    try writer.writeByte(',');
    try writer.writeAll("\"http_status\":");
    try writer.print("{d}", .{page.http_status});
    try writer.writeByte(',');
    try writeJsonField(writer, "status_text", page.status_text, true);
    try writer.writeAll("\"body_bytes\":");
    try writer.print("{d}", .{page.body_bytes});
    try writer.writeByte(',');
    try writer.writeAll("\"normalized_resources\":");
    try writer.print("{d}", .{page.normalized_resources});
    try writer.writeByte(',');
    try writer.writeAll("\"typed_rows\":");
    try writer.print("{d}", .{page.typed_rows});
    try writer.writeByte(',');
    if (page.pagination_envelope) |envelope| {
        try writeJsonField(writer, "pagination_envelope", envelope.name(), true);
    } else {
        try writer.writeAll("\"pagination_envelope\":null,");
    }
    if (page.data_len) |data_len| {
        try writer.writeAll("\"data_len\":");
        try writer.print("{d}", .{data_len});
        try writer.writeByte(',');
    } else {
        try writer.writeAll("\"data_len\":null,");
    }
    try writer.writeAll("\"has_next\":");
    try writer.writeAll(if (page.has_next) "true" else "false");
    try writer.writeByte('}');
}

fn normalizedResourceTotal(pages: []const CapturedRoutePage) usize {
    var total: usize = 0;
    for (pages) |page| total += page.normalized_resources;
    return total;
}

fn typedRowsTotal(pages: []const CapturedRoutePage) usize {
    var total: usize = 0;
    for (pages) |page| total += page.typed_rows;
    return total;
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

const CaptureTarget = struct {
    value: []const u8,
    owned: ?[]u8 = null,
};

fn captureTarget(gpa: Allocator, base_target: ?[]const u8, endpoint: []const u8, page_ref: ?CapturePageRef) !CaptureTarget {
    const ref = page_ref orelse return .{ .value = base_target orelse endpoint };
    if (base_target) |target| {
        const owned = switch (ref) {
            .page => |page_value| try std.fmt.allocPrint(gpa, "{s}?page={d}", .{ target, page_value }),
            .cursor => |page_value| try std.fmt.allocPrint(gpa, "{s}?cursor_page={d}", .{ target, page_value }),
        };
        return .{ .value = owned, .owned = owned };
    }
    return .{ .value = endpoint };
}

fn captureSummaryLabel(gpa: Allocator, operation: []const u8, page_ref: ?CapturePageRef) ![]u8 {
    const ref = page_ref orelse return try gpa.dupe(u8, operation);
    return switch (ref) {
        .page => |page_value| try std.fmt.allocPrint(gpa, "{s} page {d}", .{ operation, page_value }),
        .cursor => |page_value| try std.fmt.allocPrint(gpa, "{s} cursor page {d}", .{ operation, page_value }),
    };
}

const OwnedQueryRequest = struct {
    request: Request,
    query_params: []provider_routes.QueryParam,
    value: []u8,

    fn deinit(self: OwnedQueryRequest, gpa: Allocator) void {
        gpa.free(self.query_params);
        gpa.free(self.value);
    }
};

fn requestWithPage(gpa: Allocator, request: Request, page: usize) !OwnedQueryRequest {
    const page_value = try std.fmt.allocPrint(gpa, "{d}", .{page});
    return try requestWithQueryOverrideOwned(gpa, request, "page", page_value);
}

fn requestWithCursor(gpa: Allocator, request: Request, cursor: []const u8) !OwnedQueryRequest {
    const cursor_value = try gpa.dupe(u8, cursor);
    return try requestWithQueryOverrideOwned(gpa, request, "cursor", cursor_value);
}

fn requestWithQueryOverrideOwned(gpa: Allocator, request: Request, name: []const u8, owned_value: []u8) !OwnedQueryRequest {
    errdefer gpa.free(owned_value);
    var query_count: usize = 1;
    for (request.query_params) |param| {
        if (!std.mem.eql(u8, param.name, name)) query_count += 1;
    }
    const query_params = try gpa.alloc(provider_routes.QueryParam, query_count);
    errdefer gpa.free(query_params);
    var index: usize = 0;
    for (request.query_params) |param| {
        if (std.mem.eql(u8, param.name, name)) continue;
        query_params[index] = param;
        index += 1;
    }
    query_params[index] = .{ .name = name, .value = owned_value };
    return .{
        .request = .{
            .path_params = request.path_params,
            .query_params = query_params,
            .header_params = request.header_params,
            .body = request.body,
        },
        .query_params = query_params,
        .value = owned_value,
    };
}

fn routeSupportsPageQuery(route: provider_routes.Route) bool {
    for (route.query_params) |param| {
        if (std.mem.eql(u8, param.name, "page")) return true;
    }
    return false;
}

fn routeSupportsCursorQuery(route: provider_routes.Route) bool {
    for (route.query_params) |param| {
        if (std.mem.eql(u8, param.name, "cursor")) return true;
    }
    return false;
}

fn captureEndpoint(gpa: Allocator, route: provider_routes.Route, request: Request) ![]u8 {
    const endpoint = try route.renderRequestPath(gpa, request);
    errdefer gpa.free(endpoint);
    if (!requestHasQueryParam(request, "cursor")) return endpoint;
    const sanitized = try redactedCursorEndpoint(gpa, endpoint);
    gpa.free(endpoint);
    return sanitized;
}

fn actualCaptureRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

fn captureCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

fn dryRunCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.mode = .dry_run;
    if (next.support == null) next.support = .unsafe_mutation;
    next.detail = false;
    return next;
}

fn routeIsCaptureCandidate(row: CoverageRoute, options: CaptureCandidateOptions) bool {
    const route = row.route;
    if (route.deprecated or !route.isRoutable()) return false;
    if (route.method != .GET or route.mode != .read) return false;
    if (route.request_body.required) return false;
    if (!std.mem.eql(u8, row.tests, "missing")) return false;
    if (options.filter.support != null) return true;
    return route.support == .planned or route.support == .blocked_permission;
}

fn routeIsDryRunCandidate(row: CoverageRoute, options: DryRunCandidateOptions) bool {
    const route = row.route;
    if (route.deprecated or !route.isRoutable()) return false;
    if (!route.isDryRunMutation()) return false;
    if (!std.mem.eql(u8, row.tests, "missing")) return false;
    if (hasGeneratedDryRunPolicyEvidence(row)) return false;
    if (options.filter.support != null) return true;
    return route.support == .unsafe_mutation;
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

fn actualCaptureReady(route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) bool {
    return provider_dispatch.routeLiveCallSupported(route) and actualCaptureMissingInputCount(route, hostinger_rows) == 0;
}

fn actualCaptureMissingInputCount(route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) usize {
    var count: usize = 0;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hostinger_rows) == null) count += 1;
    }
    for (route.query_params) |param| {
        if (param.required) count += 1;
    }
    for (route.header_params) |param| {
        if (param.required) count += 1;
    }
    return count;
}

fn actualCapturePathParamHint(route: provider_routes.Route, name: []const u8, hostinger_rows: []const db_store.HostingerVpsRow) ?[]const u8 {
    if (route.provider != .hostinger) return null;
    if (std.mem.eql(u8, name, "virtualMachineId") and hostinger_rows.len != 0) return hostinger_rows[0].id;
    return null;
}

fn writeActualMissingInputsText(writer: anytype, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) !void {
    var wrote = false;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hostinger_rows) != null) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("path:{s}", .{param.name});
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
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

fn writeActualMissingInputsJson(writer: anytype, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) !void {
    try writer.writeByte('[');
    var first = true;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hostinger_rows) != null) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "path", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
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

fn writeActualCaptureCandidateJson(
    gpa: Allocator,
    row: CoverageRoute,
    state: ActualCaptureState,
    captures: []const db_store.RouteCaptureEvidenceRow,
    hostinger_rows: []const db_store.HostingerVpsRow,
    options: ActualCaptureOptions,
    writer: anytype,
) !void {
    const route = row.route;
    const command = try actualCaptureCommand(gpa, route, hostinger_rows);
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
    try writeJsonBoolField(writer, "ready", actualCaptureReady(route, hostinger_rows), true);
    try writeJsonBoolField(writer, "live_read_supported", provider_dispatch.routeLiveCallSupported(route), true);
    try writer.writeAll("\"missing_inputs\":");
    try writeActualMissingInputsJson(writer, route, hostinger_rows);
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

fn actualCaptureCommand(gpa: Allocator, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) ![]u8 {
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
    try writeActualPathParams(writer, route, hostinger_rows);
    try writeActualRequiredParamPlaceholders(writer, "--query-param", route.query_params);
    try writeActualRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (routePaginationKind(route) != null) try writer.writeAll(" --paginate");
    return try out.toOwnedSlice();
}

fn writeActualPathParams(writer: anytype, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        try writer.print(" --path-param {s}=", .{param.name});
        if (actualCapturePathParamHint(route, param.name, hostinger_rows)) |hint| {
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
    omitted_ready: usize = 0,
    planned: usize = 0,
    attempted: usize = 0,
    captured: usize = 0,
    failed: usize = 0,
};

const ActualReadyRequest = struct {
    request: Request,
    path_params: []PathParam,

    fn deinit(self: ActualReadyRequest, gpa: Allocator) void {
        gpa.free(self.path_params);
    }
};

fn validateActualReadyCaptureProvider(auth: Auth, provider: ProviderFilter) !void {
    if (provider == .all) return error.ActualReadyCaptureProviderRequired;
    if (!provider.includes(auth.provider().name())) return error.ProviderRouteAuthMismatch;
}

fn actualReadyCaptureJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, plan: ActualCapturePlan, options: ActualReadyCaptureOptions) ![]u8 {
    const hostinger_rows = plan.hostingerRows();
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
        if (!actualCaptureReady(row.route, hostinger_rows)) {
            summary.skipped_unready += 1;
            continue;
        }
        summary.ready_routes += 1;
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
        try writeActualReadyCaptureItemJson(io, gpa, db, auth, row.route, state, hostinger_rows, options, &summary, items_writer);
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
    hostinger_rows: []const db_store.HostingerVpsRow,
    options: ActualReadyCaptureOptions,
    summary: *ActualReadyCaptureSummary,
    writer: anytype,
) !void {
    const command = try actualCaptureCommand(gpa, route, hostinger_rows);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "operation_id", route.operation_id orelse route.path_template, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonField(writer, "actual_state", state.name(), true);
    try writeJsonNullableStringField(writer, "pagination", routePaginationKind(route), true);
    try writeJsonField(writer, "capture_command", command, true);
    if (!options.execute) {
        try writeJsonField(writer, "status", "planned", false);
        try writer.writeByte('}');
        return;
    }

    const result_json = actualReadyCaptureRouteJson(io, gpa, db, auth, route, hostinger_rows, options) catch |err| {
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

fn actualReadyCaptureRouteJson(io: Io, gpa: Allocator, db: *Db, auth: Auth, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow, options: ActualReadyCaptureOptions) ![]u8 {
    if (!actualCaptureReady(route, hostinger_rows)) return error.ActualCaptureRouteNotReady;
    const owned_request = try actualReadyCaptureRequest(gpa, route, hostinger_rows);
    defer owned_request.deinit(gpa);
    const client = provider_dispatch.Client.init(auth);
    const capture_options = CaptureOptions{
        .paginate = routePaginationKind(route) != null,
        .max_pages = options.max_pages,
    };
    if (capture_options.paginate) return try capturePaginatedRouteReadMetadataJson(io, gpa, db, client, route, owned_request.request, capture_options);
    const result = try client.callReadRouteResultRequest(io, gpa, route, owned_request.request);
    defer result.deinit(gpa);
    return try captureRouteReadResultJson(gpa, db, route, owned_request.request, result, capture_options);
}

fn actualReadyCaptureRequest(gpa: Allocator, route: provider_routes.Route, hostinger_rows: []const db_store.HostingerVpsRow) !ActualReadyRequest {
    var path_params = std.ArrayList(PathParam).empty;
    errdefer path_params.deinit(gpa);
    for (route.path_params) |param| {
        if (!param.required) continue;
        const value = actualCapturePathParamHint(route, param.name, hostinger_rows) orelse return error.ActualCaptureRouteNotReady;
        try path_params.append(gpa, .{ .name = param.name, .value = value });
    }
    const owned_path_params = try path_params.toOwnedSlice(gpa);
    return .{
        .request = .{
            .path_params = owned_path_params,
            .query_params = &.{},
            .header_params = &.{},
            .body = .{},
        },
        .path_params = owned_path_params,
    };
}

fn writeCaptureCandidatesText(gpa: Allocator, routes: []const CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try writer.writeAll("Cloudio route capture candidates\n");
    try writer.writeAll("rank: generated bodyless GET/read routes missing L2 capture evidence\n");
    try writer.print("filter provider={s}", .{options.filter.provider.name()});
    if (options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
    if (options.filter.family != .all) try writer.print(" family={s}", .{options.filter.family.name()});
    if (options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
    if (options.include_plans) try writer.writeAll(" plans=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var current_provider: ?[]const u8 = null;
    var current_tag: ?[]const u8 = null;
    for (routes) |row| {
        if (!routeIsCaptureCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.route.provider.name())) {
            current_provider = row.route.provider.name();
            current_tag = null;
            try writer.print("\n{s}\n", .{row.route.provider.name()});
        }
        if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
            current_tag = row.route.tag;
            try writer.print("  {s}\n", .{row.route.tag});
        }
        try writer.print("    {s} {s} | support={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support) });
        if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
        try writer.writeByte('\n');
        try writer.writeAll("      required_path=");
        try writeRequiredParamNamesText(writer, row.route.path_params);
        try writer.writeAll(" required_query=");
        try writeRequiredParamNamesText(writer, row.route.query_params);
        try writer.writeAll(" required_header=");
        try writeRequiredParamNamesText(writer, row.route.header_params);
        try writer.print(" pagination={s}\n", .{routePaginationKind(row.route) orelse "none"});
        const command = try routeCaptureCommand(gpa, row.route);
        defer gpa.free(command);
        try writer.print("      capture: {s}\n", .{command});
        if (options.include_plans) {
            const plan = try routeReadPlanJson(gpa, row.route);
            defer gpa.free(plan);
            try writer.print("      read-plan: {s}\n", .{plan});
        }
    }

    if (total == 0) {
        try writer.writeAll("no capture candidates for filter\n");
    } else if (omitted != 0) {
        try writer.print("omitted={d}\n", .{omitted});
    }
}

fn writeCaptureCandidatesJson(gpa: Allocator, routes: []const CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_capture_candidates", true);
    try writer.writeAll("\"filter\":");
    try writeRouteFilterJson(captureCandidateRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeJsonField(writer, "rank", "generated bodyless GET/read routes missing L2 capture evidence", true);
    try writer.writeAll("\"candidates\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var first = true;
    for (routes) |row| {
        if (!routeIsCaptureCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeCaptureCandidateJson(gpa, row, options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "total_candidates", total, true);
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
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
    return workplanTagFamily(provider, tag) != null;
}

fn workplanTagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    if (std.mem.eql(u8, provider, "hostinger")) {
        if (tagContainsAny(tag, &.{ "Docker", "Container" })) return .docker;
        if (tagContainsAny(tag, &.{ "Malware", "Monarx", "Firewall", "Security" })) return .security;
        if (tagContainsAny(tag, &.{ "Public key", "SSH key" })) return .public_keys;
        if (tagContainsAny(tag, &.{ "VPS", "Virtual machine", "VirtualMachine", "Post-install" })) return .hostinger_vps;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{"Domain"})) return .domains;
        if (tagContainsAny(tag, &.{"Hosting"})) return .hosting;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        return null;
    }
    if (std.mem.eql(u8, provider, "cloudflare")) {
        if (tagContainsAny(tag, &.{ "Email Security", "Security Center", "Firewall", "WAF", "Bot", "Page Shield", "IP Access", "API Gateway", "Leaked Credential", "Vulnerability Scanner", "Security" })) return .security;
        if (tagContainsAny(tag, &.{"Token"})) return .tokens;
        if (tagContainsAny(tag, &.{"Membership"})) return .memberships;
        if (tagContainsAny(tag, &.{"IAM"})) return .iam;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{ "SSL", "TLS", "Certificate", "mTLS" })) return .ssl_tls;
        if (tagContainsAny(tag, &.{"Access"})) return .access;
        if (tagContainsAny(tag, &.{"Tunnel"})) return .tunnels;
        if (tagContainsAny(tag, &.{ "Ruleset", "Rules List" })) return .rulesets;
        if (cloudflareTagIsLogsFamily(tag)) return .logs;
        if (tagContainsAny(tag, &.{ "Cache", "Argo" })) return .cache;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        if (tagContainsAny(tag, &.{"Custom Pages"})) return .custom_pages;
        if (tagContainsAny(tag, &.{"Healthcheck"})) return .healthchecks;
        if (tagContainsAny(tag, &.{"Load Balancer"})) return .load_balancing;
        if (tagContainsAny(tag, &.{"Zone"})) return .zones;
        if (tagContainsAny(tag, &.{ "Account", "Organization", "User" })) return .accounts;
        return null;
    }
    return null;
}

fn tagContainsAny(tag: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (containsIgnoreCase(tag, needle)) return true;
    }
    return false;
}

fn cloudflareTagIsLogsFamily(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "AI Gateway Logs",
        "Audit Logs",
        "Instant Logs",
        "Log Explorer",
        "Logcontrol",
        "Logs",
        "Logpush",
        "Logs Received",
        "VPC Flow logs",
        "Worker Tail Logs",
    });
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

fn writeDryRunCandidatesText(gpa: Allocator, routes: []const CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try writer.writeAll("Cloudio route dry-run candidates\n");
    try writer.writeAll("rank: generated mutation routes missing dry-run review evidence\n");
    try writer.print("filter provider={s}", .{options.filter.provider.name()});
    if (options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
    if (options.filter.family != .all) try writer.print(" family={s}", .{options.filter.family.name()});
    if (options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
    if (options.include_plans) try writer.writeAll(" plans=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var current_provider: ?[]const u8 = null;
    var current_tag: ?[]const u8 = null;
    for (routes) |row| {
        if (!routeIsDryRunCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.route.provider.name())) {
            current_provider = row.route.provider.name();
            current_tag = null;
            try writer.print("\n{s}\n", .{row.route.provider.name()});
        }
        if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
            current_tag = row.route.tag;
            try writer.print("  {s}\n", .{row.route.tag});
        }
        try writer.print("    {s} {s} | support={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support) });
        if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
        try writer.writeByte('\n');
        try writer.writeAll("      required_path=");
        try writeRequiredParamNamesText(writer, row.route.path_params);
        try writer.writeAll(" required_query=");
        try writeRequiredParamNamesText(writer, row.route.query_params);
        try writer.writeAll(" required_header=");
        try writeRequiredParamNamesText(writer, row.route.header_params);
        try writer.print(" body_required={}", .{row.route.request_body.required});
        try writer.print(" body_content_type={s}", .{primaryRequestBodyContentType(row.route.request_body) orelse "none"});
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, row.route.request_body.schema_refs);
        try writer.writeByte('\n');
        const command = try routeDryRunCommand(gpa, row.route);
        defer gpa.free(command);
        try writer.print("      dry-run: {s}\n", .{command});
        if (options.include_plans) {
            const plan = try routeDryRunPlanJson(gpa, row.route);
            defer gpa.free(plan);
            try writer.print("      dry-run-plan: {s}\n", .{plan});
        }
    }

    if (total == 0) {
        try writer.writeAll("no dry-run candidates for filter\n");
    } else if (omitted != 0) {
        try writer.print("omitted={d}\n", .{omitted});
    }
}

fn writeDryRunCandidatesJson(gpa: Allocator, routes: []const CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_dry_run_candidates", true);
    try writer.writeAll("\"filter\":");
    try writeRouteFilterJson(dryRunCandidateRouteFilter(options.filter), writer);
    try writer.writeByte(',');
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_plans", options.include_plans, true);
    try writeJsonField(writer, "rank", "generated mutation routes missing dry-run review evidence", true);
    try writer.writeAll("\"candidates\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var total: usize = 0;
    var first = true;
    for (routes) |row| {
        if (!routeIsDryRunCandidate(row, options)) continue;
        total += 1;
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeDryRunCandidateJson(gpa, row, options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "total_candidates", total, true);
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

fn writeDryRunCandidateJson(gpa: Allocator, row: CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    const route = row.route;
    const command = try routeDryRunCommand(gpa, route);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "tests", row.tests, true);
    try writer.writeAll("\"required_path_params\":");
    try writeRequiredParamNamesJson(writer, route.path_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_query_params\":");
    try writeRequiredParamNamesJson(writer, route.query_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_header_params\":");
    try writeRequiredParamNamesJson(writer, route.header_params);
    try writer.writeByte(',');
    try writeJsonBoolField(writer, "body_required", route.request_body.required, true);
    try writeJsonNullableStringField(writer, "body_content_type", primaryRequestBodyContentType(route.request_body), true);
    try writer.writeAll("\"request_body_schema_refs\":");
    try writeJsonStringArray(writer, route.request_body.schema_refs);
    try writer.writeByte(',');
    try writeJsonField(writer, "dry_run_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try routeDryRunPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"dry_run_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

fn routeDryRunPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    const example = try route.exampleRequest(gpa);
    defer example.deinit(gpa);
    return try provider_dispatch.dryRunPlanJsonRequest(gpa, route, example.request);
}

fn writeCaptureCandidateJson(gpa: Allocator, row: CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    const route = row.route;
    const command = try routeCaptureCommand(gpa, route);
    defer gpa.free(command);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "tests", row.tests, true);
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
    try writeJsonField(writer, "capture_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try routeReadPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"read_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

fn routeReadPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    const example = try route.exampleRequest(gpa);
    defer example.deinit(gpa);
    return try provider_dispatch.planRouteJsonRequest(gpa, route, example.request);
}

fn routeCaptureCommand(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route capture {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path {s}", .{ route.method.name(), route.path_template });
    }
    try writeRequiredParamPlaceholders(writer, "--path-param", route.path_params);
    try writeRequiredParamPlaceholders(writer, "--query-param", route.query_params);
    try writeRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (routePaginationKind(route) != null) try writer.writeAll(" --paginate");
    return try out.toOwnedSlice();
}

fn routeDryRunCommand(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route dry-run {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path {s}", .{ route.method.name(), route.path_template });
    }
    try writeRequiredParamPlaceholders(writer, "--path-param", route.path_params);
    try writeRequiredParamPlaceholders(writer, "--query-param", route.query_params);
    try writeRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (primaryRequestBodyContentType(route.request_body)) |content_type| {
        try writer.print(" --body-content-type {s}", .{content_type});
    }
    return try out.toOwnedSlice();
}

fn primaryRequestBodyContentType(body: provider_routes.RequestBody) ?[]const u8 {
    if (body.content_types.len == 0) return null;
    return body.content_types[0];
}

fn routePaginationKind(route: provider_routes.Route) ?[]const u8 {
    if (routeSupportsPageQuery(route)) return "page";
    if (routeSupportsCursorQuery(route)) return "cursor";
    return null;
}

fn writeRequiredParamPlaceholders(writer: anytype, option: []const u8, params: []const provider_routes.RouteParam) !void {
    for (params) |param| {
        if (!param.required) continue;
        try writer.print(" {s} {s}=<{s}>", .{ option, param.name, param.name });
    }
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

fn requestHasQueryParam(request: Request, name: []const u8) bool {
    for (request.query_params) |param| {
        if (std.mem.eql(u8, param.name, name)) return true;
    }
    return false;
}

fn redactedCursorEndpoint(gpa: Allocator, endpoint: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    var first = true;
    var parts = std.mem.splitScalar(u8, endpoint, '&');
    while (parts.next()) |part| {
        if (!first) try out.writer.writeByte('&');
        first = false;
        if (isCursorQueryPart(part)) {
            const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
            try out.writer.writeAll(part[0..eq]);
            try out.writer.writeAll("=<redacted-cursor>");
        } else {
            try out.writer.writeAll(part);
        }
    }
    return try out.toOwnedSlice();
}

fn isCursorQueryPart(part: []const u8) bool {
    if (std.mem.startsWith(u8, part, "cursor=")) return true;
    if (std.mem.endsWith(u8, part, "?cursor")) return true;
    if (std.mem.indexOf(u8, part, "?cursor=")) |_| return true;
    return false;
}

fn deinitCapturedPageList(pages: *std.ArrayList(CapturedRoutePage), gpa: Allocator) void {
    for (pages.items) |page| page.deinit(gpa);
    pages.deinit(gpa);
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

fn appendProviderRoutes(gpa: Allocator, provider: []const u8, text: []const u8, filter: RouteFilter, rows: *std.ArrayList(CoverageRoute)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const tag = core_json.fieldString(parsed.value, "tag") orelse return error.InvalidCoverageRow;
        const operation_id = core_json.fieldString(parsed.value, "operation_id");
        const method_text = core_json.fieldString(parsed.value, "method") orelse return error.InvalidCoverageRow;
        const path_template = core_json.fieldString(parsed.value, "path") orelse return error.InvalidCoverageRow;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        if (filter.tag_query) |query| {
            if (!containsIgnoreCase(tag, query)) continue;
        }
        if (filter.family != .all) {
            const family = workplanTagFamily(provider, tag) orelse continue;
            if (family != filter.family) continue;
        }
        if (filter.operation_id) |expected| {
            const actual = operation_id orelse continue;
            if (!std.mem.eql(u8, actual, expected)) continue;
        }
        if (filter.method) |expected| {
            const method = provider_routes.Method.parse(method_text) orelse return error.InvalidCoverageMethod;
            if (method != expected) continue;
        }
        if (filter.path_template) |expected| {
            if (!std.mem.eql(u8, path_template, expected)) continue;
        }
        if (filter.support) |expected| {
            if (!expected.matches(support)) continue;
        }
        if (filter.mode) |expected| {
            if (!expected.matches(mode)) continue;
        }

        const row = try CoverageRoute.init(gpa, provider, parsed.value);
        errdefer row.deinit(gpa);
        try rows.append(gpa, row);
    }
}

fn auditProviderL1(gpa: Allocator, provider: []const u8, text: []const u8, audit: *L1ProviderAudit) !void {
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
        try auditRouteL1(gpa, row.route, audit);
    }
}

fn auditRouteL1(gpa: Allocator, route: provider_routes.Route, audit: *L1ProviderAudit) !void {
    audit.total += 1;
    if (route.operation_id == null) audit.missing_operation_id += 1;
    if (route.hasRequiredQueryParameters()) audit.required_query_routes += 1;
    if (routeHasRequiredHeaderParameters(route)) audit.required_header_routes += 1;
    if (route.responses.len == 0) audit.failures.missing_responses += 1;
    if (route.security.required and route.security.alternatives.len == 0) audit.failures.missing_security += 1;
    if (!try routePathMetadataValid(gpa, route)) audit.failures.bad_path_params += 1;

    if (route.deprecated) {
        audit.deprecated += 1;
        if (route.support != .deprecated) audit.failures.deprecated_support_mismatch += 1;
        if (route.mode != .none or route.isRoutable()) audit.deprecated_routable += 1;
        return;
    }

    audit.non_deprecated += 1;
    if (route.support == .not_applicable) audit.not_applicable += 1;
    if (route.isRoutable()) audit.routable += 1;

    if (route.mode == .write) audit.failures.unexpected_write_mode += 1;

    switch (route.mode) {
        .read => {
            audit.read_routes += 1;
            if (route.method != .GET) audit.failures.read_not_get += 1;
            if (route.request_body.required) audit.failures.read_body_required += 1;
            if (provider_dispatch.routeLiveCallSupported(route)) {
                audit.live_read_supported += 1;
            } else if (!route.request_body.required and route.method == .GET and !provider_dispatch.cloudioSupportsRouteAuth(route)) {
                audit.failures.read_auth_unsupported += 1;
            }
        },
        .dry_run => {
            audit.dry_run_routes += 1;
            if (route.method == .GET or route.method == .HEAD) audit.failures.dry_run_method_invalid += 1;
            if (provider_dispatch.routeDryRunSupported(route)) {
                audit.dry_run_supported += 1;
            } else {
                audit.failures.dry_run_not_supported += 1;
            }
        },
        .none => {
            if (route.support != .not_applicable) audit.failures.unsupported_mode += 1;
        },
        .write => {},
    }

    if (route.support == .not_applicable) {
        if (route.mode != .none or route.isRoutable()) audit.failures.not_applicable_contract_mismatch += 1;
    } else if (!route.isRoutable()) {
        audit.failures.unroutable_non_deprecated += 1;
    }

    if (route.method == .GET) {
        if (route.request_body.required) {
            if (route.support != .not_applicable or route.mode != .none) audit.failures.method_mode_mismatch += 1;
        } else if (route.mode != .read) {
            audit.failures.method_mode_mismatch += 1;
        }
    } else if (route.mode != .dry_run) {
        audit.failures.method_mode_mismatch += 1;
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

fn deinitRouteList(rows: *std.ArrayList(CoverageRoute), gpa: Allocator) void {
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

fn writeL1ProviderAudit(audit: L1ProviderAudit, writer: anytype) !void {
    try writer.print("\n{s}: {s}\n", .{ audit.name, if (audit.passed()) "pass" else "fail" });
    try writer.print("  total={d} non_deprecated={d} deprecated={d} not_applicable={d} routable={d}\n", .{
        audit.total,
        audit.non_deprecated,
        audit.deprecated,
        audit.not_applicable,
        audit.routable,
    });
    try writer.print("  read_routes={d} live_read_supported={d} dry_run_routes={d} dry_run_supported={d}\n", .{
        audit.read_routes,
        audit.live_read_supported,
        audit.dry_run_routes,
        audit.dry_run_supported,
    });
    try writer.print("  required_query_routes={d} required_header_routes={d} missing_operation_id={d} deprecated_routable={d}\n", .{
        audit.required_query_routes,
        audit.required_header_routes,
        audit.missing_operation_id,
        audit.deprecated_routable,
    });
    try writer.print("  failures={d}", .{audit.failures.total()});
    try writeFailureField(writer, "bad_path_params", audit.failures.bad_path_params);
    try writeFailureField(writer, "missing_responses", audit.failures.missing_responses);
    try writeFailureField(writer, "missing_security", audit.failures.missing_security);
    try writeFailureField(writer, "deprecated_support_mismatch", audit.failures.deprecated_support_mismatch);
    try writeFailureField(writer, "not_applicable_contract_mismatch", audit.failures.not_applicable_contract_mismatch);
    try writeFailureField(writer, "unexpected_write_mode", audit.failures.unexpected_write_mode);
    try writeFailureField(writer, "unsupported_mode", audit.failures.unsupported_mode);
    try writeFailureField(writer, "read_not_get", audit.failures.read_not_get);
    try writeFailureField(writer, "read_body_required", audit.failures.read_body_required);
    try writeFailureField(writer, "read_auth_unsupported", audit.failures.read_auth_unsupported);
    try writeFailureField(writer, "dry_run_method_invalid", audit.failures.dry_run_method_invalid);
    try writeFailureField(writer, "dry_run_not_supported", audit.failures.dry_run_not_supported);
    try writeFailureField(writer, "method_mode_mismatch", audit.failures.method_mode_mismatch);
    try writeFailureField(writer, "unroutable_non_deprecated", audit.failures.unroutable_non_deprecated);
    try writer.writeByte('\n');
}

fn writeL1ProviderAuditJson(audit: L1ProviderAudit, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "name", audit.name, true);
    try writeJsonField(writer, "status", if (audit.passed()) "pass" else "fail", true);
    try writeJsonBoolField(writer, "passed", audit.passed(), true);
    try writeJsonCountField(writer, "total", audit.total, true);
    try writeJsonCountField(writer, "non_deprecated", audit.non_deprecated, true);
    try writeJsonCountField(writer, "deprecated", audit.deprecated, true);
    try writeJsonCountField(writer, "not_applicable", audit.not_applicable, true);
    try writeJsonCountField(writer, "routable", audit.routable, true);
    try writeJsonCountField(writer, "read_routes", audit.read_routes, true);
    try writeJsonCountField(writer, "live_read_supported", audit.live_read_supported, true);
    try writeJsonCountField(writer, "dry_run_routes", audit.dry_run_routes, true);
    try writeJsonCountField(writer, "dry_run_supported", audit.dry_run_supported, true);
    try writeJsonCountField(writer, "required_query_routes", audit.required_query_routes, true);
    try writeJsonCountField(writer, "required_header_routes", audit.required_header_routes, true);
    try writeJsonCountField(writer, "missing_operation_id", audit.missing_operation_id, true);
    try writeJsonCountField(writer, "deprecated_routable", audit.deprecated_routable, true);
    try writeJsonCountField(writer, "failures_total", audit.failures.total(), true);
    try writer.writeAll("\"failures\":");
    try writeL1AuditFailuresJson(audit.failures, writer);
    try writer.writeByte('}');
}

fn writeL1AuditFailuresJson(failures: L1AuditFailures, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "bad_path_params", failures.bad_path_params, true);
    try writeJsonCountField(writer, "missing_responses", failures.missing_responses, true);
    try writeJsonCountField(writer, "missing_security", failures.missing_security, true);
    try writeJsonCountField(writer, "deprecated_support_mismatch", failures.deprecated_support_mismatch, true);
    try writeJsonCountField(writer, "not_applicable_contract_mismatch", failures.not_applicable_contract_mismatch, true);
    try writeJsonCountField(writer, "unexpected_write_mode", failures.unexpected_write_mode, true);
    try writeJsonCountField(writer, "unsupported_mode", failures.unsupported_mode, true);
    try writeJsonCountField(writer, "read_not_get", failures.read_not_get, true);
    try writeJsonCountField(writer, "read_body_required", failures.read_body_required, true);
    try writeJsonCountField(writer, "read_auth_unsupported", failures.read_auth_unsupported, true);
    try writeJsonCountField(writer, "dry_run_method_invalid", failures.dry_run_method_invalid, true);
    try writeJsonCountField(writer, "dry_run_not_supported", failures.dry_run_not_supported, true);
    try writeJsonCountField(writer, "method_mode_mismatch", failures.method_mode_mismatch, true);
    try writeJsonCountField(writer, "unroutable_non_deprecated", failures.unroutable_non_deprecated, false);
    try writer.writeByte('}');
}

fn writeFailureField(writer: anytype, name: []const u8, count: usize) !void {
    if (count == 0) return;
    try writer.print(" {s}={d}", .{ name, count });
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
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", filter.provider.name(), true);
    try writeJsonNullableStringField(writer, "tag_query", filter.tag_query, true);
    try writeJsonField(writer, "family", filter.family.name(), true);
    try writeJsonNullableStringField(writer, "operation_id", filter.operation_id, true);
    try writeJsonNullableStringField(writer, "method", if (filter.method) |method| method.name() else null, true);
    try writeJsonNullableStringField(writer, "path_template", filter.path_template, true);
    try writeJsonNullableStringField(writer, "support", if (filter.support) |support| support.name() else null, true);
    try writeJsonNullableStringField(writer, "mode", if (filter.mode) |mode| mode.name() else null, true);
    try writeJsonBoolField(writer, "detail", filter.detail, false);
    try writer.writeByte('}');
}

fn writeCoverageRouteJson(row: CoverageRoute, writer: anytype) !void {
    const route = row.route;
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "mode", @tagName(route.mode), true);
    try writeJsonBoolField(writer, "deprecated", route.deprecated, true);
    try writeJsonBoolField(writer, "routable", route.isRoutable(), true);
    try writeJsonField(writer, "tests", row.tests, true);
    try writeJsonField(writer, "notes", row.notes, true);
    try writer.writeAll("\"path_params\":");
    try writeRouteParamsJson(route.path_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"query_params\":");
    try writeRouteParamsJson(route.query_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"header_params\":");
    try writeRouteParamsJson(route.header_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"request_body\":");
    try writeRequestBodyJson(route.request_body, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"responses\":");
    try writeResponsesJson(route.responses, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"security\":");
    try writeSecurityJson(route.security, writer);
    try writer.writeByte('}');
}

fn writeRouteParamsJson(params: []const provider_routes.RouteParam, writer: anytype) !void {
    try writer.writeByte('[');
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "name", param.name, true);
        try writeJsonBoolField(writer, "required", param.required, true);
        try writeJsonNullableStringField(writer, "style", param.style, true);
        try writeJsonNullableBoolField(writer, "explode", param.explode, true);
        try writer.writeAll("\"schema\":");
        try writeParamSchemaJson(param.schema, writer);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeParamSchemaJson(schema: provider_routes.ParamSchema, writer: anytype) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"schema_refs\":");
    try writeJsonStringArray(writer, schema.schema_refs);
    try writer.writeByte(',');
    try writer.writeAll("\"types\":");
    try writeJsonStringArray(writer, schema.types);
    try writer.writeByte(',');
    try writer.writeAll("\"formats\":");
    try writeJsonStringArray(writer, schema.formats);
    try writer.writeByte(',');
    try writer.writeAll("\"enum_values\":");
    try writeJsonStringArray(writer, schema.enum_values);
    try writer.writeByte('}');
}

fn writeRequestBodyJson(body: provider_routes.RequestBody, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonBoolField(writer, "required", body.required, true);
    try writer.writeAll("\"content_types\":");
    try writeJsonStringArray(writer, body.content_types);
    try writer.writeByte(',');
    try writer.writeAll("\"schema_refs\":");
    try writeJsonStringArray(writer, body.schema_refs);
    try writer.writeByte('}');
}

fn writeResponsesJson(responses: []const provider_routes.Response, writer: anytype) !void {
    try writer.writeByte('[');
    for (responses, 0..) |response, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "status", response.status, true);
        try writer.writeAll("\"content_types\":");
        try writeJsonStringArray(writer, response.content_types);
        try writer.writeByte(',');
        try writer.writeAll("\"schema_refs\":");
        try writeJsonStringArray(writer, response.schema_refs);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeSecurityJson(security: provider_routes.Security, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonBoolField(writer, "required", security.required, true);
    try writer.writeAll("\"alternatives\":[");
    for (security.alternatives, 0..) |alternative, index| {
        if (index != 0) try writer.writeByte(',');
        try writeJsonStringArray(writer, alternative.schemes);
    }
    try writer.writeAll("]}");
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
    const route = row.route;
    if (!std.mem.eql(u8, route.provider.name(), "cloudflare")) return false;
    if (route.deprecated or !route.isRoutable()) return false;
    if (!route.isDryRunMutation()) return false;
    if (route.support != .unsafe_mutation) return false;
    return true;
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

fn writeRouteDetail(writer: anytype, route: provider_routes.Route) !void {
    try writer.writeAll("      path_params: ");
    try writeRouteParamList(writer, route.path_params);
    try writer.writeByte('\n');
    try writer.writeAll("      query_params: ");
    try writeRouteParamList(writer, route.query_params);
    try writer.writeByte('\n');
    try writer.writeAll("      header_params: ");
    try writeRouteParamList(writer, route.header_params);
    try writer.writeByte('\n');
    try writeRouteParamShapeDetails(writer, "path_param_shapes", route.path_params);
    try writeRouteParamShapeDetails(writer, "query_param_shapes", route.query_params);
    try writeRouteParamShapeDetails(writer, "header_param_shapes", route.header_params);
    try writer.print("      security: required={} alternatives=", .{route.security.required});
    try writeSecurityAlternatives(writer, route.security.alternatives);
    try writer.writeByte('\n');
    try writer.print("      request_body: required={}", .{route.request_body.required});
    try writer.writeAll(" content_types=");
    try writeStringList(writer, route.request_body.content_types);
    try writer.writeAll(" schema_refs=");
    try writeStringList(writer, route.request_body.schema_refs);
    try writer.writeByte('\n');
    try writer.writeAll("      responses:");
    if (route.responses.len == 0) {
        try writer.writeAll(" none\n");
        return;
    }
    try writer.writeByte('\n');
    for (route.responses) |response| {
        try writer.print("        {s} content_types=", .{response.status});
        try writeStringList(writer, response.content_types);
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, response.schema_refs);
        try writer.writeByte('\n');
    }
}

fn writeSecurityAlternatives(writer: anytype, alternatives: []const provider_routes.SecurityAlternative) !void {
    if (alternatives.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (alternatives, 0..) |alternative, index| {
        if (index != 0) try writer.writeAll(" or ");
        if (alternative.schemes.len == 0) {
            try writer.writeAll("anonymous");
            continue;
        }
        for (alternative.schemes, 0..) |scheme, scheme_index| {
            if (scheme_index != 0) try writer.writeByte('+');
            try writer.writeAll(scheme);
        }
    }
}

fn writeRouteParamShapeDetails(writer: anytype, label: []const u8, params: []const provider_routes.RouteParam) !void {
    if (params.len == 0) return;
    try writer.print("      {s}:\n", .{label});
    for (params) |param| {
        try writer.print("        {s} style=", .{param.name});
        if (param.style) |style| {
            try writer.writeAll(style);
        } else {
            try writer.writeAll("default");
        }
        try writer.writeAll(" explode=");
        if (param.explode) |explode| {
            try writer.writeAll(if (explode) "true" else "false");
        } else {
            try writer.writeAll("default");
        }
        try writer.writeAll(" schema_types=");
        try writeStringList(writer, param.schema.types);
        try writer.writeAll(" schema_formats=");
        try writeStringList(writer, param.schema.formats);
        try writer.writeAll(" enum_values=");
        try writeStringList(writer, param.schema.enum_values);
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, param.schema.schema_refs);
        try writer.writeByte('\n');
    }
}

fn writeRouteParamList(writer: anytype, params: []const provider_routes.RouteParam) !void {
    if (params.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}({s})", .{ param.name, if (param.required) "required" else "optional" });
    }
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachinesV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachineDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"actual_state\":\"non_ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getVirtualMachineDetailsV1 --path-param virtualMachineId='12345'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_inputs\":[{\"source\":\"query\",\"name\":\"date_from\"},{\"source\":\"query\",\"name\":\"date_to\"}]") != null);
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

    const audit = try auditL1FromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 0), audit.totalFailures(.all));
    try std.testing.expectEqual(@as(usize, 3), audit.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 2), audit.cloudflare.routable);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.live_read_supported);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.dry_run_supported);
    try std.testing.expectEqual(@as(usize, 1), audit.hostinger.not_applicable);
    try std.testing.expectEqual(@as(usize, 1), audit.hostinger.dry_run_supported);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try audit.writeText(.all, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider L1 routability audit\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "status: pass\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: pass\n") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try audit.writeJson(.all, &json_out.writer);
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

    const audit = try auditL1FromText(allocator, cloudflare, hostinger, .cloudflare);
    try std.testing.expect(audit.totalFailures(.cloudflare) >= 4);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.missing_operation_id);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.failures.bad_path_params);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.failures.missing_responses);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.failures.missing_security);
    try std.testing.expectEqual(@as(usize, 1), audit.cloudflare.failures.read_auth_unsupported);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try audit.writeJson(.cloudflare, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"fail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"passed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bad_path_params\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_responses\":1") != null);
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

test "plans exact provider coverage routes without live provider calls" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Worker Script","method":"POST","path":"/accounts/{account_id}/workers/assets/upload","operation_id":"worker-assets-upload","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"base64","required":true}],"request_body":{"required":true,"content_types":["multipart/form-data"],"schema_refs":[]},"responses":[{"status":"201","content_types":["application/json"],"schema_refs":[]}],"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.MetricsResource"]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads metrics."}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads billing catalog."}
        \\
    ;

    const read_plan = try routePlanJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .hostinger, .operation_id = "VPS_getMetricsV1" },
            .request = .{
                .path_params = &.{.{ .name = "virtualMachineId", .value = "123" }},
                .query_params = &.{
                    .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                    .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
                },
            },
        },
    );
    defer allocator.free(read_plan);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"url\":\"https://developers.hostinger.com/api/vps/v1/virtual-machines/123/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_plan, "\"will_execute\":false") != null);

    const mutation_plan = try routePlanJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .cloudflare, .operation_id = "worker-assets-upload" },
            .request = .{
                .path_params = &.{.{ .name = "account_id", .value = "acct/1" }},
                .query_params = &.{.{ .name = "base64", .value = "true" }},
                .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" },
            },
        },
    );
    defer allocator.free(mutation_plan);
    try std.testing.expect(std.mem.indexOf(u8, mutation_plan, "\"operation_id\":\"worker-assets-upload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mutation_plan, "\"mode\":\"dry_run\"") != null);

    try std.testing.expectError(
        error.ProviderRoutePlanAmbiguous,
        routePlanJsonFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .hostinger } }),
    );
    try std.testing.expectError(
        error.ProviderRoutePlanNotFound,
        routePlanJsonFromText(allocator, cloudflare, hostinger, .{ .filter = .{ .provider = .hostinger, .operation_id = "missing" } }),
    );
}

test "renders exact provider route dry-runs through the shared route contract" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_email","api_key"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Order.VirtualMachineOrderResource"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes in POC."}
        \\
    ;

    const plan = try routeDryRunJsonFromText(
        allocator,
        cloudflare,
        hostinger,
        .{
            .filter = .{ .provider = .hostinger, .operation_id = "VPS_purchaseNewVirtualMachineV1" },
            .request = .{ .body = .{ .present = true, .content_type = "application/json" } },
        },
        .{ .hostinger = "test-token" },
    );
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"url\":\"https://developers.hostinger.com/api/vps/v1/virtual-machines\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"mode\":\"dry_run\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "test-token") == null);

    try std.testing.expectError(
        error.ProviderRouteAuthMismatch,
        routeDryRunJsonFromText(
            allocator,
            cloudflare,
            hostinger,
            .{ .filter = .{ .provider = .hostinger, .operation_id = "VPS_purchaseNewVirtualMachineV1" } },
            .{ .cloudflare = .{ .token = "test-token" } },
        ),
    );
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

test "captures paginated generic route pages into snapshots and metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-paged-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Public Keys","method":"GET","path":"/api/vps/v1/public-keys","operation_id":"VPS_getPublicKeysV1","path_params":[],"query_params":[{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Common.Schema.PaginationMetaSchema","#/components/schemas/VPS.V1.PublicKey.PublicKeyCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC paginates public keys."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .operation_id = "VPS_getPublicKeysV1" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    try std.testing.expect(routeSupportsPageQuery(route.route));

    const base_request = Request{
        .query_params = &.{
            .{ .name = "page", .value = "99" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const first_request = try requestWithPage(allocator, base_request, 1);
    defer first_request.deinit(allocator);
    const first_path = try route.route.renderRequestPath(allocator, first_request.request);
    defer allocator.free(first_path);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=99") == null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=1") != null);

    const first_body = try allocator.dupe(u8,
        \\{"data":[{"id":1,"password":"secret-one"}],"meta":{"current_page":1,"per_page":1,"total":2}}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        first_request.request,
        first_result,
        .{ .kind = "route-public-keys", .target = "public-keys" },
        .{ .page = 1 },
    );
    defer first_page.deinit(allocator);

    const second_request = try requestWithPage(allocator, base_request, 2);
    defer second_request.deinit(allocator);
    const second_body = try allocator.dupe(u8,
        \\{"data":[{"id":2,"password":"secret-two"}],"meta":{"current_page":2,"per_page":1,"total":2}}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        second_request.request,
        second_result,
        .{ .kind = "route-public-keys", .target = "public-keys" },
        .{ .page = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route.route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[1,2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"data_meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"data_len\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("hostinger_inventory_items"));
}

test "captures Cloudflare result_info paginated generic route pages" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-paged-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list-accounts","path_params":[],"query_params":[{"name":"direction","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":["asc","desc"]}},{"name":"name","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":[]}},{"name":"page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["number"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["number"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/iam_response_collection_accounts"]}],"security":{"required":true,"alternatives":[["api_email","api_key"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC lists accounts and stores raw/account summary data."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "accounts-list-accounts" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    try std.testing.expect(routeSupportsPageQuery(route.route));

    const base_request = Request{
        .query_params = &.{
            .{ .name = "page", .value = "7" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const first_request = try requestWithPage(allocator, base_request, 1);
    defer first_request.deinit(allocator);
    const first_path = try route.route.renderRequestPath(allocator, first_request.request);
    defer allocator.free(first_path);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=7") == null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_path, "page=1") != null);

    const first_body = try allocator.dupe(u8,
        \\{"result":[{"id":"account-one","token":"secret-one"}],"result_info":{"page":1,"per_page":1,"total_pages":2,"count":1,"total_count":2},"success":true,"errors":[],"messages":[]}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        first_request.request,
        first_result,
        .{ .kind = "route-cloudflare-accounts", .target = "accounts" },
        .{ .page = 1 },
    );
    defer first_page.deinit(allocator);

    const second_request = try requestWithPage(allocator, base_request, 2);
    defer second_request.deinit(allocator);
    const second_body = try allocator.dupe(u8,
        \\{"result":[{"id":"account-two","token":"secret-two"}],"result_info":{"page":2,"per_page":1,"total_pages":2,"count":1,"total_count":2},"success":true,"errors":[],"messages":[]}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        second_request.request,
        second_result,
        .{ .kind = "route-cloudflare-accounts", .target = "accounts" },
        .{ .page = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route.route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshots\":[1,2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"result_info\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"data_len\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"has_next\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_accounts"));
}

test "captures Cloudflare cursor paginated generic route pages without leaking cursors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-cursor-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Zone Rulesets","method":"GET","path":"/zones/{zone_id}/rulesets","operation_id":"listZoneRulesets","path_params":[{"name":"zone_id","required":true,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_ZoneId"],"types":["string"],"formats":[],"enum_values":[]}}],"query_params":[{"name":"cursor","required":false,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_Cursor"],"types":["string"],"formats":[],"enum_values":[]}},{"name":"per_page","required":false,"style":null,"explode":null,"schema":{"schema_refs":["#/components/schemas/rulesets_PerPage"],"types":["integer"],"formats":[],"enum_values":[]}}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/rulesets_Response","#/components/schemas/rulesets_ResultInfo","#/components/schemas/rulesets_Ruleset"]}],"security":{"required":true,"alternatives":[["api_email","api_key"],["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads zone ruleset lists by explicit zone ID and during configured-domain refresh as redacted raw provider data."}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "listZoneRulesets" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    try std.testing.expect(!routeSupportsPageQuery(route.route));
    try std.testing.expect(routeSupportsCursorQuery(route.route));

    const base_request = Request{
        .path_params = &.{.{ .name = "zone_id", .value = "zone-one" }},
        .query_params = &.{
            .{ .name = "cursor", .value = "old-cursor" },
            .{ .name = "per_page", .value = "1" },
        },
    };
    const cursor_request = try requestWithCursor(allocator, base_request, "opaque-next-cursor");
    defer cursor_request.deinit(allocator);
    const cursor_path = try route.route.renderRequestPath(allocator, cursor_request.request);
    defer allocator.free(cursor_path);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "old-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "per_page=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cursor_path, "cursor=opaque-next-cursor") != null);

    const first_body = try allocator.dupe(u8,
        \\{"result":[{"id":"ruleset-one","token":"secret-one"}],"result_info":{"cursors":{"after":"opaque-next-cursor"}},"success":true,"errors":[],"messages":[]}
    );
    const first_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = first_body });
    defer first_result.deinit(allocator);
    const first_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        base_request,
        first_result,
        .{ .kind = "route-cloudflare-rulesets", .target = "rulesets" },
        .{ .cursor = 1 },
    );
    defer first_page.deinit(allocator);

    const second_body = try allocator.dupe(u8,
        \\{"result":[{"id":"ruleset-two","token":"secret-two"}],"result_info":{"cursors":{"after":""}},"success":true,"errors":[],"messages":[]}
    );
    const second_result = provider_dispatch.matchReadRouteResponse(route.route, .{ .status = .ok, .body = second_body });
    defer second_result.deinit(allocator);
    const second_page = try captureRouteReadPageResult(
        allocator,
        &db,
        route.route,
        cursor_request.request,
        second_result,
        .{ .kind = "route-cloudflare-rulesets", .target = "rulesets" },
        .{ .cursor = 2 },
    );
    defer second_page.deinit(allocator);

    const pages = [_]CapturedRoutePage{ first_page, second_page };
    const json = try routePaginatedCaptureMetadataJson(allocator, route.route, pages[0..], 5);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"paginated\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured_pages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pagination_envelope\":\"cursor_result_info\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cursor=<redacted-cursor>") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "opaque-next-cursor") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-one") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-two") == null);
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 2), try db.countTable("cloudflare_inventory_items"));
}
