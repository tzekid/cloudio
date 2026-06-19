const std = @import("std");
const app_provider_api = @import("app_provider_api");
const app_render = @import("app_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const positiveLimit = app_render.positiveLimit;
const writeJsonStringField = app_render.writeJsonStringField;
const writeTextField = app_render.writeTextField;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

pub const OverviewOptions = struct {
    limit: i64 = 20,
    snapshot_limit: i64 = 12,
};

pub const CloudflareFamily = enum {
    accounts,
    zones,
    dns,
    tls,
    access,
    tunnels,
    rulesets,
    logs,
    cache,
    security,
    email,
    load_balancing,
    health,
    tokens_memberships,
    other,

    fn label(self: CloudflareFamily) []const u8 {
        return switch (self) {
            .accounts => "accounts",
            .zones => "zones",
            .dns => "dns",
            .tls => "tls",
            .access => "access",
            .tunnels => "tunnels",
            .rulesets => "rulesets",
            .logs => "logs",
            .cache => "cache",
            .security => "security",
            .email => "email",
            .load_balancing => "load_balancing",
            .health => "health",
            .tokens_memberships => "tokens_memberships",
            .other => "other",
        };
    }
};

const cloudflare_api_family_labels = [_][]const u8{
    "accounts",
    "zones",
    "dns",
    "tls",
    "access",
    "tunnels",
    "rulesets",
    "logs",
    "cache",
    "security",
    "email",
    "load_balancing",
    "health",
    "tokens_memberships",
    "other",
};

pub const CloudflareFamilySummary = struct {
    accounts: i64 = 0,
    zones: i64 = 0,
    dns: i64 = 0,
    tls: i64 = 0,
    access: i64 = 0,
    tunnels: i64 = 0,
    rulesets: i64 = 0,
    logs: i64 = 0,
    cache: i64 = 0,
    security: i64 = 0,
    email: i64 = 0,
    load_balancing: i64 = 0,
    health: i64 = 0,
    tokens_memberships: i64 = 0,
    other: i64 = 0,

    fn add(self: *CloudflareFamilySummary, family: CloudflareFamily, count: i64) void {
        switch (family) {
            .accounts => self.accounts += count,
            .zones => self.zones += count,
            .dns => self.dns += count,
            .tls => self.tls += count,
            .access => self.access += count,
            .tunnels => self.tunnels += count,
            .rulesets => self.rulesets += count,
            .logs => self.logs += count,
            .cache => self.cache += count,
            .security => self.security += count,
            .email => self.email += count,
            .load_balancing => self.load_balancing += count,
            .health => self.health += count,
            .tokens_memberships => self.tokens_memberships += count,
            .other => self.other += count,
        }
    }
};

pub const OverviewSummary = struct {
    accounts: i64 = 0,
    zones: i64 = 0,
    active_zones: usize = 0,
    paused_zones: usize = 0,
    dns_records: i64 = 0,
    proxied_dns_records: usize = 0,
    dns_only_records: usize = 0,
    resources: i64 = 0,
    inventory_items: i64 = 0,
    security_items: i64 = 0,
    resource_kinds: usize = 0,
    inventory_kinds: usize = 0,
    security_kinds: usize = 0,
    inventory_facets: usize = 0,
    recent_snapshots: usize = 0,
    families: CloudflareFamilySummary = .{},
    api_routes: usize = 0,
    api_read_routes: usize = 0,
    api_dry_run_routes: usize = 0,
    api_write_routes: usize = 0,
    api_not_applicable_routes: usize = 0,
    api_deprecated_routes: usize = 0,
    api_blocked_permission_routes: usize = 0,
    api_families: usize = 0,
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    blocked_or_missing_families: usize = 0,
};

pub const Overview = struct {
    accounts: db_store.CloudflareAccountRows,
    zones: db_store.CloudflareZoneRows,
    dns_records: db_store.CloudflareDnsRecordRows,
    resource_kinds: db_store.CloudflareKindCounts,
    inventory_kinds: db_store.CloudflareKindCounts,
    security_kinds: db_store.CloudflareKindCounts,
    inventory_facets: db_store.InventoryFacets,
    recent_snapshots: db_store.SnapshotSummaries,
    summary_zones: db_store.CloudflareZoneRows,
    summary_dns_records: db_store.CloudflareDnsRecordRows,
    summary_resource_kinds: db_store.CloudflareKindCounts,
    summary_inventory_kinds: db_store.CloudflareKindCounts,
    summary_security_kinds: db_store.CloudflareKindCounts,
    summary_inventory_facets: db_store.InventoryFacets,
    summary_snapshots: db_store.SnapshotSummaries,
    api_family_summaries: app_provider_api.ApiFamilySummaries,
    account_count: i64,
    resource_count: i64,
    inventory_count: i64,
    security_count: i64,

    pub fn load(ctx: Context, options: OverviewOptions) !Overview {
        const limit = positiveLimit(options.limit, 20);
        var accounts = try ctx.db.cloudflareAccountRows(ctx.gpa, limit);
        errdefer accounts.deinit(ctx.gpa);
        var zones = try ctx.db.cloudflareZoneRows(ctx.gpa, limit);
        errdefer zones.deinit(ctx.gpa);
        var dns_records = try ctx.db.cloudflareDnsRecordRows(ctx.gpa, limit);
        errdefer dns_records.deinit(ctx.gpa);
        var resource_kinds = try ctx.db.cloudflareResourceKindCounts(ctx.gpa, limit);
        errdefer resource_kinds.deinit(ctx.gpa);
        var inventory_kinds = try ctx.db.cloudflareInventoryKindCounts(ctx.gpa, limit);
        errdefer inventory_kinds.deinit(ctx.gpa);
        var security_kinds = try ctx.db.cloudflareSecurityKindCounts(ctx.gpa, limit);
        errdefer security_kinds.deinit(ctx.gpa);
        var inventory_facets = try ctx.db.inventoryFacets(ctx.gpa, .{
            .provider = "cloudflare",
            .limit = limit,
        });
        errdefer inventory_facets.deinit(ctx.gpa);
        var recent_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "cloudflare", positiveLimit(options.snapshot_limit, 12));
        errdefer recent_snapshots.deinit(ctx.gpa);
        var summary_zones = try ctx.db.cloudflareZoneRows(ctx.gpa, 5000);
        errdefer summary_zones.deinit(ctx.gpa);
        var summary_dns_records = try ctx.db.cloudflareDnsRecordRows(ctx.gpa, 5000);
        errdefer summary_dns_records.deinit(ctx.gpa);
        var summary_resource_kinds = try ctx.db.cloudflareResourceKindCounts(ctx.gpa, 5000);
        errdefer summary_resource_kinds.deinit(ctx.gpa);
        var summary_inventory_kinds = try ctx.db.cloudflareInventoryKindCounts(ctx.gpa, 5000);
        errdefer summary_inventory_kinds.deinit(ctx.gpa);
        var summary_security_kinds = try ctx.db.cloudflareSecurityKindCounts(ctx.gpa, 5000);
        errdefer summary_security_kinds.deinit(ctx.gpa);
        var summary_inventory_facets = try ctx.db.inventoryFacets(ctx.gpa, .{
            .provider = "cloudflare",
            .limit = 5000,
        });
        errdefer summary_inventory_facets.deinit(ctx.gpa);
        var summary_snapshots = try ctx.db.snapshotsForSource(ctx.gpa, "cloudflare", 5000);
        errdefer summary_snapshots.deinit(ctx.gpa);
        var api_family_summaries = try loadCloudflareApiFamilySummaries(ctx.io, ctx.gpa);
        errdefer api_family_summaries.deinit(ctx.gpa);
        const account_count = try ctx.db.countTable("cloudflare_accounts");
        addCloudflareObserved(&api_family_summaries, .accounts, account_count);
        addCloudflareObserved(&api_family_summaries, .zones, @intCast(summary_zones.items.len));
        addCloudflareObserved(&api_family_summaries, .dns, @intCast(summary_dns_records.items.len));
        for (summary_resource_kinds.items) |row| addCloudflareObservedForKind(&api_family_summaries, row.kind, row.count);
        for (summary_inventory_facets.items) |row| addCloudflareObservedForKind(&api_family_summaries, row.kind, row.count);
        for (summary_security_kinds.items) |row| addCloudflareObservedForKind(&api_family_summaries, row.kind, row.count);
        for (summary_snapshots.items) |row| addCloudflareObservedForKind(&api_family_summaries, row.kind, 1);
        return .{
            .accounts = accounts,
            .zones = zones,
            .dns_records = dns_records,
            .resource_kinds = resource_kinds,
            .inventory_kinds = inventory_kinds,
            .security_kinds = security_kinds,
            .inventory_facets = inventory_facets,
            .recent_snapshots = recent_snapshots,
            .summary_zones = summary_zones,
            .summary_dns_records = summary_dns_records,
            .summary_resource_kinds = summary_resource_kinds,
            .summary_inventory_kinds = summary_inventory_kinds,
            .summary_security_kinds = summary_security_kinds,
            .summary_inventory_facets = summary_inventory_facets,
            .summary_snapshots = summary_snapshots,
            .api_family_summaries = api_family_summaries,
            .account_count = account_count,
            .resource_count = try ctx.db.countTable("cloudflare_resources"),
            .inventory_count = try ctx.db.countTable("cloudflare_inventory_items"),
            .security_count = try ctx.db.countTable("cloudflare_security_items"),
        };
    }

    pub fn deinit(self: *Overview, allocator: Allocator) void {
        self.accounts.deinit(allocator);
        self.zones.deinit(allocator);
        self.dns_records.deinit(allocator);
        self.resource_kinds.deinit(allocator);
        self.inventory_kinds.deinit(allocator);
        self.security_kinds.deinit(allocator);
        self.inventory_facets.deinit(allocator);
        self.recent_snapshots.deinit(allocator);
        self.summary_zones.deinit(allocator);
        self.summary_dns_records.deinit(allocator);
        self.summary_resource_kinds.deinit(allocator);
        self.summary_inventory_kinds.deinit(allocator);
        self.summary_security_kinds.deinit(allocator);
        self.summary_inventory_facets.deinit(allocator);
        self.summary_snapshots.deinit(allocator);
        self.api_family_summaries.deinit(allocator);
    }

    pub fn summary(self: Overview) OverviewSummary {
        const api_totals = self.api_family_summaries.routeTotals();
        const status_totals = self.api_family_summaries.statusTotals();
        var out = OverviewSummary{
            .accounts = self.account_count,
            .zones = @intCast(self.summary_zones.items.len),
            .dns_records = @intCast(self.summary_dns_records.items.len),
            .resources = self.resource_count,
            .inventory_items = self.inventory_count,
            .security_items = self.security_count,
            .resource_kinds = self.summary_resource_kinds.items.len,
            .inventory_kinds = self.summary_inventory_kinds.items.len,
            .security_kinds = self.summary_security_kinds.items.len,
            .inventory_facets = self.summary_inventory_facets.items.len,
            .recent_snapshots = self.recent_snapshots.items.len,
            .api_routes = api_totals.official_routes,
            .api_read_routes = api_totals.read_routes,
            .api_dry_run_routes = api_totals.dry_run_routes,
            .api_write_routes = api_totals.write_routes,
            .api_not_applicable_routes = api_totals.not_applicable_routes,
            .api_deprecated_routes = api_totals.deprecated_routes,
            .api_blocked_permission_routes = api_totals.blocked_permission_routes,
            .api_families = self.api_family_summaries.items.len,
            .observed_read_families = status_totals.observed_read_families,
            .missing_read_families = status_totals.missing_read_families,
            .blocked_or_missing_families = status_totals.blocked_or_missing_families,
        };
        for (self.summary_zones.items) |row| {
            if (std.ascii.eqlIgnoreCase(row.status, "active")) out.active_zones += 1;
            if (std.ascii.eqlIgnoreCase(row.paused, "true")) out.paused_zones += 1;
        }
        for (self.summary_dns_records.items) |row| {
            if (std.ascii.eqlIgnoreCase(row.proxied, "true")) {
                out.proxied_dns_records += 1;
            } else if (std.ascii.eqlIgnoreCase(row.proxied, "false")) {
                out.dns_only_records += 1;
            }
        }
        for (self.summary_resource_kinds.items) |row| {
            out.families.add(cloudflareFamilyForKind(row.kind), row.count);
        }
        for (self.summary_inventory_facets.items) |row| {
            out.families.add(cloudflareFamilyForKind(row.kind), row.count);
        }
        for (self.summary_security_kinds.items) |row| {
            out.families.add(cloudflareFamilyForKind(row.kind), row.count);
        }
        return out;
    }

    pub fn writeText(self: Overview, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Cloudflare overview\n");
        try writeOverviewSummaryText(counts, writer);
        try writer.writeAll("accounts\n");
        if (self.accounts.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.accounts.items) |row| try writeAccountText(row, writer);
        }

        try writer.writeAll("zones\n");
        if (self.zones.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.zones.items) |row| try writeZoneText(row, writer);
        }

        try writer.writeAll("dns records\n");
        if (self.dns_records.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.dns_records.items) |row| try writeDnsRecordText(row, writer);
        }

        try writer.writeAll("inventory facets\n");
        if (self.inventory_facets.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.inventory_facets.items) |row| try writeInventoryFacetText(row, writer);
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

        try writer.writeAll("security\n");
        if (self.security_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.security_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("api families\n");
        for (self.api_family_summaries.items) |row| try app_provider_api.writeApiFamilySummaryText(row, writer);

        try writer.writeAll("recent snapshots\n");
        if (self.recent_snapshots.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.recent_snapshots.items) |row| try writeSnapshotText(row, writer);
        }
    }

    pub fn writeJson(self: Overview, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"cloudflare_overview\",\"summary\":");
        try writeOverviewSummaryJson(self.summary(), writer);
        try writer.writeAll(",\"accounts\":[");
        for (self.accounts.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeAccountJson(row, writer);
        }
        try writer.writeAll("],\"zones\":[");
        for (self.zones.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeZoneJson(row, writer);
        }
        try writer.writeAll("],\"dns_records\":[");
        for (self.dns_records.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeDnsRecordJson(row, writer);
        }
        try writer.writeAll("],\"inventory_facets\":[");
        for (self.inventory_facets.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeInventoryFacetJson(row, writer);
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
        try writer.writeAll("],\"security_kinds\":[");
        for (self.security_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"api_families\":[");
        for (self.api_family_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_provider_api.writeApiFamilySummaryJson(row, writer);
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

fn writeAccountText(row: db_store.CloudflareAccountRow, writer: anytype) !void {
    try writer.print("{s}", .{row.id});
    try writeTextField(writer, "name", row.name);
    try writeTextField(writer, "type", row.account_type);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "updated", row.updated_at);
    try writer.writeByte('\n');
}

fn writeZoneText(row: db_store.CloudflareZoneRow, writer: anytype) !void {
    try writer.print("{s}", .{row.id});
    try writeTextField(writer, "name", row.name);
    try writeTextField(writer, "account", row.account_id);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "paused", row.paused);
    try writeTextField(writer, "type", row.zone_type);
    try writeTextField(writer, "nameservers", row.name_servers);
    try writeTextField(writer, "updated", row.updated_at);
    try writer.writeByte('\n');
}

