const std = @import("std");
const collector_cloudflare = @import("collector_cloudflare");
const app_provider_list = @import("app_provider_list");
const app_render = @import("app_render");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_cloudflare = @import("provider_cloudflare");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const positiveLimit = app_render.positiveLimit;
const writeJsonStringField = app_render.writeJsonStringField;
const writeTextField = app_render.writeTextField;

pub const Auth = provider_cloudflare.Auth;
pub const AccountCollection = provider_cloudflare.AccountCollection;
pub const AccountEndpoint = provider_cloudflare.AccountEndpoint;
pub const AccountMutationArgs = provider_cloudflare.AccountMutationArgs;
pub const AccountMutationEndpoint = provider_cloudflare.AccountMutationEndpoint;
pub const AccountMemberMutationArgs = provider_cloudflare.AccountMemberMutationArgs;
pub const AccountMemberMutationEndpoint = provider_cloudflare.AccountMemberMutationEndpoint;
pub const AccountIamGroupMutationArgs = provider_cloudflare.AccountIamGroupMutationArgs;
pub const AccountIamGroupMutationEndpoint = provider_cloudflare.AccountIamGroupMutationEndpoint;
pub const AccountIamCollection = provider_cloudflare.AccountIamCollection;
pub const AccountTokenEndpoint = provider_cloudflare.AccountTokenEndpoint;
pub const AccountTokenMutationArgs = provider_cloudflare.AccountTokenMutationArgs;
pub const AccountTokenMutationEndpoint = provider_cloudflare.AccountTokenMutationEndpoint;
pub const AccountUserGroupMemberMutationArgs = provider_cloudflare.AccountUserGroupMemberMutationArgs;
pub const AccountUserGroupMemberMutationEndpoint = provider_cloudflare.AccountUserGroupMemberMutationEndpoint;
pub const CloudforceOneRuleMutationArgs = provider_cloudflare.CloudforceOneRuleMutationArgs;
pub const CloudforceOneRuleMutationEndpoint = provider_cloudflare.CloudforceOneRuleMutationEndpoint;
pub const CloudforceOneRuleReadArgs = provider_cloudflare.CloudforceOneRuleReadArgs;
pub const CloudforceOneRuleReadEndpoint = provider_cloudflare.CloudforceOneRuleReadEndpoint;
pub const DnsAnalyticsEndpoint = provider_cloudflare.DnsAnalyticsEndpoint;
pub const DnsFirewallMutationArgs = provider_cloudflare.DnsFirewallMutationArgs;
pub const DnsFirewallMutationEndpoint = provider_cloudflare.DnsFirewallMutationEndpoint;
pub const DnsFirewallReadEndpoint = provider_cloudflare.DnsFirewallReadEndpoint;
pub const DnsSettingsMutationArgs = provider_cloudflare.DnsSettingsMutationArgs;
pub const DnsSettingsMutationEndpoint = provider_cloudflare.DnsSettingsMutationEndpoint;
pub const EndpointHealthCheckReadEndpoint = provider_cloudflare.EndpointHealthCheckReadEndpoint;
pub const HealthCheckMutationArgs = provider_cloudflare.HealthCheckMutationArgs;
pub const HealthCheckMutationEndpoint = provider_cloudflare.HealthCheckMutationEndpoint;
pub const HealthCheckMutationResource = provider_cloudflare.HealthCheckMutationResource;
pub const IpAccessRuleListArgs = provider_cloudflare.IpAccessRuleListArgs;
pub const IpAccessRuleMutationArgs = provider_cloudflare.IpAccessRuleMutationArgs;
pub const IpAccessRuleMutationEndpoint = provider_cloudflare.IpAccessRuleMutationEndpoint;
pub const IpAccessRuleReadEndpoint = provider_cloudflare.IpAccessRuleReadEndpoint;
pub const IpAccessRuleScope = provider_cloudflare.IpAccessRuleScope;
pub const ZoneLegacyRuleMutationArgs = provider_cloudflare.ZoneLegacyRuleMutationArgs;
pub const ZoneLegacyRuleMutationEndpoint = provider_cloudflare.ZoneLegacyRuleMutationEndpoint;
pub const ZoneLegacyRuleReadEndpoint = provider_cloudflare.ZoneLegacyRuleReadEndpoint;
pub const ZoneLegacyRuleResource = provider_cloudflare.ZoneLegacyRuleResource;
pub const PageShieldMutationArgs = provider_cloudflare.PageShieldMutationArgs;
pub const PageShieldMutationEndpoint = provider_cloudflare.PageShieldMutationEndpoint;
pub const PageShieldReadArgs = provider_cloudflare.PageShieldReadArgs;
pub const PageShieldReadEndpoint = provider_cloudflare.PageShieldReadEndpoint;
pub const CustomPageMutationArgs = provider_cloudflare.CustomPageMutationArgs;
pub const CustomPageMutationEndpoint = provider_cloudflare.CustomPageMutationEndpoint;
pub const CustomPageReadArgs = provider_cloudflare.CustomPageReadArgs;
pub const CustomPageReadEndpoint = provider_cloudflare.CustomPageReadEndpoint;
pub const CustomPageResource = provider_cloudflare.CustomPageResource;
pub const CustomPageScope = provider_cloudflare.CustomPageScope;
pub const AccessCustomPageMutationArgs = provider_cloudflare.AccessCustomPageMutationArgs;
pub const AccessCustomPageMutationEndpoint = provider_cloudflare.AccessCustomPageMutationEndpoint;
pub const AccessCustomPageReadEndpoint = provider_cloudflare.AccessCustomPageReadEndpoint;
pub const AccessMutationArgs = provider_cloudflare.AccessMutationArgs;
pub const AccessMutationEndpoint = provider_cloudflare.AccessMutationEndpoint;
pub const AccessReadArgs = provider_cloudflare.AccessReadArgs;
pub const AccessReadEndpoint = provider_cloudflare.AccessReadEndpoint;
pub const AccessScope = provider_cloudflare.AccessScope;
pub const ApiShieldReadArgs = provider_cloudflare.ApiShieldReadArgs;
pub const ApiShieldReadEndpoint = provider_cloudflare.ApiShieldReadEndpoint;
pub const ZoneSecurityPostureReadArgs = provider_cloudflare.ZoneSecurityPostureReadArgs;
pub const ZoneSecurityPostureReadEndpoint = provider_cloudflare.ZoneSecurityPostureReadEndpoint;
pub const EmailRoutingAccountReadArgs = provider_cloudflare.EmailRoutingAccountReadArgs;
pub const EmailRoutingAccountReadEndpoint = provider_cloudflare.EmailRoutingAccountReadEndpoint;
pub const EmailRoutingZoneReadArgs = provider_cloudflare.EmailRoutingZoneReadArgs;
pub const EmailRoutingZoneReadEndpoint = provider_cloudflare.EmailRoutingZoneReadEndpoint;
pub const EmailAuthReadArgs = provider_cloudflare.EmailAuthReadArgs;
pub const EmailAuthReadEndpoint = provider_cloudflare.EmailAuthReadEndpoint;
pub const EmailSendingAccountReadArgs = provider_cloudflare.EmailSendingAccountReadArgs;
pub const EmailSendingAccountReadEndpoint = provider_cloudflare.EmailSendingAccountReadEndpoint;
pub const EmailSendingZoneReadArgs = provider_cloudflare.EmailSendingZoneReadArgs;
pub const EmailSendingZoneReadEndpoint = provider_cloudflare.EmailSendingZoneReadEndpoint;
pub const EmailSecuritySettingsReadArgs = provider_cloudflare.EmailSecuritySettingsReadArgs;
pub const EmailSecuritySettingsReadEndpoint = provider_cloudflare.EmailSecuritySettingsReadEndpoint;
pub const TunnelReadArgs = provider_cloudflare.TunnelReadArgs;
pub const TunnelReadEndpoint = provider_cloudflare.TunnelReadEndpoint;
pub const ZeroTrustReadArgs = provider_cloudflare.ZeroTrustReadArgs;
pub const ZeroTrustReadEndpoint = provider_cloudflare.ZeroTrustReadEndpoint;
pub const SecurityCenterReadArgs = provider_cloudflare.SecurityCenterReadArgs;
pub const SecurityCenterReadEndpoint = provider_cloudflare.SecurityCenterReadEndpoint;
pub const SecurityCenterScope = provider_cloudflare.SecurityCenterScope;
pub const AuditLogReadArgs = provider_cloudflare.AuditLogReadArgs;
pub const AuditLogReadEndpoint = provider_cloudflare.AuditLogReadEndpoint;
pub const ObservabilityScope = provider_cloudflare.ObservabilityScope;
pub const LogpushReadArgs = provider_cloudflare.LogpushReadArgs;
pub const LogpushReadEndpoint = provider_cloudflare.LogpushReadEndpoint;
pub const LogExplorerReadArgs = provider_cloudflare.LogExplorerReadArgs;
pub const LogExplorerReadEndpoint = provider_cloudflare.LogExplorerReadEndpoint;
pub const LogsReceivedReadArgs = provider_cloudflare.LogsReceivedReadArgs;
pub const LogsReceivedReadEndpoint = provider_cloudflare.LogsReceivedReadEndpoint;
pub const TlsReadArgs = provider_cloudflare.TlsReadArgs;
pub const TlsReadEndpoint = provider_cloudflare.TlsReadEndpoint;
pub const TlsScope = provider_cloudflare.TlsScope;
pub const LoadBalancingAccountReadEndpoint = provider_cloudflare.LoadBalancingAccountReadEndpoint;
pub const LoadBalancingMutationArgs = provider_cloudflare.LoadBalancingMutationArgs;
pub const LoadBalancingMutationEndpoint = provider_cloudflare.LoadBalancingMutationEndpoint;
pub const LoadBalancingMutationResource = provider_cloudflare.LoadBalancingMutationResource;
pub const LoadBalancingUserReadEndpoint = provider_cloudflare.LoadBalancingUserReadEndpoint;
pub const LoadBalancingZoneReadEndpoint = provider_cloudflare.LoadBalancingZoneReadEndpoint;
pub const ResourceTaggingAccountReadArgs = provider_cloudflare.ResourceTaggingAccountReadArgs;
pub const ResourceTaggingAccountReadEndpoint = provider_cloudflare.ResourceTaggingAccountReadEndpoint;
pub const ResourceTaggingMutationArgs = provider_cloudflare.ResourceTaggingMutationArgs;
pub const ResourceTaggingMutationEndpoint = provider_cloudflare.ResourceTaggingMutationEndpoint;
pub const ResourceTaggingMutationResource = provider_cloudflare.ResourceTaggingMutationResource;
pub const ResourceTaggingZoneReadArgs = provider_cloudflare.ResourceTaggingZoneReadArgs;
pub const RulesetMutationArgs = provider_cloudflare.RulesetMutationArgs;
pub const RulesetMutationEndpoint = provider_cloudflare.RulesetMutationEndpoint;
pub const RulesetReadArgs = provider_cloudflare.RulesetReadArgs;
pub const RulesetReadEndpoint = provider_cloudflare.RulesetReadEndpoint;
pub const RulesetScope = provider_cloudflare.RulesetScope;
pub const SecondaryDnsAccountMutationArgs = provider_cloudflare.SecondaryDnsAccountMutationArgs;
pub const SecondaryDnsAccountMutationEndpoint = provider_cloudflare.SecondaryDnsAccountMutationEndpoint;
pub const SecondaryDnsAccountResource = provider_cloudflare.SecondaryDnsAccountResource;
pub const SecondaryDnsZoneMutationArgs = provider_cloudflare.SecondaryDnsZoneMutationArgs;
pub const SecondaryDnsZoneMutationEndpoint = provider_cloudflare.SecondaryDnsZoneMutationEndpoint;
pub const SecondaryDnsZoneReadEndpoint = provider_cloudflare.SecondaryDnsZoneReadEndpoint;
pub const DnsRecordMutationArgs = provider_cloudflare.DnsRecordMutationArgs;
pub const DnsRecordMutationEndpoint = provider_cloudflare.DnsRecordMutationEndpoint;
pub const DnsRecordReadEndpoint = provider_cloudflare.DnsRecordReadEndpoint;
pub const DnssecMutationArgs = provider_cloudflare.DnssecMutationArgs;
pub const DnssecMutationEndpoint = provider_cloudflare.DnssecMutationEndpoint;
pub const IdentityEndpoint = provider_cloudflare.IdentityEndpoint;
pub const MembershipMutationArgs = provider_cloudflare.MembershipMutationArgs;
pub const MembershipMutationEndpoint = provider_cloudflare.MembershipMutationEndpoint;
pub const Output = core_output.Output;
pub const SmartShieldHealthCheckReadEndpoint = provider_cloudflare.SmartShieldHealthCheckReadEndpoint;
pub const UserTokenEndpoint = provider_cloudflare.UserTokenEndpoint;
pub const UserTokenMutationArgs = provider_cloudflare.UserTokenMutationArgs;
pub const UserTokenMutationEndpoint = provider_cloudflare.UserTokenMutationEndpoint;
pub const ZoneEndpoint = provider_cloudflare.ZoneEndpoint;
pub const ZoneHealthCheckReadEndpoint = provider_cloudflare.ZoneHealthCheckReadEndpoint;
pub const ZoneLifecycleMutationArgs = provider_cloudflare.ZoneLifecycleMutationArgs;
pub const ZoneLifecycleMutationEndpoint = provider_cloudflare.ZoneLifecycleMutationEndpoint;
pub const ZoneLifecycleReadEndpoint = provider_cloudflare.ZoneLifecycleReadEndpoint;
pub const ZoneMutationArgs = provider_cloudflare.ZoneMutationArgs;
pub const ZoneMutationEndpoint = provider_cloudflare.ZoneMutationEndpoint;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    auth: Auth,
    domains: []const []const u8,
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
            .account_count = try ctx.db.countTable("cloudflare_accounts"),
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
    }

    pub fn summary(self: Overview) OverviewSummary {
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
        try writer.writeAll("],\"recent_snapshots\":[");
        for (self.recent_snapshots.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try app_render.writeSnapshotJson(writer, row, .{ .include_id = true });
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub fn collectAccounts(ctx: Context) !Output {
    return try collector_cloudflare.collectAccounts(ctx.io, ctx.gpa, ctx.auth, ctx.db, true);
}

pub fn collectIps(ctx: Context, networks: ?[]const u8) !Output {
    return try collector_cloudflare.collectIps(ctx.io, ctx.gpa, ctx.db, networks, true);
}

pub fn collectAccountEndpoint(ctx: Context, account_id: []const u8, endpoint: AccountEndpoint) !Output {
    return try collector_cloudflare.collectAccountEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, true);
}

pub fn collectAccountDnsRecordUsage(ctx: Context, account_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountDnsRecordUsage(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, true);
}

pub fn collectAccountCollection(ctx: Context, account_id: []const u8, collection: AccountCollection) !Output {
    return try collector_cloudflare.collectAccountCollection(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, collection, true);
}

pub fn collectAccountResource(ctx: Context, account_id: []const u8, collection: AccountCollection, resource_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountResource(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, collection, resource_id, true);
}

pub fn collectAccountPermissionGroups(ctx: Context, account_id: []const u8) !Output {
    return try collectAccountIamCollection(ctx, account_id, .permission_groups);
}

pub fn collectAccountPermissionGroup(ctx: Context, account_id: []const u8, permission_group_id: []const u8) !Output {
    return try collectAccountIamResource(ctx, account_id, .permission_groups, permission_group_id);
}

pub fn collectAccountTokenEndpoint(ctx: Context, account_id: []const u8, endpoint: AccountTokenEndpoint) !Output {
    return try collector_cloudflare.collectAccountTokenEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, true);
}

