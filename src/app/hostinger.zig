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

pub const VpsOverview = struct {
    vps: db_store.HostingerVpsRows,
    resource_kinds: db_store.HostingerKindCounts,
    inventory_kinds: db_store.HostingerKindCounts,
    metric_summaries: db_store.HostingerMetricSummaries,
    family_summaries: db_store.HostingerVpsFamilySummaries,

    pub fn load(ctx: Context, options: VpsOverviewOptions) !VpsOverview {
        const limit = positiveLimit(options.limit, 20);
        return .{
            .vps = try ctx.db.hostingerVpsRows(ctx.gpa, limit),
            .resource_kinds = try ctx.db.hostingerResourceKindCounts(ctx.gpa, limit),
            .inventory_kinds = try ctx.db.hostingerInventoryKindCounts(ctx.gpa, limit),
            .metric_summaries = try ctx.db.hostingerMetricSummaries(ctx.gpa, limit),
            .family_summaries = try ctx.db.hostingerVpsFamilySummaries(ctx.gpa, limit),
        };
    }

    pub fn deinit(self: *VpsOverview, allocator: Allocator) void {
        self.vps.deinit(allocator);
        self.resource_kinds.deinit(allocator);
        self.inventory_kinds.deinit(allocator);
        self.metric_summaries.deinit(allocator);
        self.family_summaries.deinit(allocator);
    }

    pub fn summary(self: VpsOverview) VpsOverviewSummary {
        var out = VpsOverviewSummary{
            .vps = self.vps.items.len,
            .resource_kinds = self.resource_kinds.items.len,
            .inventory_kinds = self.inventory_kinds.items.len,
            .metric_summaries = self.metric_summaries.items.len,
            .family_summaries = self.family_summaries.items.len,
        };
        for (self.vps.items) |row| {
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
        for (self.metric_summaries.items) |row| {
            if (std.mem.eql(u8, row.vm_id, vm_id) and row.count > 0) out.metrics = true;
        }
        for (self.family_summaries.items) |row| {
            if (!std.mem.eql(u8, row.vm_id, vm_id) or row.count <= 0) continue;
            addCoverageKind(&out, row.kind);
        }
        return out;
    }

    pub fn writeText(self: VpsOverview, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Hostinger VPS overview\n");
        try writer.print("summary vps={d} running={d} stopped_or_other={d} complete_core_coverage={d} partial_core_coverage={d} details={d} metrics={d} actions={d} backups={d} snapshot={d} public_keys={d} security={d} docker={d} missing_details={d} missing_metrics={d} missing_actions={d} missing_backups={d} missing_snapshot={d} resource_kinds={d} inventory_kinds={d} metric_summaries={d} family_summaries={d}\n", .{
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
    try app_render.writeJsonIntField(writer, "family_summaries", summary.family_summaries, false);
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
    try db.upsertHostingerInventoryItem("hostinger-vps-templates||ubuntu", "hostinger-vps-templates", "ubuntu", "Ubuntu", "available", "linux", null, null, null, "enabled", null, null, null, "{\"id\":\"ubuntu\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-backups|12345|backup-1", "hostinger-vps-backups", "backup-1", "Backup 1", "available", "backup", null, null, null, null, "2026-01-01T00:00:00Z", null, null, "{\"id\":\"backup-1\"}");
    try db.upsertHostingerInventoryItem("snapshot|12345|snapshot", "snapshot", "snapshot", "Snapshot", "available", "snapshot", null, null, null, null, "2026-01-02T00:00:00Z", null, null, "{\"id\":\"snapshot\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var overview = try VpsOverview.load(ctx, .{ .limit = 10 });
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), overview.vps.items.len);
    try std.testing.expectEqualStrings("12345", overview.vps.items[0].id);
    try std.testing.expectEqual(@as(usize, 3), overview.resource_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 3), overview.inventory_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 1), overview.metric_summaries.items.len);
    try std.testing.expectEqualStrings("cpu", overview.metric_summaries.items[0].metric);
    try std.testing.expectEqual(@as(usize, 6), overview.family_summaries.items.len);
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
    try std.testing.expectEqual(@as(usize, 1), summary.missing_details);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_metrics);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_actions);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_backups);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_snapshot);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeVpsOverviewText(ctx, .{ .limit = 10 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger VPS overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary vps=2 running=1 stopped_or_other=1 complete_core_coverage=1 partial_core_coverage=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345\tname=srv12345.hstgr.cloud\tstatus=running\tipv4=76.13.130.170\tplan=KVM 2\tcoverage=complete\tdetails=true\tmetrics=true\tactions=true\tbackups=true\tsnapshot=true") != null);
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

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeVpsOverviewJson(ctx, .{ .limit = 10 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_vps_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"vps\":2,\"running\":1,\"stopped_or_other\":1,\"complete_core_coverage\":1,\"partial_core_coverage\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"12345\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_status\":\"complete\",\"coverage\":{\"details\":true,\"metrics\":true,\"actions\":true,\"backups\":true,\"snapshot\":true") != null);
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
}
