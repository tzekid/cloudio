const std = @import("std");
const sqlite = @import("sqlite");
const db_schema = @import("db_schema");
const models = @import("models.zig");
const helpers = @import("helpers.zig");
const connection = @import("connection.zig");

pub const Db = connection.Db;
pub const DbError = models.DbError;
pub const SnapshotSummary = models.SnapshotSummary;
pub const SnapshotSummaries = models.SnapshotSummaries;
pub const NameValueRow = models.NameValueRow;
pub const NameValueRows = models.NameValueRows;
pub const InventoryFilter = models.InventoryFilter;
pub const InventoryItem = models.InventoryItem;
pub const InventoryItems = models.InventoryItems;
pub const InventoryFacet = models.InventoryFacet;
pub const InventoryFacets = models.InventoryFacets;
pub const ProjectDetails = models.ProjectDetails;
pub const ProjectCorrelation = models.ProjectCorrelation;
pub const ProjectCorrelations = models.ProjectCorrelations;
pub const TopologyRow = models.TopologyRow;
pub const TopologyRows = models.TopologyRows;
pub const SecretScanSurface = models.SecretScanSurface;
pub const secret_scan_surfaces = models.secret_scan_surfaces;
pub const MetricRow = models.MetricRow;
pub const MetricRows = models.MetricRows;
pub const CloudflareAccountRow = models.CloudflareAccountRow;
pub const CloudflareAccountRows = models.CloudflareAccountRows;
pub const CloudflareZoneRow = models.CloudflareZoneRow;
pub const CloudflareZoneRows = models.CloudflareZoneRows;
pub const CloudflareDnsRecordRow = models.CloudflareDnsRecordRow;
pub const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
pub const ContainerRow = models.ContainerRow;
pub const ContainerRows = models.ContainerRows;
pub const CloudflareKindCount = models.CloudflareKindCount;
pub const CloudflareKindCounts = models.CloudflareKindCounts;
pub const CloudflareResourceHintRow = models.CloudflareResourceHintRow;
pub const CloudflareResourceHintRows = models.CloudflareResourceHintRows;
pub const CloudflareInventoryHintRow = models.CloudflareInventoryHintRow;
pub const CloudflareInventoryHintRows = models.CloudflareInventoryHintRows;
pub const HostingerVpsRow = models.HostingerVpsRow;
pub const HostingerVpsRows = models.HostingerVpsRows;
pub const HostingerResourceHintRow = models.HostingerResourceHintRow;
pub const HostingerResourceHintRows = models.HostingerResourceHintRows;
pub const HostingerInventoryHintRow = models.HostingerInventoryHintRow;
pub const HostingerInventoryHintRows = models.HostingerInventoryHintRows;
pub const HostingerKindCount = models.HostingerKindCount;
pub const HostingerKindCounts = models.HostingerKindCounts;
pub const HostingerMetricSummary = models.HostingerMetricSummary;
pub const HostingerMetricSummaries = models.HostingerMetricSummaries;
pub const HostingerVpsFamilySummary = models.HostingerVpsFamilySummary;
pub const HostingerVpsFamilySummaries = models.HostingerVpsFamilySummaries;
pub const AuditEvent = models.AuditEvent;
pub const AuditEvents = models.AuditEvents;
pub const ProviderEvidenceFilter = models.ProviderEvidenceFilter;
pub const ProviderEvidenceEvent = models.ProviderEvidenceEvent;
pub const ProviderEvidenceEvents = models.ProviderEvidenceEvents;
pub const ProviderEvidenceSummaryRow = models.ProviderEvidenceSummaryRow;
pub const ProviderEvidenceSummaryRows = models.ProviderEvidenceSummaryRows;
pub const RouteCaptureEvidenceFilter = models.RouteCaptureEvidenceFilter;
pub const RouteCaptureEvidenceRow = models.RouteCaptureEvidenceRow;
pub const RouteCaptureEvidenceRows = models.RouteCaptureEvidenceRows;
pub const RouteSourceEvidenceRow = models.RouteSourceEvidenceRow;
pub const RouteSourceEvidenceRows = models.RouteSourceEvidenceRows;
pub const columnText = helpers.columnText;

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
