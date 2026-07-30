const std = @import("std");

const Allocator = std.mem.Allocator;

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
