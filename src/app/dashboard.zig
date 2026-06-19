const std = @import("std");
const app_actions = @import("app_actions");
const app_overview = @import("app_overview");
const app_render = @import("app_render");
const app_topology = @import("app_topology");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_limit = 200;

pub const Section = enum {
    all,
    domains,
    vps,
    system,
    caddy,
    providers,

    pub fn parse(value: []const u8) ?Section {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "domains")) return .domains;
        if (std.mem.eql(u8, value, "vps")) return .vps;
        if (std.mem.eql(u8, value, "system")) return .system;
        if (std.mem.eql(u8, value, "caddy")) return .caddy;
        if (std.mem.eql(u8, value, "providers")) return .providers;
        return null;
    }

    pub fn label(self: Section) []const u8 {
        return switch (self) {
            .all => "all",
            .domains => "domains",
            .vps => "vps",
            .system => "system",
            .caddy => "caddy",
            .providers => "providers",
        };
    }
};

pub const Options = struct {
    domain: ?[]const u8 = null,
    issues_only: bool = false,
    section: Section = .all,
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .domain = self.domain,
            .issues_only = self.issues_only,
            .section = self.section,
            .limit = app_render.positiveLimit(self.limit, default_limit),
        };
    }
};

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const Dashboard = struct {
    options: Options,
    overview: app_overview.Overview,
    audit_events: db_store.AuditEvents,
    topology: app_topology.Topology,
    cloudflare_accounts: db_store.CloudflareAccountRows,
    cloudflare_zones: db_store.CloudflareZoneRows,
    cloudflare_dns: db_store.CloudflareDnsRecordRows,
    cloudflare_resources: db_store.CloudflareKindCounts,
    cloudflare_inventory: db_store.InventoryFacets,
    cloudflare_security: db_store.CloudflareKindCounts,
    cloudflare_security_items: i64,
    hostinger_vps: db_store.HostingerVpsRows,
    hostinger_metrics: db_store.HostingerMetricSummaries,
    hostinger_evidence: db_store.HostingerVpsFamilySummaries,
    hostinger_inventory: db_store.InventoryFacets,
    system_metrics: db_store.MetricRows,
    services: db_store.NameValueRows,
    sockets: db_store.NameValueRows,
    containers: db_store.NameValueRows,
    caddy_upstreams: db_store.NameValueRows,

    pub fn load(ctx: Context, options: Options) !Dashboard {
        const normalized = options.normalized();
        var overview = try app_overview.Overview.load(ctx.gpa, ctx.db, 12);
        errdefer overview.deinit(ctx.gpa);
        var audit_events = try ctx.db.recentAuditEvents(ctx.gpa, 50);
        errdefer audit_events.deinit(ctx.gpa);
        var topology = try app_topology.Topology.load(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .limit = normalized.limit });
        errdefer topology.deinit(ctx.gpa);
        var cloudflare_accounts = try ctx.db.cloudflareAccountRows(ctx.gpa, normalized.limit);
        errdefer cloudflare_accounts.deinit(ctx.gpa);
        var cloudflare_zones = try ctx.db.cloudflareZoneRows(ctx.gpa, normalized.limit);
        errdefer cloudflare_zones.deinit(ctx.gpa);
        var cloudflare_dns = try ctx.db.cloudflareDnsRecordRows(ctx.gpa, normalized.limit);
        errdefer cloudflare_dns.deinit(ctx.gpa);
        var cloudflare_resources = try ctx.db.cloudflareResourceKindCounts(ctx.gpa, normalized.limit);
        errdefer cloudflare_resources.deinit(ctx.gpa);
        var cloudflare_inventory = try ctx.db.inventoryFacets(ctx.gpa, .{ .provider = "cloudflare", .domain = normalized.domain, .limit = normalized.limit });
        errdefer cloudflare_inventory.deinit(ctx.gpa);
        var cloudflare_security = try ctx.db.cloudflareSecurityKindCounts(ctx.gpa, normalized.limit);
        errdefer cloudflare_security.deinit(ctx.gpa);
        var hostinger_vps = try ctx.db.hostingerVpsRows(ctx.gpa, normalized.limit);
        errdefer hostinger_vps.deinit(ctx.gpa);
        var hostinger_metrics = try ctx.db.hostingerMetricSummaries(ctx.gpa, normalized.limit);
        errdefer hostinger_metrics.deinit(ctx.gpa);
        var hostinger_evidence = try ctx.db.hostingerVpsFamilySummaries(ctx.gpa, normalized.limit);
        errdefer hostinger_evidence.deinit(ctx.gpa);
        var hostinger_inventory = try ctx.db.inventoryFacets(ctx.gpa, .{ .provider = "hostinger", .domain = normalized.domain, .limit = normalized.limit });
        errdefer hostinger_inventory.deinit(ctx.gpa);
        var system_metrics = try ctx.db.recentMetrics(ctx.gpa, normalized.limit);
        errdefer system_metrics.deinit(ctx.gpa);
        var services = try ctx.db.serviceList(ctx.gpa);
        errdefer services.deinit(ctx.gpa);
        var sockets = try ctx.db.socketList(ctx.gpa);
        errdefer sockets.deinit(ctx.gpa);
        var containers = try ctx.db.containerList(ctx.gpa);
        errdefer containers.deinit(ctx.gpa);
        var caddy_upstreams = try ctx.db.caddyUpstreams(ctx.gpa);
        errdefer caddy_upstreams.deinit(ctx.gpa);
        return .{
            .options = normalized,
            .overview = overview,
            .audit_events = audit_events,
            .topology = topology,
            .cloudflare_accounts = cloudflare_accounts,
            .cloudflare_zones = cloudflare_zones,
            .cloudflare_dns = cloudflare_dns,
            .cloudflare_resources = cloudflare_resources,
            .cloudflare_inventory = cloudflare_inventory,
            .cloudflare_security = cloudflare_security,
            .cloudflare_security_items = try ctx.db.countTable("cloudflare_security_items"),
            .hostinger_vps = hostinger_vps,
            .hostinger_metrics = hostinger_metrics,
            .hostinger_evidence = hostinger_evidence,
            .hostinger_inventory = hostinger_inventory,
            .system_metrics = system_metrics,
            .services = services,
            .sockets = sockets,
            .containers = containers,
            .caddy_upstreams = caddy_upstreams,
        };
    }

    pub fn deinit(self: *Dashboard, gpa: Allocator) void {
        self.overview.deinit(gpa);
        self.audit_events.deinit(gpa);
        self.topology.deinit(gpa);
        self.cloudflare_accounts.deinit(gpa);
        self.cloudflare_zones.deinit(gpa);
        self.cloudflare_dns.deinit(gpa);
        self.cloudflare_resources.deinit(gpa);
        self.cloudflare_inventory.deinit(gpa);
        self.cloudflare_security.deinit(gpa);
        self.hostinger_vps.deinit(gpa);
        self.hostinger_metrics.deinit(gpa);
        self.hostinger_evidence.deinit(gpa);
        self.hostinger_inventory.deinit(gpa);
        self.system_metrics.deinit(gpa);
        self.services.deinit(gpa);
        self.sockets.deinit(gpa);
        self.containers.deinit(gpa);
        self.caddy_upstreams.deinit(gpa);
    }

    pub fn writeText(self: Dashboard, writer: anytype) !void {
        const topology_summary = self.filteredTopologySummary();
        try writer.writeAll("Cloudio dashboard\n");
        try writer.print("section={s} domain={s} issues_only={} snapshots={d} topology={d} vps={d} services={d} sockets={d} containers={d}\n", .{
            self.options.section.label(),
            self.options.domain orelse "",
            self.options.issues_only,
            self.overview.counts.snapshots,
            topology_summary.total,
            self.hostinger_vps.items.len,
            self.services.items.len,
            self.sockets.items.len,
            self.containers.items.len,
        });
    }

    pub fn writeJson(self: Dashboard, ctx: Context, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"dashboard\",\"version\":1,");
        try writeRequestJson(self.options, writer);
        try writer.writeAll(",\"filters\":");
        try app_actions.writeFilterMetadataJson(writer);
        try writer.writeAll(",\"toggles\":");
        try app_actions.writeToggleMetadataJson(writer);
        try writer.writeAll(",\"summary\":");
        try self.writeSummaryJson(writer);
        try writer.writeAll(",\"sections\":{");
        try self.writeDomainsSection(writer, shouldInclude(self.options.section, .domains));
        try writer.writeByte(',');
        try self.writeVpsSection(writer, shouldInclude(self.options.section, .vps));
        try writer.writeByte(',');
        try self.writeSystemSection(writer, shouldInclude(self.options.section, .system));
        try writer.writeByte(',');
        try self.writeCaddySection(writer, shouldInclude(self.options.section, .caddy));
        try writer.writeByte(',');
        try self.writeProvidersSection(writer, shouldInclude(self.options.section, .providers));
        try writer.writeAll("},\"actions\":");
        try app_actions.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{
            .domain = self.options.domain,
            .limit = self.options.limit,
        }, writer);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }

    fn writeSummaryJson(self: Dashboard, writer: anytype) !void {
        const topology_summary = self.filteredTopologySummary();
        try writer.writeByte('{');
        try writer.writeAll("\"counts\":{");
        try writeOverviewCountsJson(self.overview.counts, self.cloudflare_security_items, writer);
        try writer.writeAll("},\"last_refresh\":");
        try writeLastRefreshJson(self.audit_events.items, writer);
        try writer.writeAll(",\"topology\":");
        try app_topology.writeSummaryJson(topology_summary, writer);
        try writer.writeByte('}');
    }

    fn writeDomainsSection(self: Dashboard, writer: anytype, include: bool) !void {
        try writer.writeAll("\"domains\":");
        if (!include) return try writer.writeAll("null");
        try writer.writeAll("{\"summary\":");
        try app_topology.writeSummaryJson(self.filteredTopologySummary(), writer);
        try writer.writeAll(",\"topology\":[");
        var first = true;
        for (self.topology.rows.items) |row| {
            if (!self.includeTopologyRow(row)) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try app_topology.writeRowJson(row, writer);
        }
        try writer.writeAll("],\"dns_records\":[");
        first = true;
        for (self.cloudflare_dns.items) |row| {
            if (!includeDomain(self.options.domain, row.name)) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writeCloudflareDnsJson(row, writer);
        }
        try writer.writeAll("]}");
    }

    fn writeVpsSection(self: Dashboard, writer: anytype, include: bool) !void {
        try writer.writeAll("\"vps\":");
        if (!include) return try writer.writeAll("null");
        try writer.writeAll("{\"items\":[");
        for (self.hostinger_vps.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeHostingerVpsJson(row, writer);
        }
        try writer.writeAll("],\"metrics\":[");
        for (self.hostinger_metrics.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeHostingerMetricSummaryJson(row, writer);
        }
        try writer.writeAll("],\"evidence\":[");
        for (self.hostinger_evidence.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeHostingerEvidenceJson(row, writer);
        }
        try writer.writeAll("]}");
    }

    fn writeSystemSection(self: Dashboard, writer: anytype, include: bool) !void {
        try writer.writeAll("\"system\":");
        if (!include) return try writer.writeAll("null");
        try writer.writeAll("{\"metrics\":[");
        for (self.system_metrics.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeMetricJson(row, writer);
        }
        try writer.writeAll("],\"services\":[");
        try writeNameValueArrayJson(self.services.items, writer);
        try writer.writeAll("],\"sockets\":[");
        try writeNameValueArrayJson(self.sockets.items, writer);
        try writer.writeAll("],\"containers\":[");
        try writeNameValueArrayJson(self.containers.items, writer);
        try writer.writeAll("]}");
    }

    fn writeCaddySection(self: Dashboard, writer: anytype, include: bool) !void {
        try writer.writeAll("\"caddy\":");
        if (!include) return try writer.writeAll("null");
        try writer.writeAll("{\"upstreams\":[");
        var first = true;
        for (self.caddy_upstreams.items) |row| {
            if (!includeDomain(self.options.domain, row.name)) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writeNameValueJson(row, "host", "upstream", writer);
        }
        try writer.writeAll("]}");
    }

    fn writeProvidersSection(self: Dashboard, writer: anytype, include: bool) !void {
        try writer.writeAll("\"providers\":");
        if (!include) return try writer.writeAll("null");
        try writer.writeAll("{\"cloudflare\":{\"accounts\":[");
        for (self.cloudflare_accounts.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeCloudflareAccountJson(row, writer);
        }
        try writer.writeAll("],\"zones\":[");
        var first = true;
        for (self.cloudflare_zones.items) |row| {
            if (!includeDomain(self.options.domain, row.name)) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writeCloudflareZoneJson(row, writer);
        }
        try writer.writeAll("],\"dns_records\":[");
        first = true;
        for (self.cloudflare_dns.items) |row| {
            if (!includeDomain(self.options.domain, row.name)) continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writeCloudflareDnsJson(row, writer);
        }
        try writer.writeAll("],\"resource_kinds\":[");
        try writeKindCountArrayJson(self.cloudflare_resources.items, writer);
        try writer.writeAll("],\"inventory_facets\":[");
        try writeInventoryFacetArrayJson(self.cloudflare_inventory.items, writer);
        try writer.writeAll("],\"security_kinds\":[");
        try writeKindCountArrayJson(self.cloudflare_security.items, writer);
        try writer.writeAll("]},\"hostinger\":{\"vps\":[");
        for (self.hostinger_vps.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeHostingerVpsJson(row, writer);
        }
        try writer.writeAll("],\"inventory_facets\":[");
        try writeInventoryFacetArrayJson(self.hostinger_inventory.items, writer);
        try writer.writeAll("],\"vps_evidence\":[");
        for (self.hostinger_evidence.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeHostingerEvidenceJson(row, writer);
        }
        try writer.writeAll("]}}");
    }

    fn filteredTopologySummary(self: Dashboard) app_topology.Summary {
        var out = app_topology.Summary{};
        for (self.topology.rows.items) |row| {
            if (!self.includeTopologyRow(row)) continue;
            addTopologyRow(&out, row);
        }
        return out;
    }

    fn includeTopologyRow(self: Dashboard, row: db_store.TopologyRow) bool {
        if (self.options.issues_only and !app_topology.rowHasIssues(row)) return false;
        const domain = self.options.domain orelse return true;
        return includeDomain(domain, row.host) or includeDomain(domain, row.dns_name);
    }
};

