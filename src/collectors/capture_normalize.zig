const std = @import("std");
const db_store = @import("db_store");
const provider_cloudflare_models = @import("provider_cloudflare_models");
const provider_hostinger_models = @import("provider_hostinger_models");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Counts = struct {
    resources: usize = 0,
    typed_rows: usize = 0,
};

pub fn normalizeRouteCapture(
    gpa: Allocator,
    db: *Db,
    route: provider_routes.Route,
    request: provider_routes.Request,
    kind: []const u8,
    explicit_target: ?[]const u8,
    status_code: u16,
    redacted_body: []const u8,
) !Counts {
    if (status_code < 200 or status_code >= 300) return .{};
    return switch (route.provider) {
        .cloudflare => try normalizeCloudflareRouteModels(gpa, db, route, request, kind, redacted_body),
        .hostinger => try normalizeHostingerRouteModels(gpa, db, route, request, kind, explicit_target, redacted_body),
    };
}

fn normalizeCloudflareRouteModels(gpa: Allocator, db: *Db, route: provider_routes.Route, request: provider_routes.Request, kind: []const u8, redacted_body: []const u8) !Counts {
    const scope = cloudflareRouteScope(route, request);
    const persisted = try persistCloudflareResourceRows(gpa, db, kind, scope.name, scope.id, redacted_body);
    const security_rows = if (isCloudflareSecurityRouteTag(route.tag))
        try normalizeCloudflareSecurityRows(gpa, db, kind, scope.name, scope.id, redacted_body)
    else
        0;
    return .{
        .resources = persisted.resources,
        .typed_rows = persisted.typed_rows + security_rows + try normalizeCloudflareTypedRows(gpa, db, route, request, redacted_body),
    };
}

fn normalizeHostingerRouteModels(gpa: Allocator, db: *Db, route: provider_routes.Route, request: provider_routes.Request, kind: []const u8, explicit_target: ?[]const u8, redacted_body: []const u8) !Counts {
    const target = explicit_target orelse firstPathParamValue(request) orelse route.operation_id orelse route.path_template;
    const persisted = try persistHostingerResourceRows(gpa, db, kind, target, redacted_body);
    return .{
        .resources = persisted.resources,
        .typed_rows = persisted.typed_rows + try normalizeHostingerTypedRows(gpa, db, route, redacted_body),
    };
}

fn normalizeCloudflareTypedRows(gpa: Allocator, db: *Db, route: provider_routes.Route, request: provider_routes.Request, redacted_body: []const u8) !usize {
    if (route.method != .GET) return 0;
    if (std.mem.eql(u8, route.path_template, "/accounts")) {
        var rows = try provider_cloudflare_models.parseAccountRows(gpa, redacted_body);
        defer rows.deinit(gpa);
        for (rows.items) |row| try db.upsertCloudflareAccount(row.id, row.name, row.typ, row.status, row.raw_json);
        return rows.items.len;
    }
    if (std.mem.eql(u8, route.path_template, "/zones") or std.mem.eql(u8, route.path_template, "/zones/{zone_id}")) {
        var rows = try provider_cloudflare_models.parseZoneRows(gpa, redacted_body);
        defer rows.deinit(gpa);
        for (rows.items) |row| try db.upsertCloudflareZone(row.id, row.name, row.account_id, row.status, row.paused, row.typ, row.name_servers, row.raw_json);
        return rows.items.len;
    }
    if (std.mem.startsWith(u8, route.path_template, "/zones/{zone_id}/dns_records")) {
        const zone_id = pathParamValue(request, "zone_id") orelse return 0;
        var rows = try provider_cloudflare_models.parseDnsRecordRows(gpa, zone_id, redacted_body);
        defer rows.deinit(gpa);
        for (rows.items) |row| try db.upsertDnsRecord(row.id, row.zone_id, row.name, row.typ, row.content, row.ttl, row.proxied, row.raw_json);
        return rows.items.len;
    }
    return 0;
}

pub fn persistCloudflareResourceRows(gpa: Allocator, db: *Db, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, redacted_body: []const u8) !Counts {
    var rows = try provider_cloudflare_models.parseResourceRows(gpa, kind, scope, scope_id, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertCloudflareResource(row.key, row.kind, row.resource_id, row.scope, row.scope_id, row.name, row.status, row.resource_type, row.raw_json);
    }
    return .{
        .resources = rows.items.len,
        .typed_rows = try persistCloudflareInventoryRows(gpa, db, kind, scope, scope_id, redacted_body),
    };
}

