const std = @import("std");
const net_http = @import("net_http");
pub const transport = @import("provider_cloudflare_transport");
pub const routes = @import("provider_cloudflare_routes");
pub const models = @import("provider_cloudflare_models");
pub const browser_run = @import("provider_cloudflare_browser_run");
const cf_transport = transport;

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Auth = cf_transport.Auth;
pub const base_url = routes.base_url;
pub const accounts_path = routes.accounts_path;
pub const zones_path = routes.zones_path;
pub const ips_path = routes.ips_path;
pub const user_path = routes.user_path;
pub const user_tenants_path = routes.user_tenants_path;
pub const memberships_path = routes.memberships_path;
pub const user_tokens_path = routes.user_tokens_path;
pub const user_tokens_verify_path = routes.user_tokens_verify_path;
pub const user_token_permission_groups_path = routes.user_token_permission_groups_path;
pub const cloudforce_one_rules_base_path = routes.cloudforce_one_rules_base_path;
pub const firewall_access_rules_path = routes.firewall_access_rules_path;
pub const AccountEndpoint = routes.AccountEndpoint;
pub const AccountMutationEndpoint = routes.AccountMutationEndpoint;
pub const AccountMutationArgs = routes.AccountMutationArgs;
pub const AccountCollection = routes.AccountCollection;
pub const AccountMemberMutationEndpoint = routes.AccountMemberMutationEndpoint;
pub const AccountMemberMutationArgs = routes.AccountMemberMutationArgs;
pub const AccountIamCollection = routes.AccountIamCollection;
pub const AccountIamGroupMutationEndpoint = routes.AccountIamGroupMutationEndpoint;
pub const AccountIamGroupMutationArgs = routes.AccountIamGroupMutationArgs;
pub const AccountUserGroupMemberMutationEndpoint = routes.AccountUserGroupMemberMutationEndpoint;
pub const AccountUserGroupMemberMutationArgs = routes.AccountUserGroupMemberMutationArgs;
pub const SecondaryDnsAccountResource = routes.SecondaryDnsAccountResource;
pub const SecondaryDnsAccountMutationEndpoint = routes.SecondaryDnsAccountMutationEndpoint;
pub const SecondaryDnsAccountMutationArgs = routes.SecondaryDnsAccountMutationArgs;
pub const DnsAnalyticsEndpoint = routes.DnsAnalyticsEndpoint;
pub const DnsFirewallReadEndpoint = routes.DnsFirewallReadEndpoint;
pub const DnsFirewallMutationEndpoint = routes.DnsFirewallMutationEndpoint;
pub const DnsFirewallMutationArgs = routes.DnsFirewallMutationArgs;
pub const DnsSettingsMutationEndpoint = routes.DnsSettingsMutationEndpoint;
pub const DnsSettingsMutationArgs = routes.DnsSettingsMutationArgs;
pub const LoadBalancingAccountReadEndpoint = routes.LoadBalancingAccountReadEndpoint;
pub const LoadBalancingUserReadEndpoint = routes.LoadBalancingUserReadEndpoint;
pub const LoadBalancingZoneReadEndpoint = routes.LoadBalancingZoneReadEndpoint;
pub const LoadBalancingMutationResource = routes.LoadBalancingMutationResource;
pub const LoadBalancingMutationEndpoint = routes.LoadBalancingMutationEndpoint;
pub const LoadBalancingMutationArgs = routes.LoadBalancingMutationArgs;
pub const EndpointHealthCheckReadEndpoint = routes.EndpointHealthCheckReadEndpoint;
pub const ZoneHealthCheckReadEndpoint = routes.ZoneHealthCheckReadEndpoint;
pub const SmartShieldHealthCheckReadEndpoint = routes.SmartShieldHealthCheckReadEndpoint;
pub const HealthCheckMutationResource = routes.HealthCheckMutationResource;
pub const HealthCheckMutationEndpoint = routes.HealthCheckMutationEndpoint;
pub const HealthCheckMutationArgs = routes.HealthCheckMutationArgs;
pub const RulesetScope = routes.RulesetScope;
pub const RulesetReadEndpoint = routes.RulesetReadEndpoint;
pub const RulesetReadArgs = routes.RulesetReadArgs;
pub const RulesetMutationEndpoint = routes.RulesetMutationEndpoint;
pub const RulesetMutationArgs = routes.RulesetMutationArgs;
pub const CloudforceOneRuleReadEndpoint = routes.CloudforceOneRuleReadEndpoint;
pub const CloudforceOneRuleReadArgs = routes.CloudforceOneRuleReadArgs;
pub const CloudforceOneRuleMutationEndpoint = routes.CloudforceOneRuleMutationEndpoint;
pub const CloudforceOneRuleMutationArgs = routes.CloudforceOneRuleMutationArgs;
pub const IpAccessRuleScope = routes.IpAccessRuleScope;
pub const IpAccessRuleReadEndpoint = routes.IpAccessRuleReadEndpoint;
pub const IpAccessRuleListArgs = routes.IpAccessRuleListArgs;
pub const IpAccessRuleMutationEndpoint = routes.IpAccessRuleMutationEndpoint;
pub const IpAccessRuleMutationArgs = routes.IpAccessRuleMutationArgs;
pub const ZoneLegacyRuleResource = routes.ZoneLegacyRuleResource;
pub const ZoneLegacyRuleReadEndpoint = routes.ZoneLegacyRuleReadEndpoint;
pub const ZoneLegacyRuleMutationEndpoint = routes.ZoneLegacyRuleMutationEndpoint;
pub const ZoneLegacyRuleMutationArgs = routes.ZoneLegacyRuleMutationArgs;
pub const PageShieldReadEndpoint = routes.PageShieldReadEndpoint;
pub const PageShieldReadArgs = routes.PageShieldReadArgs;
pub const ApiShieldReadEndpoint = routes.ApiShieldReadEndpoint;
pub const ApiShieldReadArgs = routes.ApiShieldReadArgs;
pub const ZoneSecurityPostureReadEndpoint = routes.ZoneSecurityPostureReadEndpoint;
pub const ZoneSecurityPostureReadArgs = routes.ZoneSecurityPostureReadArgs;
pub const EmailRoutingAccountReadEndpoint = routes.EmailRoutingAccountReadEndpoint;
pub const EmailRoutingAccountReadArgs = routes.EmailRoutingAccountReadArgs;
pub const EmailRoutingZoneReadEndpoint = routes.EmailRoutingZoneReadEndpoint;
pub const EmailRoutingZoneReadArgs = routes.EmailRoutingZoneReadArgs;
pub const EmailAuthReadEndpoint = routes.EmailAuthReadEndpoint;
pub const EmailAuthReadArgs = routes.EmailAuthReadArgs;
pub const EmailSendingAccountReadEndpoint = routes.EmailSendingAccountReadEndpoint;
pub const EmailSendingAccountReadArgs = routes.EmailSendingAccountReadArgs;
pub const EmailSendingZoneReadEndpoint = routes.EmailSendingZoneReadEndpoint;
pub const EmailSendingZoneReadArgs = routes.EmailSendingZoneReadArgs;
pub const EmailSecuritySettingsReadEndpoint = routes.EmailSecuritySettingsReadEndpoint;
pub const EmailSecuritySettingsReadArgs = routes.EmailSecuritySettingsReadArgs;
pub const PageShieldMutationEndpoint = routes.PageShieldMutationEndpoint;
pub const PageShieldMutationArgs = routes.PageShieldMutationArgs;
pub const CustomPageScope = routes.CustomPageScope;
pub const CustomPageResource = routes.CustomPageResource;
pub const CustomPageReadEndpoint = routes.CustomPageReadEndpoint;
pub const CustomPageReadArgs = routes.CustomPageReadArgs;
pub const CustomPageMutationEndpoint = routes.CustomPageMutationEndpoint;
pub const CustomPageMutationArgs = routes.CustomPageMutationArgs;
pub const AccessCustomPageReadEndpoint = routes.AccessCustomPageReadEndpoint;
pub const AccessCustomPageMutationEndpoint = routes.AccessCustomPageMutationEndpoint;
pub const AccessCustomPageMutationArgs = routes.AccessCustomPageMutationArgs;
pub const AccessScope = routes.AccessScope;
pub const AccessReadEndpoint = routes.AccessReadEndpoint;
pub const AccessReadArgs = routes.AccessReadArgs;
pub const AccessMutationEndpoint = routes.AccessMutationEndpoint;
pub const AccessMutationArgs = routes.AccessMutationArgs;
pub const TunnelReadEndpoint = routes.TunnelReadEndpoint;
pub const TunnelReadArgs = routes.TunnelReadArgs;
pub const ZeroTrustReadEndpoint = routes.ZeroTrustReadEndpoint;
pub const ZeroTrustReadArgs = routes.ZeroTrustReadArgs;
pub const SecurityCenterScope = routes.SecurityCenterScope;
pub const SecurityCenterReadEndpoint = routes.SecurityCenterReadEndpoint;
pub const SecurityCenterReadArgs = routes.SecurityCenterReadArgs;
pub const AuditLogReadEndpoint = routes.AuditLogReadEndpoint;
pub const AuditLogReadArgs = routes.AuditLogReadArgs;
pub const ObservabilityScope = routes.ObservabilityScope;
pub const LogpushReadEndpoint = routes.LogpushReadEndpoint;
pub const LogpushReadArgs = routes.LogpushReadArgs;
pub const LogExplorerReadEndpoint = routes.LogExplorerReadEndpoint;
pub const LogExplorerReadArgs = routes.LogExplorerReadArgs;
pub const LogsReceivedReadEndpoint = routes.LogsReceivedReadEndpoint;
pub const LogsReceivedReadArgs = routes.LogsReceivedReadArgs;
pub const TlsScope = routes.TlsScope;
pub const TlsReadEndpoint = routes.TlsReadEndpoint;
pub const TlsReadArgs = routes.TlsReadArgs;
pub const ResourceTaggingAccountReadEndpoint = routes.ResourceTaggingAccountReadEndpoint;
pub const ResourceTaggingAccountReadArgs = routes.ResourceTaggingAccountReadArgs;
pub const ResourceTaggingZoneReadArgs = routes.ResourceTaggingZoneReadArgs;
pub const ResourceTaggingMutationResource = routes.ResourceTaggingMutationResource;
pub const ResourceTaggingMutationEndpoint = routes.ResourceTaggingMutationEndpoint;
pub const ResourceTaggingMutationArgs = routes.ResourceTaggingMutationArgs;
pub const DnsRecordReadEndpoint = routes.DnsRecordReadEndpoint;
pub const DnsRecordMutationEndpoint = routes.DnsRecordMutationEndpoint;
pub const DnsRecordMutationArgs = routes.DnsRecordMutationArgs;
pub const AccountTokenEndpoint = routes.AccountTokenEndpoint;
pub const AccountTokenMutationEndpoint = routes.AccountTokenMutationEndpoint;
pub const AccountTokenMutationArgs = routes.AccountTokenMutationArgs;
pub const IdentityEndpoint = routes.IdentityEndpoint;
pub const MembershipMutationEndpoint = routes.MembershipMutationEndpoint;
pub const MembershipMutationArgs = routes.MembershipMutationArgs;
pub const UserTokenEndpoint = routes.UserTokenEndpoint;
pub const UserTokenMutationEndpoint = routes.UserTokenMutationEndpoint;
pub const UserTokenMutationArgs = routes.UserTokenMutationArgs;
pub const ZoneMutationEndpoint = routes.ZoneMutationEndpoint;
pub const ZoneMutationArgs = routes.ZoneMutationArgs;
pub const ZoneEndpoint = routes.ZoneEndpoint;
pub const ZoneLifecycleReadEndpoint = routes.ZoneLifecycleReadEndpoint;
pub const ZoneLifecycleMutationEndpoint = routes.ZoneLifecycleMutationEndpoint;
pub const ZoneLifecycleMutationArgs = routes.ZoneLifecycleMutationArgs;
pub const SecondaryDnsZoneReadEndpoint = routes.SecondaryDnsZoneReadEndpoint;
pub const SecondaryDnsZoneMutationEndpoint = routes.SecondaryDnsZoneMutationEndpoint;
pub const SecondaryDnsZoneMutationArgs = routes.SecondaryDnsZoneMutationArgs;
pub const DnssecMutationEndpoint = routes.DnssecMutationEndpoint;
pub const DnssecMutationArgs = routes.DnssecMutationArgs;
pub const accountsUrl = routes.accountsUrl;
pub const ipsUrl = routes.ipsUrl;
pub const ipsPath = routes.ipsPath;
pub const accountEndpointUrl = routes.accountEndpointUrl;
pub const accountEndpointPath = routes.accountEndpointPath;
pub const accountMutationPath = routes.accountMutationPath;
pub const accountMutationPlanJson = routes.accountMutationPlanJson;
pub const accountCollectionUrl = routes.accountCollectionUrl;
pub const accountCollectionPath = routes.accountCollectionPath;
pub const accountResourceUrl = routes.accountResourceUrl;
pub const accountResourcePath = routes.accountResourcePath;
pub const accountMemberMutationPath = routes.accountMemberMutationPath;
pub const accountMemberMutationPlanJson = routes.accountMemberMutationPlanJson;
pub const accountPermissionGroupsUrl = routes.accountPermissionGroupsUrl;
pub const accountPermissionGroupsPath = routes.accountPermissionGroupsPath;
pub const accountPermissionGroupUrl = routes.accountPermissionGroupUrl;
pub const accountPermissionGroupPath = routes.accountPermissionGroupPath;
pub const accountIamCollectionUrl = routes.accountIamCollectionUrl;
pub const accountIamCollectionPath = routes.accountIamCollectionPath;
pub const accountIamResourceUrl = routes.accountIamResourceUrl;
pub const accountIamResourcePath = routes.accountIamResourcePath;
pub const accountIamGroupMutationPath = routes.accountIamGroupMutationPath;
pub const accountIamGroupMutationPlanJson = routes.accountIamGroupMutationPlanJson;
pub const accountUserGroupMembersUrl = routes.accountUserGroupMembersUrl;
pub const accountUserGroupMembersPath = routes.accountUserGroupMembersPath;
pub const accountUserGroupMemberUrl = routes.accountUserGroupMemberUrl;
pub const accountUserGroupMemberPath = routes.accountUserGroupMemberPath;
pub const accountUserGroupMemberMutationPath = routes.accountUserGroupMemberMutationPath;
pub const accountUserGroupMemberMutationPlanJson = routes.accountUserGroupMemberMutationPlanJson;
pub const secondaryDnsAccountCollectionUrl = routes.secondaryDnsAccountCollectionUrl;
pub const secondaryDnsAccountCollectionPath = routes.secondaryDnsAccountCollectionPath;
pub const secondaryDnsAccountResourceUrl = routes.secondaryDnsAccountResourceUrl;
pub const secondaryDnsAccountResourcePath = routes.secondaryDnsAccountResourcePath;
pub const secondaryDnsAccountMutationPath = routes.secondaryDnsAccountMutationPath;
pub const secondaryDnsAccountMutationPlanJson = routes.secondaryDnsAccountMutationPlanJson;
pub const dnsFirewallReadUrl = routes.dnsFirewallReadUrl;
pub const dnsFirewallCollectionPath = routes.dnsFirewallCollectionPath;
pub const dnsFirewallResourcePath = routes.dnsFirewallResourcePath;
pub const dnsFirewallReadPath = routes.dnsFirewallReadPath;
pub const dnsFirewallMutationPath = routes.dnsFirewallMutationPath;
pub const dnsFirewallMutationPlanJson = routes.dnsFirewallMutationPlanJson;
pub const dnsFirewallAnalyticsUrl = routes.dnsFirewallAnalyticsUrl;
pub const dnsFirewallAnalyticsPath = routes.dnsFirewallAnalyticsPath;
pub const dnsSettingsMutationPath = routes.dnsSettingsMutationPath;
pub const dnsSettingsMutationPlanJson = routes.dnsSettingsMutationPlanJson;
pub const loadBalancingAccountReadUrl = routes.loadBalancingAccountReadUrl;
pub const loadBalancingAccountBasePath = routes.loadBalancingAccountBasePath;
pub const loadBalancingAccountCollectionPath = routes.loadBalancingAccountCollectionPath;
pub const loadBalancingAccountResourcePath = routes.loadBalancingAccountResourcePath;
pub const loadBalancingAccountReadPath = routes.loadBalancingAccountReadPath;
pub const loadBalancingUserReadUrl = routes.loadBalancingUserReadUrl;
pub const loadBalancingUserBasePath = routes.loadBalancingUserBasePath;
pub const loadBalancingUserCollectionPath = routes.loadBalancingUserCollectionPath;
pub const loadBalancingUserResourcePath = routes.loadBalancingUserResourcePath;
pub const loadBalancingUserReadPath = routes.loadBalancingUserReadPath;
pub const loadBalancingZoneReadUrl = routes.loadBalancingZoneReadUrl;
pub const loadBalancingZoneCollectionPath = routes.loadBalancingZoneCollectionPath;
pub const loadBalancingZoneResourcePath = routes.loadBalancingZoneResourcePath;
pub const loadBalancingZoneReadPath = routes.loadBalancingZoneReadPath;
pub const loadBalancingMutationPath = routes.loadBalancingMutationPath;
pub const loadBalancingMutationPlanJson = routes.loadBalancingMutationPlanJson;
pub const endpointHealthCheckReadUrl = routes.endpointHealthCheckReadUrl;
pub const endpointHealthCheckCollectionPath = routes.endpointHealthCheckCollectionPath;
pub const endpointHealthCheckResourcePath = routes.endpointHealthCheckResourcePath;
pub const endpointHealthCheckReadPath = routes.endpointHealthCheckReadPath;
pub const zoneHealthCheckReadUrl = routes.zoneHealthCheckReadUrl;
pub const zoneHealthCheckCollectionPath = routes.zoneHealthCheckCollectionPath;
pub const zoneHealthCheckResourcePath = routes.zoneHealthCheckResourcePath;
pub const zoneHealthCheckPreviewCollectionPath = routes.zoneHealthCheckPreviewCollectionPath;
pub const zoneHealthCheckPreviewResourcePath = routes.zoneHealthCheckPreviewResourcePath;
pub const zoneHealthCheckReadPath = routes.zoneHealthCheckReadPath;
pub const smartShieldHealthCheckReadUrl = routes.smartShieldHealthCheckReadUrl;
pub const smartShieldHealthCheckCollectionPath = routes.smartShieldHealthCheckCollectionPath;
pub const smartShieldHealthCheckResourcePath = routes.smartShieldHealthCheckResourcePath;
pub const smartShieldHealthCheckReadPath = routes.smartShieldHealthCheckReadPath;
pub const healthCheckMutationPath = routes.healthCheckMutationPath;
pub const healthCheckMutationPlanJson = routes.healthCheckMutationPlanJson;
pub const rulesetReadUrl = routes.rulesetReadUrl;
pub const rulesetCollectionPath = routes.rulesetCollectionPath;
pub const rulesetResourcePath = routes.rulesetResourcePath;
pub const rulesetEntrypointPath = routes.rulesetEntrypointPath;
pub const rulesetReadPath = routes.rulesetReadPath;
pub const rulesetMutationPath = routes.rulesetMutationPath;
pub const rulesetMutationPlanJson = routes.rulesetMutationPlanJson;
pub const cloudforceOneRuleReadUrl = routes.cloudforceOneRuleReadUrl;
pub const cloudforceOneRuleCollectionPath = routes.cloudforceOneRuleCollectionPath;
pub const cloudforceOneRuleReadPath = routes.cloudforceOneRuleReadPath;
pub const cloudforceOneRuleMutationPath = routes.cloudforceOneRuleMutationPath;
pub const cloudforceOneRuleMutationPlanJson = routes.cloudforceOneRuleMutationPlanJson;
pub const ipAccessRuleReadUrl = routes.ipAccessRuleReadUrl;
pub const ipAccessRuleCollectionPath = routes.ipAccessRuleCollectionPath;
pub const ipAccessRuleReadPath = routes.ipAccessRuleReadPath;
pub const ipAccessRuleMutationPath = routes.ipAccessRuleMutationPath;
pub const ipAccessRuleMutationPlanJson = routes.ipAccessRuleMutationPlanJson;
pub const zoneLegacyRuleReadUrl = routes.zoneLegacyRuleReadUrl;
pub const zoneLegacyRuleCollectionPath = routes.zoneLegacyRuleCollectionPath;
pub const zoneLegacyRuleReadPath = routes.zoneLegacyRuleReadPath;
pub const zoneLegacyRuleMutationPath = routes.zoneLegacyRuleMutationPath;
pub const zoneLegacyRuleMutationPlanJson = routes.zoneLegacyRuleMutationPlanJson;
pub const pageShieldReadUrl = routes.pageShieldReadUrl;
pub const pageShieldBasePath = routes.pageShieldBasePath;
pub const pageShieldReadPath = routes.pageShieldReadPath;
pub const apiShieldReadUrl = routes.apiShieldReadUrl;
pub const apiShieldReadPath = routes.apiShieldReadPath;
pub const zoneSecurityPostureReadUrl = routes.zoneSecurityPostureReadUrl;
pub const zoneSecurityPostureReadPath = routes.zoneSecurityPostureReadPath;
pub const emailRoutingAccountReadUrl = routes.emailRoutingAccountReadUrl;
pub const emailRoutingAccountReadPath = routes.emailRoutingAccountReadPath;
pub const emailRoutingZoneReadUrl = routes.emailRoutingZoneReadUrl;
pub const emailRoutingZoneReadPath = routes.emailRoutingZoneReadPath;
pub const emailAuthReadUrl = routes.emailAuthReadUrl;
pub const emailAuthReadPath = routes.emailAuthReadPath;
pub const emailSendingAccountReadUrl = routes.emailSendingAccountReadUrl;
pub const emailSendingAccountReadPath = routes.emailSendingAccountReadPath;
pub const emailSendingZoneReadUrl = routes.emailSendingZoneReadUrl;
pub const emailSendingZoneReadPath = routes.emailSendingZoneReadPath;
pub const emailSecuritySettingsReadUrl = routes.emailSecuritySettingsReadUrl;
pub const emailSecuritySettingsReadPath = routes.emailSecuritySettingsReadPath;
pub const pageShieldMutationPath = routes.pageShieldMutationPath;
pub const pageShieldMutationPlanJson = routes.pageShieldMutationPlanJson;
pub const customPageReadUrl = routes.customPageReadUrl;
pub const customPageCollectionPath = routes.customPageCollectionPath;
pub const customPageReadPath = routes.customPageReadPath;
pub const customPageMutationPath = routes.customPageMutationPath;
pub const customPageMutationPlanJson = routes.customPageMutationPlanJson;
pub const accessCustomPageReadUrl = routes.accessCustomPageReadUrl;
pub const accessCustomPageCollectionPath = routes.accessCustomPageCollectionPath;
pub const accessCustomPageReadPath = routes.accessCustomPageReadPath;
pub const accessCustomPageMutationPath = routes.accessCustomPageMutationPath;
pub const accessCustomPageMutationPlanJson = routes.accessCustomPageMutationPlanJson;
pub const accessReadUrl = routes.accessReadUrl;
pub const accessBasePath = routes.accessBasePath;
pub const accessReadPath = routes.accessReadPath;
pub const accessMutationPath = routes.accessMutationPath;
pub const accessMutationPlanJson = routes.accessMutationPlanJson;
pub const tunnelReadUrl = routes.tunnelReadUrl;
pub const tunnelReadPath = routes.tunnelReadPath;
pub const zeroTrustReadUrl = routes.zeroTrustReadUrl;
pub const zeroTrustReadPath = routes.zeroTrustReadPath;
pub const securityCenterReadUrl = routes.securityCenterReadUrl;
pub const securityCenterReadPath = routes.securityCenterReadPath;
pub const auditLogReadUrl = routes.auditLogReadUrl;
pub const auditLogReadPath = routes.auditLogReadPath;
pub const logpushReadUrl = routes.logpushReadUrl;
pub const logpushReadPath = routes.logpushReadPath;
pub const logExplorerReadUrl = routes.logExplorerReadUrl;
pub const logExplorerReadPath = routes.logExplorerReadPath;
pub const logsReceivedReadUrl = routes.logsReceivedReadUrl;
pub const logsReceivedReadPath = routes.logsReceivedReadPath;
pub const tlsReadUrl = routes.tlsReadUrl;
pub const tlsReadPath = routes.tlsReadPath;
pub const resourceTaggingAccountReadUrl = routes.resourceTaggingAccountReadUrl;
pub const resourceTaggingAccountBasePath = routes.resourceTaggingAccountBasePath;
pub const resourceTaggingAccountReadPath = routes.resourceTaggingAccountReadPath;
pub const resourceTaggingZoneReadUrl = routes.resourceTaggingZoneReadUrl;
pub const resourceTaggingZoneBasePath = routes.resourceTaggingZoneBasePath;
pub const resourceTaggingZoneReadPath = routes.resourceTaggingZoneReadPath;
pub const resourceTaggingMutationPath = routes.resourceTaggingMutationPath;
pub const resourceTaggingMutationPlanJson = routes.resourceTaggingMutationPlanJson;
pub const accountTokenEndpointUrl = routes.accountTokenEndpointUrl;
pub const accountTokenEndpointPath = routes.accountTokenEndpointPath;
pub const accountTokenUrl = routes.accountTokenUrl;
pub const accountTokenPath = routes.accountTokenPath;
pub const accountTokenMutationPath = routes.accountTokenMutationPath;
pub const accountTokenMutationPlanJson = routes.accountTokenMutationPlanJson;
pub const userTokenEndpointUrl = routes.userTokenEndpointUrl;
pub const userTokenUrl = routes.userTokenUrl;
pub const userTokenReadPath = routes.userTokenReadPath;
pub const userTokenMutationPath = routes.userTokenMutationPath;
pub const userTokenMutationPlanJson = routes.userTokenMutationPlanJson;
pub const identityEndpointUrl = routes.identityEndpointUrl;
pub const membershipUrl = routes.membershipUrl;
pub const membershipPath = routes.membershipPath;
pub const membershipMutationPath = routes.membershipMutationPath;
pub const membershipMutationPlanJson = routes.membershipMutationPlanJson;
pub const accountDnsSettingsUrl = routes.accountDnsSettingsUrl;
pub const accountDnsSettingsPath = routes.accountDnsSettingsPath;
pub const accountDnsRecordUsageUrl = routes.accountDnsRecordUsageUrl;
pub const accountDnsRecordUsagePath = routes.accountDnsRecordUsagePath;
pub const zonesUrl = routes.zonesUrl;
pub const zoneUrl = routes.zoneUrl;
pub const zonePath = routes.zonePath;
pub const dnsRecordsUrl = routes.dnsRecordsUrl;
pub const dnsAnalyticsUrl = routes.dnsAnalyticsUrl;
pub const dnsAnalyticsPath = routes.dnsAnalyticsPath;
pub const dnsRecordReadUrl = routes.dnsRecordReadUrl;
pub const dnsRecordReadPath = routes.dnsRecordReadPath;
pub const dnsRecordMutationPath = routes.dnsRecordMutationPath;
pub const dnsRecordMutationPlanJson = routes.dnsRecordMutationPlanJson;
pub const zoneMutationPath = routes.zoneMutationPath;
pub const zoneMutationPlanJson = routes.zoneMutationPlanJson;
pub const zoneEndpointUrl = routes.zoneEndpointUrl;
pub const zoneEndpointPath = routes.zoneEndpointPath;
pub const zoneLifecycleReadUrl = routes.zoneLifecycleReadUrl;
pub const zoneLifecycleReadPath = routes.zoneLifecycleReadPath;
pub const zoneLifecycleMutationPath = routes.zoneLifecycleMutationPath;
pub const zoneLifecycleMutationPlanJson = routes.zoneLifecycleMutationPlanJson;
pub const secondaryDnsZoneReadUrl = routes.secondaryDnsZoneReadUrl;
pub const secondaryDnsZoneReadPath = routes.secondaryDnsZoneReadPath;
pub const secondaryDnsZoneMutationPath = routes.secondaryDnsZoneMutationPath;
pub const secondaryDnsZoneMutationPlanJson = routes.secondaryDnsZoneMutationPlanJson;
pub const dnssecMutationPath = routes.dnssecMutationPath;
pub const dnssecMutationPlanJson = routes.dnssecMutationPlanJson;
pub const zoneSettingUrl = routes.zoneSettingUrl;
pub const zoneSettingPath = routes.zoneSettingPath;
pub const pathEscape = routes.pathEscape;

