const std = @import("std");
const app_provider_coverage_actual_inputs = @import("app_provider_coverage_actual_inputs");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const db_store = @import("db_store");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const actual_capture_load_limit: i64 = 100_000;
const actual_capture_source_evidence_limit: i64 = 5000;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;
pub const WorkplanFamily = app_provider_coverage_routes.WorkplanFamily;
pub const ActualCaptureHints = app_provider_coverage_actual_inputs.Hints;
pub const ActualCaptureSourceSummary = app_provider_coverage_actual_inputs.SourceSummary;
pub const ActualCaptureState = app_provider_coverage_actual_inputs.CaptureState;

pub const ActualCaptureFocus = enum {
    all,
    control_plane,

    pub fn parse(value: []const u8) ?ActualCaptureFocus {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "control-plane") or std.mem.eql(u8, value, "control_plane")) return .control_plane;
        if (std.mem.eql(u8, value, "cloudio") or std.mem.eql(u8, value, "cloudio-relevant")) return .control_plane;
        return null;
    }

    pub fn name(self: ActualCaptureFocus) []const u8 {
        return switch (self) {
            .all => "all",
            .control_plane => "control-plane",
        };
    }
};

pub const ActualCaptureOptions = struct {
    filter: RouteFilter = .{},
    focus: ActualCaptureFocus = .all,
    limit: usize = 25,
    include_plans: bool = false,
    configured_domains: []const []const u8 = &.{},
};

pub const ActualCaptureTotals = struct {
    official_read_routes: usize = 0,
    ok_read_routes: usize = 0,
    non_ok_read_routes: usize = 0,
    missing_read_routes: usize = 0,
    candidate_routes: usize = 0,
    ready_candidates: usize = 0,
    capture_events: i64 = 0,
};

pub const ActualCaptureCandidateRank = struct {
    route_index: usize,
    state: ActualCaptureState,
    focus_family: ?WorkplanFamily = null,
    family_candidate_routes: usize = 0,
    family_ready_candidates: usize = 0,
    family_pending_read_gaps: usize = 0,
    family_missing_tests: usize = 0,
    route_ready: bool = false,
    route_missing_inputs: usize = 0,
    route_capture_events: i64 = 0,

    pub fn familyPriority(self: ActualCaptureCandidateRank) usize {
        return self.family_pending_read_gaps;
    }
};

pub const ActualCaptureCandidateOrder = struct {
    items: []ActualCaptureCandidateRank,

    pub fn deinit(self: *ActualCaptureCandidateOrder, gpa: Allocator) void {
        gpa.free(self.items);
    }
};