pub fn writeText(ctx: Context, options: Options, writer: anytype) !void {
    var dashboard = try Dashboard.load(ctx, options);
    defer dashboard.deinit(ctx.gpa);
    try dashboard.writeText(writer);
}

pub fn writeJson(ctx: Context, options: Options, writer: anytype) !void {
    var dashboard = try Dashboard.load(ctx, options);
    defer dashboard.deinit(ctx.gpa);
    try dashboard.writeJson(ctx, writer);
}

fn shouldInclude(selected: Section, section: Section) bool {
    return selected == .all or selected == section;
}

fn addTopologyRow(summary: *app_topology.Summary, row: db_store.TopologyRow) void {
    summary.total += 1;
    switch (app_topology.rowStatus(row)) {
        .healthy => summary.healthy += 1,
        .degraded => summary.degraded += 1,
        .dns_only => summary.dns_only += 1,
        .local_only => summary.local_only += 1,
        .project_only => summary.project_only += 1,
    }
    if (app_topology.hasDns(row)) summary.dns += 1;
    if (app_topology.hasCaddy(row)) summary.caddy += 1;
    if (app_topology.hasProject(row)) summary.projects += 1;
    if (app_topology.hasSocket(row)) summary.sockets += 1;
    if (app_topology.hasService(row)) summary.services += 1;
    if (app_topology.hasContainer(row)) summary.containers += 1;
    switch (app_topology.dnsMatch(row)) {
        .direct => summary.direct_dns += 1,
        .wildcard => summary.wildcard_dns += 1,
        .none => {},
    }
    if (app_topology.issueCount(row) == 0) return;
    if (app_topology.rowStatus(row) == .dns_only) summary.dns_only += 0;
    if (row.host.len != 0 and app_topology.hasCaddy(row) and !app_topology.hasDns(row)) summary.caddy_without_dns += 1;
    if (row.upstream.len != 0 and !app_topology.hasSocket(row)) summary.upstream_without_socket += 1;
    if (app_topology.hasProject(row) and row.host.len == 0 and row.upstream.len == 0 and row.service.len == 0 and row.container.len == 0) summary.project_without_runtime += 1;
    if (app_topology.hasService(row) and !stateLooksRunning(row.service_state)) summary.service_not_running += 1;
    if (app_topology.hasContainer(row) and !stateLooksRunning(row.container_status)) summary.container_not_running += 1;
}