pub fn collectAccountToken(ctx: Context, account_id: []const u8, token_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountToken(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, token_id, true);
}

pub fn collectAccountIamCollection(ctx: Context, account_id: []const u8, collection: AccountIamCollection) !Output {
    return try collector_cloudflare.collectAccountIamCollection(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, collection, true);
}

pub fn collectAccountIamResource(ctx: Context, account_id: []const u8, collection: AccountIamCollection, resource_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountIamResource(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, collection, resource_id, true);
}

pub fn collectAccountUserGroupMembers(ctx: Context, account_id: []const u8, user_group_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountUserGroupMembers(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, user_group_id, true);
}

pub fn collectAccountUserGroupMember(ctx: Context, account_id: []const u8, user_group_id: []const u8, member_id: []const u8) !Output {
    return try collector_cloudflare.collectAccountUserGroupMember(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, user_group_id, member_id, true);
}

pub fn collectSecondaryDnsAccountCollection(ctx: Context, account_id: []const u8, resource: SecondaryDnsAccountResource) !Output {
    return try collector_cloudflare.collectSecondaryDnsAccountCollection(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, resource, true);
}

pub fn collectSecondaryDnsAccountResource(ctx: Context, account_id: []const u8, resource: SecondaryDnsAccountResource, resource_id: []const u8) !Output {
    return try collector_cloudflare.collectSecondaryDnsAccountResource(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, resource, resource_id, true);
}

