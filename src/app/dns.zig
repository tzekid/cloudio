//! Observation-backed Cloudflare DNS record workflow.
const std = @import("std");
const app_provider_writes = @import("provider_writes.zig");
const core_config = @import("../core/config.zig");
const core_json = @import("../core/json.zig");
const core_redact = @import("../core/redact.zig");
const db_store = @import("../db/store.zig");
const observation = @import("observation.zig");
const net_http = @import("../net/http.zig");
const provider_cloudflare = @import("cloudflare");
const provider_cloudflare_models = @import("cloudflare").models;

const Allocator = std.mem.Allocator;
var dns_mutex: std.atomic.Mutex = .unlocked;

pub const Error = error{
    InvalidDnsRequest,
    DnsZoneNotConfigured,
    DnsZoneNotObserved,
    DnsRecordNotObserved,
    DnsWriteUnavailable,
    DnsBusy,
    DnsProviderRejected,
    DnsProviderUnavailable,
};

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: @import("writes.zig").Metadata = .{},
};

pub const Action = enum {
    create,
    update,
    toggle,
    delete,
};

pub const RecordInput = struct {
    record_type: []const u8,
    name: []const u8,
    content: []const u8,
    ttl: i64,
    proxied: bool,
};

pub const MutationOutcome = enum {
    confirmed,
    accepted_unconfirmed,

    pub fn status(self: MutationOutcome) u16 {
        return if (self == .confirmed) 200 else 202;
    }
};

const PreparedRecord = struct {
    record_type: []const u8,
    name: []u8,
    content: []const u8,
    ttl: i64,
    proxied: bool,

    fn deinit(self: PreparedRecord, gpa: Allocator) void {
        gpa.free(self.name);
    }
};

pub const Zone = struct {
    domain: []const u8,
    observed: bool,
};

pub const Record = struct {
    row: db_store.CloudflareDnsRecordRow,
    ttl: i64,
    proxied: bool,
    can_edit: bool,
    can_toggle: bool,
    can_delete: bool,
};

/// What the DNS page shows for one configured zone: its stored records and
/// whether the observation is current enough to allow changes.
pub const View = struct {
    domain: []const u8,
    zones: []Zone,
    zone_observed: bool,
    freshness: observation.Freshness,
    latest: ?db_store.Observation,
    can_refresh: bool,
    can_write: bool,
    reason: []const u8,
    records: []Record,
    zone_rows: db_store.CloudflareZoneRows,
    record_rows: db_store.CloudflareDnsRecordRows,

    pub fn load(ctx: Context, requested_domain: ?[]const u8) !View {
        const domain = selectedDomain(ctx.config.domains, requested_domain);
        var zone_rows = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 200);
        errdefer zone_rows.deinit(ctx.gpa);
        var record_rows = try ctx.db.cloudflare().cloudflareDnsRecordRows(ctx.gpa, 5000);
        errdefer record_rows.deinit(ctx.gpa);
        const latest = if (domain.len > 0) try ctx.db.latestObservationForTarget(ctx.gpa, "cloudflare", "dns", domain) else null;
        errdefer if (latest) |value| value.deinit(ctx.gpa);

        const zone = findZone(zone_rows.items, domain);
        const fresh = observation.freshness(latest, ctx.config);
        const can_refresh = domain.len > 0 and ctx.config.hasCloudflareAuth();
        const can_write = can_refresh and zone != null and fresh == .current;

        const zones = try ctx.gpa.alloc(Zone, ctx.config.domains.len);
        errdefer ctx.gpa.free(zones);
        for (ctx.config.domains, zones) |configured, *item| item.* = .{ .domain = configured, .observed = findZone(zone_rows.items, configured) != null };

        var records: std.ArrayList(Record) = .empty;
        errdefer records.deinit(ctx.gpa);
        if (zone) |observed| for (record_rows.items) |row| {
            if (!std.mem.eql(u8, row.zone_id, observed.id)) continue;
            try records.append(ctx.gpa, .{
                .row = row,
                .ttl = std.fmt.parseInt(i64, row.ttl, 10) catch 0,
                .proxied = std.mem.eql(u8, row.proxied, "true"),
                .can_edit = can_write and supportedType(row.record_type),
                .can_toggle = can_write and proxyableType(row.record_type),
                .can_delete = can_write,
            });
        };
        return .{
            .domain = domain,
            .zones = zones,
            .zone_observed = zone != null,
            .freshness = fresh,
            .latest = latest,
            .can_refresh = can_refresh,
            .can_write = can_write,
            .reason = capabilityReason(domain, ctx.config.hasCloudflareAuth(), zone != null, fresh, latest),
            .records = try records.toOwnedSlice(ctx.gpa),
            .zone_rows = zone_rows,
            .record_rows = record_rows,
        };
    }

    pub fn deinit(self: *View, gpa: Allocator) void {
        gpa.free(self.records);
        gpa.free(self.zones);
        if (self.latest) |value| value.deinit(gpa);
        self.record_rows.deinit(gpa);
        self.zone_rows.deinit(gpa);
    }

    pub fn record(self: View, id: []const u8) ?Record {
        for (self.records) |item| if (std.mem.eql(u8, item.row.id, id)) return item;
        return null;
    }
};

