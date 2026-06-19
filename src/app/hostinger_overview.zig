const std = @import("std");
const app_provider_api = @import("app_provider_api");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const positiveLimit = app_render.positiveLimit;
const writeJsonStringField = app_render.writeJsonStringField;
const writeTextField = app_render.writeTextField;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub const VpsOverviewOptions = struct {
    limit: i64 = 20,
    snapshot_limit: i64 = 12,
};

pub const AccountOverviewOptions = struct {
    limit: i64 = 20,
    snapshot_limit: i64 = 12,
};

pub const HostingerFamily = enum {
    billing,
    dns,
    domains,
    hosting,
    vps,
    docker,
    security,
    reach,
    ecommerce,
    horizons,
    other,

    fn label(self: HostingerFamily) []const u8 {
        return switch (self) {
            .billing => "billing",
            .dns => "dns",
            .domains => "domains",
            .hosting => "hosting",
            .vps => "vps",
            .docker => "docker",
            .security => "security",
            .reach => "reach",
            .ecommerce => "ecommerce",
            .horizons => "horizons",
            .other => "other",
        };
    }
};

pub const HostingerFamilySummary = struct {
    billing: i64 = 0,
    dns: i64 = 0,
    domains: i64 = 0,
    hosting: i64 = 0,
    vps: i64 = 0,
    docker: i64 = 0,
    security: i64 = 0,
    reach: i64 = 0,
    ecommerce: i64 = 0,
    horizons: i64 = 0,
    other: i64 = 0,

    fn add(self: *HostingerFamilySummary, family: HostingerFamily, count: i64) void {
        switch (family) {
            .billing => self.billing += count,
            .dns => self.dns += count,
            .domains => self.domains += count,
            .hosting => self.hosting += count,
            .vps => self.vps += count,
            .docker => self.docker += count,
            .security => self.security += count,
            .reach => self.reach += count,
            .ecommerce => self.ecommerce += count,
            .horizons => self.horizons += count,
            .other => self.other += count,
        }
    }
};

const hostinger_account_api_family_labels = [_][]const u8{
    "billing",
    "dns",
    "domains",
    "hosting",
    "ecommerce",
    "horizons",
    "reach",
    "domain_access_verifier",
};

const hostinger_vps_api_family_labels = [_][]const u8{
    "virtual_machine",
    "firewall",
    "docker",
    "post_install_scripts",
    "snapshots",
    "public_keys",
    "malware_scanner",
    "actions",
    "backups",
    "os_templates",
    "ptr_records",
    "recovery",
    "data_centers",
};

pub const AccountOverviewSummary = struct {
    vps: usize = 0,
    running_vps: usize = 0,
    stopped_or_other_vps: usize = 0,
    complete_vps_core_coverage: usize = 0,
    partial_vps_core_coverage: usize = 0,
    resources: i64 = 0,
    inventory_items: i64 = 0,
    resource_kinds: usize = 0,
    inventory_kinds: usize = 0,
    inventory_facets: usize = 0,
    recent_snapshots: usize = 0,
    families: HostingerFamilySummary = .{},
    api_routes: usize = 0,
    api_read_routes: usize = 0,
    api_dry_run_routes: usize = 0,
    api_write_routes: usize = 0,
    api_not_applicable_routes: usize = 0,
    api_deprecated_routes: usize = 0,
    api_blocked_permission_routes: usize = 0,
    api_families: usize = 0,
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    not_applicable_families: usize = 0,
    blocked_or_missing_families: usize = 0,
};

pub const VpsOverviewSummary = struct {
    vps: usize = 0,
    running: usize = 0,
    stopped_or_other: usize = 0,
    complete_core_coverage: usize = 0,
    partial_core_coverage: usize = 0,
    with_details: usize = 0,
    with_metrics: usize = 0,
    with_actions: usize = 0,
    with_backups: usize = 0,
    with_snapshot: usize = 0,
    with_public_keys: usize = 0,
    with_security: usize = 0,
    with_docker: usize = 0,
    missing_details: usize = 0,
    missing_metrics: usize = 0,
    missing_actions: usize = 0,
    missing_backups: usize = 0,
    missing_snapshot: usize = 0,
    resource_kinds: usize = 0,
    inventory_kinds: usize = 0,
    metric_summaries: usize = 0,
    family_summaries: usize = 0,
    recent_snapshots: usize = 0,
    api_routes: usize = 0,
    api_read_routes: usize = 0,
    api_dry_run_routes: usize = 0,
    api_write_routes: usize = 0,
    api_not_applicable_routes: usize = 0,
    api_deprecated_routes: usize = 0,
    api_blocked_permission_routes: usize = 0,
    api_families: usize = 0,
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    dry_run_only_families: usize = 0,
    not_applicable_families: usize = 0,
    blocked_or_missing_families: usize = 0,
};

const VpsCoverage = struct {
    details: bool = false,
    metrics: bool = false,
    actions: bool = false,
    backups: bool = false,
    snapshot: bool = false,
    public_keys: bool = false,
    security: bool = false,
    docker: bool = false,

    fn completeCore(self: VpsCoverage) bool {
        return self.details and self.metrics and self.actions and self.backups and self.snapshot;
    }
};

