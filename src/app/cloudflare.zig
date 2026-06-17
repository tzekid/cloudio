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

pub fn collectZoneSetting(ctx: Context, domain: []const u8, setting_id: []const u8) !Output {
    return try collector_cloudflare.collectZoneSetting(ctx.io, ctx.gpa, ctx.auth, ctx.db, domain, setting_id, true);
}

pub fn diagnose(ctx: Context, domain: []const u8) !void {
    try collector_cloudflare.diagnoseDomain(ctx.io, ctx.gpa, ctx.db, domain);
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
