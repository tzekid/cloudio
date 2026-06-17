const std = @import("std");
const sqlite = @import("sqlite");
const core_time = @import("core_time");
const core_process = @import("core_process");
const core_redact = @import("core_redact");
const collector_capture = @import("collector_capture");
const db_store = @import("db_store");
const provider_cloudflare = @import("provider_cloudflare");
const provider_cloudflare_models = @import("provider_cloudflare_models");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;
const columnText = db_store.columnText;

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
pub const TunnelReadArgs = provider_cloudflare.TunnelReadArgs;
pub const TunnelReadEndpoint = provider_cloudflare.TunnelReadEndpoint;
pub const ZeroTrustReadArgs = provider_cloudflare.ZeroTrustReadArgs;
pub const ZeroTrustReadEndpoint = provider_cloudflare.ZeroTrustReadEndpoint;
pub const SecurityCenterReadArgs = provider_cloudflare.SecurityCenterReadArgs;
pub const SecurityCenterReadEndpoint = provider_cloudflare.SecurityCenterReadEndpoint;
pub const SecurityCenterScope = provider_cloudflare.SecurityCenterScope;
pub const AuditLogReadArgs = provider_cloudflare.AuditLogReadArgs;
pub const AuditLogReadEndpoint = provider_cloudflare.AuditLogReadEndpoint;
pub const LoadBalancingAccountReadEndpoint = provider_cloudflare.LoadBalancingAccountReadEndpoint;
pub const LoadBalancingMutationArgs = provider_cloudflare.LoadBalancingMutationArgs;
pub const LoadBalancingMutationEndpoint = provider_cloudflare.LoadBalancingMutationEndpoint;
pub const LoadBalancingMutationResource = provider_cloudflare.LoadBalancingMutationResource;
pub const LoadBalancingUserReadEndpoint = provider_cloudflare.LoadBalancingUserReadEndpoint;
pub const LoadBalancingZoneReadEndpoint = provider_cloudflare.LoadBalancingZoneReadEndpoint;
pub const SecondaryDnsAccountMutationArgs = provider_cloudflare.SecondaryDnsAccountMutationArgs;
pub const SecondaryDnsAccountMutationEndpoint = provider_cloudflare.SecondaryDnsAccountMutationEndpoint;
pub const SecondaryDnsAccountResource = provider_cloudflare.SecondaryDnsAccountResource;
pub const SecondaryDnsZoneMutationArgs = provider_cloudflare.SecondaryDnsZoneMutationArgs;
pub const SecondaryDnsZoneMutationEndpoint = provider_cloudflare.SecondaryDnsZoneMutationEndpoint;
pub const SecondaryDnsZoneReadEndpoint = provider_cloudflare.SecondaryDnsZoneReadEndpoint;
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
pub const DnsRecordMutationArgs = provider_cloudflare.DnsRecordMutationArgs;
pub const DnsRecordMutationEndpoint = provider_cloudflare.DnsRecordMutationEndpoint;
pub const DnsRecordReadEndpoint = provider_cloudflare.DnsRecordReadEndpoint;
pub const DnssecMutationArgs = provider_cloudflare.DnssecMutationArgs;
pub const DnssecMutationEndpoint = provider_cloudflare.DnssecMutationEndpoint;
pub const IdentityEndpoint = provider_cloudflare.IdentityEndpoint;
pub const MembershipMutationArgs = provider_cloudflare.MembershipMutationArgs;
pub const MembershipMutationEndpoint = provider_cloudflare.MembershipMutationEndpoint;
pub const UserTokenEndpoint = provider_cloudflare.UserTokenEndpoint;
pub const UserTokenMutationArgs = provider_cloudflare.UserTokenMutationArgs;
pub const UserTokenMutationEndpoint = provider_cloudflare.UserTokenMutationEndpoint;
pub const SmartShieldHealthCheckReadEndpoint = provider_cloudflare.SmartShieldHealthCheckReadEndpoint;
pub const ZoneEndpoint = provider_cloudflare.ZoneEndpoint;
pub const ZoneHealthCheckReadEndpoint = provider_cloudflare.ZoneHealthCheckReadEndpoint;
pub const ZoneLifecycleMutationArgs = provider_cloudflare.ZoneLifecycleMutationArgs;
pub const ZoneLifecycleMutationEndpoint = provider_cloudflare.ZoneLifecycleMutationEndpoint;
pub const ZoneLifecycleReadEndpoint = provider_cloudflare.ZoneLifecycleReadEndpoint;
pub const ZoneMutationArgs = provider_cloudflare.ZoneMutationArgs;
pub const ZoneMutationEndpoint = provider_cloudflare.ZoneMutationEndpoint;

const max_command_bytes = 4 * 1024 * 1024;
const runCommand = core_process.run;

pub const Output = collector_capture.Output;

pub fn collectAll(io: Io, gpa: Allocator, auth: Auth, domains: []const []const u8, db: *Db) !void {
    var ips = try collectIps(io, gpa, db, null, false);
    ips.deinit(gpa);
    var user = try collectIdentityEndpoint(io, gpa, auth, db, .user, false);
    user.deinit(gpa);
    var tenants = try collectIdentityEndpoint(io, gpa, auth, db, .tenants, false);
    tenants.deinit(gpa);
    var memberships = try collectIdentityEndpoint(io, gpa, auth, db, .memberships, false);
    memberships.deinit(gpa);
    var token_list = try collectUserTokenEndpoint(io, gpa, auth, db, .list, false);
    token_list.deinit(gpa);
    var token_verify = try collectUserTokenEndpoint(io, gpa, auth, db, .verify, false);
    token_verify.deinit(gpa);
    var token_permission_groups = try collectUserTokenEndpoint(io, gpa, auth, db, .permission_groups, false);
    token_permission_groups.deinit(gpa);
    try collectIpAccessRulesForUser(io, gpa, auth, db);
    try collectLoadBalancingUserForRefresh(io, gpa, auth, db);
    var account_output = try collectAccounts(io, gpa, auth, db, false);
    account_output.deinit(gpa);
    for (domains) |domain| {
        var zone_output = try collectZone(io, gpa, auth, db, domain, false);
        zone_output.deinit(gpa);
        var dns_output = try collectDns(io, gpa, auth, db, domain, false);
        dns_output.deinit(gpa);
        try diagnoseDomain(io, gpa, db, domain);
    }
}