pub const AccountOverview = struct {
    vps_overview: VpsOverview,
    inventory_facets: db_store.InventoryFacets,
    family_facets: db_store.InventoryFacets,
    recent_snapshots: db_store.SnapshotSummaries,
    summary_snapshots: db_store.SnapshotSummaries,
    api_family_summaries: app_provider_api.ApiFamilySummaries,
    resource_count: i64,
    inventory_count: i64,

    pub fn load(ctx: Context, options: AccountOverviewOptions) !AccountOverview {
        var vps_overview = try VpsOverview.load(ctx, .{ .limit = options.limit });
        errdefer vps_overview.deinit(ctx.gpa);
        var inventory_facets = try ctx.db.inventoryFacets(ctx.gpa, .{
            .provider = "hostinger",
            .limit = positiveLimit(options.limit, 20),
        });
        errdefer inventory_facets.deinit(ctx.gpa);
        var family_facets = try ctx.db.inventoryFacets(ctx.gpa, .{
            .provider = "hostinger",
            .limit = 5000,
        });
        errdefer family_facets.deinit(ctx.gpa);
        var recent_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "hostinger", positiveLimit(options.snapshot_limit, 12));
        errdefer recent_snapshots.deinit(ctx.gpa);
        var summary_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "hostinger", 5000);
        errdefer summary_snapshots.deinit(ctx.gpa);
        var api_family_summaries = try loadHostingerAccountApiFamilySummaries(ctx.io, ctx.gpa);
        errdefer api_family_summaries.deinit(ctx.gpa);
        for (family_facets.items) |facet| {
            addAccountApiFamilyObserved(&api_family_summaries, facet.kind, facet.count);
        }
        for (summary_snapshots.items) |snapshot| {
            addAccountApiFamilyObserved(&api_family_summaries, snapshot.kind, 1);
        }
        return .{
            .vps_overview = vps_overview,
            .inventory_facets = inventory_facets,
            .family_facets = family_facets,
            .recent_snapshots = recent_snapshots,
            .summary_snapshots = summary_snapshots,
            .api_family_summaries = api_family_summaries,
            .resource_count = try ctx.db.countTable("hostinger_resources"),
            .inventory_count = try ctx.db.countTable("hostinger_inventory_items"),
        };
    }

    pub fn deinit(self: *AccountOverview, allocator: Allocator) void {
        self.vps_overview.deinit(allocator);
        self.inventory_facets.deinit(allocator);
        self.family_facets.deinit(allocator);
        self.recent_snapshots.deinit(allocator);
        self.summary_snapshots.deinit(allocator);
        self.api_family_summaries.deinit(allocator);
    }

    pub fn summary(self: AccountOverview) AccountOverviewSummary {
        const vps_summary = self.vps_overview.summary();
        const route_totals = self.api_family_summaries.routeTotals();
        const status_totals = self.api_family_summaries.statusTotals();
        var out = AccountOverviewSummary{
            .vps = vps_summary.vps,
            .running_vps = vps_summary.running,
            .stopped_or_other_vps = vps_summary.stopped_or_other,
            .complete_vps_core_coverage = vps_summary.complete_core_coverage,
            .partial_vps_core_coverage = vps_summary.partial_core_coverage,
            .resources = self.resource_count,
            .inventory_items = self.inventory_count,
            .resource_kinds = self.vps_overview.summary_resource_kinds.items.len,
            .inventory_kinds = self.vps_overview.summary_inventory_kinds.items.len,
            .inventory_facets = self.family_facets.items.len,
            .recent_snapshots = self.recent_snapshots.items.len,
            .api_routes = route_totals.official_routes,
            .api_read_routes = route_totals.read_routes,
            .api_dry_run_routes = route_totals.dry_run_routes,
            .api_write_routes = route_totals.write_routes,
            .api_not_applicable_routes = route_totals.not_applicable_routes,
            .api_deprecated_routes = route_totals.deprecated_routes,
            .api_blocked_permission_routes = route_totals.blocked_permission_routes,
            .api_families = self.api_family_summaries.items.len,
            .observed_read_families = status_totals.observed_read_families,
            .missing_read_families = status_totals.missing_read_families,
            .not_applicable_families = status_totals.not_applicable_families,
            .blocked_or_missing_families = status_totals.blocked_or_missing_families,
        };
        for (self.family_facets.items) |facet| {
            out.families.add(hostingerFamilyForKind(facet.kind), facet.count);
        }
        return out;
    }

    pub fn writeText(self: AccountOverview, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Hostinger account overview\n");
        try writeAccountOverviewSummaryText(counts, writer);

        try writer.writeAll("vps\n");
        if (self.vps_overview.vps.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.vps_overview.vps.items) |row| try writeVpsRowText(row, self.vps_overview.coverageFor(row.id), writer);
        }

        try writer.writeAll("inventory facets\n");
        if (self.inventory_facets.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.inventory_facets.items) |row| try writeInventoryFacetText(row, writer);
        }

        try writer.writeAll("resources\n");
        if (self.vps_overview.resource_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.vps_overview.resource_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("inventory\n");
        if (self.vps_overview.inventory_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.vps_overview.inventory_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("api families\n");
        for (self.api_family_summaries.items) |row| try app_provider_api.writeApiFamilySummaryText(row, writer);

        try writer.writeAll("recent snapshots\n");
        if (self.recent_snapshots.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.recent_snapshots.items) |row| try writeSnapshotText(row, writer);
        }
    }

    pub fn writeJson(self: AccountOverview, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"hostinger_account_overview\",\"summary\":");
        try writeAccountOverviewSummaryJson(self.summary(), writer);
        try writer.writeAll(",\"vps\":[");
        for (self.vps_overview.vps.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsRowJson(row, self.vps_overview.coverageFor(row.id), writer);
        }
        try writer.writeAll("],\"inventory_facets\":[");
        for (self.inventory_facets.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeInventoryFacetJson(row, writer);
        }
        try writer.writeAll("],\"resource_kinds\":[");
        for (self.vps_overview.resource_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"inventory_kinds\":[");
        for (self.vps_overview.inventory_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"api_families\":[");
        for (self.api_family_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_provider_api.writeApiFamilySummaryJson(row, writer);
        }
        try writer.writeAll("],\"recent_snapshots\":[");
        for (self.recent_snapshots.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_render.writeSnapshotJson(writer, row, .{ .include_id = true });
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub const VpsOverview = struct {
    vps: db_store.HostingerVpsRows,
    resource_kinds: db_store.HostingerKindCounts,
    inventory_kinds: db_store.HostingerKindCounts,
    metric_summaries: db_store.HostingerMetricSummaries,
    family_summaries: db_store.HostingerVpsFamilySummaries,
    recent_snapshots: db_store.SnapshotSummaries,
    summary_vps: db_store.HostingerVpsRows,
    summary_resource_kinds: db_store.HostingerKindCounts,
    summary_inventory_kinds: db_store.HostingerKindCounts,
    summary_metric_summaries: db_store.HostingerMetricSummaries,
    summary_family_summaries: db_store.HostingerVpsFamilySummaries,
    summary_snapshots: db_store.SnapshotSummaries,
    api_family_summaries: app_provider_api.ApiFamilySummaries,

    pub fn load(ctx: Context, options: VpsOverviewOptions) !VpsOverview {
        const limit = positiveLimit(options.limit, 20);
        var vps = try ctx.db.hostingerVpsRows(ctx.gpa, limit);
        errdefer vps.deinit(ctx.gpa);
        var resource_kinds = try ctx.db.hostingerResourceKindCounts(ctx.gpa, limit);
        errdefer resource_kinds.deinit(ctx.gpa);
        var inventory_kinds = try ctx.db.hostingerInventoryKindCounts(ctx.gpa, limit);
        errdefer inventory_kinds.deinit(ctx.gpa);
        var metric_summaries = try ctx.db.hostingerMetricSummaries(ctx.gpa, limit);
        errdefer metric_summaries.deinit(ctx.gpa);
        var family_summaries = try ctx.db.hostingerVpsFamilySummaries(ctx.gpa, limit);
        errdefer family_summaries.deinit(ctx.gpa);
        var recent_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "hostinger", positiveLimit(options.snapshot_limit, 12));
        errdefer recent_snapshots.deinit(ctx.gpa);
        var summary_vps = try ctx.db.hostingerVpsRows(ctx.gpa, 5000);
        errdefer summary_vps.deinit(ctx.gpa);
        var summary_resource_kinds = try ctx.db.hostingerResourceKindCounts(ctx.gpa, 5000);
        errdefer summary_resource_kinds.deinit(ctx.gpa);
        var summary_inventory_kinds = try ctx.db.hostingerInventoryKindCounts(ctx.gpa, 5000);
        errdefer summary_inventory_kinds.deinit(ctx.gpa);
        var summary_metric_summaries = try ctx.db.hostingerMetricSummaries(ctx.gpa, 5000);
        errdefer summary_metric_summaries.deinit(ctx.gpa);
        var summary_family_summaries = try ctx.db.hostingerVpsFamilySummaries(ctx.gpa, 5000);
        errdefer summary_family_summaries.deinit(ctx.gpa);
        var summary_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "hostinger", 5000);
        errdefer summary_snapshots.deinit(ctx.gpa);
        var api_family_summaries = try loadHostingerVpsApiFamilySummaries(ctx.io, ctx.gpa);
        errdefer api_family_summaries.deinit(ctx.gpa);
        if (summary_vps.items.len != 0) {
            addVpsApiFamilyObserved(&api_family_summaries, "vps", @intCast(summary_vps.items.len));
        }
        for (summary_resource_kinds.items) |row| {
            addVpsApiFamilyObserved(&api_family_summaries, row.kind, row.count);
        }
        for (summary_inventory_kinds.items) |row| {
            addVpsApiFamilyObserved(&api_family_summaries, row.kind, row.count);
        }
        for (summary_metric_summaries.items) |row| {
            addVpsApiFamilyObserved(&api_family_summaries, "metrics", row.count);
        }
        for (summary_snapshots.items) |row| {
            addVpsApiFamilyObserved(&api_family_summaries, row.kind, 1);
        }
        return .{
            .vps = vps,
            .resource_kinds = resource_kinds,
            .inventory_kinds = inventory_kinds,
            .metric_summaries = metric_summaries,
            .family_summaries = family_summaries,
            .recent_snapshots = recent_snapshots,
            .summary_vps = summary_vps,
            .summary_resource_kinds = summary_resource_kinds,
            .summary_inventory_kinds = summary_inventory_kinds,
            .summary_metric_summaries = summary_metric_summaries,
            .summary_family_summaries = summary_family_summaries,
            .summary_snapshots = summary_snapshots,
            .api_family_summaries = api_family_summaries,
        };
    }

    pub fn deinit(self: *VpsOverview, allocator: Allocator) void {
        self.vps.deinit(allocator);
        self.resource_kinds.deinit(allocator);
        self.inventory_kinds.deinit(allocator);
        self.metric_summaries.deinit(allocator);
        self.family_summaries.deinit(allocator);
        self.recent_snapshots.deinit(allocator);
        self.summary_vps.deinit(allocator);
        self.summary_resource_kinds.deinit(allocator);
        self.summary_inventory_kinds.deinit(allocator);
        self.summary_metric_summaries.deinit(allocator);
        self.summary_family_summaries.deinit(allocator);
        self.summary_snapshots.deinit(allocator);
        self.api_family_summaries.deinit(allocator);
    }

    pub fn summary(self: VpsOverview) VpsOverviewSummary {
        const route_totals = self.api_family_summaries.routeTotals();
        const status_totals = self.api_family_summaries.statusTotals();
        var out = VpsOverviewSummary{
            .vps = self.summary_vps.items.len,
            .resource_kinds = self.summary_resource_kinds.items.len,
            .inventory_kinds = self.summary_inventory_kinds.items.len,
            .metric_summaries = self.summary_metric_summaries.items.len,
            .family_summaries = self.summary_family_summaries.items.len,
            .recent_snapshots = self.recent_snapshots.items.len,
            .api_routes = route_totals.official_routes,
            .api_read_routes = route_totals.read_routes,
            .api_dry_run_routes = route_totals.dry_run_routes,
            .api_write_routes = route_totals.write_routes,
            .api_not_applicable_routes = route_totals.not_applicable_routes,
            .api_deprecated_routes = route_totals.deprecated_routes,
            .api_blocked_permission_routes = route_totals.blocked_permission_routes,
            .api_families = self.api_family_summaries.items.len,
            .observed_read_families = status_totals.observed_read_families,
            .missing_read_families = status_totals.missing_read_families,
            .dry_run_only_families = status_totals.dry_run_only_families,
            .not_applicable_families = status_totals.not_applicable_families,
            .blocked_or_missing_families = status_totals.blocked_or_missing_families,
        };
        for (self.summary_vps.items) |row| {
            if (stateLooksRunning(row.status)) {
                out.running += 1;
            } else {
                out.stopped_or_other += 1;
            }
            const coverage = self.coverageFor(row.id);
            if (coverage.completeCore()) {
                out.complete_core_coverage += 1;
            } else {
                out.partial_core_coverage += 1;
            }
            if (coverage.details) out.with_details += 1 else out.missing_details += 1;
            if (coverage.metrics) out.with_metrics += 1 else out.missing_metrics += 1;
            if (coverage.actions) out.with_actions += 1 else out.missing_actions += 1;
            if (coverage.backups) out.with_backups += 1 else out.missing_backups += 1;
            if (coverage.snapshot) out.with_snapshot += 1 else out.missing_snapshot += 1;
            if (coverage.public_keys) out.with_public_keys += 1;
            if (coverage.security) out.with_security += 1;
            if (coverage.docker) out.with_docker += 1;
        }
        return out;
    }

    fn coverageFor(self: VpsOverview, vm_id: []const u8) VpsCoverage {
        var out = VpsCoverage{};
        for (self.summary_metric_summaries.items) |row| {
            if (std.mem.eql(u8, row.vm_id, vm_id) and row.count > 0) out.metrics = true;
        }
        for (self.summary_family_summaries.items) |row| {
            if (!std.mem.eql(u8, row.vm_id, vm_id) or row.count <= 0) continue;
            addCoverageKind(&out, row.kind);
        }
        return out;
    }

    pub fn writeText(self: VpsOverview, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Hostinger VPS overview\n");
        try writer.print("summary vps={d} running={d} stopped_or_other={d} complete_core_coverage={d} partial_core_coverage={d} details={d} metrics={d} actions={d} backups={d} snapshot={d} public_keys={d} security={d} docker={d} missing_details={d} missing_metrics={d} missing_actions={d} missing_backups={d} missing_snapshot={d} resource_kinds={d} inventory_kinds={d} metric_summaries={d} family_summaries={d} recent_snapshots={d}\n", .{
            counts.vps,
            counts.running,
            counts.stopped_or_other,
            counts.complete_core_coverage,
            counts.partial_core_coverage,
            counts.with_details,
            counts.with_metrics,
            counts.with_actions,
            counts.with_backups,
            counts.with_snapshot,
            counts.with_public_keys,
            counts.with_security,
            counts.with_docker,
            counts.missing_details,
            counts.missing_metrics,
            counts.missing_actions,
            counts.missing_backups,
            counts.missing_snapshot,
            counts.resource_kinds,
            counts.inventory_kinds,
            counts.metric_summaries,
            counts.family_summaries,
            counts.recent_snapshots,
        });
        try writer.print("api_routes total={d} read={d} dry_run={d} write={d} not_applicable={d} deprecated={d} blocked_permission={d} families={d} observed_read_families={d} missing_read_families={d} dry_run_only_families={d} not_applicable_families={d} blocked_or_missing_families={d}\n", .{
            counts.api_routes,
            counts.api_read_routes,
            counts.api_dry_run_routes,
            counts.api_write_routes,
            counts.api_not_applicable_routes,
            counts.api_deprecated_routes,
            counts.api_blocked_permission_routes,
            counts.api_families,
            counts.observed_read_families,
            counts.missing_read_families,
            counts.dry_run_only_families,
            counts.not_applicable_families,
            counts.blocked_or_missing_families,
        });
        try writer.writeAll("vps\n");
        if (self.vps.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.vps.items) |row| try writeVpsRowText(row, self.coverageFor(row.id), writer);
        }

        try writer.writeAll("resources\n");
        if (self.resource_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.resource_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("inventory\n");
        if (self.inventory_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.inventory_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("metrics\n");
        if (self.metric_summaries.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.metric_summaries.items) |row| try writeMetricSummaryText(row, writer);
        }

        try writer.writeAll("vm family\n");
        if (self.family_summaries.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.family_summaries.items) |row| try writeVpsFamilySummaryText(row, writer);
        }

        try writer.writeAll("api families\n");
        for (self.api_family_summaries.items) |row| try app_provider_api.writeApiFamilySummaryText(row, writer);

        try writer.writeAll("recent snapshots\n");
        if (self.recent_snapshots.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.recent_snapshots.items) |row| try writeSnapshotText(row, writer);
        }
    }

    pub fn writeJson(self: VpsOverview, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"hostinger_vps_overview\",\"summary\":");
        try writeVpsOverviewSummaryJson(self.summary(), writer);
        try writer.writeAll(",\"vps\":[");
        for (self.vps.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsRowJson(row, self.coverageFor(row.id), writer);
        }
        try writer.writeAll("],\"resource_kinds\":[");
        for (self.resource_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"inventory_kinds\":[");
        for (self.inventory_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"metric_summaries\":[");
        for (self.metric_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeMetricSummaryJson(row, writer);
        }
        try writer.writeAll("],\"vm_family\":[");
        for (self.family_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsFamilySummaryJson(row, writer);
        }
        try writer.writeAll("],\"api_families\":[");
        for (self.api_family_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_provider_api.writeApiFamilySummaryJson(row, writer);
        }
        try writer.writeAll("],\"recent_snapshots\":[");
        for (self.recent_snapshots.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_render.writeSnapshotJson(writer, row, .{ .include_id = true });
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

fn addCoverageKind(out: *VpsCoverage, kind: []const u8) void {
    if (kindLooksLikeDetails(kind)) out.details = true;
    if (kindLooksLikeMetrics(kind)) out.metrics = true;
    if (kindLooksLikeActions(kind)) out.actions = true;
    if (kindLooksLikeBackups(kind)) out.backups = true;
    if (kindLooksLikeSnapshot(kind)) out.snapshot = true;
    if (kindLooksLikePublicKeys(kind)) out.public_keys = true;
    if (kindLooksLikeSecurity(kind)) out.security = true;
    if (kindLooksLikeDocker(kind)) out.docker = true;
}

fn kindLooksLikeDetails(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "vps-detail") or
        containsIgnoreCase(kind, "virtualmachinedetail") or
        containsIgnoreCase(kind, "virtual-machine-detail") or
        containsIgnoreCase(kind, "virtual_machine_detail") or
        containsIgnoreCase(kind, "getvirtualmachinev1");
}

