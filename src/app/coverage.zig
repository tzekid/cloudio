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

pub const ProviderFilter = enum {
    all,
    cloudflare,
    hostinger,

    pub fn parse(value: []const u8) ?ProviderFilter {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        return null;
    }

    pub fn includes(self: ProviderFilter, provider: []const u8) bool {
        return switch (self) {
            .all => true,
            .cloudflare => std.mem.eql(u8, provider, "cloudflare"),
            .hostinger => std.mem.eql(u8, provider, "hostinger"),
        };
    }

    pub fn name(self: ProviderFilter) []const u8 {
        return @tagName(self);
    }
};

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
        return self.planned_read + self.blocked_read + self.unsafe_dry_run;
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
        try writer.writeAll("rank: planned_read + blocked_read + unsafe_dry_run\n");
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
    pending_mutation_dry_runs: usize = 0,
    l3_generic_inventory_candidates: usize = 0,
    l3_typed_table_evidence: usize = 0,

    pub fn init(name: []const u8) LevelProviderEvidence {
        return .{ .name = name };
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
};

pub const RouteFilter = struct {
    provider: ProviderFilter = .all,
    tag_query: ?[]const u8 = null,
    operation_id: ?[]const u8 = null,
    method: ?provider_routes.Method = null,
    path_template: ?[]const u8 = null,
    support: ?SupportFilter = null,
    mode: ?ModeFilter = null,
    detail: bool = false,
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
                .dry_run => row.partial_dry_run += 1,
                .write, .none => {},
            },
            .planned => {
                if (route.route.mode == .read) row.planned_read += 1;
            },
            .blocked_permission => {
                if (route.route.mode == .read) row.blocked_read += 1;
            },
            .unsafe_mutation => {
                if (route.route.mode == .dry_run) row.unsafe_dry_run += 1;
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

        evidence.total += 1;
        if (row.route.deprecated) {
            evidence.deprecated += 1;
            continue;
        }
        evidence.non_deprecated += 1;
        if (row.route.support == .not_applicable) {
            evidence.not_applicable += 1;
            continue;
        }
        if (row.route.isRoutable()) evidence.routable += 1;

        switch (row.route.mode) {
            .read => updateReadLevelEvidence(evidence, row),
            .dry_run => updateDryRunLevelEvidence(evidence, row),
            .write, .none => {},
        }
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

fn deinitTagList(rows: *std.ArrayList(TagSummary), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitGapList(rows: *std.ArrayList(GapSummary), gpa: Allocator) void {
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
    try writer.print("  dry_run evidence={d} pending_mutation_dry_runs={d}\n", .{
        evidence.dry_run_evidence,
        evidence.pending_mutation_dry_runs,
    });
    try writer.print("  L3 evidence generic_inventory_candidates={d} typed_table_evidence={d}\n", .{
        evidence.l3_generic_inventory_candidates,
        evidence.l3_typed_table_evidence,
    });
}

fn writeGapField(writer: anytype, name: []const u8, count: usize) !void {
    if (count == 0) return;
    try writer.print(" {s}={d}", .{ name, count });
}

fn gapLessThan(_: void, lhs: GapSummary, rhs: GapSummary) bool {
    const lhs_priority = lhs.priority();
    const rhs_priority = rhs.priority();
    if (lhs_priority != rhs_priority) return lhs_priority > rhs_priority;
    if (lhs.planned_read != rhs.planned_read) return lhs.planned_read > rhs.planned_read;
    if (lhs.unsafe_dry_run != rhs.unsafe_dry_run) return lhs.unsafe_dry_run > rhs.unsafe_dry_run;
    if (lhs.blocked_read != rhs.blocked_read) return lhs.blocked_read > rhs.blocked_read;
    if (lhs.non_deprecated != rhs.non_deprecated) return lhs.non_deprecated > rhs.non_deprecated;
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, lhs.tag, rhs.tag) == .lt;
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
        .unsafe_mutation => evidence.pending_mutation_dry_runs += 1,
        .implemented, .planned, .blocked_permission, .deprecated, .not_applicable => {},
    }
}

fn hasCoverageEvidence(tests: []const u8) bool {
    return tests.len != 0 and !std.mem.eql(u8, tests, "missing");
}

fn isTypedTableCoverageCandidate(provider: []const u8, tag: []const u8) bool {
    if (std.mem.eql(u8, provider, "hostinger")) {
        return std.mem.eql(u8, tag, "VPS: Virtual machine");
    }
    if (std.mem.eql(u8, provider, "cloudflare")) {
        return std.mem.eql(u8, tag, "Accounts") or
            std.mem.eql(u8, tag, "Zone") or
            std.mem.eql(u8, tag, "DNS Records for a Zone");
    }
    return false;
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
        \\{"provider":"hostinger","tag":"Domains","method":"GET","path":"/api/domains/v1/portfolio","operation_id":"domains-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture","deprecated":false,"notes":"token lacks permission"}
        \\{"provider":"hostinger","tag":"Domains","method":"POST","path":"/api/domains/v1/portfolio","operation_id":"domains-create","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    var gaps = try loadGapsFromText(allocator, cloudflare, hostinger, .all);
    defer gaps.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), gaps.items.len);
    try std.testing.expectEqualStrings("cloudflare", gaps.items[0].provider);
    try std.testing.expectEqualStrings("AI Gateway", gaps.items[0].tag);
    try std.testing.expectEqual(@as(usize, 3), gaps.items[0].priority());
    try std.testing.expectEqual(@as(usize, 2), gaps.items[0].planned_read);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].unsafe_dry_run);
    try std.testing.expectEqualStrings("hostinger", gaps.items[1].provider);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].blocked_read);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].partial_dry_run);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try gaps.writeText(&out.writer, .{ .provider = .all, .limit = 1 });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage gaps\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "rank: planned_read + blocked_read + unsafe_dry_run\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | AI Gateway: priority=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "planned_read=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unsafe_dry_run=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);
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
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.pending_mutation_dry_runs);
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

    var mutations = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .support = .unsafe_mutation, .mode = .dry_run });
    defer mutations.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), mutations.items.len);
    try std.testing.expectEqual(provider_routes.Method.POST, mutations.items[0].route.method);

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