pub fn collectAccounts(io: Io, gpa: Allocator, auth: Auth, db: *Db, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "account", null, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccounts(io, gpa);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "accounts",
        .summary_label = "account list",
        .endpoint = provider_cloudflare.accounts_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    try persistAccountRows(gpa, db, redacted);
    try collectAccountEndpoints(gpa, io, client, db, redacted);
    try collectAccountCollectionsForAccounts(gpa, io, client, db, redacted);
    try collectAccountIamCollectionsForAccounts(gpa, io, client, db, redacted);
    try collectSecondaryDnsAccountCollectionsForAccounts(gpa, io, client, db, redacted);
    try collectDnsFirewallForAccounts(gpa, io, client, db, redacted);
    try collectLoadBalancingAccountForAccounts(gpa, io, client, db, redacted);
    try collectEndpointHealthChecksForAccounts(gpa, io, client, db, redacted);
    try collectAccountRulesetsForAccounts(gpa, io, client, db, redacted);
    try collectCloudforceOneRulesForAccounts(gpa, io, client, db, redacted);
    try collectIpAccessRulesForAccounts(gpa, io, client, db, redacted);
    try collectResourceTaggingForAccounts(gpa, io, client, db, redacted);
    try collectCustomPagesForAccounts(gpa, io, client, db, redacted);
    try collectAccessCustomPagesForAccounts(gpa, io, client, db, redacted);
    try collectAccessForAccounts(gpa, io, client, db, redacted);
    try collectTunnelsForAccounts(gpa, io, client, db, redacted);
    try collectZeroTrustForAccounts(gpa, io, client, db, redacted);
    try collectSecurityCenterForAccounts(gpa, io, client, db, redacted);
    try collectAuditLogsForAccounts(gpa, io, client, db, redacted);
    try collectAccountTokenEndpointsForAccounts(gpa, io, auth, client, db, redacted);
    try collectAccountDnsSettings(gpa, io, client, db, redacted);
    try collectAccountDnsRecordUsageForAccounts(gpa, io, client, db, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectIps(io: Io, gpa: Allocator, db: *Db, networks: ?[]const u8, capture_output: bool) !Output {
    const client = provider_cloudflare.Client.init(.{});
    const body = try client.getIps(io, gpa, networks);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.ipsPath(gpa, networks);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "ips",
        .target = networks,
        .summary_label = "cloudflare ips",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: AccountEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountEndpoint(io, gpa, account_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountEndpointPath(gpa, account_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = account_id,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountDnsRecordUsage(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "account-dns-record-usage", account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountDnsRecordUsage(io, gpa, account_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountDnsRecordUsagePath(gpa, account_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "account-dns-record-usage",
        .target = account_id,
        .summary_label = "account dns-record usage",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountCollection(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, collection: AccountCollection, capture_output: bool) !Output {
    const list_kind = collection.listKind();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", list_kind, account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountCollection(io, gpa, account_id, collection);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountCollectionPath(gpa, account_id, collection);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = list_kind,
        .target = account_id,
        .summary_label = list_kind,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountResource(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, collection: AccountCollection, resource_id: []const u8, capture_output: bool) !Output {
    const detail_kind = collection.detailKind();
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, resource_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", detail_kind, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountResource(io, gpa, account_id, collection, resource_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountResourcePath(gpa, account_id, collection, resource_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = detail_kind,
        .target = target,
        .summary_label = detail_kind,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountPermissionGroups(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, capture_output: bool) !Output {
    return try collectAccountIamCollection(io, gpa, auth, db, account_id, .permission_groups, capture_output);
}

pub fn collectAccountPermissionGroup(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, permission_group_id: []const u8, capture_output: bool) !Output {
    return try collectAccountIamResource(io, gpa, auth, db, account_id, .permission_groups, permission_group_id, capture_output);
}

pub fn collectAccountTokenEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: AccountTokenEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    if (endpoint == .verify and !auth.hasApiToken()) {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, account_id, "Cloudflare account token verification requires API token auth", "Cloudflare API token auth missing for account token verification", capture_output);
    }
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountTokenEndpoint(io, gpa, account_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountTokenEndpointPath(gpa, account_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = account_id,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountToken(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, token_id: []const u8, capture_output: bool) !Output {
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, token_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "account-token", target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountToken(io, gpa, account_id, token_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountTokenPath(gpa, account_id, token_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "account-token",
        .target = target,
        .summary_label = "account-token",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountIamCollection(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, collection: AccountIamCollection, capture_output: bool) !Output {
    const list_kind = collection.listKind();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", list_kind, account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountIamCollection(io, gpa, account_id, collection);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountIamCollectionPath(gpa, account_id, collection);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = list_kind,
        .target = account_id,
        .summary_label = list_kind,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountIamResource(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, collection: AccountIamCollection, resource_id: []const u8, capture_output: bool) !Output {
    const detail_kind = collection.detailKind();
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, resource_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", detail_kind, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountIamResource(io, gpa, account_id, collection, resource_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountIamResourcePath(gpa, account_id, collection, resource_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = detail_kind,
        .target = target,
        .summary_label = detail_kind,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountUserGroupMembers(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, user_group_id: []const u8, capture_output: bool) !Output {
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, user_group_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "account-user-group-members", target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountUserGroupMembers(io, gpa, account_id, user_group_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountUserGroupMembersPath(gpa, account_id, user_group_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "account-user-group-members",
        .target = target,
        .summary_label = "account-user-group-members",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccountUserGroupMember(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, user_group_id: []const u8, member_id: []const u8, capture_output: bool) !Output {
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ account_id, user_group_id, member_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "account-user-group-member", target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccountUserGroupMember(io, gpa, account_id, user_group_id, member_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accountUserGroupMemberPath(gpa, account_id, user_group_id, member_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "account-user-group-member",
        .target = target,
        .summary_label = "account-user-group-member",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectSecondaryDnsAccountCollection(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, resource: SecondaryDnsAccountResource, capture_output: bool) !Output {
    const list_kind = resource.listKind();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", list_kind, account_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getSecondaryDnsAccountCollection(io, gpa, account_id, resource);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.secondaryDnsAccountCollectionPath(gpa, account_id, resource);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = list_kind,
        .target = account_id,
        .summary_label = resource.listSummary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectSecondaryDnsAccountResource(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, resource: SecondaryDnsAccountResource, resource_id: []const u8, capture_output: bool) !Output {
    const detail_kind = resource.detailKind();
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, resource_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", detail_kind, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getSecondaryDnsAccountResource(io, gpa, account_id, resource, resource_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.secondaryDnsAccountResourcePath(gpa, account_id, resource, resource_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = detail_kind,
        .target = target,
        .summary_label = resource.detailSummary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDnsFirewallReadEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: DnsFirewallReadEndpoint, dns_firewall_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (dns_firewall_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, id }) else try gpa.dupe(u8, account_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getDnsFirewallReadEndpoint(io, gpa, account_id, endpoint, dns_firewall_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.dnsFirewallReadPath(gpa, account_id, endpoint, dns_firewall_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDnsFirewallAnalyticsEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, dns_firewall_id: []const u8, endpoint: DnsAnalyticsEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.firewallLabel();
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, dns_firewall_id });
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getDnsFirewallAnalyticsEndpoint(io, gpa, account_id, dns_firewall_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.dnsFirewallAnalyticsPath(gpa, account_id, dns_firewall_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectLoadBalancingAccountEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (resource_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, id }) else try gpa.dupe(u8, account_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getLoadBalancingAccountEndpoint(io, gpa, account_id, endpoint, resource_id, search_query);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.loadBalancingAccountReadPath(gpa, account_id, endpoint, resource_id, search_query);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectLoadBalancingUserEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = resource_id orelse "user";
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getLoadBalancingUserEndpoint(io, gpa, endpoint, resource_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.loadBalancingUserReadPath(gpa, endpoint, resource_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectLoadBalancingZoneEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: LoadBalancingZoneReadEndpoint, load_balancer_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (load_balancer_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_id, id }) else try gpa.dupe(u8, zone_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getLoadBalancingZoneEndpoint(io, gpa, zone_id, endpoint, load_balancer_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.loadBalancingZoneReadPath(gpa, zone_id, endpoint, load_balancer_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectEndpointHealthCheck(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (healthcheck_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, id }) else try gpa.dupe(u8, account_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getEndpointHealthCheck(io, gpa, account_id, endpoint, healthcheck_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.endpointHealthCheckReadPath(gpa, account_id, endpoint, healthcheck_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZoneHealthCheck(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: ZoneHealthCheckReadEndpoint, healthcheck_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (healthcheck_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_id, id }) else try gpa.dupe(u8, zone_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZoneHealthCheck(io, gpa, zone_id, endpoint, healthcheck_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zoneHealthCheckReadPath(gpa, zone_id, endpoint, healthcheck_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectSmartShieldHealthCheck(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: SmartShieldHealthCheckReadEndpoint, healthcheck_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (healthcheck_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_id, id }) else try gpa.dupe(u8, zone_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getSmartShieldHealthCheck(io, gpa, zone_id, endpoint, healthcheck_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.smartShieldHealthCheckReadPath(gpa, zone_id, endpoint, healthcheck_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectResourceTaggingAccountEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try resourceTaggingAccountTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getResourceTaggingAccountEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.resourceTaggingAccountReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectResourceTaggingZoneTags(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, args: ResourceTaggingZoneReadArgs, capture_output: bool) !Output {
    const target = try resourceTaggingZoneTarget(gpa, zone_id, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "resource-tags-zone", target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getResourceTaggingZoneTags(io, gpa, zone_id, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.resourceTaggingZoneReadPath(gpa, zone_id, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "resource-tags-zone",
        .target = target,
        .summary_label = "Get tags for a zone-level resource",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectRulesetEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, scope: RulesetScope, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(scope);
    const target = try rulesetTarget(gpa, scope_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getRulesetEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.rulesetReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectCloudforceOneRuleEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try cloudforceOneRuleTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getCloudforceOneRuleEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.cloudforceOneRuleReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectIpAccessRuleEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(scope);
    const target = try ipAccessRuleTarget(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getIpAccessRuleEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.ipAccessRuleReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = try endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZoneLegacyRuleEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(resource);
    const target = try zoneLegacyRuleTarget(gpa, zone_id, endpoint, rule_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZoneLegacyRuleEndpoint(io, gpa, zone_id, resource, endpoint, rule_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zoneLegacyRuleReadPath(gpa, zone_id, resource, endpoint, rule_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(resource),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectPageShieldEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try pageShieldTarget(gpa, zone_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getPageShieldEndpoint(io, gpa, zone_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.pageShieldReadPath(gpa, zone_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectCustomPageEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(scope, resource);
    const target = try customPageTarget(gpa, scope_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getCustomPageEndpoint(io, gpa, scope, scope_id, resource, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.customPageReadPath(gpa, scope, scope_id, resource, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(scope, resource),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccessCustomPageEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try accessCustomPageTarget(gpa, account_id, endpoint, page_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccessCustomPageEndpoint(io, gpa, account_id, endpoint, page_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accessCustomPageReadPath(gpa, account_id, endpoint, page_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAccessEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, scope: AccessScope, scope_id: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(scope);
    const target = try accessTarget(gpa, scope_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAccessEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accessReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectTunnelEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try tunnelTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getTunnelEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.tunnelReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZeroTrustEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try zeroTrustTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZeroTrustEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zeroTrustReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectSecurityCenterEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, scope: SecurityCenterScope, scope_id: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label(scope);
    const target = try securityCenterTarget(gpa, scope_id, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getSecurityCenterEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.securityCenterReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectAuditLogEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try auditLogTarget(gpa, endpoint, args);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getAuditLogEndpoint(io, gpa, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.auditLogReadPath(gpa, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectIdentityEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, endpoint: IdentityEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, null, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getIdentityEndpoint(io, gpa, endpoint);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .summary_label = endpoint_label,
        .endpoint = endpoint.path(),
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (endpoint == .memberships) {
        try collectMembershipDetailsForResponse(gpa, io, client, db, redacted);
    }
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectMembership(io: Io, gpa: Allocator, auth: Auth, db: *Db, membership_id: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "membership", membership_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getMembership(io, gpa, membership_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.membershipPath(gpa, membership_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "membership",
        .target = membership_id,
        .summary_label = "membership",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectUserTokenEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, endpoint: UserTokenEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    if (endpoint.requiresTokenId()) {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, null, "Cloudflare user token id required", "Cloudflare user token id required", capture_output);
    }
    if (endpoint == .verify and !auth.hasApiToken()) {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, null, "Cloudflare token verification requires API token auth", "Cloudflare API token auth missing for token verification", capture_output);
    }
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, null, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getUserTokenEndpoint(io, gpa, endpoint);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .summary_label = endpoint_label,
        .endpoint = endpoint.path(),
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectUserToken(io: Io, gpa: Allocator, auth: Auth, db: *Db, token_id: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "user-token", token_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getUserToken(io, gpa, token_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.userTokenReadPath(gpa, .details, token_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "user-token",
        .target = token_id,
        .summary_label = "user-token",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZone(io: Io, gpa: Allocator, auth: Auth, db: *Db, domain: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "zone", domain, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZones(io, gpa, domain);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "zone",
        .target = domain,
        .summary_label = "zone details",
        .endpoint = provider_cloudflare.zones_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    try persistZoneRows(gpa, db, redacted);

    if (try provider_cloudflare_models.zoneIdFromResponse(gpa, redacted)) |zone_id| {
        defer gpa.free(zone_id);
        const endpoints = [_]ZoneEndpoint{
            .dnssec,
            .dns_settings,
            .settings,
            .settings_aegis,
            .settings_fonts,
            .settings_origin_h2_max_streams,
            .settings_origin_max_http_version,
            .settings_speed_brain,
            .settings_ssl_automatic_mode,
        };
        for (endpoints) |endpoint| {
            const extra_body = client.getZoneEndpoint(io, gpa, zone_id, endpoint) catch |err| {
                const endpoint_label = endpoint.label();
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, domain, "error", error_summary, null, null);
                continue;
            };
            defer extra_body.deinit(gpa);
            const endpoint_label = endpoint.label();
            const endpoint_path = try provider_cloudflare.zoneEndpointPath(gpa, zone_id, endpoint);
            defer gpa.free(endpoint_path);
            const extra_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = domain,
                .summary_label = endpoint_label,
                .endpoint = endpoint_path,
                .status = extra_body.status,
                .body = extra_body.body,
            });
            defer gpa.free(extra_redacted);
        }

        const lifecycle_endpoints = [_]ZoneLifecycleReadEndpoint{
            .available_plans,
            .available_rate_plans,
            .cache_reserve,
            .cache_reserve_clear,
            .regional_tiered_cache,
            .variants,
            .environments,
            .hold,
            .subscription,
        };
        for (lifecycle_endpoints) |endpoint| {
            const extra_body = client.getZoneLifecycleReadEndpoint(io, gpa, zone_id, endpoint, null) catch |err| {
                const endpoint_label = endpoint.label();
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, domain, "error", error_summary, null, null);
                continue;
            };
            defer extra_body.deinit(gpa);
            const endpoint_label = endpoint.label();
            const endpoint_path = try provider_cloudflare.zoneLifecycleReadPath(gpa, zone_id, endpoint, null);
            defer gpa.free(endpoint_path);
            const extra_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = domain,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = extra_body.status,
                .body = extra_body.body,
            });
            defer gpa.free(extra_redacted);
        }

        const secondary_dns_zone_endpoints = [_]SecondaryDnsZoneReadEndpoint{
            .primary,
            .primary_status,
            .secondary,
        };
        for (secondary_dns_zone_endpoints) |endpoint| {
            const extra_body = client.getSecondaryDnsZoneEndpoint(io, gpa, zone_id, endpoint) catch |err| {
                const endpoint_label = endpoint.label();
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, domain, "error", error_summary, null, null);
                continue;
            };
            defer extra_body.deinit(gpa);
            const endpoint_label = endpoint.label();
            const endpoint_path = try provider_cloudflare.secondaryDnsZoneReadPath(gpa, zone_id, endpoint);
            defer gpa.free(endpoint_path);
            const extra_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = domain,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = extra_body.status,
                .body = extra_body.body,
            });
            defer gpa.free(extra_redacted);
        }

        const dns_analytics_endpoints = [_]DnsAnalyticsEndpoint{ .report, .bytime };
        for (dns_analytics_endpoints) |endpoint| {
            const extra_body = client.getDnsAnalyticsEndpoint(io, gpa, zone_id, endpoint) catch |err| {
                const endpoint_label = endpoint.label();
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, domain, "error", error_summary, null, null);
                continue;
            };
            defer extra_body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.dnsAnalyticsPath(gpa, zone_id, endpoint);
            defer gpa.free(endpoint_path);
            const extra_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint.label(),
                .target = domain,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = extra_body.status,
                .body = extra_body.body,
            });
            defer gpa.free(extra_redacted);
        }

        lb_refresh: {
            const lb_endpoint: LoadBalancingZoneReadEndpoint = .load_balancers;
            const lb_body = client.getLoadBalancingZoneEndpoint(io, gpa, zone_id, lb_endpoint, null) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ lb_endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", lb_endpoint.label(), domain, "error", error_summary, null, null);
                break :lb_refresh;
            };
            defer lb_body.deinit(gpa);
            const lb_endpoint_path = try provider_cloudflare.loadBalancingZoneReadPath(gpa, zone_id, lb_endpoint, null);
            defer gpa.free(lb_endpoint_path);
            const lb_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = lb_endpoint.label(),
                .target = domain,
                .summary_label = lb_endpoint.summary(),
                .endpoint = lb_endpoint_path,
                .status = lb_body.status,
                .body = lb_body.body,
            });
            defer gpa.free(lb_redacted);
            try collectLoadBalancingZoneDetailsForList(gpa, io, client, db, zone_id, domain, lb_redacted);
        }

        health_checks_refresh: {
            const endpoint: ZoneHealthCheckReadEndpoint = .list;
            const health_body = client.getZoneHealthCheck(io, gpa, zone_id, endpoint, null) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), domain, "error", error_summary, null, null);
                break :health_checks_refresh;
            };
            defer health_body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.zoneHealthCheckReadPath(gpa, zone_id, endpoint, null);
            defer gpa.free(endpoint_path);
            const health_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint.label(),
                .target = domain,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = health_body.status,
                .body = health_body.body,
            });
            defer gpa.free(health_redacted);
            try collectZoneHealthCheckDetailsForList(gpa, io, client, db, zone_id, domain, health_redacted);
        }

        smart_shield_refresh: {
            const endpoint: SmartShieldHealthCheckReadEndpoint = .list;
            const smart_body = client.getSmartShieldHealthCheck(io, gpa, zone_id, endpoint, null) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), domain, "error", error_summary, null, null);
                break :smart_shield_refresh;
            };
            defer smart_body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.smartShieldHealthCheckReadPath(gpa, zone_id, endpoint, null);
            defer gpa.free(endpoint_path);
            const smart_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint.label(),
                .target = domain,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = smart_body.status,
                .body = smart_body.body,
            });
            defer gpa.free(smart_redacted);
            try collectSmartShieldHealthCheckDetailsForList(gpa, io, client, db, zone_id, domain, smart_redacted);
        }

        zone_rulesets_refresh: {
            const endpoint: RulesetReadEndpoint = .list;
            const redacted_rulesets = collectRulesetSnapshot(gpa, io, client, db, .zone, zone_id, domain, endpoint, .{}) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(.zone), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(.zone), domain, "error", error_summary, null, null);
                break :zone_rulesets_refresh;
            };
            defer gpa.free(redacted_rulesets);
            try collectRulesetDetailsForList(gpa, io, client, db, .zone, zone_id, domain, redacted_rulesets);
        }

        zone_ip_access_refresh: {
            const endpoint: IpAccessRuleReadEndpoint = .list;
            const redacted_ip_access = collectIpAccessRuleSnapshot(gpa, io, client, db, .zone, zone_id, endpoint, .{}) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(.zone), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(.zone), domain, "error", error_summary, null, null);
                break :zone_ip_access_refresh;
            };
            defer gpa.free(redacted_ip_access);
        }

        const legacy_rule_resources = [_]ZoneLegacyRuleResource{ .page_rules, .ua_rules, .zone_lockdown };
        for (legacy_rule_resources) |resource| {
            try collectZoneLegacyRulesForZone(gpa, io, client, db, zone_id, domain, resource);
        }

        try collectPageShieldForZone(gpa, io, client, db, zone_id, domain);
        try collectCustomPagesForZone(gpa, io, client, db, zone_id, domain);
        try collectAccessForZone(gpa, io, client, db, zone_id, domain);
        try collectSecurityCenterForZone(gpa, io, client, db, zone_id, domain);

        zone_tags_refresh: {
            const tag_body = client.getResourceTaggingZoneTags(io, gpa, zone_id, .{
                .resource_id = zone_id,
                .resource_type = "zone",
            }) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "resource-tags-zone: {s}", .{@errorName(err)});
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", "resource-tags-zone", domain, "error", error_summary, null, null);
                break :zone_tags_refresh;
            };
            defer tag_body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.resourceTaggingZoneReadPath(gpa, zone_id, .{
                .resource_id = zone_id,
                .resource_type = "zone",
            });
            defer gpa.free(endpoint_path);
            const tag_redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = "resource-tags-zone",
                .target = domain,
                .summary_label = "Get tags for a zone-level resource",
                .endpoint = endpoint_path,
                .status = tag_body.status,
                .body = tag_body.body,
            });
            defer gpa.free(tag_redacted);
        }
    }

    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZoneById(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", "zone-detail", zone_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZone(io, gpa, zone_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zonePath(gpa, zone_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = "zone-detail",
        .target = zone_id,
        .summary_label = "zone-detail",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZoneLifecycleReadEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: ZoneLifecycleReadEndpoint, plan_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = if (plan_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_id, id }) else try gpa.dupe(u8, zone_id);
    defer gpa.free(target);
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getZoneLifecycleReadEndpoint(io, gpa, zone_id, endpoint, plan_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zoneLifecycleReadPath(gpa, zone_id, endpoint, plan_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectSecondaryDnsZoneEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: SecondaryDnsZoneReadEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, zone_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getSecondaryDnsZoneEndpoint(io, gpa, zone_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.secondaryDnsZoneReadPath(gpa, zone_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = zone_id,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDnsAnalyticsEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, zone_id: []const u8, endpoint: DnsAnalyticsEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, zone_id, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const body = try client.getDnsAnalyticsEndpoint(io, gpa, zone_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.dnsAnalyticsPath(gpa, zone_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint_label,
        .target = zone_id,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectZoneEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, domain: []const u8, endpoint: ZoneEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint_label, domain, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const zone_body = try client.getZones(io, gpa, domain);
    defer zone_body.deinit(gpa);
    if (try provider_cloudflare_models.zoneIdFromResponse(gpa, zone_body.body)) |zone_id| {
        defer gpa.free(zone_id);
        const body = try client.getZoneEndpoint(io, gpa, zone_id, endpoint);
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.zoneEndpointPath(gpa, zone_id, endpoint);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = endpoint_label,
            .target = domain,
            .summary_label = endpoint_label,
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer if (!capture_output) gpa.free(redacted);
        return .{ .text = if (capture_output) redacted else null };
    }

    _ = try db.insertSnapshot("cloudflare", endpoint_label, domain, "not_found", "zone id not found", null, null);
    const message = try std.fmt.allocPrint(gpa, "zone not found: {s}", .{domain});
    defer gpa.free(message);
    return try collector_capture.outputText(gpa, capture_output, message);
}

pub fn collectDns(io: Io, gpa: Allocator, auth: Auth, db: *Db, domain: []const u8, capture_output: bool) !Output {
    return try collectDnsRecordEndpoint(io, gpa, auth, db, domain, .list, null, capture_output);
}

pub fn collectDnsRecordEndpoint(io: Io, gpa: Allocator, auth: Auth, db: *Db, domain: []const u8, endpoint: DnsRecordReadEndpoint, dns_record_id: ?[]const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        return try collector_capture.skipped(gpa, db, "cloudflare", endpoint.label(), domain, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const zone_body = try client.getZones(io, gpa, domain);
    defer zone_body.deinit(gpa);
    if (try provider_cloudflare_models.zoneIdFromResponse(gpa, zone_body.body)) |zone_id| {
        defer gpa.free(zone_id);
        const body = try client.getDnsRecordEndpoint(io, gpa, zone_id, endpoint, dns_record_id);
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.dnsRecordReadPath(gpa, zone_id, endpoint, dns_record_id);
        defer gpa.free(endpoint_path);
        const target = if (dns_record_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domain, id }) else try gpa.dupe(u8, domain);
        defer gpa.free(target);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = endpoint.label(),
            .target = target,
            .summary_label = endpoint.summary(),
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer if (!capture_output) gpa.free(redacted);
        if (endpoint == .list) try persistDnsRecordRows(gpa, db, zone_id, redacted);
        return .{ .text = if (capture_output) redacted else null };
    }

    _ = try db.insertSnapshot("cloudflare", endpoint.label(), domain, "not_found", "zone id not found", null, null);
    const message = try std.fmt.allocPrint(gpa, "zone not found: {s}", .{domain});
    defer gpa.free(message);
    return try collector_capture.outputText(gpa, capture_output, message);
}

pub fn collectZoneSetting(io: Io, gpa: Allocator, auth: Auth, db: *Db, domain: []const u8, setting_id: []const u8, capture_output: bool) !Output {
    const client = clientFromAuth(auth) catch {
        const target = try settingTarget(gpa, domain, setting_id);
        defer gpa.free(target);
        return try collector_capture.skipped(gpa, db, "cloudflare", "setting", target, "missing Cloudflare credentials", "Cloudflare credentials missing", capture_output);
    };
    const zone_body = try client.getZones(io, gpa, domain);
    defer zone_body.deinit(gpa);
    if (try provider_cloudflare_models.zoneIdFromResponse(gpa, zone_body.body)) |zone_id| {
        defer gpa.free(zone_id);
        const body = try client.getZoneSetting(io, gpa, zone_id, setting_id);
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.zoneSettingPath(gpa, zone_id, setting_id);
        defer gpa.free(endpoint_path);
        const target = try settingTarget(gpa, domain, setting_id);
        defer gpa.free(target);
        const summary_label = try std.fmt.allocPrint(gpa, "setting {s}", .{setting_id});
        defer gpa.free(summary_label);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "setting",
            .target = target,
            .summary_label = summary_label,
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer if (!capture_output) gpa.free(redacted);
        return .{ .text = if (capture_output) redacted else null };
    }

    _ = try db.insertSnapshot("cloudflare", "setting", domain, "not_found", "zone id not found", null, null);
    const message = try std.fmt.allocPrint(gpa, "zone not found: {s}", .{domain});
    defer gpa.free(message);
    return try collector_capture.outputText(gpa, capture_output, message);
}

fn collectAccountDnsSettings(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const body = client.getAccountDnsSettings(io, gpa, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "account-dns-settings: {s}", .{@errorName(err)});
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", "account-dns-settings", row.id, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.accountDnsSettingsPath(gpa, row.id);
        defer gpa.free(endpoint_path);
        const extra_redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "account-dns-settings",
            .target = row.id,
            .summary_label = "account dns-settings",
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(extra_redacted);
    }
}

fn collectAccountDnsRecordUsageForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const body = client.getAccountDnsRecordUsage(io, gpa, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "account-dns-record-usage: {s}", .{@errorName(err)});
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", "account-dns-record-usage", row.id, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.accountDnsRecordUsagePath(gpa, row.id);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "account-dns-record-usage",
            .target = row.id,
            .summary_label = "account dns-record usage",
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectMembershipDetailsForResponse(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, memberships_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, memberships_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const body = client.getMembership(io, gpa, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "membership: {s}", .{@errorName(err)});
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", "membership", row.id, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.membershipPath(gpa, row.id);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "membership",
            .target = row.id,
            .summary_label = "membership",
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectAccountEndpoints(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]AccountEndpoint{
        .details,
        .profile,
        .organizations,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            const endpoint_label = endpoint.label();
            const body = client.getAccountEndpoint(io, gpa, row.id, endpoint) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.accountEndpointPath(gpa, row.id, endpoint);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = row.id,
                .summary_label = endpoint_label,
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
    }
}

fn collectAccountCollectionsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const collections = [_]AccountCollection{
        .members,
        .roles,
    };
    for (rows.items) |row| {
        for (collections) |collection| {
            const list_kind = collection.listKind();
            const body = client.getAccountCollection(io, gpa, row.id, collection) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ list_kind, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", list_kind, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.accountCollectionPath(gpa, row.id, collection);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = list_kind,
                .target = row.id,
                .summary_label = list_kind,
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
    }
}

fn collectAccountIamCollectionsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const collections = [_]AccountIamCollection{
        .permission_groups,
        .resource_groups,
        .user_groups,
    };
    for (rows.items) |row| {
        for (collections) |collection| {
            const list_kind = collection.listKind();
            const body = client.getAccountIamCollection(io, gpa, row.id, collection) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ list_kind, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", list_kind, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.accountIamCollectionPath(gpa, row.id, collection);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = list_kind,
                .target = row.id,
                .summary_label = list_kind,
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
            if (collection == .user_groups) try collectAccountUserGroupMembersForGroups(gpa, io, client, db, row.id, redacted);
        }
    }
}

fn collectSecondaryDnsAccountCollectionsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const resources = [_]SecondaryDnsAccountResource{
        .acl,
        .peer,
        .tsig,
    };
    for (rows.items) |row| {
        for (resources) |resource| {
            const list_kind = resource.listKind();
            const body = client.getSecondaryDnsAccountCollection(io, gpa, row.id, resource) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ list_kind, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", list_kind, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.secondaryDnsAccountCollectionPath(gpa, row.id, resource);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = list_kind,
                .target = row.id,
                .summary_label = resource.listSummary(),
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
    }
}

fn collectDnsFirewallForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const body = client.getDnsFirewallReadEndpoint(io, gpa, row.id, .list, null) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "dns-firewall: {s}", .{@errorName(err)});
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", "dns-firewall", row.id, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.dnsFirewallReadPath(gpa, row.id, .list, null);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "dns-firewall",
            .target = row.id,
            .summary_label = "List DNS Firewall Clusters",
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
        try collectDnsFirewallDetailsForList(gpa, io, client, db, row.id, redacted);
    }
}

fn collectDnsFirewallDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const read_endpoints = [_]DnsFirewallReadEndpoint{ .details, .reverse_dns };
    const analytics_endpoints = [_]DnsAnalyticsEndpoint{ .report, .bytime };
    for (rows.items) |row| {
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
        defer gpa.free(target);
        for (read_endpoints) |endpoint| {
            const body = client.getDnsFirewallReadEndpoint(io, gpa, account_id, endpoint, row.id) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.dnsFirewallReadPath(gpa, account_id, endpoint, row.id);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint.label(),
                .target = target,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
        for (analytics_endpoints) |endpoint| {
            const body = client.getDnsFirewallAnalyticsEndpoint(io, gpa, account_id, row.id, endpoint) catch |err| {
                const endpoint_label = endpoint.firewallLabel();
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, target, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.dnsFirewallAnalyticsPath(gpa, account_id, row.id, endpoint);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint.firewallLabel(),
                .target = target,
                .summary_label = endpoint.summary(),
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
    }
}

fn collectLoadBalancingAccountForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const list_endpoints = [_]LoadBalancingAccountReadEndpoint{
        .monitor_groups,
        .monitors,
        .pools,
        .regions,
    };
    for (rows.items) |row| {
        for (list_endpoints) |endpoint| {
            const redacted = collectLoadBalancingAccountSnapshot(gpa, io, client, db, row.id, endpoint, null, null) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), row.id, "error", error_summary, null, null);
                continue;
            };
            defer gpa.free(redacted);
            try collectLoadBalancingAccountDetailsForList(gpa, io, client, db, row.id, endpoint, redacted);
        }
    }
}

fn collectLoadBalancingAccountDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_endpoint: LoadBalancingAccountReadEndpoint, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const detail_endpoints: []const LoadBalancingAccountReadEndpoint = switch (list_endpoint) {
        .monitor_groups => &[_]LoadBalancingAccountReadEndpoint{ .monitor_group, .monitor_group_references },
        .monitors => &[_]LoadBalancingAccountReadEndpoint{ .monitor, .monitor_references },
        .pools => &[_]LoadBalancingAccountReadEndpoint{ .pool, .pool_health, .pool_references },
        .regions => &[_]LoadBalancingAccountReadEndpoint{.region},
        else => &[_]LoadBalancingAccountReadEndpoint{},
    };
    for (rows.items) |row| {
        for (detail_endpoints) |endpoint| {
            const redacted = collectLoadBalancingAccountSnapshot(gpa, io, client, db, account_id, endpoint, row.id, null) catch |err| {
                const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
                defer gpa.free(target);
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
                continue;
            };
            defer gpa.free(redacted);
        }
    }
}

fn collectLoadBalancingAccountSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8) ![]u8 {
    const body = try client.getLoadBalancingAccountEndpoint(io, gpa, account_id, endpoint, resource_id, search_query);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.loadBalancingAccountReadPath(gpa, account_id, endpoint, resource_id, search_query);
    defer gpa.free(endpoint_path);
    const target = if (resource_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, id }) else try gpa.dupe(u8, account_id);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectLoadBalancingUserForRefresh(io: Io, gpa: Allocator, auth: Auth, db: *Db) !void {
    const client = clientFromAuth(auth) catch {
        _ = try db.insertSnapshot("cloudflare", "load-balancing-user", "user", "skipped", "missing Cloudflare credentials", null, null);
        return;
    };
    const list_endpoints = [_]LoadBalancingUserReadEndpoint{
        .monitors,
        .pools,
        .healthcheck_events,
    };
    for (list_endpoints) |endpoint| {
        const redacted = collectLoadBalancingUserSnapshot(gpa, io, client, db, endpoint, null) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), "user", "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectLoadBalancingUserDetailsForList(gpa, io, client, db, endpoint, redacted);
    }
}

fn collectLoadBalancingUserDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, list_endpoint: LoadBalancingUserReadEndpoint, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const detail_endpoints: []const LoadBalancingUserReadEndpoint = switch (list_endpoint) {
        .monitors => &[_]LoadBalancingUserReadEndpoint{ .monitor, .monitor_references },
        .pools => &[_]LoadBalancingUserReadEndpoint{ .pool, .pool_health, .pool_references },
        else => &[_]LoadBalancingUserReadEndpoint{},
    };
    for (rows.items) |row| {
        for (detail_endpoints) |endpoint| {
            const redacted = collectLoadBalancingUserSnapshot(gpa, io, client, db, endpoint, row.id) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), row.id, "error", error_summary, null, null);
                continue;
            };
            defer gpa.free(redacted);
        }
    }
}

fn collectLoadBalancingUserSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8) ![]u8 {
    const body = try client.getLoadBalancingUserEndpoint(io, gpa, endpoint, resource_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.loadBalancingUserReadPath(gpa, endpoint, resource_id);
    defer gpa.free(endpoint_path);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = resource_id orelse "user",
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectLoadBalancingZoneDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
        defer gpa.free(target);
        const endpoint: LoadBalancingZoneReadEndpoint = .load_balancer;
        const body = client.getLoadBalancingZoneEndpoint(io, gpa, zone_id, endpoint, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.loadBalancingZoneReadPath(gpa, zone_id, endpoint, row.id);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = endpoint.label(),
            .target = target,
            .summary_label = endpoint.summary(),
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectEndpointHealthChecksForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const list_endpoint: EndpointHealthCheckReadEndpoint = .list;
        const redacted = collectEndpointHealthCheckSnapshot(gpa, io, client, db, row.id, list_endpoint, null) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ list_endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", list_endpoint.label(), row.id, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectEndpointHealthCheckDetailsForList(gpa, io, client, db, row.id, redacted);
    }
}

fn collectEndpointHealthCheckDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const endpoint: EndpointHealthCheckReadEndpoint = .details;
        const redacted = collectEndpointHealthCheckSnapshot(gpa, io, client, db, account_id, endpoint, row.id) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectEndpointHealthCheckSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    const body = try client.getEndpointHealthCheck(io, gpa, account_id, endpoint, healthcheck_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.endpointHealthCheckReadPath(gpa, account_id, endpoint, healthcheck_id);
    defer gpa.free(endpoint_path);
    const target = if (healthcheck_id) |id| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, id }) else try gpa.dupe(u8, account_id);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectAccountRulesetsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const endpoint: RulesetReadEndpoint = .list;
        const redacted = collectRulesetSnapshot(gpa, io, client, db, .account, row.id, row.id, endpoint, .{}) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(.account), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(.account), row.id, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectRulesetDetailsForList(gpa, io, client, db, .account, row.id, row.id, redacted);
    }
}

fn collectRulesetDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: RulesetScope, scope_id: []const u8, target_label: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const details_endpoint: RulesetReadEndpoint = .ruleset;
    const versions_endpoint: RulesetReadEndpoint = .versions;
    for (rows.items) |row| {
        const args: RulesetReadArgs = .{ .ruleset_id = row.id };
        const detail = collectRulesetSnapshot(gpa, io, client, db, scope, scope_id, target_label, details_endpoint, args) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ details_endpoint.label(scope), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", details_endpoint.label(scope), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(detail);

        const versions = collectRulesetSnapshot(gpa, io, client, db, scope, scope_id, target_label, versions_endpoint, args) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ versions_endpoint.label(scope), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", versions_endpoint.label(scope), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(versions);
    }
}

fn collectCloudforceOneRulesForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]CloudforceOneRuleReadEndpoint{ .list, .managed, .stats, .tree };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            const redacted = collectCloudforceOneRuleSnapshot(gpa, io, client, db, row.id, endpoint, .{}) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), row.id, "error", error_summary, null, null);
                continue;
            };
            defer gpa.free(redacted);
            if (endpoint == .list) try collectCloudforceOneRuleDetailsForList(gpa, io, client, db, row.id, redacted);
        }
    }
}

fn collectCloudforceOneRuleDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const endpoint: CloudforceOneRuleReadEndpoint = .rule;
    for (rows.items) |row| {
        const redacted = collectCloudforceOneRuleSnapshot(gpa, io, client, db, account_id, endpoint, .{ .rule_id = row.id }) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectCloudforceOneRuleSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) ![]u8 {
    const body = try client.getCloudforceOneRuleEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.cloudforceOneRuleReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try cloudforceOneRuleTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectIpAccessRulesForUser(io: Io, gpa: Allocator, auth: Auth, db: *Db) !void {
    const client = clientFromAuth(auth) catch {
        _ = try collector_capture.skipped(gpa, db, "cloudflare", "user-ip-access-rules", "user", "missing Cloudflare credentials", "Cloudflare credentials missing", false);
        return;
    };
    const endpoint: IpAccessRuleReadEndpoint = .list;
    const redacted = collectIpAccessRuleSnapshot(gpa, io, client, db, .user, null, endpoint, .{}) catch |err| {
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(.user), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(.user), "user", "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectIpAccessRuleDetailsForList(gpa, io, client, db, .user, null, "user", redacted);
}

fn collectIpAccessRulesForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoint: IpAccessRuleReadEndpoint = .list;
    for (rows.items) |row| {
        const redacted = collectIpAccessRuleSnapshot(gpa, io, client, db, .account, row.id, endpoint, .{}) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(.account), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(.account), row.id, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectIpAccessRuleDetailsForList(gpa, io, client, db, .account, row.id, row.id, redacted);
    }
}

fn collectIpAccessRuleDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: IpAccessRuleScope, scope_id: ?[]const u8, target_label: []const u8, list_body: []const u8) !void {
    const endpoint: IpAccessRuleReadEndpoint = .rule;
    if (!endpoint.supports(scope)) return;
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const redacted = collectIpAccessRuleSnapshot(gpa, io, client, db, scope, scope_id, endpoint, .{ .rule_id = row.id }) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(scope), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(scope), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectIpAccessRuleSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) ![]u8 {
    const body = try client.getIpAccessRuleEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.ipAccessRuleReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try ipAccessRuleTarget(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(scope),
        .target = target,
        .summary_label = try endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectZoneLegacyRulesForZone(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, resource: ZoneLegacyRuleResource) !void {
    const endpoint: ZoneLegacyRuleReadEndpoint = .list;
    const redacted = collectZoneLegacyRuleSnapshot(gpa, io, client, db, zone_id, target_label, resource, endpoint, null) catch |err| {
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(resource), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(resource), target_label, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectZoneLegacyRuleDetailsForList(gpa, io, client, db, zone_id, target_label, resource, redacted);
}

fn collectZoneLegacyRuleDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, resource: ZoneLegacyRuleResource, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const endpoint: ZoneLegacyRuleReadEndpoint = .rule;
    for (rows.items) |row| {
        const redacted = collectZoneLegacyRuleSnapshot(gpa, io, client, db, zone_id, target_label, resource, endpoint, row.id) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(resource), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(resource), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectZoneLegacyRuleSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) ![]u8 {
    const body = try client.getZoneLegacyRuleEndpoint(io, gpa, zone_id, resource, endpoint, rule_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zoneLegacyRuleReadPath(gpa, zone_id, resource, endpoint, rule_id);
    defer gpa.free(endpoint_path);
    const target = try zoneLegacyRuleTarget(gpa, target_label, endpoint, rule_id);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(resource),
        .target = target,
        .summary_label = endpoint.summary(resource),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectPageShieldForZone(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8) !void {
    const endpoints = [_]PageShieldReadEndpoint{
        .settings,
        .policies,
        .connections,
        .scripts,
        .cookies,
    };
    for (endpoints) |endpoint| {
        const redacted = collectPageShieldSnapshot(gpa, io, client, db, zone_id, target_label, endpoint, .{}) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target_label, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectPageShieldDetailsForList(gpa, io, client, db, zone_id, target_label, endpoint, redacted);
    }
}

fn collectPageShieldDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, list_endpoint: PageShieldReadEndpoint, list_body: []const u8) !void {
    const detail_endpoint: ?PageShieldReadEndpoint = switch (list_endpoint) {
        .policies => .policy,
        .connections => .connection,
        .scripts => .script,
        .cookies => .cookie,
        else => null,
    };
    const endpoint = detail_endpoint orelse return;
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const redacted = collectPageShieldSnapshot(gpa, io, client, db, zone_id, target_label, endpoint, .{ .resource_id = row.id }) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectPageShieldSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) ![]u8 {
    const body = try client.getPageShieldEndpoint(io, gpa, zone_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.pageShieldReadPath(gpa, zone_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try pageShieldTarget(gpa, target_label, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectCustomPagesForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const resources = [_]CustomPageResource{ .pages, .assets };
        for (resources) |resource| {
            try collectCustomPageListForTarget(gpa, io, client, db, .account, row.id, row.id, resource);
        }
    }
}

fn collectCustomPagesForZone(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8) !void {
    const resources = [_]CustomPageResource{ .pages, .assets };
    for (resources) |resource| {
        try collectCustomPageListForTarget(gpa, io, client, db, .zone, zone_id, target_label, resource);
    }
}

fn collectCustomPageListForTarget(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: CustomPageScope, scope_id: []const u8, target_label: []const u8, resource: CustomPageResource) !void {
    const endpoint: CustomPageReadEndpoint = .list;
    const redacted = collectCustomPageSnapshot(gpa, io, client, db, scope, scope_id, target_label, resource, endpoint, .{}) catch |err| {
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(scope, resource), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(scope, resource), target_label, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectCustomPageDetailsForList(gpa, io, client, db, scope, scope_id, target_label, resource, redacted);
}

fn collectCustomPageDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: CustomPageScope, scope_id: []const u8, target_label: []const u8, resource: CustomPageResource, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const endpoint: CustomPageReadEndpoint = .details;
    for (rows.items) |row| {
        const redacted = collectCustomPageSnapshot(gpa, io, client, db, scope, scope_id, target_label, resource, endpoint, .{ .resource_id = row.id }) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(scope, resource), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(scope, resource), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectCustomPageSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: CustomPageScope, scope_id: []const u8, target_label: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) ![]u8 {
    const body = try client.getCustomPageEndpoint(io, gpa, scope, scope_id, resource, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.customPageReadPath(gpa, scope, scope_id, resource, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try customPageTarget(gpa, target_label, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(scope, resource),
        .target = target,
        .summary_label = endpoint.summary(scope, resource),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectAccessCustomPagesForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoint: AccessCustomPageReadEndpoint = .list;
    for (rows.items) |row| {
        const redacted = collectAccessCustomPageSnapshot(gpa, io, client, db, row.id, row.id, endpoint, null) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), row.id, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
        try collectAccessCustomPageDetailsForList(gpa, io, client, db, row.id, row.id, redacted);
    }
}

fn collectAccessCustomPageDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, target_label: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    const endpoint: AccessCustomPageReadEndpoint = .details;
    for (rows.items) |row| {
        const redacted = collectAccessCustomPageSnapshot(gpa, io, client, db, account_id, target_label, endpoint, row.id) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer gpa.free(redacted);
    }
}

fn collectAccessCustomPageSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, target_label: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) ![]u8 {
    const body = try client.getAccessCustomPageEndpoint(io, gpa, account_id, endpoint, page_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accessCustomPageReadPath(gpa, account_id, endpoint, page_id);
    defer gpa.free(endpoint_path);
    const target = try accessCustomPageTarget(gpa, target_label, endpoint, page_id);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectAccessForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]AccessReadEndpoint{
        .applications_list,
        .groups_list,
        .identity_providers_list,
        .service_tokens_list,
        .reusable_policies_list,
        .tags_list,
        .authenticator_device_aaguids,
        .idp_federation_grants_list,
        .saml_certificate_sets_list,
        .scim_update_logs,
        .keys,
        .authentication_logs,
        .mtls_certificates_list,
        .mtls_settings,
        .ca_list,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            try collectAccessReadForTarget(gpa, io, client, db, .account, row.id, row.id, endpoint, .{});
        }
    }
}

fn collectAccessForZone(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8) !void {
    const endpoints = [_]AccessReadEndpoint{
        .applications_list,
        .groups_list,
        .identity_providers_list,
        .service_tokens_list,
        .mtls_certificates_list,
        .mtls_settings,
        .ca_list,
    };
    for (endpoints) |endpoint| {
        try collectAccessReadForTarget(gpa, io, client, db, .zone, zone_id, target_label, endpoint, .{});
    }
}

fn collectAccessReadForTarget(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: AccessScope, scope_id: []const u8, target_label: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) anyerror!void {
    const redacted = collectAccessSnapshot(gpa, io, client, db, scope, scope_id, target_label, endpoint, args) catch |err| {
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(scope), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(scope), target_label, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectAccessDetailsForList(gpa, io, client, db, scope, scope_id, target_label, endpoint, redacted);
}

fn collectAccessDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: AccessScope, scope_id: []const u8, target_label: []const u8, list_endpoint: AccessReadEndpoint, list_body: []const u8) anyerror!void {
    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    switch (list_endpoint) {
        .applications_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .application_details, .{ .app_id = row.id });
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .application_policy_checks, .{ .app_id = row.id });
                try collectAccessApplicationPoliciesForApp(gpa, io, client, db, scope, scope_id, target_label, row.id);
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .ca_details, .{ .app_id = row.id });
            }
        },
        .groups_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .group_details, .{ .resource_id = row.id });
            }
        },
        .identity_providers_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .identity_provider_details, .{ .identity_provider_id = row.id });
                if (scope == .account) {
                    try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .identity_provider_scim_groups, .{ .identity_provider_id = row.id });
                    try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .identity_provider_scim_users, .{ .identity_provider_id = row.id });
                }
            }
        },
        .service_tokens_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .service_token_details, .{ .service_token_id = row.id });
            }
        },
        .reusable_policies_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .reusable_policy_details, .{ .policy_id = row.id });
            }
        },
        .tags_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .tag_details, .{ .tag_name = row.id });
            }
        },
        .mtls_certificates_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .mtls_certificate_details, .{ .certificate_id = row.id });
            }
        },
        .idp_federation_grants_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .idp_federation_grant_details, .{ .resource_id = row.id });
            }
        },
        .saml_certificate_sets_list => {
            for (rows.items) |row| {
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .saml_certificate_set_details, .{ .resource_id = row.id });
                try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .saml_certificate_pem, .{ .resource_id = row.id });
            }
        },
        else => {},
    }
}