fn kindLooksLikeMetrics(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "metrics") or containsIgnoreCase(kind, "metrics");
}

fn kindLooksLikeActions(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "actions") or
        std.ascii.eqlIgnoreCase(kind, "action-detail") or
        containsIgnoreCase(kind, "actions") or
        containsIgnoreCase(kind, "action-detail") or
        containsIgnoreCase(kind, "actiondetail");
}

fn kindLooksLikeBackups(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "backups") or
        containsIgnoreCase(kind, "backups") or
        containsIgnoreCase(kind, "backup");
}

fn kindLooksLikeSnapshot(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "snapshot") or containsIgnoreCase(kind, "snapshot");
}

fn kindLooksLikePublicKeys(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "public-keys") or
        containsIgnoreCase(kind, "public-keys") or
        containsIgnoreCase(kind, "public_keys") or
        containsIgnoreCase(kind, "publickey") or
        containsIgnoreCase(kind, "public-key");
}

fn kindLooksLikeSecurity(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "monarx") or
        containsIgnoreCase(kind, "monarx") or
        containsIgnoreCase(kind, "malware") or
        containsIgnoreCase(kind, "security");
}

fn kindLooksLikeDocker(kind: []const u8) bool {
    return std.ascii.eqlIgnoreCase(kind, "docker") or containsIgnoreCase(kind, "docker");
}

