const std = @import("std");
const collector_hostinger = @import("collector_hostinger");
const app_provider_list = @import("app_provider_list");
const app_render = @import("app_render");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_hostinger = @import("provider_hostinger");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const positiveLimit = app_render.positiveLimit;
const writeJsonStringField = app_render.writeJsonStringField;
const writeTextField = app_render.writeTextField;

pub const Output = core_output.Output;
pub const VmEndpoint = provider_hostinger.VmEndpoint;
pub const VpsMutationEndpoint = provider_hostinger.VpsMutationEndpoint;
pub const VpsMutationArgs = provider_hostinger.VpsMutationArgs;
pub const VpsInventoryEndpoint = provider_hostinger.VpsInventoryEndpoint;
pub const VpsInventoryDetailEndpoint = provider_hostinger.VpsInventoryDetailEndpoint;
pub const VpsResourceMutationEndpoint = provider_hostinger.VpsResourceMutationEndpoint;
pub const VpsResourceMutationArgs = provider_hostinger.VpsResourceMutationArgs;
pub const FirewallMutationEndpoint = provider_hostinger.FirewallMutationEndpoint;
pub const FirewallMutationArgs = provider_hostinger.FirewallMutationArgs;
pub const DockerEndpoint = provider_hostinger.DockerEndpoint;
pub const DockerMutationEndpoint = provider_hostinger.DockerMutationEndpoint;
pub const DockerMutationArgs = provider_hostinger.DockerMutationArgs;
pub const BillingEndpoint = provider_hostinger.BillingEndpoint;
pub const BillingMutationEndpoint = provider_hostinger.BillingMutationEndpoint;
pub const BillingMutationArgs = provider_hostinger.BillingMutationArgs;
pub const DnsEndpoint = provider_hostinger.DnsEndpoint;
pub const DnsMutationEndpoint = provider_hostinger.DnsMutationEndpoint;
pub const DnsMutationArgs = provider_hostinger.DnsMutationArgs;
pub const DomainEndpoint = provider_hostinger.DomainEndpoint;
pub const DomainMutationEndpoint = provider_hostinger.DomainMutationEndpoint;
pub const DomainMutationArgs = provider_hostinger.DomainMutationArgs;
pub const HostingEndpoint = provider_hostinger.HostingEndpoint;
pub const HostingArgs = provider_hostinger.HostingArgs;
pub const HostingMutationEndpoint = provider_hostinger.HostingMutationEndpoint;
pub const HostingMutationArgs = provider_hostinger.HostingMutationArgs;
pub const EcommerceEndpoint = provider_hostinger.EcommerceEndpoint;
pub const EcommerceMutationEndpoint = provider_hostinger.EcommerceMutationEndpoint;
pub const HorizonsEndpoint = provider_hostinger.HorizonsEndpoint;
pub const HorizonsMutationEndpoint = provider_hostinger.HorizonsMutationEndpoint;
pub const ReachEndpoint = provider_hostinger.ReachEndpoint;
pub const ReachArgs = provider_hostinger.ReachArgs;
pub const ReachMutationEndpoint = provider_hostinger.ReachMutationEndpoint;
pub const ReachMutationArgs = provider_hostinger.ReachMutationArgs;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    token: ?[]const u8,
    domains: []const []const u8,
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
    api_not_applicable_routes: usize = 0,
    api_families: usize = 0,
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    not_applicable_families: usize = 0,
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
    api_families: usize = 0,
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    dry_run_only_families: usize = 0,
};

pub const VpsApiFamilySummary = struct {
    label: []const u8,
    official_routes: usize,
    read_routes: usize,
    dry_run_routes: usize,
    observed_items: i64 = 0,
    observed_kinds: usize = 0,

    fn status(self: VpsApiFamilySummary) []const u8 {
        if (self.read_routes == 0 and self.dry_run_routes != 0) return "dry_run_only";
        if (self.observed_items != 0) return "observed";
        return "missing_read";
    }
};

