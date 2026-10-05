const std = @import("std");
const db_store = @import("db_store");
const provider_cloudflare_models = @import("provider_cloudflare_models");
const provider_hostinger_models = @import("provider_hostinger_models");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Counts = struct {
    resources: usize = 0,
    typed_rows: usize = 0,
};

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

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