pub fn collectDnsFirewallReadEndpoint(ctx: Context, account_id: []const u8, endpoint: DnsFirewallReadEndpoint, dns_firewall_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectDnsFirewallReadEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, dns_firewall_id, true);
}

pub fn collectDnsFirewallAnalyticsEndpoint(ctx: Context, account_id: []const u8, dns_firewall_id: []const u8, endpoint: DnsAnalyticsEndpoint) !Output {
    return try collector_cloudflare.collectDnsFirewallAnalyticsEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, dns_firewall_id, endpoint, true);
}

pub fn collectLoadBalancingAccountEndpoint(ctx: Context, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8) !Output {
    return try collector_cloudflare.collectLoadBalancingAccountEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, resource_id, search_query, true);
}

pub fn collectLoadBalancingUserEndpoint(ctx: Context, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectLoadBalancingUserEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, endpoint, resource_id, true);
}

pub fn collectLoadBalancingZoneEndpoint(ctx: Context, zone_id: []const u8, endpoint: LoadBalancingZoneReadEndpoint, load_balancer_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectLoadBalancingZoneEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, load_balancer_id, true);
}

pub fn collectEndpointHealthCheck(ctx: Context, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectEndpointHealthCheck(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, healthcheck_id, true);
}

pub fn collectZoneHealthCheck(ctx: Context, zone_id: []const u8, endpoint: ZoneHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectZoneHealthCheck(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, healthcheck_id, true);
}