fn writeDnsRecordText(row: db_store.CloudflareDnsRecordRow, writer: anytype) !void {
    try writer.print("{s}", .{row.id});
    try writeTextField(writer, "zone", row.zone_id);
    try writeTextField(writer, "name", row.name);
    try writeTextField(writer, "type", row.record_type);
    try writeTextField(writer, "content", row.content);
    try writeTextField(writer, "ttl", row.ttl);
    try writeTextField(writer, "proxied", row.proxied);
    try writeTextField(writer, "updated", row.updated_at);
    try writer.writeByte('\n');
}

fn writeKindCountText(row: db_store.CloudflareKindCount, writer: anytype) !void {
    try writer.print("{s}\tcount={d}", .{ row.kind, row.count });
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeInventoryFacetText(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.print("{s}", .{row.kind});
    try writeTextField(writer, "family", cloudflareFamilyForKind(row.kind).label());
    try writer.print("\tcount={d}", .{row.count});
    if (row.domains != 0) try writer.print("\tdomains={d}", .{row.domains});
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "category", row.category);
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeSnapshotText(row: db_store.SnapshotSummary, writer: anytype) !void {
    try writer.print("{d}\t{s}/{s}", .{ row.id, row.source, row.kind });
    try writeTextField(writer, "target", row.target);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "summary", row.summary);
    try writeTextField(writer, "captured", row.captured_at);
    try writer.writeByte('\n');
}

