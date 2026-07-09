const std = @import("std");
const core_fs = @import("core_fs");
const sqlite = @import("sqlite");
const db_schema = @import("db_schema");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const DbError = error{
    SqliteOpen,
    SqliteExec,
    SqlitePrepare,
    SqliteStep,
    SqliteBind,
};

pub const SnapshotSummary = struct {
    id: i64,
    source: []u8,
    kind: []u8,
    target: []u8,
    status: []u8,
    summary: []u8,
    captured_at: []u8,

    pub fn deinit(self: SnapshotSummary, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.kind);
        allocator.free(self.target);
        allocator.free(self.status);
        allocator.free(self.summary);
        allocator.free(self.captured_at);
    }
};

pub const SnapshotSummaries = struct {
    items: []SnapshotSummary,

    pub fn deinit(self: *SnapshotSummaries, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const NameValueRow = struct {
    name: []u8,
    value: []u8,

    pub fn deinit(self: NameValueRow, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const NameValueRows = struct {
    items: []NameValueRow,

    pub fn deinit(self: *NameValueRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const InventoryFilter = struct {
    provider: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    query: ?[]const u8 = null,
    limit: i64 = 200,
};

pub const InventoryItem = struct {
    provider: []u8,
    kind: []u8,
    resource_id: []u8,
    scope: []u8,
    scope_id: []u8,
    display_name: []u8,
    status: []u8,
    category: []u8,
    domain: []u8,
    username: []u8,
    account_id: []u8,
    zone_id: []u8,
    related_id: []u8,
    flag: []u8,
    created_at_source: []u8,
    updated_at_source: []u8,
    expires_at_source: []u8,
    updated_at: []u8,

    pub fn deinit(self: InventoryItem, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.scope);
        allocator.free(self.scope_id);
        allocator.free(self.display_name);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.domain);
        allocator.free(self.username);
        allocator.free(self.account_id);
        allocator.free(self.zone_id);
        allocator.free(self.related_id);
        allocator.free(self.flag);
        allocator.free(self.created_at_source);
        allocator.free(self.updated_at_source);
        allocator.free(self.expires_at_source);
        allocator.free(self.updated_at);
    }
};

pub const InventoryItems = struct {
    items: []InventoryItem,

    pub fn deinit(self: *InventoryItems, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const InventoryFacet = struct {
    provider: []u8,
    kind: []u8,
    status: []u8,
    category: []u8,
    count: i64,
    domains: i64,
    latest_updated: []u8,

    pub fn deinit(self: InventoryFacet, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.latest_updated);
    }
};

pub const InventoryFacets = struct {
    items: []InventoryFacet,

    pub fn deinit(self: *InventoryFacets, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ProjectDetails = struct {
    name: []u8,
    source: []u8,
    path: []u8,
    host: []u8,
    upstream: []u8,
    service: []u8,
    container: []u8,

    pub fn deinit(self: ProjectDetails, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.source);
        allocator.free(self.path);
        allocator.free(self.host);
        allocator.free(self.upstream);
        allocator.free(self.service);
        allocator.free(self.container);
    }
};

pub const ProjectCorrelation = struct {
    project: []u8,
    source: []u8,
    path: []u8,
    host: []u8,
    caddy_source: []u8,
    upstream: []u8,
    socket_state: []u8,
    socket_process: []u8,
    service: []u8,
    service_state: []u8,
    container: []u8,
    container_status: []u8,

    pub fn deinit(self: ProjectCorrelation, allocator: Allocator) void {
        allocator.free(self.project);
        allocator.free(self.source);
        allocator.free(self.path);
        allocator.free(self.host);
        allocator.free(self.caddy_source);
        allocator.free(self.upstream);
        allocator.free(self.socket_state);
        allocator.free(self.socket_process);
        allocator.free(self.service);
        allocator.free(self.service_state);
        allocator.free(self.container);
        allocator.free(self.container_status);
    }
};

pub const ProjectCorrelations = struct {
    items: []ProjectCorrelation,

    pub fn deinit(self: *ProjectCorrelations, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const TopologyRow = struct {
    host: []u8,
    dns_name: []u8,
    dns_type: []u8,
    dns_content: []u8,
    dns_proxied: []u8,
    project: []u8,
    source: []u8,
    path: []u8,
    caddy_source: []u8,
    upstream: []u8,
    socket_state: []u8,
    socket_process: []u8,
    service: []u8,
    service_state: []u8,
    container: []u8,
    container_status: []u8,

    pub fn deinit(self: TopologyRow, allocator: Allocator) void {
        allocator.free(self.host);
        allocator.free(self.dns_name);
        allocator.free(self.dns_type);
        allocator.free(self.dns_content);
        allocator.free(self.dns_proxied);
        allocator.free(self.project);
        allocator.free(self.source);
        allocator.free(self.path);
        allocator.free(self.caddy_source);
        allocator.free(self.upstream);
        allocator.free(self.socket_state);
        allocator.free(self.socket_process);
        allocator.free(self.service);
        allocator.free(self.service_state);
        allocator.free(self.container);
        allocator.free(self.container_status);
    }
};

pub const TopologyRows = struct {
    items: []TopologyRow,

    pub fn deinit(self: *TopologyRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const SecretScanSurface = enum {
    settings_value,
    snapshots_target,
    snapshots_summary,
    snapshots_raw_json,
    snapshots_raw_text,
    provider_raw_endpoint,
    provider_raw_body_json,
    cloudflare_accounts_raw_json,
    cloudflare_zones_raw_json,
    cloudflare_dns_records_raw_json,
    cloudflare_resources_raw_json,
    cloudflare_inventory_items_raw_json,
    cloudflare_security_items_raw_json,
    hostinger_vps_raw_json,
    hostinger_metrics_raw_json,
    hostinger_resources_raw_json,
    hostinger_inventory_items_raw_json,
    caddy_sites_raw_block,
    projects_raw_text,
    services_raw_text,
    sockets_raw_text,
    containers_raw_text,
    audit_events_detail,

    pub fn label(self: SecretScanSurface) []const u8 {
        return switch (self) {
            .settings_value => "settings.value",
            .snapshots_target => "snapshots.target",
            .snapshots_summary => "snapshots.summary",
            .snapshots_raw_json => "snapshots.raw_json",
            .snapshots_raw_text => "snapshots.raw_text",
            .provider_raw_endpoint => "provider_raw.endpoint",
            .provider_raw_body_json => "provider_raw.body_json",
            .cloudflare_accounts_raw_json => "cloudflare_accounts.raw_json",
            .cloudflare_zones_raw_json => "cloudflare_zones.raw_json",
            .cloudflare_dns_records_raw_json => "cloudflare_dns_records.raw_json",
            .cloudflare_resources_raw_json => "cloudflare_resources.raw_json",
            .cloudflare_inventory_items_raw_json => "cloudflare_inventory_items.raw_json",
            .cloudflare_security_items_raw_json => "cloudflare_security_items.raw_json",
            .hostinger_vps_raw_json => "hostinger_vps.raw_json",
            .hostinger_metrics_raw_json => "hostinger_metrics.raw_json",
            .hostinger_resources_raw_json => "hostinger_resources.raw_json",
            .hostinger_inventory_items_raw_json => "hostinger_inventory_items.raw_json",
            .caddy_sites_raw_block => "caddy_sites.raw_block",
            .projects_raw_text => "projects.raw_text",
            .services_raw_text => "services.raw_text",
            .sockets_raw_text => "sockets.raw_text",
            .containers_raw_text => "containers.raw_text",
            .audit_events_detail => "audit_events.detail",
        };
    }
};

pub const secret_scan_surfaces = [_]SecretScanSurface{
    .settings_value,
    .snapshots_target,
    .snapshots_summary,
    .snapshots_raw_json,
    .snapshots_raw_text,
    .provider_raw_endpoint,
    .provider_raw_body_json,
    .cloudflare_accounts_raw_json,
    .cloudflare_zones_raw_json,
    .cloudflare_dns_records_raw_json,
    .cloudflare_resources_raw_json,
    .cloudflare_inventory_items_raw_json,
    .cloudflare_security_items_raw_json,
    .hostinger_vps_raw_json,
    .hostinger_metrics_raw_json,
    .hostinger_resources_raw_json,
    .hostinger_inventory_items_raw_json,
    .caddy_sites_raw_block,
    .projects_raw_text,
    .services_raw_text,
    .sockets_raw_text,
    .containers_raw_text,
    .audit_events_detail,
};

pub const MetricRow = struct {
    metric: []u8,
    value: []u8,
    unit: []u8,
    captured_at: []u8,

    pub fn deinit(self: MetricRow, allocator: Allocator) void {
        allocator.free(self.metric);
        allocator.free(self.value);
        allocator.free(self.unit);
        allocator.free(self.captured_at);
    }
};

pub const MetricRows = struct {
    items: []MetricRow,

    pub fn deinit(self: *MetricRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareAccountRow = struct {
    id: []u8,
    name: []u8,
    account_type: []u8,
    status: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareAccountRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.account_type);
        allocator.free(self.status);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareAccountRows = struct {
    items: []CloudflareAccountRow,

    pub fn deinit(self: *CloudflareAccountRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareZoneRow = struct {
    id: []u8,
    name: []u8,
    account_id: []u8,
    status: []u8,
    paused: []u8,
    zone_type: []u8,
    name_servers: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareZoneRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.account_id);
        allocator.free(self.status);
        allocator.free(self.paused);
        allocator.free(self.zone_type);
        allocator.free(self.name_servers);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareZoneRows = struct {
    items: []CloudflareZoneRow,

    pub fn deinit(self: *CloudflareZoneRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareDnsRecordRow = struct {
    id: []u8,
    zone_id: []u8,
    name: []u8,
    record_type: []u8,
    content: []u8,
    ttl: []u8,
    proxied: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareDnsRecordRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.zone_id);
        allocator.free(self.name);
        allocator.free(self.record_type);
        allocator.free(self.content);
        allocator.free(self.ttl);
        allocator.free(self.proxied);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareDnsRecordRows = struct {
    items: []CloudflareDnsRecordRow,

    pub fn deinit(self: *CloudflareDnsRecordRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ContainerRow = struct {
    name: []u8,
    image: []u8,
    status: []u8,
    ports: []u8,
    updated_at: []u8,

    pub fn deinit(self: ContainerRow, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        allocator.free(self.status);
        allocator.free(self.ports);
        allocator.free(self.updated_at);
    }
};

pub const ContainerRows = struct {
    items: []ContainerRow,

    pub fn deinit(self: *ContainerRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareKindCount = struct {
    kind: []u8,
    count: i64,
    latest_updated: []u8,

    pub fn deinit(self: CloudflareKindCount, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.latest_updated);
    }
};

pub const CloudflareKindCounts = struct {
    items: []CloudflareKindCount,

    pub fn deinit(self: *CloudflareKindCounts, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareResourceHintRow = struct {
    kind: []u8,
    resource_id: []u8,
    scope: []u8,
    scope_id: []u8,
    name: []u8,
    status: []u8,
    resource_type: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareResourceHintRow, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.scope);
        allocator.free(self.scope_id);
        allocator.free(self.name);
        allocator.free(self.status);
        allocator.free(self.resource_type);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareResourceHintRows = struct {
    items: []CloudflareResourceHintRow,

    pub fn deinit(self: *CloudflareResourceHintRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloudflareInventoryHintRow = struct {
    kind: []u8,
    resource_id: []u8,
    scope: []u8,
    scope_id: []u8,
    display_name: []u8,
    status: []u8,
    category: []u8,
    domain: []u8,
    account_id: []u8,
    zone_id: []u8,
    related_id: []u8,
    flag: []u8,
    updated_at: []u8,

    pub fn deinit(self: CloudflareInventoryHintRow, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.scope);
        allocator.free(self.scope_id);
        allocator.free(self.display_name);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.domain);
        allocator.free(self.account_id);
        allocator.free(self.zone_id);
        allocator.free(self.related_id);
        allocator.free(self.flag);
        allocator.free(self.updated_at);
    }
};

pub const CloudflareInventoryHintRows = struct {
    items: []CloudflareInventoryHintRow,

    pub fn deinit(self: *CloudflareInventoryHintRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerVpsRow = struct {
    id: []u8,
    name: []u8,
    status: []u8,
    ipv4: []u8,
    plan: []u8,
    updated_at: []u8,

    pub fn deinit(self: HostingerVpsRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.status);
        allocator.free(self.ipv4);
        allocator.free(self.plan);
        allocator.free(self.updated_at);
    }
};

pub const HostingerVpsRows = struct {
    items: []HostingerVpsRow,

    pub fn deinit(self: *HostingerVpsRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerResourceHintRow = struct {
    kind: []u8,
    resource_id: []u8,
    target: []u8,
    name: []u8,
    status: []u8,
    domain: []u8,
    updated_at: []u8,

    pub fn deinit(self: HostingerResourceHintRow, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.target);
        allocator.free(self.name);
        allocator.free(self.status);
        allocator.free(self.domain);
        allocator.free(self.updated_at);
    }
};

pub const HostingerResourceHintRows = struct {
    items: []HostingerResourceHintRow,

    pub fn deinit(self: *HostingerResourceHintRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerInventoryHintRow = struct {
    kind: []u8,
    resource_id: []u8,
    display_name: []u8,
    status: []u8,
    category: []u8,
    domain: []u8,
    username: []u8,
    related_id: []u8,
    flag: []u8,
    updated_at: []u8,

    pub fn deinit(self: HostingerInventoryHintRow, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        allocator.free(self.display_name);
        allocator.free(self.status);
        allocator.free(self.category);
        allocator.free(self.domain);
        allocator.free(self.username);
        allocator.free(self.related_id);
        allocator.free(self.flag);
        allocator.free(self.updated_at);
    }
};

pub const HostingerInventoryHintRows = struct {
    items: []HostingerInventoryHintRow,

    pub fn deinit(self: *HostingerInventoryHintRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerKindCount = struct {
    kind: []u8,
    count: i64,
    latest_updated: []u8,

    pub fn deinit(self: HostingerKindCount, allocator: Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.latest_updated);
    }
};

pub const HostingerKindCounts = struct {
    items: []HostingerKindCount,

    pub fn deinit(self: *HostingerKindCounts, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerMetricSummary = struct {
    vm_id: []u8,
    metric: []u8,
    count: i64,
    latest_captured: []u8,

    pub fn deinit(self: HostingerMetricSummary, allocator: Allocator) void {
        allocator.free(self.vm_id);
        allocator.free(self.metric);
        allocator.free(self.latest_captured);
    }
};

pub const HostingerMetricSummaries = struct {
    items: []HostingerMetricSummary,

    pub fn deinit(self: *HostingerMetricSummaries, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const HostingerVpsFamilySummary = struct {
    vm_id: []u8,
    source: []u8,
    kind: []u8,
    count: i64,
    latest_updated: []u8,

    pub fn deinit(self: HostingerVpsFamilySummary, allocator: Allocator) void {
        allocator.free(self.vm_id);
        allocator.free(self.source);
        allocator.free(self.kind);
        allocator.free(self.latest_updated);
    }
};

pub const HostingerVpsFamilySummaries = struct {
    items: []HostingerVpsFamilySummary,

    pub fn deinit(self: *HostingerVpsFamilySummaries, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AuditEvent = struct {
    id: i64,
    action: []u8,
    status: []u8,
    detail: []u8,
    created_at: []u8,

    pub fn deinit(self: AuditEvent, allocator: Allocator) void {
        allocator.free(self.action);
        allocator.free(self.status);
        allocator.free(self.detail);
        allocator.free(self.created_at);
    }
};

pub const AuditEvents = struct {
    items: []AuditEvent,

    pub fn deinit(self: *AuditEvents, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ProviderEvidenceFilter = struct {
    provider: ?[]const u8 = null,
    limit: i64 = 200,
};

pub const ProviderEvidenceEvent = struct {
    row_id: i64,
    source: []u8,
    provider: []u8,
    kind: []u8,
    target: []u8,
    status: []u8,
    detail: []u8,
    recorded_at: []u8,

    pub fn deinit(self: ProviderEvidenceEvent, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.target);
        allocator.free(self.status);
        allocator.free(self.detail);
        allocator.free(self.recorded_at);
    }
};

pub const ProviderEvidenceEvents = struct {
    items: []ProviderEvidenceEvent,

    pub fn deinit(self: *ProviderEvidenceEvents, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ProviderEvidenceSummaryRow = struct {
    source: []u8,
    provider: []u8,
    kind: []u8,
    status: []u8,
    count: i64,
    latest_at: []u8,

    pub fn deinit(self: ProviderEvidenceSummaryRow, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.provider);
        allocator.free(self.kind);
        allocator.free(self.status);
        allocator.free(self.latest_at);
    }
};

pub const ProviderEvidenceSummaryRows = struct {
    items: []ProviderEvidenceSummaryRow,

    pub fn deinit(self: *ProviderEvidenceSummaryRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const RouteCaptureEvidenceFilter = struct {
    provider: ?[]const u8 = null,
    limit: i64 = 200,
};

pub const RouteCaptureEvidenceRow = struct {
    provider: []u8,
    operation_id: []u8,
    status: []u8,
    endpoint_sample: []u8,
    count: i64,
    latest_at: []u8,

    pub fn deinit(self: RouteCaptureEvidenceRow, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.operation_id);
        allocator.free(self.status);
        allocator.free(self.endpoint_sample);
        allocator.free(self.latest_at);
    }
};

pub const RouteCaptureEvidenceRows = struct {
    items: []RouteCaptureEvidenceRow,

    pub fn deinit(self: *RouteCaptureEvidenceRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const RouteSourceEvidenceRow = struct {
    provider: []u8,
    operation_id: []u8,
    status: []u8,
    target: []u8,
    summary: []u8,
    raw_json: []u8,
    captured_at: []u8,

    pub fn deinit(self: RouteSourceEvidenceRow, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.operation_id);
        allocator.free(self.status);
        allocator.free(self.target);
        allocator.free(self.summary);
        allocator.free(self.raw_json);
        allocator.free(self.captured_at);
    }
};

pub const RouteSourceEvidenceRows = struct {
    items: []RouteSourceEvidenceRow,

    pub fn deinit(self: *RouteSourceEvidenceRows, allocator: Allocator) void {
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const Db = struct {
    handle: *sqlite.sqlite3,

    pub fn open(io: Io, path: []const u8) !Db {
        try core_fs.ensureParentDir(io, path);
        if (path.len >= std.fs.max_path_bytes) return error.NameTooLong;
        var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var handle: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open_v2(@ptrCast(&path_z), &handle, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqliteOpen;
        _ = sqlite.sqlite3_busy_timeout(handle.?, 5000);
        return .{ .handle = handle.? };
    }

    pub fn close(self: *Db) void {
        _ = sqlite.sqlite3_close(self.handle);
    }

    pub fn initSchema(self: *Db) !void {
        try db_schema.apply(self.handle);
    }

    pub fn schemaVersion(self: *Db) !i64 {
        return try db_schema.latestAppliedVersion(self.handle);
    }

    pub fn exec(self: *Db, sql: []const u8) !void {
        var err: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err);
        if (rc != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return DbError.SqliteExec;
        }
    }

    pub fn prepare(self: *Db, sql: []const u8) !*sqlite.sqlite3_stmt {
        var stmt: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(self.handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqlitePrepare;
        return stmt.?;
    }

    pub fn insertSnapshot(self: *Db, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
        const stmt = try self.prepare(
            \\INSERT INTO snapshots(source, kind, target, status, summary, raw_json, raw_text)
            \\VALUES (?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindText(stmt, 2, kind);
        try bindTextOpt(stmt, 3, target);
        try bindText(stmt, 4, status);
        try bindTextOpt(stmt, 5, summary);
        try bindTextOpt(stmt, 6, raw_json);
        try bindTextOpt(stmt, 7, raw_text);
        try stepDone(stmt);
        return sqlite.sqlite3_last_insert_rowid(self.handle);
    }

    pub fn insertProviderRaw(self: *Db, provider: []const u8, endpoint: []const u8, status: i64, body: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO provider_raw(provider, endpoint, status, body_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, provider);
        try bindText(stmt, 2, endpoint);
        try bindI64(stmt, 3, status);
        try bindText(stmt, 4, body);
        try stepDone(stmt);
    }

    pub fn insertAudit(self: *Db, action: []const u8, status: []const u8, detail: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO audit_events(action, status, detail) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, action);
        try bindText(stmt, 2, status);
        try bindText(stmt, 3, detail);
        try stepDone(stmt);
    }

    pub fn clear(self: *Db, table: []const u8) !void {
        if (!isKnownTable(table)) return error.InvalidTable;
        var buf: [128]u8 = undefined;
        const sql = try std.fmt.bufPrint(&buf, "DELETE FROM {s}", .{table});
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try stepDone(stmt);
    }

    pub fn countTable(self: *Db, table: []const u8) !i64 {
        if (!isKnownTable(table)) return error.InvalidTable;
        var buf: [160]u8 = undefined;
        const sql = try std.fmt.bufPrint(&buf, "SELECT COUNT(*) FROM {s}", .{table});
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn countSecretNeedle(self: *Db, surface: SecretScanSurface, needle: []const u8) !i64 {
        if (needle.len == 0) return 0;
        const stmt = try self.prepare(secretScanSql(surface));
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, needle);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn latestSnapshotId(self: *Db) !i64 {
        const stmt = try self.prepare("SELECT COALESCE(MAX(id), 0) FROM snapshots");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return DbError.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn upsertCloudflareAccount(self: *Db, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_accounts(id, name, type, status, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, type=excluded.type, status=excluded.status, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, typ);
        try bindTextOpt(stmt, 4, status);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareZone(self: *Db, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_zones(id, name, account_id, status, paused, type, name_servers, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, account_id=excluded.account_id, status=excluded.status, paused=excluded.paused, type=excluded.type, name_servers=excluded.name_servers, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, account_id);
        try bindTextOpt(stmt, 4, status);
        try bindBoolOpt(stmt, 5, paused);
        try bindTextOpt(stmt, 6, typ);
        try bindTextOpt(stmt, 7, name_servers);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertDnsRecord(self: *Db, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_dns_records(id, zone_id, name, type, content, ttl, proxied, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET zone_id=excluded.zone_id, name=excluded.name, type=excluded.type, content=excluded.content, ttl=excluded.ttl, proxied=excluded.proxied, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindText(stmt, 2, zone_id);
        try bindTextOpt(stmt, 3, name);
        try bindTextOpt(stmt, 4, typ);
        try bindTextOpt(stmt, 5, content);
        try bindI64Opt(stmt, 6, ttl);
        try bindBoolOpt(stmt, 7, proxied);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, name: ?[]const u8, status: ?[]const u8, resource_type: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_resources(key, kind, resource_id, scope, scope_id, name, status, resource_type, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, name=excluded.name, status=excluded.status, resource_type=excluded.resource_type, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, resource_type);
        try bindText(stmt, 9, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareInventoryItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        scope: ?[]const u8,
        scope_id: ?[]const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        domain: ?[]const u8,
        account_id: ?[]const u8,
        zone_id: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_inventory_items(key, kind, resource_id, scope, scope_id, display_name, status, category, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, domain=excluded.domain, account_id=excluded.account_id, zone_id=excluded.zone_id, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, display_name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, category);
        try bindTextOpt(stmt, 9, domain);
        try bindTextOpt(stmt, 10, account_id);
        try bindTextOpt(stmt, 11, zone_id);
        try bindTextOpt(stmt, 12, related_id);
        try bindTextOpt(stmt, 13, flag);
        try bindTextOpt(stmt, 14, created_at_source);
        try bindTextOpt(stmt, 15, updated_at_source);
        try bindTextOpt(stmt, 16, expires_at_source);
        try bindText(stmt, 17, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareSecurityItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        scope: ?[]const u8,
        scope_id: ?[]const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        severity: ?[]const u8,
        action: ?[]const u8,
        domain: ?[]const u8,
        account_id: ?[]const u8,
        zone_id: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_security_items(key, kind, resource_id, scope, scope_id, display_name, status, category, severity, action, domain, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, scope=excluded.scope, scope_id=excluded.scope_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, severity=excluded.severity, action=excluded.action, domain=excluded.domain, account_id=excluded.account_id, zone_id=excluded.zone_id, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, scope);
        try bindTextOpt(stmt, 5, scope_id);
        try bindTextOpt(stmt, 6, display_name);
        try bindTextOpt(stmt, 7, status);
        try bindTextOpt(stmt, 8, category);
        try bindTextOpt(stmt, 9, severity);
        try bindTextOpt(stmt, 10, action);
        try bindTextOpt(stmt, 11, domain);
        try bindTextOpt(stmt, 12, account_id);
        try bindTextOpt(stmt, 13, zone_id);
        try bindTextOpt(stmt, 14, related_id);
        try bindTextOpt(stmt, 15, flag);
        try bindTextOpt(stmt, 16, created_at_source);
        try bindTextOpt(stmt, 17, updated_at_source);
        try bindTextOpt(stmt, 18, expires_at_source);
        try bindText(stmt, 19, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerVps(self: *Db, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_vps(id, name, status, ipv4, plan, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, status=excluded.status, ipv4=excluded.ipv4, plan=excluded.plan, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, status);
        try bindTextOpt(stmt, 4, ipv4);
        try bindTextOpt(stmt, 5, plan);
        try bindText(stmt, 6, raw);
        try stepDone(stmt);
    }

    pub fn insertHostingerMetric(self: *Db, vm_id: []const u8, metric: []const u8, value: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO hostinger_metrics(vm_id, metric, value, raw_json) VALUES (?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, vm_id);
        try bindText(stmt, 2, metric);
        try bindTextOpt(stmt, 3, value);
        try bindText(stmt, 4, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerResource(self: *Db, key: []const u8, kind: []const u8, resource_id: []const u8, target: ?[]const u8, name: ?[]const u8, status: ?[]const u8, domain: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_resources(key, kind, resource_id, target, name, status, domain, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, target=excluded.target, name=excluded.name, status=excluded.status, domain=excluded.domain, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, target);
        try bindTextOpt(stmt, 5, name);
        try bindTextOpt(stmt, 6, status);
        try bindTextOpt(stmt, 7, domain);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertHostingerInventoryItem(
        self: *Db,
        key: []const u8,
        kind: []const u8,
        resource_id: []const u8,
        display_name: ?[]const u8,
        status: ?[]const u8,
        category: ?[]const u8,
        domain: ?[]const u8,
        username: ?[]const u8,
        related_id: ?[]const u8,
        flag: ?[]const u8,
        created_at_source: ?[]const u8,
        updated_at_source: ?[]const u8,
        expires_at_source: ?[]const u8,
        raw: []const u8,
    ) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_inventory_items(key, kind, resource_id, display_name, status, category, domain, username, related_id, flag, created_at_source, updated_at_source, expires_at_source, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(key) DO UPDATE SET kind=excluded.kind, resource_id=excluded.resource_id, display_name=excluded.display_name, status=excluded.status, category=excluded.category, domain=excluded.domain, username=excluded.username, related_id=excluded.related_id, flag=excluded.flag, created_at_source=excluded.created_at_source, updated_at_source=excluded.updated_at_source, expires_at_source=excluded.expires_at_source, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, key);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, resource_id);
        try bindTextOpt(stmt, 4, display_name);
        try bindTextOpt(stmt, 5, status);
        try bindTextOpt(stmt, 6, category);
        try bindTextOpt(stmt, 7, domain);
        try bindTextOpt(stmt, 8, username);
        try bindTextOpt(stmt, 9, related_id);
        try bindTextOpt(stmt, 10, flag);
        try bindTextOpt(stmt, 11, created_at_source);
        try bindTextOpt(stmt, 12, updated_at_source);
        try bindTextOpt(stmt, 13, expires_at_source);
        try bindText(stmt, 14, raw);
        try stepDone(stmt);
    }

    pub fn upsertCaddySite(self: *Db, host: []const u8, source_path: []const u8, raw_block: ?[]const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO caddy_sites(host, source_path, raw_block, updated_at)
            \\VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(host) DO UPDATE SET source_path=excluded.source_path, raw_block=excluded.raw_block, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, host);
        try bindText(stmt, 2, source_path);
        try bindTextOpt(stmt, 3, raw_block);
        try stepDone(stmt);
    }

    pub fn insertCaddyUpstream(self: *Db, host: []const u8, route: []const u8, upstream: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO caddy_upstreams(host, route, upstream) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, host);
        try bindText(stmt, 2, route);
        try bindText(stmt, 3, upstream);
        try stepDone(stmt);
    }

    pub fn upsertProject(self: *Db, name: []const u8, source: []const u8, path: ?[]const u8, host: ?[]const u8, upstream: ?[]const u8, service: ?[]const u8, container: ?[]const u8, raw: ?[]const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO projects(name, source, path, host, upstream, service, container, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET source=excluded.source, path=excluded.path, host=excluded.host, upstream=excluded.upstream, service=excluded.service, container=excluded.container, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindText(stmt, 2, source);
        try bindTextOpt(stmt, 3, path);
        try bindTextOpt(stmt, 4, host);
        try bindTextOpt(stmt, 5, upstream);
        try bindTextOpt(stmt, 6, service);
        try bindTextOpt(stmt, 7, container);
        try bindTextOpt(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn insertSystemMetric(self: *Db, metric: []const u8, value: []const u8, unit: ?[]const u8) !void {
        const stmt = try self.prepare("INSERT INTO system_metrics(metric, value, unit) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, metric);
        try bindText(stmt, 2, value);
        try bindTextOpt(stmt, 3, unit);
        try stepDone(stmt);
    }

    pub fn upsertService(self: *Db, name: []const u8, scope: []const u8, state: ?[]const u8, sub_state: ?[]const u8, description: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO services(name, scope, state, sub_state, description, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET scope=excluded.scope, state=excluded.state, sub_state=excluded.sub_state, description=excluded.description, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindText(stmt, 2, scope);
        try bindTextOpt(stmt, 3, state);
        try bindTextOpt(stmt, 4, sub_state);
        try bindTextOpt(stmt, 5, description);
        try bindText(stmt, 6, raw);
        try stepDone(stmt);
    }

    pub fn insertSocket(self: *Db, proto: ?[]const u8, state: ?[]const u8, local_address: ?[]const u8, process: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO sockets(proto, state, local_address, process, raw_text) VALUES (?, ?, ?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, proto);
        try bindTextOpt(stmt, 2, state);
        try bindTextOpt(stmt, 3, local_address);
        try bindTextOpt(stmt, 4, process);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertContainer(self: *Db, name: []const u8, image: ?[]const u8, status: ?[]const u8, ports: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO containers(name, image, status, ports, raw_text, updated_at)
            \\VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(name) DO UPDATE SET image=excluded.image, status=excluded.status, ports=excluded.ports, raw_text=excluded.raw_text, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        try bindTextOpt(stmt, 2, image);
        try bindTextOpt(stmt, 3, status);
        try bindTextOpt(stmt, 4, ports);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn writeOverviewCounts(self: *Db, writer: anytype) !void {
        try writer.print("snapshots={d}\n", .{try self.countTable("snapshots")});
        try writer.print("cloudflare_accounts={d}\n", .{try self.countTable("cloudflare_accounts")});
        try writer.print("cloudflare_zones={d}\n", .{try self.countTable("cloudflare_zones")});
        try writer.print("cloudflare_dns_records={d}\n", .{try self.countTable("cloudflare_dns_records")});
        try writer.print("cloudflare_resources={d}\n", .{try self.countTable("cloudflare_resources")});
        try writer.print("cloudflare_inventory_items={d}\n", .{try self.countTable("cloudflare_inventory_items")});
        try writer.print("cloudflare_security_items={d}\n", .{try self.countTable("cloudflare_security_items")});
        try writer.print("hostinger_vps={d}\n", .{try self.countTable("hostinger_vps")});
        try writer.print("hostinger_resources={d}\n", .{try self.countTable("hostinger_resources")});
        try writer.print("hostinger_inventory_items={d}\n", .{try self.countTable("hostinger_inventory_items")});
        try writer.print("caddy_sites={d}\n", .{try self.countTable("caddy_sites")});
        try writer.print("caddy_upstreams={d}\n", .{try self.countTable("caddy_upstreams")});
        try writer.print("projects={d}\n", .{try self.countTable("projects")});
        try writer.print("services={d}\n", .{try self.countTable("services")});
        try writer.print("sockets={d}\n", .{try self.countTable("sockets")});
        try writer.print("containers={d}\n", .{try self.countTable("containers")});
    }

    pub fn recentSnapshots(self: *Db, gpa: Allocator, limit: i64) !SnapshotSummaries {
        const stmt = try self.prepare(
            \\SELECT id, source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(SnapshotSummary).empty;
        errdefer deinitSnapshotList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try snapshotSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn snapshotsForSource(self: *Db, gpa: Allocator, source: []const u8, limit: i64) !SnapshotSummaries {
        const stmt = try self.prepare(
            \\SELECT id, source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots WHERE source = ? ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindI64(stmt, 2, limit);
        return try self.snapshotRowsFromStmt(gpa, stmt);
    }

    pub fn projectList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT name, source FROM projects ORDER BY name LIMIT 200");
    }

    pub fn projectCorrelations(self: *Db, gpa: Allocator, limit: i64) !ProjectCorrelations {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT DISTINCT p.name AS project,
            \\         p.source AS source,
            \\         COALESCE(p.path, '') AS path,
            \\         COALESCE(NULLIF(p.host, ''), cu.host, '') AS host,
            \\         COALESCE(NULLIF(cu.upstream, ''), p.upstream, '') AS upstream,
            \\         COALESCE(p.service, '') AS service,
            \\         COALESCE(p.container, '') AS container
            \\  FROM projects p
            \\  LEFT JOIN caddy_upstreams cu
            \\    ON (p.host IS NOT NULL AND p.host != '' AND cu.host = p.host)
            \\    OR (p.upstream IS NOT NULL AND p.upstream != '' AND cu.upstream = p.upstream)
            \\  UNION ALL
            \\  SELECT DISTINCT '' AS project,
            \\         'caddy' AS source,
            \\         '' AS path,
            \\         cu.host AS host,
            \\         cu.upstream AS upstream,
            \\         '' AS service,
            \\         '' AS container
            \\  FROM caddy_upstreams cu
            \\  WHERE NOT EXISTS (
            \\    SELECT 1 FROM projects p
            \\    WHERE (p.host IS NOT NULL AND p.host != '' AND p.host = cu.host)
            \\       OR (p.upstream IS NOT NULL AND p.upstream != '' AND p.upstream = cu.upstream)
            \\  )
            \\)
            \\SELECT rows.project,
            \\       rows.source,
            \\       rows.path,
            \\       rows.host,
            \\       COALESCE(cs.source_path, '') AS caddy_source,
            \\       rows.upstream,
            \\       COALESCE(sock.state, '') AS socket_state,
            \\       COALESCE(sock.process, '') AS socket_process,
            \\       rows.service,
            \\       COALESCE(svc.state, '') AS service_state,
            \\       rows.container,
            \\       COALESCE(ct.status, '') AS container_status
            \\FROM rows
            \\LEFT JOIN caddy_sites cs ON cs.host = rows.host
            \\LEFT JOIN sockets sock
            \\  ON rows.upstream != ''
            \\ AND (sock.local_address = rows.upstream OR rows.upstream LIKE '%' || sock.local_address)
            \\LEFT JOIN services svc
            \\  ON rows.service != ''
            \\ AND svc.name = rows.service
            \\LEFT JOIN containers ct
            \\  ON rows.container != ''
            \\ AND ct.name = rows.container
            \\ORDER BY rows.project = '', rows.project, rows.host, rows.upstream
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(ProjectCorrelation).empty;
        errdefer deinitProjectCorrelationList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try projectCorrelationFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn topologyRows(self: *Db, gpa: Allocator, limit: i64) !TopologyRows {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT DISTINCT p.name AS project,
            \\         p.source AS source,
            \\         COALESCE(p.path, '') AS path,
            \\         COALESCE(NULLIF(p.host, ''), cu.host, '') AS host,
            \\         COALESCE(NULLIF(cu.upstream, ''), p.upstream, '') AS upstream,
            \\         COALESCE(p.service, '') AS service,
            \\         COALESCE(p.container, '') AS container
            \\  FROM projects p
            \\  LEFT JOIN caddy_upstreams cu
            \\    ON (p.host IS NOT NULL AND p.host != '' AND cu.host = p.host)
            \\    OR (p.upstream IS NOT NULL AND p.upstream != '' AND cu.upstream = p.upstream)
            \\  UNION ALL
            \\  SELECT DISTINCT '' AS project,
            \\         'caddy' AS source,
            \\         '' AS path,
            \\         cu.host AS host,
            \\         cu.upstream AS upstream,
            \\         '' AS service,
            \\         '' AS container
            \\  FROM caddy_upstreams cu
            \\  WHERE NOT EXISTS (
            \\    SELECT 1 FROM projects p
            \\    WHERE (p.host IS NOT NULL AND p.host != '' AND p.host = cu.host)
            \\       OR (p.upstream IS NOT NULL AND p.upstream != '' AND p.upstream = cu.upstream)
            \\  )
            \\),
            \\local_rows AS (
            \\  SELECT rows.project,
            \\         rows.source,
            \\         rows.path,
            \\         rows.host,
            \\         COALESCE(cs.source_path, '') AS caddy_source,
            \\         rows.upstream,
            \\         COALESCE(sock.state, '') AS socket_state,
            \\         COALESCE(sock.process, '') AS socket_process,
            \\         rows.service,
            \\         COALESCE(svc.state, '') AS service_state,
            \\         rows.container,
            \\         COALESCE(ct.status, '') AS container_status
            \\  FROM rows
            \\  LEFT JOIN caddy_sites cs ON cs.host = rows.host
            \\  LEFT JOIN sockets sock
            \\    ON rows.upstream != ''
            \\   AND (sock.local_address = rows.upstream OR rows.upstream LIKE '%' || sock.local_address)
            \\  LEFT JOIN services svc
            \\    ON rows.service != ''
            \\   AND svc.name = rows.service
            \\  LEFT JOIN containers ct
            \\    ON rows.container != ''
            \\   AND ct.name = rows.container
            \\),
            \\dns_local_target AS (
            \\  SELECT dns.id,
            \\         dns.name,
            \\         dns.type,
            \\         dns.content,
            \\         dns.proxied
            \\  FROM cloudflare_dns_records dns
            \\  WHERE dns.name IS NOT NULL
            \\    AND dns.name != ''
            \\    AND upper(COALESCE(dns.type, '')) IN ('A', 'AAAA')
            \\    AND NOT EXISTS (
            \\      SELECT 1 FROM cloudflare_dns_records better
            \\      WHERE better.name = dns.name
            \\        AND upper(COALESCE(better.type, '')) IN ('A', 'AAAA')
            \\        AND (
            \\          CASE upper(COALESCE(better.type, '')) WHEN 'A' THEN 0 ELSE 1 END <
            \\          CASE upper(COALESCE(dns.type, '')) WHEN 'A' THEN 0 ELSE 1 END
            \\          OR (
            \\            CASE upper(COALESCE(better.type, '')) WHEN 'A' THEN 0 ELSE 1 END =
            \\            CASE upper(COALESCE(dns.type, '')) WHEN 'A' THEN 0 ELSE 1 END
            \\            AND better.id < dns.id
            \\          )
            \\        )
            \\    )
            \\),
            \\combined AS (
            \\  SELECT COALESCE(NULLIF(local_rows.host, ''), direct_dns.name, wildcard_dns.name, '') AS host,
            \\         COALESCE(direct_dns.name, wildcard_dns.name, '') AS dns_name,
            \\         COALESCE(direct_dns.type, wildcard_dns.type, '') AS dns_type,
            \\         COALESCE(direct_dns.content, wildcard_dns.content, '') AS dns_content,
            \\         CASE
            \\           WHEN COALESCE(direct_dns.proxied, wildcard_dns.proxied) IS NULL THEN ''
            \\           WHEN COALESCE(direct_dns.proxied, wildcard_dns.proxied) != 0 THEN 'true'
            \\           ELSE 'false'
            \\         END AS dns_proxied,
            \\         local_rows.project,
            \\         local_rows.source,
            \\         local_rows.path,
            \\         local_rows.caddy_source,
            \\         local_rows.upstream,
            \\         local_rows.socket_state,
            \\         local_rows.socket_process,
            \\         local_rows.service,
            \\         local_rows.service_state,
            \\         local_rows.container,
            \\         local_rows.container_status
            \\  FROM local_rows
            \\  LEFT JOIN dns_local_target direct_dns
            \\    ON direct_dns.name = local_rows.host
            \\  LEFT JOIN dns_local_target wildcard_dns
            \\    ON direct_dns.name IS NULL
            \\   AND wildcard_dns.name LIKE '*.%'
            \\   AND local_rows.host LIKE '%' || substr(wildcard_dns.name, 2)
            \\  UNION ALL
            \\  SELECT dns.name AS host,
            \\         dns.name AS dns_name,
            \\         COALESCE(dns.type, '') AS dns_type,
            \\         COALESCE(dns.content, '') AS dns_content,
            \\         CASE WHEN dns.proxied IS NULL THEN '' WHEN dns.proxied != 0 THEN 'true' ELSE 'false' END AS dns_proxied,
            \\         '' AS project,
            \\         'cloudflare' AS source,
            \\         '' AS path,
            \\         '' AS caddy_source,
            \\         '' AS upstream,
            \\         '' AS socket_state,
            \\         '' AS socket_process,
            \\         '' AS service,
            \\         '' AS service_state,
            \\         '' AS container,
            \\         '' AS container_status
            \\  FROM dns_local_target dns
            \\  WHERE dns.name IS NOT NULL
            \\    AND dns.name != ''
            \\    AND NOT EXISTS (
            \\      SELECT 1 FROM local_rows
            \\      WHERE dns.name = local_rows.host
            \\         OR (dns.name LIKE '*.%' AND local_rows.host LIKE '%' || substr(dns.name, 2))
            \\    )
            \\)
            \\SELECT * FROM combined
            \\ORDER BY project = '', project, host, dns_type, upstream
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(TopologyRow).empty;
        errdefer deinitTopologyRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try topologyRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn serviceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(state,'') FROM services ORDER BY 1 LIMIT 200");
    }

    pub fn socketList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(local_address,''), COALESCE(process,'') FROM sockets ORDER BY 1 LIMIT 200");
    }

    pub fn containerRows(self: *Db, gpa: Allocator, limit: i64) !ContainerRows {
        const stmt = try self.prepare(
            \\SELECT COALESCE(name,''), COALESCE(image,''), COALESCE(status,''), COALESCE(ports,''), updated_at
            \\FROM containers
            \\ORDER BY name
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(ContainerRow).empty;
        errdefer {
            for (rows.items) |row| row.deinit(gpa);
            rows.deinit(gpa);
        }
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = ContainerRow{
                .name = try dupeColumn(gpa, stmt, 0),
                .image = try dupeColumn(gpa, stmt, 1),
                .status = try dupeColumn(gpa, stmt, 2),
                .ports = try dupeColumn(gpa, stmt, 3),
                .updated_at = try dupeColumn(gpa, stmt, 4),
            };
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn containerList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT COALESCE(name,''), COALESCE(status,'') FROM containers ORDER BY 1 LIMIT 200");
    }

    pub fn cloudflareResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(resource_type,'') || ' ' || COALESCE(name,''))
            \\FROM cloudflare_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn cloudflareInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(scope,'') || ' ' || COALESCE(scope_id,'') || ' ' || COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM cloudflare_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn cloudflareAccountRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareAccountRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(type,''), COALESCE(status,''), updated_at
            \\FROM cloudflare_accounts
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareAccountRow).empty;
        errdefer deinitCloudflareAccountRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareAccountRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareZoneRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareZoneRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(account_id,''), COALESCE(status,''),
            \\       CASE WHEN paused IS NULL THEN '' WHEN paused != 0 THEN 'true' ELSE 'false' END,
            \\       COALESCE(type,''), COALESCE(name_servers,''), updated_at
            \\FROM cloudflare_zones
            \\ORDER BY updated_at DESC, name, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareZoneRow).empty;
        errdefer deinitCloudflareZoneRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareZoneRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareDnsRecordRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(zone_id,''), COALESCE(name,''), COALESCE(type,''), COALESCE(content,''),
            \\       COALESCE(CAST(ttl AS TEXT), ''),
            \\       CASE WHEN proxied IS NULL THEN '' WHEN proxied != 0 THEN 'true' ELSE 'false' END,
            \\       updated_at
            \\FROM cloudflare_dns_records
            \\ORDER BY updated_at DESC, name, type, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareDnsRecordRow).empty;
        errdefer deinitCloudflareDnsRecordRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareDnsRecordRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareResourceHints(self: *Db, gpa: Allocator, limit: i64) !CloudflareResourceHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(scope,''), COALESCE(scope_id,''), COALESCE(name,''), COALESCE(status,''), COALESCE(resource_type,''), updated_at
            \\FROM cloudflare_resources
            \\WHERE resource_id != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(CloudflareResourceHintRow).empty;
        errdefer deinitCloudflareResourceHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareResourceHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareInventoryHints(self: *Db, gpa: Allocator, limit: i64) !CloudflareInventoryHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(scope,''), COALESCE(scope_id,''), COALESCE(display_name,''), COALESCE(status,''), COALESCE(category,''), COALESCE(domain,''), COALESCE(account_id,''), COALESCE(zone_id,''), COALESCE(related_id,''), COALESCE(flag,''), COALESCE(updated_at_source, updated_at)
            \\FROM cloudflare_inventory_items
            \\WHERE resource_id != '' OR COALESCE(scope_id,'') != '' OR COALESCE(domain,'') != '' OR COALESCE(account_id,'') != '' OR COALESCE(zone_id,'') != '' OR COALESCE(related_id,'') != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(CloudflareInventoryHintRow).empty;
        errdefer deinitCloudflareInventoryHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareInventoryHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn cloudflareSecurityKindCounts(self: *Db, gpa: Allocator, limit: i64) !CloudflareKindCounts {
        return try self.cloudflareKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM cloudflare_security_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerResourceList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(name,''))
            \\FROM hostinger_resources
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerInventoryItemList(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa,
            \\SELECT kind || '/' || resource_id,
            \\       trim(COALESCE(status,'') || ' ' || COALESCE(flag,'') || ' ' || COALESCE(category,'') || ' ' || COALESCE(domain,'') || ' ' || COALESCE(username,'') || ' ' || COALESCE(display_name,'') || ' ' || COALESCE(related_id,''))
            \\FROM hostinger_inventory_items
            \\ORDER BY updated_at DESC, kind, resource_id
            \\LIMIT 200
        );
    }

    pub fn hostingerVpsRows(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(status,''), COALESCE(ipv4,''), COALESCE(plan,''), updated_at
            \\FROM hostinger_vps
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerVpsRow).empty;
        errdefer deinitHostingerVpsRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerVpsRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerResourceHints(self: *Db, gpa: Allocator, limit: i64) !HostingerResourceHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(target,''), COALESCE(name,''), COALESCE(status,''), COALESCE(domain,''), updated_at
            \\FROM hostinger_resources
            \\WHERE resource_id != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(HostingerResourceHintRow).empty;
        errdefer deinitHostingerResourceHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerResourceHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerInventoryHints(self: *Db, gpa: Allocator, limit: i64) !HostingerInventoryHintRows {
        const stmt = try self.prepare(
            \\SELECT kind, resource_id, COALESCE(display_name,''), COALESCE(status,''), COALESCE(category,''), COALESCE(domain,''), COALESCE(username,''), COALESCE(related_id,''), COALESCE(flag,''), updated_at
            \\FROM hostinger_inventory_items
            \\WHERE resource_id != '' OR COALESCE(domain,'') != '' OR COALESCE(username,'') != '' OR COALESCE(related_id,'') != ''
            \\ORDER BY updated_at DESC, kind, resource_id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 5000));
        var rows = std.ArrayList(HostingerInventoryHintRow).empty;
        errdefer deinitHostingerInventoryHintRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerInventoryHintRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerResourceKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_resources
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerInventoryKindCounts(self: *Db, gpa: Allocator, limit: i64) !HostingerKindCounts {
        return try self.hostingerKindCounts(gpa,
            \\SELECT kind, COUNT(*) AS item_count, COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM hostinger_inventory_items
            \\GROUP BY kind
            \\ORDER BY item_count DESC, kind
            \\LIMIT ?
        , limit);
    }

    pub fn hostingerMetricSummaries(self: *Db, gpa: Allocator, limit: i64) !HostingerMetricSummaries {
        const stmt = try self.prepare(
            \\SELECT COALESCE(vm_id,''), metric, COUNT(*) AS sample_count, COALESCE(MAX(captured_at), '') AS latest_captured
            \\FROM hostinger_metrics
            \\GROUP BY vm_id, metric
            \\ORDER BY latest_captured DESC, vm_id, metric
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerMetricSummary).empty;
        errdefer deinitHostingerMetricSummaryList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerMetricSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn hostingerVpsFamilySummaries(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsFamilySummaries {
        const stmt = try self.prepare(
            \\WITH rows AS (
            \\  SELECT v.id AS vm_id,
            \\         'resource' AS source,
            \\         r.kind AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(r.updated_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_resources r
            \\    ON r.target = v.id OR r.target LIKE v.id || '/%'
            \\  GROUP BY v.id, r.kind
            \\  UNION ALL
            \\  SELECT v.id AS vm_id,
            \\         'inventory' AS source,
            \\         i.kind AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(i.updated_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_inventory_items i
            \\    ON i.key LIKE i.kind || '|' || v.id || '|%'
            \\    OR i.key LIKE i.kind || '|' || v.id || '/%'
            \\  GROUP BY v.id, i.kind
            \\  UNION ALL
            \\  SELECT v.id AS vm_id,
            \\         'metric' AS source,
            \\         m.metric AS kind,
            \\         COUNT(*) AS item_count,
            \\         COALESCE(MAX(m.captured_at), '') AS latest_updated
            \\  FROM hostinger_vps v
            \\  JOIN hostinger_metrics m ON m.vm_id = v.id
            \\  GROUP BY v.id, m.metric
            \\)
            \\SELECT vm_id, source, kind, item_count, latest_updated
            \\FROM rows
            \\ORDER BY vm_id, source, kind
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerVpsFamilySummary).empty;
        errdefer deinitHostingerVpsFamilySummaryList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerVpsFamilySummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn inventoryItems(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryItems {
        const stmt = try self.prepare(
            \\SELECT provider, kind, resource_id, scope, scope_id, display_name, status, category, domain, username, account_id, zone_id, related_id, flag, created_at_source, updated_at_source, expires_at_source, updated_at
            \\FROM (
            \\  SELECT 'cloudflare' AS provider,
            \\         kind,
            \\         resource_id,
            \\         COALESCE(scope, '') AS scope,
            \\         COALESCE(scope_id, '') AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         '' AS username,
            \\         COALESCE(account_id, '') AS account_id,
            \\         COALESCE(zone_id, '') AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         COALESCE(created_at_source, '') AS created_at_source,
            \\         COALESCE(updated_at_source, '') AS updated_at_source,
            \\         COALESCE(expires_at_source, '') AS expires_at_source,
            \\         updated_at
            \\  FROM cloudflare_inventory_items
            \\  UNION ALL
            \\  SELECT 'hostinger' AS provider,
            \\         kind,
            \\         resource_id,
            \\         '' AS scope,
            \\         '' AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         COALESCE(username, '') AS username,
            \\         '' AS account_id,
            \\         '' AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         COALESCE(created_at_source, '') AS created_at_source,
            \\         COALESCE(updated_at_source, '') AS updated_at_source,
            \\         COALESCE(expires_at_source, '') AS expires_at_source,
            \\         updated_at
            \\  FROM hostinger_inventory_items
            \\)
            \\WHERE (? IS NULL OR provider = ?)
            \\  AND (? IS NULL OR domain = ?)
            \\  AND (? IS NULL OR lower(provider || ' ' || kind || ' ' || resource_id || ' ' || scope || ' ' || scope_id || ' ' || display_name || ' ' || status || ' ' || category || ' ' || domain || ' ' || username || ' ' || account_id || ' ' || zone_id || ' ' || related_id || ' ' || flag) LIKE '%' || lower(?) || '%')
            \\ORDER BY updated_at DESC, provider, kind, resource_id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindTextOpt(stmt, 3, filter.domain);
        try bindTextOpt(stmt, 4, filter.domain);
        try bindTextOpt(stmt, 5, filter.query);
        try bindTextOpt(stmt, 6, filter.query);
        try bindI64(stmt, 7, if (filter.limit > 0) filter.limit else 200);

        var rows = std.ArrayList(InventoryItem).empty;
        errdefer deinitInventoryItemList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try inventoryItemFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn cloudflareKindCounts(self: *Db, gpa: Allocator, sql: []const u8, limit: i64) !CloudflareKindCounts {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareKindCount).empty;
        errdefer deinitCloudflareKindCountList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareKindCountFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn hostingerKindCounts(self: *Db, gpa: Allocator, sql: []const u8, limit: i64) !HostingerKindCounts {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerKindCount).empty;
        errdefer deinitHostingerKindCountList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerKindCountFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn inventoryFacets(self: *Db, gpa: Allocator, filter: InventoryFilter) !InventoryFacets {
        const stmt = try self.prepare(
            \\WITH inventory AS (
            \\  SELECT 'cloudflare' AS provider,
            \\         kind,
            \\         COALESCE(resource_id, '') AS resource_id,
            \\         COALESCE(scope, '') AS scope,
            \\         COALESCE(scope_id, '') AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         '' AS username,
            \\         COALESCE(account_id, '') AS account_id,
            \\         COALESCE(zone_id, '') AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         updated_at
            \\  FROM cloudflare_inventory_items
            \\  UNION ALL
            \\  SELECT 'hostinger' AS provider,
            \\         kind,
            \\         COALESCE(resource_id, '') AS resource_id,
            \\         '' AS scope,
            \\         '' AS scope_id,
            \\         COALESCE(display_name, '') AS display_name,
            \\         COALESCE(status, '') AS status,
            \\         COALESCE(category, '') AS category,
            \\         COALESCE(domain, '') AS domain,
            \\         COALESCE(username, '') AS username,
            \\         '' AS account_id,
            \\         '' AS zone_id,
            \\         COALESCE(related_id, '') AS related_id,
            \\         COALESCE(flag, '') AS flag,
            \\         updated_at
            \\  FROM hostinger_inventory_items
            \\)
            \\SELECT provider,
            \\       kind,
            \\       status,
            \\       category,
            \\       COUNT(*) AS item_count,
            \\       COUNT(DISTINCT NULLIF(domain, '')) AS domain_count,
            \\       COALESCE(MAX(updated_at), '') AS latest_updated
            \\FROM inventory
            \\WHERE (? IS NULL OR provider = ?)
            \\  AND (? IS NULL OR domain = ?)
            \\  AND (? IS NULL OR lower(provider || ' ' || kind || ' ' || resource_id || ' ' || scope || ' ' || scope_id || ' ' || display_name || ' ' || status || ' ' || category || ' ' || domain || ' ' || username || ' ' || account_id || ' ' || zone_id || ' ' || related_id || ' ' || flag) LIKE '%' || lower(?) || '%')
            \\GROUP BY provider, kind, status, category
            \\ORDER BY item_count DESC, provider, kind, status, category
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindTextOpt(stmt, 3, filter.domain);
        try bindTextOpt(stmt, 4, filter.domain);
        try bindTextOpt(stmt, 5, filter.query);
        try bindTextOpt(stmt, 6, filter.query);
        try bindI64(stmt, 7, if (filter.limit > 0) filter.limit else 200);

        var rows = std.ArrayList(InventoryFacet).empty;
        errdefer deinitInventoryFacetList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try inventoryFacetFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn caddyUpstreams(self: *Db, gpa: Allocator) !NameValueRows {
        return try self.nameValueRows(gpa, "SELECT DISTINCT host, upstream FROM caddy_upstreams ORDER BY host, upstream");
    }

    pub fn recentMetrics(self: *Db, gpa: Allocator, limit: i64) !MetricRows {
        const stmt = try self.prepare(
            \\SELECT metric, COALESCE(value,''), COALESCE(unit,''), captured_at
            \\FROM system_metrics WHERE value IS NOT NULL AND value != '' ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(MetricRow).empty;
        errdefer deinitMetricList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try metricRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn recentAuditEvents(self: *Db, gpa: Allocator, limit: i64) !AuditEvents {
        const stmt = try self.prepare(
            \\SELECT id, action, status, COALESCE(detail,''), created_at
            \\FROM audit_events ORDER BY id DESC LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(AuditEvent).empty;
        errdefer deinitAuditEventList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try auditEventFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn providerEvidenceEvents(self: *Db, gpa: Allocator, filter: ProviderEvidenceFilter) !ProviderEvidenceEvents {
        const stmt = try self.prepare(provider_evidence_events_sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindI64(stmt, 3, positiveLimit(filter.limit, 200));
        var rows = std.ArrayList(ProviderEvidenceEvent).empty;
        errdefer deinitProviderEvidenceEventList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try providerEvidenceEventFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn providerEvidenceSummary(self: *Db, gpa: Allocator, provider: ?[]const u8) !ProviderEvidenceSummaryRows {
        const stmt = try self.prepare(provider_evidence_summary_sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, provider);
        try bindTextOpt(stmt, 2, provider);
        var rows = std.ArrayList(ProviderEvidenceSummaryRow).empty;
        errdefer deinitProviderEvidenceSummaryList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try providerEvidenceSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn routeCaptureEvidence(self: *Db, gpa: Allocator, filter: RouteCaptureEvidenceFilter) !RouteCaptureEvidenceRows {
        const stmt = try self.prepare(route_capture_evidence_sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindI64(stmt, 3, positiveLimit(filter.limit, 200));
        var rows = std.ArrayList(RouteCaptureEvidenceRow).empty;
        errdefer deinitRouteCaptureEvidenceList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try routeCaptureEvidenceFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn routeSourceEvidence(self: *Db, gpa: Allocator, filter: RouteCaptureEvidenceFilter) !RouteSourceEvidenceRows {
        const stmt = try self.prepare(
            \\SELECT source,
            \\       kind,
            \\       status,
            \\       COALESCE(target, ''),
            \\       COALESCE(summary, ''),
            \\       COALESCE(raw_json, ''),
            \\       captured_at
            \\FROM snapshots
            \\WHERE (? IS NULL OR source = ?)
            \\ORDER BY id DESC
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, filter.provider);
        try bindTextOpt(stmt, 2, filter.provider);
        try bindI64(stmt, 3, positiveLimit(filter.limit, 200));
        var rows = std.ArrayList(RouteSourceEvidenceRow).empty;
        errdefer deinitRouteSourceEvidenceList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try routeSourceEvidenceFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn projectDetails(self: *Db, gpa: Allocator, name: []const u8) !?ProjectDetails {
        const stmt = try self.prepare(
            \\SELECT name, source, COALESCE(path,''), COALESCE(host,''), COALESCE(upstream,''), COALESCE(service,''), COALESCE(container,'')
            \\FROM projects WHERE name = ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, name);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try projectDetailsFromStmt(gpa, stmt);
    }

    fn nameValueRows(self: *Db, gpa: Allocator, sql: []const u8) !NameValueRows {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        var rows = std.ArrayList(NameValueRow).empty;
        errdefer deinitNameValueList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try nameValueRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn snapshotRowsFromStmt(self: *Db, gpa: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummaries {
        _ = self;
        var rows = std.ArrayList(SnapshotSummary).empty;
        errdefer deinitSnapshotList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try snapshotSummaryFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn writeSnapshotsAfter(self: *Db, writer: anytype, after_id: i64) !void {
        const stmt = try self.prepare(
            \\SELECT source, kind, COALESCE(target,''), status, COALESCE(summary,''), captured_at
            \\FROM snapshots WHERE id > ? ORDER BY id DESC
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, after_id);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            try writer.print("{s}/{s}\t{s}\t[{s}]\t{s}\t{s}\n", .{
                columnText(stmt, 0) orelse "",
                columnText(stmt, 1) orelse "",
                columnText(stmt, 2) orelse "",
                columnText(stmt, 3) orelse "",
                columnText(stmt, 4) orelse "",
                columnText(stmt, 5) orelse "",
            });
        }
    }
};

fn bindI64(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: i64) !void {
    if (sqlite.sqlite3_bind_int64(stmt, idx, value) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindI64Opt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?i64) !void {
    if (value) |v| try bindI64(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindBoolOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?bool) !void {
    if (value) |v| try bindI64(stmt, idx, if (v) 1 else 0) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn bindText(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) {
        return DbError.SqliteBind;
    }
}

fn bindTextOpt(stmt: *sqlite.sqlite3_stmt, idx: c_int, value: ?[]const u8) !void {
    if (value) |v| try bindText(stmt, idx, v) else if (sqlite.sqlite3_bind_null(stmt, idx) != sqlite.SQLITE_OK) return DbError.SqliteBind;
}

fn stepDone(stmt: *sqlite.sqlite3_stmt) !void {
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return DbError.SqliteStep;
}

fn deinitSnapshotList(rows: *std.ArrayList(SnapshotSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitNameValueList(rows: *std.ArrayList(NameValueRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitInventoryItemList(rows: *std.ArrayList(InventoryItem), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitInventoryFacetList(rows: *std.ArrayList(InventoryFacet), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitProjectCorrelationList(rows: *std.ArrayList(ProjectCorrelation), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitTopologyRowList(rows: *std.ArrayList(TopologyRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitMetricList(rows: *std.ArrayList(MetricRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareAccountRowList(rows: *std.ArrayList(CloudflareAccountRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareZoneRowList(rows: *std.ArrayList(CloudflareZoneRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareDnsRecordRowList(rows: *std.ArrayList(CloudflareDnsRecordRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareKindCountList(rows: *std.ArrayList(CloudflareKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareResourceHintRowList(rows: *std.ArrayList(CloudflareResourceHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitCloudflareInventoryHintRowList(rows: *std.ArrayList(CloudflareInventoryHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerVpsRowList(rows: *std.ArrayList(HostingerVpsRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerResourceHintRowList(rows: *std.ArrayList(HostingerResourceHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerInventoryHintRowList(rows: *std.ArrayList(HostingerInventoryHintRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerKindCountList(rows: *std.ArrayList(HostingerKindCount), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerMetricSummaryList(rows: *std.ArrayList(HostingerMetricSummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitHostingerVpsFamilySummaryList(rows: *std.ArrayList(HostingerVpsFamilySummary), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitAuditEventList(rows: *std.ArrayList(AuditEvent), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitProviderEvidenceEventList(rows: *std.ArrayList(ProviderEvidenceEvent), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitProviderEvidenceSummaryList(rows: *std.ArrayList(ProviderEvidenceSummaryRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitRouteCaptureEvidenceList(rows: *std.ArrayList(RouteCaptureEvidenceRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn deinitRouteSourceEvidenceList(rows: *std.ArrayList(RouteSourceEvidenceRow), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn snapshotSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !SnapshotSummary {
    const id = sqlite.sqlite3_column_int64(stmt, 0);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const target = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(target);
    const status = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(status);
    const summary = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(summary);
    const captured_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(captured_at);
    return .{
        .id = id,
        .source = source,
        .kind = kind,
        .target = target,
        .status = status,
        .summary = summary,
        .captured_at = captured_at,
    };
}

fn auditEventFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !AuditEvent {
    const id = sqlite.sqlite3_column_int64(stmt, 0);
    const action = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(action);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const detail = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(detail);
    const created_at = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(created_at);
    return .{
        .id = id,
        .action = action,
        .status = status,
        .detail = detail,
        .created_at = created_at,
    };
}

fn providerEvidenceEventFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProviderEvidenceEvent {
    const row_id = sqlite.sqlite3_column_int64(stmt, 0);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const provider = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(kind);
    const target = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(target);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const detail = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(detail);
    const recorded_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(recorded_at);
    return .{
        .row_id = row_id,
        .source = source,
        .provider = provider,
        .kind = kind,
        .target = target,
        .status = status,
        .detail = detail,
        .recorded_at = recorded_at,
    };
}

fn providerEvidenceSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProviderEvidenceSummaryRow {
    const source = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(source);
    const provider = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const latest_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(latest_at);
    return .{
        .source = source,
        .provider = provider,
        .kind = kind,
        .status = status,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .latest_at = latest_at,
    };
}

fn routeCaptureEvidenceFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !RouteCaptureEvidenceRow {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const operation_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(operation_id);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const endpoint_sample = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(endpoint_sample);
    const latest_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(latest_at);
    return .{
        .provider = provider,
        .operation_id = operation_id,
        .status = status,
        .endpoint_sample = endpoint_sample,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .latest_at = latest_at,
    };
}

fn routeSourceEvidenceFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !RouteSourceEvidenceRow {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const operation_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(operation_id);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const target = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(target);
    const summary = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(summary);
    const raw_json = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(raw_json);
    const captured_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(captured_at);
    return .{
        .provider = provider,
        .operation_id = operation_id,
        .status = status,
        .target = target,
        .summary = summary,
        .raw_json = raw_json,
        .captured_at = captured_at,
    };
}

fn metricRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !MetricRow {
    const metric = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(metric);
    const value = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(value);
    const unit = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(unit);
    const captured_at = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(captured_at);
    return .{
        .metric = metric,
        .value = value,
        .unit = unit,
        .captured_at = captured_at,
    };
}

fn cloudflareAccountRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareAccountRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const account_type = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(account_type);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const updated_at = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .account_type = account_type,
        .status = status,
        .updated_at = updated_at,
    };
}

fn cloudflareZoneRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareZoneRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const account_id = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(account_id);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const paused = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(paused);
    const zone_type = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(zone_type);
    const name_servers = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(name_servers);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .account_id = account_id,
        .status = status,
        .paused = paused,
        .zone_type = zone_type,
        .name_servers = name_servers,
        .updated_at = updated_at,
    };
}

fn cloudflareDnsRecordRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareDnsRecordRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const zone_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(zone_id);
    const name = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(name);
    const record_type = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(record_type);
    const content = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(content);
    const ttl = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(ttl);
    const proxied = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(proxied);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .zone_id = zone_id,
        .name = name,
        .record_type = record_type,
        .content = content,
        .ttl = ttl,
        .proxied = proxied,
        .updated_at = updated_at,
    };
}

fn cloudflareKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareKindCount {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(latest_updated);
    return .{
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 1),
        .latest_updated = latest_updated,
    };
}

fn cloudflareResourceHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareResourceHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope_id);
    const name = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const resource_type = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(resource_type);
    const updated_at = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .name = name,
        .status = status,
        .resource_type = resource_type,
        .updated_at = updated_at,
    };
}

fn cloudflareInventoryHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !CloudflareInventoryHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope_id);
    const display_name = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(domain);
    const account_id = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(account_id);
    const zone_id = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(zone_id);
    const related_id = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(flag);
    const updated_at = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .updated_at = updated_at,
    };
}

fn hostingerVpsRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerVpsRow {
    const id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(id);
    const name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const ipv4 = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(ipv4);
    const plan = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(plan);
    const updated_at = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(updated_at);
    return .{
        .id = id,
        .name = name,
        .status = status,
        .ipv4 = ipv4,
        .plan = plan,
        .updated_at = updated_at,
    };
}

fn hostingerResourceHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerResourceHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const target = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(target);
    const name = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(name);
    const status = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(status);
    const domain = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(domain);
    const updated_at = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .target = target,
        .name = name,
        .status = status,
        .domain = domain,
        .updated_at = updated_at,
    };
}

fn hostingerInventoryHintRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerInventoryHintRow {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(resource_id);
    const display_name = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(domain);
    const username = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(username);
    const related_id = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(flag);
    const updated_at = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(updated_at);
    return .{
        .kind = kind,
        .resource_id = resource_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .username = username,
        .related_id = related_id,
        .flag = flag,
        .updated_at = updated_at,
    };
}

fn hostingerKindCountFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerKindCount {
    const kind = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(latest_updated);
    return .{
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 1),
        .latest_updated = latest_updated,
    };
}

fn hostingerMetricSummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerMetricSummary {
    const vm_id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(vm_id);
    const metric = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(metric);
    const latest_captured = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(latest_captured);
    return .{
        .vm_id = vm_id,
        .metric = metric,
        .count = sqlite.sqlite3_column_int64(stmt, 2),
        .latest_captured = latest_captured,
    };
}

fn hostingerVpsFamilySummaryFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !HostingerVpsFamilySummary {
    const vm_id = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(vm_id);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const kind = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(kind);
    const latest_updated = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(latest_updated);
    return .{
        .vm_id = vm_id,
        .source = source,
        .kind = kind,
        .count = sqlite.sqlite3_column_int64(stmt, 3),
        .latest_updated = latest_updated,
    };
}

fn nameValueRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !NameValueRow {
    const name = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(name);
    const value = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(value);
    return .{
        .name = name,
        .value = value,
    };
}

fn inventoryItemFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryItem {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(kind);
    const resource_id = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(resource_id);
    const scope = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(scope);
    const scope_id = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(scope_id);
    const display_name = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(display_name);
    const status = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(category);
    const domain = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(domain);
    const username = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(username);
    const account_id = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(account_id);
    const zone_id = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(zone_id);
    const related_id = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(related_id);
    const flag = try dupeColumn(allocator, stmt, 13);
    errdefer allocator.free(flag);
    const created_at_source = try dupeColumn(allocator, stmt, 14);
    errdefer allocator.free(created_at_source);
    const updated_at_source = try dupeColumn(allocator, stmt, 15);
    errdefer allocator.free(updated_at_source);
    const expires_at_source = try dupeColumn(allocator, stmt, 16);
    errdefer allocator.free(expires_at_source);
    const updated_at = try dupeColumn(allocator, stmt, 17);
    errdefer allocator.free(updated_at);
    return .{
        .provider = provider,
        .kind = kind,
        .resource_id = resource_id,
        .scope = scope,
        .scope_id = scope_id,
        .display_name = display_name,
        .status = status,
        .category = category,
        .domain = domain,
        .username = username,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .created_at_source = created_at_source,
        .updated_at_source = updated_at_source,
        .expires_at_source = expires_at_source,
        .updated_at = updated_at,
    };
}

fn inventoryFacetFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !InventoryFacet {
    const provider = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(provider);
    const kind = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(kind);
    const status = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(status);
    const category = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(category);
    const latest_updated = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(latest_updated);
    return .{
        .provider = provider,
        .kind = kind,
        .status = status,
        .category = category,
        .count = sqlite.sqlite3_column_int64(stmt, 4),
        .domains = sqlite.sqlite3_column_int64(stmt, 5),
        .latest_updated = latest_updated,
    };
}

fn projectDetailsFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProjectDetails {
    const name = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(name);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(path);
    const host = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(host);
    const upstream = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(upstream);
    const service = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(service);
    const container = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(container);
    return .{
        .name = name,
        .source = source,
        .path = path,
        .host = host,
        .upstream = upstream,
        .service = service,
        .container = container,
    };
}

fn projectCorrelationFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !ProjectCorrelation {
    const project = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(project);
    const source = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(path);
    const host = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(host);
    const caddy_source = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(caddy_source);
    const upstream = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(upstream);
    const socket_state = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(socket_state);
    const socket_process = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(socket_process);
    const service = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(service);
    const service_state = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(service_state);
    const container = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(container);
    const container_status = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(container_status);
    return .{
        .project = project,
        .source = source,
        .path = path,
        .host = host,
        .caddy_source = caddy_source,
        .upstream = upstream,
        .socket_state = socket_state,
        .socket_process = socket_process,
        .service = service,
        .service_state = service_state,
        .container = container,
        .container_status = container_status,
    };
}

fn topologyRowFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !TopologyRow {
    const host = try dupeColumn(allocator, stmt, 0);
    errdefer allocator.free(host);
    const dns_name = try dupeColumn(allocator, stmt, 1);
    errdefer allocator.free(dns_name);
    const dns_type = try dupeColumn(allocator, stmt, 2);
    errdefer allocator.free(dns_type);
    const dns_content = try dupeColumn(allocator, stmt, 3);
    errdefer allocator.free(dns_content);
    const dns_proxied = try dupeColumn(allocator, stmt, 4);
    errdefer allocator.free(dns_proxied);
    const project = try dupeColumn(allocator, stmt, 5);
    errdefer allocator.free(project);
    const source = try dupeColumn(allocator, stmt, 6);
    errdefer allocator.free(source);
    const path = try dupeColumn(allocator, stmt, 7);
    errdefer allocator.free(path);
    const caddy_source = try dupeColumn(allocator, stmt, 8);
    errdefer allocator.free(caddy_source);
    const upstream = try dupeColumn(allocator, stmt, 9);
    errdefer allocator.free(upstream);
    const socket_state = try dupeColumn(allocator, stmt, 10);
    errdefer allocator.free(socket_state);
    const socket_process = try dupeColumn(allocator, stmt, 11);
    errdefer allocator.free(socket_process);
    const service = try dupeColumn(allocator, stmt, 12);
    errdefer allocator.free(service);
    const service_state = try dupeColumn(allocator, stmt, 13);
    errdefer allocator.free(service_state);
    const container = try dupeColumn(allocator, stmt, 14);
    errdefer allocator.free(container);
    const container_status = try dupeColumn(allocator, stmt, 15);
    errdefer allocator.free(container_status);
    return .{
        .host = host,
        .dns_name = dns_name,
        .dns_type = dns_type,
        .dns_content = dns_content,
        .dns_proxied = dns_proxied,
        .project = project,
        .source = source,
        .path = path,
        .caddy_source = caddy_source,
        .upstream = upstream,
        .socket_state = socket_state,
        .socket_process = socket_process,
        .service = service,
        .service_state = service_state,
        .container = container,
        .container_status = container_status,
    };
}

fn dupeColumn(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, idx: c_int) ![]u8 {
    return try allocator.dupe(u8, columnText(stmt, idx) orelse "");
}

fn positiveLimit(value: i64, fallback: i64) i64 {
    return if (value > 0) value else fallback;
}

pub fn columnText(stmt: *sqlite.sqlite3_stmt, idx: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(stmt, idx) == sqlite.SQLITE_NULL) return null;
    const ptr = sqlite.sqlite3_column_text(stmt, idx) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, idx));
    return @as([*]const u8, @ptrCast(ptr))[0..len];
}

const provider_evidence_cte =
    \\WITH evidence AS (
    \\  SELECT id AS row_id,
    \\         'provider_raw' AS source,
    \\         provider AS provider,
    \\         'http' AS kind,
    \\         endpoint AS target,
    \\         COALESCE(CAST(status AS TEXT), '') AS status,
    \\         'body_bytes=' || length(COALESCE(body_json, '')) AS detail,
    \\         captured_at AS recorded_at
    \\  FROM provider_raw
    \\  UNION ALL
    \\  SELECT id AS row_id,
    \\         'snapshot' AS source,
    \\         source AS provider,
    \\         kind AS kind,
    \\         COALESCE(target, '') AS target,
    \\         status AS status,
    \\         COALESCE(summary, '') AS detail,
    \\         captured_at AS recorded_at
    \\  FROM snapshots
    \\  UNION ALL
    \\  SELECT id AS row_id,
    \\         'audit' AS source,
    \\         CASE
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%cloudflare%' THEN 'cloudflare'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%hostinger%' THEN 'hostinger'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%caddy%' THEN 'caddy'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%system%' THEN 'system'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%project%' THEN 'projects'
    \\           WHEN lower(action || ' ' || COALESCE(detail, '')) LIKE '%route%' THEN 'route'
    \\           ELSE ''
    \\         END AS provider,
    \\         action AS kind,
    \\         '' AS target,
    \\         status AS status,
    \\         COALESCE(detail, '') AS detail,
    \\         created_at AS recorded_at
    \\  FROM audit_events
    \\)
;

const provider_evidence_events_sql = provider_evidence_cte ++
    \\SELECT row_id, source, provider, kind, target, status, detail, recorded_at
    \\FROM evidence
    \\WHERE (? IS NULL OR provider = ?)
    \\ORDER BY recorded_at DESC, row_id DESC
    \\LIMIT ?
;

const provider_evidence_summary_sql = provider_evidence_cte ++
    \\SELECT source,
    \\       provider,
    \\       kind,
    \\       status,
    \\       COUNT(*) AS event_count,
    \\       COALESCE(MAX(recorded_at), '') AS latest_at
    \\FROM evidence
    \\WHERE (? IS NULL OR provider = ?)
    \\GROUP BY source, provider, kind, status
    \\ORDER BY latest_at DESC, event_count DESC, source, provider, kind, status
;

const route_capture_evidence_sql =
    \\WITH parsed AS (
    \\  SELECT status,
    \\         created_at,
    \\         detail,
    \\         instr(detail, '/') AS slash_pos
    \\  FROM audit_events
    \\  WHERE action = 'route.capture'
    \\),
    \\provider_rows AS (
    \\  SELECT status,
    \\         created_at,
    \\         detail,
    \\         CASE WHEN slash_pos > 1 THEN substr(detail, 1, slash_pos - 1) ELSE '' END AS provider,
    \\         CASE WHEN slash_pos > 0 THEN substr(detail, slash_pos + 1) ELSE detail END AS rest
    \\  FROM parsed
    \\),
    \\route_rows AS (
    \\  SELECT provider,
    \\         CASE
    \\           WHEN instr(rest, ' ') > 1 THEN substr(rest, 1, instr(rest, ' ') - 1)
    \\           ELSE rest
    \\         END AS operation_id,
    \\         status,
    \\         CASE
    \\           WHEN instr(rest, ' ') > 0 THEN substr(rest, instr(rest, ' ') + 1)
    \\           ELSE ''
    \\         END AS endpoint,
    \\         created_at
    \\  FROM provider_rows
    \\)
    \\SELECT provider,
    \\       operation_id,
    \\       status,
    \\       COALESCE(MAX(endpoint), '') AS endpoint_sample,
    \\       COUNT(*) AS event_count,
    \\       COALESCE(MAX(created_at), '') AS latest_at
    \\FROM route_rows
    \\WHERE (? IS NULL OR provider = ?)
    \\GROUP BY provider, operation_id, status
    \\ORDER BY latest_at DESC, event_count DESC, provider, operation_id, status
    \\LIMIT ?
;

fn isKnownTable(table: []const u8) bool {
    const known = [_][]const u8{
        "snapshots",            "provider_raw",               "cloudflare_accounts",       "cloudflare_zones", "cloudflare_dns_records",
        "cloudflare_resources", "cloudflare_inventory_items", "cloudflare_security_items", "hostinger_vps",    "hostinger_metrics",
        "hostinger_resources",  "hostinger_inventory_items",  "caddy_sites",               "caddy_upstreams",  "projects",
        "system_metrics",       "services",                   "sockets",                   "containers",       "audit_events",
        "settings",
    };
    for (known) |name| if (std.mem.eql(u8, table, name)) return true;
    return false;
}

fn secretScanSql(surface: SecretScanSurface) []const u8 {
    return switch (surface) {
        .settings_value => "SELECT COUNT(*) FROM settings WHERE instr(COALESCE(value, ''), ?) > 0",
        .snapshots_target => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(target, ''), ?) > 0",
        .snapshots_summary => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(summary, ''), ?) > 0",
        .snapshots_raw_json => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .snapshots_raw_text => "SELECT COUNT(*) FROM snapshots WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .provider_raw_endpoint => "SELECT COUNT(*) FROM provider_raw WHERE instr(COALESCE(endpoint, ''), ?) > 0",
        .provider_raw_body_json => "SELECT COUNT(*) FROM provider_raw WHERE instr(COALESCE(body_json, ''), ?) > 0",
        .cloudflare_accounts_raw_json => "SELECT COUNT(*) FROM cloudflare_accounts WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_zones_raw_json => "SELECT COUNT(*) FROM cloudflare_zones WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_dns_records_raw_json => "SELECT COUNT(*) FROM cloudflare_dns_records WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_resources_raw_json => "SELECT COUNT(*) FROM cloudflare_resources WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_inventory_items_raw_json => "SELECT COUNT(*) FROM cloudflare_inventory_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .cloudflare_security_items_raw_json => "SELECT COUNT(*) FROM cloudflare_security_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_vps_raw_json => "SELECT COUNT(*) FROM hostinger_vps WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_metrics_raw_json => "SELECT COUNT(*) FROM hostinger_metrics WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_resources_raw_json => "SELECT COUNT(*) FROM hostinger_resources WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .hostinger_inventory_items_raw_json => "SELECT COUNT(*) FROM hostinger_inventory_items WHERE instr(COALESCE(raw_json, ''), ?) > 0",
        .caddy_sites_raw_block => "SELECT COUNT(*) FROM caddy_sites WHERE instr(COALESCE(raw_block, ''), ?) > 0",
        .projects_raw_text => "SELECT COUNT(*) FROM projects WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .services_raw_text => "SELECT COUNT(*) FROM services WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .sockets_raw_text => "SELECT COUNT(*) FROM sockets WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .containers_raw_text => "SELECT COUNT(*) FROM containers WHERE instr(COALESCE(raw_text, ''), ?) > 0",
        .audit_events_detail => "SELECT COUNT(*) FROM audit_events WHERE instr(COALESCE(detail, ''), ?) > 0",
    };
}

test "sqlite schema initializes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-store.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try std.testing.expectEqual(db_schema.latest_version, try db.schemaVersion());
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("snapshots"));
}

test "secret scan counts exact configured bytes across output storage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-secret-scan.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const secret = "super-secret-token";
    _ = try db.insertSnapshot("cloudflare", "raw", "/accounts", "ok", "summary", "{\"token\":\"super-secret-token\"}", null);
    try db.insertProviderRaw("cloudflare", "/accounts", 200, "{\"ok\":true}");
    try db.insertAudit("route.capture", "ok", "captured super-secret-token");

    try std.testing.expectEqual(@as(i64, 1), try db.countSecretNeedle(.snapshots_raw_json, secret));
    try std.testing.expectEqual(@as(i64, 1), try db.countSecretNeedle(.audit_events_detail, secret));
    try std.testing.expectEqual(@as(i64, 0), try db.countSecretNeedle(.provider_raw_body_json, secret));
    try std.testing.expectEqualStrings("snapshots.raw_json", SecretScanSurface.snapshots_raw_json.label());
}

test "audit events can be inserted and queried as a read model" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-audit.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertAudit("caddy.diff", "dry_run", "rendered only");
    var rows = try db.recentAuditEvents(allocator, 10);
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("caddy.diff", rows.items[0].action);
    try std.testing.expectEqualStrings("dry_run", rows.items[0].status);
    try std.testing.expectEqualStrings("rendered only", rows.items[0].detail);
}

test "provider evidence read model joins raw captures snapshots and audit events" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-provider-evidence.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertProviderRaw("hostinger", "/api/vps/v1/virtual-machines", 200, "{\"data\":[]}");
    _ = try db.insertSnapshot("hostinger", "route-hostinger-vps", "vps", "ok", "captured 0 rows", null, null);
    _ = try db.insertSnapshot("cloudflare", "route-cloudflare-dns", "plosca.ru", "error", "permission denied", null, null);
    try db.insertAudit("route.capture", "ok", "hostinger vps captured");
    try db.insertAudit("caddy.diff", "dry_run", "rendered only");

    var hostinger_events = try db.providerEvidenceEvents(allocator, .{ .provider = "hostinger", .limit = 20 });
    defer hostinger_events.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), hostinger_events.items.len);
    try std.testing.expectEqualStrings("hostinger", hostinger_events.items[0].provider);

    var all_summary = try db.providerEvidenceSummary(allocator, null);
    defer all_summary.deinit(allocator);
    try std.testing.expect(all_summary.items.len >= 5);

    var saw_raw = false;
    var saw_cloudflare_error = false;
    for (all_summary.items) |row| {
        if (std.mem.eql(u8, row.source, "provider_raw") and std.mem.eql(u8, row.provider, "hostinger")) saw_raw = true;
        if (std.mem.eql(u8, row.provider, "cloudflare") and std.mem.eql(u8, row.status, "error")) saw_cloudflare_error = true;
    }
    try std.testing.expect(saw_raw);
    try std.testing.expect(saw_cloudflare_error);
}

test "route capture evidence extracts operation ids from audit detail" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-route-capture-evidence.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertAudit("route.capture", "ok", "cloudflare/accounts-list-accounts /accounts");
    try db.insertAudit("route.capture", "ok", "cloudflare/accounts-list-accounts /accounts?page=2");
    try db.insertAudit("route.capture", "http_error", "cloudflare/listZoneRulesets /zones/zone/rulesets");
    try db.insertAudit("route.capture", "ok", "hostinger/VPS_getVirtualMachinesV1 /api/vps/v1/virtual-machines");

    var cloudflare_rows = try db.routeCaptureEvidence(allocator, .{ .provider = "cloudflare", .limit = 20 });
    defer cloudflare_rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), cloudflare_rows.items.len);

    var saw_accounts = false;
    var saw_rulesets = false;
    for (cloudflare_rows.items) |row| {
        try std.testing.expectEqualStrings("cloudflare", row.provider);
        if (std.mem.eql(u8, row.operation_id, "accounts-list-accounts")) {
            saw_accounts = true;
            try std.testing.expectEqual(@as(i64, 2), row.count);
            try std.testing.expectEqualStrings("ok", row.status);
        }
        if (std.mem.eql(u8, row.operation_id, "listZoneRulesets")) {
            saw_rulesets = true;
            try std.testing.expectEqualStrings("http_error", row.status);
        }
    }
    try std.testing.expect(saw_accounts);
    try std.testing.expect(saw_rulesets);
}

test "route source evidence exposes snapshot bodies by operation id" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-route-source-evidence.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    _ = try db.insertSnapshot("hostinger", "domains_getWHOISProfileListV1", "/api/domains/v1/whois", "ok", "HTTP 200", "[]", null);
    _ = try db.insertSnapshot("cloudflare", "accounts-list-accounts", "/accounts", "ok", "HTTP 200", "{\"result\":[]}", null);

    var rows = try db.routeSourceEvidence(allocator, .{ .provider = "hostinger", .limit = 20 });
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("hostinger", rows.items[0].provider);
    try std.testing.expectEqualStrings("domains_getWHOISProfileListV1", rows.items[0].operation_id);
    try std.testing.expectEqualStrings("/api/domains/v1/whois", rows.items[0].target);
    try std.testing.expectEqualStrings("ok", rows.items[0].status);
    try std.testing.expectEqualStrings("[]", rows.items[0].raw_json);
}

test "provider inventory read model joins and filters typed inventory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    var all = try db.inventoryItems(allocator, .{});
    defer all.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), all.items.len);

    var cloudflare = try db.inventoryItems(allocator, .{ .provider = "cloudflare" });
    defer cloudflare.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), cloudflare.items.len);
    try std.testing.expectEqualStrings("cloudflare", cloudflare.items[0].provider);
    try std.testing.expectEqualStrings("zone", cloudflare.items[0].scope);
    try std.testing.expectEqualStrings("zone-1", cloudflare.items[0].scope_id);

    var query = try db.inventoryItems(allocator, .{ .query = "u123" });
    defer query.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), query.items.len);
    try std.testing.expectEqualStrings("hostinger", query.items[0].provider);
    try std.testing.expectEqualStrings("u123", query.items[0].username);

    var facets = try db.inventoryFacets(allocator, .{ .domain = "plosca.ru" });
    defer facets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), facets.items.len);
    try std.testing.expectEqualStrings("cloudflare", facets.items[0].provider);
    try std.testing.expectEqualStrings("dns-records", facets.items[0].kind);
    try std.testing.expectEqualStrings("active", facets.items[0].status);
    try std.testing.expectEqualStrings("A", facets.items[0].category);
    try std.testing.expectEqual(@as(i64, 1), facets.items[0].count);
    try std.testing.expectEqual(@as(i64, 1), facets.items[0].domains);

    var hostinger_facets = try db.inventoryFacets(allocator, .{ .provider = "hostinger", .query = "u123" });
    defer hostinger_facets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), hostinger_facets.items.len);
    try std.testing.expectEqualStrings("hostinger-websites", hostinger_facets.items[0].kind);
    try std.testing.expectEqualStrings("enabled", hostinger_facets.items[0].status);
    try std.testing.expectEqualStrings("main", hostinger_facets.items[0].category);
}
