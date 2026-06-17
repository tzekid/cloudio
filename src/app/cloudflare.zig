const std = @import("std");
const collector_cloudflare = @import("collector_cloudflare");
const db_store = @import("db_store");
const provider_cloudflare = @import("provider_cloudflare");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Auth = collector_cloudflare.Auth;
pub const AccountCollection = collector_cloudflare.AccountCollection;
pub const AccountEndpoint = collector_cloudflare.AccountEndpoint;
pub const AccountMutationArgs = collector_cloudflare.AccountMutationArgs;
pub const AccountMutationEndpoint = collector_cloudflare.AccountMutationEndpoint;
pub const AccountMemberMutationArgs = collector_cloudflare.AccountMemberMutationArgs;
pub const AccountMemberMutationEndpoint = collector_cloudflare.AccountMemberMutationEndpoint;
pub const AccountIamGroupMutationArgs = collector_cloudflare.AccountIamGroupMutationArgs;
pub const AccountIamGroupMutationEndpoint = collector_cloudflare.AccountIamGroupMutationEndpoint;
pub const AccountIamCollection = collector_cloudflare.AccountIamCollection;
pub const AccountTokenEndpoint = collector_cloudflare.AccountTokenEndpoint;
pub const AccountTokenMutationArgs = collector_cloudflare.AccountTokenMutationArgs;
pub const AccountTokenMutationEndpoint = collector_cloudflare.AccountTokenMutationEndpoint;
pub const AccountUserGroupMemberMutationArgs = collector_cloudflare.AccountUserGroupMemberMutationArgs;
pub const AccountUserGroupMemberMutationEndpoint = collector_cloudflare.AccountUserGroupMemberMutationEndpoint;
pub const CloudforceOneRuleMutationArgs = collector_cloudflare.CloudforceOneRuleMutationArgs;
pub const CloudforceOneRuleMutationEndpoint = collector_cloudflare.CloudforceOneRuleMutationEndpoint;
pub const CloudforceOneRuleReadArgs = collector_cloudflare.CloudforceOneRuleReadArgs;
pub const CloudforceOneRuleReadEndpoint = collector_cloudflare.CloudforceOneRuleReadEndpoint;
pub const DnsAnalyticsEndpoint = collector_cloudflare.DnsAnalyticsEndpoint;
pub const DnsFirewallMutationArgs = collector_cloudflare.DnsFirewallMutationArgs;
pub const DnsFirewallMutationEndpoint = collector_cloudflare.DnsFirewallMutationEndpoint;
pub const DnsFirewallReadEndpoint = collector_cloudflare.DnsFirewallReadEndpoint;
pub const DnsSettingsMutationArgs = collector_cloudflare.DnsSettingsMutationArgs;
pub const DnsSettingsMutationEndpoint = collector_cloudflare.DnsSettingsMutationEndpoint;
pub const EndpointHealthCheckReadEndpoint = collector_cloudflare.EndpointHealthCheckReadEndpoint;
pub const HealthCheckMutationArgs = collector_cloudflare.HealthCheckMutationArgs;
pub const HealthCheckMutationEndpoint = collector_cloudflare.HealthCheckMutationEndpoint;
pub const HealthCheckMutationResource = collector_cloudflare.HealthCheckMutationResource;
pub const IpAccessRuleListArgs = collector_cloudflare.IpAccessRuleListArgs;
pub const IpAccessRuleMutationArgs = collector_cloudflare.IpAccessRuleMutationArgs;
pub const IpAccessRuleMutationEndpoint = collector_cloudflare.IpAccessRuleMutationEndpoint;
pub const IpAccessRuleReadEndpoint = collector_cloudflare.IpAccessRuleReadEndpoint;
pub const IpAccessRuleScope = collector_cloudflare.IpAccessRuleScope;
pub const ZoneLegacyRuleMutationArgs = collector_cloudflare.ZoneLegacyRuleMutationArgs;
pub const ZoneLegacyRuleMutationEndpoint = collector_cloudflare.ZoneLegacyRuleMutationEndpoint;
pub const ZoneLegacyRuleReadEndpoint = collector_cloudflare.ZoneLegacyRuleReadEndpoint;
pub const ZoneLegacyRuleResource = collector_cloudflare.ZoneLegacyRuleResource;
pub const PageShieldMutationArgs = collector_cloudflare.PageShieldMutationArgs;
pub const PageShieldMutationEndpoint = collector_cloudflare.PageShieldMutationEndpoint;
pub const PageShieldReadArgs = collector_cloudflare.PageShieldReadArgs;
pub const PageShieldReadEndpoint = collector_cloudflare.PageShieldReadEndpoint;
pub const CustomPageMutationArgs = collector_cloudflare.CustomPageMutationArgs;
pub const CustomPageMutationEndpoint = collector_cloudflare.CustomPageMutationEndpoint;
pub const CustomPageReadArgs = collector_cloudflare.CustomPageReadArgs;
pub const CustomPageReadEndpoint = collector_cloudflare.CustomPageReadEndpoint;
pub const CustomPageResource = collector_cloudflare.CustomPageResource;
pub const CustomPageScope = collector_cloudflare.CustomPageScope;
pub const AccessCustomPageMutationArgs = collector_cloudflare.AccessCustomPageMutationArgs;
pub const AccessCustomPageMutationEndpoint = collector_cloudflare.AccessCustomPageMutationEndpoint;
pub const AccessCustomPageReadEndpoint = collector_cloudflare.AccessCustomPageReadEndpoint;
pub const AccessMutationArgs = collector_cloudflare.AccessMutationArgs;
pub const AccessMutationEndpoint = collector_cloudflare.AccessMutationEndpoint;
pub const AccessReadArgs = collector_cloudflare.AccessReadArgs;
pub const AccessReadEndpoint = collector_cloudflare.AccessReadEndpoint;
pub const AccessScope = collector_cloudflare.AccessScope;
pub const TunnelReadArgs = collector_cloudflare.TunnelReadArgs;
pub const TunnelReadEndpoint = collector_cloudflare.TunnelReadEndpoint;
pub const ZeroTrustReadArgs = collector_cloudflare.ZeroTrustReadArgs;
pub const ZeroTrustReadEndpoint = collector_cloudflare.ZeroTrustReadEndpoint;
pub const SecurityCenterReadArgs = collector_cloudflare.SecurityCenterReadArgs;
pub const SecurityCenterReadEndpoint = collector_cloudflare.SecurityCenterReadEndpoint;
pub const SecurityCenterScope = collector_cloudflare.SecurityCenterScope;
pub const AuditLogReadArgs = collector_cloudflare.AuditLogReadArgs;
pub const AuditLogReadEndpoint = collector_cloudflare.AuditLogReadEndpoint;
pub const ObservabilityScope = collector_cloudflare.ObservabilityScope;
pub const LogpushReadArgs = collector_cloudflare.LogpushReadArgs;
pub const LogpushReadEndpoint = collector_cloudflare.LogpushReadEndpoint;
pub const LogExplorerReadArgs = collector_cloudflare.LogExplorerReadArgs;
pub const LogExplorerReadEndpoint = collector_cloudflare.LogExplorerReadEndpoint;
pub const LogsReceivedReadArgs = collector_cloudflare.LogsReceivedReadArgs;
pub const LogsReceivedReadEndpoint = collector_cloudflare.LogsReceivedReadEndpoint;
pub const TlsReadArgs = collector_cloudflare.TlsReadArgs;
pub const TlsReadEndpoint = collector_cloudflare.TlsReadEndpoint;
pub const TlsScope = collector_cloudflare.TlsScope;
pub const LoadBalancingAccountReadEndpoint = collector_cloudflare.LoadBalancingAccountReadEndpoint;
pub const LoadBalancingMutationArgs = collector_cloudflare.LoadBalancingMutationArgs;
pub const LoadBalancingMutationEndpoint = collector_cloudflare.LoadBalancingMutationEndpoint;
pub const LoadBalancingMutationResource = collector_cloudflare.LoadBalancingMutationResource;
pub const LoadBalancingUserReadEndpoint = collector_cloudflare.LoadBalancingUserReadEndpoint;
pub const LoadBalancingZoneReadEndpoint = collector_cloudflare.LoadBalancingZoneReadEndpoint;
pub const ResourceTaggingAccountReadArgs = collector_cloudflare.ResourceTaggingAccountReadArgs;
pub const ResourceTaggingAccountReadEndpoint = collector_cloudflare.ResourceTaggingAccountReadEndpoint;
pub const ResourceTaggingMutationArgs = collector_cloudflare.ResourceTaggingMutationArgs;
pub const ResourceTaggingMutationEndpoint = collector_cloudflare.ResourceTaggingMutationEndpoint;
pub const ResourceTaggingMutationResource = collector_cloudflare.ResourceTaggingMutationResource;
pub const ResourceTaggingZoneReadArgs = collector_cloudflare.ResourceTaggingZoneReadArgs;
pub const RulesetMutationArgs = collector_cloudflare.RulesetMutationArgs;
pub const RulesetMutationEndpoint = collector_cloudflare.RulesetMutationEndpoint;
pub const RulesetReadArgs = collector_cloudflare.RulesetReadArgs;
pub const RulesetReadEndpoint = collector_cloudflare.RulesetReadEndpoint;
pub const RulesetScope = collector_cloudflare.RulesetScope;
pub const SecondaryDnsAccountMutationArgs = collector_cloudflare.SecondaryDnsAccountMutationArgs;
pub const SecondaryDnsAccountMutationEndpoint = collector_cloudflare.SecondaryDnsAccountMutationEndpoint;
pub const SecondaryDnsAccountResource = collector_cloudflare.SecondaryDnsAccountResource;
pub const SecondaryDnsZoneMutationArgs = collector_cloudflare.SecondaryDnsZoneMutationArgs;
pub const SecondaryDnsZoneMutationEndpoint = collector_cloudflare.SecondaryDnsZoneMutationEndpoint;
pub const SecondaryDnsZoneReadEndpoint = collector_cloudflare.SecondaryDnsZoneReadEndpoint;
pub const DnsRecordMutationArgs = collector_cloudflare.DnsRecordMutationArgs;
pub const DnsRecordMutationEndpoint = collector_cloudflare.DnsRecordMutationEndpoint;
pub const DnsRecordReadEndpoint = collector_cloudflare.DnsRecordReadEndpoint;
pub const DnssecMutationArgs = collector_cloudflare.DnssecMutationArgs;
pub const DnssecMutationEndpoint = collector_cloudflare.DnssecMutationEndpoint;
pub const IdentityEndpoint = collector_cloudflare.IdentityEndpoint;
pub const MembershipMutationArgs = collector_cloudflare.MembershipMutationArgs;
pub const MembershipMutationEndpoint = collector_cloudflare.MembershipMutationEndpoint;
pub const Output = collector_cloudflare.Output;
pub const SmartShieldHealthCheckReadEndpoint = collector_cloudflare.SmartShieldHealthCheckReadEndpoint;
pub const UserTokenEndpoint = collector_cloudflare.UserTokenEndpoint;
pub const UserTokenMutationArgs = collector_cloudflare.UserTokenMutationArgs;
pub const UserTokenMutationEndpoint = collector_cloudflare.UserTokenMutationEndpoint;
pub const ZoneEndpoint = collector_cloudflare.ZoneEndpoint;
pub const ZoneHealthCheckReadEndpoint = collector_cloudflare.ZoneHealthCheckReadEndpoint;
pub const ZoneLifecycleMutationArgs = collector_cloudflare.ZoneLifecycleMutationArgs;
pub const ZoneLifecycleMutationEndpoint = collector_cloudflare.ZoneLifecycleMutationEndpoint;
pub const ZoneLifecycleReadEndpoint = collector_cloudflare.ZoneLifecycleReadEndpoint;
pub const ZoneMutationArgs = collector_cloudflare.ZoneMutationArgs;
pub const ZoneMutationEndpoint = collector_cloudflare.ZoneMutationEndpoint;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    auth: Auth,
    domains: []const []const u8,
    db: *Db,
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

pub fn diagnose(ctx: Context, domain: []const u8) !void {
    try collector_cloudflare.diagnoseDomain(ctx.io, ctx.gpa, ctx.db, domain);
}

pub fn listResources(ctx: Context) !Output {
    var rows = try ctx.db.cloudflareResourceList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    for (rows.items) |row| {
        try out.writer.print("{s}\t{s}\n", .{ row.name, row.value });
    }
    return .{ .text = try out.toOwnedSlice() };
}

pub fn selectedDomain(domains: []const []const u8, args: []const []const u8) []const u8 {
    if (args.len > 1) return args[1];
    return domains[0];
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
