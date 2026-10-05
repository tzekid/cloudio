const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DbError = error{
    SqliteOpen,
    SqliteExec,
    SqlitePrepare,
    SqliteStep,
    SqliteBind,
};

/// Latest collection attempt plus the most recent successful observation for
/// one source/kind pair. A failed attempt never erases the last-good timestamp.
pub const Observation = struct {
    source: []u8,
    kind: []u8,
    attempt_status: []u8,
    attempt_summary: []u8,
    attempted_at: []u8,
    observed_at: []u8,
    age_seconds: i64,

    pub fn deinit(self: Observation, allocator: Allocator) void {
        allocator.free(self.source);
        allocator.free(self.kind);
        allocator.free(self.attempt_status);
        allocator.free(self.attempt_summary);
        allocator.free(self.attempted_at);
        allocator.free(self.observed_at);
    }

    pub fn hasSuccessfulObservation(self: Observation) bool {
        return self.observed_at.len != 0;
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