fn collectAccessApplicationPoliciesForApp(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: AccessScope, scope_id: []const u8, target_label: []const u8, app_id: []const u8) anyerror!void {
    const list_endpoint: AccessReadEndpoint = .application_policies_list;
    const redacted = collectAccessSnapshot(gpa, io, client, db, scope, scope_id, target_label, list_endpoint, .{ .app_id = app_id }) catch |err| {
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, app_id });
        defer gpa.free(target);
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ list_endpoint.label(scope), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", list_endpoint.label(scope), target, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, redacted);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try collectAccessReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .application_policy_details, .{ .app_id = app_id, .policy_id = row.id });
    }
}

fn collectAccessSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: AccessScope, scope_id: []const u8, target_label: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) ![]u8 {
    const body = try client.getAccessEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.accessReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try accessTarget(gpa, target_label, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(scope),
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectTunnelsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]TunnelReadEndpoint{
        .cfd_tunnels,
        .all_tunnels,
        .warp_connectors,
        .tunnel_routes,
        .virtual_networks,
        .zero_trust_connectivity_settings,
        .hostname_routes,
        .subnets,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            try collectTunnelReadForAccount(gpa, io, client, db, row.id, endpoint, .{});
        }
    }
}

fn collectTunnelReadForAccount(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs) anyerror!void {
    const redacted = collectTunnelSnapshot(gpa, io, client, db, account_id, endpoint, args) catch |err| {
        const target = tunnelTarget(gpa, account_id, endpoint, args) catch try gpa.dupe(u8, account_id);
        defer gpa.free(target);
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectTunnelDetailsForList(gpa, io, client, db, account_id, endpoint, redacted);
}

fn collectTunnelDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_endpoint: TunnelReadEndpoint, list_body: []const u8) anyerror!void {
    const detail_endpoints: []const TunnelReadEndpoint = switch (list_endpoint) {
        .cfd_tunnels => &[_]TunnelReadEndpoint{ .cfd_tunnel, .cfd_tunnel_configurations, .cfd_tunnel_connections },
        .warp_connectors => &[_]TunnelReadEndpoint{ .warp_connector, .warp_connector_configurations, .warp_connector_connections },
        .tunnel_routes => &[_]TunnelReadEndpoint{.tunnel_route},
        .hostname_routes => &[_]TunnelReadEndpoint{.hostname_route},
        .subnets => &[_]TunnelReadEndpoint{.subnet},
        else => &[_]TunnelReadEndpoint{},
    };
    if (detail_endpoints.len == 0) return;

    var rows = if (list_endpoint == .subnets)
        try provider_cloudflare_models.parseResourceIdRowsMatchingString(gpa, list_body, "subnet_type", "warp")
    else
        try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        for (detail_endpoints) |endpoint| {
            const args: TunnelReadArgs = switch (endpoint) {
                .cfd_tunnel, .cfd_tunnel_configurations, .cfd_tunnel_connections => .{ .tunnel_id = row.id },
                .warp_connector, .warp_connector_configurations, .warp_connector_connections => .{ .tunnel_id = row.id },
                .tunnel_route => .{ .route_id = row.id },
                .hostname_route => .{ .hostname_route_id = row.id },
                .subnet => .{ .subnet_id = row.id },
                else => .{},
            };
            try collectTunnelReadForAccount(gpa, io, client, db, account_id, endpoint, args);
        }
    }
}