pub fn persistCloudflareInventoryRows(gpa: Allocator, db: *Db, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, redacted_body: []const u8) !usize {
    var rows = try provider_cloudflare_models.parseInventoryRows(gpa, kind, scope, scope_id, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertCloudflareInventoryItem(
            row.key,
            row.kind,
            row.resource_id,
            row.scope,
            row.scope_id,
            row.name,
            row.status,
            row.category,
            row.domain,
            row.account_id,
            row.zone_id,
            row.related_id,
            row.flag,
            row.created_at,
            row.updated_at,
            row.expires_at,
            row.raw_json,
        );
    }
    return rows.items.len;
}

fn normalizeCloudflareSecurityRows(gpa: Allocator, db: *Db, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, redacted_body: []const u8) !usize {
    var rows = try provider_cloudflare_models.parseSecurityRows(gpa, kind, scope, scope_id, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertCloudflareSecurityItem(
            row.key,
            row.kind,
            row.resource_id,
            row.scope,
            row.scope_id,
            row.name,
            row.status,
            row.category,
            row.severity,
            row.action,
            row.domain,
            row.account_id,
            row.zone_id,
            row.related_id,
            row.flag,
            row.created_at,
            row.updated_at,
            row.expires_at,
            row.raw_json,
        );
    }
    return rows.items.len;
}

fn normalizeHostingerTypedRows(gpa: Allocator, db: *Db, route: provider_routes.Route, redacted_body: []const u8) !usize {
    if (route.method != .GET) return 0;
    if (!std.mem.startsWith(u8, route.path_template, "/api/vps/v1/virtual-machines")) return 0;
    var rows = try provider_hostinger_models.parseVpsRows(gpa, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| try db.upsertHostingerVps(row.id, row.name, row.status, row.ipv4, row.plan, row.raw_json);
    return rows.items.len;
}

pub fn persistHostingerResourceRows(gpa: Allocator, db: *Db, kind: []const u8, target: ?[]const u8, redacted_body: []const u8) !Counts {
    var rows = try provider_hostinger_models.parseResourceRows(gpa, kind, target, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertHostingerResource(row.key, row.kind, row.resource_id, row.target, row.name, row.status, row.domain, row.raw_json);
    }
    return .{
        .resources = rows.items.len,
        .typed_rows = try persistHostingerInventoryRows(gpa, db, kind, target, redacted_body),
    };
}

pub fn persistHostingerInventoryRows(gpa: Allocator, db: *Db, kind: []const u8, target: ?[]const u8, redacted_body: []const u8) !usize {
    var rows = try provider_hostinger_models.parseInventoryRows(gpa, kind, target, redacted_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertHostingerInventoryItem(
            row.key,
            row.kind,
            row.resource_id,
            row.name,
            row.status,
            row.category,
            row.domain,
            row.username,
            row.related_id,
            row.flag,
            row.created_at,
            row.updated_at,
            row.expires_at,
            row.raw_json,
        );
    }
    return rows.items.len;
}

const CloudflareRouteScope = struct {
    name: ?[]const u8,
    id: ?[]const u8,
};

fn cloudflareRouteScope(route: provider_routes.Route, request: provider_routes.Request) CloudflareRouteScope {
    if (pathParamValue(request, "account_id")) |id| return .{ .name = "account", .id = id };
    if (pathParamValue(request, "accounts_id")) |id| return .{ .name = "account", .id = id };
    if (pathParamValue(request, "account_identifier")) |id| return .{ .name = "account", .id = id };
    if (pathParamValue(request, "zone_id")) |id| return .{ .name = "zone", .id = id };
    if (pathParamValue(request, "zones_id")) |id| return .{ .name = "zone", .id = id };
    if (pathParamValue(request, "zone_identifier")) |id| return .{ .name = "zone", .id = id };
    if (std.mem.startsWith(u8, route.path_template, "/user") or std.mem.indexOf(u8, route.path_template, "/memberships") != null) {
        return .{ .name = "user", .id = null };
    }
    if (std.mem.startsWith(u8, route.path_template, "/ips")) return .{ .name = "global", .id = null };
    return .{ .name = null, .id = null };
}

fn pathParamValue(request: provider_routes.Request, name: []const u8) ?[]const u8 {
    for (request.path_params) |param| {
        if (std.mem.eql(u8, param.name, name)) return param.value;
    }
    return null;
}

fn firstPathParamValue(request: provider_routes.Request) ?[]const u8 {
    if (request.path_params.len == 0) return null;
    return request.path_params[0].value;
}

fn isCloudflareSecurityRouteTag(tag: []const u8) bool {
    const needles = [_][]const u8{
        "Email Security",
        "Security Center",
        "Leaked Credential",
        "Page Shield",
        "Bot",
        "Botnet",
        "DNS Firewall",
        "IP Access",
        "WAF",
        "Firewall",
        "API Gateway",
        "Schema Validation",
        "Token Validation",
        "Vulnerability Scanner",
        "AI Security",
        "security.txt",
    };
    for (needles) |needle| {
        if (containsIgnoreCase(tag, needle)) return true;
    }
    return false;
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