pub const Client = struct {
    auth: Auth,
    base_url_override: []const u8 = base_url,

    pub fn init(auth: Auth) Client {
        return .{
            .auth = auth,
            .base_url_override = auth.base_url orelse base_url,
        };
    }

    /// Returns a borrowed Browser Run client with an explicitly selected
    /// engine. Kitesurf is never selected as an implicit Chromium fallback.
    pub fn browserRun(self: Client, account_id: []const u8, engine: browser_run.Engine) !browser_run.Client {
        return browser_run.Client.init(self.auth, self.base_url_override, account_id, engine);
    }

    pub fn getAccounts(self: Client, io: Io, gpa: Allocator) !net_http.Response {
        const url = try accountsUrl(gpa, self.base_url_override);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getIps(self: Client, io: Io, gpa: Allocator, networks: ?[]const u8) !net_http.Response {
        const url = try ipsUrl(gpa, self.base_url_override, networks);
        defer gpa.free(url);
        return try self.getPublic(io, gpa, url);
    }

    pub fn getAccountDnsSettings(self: Client, io: Io, gpa: Allocator, account_id: []const u8) !net_http.Response {
        const url = try accountDnsSettingsUrl(gpa, self.base_url_override, account_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountDnsRecordUsage(self: Client, io: Io, gpa: Allocator, account_id: []const u8) !net_http.Response {
        const url = try accountDnsRecordUsageUrl(gpa, self.base_url_override, account_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: AccountEndpoint) !net_http.Response {
        const url = try accountEndpointUrl(gpa, self.base_url_override, account_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountCollection(self: Client, io: Io, gpa: Allocator, account_id: []const u8, collection: AccountCollection) !net_http.Response {
        const url = try accountCollectionUrl(gpa, self.base_url_override, account_id, collection);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountResource(self: Client, io: Io, gpa: Allocator, account_id: []const u8, collection: AccountCollection, resource_id: []const u8) !net_http.Response {
        const url = try accountResourceUrl(gpa, self.base_url_override, account_id, collection, resource_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountIamCollection(self: Client, io: Io, gpa: Allocator, account_id: []const u8, collection: AccountIamCollection) !net_http.Response {
        const url = try accountIamCollectionUrl(gpa, self.base_url_override, account_id, collection);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountIamResource(self: Client, io: Io, gpa: Allocator, account_id: []const u8, collection: AccountIamCollection, resource_id: []const u8) !net_http.Response {
        const url = try accountIamResourceUrl(gpa, self.base_url_override, account_id, collection, resource_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountUserGroupMembers(self: Client, io: Io, gpa: Allocator, account_id: []const u8, user_group_id: []const u8) !net_http.Response {
        const url = try accountUserGroupMembersUrl(gpa, self.base_url_override, account_id, user_group_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountUserGroupMember(self: Client, io: Io, gpa: Allocator, account_id: []const u8, user_group_id: []const u8, member_id: []const u8) !net_http.Response {
        const url = try accountUserGroupMemberUrl(gpa, self.base_url_override, account_id, user_group_id, member_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountTokenEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: AccountTokenEndpoint) !net_http.Response {
        const url = try accountTokenEndpointUrl(gpa, self.base_url_override, account_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountToken(self: Client, io: Io, gpa: Allocator, account_id: []const u8, token_id: []const u8) !net_http.Response {
        const url = try accountTokenUrl(gpa, self.base_url_override, account_id, token_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccountPermissionGroups(self: Client, io: Io, gpa: Allocator, account_id: []const u8) !net_http.Response {
        return try self.getAccountIamCollection(io, gpa, account_id, .permission_groups);
    }

    pub fn getAccountPermissionGroup(self: Client, io: Io, gpa: Allocator, account_id: []const u8, permission_group_id: []const u8) !net_http.Response {
        return try self.getAccountIamResource(io, gpa, account_id, .permission_groups, permission_group_id);
    }

    pub fn getSecondaryDnsAccountCollection(self: Client, io: Io, gpa: Allocator, account_id: []const u8, resource: SecondaryDnsAccountResource) !net_http.Response {
        const url = try secondaryDnsAccountCollectionUrl(gpa, self.base_url_override, account_id, resource);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getSecondaryDnsAccountResource(self: Client, io: Io, gpa: Allocator, account_id: []const u8, resource: SecondaryDnsAccountResource, resource_id: []const u8) !net_http.Response {
        const url = try secondaryDnsAccountResourceUrl(gpa, self.base_url_override, account_id, resource, resource_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsFirewallReadEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: DnsFirewallReadEndpoint, dns_firewall_id: ?[]const u8) !net_http.Response {
        const url = try dnsFirewallReadUrl(gpa, self.base_url_override, account_id, endpoint, dns_firewall_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsFirewallAnalyticsEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, dns_firewall_id: []const u8, endpoint: DnsAnalyticsEndpoint) !net_http.Response {
        const url = try dnsFirewallAnalyticsUrl(gpa, self.base_url_override, account_id, dns_firewall_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLoadBalancingAccountEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8) !net_http.Response {
        const url = try loadBalancingAccountReadUrl(gpa, self.base_url_override, account_id, endpoint, resource_id, search_query);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLoadBalancingUserEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8) !net_http.Response {
        const url = try loadBalancingUserReadUrl(gpa, self.base_url_override, endpoint, resource_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLoadBalancingZoneEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: LoadBalancingZoneReadEndpoint, load_balancer_id: ?[]const u8) !net_http.Response {
        const url = try loadBalancingZoneReadUrl(gpa, self.base_url_override, zone_id, endpoint, load_balancer_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEndpointHealthCheck(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !net_http.Response {
        const url = try endpointHealthCheckReadUrl(gpa, self.base_url_override, account_id, endpoint, healthcheck_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneHealthCheck(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: ZoneHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !net_http.Response {
        const url = try zoneHealthCheckReadUrl(gpa, self.base_url_override, zone_id, endpoint, healthcheck_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getSmartShieldHealthCheck(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: SmartShieldHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) !net_http.Response {
        const url = try smartShieldHealthCheckReadUrl(gpa, self.base_url_override, zone_id, endpoint, healthcheck_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getResourceTaggingAccountEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) !net_http.Response {
        const url = try resourceTaggingAccountReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getResourceTaggingZoneTags(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, args: ResourceTaggingZoneReadArgs) !net_http.Response {
        const url = try resourceTaggingZoneReadUrl(gpa, self.base_url_override, zone_id, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getRulesetEndpoint(self: Client, io: Io, gpa: Allocator, scope: RulesetScope, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) !net_http.Response {
        const url = try rulesetReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getCloudforceOneRuleEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) !net_http.Response {
        const url = try cloudforceOneRuleReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getIpAccessRuleEndpoint(self: Client, io: Io, gpa: Allocator, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) !net_http.Response {
        const url = try ipAccessRuleReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneLegacyRuleEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) !net_http.Response {
        const url = try zoneLegacyRuleReadUrl(gpa, self.base_url_override, zone_id, resource, endpoint, rule_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getPageShieldEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) !net_http.Response {
        const url = try pageShieldReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getApiShieldEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: ApiShieldReadEndpoint, args: ApiShieldReadArgs) !net_http.Response {
        const url = try apiShieldReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneSecurityPostureEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: ZoneSecurityPostureReadEndpoint, args: ZoneSecurityPostureReadArgs) !net_http.Response {
        const url = try zoneSecurityPostureReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEmailRoutingAccountEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: EmailRoutingAccountReadEndpoint, args: EmailRoutingAccountReadArgs) !net_http.Response {
        const url = try emailRoutingAccountReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEmailRoutingZoneEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: EmailRoutingZoneReadEndpoint, args: EmailRoutingZoneReadArgs) !net_http.Response {
        const url = try emailRoutingZoneReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEmailSecuritySettingsEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: EmailSecuritySettingsReadEndpoint, args: EmailSecuritySettingsReadArgs) !net_http.Response {
        const url = try emailSecuritySettingsReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEmailAuthEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: EmailAuthReadEndpoint, args: EmailAuthReadArgs) !net_http.Response {
        const url = try emailAuthReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getEmailSendingAccountEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: EmailSendingAccountReadEndpoint, args: EmailSendingAccountReadArgs) !net_http.Response {
        const url = try emailSendingAccountReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.getLegacy(io, gpa, url);
    }

    pub fn getEmailSendingZoneEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: EmailSendingZoneReadEndpoint, args: EmailSendingZoneReadArgs) !net_http.Response {
        const url = try emailSendingZoneReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.getLegacy(io, gpa, url);
    }

    pub fn getCustomPageEndpoint(self: Client, io: Io, gpa: Allocator, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) !net_http.Response {
        const url = try customPageReadUrl(gpa, self.base_url_override, scope, scope_id, resource, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccessCustomPageEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) !net_http.Response {
        const url = try accessCustomPageReadUrl(gpa, self.base_url_override, account_id, endpoint, page_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAccessEndpoint(self: Client, io: Io, gpa: Allocator, scope: AccessScope, scope_id: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) !net_http.Response {
        const url = try accessReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getTunnelEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs) !net_http.Response {
        const url = try tunnelReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZeroTrustEndpoint(self: Client, io: Io, gpa: Allocator, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs) !net_http.Response {
        const url = try zeroTrustReadUrl(gpa, self.base_url_override, account_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getSecurityCenterEndpoint(self: Client, io: Io, gpa: Allocator, scope: SecurityCenterScope, scope_id: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs) !net_http.Response {
        const url = try securityCenterReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getAuditLogEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs) !net_http.Response {
        const url = try auditLogReadUrl(gpa, self.base_url_override, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLogpushEndpoint(self: Client, io: Io, gpa: Allocator, scope: ObservabilityScope, scope_id: []const u8, endpoint: LogpushReadEndpoint, args: LogpushReadArgs) !net_http.Response {
        const url = try logpushReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLogExplorerEndpoint(self: Client, io: Io, gpa: Allocator, scope: ObservabilityScope, scope_id: []const u8, endpoint: LogExplorerReadEndpoint, args: LogExplorerReadArgs) !net_http.Response {
        const url = try logExplorerReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getLogsReceivedEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: LogsReceivedReadEndpoint, args: LogsReceivedReadArgs) !net_http.Response {
        const url = try logsReceivedReadUrl(gpa, self.base_url_override, zone_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getTlsEndpoint(self: Client, io: Io, gpa: Allocator, scope: TlsScope, scope_id: []const u8, endpoint: TlsReadEndpoint, args: TlsReadArgs) !net_http.Response {
        const url = try tlsReadUrl(gpa, self.base_url_override, scope, scope_id, endpoint, args);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZones(self: Client, io: Io, gpa: Allocator, domain: []const u8) !net_http.Response {
        const url = try zonesUrl(gpa, self.base_url_override, domain);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZone(self: Client, io: Io, gpa: Allocator, zone_id: []const u8) !net_http.Response {
        const url = try zoneUrl(gpa, self.base_url_override, zone_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsRecords(self: Client, io: Io, gpa: Allocator, zone_id: []const u8) !net_http.Response {
        const url = try dnsRecordsUrl(gpa, self.base_url_override, zone_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsAnalyticsEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: DnsAnalyticsEndpoint) !net_http.Response {
        const url = try dnsAnalyticsUrl(gpa, self.base_url_override, zone_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getDnsRecordEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: DnsRecordReadEndpoint, dns_record_id: ?[]const u8) !net_http.Response {
        const url = try dnsRecordReadUrl(gpa, self.base_url_override, zone_id, endpoint, dns_record_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: ZoneEndpoint) !net_http.Response {
        const url = try zoneEndpointUrl(gpa, self.base_url_override, zone_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneLifecycleReadEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: ZoneLifecycleReadEndpoint, plan_id: ?[]const u8) !net_http.Response {
        const url = try zoneLifecycleReadUrl(gpa, self.base_url_override, zone_id, endpoint, plan_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getSecondaryDnsZoneEndpoint(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, endpoint: SecondaryDnsZoneReadEndpoint) !net_http.Response {
        const url = try secondaryDnsZoneReadUrl(gpa, self.base_url_override, zone_id, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getUserTokenEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: UserTokenEndpoint) !net_http.Response {
        const url = try userTokenEndpointUrl(gpa, self.base_url_override, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getUserToken(self: Client, io: Io, gpa: Allocator, token_id: []const u8) !net_http.Response {
        const url = try userTokenUrl(gpa, self.base_url_override, token_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getIdentityEndpoint(self: Client, io: Io, gpa: Allocator, endpoint: IdentityEndpoint) !net_http.Response {
        const url = try identityEndpointUrl(gpa, self.base_url_override, endpoint);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getMembership(self: Client, io: Io, gpa: Allocator, membership_id: []const u8) !net_http.Response {
        const url = try membershipUrl(gpa, self.base_url_override, membership_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn getZoneSetting(self: Client, io: Io, gpa: Allocator, zone_id: []const u8, setting_id: []const u8) !net_http.Response {
        const url = try zoneSettingUrl(gpa, self.base_url_override, zone_id, setting_id);
        defer gpa.free(url);
        return try self.get(io, gpa, url);
    }

    pub fn get(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        return try cf_transport.get(io, gpa, self.auth, url);
    }

    pub fn getLegacy(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        return try cf_transport.getLegacy(io, gpa, self.auth, url);
    }

    pub fn getWithHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        return try cf_transport.getWithHeaders(io, gpa, self.auth, url, route_headers);
    }

    pub fn getWithLegacyHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        return try cf_transport.getWithLegacyHeaders(io, gpa, self.auth, url, route_headers);
    }

    pub fn getPublic(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        _ = self;
        return try cf_transport.getPublic(io, gpa, url);
    }

    pub fn getPublicWithHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        _ = self;
        return try cf_transport.getPublicWithHeaders(io, gpa, url, route_headers);
    }

    /// Raw authenticated escape hatch for endpoints without a typed helper.
    pub fn requestJson(self: Client, io: Io, gpa: Allocator, method: std.http.Method, url: []const u8, body: ?[]const u8) !net_http.Response {
        return try cf_transport.requestJson(io, gpa, self.auth, method, url, body);
    }
};

test "Browser Run clients preserve the configured base URL and explicit engine" {
    var client = Client.init(.{ .token = "token" });
    client.base_url_override = "http://127.0.0.1:9000/client/v4";
    const browser = try client.browserRun("account", .kitesurf);
    try std.testing.expectEqualStrings("http://127.0.0.1:9000/client/v4", browser.base_url);
    try std.testing.expectEqualStrings("account", browser.account_id);
    try std.testing.expectEqual(browser_run.Engine.kitesurf, browser.engine);
}