fn collectTunnelSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs) ![]u8 {
    const body = try client.getTunnelEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.tunnelReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try tunnelTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectZeroTrustForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]ZeroTrustReadEndpoint{
        .device_settings,
        .gateway_account,
        .gateway_configuration,
        .gateway_egress_cidr_pairs,
        .gateway_logging,
        .dns_destination_ips,
        .app_types,
        .categories,
        .operations,
        .locations,
        .proxy_endpoints,
        .rules,
        .tenant_rules,
        .ssh_settings,
        .applications_review_status,
        .certificates,
        .pacfiles,
        .lists,
        .organization,
        .organization_doh,
        .users,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            try collectZeroTrustReadForAccount(gpa, io, client, db, row.id, endpoint, .{});
        }
    }
}

fn collectZeroTrustReadForAccount(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs) anyerror!void {
    const redacted = collectZeroTrustSnapshot(gpa, io, client, db, account_id, endpoint, args) catch |err| {
        const target = zeroTrustTarget(gpa, account_id, endpoint, args) catch try gpa.dupe(u8, account_id);
        defer gpa.free(target);
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectZeroTrustDetailsForList(gpa, io, client, db, account_id, endpoint, redacted);
}

fn collectZeroTrustDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, list_endpoint: ZeroTrustReadEndpoint, list_body: []const u8) anyerror!void {
    const detail_endpoints: []const ZeroTrustReadEndpoint = switch (list_endpoint) {
        .operations => &[_]ZeroTrustReadEndpoint{.operation},
        .locations => &[_]ZeroTrustReadEndpoint{.location},
        .proxy_endpoints => &[_]ZeroTrustReadEndpoint{.proxy_endpoint},
        .rules => &[_]ZeroTrustReadEndpoint{.rule},
        .certificates => &[_]ZeroTrustReadEndpoint{.certificate},
        .pacfiles => &[_]ZeroTrustReadEndpoint{.pacfile},
        .lists => &[_]ZeroTrustReadEndpoint{ .list, .list_items },
        .users => &[_]ZeroTrustReadEndpoint{ .user, .user_active_sessions, .user_failed_logins, .user_last_seen_identity },
        else => &[_]ZeroTrustReadEndpoint{},
    };
    if (detail_endpoints.len == 0) return;

    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        for (detail_endpoints) |endpoint| {
            const args: ZeroTrustReadArgs = switch (endpoint) {
                .operation => .{ .operation_id = row.id },
                .location => .{ .location_id = row.id },
                .proxy_endpoint => .{ .proxy_endpoint_id = row.id },
                .rule => .{ .rule_id = row.id },
                .certificate => .{ .certificate_id = row.id },
                .pacfile => .{ .pacfile_id = row.id },
                .list, .list_items => .{ .list_id = row.id },
                .user, .user_active_sessions, .user_failed_logins, .user_last_seen_identity => .{ .user_id = row.id },
                else => .{},
            };
            try collectZeroTrustReadForAccount(gpa, io, client, db, account_id, endpoint, args);
        }
    }
}