pub const AccountApiFamilySummary = struct {
    label: []const u8,
    official_routes: usize,
    read_routes: usize,
    dry_run_routes: usize,
    not_applicable_routes: usize,
    observed_items: i64 = 0,
    observed_kinds: usize = 0,

    fn status(self: AccountApiFamilySummary) []const u8 {
        if (self.not_applicable_routes != 0 and self.read_routes == 0 and self.dry_run_routes == 0) return "not_applicable";
        if (self.observed_items != 0) return "observed";
        return "missing_read";
    }
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
        return .{
            .vps_overview = vps_overview,
            .inventory_facets = inventory_facets,
            .family_facets = family_facets,
            .recent_snapshots = recent_snapshots,
            .summary_snapshots = summary_snapshots,
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
    }

    pub fn summary(self: AccountOverview) AccountOverviewSummary {
        const vps_summary = self.vps_overview.summary();
        const route_totals = provider_hostinger.accountApiRouteTotals();
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
            .api_not_applicable_routes = route_totals.not_applicable_routes,
            .api_families = provider_hostinger.account_api_family_count,
        };
        for (self.family_facets.items) |facet| {
            out.families.add(hostingerFamilyForKind(facet.kind), facet.count);
        }
        for (self.apiFamilySummaries()) |family| {
            if (family.not_applicable_routes != 0 and family.read_routes == 0) {
                out.not_applicable_families += 1;
            } else if (family.read_routes != 0 and family.observed_items != 0) {
                out.observed_read_families += 1;
            } else if (family.read_routes != 0) {
                out.missing_read_families += 1;
            }
        }
        return out;
    }

    fn apiFamilySummaries(self: AccountOverview) [provider_hostinger.account_api_family_count]AccountApiFamilySummary {
        var out: [provider_hostinger.account_api_family_count]AccountApiFamilySummary = undefined;
        for (provider_hostinger.account_api_families, 0..) |family, index| {
            out[index] = .{
                .label = family.label,
                .official_routes = family.official_routes,
                .read_routes = family.read_routes,
                .dry_run_routes = family.dry_run_routes,
                .not_applicable_routes = family.not_applicable_routes,
            };
        }
        for (self.family_facets.items) |facet| {
            addAccountApiFamilyObserved(&out, facet.kind, facet.count);
        }
        for (self.summary_snapshots.items) |snapshot| {
            addAccountApiFamilyObserved(&out, snapshot.kind, 1);
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
        for (self.apiFamilySummaries()) |row| try writeAccountApiFamilySummaryText(row, writer);

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
        for (self.apiFamilySummaries(), 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeAccountApiFamilySummaryJson(row, writer);
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
    }

    pub fn summary(self: VpsOverview) VpsOverviewSummary {
        const route_totals = provider_hostinger.vpsApiRouteTotals();
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
            .api_families = provider_hostinger.vps_api_family_count,
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
        for (self.apiFamilySummaries()) |family| {
            if (family.read_routes == 0 and family.dry_run_routes != 0) {
                out.dry_run_only_families += 1;
            } else if (family.read_routes != 0 and family.observed_items != 0) {
                out.observed_read_families += 1;
            } else if (family.read_routes != 0) {
                out.missing_read_families += 1;
            }
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

    fn apiFamilySummaries(self: VpsOverview) [provider_hostinger.vps_api_family_count]VpsApiFamilySummary {
        var out: [provider_hostinger.vps_api_family_count]VpsApiFamilySummary = undefined;
        for (provider_hostinger.vps_api_families, 0..) |family, index| {
            out[index] = .{
                .label = family.label,
                .official_routes = family.official_routes,
                .read_routes = family.read_routes,
                .dry_run_routes = family.dry_run_routes,
            };
        }

        if (self.summary_vps.items.len != 0) {
            addVpsApiFamilyObserved(&out, "vps", @intCast(self.summary_vps.items.len));
        }
        for (self.summary_resource_kinds.items) |row| {
            addVpsApiFamilyObserved(&out, row.kind, row.count);
        }
        for (self.summary_inventory_kinds.items) |row| {
            addVpsApiFamilyObserved(&out, row.kind, row.count);
        }
        for (self.summary_metric_summaries.items) |row| {
            addVpsApiFamilyObserved(&out, "metrics", row.count);
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
        try writer.print("api_routes total={d} read={d} dry_run={d} families={d} observed_read_families={d} missing_read_families={d} dry_run_only_families={d}\n", .{
            counts.api_routes,
            counts.api_read_routes,
            counts.api_dry_run_routes,
            counts.api_families,
            counts.observed_read_families,
            counts.missing_read_families,
            counts.dry_run_only_families,
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
        for (self.apiFamilySummaries()) |row| try writeVpsApiFamilySummaryText(row, writer);

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
        for (self.apiFamilySummaries(), 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsApiFamilySummaryJson(row, writer);
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

pub fn collectVps(ctx: Context) !Output {
    return try collector_hostinger.collectVps(ctx.io, ctx.gpa, ctx.token, ctx.db, true);
}

pub fn collectVpsDetails(ctx: Context, vm_id: []const u8) !Output {
    return try collector_hostinger.collectVpsDetails(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, true);
}

pub fn collectVmEndpoint(ctx: Context, vm_id: []const u8, endpoint: VmEndpoint) !Output {
    return try collector_hostinger.collectVmEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, endpoint, true);
}

pub fn collectActionDetails(ctx: Context, vm_id: []const u8, action_id: []const u8) !Output {
    return try collector_hostinger.collectActionDetails(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, action_id, true);
}

pub fn planVpsMutation(ctx: Context, endpoint: VpsMutationEndpoint, args: VpsMutationArgs) !Output {
    return .{ .text = try provider_hostinger.vpsMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planFirewallMutation(ctx: Context, endpoint: FirewallMutationEndpoint, args: FirewallMutationArgs) !Output {
    return .{ .text = try provider_hostinger.firewallMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planVpsResourceMutation(ctx: Context, endpoint: VpsResourceMutationEndpoint, args: VpsResourceMutationArgs) !Output {
    return .{ .text = try provider_hostinger.vpsResourceMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDockerMutation(ctx: Context, endpoint: DockerMutationEndpoint, args: DockerMutationArgs) !Output {
    return .{ .text = try provider_hostinger.dockerMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDnsMutation(ctx: Context, endpoint: DnsMutationEndpoint, args: DnsMutationArgs) !Output {
    return .{ .text = try provider_hostinger.dnsMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planBillingMutation(ctx: Context, endpoint: BillingMutationEndpoint, args: BillingMutationArgs) !Output {
    return .{ .text = try provider_hostinger.billingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDomainMutation(ctx: Context, endpoint: DomainMutationEndpoint, args: DomainMutationArgs) !Output {
    return .{ .text = try provider_hostinger.domainMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planHostingMutation(ctx: Context, endpoint: HostingMutationEndpoint, args: HostingMutationArgs) !Output {
    return .{ .text = try provider_hostinger.hostingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planEcommerceMutation(ctx: Context, endpoint: EcommerceMutationEndpoint) !Output {
    return .{ .text = try provider_hostinger.ecommerceMutationPlanJson(ctx.gpa, endpoint) };
}

pub fn planHorizonsMutation(ctx: Context, endpoint: HorizonsMutationEndpoint) !Output {
    return .{ .text = try provider_hostinger.horizonsMutationPlanJson(ctx.gpa, endpoint) };
}

pub fn planReachMutation(ctx: Context, endpoint: ReachMutationEndpoint, args: ReachMutationArgs) !Output {
    return .{ .text = try provider_hostinger.reachMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn collectDockerEndpoint(ctx: Context, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8) !Output {
    return try collector_hostinger.collectDockerEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, endpoint, project_name, true);
}

pub fn collectBillingEndpoint(ctx: Context, endpoint: BillingEndpoint) !Output {
    return try collector_hostinger.collectBillingEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectDnsEndpoint(ctx: Context, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8) !Output {
    return try collector_hostinger.collectDnsEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, domain, snapshot_id, true);
}

pub fn collectDomainEndpoint(ctx: Context, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8) !Output {
    return try collector_hostinger.collectDomainEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, path_arg, tld, true);
}

pub fn collectHostingEndpoint(ctx: Context, endpoint: HostingEndpoint, args: HostingArgs) !Output {
    return try collector_hostinger.collectHostingEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, args, true);
}

pub fn collectEcommerceEndpoint(ctx: Context, endpoint: EcommerceEndpoint) !Output {
    return try collector_hostinger.collectEcommerceEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectHorizonsEndpoint(ctx: Context, endpoint: HorizonsEndpoint, website_id: []const u8) !Output {
    return try collector_hostinger.collectHorizonsEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, website_id, true);
}

pub fn collectReachEndpoint(ctx: Context, endpoint: ReachEndpoint, args: ReachArgs) !Output {
    return try collector_hostinger.collectReachEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, args, true);
}

pub fn collectVpsInventoryEndpoint(ctx: Context, endpoint: VpsInventoryEndpoint) !Output {
    return try collector_hostinger.collectVpsInventoryEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectVpsInventoryDetail(ctx: Context, endpoint: VpsInventoryDetailEndpoint, id: []const u8) !Output {
    return try collector_hostinger.collectVpsInventoryDetail(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, id, true);
}

pub fn listResources(ctx: Context) !Output {
    return try app_provider_list.resources(providerListContext(ctx), .hostinger);
}

pub fn listInventoryItems(ctx: Context) !Output {
    return try app_provider_list.inventoryItems(providerListContext(ctx), .hostinger);
}

pub fn writeVpsOverviewText(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeVpsOverviewJson(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeJson(writer);
}

pub fn writeAccountOverviewText(ctx: Context, options: AccountOverviewOptions, writer: anytype) !void {
    var overview = try AccountOverview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeAccountOverviewJson(ctx: Context, options: AccountOverviewOptions, writer: anytype) !void {
    var overview = try AccountOverview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeJson(writer);
}

pub fn defaultDomain(ctx: Context) []const u8 {
    return ctx.domains[0];
}

fn providerListContext(ctx: Context) app_provider_list.Context {
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

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

fn addAccountApiFamilyObserved(summaries: *[provider_hostinger.account_api_family_count]AccountApiFamilySummary, kind: []const u8, count: i64) void {
    const index = accountApiFamilyIndexForKind(kind) orelse return;
    summaries[index].observed_items += count;
    summaries[index].observed_kinds += 1;
}

fn accountApiFamilyIndexForKind(kind: []const u8) ?usize {
    if (containsIgnoreCase(kind, "domain-access") or containsIgnoreCase(kind, "verifications") or containsIgnoreCase(kind, "v2_getdomainverificationsdirect")) return accountApiFamilyIndexByLabel("domain_access_verifier");
    if (containsIgnoreCase(kind, "billing")) return accountApiFamilyIndexByLabel("billing");
    if (containsIgnoreCase(kind, "dns")) return accountApiFamilyIndexByLabel("dns");
    if (containsIgnoreCase(kind, "ecommerce") or containsIgnoreCase(kind, "store")) return accountApiFamilyIndexByLabel("ecommerce");
    if (containsIgnoreCase(kind, "horizons")) return accountApiFamilyIndexByLabel("horizons");
    if (containsIgnoreCase(kind, "reach") or containsIgnoreCase(kind, "contact") or containsIgnoreCase(kind, "segment") or containsIgnoreCase(kind, "profile")) return accountApiFamilyIndexByLabel("reach");
    if (containsIgnoreCase(kind, "hosting") or
        containsIgnoreCase(kind, "wordpress") or
        containsIgnoreCase(kind, "nodejs") or
        containsIgnoreCase(kind, "database") or
        containsIgnoreCase(kind, "phpmyadmin") or
        containsIgnoreCase(kind, "parked") or
        containsIgnoreCase(kind, "subdomain"))
    {
        return accountApiFamilyIndexByLabel("hosting");
    }
    if (containsIgnoreCase(kind, "domain") or containsIgnoreCase(kind, "whois") or containsIgnoreCase(kind, "forwarding") or containsIgnoreCase(kind, "availability")) return accountApiFamilyIndexByLabel("domains");
    return null;
}

fn accountApiFamilyIndexByLabel(label: []const u8) ?usize {
    for (provider_hostinger.account_api_families, 0..) |family, index| {
        if (std.mem.eql(u8, family.label, label)) return index;
    }
    return null;
}

fn addVpsApiFamilyObserved(summaries: *[provider_hostinger.vps_api_family_count]VpsApiFamilySummary, kind: []const u8, count: i64) void {
    const index = vpsApiFamilyIndexForKind(kind) orelse return;
    summaries[index].observed_items += count;
    summaries[index].observed_kinds += 1;
}

fn vpsApiFamilyIndexForKind(kind: []const u8) ?usize {
    if (std.ascii.eqlIgnoreCase(kind, "data-centers") or containsIgnoreCase(kind, "data-center") or containsIgnoreCase(kind, "datacenter")) return vpsApiFamilyIndexByLabel("data_centers");
    if (std.ascii.eqlIgnoreCase(kind, "firewalls") or std.ascii.eqlIgnoreCase(kind, "firewall-detail") or containsIgnoreCase(kind, "firewall")) return vpsApiFamilyIndexByLabel("firewall");
    if (kindLooksLikeDocker(kind) or containsIgnoreCase(kind, "project") or containsIgnoreCase(kind, "container")) return vpsApiFamilyIndexByLabel("docker");
    if (containsIgnoreCase(kind, "post-install") or containsIgnoreCase(kind, "post_install")) return vpsApiFamilyIndexByLabel("post_install_scripts");
    if (kindLooksLikeSnapshot(kind)) return vpsApiFamilyIndexByLabel("snapshots");
    if (std.ascii.eqlIgnoreCase(kind, "public-keys-global")) return vpsApiFamilyIndexByLabel("public_keys");
    if (kindLooksLikeSecurity(kind) or containsIgnoreCase(kind, "scanmetrics")) return vpsApiFamilyIndexByLabel("malware_scanner");
    if (kindLooksLikeActions(kind)) return vpsApiFamilyIndexByLabel("actions");
    if (kindLooksLikeBackups(kind)) return vpsApiFamilyIndexByLabel("backups");
    if (std.ascii.eqlIgnoreCase(kind, "templates") or std.ascii.eqlIgnoreCase(kind, "template-detail") or containsIgnoreCase(kind, "template")) return vpsApiFamilyIndexByLabel("os_templates");
    if (containsIgnoreCase(kind, "ptr")) return vpsApiFamilyIndexByLabel("ptr_records");
    if (containsIgnoreCase(kind, "recovery")) return vpsApiFamilyIndexByLabel("recovery");
    if (std.ascii.eqlIgnoreCase(kind, "vps") or kindLooksLikeDetails(kind) or kindLooksLikeMetrics(kind) or std.ascii.eqlIgnoreCase(kind, "public-keys")) return vpsApiFamilyIndexByLabel("virtual_machine");
    return null;
}

fn vpsApiFamilyIndexByLabel(label: []const u8) ?usize {
    for (provider_hostinger.vps_api_families, 0..) |family, index| {
        if (std.mem.eql(u8, family.label, label)) return index;
    }
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

fn writeAccountApiFamilySummaryText(row: AccountApiFamilySummary, writer: anytype) !void {
    try writer.print("{s}\tofficial_routes={d}\tread_routes={d}\tdry_run_routes={d}\tnot_applicable_routes={d}\tobserved_items={d}\tobserved_kinds={d}\tstatus={s}\n", .{
        row.label,
        row.official_routes,
        row.read_routes,
        row.dry_run_routes,
        row.not_applicable_routes,
        row.observed_items,
        row.observed_kinds,
        row.status(),
    });
}

fn writeVpsApiFamilySummaryText(row: VpsApiFamilySummary, writer: anytype) !void {
    try writer.print("{s}\tofficial_routes={d}\tread_routes={d}\tdry_run_routes={d}\tobserved_items={d}\tobserved_kinds={d}\tstatus={s}\n", .{
        row.label,
        row.official_routes,
        row.read_routes,
        row.dry_run_routes,
        row.observed_items,
        row.observed_kinds,
        row.status(),
    });
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
    try writer.print("api_routes total={d} read={d} dry_run={d} not_applicable={d} families={d} observed_read_families={d} missing_read_families={d} not_applicable_families={d}\n", .{
        summary.api_routes,
        summary.api_read_routes,
        summary.api_dry_run_routes,
        summary.api_not_applicable_routes,
        summary.api_families,
        summary.observed_read_families,
        summary.missing_read_families,
        summary.not_applicable_families,
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
    try app_render.writeJsonIntField(writer, "api_families", summary.api_families, true);
    try app_render.writeJsonIntField(writer, "observed_read_families", summary.observed_read_families, true);
    try app_render.writeJsonIntField(writer, "missing_read_families", summary.missing_read_families, true);
    try app_render.writeJsonIntField(writer, "dry_run_only_families", summary.dry_run_only_families, false);
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
    try app_render.writeJsonIntField(writer, "api_not_applicable_routes", summary.api_not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "api_families", summary.api_families, true);
    try app_render.writeJsonIntField(writer, "observed_read_families", summary.observed_read_families, true);
    try app_render.writeJsonIntField(writer, "missing_read_families", summary.missing_read_families, true);
    try app_render.writeJsonIntField(writer, "not_applicable_families", summary.not_applicable_families, true);
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

fn writeAccountApiFamilySummaryJson(row: AccountApiFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "label", row.label, true);
    try app_render.writeJsonIntField(writer, "official_routes", row.official_routes, true);
    try app_render.writeJsonIntField(writer, "read_routes", row.read_routes, true);
    try app_render.writeJsonIntField(writer, "dry_run_routes", row.dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "not_applicable_routes", row.not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "observed_items", row.observed_items, true);
    try app_render.writeJsonIntField(writer, "observed_kinds", row.observed_kinds, true);
    try writeJsonStringField(writer, "status", row.status(), false);
    try writer.writeByte('}');
}

fn writeVpsApiFamilySummaryJson(row: VpsApiFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "label", row.label, true);
    try app_render.writeJsonIntField(writer, "official_routes", row.official_routes, true);
    try app_render.writeJsonIntField(writer, "read_routes", row.read_routes, true);
    try app_render.writeJsonIntField(writer, "dry_run_routes", row.dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "observed_items", row.observed_items, true);
    try app_render.writeJsonIntField(writer, "observed_kinds", row.observed_kinds, true);
    try writeJsonStringField(writer, "status", row.status(), false);
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

test "hostinger app default domain uses first configured domain" {
    const domains = [_][]const u8{ "plosca.ru", "sparkdate.love" };
    var db: Db = undefined;
    const ctx = Context{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    try std.testing.expectEqualStrings("plosca.ru", defaultDomain(ctx));
}

test "hostinger app lists normalized resources" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-resources.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerResource("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", null, "plosca.ru", "enabled", "plosca.ru", "{\"domain\":\"plosca.ru\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listResources(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "enabled plosca.ru plosca.ru") != null);
}

test "hostinger app lists typed inventory items" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listInventoryItems(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "enabled enabled main plosca.ru u123 plosca.ru 12345") != null);
}

test "hostinger app renders account overview across provider families" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-account-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerResource("billing_getSubscriptionListV1/sub-1", "billing_getSubscriptionListV1", "sub-1", "billing_getSubscriptionListV1", "KVM 2", "active", null, "{\"id\":\"sub-1\"}");
    try db.upsertHostingerInventoryItem("billing_getSubscriptionListV1/sub-1", "billing_getSubscriptionListV1", "sub-1", "KVM 2", "active", "EUR", null, null, null, "auto_renewed", null, null, null, "{\"id\":\"sub-1\"}");
    try db.upsertHostingerInventoryItem("domains_getDomainListV1/domain-1", "domains_getDomainListV1", "domain-1", "plosca.ru", "active", "domain", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"domain-1\"}");
    try db.upsertHostingerInventoryItem("DNS_getDNSRecordsV1/plosca.ru/A", "DNS_getDNSRecordsV1", "A", "plosca.ru A", "active", "A", "plosca.ru", null, null, null, null, null, null, "{\"type\":\"A\"}");
    try db.upsertHostingerInventoryItem("DNS_getDNSRecordsV1/plosca.ru/TXT", "DNS_getDNSRecordsV1", "TXT", "plosca.ru TXT", "active", "A", "plosca.ru", null, null, null, null, null, null, "{\"type\":\"TXT\"}");
    try db.upsertHostingerInventoryItem("hosting_listWebsitesV1/plosca.ru", "hosting_listWebsitesV1", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "order-1", null, null, null, null, "{\"domain\":\"plosca.ru\"}");
    try db.upsertHostingerInventoryItem("VPS_getVirtualMachineDetailsV1|12345|detail", "VPS_getVirtualMachineDetailsV1", "12345", "srv12345.hstgr.cloud", "running", "vps", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"12345\"}");
    try db.upsertHostingerInventoryItem("VPS_getProjectListV1|12345|stack", "VPS_getProjectListV1", "stack", "stack", "running", "docker", null, null, null, null, null, null, null, "{\"projectName\":\"stack\"}");
    try db.upsertHostingerInventoryItem("VPS_getScanMetricsV1|12345|monarx", "VPS_getScanMetricsV1", "monarx", "Monarx", "unsupported", "security", null, null, null, null, null, null, null, "{\"status\":\"unsupported\"}");
    try db.upsertHostingerInventoryItem("reach_listContactsV1/contact-1", "reach_listContactsV1", "contact-1", "Contact", "active", "contact", null, null, null, null, null, null, null, "{\"id\":\"contact-1\"}");
    try db.upsertHostingerInventoryItem("ecommerce_getStoresV1/store-1", "ecommerce_getStoresV1", "store-1", "Store", "active", "store", null, null, null, null, null, null, null, "{\"id\":\"store-1\"}");
    try db.upsertHostingerInventoryItem("horizons_getWebsitesV1/site-1", "horizons_getWebsitesV1", "site-1", "Site", "active", "website", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"site-1\"}");
    try db.upsertHostingerInventoryItem("miscKind/item-1", "miscKind", "item-1", "Other", "active", "misc", null, null, null, null, null, null, null, "{\"id\":\"item-1\"}");
    _ = try db.insertSnapshot("hostinger", "billing", null, "ok", "billing catalog", null, null);
    _ = try db.insertSnapshot("hostinger", "dns", "plosca.ru", "ok", "dns zone", null, null);
    _ = try db.insertSnapshot("cloudflare", "zone", "plosca.ru", "ok", "zone", null, null);

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var overview = try AccountOverview.load(ctx, .{ .limit = 20, .snapshot_limit = 5 });
    defer overview.deinit(allocator);
    const summary = overview.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.vps);
    try std.testing.expectEqual(@as(usize, 1), summary.running_vps);
    try std.testing.expectEqual(@as(usize, 0), summary.complete_vps_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.partial_vps_core_coverage);
    try std.testing.expectEqual(@as(i64, 1), summary.resources);
    try std.testing.expectEqual(@as(i64, 12), summary.inventory_items);
    try std.testing.expectEqual(@as(usize, 1), summary.resource_kinds);
    try std.testing.expectEqual(@as(usize, 11), summary.inventory_kinds);
    try std.testing.expectEqual(@as(usize, 11), summary.inventory_facets);
    try std.testing.expectEqual(@as(usize, 2), summary.recent_snapshots);
    try std.testing.expectEqual(@as(usize, 71), summary.api_routes);
    try std.testing.expectEqual(@as(usize, 31), summary.api_read_routes);
    try std.testing.expectEqual(@as(usize, 39), summary.api_dry_run_routes);
    try std.testing.expectEqual(@as(usize, 1), summary.api_not_applicable_routes);
    try std.testing.expectEqual(@as(usize, 8), summary.api_families);
    try std.testing.expectEqual(@as(usize, 7), summary.observed_read_families);
    try std.testing.expectEqual(@as(usize, 0), summary.missing_read_families);
    try std.testing.expectEqual(@as(usize, 1), summary.not_applicable_families);
    try std.testing.expectEqual(@as(i64, 1), summary.families.billing);
    try std.testing.expectEqual(@as(i64, 2), summary.families.dns);
    try std.testing.expectEqual(@as(i64, 1), summary.families.domains);
    try std.testing.expectEqual(@as(i64, 1), summary.families.hosting);
    try std.testing.expectEqual(@as(i64, 1), summary.families.vps);
    try std.testing.expectEqual(@as(i64, 1), summary.families.docker);
    try std.testing.expectEqual(@as(i64, 1), summary.families.security);
    try std.testing.expectEqual(@as(i64, 1), summary.families.reach);
    try std.testing.expectEqual(@as(i64, 1), summary.families.ecommerce);
    try std.testing.expectEqual(@as(i64, 1), summary.families.horizons);
    try std.testing.expectEqual(@as(i64, 1), summary.families.other);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeAccountOverviewText(ctx, .{ .limit = 20, .snapshot_limit = 5 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger account overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary vps=1 running_vps=1 stopped_or_other_vps=0 complete_vps_core_coverage=0 partial_vps_core_coverage=1 resources=1 inventory_items=12 resource_kinds=1 inventory_kinds=11 inventory_facets=11 recent_snapshots=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_routes total=71 read=31 dry_run=39 not_applicable=1 families=8 observed_read_families=7 missing_read_families=0 not_applicable_families=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "families billing=1 dns=2 domains=1 hosting=1 vps=1 docker=1 security=1 reach=1 ecommerce=1 horizons=1 other=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "VPS_getProjectListV1\tfamily=docker\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "horizons_getWebsitesV1\tfamily=horizons\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "billing\tofficial_routes=7\tread_routes=3\tdry_run_routes=4\tnot_applicable_routes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "domain_access_verifier\tofficial_routes=1\tread_routes=0\tdry_run_routes=0\tnot_applicable_routes=1\tobserved_items=0\tobserved_kinds=0\tstatus=not_applicable") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "recent snapshots\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/dns\ttarget=plosca.ru\tstatus=ok\tsummary=dns zone") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/zone") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeAccountOverviewJson(ctx, .{ .limit = 20, .snapshot_limit = 5 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_account_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"vps\":1,\"running_vps\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_routes\":71,\"api_read_routes\":31,\"api_dry_run_routes\":39,\"api_not_applicable_routes\":1,\"api_families\":8,\"observed_read_families\":7,\"missing_read_families\":0,\"not_applicable_families\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"families\":{\"billing\":1,\"dns\":2,\"domains\":1,\"hosting\":1,\"vps\":1,\"docker\":1,\"security\":1,\"reach\":1,\"ecommerce\":1,\"horizons\":1,\"other\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_facets\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"VPS_getProjectListV1\",\"family\":\"docker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"horizons_getWebsitesV1\",\"family\":\"horizons\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"billing\",\"official_routes\":7,\"read_routes\":3,\"dry_run_routes\":4,\"not_applicable_routes\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"domain_access_verifier\",\"official_routes\":1,\"read_routes\":0,\"dry_run_routes\":0,\"not_applicable_routes\":1,\"observed_items\":0,\"observed_kinds\":0,\"status\":\"not_applicable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\",\"kind\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\"") == null);
}

test "hostinger app renders VPS overview from normalized storage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-vps-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerVps("67890", "srv67890.hstgr.cloud", "stopped", "", "KVM 1", "{\"id\":67890}");
    try db.insertHostingerMetric("12345", "cpu", "0.42", "{\"cpu\":0.42}");
    try db.upsertHostingerResource("hostinger-vps-detail||12345", "vps-detail", "12345", "12345", "srv12345.hstgr.cloud", "running", null, "{\"id\":\"12345\"}");
    try db.upsertHostingerResource("hostinger-vps-actions||12345||reboot", "hostinger-vps-actions", "reboot", "12345", "Reboot", "available", null, "{\"id\":\"reboot\"}");
    try db.upsertHostingerResource("hostinger-vps-action-detail||12345/reboot||step-1", "hostinger-vps-action-detail", "step-1", "12345/reboot", "Step 1", "complete", null, "{\"id\":\"step-1\"}");
    try db.upsertHostingerResource("hostinger-vps-public-keys||12345||key-1", "public-keys", "key-1", "12345", "deploy", "attached", null, "{\"id\":\"key-1\"}");
    try db.upsertHostingerResource("hostinger-vps-docker||12345||stack", "docker", "stack", "12345", "stack", "running", null, "{\"name\":\"stack\"}");
    try db.upsertHostingerResource("hostinger-vps-monarx||12345||scan", "monarx", "scan", "12345", "Monarx", "enabled", null, "{\"state\":\"enabled\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-templates||ubuntu", "hostinger-vps-templates", "ubuntu", "Ubuntu", "available", "linux", null, null, null, "enabled", null, null, null, "{\"id\":\"ubuntu\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-data-centers||eu-west", "data-centers", "eu-west", "EU West", "available", "location", null, null, null, null, null, null, null, "{\"id\":\"eu-west\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-firewalls||fw-1", "firewalls", "fw-1", "default", "active", "firewall", null, null, null, null, null, null, null, "{\"id\":\"fw-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-post-install||script-1", "post-install-scripts", "script-1", "bootstrap", "active", "script", null, null, null, null, null, null, null, "{\"id\":\"script-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-public-keys-global||key-1", "public-keys-global", "key-1", "deploy", "active", "ssh", null, null, null, null, null, null, null, "{\"id\":\"key-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-backups|12345|backup-1", "hostinger-vps-backups", "backup-1", "Backup 1", "available", "backup", null, null, null, null, "2026-01-01T00:00:00Z", null, null, "{\"id\":\"backup-1\"}");
    try db.upsertHostingerInventoryItem("snapshot|12345|snapshot", "snapshot", "snapshot", "Snapshot", "available", "snapshot", null, null, null, null, "2026-01-02T00:00:00Z", null, null, "{\"id\":\"snapshot\"}");
    _ = try db.insertSnapshot("hostinger", "vps", null, "ok", "vps list", null, null);
    _ = try db.insertSnapshot("hostinger", "monarx", "12345", "ok", "scan metrics", null, null);
    _ = try db.insertSnapshot("cloudflare", "zone", "plosca.ru", "ok", "zone", null, null);

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var limited_overview = try VpsOverview.load(ctx, .{ .limit = 1, .snapshot_limit = 1 });
    defer limited_overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), limited_overview.vps.items.len);
    try std.testing.expectEqual(@as(usize, 2), limited_overview.summary().vps);
    try std.testing.expectEqual(@as(usize, 1), limited_overview.recent_snapshots.items.len);

    var overview = try VpsOverview.load(ctx, .{ .limit = 10, .snapshot_limit = 2 });
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), overview.vps.items.len);
    try std.testing.expectEqualStrings("12345", overview.vps.items[0].id);
    try std.testing.expectEqual(@as(usize, 6), overview.resource_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 7), overview.inventory_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 1), overview.metric_summaries.items.len);
    try std.testing.expectEqualStrings("cpu", overview.metric_summaries.items[0].metric);
    try std.testing.expectEqual(@as(usize, 9), overview.family_summaries.items.len);
    const summary = overview.summary();
    try std.testing.expectEqual(@as(usize, 2), summary.vps);
    try std.testing.expectEqual(@as(usize, 1), summary.running);
    try std.testing.expectEqual(@as(usize, 1), summary.stopped_or_other);
    try std.testing.expectEqual(@as(usize, 1), summary.complete_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.partial_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.with_details);
    try std.testing.expectEqual(@as(usize, 1), summary.with_metrics);
    try std.testing.expectEqual(@as(usize, 1), summary.with_actions);
    try std.testing.expectEqual(@as(usize, 1), summary.with_backups);
    try std.testing.expectEqual(@as(usize, 1), summary.with_snapshot);
    try std.testing.expectEqual(@as(usize, 1), summary.with_public_keys);
    try std.testing.expectEqual(@as(usize, 1), summary.with_security);
    try std.testing.expectEqual(@as(usize, 1), summary.with_docker);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_details);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_metrics);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_actions);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_backups);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_snapshot);
    try std.testing.expectEqual(@as(usize, 6), summary.resource_kinds);
    try std.testing.expectEqual(@as(usize, 7), summary.inventory_kinds);
    try std.testing.expectEqual(@as(usize, 1), summary.metric_summaries);
    try std.testing.expectEqual(@as(usize, 9), summary.family_summaries);
    try std.testing.expectEqual(@as(usize, 2), summary.recent_snapshots);
    try std.testing.expectEqual(@as(usize, 62), summary.api_routes);
    try std.testing.expectEqual(@as(usize, 21), summary.api_read_routes);
    try std.testing.expectEqual(@as(usize, 41), summary.api_dry_run_routes);
    try std.testing.expectEqual(@as(usize, 13), summary.api_families);
    try std.testing.expectEqual(@as(usize, 11), summary.observed_read_families);
    try std.testing.expectEqual(@as(usize, 0), summary.missing_read_families);
    try std.testing.expectEqual(@as(usize, 2), summary.dry_run_only_families);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeVpsOverviewText(ctx, .{ .limit = 10, .snapshot_limit = 2 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger VPS overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary vps=2 running=1 stopped_or_other=1 complete_core_coverage=1 partial_core_coverage=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_routes total=62 read=21 dry_run=41 families=13 observed_read_families=11 missing_read_families=0 dry_run_only_families=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345\tname=srv12345.hstgr.cloud\tstatus=running\tipv4=76.13.130.170\tplan=KVM 2\tcoverage=complete\tdetails=true\tmetrics=true\tactions=true\tbackups=true\tsnapshot=true\tpublic_keys=true\tsecurity=true\tdocker=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "67890\tname=srv67890.hstgr.cloud\tstatus=stopped\tplan=KVM 1\tcoverage=partial\tdetails=false\tmetrics=false\tactions=false\tbackups=false\tsnapshot=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "coverage_issues=missing_details,missing_metrics,missing_actions,missing_backups,missing_snapshot") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/cpu\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "vm family\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/vps-detail\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-action-detail\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/inventory/hostinger-vps-backups\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/inventory/snapshot\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/metric/cpu\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "virtual_machine\tofficial_routes=15\tread_routes=4\tdry_run_routes=11\tobserved_items=5\tobserved_kinds=4\tstatus=observed") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ptr_records\tofficial_routes=2\tread_routes=0\tdry_run_routes=2\tobserved_items=0\tobserved_kinds=0\tstatus=dry_run_only") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "recent snapshots\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/monarx\ttarget=12345\tstatus=ok\tsummary=scan metrics") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/zone") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeVpsOverviewJson(ctx, .{ .limit = 10, .snapshot_limit = 2 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_vps_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"vps\":2,\"running\":1,\"stopped_or_other\":1,\"complete_core_coverage\":1,\"partial_core_coverage\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_routes\":62,\"api_read_routes\":21,\"api_dry_run_routes\":41,\"api_families\":13,\"observed_read_families\":11,\"missing_read_families\":0,\"dry_run_only_families\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"12345\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_status\":\"complete\",\"coverage\":{\"details\":true,\"metrics\":true,\"actions\":true,\"backups\":true,\"snapshot\":true,\"public_keys\":true,\"security\":true,\"docker\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"67890\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_status\":\"partial\",\"coverage\":{\"details\":false,\"metrics\":false,\"actions\":false,\"backups\":false,\"snapshot\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_issues\":[\"missing_details\",\"missing_metrics\",\"missing_actions\",\"missing_backups\",\"missing_snapshot\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"resource_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric_summaries\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric\":\"cpu\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"vm_family\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"resource\",\"kind\":\"vps-detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"resource\",\"kind\":\"hostinger-vps-actions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"inventory\",\"kind\":\"hostinger-vps-backups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"inventory\",\"kind\":\"snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"virtual_machine\",\"official_routes\":15,\"read_routes\":4,\"dry_run_routes\":11,\"observed_items\":5,\"observed_kinds\":4,\"status\":\"observed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"recovery\",\"official_routes\":2,\"read_routes\":0,\"dry_run_routes\":2,\"observed_items\":0,\"observed_kinds\":0,\"status\":\"dry_run_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\",\"kind\":\"monarx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\"") == null);
}