fn loadCloudflareApiFamilySummaries(io: Io, gpa: Allocator) !app_provider_api.ApiFamilySummaries {
    return try app_provider_api.loadProvider(io, gpa, .{}, .cloudflare, .{
        .seed_labels = cloudflare_api_family_labels[0..],
        .classifier = cloudflareApiFamilyLabelForRoute,
    });
}

fn cloudflareApiFamilyLabelForRoute(route: app_provider_api.Route) ?[]const u8 {
    const tag_family = cloudflareFamilyForKind(route.tag);
    if (tag_family != .other) return tag_family.label();
    if (route.operation_id) |operation_id| {
        const operation_family = cloudflareFamilyForKind(operation_id);
        if (operation_family != .other) return operation_family.label();
    }
    const path_family = cloudflareFamilyForKind(route.path_template);
    return path_family.label();
}

fn addCloudflareObserved(summaries: *app_provider_api.ApiFamilySummaries, family: CloudflareFamily, count: i64) void {
    _ = summaries.addObservedByLabel(family.label(), count);
}

fn addCloudflareObservedForKind(summaries: *app_provider_api.ApiFamilySummaries, kind: []const u8, count: i64) void {
    addCloudflareObserved(summaries, cloudflareFamilyForKind(kind), count);
}

fn writeOverviewSummaryText(summary: OverviewSummary, writer: anytype) !void {
    try writer.print("summary accounts={d} zones={d} active_zones={d} paused_zones={d} dns_records={d} proxied_dns_records={d} dns_only_records={d} resources={d} inventory_items={d} security_items={d} resource_kinds={d} inventory_kinds={d} security_kinds={d} inventory_facets={d} recent_snapshots={d}\n", .{
        summary.accounts,
        summary.zones,
        summary.active_zones,
        summary.paused_zones,
        summary.dns_records,
        summary.proxied_dns_records,
        summary.dns_only_records,
        summary.resources,
        summary.inventory_items,
        summary.security_items,
        summary.resource_kinds,
        summary.inventory_kinds,
        summary.security_kinds,
        summary.inventory_facets,
        summary.recent_snapshots,
    });
    try writer.print("api_routes total={d} read={d} dry_run={d} write={d} not_applicable={d} deprecated={d} blocked_permission={d} families={d} observed_read_families={d} missing_read_families={d} blocked_or_missing_families={d}\n", .{
        summary.api_routes,
        summary.api_read_routes,
        summary.api_dry_run_routes,
        summary.api_write_routes,
        summary.api_not_applicable_routes,
        summary.api_deprecated_routes,
        summary.api_blocked_permission_routes,
        summary.api_families,
        summary.observed_read_families,
        summary.missing_read_families,
        summary.blocked_or_missing_families,
    });
    try writer.print("families accounts={d} zones={d} dns={d} tls={d} access={d} tunnels={d} rulesets={d} logs={d} cache={d} security={d} email={d} load_balancing={d} health={d} tokens_memberships={d} other={d}\n", .{
        summary.families.accounts,
        summary.families.zones,
        summary.families.dns,
        summary.families.tls,
        summary.families.access,
        summary.families.tunnels,
        summary.families.rulesets,
        summary.families.logs,
        summary.families.cache,
        summary.families.security,
        summary.families.email,
        summary.families.load_balancing,
        summary.families.health,
        summary.families.tokens_memberships,
        summary.families.other,
    });
}