fn collectZeroTrustSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs) ![]u8 {
    const body = try client.getZeroTrustEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.zeroTrustReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try zeroTrustTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectSecurityCenterForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]SecurityCenterReadEndpoint{
        .issue_types,
        .insights,
        .class_counts,
        .severity_counts,
        .type_counts,
        .audit_log,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            try collectSecurityCenterReadForTarget(gpa, io, client, db, .account, row.id, row.id, endpoint, .{});
        }
    }
}

fn collectSecurityCenterForZone(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8) !void {
    const endpoints = [_]SecurityCenterReadEndpoint{
        .insights,
        .class_counts,
        .severity_counts,
        .type_counts,
        .audit_log,
    };
    for (endpoints) |endpoint| {
        try collectSecurityCenterReadForTarget(gpa, io, client, db, .zone, zone_id, target_label, endpoint, .{});
    }
}

fn collectSecurityCenterReadForTarget(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: SecurityCenterScope, scope_id: []const u8, target_label: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs) anyerror!void {
    const redacted = collectSecurityCenterSnapshot(gpa, io, client, db, scope, scope_id, target_label, endpoint, args) catch |err| {
        const target = securityCenterTarget(gpa, target_label, endpoint, args) catch try gpa.dupe(u8, target_label);
        defer gpa.free(target);
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(scope), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(scope), target, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
    try collectSecurityCenterDetailsForList(gpa, io, client, db, scope, scope_id, target_label, endpoint, redacted);
}

fn collectSecurityCenterDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: SecurityCenterScope, scope_id: []const u8, target_label: []const u8, list_endpoint: SecurityCenterReadEndpoint, list_body: []const u8) anyerror!void {
    if (list_endpoint != .insights) return;
    var rows = try provider_cloudflare_models.parseResourceIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        if (scope == .account) {
            try collectSecurityCenterReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .insight_context, .{ .issue_id = row.id });
        }
        try collectSecurityCenterReadForTarget(gpa, io, client, db, scope, scope_id, target_label, .insight_audit_log, .{ .issue_id = row.id });
    }
}