pub fn refresh(ctx: Context, domain_input: []const u8) !void {
    if (!dns_mutex.tryLock()) return error.DnsBusy;
    defer dns_mutex.unlock();
    const domain = configuredDomain(ctx.config.domains, domain_input) orelse return error.DnsZoneNotConfigured;
    try refreshLocked(ctx, domain);
}

pub fn mutate(
    ctx: Context,
    action: Action,
    domain_input: []const u8,
    record_id: ?[]const u8,
    input: ?RecordInput,
) !MutationOutcome {
    if (!dns_mutex.tryLock()) return error.DnsBusy;
    defer dns_mutex.unlock();
    const domain = configuredDomain(ctx.config.domains, domain_input) orelse return error.DnsZoneNotConfigured;
    if (!ctx.config.hasCloudflareAuth()) return error.DnsWriteUnavailable;

    var zones = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 200);
    defer zones.deinit(ctx.gpa);
    const zone = findZone(zones.items, domain) orelse return error.DnsZoneNotObserved;
    const observation_optional = try ctx.db.latestObservationForTarget(ctx.gpa, "cloudflare", "dns", domain);
    defer if (observation_optional) |value| value.deinit(ctx.gpa);
    if (observation.freshness(observation_optional, ctx.config) != .current)
        return error.DnsWriteUnavailable;

    var records = try ctx.db.cloudflare().cloudflareDnsRecordRows(ctx.gpa, 5000);
    defer records.deinit(ctx.gpa);
    const observed_record = if (record_id) |id| findRecord(records.items, zone.id, id) else null;
    if (action != .create and observed_record == null) return error.DnsRecordNotObserved;

    var provider_output = std.Io.Writer.Allocating.init(ctx.gpa);
    defer provider_output.deinit();
    switch (action) {
        .create, .update => {
            var prepared = try prepareRecord(ctx.gpa, domain, input orelse return error.InvalidDnsRequest);
            defer prepared.deinit(ctx.gpa);
            const body = try recordJson(ctx.gpa, prepared);
            defer ctx.gpa.free(body);
            if (action == .create) {
                try app_provider_writes.dnsRecordCreate(providerContext(ctx), zone.id, body, &provider_output.writer);
            } else {
                try app_provider_writes.dnsRecordUpdate(providerContext(ctx), zone.id, observed_record.?.id, body, &provider_output.writer);
            }
        },
        .toggle => {
            const record = observed_record.?;
            if (!proxyableType(record.record_type)) return error.InvalidDnsRequest;
            const ttl = std.fmt.parseInt(i64, record.ttl, 10) catch return error.InvalidDnsRequest;
            var prepared = try prepareRecord(ctx.gpa, domain, .{
                .record_type = record.record_type,
                .name = record.name,
                .content = record.content,
                .ttl = ttl,
                .proxied = !std.mem.eql(u8, record.proxied, "true"),
            });
            defer prepared.deinit(ctx.gpa);
            const body = try recordJson(ctx.gpa, prepared);
            defer ctx.gpa.free(body);
            try app_provider_writes.dnsRecordUpdate(providerContext(ctx), zone.id, record.id, body, &provider_output.writer);
        },
        .delete => try app_provider_writes.dnsRecordDelete(providerContext(ctx), zone.id, observed_record.?.id, &provider_output.writer),
    }
    try requireAcceptedMutation(ctx.gpa, provider_output.written());
    refreshLocked(ctx, domain) catch |err| switch (err) {
        error.DnsProviderRejected, error.DnsProviderUnavailable => return .accepted_unconfirmed,
        else => return err,
    };
    return .confirmed;
}