pub const ActualCapturePlan = struct {
    options: ActualCaptureOptions,
    routes: CoverageRoutes,
    source_routes: CoverageRoutes,
    captures: db_store.RouteCaptureEvidenceRows,
    source_evidence: db_store.RouteSourceEvidenceRows,
    cloudflare_accounts: ?db_store.CloudflareAccountRows,
    cloudflare_zones: ?db_store.CloudflareZoneRows,
    cloudflare_resources: ?db_store.CloudflareResourceHintRows,
    cloudflare_inventory: ?db_store.CloudflareInventoryHintRows,
    hostinger_vps: ?db_store.HostingerVpsRows,
    hostinger_resources: ?db_store.HostingerResourceHintRows,
    hostinger_inventory: ?db_store.HostingerInventoryHintRows,

    pub fn deinit(self: *ActualCapturePlan, gpa: Allocator) void {
        if (self.hostinger_inventory) |*rows| rows.deinit(gpa);
        if (self.hostinger_resources) |*rows| rows.deinit(gpa);
        if (self.hostinger_vps) |*rows| rows.deinit(gpa);
        if (self.cloudflare_inventory) |*rows| rows.deinit(gpa);
        if (self.cloudflare_resources) |*rows| rows.deinit(gpa);
        if (self.cloudflare_zones) |*rows| rows.deinit(gpa);
        if (self.cloudflare_accounts) |*rows| rows.deinit(gpa);
        self.source_evidence.deinit(gpa);
        self.captures.deinit(gpa);
        self.source_routes.deinit(gpa);
        self.routes.deinit(gpa);
    }

    pub fn cloudflareAccountRows(self: ActualCapturePlan) []const db_store.CloudflareAccountRow {
        if (self.cloudflare_accounts) |rows| return rows.items;
        return &.{};
    }

    pub fn cloudflareZoneRows(self: ActualCapturePlan) []const db_store.CloudflareZoneRow {
        if (self.cloudflare_zones) |rows| return rows.items;
        return &.{};
    }

    pub fn cloudflareResourceRows(self: ActualCapturePlan) []const db_store.CloudflareResourceHintRow {
        if (self.cloudflare_resources) |rows| return rows.items;
        return &.{};
    }

    pub fn cloudflareInventoryRows(self: ActualCapturePlan) []const db_store.CloudflareInventoryHintRow {
        if (self.cloudflare_inventory) |rows| return rows.items;
        return &.{};
    }

    pub fn hostingerVpsRows(self: ActualCapturePlan) []const db_store.HostingerVpsRow {
        if (self.hostinger_vps) |rows| return rows.items;
        return &.{};
    }

    pub fn hostingerResourceRows(self: ActualCapturePlan) []const db_store.HostingerResourceHintRow {
        if (self.hostinger_resources) |rows| return rows.items;
        return &.{};
    }

    pub fn hostingerInventoryRows(self: ActualCapturePlan) []const db_store.HostingerInventoryHintRow {
        if (self.hostinger_inventory) |rows| return rows.items;
        return &.{};
    }

    pub fn hints(self: ActualCapturePlan) ActualCaptureHints {
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

    pub fn totals(self: ActualCapturePlan) ActualCaptureTotals {
        var out = ActualCaptureTotals{};
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            if (!actualCaptureRouteInFocus(self.options, row)) continue;
            const status = app_provider_coverage_actual_inputs.actualCaptureState(row.route, self.captures.items) orelse continue;
            out.official_read_routes += 1;
            const route_status = app_provider_coverage_actual_inputs.actualRouteCaptureStatus(row.route.provider.name(), row.route.operation_id.?, self.captures.items);
            out.capture_events += route_status.events;
            switch (status) {
                .ok => out.ok_read_routes += 1,
                .missing => {
                    out.missing_read_routes += 1;
                    out.candidate_routes += 1;
                    if (app_provider_coverage_actual_inputs.actualCaptureReady(row.route, hints_value)) out.ready_candidates += 1;
                },
                .non_ok => {
                    out.non_ok_read_routes += 1;
                    out.candidate_routes += 1;
                    if (app_provider_coverage_actual_inputs.actualCaptureReady(row.route, hints_value)) out.ready_candidates += 1;
                },
            }
        }
        return out;
    }

    pub fn sourceSummary(self: ActualCapturePlan, gpa: Allocator) !ActualCaptureSourceSummary {
        var out = ActualCaptureSourceSummary{};
        const hints_value = self.hints();
        for (self.routes.items) |row| {
            if (!actualCaptureRouteInFocus(self.options, row)) continue;
            const state = app_provider_coverage_actual_inputs.actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            try app_provider_coverage_actual_inputs.actualCaptureSummarizeMissingInputSources(gpa, &out, row.route, self.source_routes.items, self.captures.items, self.source_evidence.items, hints_value);
        }
        return out;
    }

    pub fn candidateOrder(self: ActualCapturePlan, gpa: Allocator) !ActualCaptureCandidateOrder {
        var items = std.ArrayList(ActualCaptureCandidateRank).empty;
        errdefer items.deinit(gpa);
        const hints_value = self.hints();
        for (self.routes.items, 0..) |row, route_index| {
            if (!actualCaptureRouteInFocus(self.options, row)) continue;
            const state = app_provider_coverage_actual_inputs.actualCaptureState(row.route, self.captures.items) orelse continue;
            if (state == .ok) continue;
            const route_status = app_provider_coverage_actual_inputs.actualRouteCaptureStatus(row.route.provider.name(), row.route.operation_id.?, self.captures.items);
            try items.append(gpa, .{
                .route_index = route_index,
                .state = state,
                .focus_family = app_provider_coverage_routes.tagFamily(row.route.provider.name(), row.route.tag),
                .route_ready = app_provider_coverage_actual_inputs.actualCaptureReady(row.route, hints_value),
                .route_missing_inputs = app_provider_coverage_actual_inputs.actualCaptureMissingInputCount(row.route, hints_value),
                .route_capture_events = route_status.events,
            });
        }
        addFamilyCandidateStats(self.routes.items, items.items);
        sortCandidateOrder(self.routes.items, items.items);
        return .{ .items = try items.toOwnedSlice(gpa) };
    }
};