fn writeRequestJson(options: Options, writer: anytype) !void {
    try writer.writeAll("\"request\":{");
    try app_render.writeJsonNullableStringField(writer, "domain", options.domain, true);
    try app_render.writeJsonBoolField(writer, "issues_only", options.issues_only, true);
    try app_render.writeJsonStringField(writer, "section", options.section.label(), true);
    try app_render.writeJsonIntField(writer, "limit", options.limit, false);
    try writer.writeByte('}');
}

fn writeOverviewCountsJson(counts: app_overview.Counts, cloudflare_security_items: i64, writer: anytype) !void {
    try app_render.writeJsonIntField(writer, "snapshots", counts.snapshots, true);
    try app_render.writeJsonIntField(writer, "cloudflare_accounts", counts.cloudflare_accounts, true);
    try app_render.writeJsonIntField(writer, "cloudflare_zones", counts.cloudflare_zones, true);
    try app_render.writeJsonIntField(writer, "cloudflare_dns_records", counts.cloudflare_dns_records, true);
    try app_render.writeJsonIntField(writer, "cloudflare_resources", counts.cloudflare_resources, true);
    try app_render.writeJsonIntField(writer, "cloudflare_inventory_items", counts.cloudflare_inventory_items, true);
    try app_render.writeJsonIntField(writer, "cloudflare_security_items", cloudflare_security_items, true);
    try app_render.writeJsonIntField(writer, "hostinger_vps", counts.hostinger_vps, true);
    try app_render.writeJsonIntField(writer, "hostinger_resources", counts.hostinger_resources, true);
    try app_render.writeJsonIntField(writer, "hostinger_inventory_items", counts.hostinger_inventory_items, true);
    try app_render.writeJsonIntField(writer, "caddy_sites", counts.caddy_sites, true);
    try app_render.writeJsonIntField(writer, "caddy_upstreams", counts.caddy_upstreams, true);
    try app_render.writeJsonIntField(writer, "projects", counts.projects, true);
    try app_render.writeJsonIntField(writer, "services", counts.services, true);
    try app_render.writeJsonIntField(writer, "sockets", counts.sockets, true);
    try app_render.writeJsonIntField(writer, "containers", counts.containers, false);
}