pub fn observedRecordName(ctx: Context, domain_input: []const u8, record_id: []const u8) !?[]u8 {
    const domain = configuredDomain(ctx.config.domains, domain_input) orelse return error.DnsZoneNotConfigured;
    var zones = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 200);
    defer zones.deinit(ctx.gpa);
    const zone = findZone(zones.items, domain) orelse return error.DnsZoneNotObserved;
    var records = try ctx.db.cloudflare().cloudflareDnsRecordRows(ctx.gpa, 5000);
    defer records.deinit(ctx.gpa);
    const record = findRecord(records.items, zone.id, record_id) orelse return null;
    return try ctx.gpa.dupe(u8, record.name);
}

fn refreshLocked(ctx: Context, domain: []const u8) !void {
    if (!ctx.config.hasCloudflareAuth()) {
        try recordRefreshAttempt(ctx, domain, "error", "Cloudflare credentials are not configured.", null);
        return error.DnsProviderUnavailable;
    }
    const client = provider_cloudflare.Client.init(.{
        .token = ctx.config.cloudflare_api_token,
        .email = ctx.config.cloudflare_email,
        .key = ctx.config.cloudflare_api_key,
        .base_url = ctx.config.cloudflare_api_base,
    });
    var zones = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 200);
    defer zones.deinit(ctx.gpa);
    var zone_id_buffer: ?[]u8 = null;
    defer if (zone_id_buffer) |value| ctx.gpa.free(value);
    const existing_zone = findZone(zones.items, domain);
    const zone_id: []const u8 = if (existing_zone) |zone|
        zone.id
    else blk: {
        const response = client.getZones(ctx.io, ctx.gpa, domain) catch |err| {
            const summary = try std.fmt.allocPrint(ctx.gpa, "Zone lookup failed: {s}", .{@errorName(err)});
            defer ctx.gpa.free(summary);
            try recordRefreshAttempt(ctx, domain, "error", summary, null);
            return error.DnsProviderUnavailable;
        };
        defer response.deinit(ctx.gpa);
        const redacted = try core_redact.providerResponse(ctx.gpa, response.body);
        defer ctx.gpa.free(redacted);
        if (!net_http.isOk(response.status) or !validCloudflareEnvelope(ctx.gpa, redacted, .array)) {
            try recordRefreshAttempt(ctx, domain, "error", "Cloudflare rejected the zone lookup.", redacted);
            return error.DnsProviderRejected;
        }
        var parsed_zones = try provider_cloudflare_models.parseZoneRows(ctx.gpa, redacted);
        defer parsed_zones.deinit(ctx.gpa);
        var matched: ?[]const u8 = null;
        for (parsed_zones.items) |zone| {
            if (zone.name == null or !std.ascii.eqlIgnoreCase(zone.name.?, domain)) continue;
            if (matched != null) return error.DnsProviderRejected;
            matched = zone.id;
            try ctx.db.upsertCloudflareZone(zone.id, zone.name, zone.account_id, zone.status, zone.paused, zone.typ, zone.name_servers, zone.raw_json);
        }
        const found = matched orelse {
            try recordRefreshAttempt(ctx, domain, "error", "The configured zone was not returned by Cloudflare.", redacted);
            return error.DnsZoneNotObserved;
        };
        zone_id_buffer = try ctx.gpa.dupe(u8, found);
        break :blk zone_id_buffer.?;
    };

    const response = client.getDnsRecords(ctx.io, ctx.gpa, zone_id) catch |err| {
        const summary = try std.fmt.allocPrint(ctx.gpa, "DNS refresh failed: {s}", .{@errorName(err)});
        defer ctx.gpa.free(summary);
        try recordRefreshAttempt(ctx, domain, "error", summary, null);
        return error.DnsProviderUnavailable;
    };
    defer response.deinit(ctx.gpa);
    const redacted = try core_redact.providerResponse(ctx.gpa, response.body);
    defer ctx.gpa.free(redacted);
    if (!net_http.isOk(response.status) or !validCloudflareEnvelope(ctx.gpa, redacted, .array)) {
        try recordRefreshAttempt(ctx, domain, "error", "Cloudflare rejected the DNS record read.", redacted);
        return error.DnsProviderRejected;
    }

    var rows = try provider_cloudflare_models.parseDnsRecordRows(ctx.gpa, zone_id, redacted);
    defer rows.deinit(ctx.gpa);
    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    try ctx.db.cloudflare().deleteDnsRecordsForZone(zone_id);
    for (rows.items) |row| {
        try ctx.db.upsertDnsRecord(row.id, row.zone_id, row.name, row.typ, row.content, row.ttl, row.proxied, row.raw_json);
    }
    const summary = try std.fmt.allocPrint(ctx.gpa, "Observed {d} DNS {s} for {s}.", .{ rows.items.len, if (rows.items.len == 1) "record" else "records", domain });
    defer ctx.gpa.free(summary);
    _ = try ctx.db.insertSnapshot("cloudflare", "dns", domain, "ok", summary, redacted, null);
    try ctx.db.exec("COMMIT");
    committed = true;
    try ctx.db.insertAudit("cloudflare.dns.refresh", "ok", summary);
}