pub fn loadActualCapturePlanFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions) !ActualCapturePlan {
    var routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, app_provider_coverage_actual_inputs.actualCaptureRouteFilter(options.filter));
    errdefer routes.deinit(gpa);
    var source_routes = try app_provider_coverage_routes.loadRoutes(io, gpa, paths, actualCaptureSourceRouteFilter(options.filter));
    errdefer source_routes.deinit(gpa);
    return try loadActualCapturePlanWithRoutes(gpa, db, options, routes, source_routes);
}

pub fn loadActualCapturePlanFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions) !ActualCapturePlan {
    var routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, app_provider_coverage_actual_inputs.actualCaptureRouteFilter(options.filter));
    errdefer routes.deinit(gpa);
    var source_routes = try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, actualCaptureSourceRouteFilter(options.filter));
    errdefer source_routes.deinit(gpa);
    return try loadActualCapturePlanWithRoutes(gpa, db, options, routes, source_routes);
}

fn loadActualCapturePlanWithRoutes(gpa: Allocator, db: *Db, options: ActualCaptureOptions, routes: CoverageRoutes, source_routes: CoverageRoutes) !ActualCapturePlan {
    var owned_routes = routes;
    errdefer owned_routes.deinit(gpa);
    var owned_source_routes = source_routes;
    errdefer owned_source_routes.deinit(gpa);
    var captures = try db.routeCaptureEvidence(gpa, .{
        .provider = app_provider_coverage_actual_inputs.actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_load_limit,
    });
    errdefer captures.deinit(gpa);
    var source_evidence = try db.routeSourceEvidence(gpa, .{
        .provider = app_provider_coverage_actual_inputs.actualCaptureProviderDbValue(options.filter.provider),
        .limit = actual_capture_source_evidence_limit,
    });
    errdefer source_evidence.deinit(gpa);
    var cloudflare_accounts = try app_provider_coverage_actual_inputs.loadActualCaptureCloudflareAccountHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_accounts) |*rows| rows.deinit(gpa);
    var cloudflare_zones = try app_provider_coverage_actual_inputs.loadActualCaptureCloudflareZoneHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_zones) |*rows| rows.deinit(gpa);
    var cloudflare_resources = try app_provider_coverage_actual_inputs.loadActualCaptureCloudflareResourceHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_resources) |*rows| rows.deinit(gpa);
    var cloudflare_inventory = try app_provider_coverage_actual_inputs.loadActualCaptureCloudflareInventoryHints(gpa, db, options.filter.provider);
    errdefer if (cloudflare_inventory) |*rows| rows.deinit(gpa);
    var hostinger_vps = try app_provider_coverage_actual_inputs.loadActualCaptureHostingerHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_vps) |*rows| rows.deinit(gpa);
    var hostinger_resources = try app_provider_coverage_actual_inputs.loadActualCaptureHostingerResourceHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_resources) |*rows| rows.deinit(gpa);
    var hostinger_inventory = try app_provider_coverage_actual_inputs.loadActualCaptureHostingerInventoryHints(gpa, db, options.filter.provider);
    errdefer if (hostinger_inventory) |*rows| rows.deinit(gpa);
    return .{
        .options = options,
        .routes = owned_routes,
        .source_routes = owned_source_routes,
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

fn actualCaptureSourceRouteFilter(filter: RouteFilter) RouteFilter {
    return .{
        .provider = filter.provider,
        .method = .GET,
        .mode = .read,
    };
}

pub fn actualCaptureRouteInFocus(options: ActualCaptureOptions, row: CoverageRoute) bool {
    return switch (options.focus) {
        .all => true,
        .control_plane => app_provider_coverage_routes.tagIsControlPlane(row.route.provider.name(), row.route.tag),
    };
}

fn addFamilyCandidateStats(routes: []const CoverageRoute, items: []ActualCaptureCandidateRank) void {
    for (items) |*item| {
        const item_route = routes[item.route_index];
        for (items) |other| {
            const other_route = routes[other.route_index];
            if (!candidateFamilyMatches(item_route, item.*, other_route, other)) continue;
            item.family_candidate_routes += 1;
            if (other.route_ready) item.family_ready_candidates += 1;
            if (staticReadGap(other_route)) {
                item.family_pending_read_gaps += 1;
                if (!hasCoverageEvidence(other_route.tests)) item.family_missing_tests += 1;
            }
        }
    }
}

fn sortCandidateOrder(routes: []const CoverageRoute, items: []ActualCaptureCandidateRank) void {
    var index: usize = 1;
    while (index < items.len) : (index += 1) {
        var cursor = index;
        while (cursor > 0 and candidateRankLessThan(routes, items[cursor], items[cursor - 1])) : (cursor -= 1) {
            const tmp = items[cursor - 1];
            items[cursor - 1] = items[cursor];
            items[cursor] = tmp;
        }
    }
}

fn candidateRankLessThan(routes: []const CoverageRoute, lhs: ActualCaptureCandidateRank, rhs: ActualCaptureCandidateRank) bool {
    if (lhs.familyPriority() != rhs.familyPriority()) return lhs.familyPriority() > rhs.familyPriority();
    if (lhs.family_ready_candidates != rhs.family_ready_candidates) return lhs.family_ready_candidates > rhs.family_ready_candidates;
    if (lhs.family_candidate_routes != rhs.family_candidate_routes) return lhs.family_candidate_routes > rhs.family_candidate_routes;
    if (actualCaptureStatePriority(lhs.state) != actualCaptureStatePriority(rhs.state)) return actualCaptureStatePriority(lhs.state) > actualCaptureStatePriority(rhs.state);
    if (lhs.route_ready != rhs.route_ready) return lhs.route_ready;
    if (lhs.route_missing_inputs != rhs.route_missing_inputs) return lhs.route_missing_inputs < rhs.route_missing_inputs;
    const lhs_route = routes[lhs.route_index].route;
    const rhs_route = routes[rhs.route_index].route;
    const family_order = actualCaptureFamilyOrder(lhs.focus_family, rhs.focus_family);
    if (family_order != .eq) return family_order == .lt;
    const provider_order = std.mem.order(u8, lhs_route.provider.name(), rhs_route.provider.name());
    if (provider_order != .eq) return provider_order == .lt;
    const tag_order = std.mem.order(u8, lhs_route.tag, rhs_route.tag);
    if (tag_order != .eq) return tag_order == .lt;
    return lhs.route_index < rhs.route_index;
}

fn actualCaptureStatePriority(state: ActualCaptureState) usize {
    return switch (state) {
        .non_ok => 2,
        .missing => 1,
        .ok => 0,
    };
}

fn actualCaptureFamilyOrder(lhs: ?WorkplanFamily, rhs: ?WorkplanFamily) std.math.Order {
    return std.math.order(actualCaptureFamilyRank(lhs), actualCaptureFamilyRank(rhs));
}

fn actualCaptureFamilyRank(family: ?WorkplanFamily) usize {
    return switch (family orelse .all) {
        .hostinger_vps => 0,
        .dns => 1,
        .zones => 2,
        .ssl_tls => 3,
        .logs => 4,
        .access => 5,
        .tunnels => 6,
        .rulesets => 7,
        .cache => 8,
        .security => 9,
        .tokens => 10,
        .memberships => 11,
        .accounts => 12,
        .billing => 13,
        .domains => 14,
        .hosting => 15,
        .docker => 16,
        .reach => 17,
        .ecommerce => 18,
        .horizons => 19,
        .verification => 20,
        .public_keys => 21,
        .iam => 22,
        .custom_pages => 23,
        .healthchecks => 24,
        .load_balancing => 25,
        .all => 1000,
    };
}

fn candidateFamilyMatches(item_route: CoverageRoute, item: ActualCaptureCandidateRank, other_route: CoverageRoute, other: ActualCaptureCandidateRank) bool {
    if (!std.mem.eql(u8, item_route.route.provider.name(), other_route.route.provider.name())) return false;
    if (item.focus_family == null or other.focus_family == null) return item.focus_family == null and other.focus_family == null;
    return item.focus_family.? == other.focus_family.?;
}

fn staticReadGap(row: CoverageRoute) bool {
    if (row.route.mode != .read) return false;
    return switch (row.route.support) {
        .planned => true,
        .blocked_permission => !hasCoverageEvidence(row.tests),
        .implemented, .partial, .unsafe_mutation, .deprecated, .not_applicable => false,
    };
}

fn hasCoverageEvidence(tests: []const u8) bool {
    return tests.len != 0 and !std.mem.eql(u8, tests, "missing");
}