fn writeLastRefreshJson(events: []const db_store.AuditEvent, writer: anytype) !void {
    for (events) |event| {
        if (!std.mem.eql(u8, event.action, "refresh")) continue;
        try app_render.writeAuditEventJson(writer, event, .{ .include_id = true });
        return;
    }
    try writer.writeAll("null");
}

fn writeCloudflareAccountJson(row: db_store.CloudflareAccountRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", row.id, true);
    try app_render.writeJsonStringField(writer, "name", row.name, true);
    try app_render.writeJsonStringField(writer, "type", row.account_type, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeCloudflareZoneJson(row: db_store.CloudflareZoneRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", row.id, true);
    try app_render.writeJsonStringField(writer, "name", row.name, true);
    try app_render.writeJsonStringField(writer, "account_id", row.account_id, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "paused", row.paused, true);
    try app_render.writeJsonStringField(writer, "type", row.zone_type, true);
    try app_render.writeJsonStringField(writer, "name_servers", row.name_servers, true);
    try app_render.writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeCloudflareDnsJson(row: db_store.CloudflareDnsRecordRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", row.id, true);
    try app_render.writeJsonStringField(writer, "zone_id", row.zone_id, true);
    try app_render.writeJsonStringField(writer, "name", row.name, true);
    try app_render.writeJsonStringField(writer, "type", row.record_type, true);
    try app_render.writeJsonStringField(writer, "content", row.content, true);
    try app_render.writeJsonStringField(writer, "ttl", row.ttl, true);
    try app_render.writeJsonStringField(writer, "proxied", row.proxied, true);
    try app_render.writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeHostingerVpsJson(row: db_store.HostingerVpsRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "id", row.id, true);
    try app_render.writeJsonStringField(writer, "name", row.name, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "ipv4", row.ipv4, true);
    try app_render.writeJsonStringField(writer, "plan", row.plan, true);
    try app_render.writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeHostingerMetricSummaryJson(row: db_store.HostingerMetricSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try app_render.writeJsonStringField(writer, "metric", row.metric, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_captured", row.latest_captured, false);
    try writer.writeByte('}');
}

fn writeHostingerEvidenceJson(row: db_store.HostingerVpsFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeMetricJson(row: db_store.MetricRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "metric", row.metric, true);
    try app_render.writeJsonStringField(writer, "value", row.value, true);
    try app_render.writeJsonStringField(writer, "unit", row.unit, true);
    try app_render.writeJsonStringField(writer, "captured_at", row.captured_at, false);
    try writer.writeByte('}');
}

fn writeNameValueArrayJson(rows: []const db_store.NameValueRow, writer: anytype) !void {
    for (rows, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writeNameValueJson(row, "name", "value", writer);
    }
}

fn writeNameValueJson(row: db_store.NameValueRow, name_field: []const u8, value_field: []const u8, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, name_field, row.name, true);
    try app_render.writeJsonStringField(writer, value_field, row.value, false);
    try writer.writeByte('}');
}

fn writeKindCountArrayJson(rows: []const db_store.CloudflareKindCount, writer: anytype) !void {
    for (rows, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "kind", row.kind, true);
        try app_render.writeJsonIntField(writer, "count", row.count, true);
        try app_render.writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
        try writer.writeByte('}');
    }
}

fn writeInventoryFacetArrayJson(rows: []const db_store.InventoryFacet, writer: anytype) !void {
    for (rows, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "provider", row.provider, true);
        try app_render.writeJsonStringField(writer, "kind", row.kind, true);
        try app_render.writeJsonStringField(writer, "status", row.status, true);
        try app_render.writeJsonStringField(writer, "category", row.category, true);
        try app_render.writeJsonIntField(writer, "count", row.count, true);
        try app_render.writeJsonIntField(writer, "domains", row.domains, true);
        try app_render.writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
        try writer.writeByte('}');
    }
}

fn includeDomain(filter: ?[]const u8, value: []const u8) bool {
    const domain = filter orelse return true;
    return domainMatches(value, domain);
}

fn domainMatches(value: []const u8, domain: []const u8) bool {
    if (domain.len == 0) return true;
    if (std.ascii.eqlIgnoreCase(value, domain)) return true;
    if (value.len > domain.len and std.ascii.endsWithIgnoreCase(value, domain) and value[value.len - domain.len - 1] == '.') return true;
    return false;
}

fn stateLooksRunning(value: []const u8) bool {
    return containsIgnoreCase(value, "running") or containsIgnoreCase(value, "active") or containsIgnoreCase(value, "up") or containsIgnoreCase(value, "observed");
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

test "dashboard renders stable top-level JSON contract" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-dashboard.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.insertAudit("refresh", "ok", "dashboard refresh complete");
    _ = try db.insertSnapshot("cloudflare", "dns", "plosca.ru", "ok", "records", null, null);
    try db.upsertCloudflareAccount("acct-1", "account", "standard", "active", "{}");
    try db.upsertCloudflareZone("zone-1", "plosca.ru", "acct-1", "active", false, "full", "[]", "{}");
    try db.upsertDnsRecord("record-1", "zone-1", "plosca.ru", "A", "76.13.130.170", 1, false, "{}");
    try db.upsertCaddySite("plosca.ru", "/etc/caddy/Caddyfile", "plosca.ru { reverse_proxy 127.0.0.1:9327 }");
    try db.insertCaddyUpstream("plosca.ru", "", "127.0.0.1:9327");
    try db.upsertProject("plosca", "zig", "/home/kid/Projects/plosca.ru", "plosca.ru", "127.0.0.1:9327", "plosca.service", "plosca", null);
    try db.upsertService("plosca.service", "user", "active", "running", "plosca", "raw");
    try db.insertSocket("tcp", "LISTEN", "127.0.0.1:9327", "plosca.service", "raw");
    try db.upsertContainer("plosca", "plosca:latest", "Up", "9327/tcp", "raw");
    try db.upsertHostingerVps("123", "vps", "running", "76.13.130.170", "KVM", "{}");
    try db.insertHostingerMetric("123", "metrics", "{}", "{}");
    try db.upsertHostingerResource("backups|123|b1", "backups", "b1", "123", "backup", "available", null, "{}");
    try db.upsertCloudflareSecurityItem("security|zone|zone-1|i1", "security-center-insights", "i1", "zone", "zone-1", "Insight", "open", "insight", "low", "review", "plosca.ru", "acct-1", "zone-1", null, "managed", null, "2026-06-17T00:00:00Z", null, "{}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJson(.{ .gpa = allocator, .db = &db }, .{ .domain = "plosca.ru" }, &out.writer);
    const json = try out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("dashboard", parsed.value.object.get("kind").?.string);
    try std.testing.expect(parsed.value.object.get("filters").?.array.items.len >= 8);
    try std.testing.expect(parsed.value.object.get("toggles").?.array.items.len >= 10);
    const sections = parsed.value.object.get("sections").?.object;
    try std.testing.expect(sections.get("domains").? != .null);
    try std.testing.expect(sections.get("vps").? != .null);
    try std.testing.expect(sections.get("system").? != .null);
    try std.testing.expect(sections.get("caddy").? != .null);
    try std.testing.expect(sections.get("providers").? != .null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"last_refresh\":{\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger.vps.snapshot:123\"") != null);
}

test "dashboard section parser accepts UI sections" {
    try std.testing.expectEqual(Section.domains, Section.parse("domains").?);
    try std.testing.expectEqual(Section.vps, Section.parse("vps").?);
    try std.testing.expectEqual(Section.system, Section.parse("system").?);
    try std.testing.expectEqual(Section.caddy, Section.parse("caddy").?);
    try std.testing.expectEqual(Section.providers, Section.parse("providers").?);
    try std.testing.expect(Section.parse("coverage") == null);
}