const EnvelopeResult = enum { array, object };

fn validCloudflareEnvelope(gpa: Allocator, body: []const u8, expected: EnvelopeResult) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const success = parsed.value.object.get("success") orelse return false;
    if (success != .bool or !success.bool) return false;
    const result = parsed.value.object.get("result") orelse return false;
    return switch (expected) {
        .array => result == .array,
        .object => result == .object,
    };
}

fn recordRefreshAttempt(ctx: Context, domain: []const u8, status: []const u8, summary: []const u8, raw: ?[]const u8) !void {
    _ = try ctx.db.insertSnapshot("cloudflare", "dns", domain, status, summary, raw, null);
    try ctx.db.insertAudit("cloudflare.dns.refresh", status, summary);
}

fn requireAcceptedMutation(gpa: Allocator, body: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return error.DnsProviderUnavailable;
    defer parsed.deinit();
    if (parsed.value != .object) return error.DnsProviderUnavailable;
    const ok = core_json.fieldBool(parsed.value, "ok") orelse false;
    const status = core_json.fieldInt(parsed.value, "status") orelse 0;
    if (!ok) return if (status == 0) error.DnsProviderUnavailable else error.DnsProviderRejected;
    const result = core_json.field(parsed.value, "result") orelse return error.DnsProviderRejected;
    if (!validCloudflareValue(result)) return error.DnsProviderRejected;
}

fn validCloudflareValue(value: std.json.Value) bool {
    if (value != .object) return false;
    const success = value.object.get("success") orelse return false;
    return success == .bool and success.bool;
}

fn providerContext(ctx: Context) app_provider_writes.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .write_meta = ctx.write_meta,
    };
}

fn recordJson(gpa: Allocator, record: PreparedRecord) ![]u8 {
    var output = std.Io.Writer.Allocating.init(gpa);
    defer output.deinit();
    try output.writer.writeByte('{');
    try core_json.writeStringField(&output.writer, "type", record.record_type, true);
    try core_json.writeStringField(&output.writer, "name", record.name, true);
    try core_json.writeStringField(&output.writer, "content", record.content, true);
    try core_json.writeIntField(&output.writer, "ttl", record.ttl, true);
    try core_json.writeBoolField(&output.writer, "proxied", record.proxied, false);
    try output.writer.writeByte('}');
    return try output.toOwnedSlice();
}

fn prepareRecord(gpa: Allocator, domain: []const u8, input: RecordInput) !PreparedRecord {
    const record_type = std.mem.trim(u8, input.record_type, " \t\r\n");
    const content = std.mem.trim(u8, input.content, " \t\r\n");
    if (!supportedType(record_type) or content.len == 0 or content.len > 4096) return error.InvalidDnsRequest;
    if (input.ttl != 1 and (input.ttl < 60 or input.ttl > 86_400)) return error.InvalidDnsRequest;
    if (input.proxied and !proxyableType(record_type)) return error.InvalidDnsRequest;
    if (std.mem.eql(u8, record_type, "A") and !validIpv4(content)) return error.InvalidDnsRequest;
    if (std.mem.eql(u8, record_type, "AAAA") and !validIpv6Shape(content)) return error.InvalidDnsRequest;
    if (std.mem.eql(u8, record_type, "CNAME") and !validDnsName(content, false)) return error.InvalidDnsRequest;
    const name = try canonicalRecordName(gpa, domain, input.name);
    return .{
        .record_type = record_type,
        .name = name,
        .content = content,
        .ttl = input.ttl,
        .proxied = input.proxied,
    };
}