fn collectSecurityCenterSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: SecurityCenterScope, scope_id: []const u8, target_label: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs) ![]u8 {
    const body = try client.getSecurityCenterEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.securityCenterReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try securityCenterTarget(gpa, target_label, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(scope),
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectAuditLogsForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const now_seconds = core_time.currentEpochSeconds() catch 0;
    const day_seconds: u64 = 24 * 60 * 60;
    const since_seconds = if (now_seconds > day_seconds) now_seconds - day_seconds else 0;
    var since_buf: [20]u8 = undefined;
    var before_buf: [20]u8 = undefined;
    const since = try core_time.formatUtcSecond(&since_buf, since_seconds);
    const before = try core_time.formatUtcSecond(&before_buf, now_seconds);
    for (rows.items) |row| {
        try collectAuditLogRead(gpa, io, client, db, .account_v1, .{ .account_id = row.id });
        try collectAuditLogRead(gpa, io, client, db, .account_v2, .{ .account_id = row.id, .since = since, .before = before });

        const org_body = client.getAccountEndpoint(io, gpa, row.id, .organizations) catch continue;
        defer org_body.deinit(gpa);
        var org_rows = try provider_cloudflare_models.parseResourceIdRows(gpa, org_body.body);
        defer org_rows.deinit(gpa);
        for (org_rows.items) |org_row| {
            try collectAuditLogRead(gpa, io, client, db, .organization_v2, .{ .organization_id = org_row.id, .since = since, .before = before });
        }
    }
    try collectAuditLogRead(gpa, io, client, db, .user_v1, .{});
}

fn collectAuditLogRead(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs) anyerror!void {
    const redacted = collectAuditLogSnapshot(gpa, io, client, db, endpoint, args) catch |err| {
        const target = auditLogTarget(gpa, endpoint, args) catch try gpa.dupe(u8, endpoint.commandName());
        defer gpa.free(target);
        const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
        defer gpa.free(error_summary);
        _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
        return;
    };
    defer gpa.free(redacted);
}

fn collectAuditLogSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs) ![]u8 {
    const body = try client.getAuditLogEndpoint(io, gpa, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.auditLogReadPath(gpa, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try auditLogTarget(gpa, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectRulesetSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, scope: RulesetScope, scope_id: []const u8, target_label: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) ![]u8 {
    const body = try client.getRulesetEndpoint(io, gpa, scope, scope_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.rulesetReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try rulesetTarget(gpa, target_label, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(scope),
        .target = target,
        .summary_label = endpoint.summary(scope),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectResourceTaggingForAccounts(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]ResourceTaggingAccountReadEndpoint{ .keys, .resources };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            const redacted = collectResourceTaggingAccountSnapshot(gpa, io, client, db, row.id, endpoint, .{}) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint.label(), row.id, "error", error_summary, null, null);
                continue;
            };
            defer gpa.free(redacted);
        }
    }
}

fn collectResourceTaggingAccountSnapshot(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) ![]u8 {
    const body = try client.getResourceTaggingAccountEndpoint(io, gpa, account_id, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_cloudflare.resourceTaggingAccountReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(endpoint_path);
    const target = try resourceTaggingAccountTarget(gpa, account_id, endpoint, args);
    defer gpa.free(target);
    return try collector_capture.storeResponse(gpa, db, .{
        .provider = "cloudflare",
        .kind = endpoint.label(),
        .target = target,
        .summary_label = endpoint.summary(),
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
}

fn collectZoneHealthCheckDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
        defer gpa.free(target);
        const endpoint: ZoneHealthCheckReadEndpoint = .details;
        const body = client.getZoneHealthCheck(io, gpa, zone_id, endpoint, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.zoneHealthCheckReadPath(gpa, zone_id, endpoint, row.id);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = endpoint.label(),
            .target = target,
            .summary_label = endpoint.summary(),
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectSmartShieldHealthCheckDetailsForList(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, zone_id: []const u8, target_label: []const u8, list_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, list_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ target_label, row.id });
        defer gpa.free(target);
        const endpoint: SmartShieldHealthCheckReadEndpoint = .details;
        const body = client.getSmartShieldHealthCheck(io, gpa, zone_id, endpoint, row.id) catch |err| {
            const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint.label(), @errorName(err) });
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", endpoint.label(), target, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.smartShieldHealthCheckReadPath(gpa, zone_id, endpoint, row.id);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = endpoint.label(),
            .target = target,
            .summary_label = endpoint.summary(),
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectAccountUserGroupMembersForGroups(gpa: Allocator, io: Io, client: provider_cloudflare.Client, db: *Db, account_id: []const u8, user_groups_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseIdRows(gpa, user_groups_body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        const body = client.getAccountUserGroupMembers(io, gpa, account_id, row.id) catch |err| {
            const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
            defer gpa.free(target);
            const error_summary = try std.fmt.allocPrint(gpa, "account-user-group-members: {s}", .{@errorName(err)});
            defer gpa.free(error_summary);
            _ = try db.insertSnapshot("cloudflare", "account-user-group-members", target, "error", error_summary, null, null);
            continue;
        };
        defer body.deinit(gpa);
        const endpoint_path = try provider_cloudflare.accountUserGroupMembersPath(gpa, account_id, row.id);
        defer gpa.free(endpoint_path);
        const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, row.id });
        defer gpa.free(target);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "cloudflare",
            .kind = "account-user-group-members",
            .target = target,
            .summary_label = "account-user-group-members",
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        defer gpa.free(redacted);
    }
}

fn collectAccountTokenEndpointsForAccounts(gpa: Allocator, io: Io, auth: Auth, client: provider_cloudflare.Client, db: *Db, accounts_body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, accounts_body);
    defer rows.deinit(gpa);
    const endpoints = [_]AccountTokenEndpoint{
        .list,
        .permission_groups,
    };
    for (rows.items) |row| {
        for (endpoints) |endpoint| {
            const endpoint_label = endpoint.label();
            const body = client.getAccountTokenEndpoint(io, gpa, row.id, endpoint) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.accountTokenEndpointPath(gpa, row.id, endpoint);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = row.id,
                .summary_label = endpoint_label,
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
        if (auth.hasApiToken()) {
            const endpoint: AccountTokenEndpoint = .verify;
            const endpoint_label = endpoint.label();
            const body = client.getAccountTokenEndpoint(io, gpa, row.id, endpoint) catch |err| {
                const error_summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ endpoint_label, @errorName(err) });
                defer gpa.free(error_summary);
                _ = try db.insertSnapshot("cloudflare", endpoint_label, row.id, "error", error_summary, null, null);
                continue;
            };
            defer body.deinit(gpa);
            const endpoint_path = try provider_cloudflare.accountTokenEndpointPath(gpa, row.id, endpoint);
            defer gpa.free(endpoint_path);
            const redacted = try collector_capture.storeResponse(gpa, db, .{
                .provider = "cloudflare",
                .kind = endpoint_label,
                .target = row.id,
                .summary_label = endpoint_label,
                .endpoint = endpoint_path,
                .status = body.status,
                .body = body.body,
            });
            defer gpa.free(redacted);
        }
    }
}