fn hostingerFamilyForKind(kind: []const u8) HostingerFamily {
    if (containsIgnoreCase(kind, "billing")) return .billing;
    if (containsIgnoreCase(kind, "dns")) return .dns;
    if (kindLooksLikeDocker(kind) or containsIgnoreCase(kind, "project") or containsIgnoreCase(kind, "container")) return .docker;
    if (kindLooksLikeSecurity(kind) or containsIgnoreCase(kind, "scanmetrics")) return .security;
    if (containsIgnoreCase(kind, "ecommerce") or containsIgnoreCase(kind, "store")) return .ecommerce;
    if (containsIgnoreCase(kind, "horizons")) return .horizons;
    if (containsIgnoreCase(kind, "reach") or containsIgnoreCase(kind, "contact") or containsIgnoreCase(kind, "segment") or containsIgnoreCase(kind, "profile")) return .reach;
    if (containsIgnoreCase(kind, "domain")) return .domains;
    if (containsIgnoreCase(kind, "hosting") or containsIgnoreCase(kind, "website") or containsIgnoreCase(kind, "wordpress") or containsIgnoreCase(kind, "nodejs")) return .hosting;
    if (containsIgnoreCase(kind, "vps") or
        kindLooksLikeDetails(kind) or
        kindLooksLikeMetrics(kind) or
        kindLooksLikeActions(kind) or
        kindLooksLikeBackups(kind) or
        kindLooksLikeSnapshot(kind) or
        kindLooksLikePublicKeys(kind) or
        containsIgnoreCase(kind, "template") or
        containsIgnoreCase(kind, "data-center") or
        containsIgnoreCase(kind, "datacenter") or
        containsIgnoreCase(kind, "firewall"))
    {
        return .vps;
    }
    return .other;
}

