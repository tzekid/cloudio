const std = @import("std");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;

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
            try writeMaybeJsonComma(writer, &first);
            visible += 1;
            try writeGapJson(row, writer);
        }

        try writer.writeAll("],");
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

pub fn load(io: Io, gpa: Allocator, paths: Paths) !Summary {
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{ .provider = .all });
    defer routes.deinit(gpa);
    return buildSummary(routes.items);
}

pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !Summary {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{ .provider = .all });
    defer routes.deinit(gpa);
    return buildSummary(routes.items);
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
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildTags(gpa, routes.items);
}

pub fn loadTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !TagSummaries {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildTags(gpa, routes.items);
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
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildGaps(gpa, routes.items);
}

pub fn loadGapsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !GapReport {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, .{ .provider = filter });
    defer routes.deinit(gpa);
    return try buildGaps(gpa, routes.items);
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

pub fn buildSummary(routes: []const CoverageRoute) Summary {
    var summary = Summary.init();
    for (routes) |row| {
        const provider = row.route.provider.name();
        if (std.mem.eql(u8, provider, "cloudflare")) {
            addProviderSummaryRoute(&summary.cloudflare, row);
        } else if (std.mem.eql(u8, provider, "hostinger")) {
            addProviderSummaryRoute(&summary.hostinger, row);
        }
    }
    return summary;
}

pub fn buildTags(gpa: Allocator, routes: []const CoverageRoute) !TagSummaries {
    var rows = std.ArrayList(TagSummary).empty;
    errdefer deinitTagList(&rows, gpa);
    for (routes) |route| {
        const row = try tagRow(gpa, &rows, route.route.provider.name(), route.route.tag);
        addTagSummaryRoute(row, route);
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn buildGaps(gpa: Allocator, routes: []const CoverageRoute) !GapReport {
    var rows = std.ArrayList(GapSummary).empty;
    errdefer deinitGapList(&rows, gpa);
    for (routes) |route| {
        const row = try gapRow(gpa, &rows, route.route.provider.name(), route.route.tag);
        addGapRoute(row, route);
    }
    std.mem.sort(GapSummary, rows.items, {}, gapLessThan);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn addProviderSummaryRoute(summary: *ProviderSummary, row: CoverageRoute) void {
    summary.total += 1;
    summary.support_counts[supportIndex(row.route.support)] += 1;
    summary.mode_counts[modeIndex(row.route.mode)] += 1;
    if (row.route.deprecated) summary.deprecated += 1;
}

fn addTagSummaryRoute(summary: *TagSummary, row: CoverageRoute) void {
    summary.total += 1;
    summary.support_counts[supportIndex(row.route.support)] += 1;
    summary.mode_counts[modeIndex(row.route.mode)] += 1;
    if (row.route.deprecated) summary.deprecated += 1;
}

fn addGapRoute(row: *GapSummary, route: CoverageRoute) void {
    const has_evidence = hasCoverageEvidence(route.tests);
    row.total += 1;
    if (route.route.deprecated) {
        row.deprecated += 1;
        return;
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
                if (app_provider_coverage_candidates.hasGeneratedDryRunPolicyEvidence(route)) {
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

pub fn supportIndex(value: provider_routes.Support) usize {
    return switch (value) {
        .implemented => 0,
        .partial => 1,
        .planned => 2,
        .blocked_permission => 3,
        .unsafe_mutation => 4,
        .deprecated => 5,
        .not_applicable => 6,
    };
}

pub fn modeIndex(value: provider_routes.Mode) usize {
    return switch (value) {
        .read => 0,
        .dry_run => 1,
        .write => 2,
        .none => 3,
    };
}

fn hasCoverageEvidence(tests: []const u8) bool {
    return tests.len != 0 and !std.mem.eql(u8, tests, "missing");
}

const fixture_cloudflare =
    \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
    \\{"provider":"cloudflare","tag":"Accounts","method":"POST","path":"/accounts","operation_id":"accounts-create","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
    \\{"provider":"cloudflare","tag":"Zone Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":"zone-settings-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"deprecated","mode":"read","tests":"fixture","deprecated":true,"notes":"old"}
    \\
;

const fixture_hostinger =
    \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"vps-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
    \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"no write"}
    \\{"provider":"hostinger","tag":"Domains","method":"GET","path":"/api/domains/v1/portfolio","operation_id":"domains-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"missing","deprecated":false,"notes":"token lacks permission"}
    \\{"provider":"hostinger","tag":"Billing","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"diagnostic evidence"}
    \\
;

test "summarizes provider coverage by status and mode from route metadata" {
    const allocator = std.testing.allocator;
    const summary = try loadFromText(allocator, fixture_cloudflare, fixture_hostinger);

    try std.testing.expectEqual(@as(usize, 7), summary.total());
    try std.testing.expectEqual(@as(usize, 3), summary.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.deprecated);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.support_counts[supportIndex(.partial)]);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.support_counts[supportIndex(.unsafe_mutation)]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.support_counts[supportIndex(.unsafe_mutation)]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.mode_counts[modeIndex(.dry_run)]);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try summary.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: 3 operations\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unsafe_mutation=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try summary.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_operations\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"deprecated\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"unsafe_mutation\":1") != null);
}

test "summarizes provider coverage by tag with provider filters" {
    const allocator = std.testing.allocator;
    var rows = try loadTagsFromText(allocator, fixture_cloudflare, fixture_hostinger, .cloudflare);
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("cloudflare", rows.items[0].provider);
    try std.testing.expectEqualStrings("Accounts", rows.items[0].tag);
    try std.testing.expectEqual(@as(usize, 2), rows.items[0].total);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[supportIndex(.partial)]);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[supportIndex(.unsafe_mutation)]);

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

test "ranks provider coverage gaps by unresolved tag groups" {
    const allocator = std.testing.allocator;
    var gaps = try loadGapsFromText(allocator, fixture_cloudflare, fixture_hostinger, .all);
    defer gaps.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), gaps.items.len);
    try std.testing.expectEqualStrings("hostinger", gaps.items[0].provider);
    try std.testing.expectEqualStrings("Domains", gaps.items[0].tag);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].blocked_read);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[0].pending_reads);
    try std.testing.expectEqualStrings("hostinger", gaps.items[1].provider);
    try std.testing.expectEqualStrings("VPS", gaps.items[1].tag);
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[1].pending_mutation_dry_runs);
    try std.testing.expectEqualStrings("hostinger", gaps.items[2].provider);
    try std.testing.expectEqualStrings("Billing", gaps.items[2].tag);
    try std.testing.expectEqual(@as(usize, 0), gaps.items[2].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[2].diagnostic_blocked_reads);
    try std.testing.expectEqualStrings("cloudflare", gaps.items[3].provider);
    try std.testing.expectEqualStrings("Accounts", gaps.items[3].tag);
    try std.testing.expectEqual(@as(usize, 0), gaps.items[3].priority());
    try std.testing.expectEqual(@as(usize, 1), gaps.items[3].generated_dry_run_policy_evidence);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try gaps.writeJson(&out.writer, .{ .provider = .all, .limit = 2 });
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_gaps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Domains\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"VPS\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Accounts\"") == null);
}