pub fn diagnoseDomain(io: Io, gpa: Allocator, db: *Db, domain: []const u8) !void {
    const doh_url = try std.fmt.allocPrint(gpa, "https://cloudflare-dns.com/dns-query?name={s}&type=A", .{domain});
    defer gpa.free(doh_url);
    const tcp_22 = try std.fmt.allocPrint(gpa, ":</dev/tcp/{s}/22", .{domain});
    defer gpa.free(tcp_22);
    const tcp_80 = try std.fmt.allocPrint(gpa, ":</dev/tcp/{s}/80", .{domain});
    defer gpa.free(tcp_80);
    const tcp_443 = try std.fmt.allocPrint(gpa, ":</dev/tcp/{s}/443", .{domain});
    defer gpa.free(tcp_443);
    const https_url = try std.fmt.allocPrint(gpa, "https://{s}/", .{domain});
    defer gpa.free(https_url);
    const checks = [_]struct { kind: []const u8, argv: []const []const u8 }{
        .{ .kind = "egress-ip", .argv = &.{ "curl", "-sS", "--max-time", "8", "https://ipinfo.io/ip" } },
        .{ .kind = "resolver", .argv = &.{ "getent", "ahosts", domain } },
        .{ .kind = "doh-cloudflare", .argv = &.{ "curl", "-sS", "--max-time", "8", "-H", "Accept: application/dns-json", doh_url } },
        .{ .kind = "tcp-22", .argv = &.{ "timeout", "5", "bash", "-lc", tcp_22 } },
        .{ .kind = "tcp-80", .argv = &.{ "timeout", "5", "bash", "-lc", tcp_80 } },
        .{ .kind = "tcp-443", .argv = &.{ "timeout", "5", "bash", "-lc", tcp_443 } },
        .{ .kind = "https-head", .argv = &.{ "curl", "-sS", "-I", "--max-time", "8", https_url } },
    };
    for (checks) |check| {
        const result = runCommand(gpa, io, check.argv, max_command_bytes) catch |err| {
            const summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ check.kind, @errorName(err) });
            defer gpa.free(summary);
            _ = try db.insertSnapshot("cloudflare", check.kind, domain, "error", summary, null, null);
            continue;
        };
        defer result.deinit(gpa);
        const redacted = try core_redact.secrets(gpa, result.stdout);
        defer gpa.free(redacted);
        _ = try db.insertSnapshot("cloudflare", check.kind, domain, if (result.ok()) "ok" else "error", firstLine(redacted), null, redacted);
        std.debug.print("{s}: {s}\n", .{ check.kind, if (firstLine(redacted).len > 0) firstLine(redacted) else result.statusText() });
    }
}

pub fn persistAccountRows(gpa: Allocator, db: *Db, body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseAccountRows(gpa, body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertCloudflareAccount(row.id, row.name, row.typ, row.status, row.raw_json);
    }
}

pub fn persistZoneRows(gpa: Allocator, db: *Db, body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseZoneRows(gpa, body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertCloudflareZone(row.id, row.name, row.account_id, row.status, row.paused, row.typ, row.name_servers, row.raw_json);
    }
}

pub fn persistDnsRecordRows(gpa: Allocator, db: *Db, zone_id: []const u8, body: []const u8) !void {
    var rows = try provider_cloudflare_models.parseDnsRecordRows(gpa, zone_id, body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertDnsRecord(row.id, row.zone_id, row.name, row.typ, row.content, row.ttl, row.proxied, row.raw_json);
    }
}

fn clientFromAuth(auth: Auth) !provider_cloudflare.Client {
    if (!auth.isConfigured()) return error.MissingCloudflareAuth;
    return provider_cloudflare.Client.init(auth);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn firstLine(value: []const u8) []const u8 {
    const clean = trim(value);
    if (std.mem.indexOfScalar(u8, clean, '\n')) |idx| return clean[0..idx];
    return clean;
}

fn settingTarget(gpa: Allocator, domain: []const u8, setting_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domain, setting_id });
}