fn loadHostingerAccountApiFamilySummaries(io: Io, gpa: Allocator) !app_provider_api.ApiFamilySummaries {
    return try app_provider_api.loadProvider(io, gpa, .{}, .hostinger, .{
        .seed_labels = hostinger_account_api_family_labels[0..],
        .classifier = hostingerAccountApiFamilyLabelForRoute,
    });
}

fn loadHostingerVpsApiFamilySummaries(io: Io, gpa: Allocator) !app_provider_api.ApiFamilySummaries {
    return try app_provider_api.loadProvider(io, gpa, .{}, .hostinger, .{
        .seed_labels = hostinger_vps_api_family_labels[0..],
        .classifier = hostingerVpsApiFamilyLabelForRoute,
    });
}

fn hostingerAccountApiFamilyLabelForRoute(route: app_provider_api.Route) ?[]const u8 {
    const tag = route.tag;
    if (containsIgnoreCase(tag, "billing:")) return "billing";
    if (containsIgnoreCase(tag, "dns:")) return "dns";
    if (containsIgnoreCase(tag, "domains:")) return "domains";
    if (containsIgnoreCase(tag, "hosting:")) return "hosting";
    if (containsIgnoreCase(tag, "ecommerce:")) return "ecommerce";
    if (containsIgnoreCase(tag, "horizons:")) return "horizons";
    if (containsIgnoreCase(tag, "reach:")) return "reach";
    if (containsIgnoreCase(tag, "domain access verifier:")) return "domain_access_verifier";
    return null;
}

fn hostingerVpsApiFamilyLabelForRoute(route: app_provider_api.Route) ?[]const u8 {
    const tag = route.tag;
    if (!containsIgnoreCase(tag, "vps:")) return null;
    if (containsIgnoreCase(tag, "virtual machine")) return "virtual_machine";
    if (containsIgnoreCase(tag, "firewall")) return "firewall";
    if (containsIgnoreCase(tag, "docker")) return "docker";
    if (containsIgnoreCase(tag, "post-install")) return "post_install_scripts";
    if (containsIgnoreCase(tag, "snapshot")) return "snapshots";
    if (containsIgnoreCase(tag, "public key")) return "public_keys";
    if (containsIgnoreCase(tag, "malware")) return "malware_scanner";
    if (containsIgnoreCase(tag, "action")) return "actions";
    if (containsIgnoreCase(tag, "backup")) return "backups";
    if (containsIgnoreCase(tag, "os template")) return "os_templates";
    if (containsIgnoreCase(tag, "ptr")) return "ptr_records";
    if (containsIgnoreCase(tag, "recovery")) return "recovery";
    if (containsIgnoreCase(tag, "data center")) return "data_centers";
    return null;
}

fn addAccountApiFamilyObserved(summaries: *app_provider_api.ApiFamilySummaries, kind: []const u8, count: i64) void {
    const label = accountApiFamilyLabelForKind(kind) orelse return;
    _ = summaries.addObservedByLabel(label, count);
}