fn writeAccountJson(row: db_store.CloudflareAccountRow, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "id", row.id, true);
    try writeJsonStringField(writer, "name", row.name, true);
    try writeJsonStringField(writer, "type", row.account_type, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeZoneJson(row: db_store.CloudflareZoneRow, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "id", row.id, true);
    try writeJsonStringField(writer, "name", row.name, true);
    try writeJsonStringField(writer, "account_id", row.account_id, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "paused", row.paused, true);
    try writeJsonStringField(writer, "type", row.zone_type, true);
    try writeJsonStringField(writer, "name_servers", row.name_servers, true);
    try writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeDnsRecordJson(row: db_store.CloudflareDnsRecordRow, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "id", row.id, true);
    try writeJsonStringField(writer, "zone_id", row.zone_id, true);
    try writeJsonStringField(writer, "name", row.name, true);
    try writeJsonStringField(writer, "type", row.record_type, true);
    try writeJsonStringField(writer, "content", row.content, true);
    try writeJsonStringField(writer, "ttl", row.ttl, true);
    try writeJsonStringField(writer, "proxied", row.proxied, true);
    try writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeKindCountJson(row: db_store.CloudflareKindCount, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeInventoryFacetJson(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "kind", row.kind, true);
    try writeJsonStringField(writer, "family", cloudflareFamilyForKind(row.kind).label(), true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "category", row.category, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonIntField(writer, "domains", row.domains, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeOverviewSummaryJson(summary: OverviewSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "accounts", summary.accounts, true);
    try app_render.writeJsonIntField(writer, "zones", summary.zones, true);
    try app_render.writeJsonIntField(writer, "active_zones", summary.active_zones, true);
    try app_render.writeJsonIntField(writer, "paused_zones", summary.paused_zones, true);
    try app_render.writeJsonIntField(writer, "dns_records", summary.dns_records, true);
    try app_render.writeJsonIntField(writer, "proxied_dns_records", summary.proxied_dns_records, true);
    try app_render.writeJsonIntField(writer, "dns_only_records", summary.dns_only_records, true);
    try app_render.writeJsonIntField(writer, "resources", summary.resources, true);
    try app_render.writeJsonIntField(writer, "inventory_items", summary.inventory_items, true);
    try app_render.writeJsonIntField(writer, "security_items", summary.security_items, true);
    try app_render.writeJsonIntField(writer, "resource_kinds", summary.resource_kinds, true);
    try app_render.writeJsonIntField(writer, "inventory_kinds", summary.inventory_kinds, true);
    try app_render.writeJsonIntField(writer, "security_kinds", summary.security_kinds, true);
    try app_render.writeJsonIntField(writer, "inventory_facets", summary.inventory_facets, true);
    try app_render.writeJsonIntField(writer, "recent_snapshots", summary.recent_snapshots, true);
    try app_render.writeJsonIntField(writer, "api_routes", summary.api_routes, true);
    try app_render.writeJsonIntField(writer, "api_read_routes", summary.api_read_routes, true);
    try app_render.writeJsonIntField(writer, "api_dry_run_routes", summary.api_dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "api_write_routes", summary.api_write_routes, true);
    try app_render.writeJsonIntField(writer, "api_not_applicable_routes", summary.api_not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "api_deprecated_routes", summary.api_deprecated_routes, true);
    try app_render.writeJsonIntField(writer, "api_blocked_permission_routes", summary.api_blocked_permission_routes, true);
    try app_render.writeJsonIntField(writer, "api_families", summary.api_families, true);
    try app_render.writeJsonIntField(writer, "observed_read_families", summary.observed_read_families, true);
    try app_render.writeJsonIntField(writer, "missing_read_families", summary.missing_read_families, true);
    try app_render.writeJsonIntField(writer, "blocked_or_missing_families", summary.blocked_or_missing_families, true);
    try writer.writeAll("\"families\":");
    try writeFamilySummaryJson(summary.families, writer);
    try writer.writeByte('}');
}

fn writeFamilySummaryJson(summary: CloudflareFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "accounts", summary.accounts, true);
    try app_render.writeJsonIntField(writer, "zones", summary.zones, true);
    try app_render.writeJsonIntField(writer, "dns", summary.dns, true);
    try app_render.writeJsonIntField(writer, "tls", summary.tls, true);
    try app_render.writeJsonIntField(writer, "access", summary.access, true);
    try app_render.writeJsonIntField(writer, "tunnels", summary.tunnels, true);
    try app_render.writeJsonIntField(writer, "rulesets", summary.rulesets, true);
    try app_render.writeJsonIntField(writer, "logs", summary.logs, true);
    try app_render.writeJsonIntField(writer, "cache", summary.cache, true);
    try app_render.writeJsonIntField(writer, "security", summary.security, true);
    try app_render.writeJsonIntField(writer, "email", summary.email, true);
    try app_render.writeJsonIntField(writer, "load_balancing", summary.load_balancing, true);
    try app_render.writeJsonIntField(writer, "health", summary.health, true);
    try app_render.writeJsonIntField(writer, "tokens_memberships", summary.tokens_memberships, true);
    try app_render.writeJsonIntField(writer, "other", summary.other, false);
    try writer.writeByte('}');
}

fn cloudflareFamilyForKind(kind: []const u8) CloudflareFamily {
    if (containsIgnoreCase(kind, "token") or
        containsIgnoreCase(kind, "membership") or
        containsIgnoreCase(kind, "permission") or
        containsIgnoreCase(kind, "role") or
        containsIgnoreCase(kind, "user-group") or
        containsIgnoreCase(kind, "user_group") or
        containsIgnoreCase(kind, "member"))
    {
        return .tokens_memberships;
    }
    if (containsIgnoreCase(kind, "email")) return .email;
    if (containsIgnoreCase(kind, "log") or containsIgnoreCase(kind, "audit")) return .logs;
    if (containsIgnoreCase(kind, "load-balanc") or containsIgnoreCase(kind, "load_balanc") or containsIgnoreCase(kind, "loadbalanc") or containsIgnoreCase(kind, "load balanc")) return .load_balancing;
    if (containsIgnoreCase(kind, "health")) return .health;
    if (containsIgnoreCase(kind, "tunnel")) return .tunnels;
    if (containsIgnoreCase(kind, "tls") or
        containsIgnoreCase(kind, "ssl") or
        containsIgnoreCase(kind, "certificate") or
        containsIgnoreCase(kind, "cert") or
        containsIgnoreCase(kind, "origin-ca") or
        containsIgnoreCase(kind, "origin ca"))
    {
        return .tls;
    }
    if (containsIgnoreCase(kind, "access") or containsIgnoreCase(kind, "zero-trust") or containsIgnoreCase(kind, "zero trust") or containsIgnoreCase(kind, "zerotrust") or containsIgnoreCase(kind, "gateway")) return .access;
    if (containsIgnoreCase(kind, "cache") or containsIgnoreCase(kind, "argo") or containsIgnoreCase(kind, "tiered")) return .cache;
    if (containsIgnoreCase(kind, "security") or
        containsIgnoreCase(kind, "waf") or
        containsIgnoreCase(kind, "firewall") or
        containsIgnoreCase(kind, "api-shield") or
        containsIgnoreCase(kind, "api shield") or
        containsIgnoreCase(kind, "page-shield") or
        containsIgnoreCase(kind, "page shield") or
        containsIgnoreCase(kind, "ip-access") or
        containsIgnoreCase(kind, "ip access") or
        containsIgnoreCase(kind, "posture"))
    {
        return .security;
    }
    if (containsIgnoreCase(kind, "ruleset") or containsIgnoreCase(kind, "rule")) return .rulesets;
    if (containsIgnoreCase(kind, "dns") or containsIgnoreCase(kind, "dnssec") or containsIgnoreCase(kind, "secondary-dns") or containsIgnoreCase(kind, "secondary dns")) return .dns;
    if (containsIgnoreCase(kind, "zone") or containsIgnoreCase(kind, "setting")) return .zones;
    if (containsIgnoreCase(kind, "account")) return .accounts;
    return .other;
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

fn hasCloudflareZone(rows: []const db_store.CloudflareZoneRow, name: []const u8, paused: []const u8) bool {
    for (rows) |row| {
        if (std.mem.eql(u8, row.name, name) and std.mem.eql(u8, row.paused, paused)) return true;
    }
    return false;
}

fn hasCloudflareDnsRecord(rows: []const db_store.CloudflareDnsRecordRow, name: []const u8, proxied: []const u8) bool {
    for (rows) |row| {
        if (std.mem.eql(u8, row.name, name) and std.mem.eql(u8, row.proxied, proxied)) return true;
    }
    return false;
}

test "cloudflare overview renders account zone DNS read model from normalized storage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudflare-app-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-1", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-1\"}");
    try db.upsertCloudflareZone("zone-2", "paused.test", "acct-1", "pending", true, "full", "ns3.example,ns4.example", "{\"id\":\"zone-2\"}");
    try db.upsertDnsRecord("record-1", "zone-1", "plosca.ru", "A", "76.13.130.170", 1, false, "{\"id\":\"record-1\"}");
    try db.upsertDnsRecord("record-2", "zone-1", "www.plosca.ru", "A", "76.13.130.170", 1, true, "{\"id\":\"record-2\"}");
    try db.upsertCloudflareResource("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "{\"id\":\"record-1\"}");
    try db.upsertCloudflareResource("zone-settings|zone|zone-1|ssl", "zone-settings", "ssl", "zone", "zone-1", "SSL", "full", "setting", "{\"id\":\"ssl\"}");
    try db.upsertCloudflareResource("tls-certificates|zone|zone-1|cert-1", "tls-certificates", "cert-1", "zone", "zone-1", "cert-1", "active", "certificate", "{\"id\":\"cert-1\"}");
    try db.upsertCloudflareResource("access-apps|account|acct-1|app-1", "access-apps", "app-1", "account", "acct-1", "app-1", "active", "access", "{\"id\":\"app-1\"}");
    try db.upsertCloudflareResource("cloudflare-tunnel|account|acct-1|tun-1", "cloudflare-tunnel", "tun-1", "account", "acct-1", "tun-1", "active", "tunnel", "{\"id\":\"tun-1\"}");
    try db.upsertCloudflareResource("account-rulesets|account|acct-1|ruleset-1", "account-rulesets", "ruleset-1", "account", "acct-1", "ruleset-1", "active", "ruleset", "{\"id\":\"ruleset-1\"}");
    try db.upsertCloudflareResource("logpush-jobs|zone|zone-1|job-1", "logpush-jobs", "job-1", "zone", "zone-1", "job-1", "active", "logs", "{\"id\":\"job-1\"}");
    try db.upsertCloudflareResource("cache-rules|zone|zone-1|cache-1", "cache-rules", "cache-1", "zone", "zone-1", "cache-1", "active", "cache", "{\"id\":\"cache-1\"}");
    try db.upsertCloudflareResource("load-balancing-pools|account|acct-1|pool-1", "load-balancing-pools", "pool-1", "account", "acct-1", "pool-1", "active", "pool", "{\"id\":\"pool-1\"}");
    try db.upsertCloudflareResource("health-checks|account|acct-1|health-1", "health-checks", "health-1", "account", "acct-1", "health-1", "active", "health", "{\"id\":\"health-1\"}");
    try db.upsertCloudflareResource("account-token|account|acct-1|token-1", "account-token", "token-1", "account", "acct-1", "token-1", "active", "token", "{\"id\":\"token-1\"}");
    try db.upsertCloudflareResource("misc-kind|account|acct-1|misc-1", "misc-kind", "misc-1", "account", "acct-1", "misc-1", "active", "misc", "{\"id\":\"misc-1\"}");
    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertCloudflareInventoryItem("email-routing|zone|zone-1|rule-1", "email-routing", "rule-1", "zone", "zone-1", "mail", "enabled", "routing", "plosca.ru", "acct-1", "zone-1", "dest", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"rule-1\"}");
    try db.upsertCloudflareInventoryItem("zero-trust-users|account|acct-1|user-1", "zero-trust-users", "user-1", "account", "acct-1", "user", "active", "identity", "", "acct-1", "", "user", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"user-1\"}");
    try db.upsertCloudflareInventoryItem("cloudflare-tunnel|account|acct-1|tun-1", "cloudflare-tunnel", "tun-1", "account", "acct-1", "tun-1", "active", "tunnel", "", "acct-1", "", "tun-1", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"tun-1\"}");
    try db.upsertCloudflareInventoryItem("tls-certificates|zone|zone-1|cert-1", "tls-certificates", "cert-1", "zone", "zone-1", "cert-1", "active", "certificate", "plosca.ru", "acct-1", "zone-1", "cert-1", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"cert-1\"}");
    try db.upsertCloudflareInventoryItem("cache-rules|zone|zone-1|cache-1", "cache-rules", "cache-1", "zone", "zone-1", "cache-1", "enabled", "cache", "plosca.ru", "acct-1", "zone-1", "cache-1", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"cache-1\"}");
    try db.upsertCloudflareInventoryItem("account-token|account|acct-1|token-1", "account-token", "token-1", "account", "acct-1", "token-1", "active", "token", "", "acct-1", "", "token-1", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"token-1\"}");
    try db.upsertCloudflareInventoryItem("account-profile|account|acct-1|profile", "account-profile", "profile", "account", "acct-1", "Main account", "active", "profile", "", "acct-1", "", "profile", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"profile\"}");
    try db.upsertCloudflareInventoryItem("misc-kind|account|acct-1|misc-1", "misc-kind", "misc-1", "account", "acct-1", "misc-1", "active", "misc", "", "acct-1", "", "misc-1", null, null, "2026-06-17T00:00:00Z", null, "{\"id\":\"misc-1\"}");
    try db.upsertCloudflareSecurityItem("waf|zone|zone-1|ruleset-1", "waf-rulesets", "ruleset-1", "zone", "zone-1", "Default WAF", "enabled", "waf", "medium", "block", "plosca.ru", "acct-1", "zone-1", null, "managed", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"ruleset-1\"}");
    try db.upsertCloudflareSecurityItem("security-center|account|acct-1|insight-1", "security-center-insights", "insight-1", "account", "acct-1", "Insight", "open", "insight", "low", "review", null, "acct-1", null, null, "managed", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"insight-1\"}");
    _ = try db.insertSnapshot("cloudflare", "zone", "plosca.ru", "ok", "zone detail", null, null);
    _ = try db.insertSnapshot("cloudflare", "dns", "plosca.ru", "ok", "dns records", null, null);
    _ = try db.insertSnapshot("hostinger", "vps", "12345", "ok", "vps", null, null);

    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .db = &db,
    };

    var overview = try Overview.load(ctx, .{ .limit = 3, .snapshot_limit = 2 });
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), overview.accounts.items.len);
    try std.testing.expectEqualStrings("acct-1", overview.accounts.items[0].id);
    try std.testing.expectEqual(@as(usize, 2), overview.zones.items.len);
    try std.testing.expect(hasCloudflareZone(overview.zones.items, "plosca.ru", "false"));
    try std.testing.expect(hasCloudflareZone(overview.zones.items, "paused.test", "true"));
    try std.testing.expectEqual(@as(usize, 2), overview.dns_records.items.len);
    try std.testing.expect(hasCloudflareDnsRecord(overview.dns_records.items, "plosca.ru", "false"));
    try std.testing.expect(hasCloudflareDnsRecord(overview.dns_records.items, "www.plosca.ru", "true"));
    try std.testing.expectEqual(@as(usize, 3), overview.resource_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 3), overview.inventory_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 2), overview.security_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 3), overview.inventory_facets.items.len);
    try std.testing.expectEqual(@as(usize, 2), overview.recent_snapshots.items.len);
    const summary = overview.summary();
    try std.testing.expectEqual(@as(i64, 1), summary.accounts);
    try std.testing.expectEqual(@as(i64, 2), summary.zones);
    try std.testing.expectEqual(@as(usize, 1), summary.active_zones);
    try std.testing.expectEqual(@as(usize, 1), summary.paused_zones);
    try std.testing.expectEqual(@as(i64, 2), summary.dns_records);
    try std.testing.expectEqual(@as(usize, 1), summary.proxied_dns_records);
    try std.testing.expectEqual(@as(usize, 1), summary.dns_only_records);
    try std.testing.expectEqual(@as(i64, 12), summary.resources);
    try std.testing.expectEqual(@as(i64, 9), summary.inventory_items);
    try std.testing.expectEqual(@as(i64, 2), summary.security_items);
    try std.testing.expectEqual(@as(usize, 12), summary.resource_kinds);
    try std.testing.expectEqual(@as(usize, 9), summary.inventory_kinds);
    try std.testing.expectEqual(@as(usize, 2), summary.security_kinds);
    try std.testing.expectEqual(@as(usize, 9), summary.inventory_facets);
    try std.testing.expectEqual(@as(usize, 2), summary.recent_snapshots);
    try std.testing.expectEqual(@as(i64, 1), summary.families.accounts);
    try std.testing.expectEqual(@as(i64, 1), summary.families.zones);
    try std.testing.expectEqual(@as(i64, 2), summary.families.dns);
    try std.testing.expectEqual(@as(i64, 2), summary.families.tls);
    try std.testing.expectEqual(@as(i64, 2), summary.families.access);
    try std.testing.expectEqual(@as(i64, 2), summary.families.tunnels);
    try std.testing.expectEqual(@as(i64, 1), summary.families.rulesets);
    try std.testing.expectEqual(@as(i64, 1), summary.families.logs);
    try std.testing.expectEqual(@as(i64, 2), summary.families.cache);
    try std.testing.expectEqual(@as(i64, 2), summary.families.security);
    try std.testing.expectEqual(@as(i64, 1), summary.families.email);
    try std.testing.expectEqual(@as(i64, 1), summary.families.load_balancing);
    try std.testing.expectEqual(@as(i64, 1), summary.families.health);
    try std.testing.expectEqual(@as(i64, 2), summary.families.tokens_memberships);
    try std.testing.expectEqual(@as(i64, 2), summary.families.other);
    try std.testing.expectEqual(@as(usize, cloudflare_api_family_labels.len), summary.api_families);
    try std.testing.expect(summary.api_routes > 1000);
    try std.testing.expect(summary.api_read_routes > 0);
    try std.testing.expect(summary.api_dry_run_routes > 0);
    try std.testing.expect(summary.api_deprecated_routes > 0);
    try std.testing.expect(summary.observed_read_families > 10);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var text_overview = try Overview.load(ctx, .{ .limit = 20, .snapshot_limit = 2 });
    defer text_overview.deinit(allocator);
    try text_overview.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudflare overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary accounts=1 zones=2 active_zones=1 paused_zones=1 dns_records=2 proxied_dns_records=1 dns_only_records=1 resources=12 inventory_items=9 security_items=2 resource_kinds=12 inventory_kinds=9 security_kinds=2 inventory_facets=9 recent_snapshots=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_routes total=") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "families accounts=1 zones=1 dns=2 tls=2 access=2 tunnels=2 rulesets=1 logs=1 cache=2 security=2 email=1 load_balancing=1 health=1 tokens_memberships=2 other=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "acct-1\tname=Main account\ttype=standard\tstatus=active") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zone-1\tname=plosca.ru\taccount=acct-1\tstatus=active\tpaused=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "record-1\tzone=zone-1\tname=plosca.ru\ttype=A\tcontent=76.13.130.170\tttl=1\tproxied=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "tls-certificates\tfamily=tls\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\napi families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dns\tofficial_routes=") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "tokens_memberships\tofficial_routes=") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/dns\ttarget=plosca.ru\tstatus=ok\tsummary=dns records") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/vps") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "waf-rulesets\tcount=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    var json_overview = try Overview.load(ctx, .{ .limit = 20, .snapshot_limit = 2 });
    defer json_overview.deinit(allocator);
    try json_overview.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"cloudflare_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"accounts\":1,\"zones\":2,\"active_zones\":1,\"paused_zones\":1,\"dns_records\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_routes\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":15") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"families\":{\"accounts\":1,\"zones\":1,\"dns\":2,\"tls\":2,\"access\":2,\"tunnels\":2,\"rulesets\":1,\"logs\":1,\"cache\":2,\"security\":2,\"email\":1,\"load_balancing\":1,\"health\":1,\"tokens_memberships\":2,\"other\":2}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"accounts\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"zones\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dns_records\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_facets\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"tls-certificates\",\"family\":\"tls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"security_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\",\"kind\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"content\":\"76.13.130.170\"") != null);
}
