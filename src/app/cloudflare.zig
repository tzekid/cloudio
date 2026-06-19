const std = @import("std");
const collector_cloudflare = @import("collector_cloudflare");
const app_cloudflare_overview = @import("app_cloudflare_overview");
const app_provider_list = @import("app_provider_list");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_cloudflare = @import("provider_cloudflare");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

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

pub const OverviewOptions = app_cloudflare_overview.OverviewOptions;
pub const CloudflareFamily = app_cloudflare_overview.CloudflareFamily;
pub const CloudflareFamilySummary = app_cloudflare_overview.CloudflareFamilySummary;
pub const OverviewSummary = app_cloudflare_overview.OverviewSummary;
pub const Overview = app_cloudflare_overview.Overview;
pub const OverviewContext = app_cloudflare_overview.Context;

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
    var overview = try Overview.load(overviewContext(ctx), options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeOverviewJson(ctx: Context, options: OverviewOptions, writer: anytype) !void {
    var overview = try Overview.load(overviewContext(ctx), options);
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

fn overviewContext(ctx: Context) OverviewContext {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
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