fn accountApiFamilyLabelForKind(kind: []const u8) ?[]const u8 {
    if (containsIgnoreCase(kind, "domain-access") or containsIgnoreCase(kind, "verifications") or containsIgnoreCase(kind, "v2_getdomainverificationsdirect")) return "domain_access_verifier";
    if (containsIgnoreCase(kind, "billing")) return "billing";
    if (containsIgnoreCase(kind, "dns")) return "dns";
    if (containsIgnoreCase(kind, "ecommerce") or containsIgnoreCase(kind, "store")) return "ecommerce";
    if (containsIgnoreCase(kind, "horizons")) return "horizons";
    if (containsIgnoreCase(kind, "reach") or containsIgnoreCase(kind, "contact") or containsIgnoreCase(kind, "segment") or containsIgnoreCase(kind, "profile")) return "reach";
    if (containsIgnoreCase(kind, "hosting") or
        containsIgnoreCase(kind, "wordpress") or
        containsIgnoreCase(kind, "nodejs") or
        containsIgnoreCase(kind, "database") or
        containsIgnoreCase(kind, "phpmyadmin") or
        containsIgnoreCase(kind, "parked") or
        containsIgnoreCase(kind, "subdomain"))
    {
        return "hosting";
    }
    if (containsIgnoreCase(kind, "domain") or containsIgnoreCase(kind, "whois") or containsIgnoreCase(kind, "forwarding") or containsIgnoreCase(kind, "availability")) return "domains";
    return null;
}

fn addVpsApiFamilyObserved(summaries: *app_provider_api.ApiFamilySummaries, kind: []const u8, count: i64) void {
    const label = vpsApiFamilyLabelForKind(kind) orelse return;
    _ = summaries.addObservedByLabel(label, count);
}

fn vpsApiFamilyLabelForKind(kind: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(kind, "data-centers") or containsIgnoreCase(kind, "data-center") or containsIgnoreCase(kind, "datacenter")) return "data_centers";
    if (std.ascii.eqlIgnoreCase(kind, "firewalls") or std.ascii.eqlIgnoreCase(kind, "firewall-detail") or containsIgnoreCase(kind, "firewall")) return "firewall";
    if (kindLooksLikeDocker(kind) or containsIgnoreCase(kind, "project") or containsIgnoreCase(kind, "container")) return "docker";
    if (containsIgnoreCase(kind, "post-install") or containsIgnoreCase(kind, "post_install")) return "post_install_scripts";
    if (kindLooksLikeSnapshot(kind)) return "snapshots";
    if (std.ascii.eqlIgnoreCase(kind, "public-keys-global")) return "public_keys";
    if (kindLooksLikeSecurity(kind) or containsIgnoreCase(kind, "scanmetrics")) return "malware_scanner";
    if (kindLooksLikeActions(kind)) return "actions";
    if (kindLooksLikeBackups(kind)) return "backups";
    if (std.ascii.eqlIgnoreCase(kind, "templates") or std.ascii.eqlIgnoreCase(kind, "template-detail") or containsIgnoreCase(kind, "template")) return "os_templates";
    if (containsIgnoreCase(kind, "ptr")) return "ptr_records";
    if (containsIgnoreCase(kind, "recovery")) return "recovery";
    if (std.ascii.eqlIgnoreCase(kind, "vps") or kindLooksLikeDetails(kind) or kindLooksLikeMetrics(kind) or std.ascii.eqlIgnoreCase(kind, "public-keys")) return "virtual_machine";
    return null;
}