fn canonicalRecordName(gpa: Allocator, domain: []const u8, raw: []const u8) ![]u8 {
    const name = std.mem.trim(u8, raw, " \t\r\n");
    if (name.len == 0 or name.len > 253) return error.InvalidDnsRequest;
    if (std.mem.eql(u8, name, "@")) return try gpa.dupe(u8, domain);
    if (!validDnsName(name, true)) return error.InvalidDnsRequest;
    if (std.ascii.eqlIgnoreCase(name, domain) or
        (name.len > domain.len + 1 and std.ascii.endsWithIgnoreCase(name, domain) and name[name.len - domain.len - 1] == '.'))
        return try gpa.dupe(u8, name);
    if (std.mem.indexOfScalar(u8, name, '.') != null) return error.InvalidDnsRequest;
    return try std.fmt.allocPrint(gpa, "{s}.{s}", .{ name, domain });
}

fn supportedType(value: []const u8) bool {
    return std.mem.eql(u8, value, "A") or std.mem.eql(u8, value, "AAAA") or
        std.mem.eql(u8, value, "CNAME") or std.mem.eql(u8, value, "TXT");
}

fn proxyableType(value: []const u8) bool {
    return std.mem.eql(u8, value, "A") or std.mem.eql(u8, value, "AAAA") or std.mem.eql(u8, value, "CNAME");
}

fn validDnsName(value: []const u8, allow_wildcard: bool) bool {
    if (value.len == 0 or value.len > 253 or value[0] == '.' or value[value.len - 1] == '.') return false;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_') continue;
        if (allow_wildcard and byte == '*') continue;
        return false;
    }
    return true;
}

fn validIpv4(value: []const u8) bool {
    var parts = std.mem.splitScalar(u8, value, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0 or part.len > 3) return false;
        const octet = std.fmt.parseInt(u8, part, 10) catch return false;
        _ = octet;
        count += 1;
    }
    return count == 4;
}

fn validIpv6Shape(value: []const u8) bool {
    if (std.mem.indexOfScalar(u8, value, ':') == null) return false;
    for (value) |byte| if (!(std.ascii.isHex(byte) or byte == ':' or byte == '.')) return false;
    return true;
}

fn selectedDomain(configured: []const []const u8, requested: ?[]const u8) []const u8 {
    if (requested) |value| return configuredDomain(configured, value) orelse "";
    return if (configured.len > 0) configured[0] else "";
}

fn configuredDomain(configured: []const []const u8, requested: []const u8) ?[]const u8 {
    for (configured) |domain| if (std.ascii.eqlIgnoreCase(domain, requested)) return domain;
    return null;
}

fn findZone(zones: []const db_store.CloudflareZoneRow, domain: []const u8) ?db_store.CloudflareZoneRow {
    for (zones) |zone| if (std.ascii.eqlIgnoreCase(zone.name, domain)) return zone;
    return null;
}

fn findRecord(records: []const db_store.CloudflareDnsRecordRow, zone_id: []const u8, record_id: []const u8) ?db_store.CloudflareDnsRecordRow {
    for (records) |record| if (std.mem.eql(u8, record.zone_id, zone_id) and std.mem.eql(u8, record.id, record_id)) return record;
    return null;
}

fn capabilityReason(domain: []const u8, has_auth: bool, has_zone: bool, freshness: observation.Freshness, latest: ?db_store.Observation) []const u8 {
    if (domain.len == 0) return "Choose a configured DNS zone.";
    if (!has_auth) return "Cloudflare credentials are not configured; stored records are read-only.";
    if (!has_zone) return "Refresh this configured zone to resolve its exact Cloudflare identity.";
    if (latest == null or !latest.?.hasSuccessfulObservation()) return "Refresh this zone successfully before changing records.";
    if (!std.mem.eql(u8, latest.?.attempt_status, "ok")) return "The latest refresh failed; retained records are read-only.";
    if (freshness != .current) return "The observation is stale; refresh this zone before changing records.";
    return "Cloudflare access and the exact zone identity were confirmed by the current observation.";
}

test "DNS record validation and observation capability are bounded" {
    const allocator = std.testing.allocator;
    var valid = try prepareRecord(allocator, "example.test", .{
        .record_type = "A",
        .name = "www",
        .content = "192.0.2.10",
        .ttl = 60,
        .proxied = true,
    });
    defer valid.deinit(allocator);
    try std.testing.expectEqualStrings("www.example.test", valid.name);
    try std.testing.expectError(error.InvalidDnsRequest, prepareRecord(allocator, "example.test", .{
        .record_type = "A",
        .name = "www",
        .content = "999.0.2.10",
        .ttl = 60,
        .proxied = false,
    }));
    try std.testing.expectError(error.InvalidDnsRequest, prepareRecord(allocator, "example.test", .{
        .record_type = "TXT",
        .name = "_check",
        .content = "value",
        .ttl = 2,
        .proxied = false,
    }));
}