fn rulesetTarget(gpa: Allocator, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) ![]u8 {
    if (endpoint.requiresRulesetId()) {
        const ruleset_id = args.ruleset_id orelse return try gpa.dupe(u8, scope_id);
        if (endpoint.requiresVersion()) {
            const version = args.version orelse return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_id, ruleset_id });
            if (endpoint.requiresRuleTag()) {
                const rule_tag = args.rule_tag orelse return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ scope_id, ruleset_id, version });
                return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/{s}", .{ scope_id, ruleset_id, version, rule_tag });
            }
            return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ scope_id, ruleset_id, version });
        }
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_id, ruleset_id });
    }
    if (endpoint.requiresPhase()) {
        const phase = args.phase orelse return try gpa.dupe(u8, scope_id);
        if (endpoint.requiresVersion()) {
            const version = args.version orelse return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_id, phase });
            return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ scope_id, phase, version });
        }
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_id, phase });
    }
    return try gpa.dupe(u8, scope_id);
}

fn cloudforceOneRuleTarget(gpa: Allocator, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) ![]u8 {
    if (endpoint.requiresRuleId()) {
        const rule_id = args.rule_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, rule_id });
    }
    if (endpoint.requiresQuery()) {
        const query = args.query orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, query });
    }
    return try gpa.dupe(u8, account_id);
}

fn ipAccessRuleTarget(gpa: Allocator, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) ![]u8 {
    const scope_label = if (scope.usesScopeId()) scope_id orelse scope.idLabel() else scope.idLabel();
    if (endpoint.requiresRuleId()) {
        const rule_id = args.rule_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_label, rule_id });
    }
    return try gpa.dupe(u8, scope_label);
}

fn zoneLegacyRuleTarget(gpa: Allocator, zone_label: []const u8, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) ![]u8 {
    if (endpoint.requiresRuleId()) {
        const id = rule_id orelse return try gpa.dupe(u8, zone_label);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_label, id });
    }
    return try gpa.dupe(u8, zone_label);
}

fn pageShieldTarget(gpa: Allocator, zone_label: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) ![]u8 {
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return try gpa.dupe(u8, zone_label);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_label, resource_id });
    }
    return try gpa.dupe(u8, zone_label);
}

fn customPageTarget(gpa: Allocator, scope_label: []const u8, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) ![]u8 {
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ scope_label, resource_id });
    }
    return try gpa.dupe(u8, scope_label);
}

fn accessCustomPageTarget(gpa: Allocator, account_label: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) ![]u8 {
    if (endpoint.requiresPageId()) {
        const id = page_id orelse return try gpa.dupe(u8, account_label);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_label, id });
    }
    return try gpa.dupe(u8, account_label);
}

fn accessTarget(gpa: Allocator, scope_label: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) ![]u8 {
    if (endpoint.requiresAppId()) {
        const app_id = args.app_id orelse return try gpa.dupe(u8, scope_label);
        if (endpoint.requiresPolicyId()) {
            const policy_id = args.policy_id orelse return try std.fmt.allocPrint(gpa, "{s}/app:{s}", .{ scope_label, app_id });
            return try std.fmt.allocPrint(gpa, "{s}/app:{s}/policy:{s}", .{ scope_label, app_id, policy_id });
        }
        return try std.fmt.allocPrint(gpa, "{s}/app:{s}", .{ scope_label, app_id });
    }
    if (endpoint.requiresPolicyId()) {
        const policy_id = args.policy_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/policy:{s}", .{ scope_label, policy_id });
    }
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/resource:{s}", .{ scope_label, resource_id });
    }
    if (endpoint.requiresIdentityProviderId()) {
        const identity_provider_id = args.identity_provider_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/idp:{s}", .{ scope_label, identity_provider_id });
    }
    if (endpoint.requiresServiceTokenId()) {
        const service_token_id = args.service_token_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/service-token:{s}", .{ scope_label, service_token_id });
    }
    if (endpoint.requiresTagName()) {
        const tag_name = args.tag_name orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/tag:{s}", .{ scope_label, tag_name });
    }
    if (endpoint.requiresPolicyTestId()) {
        const policy_test_id = args.policy_test_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/policy-test:{s}", .{ scope_label, policy_test_id });
    }
    if (endpoint.requiresCertificateId()) {
        const certificate_id = args.certificate_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/certificate:{s}", .{ scope_label, certificate_id });
    }
    return try gpa.dupe(u8, scope_label);
}

fn tunnelTarget(gpa: Allocator, account_id: []const u8, endpoint: TunnelReadEndpoint, args: TunnelReadArgs) ![]u8 {
    if (endpoint.requiresConnectorId()) {
        const tunnel_id = args.tunnel_id orelse return try gpa.dupe(u8, account_id);
        const connector_id = args.connector_id orelse return try std.fmt.allocPrint(gpa, "{s}/tunnel:{s}", .{ account_id, tunnel_id });
        return try std.fmt.allocPrint(gpa, "{s}/tunnel:{s}/connector:{s}", .{ account_id, tunnel_id, connector_id });
    }
    if (endpoint.requiresTunnelId()) {
        const tunnel_id = args.tunnel_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/tunnel:{s}", .{ account_id, tunnel_id });
    }
    if (endpoint.requiresRouteId()) {
        const route_id = args.route_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/route:{s}", .{ account_id, route_id });
    }
    if (endpoint.requiresIp()) {
        const ip = args.ip orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/ip:{s}", .{ account_id, ip });
    }
    if (endpoint.requiresHostnameRouteId()) {
        const route_id = args.hostname_route_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/hostname-route:{s}", .{ account_id, route_id });
    }
    if (endpoint.requiresSubnetId()) {
        const subnet_id = args.subnet_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/subnet:{s}", .{ account_id, subnet_id });
    }
    return try gpa.dupe(u8, account_id);
}

fn zeroTrustTarget(gpa: Allocator, account_id: []const u8, endpoint: ZeroTrustReadEndpoint, args: ZeroTrustReadArgs) ![]u8 {
    if (endpoint.requiresOperationId()) {
        const operation_id = args.operation_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/operation:{s}", .{ account_id, operation_id });
    }
    if (endpoint.requiresLocationId()) {
        const location_id = args.location_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/location:{s}", .{ account_id, location_id });
    }
    if (endpoint.requiresProxyEndpointId()) {
        const proxy_endpoint_id = args.proxy_endpoint_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/proxy-endpoint:{s}", .{ account_id, proxy_endpoint_id });
    }
    if (endpoint.requiresRuleId()) {
        const rule_id = args.rule_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/rule:{s}", .{ account_id, rule_id });
    }
    if (endpoint.requiresPacfileId()) {
        const pacfile_id = args.pacfile_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/pacfile:{s}", .{ account_id, pacfile_id });
    }
    if (endpoint.requiresCertificateId()) {
        const certificate_id = args.certificate_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/certificate:{s}", .{ account_id, certificate_id });
    }
    if (endpoint.requiresListId()) {
        const list_id = args.list_id orelse return try gpa.dupe(u8, account_id);
        return try std.fmt.allocPrint(gpa, "{s}/list:{s}", .{ account_id, list_id });
    }
    if (endpoint.requiresUserId()) {
        const user_id = args.user_id orelse return try gpa.dupe(u8, account_id);
        if (endpoint.requiresNonce()) {
            const nonce = args.nonce orelse return try std.fmt.allocPrint(gpa, "{s}/user:{s}", .{ account_id, user_id });
            return try std.fmt.allocPrint(gpa, "{s}/user:{s}/session:{s}", .{ account_id, user_id, nonce });
        }
        return try std.fmt.allocPrint(gpa, "{s}/user:{s}", .{ account_id, user_id });
    }
    return try gpa.dupe(u8, account_id);
}

fn securityCenterTarget(gpa: Allocator, scope_label: []const u8, endpoint: SecurityCenterReadEndpoint, args: SecurityCenterReadArgs) ![]u8 {
    if (endpoint.requiresIssueId()) {
        const issue_id = args.issue_id orelse return try gpa.dupe(u8, scope_label);
        return try std.fmt.allocPrint(gpa, "{s}/issue:{s}", .{ scope_label, issue_id });
    }
    return try gpa.dupe(u8, scope_label);
}

fn auditLogTarget(gpa: Allocator, endpoint: AuditLogReadEndpoint, args: AuditLogReadArgs) ![]u8 {
    return switch (endpoint) {
        .account_v1, .account_v2 => if (args.account_id) |account_id| try gpa.dupe(u8, account_id) else try gpa.dupe(u8, endpoint.commandName()),
        .organization_v2 => if (args.organization_id) |organization_id| try gpa.dupe(u8, organization_id) else try gpa.dupe(u8, endpoint.commandName()),
        .user_v1 => try gpa.dupe(u8, "user"),
    };
}

fn resourceTaggingAccountTarget(gpa: Allocator, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) ![]u8 {
    return switch (endpoint) {
        .tags => if (args.resource_type) |resource_type|
            if (args.resource_id) |resource_id|
                try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ account_id, resource_type, resource_id })
            else
                try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, resource_type })
        else
            try gpa.dupe(u8, account_id),
        .keys, .resources => try gpa.dupe(u8, account_id),
        .values => if (args.tag_key) |tag_key| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ account_id, tag_key }) else try gpa.dupe(u8, account_id),
    };
}

fn resourceTaggingZoneTarget(gpa: Allocator, zone_id: []const u8, args: ResourceTaggingZoneReadArgs) ![]u8 {
    if (args.resource_type) |resource_type| {
        if (args.resource_id) |resource_id| return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ zone_id, resource_type, resource_id });
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zone_id, resource_type });
    }
    return try gpa.dupe(u8, zone_id);
}

test "persists Cloudflare account, zone, and DNS rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudflare.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistAccountRows(allocator, &db,
        \\{"result":[{"id":"acct-1","name":"Main","type":"standard","status":"active"}]}
    );
    try persistZoneRows(allocator, &db,
        \\{"result":[{"id":"zone-1","name":"plosca.ru","account":{"id":"acct-1"},"status":"active","paused":false,"type":"full","name_servers":["a.ns.cloudflare.com"]}]}
    );
    try persistDnsRecordRows(allocator, &db, "zone-1",
        \\{"result":[{"id":"dns-1","name":"plosca.ru","type":"A","content":"76.13.130.170","ttl":1,"proxied":true}]}
    );

    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_accounts"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_zones"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_dns_records"));

    const stmt = try db.prepare("SELECT name, account_id, status, paused FROM cloudflare_zones WHERE id = 'zone-1'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(stmt));
    try std.testing.expectEqualStrings("plosca.ru", columnText(stmt, 0) orelse "");
    try std.testing.expectEqualStrings("acct-1", columnText(stmt, 1) orelse "");
    try std.testing.expectEqualStrings("active", columnText(stmt, 2) orelse "");
    try std.testing.expectEqual(@as(c_int, 0), sqlite.sqlite3_column_int(stmt, 3));
}

test "missing Cloudflare credentials records zone setting snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudflare-setting.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectZoneSetting(std.testing.io, allocator, .{}, &db, "plosca.ru", "ssl", true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Cloudflare credentials missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}