fn stateLooksRunning(value: []const u8) bool {
    return containsIgnoreCase(value, "running") or containsIgnoreCase(value, "active") or containsIgnoreCase(value, "up");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn boolText(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn coverageStatus(coverage: VpsCoverage) []const u8 {
    return if (coverage.completeCore()) "complete" else "partial";
}

fn writeBoolTextField(writer: anytype, label: []const u8, value: bool) !void {
    try writer.print("\t{s}={s}", .{ label, boolText(value) });
}

fn writeVpsRowText(row: db_store.HostingerVpsRow, coverage: VpsCoverage, writer: anytype) !void {
    try writer.print("{s}", .{row.id});
    try writeTextField(writer, "name", row.name);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "ipv4", row.ipv4);
    try writeTextField(writer, "plan", row.plan);
    try writeTextField(writer, "coverage", coverageStatus(coverage));
    try writeVpsCoverageText(coverage, writer);
    try writeVpsCoverageIssuesText(coverage, writer);
    try writeTextField(writer, "updated", row.updated_at);
    try writer.writeByte('\n');
}

fn writeKindCountText(row: db_store.HostingerKindCount, writer: anytype) !void {
    try writer.print("{s}\tcount={d}", .{ row.kind, row.count });
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeMetricSummaryText(row: db_store.HostingerMetricSummary, writer: anytype) !void {
    try writer.print("{s}/{s}\tcount={d}", .{ row.vm_id, row.metric, row.count });
    try writeTextField(writer, "latest", row.latest_captured);
    try writer.writeByte('\n');
}

fn writeVpsFamilySummaryText(row: db_store.HostingerVpsFamilySummary, writer: anytype) !void {
    try writer.print("{s}/{s}/{s}\tcount={d}", .{ row.vm_id, row.source, row.kind, row.count });
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeAccountOverviewSummaryText(summary: AccountOverviewSummary, writer: anytype) !void {
    try writer.print("summary vps={d} running_vps={d} stopped_or_other_vps={d} complete_vps_core_coverage={d} partial_vps_core_coverage={d} resources={d} inventory_items={d} resource_kinds={d} inventory_kinds={d} inventory_facets={d} recent_snapshots={d}\n", .{
        summary.vps,
        summary.running_vps,
        summary.stopped_or_other_vps,
        summary.complete_vps_core_coverage,
        summary.partial_vps_core_coverage,
        summary.resources,
        summary.inventory_items,
        summary.resource_kinds,
        summary.inventory_kinds,
        summary.inventory_facets,
        summary.recent_snapshots,
    });
    try writer.print("api_routes total={d} read={d} dry_run={d} write={d} not_applicable={d} deprecated={d} blocked_permission={d} families={d} observed_read_families={d} missing_read_families={d} not_applicable_families={d} blocked_or_missing_families={d}\n", .{
        summary.api_routes,
        summary.api_read_routes,
        summary.api_dry_run_routes,
        summary.api_write_routes,
        summary.api_not_applicable_routes,
        summary.api_deprecated_routes,
        summary.api_blocked_permission_routes,
        summary.api_families,
        summary.observed_read_families,
        summary.missing_read_families,
        summary.not_applicable_families,
        summary.blocked_or_missing_families,
    });
    try writer.print("families billing={d} dns={d} domains={d} hosting={d} vps={d} docker={d} security={d} reach={d} ecommerce={d} horizons={d} other={d}\n", .{
        summary.families.billing,
        summary.families.dns,
        summary.families.domains,
        summary.families.hosting,
        summary.families.vps,
        summary.families.docker,
        summary.families.security,
        summary.families.reach,
        summary.families.ecommerce,
        summary.families.horizons,
        summary.families.other,
    });
}

fn writeVpsOverviewSummaryJson(summary: VpsOverviewSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "vps", summary.vps, true);
    try app_render.writeJsonIntField(writer, "running", summary.running, true);
    try app_render.writeJsonIntField(writer, "stopped_or_other", summary.stopped_or_other, true);
    try app_render.writeJsonIntField(writer, "complete_core_coverage", summary.complete_core_coverage, true);
    try app_render.writeJsonIntField(writer, "partial_core_coverage", summary.partial_core_coverage, true);
    try app_render.writeJsonIntField(writer, "with_details", summary.with_details, true);
    try app_render.writeJsonIntField(writer, "with_metrics", summary.with_metrics, true);
    try app_render.writeJsonIntField(writer, "with_actions", summary.with_actions, true);
    try app_render.writeJsonIntField(writer, "with_backups", summary.with_backups, true);
    try app_render.writeJsonIntField(writer, "with_snapshot", summary.with_snapshot, true);
    try app_render.writeJsonIntField(writer, "with_public_keys", summary.with_public_keys, true);
    try app_render.writeJsonIntField(writer, "with_security", summary.with_security, true);
    try app_render.writeJsonIntField(writer, "with_docker", summary.with_docker, true);
    try app_render.writeJsonIntField(writer, "missing_details", summary.missing_details, true);
    try app_render.writeJsonIntField(writer, "missing_metrics", summary.missing_metrics, true);
    try app_render.writeJsonIntField(writer, "missing_actions", summary.missing_actions, true);
    try app_render.writeJsonIntField(writer, "missing_backups", summary.missing_backups, true);
    try app_render.writeJsonIntField(writer, "missing_snapshot", summary.missing_snapshot, true);
    try app_render.writeJsonIntField(writer, "resource_kinds", summary.resource_kinds, true);
    try app_render.writeJsonIntField(writer, "inventory_kinds", summary.inventory_kinds, true);
    try app_render.writeJsonIntField(writer, "metric_summaries", summary.metric_summaries, true);
    try app_render.writeJsonIntField(writer, "family_summaries", summary.family_summaries, true);
    try app_render.writeJsonIntField(writer, "recent_snapshots", summary.recent_snapshots, true);
    try app_render.writeJsonIntField(writer, "api_routes", summary.api_routes, true);
    try app_render.writeJsonIntField(writer, "api_read_routes", summary.api_read_routes, true);
    try app_render.writeJsonIntField(writer, "api_dry_run_routes", summary.api_dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "api_write_routes", summary.api_write_routes, true);
    try app_render.writeJsonIntField(writer, "api_not_applicable_routes", summary.api_not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "api_deprecated_routes", summary.api_deprecated_routes, true);
    try app_render.writeJsonIntField(writer, "api_blocked_permission_routes", summary.api_blocked_permission_routes, true);
    try app_render.writeJsonIntField(writer, "api_families", summary.api_families, true);
    try app_render.writeJsonIntField(writer, "observed_read_families", summary.observed_read_families, true);
    try app_render.writeJsonIntField(writer, "missing_read_families", summary.missing_read_families, true);
    try app_render.writeJsonIntField(writer, "dry_run_only_families", summary.dry_run_only_families, true);
    try app_render.writeJsonIntField(writer, "not_applicable_families", summary.not_applicable_families, true);
    try app_render.writeJsonIntField(writer, "blocked_or_missing_families", summary.blocked_or_missing_families, false);
    try writer.writeByte('}');
}

fn writeAccountOverviewSummaryJson(summary: AccountOverviewSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "vps", summary.vps, true);
    try app_render.writeJsonIntField(writer, "running_vps", summary.running_vps, true);
    try app_render.writeJsonIntField(writer, "stopped_or_other_vps", summary.stopped_or_other_vps, true);
    try app_render.writeJsonIntField(writer, "complete_vps_core_coverage", summary.complete_vps_core_coverage, true);
    try app_render.writeJsonIntField(writer, "partial_vps_core_coverage", summary.partial_vps_core_coverage, true);
    try app_render.writeJsonIntField(writer, "resources", summary.resources, true);
    try app_render.writeJsonIntField(writer, "inventory_items", summary.inventory_items, true);
    try app_render.writeJsonIntField(writer, "resource_kinds", summary.resource_kinds, true);
    try app_render.writeJsonIntField(writer, "inventory_kinds", summary.inventory_kinds, true);
    try app_render.writeJsonIntField(writer, "inventory_facets", summary.inventory_facets, true);
    try app_render.writeJsonIntField(writer, "recent_snapshots", summary.recent_snapshots, true);
    try app_render.writeJsonIntField(writer, "api_routes", summary.api_routes, true);
    try app_render.writeJsonIntField(writer, "api_read_routes", summary.api_read_routes, true);
    try app_render.writeJsonIntField(writer, "api_dry_run_routes", summary.api_dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "api_write_routes", summary.api_write_routes, true);
    try app_render.writeJsonIntField(writer, "api_not_applicable_routes", summary.api_not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "api_deprecated_routes", summary.api_deprecated_routes, true);
    try app_render.writeJsonIntField(writer, "api_blocked_permission_routes", summary.api_blocked_permission_routes, true);
    try app_render.writeJsonIntField(writer, "api_families", summary.api_families, true);
    try app_render.writeJsonIntField(writer, "observed_read_families", summary.observed_read_families, true);
    try app_render.writeJsonIntField(writer, "missing_read_families", summary.missing_read_families, true);
    try app_render.writeJsonIntField(writer, "not_applicable_families", summary.not_applicable_families, true);
    try app_render.writeJsonIntField(writer, "blocked_or_missing_families", summary.blocked_or_missing_families, true);
    try writer.writeAll("\"families\":");
    try writeFamilySummaryJson(summary.families, writer);
    try writer.writeByte('}');
}

fn writeFamilySummaryJson(summary: HostingerFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "billing", summary.billing, true);
    try app_render.writeJsonIntField(writer, "dns", summary.dns, true);
    try app_render.writeJsonIntField(writer, "domains", summary.domains, true);
    try app_render.writeJsonIntField(writer, "hosting", summary.hosting, true);
    try app_render.writeJsonIntField(writer, "vps", summary.vps, true);
    try app_render.writeJsonIntField(writer, "docker", summary.docker, true);
    try app_render.writeJsonIntField(writer, "security", summary.security, true);
    try app_render.writeJsonIntField(writer, "reach", summary.reach, true);
    try app_render.writeJsonIntField(writer, "ecommerce", summary.ecommerce, true);
    try app_render.writeJsonIntField(writer, "horizons", summary.horizons, true);
    try app_render.writeJsonIntField(writer, "other", summary.other, false);
    try writer.writeByte('}');
}