pub fn collectSmartShieldHealthCheck(ctx: Context, zone_id: []const u8, endpoint: SmartShieldHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectSmartShieldHealthCheck(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, healthcheck_id, true);
}

pub fn collectResourceTaggingAccountEndpoint(ctx: Context, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) !Output {
    return try collector_cloudflare.collectResourceTaggingAccountEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectResourceTaggingZoneTags(ctx: Context, zone_id: []const u8, args: ResourceTaggingZoneReadArgs) !Output {
    return try collector_cloudflare.collectResourceTaggingZoneTags(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, args, true);
}

pub fn collectRulesetEndpoint(ctx: Context, scope: RulesetScope, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) !Output {
    return try collector_cloudflare.collectRulesetEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectCloudforceOneRuleEndpoint(ctx: Context, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) !Output {
    return try collector_cloudflare.collectCloudforceOneRuleEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectIpAccessRuleEndpoint(ctx: Context, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) !Output {
    return try collector_cloudflare.collectIpAccessRuleEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectZoneLegacyRuleEndpoint(ctx: Context, zone_id: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectZoneLegacyRuleEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, resource, endpoint, rule_id, true);
}

pub fn collectPageShieldEndpoint(ctx: Context, zone_id: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) !Output {
    return try collector_cloudflare.collectPageShieldEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectApiShieldEndpoint(ctx: Context, zone_id: []const u8, endpoint: ApiShieldReadEndpoint, args: ApiShieldReadArgs) !Output {
    return try collector_cloudflare.collectApiShieldEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectZoneSecurityPostureEndpoint(ctx: Context, zone_id: []const u8, endpoint: ZoneSecurityPostureReadEndpoint, args: ZoneSecurityPostureReadArgs) !Output {
    return try collector_cloudflare.collectZoneSecurityPostureEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectEmailRoutingAccountEndpoint(ctx: Context, account_id: []const u8, endpoint: EmailRoutingAccountReadEndpoint, args: EmailRoutingAccountReadArgs) !Output {
    return try collector_cloudflare.collectEmailRoutingAccountEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectEmailRoutingZoneEndpoint(ctx: Context, zone_id: []const u8, endpoint: EmailRoutingZoneReadEndpoint, args: EmailRoutingZoneReadArgs) !Output {
    return try collector_cloudflare.collectEmailRoutingZoneEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectEmailAuthEndpoint(ctx: Context, zone_id: []const u8, endpoint: EmailAuthReadEndpoint, args: EmailAuthReadArgs) !Output {
    return try collector_cloudflare.collectEmailAuthEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectEmailSendingAccountEndpoint(ctx: Context, account_id: []const u8, endpoint: EmailSendingAccountReadEndpoint, args: EmailSendingAccountReadArgs) !Output {
    return try collector_cloudflare.collectEmailSendingAccountEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectEmailSendingZoneEndpoint(ctx: Context, zone_id: []const u8, endpoint: EmailSendingZoneReadEndpoint, args: EmailSendingZoneReadArgs) !Output {
    return try collector_cloudflare.collectEmailSendingZoneEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectEmailSecuritySettingsEndpoint(ctx: Context, account_id: []const u8, endpoint: EmailSecuritySettingsReadEndpoint, args: EmailSecuritySettingsReadArgs) !Output {
    return try collector_cloudflare.collectEmailSecuritySettingsEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectCustomPageEndpoint(ctx: Context, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) !Output {
    return try collector_cloudflare.collectCustomPageEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, resource, endpoint, args, true);
}

pub fn collectAccessCustomPageEndpoint(ctx: Context, account_id: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectAccessCustomPageEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, page_id, true);
}

pub fn collectAccessEndpoint(ctx: Context, scope: AccessScope, scope_id: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) !Output {
    return try collector_cloudflare.collectAccessEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectTunnelEndpoint(ctx: Context, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs) !Output {
    return try collector_cloudflare.collectTunnelEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectZeroTrustEndpoint(ctx: Context, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs) !Output {
    return try collector_cloudflare.collectZeroTrustEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, account_id, endpoint, args, true);
}

pub fn collectSecurityCenterEndpoint(ctx: Context, scope: SecurityCenterScope, scope_id: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs) !Output {
    return try collector_cloudflare.collectSecurityCenterEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectAuditLogEndpoint(ctx: Context, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs) !Output {
    return try collector_cloudflare.collectAuditLogEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, endpoint, args, true);
}

pub fn collectLogpushEndpoint(ctx: Context, scope: ObservabilityScope, scope_id: []const u8, endpoint: LogpushReadEndpoint, args: LogpushReadArgs) !Output {
    return try collector_cloudflare.collectLogpushEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectLogExplorerEndpoint(ctx: Context, scope: ObservabilityScope, scope_id: []const u8, endpoint: LogExplorerReadEndpoint, args: LogExplorerReadArgs) !Output {
    return try collector_cloudflare.collectLogExplorerEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectLogsReceivedEndpoint(ctx: Context, zone_id: []const u8, endpoint: LogsReceivedReadEndpoint, args: LogsReceivedReadArgs) !Output {
    return try collector_cloudflare.collectLogsReceivedEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, args, true);
}

pub fn collectTlsEndpoint(ctx: Context, scope: TlsScope, scope_id: []const u8, endpoint: TlsReadEndpoint, args: TlsReadArgs) !Output {
    return try collector_cloudflare.collectTlsEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, scope, scope_id, endpoint, args, true);
}

pub fn collectIdentityEndpoint(ctx: Context, endpoint: IdentityEndpoint) !Output {
    return try collector_cloudflare.collectIdentityEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, endpoint, true);
}

pub fn collectMembership(ctx: Context, membership_id: []const u8) !Output {
    return try collector_cloudflare.collectMembership(ctx.io, ctx.gpa, ctx.auth, ctx.db, membership_id, true);
}

pub fn collectUserTokenEndpoint(ctx: Context, endpoint: UserTokenEndpoint) !Output {
    return try collector_cloudflare.collectUserTokenEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, endpoint, true);
}

pub fn collectUserToken(ctx: Context, token_id: []const u8) !Output {
    return try collector_cloudflare.collectUserToken(ctx.io, ctx.gpa, ctx.auth, ctx.db, token_id, true);
}

pub fn collectZone(ctx: Context, domain: []const u8) !Output {
    return try collector_cloudflare.collectZone(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, true);
}

pub fn collectZoneById(ctx: Context, zone_id: []const u8) !Output {
    return try collector_cloudflare.collectZoneById(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, true);
}

pub fn collectZoneLifecycleReadEndpoint(ctx: Context, zone_id: []const u8, endpoint: ZoneLifecycleReadEndpoint, plan_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectZoneLifecycleReadEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, plan_id, true);
}

pub fn collectSecondaryDnsZoneEndpoint(ctx: Context, zone_id: []const u8, endpoint: SecondaryDnsZoneReadEndpoint) !Output {
    return try collector_cloudflare.collectSecondaryDnsZoneEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, true);
}

pub fn collectDnsAnalyticsEndpoint(ctx: Context, zone_id: []const u8, endpoint: DnsAnalyticsEndpoint) !Output {
    return try collector_cloudflare.collectDnsAnalyticsEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, zone_id, endpoint, true);
}

pub fn collectZoneEndpoint(ctx: Context, domain: []const u8, endpoint: ZoneEndpoint) !Output {
    return try collector_cloudflare.collectZoneEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, endpoint, true);
}

pub fn collectDns(ctx: Context, domain: []const u8) !Output {
    return try collector_cloudflare.collectDns(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, true);
}

pub fn collectDnsRecordEndpoint(ctx: Context, domain: []const u8, endpoint: DnsRecordReadEndpoint, dns_record_id: ?[]const u8) !Output {
    return try collector_cloudflare.collectDnsRecordEndpoint(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, endpoint, dns_record_id, true);
}

pub fn planDnsRecordMutation(ctx: Context, endpoint: DnsRecordMutationEndpoint, args: DnsRecordMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.dnsRecordMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDnssecMutation(ctx: Context, endpoint: DnssecMutationEndpoint, args: DnssecMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.dnssecMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccountMutation(ctx: Context, endpoint: AccountMutationEndpoint, args: AccountMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accountMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccountMemberMutation(ctx: Context, endpoint: AccountMemberMutationEndpoint, args: AccountMemberMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accountMemberMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccountIamGroupMutation(ctx: Context, endpoint: AccountIamGroupMutationEndpoint, args: AccountIamGroupMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accountIamGroupMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccountTokenMutation(ctx: Context, endpoint: AccountTokenMutationEndpoint, args: AccountTokenMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accountTokenMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planMembershipMutation(ctx: Context, endpoint: MembershipMutationEndpoint, args: MembershipMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.membershipMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planUserTokenMutation(ctx: Context, endpoint: UserTokenMutationEndpoint, args: UserTokenMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.userTokenMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planZoneMutation(ctx: Context, endpoint: ZoneMutationEndpoint, args: ZoneMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.zoneMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planZoneLifecycleMutation(ctx: Context, endpoint: ZoneLifecycleMutationEndpoint, args: ZoneLifecycleMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.zoneLifecycleMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccountUserGroupMemberMutation(ctx: Context, endpoint: AccountUserGroupMemberMutationEndpoint, args: AccountUserGroupMemberMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accountUserGroupMemberMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planSecondaryDnsAccountMutation(ctx: Context, endpoint: SecondaryDnsAccountMutationEndpoint, args: SecondaryDnsAccountMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.secondaryDnsAccountMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planSecondaryDnsZoneMutation(ctx: Context, endpoint: SecondaryDnsZoneMutationEndpoint, args: SecondaryDnsZoneMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.secondaryDnsZoneMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDnsFirewallMutation(ctx: Context, endpoint: DnsFirewallMutationEndpoint, args: DnsFirewallMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.dnsFirewallMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDnsSettingsMutation(ctx: Context, endpoint: DnsSettingsMutationEndpoint, args: DnsSettingsMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.dnsSettingsMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planLoadBalancingMutation(ctx: Context, endpoint: LoadBalancingMutationEndpoint, args: LoadBalancingMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.loadBalancingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planHealthCheckMutation(ctx: Context, endpoint: HealthCheckMutationEndpoint, args: HealthCheckMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.healthCheckMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planResourceTaggingMutation(ctx: Context, endpoint: ResourceTaggingMutationEndpoint, args: ResourceTaggingMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.resourceTaggingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planRulesetMutation(ctx: Context, endpoint: RulesetMutationEndpoint, args: RulesetMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.rulesetMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planCloudforceOneRuleMutation(ctx: Context, endpoint: CloudforceOneRuleMutationEndpoint, args: CloudforceOneRuleMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.cloudforceOneRuleMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planIpAccessRuleMutation(ctx: Context, endpoint: IpAccessRuleMutationEndpoint, args: IpAccessRuleMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.ipAccessRuleMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planZoneLegacyRuleMutation(ctx: Context, endpoint: ZoneLegacyRuleMutationEndpoint, args: ZoneLegacyRuleMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.zoneLegacyRuleMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planPageShieldMutation(ctx: Context, endpoint: PageShieldMutationEndpoint, args: PageShieldMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.pageShieldMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planCustomPageMutation(ctx: Context, endpoint: CustomPageMutationEndpoint, args: CustomPageMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.customPageMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccessCustomPageMutation(ctx: Context, endpoint: AccessCustomPageMutationEndpoint, args: AccessCustomPageMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accessCustomPageMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planAccessMutation(ctx: Context, endpoint: AccessMutationEndpoint, args: AccessMutationArgs) !Output {
    return .{ .text = try provider_cloudflare.accessMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn collectZoneSetting(ctx: Context, domain: []const u8, setting_id: []const u8) !Output {
    return try collector_cloudflare.collectZoneSetting(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, setting_id, true);
}

pub fn diagnose(ctx: Context, domain: []const u8) !Output {
    return try collector_cloudflare.diagnoseDomain(ctx.io, ctx.gpa, ctx.db, domain, true);
}

pub fn listResources(ctx: Context) !Output {
    return try app_provider_list.resources(providerListContext(ctx), .cloudflare);
}

pub fn listInventoryItems(ctx: Context) !Output {
    return try app_provider_list.inventoryItems(providerListContext(ctx), .cloudflare);
}

pub fn writeOverviewText(ctx: Context, options: OverviewOptions, writer: anytype) !void {
    var overview = try Overview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeOverviewJson(ctx: Context, options: OverviewOptions, writer: anytype) !void {
    var overview = try Overview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeJson(writer);
}

pub fn selectedDomain(domains: []const []const u8, args: []const []const u8) []const u8 {
    if (args.len > 1) return args[1];
    return domains[0];
}

fn providerListContext(ctx: Context) app_provider_list.Context {
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

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
    if (containsIgnoreCase(kind, "load-balanc") or containsIgnoreCase(kind, "load_balanc") or containsIgnoreCase(kind, "loadbalanc")) return .load_balancing;
    if (containsIgnoreCase(kind, "health")) return .health;
    if (containsIgnoreCase(kind, "tunnel")) return .tunnels;
    if (containsIgnoreCase(kind, "tls") or
        containsIgnoreCase(kind, "ssl") or
        containsIgnoreCase(kind, "certificate") or
        containsIgnoreCase(kind, "cert") or
        containsIgnoreCase(kind, "origin-ca"))
    {
        return .tls;
    }
    if (containsIgnoreCase(kind, "access") or containsIgnoreCase(kind, "zero-trust") or containsIgnoreCase(kind, "zerotrust") or containsIgnoreCase(kind, "gateway")) return .access;
    if (containsIgnoreCase(kind, "cache") or containsIgnoreCase(kind, "argo") or containsIgnoreCase(kind, "tiered")) return .cache;
    if (containsIgnoreCase(kind, "security") or
        containsIgnoreCase(kind, "waf") or
        containsIgnoreCase(kind, "firewall") or
        containsIgnoreCase(kind, "api-shield") or
        containsIgnoreCase(kind, "page-shield") or
        containsIgnoreCase(kind, "ip-access") or
        containsIgnoreCase(kind, "posture"))
    {
        return .security;
    }
    if (containsIgnoreCase(kind, "ruleset") or containsIgnoreCase(kind, "rule")) return .rulesets;
    if (containsIgnoreCase(kind, "dns") or containsIgnoreCase(kind, "dnssec") or containsIgnoreCase(kind, "secondary-dns")) return .dns;
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

test "cloudflare app domain selection uses explicit or default domain" {
    const configured = [_][]const u8{ "plosca.ru", "example.com" };
    const zone_default = [_][]const u8{"zone"};
    try std.testing.expectEqualStrings("plosca.ru", selectedDomain(configured[0..], zone_default[0..]));

    const zone_explicit = [_][]const u8{ "zone", "example.net" };
    try std.testing.expectEqualStrings("example.net", selectedDomain(configured[0..], zone_explicit[0..]));
}

test "cloudflare app lists normalized resources" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudflare-app-resources.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareResource("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "{\"id\":\"record-1\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .auth = .{},
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listResources(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "dns-records/record-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "zone zone-1 active A plosca.ru") != null);
}

test "cloudflare app lists typed inventory items" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudflare-app-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .auth = .{},
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listInventoryItems(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "dns-records/record-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "zone zone-1 active dns_only A plosca.ru plosca.ru 76.13.130.170") != null);
}

test "cloudflare app renders account zone DNS overview from normalized storage" {
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

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .auth = .{},
        .domains = domains[0..],
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

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeOverviewText(ctx, .{ .limit = 20, .snapshot_limit = 2 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudflare overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary accounts=1 zones=2 active_zones=1 paused_zones=1 dns_records=2 proxied_dns_records=1 dns_only_records=1 resources=12 inventory_items=9 security_items=2 resource_kinds=12 inventory_kinds=9 security_kinds=2 inventory_facets=9 recent_snapshots=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "families accounts=1 zones=1 dns=2 tls=2 access=2 tunnels=2 rulesets=1 logs=1 cache=2 security=2 email=1 load_balancing=1 health=1 tokens_memberships=2 other=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "acct-1\tname=Main account\ttype=standard\tstatus=active") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zone-1\tname=plosca.ru\taccount=acct-1\tstatus=active\tpaused=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "record-1\tzone=zone-1\tname=plosca.ru\ttype=A\tcontent=76.13.130.170\tttl=1\tproxied=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "tls-certificates\tfamily=tls\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/dns\ttarget=plosca.ru\tstatus=ok\tsummary=dns records") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/vps") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "waf-rulesets\tcount=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeOverviewJson(ctx, .{ .limit = 20, .snapshot_limit = 2 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"cloudflare_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"accounts\":1,\"zones\":2,\"active_zones\":1,\"paused_zones\":1,\"dns_records\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"families\":{\"accounts\":1,\"zones\":1,\"dns\":2,\"tls\":2,\"access\":2,\"tunnels\":2,\"rulesets\":1,\"logs\":1,\"cache\":2,\"security\":2,\"email\":1,\"load_balancing\":1,\"health\":1,\"tokens_memberships\":2,\"other\":2}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"accounts\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"zones\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dns_records\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_facets\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"tls-certificates\",\"family\":\"tls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"security_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\",\"kind\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"content\":\"76.13.130.170\"") != null);
}