fn writeVpsCoverageText(coverage: VpsCoverage, writer: anytype) !void {
    try writeBoolTextField(writer, "details", coverage.details);
    try writeBoolTextField(writer, "metrics", coverage.metrics);
    try writeBoolTextField(writer, "actions", coverage.actions);
    try writeBoolTextField(writer, "backups", coverage.backups);
    try writeBoolTextField(writer, "snapshot", coverage.snapshot);
    try writeBoolTextField(writer, "public_keys", coverage.public_keys);
    try writeBoolTextField(writer, "security", coverage.security);
    try writeBoolTextField(writer, "docker", coverage.docker);
}

fn writeVpsCoverageJson(coverage: VpsCoverage, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonBoolField(writer, "details", coverage.details, true);
    try app_render.writeJsonBoolField(writer, "metrics", coverage.metrics, true);
    try app_render.writeJsonBoolField(writer, "actions", coverage.actions, true);
    try app_render.writeJsonBoolField(writer, "backups", coverage.backups, true);
    try app_render.writeJsonBoolField(writer, "snapshot", coverage.snapshot, true);
    try app_render.writeJsonBoolField(writer, "public_keys", coverage.public_keys, true);
    try app_render.writeJsonBoolField(writer, "security", coverage.security, true);
    try app_render.writeJsonBoolField(writer, "docker", coverage.docker, false);
    try writer.writeByte('}');
}

fn writeVpsCoverageIssuesText(coverage: VpsCoverage, writer: anytype) !void {
    if (vpsCoverageIssueCount(coverage) == 0) return;
    try writer.writeAll("\tcoverage_issues=");
    var first = true;
    try writeVpsCoverageIssueText(writer, &first, !coverage.details, "missing_details");
    try writeVpsCoverageIssueText(writer, &first, !coverage.metrics, "missing_metrics");
    try writeVpsCoverageIssueText(writer, &first, !coverage.actions, "missing_actions");
    try writeVpsCoverageIssueText(writer, &first, !coverage.backups, "missing_backups");
    try writeVpsCoverageIssueText(writer, &first, !coverage.snapshot, "missing_snapshot");
}

fn writeVpsCoverageIssuesJson(coverage: VpsCoverage, writer: anytype) !void {
    try writer.writeByte('[');
    var first = true;
    try writeVpsCoverageIssueJson(writer, &first, !coverage.details, "missing_details");
    try writeVpsCoverageIssueJson(writer, &first, !coverage.metrics, "missing_metrics");
    try writeVpsCoverageIssueJson(writer, &first, !coverage.actions, "missing_actions");
    try writeVpsCoverageIssueJson(writer, &first, !coverage.backups, "missing_backups");
    try writeVpsCoverageIssueJson(writer, &first, !coverage.snapshot, "missing_snapshot");
    try writer.writeByte(']');
}

fn writeVpsCoverageIssueText(writer: anytype, first: *bool, present: bool, label: []const u8) !void {
    if (!present) return;
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeAll(label);
}

fn writeVpsCoverageIssueJson(writer: anytype, first: *bool, present: bool, label: []const u8) !void {
    if (!present) return;
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try app_render.writeJsonString(writer, label);
}

fn vpsCoverageIssueCount(coverage: VpsCoverage) usize {
    var count: usize = 0;
    if (!coverage.details) count += 1;
    if (!coverage.metrics) count += 1;
    if (!coverage.actions) count += 1;
    if (!coverage.backups) count += 1;
    if (!coverage.snapshot) count += 1;
    return count;
}

fn writeVpsRowJson(row: db_store.HostingerVpsRow, coverage: VpsCoverage, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "id", row.id, true);
    try writeJsonStringField(writer, "name", row.name, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "ipv4", row.ipv4, true);
    try writeJsonStringField(writer, "plan", row.plan, true);
    try writeJsonStringField(writer, "coverage_status", coverageStatus(coverage), true);
    try writer.writeAll("\"coverage\":");
    try writeVpsCoverageJson(coverage, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"coverage_issues\":");
    try writeVpsCoverageIssuesJson(coverage, writer);
    try writer.writeByte(',');
    try writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeKindCountJson(row: db_store.HostingerKindCount, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeMetricSummaryJson(row: db_store.HostingerMetricSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try writeJsonStringField(writer, "metric", row.metric, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_captured", row.latest_captured, false);
    try writer.writeByte('}');
}

fn writeVpsFamilySummaryJson(row: db_store.HostingerVpsFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try writeJsonStringField(writer, "source", row.source, true);
    try writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeInventoryFacetText(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.print("{s}", .{row.kind});
    try writeTextField(writer, "family", hostingerFamilyForKind(row.kind).label());
    try writer.print("\tcount={d}", .{row.count});
    if (row.domains != 0) try writer.print("\tdomains={d}", .{row.domains});
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "category", row.category);
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeInventoryFacetJson(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "kind", row.kind, true);
    try writeJsonStringField(writer, "family", hostingerFamilyForKind(row.kind).label(), true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "category", row.category, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonIntField(writer, "domains", row.domains, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeSnapshotText(row: db_store.SnapshotSummary, writer: anytype) !void {
    try writer.print("{d}\t{s}/{s}", .{ row.id, row.source, row.kind });
    try writeTextField(writer, "target", row.target);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "summary", row.summary);
    try writeTextField(writer, "captured", row.captured_at);
    try writer.writeByte('\n');
}
