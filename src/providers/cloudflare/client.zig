const std = @import("std");
const net_http = @import("net_http");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const DryRunPlan = struct {
    group: []const u8,
    operation: []const u8,
    operation_id: []const u8,
    summary: []const u8,
    method: []const u8,
    path: []const u8,
    request_body_schema: ?[]const u8,
};

pub const base_url = "https://api.cloudflare.com/client/v4";
pub const accounts_path = "/accounts";
pub const zones_path = "/zones";
pub const ips_path = "/ips";
pub const user_path = "/user";
pub const user_tenants_path = "/user/tenants";
pub const memberships_path = "/memberships";
pub const user_tokens_path = "/user/tokens";
pub const user_tokens_verify_path = "/user/tokens/verify";
pub const user_token_permission_groups_path = "/user/tokens/permission_groups";
pub const cloudforce_one_rules_base_path = "/cloudforce-one/rules";
pub const firewall_access_rules_path = "/firewall/access_rules/rules";

pub const Auth = struct {
    token: ?[]const u8 = null,
    email: ?[]const u8 = null,
    key: ?[]const u8 = null,

    pub fn isConfigured(self: Auth) bool {
        return self.token != null or (self.email != null and self.key != null);
    }

    pub fn hasApiToken(self: Auth) bool {
        const token = self.token orelse return false;
        return token.len != 0;
    }
};

pub const Client = struct {
    auth: Auth,
    base_url_override: []const u8 = base_url,

    pub fn init(auth: Auth) Client {
        return .{ .auth = auth };
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
        return try self.getWithHeaders(io, gpa, url, &.{});
    }

    pub fn getWithHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        const common = jsonHeaders();
        if (self.auth.token) |token| {
            if (token.len == 0) return error.MissingCloudflareAuth;
            const auth_header = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
            defer gpa.free(auth_header);
            const privileged = [_]std.http.Header{.{ .name = "Authorization", .value = auth_header }};
            const headers = try mergeHeaders(gpa, &common, route_headers);
            defer gpa.free(headers);
            return try net_http.get(gpa, io, url, headers, &privileged);
        }
        const email = self.auth.email orelse return error.MissingCloudflareAuth;
        const key = self.auth.key orelse return error.MissingCloudflareAuth;
        if (email.len == 0 or key.len == 0) return error.MissingCloudflareAuth;
        const legacy = [_]std.http.Header{
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "X-Auth-Email", .value = email },
            .{ .name = "X-Auth-Key", .value = key },
        };
        const headers = try mergeHeaders(gpa, &legacy, route_headers);
        defer gpa.free(headers);
        return try net_http.get(gpa, io, url, headers, &.{});
    }

    pub fn getPublic(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        return try self.getPublicWithHeaders(io, gpa, url, &.{});
    }

    pub fn getPublicWithHeaders(self: Client, io: Io, gpa: Allocator, url: []const u8, route_headers: []const std.http.Header) !net_http.Response {
        _ = self;
        const common = jsonHeaders();
        const headers = try mergeHeaders(gpa, &common, route_headers);
        defer gpa.free(headers);
        return try net_http.get(gpa, io, url, headers, &.{});
    }
};

fn jsonHeaders() [2]std.http.Header {
    return .{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    };
}

fn mergeHeaders(gpa: Allocator, base: []const std.http.Header, extra: []const std.http.Header) ![]std.http.Header {
    const merged = try gpa.alloc(std.http.Header, base.len + extra.len);
    @memcpy(merged[0..base.len], base);
    @memcpy(merged[base.len..], extra);
    return merged;
}

pub const AccountEndpoint = enum {
    details,
    profile,
    organizations,

    pub fn label(self: AccountEndpoint) []const u8 {
        return switch (self) {
            .details => "account-detail",
            .profile => "account-profile",
            .organizations => "account-organizations",
        };
    }

    pub fn suffix(self: AccountEndpoint) ?[]const u8 {
        return switch (self) {
            .details => null,
            .profile => "profile",
            .organizations => "organizations",
        };
    }

    pub fn parse(value: []const u8) ?AccountEndpoint {
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .details;
        if (std.mem.eql(u8, value, "profile")) return .profile;
        if (std.mem.eql(u8, value, "organizations") or std.mem.eql(u8, value, "orgs")) return .organizations;
        return null;
    }

    pub fn commandName(self: AccountEndpoint) []const u8 {
        return switch (self) {
            .details => "show",
            .profile => "profile",
            .organizations => "organizations",
        };
    }
};

pub const AccountMutationEndpoint = enum {
    create,
    delete_account,
    update,
    batch_move,
    move,
    update_profile,

    pub fn parse(value: []const u8) ?AccountMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_account;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "batch-move") or std.mem.eql(u8, value, "move-batch")) return .batch_move;
        if (std.mem.eql(u8, value, "move")) return .move;
        if (std.mem.eql(u8, value, "profile") or std.mem.eql(u8, value, "update-profile")) return .update_profile;
        return null;
    }

    pub fn commandName(self: AccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .delete_account => "delete",
            .update => "update",
            .batch_move => "batch-move",
            .move => "move",
            .update_profile => "profile",
        };
    }

    pub fn group(self: AccountMutationEndpoint) []const u8 {
        _ = self;
        return "Accounts";
    }

    pub fn method(self: AccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .batch_move, .move => "POST",
            .delete_account => "DELETE",
            .update, .update_profile => "PUT",
        };
    }

    pub fn operationId(self: AccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "account-creation",
            .delete_account => "account-deletion",
            .update => "accounts-update-account",
            .batch_move => "Accounts_batchMoveAccounts",
            .move => "Accounts_moveAccounts",
            .update_profile => "Accounts_modifyAccountProfile",
        };
    }

    pub fn summary(self: AccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create an account",
            .delete_account => "Delete a specific account",
            .update => "Update Account",
            .batch_move => "Batch move accounts",
            .move => "Move account",
            .update_profile => "Modify account profile",
        };
    }

    pub fn requestBodySchemaRef(self: AccountMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/iam_create-account",
            .update => "#/components/schemas/iam_components-schemas-account",
            .batch_move => "inline:{account_ids:[]string,destination_organization_id:string}",
            .move => "inline:{destination_organization_id:string}",
            .update_profile => "#/components/schemas/organizations-api_Profile",
            .delete_account => null,
        };
    }

    pub fn requiresAccountId(self: AccountMutationEndpoint) bool {
        return switch (self) {
            .create, .batch_move => false,
            .delete_account, .update, .move, .update_profile => true,
        };
    }
};

pub const AccountMutationArgs = struct {
    account_id: ?[]const u8 = null,
};

pub const AccountCollection = enum {
    members,
    roles,

    pub fn slug(self: AccountCollection) []const u8 {
        return switch (self) {
            .members => "members",
            .roles => "roles",
        };
    }

    pub fn listKind(self: AccountCollection) []const u8 {
        return switch (self) {
            .members => "account-members",
            .roles => "account-roles",
        };
    }

    pub fn detailKind(self: AccountCollection) []const u8 {
        return switch (self) {
            .members => "account-member",
            .roles => "account-role",
        };
    }

    pub fn listCommandName(self: AccountCollection) []const u8 {
        return switch (self) {
            .members => "members",
            .roles => "roles",
        };
    }

    pub fn detailCommandName(self: AccountCollection) []const u8 {
        return switch (self) {
            .members => "member",
            .roles => "role",
        };
    }

    pub fn parseListCommand(value: []const u8) ?AccountCollection {
        if (std.mem.eql(u8, value, "members")) return .members;
        if (std.mem.eql(u8, value, "roles")) return .roles;
        return null;
    }

    pub fn parseDetailCommand(value: []const u8) ?AccountCollection {
        if (std.mem.eql(u8, value, "member")) return .members;
        if (std.mem.eql(u8, value, "role")) return .roles;
        return null;
    }
};

pub const AccountMemberMutationEndpoint = enum {
    create,
    update,
    delete_member,

    pub fn parse(value: []const u8) ?AccountMemberMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add") or std.mem.eql(u8, value, "invite")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "replace")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_member;
        return null;
    }

    pub fn commandName(self: AccountMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_member => "delete",
        };
    }

    pub fn group(self: AccountMemberMutationEndpoint) []const u8 {
        _ = self;
        return "Account Members";
    }

    pub fn method(self: AccountMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .delete_member => "DELETE",
        };
    }

    pub fn operationId(self: AccountMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "account-members-add-member",
            .update => "account-members-update-member",
            .delete_member => "account-members-remove-member",
        };
    }

    pub fn summary(self: AccountMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Add Member",
            .update => "Update Member",
            .delete_member => "Remove Member",
        };
    }

    pub fn requestBodySchemaRef(self: AccountMemberMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "oneOf:#/components/schemas/iam_create-member-with-roles|#/components/schemas/iam_create-member-with-policies",
            .update => "oneOf:#/components/schemas/iam_update-member-with-roles|#/components/schemas/iam_update-member-with-policies",
            .delete_member => null,
        };
    }

    pub fn requiresMemberId(self: AccountMemberMutationEndpoint) bool {
        return self != .create;
    }
};

pub const AccountMemberMutationArgs = struct {
    account_id: []const u8,
    member_id: ?[]const u8 = null,
};

pub const AccountIamCollection = enum {
    permission_groups,
    resource_groups,
    user_groups,

    pub fn slug(self: AccountIamCollection) []const u8 {
        return switch (self) {
            .permission_groups => "permission_groups",
            .resource_groups => "resource_groups",
            .user_groups => "user_groups",
        };
    }

    pub fn listKind(self: AccountIamCollection) []const u8 {
        return switch (self) {
            .permission_groups => "account-permission-groups",
            .resource_groups => "account-resource-groups",
            .user_groups => "account-user-groups",
        };
    }

    pub fn detailKind(self: AccountIamCollection) []const u8 {
        return switch (self) {
            .permission_groups => "account-permission-group",
            .resource_groups => "account-resource-group",
            .user_groups => "account-user-group",
        };
    }

    pub fn listCommandName(self: AccountIamCollection) []const u8 {
        return switch (self) {
            .permission_groups => "permission-groups",
            .resource_groups => "resource-groups",
            .user_groups => "user-groups",
        };
    }

    pub fn detailCommandName(self: AccountIamCollection) []const u8 {
        return switch (self) {
            .permission_groups => "permission-group",
            .resource_groups => "resource-group",
            .user_groups => "user-group",
        };
    }

    pub fn parseListCommand(value: []const u8) ?AccountIamCollection {
        if (std.mem.eql(u8, value, "permission-groups")) return .permission_groups;
        if (std.mem.eql(u8, value, "resource-groups")) return .resource_groups;
        if (std.mem.eql(u8, value, "user-groups")) return .user_groups;
        return null;
    }

    pub fn parseDetailCommand(value: []const u8) ?AccountIamCollection {
        if (std.mem.eql(u8, value, "permission-group")) return .permission_groups;
        if (std.mem.eql(u8, value, "resource-group")) return .resource_groups;
        if (std.mem.eql(u8, value, "user-group")) return .user_groups;
        return null;
    }

    pub fn supportsGroupMutation(self: AccountIamCollection) bool {
        return switch (self) {
            .resource_groups, .user_groups => true,
            .permission_groups => false,
        };
    }
};

pub const AccountIamGroupMutationEndpoint = enum {
    create,
    update,
    delete_group,

    pub fn parse(value: []const u8) ?AccountIamGroupMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "replace")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_group;
        return null;
    }

    pub fn commandName(self: AccountIamGroupMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_group => "delete",
        };
    }

    pub fn method(self: AccountIamGroupMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .delete_group => "DELETE",
        };
    }

    pub fn requiresResourceId(self: AccountIamGroupMutationEndpoint) bool {
        return self != .create;
    }

    pub fn group(self: AccountIamGroupMutationEndpoint, collection: AccountIamCollection) ![]const u8 {
        _ = self;
        return switch (collection) {
            .resource_groups => "Account Resource Groups",
            .user_groups => "Account User Groups",
            .permission_groups => error.UnsupportedCloudflareAccountIamGroupMutation,
        };
    }

    pub fn operationId(self: AccountIamGroupMutationEndpoint, collection: AccountIamCollection) ![]const u8 {
        return switch (collection) {
            .resource_groups => switch (self) {
                .create => "account-resource-group-create",
                .update => "account-resource-group-update",
                .delete_group => "account-resource-group-delete",
            },
            .user_groups => switch (self) {
                .create => "account-user-group-create",
                .update => "account-user-group-update",
                .delete_group => "account-user-group-delete",
            },
            .permission_groups => error.UnsupportedCloudflareAccountIamGroupMutation,
        };
    }

    pub fn summary(self: AccountIamGroupMutationEndpoint, collection: AccountIamCollection) ![]const u8 {
        return switch (collection) {
            .resource_groups => switch (self) {
                .create => "Create Resource Group",
                .update => "Update Resource Group",
                .delete_group => "Remove Resource Group",
            },
            .user_groups => switch (self) {
                .create => "Create User Group",
                .update => "Update User Group",
                .delete_group => "Remove User Group",
            },
            .permission_groups => error.UnsupportedCloudflareAccountIamGroupMutation,
        };
    }

    pub fn requestBodySchemaRef(self: AccountIamGroupMutationEndpoint, collection: AccountIamCollection) !?[]const u8 {
        return switch (collection) {
            .resource_groups => switch (self) {
                .create => "#/components/schemas/iam_request_create_resource_group",
                .update => "#/components/schemas/iam_request_update_resource_group",
                .delete_group => null,
            },
            .user_groups => switch (self) {
                .create => "#/components/schemas/iam_create_user_group_body",
                .update => "#/components/schemas/iam_update_user_group_body",
                .delete_group => null,
            },
            .permission_groups => error.UnsupportedCloudflareAccountIamGroupMutation,
        };
    }
};

pub const AccountIamGroupMutationArgs = struct {
    collection: AccountIamCollection,
    account_id: []const u8,
    resource_id: ?[]const u8 = null,
};

pub const AccountUserGroupMemberMutationEndpoint = enum {
    create,
    update,
    delete_member,

    pub fn parse(value: []const u8) ?AccountUserGroupMemberMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "replace")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_member;
        return null;
    }

    pub fn commandName(self: AccountUserGroupMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_member => "delete",
        };
    }

    pub fn group(self: AccountUserGroupMemberMutationEndpoint) []const u8 {
        _ = self;
        return "Account User Group Members";
    }

    pub fn method(self: AccountUserGroupMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .delete_member => "DELETE",
        };
    }

    pub fn operationId(self: AccountUserGroupMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "account-user-group-member-create",
            .update => "account-user-group-members-update",
            .delete_member => "account-user-group-member-delete",
        };
    }

    pub fn summary(self: AccountUserGroupMemberMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Add User Group Members",
            .update => "Update User Group Members",
            .delete_member => "Remove User Group Member",
        };
    }

    pub fn requestBodySchemaRef(self: AccountUserGroupMemberMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create, .update => "inline: array<{id:#/components/schemas/iam_user_group_member_identifier}>",
            .delete_member => null,
        };
    }

    pub fn requiresMemberId(self: AccountUserGroupMemberMutationEndpoint) bool {
        return self == .delete_member;
    }
};

pub const AccountUserGroupMemberMutationArgs = struct {
    account_id: []const u8,
    user_group_id: []const u8,
    member_id: ?[]const u8 = null,
};

pub const SecondaryDnsAccountResource = enum {
    acl,
    peer,
    tsig,

    pub fn parseListCommand(value: []const u8) ?SecondaryDnsAccountResource {
        if (std.mem.eql(u8, value, "acls")) return .acl;
        if (std.mem.eql(u8, value, "peers")) return .peer;
        if (std.mem.eql(u8, value, "tsigs")) return .tsig;
        return null;
    }

    pub fn parseDetailCommand(value: []const u8) ?SecondaryDnsAccountResource {
        if (std.mem.eql(u8, value, "acl")) return .acl;
        if (std.mem.eql(u8, value, "peer")) return .peer;
        if (std.mem.eql(u8, value, "tsig")) return .tsig;
        return null;
    }

    pub fn slug(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "acls",
            .peer => "peers",
            .tsig => "tsigs",
        };
    }

    pub fn listCommandName(self: SecondaryDnsAccountResource) []const u8 {
        return self.slug();
    }

    pub fn detailCommandName(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "acl",
            .peer => "peer",
            .tsig => "tsig",
        };
    }

    pub fn group(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "Secondary DNS (ACL)",
            .peer => "Secondary DNS (Peer)",
            .tsig => "Secondary DNS (TSIG)",
        };
    }

    pub fn listKind(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "secondary-dns-acls",
            .peer => "secondary-dns-peers",
            .tsig => "secondary-dns-tsigs",
        };
    }

    pub fn detailKind(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "secondary-dns-acl",
            .peer => "secondary-dns-peer",
            .tsig => "secondary-dns-tsig",
        };
    }

    pub fn listOperationId(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "secondary-dns-(-acl)-list-ac-ls",
            .peer => "secondary-dns-(-peer)-list-peers",
            .tsig => "secondary-dns-(-tsig)-list-tsi-gs",
        };
    }

    pub fn detailOperationId(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "secondary-dns-(-acl)-acl-details",
            .peer => "secondary-dns-(-peer)-peer-details",
            .tsig => "secondary-dns-(-tsig)-tsig-details",
        };
    }

    pub fn listSummary(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "List ACLs",
            .peer => "List Peers",
            .tsig => "List TSIGs",
        };
    }

    pub fn detailSummary(self: SecondaryDnsAccountResource) []const u8 {
        return switch (self) {
            .acl => "ACL Details",
            .peer => "Peer Details",
            .tsig => "TSIG Details",
        };
    }
};

pub const SecondaryDnsAccountMutationEndpoint = enum {
    create,
    update,
    delete_resource,

    pub fn parse(value: []const u8) ?SecondaryDnsAccountMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "replace")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_resource;
        return null;
    }

    pub fn commandName(self: SecondaryDnsAccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_resource => "delete",
        };
    }

    pub fn method(self: SecondaryDnsAccountMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .delete_resource => "DELETE",
        };
    }

    pub fn requiresResourceId(self: SecondaryDnsAccountMutationEndpoint) bool {
        return self != .create;
    }

    pub fn operationId(self: SecondaryDnsAccountMutationEndpoint, resource: SecondaryDnsAccountResource) []const u8 {
        return switch (resource) {
            .acl => switch (self) {
                .create => "secondary-dns-(-acl)-create-acl",
                .update => "secondary-dns-(-acl)-update-acl",
                .delete_resource => "secondary-dns-(-acl)-delete-acl",
            },
            .peer => switch (self) {
                .create => "secondary-dns-(-peer)-create-peer",
                .update => "secondary-dns-(-peer)-update-peer",
                .delete_resource => "secondary-dns-(-peer)-delete-peer",
            },
            .tsig => switch (self) {
                .create => "secondary-dns-(-tsig)-create-tsig",
                .update => "secondary-dns-(-tsig)-update-tsig",
                .delete_resource => "secondary-dns-(-tsig)-delete-tsig",
            },
        };
    }

    pub fn summary(self: SecondaryDnsAccountMutationEndpoint, resource: SecondaryDnsAccountResource) []const u8 {
        return switch (resource) {
            .acl => switch (self) {
                .create => "Create ACL",
                .update => "Update ACL",
                .delete_resource => "Delete ACL",
            },
            .peer => switch (self) {
                .create => "Create Peer",
                .update => "Update Peer",
                .delete_resource => "Delete Peer",
            },
            .tsig => switch (self) {
                .create => "Create TSIG",
                .update => "Update TSIG",
                .delete_resource => "Delete TSIG",
            },
        };
    }

    pub fn requestBodySchemaRef(self: SecondaryDnsAccountMutationEndpoint, resource: SecondaryDnsAccountResource) ?[]const u8 {
        return switch (resource) {
            .acl => switch (self) {
                .create => "inline:{ip_range:string,name:string}",
                .update => "#/components/schemas/secondary-dns_acl",
                .delete_resource => null,
            },
            .peer => switch (self) {
                .create => "inline:{name:string}",
                .update => "#/components/schemas/secondary-dns_peer",
                .delete_resource => null,
            },
            .tsig => switch (self) {
                .create, .update => "#/components/schemas/secondary-dns_tsig",
                .delete_resource => null,
            },
        };
    }
};

pub const SecondaryDnsAccountMutationArgs = struct {
    resource: SecondaryDnsAccountResource,
    account_id: []const u8,
    resource_id: ?[]const u8 = null,
};

pub const DnsAnalyticsEndpoint = enum {
    report,
    bytime,

    pub fn parse(value: []const u8) ?DnsAnalyticsEndpoint {
        if (std.mem.eql(u8, value, "report") or std.mem.eql(u8, value, "table")) return .report;
        if (std.mem.eql(u8, value, "bytime") or std.mem.eql(u8, value, "by-time")) return .bytime;
        return null;
    }

    pub fn commandName(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "report",
            .bytime => "bytime",
        };
    }

    pub fn label(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "dns-analytics-report",
            .bytime => "dns-analytics-bytime",
        };
    }

    pub fn firewallLabel(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "dns-firewall-analytics-report",
            .bytime => "dns-firewall-analytics-bytime",
        };
    }

    pub fn operationId(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "dns-analytics-table",
            .bytime => "dns-analytics-by-time",
        };
    }

    pub fn firewallOperationId(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "dns-firewall-analytics-table",
            .bytime => "dns-firewall-analytics-by-time",
        };
    }

    pub fn summary(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "Table",
            .bytime => "By Time",
        };
    }

    pub fn suffix(self: DnsAnalyticsEndpoint) []const u8 {
        return switch (self) {
            .report => "report",
            .bytime => "report/bytime",
        };
    }
};

pub const DnsFirewallReadEndpoint = enum {
    list,
    details,
    reverse_dns,

    pub fn parse(value: []const u8) ?DnsFirewallReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "clusters")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .details;
        if (std.mem.eql(u8, value, "reverse-dns") or std.mem.eql(u8, value, "reverse")) return .reverse_dns;
        return null;
    }

    pub fn commandName(self: DnsFirewallReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
            .reverse_dns => "reverse-dns",
        };
    }

    pub fn label(self: DnsFirewallReadEndpoint) []const u8 {
        return switch (self) {
            .list => "dns-firewall",
            .details => "dns-firewall-cluster",
            .reverse_dns => "dns-firewall-reverse-dns",
        };
    }

    pub fn operationId(self: DnsFirewallReadEndpoint) []const u8 {
        return switch (self) {
            .list => "dns-firewall-list-dns-firewall-clusters",
            .details => "dns-firewall-dns-firewall-cluster-details",
            .reverse_dns => "dns-firewall-show-dns-firewall-cluster-reverse-dns",
        };
    }

    pub fn summary(self: DnsFirewallReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List DNS Firewall Clusters",
            .details => "DNS Firewall Cluster Details",
            .reverse_dns => "Show DNS Firewall Cluster Reverse DNS",
        };
    }

    pub fn requiresFirewallId(self: DnsFirewallReadEndpoint) bool {
        return self != .list;
    }
};

pub const DnsFirewallMutationEndpoint = enum {
    create,
    update,
    delete_cluster,
    update_reverse_dns,

    pub fn parse(value: []const u8) ?DnsFirewallMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "create-cluster")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "update-cluster")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-cluster")) return .delete_cluster;
        if (std.mem.eql(u8, value, "update-reverse-dns") or std.mem.eql(u8, value, "reverse-dns")) return .update_reverse_dns;
        return null;
    }

    pub fn commandName(self: DnsFirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_cluster => "delete",
            .update_reverse_dns => "update-reverse-dns",
        };
    }

    pub fn group(self: DnsFirewallMutationEndpoint) []const u8 {
        _ = self;
        return "DNS Firewall";
    }

    pub fn method(self: DnsFirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update, .update_reverse_dns => "PATCH",
            .delete_cluster => "DELETE",
        };
    }

    pub fn operationId(self: DnsFirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "dns-firewall-create-dns-firewall-cluster",
            .update => "dns-firewall-update-dns-firewall-cluster",
            .delete_cluster => "dns-firewall-delete-dns-firewall-cluster",
            .update_reverse_dns => "dns-firewall-update-dns-firewall-cluster-reverse-dns",
        };
    }

    pub fn summary(self: DnsFirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create DNS Firewall Cluster",
            .update => "Update DNS Firewall Cluster",
            .delete_cluster => "Delete DNS Firewall Cluster",
            .update_reverse_dns => "Update DNS Firewall Cluster Reverse DNS",
        };
    }

    pub fn requestBodySchemaRef(self: DnsFirewallMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/dns-firewall_dns-firewall-cluster-post",
            .update => "#/components/schemas/dns-firewall_dns-firewall-cluster-patch",
            .update_reverse_dns => "#/components/schemas/dns-firewall_dns-firewall-reverse-dns-patch",
            .delete_cluster => null,
        };
    }

    pub fn requiresFirewallId(self: DnsFirewallMutationEndpoint) bool {
        return self != .create;
    }
};

pub const DnsFirewallMutationArgs = struct {
    account_id: []const u8,
    dns_firewall_id: ?[]const u8 = null,
};

pub const DnsSettingsMutationEndpoint = enum {
    account,
    zone,

    pub fn parse(value: []const u8) ?DnsSettingsMutationEndpoint {
        if (std.mem.eql(u8, value, "account")) return .account;
        if (std.mem.eql(u8, value, "zone")) return .zone;
        return null;
    }

    pub fn commandName(self: DnsSettingsMutationEndpoint) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn group(self: DnsSettingsMutationEndpoint) []const u8 {
        return switch (self) {
            .account => "DNS Settings for an Account",
            .zone => "DNS Settings for a Zone",
        };
    }

    pub fn method(self: DnsSettingsMutationEndpoint) []const u8 {
        _ = self;
        return "PATCH";
    }

    pub fn operationId(self: DnsSettingsMutationEndpoint) []const u8 {
        return switch (self) {
            .account => "dns-settings-for-an-account-update-dns-settings",
            .zone => "dns-settings-for-a-zone-update-dns-settings",
        };
    }

    pub fn summary(self: DnsSettingsMutationEndpoint) []const u8 {
        _ = self;
        return "Update DNS Settings";
    }

    pub fn requestBodySchemaRef(self: DnsSettingsMutationEndpoint) []const u8 {
        return switch (self) {
            .account => "#/components/schemas/dns-settings_account_settings_patch",
            .zone => "#/components/schemas/dns-settings_dns-settings-zone-patch",
        };
    }
};

pub const DnsSettingsMutationArgs = struct {
    account_id: ?[]const u8 = null,
    zone_id: ?[]const u8 = null,
};

pub const LoadBalancingAccountReadEndpoint = enum {
    monitor_groups,
    monitor_group,
    monitor_group_references,
    monitors,
    monitor,
    monitor_references,
    monitor_preview_result,
    pools,
    pool,
    pool_health,
    pool_references,
    regions,
    region,
    search,

    pub fn parse(value: []const u8) ?LoadBalancingAccountReadEndpoint {
        if (std.mem.eql(u8, value, "monitor-groups")) return .monitor_groups;
        if (std.mem.eql(u8, value, "monitor-group")) return .monitor_group;
        if (std.mem.eql(u8, value, "monitor-group-references") or std.mem.eql(u8, value, "monitor-group-refs")) return .monitor_group_references;
        if (std.mem.eql(u8, value, "monitors")) return .monitors;
        if (std.mem.eql(u8, value, "monitor")) return .monitor;
        if (std.mem.eql(u8, value, "monitor-references") or std.mem.eql(u8, value, "monitor-refs")) return .monitor_references;
        if (std.mem.eql(u8, value, "preview-result") or std.mem.eql(u8, value, "monitor-preview-result")) return .monitor_preview_result;
        if (std.mem.eql(u8, value, "pools")) return .pools;
        if (std.mem.eql(u8, value, "pool")) return .pool;
        if (std.mem.eql(u8, value, "pool-health")) return .pool_health;
        if (std.mem.eql(u8, value, "pool-references") or std.mem.eql(u8, value, "pool-refs")) return .pool_references;
        if (std.mem.eql(u8, value, "regions")) return .regions;
        if (std.mem.eql(u8, value, "region")) return .region;
        if (std.mem.eql(u8, value, "search")) return .search;
        return null;
    }

    pub fn commandName(self: LoadBalancingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .monitor_groups => "monitor-groups",
            .monitor_group => "monitor-group",
            .monitor_group_references => "monitor-group-references",
            .monitors => "monitors",
            .monitor => "monitor",
            .monitor_references => "monitor-references",
            .monitor_preview_result => "preview-result",
            .pools => "pools",
            .pool => "pool",
            .pool_health => "pool-health",
            .pool_references => "pool-references",
            .regions => "regions",
            .region => "region",
            .search => "search",
        };
    }

    pub fn label(self: LoadBalancingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .monitor_groups => "load-balancing-account-monitor-groups",
            .monitor_group => "load-balancing-account-monitor-group",
            .monitor_group_references => "load-balancing-account-monitor-group-references",
            .monitors => "load-balancing-account-monitors",
            .monitor => "load-balancing-account-monitor",
            .monitor_references => "load-balancing-account-monitor-references",
            .monitor_preview_result => "load-balancing-account-preview-result",
            .pools => "load-balancing-account-pools",
            .pool => "load-balancing-account-pool",
            .pool_health => "load-balancing-account-pool-health",
            .pool_references => "load-balancing-account-pool-references",
            .regions => "load-balancing-account-regions",
            .region => "load-balancing-account-region",
            .search => "load-balancing-account-search",
        };
    }

    pub fn group(self: LoadBalancingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .monitor_groups, .monitor_group, .monitor_group_references => "Account Load Balancer Monitor Groups",
            .monitors, .monitor, .monitor_references, .monitor_preview_result => "Account Load Balancer Monitors",
            .pools, .pool, .pool_health, .pool_references => "Account Load Balancer Pools",
            .regions, .region => "Load Balancer Regions",
            .search => "Account Load Balancer Search",
        };
    }

    pub fn operationId(self: LoadBalancingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .monitor_groups => "account-load-balancer-monitor-groups-list-monitor-groups",
            .monitor_group => "account-load-balancer-monitor-groups-monitor-group-details",
            .monitor_group_references => "account-load-balancer-monitor-groups-list-monitor-group-references",
            .monitors => "account-load-balancer-monitors-list-monitors",
            .monitor => "account-load-balancer-monitors-monitor-details",
            .monitor_references => "account-load-balancer-monitors-list-monitor-references",
            .monitor_preview_result => "account-load-balancer-monitors-preview-result",
            .pools => "account-load-balancer-pools-list-pools",
            .pool => "account-load-balancer-pools-pool-details",
            .pool_health => "account-load-balancer-pools-pool-health-details",
            .pool_references => "account-load-balancer-pools-list-pool-references",
            .regions => "load-balancer-regions-list-regions",
            .region => "load-balancer-regions-get-region",
            .search => "account-load-balancer-search-search-resources",
        };
    }

    pub fn summary(self: LoadBalancingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .monitor_groups => "List Monitor Groups",
            .monitor_group => "Monitor Group Details",
            .monitor_group_references => "List Monitor Group References",
            .monitors => "List Monitors",
            .monitor => "Monitor Details",
            .monitor_references => "List Monitor References",
            .monitor_preview_result => "Preview Result",
            .pools => "List Pools",
            .pool => "Pool Details",
            .pool_health => "Pool Health Details",
            .pool_references => "List Pool References",
            .regions => "List Regions",
            .region => "Get Region",
            .search => "Search Resources",
        };
    }

    pub fn requiresResourceId(self: LoadBalancingAccountReadEndpoint) bool {
        return switch (self) {
            .monitor_groups, .monitors, .pools, .regions, .search => false,
            .monitor_group, .monitor_group_references, .monitor, .monitor_references, .monitor_preview_result, .pool, .pool_health, .pool_references, .region => true,
        };
    }
};

pub const LoadBalancingUserReadEndpoint = enum {
    monitors,
    monitor,
    monitor_references,
    monitor_preview_result,
    pools,
    pool,
    pool_health,
    pool_references,
    healthcheck_events,

    pub fn parse(value: []const u8) ?LoadBalancingUserReadEndpoint {
        if (std.mem.eql(u8, value, "monitors")) return .monitors;
        if (std.mem.eql(u8, value, "monitor")) return .monitor;
        if (std.mem.eql(u8, value, "monitor-references") or std.mem.eql(u8, value, "monitor-refs")) return .monitor_references;
        if (std.mem.eql(u8, value, "preview-result") or std.mem.eql(u8, value, "monitor-preview-result")) return .monitor_preview_result;
        if (std.mem.eql(u8, value, "pools")) return .pools;
        if (std.mem.eql(u8, value, "pool")) return .pool;
        if (std.mem.eql(u8, value, "pool-health")) return .pool_health;
        if (std.mem.eql(u8, value, "pool-references") or std.mem.eql(u8, value, "pool-refs")) return .pool_references;
        if (std.mem.eql(u8, value, "healthcheck-events") or std.mem.eql(u8, value, "events")) return .healthcheck_events;
        return null;
    }

    pub fn commandName(self: LoadBalancingUserReadEndpoint) []const u8 {
        return switch (self) {
            .monitors => "monitors",
            .monitor => "monitor",
            .monitor_references => "monitor-references",
            .monitor_preview_result => "preview-result",
            .pools => "pools",
            .pool => "pool",
            .pool_health => "pool-health",
            .pool_references => "pool-references",
            .healthcheck_events => "healthcheck-events",
        };
    }

    pub fn label(self: LoadBalancingUserReadEndpoint) []const u8 {
        return switch (self) {
            .monitors => "load-balancing-user-monitors",
            .monitor => "load-balancing-user-monitor",
            .monitor_references => "load-balancing-user-monitor-references",
            .monitor_preview_result => "load-balancing-user-preview-result",
            .pools => "load-balancing-user-pools",
            .pool => "load-balancing-user-pool",
            .pool_health => "load-balancing-user-pool-health",
            .pool_references => "load-balancing-user-pool-references",
            .healthcheck_events => "load-balancing-healthcheck-events",
        };
    }

    pub fn group(self: LoadBalancingUserReadEndpoint) []const u8 {
        return switch (self) {
            .monitors, .monitor, .monitor_references, .monitor_preview_result => "Load Balancer Monitors",
            .pools, .pool, .pool_health, .pool_references => "Load Balancer Pools",
            .healthcheck_events => "Load Balancer Healthcheck Events",
        };
    }

    pub fn operationId(self: LoadBalancingUserReadEndpoint) []const u8 {
        return switch (self) {
            .monitors => "load-balancer-monitors-list-monitors",
            .monitor => "load-balancer-monitors-monitor-details",
            .monitor_references => "load-balancer-monitors-list-monitor-references",
            .monitor_preview_result => "load-balancer-monitors-preview-result",
            .pools => "load-balancer-pools-list-pools",
            .pool => "load-balancer-pools-pool-details",
            .pool_health => "load-balancer-pools-pool-health-details",
            .pool_references => "load-balancer-pools-list-pool-references",
            .healthcheck_events => "load-balancer-healthcheck-events-list-healthcheck-events",
        };
    }

    pub fn summary(self: LoadBalancingUserReadEndpoint) []const u8 {
        return switch (self) {
            .monitors => "List Monitors",
            .monitor => "Monitor Details",
            .monitor_references => "List Monitor References",
            .monitor_preview_result => "Preview Result",
            .pools => "List Pools",
            .pool => "Pool Details",
            .pool_health => "Pool Health Details",
            .pool_references => "List Pool References",
            .healthcheck_events => "List Healthcheck Events",
        };
    }

    pub fn requiresResourceId(self: LoadBalancingUserReadEndpoint) bool {
        return switch (self) {
            .monitors, .pools, .healthcheck_events => false,
            .monitor, .monitor_references, .monitor_preview_result, .pool, .pool_health, .pool_references => true,
        };
    }
};

pub const LoadBalancingZoneReadEndpoint = enum {
    load_balancers,
    load_balancer,

    pub fn parse(value: []const u8) ?LoadBalancingZoneReadEndpoint {
        if (std.mem.eql(u8, value, "load-balancers") or std.mem.eql(u8, value, "list")) return .load_balancers;
        if (std.mem.eql(u8, value, "load-balancer") or std.mem.eql(u8, value, "show")) return .load_balancer;
        return null;
    }

    pub fn commandName(self: LoadBalancingZoneReadEndpoint) []const u8 {
        return switch (self) {
            .load_balancers => "load-balancers",
            .load_balancer => "load-balancer",
        };
    }

    pub fn label(self: LoadBalancingZoneReadEndpoint) []const u8 {
        return switch (self) {
            .load_balancers => "load-balancers",
            .load_balancer => "load-balancer",
        };
    }

    pub fn group(self: LoadBalancingZoneReadEndpoint) []const u8 {
        _ = self;
        return "Load Balancers";
    }

    pub fn operationId(self: LoadBalancingZoneReadEndpoint) []const u8 {
        return switch (self) {
            .load_balancers => "load-balancers-list-load-balancers",
            .load_balancer => "load-balancers-load-balancer-details",
        };
    }

    pub fn summary(self: LoadBalancingZoneReadEndpoint) []const u8 {
        return switch (self) {
            .load_balancers => "List Load Balancers",
            .load_balancer => "Load Balancer Details",
        };
    }

    pub fn requiresLoadBalancerId(self: LoadBalancingZoneReadEndpoint) bool {
        return self == .load_balancer;
    }
};

pub const LoadBalancingMutationResource = enum {
    account_monitor_group,
    account_monitor,
    account_pool,
    user_monitor,
    user_pool,
    zone_load_balancer,

    pub fn parse(value: []const u8) ?LoadBalancingMutationResource {
        if (std.mem.eql(u8, value, "account-monitor-group")) return .account_monitor_group;
        if (std.mem.eql(u8, value, "account-monitor")) return .account_monitor;
        if (std.mem.eql(u8, value, "account-pool")) return .account_pool;
        if (std.mem.eql(u8, value, "user-monitor")) return .user_monitor;
        if (std.mem.eql(u8, value, "user-pool")) return .user_pool;
        if (std.mem.eql(u8, value, "zone-load-balancer") or std.mem.eql(u8, value, "load-balancer")) return .zone_load_balancer;
        return null;
    }

    pub fn commandName(self: LoadBalancingMutationResource) []const u8 {
        return switch (self) {
            .account_monitor_group => "account-monitor-group",
            .account_monitor => "account-monitor",
            .account_pool => "account-pool",
            .user_monitor => "user-monitor",
            .user_pool => "user-pool",
            .zone_load_balancer => "zone-load-balancer",
        };
    }

    pub fn group(self: LoadBalancingMutationResource) []const u8 {
        return switch (self) {
            .account_monitor_group => "Account Load Balancer Monitor Groups",
            .account_monitor => "Account Load Balancer Monitors",
            .account_pool => "Account Load Balancer Pools",
            .user_monitor => "Load Balancer Monitors",
            .user_pool => "Load Balancer Pools",
            .zone_load_balancer => "Load Balancers",
        };
    }

    pub fn collectionSlug(self: LoadBalancingMutationResource) []const u8 {
        return switch (self) {
            .account_monitor_group => "monitor_groups",
            .account_monitor, .user_monitor => "monitors",
            .account_pool, .user_pool => "pools",
            .zone_load_balancer => "load_balancers",
        };
    }

    pub fn resourceLabel(self: LoadBalancingMutationResource) []const u8 {
        return switch (self) {
            .account_monitor_group => "monitor group",
            .account_monitor, .user_monitor => "monitor",
            .account_pool, .user_pool => "pool",
            .zone_load_balancer => "load balancer",
        };
    }

    pub fn usesAccountId(self: LoadBalancingMutationResource) bool {
        return switch (self) {
            .account_monitor_group, .account_monitor, .account_pool => true,
            .user_monitor, .user_pool, .zone_load_balancer => false,
        };
    }

    pub fn usesZoneId(self: LoadBalancingMutationResource) bool {
        return self == .zone_load_balancer;
    }
};

pub const LoadBalancingMutationEndpoint = enum {
    create,
    update,
    patch,
    delete_resource,
    preview,
    patch_collection,

    pub fn parse(value: []const u8) ?LoadBalancingMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "patch")) return .patch;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_resource;
        if (std.mem.eql(u8, value, "preview")) return .preview;
        if (std.mem.eql(u8, value, "patch-all") or std.mem.eql(u8, value, "patch-collection")) return .patch_collection;
        return null;
    }

    pub fn commandName(self: LoadBalancingMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .patch => "patch",
            .delete_resource => "delete",
            .preview => "preview",
            .patch_collection => "patch-all",
        };
    }

    pub fn method(self: LoadBalancingMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .preview => "POST",
            .update => "PUT",
            .patch, .patch_collection => "PATCH",
            .delete_resource => "DELETE",
        };
    }

    pub fn supports(self: LoadBalancingMutationEndpoint, resource: LoadBalancingMutationResource) bool {
        return switch (resource) {
            .account_monitor_group, .zone_load_balancer => switch (self) {
                .create, .update, .patch, .delete_resource => true,
                .preview, .patch_collection => false,
            },
            .account_monitor, .user_monitor => switch (self) {
                .create, .update, .patch, .delete_resource, .preview => true,
                .patch_collection => false,
            },
            .account_pool, .user_pool => true,
        };
    }

    pub fn requiresResourceId(self: LoadBalancingMutationEndpoint) bool {
        return switch (self) {
            .create, .patch_collection => false,
            .update, .patch, .delete_resource, .preview => true,
        };
    }

    pub fn operationId(self: LoadBalancingMutationEndpoint, resource: LoadBalancingMutationResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareLoadBalancingMutation;
        return switch (resource) {
            .account_monitor_group => switch (self) {
                .create => "account-load-balancer-monitor-groups-create-monitor-group",
                .update => "account-load-balancer-monitor-groups-update-monitor-group",
                .patch => "account-load-balancer-monitor-groups-patch-monitor-group",
                .delete_resource => "account-load-balancer-monitor-groups-delete-monitor-group",
                else => unreachable,
            },
            .account_monitor => switch (self) {
                .create => "account-load-balancer-monitors-create-monitor",
                .update => "account-load-balancer-monitors-update-monitor",
                .patch => "account-load-balancer-monitors-patch-monitor",
                .delete_resource => "account-load-balancer-monitors-delete-monitor",
                .preview => "account-load-balancer-monitors-preview-monitor",
                else => unreachable,
            },
            .account_pool => switch (self) {
                .create => "account-load-balancer-pools-create-pool",
                .update => "account-load-balancer-pools-update-pool",
                .patch => "account-load-balancer-pools-patch-pool",
                .delete_resource => "account-load-balancer-pools-delete-pool",
                .preview => "account-load-balancer-pools-preview-pool",
                .patch_collection => "account-load-balancer-pools-patch-pools",
            },
            .user_monitor => switch (self) {
                .create => "load-balancer-monitors-create-monitor",
                .update => "load-balancer-monitors-update-monitor",
                .patch => "load-balancer-monitors-patch-monitor",
                .delete_resource => "load-balancer-monitors-delete-monitor",
                .preview => "load-balancer-monitors-preview-monitor",
                else => unreachable,
            },
            .user_pool => switch (self) {
                .create => "load-balancer-pools-create-pool",
                .update => "load-balancer-pools-update-pool",
                .patch => "load-balancer-pools-patch-pool",
                .delete_resource => "load-balancer-pools-delete-pool",
                .preview => "load-balancer-pools-preview-pool",
                .patch_collection => "load-balancer-pools-patch-pools",
            },
            .zone_load_balancer => switch (self) {
                .create => "load-balancers-create-load-balancer",
                .update => "load-balancers-update-load-balancer",
                .patch => "load-balancers-patch-load-balancer",
                .delete_resource => "load-balancers-delete-load-balancer",
                else => unreachable,
            },
        };
    }

    pub fn summary(self: LoadBalancingMutationEndpoint, resource: LoadBalancingMutationResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareLoadBalancingMutation;
        return switch (resource) {
            .account_monitor_group => switch (self) {
                .create => "Create Monitor Group",
                .update => "Update Monitor Group",
                .patch => "Patch Monitor Group",
                .delete_resource => "Delete Monitor Group",
                else => unreachable,
            },
            .account_monitor, .user_monitor => switch (self) {
                .create => "Create Monitor",
                .update => "Update Monitor",
                .patch => "Patch Monitor",
                .delete_resource => "Delete Monitor",
                .preview => "Preview Monitor",
                else => unreachable,
            },
            .account_pool, .user_pool => switch (self) {
                .create => "Create Pool",
                .update => "Update Pool",
                .patch => "Patch Pool",
                .delete_resource => "Delete Pool",
                .preview => "Preview Pool",
                .patch_collection => "Patch Pools",
            },
            .zone_load_balancer => switch (self) {
                .create => "Create Load Balancer",
                .update => "Update Load Balancer",
                .patch => "Patch Load Balancer",
                .delete_resource => "Delete Load Balancer",
                else => unreachable,
            },
        };
    }

    pub fn requestBodySchemaRef(self: LoadBalancingMutationEndpoint, resource: LoadBalancingMutationResource) !?[]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareLoadBalancingMutation;
        return switch (resource) {
            .account_monitor_group => switch (self) {
                .create, .update, .patch => "#/components/schemas/load-balancing_monitor-group",
                .delete_resource => null,
                else => unreachable,
            },
            .account_monitor, .user_monitor => switch (self) {
                .create, .update, .patch, .preview => "object",
                .delete_resource => null,
                else => unreachable,
            },
            .account_pool, .user_pool => switch (self) {
                .patch_collection => "string",
                .create, .update, .patch => "object",
                .preview => "object",
                .delete_resource => null,
            },
            .zone_load_balancer => switch (self) {
                .create, .update, .patch => "object",
                .delete_resource => null,
                else => unreachable,
            },
        };
    }
};

pub const LoadBalancingMutationArgs = struct {
    resource: LoadBalancingMutationResource,
    account_id: ?[]const u8 = null,
    zone_id: ?[]const u8 = null,
    resource_id: ?[]const u8 = null,
};

pub const EndpointHealthCheckReadEndpoint = enum {
    list,
    details,

    pub fn parse(value: []const u8) ?EndpointHealthCheckReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "endpoint-healthchecks")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details") or std.mem.eql(u8, value, "endpoint-healthcheck")) return .details;
        return null;
    }

    pub fn commandName(self: EndpointHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
        };
    }

    pub fn label(self: EndpointHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "endpoint-healthchecks",
            .details => "endpoint-healthcheck",
        };
    }

    pub fn group(self: EndpointHealthCheckReadEndpoint) []const u8 {
        _ = self;
        return "Endpoint Health Checks";
    }

    pub fn operationId(self: EndpointHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "diagnostics-endpoint-healthcheck-list",
            .details => "diagnostics-endpoint-healthcheck-get",
        };
    }

    pub fn summary(self: EndpointHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List Endpoint Health Checks",
            .details => "Get Endpoint Health Check",
        };
    }

    pub fn requiresHealthCheckId(self: EndpointHealthCheckReadEndpoint) bool {
        return self == .details;
    }
};

pub const ZoneHealthCheckReadEndpoint = enum {
    list,
    details,
    preview_details,

    pub fn parse(value: []const u8) ?ZoneHealthCheckReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "healthchecks")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details") or std.mem.eql(u8, value, "healthcheck")) return .details;
        if (std.mem.eql(u8, value, "preview") or std.mem.eql(u8, value, "preview-details")) return .preview_details;
        return null;
    }

    pub fn commandName(self: ZoneHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
            .preview_details => "preview",
        };
    }

    pub fn label(self: ZoneHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "healthchecks",
            .details => "healthcheck",
            .preview_details => "healthcheck-preview",
        };
    }

    pub fn group(self: ZoneHealthCheckReadEndpoint) []const u8 {
        _ = self;
        return "Health Checks";
    }

    pub fn operationId(self: ZoneHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "health-checks-list-health-checks",
            .details => "health-checks-health-check-details",
            .preview_details => "health-checks-health-check-preview-details",
        };
    }

    pub fn summary(self: ZoneHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List Health Checks",
            .details => "Health Check Details",
            .preview_details => "Health Check Preview Details",
        };
    }

    pub fn requiresHealthCheckId(self: ZoneHealthCheckReadEndpoint) bool {
        return self != .list;
    }
};

pub const SmartShieldHealthCheckReadEndpoint = enum {
    list,
    details,

    pub fn parse(value: []const u8) ?SmartShieldHealthCheckReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "healthchecks")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details") or std.mem.eql(u8, value, "healthcheck")) return .details;
        return null;
    }

    pub fn commandName(self: SmartShieldHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
        };
    }

    pub fn label(self: SmartShieldHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "smart-shield-healthchecks",
            .details => "smart-shield-healthcheck",
        };
    }

    pub fn group(self: SmartShieldHealthCheckReadEndpoint) []const u8 {
        _ = self;
        return "Health Checks";
    }

    pub fn operationId(self: SmartShieldHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "smart-shield-list-health-checks",
            .details => "smart-shield-health-check-details",
        };
    }

    pub fn summary(self: SmartShieldHealthCheckReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List Health Checks",
            .details => "Health Check Details",
        };
    }

    pub fn requiresHealthCheckId(self: SmartShieldHealthCheckReadEndpoint) bool {
        return self == .details;
    }
};

pub const HealthCheckMutationResource = enum {
    endpoint,
    zone,
    preview,
    smart_shield,

    pub fn parse(value: []const u8) ?HealthCheckMutationResource {
        if (std.mem.eql(u8, value, "endpoint") or std.mem.eql(u8, value, "endpoint-healthcheck")) return .endpoint;
        if (std.mem.eql(u8, value, "zone") or std.mem.eql(u8, value, "healthcheck")) return .zone;
        if (std.mem.eql(u8, value, "preview") or std.mem.eql(u8, value, "healthcheck-preview")) return .preview;
        if (std.mem.eql(u8, value, "smart-shield") or std.mem.eql(u8, value, "smartshield")) return .smart_shield;
        return null;
    }

    pub fn commandName(self: HealthCheckMutationResource) []const u8 {
        return switch (self) {
            .endpoint => "endpoint",
            .zone => "zone",
            .preview => "preview",
            .smart_shield => "smart-shield",
        };
    }

    pub fn group(self: HealthCheckMutationResource) []const u8 {
        return switch (self) {
            .endpoint => "Endpoint Health Checks",
            .zone, .preview, .smart_shield => "Health Checks",
        };
    }

    pub fn resourceLabel(self: HealthCheckMutationResource) []const u8 {
        return switch (self) {
            .endpoint => "endpoint health check",
            .zone => "health check",
            .preview => "preview health check",
            .smart_shield => "smart-shield health check",
        };
    }

    pub fn usesAccountId(self: HealthCheckMutationResource) bool {
        return self == .endpoint;
    }

    pub fn usesZoneId(self: HealthCheckMutationResource) bool {
        return self != .endpoint;
    }
};

pub const HealthCheckMutationEndpoint = enum {
    create,
    update,
    patch,
    delete_resource,

    pub fn parse(value: []const u8) ?HealthCheckMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "patch")) return .patch;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_resource;
        return null;
    }

    pub fn commandName(self: HealthCheckMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .patch => "patch",
            .delete_resource => "delete",
        };
    }

    pub fn method(self: HealthCheckMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .patch => "PATCH",
            .delete_resource => "DELETE",
        };
    }

    pub fn supports(self: HealthCheckMutationEndpoint, resource: HealthCheckMutationResource) bool {
        return switch (resource) {
            .endpoint => switch (self) {
                .create, .update, .delete_resource => true,
                .patch => false,
            },
            .zone, .smart_shield => true,
            .preview => switch (self) {
                .create, .delete_resource => true,
                .update, .patch => false,
            },
        };
    }

    pub fn requiresHealthCheckId(self: HealthCheckMutationEndpoint) bool {
        return self != .create;
    }

    pub fn operationId(self: HealthCheckMutationEndpoint, resource: HealthCheckMutationResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareHealthCheckMutation;
        return switch (resource) {
            .endpoint => switch (self) {
                .create => "diagnostics-endpoint-healthcheck-create",
                .update => "diagnostics-endpoint-healthcheck-update",
                .delete_resource => "diagnostics-endpoint-healthcheck-delete",
                else => unreachable,
            },
            .zone => switch (self) {
                .create => "health-checks-create-health-check",
                .update => "health-checks-update-health-check",
                .patch => "health-checks-patch-health-check",
                .delete_resource => "health-checks-delete-health-check",
            },
            .preview => switch (self) {
                .create => "health-checks-create-preview-health-check",
                .delete_resource => "health-checks-delete-preview-health-check",
                else => unreachable,
            },
            .smart_shield => switch (self) {
                .create => "smart-shield-create-health-check",
                .update => "smart-shield-update-health-check",
                .patch => "smart-shield-patch-health-check",
                .delete_resource => "smart-shield-delete-health-check",
            },
        };
    }

    pub fn summary(self: HealthCheckMutationEndpoint, resource: HealthCheckMutationResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareHealthCheckMutation;
        return switch (resource) {
            .endpoint => switch (self) {
                .create => "Endpoint Health Check",
                .update => "Update Endpoint Health Check",
                .delete_resource => "Delete Endpoint Health Check",
                else => unreachable,
            },
            .zone => switch (self) {
                .create => "Create Health Check",
                .update => "Update Health Check",
                .patch => "Patch Health Check",
                .delete_resource => "Delete Health Check",
            },
            .preview => switch (self) {
                .create => "Create Preview Health Check",
                .delete_resource => "Delete Preview Health Check",
                else => unreachable,
            },
            .smart_shield => switch (self) {
                .create => "Create Health Check",
                .update => "Update Health Check",
                .patch => "Patch Health Check",
                .delete_resource => "Delete Health Check",
            },
        };
    }

    pub fn requestBodySchemaRef(self: HealthCheckMutationEndpoint, resource: HealthCheckMutationResource) !?[]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareHealthCheckMutation;
        return switch (resource) {
            .endpoint => switch (self) {
                .create, .update => "#/components/schemas/magic-transit_endpoint_health_check",
                .delete_resource => null,
                else => unreachable,
            },
            .zone, .preview => switch (self) {
                .create, .update, .patch => "#/components/schemas/healthchecks_query_healthcheck",
                .delete_resource => null,
            },
            .smart_shield => switch (self) {
                .create, .patch => "#/components/schemas/smartshield_query_healthcheck",
                .update => "#/components/schemas/smartshield_single_hc_response",
                .delete_resource => null,
            },
        };
    }
};

pub const HealthCheckMutationArgs = struct {
    resource: HealthCheckMutationResource,
    account_id: ?[]const u8 = null,
    zone_id: ?[]const u8 = null,
    healthcheck_id: ?[]const u8 = null,
};

pub const RulesetScope = enum {
    account,
    zone,

    pub fn parse(value: []const u8) ?RulesetScope {
        if (std.mem.eql(u8, value, "account") or std.mem.eql(u8, value, "accounts")) return .account;
        if (std.mem.eql(u8, value, "zone") or std.mem.eql(u8, value, "zones")) return .zone;
        return null;
    }

    pub fn commandName(self: RulesetScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn group(self: RulesetScope) []const u8 {
        return switch (self) {
            .account => "Account Rulesets",
            .zone => "Zone Rulesets",
        };
    }

    pub fn idLabel(self: RulesetScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn basePath(self: RulesetScope) []const u8 {
        return switch (self) {
            .account => accounts_path,
            .zone => zones_path,
        };
    }
};

pub const RulesetReadEndpoint = enum {
    list,
    ruleset,
    entrypoint,
    entrypoint_versions,
    entrypoint_version,
    versions,
    version,
    rules_by_tag,

    pub fn parse(value: []const u8) ?RulesetReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "rulesets")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "ruleset") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .ruleset;
        if (std.mem.eql(u8, value, "entrypoint") or std.mem.eql(u8, value, "entry-point")) return .entrypoint;
        if (std.mem.eql(u8, value, "entrypoint-versions") or std.mem.eql(u8, value, "entry-point-versions")) return .entrypoint_versions;
        if (std.mem.eql(u8, value, "entrypoint-version") or std.mem.eql(u8, value, "entry-point-version")) return .entrypoint_version;
        if (std.mem.eql(u8, value, "versions")) return .versions;
        if (std.mem.eql(u8, value, "version")) return .version;
        if (std.mem.eql(u8, value, "rules-by-tag") or std.mem.eql(u8, value, "by-tag")) return .rules_by_tag;
        return null;
    }

    pub fn commandName(self: RulesetReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .ruleset => "show",
            .entrypoint => "entrypoint",
            .entrypoint_versions => "entrypoint-versions",
            .entrypoint_version => "entrypoint-version",
            .versions => "versions",
            .version => "version",
            .rules_by_tag => "rules-by-tag",
        };
    }

    pub fn label(self: RulesetReadEndpoint, scope: RulesetScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .list => "account-rulesets",
                .ruleset => "account-ruleset",
                .entrypoint => "account-ruleset-entrypoint",
                .entrypoint_versions => "account-ruleset-entrypoint-versions",
                .entrypoint_version => "account-ruleset-entrypoint-version",
                .versions => "account-ruleset-versions",
                .version => "account-ruleset-version",
                .rules_by_tag => "account-ruleset-version-rules-by-tag",
            },
            .zone => switch (self) {
                .list => "zone-rulesets",
                .ruleset => "zone-ruleset",
                .entrypoint => "zone-ruleset-entrypoint",
                .entrypoint_versions => "zone-ruleset-entrypoint-versions",
                .entrypoint_version => "zone-ruleset-entrypoint-version",
                .versions => "zone-ruleset-versions",
                .version => "zone-ruleset-version",
                .rules_by_tag => "zone-ruleset-version-rules-by-tag",
            },
        };
    }

    pub fn operationId(self: RulesetReadEndpoint, scope: RulesetScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .list => "listAccountRulesets",
                .ruleset => "getAccountRuleset",
                .entrypoint => "getAccountEntrypointRuleset",
                .entrypoint_versions => "listAccountEntrypointRulesetVersions",
                .entrypoint_version => "getAccountEntrypointRulesetVersion",
                .versions => "listAccountRulesetVersions",
                .version => "getAccountRulesetVersion",
                .rules_by_tag => "listAccountRulesetVersionRulesByTag",
            },
            .zone => switch (self) {
                .list => "listZoneRulesets",
                .ruleset => "getZoneRuleset",
                .entrypoint => "getZoneEntrypointRuleset",
                .entrypoint_versions => "listZoneEntrypointRulesetVersions",
                .entrypoint_version => "getZoneEntrypointRulesetVersion",
                .versions => "listZoneRulesetVersions",
                .version => "getZoneRulesetVersion",
                .rules_by_tag => "listZoneRulesetVersionRulesByTag",
            },
        };
    }

    pub fn summary(self: RulesetReadEndpoint, scope: RulesetScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .list => "List account rulesets",
                .ruleset => "Get an account ruleset",
                .entrypoint => "Get an account entry point ruleset",
                .entrypoint_versions => "List an account entry point ruleset's versions",
                .entrypoint_version => "Get an account entry point ruleset version",
                .versions => "List an account ruleset's versions",
                .version => "Get an account ruleset version",
                .rules_by_tag => "List an account ruleset version's rules by tag",
            },
            .zone => switch (self) {
                .list => "List zone rulesets",
                .ruleset => "Get a zone ruleset",
                .entrypoint => "Get a zone entry point ruleset",
                .entrypoint_versions => "List a zone entry point ruleset's versions",
                .entrypoint_version => "Get a zone entry point ruleset version",
                .versions => "List a zone ruleset's versions",
                .version => "Get a zone ruleset version",
                .rules_by_tag => "List a zone ruleset version's rules by tag",
            },
        };
    }

    pub fn requiresRulesetId(self: RulesetReadEndpoint) bool {
        return switch (self) {
            .ruleset, .versions, .version, .rules_by_tag => true,
            .list, .entrypoint, .entrypoint_versions, .entrypoint_version => false,
        };
    }

    pub fn requiresPhase(self: RulesetReadEndpoint) bool {
        return switch (self) {
            .entrypoint, .entrypoint_versions, .entrypoint_version => true,
            .list, .ruleset, .versions, .version, .rules_by_tag => false,
        };
    }

    pub fn requiresVersion(self: RulesetReadEndpoint) bool {
        return switch (self) {
            .entrypoint_version, .version, .rules_by_tag => true,
            .list, .ruleset, .entrypoint, .entrypoint_versions, .versions => false,
        };
    }

    pub fn requiresRuleTag(self: RulesetReadEndpoint) bool {
        return self == .rules_by_tag;
    }
};

pub const RulesetReadArgs = struct {
    ruleset_id: ?[]const u8 = null,
    phase: ?[]const u8 = null,
    version: ?[]const u8 = null,
    rule_tag: ?[]const u8 = null,
};

pub const RulesetMutationEndpoint = enum {
    create_ruleset,
    update_ruleset,
    delete_ruleset,
    update_entrypoint,
    create_rule,
    update_rule,
    delete_rule,
    delete_version,

    pub fn parse(value: []const u8) ?RulesetMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "create-ruleset")) return .create_ruleset;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "update-ruleset")) return .update_ruleset;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-ruleset") or std.mem.eql(u8, value, "remove")) return .delete_ruleset;
        if (std.mem.eql(u8, value, "update-entrypoint") or std.mem.eql(u8, value, "update-entry-point")) return .update_entrypoint;
        if (std.mem.eql(u8, value, "create-rule") or std.mem.eql(u8, value, "add-rule")) return .create_rule;
        if (std.mem.eql(u8, value, "update-rule") or std.mem.eql(u8, value, "patch-rule")) return .update_rule;
        if (std.mem.eql(u8, value, "delete-rule") or std.mem.eql(u8, value, "remove-rule")) return .delete_rule;
        if (std.mem.eql(u8, value, "delete-version") or std.mem.eql(u8, value, "remove-version")) return .delete_version;
        return null;
    }

    pub fn commandName(self: RulesetMutationEndpoint) []const u8 {
        return switch (self) {
            .create_ruleset => "create",
            .update_ruleset => "update",
            .delete_ruleset => "delete",
            .update_entrypoint => "update-entrypoint",
            .create_rule => "create-rule",
            .update_rule => "update-rule",
            .delete_rule => "delete-rule",
            .delete_version => "delete-version",
        };
    }

    pub fn method(self: RulesetMutationEndpoint) []const u8 {
        return switch (self) {
            .create_ruleset, .create_rule => "POST",
            .update_ruleset, .update_entrypoint => "PUT",
            .update_rule => "PATCH",
            .delete_ruleset, .delete_rule, .delete_version => "DELETE",
        };
    }

    pub fn operationId(self: RulesetMutationEndpoint, scope: RulesetScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .create_ruleset => "createAccountRuleset",
                .update_ruleset => "updateAccountRuleset",
                .delete_ruleset => "deleteAccountRuleset",
                .update_entrypoint => "updateAccountEntrypointRuleset",
                .create_rule => "createAccountRulesetRule",
                .update_rule => "updateAccountRulesetRule",
                .delete_rule => "deleteAccountRulesetRule",
                .delete_version => "deleteAccountRulesetVersion",
            },
            .zone => switch (self) {
                .create_ruleset => "createZoneRuleset",
                .update_ruleset => "updateZoneRuleset",
                .delete_ruleset => "deleteZoneRuleset",
                .update_entrypoint => "updateZoneEntrypointRuleset",
                .create_rule => "createZoneRulesetRule",
                .update_rule => "updateZoneRulesetRule",
                .delete_rule => "deleteZoneRulesetRule",
                .delete_version => "deleteZoneRulesetVersion",
            },
        };
    }

    pub fn summary(self: RulesetMutationEndpoint, scope: RulesetScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .create_ruleset => "Create an account ruleset",
                .update_ruleset => "Update an account ruleset",
                .delete_ruleset => "Delete an account ruleset",
                .update_entrypoint => "Update an account entry point ruleset",
                .create_rule => "Create an account ruleset rule",
                .update_rule => "Update an account ruleset rule",
                .delete_rule => "Delete an account ruleset rule",
                .delete_version => "Delete an account ruleset version",
            },
            .zone => switch (self) {
                .create_ruleset => "Create a zone ruleset",
                .update_ruleset => "Update a zone ruleset",
                .delete_ruleset => "Delete a zone ruleset",
                .update_entrypoint => "Update a zone entry point ruleset",
                .create_rule => "Create a zone ruleset rule",
                .update_rule => "Update a zone ruleset rule",
                .delete_rule => "Delete a zone ruleset rule",
                .delete_version => "Delete a zone ruleset version",
            },
        };
    }

    pub fn requestBodySchemaRef(self: RulesetMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_ruleset => "#/components/requestBodies/rulesets_CreateRuleset",
            .update_ruleset => "#/components/requestBodies/rulesets_UpdateRuleset",
            .update_entrypoint => "#/components/requestBodies/rulesets_UpdateEntrypointRuleset",
            .create_rule, .update_rule => "#/components/requestBodies/rulesets_Rule",
            .delete_ruleset, .delete_rule, .delete_version => null,
        };
    }

    pub fn requiresRulesetId(self: RulesetMutationEndpoint) bool {
        return switch (self) {
            .update_ruleset, .delete_ruleset, .create_rule, .update_rule, .delete_rule, .delete_version => true,
            .create_ruleset, .update_entrypoint => false,
        };
    }

    pub fn requiresPhase(self: RulesetMutationEndpoint) bool {
        return self == .update_entrypoint;
    }

    pub fn requiresRuleId(self: RulesetMutationEndpoint) bool {
        return self == .update_rule or self == .delete_rule;
    }

    pub fn requiresVersion(self: RulesetMutationEndpoint) bool {
        return self == .delete_version;
    }
};

pub const RulesetMutationArgs = struct {
    scope: RulesetScope,
    scope_id: []const u8,
    ruleset_id: ?[]const u8 = null,
    phase: ?[]const u8 = null,
    version: ?[]const u8 = null,
    rule_id: ?[]const u8 = null,
};

pub const CloudforceOneRuleReadEndpoint = enum {
    list,
    managed,
    search,
    stats,
    tree,
    rule,

    pub fn parse(value: []const u8) ?CloudforceOneRuleReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "rules")) return .list;
        if (std.mem.eql(u8, value, "managed") or std.mem.eql(u8, value, "managed-rules")) return .managed;
        if (std.mem.eql(u8, value, "search")) return .search;
        if (std.mem.eql(u8, value, "stats") or std.mem.eql(u8, value, "dashboard-stats")) return .stats;
        if (std.mem.eql(u8, value, "tree") or std.mem.eql(u8, value, "folder-tree")) return .tree;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "rule") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .rule;
        return null;
    }

    pub fn commandName(self: CloudforceOneRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .managed => "managed",
            .search => "search",
            .stats => "stats",
            .tree => "tree",
            .rule => "show",
        };
    }

    pub fn label(self: CloudforceOneRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "cloudforce-one-rules",
            .managed => "cloudforce-one-managed-rules",
            .search => "cloudforce-one-rule-search",
            .stats => "cloudforce-one-rule-stats",
            .tree => "cloudforce-one-rule-tree",
            .rule => "cloudforce-one-rule",
        };
    }

    pub fn operationId(self: CloudforceOneRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "cloudforce-one-list-rules",
            .managed => "cloudforce-one-get-managed-rules",
            .search => "cloudforce-one-search-rules",
            .stats => "cloudforce-one-get-rule-stats",
            .tree => "cloudforce-one-get-rule-tree",
            .rule => "cloudforce-one-get-rule",
        };
    }

    pub fn summary(self: CloudforceOneRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List Cloudforce One rules",
            .managed => "Get Cloudforce One managed rules",
            .search => "Search Cloudforce One rules",
            .stats => "Get Cloudforce One rule dashboard stats",
            .tree => "Get Cloudforce One rule folder tree structure",
            .rule => "Get a Cloudforce One rule",
        };
    }

    pub fn requiresRuleId(self: CloudforceOneRuleReadEndpoint) bool {
        return self == .rule;
    }

    pub fn requiresQuery(self: CloudforceOneRuleReadEndpoint) bool {
        return self == .search;
    }

    pub fn allowsListFilters(self: CloudforceOneRuleReadEndpoint) bool {
        return self == .list or self == .search;
    }
};

pub const CloudforceOneRuleReadArgs = struct {
    rule_id: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    recursive: ?[]const u8 = null,
    search_filter: ?[]const u8 = null,
    is_public: ?[]const u8 = null,
    limit: ?[]const u8 = null,
    offset: ?[]const u8 = null,
    query: ?[]const u8 = null,
    mode: ?[]const u8 = null,
    language: ?[]const u8 = null,
};

pub const CloudforceOneRuleMutationEndpoint = enum {
    create,
    update,
    delete_rule,
    delete_all,
    validate,

    pub fn parse(value: []const u8) ?CloudforceOneRuleMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "put")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-rule") or std.mem.eql(u8, value, "remove")) return .delete_rule;
        if (std.mem.eql(u8, value, "delete-all") or std.mem.eql(u8, value, "clear")) return .delete_all;
        if (std.mem.eql(u8, value, "validate")) return .validate;
        return null;
    }

    pub fn commandName(self: CloudforceOneRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_rule => "delete",
            .delete_all => "delete-all",
            .validate => "validate",
        };
    }

    pub fn method(self: CloudforceOneRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .validate => "POST",
            .update => "PUT",
            .delete_rule, .delete_all => "DELETE",
        };
    }

    pub fn operationId(self: CloudforceOneRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "cloudforce-one-create-rule",
            .update => "cloudforce-one-update-rule",
            .delete_rule => "cloudforce-one-delete-rule",
            .delete_all => "cloudforce-one-delete-all-rules",
            .validate => "cloudforce-one-validate-rule",
        };
    }

    pub fn summary(self: CloudforceOneRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create a Cloudforce One rule",
            .update => "Update a Cloudforce One rule",
            .delete_rule => "Delete a Cloudforce One rule",
            .delete_all => "Delete all Cloudforce One rules",
            .validate => "Validate a Cloudforce One rule with context",
        };
    }

    pub fn requestBodySchemaRef(self: CloudforceOneRuleMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/cloudforce-one_CreateRule",
            .update => "#/components/schemas/cloudforce-one_UpdateRule",
            .validate => "object",
            .delete_rule, .delete_all => null,
        };
    }

    pub fn requiresRuleId(self: CloudforceOneRuleMutationEndpoint) bool {
        return self == .update or self == .delete_rule;
    }
};

pub const CloudforceOneRuleMutationArgs = struct {
    account_id: []const u8,
    rule_id: ?[]const u8 = null,
};

pub const IpAccessRuleScope = enum {
    user,
    account,
    zone,

    pub fn parse(value: []const u8) ?IpAccessRuleScope {
        if (std.mem.eql(u8, value, "user")) return .user;
        if (std.mem.eql(u8, value, "account") or std.mem.eql(u8, value, "accounts")) return .account;
        if (std.mem.eql(u8, value, "zone") or std.mem.eql(u8, value, "zones")) return .zone;
        return null;
    }

    pub fn commandName(self: IpAccessRuleScope) []const u8 {
        return switch (self) {
            .user => "user",
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn group(self: IpAccessRuleScope) []const u8 {
        return switch (self) {
            .user => "IP Access rules for a user",
            .account => "IP Access rules for an account",
            .zone => "IP Access rules for a zone",
        };
    }

    pub fn idLabel(self: IpAccessRuleScope) []const u8 {
        return switch (self) {
            .user => "user",
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn usesScopeId(self: IpAccessRuleScope) bool {
        return self != .user;
    }

    pub fn basePath(self: IpAccessRuleScope) []const u8 {
        return switch (self) {
            .user => user_path,
            .account => accounts_path,
            .zone => zones_path,
        };
    }
};

pub const IpAccessRuleReadEndpoint = enum {
    list,
    rule,

    pub fn parse(value: []const u8) ?IpAccessRuleReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "rules")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "rule") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .rule;
        return null;
    }

    pub fn commandName(self: IpAccessRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .rule => "show",
        };
    }

    pub fn label(self: IpAccessRuleReadEndpoint, scope: IpAccessRuleScope) []const u8 {
        return switch (scope) {
            .user => switch (self) {
                .list => "user-ip-access-rules",
                .rule => "user-ip-access-rule",
            },
            .account => switch (self) {
                .list => "account-ip-access-rules",
                .rule => "account-ip-access-rule",
            },
            .zone => switch (self) {
                .list => "zone-ip-access-rules",
                .rule => "zone-ip-access-rule",
            },
        };
    }

    pub fn operationId(self: IpAccessRuleReadEndpoint, scope: IpAccessRuleScope) ![]const u8 {
        return switch (scope) {
            .user => switch (self) {
                .list => "ip-access-rules-for-a-user-list-ip-access-rules",
                .rule => "ip-access-rules-for-a-user-get-an-ip-access-rule",
            },
            .account => switch (self) {
                .list => "ip-access-rules-for-an-account-list-ip-access-rules",
                .rule => "ip-access-rules-for-an-account-get-an-ip-access-rule",
            },
            .zone => switch (self) {
                .list => "ip-access-rules-for-a-zone-list-ip-access-rules",
                .rule => return error.UnsupportedCloudflareIpAccessRuleEndpoint,
            },
        };
    }

    pub fn summary(self: IpAccessRuleReadEndpoint, scope: IpAccessRuleScope) ![]const u8 {
        return switch (scope) {
            .user => switch (self) {
                .list => "List user IP Access rules",
                .rule => "Get a user IP Access rule",
            },
            .account => switch (self) {
                .list => "List account IP Access rules",
                .rule => "Get an account IP Access rule",
            },
            .zone => switch (self) {
                .list => "List zone IP Access rules",
                .rule => return error.UnsupportedCloudflareIpAccessRuleEndpoint,
            },
        };
    }

    pub fn requiresRuleId(self: IpAccessRuleReadEndpoint) bool {
        return self == .rule;
    }

    pub fn supports(self: IpAccessRuleReadEndpoint, scope: IpAccessRuleScope) bool {
        return self == .list or scope != .zone;
    }
};

pub const IpAccessRuleListArgs = struct {
    rule_id: ?[]const u8 = null,
    mode: ?[]const u8 = null,
    configuration_target: ?[]const u8 = null,
    configuration_value: ?[]const u8 = null,
    notes: ?[]const u8 = null,
    match: ?[]const u8 = null,
    page: ?[]const u8 = null,
    per_page: ?[]const u8 = null,
    order: ?[]const u8 = null,
    direction: ?[]const u8 = null,
};

pub const IpAccessRuleMutationEndpoint = enum {
    create,
    update,
    delete_rule,

    pub fn parse(value: []const u8) ?IpAccessRuleMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "patch")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-rule") or std.mem.eql(u8, value, "remove")) return .delete_rule;
        return null;
    }

    pub fn commandName(self: IpAccessRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_rule => "delete",
        };
    }

    pub fn method(self: IpAccessRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PATCH",
            .delete_rule => "DELETE",
        };
    }

    pub fn operationId(self: IpAccessRuleMutationEndpoint, scope: IpAccessRuleScope) []const u8 {
        return switch (scope) {
            .user => switch (self) {
                .create => "ip-access-rules-for-a-user-create-an-ip-access-rule",
                .update => "ip-access-rules-for-a-user-update-an-ip-access-rule",
                .delete_rule => "ip-access-rules-for-a-user-delete-an-ip-access-rule",
            },
            .account => switch (self) {
                .create => "ip-access-rules-for-an-account-create-an-ip-access-rule",
                .update => "ip-access-rules-for-an-account-update-an-ip-access-rule",
                .delete_rule => "ip-access-rules-for-an-account-delete-an-ip-access-rule",
            },
            .zone => switch (self) {
                .create => "ip-access-rules-for-a-zone-create-an-ip-access-rule",
                .update => "ip-access-rules-for-a-zone-update-an-ip-access-rule",
                .delete_rule => "ip-access-rules-for-a-zone-delete-an-ip-access-rule",
            },
        };
    }

    pub fn summary(self: IpAccessRuleMutationEndpoint, scope: IpAccessRuleScope) []const u8 {
        return switch (self) {
            .create => switch (scope) {
                .user => "Create a user IP Access rule",
                .account => "Create an account IP Access rule",
                .zone => "Create a zone IP Access rule",
            },
            .update => switch (scope) {
                .user => "Update a user IP Access rule",
                .account => "Update an account IP Access rule",
                .zone => "Update a zone IP Access rule",
            },
            .delete_rule => switch (scope) {
                .user => "Delete a user IP Access rule",
                .account => "Delete an account IP Access rule",
                .zone => "Delete a zone IP Access rule",
            },
        };
    }

    pub fn requestBodySchemaRef(self: IpAccessRuleMutationEndpoint, scope: IpAccessRuleScope) ?[]const u8 {
        return switch (self) {
            .create => "object",
            .update => switch (scope) {
                .account => "#/components/schemas/firewall_schemas-rule",
                .user, .zone => "object",
            },
            .delete_rule => if (scope == .zone) "object" else null,
        };
    }

    pub fn requiresRuleId(self: IpAccessRuleMutationEndpoint) bool {
        return self == .update or self == .delete_rule;
    }
};

pub const IpAccessRuleMutationArgs = struct {
    scope: IpAccessRuleScope,
    scope_id: ?[]const u8 = null,
    rule_id: ?[]const u8 = null,
};

pub const ZoneLegacyRuleResource = enum {
    page_rules,
    ua_rules,
    zone_lockdown,

    pub fn parse(value: []const u8) ?ZoneLegacyRuleResource {
        if (std.mem.eql(u8, value, "page-rules") or std.mem.eql(u8, value, "page-rule") or std.mem.eql(u8, value, "pagerules")) return .page_rules;
        if (std.mem.eql(u8, value, "ua-rules") or std.mem.eql(u8, value, "ua-rule") or std.mem.eql(u8, value, "user-agent-rules") or std.mem.eql(u8, value, "user-agent-blocking")) return .ua_rules;
        if (std.mem.eql(u8, value, "zone-lockdown") or std.mem.eql(u8, value, "lockdowns") or std.mem.eql(u8, value, "lockdown")) return .zone_lockdown;
        return null;
    }

    pub fn commandName(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "page-rules",
            .ua_rules => "ua-rules",
            .zone_lockdown => "zone-lockdown",
        };
    }

    pub fn group(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "Page Rules",
            .ua_rules => "User Agent Blocking rules",
            .zone_lockdown => "Zone Lockdown",
        };
    }

    pub fn collectionSuffix(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "pagerules",
            .ua_rules => "firewall/ua_rules",
            .zone_lockdown => "firewall/lockdowns",
        };
    }

    pub fn idLabel(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "pagerule",
            .ua_rules => "ua rule",
            .zone_lockdown => "lockdown",
        };
    }

    pub fn listLabel(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "page-rules",
            .ua_rules => "ua-rules",
            .zone_lockdown => "zone-lockdown-rules",
        };
    }

    pub fn detailLabel(self: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .page_rules => "page-rule",
            .ua_rules => "ua-rule",
            .zone_lockdown => "zone-lockdown-rule",
        };
    }
};

pub const ZoneLegacyRuleReadEndpoint = enum {
    list,
    rule,

    pub fn parse(value: []const u8) ?ZoneLegacyRuleReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "rules")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "rule") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .rule;
        return null;
    }

    pub fn commandName(self: ZoneLegacyRuleReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .rule => "show",
        };
    }

    pub fn label(self: ZoneLegacyRuleReadEndpoint, resource: ZoneLegacyRuleResource) []const u8 {
        return switch (self) {
            .list => resource.listLabel(),
            .rule => resource.detailLabel(),
        };
    }

    pub fn operationId(self: ZoneLegacyRuleReadEndpoint, resource: ZoneLegacyRuleResource) []const u8 {
        return switch (resource) {
            .page_rules => switch (self) {
                .list => "page-rules-list-page-rules",
                .rule => "page-rules-get-a-page-rule",
            },
            .ua_rules => switch (self) {
                .list => "user-agent-blocking-rules-list-user-agent-blocking-rules",
                .rule => "user-agent-blocking-rules-get-a-user-agent-blocking-rule",
            },
            .zone_lockdown => switch (self) {
                .list => "zone-lockdown-list-zone-lockdown-rules",
                .rule => "zone-lockdown-get-a-zone-lockdown-rule",
            },
        };
    }

    pub fn summary(self: ZoneLegacyRuleReadEndpoint, resource: ZoneLegacyRuleResource) []const u8 {
        return switch (resource) {
            .page_rules => switch (self) {
                .list => "List Page Rules",
                .rule => "Get a Page Rule",
            },
            .ua_rules => switch (self) {
                .list => "List User Agent Blocking rules",
                .rule => "Get a User Agent Blocking rule",
            },
            .zone_lockdown => switch (self) {
                .list => "List Zone Lockdown rules",
                .rule => "Get a Zone Lockdown rule",
            },
        };
    }

    pub fn requiresRuleId(self: ZoneLegacyRuleReadEndpoint) bool {
        return self == .rule;
    }
};

pub const ZoneLegacyRuleMutationEndpoint = enum {
    create,
    update,
    edit,
    delete_rule,

    pub fn parse(value: []const u8) ?ZoneLegacyRuleMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "put")) return .update;
        if (std.mem.eql(u8, value, "edit") or std.mem.eql(u8, value, "patch")) return .edit;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-rule") or std.mem.eql(u8, value, "remove")) return .delete_rule;
        return null;
    }

    pub fn commandName(self: ZoneLegacyRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .edit => "edit",
            .delete_rule => "delete",
        };
    }

    pub fn supports(self: ZoneLegacyRuleMutationEndpoint, resource: ZoneLegacyRuleResource) bool {
        return self != .edit or resource == .page_rules;
    }

    pub fn method(self: ZoneLegacyRuleMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .edit => "PATCH",
            .delete_rule => "DELETE",
        };
    }

    pub fn operationId(self: ZoneLegacyRuleMutationEndpoint, resource: ZoneLegacyRuleResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareZoneLegacyRuleMutation;
        return switch (resource) {
            .page_rules => switch (self) {
                .create => "page-rules-create-a-page-rule",
                .update => "page-rules-update-a-page-rule",
                .edit => "page-rules-edit-a-page-rule",
                .delete_rule => "page-rules-delete-a-page-rule",
            },
            .ua_rules => switch (self) {
                .create => "user-agent-blocking-rules-create-a-user-agent-blocking-rule",
                .update => "user-agent-blocking-rules-update-a-user-agent-blocking-rule",
                .edit => unreachable,
                .delete_rule => "user-agent-blocking-rules-delete-a-user-agent-blocking-rule",
            },
            .zone_lockdown => switch (self) {
                .create => "zone-lockdown-create-a-zone-lockdown-rule",
                .update => "zone-lockdown-update-a-zone-lockdown-rule",
                .edit => unreachable,
                .delete_rule => "zone-lockdown-delete-a-zone-lockdown-rule",
            },
        };
    }

    pub fn summary(self: ZoneLegacyRuleMutationEndpoint, resource: ZoneLegacyRuleResource) ![]const u8 {
        if (!self.supports(resource)) return error.UnsupportedCloudflareZoneLegacyRuleMutation;
        return switch (resource) {
            .page_rules => switch (self) {
                .create => "Create a Page Rule object",
                .update => "Update a Page Rule object",
                .edit => "Edit a Page Rule object",
                .delete_rule => "Delete a Page Rule",
            },
            .ua_rules => switch (self) {
                .create => "Create a User Agent Blocking rule object",
                .update => "Update a User Agent Blocking rule object",
                .edit => unreachable,
                .delete_rule => "Delete a User Agent Blocking rule",
            },
            .zone_lockdown => switch (self) {
                .create => "Create a Zone Lockdown rule object",
                .update => "Update a Zone Lockdown rule object",
                .edit => unreachable,
                .delete_rule => "Delete a Zone Lockdown rule",
            },
        };
    }

    pub fn requestBodySchemaRef(self: ZoneLegacyRuleMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create, .update, .edit => "object",
            .delete_rule => null,
        };
    }

    pub fn requiresRuleId(self: ZoneLegacyRuleMutationEndpoint) bool {
        return self == .update or self == .edit or self == .delete_rule;
    }
};

pub const ZoneLegacyRuleMutationArgs = struct {
    resource: ZoneLegacyRuleResource,
    zone_id: []const u8,
    rule_id: ?[]const u8 = null,
};

pub const PageShieldReadEndpoint = enum {
    settings,
    policies,
    policy,
    connections,
    connection,
    scripts,
    script,
    cookies,
    cookie,

    pub fn parse(value: []const u8) ?PageShieldReadEndpoint {
        if (std.mem.eql(u8, value, "settings") or std.mem.eql(u8, value, "setting")) return .settings;
        if (std.mem.eql(u8, value, "policies") or std.mem.eql(u8, value, "policy-list")) return .policies;
        if (std.mem.eql(u8, value, "policy") or std.mem.eql(u8, value, "policy-show")) return .policy;
        if (std.mem.eql(u8, value, "connections") or std.mem.eql(u8, value, "connection-list")) return .connections;
        if (std.mem.eql(u8, value, "connection") or std.mem.eql(u8, value, "connection-show")) return .connection;
        if (std.mem.eql(u8, value, "scripts") or std.mem.eql(u8, value, "script-list")) return .scripts;
        if (std.mem.eql(u8, value, "script") or std.mem.eql(u8, value, "script-show")) return .script;
        if (std.mem.eql(u8, value, "cookies") or std.mem.eql(u8, value, "cookie-list")) return .cookies;
        if (std.mem.eql(u8, value, "cookie") or std.mem.eql(u8, value, "cookie-show")) return .cookie;
        return null;
    }

    pub fn commandName(self: PageShieldReadEndpoint) []const u8 {
        return switch (self) {
            .settings => "settings",
            .policies => "policies",
            .policy => "policy",
            .connections => "connections",
            .connection => "connection",
            .scripts => "scripts",
            .script => "script",
            .cookies => "cookies",
            .cookie => "cookie",
        };
    }

    pub fn label(self: PageShieldReadEndpoint) []const u8 {
        return switch (self) {
            .settings => "page-shield-settings",
            .policies => "page-shield-policies",
            .policy => "page-shield-policy",
            .connections => "page-shield-connections",
            .connection => "page-shield-connection",
            .scripts => "page-shield-scripts",
            .script => "page-shield-script",
            .cookies => "page-shield-cookies",
            .cookie => "page-shield-cookie",
        };
    }

    pub fn collectionName(self: PageShieldReadEndpoint) ?[]const u8 {
        return switch (self) {
            .settings => null,
            .policies, .policy => "policies",
            .connections, .connection => "connections",
            .scripts, .script => "scripts",
            .cookies, .cookie => "cookies",
        };
    }

    pub fn operationId(self: PageShieldReadEndpoint) []const u8 {
        return switch (self) {
            .settings => "page-shield-get-settings",
            .policies => "page-shield-list-policies",
            .policy => "page-shield-get-policy",
            .connections => "page-shield-list-connections",
            .connection => "page-shield-get-connection",
            .scripts => "page-shield-list-scripts",
            .script => "page-shield-get-script",
            .cookies => "page-shield-list-cookies",
            .cookie => "page-shield-get-cookie",
        };
    }

    pub fn summary(self: PageShieldReadEndpoint) []const u8 {
        return switch (self) {
            .settings => "Get Page Shield settings",
            .policies => "List Page Shield policies",
            .policy => "Get a Page Shield policy",
            .connections => "List Page Shield connections",
            .connection => "Get a Page Shield connection",
            .scripts => "List Page Shield scripts",
            .script => "Get a Page Shield script",
            .cookies => "List Page Shield Cookies",
            .cookie => "Get a Page Shield cookie",
        };
    }

    pub fn requiresResourceId(self: PageShieldReadEndpoint) bool {
        return switch (self) {
            .policy, .connection, .script, .cookie => true,
            .settings, .policies, .connections, .scripts, .cookies => false,
        };
    }

    pub fn acceptsFilters(self: PageShieldReadEndpoint) bool {
        return switch (self) {
            .connections, .scripts, .cookies => true,
            .settings, .policies, .policy, .connection, .script, .cookie => false,
        };
    }

    pub fn idLabel(self: PageShieldReadEndpoint) []const u8 {
        return switch (self) {
            .policy => "policy",
            .connection => "connection",
            .script => "script",
            .cookie => "cookie",
            else => "resource",
        };
    }
};

pub const PageShieldReadArgs = struct {
    resource_id: ?[]const u8 = null,
    exclude_urls: ?[]const u8 = null,
    urls: ?[]const u8 = null,
    hosts: ?[]const u8 = null,
    page: ?[]const u8 = null,
    per_page: ?[]const u8 = null,
    order_by: ?[]const u8 = null,
    direction: ?[]const u8 = null,
    prioritize_malicious: ?[]const u8 = null,
    exclude_cdn_cgi: ?[]const u8 = null,
    exclude_duplicates: ?[]const u8 = null,
    status: ?[]const u8 = null,
    page_url: ?[]const u8 = null,
    export_format: ?[]const u8 = null,
    name: ?[]const u8 = null,
    secure: ?[]const u8 = null,
    http_only: ?[]const u8 = null,
    same_site: ?[]const u8 = null,
    type_filter: ?[]const u8 = null,
    path_filter: ?[]const u8 = null,
    domain: ?[]const u8 = null,
};

pub const PageShieldMutationEndpoint = enum {
    update_settings,
    create_policy,
    update_policy,
    delete_policy,

    pub fn parse(value: []const u8) ?PageShieldMutationEndpoint {
        if (std.mem.eql(u8, value, "update-settings") or std.mem.eql(u8, value, "settings-update") or std.mem.eql(u8, value, "settings")) return .update_settings;
        if (std.mem.eql(u8, value, "create-policy") or std.mem.eql(u8, value, "policy-create") or std.mem.eql(u8, value, "create")) return .create_policy;
        if (std.mem.eql(u8, value, "update-policy") or std.mem.eql(u8, value, "policy-update") or std.mem.eql(u8, value, "update")) return .update_policy;
        if (std.mem.eql(u8, value, "delete-policy") or std.mem.eql(u8, value, "policy-delete") or std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_policy;
        return null;
    }

    pub fn commandName(self: PageShieldMutationEndpoint) []const u8 {
        return switch (self) {
            .update_settings => "update-settings",
            .create_policy => "create-policy",
            .update_policy => "update-policy",
            .delete_policy => "delete-policy",
        };
    }

    pub fn method(self: PageShieldMutationEndpoint) []const u8 {
        return switch (self) {
            .update_settings, .update_policy => "PUT",
            .create_policy => "POST",
            .delete_policy => "DELETE",
        };
    }

    pub fn operationId(self: PageShieldMutationEndpoint) []const u8 {
        return switch (self) {
            .update_settings => "page-shield-update-settings",
            .create_policy => "page-shield-create-policy",
            .update_policy => "page-shield-update-policy",
            .delete_policy => "page-shield-delete-policy",
        };
    }

    pub fn summary(self: PageShieldMutationEndpoint) []const u8 {
        return switch (self) {
            .update_settings => "Update Page Shield settings",
            .create_policy => "Create a Page Shield policy",
            .update_policy => "Update a Page Shield policy",
            .delete_policy => "Delete a Page Shield policy",
        };
    }

    pub fn requestBodySchemaRef(self: PageShieldMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .update_settings => "inline:{enabled?:bool,use_cloudflare_reporting_endpoint?:bool,use_connection_url_path?:bool}",
            .create_policy => "#/components/schemas/page-shield_policy",
            .update_policy => "inline:{action?:string,description?:string,enabled?:bool,expression?:string,value?:string}",
            .delete_policy => null,
        };
    }

    pub fn requiresPolicyId(self: PageShieldMutationEndpoint) bool {
        return self == .update_policy or self == .delete_policy;
    }
};

pub const PageShieldMutationArgs = struct {
    zone_id: []const u8,
    policy_id: ?[]const u8 = null,
};

pub const CustomPageScope = enum {
    account,
    zone,

    pub fn parse(value: []const u8) ?CustomPageScope {
        if (std.mem.eql(u8, value, "account") or std.mem.eql(u8, value, "accounts")) return .account;
        if (std.mem.eql(u8, value, "zone") or std.mem.eql(u8, value, "zones")) return .zone;
        return null;
    }

    pub fn commandName(self: CustomPageScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn idLabel(self: CustomPageScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn basePath(self: CustomPageScope) []const u8 {
        return switch (self) {
            .account => accounts_path,
            .zone => zones_path,
        };
    }
};

pub const CustomPageResource = enum {
    pages,
    assets,

    pub fn parse(value: []const u8) ?CustomPageResource {
        if (std.mem.eql(u8, value, "pages") or std.mem.eql(u8, value, "page") or std.mem.eql(u8, value, "custom-pages")) return .pages;
        if (std.mem.eql(u8, value, "assets") or std.mem.eql(u8, value, "asset") or std.mem.eql(u8, value, "custom-assets")) return .assets;
        return null;
    }

    pub fn commandName(self: CustomPageResource) []const u8 {
        return switch (self) {
            .pages => "pages",
            .assets => "assets",
        };
    }

    pub fn idLabel(self: CustomPageResource) []const u8 {
        return switch (self) {
            .pages => "custom page",
            .assets => "asset",
        };
    }

    pub fn pathSuffix(self: CustomPageResource) []const u8 {
        return switch (self) {
            .pages => "custom_pages",
            .assets => "custom_pages/assets",
        };
    }
};

pub const CustomPageReadEndpoint = enum {
    list,
    details,

    pub fn parse(value: []const u8) ?CustomPageReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "all")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .details;
        return null;
    }

    pub fn commandName(self: CustomPageReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
        };
    }

    pub fn label(self: CustomPageReadEndpoint, scope: CustomPageScope, resource: CustomPageResource) []const u8 {
        return switch (scope) {
            .account => switch (resource) {
                .pages => if (self == .list) "account-custom-pages" else "account-custom-page",
                .assets => if (self == .list) "account-custom-assets" else "account-custom-asset",
            },
            .zone => switch (resource) {
                .pages => if (self == .list) "zone-custom-pages" else "zone-custom-page",
                .assets => if (self == .list) "zone-custom-assets" else "zone-custom-asset",
            },
        };
    }

    pub fn operationId(self: CustomPageReadEndpoint, scope: CustomPageScope, resource: CustomPageResource) []const u8 {
        return switch (scope) {
            .account => switch (resource) {
                .pages => switch (self) {
                    .list => "custom-pages-for-an-account-list-custom-pages",
                    .details => "custom-pages-for-an-account-get-a-custom-page",
                },
                .assets => switch (self) {
                    .list => "custom-assets-for-an-account-list-custom-assets",
                    .details => "custom-assets-for-an-account-get-a-custom-asset",
                },
            },
            .zone => switch (resource) {
                .pages => switch (self) {
                    .list => "custom-pages-for-a-zone-list-custom-pages",
                    .details => "custom-pages-for-a-zone-get-a-custom-page",
                },
                .assets => switch (self) {
                    .list => "custom-assets-for-a-zone-list-custom-assets",
                    .details => "custom-assets-for-a-zone-get-a-custom-asset",
                },
            },
        };
    }

    pub fn summary(self: CustomPageReadEndpoint, scope: CustomPageScope, resource: CustomPageResource) []const u8 {
        return switch (resource) {
            .pages => switch (self) {
                .list => if (scope == .account) "List account custom pages" else "List zone custom pages",
                .details => if (scope == .account) "Get an account custom page" else "Get a zone custom page",
            },
            .assets => switch (self) {
                .list => if (scope == .account) "List account custom assets" else "List zone custom assets",
                .details => if (scope == .account) "Get an account custom asset" else "Get a zone custom asset",
            },
        };
    }

    pub fn requiresResourceId(self: CustomPageReadEndpoint) bool {
        return self == .details;
    }
};

pub const CustomPageReadArgs = struct {
    resource_id: ?[]const u8 = null,
};

pub const CustomPageMutationEndpoint = enum {
    update_page,
    create_preview_token,
    create_asset,
    update_asset,
    delete_asset,

    pub fn parse(value: []const u8) ?CustomPageMutationEndpoint {
        if (std.mem.eql(u8, value, "update-page") or std.mem.eql(u8, value, "page-update")) return .update_page;
        if (std.mem.eql(u8, value, "create-preview-token") or std.mem.eql(u8, value, "preview-token")) return .create_preview_token;
        if (std.mem.eql(u8, value, "create-asset") or std.mem.eql(u8, value, "asset-create") or std.mem.eql(u8, value, "create")) return .create_asset;
        if (std.mem.eql(u8, value, "update-asset") or std.mem.eql(u8, value, "asset-update") or std.mem.eql(u8, value, "update")) return .update_asset;
        if (std.mem.eql(u8, value, "delete-asset") or std.mem.eql(u8, value, "asset-delete") or std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_asset;
        return null;
    }

    pub fn commandName(self: CustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .update_page => "update-page",
            .create_preview_token => "create-preview-token",
            .create_asset => "create-asset",
            .update_asset => "update-asset",
            .delete_asset => "delete-asset",
        };
    }

    pub fn resource(self: CustomPageMutationEndpoint) CustomPageResource {
        return switch (self) {
            .update_page, .create_preview_token => .pages,
            .create_asset, .update_asset, .delete_asset => .assets,
        };
    }

    pub fn method(self: CustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .create_preview_token, .create_asset => "POST",
            .update_page, .update_asset => "PUT",
            .delete_asset => "DELETE",
        };
    }

    pub fn operationId(self: CustomPageMutationEndpoint, scope: CustomPageScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .update_page => "custom-pages-for-an-account-update-a-custom-page",
                .create_preview_token => "custom-pages-for-an-account-create-preview-token",
                .create_asset => "custom-assets-for-an-account-create-a-custom-asset",
                .update_asset => "custom-assets-for-an-account-update-a-custom-asset",
                .delete_asset => "custom-assets-for-an-account-delete-a-custom-asset",
            },
            .zone => switch (self) {
                .update_page => "custom-pages-for-a-zone-update-a-custom-page",
                .create_preview_token => "custom-pages-for-a-zone-create-preview-token",
                .create_asset => "custom-assets-for-a-zone-create-a-custom-asset",
                .update_asset => "custom-assets-for-a-zone-update-a-custom-asset",
                .delete_asset => "custom-assets-for-a-zone-delete-a-custom-asset",
            },
        };
    }

    pub fn summary(self: CustomPageMutationEndpoint, scope: CustomPageScope) []const u8 {
        return switch (self) {
            .update_page => if (scope == .account) "Update an account custom page" else "Update a zone custom page",
            .create_preview_token => if (scope == .account) "Create an account custom page preview token" else "Create a zone custom page preview token",
            .create_asset => if (scope == .account) "Create an account custom asset" else "Create a zone custom asset",
            .update_asset => if (scope == .account) "Update an account custom asset" else "Update a zone custom asset",
            .delete_asset => if (scope == .account) "Delete an account custom asset" else "Delete a zone custom asset",
        };
    }

    pub fn requestBodySchemaRef(self: CustomPageMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .update_page => "object",
            .create_preview_token => "#/components/schemas/custom-pages_preview_request",
            .create_asset, .update_asset => "multipart/form-data",
            .delete_asset => null,
        };
    }

    pub fn requiresResourceId(self: CustomPageMutationEndpoint) bool {
        return switch (self) {
            .update_page, .update_asset, .delete_asset => true,
            .create_preview_token, .create_asset => false,
        };
    }
};

pub const CustomPageMutationArgs = struct {
    scope: CustomPageScope,
    scope_id: []const u8,
    resource_id: ?[]const u8 = null,
};

pub const AccessCustomPageReadEndpoint = enum {
    list,
    details,

    pub fn parse(value: []const u8) ?AccessCustomPageReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "pages")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "page") or std.mem.eql(u8, value, "details")) return .details;
        return null;
    }

    pub fn commandName(self: AccessCustomPageReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .details => "show",
        };
    }

    pub fn label(self: AccessCustomPageReadEndpoint) []const u8 {
        return switch (self) {
            .list => "access-custom-pages",
            .details => "access-custom-page",
        };
    }

    pub fn operationId(self: AccessCustomPageReadEndpoint) []const u8 {
        return switch (self) {
            .list => "access-custom-pages-list-custom-pages",
            .details => "access-custom-pages-get-a-custom-page",
        };
    }

    pub fn summary(self: AccessCustomPageReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List Access custom pages",
            .details => "Get an Access custom page",
        };
    }

    pub fn requiresPageId(self: AccessCustomPageReadEndpoint) bool {
        return self == .details;
    }
};

pub const AccessCustomPageMutationEndpoint = enum {
    create,
    update,
    delete_page,

    pub fn parse(value: []const u8) ?AccessCustomPageMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "add")) return .create;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "put")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_page;
        return null;
    }

    pub fn commandName(self: AccessCustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete_page => "delete",
        };
    }

    pub fn method(self: AccessCustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .update => "PUT",
            .delete_page => "DELETE",
        };
    }

    pub fn operationId(self: AccessCustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "access-custom-pages-create-a-custom-page",
            .update => "access-custom-pages-update-a-custom-page",
            .delete_page => "access-custom-pages-delete-a-custom-page",
        };
    }

    pub fn summary(self: AccessCustomPageMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create an Access custom page",
            .update => "Update an Access custom page",
            .delete_page => "Delete an Access custom page",
        };
    }

    pub fn requestBodySchemaRef(self: AccessCustomPageMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create, .update => "#/components/schemas/access_custom_page",
            .delete_page => null,
        };
    }

    pub fn requiresPageId(self: AccessCustomPageMutationEndpoint) bool {
        return self == .update or self == .delete_page;
    }
};

pub const AccessCustomPageMutationArgs = struct {
    account_id: []const u8,
    page_id: ?[]const u8 = null,
};

pub const AccessScope = enum {
    account,
    zone,

    pub fn parse(value: []const u8) ?AccessScope {
        if (std.mem.eql(u8, value, "account") or std.mem.eql(u8, value, "accounts")) return .account;
        if (std.mem.eql(u8, value, "zone") or std.mem.eql(u8, value, "zones")) return .zone;
        return null;
    }

    pub fn commandName(self: AccessScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn idLabel(self: AccessScope) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn basePath(self: AccessScope) []const u8 {
        return switch (self) {
            .account => accounts_path,
            .zone => zones_path,
        };
    }
};

pub const AccessReadEndpoint = enum {
    applications_list,
    application_details,
    application_policy_checks,
    application_policies_list,
    application_policy_details,
    groups_list,
    group_details,
    identity_providers_list,
    identity_provider_details,
    identity_provider_scim_groups,
    identity_provider_scim_users,
    service_tokens_list,
    service_token_details,
    reusable_policies_list,
    reusable_policy_details,
    tags_list,
    tag_details,
    authenticator_device_aaguids,
    idp_federation_grants_list,
    idp_federation_grant_details,
    saml_certificate_sets_list,
    saml_certificate_set_details,
    saml_certificate_pem,
    scim_update_logs,
    keys,
    authentication_logs,
    policy_test,
    policy_test_users,
    mtls_certificates_list,
    mtls_certificate_details,
    mtls_settings,
    ca_list,
    ca_details,

    pub fn parse(value: []const u8) ?AccessReadEndpoint {
        if (std.mem.eql(u8, value, "applications") or std.mem.eql(u8, value, "apps")) return .applications_list;
        if (std.mem.eql(u8, value, "application") or std.mem.eql(u8, value, "app")) return .application_details;
        if (std.mem.eql(u8, value, "application-policy-checks") or std.mem.eql(u8, value, "app-policy-checks") or std.mem.eql(u8, value, "user-policy-checks")) return .application_policy_checks;
        if (std.mem.eql(u8, value, "application-policies") or std.mem.eql(u8, value, "app-policies") or std.mem.eql(u8, value, "policies")) return .application_policies_list;
        if (std.mem.eql(u8, value, "application-policy") or std.mem.eql(u8, value, "app-policy") or std.mem.eql(u8, value, "policy")) return .application_policy_details;
        if (std.mem.eql(u8, value, "groups")) return .groups_list;
        if (std.mem.eql(u8, value, "group")) return .group_details;
        if (std.mem.eql(u8, value, "identity-providers") or std.mem.eql(u8, value, "idps")) return .identity_providers_list;
        if (std.mem.eql(u8, value, "identity-provider") or std.mem.eql(u8, value, "idp")) return .identity_provider_details;
        if (std.mem.eql(u8, value, "idp-scim-groups") or std.mem.eql(u8, value, "scim-groups")) return .identity_provider_scim_groups;
        if (std.mem.eql(u8, value, "idp-scim-users") or std.mem.eql(u8, value, "scim-users")) return .identity_provider_scim_users;
        if (std.mem.eql(u8, value, "service-tokens")) return .service_tokens_list;
        if (std.mem.eql(u8, value, "service-token")) return .service_token_details;
        if (std.mem.eql(u8, value, "reusable-policies")) return .reusable_policies_list;
        if (std.mem.eql(u8, value, "reusable-policy")) return .reusable_policy_details;
        if (std.mem.eql(u8, value, "tags")) return .tags_list;
        if (std.mem.eql(u8, value, "tag")) return .tag_details;
        if (std.mem.eql(u8, value, "authenticator-aaguids") or std.mem.eql(u8, value, "aaguids")) return .authenticator_device_aaguids;
        if (std.mem.eql(u8, value, "idp-federation-grants") or std.mem.eql(u8, value, "federation-grants")) return .idp_federation_grants_list;
        if (std.mem.eql(u8, value, "idp-federation-grant") or std.mem.eql(u8, value, "federation-grant")) return .idp_federation_grant_details;
        if (std.mem.eql(u8, value, "saml-certificates") or std.mem.eql(u8, value, "saml-certificate-sets")) return .saml_certificate_sets_list;
        if (std.mem.eql(u8, value, "saml-certificate") or std.mem.eql(u8, value, "saml-certificate-set")) return .saml_certificate_set_details;
        if (std.mem.eql(u8, value, "saml-certificate-pem") or std.mem.eql(u8, value, "saml-pem")) return .saml_certificate_pem;
        if (std.mem.eql(u8, value, "scim-update-logs") or std.mem.eql(u8, value, "scim-logs")) return .scim_update_logs;
        if (std.mem.eql(u8, value, "keys") or std.mem.eql(u8, value, "key-config")) return .keys;
        if (std.mem.eql(u8, value, "authentication-logs") or std.mem.eql(u8, value, "auth-logs") or std.mem.eql(u8, value, "logs")) return .authentication_logs;
        if (std.mem.eql(u8, value, "policy-test")) return .policy_test;
        if (std.mem.eql(u8, value, "policy-test-users")) return .policy_test_users;
        if (std.mem.eql(u8, value, "mtls-certificates") or std.mem.eql(u8, value, "certificates")) return .mtls_certificates_list;
        if (std.mem.eql(u8, value, "mtls-certificate") or std.mem.eql(u8, value, "certificate")) return .mtls_certificate_details;
        if (std.mem.eql(u8, value, "mtls-settings") or std.mem.eql(u8, value, "certificate-settings")) return .mtls_settings;
        if (std.mem.eql(u8, value, "cas") or std.mem.eql(u8, value, "short-lived-cas")) return .ca_list;
        if (std.mem.eql(u8, value, "ca") or std.mem.eql(u8, value, "short-lived-ca")) return .ca_details;
        return null;
    }

    pub fn commandName(self: AccessReadEndpoint) []const u8 {
        return switch (self) {
            .applications_list => "applications",
            .application_details => "application",
            .application_policy_checks => "application-policy-checks",
            .application_policies_list => "application-policies",
            .application_policy_details => "application-policy",
            .groups_list => "groups",
            .group_details => "group",
            .identity_providers_list => "identity-providers",
            .identity_provider_details => "identity-provider",
            .identity_provider_scim_groups => "idp-scim-groups",
            .identity_provider_scim_users => "idp-scim-users",
            .service_tokens_list => "service-tokens",
            .service_token_details => "service-token",
            .reusable_policies_list => "reusable-policies",
            .reusable_policy_details => "reusable-policy",
            .tags_list => "tags",
            .tag_details => "tag",
            .authenticator_device_aaguids => "authenticator-aaguids",
            .idp_federation_grants_list => "idp-federation-grants",
            .idp_federation_grant_details => "idp-federation-grant",
            .saml_certificate_sets_list => "saml-certificates",
            .saml_certificate_set_details => "saml-certificate",
            .saml_certificate_pem => "saml-certificate-pem",
            .scim_update_logs => "scim-update-logs",
            .keys => "keys",
            .authentication_logs => "authentication-logs",
            .policy_test => "policy-test",
            .policy_test_users => "policy-test-users",
            .mtls_certificates_list => "mtls-certificates",
            .mtls_certificate_details => "mtls-certificate",
            .mtls_settings => "mtls-settings",
            .ca_list => "cas",
            .ca_details => "ca",
        };
    }

    pub fn supports(self: AccessReadEndpoint, scope: AccessScope) bool {
        return switch (self) {
            .identity_provider_scim_groups,
            .identity_provider_scim_users,
            .reusable_policies_list,
            .reusable_policy_details,
            .tags_list,
            .tag_details,
            .keys,
            .authentication_logs,
            .policy_test,
            .policy_test_users,
            .authenticator_device_aaguids,
            .idp_federation_grants_list,
            .idp_federation_grant_details,
            .saml_certificate_sets_list,
            .saml_certificate_set_details,
            .saml_certificate_pem,
            .scim_update_logs,
            => scope == .account,
            .mtls_certificates_list,
            .mtls_certificate_details,
            .mtls_settings,
            .ca_list,
            .ca_details,
            => true,
            else => true,
        };
    }

    pub fn group(self: AccessReadEndpoint, scope: AccessScope) []const u8 {
        return switch (self) {
            .applications_list, .application_details, .application_policy_checks => if (scope == .account) "Access applications" else "Zone-Level Access applications",
            .application_policies_list, .application_policy_details => if (scope == .account) "Access application-scoped policies" else "Zone-Level Access policies",
            .groups_list, .group_details => if (scope == .account) "Access groups" else "Zone-Level Access groups",
            .identity_providers_list, .identity_provider_details, .identity_provider_scim_groups, .identity_provider_scim_users => if (scope == .account) "Access identity providers" else "Zone-Level Access identity providers",
            .service_tokens_list, .service_token_details => if (scope == .account) "Access service tokens" else "Zone-Level Access service tokens",
            .reusable_policies_list, .reusable_policy_details => "Access reusable policies",
            .tags_list, .tag_details => "Access tags",
            .authenticator_device_aaguids => "Access Authenticator Device AAGUIDs",
            .idp_federation_grants_list, .idp_federation_grant_details => "Access IdP federation grants",
            .saml_certificate_sets_list, .saml_certificate_set_details, .saml_certificate_pem => "Access SAML encryption certificates",
            .scim_update_logs => "Access SCIM update logs",
            .keys => "Access key configuration",
            .authentication_logs => "Access authentication logs",
            .policy_test, .policy_test_users => "Access policy tester",
            .mtls_certificates_list, .mtls_certificate_details, .mtls_settings => if (scope == .account) "Access mTLS authentication" else "Zone-Level Access mTLS authentication",
            .ca_list, .ca_details => if (scope == .account) "Access short-lived certificate CAs" else "Zone-Level Access short-lived certificate CAs",
        };
    }

    pub fn label(self: AccessReadEndpoint, scope: AccessScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .applications_list => "access-account-applications",
                .application_details => "access-account-application",
                .application_policy_checks => "access-account-application-policy-checks",
                .application_policies_list => "access-account-application-policies",
                .application_policy_details => "access-account-application-policy",
                .groups_list => "access-account-groups",
                .group_details => "access-account-group",
                .identity_providers_list => "access-account-identity-providers",
                .identity_provider_details => "access-account-identity-provider",
                .identity_provider_scim_groups => "access-account-idp-scim-groups",
                .identity_provider_scim_users => "access-account-idp-scim-users",
                .service_tokens_list => "access-account-service-tokens",
                .service_token_details => "access-account-service-token",
                .reusable_policies_list => "access-account-reusable-policies",
                .reusable_policy_details => "access-account-reusable-policy",
                .tags_list => "access-account-tags",
                .tag_details => "access-account-tag",
                .authenticator_device_aaguids => "access-account-authenticator-aaguids",
                .idp_federation_grants_list => "access-account-idp-federation-grants",
                .idp_federation_grant_details => "access-account-idp-federation-grant",
                .saml_certificate_sets_list => "access-account-saml-certificates",
                .saml_certificate_set_details => "access-account-saml-certificate",
                .saml_certificate_pem => "access-account-saml-certificate-pem",
                .scim_update_logs => "access-account-scim-update-logs",
                .keys => "access-account-keys",
                .authentication_logs => "access-account-authentication-logs",
                .policy_test => "access-account-policy-test",
                .policy_test_users => "access-account-policy-test-users",
                .mtls_certificates_list => "access-account-mtls-certificates",
                .mtls_certificate_details => "access-account-mtls-certificate",
                .mtls_settings => "access-account-mtls-settings",
                .ca_list => "access-account-cas",
                .ca_details => "access-account-ca",
            },
            .zone => switch (self) {
                .applications_list => "access-zone-applications",
                .application_details => "access-zone-application",
                .application_policy_checks => "access-zone-application-policy-checks",
                .application_policies_list => "access-zone-application-policies",
                .application_policy_details => "access-zone-application-policy",
                .groups_list => "access-zone-groups",
                .group_details => "access-zone-group",
                .identity_providers_list => "access-zone-identity-providers",
                .identity_provider_details => "access-zone-identity-provider",
                .service_tokens_list => "access-zone-service-tokens",
                .service_token_details => "access-zone-service-token",
                .mtls_certificates_list => "access-zone-mtls-certificates",
                .mtls_certificate_details => "access-zone-mtls-certificate",
                .mtls_settings => "access-zone-mtls-settings",
                .ca_list => "access-zone-cas",
                .ca_details => "access-zone-ca",
                else => "access-zone-unsupported",
            },
        };
    }

    pub fn operationId(self: AccessReadEndpoint, scope: AccessScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .applications_list => "access-applications-list-access-applications",
                .application_details => "access-applications-get-an-access-application",
                .application_policy_checks => "access-applications-test-access-policies",
                .application_policies_list => "access-policies-list-access-app-policies",
                .application_policy_details => "access-policies-get-an-access-policy",
                .groups_list => "access-groups-list-access-groups",
                .group_details => "access-groups-get-an-access-group",
                .identity_providers_list => "access-identity-providers-list-access-identity-providers",
                .identity_provider_details => "access-identity-providers-get-an-access-identity-provider",
                .identity_provider_scim_groups => "access-identity-providers-list-scim-group-resources",
                .identity_provider_scim_users => "access-identity-providers-list-scim-user-resources",
                .service_tokens_list => "access-service-tokens-list-service-tokens",
                .service_token_details => "access-service-tokens-get-a-service-token",
                .reusable_policies_list => "access-policies-list-access-reusable-policies",
                .reusable_policy_details => "access-policies-get-an-access-reusable-policy",
                .tags_list => "access-tags-list-tags",
                .tag_details => "access-tags-get-a-tag",
                .authenticator_device_aaguids => "access-authenticator-device-aaguids-list",
                .idp_federation_grants_list => "access-idp-federation-grants-list",
                .idp_federation_grant_details => "access-idp-federation-grants-get",
                .saml_certificate_sets_list => "access-saml-certificates-list-certificate-sets",
                .saml_certificate_set_details => "access-saml-certificates-get-certificate-set",
                .saml_certificate_pem => "access-saml-certificates-get-pem",
                .scim_update_logs => "access-scim-update-logs-list-access-scim-update-logs",
                .keys => "access-key-configuration-get-the-access-key-configuration",
                .authentication_logs => "access-authentication-logs-get-access-authentication-logs",
                .policy_test => "access-policy-tests-get-an-update",
                .policy_test_users => "access-policy-tests-get-a-user-page",
                .mtls_certificates_list => "access-mtls-authentication-list-mtls-certificates",
                .mtls_certificate_details => "access-mtls-authentication-get-an-mtls-certificate",
                .mtls_settings => "access-mtls-authentication-list-mtls-certificates-hostname-settings",
                .ca_list => "access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
                .ca_details => "access-short-lived-certificate-c-as-get-a-short-lived-certificate-ca",
            },
            .zone => switch (self) {
                .applications_list => "zone-level-access-applications-list-access-applications",
                .application_details => "zone-level-access-applications-get-an-access-application",
                .application_policy_checks => "zone-level-access-applications-test-access-policies",
                .application_policies_list => "zone-level-access-policies-list-access-policies",
                .application_policy_details => "zone-level-access-policies-get-an-access-policy",
                .groups_list => "zone-level-access-groups-list-access-groups",
                .group_details => "zone-level-access-groups-get-an-access-group",
                .identity_providers_list => "zone-level-access-identity-providers-list-access-identity-providers",
                .identity_provider_details => "zone-level-access-identity-providers-get-an-access-identity-provider",
                .service_tokens_list => "zone-level-access-service-tokens-list-service-tokens",
                .service_token_details => "zone-level-access-service-tokens-get-a-service-token",
                .mtls_certificates_list => "zone-level-access-mtls-authentication-list-mtls-certificates",
                .mtls_certificate_details => "zone-level-access-mtls-authentication-get-an-mtls-certificate",
                .mtls_settings => "zone-level-access-mtls-authentication-list-mtls-certificates-hostname-settings",
                .ca_list => "zone-level-access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
                .ca_details => "zone-level-access-short-lived-certificate-c-as-get-a-short-lived-certificate-ca",
                else => "unsupported",
            },
        };
    }

    pub fn summary(self: AccessReadEndpoint, scope: AccessScope) []const u8 {
        return switch (self) {
            .applications_list => if (scope == .account) "List account Access applications" else "List zone Access applications",
            .application_details => if (scope == .account) "Get an account Access application" else "Get a zone Access application",
            .application_policy_checks => "Test Access policies",
            .application_policies_list => if (scope == .account) "List account Access application policies" else "List zone Access policies",
            .application_policy_details => if (scope == .account) "Get an account Access application policy" else "Get a zone Access policy",
            .groups_list => if (scope == .account) "List account Access groups" else "List zone Access groups",
            .group_details => if (scope == .account) "Get an account Access group" else "Get a zone Access group",
            .identity_providers_list => if (scope == .account) "List account Access identity providers" else "List zone Access identity providers",
            .identity_provider_details => if (scope == .account) "Get an account Access identity provider" else "Get a zone Access identity provider",
            .identity_provider_scim_groups => "List Access identity provider SCIM group resources",
            .identity_provider_scim_users => "List Access identity provider SCIM user resources",
            .service_tokens_list => if (scope == .account) "List account Access service tokens" else "List zone Access service tokens",
            .service_token_details => if (scope == .account) "Get an account Access service token" else "Get a zone Access service token",
            .reusable_policies_list => "List account Access reusable policies",
            .reusable_policy_details => "Get an account Access reusable policy",
            .tags_list => "List account Access tags",
            .tag_details => "Get an account Access tag",
            .authenticator_device_aaguids => "List account Access authenticator device AAGUIDs",
            .idp_federation_grants_list => "List account Access IdP federation grants",
            .idp_federation_grant_details => "Get an account Access IdP federation grant",
            .saml_certificate_sets_list => "List account Access SAML certificate sets",
            .saml_certificate_set_details => "Get an account Access SAML certificate set",
            .saml_certificate_pem => "Download an account Access SAML certificate PEM",
            .scim_update_logs => "List account Access SCIM update logs",
            .keys => "Get account Access key configuration",
            .authentication_logs => "Get account Access authentication logs",
            .policy_test => "Get account Access policy test status",
            .policy_test_users => "Get account Access policy test users",
            .mtls_certificates_list => if (scope == .account) "List account Access mTLS certificates" else "List zone Access mTLS certificates",
            .mtls_certificate_details => if (scope == .account) "Get an account Access mTLS certificate" else "Get a zone Access mTLS certificate",
            .mtls_settings => if (scope == .account) "List account Access mTLS hostname settings" else "List zone Access mTLS hostname settings",
            .ca_list => if (scope == .account) "List account Access short-lived certificate CAs" else "List zone Access short-lived certificate CAs",
            .ca_details => if (scope == .account) "Get an account Access short-lived certificate CA" else "Get a zone Access short-lived certificate CA",
        };
    }

    pub fn requiresAppId(self: AccessReadEndpoint) bool {
        return switch (self) {
            .application_details,
            .application_policy_checks,
            .application_policies_list,
            .application_policy_details,
            .ca_details,
            => true,
            else => false,
        };
    }

    pub fn requiresPolicyId(self: AccessReadEndpoint) bool {
        return self == .application_policy_details;
    }

    pub fn requiresResourceId(self: AccessReadEndpoint) bool {
        return self == .group_details or self == .idp_federation_grant_details or self == .saml_certificate_set_details or self == .saml_certificate_pem;
    }

    pub fn requiresIdentityProviderId(self: AccessReadEndpoint) bool {
        return switch (self) {
            .identity_provider_details,
            .identity_provider_scim_groups,
            .identity_provider_scim_users,
            => true,
            else => false,
        };
    }

    pub fn requiresServiceTokenId(self: AccessReadEndpoint) bool {
        return self == .service_token_details;
    }

    pub fn requiresTagName(self: AccessReadEndpoint) bool {
        return self == .tag_details;
    }

    pub fn requiresPolicyTestId(self: AccessReadEndpoint) bool {
        return self == .policy_test or self == .policy_test_users;
    }

    pub fn requiresCertificateId(self: AccessReadEndpoint) bool {
        return self == .mtls_certificate_details;
    }
};

pub const AccessReadArgs = struct {
    app_id: ?[]const u8 = null,
    policy_id: ?[]const u8 = null,
    resource_id: ?[]const u8 = null,
    identity_provider_id: ?[]const u8 = null,
    service_token_id: ?[]const u8 = null,
    tag_name: ?[]const u8 = null,
    policy_test_id: ?[]const u8 = null,
    certificate_id: ?[]const u8 = null,
};

pub const AccessMutationEndpoint = enum {
    create_application,
    update_application,
    delete_application,
    patch_application_settings,
    put_application_settings,
    revoke_application_tokens,
    create_application_policy,
    update_application_policy,
    delete_application_policy,
    make_policy_reusable,
    create_group,
    update_group,
    delete_group,
    create_identity_provider,
    update_identity_provider,
    delete_identity_provider,
    create_idp_saml_certificate,
    create_service_token,
    update_service_token,
    delete_service_token,
    refresh_service_token,
    rotate_service_token,
    create_reusable_policy,
    update_reusable_policy,
    delete_reusable_policy,
    create_tag,
    update_tag,
    delete_tag,
    update_keys,
    rotate_keys,
    start_policy_test,
    create_idp_federation_grant,
    delete_idp_federation_grant,
    rotate_saml_certificate,
    create_mtls_certificate,
    update_mtls_certificate,
    delete_mtls_certificate,
    update_mtls_settings,
    create_ca,
    delete_ca,

    pub fn parse(value: []const u8) ?AccessMutationEndpoint {
        if (std.mem.eql(u8, value, "create-application") or std.mem.eql(u8, value, "create-app")) return .create_application;
        if (std.mem.eql(u8, value, "update-application") or std.mem.eql(u8, value, "update-app")) return .update_application;
        if (std.mem.eql(u8, value, "delete-application") or std.mem.eql(u8, value, "delete-app")) return .delete_application;
        if (std.mem.eql(u8, value, "patch-application-settings") or std.mem.eql(u8, value, "patch-app-settings")) return .patch_application_settings;
        if (std.mem.eql(u8, value, "put-application-settings") or std.mem.eql(u8, value, "put-app-settings") or std.mem.eql(u8, value, "update-app-settings")) return .put_application_settings;
        if (std.mem.eql(u8, value, "revoke-application-tokens") or std.mem.eql(u8, value, "revoke-app-tokens")) return .revoke_application_tokens;
        if (std.mem.eql(u8, value, "create-application-policy") or std.mem.eql(u8, value, "create-app-policy")) return .create_application_policy;
        if (std.mem.eql(u8, value, "update-application-policy") or std.mem.eql(u8, value, "update-app-policy")) return .update_application_policy;
        if (std.mem.eql(u8, value, "delete-application-policy") or std.mem.eql(u8, value, "delete-app-policy")) return .delete_application_policy;
        if (std.mem.eql(u8, value, "make-policy-reusable") or std.mem.eql(u8, value, "convert-reusable")) return .make_policy_reusable;
        if (std.mem.eql(u8, value, "create-group")) return .create_group;
        if (std.mem.eql(u8, value, "update-group")) return .update_group;
        if (std.mem.eql(u8, value, "delete-group")) return .delete_group;
        if (std.mem.eql(u8, value, "create-identity-provider") or std.mem.eql(u8, value, "create-idp")) return .create_identity_provider;
        if (std.mem.eql(u8, value, "update-identity-provider") or std.mem.eql(u8, value, "update-idp")) return .update_identity_provider;
        if (std.mem.eql(u8, value, "delete-identity-provider") or std.mem.eql(u8, value, "delete-idp")) return .delete_identity_provider;
        if (std.mem.eql(u8, value, "create-idp-saml-certificate") or std.mem.eql(u8, value, "idp-saml-certificate")) return .create_idp_saml_certificate;
        if (std.mem.eql(u8, value, "create-service-token")) return .create_service_token;
        if (std.mem.eql(u8, value, "update-service-token")) return .update_service_token;
        if (std.mem.eql(u8, value, "delete-service-token")) return .delete_service_token;
        if (std.mem.eql(u8, value, "refresh-service-token")) return .refresh_service_token;
        if (std.mem.eql(u8, value, "rotate-service-token")) return .rotate_service_token;
        if (std.mem.eql(u8, value, "create-reusable-policy")) return .create_reusable_policy;
        if (std.mem.eql(u8, value, "update-reusable-policy")) return .update_reusable_policy;
        if (std.mem.eql(u8, value, "delete-reusable-policy")) return .delete_reusable_policy;
        if (std.mem.eql(u8, value, "create-tag")) return .create_tag;
        if (std.mem.eql(u8, value, "update-tag")) return .update_tag;
        if (std.mem.eql(u8, value, "delete-tag")) return .delete_tag;
        if (std.mem.eql(u8, value, "update-keys")) return .update_keys;
        if (std.mem.eql(u8, value, "rotate-keys")) return .rotate_keys;
        if (std.mem.eql(u8, value, "start-policy-test")) return .start_policy_test;
        if (std.mem.eql(u8, value, "create-idp-federation-grant") or std.mem.eql(u8, value, "create-federation-grant")) return .create_idp_federation_grant;
        if (std.mem.eql(u8, value, "delete-idp-federation-grant") or std.mem.eql(u8, value, "delete-federation-grant")) return .delete_idp_federation_grant;
        if (std.mem.eql(u8, value, "rotate-saml-certificate") or std.mem.eql(u8, value, "rotate-saml-cert")) return .rotate_saml_certificate;
        if (std.mem.eql(u8, value, "create-mtls-certificate") or std.mem.eql(u8, value, "create-certificate")) return .create_mtls_certificate;
        if (std.mem.eql(u8, value, "update-mtls-certificate") or std.mem.eql(u8, value, "update-certificate")) return .update_mtls_certificate;
        if (std.mem.eql(u8, value, "delete-mtls-certificate") or std.mem.eql(u8, value, "delete-certificate")) return .delete_mtls_certificate;
        if (std.mem.eql(u8, value, "update-mtls-settings") or std.mem.eql(u8, value, "update-certificate-settings")) return .update_mtls_settings;
        if (std.mem.eql(u8, value, "create-ca") or std.mem.eql(u8, value, "create-short-lived-ca")) return .create_ca;
        if (std.mem.eql(u8, value, "delete-ca") or std.mem.eql(u8, value, "delete-short-lived-ca")) return .delete_ca;
        return null;
    }

    pub fn commandName(self: AccessMutationEndpoint) []const u8 {
        return switch (self) {
            .create_application => "create-application",
            .update_application => "update-application",
            .delete_application => "delete-application",
            .patch_application_settings => "patch-application-settings",
            .put_application_settings => "put-application-settings",
            .revoke_application_tokens => "revoke-application-tokens",
            .create_application_policy => "create-application-policy",
            .update_application_policy => "update-application-policy",
            .delete_application_policy => "delete-application-policy",
            .make_policy_reusable => "make-policy-reusable",
            .create_group => "create-group",
            .update_group => "update-group",
            .delete_group => "delete-group",
            .create_identity_provider => "create-identity-provider",
            .update_identity_provider => "update-identity-provider",
            .delete_identity_provider => "delete-identity-provider",
            .create_idp_saml_certificate => "create-idp-saml-certificate",
            .create_service_token => "create-service-token",
            .update_service_token => "update-service-token",
            .delete_service_token => "delete-service-token",
            .refresh_service_token => "refresh-service-token",
            .rotate_service_token => "rotate-service-token",
            .create_reusable_policy => "create-reusable-policy",
            .update_reusable_policy => "update-reusable-policy",
            .delete_reusable_policy => "delete-reusable-policy",
            .create_tag => "create-tag",
            .update_tag => "update-tag",
            .delete_tag => "delete-tag",
            .update_keys => "update-keys",
            .rotate_keys => "rotate-keys",
            .start_policy_test => "start-policy-test",
            .create_idp_federation_grant => "create-idp-federation-grant",
            .delete_idp_federation_grant => "delete-idp-federation-grant",
            .rotate_saml_certificate => "rotate-saml-certificate",
            .create_mtls_certificate => "create-mtls-certificate",
            .update_mtls_certificate => "update-mtls-certificate",
            .delete_mtls_certificate => "delete-mtls-certificate",
            .update_mtls_settings => "update-mtls-settings",
            .create_ca => "create-ca",
            .delete_ca => "delete-ca",
        };
    }

    pub fn supports(self: AccessMutationEndpoint, scope: AccessScope) bool {
        return switch (self) {
            .make_policy_reusable,
            .create_idp_saml_certificate,
            .refresh_service_token,
            .rotate_service_token,
            .create_reusable_policy,
            .update_reusable_policy,
            .delete_reusable_policy,
            .create_tag,
            .update_tag,
            .delete_tag,
            .update_keys,
            .rotate_keys,
            .start_policy_test,
            .create_idp_federation_grant,
            .delete_idp_federation_grant,
            .rotate_saml_certificate,
            => scope == .account,
            .create_mtls_certificate,
            .update_mtls_certificate,
            .delete_mtls_certificate,
            .update_mtls_settings,
            .create_ca,
            .delete_ca,
            => true,
            else => true,
        };
    }

    pub fn method(self: AccessMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_application,
            .delete_application_policy,
            .delete_group,
            .delete_identity_provider,
            .delete_service_token,
            .delete_reusable_policy,
            .delete_tag,
            .delete_idp_federation_grant,
            .delete_mtls_certificate,
            .delete_ca,
            => "DELETE",
            .patch_application_settings => "PATCH",
            .update_application,
            .put_application_settings,
            .update_application_policy,
            .make_policy_reusable,
            .update_group,
            .update_identity_provider,
            .update_service_token,
            .update_reusable_policy,
            .update_tag,
            .update_keys,
            .update_mtls_certificate,
            .update_mtls_settings,
            => "PUT",
            else => "POST",
        };
    }

    pub fn group(self: AccessMutationEndpoint, scope: AccessScope) []const u8 {
        return switch (self) {
            .create_application, .update_application, .delete_application, .patch_application_settings, .put_application_settings, .revoke_application_tokens => if (scope == .account) "Access applications" else "Zone-Level Access applications",
            .create_application_policy, .update_application_policy, .delete_application_policy, .make_policy_reusable => if (scope == .account) "Access application-scoped policies" else "Zone-Level Access policies",
            .create_group, .update_group, .delete_group => if (scope == .account) "Access groups" else "Zone-Level Access groups",
            .create_identity_provider, .update_identity_provider, .delete_identity_provider, .create_idp_saml_certificate => if (scope == .account) "Access identity providers" else "Zone-Level Access identity providers",
            .create_service_token, .update_service_token, .delete_service_token, .refresh_service_token, .rotate_service_token => if (scope == .account) "Access service tokens" else "Zone-Level Access service tokens",
            .create_reusable_policy, .update_reusable_policy, .delete_reusable_policy => "Access reusable policies",
            .create_tag, .update_tag, .delete_tag => "Access tags",
            .update_keys, .rotate_keys => "Access key configuration",
            .start_policy_test => "Access policy tester",
            .create_idp_federation_grant, .delete_idp_federation_grant => "Access IdP federation grants",
            .rotate_saml_certificate => "Access SAML encryption certificates",
            .create_mtls_certificate, .update_mtls_certificate, .delete_mtls_certificate, .update_mtls_settings => if (scope == .account) "Access mTLS authentication" else "Zone-Level Access mTLS authentication",
            .create_ca, .delete_ca => if (scope == .account) "Access short-lived certificate CAs" else "Zone-Level Access short-lived certificate CAs",
        };
    }

    pub fn operationId(self: AccessMutationEndpoint, scope: AccessScope) []const u8 {
        return switch (scope) {
            .account => switch (self) {
                .create_application => "access-applications-add-an-application",
                .update_application => "access-applications-update-an-access-application",
                .delete_application => "access-applications-delete-an-access-application",
                .patch_application_settings => "access-applications-patch-update-access-application-settings",
                .put_application_settings => "access-applications-put-update-access-application-settings",
                .revoke_application_tokens => "access-applications-revoke-service-tokens",
                .create_application_policy => "access-policies-create-an-access-policy",
                .update_application_policy => "access-policies-update-an-access-policy",
                .delete_application_policy => "access-policies-delete-an-access-policy",
                .make_policy_reusable => "access-policies-convert-reusable",
                .create_group => "access-groups-create-an-access-group",
                .update_group => "access-groups-update-an-access-group",
                .delete_group => "access-groups-delete-an-access-group",
                .create_identity_provider => "access-identity-providers-add-an-access-identity-provider",
                .update_identity_provider => "access-identity-providers-update-an-access-identity-provider",
                .delete_identity_provider => "access-identity-providers-delete-an-access-identity-provider",
                .create_idp_saml_certificate => "access-identity-providers-create-saml-certificate-for-identity-provider",
                .create_service_token => "access-service-tokens-create-a-service-token",
                .update_service_token => "access-service-tokens-update-a-service-token",
                .delete_service_token => "access-service-tokens-delete-a-service-token",
                .refresh_service_token => "access-service-tokens-refresh-a-service-token",
                .rotate_service_token => "access-service-tokens-rotate-a-service-token",
                .create_reusable_policy => "access-policies-create-an-access-reusable-policy",
                .update_reusable_policy => "access-policies-update-an-access-reusable-policy",
                .delete_reusable_policy => "access-policies-delete-an-access-reusable-policy",
                .create_tag => "access-tags-create-tag",
                .update_tag => "access-tags-update-a-tag",
                .delete_tag => "access-tags-delete-a-tag",
                .update_keys => "access-key-configuration-update-the-access-key-configuration",
                .rotate_keys => "access-key-configuration-rotate-access-keys",
                .start_policy_test => "access-policy-tests",
                .create_idp_federation_grant => "access-idp-federation-grants-create",
                .delete_idp_federation_grant => "access-idp-federation-grants-delete",
                .rotate_saml_certificate => "access-saml-certificates-rotate-certificate",
                .create_mtls_certificate => "access-mtls-authentication-add-an-mtls-certificate",
                .update_mtls_certificate => "access-mtls-authentication-update-an-mtls-certificate",
                .delete_mtls_certificate => "access-mtls-authentication-delete-an-mtls-certificate",
                .update_mtls_settings => "access-mtls-authentication-update-an-mtls-certificate-settings",
                .create_ca => "access-short-lived-certificate-c-as-create-a-short-lived-certificate-ca",
                .delete_ca => "access-short-lived-certificate-c-as-delete-a-short-lived-certificate-ca",
            },
            .zone => switch (self) {
                .create_application => "zone-level-access-applications-add-a-bookmark-application",
                .update_application => "zone-level-access-applications-update-a-bookmark-application",
                .delete_application => "zone-level-access-applications-delete-an-access-application",
                .patch_application_settings => "zone-level-access-applications-patch-update-access-application-settings",
                .put_application_settings => "zone-level-access-applications-put-update-access-application-settings",
                .revoke_application_tokens => "zone-level-access-applications-revoke-service-tokens",
                .create_application_policy => "zone-level-access-policies-create-an-access-policy",
                .update_application_policy => "zone-level-access-policies-update-an-access-policy",
                .delete_application_policy => "zone-level-access-policies-delete-an-access-policy",
                .create_group => "zone-level-access-groups-create-an-access-group",
                .update_group => "zone-level-access-groups-update-an-access-group",
                .delete_group => "zone-level-access-groups-delete-an-access-group",
                .create_identity_provider => "zone-level-access-identity-providers-add-an-access-identity-provider",
                .update_identity_provider => "zone-level-access-identity-providers-update-an-access-identity-provider",
                .delete_identity_provider => "zone-level-access-identity-providers-delete-an-access-identity-provider",
                .create_service_token => "zone-level-access-service-tokens-create-a-service-token",
                .update_service_token => "zone-level-access-service-tokens-update-a-service-token",
                .delete_service_token => "zone-level-access-service-tokens-delete-a-service-token",
                .create_mtls_certificate => "zone-level-access-mtls-authentication-add-an-mtls-certificate",
                .update_mtls_certificate => "zone-level-access-mtls-authentication-update-an-mtls-certificate",
                .delete_mtls_certificate => "zone-level-access-mtls-authentication-delete-an-mtls-certificate",
                .update_mtls_settings => "zone-level-access-mtls-authentication-update-an-mtls-certificate-settings",
                .create_ca => "zone-level-access-short-lived-certificate-c-as-create-a-short-lived-certificate-ca",
                .delete_ca => "zone-level-access-short-lived-certificate-c-as-delete-a-short-lived-certificate-ca",
                else => "unsupported",
            },
        };
    }

    pub fn summary(self: AccessMutationEndpoint, scope: AccessScope) []const u8 {
        return switch (self) {
            .create_application => if (scope == .account) "Add an account Access application" else "Add a zone Access application",
            .update_application => if (scope == .account) "Update an account Access application" else "Update a zone Access application",
            .delete_application => if (scope == .account) "Delete an account Access application" else "Delete a zone Access application",
            .patch_application_settings => "Patch Access application settings",
            .put_application_settings => "Update Access application settings",
            .revoke_application_tokens => "Revoke Access application tokens",
            .create_application_policy => "Create an Access application policy",
            .update_application_policy => "Update an Access application policy",
            .delete_application_policy => "Delete an Access application policy",
            .make_policy_reusable => "Convert an Access application policy to a reusable policy",
            .create_group => if (scope == .account) "Create an account Access group" else "Create a zone Access group",
            .update_group => if (scope == .account) "Update an account Access group" else "Update a zone Access group",
            .delete_group => if (scope == .account) "Delete an account Access group" else "Delete a zone Access group",
            .create_identity_provider => if (scope == .account) "Add an account Access identity provider" else "Add a zone Access identity provider",
            .update_identity_provider => if (scope == .account) "Update an account Access identity provider" else "Update a zone Access identity provider",
            .delete_identity_provider => if (scope == .account) "Delete an account Access identity provider" else "Delete a zone Access identity provider",
            .create_idp_saml_certificate => "Create a SAML certificate for an Access identity provider",
            .create_service_token => if (scope == .account) "Create an account Access service token" else "Create a zone Access service token",
            .update_service_token => if (scope == .account) "Update an account Access service token" else "Update a zone Access service token",
            .delete_service_token => if (scope == .account) "Delete an account Access service token" else "Delete a zone Access service token",
            .refresh_service_token => "Refresh an account Access service token",
            .rotate_service_token => "Rotate an account Access service token",
            .create_reusable_policy => "Create an account Access reusable policy",
            .update_reusable_policy => "Update an account Access reusable policy",
            .delete_reusable_policy => "Delete an account Access reusable policy",
            .create_tag => "Create an account Access tag",
            .update_tag => "Update an account Access tag",
            .delete_tag => "Delete an account Access tag",
            .update_keys => "Update account Access key configuration",
            .rotate_keys => "Rotate account Access keys",
            .start_policy_test => "Start an account Access policy test",
            .create_idp_federation_grant => "Create an account Access IdP federation grant",
            .delete_idp_federation_grant => "Delete an account Access IdP federation grant",
            .rotate_saml_certificate => "Rotate an account Access SAML certificate",
            .create_mtls_certificate => if (scope == .account) "Add an account Access mTLS certificate" else "Add a zone Access mTLS certificate",
            .update_mtls_certificate => if (scope == .account) "Update an account Access mTLS certificate" else "Update a zone Access mTLS certificate",
            .delete_mtls_certificate => if (scope == .account) "Delete an account Access mTLS certificate" else "Delete a zone Access mTLS certificate",
            .update_mtls_settings => if (scope == .account) "Update account Access mTLS certificate hostname settings" else "Update zone Access mTLS certificate hostname settings",
            .create_ca => if (scope == .account) "Create an account Access short-lived certificate CA" else "Create a zone Access short-lived certificate CA",
            .delete_ca => if (scope == .account) "Delete an account Access short-lived certificate CA" else "Delete a zone Access short-lived certificate CA",
        };
    }

    pub fn requestBodySchemaRef(self: AccessMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .delete_application,
            .delete_application_policy,
            .delete_group,
            .delete_identity_provider,
            .delete_service_token,
            .refresh_service_token,
            .rotate_service_token,
            .delete_reusable_policy,
            .delete_tag,
            .rotate_keys,
            .delete_idp_federation_grant,
            .delete_mtls_certificate,
            .delete_ca,
            => null,
            else => "object",
        };
    }

    pub fn requiresAppId(self: AccessMutationEndpoint) bool {
        return switch (self) {
            .update_application,
            .delete_application,
            .patch_application_settings,
            .put_application_settings,
            .revoke_application_tokens,
            .create_application_policy,
            .update_application_policy,
            .delete_application_policy,
            .make_policy_reusable,
            .create_ca,
            .delete_ca,
            => true,
            else => false,
        };
    }

    pub fn requiresPolicyId(self: AccessMutationEndpoint) bool {
        return switch (self) {
            .update_application_policy,
            .delete_application_policy,
            .make_policy_reusable,
            .update_reusable_policy,
            .delete_reusable_policy,
            => true,
            else => false,
        };
    }

    pub fn requiresResourceId(self: AccessMutationEndpoint) bool {
        return self == .update_group or self == .delete_group or self == .delete_idp_federation_grant or self == .rotate_saml_certificate;
    }

    pub fn requiresIdentityProviderId(self: AccessMutationEndpoint) bool {
        return self == .update_identity_provider or self == .delete_identity_provider or self == .create_idp_saml_certificate;
    }

    pub fn requiresServiceTokenId(self: AccessMutationEndpoint) bool {
        return self == .update_service_token or self == .delete_service_token or self == .refresh_service_token or self == .rotate_service_token;
    }

    pub fn requiresTagName(self: AccessMutationEndpoint) bool {
        return self == .update_tag or self == .delete_tag;
    }

    pub fn requiresCertificateId(self: AccessMutationEndpoint) bool {
        return self == .update_mtls_certificate or self == .delete_mtls_certificate;
    }
};

pub const AccessMutationArgs = struct {
    scope: AccessScope,
    scope_id: []const u8,
    app_id: ?[]const u8 = null,
    policy_id: ?[]const u8 = null,
    resource_id: ?[]const u8 = null,
    identity_provider_id: ?[]const u8 = null,
    service_token_id: ?[]const u8 = null,
    tag_name: ?[]const u8 = null,
    certificate_id: ?[]const u8 = null,
};

pub const ResourceTaggingAccountReadEndpoint = enum {
    tags,
    keys,
    resources,
    values,

    pub fn parse(value: []const u8) ?ResourceTaggingAccountReadEndpoint {
        if (std.mem.eql(u8, value, "tags") or std.mem.eql(u8, value, "get")) return .tags;
        if (std.mem.eql(u8, value, "keys") or std.mem.eql(u8, value, "tag-keys")) return .keys;
        if (std.mem.eql(u8, value, "resources") or std.mem.eql(u8, value, "tagged-resources")) return .resources;
        if (std.mem.eql(u8, value, "values") or std.mem.eql(u8, value, "tag-values")) return .values;
        return null;
    }

    pub fn commandName(self: ResourceTaggingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .tags => "tags",
            .keys => "keys",
            .resources => "resources",
            .values => "values",
        };
    }

    pub fn label(self: ResourceTaggingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .tags => "resource-tags-account",
            .keys => "resource-tags-keys",
            .resources => "resource-tags-resources",
            .values => "resource-tags-values",
        };
    }

    pub fn group(self: ResourceTaggingAccountReadEndpoint) []const u8 {
        _ = self;
        return "Resource Tagging";
    }

    pub fn operationId(self: ResourceTaggingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .tags => "tags-get",
            .keys => "tags-list-keys",
            .resources => "tags-list",
            .values => "tags-list-values",
        };
    }

    pub fn summary(self: ResourceTaggingAccountReadEndpoint) []const u8 {
        return switch (self) {
            .tags => "Get tags for an account-level resource",
            .keys => "List tag keys",
            .resources => "List tagged resources",
            .values => "List tag values",
        };
    }

    pub fn requiresTagKey(self: ResourceTaggingAccountReadEndpoint) bool {
        return self == .values;
    }
};

pub const ResourceTaggingAccountReadArgs = struct {
    tag_key: ?[]const u8 = null,
    resource_id: ?[]const u8 = null,
    resource_type: ?[]const u8 = null,
    worker_id: ?[]const u8 = null,
    type_filter: ?[]const u8 = null,
};

pub const ResourceTaggingZoneReadArgs = struct {
    resource_id: ?[]const u8 = null,
    resource_type: ?[]const u8 = null,
    access_application_id: ?[]const u8 = null,
};

pub const ResourceTaggingMutationResource = enum {
    account,
    zone,

    pub fn parse(value: []const u8) ?ResourceTaggingMutationResource {
        if (std.mem.eql(u8, value, "account")) return .account;
        if (std.mem.eql(u8, value, "zone")) return .zone;
        return null;
    }

    pub fn commandName(self: ResourceTaggingMutationResource) []const u8 {
        return switch (self) {
            .account => "account",
            .zone => "zone",
        };
    }

    pub fn group(self: ResourceTaggingMutationResource) []const u8 {
        _ = self;
        return "Resource Tagging";
    }

    pub fn usesAccountId(self: ResourceTaggingMutationResource) bool {
        return self == .account;
    }
};

pub const ResourceTaggingMutationEndpoint = enum {
    set,
    delete_resource,

    pub fn parse(value: []const u8) ?ResourceTaggingMutationEndpoint {
        if (std.mem.eql(u8, value, "set") or std.mem.eql(u8, value, "put")) return .set;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_resource;
        return null;
    }

    pub fn commandName(self: ResourceTaggingMutationEndpoint) []const u8 {
        return switch (self) {
            .set => "set",
            .delete_resource => "delete",
        };
    }

    pub fn method(self: ResourceTaggingMutationEndpoint) []const u8 {
        return switch (self) {
            .set => "PUT",
            .delete_resource => "DELETE",
        };
    }

    pub fn operationId(self: ResourceTaggingMutationEndpoint, resource: ResourceTaggingMutationResource) []const u8 {
        return switch (resource) {
            .account => switch (self) {
                .set => "tags-set",
                .delete_resource => "tags-delete",
            },
            .zone => switch (self) {
                .set => "tags-zone-set",
                .delete_resource => "tags-zone-delete",
            },
        };
    }

    pub fn summary(self: ResourceTaggingMutationEndpoint, resource: ResourceTaggingMutationResource) []const u8 {
        return switch (resource) {
            .account => switch (self) {
                .set => "Set tags for an account-level resource",
                .delete_resource => "Delete tags from an account-level resource",
            },
            .zone => switch (self) {
                .set => "Set tags for a zone-level resource",
                .delete_resource => "Delete tags from a zone-level resource",
            },
        };
    }

    pub fn requestBodySchemaRef(self: ResourceTaggingMutationEndpoint, resource: ResourceTaggingMutationResource) []const u8 {
        return switch (resource) {
            .account => switch (self) {
                .set => "#/components/schemas/resource-tagging_set_tags_request_account_level",
                .delete_resource => "#/components/schemas/resource-tagging_delete_tags_request_account_level",
            },
            .zone => switch (self) {
                .set => "#/components/schemas/resource-tagging_set_tags_request_zone_level",
                .delete_resource => "#/components/schemas/resource-tagging_delete_tags_request_zone_level",
            },
        };
    }
};

pub const ResourceTaggingMutationArgs = struct {
    resource: ResourceTaggingMutationResource,
    account_id: ?[]const u8 = null,
    zone_id: ?[]const u8 = null,
};

pub const DnsRecordReadEndpoint = enum {
    list,
    export_records,
    scan_review,
    usage,
    details,

    pub fn parse(value: []const u8) ?DnsRecordReadEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "records")) return .list;
        if (std.mem.eql(u8, value, "export") or std.mem.eql(u8, value, "export-records")) return .export_records;
        if (std.mem.eql(u8, value, "scan-review") or std.mem.eql(u8, value, "review-scan")) return .scan_review;
        if (std.mem.eql(u8, value, "usage")) return .usage;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .details;
        return null;
    }

    pub fn commandName(self: DnsRecordReadEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .export_records => "export",
            .scan_review => "scan-review",
            .usage => "usage",
            .details => "show",
        };
    }

    pub fn label(self: DnsRecordReadEndpoint) []const u8 {
        return switch (self) {
            .list => "dns",
            .export_records => "dns-export",
            .scan_review => "dns-scan-review",
            .usage => "dns-usage",
            .details => "dns-record",
        };
    }

    pub fn operationId(self: DnsRecordReadEndpoint) []const u8 {
        return switch (self) {
            .list => "dns-records-for-a-zone-list-dns-records",
            .export_records => "dns-records-for-a-zone-export-dns-records",
            .scan_review => "dns-records-for-a-zone-review-dns-scan",
            .usage => "dns-records-for-a-zone-get-usage",
            .details => "dns-records-for-a-zone-dns-record-details",
        };
    }

    pub fn summary(self: DnsRecordReadEndpoint) []const u8 {
        return switch (self) {
            .list => "List DNS Records",
            .export_records => "Export DNS Records",
            .scan_review => "List Scanned DNS Records",
            .usage => "Get DNS Record Usage",
            .details => "DNS Record Details",
        };
    }

    pub fn requiresRecordId(self: DnsRecordReadEndpoint) bool {
        return self == .details;
    }
};

pub const DnsRecordMutationEndpoint = enum {
    create,
    batch,
    import_records,
    apply_scan_results,
    trigger_scan,
    delete_record,
    patch_record,
    update_record,

    pub fn parse(value: []const u8) ?DnsRecordMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "create-record")) return .create;
        if (std.mem.eql(u8, value, "batch") or std.mem.eql(u8, value, "batch-records")) return .batch;
        if (std.mem.eql(u8, value, "import") or std.mem.eql(u8, value, "import-records")) return .import_records;
        if (std.mem.eql(u8, value, "apply-scan") or std.mem.eql(u8, value, "apply-scan-results")) return .apply_scan_results;
        if (std.mem.eql(u8, value, "trigger-scan")) return .trigger_scan;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-record")) return .delete_record;
        if (std.mem.eql(u8, value, "patch") or std.mem.eql(u8, value, "patch-record")) return .patch_record;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "update-record")) return .update_record;
        return null;
    }

    pub fn commandName(self: DnsRecordMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .batch => "batch",
            .import_records => "import",
            .apply_scan_results => "apply-scan-results",
            .trigger_scan => "trigger-scan",
            .delete_record => "delete",
            .patch_record => "patch",
            .update_record => "update",
        };
    }

    pub fn group(self: DnsRecordMutationEndpoint) []const u8 {
        _ = self;
        return "DNS Records for a Zone";
    }

    pub fn method(self: DnsRecordMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .batch, .import_records, .apply_scan_results, .trigger_scan => "POST",
            .delete_record => "DELETE",
            .patch_record => "PATCH",
            .update_record => "PUT",
        };
    }

    pub fn operationId(self: DnsRecordMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "dns-records-for-a-zone-create-dns-record",
            .batch => "dns-records-for-a-zone-batch-dns-records",
            .import_records => "dns-records-for-a-zone-import-dns-records",
            .apply_scan_results => "dns-records-for-a-zone-apply-dns-scan-results",
            .trigger_scan => "dns-records-for-a-zone-trigger-dns-scan",
            .delete_record => "dns-records-for-a-zone-delete-dns-record",
            .patch_record => "dns-records-for-a-zone-patch-dns-record",
            .update_record => "dns-records-for-a-zone-update-dns-record",
        };
    }

    pub fn summary(self: DnsRecordMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create DNS Record",
            .batch => "Batch DNS Records",
            .import_records => "Import DNS Records",
            .apply_scan_results => "Review Scanned DNS Records",
            .trigger_scan => "Trigger DNS Record Scan",
            .delete_record => "Delete DNS Record",
            .patch_record => "Update DNS Record",
            .update_record => "Overwrite DNS Record",
        };
    }

    pub fn requestBodySchemaRef(self: DnsRecordMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create, .update_record => "#/components/schemas/dns-records_dns-record-post",
            .batch => "#/components/schemas/dns-records_dns-request-batch-object",
            .apply_scan_results => "#/components/schemas/dns-records_dns-request-review-scan-object",
            .patch_record => "#/components/schemas/dns-records_dns-record-patch",
            .import_records, .trigger_scan, .delete_record => null,
        };
    }

    pub fn requiresRecordId(self: DnsRecordMutationEndpoint) bool {
        return self == .delete_record or self == .patch_record or self == .update_record;
    }

    pub fn suffix(self: DnsRecordMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create, .delete_record, .patch_record, .update_record => null,
            .batch => "batch",
            .import_records => "import",
            .apply_scan_results => "scan/review",
            .trigger_scan => "scan/trigger",
        };
    }
};

pub const DnsRecordMutationArgs = struct {
    zone_id: []const u8,
    dns_record_id: ?[]const u8 = null,
};

pub const AccountTokenEndpoint = enum {
    list,
    permission_groups,
    verify,

    pub fn label(self: AccountTokenEndpoint) []const u8 {
        return switch (self) {
            .list => "account-tokens",
            .permission_groups => "account-token-permission-groups",
            .verify => "account-token-verify",
        };
    }

    pub fn pathSuffix(self: AccountTokenEndpoint) []const u8 {
        return switch (self) {
            .list => "tokens",
            .permission_groups => "tokens/permission_groups",
            .verify => "tokens/verify",
        };
    }

    pub fn commandName(self: AccountTokenEndpoint) []const u8 {
        return switch (self) {
            .list => "tokens",
            .permission_groups => "token-permission-groups",
            .verify => "token-verify",
        };
    }

    pub fn parse(value: []const u8) ?AccountTokenEndpoint {
        if (std.mem.eql(u8, value, "tokens")) return .list;
        if (std.mem.eql(u8, value, "token-permission-groups") or std.mem.eql(u8, value, "token-permissions")) return .permission_groups;
        if (std.mem.eql(u8, value, "token-verify")) return .verify;
        return null;
    }
};

pub const AccountTokenMutationEndpoint = enum {
    create,
    delete_token,
    update,
    roll,

    pub fn parse(value: []const u8) ?AccountTokenMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-token")) return .delete_token;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "roll") or std.mem.eql(u8, value, "roll-token")) return .roll;
        return null;
    }

    pub fn commandName(self: AccountTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .delete_token => "delete",
            .update => "update",
            .roll => "roll",
        };
    }

    pub fn group(self: AccountTokenMutationEndpoint) []const u8 {
        _ = self;
        return "Account Owned API Tokens";
    }

    pub fn method(self: AccountTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .delete_token => "DELETE",
            .update, .roll => "PUT",
        };
    }

    pub fn operationId(self: AccountTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "account-api-tokens-create-token",
            .delete_token => "account-api-tokens-delete-token",
            .update => "account-api-tokens-update-token",
            .roll => "account-api-tokens-roll-token",
        };
    }

    pub fn summary(self: AccountTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create Token",
            .delete_token => "Delete Token",
            .update => "Update Token",
            .roll => "Roll Token",
        };
    }

    pub fn requestBodySchemaRef(self: AccountTokenMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/iam_create_payload",
            .update => "#/components/schemas/iam_token_body",
            .delete_token, .roll => null,
        };
    }

    pub fn requiresTokenId(self: AccountTokenMutationEndpoint) bool {
        return self == .delete_token or self == .update or self == .roll;
    }
};

pub const AccountTokenMutationArgs = struct {
    account_id: []const u8,
    token_id: ?[]const u8 = null,
};

pub const IdentityEndpoint = enum {
    user,
    tenants,
    memberships,

    pub fn label(self: IdentityEndpoint) []const u8 {
        return switch (self) {
            .user => "user",
            .tenants => "user-tenants",
            .memberships => "memberships",
        };
    }

    pub fn path(self: IdentityEndpoint) []const u8 {
        return switch (self) {
            .user => user_path,
            .tenants => user_tenants_path,
            .memberships => memberships_path,
        };
    }

    pub fn parse(value: []const u8) ?IdentityEndpoint {
        if (std.mem.eql(u8, value, "user")) return .user;
        if (std.mem.eql(u8, value, "tenants") or std.mem.eql(u8, value, "user-tenants")) return .tenants;
        if (std.mem.eql(u8, value, "memberships") or std.mem.eql(u8, value, "membership")) return .memberships;
        return null;
    }
};

pub const MembershipMutationEndpoint = enum {
    update,
    delete_membership,

    pub fn parse(value: []const u8) ?MembershipMutationEndpoint {
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "accept") or std.mem.eql(u8, value, "reject")) return .update;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_membership;
        return null;
    }

    pub fn commandName(self: MembershipMutationEndpoint) []const u8 {
        return switch (self) {
            .update => "update",
            .delete_membership => "delete",
        };
    }

    pub fn group(self: MembershipMutationEndpoint) []const u8 {
        _ = self;
        return "User's Account Memberships";
    }

    pub fn method(self: MembershipMutationEndpoint) []const u8 {
        return switch (self) {
            .update => "PUT",
            .delete_membership => "DELETE",
        };
    }

    pub fn operationId(self: MembershipMutationEndpoint) []const u8 {
        return switch (self) {
            .update => "user'-s-account-memberships-update-membership",
            .delete_membership => "user'-s-account-memberships-delete-membership",
        };
    }

    pub fn summary(self: MembershipMutationEndpoint) []const u8 {
        return switch (self) {
            .update => "Update Membership",
            .delete_membership => "Delete Membership",
        };
    }

    pub fn requestBodySchemaRef(self: MembershipMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .update => "inline:{status:accepted|rejected}",
            .delete_membership => null,
        };
    }
};

pub const MembershipMutationArgs = struct {
    membership_id: []const u8,
};

pub const UserTokenEndpoint = enum {
    list,
    verify,
    permission_groups,
    details,

    pub fn label(self: UserTokenEndpoint) []const u8 {
        return switch (self) {
            .list => "user-tokens",
            .verify => "user-token-verify",
            .permission_groups => "user-token-permission-groups",
            .details => "user-token",
        };
    }

    pub fn path(self: UserTokenEndpoint) []const u8 {
        return switch (self) {
            .list => user_tokens_path,
            .verify => user_tokens_verify_path,
            .permission_groups => user_token_permission_groups_path,
            .details => user_tokens_path,
        };
    }

    pub fn commandName(self: UserTokenEndpoint) []const u8 {
        return switch (self) {
            .list => "list",
            .verify => "verify",
            .permission_groups => "permission-groups",
            .details => "show",
        };
    }

    pub fn parse(value: []const u8) ?UserTokenEndpoint {
        if (std.mem.eql(u8, value, "list") or std.mem.eql(u8, value, "tokens")) return .list;
        if (std.mem.eql(u8, value, "show") or std.mem.eql(u8, value, "detail") or std.mem.eql(u8, value, "details")) return .details;
        if (std.mem.eql(u8, value, "verify") or std.mem.eql(u8, value, "token-verify")) return .verify;
        if (std.mem.eql(u8, value, "permission-groups") or
            std.mem.eql(u8, value, "permissions") or
            std.mem.eql(u8, value, "token-permission-groups"))
        {
            return .permission_groups;
        }
        return null;
    }

    pub fn requiresTokenId(self: UserTokenEndpoint) bool {
        return self == .details;
    }
};

pub const UserTokenMutationEndpoint = enum {
    create,
    delete_token,
    update,
    roll,

    pub fn parse(value: []const u8) ?UserTokenMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-token")) return .delete_token;
        if (std.mem.eql(u8, value, "update")) return .update;
        if (std.mem.eql(u8, value, "roll") or std.mem.eql(u8, value, "roll-token")) return .roll;
        return null;
    }

    pub fn commandName(self: UserTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .delete_token => "delete",
            .update => "update",
            .roll => "roll",
        };
    }

    pub fn group(self: UserTokenMutationEndpoint) []const u8 {
        _ = self;
        return "User API Tokens";
    }

    pub fn method(self: UserTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "POST",
            .delete_token => "DELETE",
            .update, .roll => "PUT",
        };
    }

    pub fn operationId(self: UserTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "user-api-tokens-create-token",
            .delete_token => "user-api-tokens-delete-token",
            .update => "user-api-tokens-update-token",
            .roll => "user-api-tokens-roll-token",
        };
    }

    pub fn summary(self: UserTokenMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create Token",
            .delete_token => "Delete Token",
            .update => "Update Token",
            .roll => "Roll Token",
        };
    }

    pub fn requestBodySchemaRef(self: UserTokenMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/iam_create_payload",
            .update => "#/components/schemas/iam_token_body",
            .delete_token, .roll => null,
        };
    }

    pub fn requiresTokenId(self: UserTokenMutationEndpoint) bool {
        return self == .delete_token or self == .update or self == .roll;
    }
};

pub const UserTokenMutationArgs = struct {
    token_id: ?[]const u8 = null,
};

pub const ZoneMutationEndpoint = enum {
    create,
    delete_zone,
    edit,
    purge_cache,
    purge_environment_cache,
    activation_check,

    pub fn parse(value: []const u8) ?ZoneMutationEndpoint {
        if (std.mem.eql(u8, value, "create")) return .create;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "remove")) return .delete_zone;
        if (std.mem.eql(u8, value, "edit") or std.mem.eql(u8, value, "patch") or std.mem.eql(u8, value, "update")) return .edit;
        if (std.mem.eql(u8, value, "purge") or std.mem.eql(u8, value, "purge-cache")) return .purge_cache;
        if (std.mem.eql(u8, value, "purge-environment") or std.mem.eql(u8, value, "purge-environment-cache")) return .purge_environment_cache;
        if (std.mem.eql(u8, value, "activation-check") or std.mem.eql(u8, value, "check-activation")) return .activation_check;
        return null;
    }

    pub fn commandName(self: ZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .delete_zone => "delete",
            .edit => "edit",
            .purge_cache => "purge-cache",
            .purge_environment_cache => "purge-environment-cache",
            .activation_check => "activation-check",
        };
    }

    pub fn group(self: ZoneMutationEndpoint) []const u8 {
        _ = self;
        return "Zone";
    }

    pub fn method(self: ZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .purge_cache, .purge_environment_cache => "POST",
            .delete_zone => "DELETE",
            .edit => "PATCH",
            .activation_check => "PUT",
        };
    }

    pub fn operationId(self: ZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "zones-post",
            .delete_zone => "zones-0-delete",
            .edit => "zones-0-patch",
            .purge_cache => "zone-purge",
            .purge_environment_cache => "zone-environment-purge",
            .activation_check => "put-zones-zone_id-activation_check",
        };
    }

    pub fn summary(self: ZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create Zone",
            .delete_zone => "Delete Zone",
            .edit => "Edit Zone",
            .purge_cache => "Purge Cached Content",
            .purge_environment_cache => "Purge Cached Content by Environment",
            .activation_check => "Rerun the Activation Check",
        };
    }

    pub fn requestBodySchemaRef(self: ZoneMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "inline:{name:string,account:{id:string},type?:string}",
            .edit => "inline:{paused?:bool,plan?:{id:string},type?:full|partial|secondary|internal,vanity_name_servers?:[]string}",
            .purge_cache, .purge_environment_cache => "anyOf:#/components/schemas/cache-purge_FlexPurgeByTags|#/components/schemas/cache-purge_FlexPurgeByHostnames|#/components/schemas/cache-purge_FlexPurgeByPrefixes|#/components/schemas/cache-purge_Everything|#/components/schemas/cache-purge_SingleFile|#/components/schemas/cache-purge_SingleFileWithUrlAndHeaders",
            .delete_zone, .activation_check => null,
        };
    }

    pub fn requiresZoneId(self: ZoneMutationEndpoint) bool {
        return self != .create;
    }

    pub fn requiresEnvironmentId(self: ZoneMutationEndpoint) bool {
        return self == .purge_environment_cache;
    }
};

pub const ZoneMutationArgs = struct {
    zone_id: ?[]const u8 = null,
    environment_id: ?[]const u8 = null,
};

pub const ZoneEndpoint = enum {
    dnssec,
    dnssec_zsk,
    dns_settings,
    settings,
    settings_aegis,
    settings_fonts,
    settings_origin_h2_max_streams,
    settings_origin_max_http_version,
    settings_speed_brain,
    settings_ssl_automatic_mode,

    pub fn label(self: ZoneEndpoint) []const u8 {
        return switch (self) {
            .dnssec => "dnssec",
            .dnssec_zsk => "dnssec-zsk",
            .dns_settings => "dns-settings",
            .settings => "settings",
            .settings_aegis => "settings-aegis",
            .settings_fonts => "settings-fonts",
            .settings_origin_h2_max_streams => "settings-origin-h2-max-streams",
            .settings_origin_max_http_version => "settings-origin-max-http-version",
            .settings_speed_brain => "settings-speed-brain",
            .settings_ssl_automatic_mode => "settings-ssl-automatic-mode",
        };
    }

    pub fn pathSuffix(self: ZoneEndpoint) []const u8 {
        return switch (self) {
            .dnssec => "dnssec",
            .dnssec_zsk => "dnssec/zsk",
            .dns_settings => "dns_settings",
            .settings => "settings",
            .settings_aegis => "settings/aegis",
            .settings_fonts => "settings/fonts",
            .settings_origin_h2_max_streams => "settings/origin_h2_max_streams",
            .settings_origin_max_http_version => "settings/origin_max_http_version",
            .settings_speed_brain => "settings/speed_brain",
            .settings_ssl_automatic_mode => "settings/ssl_automatic_mode",
        };
    }
};

pub const ZoneLifecycleReadEndpoint = enum {
    available_plans,
    available_plan,
    available_rate_plans,
    cache_reserve,
    cache_reserve_clear,
    regional_tiered_cache,
    variants,
    environments,
    hold,
    subscription,

    pub fn parse(value: []const u8) ?ZoneLifecycleReadEndpoint {
        if (std.mem.eql(u8, value, "available-plans") or std.mem.eql(u8, value, "plans")) return .available_plans;
        if (std.mem.eql(u8, value, "available-plan") or std.mem.eql(u8, value, "plan")) return .available_plan;
        if (std.mem.eql(u8, value, "available-rate-plans") or std.mem.eql(u8, value, "rate-plans")) return .available_rate_plans;
        if (std.mem.eql(u8, value, "cache-reserve")) return .cache_reserve;
        if (std.mem.eql(u8, value, "cache-reserve-clear")) return .cache_reserve_clear;
        if (std.mem.eql(u8, value, "regional-tiered-cache")) return .regional_tiered_cache;
        if (std.mem.eql(u8, value, "variants") or std.mem.eql(u8, value, "cache-variants")) return .variants;
        if (std.mem.eql(u8, value, "environments") or std.mem.eql(u8, value, "envs")) return .environments;
        if (std.mem.eql(u8, value, "hold") or std.mem.eql(u8, value, "zone-hold")) return .hold;
        if (std.mem.eql(u8, value, "subscription")) return .subscription;
        return null;
    }

    pub fn commandName(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans => "available-plans",
            .available_plan => "available-plan",
            .available_rate_plans => "available-rate-plans",
            .cache_reserve => "cache-reserve",
            .cache_reserve_clear => "cache-reserve-clear",
            .regional_tiered_cache => "regional-tiered-cache",
            .variants => "variants",
            .environments => "environments",
            .hold => "hold",
            .subscription => "subscription",
        };
    }

    pub fn label(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans => "zone-available-plans",
            .available_plan => "zone-available-plan",
            .available_rate_plans => "zone-available-rate-plans",
            .cache_reserve => "zone-cache-reserve",
            .cache_reserve_clear => "zone-cache-reserve-clear",
            .regional_tiered_cache => "zone-regional-tiered-cache",
            .variants => "zone-cache-variants",
            .environments => "zone-environments",
            .hold => "zone-hold",
            .subscription => "zone-subscription",
        };
    }

    pub fn group(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans, .available_plan, .available_rate_plans => "Zone Rate Plan",
            .cache_reserve, .cache_reserve_clear, .regional_tiered_cache, .variants => "Zone Cache Settings",
            .environments => "Zone Environments",
            .hold => "Zone Holds",
            .subscription => "Zone Subscription",
        };
    }

    pub fn operationId(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans => "zone-rate-plan-list-available-plans",
            .available_plan => "zone-rate-plan-available-plan-details",
            .available_rate_plans => "zone-rate-plan-list-available-rate-plans",
            .cache_reserve => "zone-cache-settings-get-cache-reserve-setting",
            .cache_reserve_clear => "zone-cache-settings-get-cache-reserve-clear",
            .regional_tiered_cache => "zone-cache-settings-get-regional-tiered-cache-setting",
            .variants => "zone-cache-settings-get-variants-setting",
            .environments => "zonesEnvironmentsList",
            .hold => "zones-0-hold-get",
            .subscription => "zone-subscription-zone-subscription-details",
        };
    }

    pub fn summary(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans => "List Available Plans",
            .available_plan => "Available Plan Details",
            .available_rate_plans => "List Available Rate Plans",
            .cache_reserve => "Get Cache Reserve setting",
            .cache_reserve_clear => "Get Cache Reserve Clear",
            .regional_tiered_cache => "Get Regional Tiered Cache setting",
            .variants => "Get variants setting",
            .environments => "List zone environments",
            .hold => "Get Zone Hold",
            .subscription => "Zone Subscription Details",
        };
    }

    pub fn pathSuffix(self: ZoneLifecycleReadEndpoint) []const u8 {
        return switch (self) {
            .available_plans, .available_plan => "available_plans",
            .available_rate_plans => "available_rate_plans",
            .cache_reserve => "cache/cache_reserve",
            .cache_reserve_clear => "cache/cache_reserve_clear",
            .regional_tiered_cache => "cache/regional_tiered_cache",
            .variants => "cache/variants",
            .environments => "environments",
            .hold => "hold",
            .subscription => "subscription",
        };
    }

    pub fn requiresPlanId(self: ZoneLifecycleReadEndpoint) bool {
        return self == .available_plan;
    }
};

pub const ZoneLifecycleMutationEndpoint = enum {
    change_cache_reserve,
    start_cache_reserve_clear,
    change_regional_tiered_cache,
    delete_variants,
    change_variants,
    create_environments,
    edit_environments,
    update_environments,
    delete_environment,
    rollback_environment,
    create_hold,
    update_hold,
    delete_hold,
    create_subscription,
    update_subscription,

    pub fn parse(value: []const u8) ?ZoneLifecycleMutationEndpoint {
        if (std.mem.eql(u8, value, "cache-reserve-change") or std.mem.eql(u8, value, "change-cache-reserve")) return .change_cache_reserve;
        if (std.mem.eql(u8, value, "cache-reserve-clear-start") or std.mem.eql(u8, value, "start-cache-reserve-clear")) return .start_cache_reserve_clear;
        if (std.mem.eql(u8, value, "regional-tiered-cache-change") or std.mem.eql(u8, value, "change-regional-tiered-cache")) return .change_regional_tiered_cache;
        if (std.mem.eql(u8, value, "variants-delete") or std.mem.eql(u8, value, "delete-variants")) return .delete_variants;
        if (std.mem.eql(u8, value, "variants-change") or std.mem.eql(u8, value, "change-variants")) return .change_variants;
        if (std.mem.eql(u8, value, "environments-create") or std.mem.eql(u8, value, "create-environments")) return .create_environments;
        if (std.mem.eql(u8, value, "environments-edit") or std.mem.eql(u8, value, "edit-environments")) return .edit_environments;
        if (std.mem.eql(u8, value, "environments-update") or std.mem.eql(u8, value, "update-environments")) return .update_environments;
        if (std.mem.eql(u8, value, "environment-delete") or std.mem.eql(u8, value, "delete-environment")) return .delete_environment;
        if (std.mem.eql(u8, value, "environment-rollback") or std.mem.eql(u8, value, "rollback-environment")) return .rollback_environment;
        if (std.mem.eql(u8, value, "hold-create") or std.mem.eql(u8, value, "create-hold")) return .create_hold;
        if (std.mem.eql(u8, value, "hold-update") or std.mem.eql(u8, value, "update-hold")) return .update_hold;
        if (std.mem.eql(u8, value, "hold-delete") or std.mem.eql(u8, value, "delete-hold")) return .delete_hold;
        if (std.mem.eql(u8, value, "subscription-create") or std.mem.eql(u8, value, "create-subscription")) return .create_subscription;
        if (std.mem.eql(u8, value, "subscription-update") or std.mem.eql(u8, value, "update-subscription")) return .update_subscription;
        return null;
    }

    pub fn commandName(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .change_cache_reserve => "cache-reserve-change",
            .start_cache_reserve_clear => "cache-reserve-clear-start",
            .change_regional_tiered_cache => "regional-tiered-cache-change",
            .delete_variants => "variants-delete",
            .change_variants => "variants-change",
            .create_environments => "environments-create",
            .edit_environments => "environments-edit",
            .update_environments => "environments-update",
            .delete_environment => "environment-delete",
            .rollback_environment => "environment-rollback",
            .create_hold => "hold-create",
            .update_hold => "hold-update",
            .delete_hold => "hold-delete",
            .create_subscription => "subscription-create",
            .update_subscription => "subscription-update",
        };
    }

    pub fn group(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .change_cache_reserve,
            .start_cache_reserve_clear,
            .change_regional_tiered_cache,
            .delete_variants,
            .change_variants,
            => "Zone Cache Settings",
            .create_environments,
            .edit_environments,
            .update_environments,
            .delete_environment,
            .rollback_environment,
            => "Zone Environments",
            .create_hold, .update_hold, .delete_hold => "Zone Holds",
            .create_subscription, .update_subscription => "Zone Subscription",
        };
    }

    pub fn method(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_variants, .delete_environment, .delete_hold => "DELETE",
            .change_cache_reserve,
            .change_regional_tiered_cache,
            .change_variants,
            .edit_environments,
            .update_hold,
            => "PATCH",
            .start_cache_reserve_clear,
            .create_environments,
            .rollback_environment,
            .create_hold,
            .create_subscription,
            => "POST",
            .update_environments, .update_subscription => "PUT",
        };
    }

    pub fn operationId(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .change_cache_reserve => "zone-cache-settings-change-cache-reserve-setting",
            .start_cache_reserve_clear => "zone-cache-settings-start-cache-reserve-clear",
            .change_regional_tiered_cache => "zone-cache-settings-change-regional-tiered-cache-setting",
            .delete_variants => "zone-cache-settings-delete-variants-setting",
            .change_variants => "zone-cache-settings-change-variants-setting",
            .create_environments => "zonesEnvironmentsCreate",
            .edit_environments => "zonesEnvironmentsEdit",
            .update_environments => "zonesEnvironmentsUpdate",
            .delete_environment => "zonesEnvironmentsDelete",
            .rollback_environment => "zonesEnvironmentsRollback",
            .create_hold => "zones-0-hold-post",
            .update_hold => "zones-0-hold-patch",
            .delete_hold => "zones-0-hold-delete",
            .create_subscription => "zone-subscription-create-zone-subscription",
            .update_subscription => "zone-subscription-update-zone-subscription",
        };
    }

    pub fn summary(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .change_cache_reserve => "Change Cache Reserve setting",
            .start_cache_reserve_clear => "Start Cache Reserve Clear",
            .change_regional_tiered_cache => "Change Regional Tiered Cache setting",
            .delete_variants => "Delete variants setting",
            .change_variants => "Change variants setting",
            .create_environments => "Create zone environments",
            .edit_environments => "Partially update zone environments",
            .update_environments => "Upsert zone environments",
            .delete_environment => "Delete zone environment",
            .rollback_environment => "Roll back zone environment",
            .create_hold => "Create Zone Hold",
            .update_hold => "Update Zone Hold",
            .delete_hold => "Remove Zone Hold",
            .create_subscription => "Create Zone Subscription",
            .update_subscription => "Update Zone Subscription",
        };
    }

    pub fn requestBodySchemaRef(self: ZoneLifecycleMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .change_cache_reserve => "inline:{value:#/components/schemas/cache-rules_cache_reserve_value}",
            .change_regional_tiered_cache => "inline:{value:#/components/schemas/cache-rules_regional_tiered_cache_value}",
            .change_variants => "inline:{value:#/components/schemas/cache-rules_variants_value}",
            .create_environments, .edit_environments, .update_environments => "#/components/schemas/kamino_environments_request",
            .update_hold => "inline:{hold_after?:string|null,include_subdomains?:bool}",
            .create_subscription, .update_subscription => "#/components/schemas/bill-subs-api_subscription-v2",
            .start_cache_reserve_clear,
            .delete_variants,
            .delete_environment,
            .rollback_environment,
            .create_hold,
            .delete_hold,
            => null,
        };
    }

    pub fn requiresEnvironmentId(self: ZoneLifecycleMutationEndpoint) bool {
        return self == .delete_environment or self == .rollback_environment;
    }

    pub fn pathSuffix(self: ZoneLifecycleMutationEndpoint) []const u8 {
        return switch (self) {
            .change_cache_reserve => "cache/cache_reserve",
            .start_cache_reserve_clear => "cache/cache_reserve_clear",
            .change_regional_tiered_cache => "cache/regional_tiered_cache",
            .delete_variants, .change_variants => "cache/variants",
            .create_environments, .edit_environments, .update_environments, .delete_environment, .rollback_environment => "environments",
            .create_hold, .update_hold, .delete_hold => "hold",
            .create_subscription, .update_subscription => "subscription",
        };
    }
};

pub const ZoneLifecycleMutationArgs = struct {
    zone_id: []const u8,
    environment_id: ?[]const u8 = null,
};

pub const SecondaryDnsZoneReadEndpoint = enum {
    primary,
    primary_status,
    secondary,

    pub fn parse(value: []const u8) ?SecondaryDnsZoneReadEndpoint {
        if (std.mem.eql(u8, value, "primary") or std.mem.eql(u8, value, "outgoing")) return .primary;
        if (std.mem.eql(u8, value, "primary-status") or std.mem.eql(u8, value, "outgoing-status")) return .primary_status;
        if (std.mem.eql(u8, value, "secondary") or std.mem.eql(u8, value, "incoming")) return .secondary;
        return null;
    }

    pub fn commandName(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary => "primary",
            .primary_status => "primary-status",
            .secondary => "secondary",
        };
    }

    pub fn label(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary => "secondary-dns-primary-zone",
            .primary_status => "secondary-dns-primary-zone-status",
            .secondary => "secondary-dns-secondary-zone",
        };
    }

    pub fn group(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary, .primary_status => "Secondary DNS (Primary Zone)",
            .secondary => "Secondary DNS (Secondary Zone)",
        };
    }

    pub fn operationId(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary => "secondary-dns-(-primary-zone)-primary-zone-configuration-details",
            .primary_status => "secondary-dns-(-primary-zone)-get-outgoing-zone-transfer-status",
            .secondary => "secondary-dns-(-secondary-zone)-secondary-zone-configuration-details",
        };
    }

    pub fn summary(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary => "Primary Zone Configuration Details",
            .primary_status => "Get Outgoing Zone Transfer Status",
            .secondary => "Secondary Zone Configuration Details",
        };
    }

    pub fn pathSuffix(self: SecondaryDnsZoneReadEndpoint) []const u8 {
        return switch (self) {
            .primary => "secondary_dns/outgoing",
            .primary_status => "secondary_dns/outgoing/status",
            .secondary => "secondary_dns/incoming",
        };
    }
};

pub const SecondaryDnsZoneMutationEndpoint = enum {
    primary_create,
    primary_update,
    primary_delete,
    primary_enable,
    primary_disable,
    primary_force_notify,
    secondary_create,
    secondary_update,
    secondary_delete,
    secondary_force_axfr,

    pub fn parse(value: []const u8) ?SecondaryDnsZoneMutationEndpoint {
        if (std.mem.eql(u8, value, "primary-create") or std.mem.eql(u8, value, "create-primary")) return .primary_create;
        if (std.mem.eql(u8, value, "primary-update") or std.mem.eql(u8, value, "update-primary")) return .primary_update;
        if (std.mem.eql(u8, value, "primary-delete") or std.mem.eql(u8, value, "delete-primary")) return .primary_delete;
        if (std.mem.eql(u8, value, "primary-enable") or std.mem.eql(u8, value, "enable-primary")) return .primary_enable;
        if (std.mem.eql(u8, value, "primary-disable") or std.mem.eql(u8, value, "disable-primary")) return .primary_disable;
        if (std.mem.eql(u8, value, "primary-force-notify") or std.mem.eql(u8, value, "force-notify")) return .primary_force_notify;
        if (std.mem.eql(u8, value, "secondary-create") or std.mem.eql(u8, value, "create-secondary")) return .secondary_create;
        if (std.mem.eql(u8, value, "secondary-update") or std.mem.eql(u8, value, "update-secondary")) return .secondary_update;
        if (std.mem.eql(u8, value, "secondary-delete") or std.mem.eql(u8, value, "delete-secondary")) return .secondary_delete;
        if (std.mem.eql(u8, value, "secondary-force-axfr") or std.mem.eql(u8, value, "force-axfr")) return .secondary_force_axfr;
        return null;
    }

    pub fn commandName(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_create => "primary-create",
            .primary_update => "primary-update",
            .primary_delete => "primary-delete",
            .primary_enable => "primary-enable",
            .primary_disable => "primary-disable",
            .primary_force_notify => "primary-force-notify",
            .secondary_create => "secondary-create",
            .secondary_update => "secondary-update",
            .secondary_delete => "secondary-delete",
            .secondary_force_axfr => "secondary-force-axfr",
        };
    }

    pub fn group(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_create,
            .primary_update,
            .primary_delete,
            .primary_enable,
            .primary_disable,
            .primary_force_notify,
            => "Secondary DNS (Primary Zone)",
            .secondary_create,
            .secondary_update,
            .secondary_delete,
            .secondary_force_axfr,
            => "Secondary DNS (Secondary Zone)",
        };
    }

    pub fn method(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_delete, .secondary_delete => "DELETE",
            .primary_update, .secondary_update => "PUT",
            .primary_create,
            .primary_enable,
            .primary_disable,
            .primary_force_notify,
            .secondary_create,
            .secondary_force_axfr,
            => "POST",
        };
    }

    pub fn operationId(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_create => "secondary-dns-(-primary-zone)-create-primary-zone-configuration",
            .primary_update => "secondary-dns-(-primary-zone)-update-primary-zone-configuration",
            .primary_delete => "secondary-dns-(-primary-zone)-delete-primary-zone-configuration",
            .primary_enable => "secondary-dns-(-primary-zone)-enable-outgoing-zone-transfers",
            .primary_disable => "secondary-dns-(-primary-zone)-disable-outgoing-zone-transfers",
            .primary_force_notify => "secondary-dns-(-primary-zone)-force-dns-notify",
            .secondary_create => "secondary-dns-(-secondary-zone)-create-secondary-zone-configuration",
            .secondary_update => "secondary-dns-(-secondary-zone)-update-secondary-zone-configuration",
            .secondary_delete => "secondary-dns-(-secondary-zone)-delete-secondary-zone-configuration",
            .secondary_force_axfr => "secondary-dns-(-secondary-zone)-force-axfr",
        };
    }

    pub fn summary(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_create => "Create Primary Zone Configuration",
            .primary_update => "Update Primary Zone Configuration",
            .primary_delete => "Delete Primary Zone Configuration",
            .primary_enable => "Enable Outgoing Zone Transfers",
            .primary_disable => "Disable Outgoing Zone Transfers",
            .primary_force_notify => "Force DNS NOTIFY",
            .secondary_create => "Create Secondary Zone Configuration",
            .secondary_update => "Update Secondary Zone Configuration",
            .secondary_delete => "Delete Secondary Zone Configuration",
            .secondary_force_axfr => "Force AXFR",
        };
    }

    pub fn requestBodySchemaRef(self: SecondaryDnsZoneMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .primary_create, .primary_update => "#/components/schemas/secondary-dns_single_request_outgoing",
            .secondary_create, .secondary_update => "#/components/schemas/secondary-dns_dns-secondary-secondary-zone",
            .primary_delete,
            .primary_enable,
            .primary_disable,
            .primary_force_notify,
            .secondary_delete,
            .secondary_force_axfr,
            => null,
        };
    }

    pub fn pathSuffix(self: SecondaryDnsZoneMutationEndpoint) []const u8 {
        return switch (self) {
            .primary_create, .primary_update, .primary_delete => "secondary_dns/outgoing",
            .primary_enable => "secondary_dns/outgoing/enable",
            .primary_disable => "secondary_dns/outgoing/disable",
            .primary_force_notify => "secondary_dns/outgoing/force_notify",
            .secondary_create, .secondary_update, .secondary_delete => "secondary_dns/incoming",
            .secondary_force_axfr => "secondary_dns/force_axfr",
        };
    }
};

pub const SecondaryDnsZoneMutationArgs = struct {
    zone_id: []const u8,
};

pub const DnssecMutationEndpoint = enum {
    delete_records,
    edit_status,

    pub fn parse(value: []const u8) ?DnssecMutationEndpoint {
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-records")) return .delete_records;
        if (std.mem.eql(u8, value, "edit") or std.mem.eql(u8, value, "edit-status")) return .edit_status;
        return null;
    }

    pub fn commandName(self: DnssecMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_records => "delete-records",
            .edit_status => "edit-status",
        };
    }

    pub fn group(self: DnssecMutationEndpoint) []const u8 {
        _ = self;
        return "DNSSEC";
    }

    pub fn method(self: DnssecMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_records => "DELETE",
            .edit_status => "PATCH",
        };
    }

    pub fn operationId(self: DnssecMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_records => "dnssec-delete-dnssec-records",
            .edit_status => "dnssec-edit-dnssec-status",
        };
    }

    pub fn summary(self: DnssecMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_records => "Delete DNSSEC records",
            .edit_status => "Edit DNSSEC Status",
        };
    }

    pub fn requestBodySchemaRef(self: DnssecMutationEndpoint) ?[]const u8 {
        _ = self;
        return null;
    }
};

pub const DnssecMutationArgs = struct {
    zone_id: []const u8,
};

pub fn accountsUrl(gpa: Allocator, host: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, accounts_path });
}

pub fn ipsUrl(gpa: Allocator, host: []const u8, networks: ?[]const u8) ![]u8 {
    const path = try ipsPath(gpa, networks);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn ipsPath(gpa: Allocator, networks: ?[]const u8) ![]u8 {
    const value = networks orelse return try gpa.dupe(u8, ips_path);
    const escaped = try pathEscape(gpa, value);
    defer gpa.free(escaped);
    return try std.fmt.allocPrint(gpa, "{s}?networks={s}", .{ ips_path, escaped });
}

pub fn accountEndpointUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: AccountEndpoint) ![]u8 {
    const path = try accountEndpointPath(gpa, account_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountEndpointPath(gpa: Allocator, account_id: []const u8, endpoint: AccountEndpoint) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    if (endpoint.suffix()) |suffix| {
        return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ accounts_path, escaped_account_id, suffix });
    }
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ accounts_path, escaped_account_id });
}

pub fn accountMutationPath(gpa: Allocator, endpoint: AccountMutationEndpoint, args: AccountMutationArgs) ![]u8 {
    if (!endpoint.requiresAccountId()) {
        return switch (endpoint) {
            .create => try gpa.dupe(u8, accounts_path),
            .batch_move => try std.fmt.allocPrint(gpa, "{s}/move", .{accounts_path}),
            else => unreachable,
        };
    }
    const account_id = args.account_id orelse return error.MissingCloudflareAccountId;
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    const account_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ accounts_path, escaped_account_id });
    defer gpa.free(account_path);
    return switch (endpoint) {
        .delete_account, .update => try gpa.dupe(u8, account_path),
        .move => try std.fmt.allocPrint(gpa, "{s}/move", .{account_path}),
        .update_profile => try std.fmt.allocPrint(gpa, "{s}/profile", .{account_path}),
        else => unreachable,
    };
}

pub fn accountMutationPlanJson(gpa: Allocator, endpoint: AccountMutationEndpoint, args: AccountMutationArgs) ![]u8 {
    const path = try accountMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn accountCollectionUrl(gpa: Allocator, host: []const u8, account_id: []const u8, collection: AccountCollection) ![]u8 {
    const path = try accountCollectionPath(gpa, account_id, collection);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountCollectionPath(gpa: Allocator, account_id: []const u8, collection: AccountCollection) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ accounts_path, escaped_account_id, collection.slug() });
}

pub fn accountResourceUrl(gpa: Allocator, host: []const u8, account_id: []const u8, collection: AccountCollection, resource_id: []const u8) ![]u8 {
    const path = try accountResourcePath(gpa, account_id, collection, resource_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountResourcePath(gpa: Allocator, account_id: []const u8, collection: AccountCollection, resource_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/{s}", .{ accounts_path, escaped_account_id, collection.slug(), escaped_resource_id });
}

pub fn accountMemberMutationPath(gpa: Allocator, endpoint: AccountMemberMutationEndpoint, args: AccountMemberMutationArgs) ![]u8 {
    if (endpoint.requiresMemberId()) {
        const member_id = args.member_id orelse return error.MissingCloudflareAccountMemberId;
        return try accountResourcePath(gpa, args.account_id, .members, member_id);
    }
    return try accountCollectionPath(gpa, args.account_id, .members);
}

pub fn accountMemberMutationPlanJson(gpa: Allocator, endpoint: AccountMemberMutationEndpoint, args: AccountMemberMutationArgs) ![]u8 {
    const path = try accountMemberMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn accountPermissionGroupsUrl(gpa: Allocator, host: []const u8, account_id: []const u8) ![]u8 {
    return try accountIamCollectionUrl(gpa, host, account_id, .permission_groups);
}

pub fn accountPermissionGroupsPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    return try accountIamCollectionPath(gpa, account_id, .permission_groups);
}

pub fn accountPermissionGroupUrl(gpa: Allocator, host: []const u8, account_id: []const u8, permission_group_id: []const u8) ![]u8 {
    return try accountIamResourceUrl(gpa, host, account_id, .permission_groups, permission_group_id);
}

pub fn accountPermissionGroupPath(gpa: Allocator, account_id: []const u8, permission_group_id: []const u8) ![]u8 {
    return try accountIamResourcePath(gpa, account_id, .permission_groups, permission_group_id);
}

pub fn accountIamCollectionUrl(gpa: Allocator, host: []const u8, account_id: []const u8, collection: AccountIamCollection) ![]u8 {
    const path = try accountIamCollectionPath(gpa, account_id, collection);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountIamCollectionPath(gpa: Allocator, account_id: []const u8, collection: AccountIamCollection) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/iam/{s}", .{ accounts_path, escaped_account_id, collection.slug() });
}

pub fn accountIamResourceUrl(gpa: Allocator, host: []const u8, account_id: []const u8, collection: AccountIamCollection, resource_id: []const u8) ![]u8 {
    const path = try accountIamResourcePath(gpa, account_id, collection, resource_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountIamResourcePath(gpa: Allocator, account_id: []const u8, collection: AccountIamCollection, resource_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/iam/{s}/{s}", .{ accounts_path, escaped_account_id, collection.slug(), escaped_resource_id });
}

pub fn accountIamGroupMutationPath(gpa: Allocator, endpoint: AccountIamGroupMutationEndpoint, args: AccountIamGroupMutationArgs) ![]u8 {
    if (!args.collection.supportsGroupMutation()) return error.UnsupportedCloudflareAccountIamGroupMutation;
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return error.MissingCloudflareAccountIamGroupId;
        return try accountIamResourcePath(gpa, args.account_id, args.collection, resource_id);
    }
    return try accountIamCollectionPath(gpa, args.account_id, args.collection);
}

pub fn accountIamGroupMutationPlanJson(gpa: Allocator, endpoint: AccountIamGroupMutationEndpoint, args: AccountIamGroupMutationArgs) ![]u8 {
    const path = try accountIamGroupMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = try endpoint.group(args.collection),
        .operation = endpoint.commandName(),
        .operation_id = try endpoint.operationId(args.collection),
        .summary = try endpoint.summary(args.collection),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = try endpoint.requestBodySchemaRef(args.collection),
    });
}

pub fn accountUserGroupMembersUrl(gpa: Allocator, host: []const u8, account_id: []const u8, user_group_id: []const u8) ![]u8 {
    const path = try accountUserGroupMembersPath(gpa, account_id, user_group_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountUserGroupMembersPath(gpa: Allocator, account_id: []const u8, user_group_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    const escaped_user_group_id = try pathEscape(gpa, user_group_id);
    defer gpa.free(escaped_user_group_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/iam/user_groups/{s}/members", .{ accounts_path, escaped_account_id, escaped_user_group_id });
}

pub fn accountUserGroupMemberUrl(gpa: Allocator, host: []const u8, account_id: []const u8, user_group_id: []const u8, member_id: []const u8) ![]u8 {
    const path = try accountUserGroupMemberPath(gpa, account_id, user_group_id, member_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountUserGroupMemberPath(gpa: Allocator, account_id: []const u8, user_group_id: []const u8, member_id: []const u8) ![]u8 {
    const members_path = try accountUserGroupMembersPath(gpa, account_id, user_group_id);
    defer gpa.free(members_path);
    const escaped_member_id = try pathEscape(gpa, member_id);
    defer gpa.free(escaped_member_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ members_path, escaped_member_id });
}

pub fn accountUserGroupMemberMutationPath(gpa: Allocator, endpoint: AccountUserGroupMemberMutationEndpoint, args: AccountUserGroupMemberMutationArgs) ![]u8 {
    if (endpoint.requiresMemberId()) {
        const member_id = args.member_id orelse return error.MissingCloudflareAccountUserGroupMemberId;
        return try accountUserGroupMemberPath(gpa, args.account_id, args.user_group_id, member_id);
    }
    return try accountUserGroupMembersPath(gpa, args.account_id, args.user_group_id);
}

pub fn accountUserGroupMemberMutationPlanJson(gpa: Allocator, endpoint: AccountUserGroupMemberMutationEndpoint, args: AccountUserGroupMemberMutationArgs) ![]u8 {
    const path = try accountUserGroupMemberMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn secondaryDnsAccountCollectionUrl(gpa: Allocator, host: []const u8, account_id: []const u8, resource: SecondaryDnsAccountResource) ![]u8 {
    const path = try secondaryDnsAccountCollectionPath(gpa, account_id, resource);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn secondaryDnsAccountCollectionPath(gpa: Allocator, account_id: []const u8, resource: SecondaryDnsAccountResource) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/secondary_dns/{s}", .{ accounts_path, escaped_account_id, resource.slug() });
}

pub fn secondaryDnsAccountResourceUrl(gpa: Allocator, host: []const u8, account_id: []const u8, resource: SecondaryDnsAccountResource, resource_id: []const u8) ![]u8 {
    const path = try secondaryDnsAccountResourcePath(gpa, account_id, resource, resource_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn secondaryDnsAccountResourcePath(gpa: Allocator, account_id: []const u8, resource: SecondaryDnsAccountResource, resource_id: []const u8) ![]u8 {
    const collection_path = try secondaryDnsAccountCollectionPath(gpa, account_id, resource);
    defer gpa.free(collection_path);
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
}

pub fn secondaryDnsAccountMutationPath(gpa: Allocator, endpoint: SecondaryDnsAccountMutationEndpoint, args: SecondaryDnsAccountMutationArgs) ![]u8 {
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return error.MissingCloudflareSecondaryDnsResourceId;
        return try secondaryDnsAccountResourcePath(gpa, args.account_id, args.resource, resource_id);
    }
    return try secondaryDnsAccountCollectionPath(gpa, args.account_id, args.resource);
}

pub fn secondaryDnsAccountMutationPlanJson(gpa: Allocator, endpoint: SecondaryDnsAccountMutationEndpoint, args: SecondaryDnsAccountMutationArgs) ![]u8 {
    const path = try secondaryDnsAccountMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.resource.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.resource),
        .summary = endpoint.summary(args.resource),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(args.resource),
    });
}

pub fn dnsFirewallReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: DnsFirewallReadEndpoint, dns_firewall_id: ?[]const u8) ![]u8 {
    const path = try dnsFirewallReadPath(gpa, account_id, endpoint, dns_firewall_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dnsFirewallCollectionPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/dns_firewall", .{ accounts_path, escaped_account_id });
}

pub fn dnsFirewallResourcePath(gpa: Allocator, account_id: []const u8, dns_firewall_id: []const u8) ![]u8 {
    const collection_path = try dnsFirewallCollectionPath(gpa, account_id);
    defer gpa.free(collection_path);
    const escaped_firewall_id = try pathEscape(gpa, dns_firewall_id);
    defer gpa.free(escaped_firewall_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_firewall_id });
}

pub fn dnsFirewallReadPath(gpa: Allocator, account_id: []const u8, endpoint: DnsFirewallReadEndpoint, dns_firewall_id: ?[]const u8) ![]u8 {
    if (!endpoint.requiresFirewallId()) return try dnsFirewallCollectionPath(gpa, account_id);
    const id = dns_firewall_id orelse return error.MissingCloudflareDnsFirewallId;
    const resource_path = try dnsFirewallResourcePath(gpa, account_id, id);
    defer gpa.free(resource_path);
    return switch (endpoint) {
        .details => try gpa.dupe(u8, resource_path),
        .reverse_dns => try std.fmt.allocPrint(gpa, "{s}/reverse_dns", .{resource_path}),
        .list => unreachable,
    };
}

pub fn dnsFirewallMutationPath(gpa: Allocator, endpoint: DnsFirewallMutationEndpoint, args: DnsFirewallMutationArgs) ![]u8 {
    if (!endpoint.requiresFirewallId()) return try dnsFirewallCollectionPath(gpa, args.account_id);
    const id = args.dns_firewall_id orelse return error.MissingCloudflareDnsFirewallId;
    const resource_path = try dnsFirewallResourcePath(gpa, args.account_id, id);
    defer gpa.free(resource_path);
    if (endpoint == .update_reverse_dns) return try std.fmt.allocPrint(gpa, "{s}/reverse_dns", .{resource_path});
    return try gpa.dupe(u8, resource_path);
}

pub fn dnsFirewallMutationPlanJson(gpa: Allocator, endpoint: DnsFirewallMutationEndpoint, args: DnsFirewallMutationArgs) ![]u8 {
    const path = try dnsFirewallMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn dnsFirewallAnalyticsUrl(gpa: Allocator, host: []const u8, account_id: []const u8, dns_firewall_id: []const u8, endpoint: DnsAnalyticsEndpoint) ![]u8 {
    const path = try dnsFirewallAnalyticsPath(gpa, account_id, dns_firewall_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dnsFirewallAnalyticsPath(gpa: Allocator, account_id: []const u8, dns_firewall_id: []const u8, endpoint: DnsAnalyticsEndpoint) ![]u8 {
    const resource_path = try dnsFirewallResourcePath(gpa, account_id, dns_firewall_id);
    defer gpa.free(resource_path);
    return try std.fmt.allocPrint(gpa, "{s}/dns_analytics/{s}", .{ resource_path, endpoint.suffix() });
}

pub fn dnsSettingsMutationPath(gpa: Allocator, endpoint: DnsSettingsMutationEndpoint, args: DnsSettingsMutationArgs) ![]u8 {
    return switch (endpoint) {
        .account => blk: {
            const account_id = args.account_id orelse return error.MissingCloudflareAccountId;
            break :blk try accountDnsSettingsPath(gpa, account_id);
        },
        .zone => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            const base_path = try zonePath(gpa, zone_id);
            defer gpa.free(base_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/dns_settings", .{base_path});
        },
    };
}

pub fn dnsSettingsMutationPlanJson(gpa: Allocator, endpoint: DnsSettingsMutationEndpoint, args: DnsSettingsMutationArgs) ![]u8 {
    const path = try dnsSettingsMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn loadBalancingAccountReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8) ![]u8 {
    const path = try loadBalancingAccountReadPath(gpa, account_id, endpoint, resource_id, search_query);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn loadBalancingAccountBasePath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/load_balancers", .{ accounts_path, escaped_account_id });
}

pub fn loadBalancingAccountCollectionPath(gpa: Allocator, account_id: []const u8, slug: []const u8) ![]u8 {
    const base_path = try loadBalancingAccountBasePath(gpa, account_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, slug });
}

pub fn loadBalancingAccountResourcePath(gpa: Allocator, account_id: []const u8, slug: []const u8, resource_id: []const u8) ![]u8 {
    const collection_path = try loadBalancingAccountCollectionPath(gpa, account_id, slug);
    defer gpa.free(collection_path);
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
}

pub fn loadBalancingAccountReadPath(gpa: Allocator, account_id: []const u8, endpoint: LoadBalancingAccountReadEndpoint, resource_id: ?[]const u8, search_query: ?[]const u8) ![]u8 {
    switch (endpoint) {
        .monitor_groups => return try loadBalancingAccountCollectionPath(gpa, account_id, "monitor_groups"),
        .monitors => return try loadBalancingAccountCollectionPath(gpa, account_id, "monitors"),
        .pools => return try loadBalancingAccountCollectionPath(gpa, account_id, "pools"),
        .regions => return try loadBalancingAccountCollectionPath(gpa, account_id, "regions"),
        .search => {
            const base_path = try loadBalancingAccountCollectionPath(gpa, account_id, "search");
            defer gpa.free(base_path);
            const query = search_query orelse return try gpa.dupe(u8, base_path);
            const escaped_query = try pathEscape(gpa, query);
            defer gpa.free(escaped_query);
            return try std.fmt.allocPrint(gpa, "{s}?query={s}", .{ base_path, escaped_query });
        },
        .monitor_group, .monitor_group_references, .monitor, .monitor_references, .monitor_preview_result, .pool, .pool_health, .pool_references, .region => {},
    }
    const id = resource_id orelse return error.MissingCloudflareLoadBalancingResourceId;
    return switch (endpoint) {
        .monitor_group => try loadBalancingAccountResourcePath(gpa, account_id, "monitor_groups", id),
        .monitor_group_references => blk: {
            const resource_path = try loadBalancingAccountResourcePath(gpa, account_id, "monitor_groups", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/references", .{resource_path});
        },
        .monitor => try loadBalancingAccountResourcePath(gpa, account_id, "monitors", id),
        .monitor_references => blk: {
            const resource_path = try loadBalancingAccountResourcePath(gpa, account_id, "monitors", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/references", .{resource_path});
        },
        .monitor_preview_result => blk: {
            const base_path = try loadBalancingAccountBasePath(gpa, account_id);
            defer gpa.free(base_path);
            const escaped_id = try pathEscape(gpa, id);
            defer gpa.free(escaped_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/preview/{s}", .{ base_path, escaped_id });
        },
        .pool => try loadBalancingAccountResourcePath(gpa, account_id, "pools", id),
        .pool_health => blk: {
            const resource_path = try loadBalancingAccountResourcePath(gpa, account_id, "pools", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/health", .{resource_path});
        },
        .pool_references => blk: {
            const resource_path = try loadBalancingAccountResourcePath(gpa, account_id, "pools", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/references", .{resource_path});
        },
        .region => try loadBalancingAccountResourcePath(gpa, account_id, "regions", id),
        .monitor_groups, .monitors, .pools, .regions, .search => unreachable,
    };
}

pub fn loadBalancingUserReadUrl(gpa: Allocator, host: []const u8, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8) ![]u8 {
    const path = try loadBalancingUserReadPath(gpa, endpoint, resource_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn loadBalancingUserBasePath(gpa: Allocator) ![]u8 {
    return try gpa.dupe(u8, "/user/load_balancers");
}

pub fn loadBalancingUserCollectionPath(gpa: Allocator, slug: []const u8) ![]u8 {
    const base_path = try loadBalancingUserBasePath(gpa);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, slug });
}

pub fn loadBalancingUserResourcePath(gpa: Allocator, slug: []const u8, resource_id: []const u8) ![]u8 {
    const collection_path = try loadBalancingUserCollectionPath(gpa, slug);
    defer gpa.free(collection_path);
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
}

pub fn loadBalancingUserReadPath(gpa: Allocator, endpoint: LoadBalancingUserReadEndpoint, resource_id: ?[]const u8) ![]u8 {
    switch (endpoint) {
        .monitors => return try loadBalancingUserCollectionPath(gpa, "monitors"),
        .pools => return try loadBalancingUserCollectionPath(gpa, "pools"),
        .healthcheck_events => return try gpa.dupe(u8, "/user/load_balancing_analytics/events"),
        .monitor, .monitor_references, .monitor_preview_result, .pool, .pool_health, .pool_references => {},
    }
    const id = resource_id orelse return error.MissingCloudflareLoadBalancingResourceId;
    return switch (endpoint) {
        .monitor => try loadBalancingUserResourcePath(gpa, "monitors", id),
        .monitor_references => blk: {
            const resource_path = try loadBalancingUserResourcePath(gpa, "monitors", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/references", .{resource_path});
        },
        .monitor_preview_result => blk: {
            const base_path = try loadBalancingUserBasePath(gpa);
            defer gpa.free(base_path);
            const escaped_id = try pathEscape(gpa, id);
            defer gpa.free(escaped_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/preview/{s}", .{ base_path, escaped_id });
        },
        .pool => try loadBalancingUserResourcePath(gpa, "pools", id),
        .pool_health => blk: {
            const resource_path = try loadBalancingUserResourcePath(gpa, "pools", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/health", .{resource_path});
        },
        .pool_references => blk: {
            const resource_path = try loadBalancingUserResourcePath(gpa, "pools", id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/references", .{resource_path});
        },
        .monitors, .pools, .healthcheck_events => unreachable,
    };
}

pub fn loadBalancingZoneReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: LoadBalancingZoneReadEndpoint, load_balancer_id: ?[]const u8) ![]u8 {
    const path = try loadBalancingZoneReadPath(gpa, zone_id, endpoint, load_balancer_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn loadBalancingZoneCollectionPath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/load_balancers", .{base_path});
}

pub fn loadBalancingZoneResourcePath(gpa: Allocator, zone_id: []const u8, load_balancer_id: []const u8) ![]u8 {
    const collection_path = try loadBalancingZoneCollectionPath(gpa, zone_id);
    defer gpa.free(collection_path);
    const escaped_id = try pathEscape(gpa, load_balancer_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn loadBalancingZoneReadPath(gpa: Allocator, zone_id: []const u8, endpoint: LoadBalancingZoneReadEndpoint, load_balancer_id: ?[]const u8) ![]u8 {
    return switch (endpoint) {
        .load_balancers => try loadBalancingZoneCollectionPath(gpa, zone_id),
        .load_balancer => blk: {
            const id = load_balancer_id orelse return error.MissingCloudflareLoadBalancingResourceId;
            break :blk try loadBalancingZoneResourcePath(gpa, zone_id, id);
        },
    };
}

pub fn loadBalancingMutationPath(gpa: Allocator, endpoint: LoadBalancingMutationEndpoint, args: LoadBalancingMutationArgs) ![]u8 {
    if (!endpoint.supports(args.resource)) return error.UnsupportedCloudflareLoadBalancingMutation;
    const collection_path = switch (args.resource) {
        .account_monitor_group, .account_monitor, .account_pool => blk: {
            const account_id = args.account_id orelse return error.MissingCloudflareAccountId;
            break :blk try loadBalancingAccountCollectionPath(gpa, account_id, args.resource.collectionSlug());
        },
        .user_monitor, .user_pool => try loadBalancingUserCollectionPath(gpa, args.resource.collectionSlug()),
        .zone_load_balancer => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            break :blk try loadBalancingZoneCollectionPath(gpa, zone_id);
        },
    };
    defer gpa.free(collection_path);
    if (!endpoint.requiresResourceId()) return try gpa.dupe(u8, collection_path);
    const id = args.resource_id orelse return error.MissingCloudflareLoadBalancingResourceId;
    const escaped_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_id);
    const resource_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
    defer gpa.free(resource_path);
    if (endpoint == .preview) return try std.fmt.allocPrint(gpa, "{s}/preview", .{resource_path});
    return try gpa.dupe(u8, resource_path);
}

pub fn loadBalancingMutationPlanJson(gpa: Allocator, endpoint: LoadBalancingMutationEndpoint, args: LoadBalancingMutationArgs) ![]u8 {
    const path = try loadBalancingMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.resource.group(),
        .operation = endpoint.commandName(),
        .operation_id = try endpoint.operationId(args.resource),
        .summary = try endpoint.summary(args.resource),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = try endpoint.requestBodySchemaRef(args.resource),
    });
}

pub fn endpointHealthCheckReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    const path = try endpointHealthCheckReadPath(gpa, account_id, endpoint, healthcheck_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn endpointHealthCheckCollectionPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/diagnostics/endpoint-healthchecks", .{ accounts_path, escaped_account_id });
}

pub fn endpointHealthCheckResourcePath(gpa: Allocator, account_id: []const u8, healthcheck_id: []const u8) ![]u8 {
    const collection_path = try endpointHealthCheckCollectionPath(gpa, account_id);
    defer gpa.free(collection_path);
    const escaped_id = try pathEscape(gpa, healthcheck_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn endpointHealthCheckReadPath(gpa: Allocator, account_id: []const u8, endpoint: EndpointHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    return switch (endpoint) {
        .list => try endpointHealthCheckCollectionPath(gpa, account_id),
        .details => blk: {
            const id = healthcheck_id orelse return error.MissingCloudflareHealthCheckId;
            break :blk try endpointHealthCheckResourcePath(gpa, account_id, id);
        },
    };
}

pub fn zoneHealthCheckReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: ZoneHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    const path = try zoneHealthCheckReadPath(gpa, zone_id, endpoint, healthcheck_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zoneHealthCheckCollectionPath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/healthchecks", .{base_path});
}

pub fn zoneHealthCheckResourcePath(gpa: Allocator, zone_id: []const u8, healthcheck_id: []const u8) ![]u8 {
    const collection_path = try zoneHealthCheckCollectionPath(gpa, zone_id);
    defer gpa.free(collection_path);
    const escaped_id = try pathEscape(gpa, healthcheck_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn zoneHealthCheckPreviewCollectionPath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const collection_path = try zoneHealthCheckCollectionPath(gpa, zone_id);
    defer gpa.free(collection_path);
    return try std.fmt.allocPrint(gpa, "{s}/preview", .{collection_path});
}

pub fn zoneHealthCheckPreviewResourcePath(gpa: Allocator, zone_id: []const u8, healthcheck_id: []const u8) ![]u8 {
    const collection_path = try zoneHealthCheckPreviewCollectionPath(gpa, zone_id);
    defer gpa.free(collection_path);
    const escaped_id = try pathEscape(gpa, healthcheck_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn zoneHealthCheckReadPath(gpa: Allocator, zone_id: []const u8, endpoint: ZoneHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    return switch (endpoint) {
        .list => try zoneHealthCheckCollectionPath(gpa, zone_id),
        .details => blk: {
            const id = healthcheck_id orelse return error.MissingCloudflareHealthCheckId;
            break :blk try zoneHealthCheckResourcePath(gpa, zone_id, id);
        },
        .preview_details => blk: {
            const id = healthcheck_id orelse return error.MissingCloudflareHealthCheckId;
            break :blk try zoneHealthCheckPreviewResourcePath(gpa, zone_id, id);
        },
    };
}

pub fn smartShieldHealthCheckReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: SmartShieldHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    const path = try smartShieldHealthCheckReadPath(gpa, zone_id, endpoint, healthcheck_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn smartShieldHealthCheckCollectionPath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/smart_shield/healthchecks", .{base_path});
}

pub fn smartShieldHealthCheckResourcePath(gpa: Allocator, zone_id: []const u8, healthcheck_id: []const u8) ![]u8 {
    const collection_path = try smartShieldHealthCheckCollectionPath(gpa, zone_id);
    defer gpa.free(collection_path);
    const escaped_id = try pathEscape(gpa, healthcheck_id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn smartShieldHealthCheckReadPath(gpa: Allocator, zone_id: []const u8, endpoint: SmartShieldHealthCheckReadEndpoint, healthcheck_id: ?[]const u8) ![]u8 {
    return switch (endpoint) {
        .list => try smartShieldHealthCheckCollectionPath(gpa, zone_id),
        .details => blk: {
            const id = healthcheck_id orelse return error.MissingCloudflareHealthCheckId;
            break :blk try smartShieldHealthCheckResourcePath(gpa, zone_id, id);
        },
    };
}

pub fn healthCheckMutationPath(gpa: Allocator, endpoint: HealthCheckMutationEndpoint, args: HealthCheckMutationArgs) ![]u8 {
    if (!endpoint.supports(args.resource)) return error.UnsupportedCloudflareHealthCheckMutation;
    const collection_path = switch (args.resource) {
        .endpoint => blk: {
            const account_id = args.account_id orelse return error.MissingCloudflareAccountId;
            break :blk try endpointHealthCheckCollectionPath(gpa, account_id);
        },
        .zone => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            break :blk try zoneHealthCheckCollectionPath(gpa, zone_id);
        },
        .preview => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            break :blk try zoneHealthCheckPreviewCollectionPath(gpa, zone_id);
        },
        .smart_shield => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            break :blk try smartShieldHealthCheckCollectionPath(gpa, zone_id);
        },
    };
    defer gpa.free(collection_path);
    if (!endpoint.requiresHealthCheckId()) return try gpa.dupe(u8, collection_path);
    const id = args.healthcheck_id orelse return error.MissingCloudflareHealthCheckId;
    const escaped_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn healthCheckMutationPlanJson(gpa: Allocator, endpoint: HealthCheckMutationEndpoint, args: HealthCheckMutationArgs) ![]u8 {
    const path = try healthCheckMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.resource.group(),
        .operation = endpoint.commandName(),
        .operation_id = try endpoint.operationId(args.resource),
        .summary = try endpoint.summary(args.resource),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = try endpoint.requestBodySchemaRef(args.resource),
    });
}

pub fn rulesetReadUrl(gpa: Allocator, host: []const u8, scope: RulesetScope, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) ![]u8 {
    const path = try rulesetReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(path);
    if (endpoint == .list) {
        return try std.fmt.allocPrint(gpa, "{s}{s}?per_page=50", .{ host, path });
    }
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn rulesetCollectionPath(gpa: Allocator, scope: RulesetScope, scope_id: []const u8) ![]u8 {
    const escaped_scope_id = try pathEscape(gpa, scope_id);
    defer gpa.free(escaped_scope_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/rulesets", .{ scope.basePath(), escaped_scope_id });
}

pub fn rulesetResourcePath(gpa: Allocator, scope: RulesetScope, scope_id: []const u8, ruleset_id: []const u8) ![]u8 {
    const collection_path = try rulesetCollectionPath(gpa, scope, scope_id);
    defer gpa.free(collection_path);
    const escaped_ruleset_id = try pathEscape(gpa, ruleset_id);
    defer gpa.free(escaped_ruleset_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_ruleset_id });
}

pub fn rulesetEntrypointPath(gpa: Allocator, scope: RulesetScope, scope_id: []const u8, phase: []const u8) ![]u8 {
    const collection_path = try rulesetCollectionPath(gpa, scope, scope_id);
    defer gpa.free(collection_path);
    const escaped_phase = try pathEscape(gpa, phase);
    defer gpa.free(escaped_phase);
    return try std.fmt.allocPrint(gpa, "{s}/phases/{s}/entrypoint", .{ collection_path, escaped_phase });
}

pub fn rulesetReadPath(gpa: Allocator, scope: RulesetScope, scope_id: []const u8, endpoint: RulesetReadEndpoint, args: RulesetReadArgs) ![]u8 {
    return switch (endpoint) {
        .list => try rulesetCollectionPath(gpa, scope, scope_id),
        .ruleset => blk: {
            const ruleset_id = args.ruleset_id orelse return error.MissingCloudflareRulesetId;
            break :blk try rulesetResourcePath(gpa, scope, scope_id, ruleset_id);
        },
        .entrypoint => blk: {
            const phase = args.phase orelse return error.MissingCloudflareRulesetPhase;
            break :blk try rulesetEntrypointPath(gpa, scope, scope_id, phase);
        },
        .entrypoint_versions => blk: {
            const phase = args.phase orelse return error.MissingCloudflareRulesetPhase;
            const entrypoint_path = try rulesetEntrypointPath(gpa, scope, scope_id, phase);
            defer gpa.free(entrypoint_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/versions", .{entrypoint_path});
        },
        .entrypoint_version => blk: {
            const phase = args.phase orelse return error.MissingCloudflareRulesetPhase;
            const version = args.version orelse return error.MissingCloudflareRulesetVersion;
            const entrypoint_path = try rulesetEntrypointPath(gpa, scope, scope_id, phase);
            defer gpa.free(entrypoint_path);
            const escaped_version = try pathEscape(gpa, version);
            defer gpa.free(escaped_version);
            break :blk try std.fmt.allocPrint(gpa, "{s}/versions/{s}", .{ entrypoint_path, escaped_version });
        },
        .versions => blk: {
            const ruleset_id = args.ruleset_id orelse return error.MissingCloudflareRulesetId;
            const resource_path = try rulesetResourcePath(gpa, scope, scope_id, ruleset_id);
            defer gpa.free(resource_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/versions", .{resource_path});
        },
        .version, .rules_by_tag => blk: {
            const ruleset_id = args.ruleset_id orelse return error.MissingCloudflareRulesetId;
            const version = args.version orelse return error.MissingCloudflareRulesetVersion;
            const resource_path = try rulesetResourcePath(gpa, scope, scope_id, ruleset_id);
            defer gpa.free(resource_path);
            const escaped_version = try pathEscape(gpa, version);
            defer gpa.free(escaped_version);
            const version_path = try std.fmt.allocPrint(gpa, "{s}/versions/{s}", .{ resource_path, escaped_version });
            defer gpa.free(version_path);
            if (endpoint == .version) break :blk try gpa.dupe(u8, version_path);
            const rule_tag = args.rule_tag orelse return error.MissingCloudflareRulesetRuleTag;
            const escaped_rule_tag = try pathEscape(gpa, rule_tag);
            defer gpa.free(escaped_rule_tag);
            break :blk try std.fmt.allocPrint(gpa, "{s}/by_tag/{s}", .{ version_path, escaped_rule_tag });
        },
    };
}

pub fn rulesetMutationPath(gpa: Allocator, endpoint: RulesetMutationEndpoint, args: RulesetMutationArgs) ![]u8 {
    if (endpoint.requiresPhase()) {
        const phase = args.phase orelse return error.MissingCloudflareRulesetPhase;
        return try rulesetEntrypointPath(gpa, args.scope, args.scope_id, phase);
    }

    const collection_path = try rulesetCollectionPath(gpa, args.scope, args.scope_id);
    defer gpa.free(collection_path);

    if (!endpoint.requiresRulesetId()) return try gpa.dupe(u8, collection_path);
    const ruleset_id = args.ruleset_id orelse return error.MissingCloudflareRulesetId;
    const escaped_ruleset_id = try pathEscape(gpa, ruleset_id);
    defer gpa.free(escaped_ruleset_id);
    const ruleset_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_ruleset_id });
    defer gpa.free(ruleset_path);

    if (endpoint == .create_rule) return try std.fmt.allocPrint(gpa, "{s}/rules", .{ruleset_path});

    if (endpoint.requiresRuleId()) {
        const rule_id = args.rule_id orelse return error.MissingCloudflareRulesetRuleId;
        const escaped_rule_id = try pathEscape(gpa, rule_id);
        defer gpa.free(escaped_rule_id);
        return try std.fmt.allocPrint(gpa, "{s}/rules/{s}", .{ ruleset_path, escaped_rule_id });
    }

    if (endpoint.requiresVersion()) {
        const version = args.version orelse return error.MissingCloudflareRulesetVersion;
        const escaped_version = try pathEscape(gpa, version);
        defer gpa.free(escaped_version);
        return try std.fmt.allocPrint(gpa, "{s}/versions/{s}", .{ ruleset_path, escaped_version });
    }

    return try gpa.dupe(u8, ruleset_path);
}

pub fn rulesetMutationPlanJson(gpa: Allocator, endpoint: RulesetMutationEndpoint, args: RulesetMutationArgs) ![]u8 {
    const path = try rulesetMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.scope.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.scope),
        .summary = endpoint.summary(args.scope),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn cloudforceOneRuleReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) ![]u8 {
    const path = try cloudforceOneRuleReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn cloudforceOneRuleCollectionPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ accounts_path, escaped_account_id, cloudforce_one_rules_base_path });
}

pub fn cloudforceOneRuleReadPath(gpa: Allocator, account_id: []const u8, endpoint: CloudforceOneRuleReadEndpoint, args: CloudforceOneRuleReadArgs) ![]u8 {
    const base_path = try cloudforceOneRuleCollectionPath(gpa, account_id);
    defer gpa.free(base_path);

    return switch (endpoint) {
        .list => try appendCloudforceOneRuleFilters(gpa, base_path, args, false),
        .managed => try std.fmt.allocPrint(gpa, "{s}/managed", .{base_path}),
        .search => blk: {
            if (args.query == null) return error.MissingCloudforceOneRuleSearchQuery;
            const search_path = try std.fmt.allocPrint(gpa, "{s}/search", .{base_path});
            defer gpa.free(search_path);
            break :blk try appendCloudforceOneRuleFilters(gpa, search_path, args, true);
        },
        .stats => try std.fmt.allocPrint(gpa, "{s}/stats", .{base_path}),
        .tree => try std.fmt.allocPrint(gpa, "{s}/tree", .{base_path}),
        .rule => blk: {
            const rule_id = args.rule_id orelse return error.MissingCloudforceOneRuleId;
            const escaped_rule_id = try pathEscape(gpa, rule_id);
            defer gpa.free(escaped_rule_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
        },
    };
}

pub fn cloudforceOneRuleMutationPath(gpa: Allocator, endpoint: CloudforceOneRuleMutationEndpoint, args: CloudforceOneRuleMutationArgs) ![]u8 {
    const base_path = try cloudforceOneRuleCollectionPath(gpa, args.account_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .create, .delete_all => try gpa.dupe(u8, base_path),
        .validate => try std.fmt.allocPrint(gpa, "{s}/validate", .{base_path}),
        .update, .delete_rule => blk: {
            const rule_id = args.rule_id orelse return error.MissingCloudforceOneRuleId;
            const escaped_rule_id = try pathEscape(gpa, rule_id);
            defer gpa.free(escaped_rule_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
        },
    };
}

pub fn cloudforceOneRuleMutationPlanJson(gpa: Allocator, endpoint: CloudforceOneRuleMutationEndpoint, args: CloudforceOneRuleMutationArgs) ![]u8 {
    const path = try cloudforceOneRuleMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = "Rules",
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn ipAccessRuleReadUrl(gpa: Allocator, host: []const u8, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) ![]u8 {
    const path = try ipAccessRuleReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn ipAccessRuleCollectionPath(gpa: Allocator, scope: IpAccessRuleScope, scope_id: ?[]const u8) ![]u8 {
    if (!scope.usesScopeId()) return try std.fmt.allocPrint(gpa, "{s}{s}", .{ user_path, firewall_access_rules_path });
    const id = scope_id orelse return error.MissingCloudflareIpAccessRuleScopeId;
    const escaped_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ scope.basePath(), escaped_id, firewall_access_rules_path });
}

pub fn ipAccessRuleReadPath(gpa: Allocator, scope: IpAccessRuleScope, scope_id: ?[]const u8, endpoint: IpAccessRuleReadEndpoint, args: IpAccessRuleListArgs) ![]u8 {
    if (!endpoint.supports(scope)) return error.UnsupportedCloudflareIpAccessRuleEndpoint;
    const base_path = try ipAccessRuleCollectionPath(gpa, scope, scope_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .list => try appendIpAccessRuleFilters(gpa, base_path, args),
        .rule => blk: {
            const rule_id = args.rule_id orelse return error.MissingCloudflareIpAccessRuleId;
            const escaped_rule_id = try pathEscape(gpa, rule_id);
            defer gpa.free(escaped_rule_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
        },
    };
}

pub fn ipAccessRuleMutationPath(gpa: Allocator, endpoint: IpAccessRuleMutationEndpoint, args: IpAccessRuleMutationArgs) ![]u8 {
    const base_path = try ipAccessRuleCollectionPath(gpa, args.scope, args.scope_id);
    defer gpa.free(base_path);
    if (!endpoint.requiresRuleId()) return try gpa.dupe(u8, base_path);
    const rule_id = args.rule_id orelse return error.MissingCloudflareIpAccessRuleId;
    const escaped_rule_id = try pathEscape(gpa, rule_id);
    defer gpa.free(escaped_rule_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
}

pub fn ipAccessRuleMutationPlanJson(gpa: Allocator, endpoint: IpAccessRuleMutationEndpoint, args: IpAccessRuleMutationArgs) ![]u8 {
    const path = try ipAccessRuleMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.scope.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.scope),
        .summary = endpoint.summary(args.scope),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(args.scope),
    });
}

pub fn zoneLegacyRuleReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) ![]u8 {
    const path = try zoneLegacyRuleReadPath(gpa, zone_id, resource, endpoint, rule_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zoneLegacyRuleCollectionPath(gpa: Allocator, zone_id: []const u8, resource: ZoneLegacyRuleResource) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ zones_path, escaped_zone_id, resource.collectionSuffix() });
}

pub fn zoneLegacyRuleReadPath(gpa: Allocator, zone_id: []const u8, resource: ZoneLegacyRuleResource, endpoint: ZoneLegacyRuleReadEndpoint, rule_id: ?[]const u8) ![]u8 {
    const base_path = try zoneLegacyRuleCollectionPath(gpa, zone_id, resource);
    defer gpa.free(base_path);
    if (!endpoint.requiresRuleId()) return try gpa.dupe(u8, base_path);
    const id = rule_id orelse return error.MissingCloudflareZoneLegacyRuleId;
    const escaped_rule_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_rule_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
}

pub fn zoneLegacyRuleMutationPath(gpa: Allocator, endpoint: ZoneLegacyRuleMutationEndpoint, args: ZoneLegacyRuleMutationArgs) ![]u8 {
    if (!endpoint.supports(args.resource)) return error.UnsupportedCloudflareZoneLegacyRuleMutation;
    const base_path = try zoneLegacyRuleCollectionPath(gpa, args.zone_id, args.resource);
    defer gpa.free(base_path);
    if (!endpoint.requiresRuleId()) return try gpa.dupe(u8, base_path);
    const rule_id = args.rule_id orelse return error.MissingCloudflareZoneLegacyRuleId;
    const escaped_rule_id = try pathEscape(gpa, rule_id);
    defer gpa.free(escaped_rule_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_rule_id });
}

pub fn zoneLegacyRuleMutationPlanJson(gpa: Allocator, endpoint: ZoneLegacyRuleMutationEndpoint, args: ZoneLegacyRuleMutationArgs) ![]u8 {
    const path = try zoneLegacyRuleMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.resource.group(),
        .operation = endpoint.commandName(),
        .operation_id = try endpoint.operationId(args.resource),
        .summary = try endpoint.summary(args.resource),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn pageShieldReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) ![]u8 {
    const path = try pageShieldReadPath(gpa, zone_id, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn pageShieldBasePath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/page_shield", .{ zones_path, escaped_zone_id });
}

pub fn pageShieldReadPath(gpa: Allocator, zone_id: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) ![]u8 {
    const base_path = try pageShieldBasePath(gpa, zone_id);
    defer gpa.free(base_path);
    const collection = endpoint.collectionName() orelse return try gpa.dupe(u8, base_path);
    const collection_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, collection });
    defer gpa.free(collection_path);
    if (endpoint.requiresResourceId()) {
        const resource_id = args.resource_id orelse return error.MissingCloudflarePageShieldResourceId;
        const escaped_resource_id = try pathEscape(gpa, resource_id);
        defer gpa.free(escaped_resource_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
    }
    return try appendPageShieldFilters(gpa, collection_path, endpoint, args);
}

pub fn pageShieldMutationPath(gpa: Allocator, endpoint: PageShieldMutationEndpoint, args: PageShieldMutationArgs) ![]u8 {
    const base_path = try pageShieldBasePath(gpa, args.zone_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .update_settings => try gpa.dupe(u8, base_path),
        .create_policy => try std.fmt.allocPrint(gpa, "{s}/policies", .{base_path}),
        .update_policy, .delete_policy => blk: {
            const policy_id = args.policy_id orelse return error.MissingCloudflarePageShieldPolicyId;
            const escaped_policy_id = try pathEscape(gpa, policy_id);
            defer gpa.free(escaped_policy_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/policies/{s}", .{ base_path, escaped_policy_id });
        },
    };
}

pub fn pageShieldMutationPlanJson(gpa: Allocator, endpoint: PageShieldMutationEndpoint, args: PageShieldMutationArgs) ![]u8 {
    const path = try pageShieldMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = "Page Shield",
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn customPageReadUrl(gpa: Allocator, host: []const u8, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) ![]u8 {
    const path = try customPageReadPath(gpa, scope, scope_id, resource, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn customPageCollectionPath(gpa: Allocator, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource) ![]u8 {
    const escaped_scope_id = try pathEscape(gpa, scope_id);
    defer gpa.free(escaped_scope_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ scope.basePath(), escaped_scope_id, resource.pathSuffix() });
}

pub fn customPageReadPath(gpa: Allocator, scope: CustomPageScope, scope_id: []const u8, resource: CustomPageResource, endpoint: CustomPageReadEndpoint, args: CustomPageReadArgs) ![]u8 {
    const collection_path = try customPageCollectionPath(gpa, scope, scope_id, resource);
    defer gpa.free(collection_path);
    if (!endpoint.requiresResourceId()) return try gpa.dupe(u8, collection_path);
    const resource_id = args.resource_id orelse return error.MissingCloudflareCustomPageResourceId;
    const escaped_resource_id = try pathEscape(gpa, resource_id);
    defer gpa.free(escaped_resource_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
}

pub fn customPageMutationPath(gpa: Allocator, endpoint: CustomPageMutationEndpoint, args: CustomPageMutationArgs) ![]u8 {
    const resource = endpoint.resource();
    const collection_path = try customPageCollectionPath(gpa, args.scope, args.scope_id, resource);
    defer gpa.free(collection_path);
    return switch (endpoint) {
        .create_preview_token => blk: {
            const pages_path = try customPageCollectionPath(gpa, args.scope, args.scope_id, .pages);
            defer gpa.free(pages_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/preview_tokens", .{pages_path});
        },
        .create_asset => try gpa.dupe(u8, collection_path),
        .update_page, .update_asset, .delete_asset => blk: {
            const resource_id = args.resource_id orelse return error.MissingCloudflareCustomPageResourceId;
            const escaped_resource_id = try pathEscape(gpa, resource_id);
            defer gpa.free(escaped_resource_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_resource_id });
        },
    };
}

pub fn customPageMutationPlanJson(gpa: Allocator, endpoint: CustomPageMutationEndpoint, args: CustomPageMutationArgs) ![]u8 {
    const path = try customPageMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = "Custom Pages",
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.scope),
        .summary = endpoint.summary(args.scope),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn accessCustomPageReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) ![]u8 {
    const path = try accessCustomPageReadPath(gpa, account_id, endpoint, page_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accessCustomPageCollectionPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/access/custom_pages", .{ accounts_path, escaped_account_id });
}

pub fn accessCustomPageReadPath(gpa: Allocator, account_id: []const u8, endpoint: AccessCustomPageReadEndpoint, page_id: ?[]const u8) ![]u8 {
    const collection_path = try accessCustomPageCollectionPath(gpa, account_id);
    defer gpa.free(collection_path);
    if (!endpoint.requiresPageId()) return try gpa.dupe(u8, collection_path);
    const id = page_id orelse return error.MissingCloudflareAccessCustomPageId;
    const escaped_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_id });
}

pub fn accessCustomPageMutationPath(gpa: Allocator, endpoint: AccessCustomPageMutationEndpoint, args: AccessCustomPageMutationArgs) ![]u8 {
    const collection_path = try accessCustomPageCollectionPath(gpa, args.account_id);
    defer gpa.free(collection_path);
    if (!endpoint.requiresPageId()) return try gpa.dupe(u8, collection_path);
    const page_id = args.page_id orelse return error.MissingCloudflareAccessCustomPageId;
    const escaped_page_id = try pathEscape(gpa, page_id);
    defer gpa.free(escaped_page_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_page_id });
}

pub fn accessCustomPageMutationPlanJson(gpa: Allocator, endpoint: AccessCustomPageMutationEndpoint, args: AccessCustomPageMutationArgs) ![]u8 {
    const path = try accessCustomPageMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = "Access custom pages",
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn accessReadUrl(gpa: Allocator, host: []const u8, scope: AccessScope, scope_id: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) ![]u8 {
    const path = try accessReadPath(gpa, scope, scope_id, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accessBasePath(gpa: Allocator, scope: AccessScope, scope_id: []const u8) ![]u8 {
    const escaped_scope_id = try pathEscape(gpa, scope_id);
    defer gpa.free(escaped_scope_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/access", .{ scope.basePath(), escaped_scope_id });
}

fn accessAppendEscaped(gpa: Allocator, base_path: []const u8, value: []const u8) ![]u8 {
    const escaped = try pathEscape(gpa, value);
    defer gpa.free(escaped);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped });
}

fn accessAppPath(gpa: Allocator, base_path: []const u8, app_id: []const u8) ![]u8 {
    const apps_path = try std.fmt.allocPrint(gpa, "{s}/apps", .{base_path});
    defer gpa.free(apps_path);
    return try accessAppendEscaped(gpa, apps_path, app_id);
}

fn accessAppPoliciesPath(gpa: Allocator, base_path: []const u8, app_id: []const u8) ![]u8 {
    const app_path = try accessAppPath(gpa, base_path, app_id);
    defer gpa.free(app_path);
    return try std.fmt.allocPrint(gpa, "{s}/policies", .{app_path});
}

pub fn accessReadPath(gpa: Allocator, scope: AccessScope, scope_id: []const u8, endpoint: AccessReadEndpoint, args: AccessReadArgs) ![]u8 {
    if (!endpoint.supports(scope)) return error.UnsupportedCloudflareAccessEndpoint;
    const base_path = try accessBasePath(gpa, scope, scope_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .applications_list => try std.fmt.allocPrint(gpa, "{s}/apps", .{base_path}),
        .application_details => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            break :blk try accessAppPath(gpa, base_path, app_id);
        },
        .application_policy_checks => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const app_path = try accessAppPath(gpa, base_path, app_id);
            defer gpa.free(app_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/user_policy_checks", .{app_path});
        },
        .application_policies_list => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            break :blk try accessAppPoliciesPath(gpa, base_path, app_id);
        },
        .application_policy_details => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const policy_id = args.policy_id orelse return error.MissingCloudflareAccessPolicyId;
            const policies_path = try accessAppPoliciesPath(gpa, base_path, app_id);
            defer gpa.free(policies_path);
            break :blk try accessAppendEscaped(gpa, policies_path, policy_id);
        },
        .groups_list => try std.fmt.allocPrint(gpa, "{s}/groups", .{base_path}),
        .group_details => blk: {
            const group_id = args.resource_id orelse return error.MissingCloudflareAccessGroupId;
            const groups_path = try std.fmt.allocPrint(gpa, "{s}/groups", .{base_path});
            defer gpa.free(groups_path);
            break :blk try accessAppendEscaped(gpa, groups_path, group_id);
        },
        .identity_providers_list => try std.fmt.allocPrint(gpa, "{s}/identity_providers", .{base_path}),
        .identity_provider_details => blk: {
            const identity_provider_id = args.identity_provider_id orelse return error.MissingCloudflareAccessIdentityProviderId;
            const idps_path = try std.fmt.allocPrint(gpa, "{s}/identity_providers", .{base_path});
            defer gpa.free(idps_path);
            break :blk try accessAppendEscaped(gpa, idps_path, identity_provider_id);
        },
        .identity_provider_scim_groups, .identity_provider_scim_users => blk: {
            const identity_provider_id = args.identity_provider_id orelse return error.MissingCloudflareAccessIdentityProviderId;
            const idp_path = try accessReadPath(gpa, scope, scope_id, .identity_provider_details, .{ .identity_provider_id = identity_provider_id });
            defer gpa.free(idp_path);
            const suffix = if (endpoint == .identity_provider_scim_groups) "groups" else "users";
            break :blk try std.fmt.allocPrint(gpa, "{s}/scim/{s}", .{ idp_path, suffix });
        },
        .service_tokens_list => try std.fmt.allocPrint(gpa, "{s}/service_tokens", .{base_path}),
        .service_token_details => blk: {
            const service_token_id = args.service_token_id orelse return error.MissingCloudflareAccessServiceTokenId;
            const tokens_path = try std.fmt.allocPrint(gpa, "{s}/service_tokens", .{base_path});
            defer gpa.free(tokens_path);
            break :blk try accessAppendEscaped(gpa, tokens_path, service_token_id);
        },
        .reusable_policies_list => try std.fmt.allocPrint(gpa, "{s}/policies", .{base_path}),
        .reusable_policy_details => blk: {
            const policy_id = args.policy_id orelse return error.MissingCloudflareAccessPolicyId;
            const policies_path = try std.fmt.allocPrint(gpa, "{s}/policies", .{base_path});
            defer gpa.free(policies_path);
            break :blk try accessAppendEscaped(gpa, policies_path, policy_id);
        },
        .tags_list => try std.fmt.allocPrint(gpa, "{s}/tags", .{base_path}),
        .tag_details => blk: {
            const tag_name = args.tag_name orelse return error.MissingCloudflareAccessTagName;
            const tags_path = try std.fmt.allocPrint(gpa, "{s}/tags", .{base_path});
            defer gpa.free(tags_path);
            break :blk try accessAppendEscaped(gpa, tags_path, tag_name);
        },
        .authenticator_device_aaguids => try std.fmt.allocPrint(gpa, "{s}/authenticator_device_aaguids", .{base_path}),
        .idp_federation_grants_list => try std.fmt.allocPrint(gpa, "{s}/idp_federation_grants", .{base_path}),
        .idp_federation_grant_details => blk: {
            const grant_id = args.resource_id orelse return error.MissingCloudflareAccessResourceId;
            const grants_path = try std.fmt.allocPrint(gpa, "{s}/idp_federation_grants", .{base_path});
            defer gpa.free(grants_path);
            break :blk try accessAppendEscaped(gpa, grants_path, grant_id);
        },
        .saml_certificate_sets_list => try std.fmt.allocPrint(gpa, "{s}/saml_certificates", .{base_path}),
        .saml_certificate_set_details, .saml_certificate_pem => blk: {
            const cert_set_id = args.resource_id orelse return error.MissingCloudflareAccessResourceId;
            const sets_path = try std.fmt.allocPrint(gpa, "{s}/saml_certificates", .{base_path});
            defer gpa.free(sets_path);
            const set_path = try accessAppendEscaped(gpa, sets_path, cert_set_id);
            defer gpa.free(set_path);
            if (endpoint == .saml_certificate_pem) break :blk try std.fmt.allocPrint(gpa, "{s}/pem", .{set_path});
            break :blk try gpa.dupe(u8, set_path);
        },
        .scim_update_logs => try std.fmt.allocPrint(gpa, "{s}/logs/scim/updates", .{base_path}),
        .keys => try std.fmt.allocPrint(gpa, "{s}/keys", .{base_path}),
        .authentication_logs => try std.fmt.allocPrint(gpa, "{s}/logs/access_requests", .{base_path}),
        .policy_test => blk: {
            const policy_test_id = args.policy_test_id orelse return error.MissingCloudflareAccessPolicyTestId;
            const tests_path = try std.fmt.allocPrint(gpa, "{s}/policy-tests", .{base_path});
            defer gpa.free(tests_path);
            break :blk try accessAppendEscaped(gpa, tests_path, policy_test_id);
        },
        .policy_test_users => blk: {
            const policy_test_id = args.policy_test_id orelse return error.MissingCloudflareAccessPolicyTestId;
            const test_path = try accessReadPath(gpa, scope, scope_id, .policy_test, .{ .policy_test_id = policy_test_id });
            defer gpa.free(test_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/users", .{test_path});
        },
        .mtls_certificates_list => try std.fmt.allocPrint(gpa, "{s}/certificates", .{base_path}),
        .mtls_certificate_details => blk: {
            const certificate_id = args.certificate_id orelse return error.MissingCloudflareAccessCertificateId;
            const certificates_path = try std.fmt.allocPrint(gpa, "{s}/certificates", .{base_path});
            defer gpa.free(certificates_path);
            break :blk try accessAppendEscaped(gpa, certificates_path, certificate_id);
        },
        .mtls_settings => try std.fmt.allocPrint(gpa, "{s}/certificates/settings", .{base_path}),
        .ca_list => try std.fmt.allocPrint(gpa, "{s}/apps/ca", .{base_path}),
        .ca_details => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const app_path = try accessAppPath(gpa, base_path, app_id);
            defer gpa.free(app_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/ca", .{app_path});
        },
    };
}

pub fn accessMutationPath(gpa: Allocator, endpoint: AccessMutationEndpoint, args: AccessMutationArgs) ![]u8 {
    if (!endpoint.supports(args.scope)) return error.UnsupportedCloudflareAccessMutation;
    const base_path = try accessBasePath(gpa, args.scope, args.scope_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .create_application => try std.fmt.allocPrint(gpa, "{s}/apps", .{base_path}),
        .update_application, .delete_application => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            break :blk try accessAppPath(gpa, base_path, app_id);
        },
        .patch_application_settings, .put_application_settings => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const app_path = try accessAppPath(gpa, base_path, app_id);
            defer gpa.free(app_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/settings", .{app_path});
        },
        .revoke_application_tokens => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const app_path = try accessAppPath(gpa, base_path, app_id);
            defer gpa.free(app_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/revoke_tokens", .{app_path});
        },
        .create_application_policy => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            break :blk try accessAppPoliciesPath(gpa, base_path, app_id);
        },
        .update_application_policy, .delete_application_policy, .make_policy_reusable => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const policy_id = args.policy_id orelse return error.MissingCloudflareAccessPolicyId;
            const policies_path = try accessAppPoliciesPath(gpa, base_path, app_id);
            defer gpa.free(policies_path);
            const policy_path = try accessAppendEscaped(gpa, policies_path, policy_id);
            defer gpa.free(policy_path);
            if (endpoint == .make_policy_reusable) break :blk try std.fmt.allocPrint(gpa, "{s}/make_reusable", .{policy_path});
            break :blk try gpa.dupe(u8, policy_path);
        },
        .create_group => try std.fmt.allocPrint(gpa, "{s}/groups", .{base_path}),
        .update_group, .delete_group => blk: {
            const group_id = args.resource_id orelse return error.MissingCloudflareAccessGroupId;
            const groups_path = try std.fmt.allocPrint(gpa, "{s}/groups", .{base_path});
            defer gpa.free(groups_path);
            break :blk try accessAppendEscaped(gpa, groups_path, group_id);
        },
        .create_identity_provider => try std.fmt.allocPrint(gpa, "{s}/identity_providers", .{base_path}),
        .update_identity_provider, .delete_identity_provider, .create_idp_saml_certificate => blk: {
            const identity_provider_id = args.identity_provider_id orelse return error.MissingCloudflareAccessIdentityProviderId;
            const idps_path = try std.fmt.allocPrint(gpa, "{s}/identity_providers", .{base_path});
            defer gpa.free(idps_path);
            const idp_path = try accessAppendEscaped(gpa, idps_path, identity_provider_id);
            defer gpa.free(idp_path);
            if (endpoint == .create_idp_saml_certificate) break :blk try std.fmt.allocPrint(gpa, "{s}/saml_certificate", .{idp_path});
            break :blk try gpa.dupe(u8, idp_path);
        },
        .create_service_token => try std.fmt.allocPrint(gpa, "{s}/service_tokens", .{base_path}),
        .update_service_token, .delete_service_token, .refresh_service_token, .rotate_service_token => blk: {
            const service_token_id = args.service_token_id orelse return error.MissingCloudflareAccessServiceTokenId;
            const tokens_path = try std.fmt.allocPrint(gpa, "{s}/service_tokens", .{base_path});
            defer gpa.free(tokens_path);
            const token_path = try accessAppendEscaped(gpa, tokens_path, service_token_id);
            defer gpa.free(token_path);
            if (endpoint == .refresh_service_token) break :blk try std.fmt.allocPrint(gpa, "{s}/refresh", .{token_path});
            if (endpoint == .rotate_service_token) break :blk try std.fmt.allocPrint(gpa, "{s}/rotate", .{token_path});
            break :blk try gpa.dupe(u8, token_path);
        },
        .create_reusable_policy => try std.fmt.allocPrint(gpa, "{s}/policies", .{base_path}),
        .update_reusable_policy, .delete_reusable_policy => blk: {
            const policy_id = args.policy_id orelse return error.MissingCloudflareAccessPolicyId;
            const policies_path = try std.fmt.allocPrint(gpa, "{s}/policies", .{base_path});
            defer gpa.free(policies_path);
            break :blk try accessAppendEscaped(gpa, policies_path, policy_id);
        },
        .create_tag => try std.fmt.allocPrint(gpa, "{s}/tags", .{base_path}),
        .update_tag, .delete_tag => blk: {
            const tag_name = args.tag_name orelse return error.MissingCloudflareAccessTagName;
            const tags_path = try std.fmt.allocPrint(gpa, "{s}/tags", .{base_path});
            defer gpa.free(tags_path);
            break :blk try accessAppendEscaped(gpa, tags_path, tag_name);
        },
        .update_keys => try std.fmt.allocPrint(gpa, "{s}/keys", .{base_path}),
        .rotate_keys => try std.fmt.allocPrint(gpa, "{s}/keys/rotate", .{base_path}),
        .start_policy_test => try std.fmt.allocPrint(gpa, "{s}/policy-tests", .{base_path}),
        .create_idp_federation_grant => try std.fmt.allocPrint(gpa, "{s}/idp_federation_grants", .{base_path}),
        .delete_idp_federation_grant => blk: {
            const grant_id = args.resource_id orelse return error.MissingCloudflareAccessResourceId;
            const grants_path = try std.fmt.allocPrint(gpa, "{s}/idp_federation_grants", .{base_path});
            defer gpa.free(grants_path);
            break :blk try accessAppendEscaped(gpa, grants_path, grant_id);
        },
        .rotate_saml_certificate => blk: {
            const cert_set_id = args.resource_id orelse return error.MissingCloudflareAccessResourceId;
            const sets_path = try std.fmt.allocPrint(gpa, "{s}/saml_certificates", .{base_path});
            defer gpa.free(sets_path);
            const set_path = try accessAppendEscaped(gpa, sets_path, cert_set_id);
            defer gpa.free(set_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/rotate", .{set_path});
        },
        .create_mtls_certificate => try std.fmt.allocPrint(gpa, "{s}/certificates", .{base_path}),
        .update_mtls_certificate, .delete_mtls_certificate => blk: {
            const certificate_id = args.certificate_id orelse return error.MissingCloudflareAccessCertificateId;
            const certificates_path = try std.fmt.allocPrint(gpa, "{s}/certificates", .{base_path});
            defer gpa.free(certificates_path);
            break :blk try accessAppendEscaped(gpa, certificates_path, certificate_id);
        },
        .update_mtls_settings => try std.fmt.allocPrint(gpa, "{s}/certificates/settings", .{base_path}),
        .create_ca, .delete_ca => blk: {
            const app_id = args.app_id orelse return error.MissingCloudflareAccessApplicationId;
            const app_path = try accessAppPath(gpa, base_path, app_id);
            defer gpa.free(app_path);
            break :blk try std.fmt.allocPrint(gpa, "{s}/ca", .{app_path});
        },
    };
}

pub fn accessMutationPlanJson(gpa: Allocator, endpoint: AccessMutationEndpoint, args: AccessMutationArgs) ![]u8 {
    const path = try accessMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(args.scope),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.scope),
        .summary = endpoint.summary(args.scope),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn resourceTaggingAccountReadUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) ![]u8 {
    const path = try resourceTaggingAccountReadPath(gpa, account_id, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn resourceTaggingAccountBasePath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/tags", .{ accounts_path, escaped_account_id });
}

pub fn resourceTaggingAccountReadPath(gpa: Allocator, account_id: []const u8, endpoint: ResourceTaggingAccountReadEndpoint, args: ResourceTaggingAccountReadArgs) ![]u8 {
    const base_path = try resourceTaggingAccountBasePath(gpa, account_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .tags => try appendQuery(gpa, base_path, &[_]QueryParam{
            .{ .name = "resource_id", .value = args.resource_id },
            .{ .name = "resource_type", .value = args.resource_type },
            .{ .name = "worker_id", .value = args.worker_id },
        }),
        .keys => try std.fmt.allocPrint(gpa, "{s}/keys", .{base_path}),
        .resources => blk: {
            const resources_path = try std.fmt.allocPrint(gpa, "{s}/resources", .{base_path});
            defer gpa.free(resources_path);
            break :blk try appendQuery(gpa, resources_path, &[_]QueryParam{.{ .name = "type", .value = args.type_filter }});
        },
        .values => blk: {
            const tag_key = args.tag_key orelse return error.MissingCloudflareTagKey;
            const escaped_tag_key = try pathEscape(gpa, tag_key);
            defer gpa.free(escaped_tag_key);
            break :blk try std.fmt.allocPrint(gpa, "{s}/values/{s}", .{ base_path, escaped_tag_key });
        },
    };
}

pub fn resourceTaggingZoneReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, args: ResourceTaggingZoneReadArgs) ![]u8 {
    const path = try resourceTaggingZoneReadPath(gpa, zone_id, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn resourceTaggingZoneBasePath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/tags", .{ zones_path, escaped_zone_id });
}

pub fn resourceTaggingZoneReadPath(gpa: Allocator, zone_id: []const u8, args: ResourceTaggingZoneReadArgs) ![]u8 {
    const base_path = try resourceTaggingZoneBasePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try appendQuery(gpa, base_path, &[_]QueryParam{
        .{ .name = "resource_id", .value = args.resource_id },
        .{ .name = "resource_type", .value = args.resource_type },
        .{ .name = "access_application_id", .value = args.access_application_id },
    });
}

pub fn resourceTaggingMutationPath(gpa: Allocator, endpoint: ResourceTaggingMutationEndpoint, args: ResourceTaggingMutationArgs) ![]u8 {
    _ = endpoint;
    return switch (args.resource) {
        .account => blk: {
            const account_id = args.account_id orelse return error.MissingCloudflareAccountId;
            break :blk try resourceTaggingAccountBasePath(gpa, account_id);
        },
        .zone => blk: {
            const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
            break :blk try resourceTaggingZoneBasePath(gpa, zone_id);
        },
    };
}

pub fn resourceTaggingMutationPlanJson(gpa: Allocator, endpoint: ResourceTaggingMutationEndpoint, args: ResourceTaggingMutationArgs) ![]u8 {
    const path = try resourceTaggingMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = args.resource.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(args.resource),
        .summary = endpoint.summary(args.resource),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(args.resource),
    });
}

pub fn accountTokenEndpointUrl(gpa: Allocator, host: []const u8, account_id: []const u8, endpoint: AccountTokenEndpoint) ![]u8 {
    const path = try accountTokenEndpointPath(gpa, account_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountTokenEndpointPath(gpa: Allocator, account_id: []const u8, endpoint: AccountTokenEndpoint) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ accounts_path, escaped_account_id, endpoint.pathSuffix() });
}

pub fn accountTokenUrl(gpa: Allocator, host: []const u8, account_id: []const u8, token_id: []const u8) ![]u8 {
    const path = try accountTokenPath(gpa, account_id, token_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountTokenPath(gpa: Allocator, account_id: []const u8, token_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    const escaped_token_id = try pathEscape(gpa, token_id);
    defer gpa.free(escaped_token_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/tokens/{s}", .{ accounts_path, escaped_account_id, escaped_token_id });
}

pub fn accountTokenMutationPath(gpa: Allocator, endpoint: AccountTokenMutationEndpoint, args: AccountTokenMutationArgs) ![]u8 {
    if (endpoint.requiresTokenId()) {
        const token_id = args.token_id orelse return error.MissingCloudflareAccountTokenId;
        const base_path = try accountTokenPath(gpa, args.account_id, token_id);
        defer gpa.free(base_path);
        if (endpoint == .roll) return try std.fmt.allocPrint(gpa, "{s}/value", .{base_path});
        return try gpa.dupe(u8, base_path);
    }
    return try accountTokenEndpointPath(gpa, args.account_id, .list);
}

pub fn accountTokenMutationPlanJson(gpa: Allocator, endpoint: AccountTokenMutationEndpoint, args: AccountTokenMutationArgs) ![]u8 {
    const path = try accountTokenMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn userTokenEndpointUrl(gpa: Allocator, host: []const u8, endpoint: UserTokenEndpoint) ![]u8 {
    if (endpoint.requiresTokenId()) return error.MissingCloudflareUserTokenId;
    const path = try userTokenReadPath(gpa, endpoint, null);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn userTokenUrl(gpa: Allocator, host: []const u8, token_id: []const u8) ![]u8 {
    const path = try userTokenReadPath(gpa, .details, token_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn userTokenReadPath(gpa: Allocator, endpoint: UserTokenEndpoint, token_id: ?[]const u8) ![]u8 {
    if (endpoint.requiresTokenId()) {
        const id = token_id orelse return error.MissingCloudflareUserTokenId;
        const escaped = try pathEscape(gpa, id);
        defer gpa.free(escaped);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ user_tokens_path, escaped });
    }
    return try gpa.dupe(u8, endpoint.path());
}

pub fn userTokenMutationPath(gpa: Allocator, endpoint: UserTokenMutationEndpoint, args: UserTokenMutationArgs) ![]u8 {
    if (endpoint.requiresTokenId()) {
        const token_id = args.token_id orelse return error.MissingCloudflareUserTokenId;
        const escaped = try pathEscape(gpa, token_id);
        defer gpa.free(escaped);
        if (endpoint == .roll) return try std.fmt.allocPrint(gpa, "{s}/{s}/value", .{ user_tokens_path, escaped });
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ user_tokens_path, escaped });
    }
    return try gpa.dupe(u8, user_tokens_path);
}

pub fn userTokenMutationPlanJson(gpa: Allocator, endpoint: UserTokenMutationEndpoint, args: UserTokenMutationArgs) ![]u8 {
    const path = try userTokenMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn identityEndpointUrl(gpa: Allocator, host: []const u8, endpoint: IdentityEndpoint) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, endpoint.path() });
}

pub fn membershipUrl(gpa: Allocator, host: []const u8, membership_id: []const u8) ![]u8 {
    const path = try membershipPath(gpa, membership_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn membershipPath(gpa: Allocator, membership_id: []const u8) ![]u8 {
    const escaped_membership_id = try pathEscape(gpa, membership_id);
    defer gpa.free(escaped_membership_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ memberships_path, escaped_membership_id });
}

pub fn membershipMutationPath(gpa: Allocator, endpoint: MembershipMutationEndpoint, args: MembershipMutationArgs) ![]u8 {
    _ = endpoint;
    return try membershipPath(gpa, args.membership_id);
}

pub fn membershipMutationPlanJson(gpa: Allocator, endpoint: MembershipMutationEndpoint, args: MembershipMutationArgs) ![]u8 {
    const path = try membershipMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn accountDnsSettingsUrl(gpa: Allocator, host: []const u8, account_id: []const u8) ![]u8 {
    const path = try accountDnsSettingsPath(gpa, account_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountDnsSettingsPath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/dns_settings", .{ accounts_path, escaped_account_id });
}

pub fn accountDnsRecordUsageUrl(gpa: Allocator, host: []const u8, account_id: []const u8) ![]u8 {
    const path = try accountDnsRecordUsagePath(gpa, account_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn accountDnsRecordUsagePath(gpa: Allocator, account_id: []const u8) ![]u8 {
    const escaped_account_id = try pathEscape(gpa, account_id);
    defer gpa.free(escaped_account_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/dns_records/usage", .{ accounts_path, escaped_account_id });
}

pub fn zonesUrl(gpa: Allocator, host: []const u8, domain: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}?name={s}&per_page=50", .{ host, zones_path, domain });
}

pub fn zoneUrl(gpa: Allocator, host: []const u8, zone_id: []const u8) ![]u8 {
    const path = try zonePath(gpa, zone_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zonePath(gpa: Allocator, zone_id: []const u8) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ zones_path, escaped_zone_id });
}

pub fn dnsRecordsUrl(gpa: Allocator, host: []const u8, zone_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}/dns_records?per_page=5000", .{ host, zones_path, zone_id });
}

pub fn dnsAnalyticsUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: DnsAnalyticsEndpoint) ![]u8 {
    const path = try dnsAnalyticsPath(gpa, zone_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dnsAnalyticsPath(gpa: Allocator, zone_id: []const u8, endpoint: DnsAnalyticsEndpoint) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/dns_analytics/{s}", .{ base_path, endpoint.suffix() });
}

pub fn dnsRecordReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: DnsRecordReadEndpoint, dns_record_id: ?[]const u8) ![]u8 {
    const path = try dnsRecordReadPath(gpa, zone_id, endpoint, dns_record_id);
    defer gpa.free(path);
    if (endpoint == .list) {
        return try std.fmt.allocPrint(gpa, "{s}{s}?per_page=5000", .{ host, path });
    }
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dnsRecordReadPath(gpa: Allocator, zone_id: []const u8, endpoint: DnsRecordReadEndpoint, dns_record_id: ?[]const u8) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    const base_path = try std.fmt.allocPrint(gpa, "{s}/{s}/dns_records", .{ zones_path, escaped_zone_id });
    defer gpa.free(base_path);
    return switch (endpoint) {
        .list => try gpa.dupe(u8, base_path),
        .export_records => try std.fmt.allocPrint(gpa, "{s}/export", .{base_path}),
        .scan_review => try std.fmt.allocPrint(gpa, "{s}/scan/review", .{base_path}),
        .usage => try std.fmt.allocPrint(gpa, "{s}/usage", .{base_path}),
        .details => blk: {
            const record_id = dns_record_id orelse return error.MissingCloudflareDnsRecordId;
            const escaped_record_id = try pathEscape(gpa, record_id);
            defer gpa.free(escaped_record_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_record_id });
        },
    };
}

pub fn dnsRecordMutationPath(gpa: Allocator, endpoint: DnsRecordMutationEndpoint, args: DnsRecordMutationArgs) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, args.zone_id);
    defer gpa.free(escaped_zone_id);
    const base_path = try std.fmt.allocPrint(gpa, "{s}/{s}/dns_records", .{ zones_path, escaped_zone_id });
    defer gpa.free(base_path);
    if (endpoint.requiresRecordId()) {
        const record_id = args.dns_record_id orelse return error.MissingCloudflareDnsRecordId;
        const escaped_record_id = try pathEscape(gpa, record_id);
        defer gpa.free(escaped_record_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, escaped_record_id });
    }
    if (endpoint.suffix()) |suffix| {
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, suffix });
    }
    return try gpa.dupe(u8, base_path);
}

pub fn dnsRecordMutationPlanJson(gpa: Allocator, endpoint: DnsRecordMutationEndpoint, args: DnsRecordMutationArgs) ![]u8 {
    const path = try dnsRecordMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn zoneMutationPath(gpa: Allocator, endpoint: ZoneMutationEndpoint, args: ZoneMutationArgs) ![]u8 {
    if (!endpoint.requiresZoneId()) return try gpa.dupe(u8, zones_path);
    const zone_id = args.zone_id orelse return error.MissingCloudflareZoneId;
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return switch (endpoint) {
        .delete_zone, .edit => try gpa.dupe(u8, base_path),
        .purge_cache => try std.fmt.allocPrint(gpa, "{s}/purge_cache", .{base_path}),
        .activation_check => try std.fmt.allocPrint(gpa, "{s}/activation_check", .{base_path}),
        .purge_environment_cache => blk: {
            const environment_id = args.environment_id orelse return error.MissingCloudflareZoneEnvironmentId;
            const escaped_environment_id = try pathEscape(gpa, environment_id);
            defer gpa.free(escaped_environment_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/environments/{s}/purge_cache", .{ base_path, escaped_environment_id });
        },
        .create => unreachable,
    };
}

pub fn zoneMutationPlanJson(gpa: Allocator, endpoint: ZoneMutationEndpoint, args: ZoneMutationArgs) ![]u8 {
    const path = try zoneMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn zoneEndpointUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: ZoneEndpoint) ![]u8 {
    const path = try zoneEndpointPath(gpa, zone_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zoneEndpointPath(gpa: Allocator, zone_id: []const u8, endpoint: ZoneEndpoint) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ zones_path, escaped_zone_id, endpoint.pathSuffix() });
}

pub fn zoneLifecycleReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: ZoneLifecycleReadEndpoint, plan_id: ?[]const u8) ![]u8 {
    const path = try zoneLifecycleReadPath(gpa, zone_id, endpoint, plan_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zoneLifecycleReadPath(gpa: Allocator, zone_id: []const u8, endpoint: ZoneLifecycleReadEndpoint, plan_id: ?[]const u8) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    const collection_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, endpoint.pathSuffix() });
    defer gpa.free(collection_path);
    if (endpoint.requiresPlanId()) {
        const id = plan_id orelse return error.MissingCloudflareZonePlanId;
        const escaped_plan_id = try pathEscape(gpa, id);
        defer gpa.free(escaped_plan_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ collection_path, escaped_plan_id });
    }
    return try gpa.dupe(u8, collection_path);
}

pub fn zoneLifecycleMutationPath(gpa: Allocator, endpoint: ZoneLifecycleMutationEndpoint, args: ZoneLifecycleMutationArgs) ![]u8 {
    const base_path = try zonePath(gpa, args.zone_id);
    defer gpa.free(base_path);
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, endpoint.pathSuffix() });
    defer gpa.free(path);
    if (endpoint.requiresEnvironmentId()) {
        const environment_id = args.environment_id orelse return error.MissingCloudflareZoneEnvironmentId;
        const escaped_environment_id = try pathEscape(gpa, environment_id);
        defer gpa.free(escaped_environment_id);
        const suffix = if (endpoint == .rollback_environment) "/rollback" else "";
        return try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ path, escaped_environment_id, suffix });
    }
    return try gpa.dupe(u8, path);
}

pub fn zoneLifecycleMutationPlanJson(gpa: Allocator, endpoint: ZoneLifecycleMutationEndpoint, args: ZoneLifecycleMutationArgs) ![]u8 {
    const path = try zoneLifecycleMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn secondaryDnsZoneReadUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, endpoint: SecondaryDnsZoneReadEndpoint) ![]u8 {
    const path = try secondaryDnsZoneReadPath(gpa, zone_id, endpoint);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn secondaryDnsZoneReadPath(gpa: Allocator, zone_id: []const u8, endpoint: SecondaryDnsZoneReadEndpoint) ![]u8 {
    const base_path = try zonePath(gpa, zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, endpoint.pathSuffix() });
}

pub fn secondaryDnsZoneMutationPath(gpa: Allocator, endpoint: SecondaryDnsZoneMutationEndpoint, args: SecondaryDnsZoneMutationArgs) ![]u8 {
    const base_path = try zonePath(gpa, args.zone_id);
    defer gpa.free(base_path);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_path, endpoint.pathSuffix() });
}

pub fn secondaryDnsZoneMutationPlanJson(gpa: Allocator, endpoint: SecondaryDnsZoneMutationEndpoint, args: SecondaryDnsZoneMutationArgs) ![]u8 {
    const path = try secondaryDnsZoneMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn dnssecMutationPath(gpa: Allocator, endpoint: DnssecMutationEndpoint, args: DnssecMutationArgs) ![]u8 {
    _ = endpoint;
    const escaped_zone_id = try pathEscape(gpa, args.zone_id);
    defer gpa.free(escaped_zone_id);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/dnssec", .{ zones_path, escaped_zone_id });
}

pub fn dnssecMutationPlanJson(gpa: Allocator, endpoint: DnssecMutationEndpoint, args: DnssecMutationArgs) ![]u8 {
    const path = try dnssecMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn zoneSettingUrl(gpa: Allocator, host: []const u8, zone_id: []const u8, setting_id: []const u8) ![]u8 {
    const path = try zoneSettingPath(gpa, zone_id, setting_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn zoneSettingPath(gpa: Allocator, zone_id: []const u8, setting_id: []const u8) ![]u8 {
    const escaped_zone_id = try pathEscape(gpa, zone_id);
    defer gpa.free(escaped_zone_id);
    const escaped = try pathEscape(gpa, setting_id);
    defer gpa.free(escaped);
    return try std.fmt.allocPrint(gpa, "{s}/{s}/settings/{s}", .{ zones_path, escaped_zone_id, escaped });
}

fn dryRunPlanJson(gpa: Allocator, plan: DryRunPlan) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{");
    try writeJsonField(writer, "provider", "cloudflare", true);
    try writeJsonField(writer, "group", plan.group, true);
    try writeJsonField(writer, "operation", plan.operation, true);
    try writeJsonField(writer, "operation_id", plan.operation_id, true);
    try writeJsonField(writer, "summary", plan.summary, true);
    try writeJsonField(writer, "method", plan.method, true);
    try writeJsonField(writer, "path", plan.path, true);
    if (plan.request_body_schema) |schema| {
        try writeJsonField(writer, "request_body_schema", schema, true);
    } else {
        try writer.writeAll("\"request_body_schema\":null,");
    }
    try writer.writeAll("\"mode\":\"dry_run\",");
    try writer.writeAll("\"will_execute\":false,");
    try writeJsonField(writer, "safety", "No Cloudflare API request is sent. This is a typed dry-run plan for a live mutation route.", false);
    try writer.writeAll("}");
    return try out.toOwnedSlice();
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try writeJsonString(writer, name);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

const QueryParam = struct {
    name: []const u8,
    value: ?[]const u8,
};

fn appendQuery(gpa: Allocator, base_path: []const u8, params: []const QueryParam) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.writeAll(base_path);
    var first = true;
    for (params) |param| {
        const value = param.value orelse continue;
        try out.writer.writeByte(if (first) '?' else '&');
        first = false;
        try out.writer.writeAll(param.name);
        try out.writer.writeByte('=');
        const escaped = try pathEscape(gpa, value);
        defer gpa.free(escaped);
        try out.writer.writeAll(escaped);
    }
    return try out.toOwnedSlice();
}

fn appendCloudforceOneRuleFilters(gpa: Allocator, base_path: []const u8, args: CloudforceOneRuleReadArgs, include_search_query: bool) ![]u8 {
    return try appendQuery(gpa, base_path, &[_]QueryParam{
        .{ .name = "namespace", .value = args.namespace },
        .{ .name = "recursive", .value = args.recursive },
        .{ .name = "search", .value = args.search_filter },
        .{ .name = "is_public", .value = args.is_public },
        .{ .name = "limit", .value = args.limit },
        .{ .name = "offset", .value = args.offset },
        .{ .name = "query", .value = if (include_search_query) args.query else null },
        .{ .name = "mode", .value = if (include_search_query) args.mode else null },
        .{ .name = "language", .value = if (include_search_query) args.language else null },
    });
}

fn appendIpAccessRuleFilters(gpa: Allocator, base_path: []const u8, args: IpAccessRuleListArgs) ![]u8 {
    return try appendQuery(gpa, base_path, &[_]QueryParam{
        .{ .name = "mode", .value = args.mode },
        .{ .name = "configuration.target", .value = args.configuration_target },
        .{ .name = "configuration.value", .value = args.configuration_value },
        .{ .name = "notes", .value = args.notes },
        .{ .name = "match", .value = args.match },
        .{ .name = "page", .value = args.page },
        .{ .name = "per_page", .value = args.per_page },
        .{ .name = "order", .value = args.order },
        .{ .name = "direction", .value = args.direction },
    });
}

fn appendPageShieldFilters(gpa: Allocator, base_path: []const u8, endpoint: PageShieldReadEndpoint, args: PageShieldReadArgs) ![]u8 {
    return switch (endpoint) {
        .connections => try appendQuery(gpa, base_path, &[_]QueryParam{
            .{ .name = "exclude_urls", .value = args.exclude_urls },
            .{ .name = "urls", .value = args.urls },
            .{ .name = "hosts", .value = args.hosts },
            .{ .name = "page", .value = args.page },
            .{ .name = "per_page", .value = args.per_page },
            .{ .name = "order_by", .value = args.order_by },
            .{ .name = "direction", .value = args.direction },
            .{ .name = "prioritize_malicious", .value = args.prioritize_malicious },
            .{ .name = "exclude_cdn_cgi", .value = args.exclude_cdn_cgi },
            .{ .name = "status", .value = args.status },
            .{ .name = "page_url", .value = args.page_url },
            .{ .name = "export", .value = args.export_format },
        }),
        .scripts => try appendQuery(gpa, base_path, &[_]QueryParam{
            .{ .name = "exclude_urls", .value = args.exclude_urls },
            .{ .name = "urls", .value = args.urls },
            .{ .name = "hosts", .value = args.hosts },
            .{ .name = "page", .value = args.page },
            .{ .name = "per_page", .value = args.per_page },
            .{ .name = "order_by", .value = args.order_by },
            .{ .name = "direction", .value = args.direction },
            .{ .name = "prioritize_malicious", .value = args.prioritize_malicious },
            .{ .name = "exclude_cdn_cgi", .value = args.exclude_cdn_cgi },
            .{ .name = "exclude_duplicates", .value = args.exclude_duplicates },
            .{ .name = "status", .value = args.status },
            .{ .name = "page_url", .value = args.page_url },
            .{ .name = "export", .value = args.export_format },
        }),
        .cookies => try appendQuery(gpa, base_path, &[_]QueryParam{
            .{ .name = "hosts", .value = args.hosts },
            .{ .name = "page", .value = args.page },
            .{ .name = "per_page", .value = args.per_page },
            .{ .name = "order_by", .value = args.order_by },
            .{ .name = "direction", .value = args.direction },
            .{ .name = "page_url", .value = args.page_url },
            .{ .name = "export", .value = args.export_format },
            .{ .name = "name", .value = args.name },
            .{ .name = "secure", .value = args.secure },
            .{ .name = "http_only", .value = args.http_only },
            .{ .name = "same_site", .value = args.same_site },
            .{ .name = "type", .value = args.type_filter },
            .{ .name = "path", .value = args.path_filter },
            .{ .name = "domain", .value = args.domain },
        }),
        else => try gpa.dupe(u8, base_path),
    };
}

pub fn pathEscape(gpa: Allocator, value: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try (std.Uri.Component{ .raw = value }).formatEscaped(&out.writer);
    return try out.toOwnedSlice();
}

test "auth detects token and legacy credentials" {
    try std.testing.expect((Auth{ .token = "token" }).isConfigured());
    try std.testing.expect((Auth{ .email = "a@example.com", .key = "global" }).isConfigured());
    try std.testing.expect(!(Auth{ .email = "a@example.com" }).isConfigured());
}

test "builds Cloudflare IP range URLs" {
    const allocator = std.testing.allocator;
    const ips = try ipsUrl(allocator, base_url, null);
    defer allocator.free(ips);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/ips", ips);

    const jdcloud = try ipsUrl(allocator, base_url, "jdcloud");
    defer allocator.free(jdcloud);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/ips?networks=jdcloud", jdcloud);
}

test "cloudflare account mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccountMutationEndpoint.create, AccountMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(AccountMutationEndpoint.delete_account, AccountMutationEndpoint.parse("remove").?);
    try std.testing.expectEqual(AccountMutationEndpoint.update, AccountMutationEndpoint.parse("update").?);
    try std.testing.expectEqual(AccountMutationEndpoint.batch_move, AccountMutationEndpoint.parse("move-batch").?);
    try std.testing.expectEqual(AccountMutationEndpoint.move, AccountMutationEndpoint.parse("move").?);
    try std.testing.expectEqual(AccountMutationEndpoint.update_profile, AccountMutationEndpoint.parse("update-profile").?);
    try std.testing.expect(AccountMutationEndpoint.parse("show") == null);

    try std.testing.expectEqualStrings("Accounts", AccountMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", AccountMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("DELETE", AccountMutationEndpoint.delete_account.method());
    try std.testing.expectEqualStrings("PUT", AccountMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("account-creation", AccountMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("account-deletion", AccountMutationEndpoint.delete_account.operationId());
    try std.testing.expectEqualStrings("accounts-update-account", AccountMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("Accounts_batchMoveAccounts", AccountMutationEndpoint.batch_move.operationId());
    try std.testing.expectEqualStrings("Accounts_moveAccounts", AccountMutationEndpoint.move.operationId());
    try std.testing.expectEqualStrings("Accounts_modifyAccountProfile", AccountMutationEndpoint.update_profile.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/iam_create-account", AccountMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/iam_components-schemas-account", AccountMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("inline:{account_ids:[]string,destination_organization_id:string}", AccountMutationEndpoint.batch_move.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("inline:{destination_organization_id:string}", AccountMutationEndpoint.move.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/organizations-api_Profile", AccountMutationEndpoint.update_profile.requestBodySchemaRef().?);
    try std.testing.expect(AccountMutationEndpoint.delete_account.requestBodySchemaRef() == null);
    try std.testing.expect(!AccountMutationEndpoint.create.requiresAccountId());
    try std.testing.expect(!AccountMutationEndpoint.batch_move.requiresAccountId());
    try std.testing.expect(AccountMutationEndpoint.move.requiresAccountId());
}

test "parses account collection commands" {
    try std.testing.expectEqual(AccountCollection.members, AccountCollection.parseListCommand("members").?);
    try std.testing.expectEqual(AccountCollection.roles, AccountCollection.parseListCommand("roles").?);
    try std.testing.expectEqual(AccountCollection.members, AccountCollection.parseDetailCommand("member").?);
    try std.testing.expectEqual(AccountCollection.roles, AccountCollection.parseDetailCommand("role").?);
    try std.testing.expect(AccountCollection.parseListCommand("member") == null);
    try std.testing.expect(AccountCollection.parseDetailCommand("roles") == null);
}

test "cloudflare account member mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccountMemberMutationEndpoint.create, AccountMemberMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(AccountMemberMutationEndpoint.create, AccountMemberMutationEndpoint.parse("invite").?);
    try std.testing.expectEqual(AccountMemberMutationEndpoint.update, AccountMemberMutationEndpoint.parse("replace").?);
    try std.testing.expectEqual(AccountMemberMutationEndpoint.delete_member, AccountMemberMutationEndpoint.parse("remove").?);
    try std.testing.expect(AccountMemberMutationEndpoint.parse("list") == null);

    try std.testing.expectEqualStrings("Account Members", AccountMemberMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", AccountMemberMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", AccountMemberMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", AccountMemberMutationEndpoint.delete_member.method());
    try std.testing.expectEqualStrings("account-members-add-member", AccountMemberMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("account-members-update-member", AccountMemberMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("account-members-remove-member", AccountMemberMutationEndpoint.delete_member.operationId());
    try std.testing.expectEqualStrings("oneOf:#/components/schemas/iam_create-member-with-roles|#/components/schemas/iam_create-member-with-policies", AccountMemberMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("oneOf:#/components/schemas/iam_update-member-with-roles|#/components/schemas/iam_update-member-with-policies", AccountMemberMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expect(AccountMemberMutationEndpoint.delete_member.requestBodySchemaRef() == null);
    try std.testing.expect(!AccountMemberMutationEndpoint.create.requiresMemberId());
    try std.testing.expect(AccountMemberMutationEndpoint.update.requiresMemberId());
}

test "parses account IAM collection commands" {
    try std.testing.expectEqual(AccountIamCollection.permission_groups, AccountIamCollection.parseListCommand("permission-groups").?);
    try std.testing.expectEqual(AccountIamCollection.resource_groups, AccountIamCollection.parseListCommand("resource-groups").?);
    try std.testing.expectEqual(AccountIamCollection.user_groups, AccountIamCollection.parseListCommand("user-groups").?);
    try std.testing.expectEqual(AccountIamCollection.permission_groups, AccountIamCollection.parseDetailCommand("permission-group").?);
    try std.testing.expectEqual(AccountIamCollection.resource_groups, AccountIamCollection.parseDetailCommand("resource-group").?);
    try std.testing.expectEqual(AccountIamCollection.user_groups, AccountIamCollection.parseDetailCommand("user-group").?);
    try std.testing.expect(AccountIamCollection.parseListCommand("groups") == null);
    try std.testing.expect(AccountIamCollection.parseDetailCommand("group") == null);
    try std.testing.expect(!AccountIamCollection.permission_groups.supportsGroupMutation());
    try std.testing.expect(AccountIamCollection.resource_groups.supportsGroupMutation());
    try std.testing.expect(AccountIamCollection.user_groups.supportsGroupMutation());
}

test "cloudflare account IAM group mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccountIamGroupMutationEndpoint.create, AccountIamGroupMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(AccountIamGroupMutationEndpoint.create, AccountIamGroupMutationEndpoint.parse("add").?);
    try std.testing.expectEqual(AccountIamGroupMutationEndpoint.update, AccountIamGroupMutationEndpoint.parse("replace").?);
    try std.testing.expectEqual(AccountIamGroupMutationEndpoint.delete_group, AccountIamGroupMutationEndpoint.parse("remove").?);
    try std.testing.expect(AccountIamGroupMutationEndpoint.parse("list") == null);

    try std.testing.expectEqualStrings("POST", AccountIamGroupMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", AccountIamGroupMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", AccountIamGroupMutationEndpoint.delete_group.method());
    try std.testing.expect(!AccountIamGroupMutationEndpoint.create.requiresResourceId());
    try std.testing.expect(AccountIamGroupMutationEndpoint.update.requiresResourceId());

    try std.testing.expectEqualStrings("Account Resource Groups", try AccountIamGroupMutationEndpoint.create.group(.resource_groups));
    try std.testing.expectEqualStrings("account-resource-group-create", try AccountIamGroupMutationEndpoint.create.operationId(.resource_groups));
    try std.testing.expectEqualStrings("account-resource-group-update", try AccountIamGroupMutationEndpoint.update.operationId(.resource_groups));
    try std.testing.expectEqualStrings("account-resource-group-delete", try AccountIamGroupMutationEndpoint.delete_group.operationId(.resource_groups));
    try std.testing.expectEqualStrings("#/components/schemas/iam_request_create_resource_group", (try AccountIamGroupMutationEndpoint.create.requestBodySchemaRef(.resource_groups)).?);
    try std.testing.expectEqualStrings("#/components/schemas/iam_request_update_resource_group", (try AccountIamGroupMutationEndpoint.update.requestBodySchemaRef(.resource_groups)).?);

    try std.testing.expectEqualStrings("Account User Groups", try AccountIamGroupMutationEndpoint.create.group(.user_groups));
    try std.testing.expectEqualStrings("account-user-group-create", try AccountIamGroupMutationEndpoint.create.operationId(.user_groups));
    try std.testing.expectEqualStrings("account-user-group-update", try AccountIamGroupMutationEndpoint.update.operationId(.user_groups));
    try std.testing.expectEqualStrings("account-user-group-delete", try AccountIamGroupMutationEndpoint.delete_group.operationId(.user_groups));
    try std.testing.expectEqualStrings("#/components/schemas/iam_create_user_group_body", (try AccountIamGroupMutationEndpoint.create.requestBodySchemaRef(.user_groups)).?);
    try std.testing.expectEqualStrings("#/components/schemas/iam_update_user_group_body", (try AccountIamGroupMutationEndpoint.update.requestBodySchemaRef(.user_groups)).?);
    try std.testing.expect((try AccountIamGroupMutationEndpoint.delete_group.requestBodySchemaRef(.user_groups)) == null);

    try std.testing.expectError(error.UnsupportedCloudflareAccountIamGroupMutation, AccountIamGroupMutationEndpoint.create.operationId(.permission_groups));
}

test "cloudflare account user-group member mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccountUserGroupMemberMutationEndpoint.create, AccountUserGroupMemberMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(AccountUserGroupMemberMutationEndpoint.create, AccountUserGroupMemberMutationEndpoint.parse("add").?);
    try std.testing.expectEqual(AccountUserGroupMemberMutationEndpoint.update, AccountUserGroupMemberMutationEndpoint.parse("replace").?);
    try std.testing.expectEqual(AccountUserGroupMemberMutationEndpoint.delete_member, AccountUserGroupMemberMutationEndpoint.parse("remove").?);
    try std.testing.expect(AccountUserGroupMemberMutationEndpoint.parse("list") == null);

    try std.testing.expectEqualStrings("Account User Group Members", AccountUserGroupMemberMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", AccountUserGroupMemberMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", AccountUserGroupMemberMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", AccountUserGroupMemberMutationEndpoint.delete_member.method());
    try std.testing.expectEqualStrings("account-user-group-member-create", AccountUserGroupMemberMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("account-user-group-members-update", AccountUserGroupMemberMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("account-user-group-member-delete", AccountUserGroupMemberMutationEndpoint.delete_member.operationId());
    try std.testing.expectEqualStrings("inline: array<{id:#/components/schemas/iam_user_group_member_identifier}>", AccountUserGroupMemberMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expect(AccountUserGroupMemberMutationEndpoint.delete_member.requestBodySchemaRef() == null);
    try std.testing.expect(!AccountUserGroupMemberMutationEndpoint.create.requiresMemberId());
    try std.testing.expect(AccountUserGroupMemberMutationEndpoint.delete_member.requiresMemberId());
}

test "parses account token commands" {
    try std.testing.expectEqual(AccountTokenEndpoint.list, AccountTokenEndpoint.parse("tokens").?);
    try std.testing.expectEqual(AccountTokenEndpoint.permission_groups, AccountTokenEndpoint.parse("token-permission-groups").?);
    try std.testing.expectEqual(AccountTokenEndpoint.permission_groups, AccountTokenEndpoint.parse("token-permissions").?);
    try std.testing.expectEqual(AccountTokenEndpoint.verify, AccountTokenEndpoint.parse("token-verify").?);
    try std.testing.expect(AccountTokenEndpoint.parse("token") == null);
}

test "cloudflare account token mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccountTokenMutationEndpoint.create, AccountTokenMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(AccountTokenMutationEndpoint.delete_token, AccountTokenMutationEndpoint.parse("delete-token").?);
    try std.testing.expectEqual(AccountTokenMutationEndpoint.update, AccountTokenMutationEndpoint.parse("update").?);
    try std.testing.expectEqual(AccountTokenMutationEndpoint.roll, AccountTokenMutationEndpoint.parse("roll-token").?);
    try std.testing.expect(AccountTokenMutationEndpoint.parse("list") == null);

    try std.testing.expectEqualStrings("Account Owned API Tokens", AccountTokenMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", AccountTokenMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("DELETE", AccountTokenMutationEndpoint.delete_token.method());
    try std.testing.expectEqualStrings("PUT", AccountTokenMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("account-api-tokens-create-token", AccountTokenMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("account-api-tokens-delete-token", AccountTokenMutationEndpoint.delete_token.operationId());
    try std.testing.expectEqualStrings("account-api-tokens-update-token", AccountTokenMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("account-api-tokens-roll-token", AccountTokenMutationEndpoint.roll.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/iam_create_payload", AccountTokenMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/iam_token_body", AccountTokenMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expect(AccountTokenMutationEndpoint.roll.requestBodySchemaRef() == null);
    try std.testing.expect(AccountTokenMutationEndpoint.roll.requiresTokenId());
    try std.testing.expect(!AccountTokenMutationEndpoint.create.requiresTokenId());
}

test "cloudflare membership mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(MembershipMutationEndpoint.update, MembershipMutationEndpoint.parse("update").?);
    try std.testing.expectEqual(MembershipMutationEndpoint.update, MembershipMutationEndpoint.parse("accept").?);
    try std.testing.expectEqual(MembershipMutationEndpoint.delete_membership, MembershipMutationEndpoint.parse("remove").?);
    try std.testing.expect(MembershipMutationEndpoint.parse("list") == null);

    try std.testing.expectEqualStrings("User's Account Memberships", MembershipMutationEndpoint.update.group());
    try std.testing.expectEqualStrings("PUT", MembershipMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", MembershipMutationEndpoint.delete_membership.method());
    try std.testing.expectEqualStrings("user'-s-account-memberships-update-membership", MembershipMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("user'-s-account-memberships-delete-membership", MembershipMutationEndpoint.delete_membership.operationId());
    try std.testing.expectEqualStrings("Update Membership", MembershipMutationEndpoint.update.summary());
    try std.testing.expectEqualStrings("inline:{status:accepted|rejected}", MembershipMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expect(MembershipMutationEndpoint.delete_membership.requestBodySchemaRef() == null);
}

test "cloudflare user token endpoints map to official operation metadata" {
    try std.testing.expectEqual(UserTokenEndpoint.list, UserTokenEndpoint.parse("tokens").?);
    try std.testing.expectEqual(UserTokenEndpoint.details, UserTokenEndpoint.parse("show").?);
    try std.testing.expectEqual(UserTokenEndpoint.verify, UserTokenEndpoint.parse("verify").?);
    try std.testing.expectEqual(UserTokenEndpoint.permission_groups, UserTokenEndpoint.parse("permission-groups").?);
    try std.testing.expect(UserTokenEndpoint.details.requiresTokenId());
    try std.testing.expect(!UserTokenEndpoint.list.requiresTokenId());

    try std.testing.expectEqual(UserTokenMutationEndpoint.create, UserTokenMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(UserTokenMutationEndpoint.delete_token, UserTokenMutationEndpoint.parse("delete-token").?);
    try std.testing.expectEqual(UserTokenMutationEndpoint.update, UserTokenMutationEndpoint.parse("update").?);
    try std.testing.expectEqual(UserTokenMutationEndpoint.roll, UserTokenMutationEndpoint.parse("roll-token").?);
    try std.testing.expectEqualStrings("User API Tokens", UserTokenMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", UserTokenMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("DELETE", UserTokenMutationEndpoint.delete_token.method());
    try std.testing.expectEqualStrings("PUT", UserTokenMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("user-api-tokens-create-token", UserTokenMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("user-api-tokens-delete-token", UserTokenMutationEndpoint.delete_token.operationId());
    try std.testing.expectEqualStrings("user-api-tokens-update-token", UserTokenMutationEndpoint.update.operationId());
    try std.testing.expectEqualStrings("user-api-tokens-roll-token", UserTokenMutationEndpoint.roll.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/iam_create_payload", UserTokenMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/iam_token_body", UserTokenMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expect(UserTokenMutationEndpoint.roll.requestBodySchemaRef() == null);
    try std.testing.expect(UserTokenMutationEndpoint.roll.requiresTokenId());
    try std.testing.expect(!UserTokenMutationEndpoint.create.requiresTokenId());
}

test "builds Cloudflare membership dry-run plans" {
    const allocator = std.testing.allocator;
    const update = try membershipMutationPlanJson(allocator, .update, .{ .membership_id = "membership/1" });
    defer allocator.free(update);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"group\":\"User's Account Memberships\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"operation_id\":\"user'-s-account-memberships-update-membership\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"path\":\"/memberships/membership%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"request_body_schema\":\"inline:{status:accepted|rejected}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"will_execute\":false") != null);

    const delete_membership = try membershipMutationPlanJson(allocator, .delete_membership, .{ .membership_id = "membership/1" });
    defer allocator.free(delete_membership);
    try std.testing.expect(std.mem.indexOf(u8, delete_membership, "\"operation_id\":\"user'-s-account-memberships-delete-membership\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_membership, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_membership, "\"path\":\"/memberships/membership%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_membership, "\"request_body_schema\":null") != null);
}

test "builds Cloudflare account token dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try accountTokenMutationPlanJson(allocator, .create, .{ .account_id = "acct 1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Account Owned API Tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"account-api-tokens-create-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts/acct%201/tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/iam_create_payload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const roll = try accountTokenMutationPlanJson(allocator, .roll, .{ .account_id = "acct 1", .token_id = "token/1" });
    defer allocator.free(roll);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"operation_id\":\"account-api-tokens-roll-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"path\":\"/accounts/acct%201/tokens/token%2F1/value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"request_body_schema\":null") != null);

    const update = try accountTokenMutationPlanJson(allocator, .update, .{ .account_id = "acct 1", .token_id = "token/1" });
    defer allocator.free(update);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"operation_id\":\"account-api-tokens-update-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"request_body_schema\":\"#/components/schemas/iam_token_body\"") != null);
}

test "builds Cloudflare user token dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try userTokenMutationPlanJson(allocator, .create, .{});
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"User API Tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"user-api-tokens-create-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/user/tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/iam_create_payload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const roll = try userTokenMutationPlanJson(allocator, .roll, .{ .token_id = "token/1" });
    defer allocator.free(roll);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"operation_id\":\"user-api-tokens-roll-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"path\":\"/user/tokens/token%2F1/value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, roll, "\"request_body_schema\":null") != null);
}

test "builds Cloudflare account dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try accountMutationPlanJson(allocator, .create, .{});
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"account-creation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/iam_create-account\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const batch_move = try accountMutationPlanJson(allocator, .batch_move, .{});
    defer allocator.free(batch_move);
    try std.testing.expect(std.mem.indexOf(u8, batch_move, "\"operation_id\":\"Accounts_batchMoveAccounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, batch_move, "\"path\":\"/accounts/move\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, batch_move, "\"request_body_schema\":\"inline:{account_ids:[]string,destination_organization_id:string}\"") != null);

    const profile = try accountMutationPlanJson(allocator, .update_profile, .{ .account_id = "acct/1" });
    defer allocator.free(profile);
    try std.testing.expect(std.mem.indexOf(u8, profile, "\"operation_id\":\"Accounts_modifyAccountProfile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, profile, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, profile, "\"path\":\"/accounts/acct%2F1/profile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, profile, "\"request_body_schema\":\"#/components/schemas/organizations-api_Profile\"") != null);

    const delete_account = try accountMutationPlanJson(allocator, .delete_account, .{ .account_id = "acct/1" });
    defer allocator.free(delete_account);
    try std.testing.expect(std.mem.indexOf(u8, delete_account, "\"operation_id\":\"account-deletion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_account, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_account, "\"path\":\"/accounts/acct%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_account, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflareAccountId, accountMutationPlanJson(allocator, .move, .{}));
}

test "builds Cloudflare account member dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try accountMemberMutationPlanJson(allocator, .create, .{ .account_id = "acct 1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Account Members\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"account-members-add-member\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts/acct%201/members\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"oneOf:#/components/schemas/iam_create-member-with-roles|#/components/schemas/iam_create-member-with-policies\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const update = try accountMemberMutationPlanJson(allocator, .update, .{ .account_id = "acct 1", .member_id = "member/1" });
    defer allocator.free(update);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"operation_id\":\"account-members-update-member\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"path\":\"/accounts/acct%201/members/member%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"request_body_schema\":\"oneOf:#/components/schemas/iam_update-member-with-roles|#/components/schemas/iam_update-member-with-policies\"") != null);

    const delete_member = try accountMemberMutationPlanJson(allocator, .delete_member, .{ .account_id = "acct 1", .member_id = "member/1" });
    defer allocator.free(delete_member);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"operation_id\":\"account-members-remove-member\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"path\":\"/accounts/acct%201/members/member%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"request_body_schema\":null") != null);
}

test "builds Cloudflare account IAM group dry-run plans" {
    const allocator = std.testing.allocator;
    const resource_create = try accountIamGroupMutationPlanJson(allocator, .create, .{ .collection = .resource_groups, .account_id = "acct 1" });
    defer allocator.free(resource_create);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"group\":\"Account Resource Groups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"operation_id\":\"account-resource-group-create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"path\":\"/accounts/acct%201/iam/resource_groups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"request_body_schema\":\"#/components/schemas/iam_request_create_resource_group\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_create, "\"will_execute\":false") != null);

    const user_update = try accountIamGroupMutationPlanJson(allocator, .update, .{ .collection = .user_groups, .account_id = "acct 1", .resource_id = "group/1" });
    defer allocator.free(user_update);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"group\":\"Account User Groups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"operation_id\":\"account-user-group-update\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"path\":\"/accounts/acct%201/iam/user_groups/group%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"request_body_schema\":\"#/components/schemas/iam_update_user_group_body\"") != null);

    const resource_delete = try accountIamGroupMutationPlanJson(allocator, .delete_group, .{ .collection = .resource_groups, .account_id = "acct 1", .resource_id = "resource/1" });
    defer allocator.free(resource_delete);
    try std.testing.expect(std.mem.indexOf(u8, resource_delete, "\"operation_id\":\"account-resource-group-delete\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_delete, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_delete, "\"path\":\"/accounts/acct%201/iam/resource_groups/resource%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resource_delete, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.UnsupportedCloudflareAccountIamGroupMutation, accountIamGroupMutationPlanJson(allocator, .create, .{ .collection = .permission_groups, .account_id = "acct 1" }));
}

test "builds Cloudflare account user-group member dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try accountUserGroupMemberMutationPlanJson(allocator, .create, .{ .account_id = "acct 1", .user_group_id = "group/1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Account User Group Members\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"account-user-group-member-create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts/acct%201/iam/user_groups/group%2F1/members\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"inline: array<{id:#/components/schemas/iam_user_group_member_identifier}>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const delete_member = try accountUserGroupMemberMutationPlanJson(allocator, .delete_member, .{ .account_id = "acct 1", .user_group_id = "group/1", .member_id = "member/1" });
    defer allocator.free(delete_member);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"operation_id\":\"account-user-group-member-delete\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"path\":\"/accounts/acct%201/iam/user_groups/group%2F1/members/member%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_member, "\"request_body_schema\":null") != null);
}

test "cloudflare secondary dns endpoints map to official operation metadata" {
    try std.testing.expectEqual(SecondaryDnsAccountResource.acl, SecondaryDnsAccountResource.parseListCommand("acls").?);
    try std.testing.expectEqual(SecondaryDnsAccountResource.peer, SecondaryDnsAccountResource.parseDetailCommand("peer").?);
    try std.testing.expectEqual(SecondaryDnsAccountResource.tsig, SecondaryDnsAccountResource.parseListCommand("tsigs").?);
    try std.testing.expectEqualStrings("Secondary DNS (ACL)", SecondaryDnsAccountResource.acl.group());
    try std.testing.expectEqualStrings("secondary-dns-(-acl)-list-ac-ls", SecondaryDnsAccountResource.acl.listOperationId());
    try std.testing.expectEqualStrings("secondary-dns-(-peer)-peer-details", SecondaryDnsAccountResource.peer.detailOperationId());
    try std.testing.expectEqualStrings("secondary-dns-(-tsig)-list-tsi-gs", SecondaryDnsAccountResource.tsig.listOperationId());

    try std.testing.expectEqual(SecondaryDnsAccountMutationEndpoint.create, SecondaryDnsAccountMutationEndpoint.parse("add").?);
    try std.testing.expectEqual(SecondaryDnsAccountMutationEndpoint.update, SecondaryDnsAccountMutationEndpoint.parse("replace").?);
    try std.testing.expectEqual(SecondaryDnsAccountMutationEndpoint.delete_resource, SecondaryDnsAccountMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("POST", SecondaryDnsAccountMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", SecondaryDnsAccountMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", SecondaryDnsAccountMutationEndpoint.delete_resource.method());
    try std.testing.expectEqualStrings("secondary-dns-(-acl)-create-acl", SecondaryDnsAccountMutationEndpoint.create.operationId(.acl));
    try std.testing.expectEqualStrings("secondary-dns-(-peer)-update-peer", SecondaryDnsAccountMutationEndpoint.update.operationId(.peer));
    try std.testing.expectEqualStrings("secondary-dns-(-tsig)-delete-tsig", SecondaryDnsAccountMutationEndpoint.delete_resource.operationId(.tsig));
    try std.testing.expectEqualStrings("inline:{ip_range:string,name:string}", SecondaryDnsAccountMutationEndpoint.create.requestBodySchemaRef(.acl).?);
    try std.testing.expectEqualStrings("#/components/schemas/secondary-dns_peer", SecondaryDnsAccountMutationEndpoint.update.requestBodySchemaRef(.peer).?);
    try std.testing.expectEqualStrings("#/components/schemas/secondary-dns_tsig", SecondaryDnsAccountMutationEndpoint.create.requestBodySchemaRef(.tsig).?);
    try std.testing.expect(SecondaryDnsAccountMutationEndpoint.delete_resource.requestBodySchemaRef(.acl) == null);
    try std.testing.expect(SecondaryDnsAccountMutationEndpoint.update.requiresResourceId());
    try std.testing.expect(!SecondaryDnsAccountMutationEndpoint.create.requiresResourceId());

    try std.testing.expectEqual(SecondaryDnsZoneReadEndpoint.primary, SecondaryDnsZoneReadEndpoint.parse("outgoing").?);
    try std.testing.expectEqual(SecondaryDnsZoneReadEndpoint.primary_status, SecondaryDnsZoneReadEndpoint.parse("outgoing-status").?);
    try std.testing.expectEqual(SecondaryDnsZoneReadEndpoint.secondary, SecondaryDnsZoneReadEndpoint.parse("incoming").?);
    try std.testing.expectEqualStrings("secondary-dns-(-primary-zone)-primary-zone-configuration-details", SecondaryDnsZoneReadEndpoint.primary.operationId());
    try std.testing.expectEqualStrings("secondary-dns-(-primary-zone)-get-outgoing-zone-transfer-status", SecondaryDnsZoneReadEndpoint.primary_status.operationId());
    try std.testing.expectEqualStrings("secondary-dns-(-secondary-zone)-secondary-zone-configuration-details", SecondaryDnsZoneReadEndpoint.secondary.operationId());

    try std.testing.expectEqual(SecondaryDnsZoneMutationEndpoint.primary_create, SecondaryDnsZoneMutationEndpoint.parse("create-primary").?);
    try std.testing.expectEqual(SecondaryDnsZoneMutationEndpoint.primary_force_notify, SecondaryDnsZoneMutationEndpoint.parse("force-notify").?);
    try std.testing.expectEqual(SecondaryDnsZoneMutationEndpoint.secondary_force_axfr, SecondaryDnsZoneMutationEndpoint.parse("force-axfr").?);
    try std.testing.expectEqualStrings("POST", SecondaryDnsZoneMutationEndpoint.primary_create.method());
    try std.testing.expectEqualStrings("PUT", SecondaryDnsZoneMutationEndpoint.secondary_update.method());
    try std.testing.expectEqualStrings("DELETE", SecondaryDnsZoneMutationEndpoint.secondary_delete.method());
    try std.testing.expectEqualStrings("secondary-dns-(-primary-zone)-create-primary-zone-configuration", SecondaryDnsZoneMutationEndpoint.primary_create.operationId());
    try std.testing.expectEqualStrings("secondary-dns-(-secondary-zone)-force-axfr", SecondaryDnsZoneMutationEndpoint.secondary_force_axfr.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/secondary-dns_single_request_outgoing", SecondaryDnsZoneMutationEndpoint.primary_create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/secondary-dns_dns-secondary-secondary-zone", SecondaryDnsZoneMutationEndpoint.secondary_update.requestBodySchemaRef().?);
    try std.testing.expect(SecondaryDnsZoneMutationEndpoint.primary_force_notify.requestBodySchemaRef() == null);
}

test "builds Cloudflare secondary dns dry-run plans" {
    const allocator = std.testing.allocator;

    const acl_create = try secondaryDnsAccountMutationPlanJson(allocator, .create, .{ .resource = .acl, .account_id = "acct/1" });
    defer allocator.free(acl_create);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"group\":\"Secondary DNS (ACL)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"operation_id\":\"secondary-dns-(-acl)-create-acl\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"path\":\"/accounts/acct%2F1/secondary_dns/acls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"request_body_schema\":\"inline:{ip_range:string,name:string}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acl_create, "\"will_execute\":false") != null);

    const peer_update = try secondaryDnsAccountMutationPlanJson(allocator, .update, .{ .resource = .peer, .account_id = "acct/1", .resource_id = "peer/1" });
    defer allocator.free(peer_update);
    try std.testing.expect(std.mem.indexOf(u8, peer_update, "\"operation_id\":\"secondary-dns-(-peer)-update-peer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, peer_update, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, peer_update, "\"path\":\"/accounts/acct%2F1/secondary_dns/peers/peer%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, peer_update, "\"request_body_schema\":\"#/components/schemas/secondary-dns_peer\"") != null);

    const tsig_delete = try secondaryDnsAccountMutationPlanJson(allocator, .delete_resource, .{ .resource = .tsig, .account_id = "acct/1", .resource_id = "tsig/1" });
    defer allocator.free(tsig_delete);
    try std.testing.expect(std.mem.indexOf(u8, tsig_delete, "\"operation_id\":\"secondary-dns-(-tsig)-delete-tsig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tsig_delete, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tsig_delete, "\"path\":\"/accounts/acct%2F1/secondary_dns/tsigs/tsig%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tsig_delete, "\"request_body_schema\":null") != null);

    const primary = try secondaryDnsZoneMutationPlanJson(allocator, .primary_force_notify, .{ .zone_id = "zone/1" });
    defer allocator.free(primary);
    try std.testing.expect(std.mem.indexOf(u8, primary, "\"group\":\"Secondary DNS (Primary Zone)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, primary, "\"operation_id\":\"secondary-dns-(-primary-zone)-force-dns-notify\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, primary, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, primary, "\"path\":\"/zones/zone%2F1/secondary_dns/outgoing/force_notify\"") != null);

    const secondary = try secondaryDnsZoneMutationPlanJson(allocator, .secondary_update, .{ .zone_id = "zone/1" });
    defer allocator.free(secondary);
    try std.testing.expect(std.mem.indexOf(u8, secondary, "\"group\":\"Secondary DNS (Secondary Zone)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, secondary, "\"operation_id\":\"secondary-dns-(-secondary-zone)-update-secondary-zone-configuration\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, secondary, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, secondary, "\"path\":\"/zones/zone%2F1/secondary_dns/incoming\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, secondary, "\"request_body_schema\":\"#/components/schemas/secondary-dns_dns-secondary-secondary-zone\"") != null);

    try std.testing.expectError(error.MissingCloudflareSecondaryDnsResourceId, secondaryDnsAccountMutationPlanJson(allocator, .update, .{ .resource = .acl, .account_id = "acct/1" }));
}

test "cloudflare dns firewall and analytics endpoints map to official operation metadata" {
    try std.testing.expectEqual(DnsAnalyticsEndpoint.report, DnsAnalyticsEndpoint.parse("table").?);
    try std.testing.expectEqual(DnsAnalyticsEndpoint.bytime, DnsAnalyticsEndpoint.parse("by-time").?);
    try std.testing.expectEqualStrings("dns-analytics-table", DnsAnalyticsEndpoint.report.operationId());
    try std.testing.expectEqualStrings("dns-firewall-analytics-by-time", DnsAnalyticsEndpoint.bytime.firewallOperationId());
    try std.testing.expectEqualStrings("report/bytime", DnsAnalyticsEndpoint.bytime.suffix());

    try std.testing.expectEqual(DnsFirewallReadEndpoint.list, DnsFirewallReadEndpoint.parse("clusters").?);
    try std.testing.expectEqual(DnsFirewallReadEndpoint.details, DnsFirewallReadEndpoint.parse("show").?);
    try std.testing.expectEqual(DnsFirewallReadEndpoint.reverse_dns, DnsFirewallReadEndpoint.parse("reverse").?);
    try std.testing.expectEqualStrings("dns-firewall-list-dns-firewall-clusters", DnsFirewallReadEndpoint.list.operationId());
    try std.testing.expectEqualStrings("dns-firewall-show-dns-firewall-cluster-reverse-dns", DnsFirewallReadEndpoint.reverse_dns.operationId());
    try std.testing.expect(DnsFirewallReadEndpoint.details.requiresFirewallId());
    try std.testing.expect(!DnsFirewallReadEndpoint.list.requiresFirewallId());

    try std.testing.expectEqual(DnsFirewallMutationEndpoint.create, DnsFirewallMutationEndpoint.parse("create-cluster").?);
    try std.testing.expectEqual(DnsFirewallMutationEndpoint.update, DnsFirewallMutationEndpoint.parse("update-cluster").?);
    try std.testing.expectEqual(DnsFirewallMutationEndpoint.delete_cluster, DnsFirewallMutationEndpoint.parse("delete-cluster").?);
    try std.testing.expectEqual(DnsFirewallMutationEndpoint.update_reverse_dns, DnsFirewallMutationEndpoint.parse("reverse-dns").?);
    try std.testing.expectEqualStrings("POST", DnsFirewallMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PATCH", DnsFirewallMutationEndpoint.update_reverse_dns.method());
    try std.testing.expectEqualStrings("DELETE", DnsFirewallMutationEndpoint.delete_cluster.method());
    try std.testing.expectEqualStrings("dns-firewall-create-dns-firewall-cluster", DnsFirewallMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("dns-firewall-update-dns-firewall-cluster-reverse-dns", DnsFirewallMutationEndpoint.update_reverse_dns.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/dns-firewall_dns-firewall-cluster-post", DnsFirewallMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/dns-firewall_dns-firewall-reverse-dns-patch", DnsFirewallMutationEndpoint.update_reverse_dns.requestBodySchemaRef().?);
    try std.testing.expect(DnsFirewallMutationEndpoint.delete_cluster.requestBodySchemaRef() == null);

    try std.testing.expectEqual(DnsSettingsMutationEndpoint.account, DnsSettingsMutationEndpoint.parse("account").?);
    try std.testing.expectEqual(DnsSettingsMutationEndpoint.zone, DnsSettingsMutationEndpoint.parse("zone").?);
    try std.testing.expectEqualStrings("dns-settings-for-an-account-update-dns-settings", DnsSettingsMutationEndpoint.account.operationId());
    try std.testing.expectEqualStrings("dns-settings-for-a-zone-update-dns-settings", DnsSettingsMutationEndpoint.zone.operationId());
}

test "builds Cloudflare dns firewall, analytics, and settings paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const dns_analytics = try dnsAnalyticsPath(allocator, "zone/1", .bytime);
    defer allocator.free(dns_analytics);
    try std.testing.expectEqualStrings("/zones/zone%2F1/dns_analytics/report/bytime", dns_analytics);

    const firewall_analytics = try dnsFirewallAnalyticsPath(allocator, "acct/1", "firewall/1", .report);
    defer allocator.free(firewall_analytics);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/dns_firewall/firewall%2F1/dns_analytics/report", firewall_analytics);

    const create = try dnsFirewallMutationPlanJson(allocator, .create, .{ .account_id = "acct/1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"DNS Firewall\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"dns-firewall-create-dns-firewall-cluster\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts/acct%2F1/dns_firewall\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/dns-firewall_dns-firewall-cluster-post\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const reverse = try dnsFirewallMutationPlanJson(allocator, .update_reverse_dns, .{ .account_id = "acct/1", .dns_firewall_id = "firewall/1" });
    defer allocator.free(reverse);
    try std.testing.expect(std.mem.indexOf(u8, reverse, "\"operation_id\":\"dns-firewall-update-dns-firewall-cluster-reverse-dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, reverse, "\"path\":\"/accounts/acct%2F1/dns_firewall/firewall%2F1/reverse_dns\"") != null);

    const account_settings = try dnsSettingsMutationPlanJson(allocator, .account, .{ .account_id = "acct/1" });
    defer allocator.free(account_settings);
    try std.testing.expect(std.mem.indexOf(u8, account_settings, "\"group\":\"DNS Settings for an Account\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_settings, "\"operation_id\":\"dns-settings-for-an-account-update-dns-settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_settings, "\"path\":\"/accounts/acct%2F1/dns_settings\"") != null);

    const zone_settings = try dnsSettingsMutationPlanJson(allocator, .zone, .{ .zone_id = "zone/1" });
    defer allocator.free(zone_settings);
    try std.testing.expect(std.mem.indexOf(u8, zone_settings, "\"group\":\"DNS Settings for a Zone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_settings, "\"operation_id\":\"dns-settings-for-a-zone-update-dns-settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_settings, "\"path\":\"/zones/zone%2F1/dns_settings\"") != null);

    try std.testing.expectError(error.MissingCloudflareDnsFirewallId, dnsFirewallMutationPlanJson(allocator, .update, .{ .account_id = "acct/1" }));
    try std.testing.expectError(error.MissingCloudflareAccountId, dnsSettingsMutationPlanJson(allocator, .account, .{}));
    try std.testing.expectError(error.MissingCloudflareZoneId, dnsSettingsMutationPlanJson(allocator, .zone, .{}));
}

test "cloudflare load-balancing endpoints map to official operation metadata" {
    try std.testing.expectEqual(LoadBalancingAccountReadEndpoint.monitor_groups, LoadBalancingAccountReadEndpoint.parse("monitor-groups").?);
    try std.testing.expectEqual(LoadBalancingAccountReadEndpoint.monitor_group_references, LoadBalancingAccountReadEndpoint.parse("monitor-group-refs").?);
    try std.testing.expectEqual(LoadBalancingAccountReadEndpoint.monitor_preview_result, LoadBalancingAccountReadEndpoint.parse("preview-result").?);
    try std.testing.expectEqual(LoadBalancingAccountReadEndpoint.pool_health, LoadBalancingAccountReadEndpoint.parse("pool-health").?);
    try std.testing.expectEqualStrings("account-load-balancer-pools-pool-health-details", LoadBalancingAccountReadEndpoint.pool_health.operationId());
    try std.testing.expectEqualStrings("load-balancer-regions-get-region", LoadBalancingAccountReadEndpoint.region.operationId());
    try std.testing.expect(LoadBalancingAccountReadEndpoint.pool_health.requiresResourceId());
    try std.testing.expect(!LoadBalancingAccountReadEndpoint.pools.requiresResourceId());

    try std.testing.expectEqual(LoadBalancingUserReadEndpoint.healthcheck_events, LoadBalancingUserReadEndpoint.parse("events").?);
    try std.testing.expectEqualStrings("load-balancer-healthcheck-events-list-healthcheck-events", LoadBalancingUserReadEndpoint.healthcheck_events.operationId());
    try std.testing.expect(LoadBalancingUserReadEndpoint.monitor_references.requiresResourceId());
    try std.testing.expect(!LoadBalancingUserReadEndpoint.healthcheck_events.requiresResourceId());

    try std.testing.expectEqual(LoadBalancingZoneReadEndpoint.load_balancers, LoadBalancingZoneReadEndpoint.parse("list").?);
    try std.testing.expectEqual(LoadBalancingZoneReadEndpoint.load_balancer, LoadBalancingZoneReadEndpoint.parse("show").?);
    try std.testing.expectEqualStrings("load-balancers-load-balancer-details", LoadBalancingZoneReadEndpoint.load_balancer.operationId());

    try std.testing.expectEqual(LoadBalancingMutationResource.account_pool, LoadBalancingMutationResource.parse("account-pool").?);
    try std.testing.expectEqual(LoadBalancingMutationResource.zone_load_balancer, LoadBalancingMutationResource.parse("load-balancer").?);
    try std.testing.expectEqual(LoadBalancingMutationEndpoint.patch_collection, LoadBalancingMutationEndpoint.parse("patch-all").?);
    try std.testing.expect(LoadBalancingMutationEndpoint.preview.supports(.user_monitor));
    try std.testing.expect(!LoadBalancingMutationEndpoint.preview.supports(.account_monitor_group));
    try std.testing.expectEqualStrings("account-load-balancer-pools-patch-pools", try LoadBalancingMutationEndpoint.patch_collection.operationId(.account_pool));
    try std.testing.expectEqualStrings("load-balancers-update-load-balancer", try LoadBalancingMutationEndpoint.update.operationId(.zone_load_balancer));
    try std.testing.expectEqualStrings("string", (try LoadBalancingMutationEndpoint.patch_collection.requestBodySchemaRef(.account_pool)).?);
    try std.testing.expectError(error.UnsupportedCloudflareLoadBalancingMutation, LoadBalancingMutationEndpoint.preview.operationId(.zone_load_balancer));
}

test "builds Cloudflare load-balancing paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const account_monitors = try loadBalancingAccountReadUrl(allocator, base_url, "acct/1", .monitors, null, null);
    defer allocator.free(account_monitors);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/load_balancers/monitors", account_monitors);

    const account_pool_health = try loadBalancingAccountReadPath(allocator, "acct/1", .pool_health, "pool/1", null);
    defer allocator.free(account_pool_health);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/load_balancers/pools/pool%2F1/health", account_pool_health);

    const account_search = try loadBalancingAccountReadPath(allocator, "acct 1", .search, null, "origin name");
    defer allocator.free(account_search);
    try std.testing.expectEqualStrings("/accounts/acct%201/load_balancers/search?query=origin%20name", account_search);

    const user_events = try loadBalancingUserReadPath(allocator, .healthcheck_events, null);
    defer allocator.free(user_events);
    try std.testing.expectEqualStrings("/user/load_balancing_analytics/events", user_events);

    const user_monitor_refs = try loadBalancingUserReadPath(allocator, .monitor_references, "monitor/1");
    defer allocator.free(user_monitor_refs);
    try std.testing.expectEqualStrings("/user/load_balancers/monitors/monitor%2F1/references", user_monitor_refs);

    const zone_lb = try loadBalancingZoneReadPath(allocator, "zone/1", .load_balancer, "lb/1");
    defer allocator.free(zone_lb);
    try std.testing.expectEqualStrings("/zones/zone%2F1/load_balancers/lb%2F1", zone_lb);

    const patch_pools = try loadBalancingMutationPlanJson(allocator, .patch_collection, .{ .resource = .account_pool, .account_id = "acct/1" });
    defer allocator.free(patch_pools);
    try std.testing.expect(std.mem.indexOf(u8, patch_pools, "\"operation_id\":\"account-load-balancer-pools-patch-pools\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, patch_pools, "\"path\":\"/accounts/acct%2F1/load_balancers/pools\"") != null);

    const user_preview = try loadBalancingMutationPlanJson(allocator, .preview, .{ .resource = .user_monitor, .resource_id = "monitor/1" });
    defer allocator.free(user_preview);
    try std.testing.expect(std.mem.indexOf(u8, user_preview, "\"operation_id\":\"load-balancer-monitors-preview-monitor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_preview, "\"path\":\"/user/load_balancers/monitors/monitor%2F1/preview\"") != null);

    const zone_update = try loadBalancingMutationPlanJson(allocator, .update, .{ .resource = .zone_load_balancer, .zone_id = "zone/1", .resource_id = "lb/1" });
    defer allocator.free(zone_update);
    try std.testing.expect(std.mem.indexOf(u8, zone_update, "\"operation_id\":\"load-balancers-update-load-balancer\"") != null);

    try std.testing.expectError(error.MissingCloudflareAccountId, loadBalancingMutationPlanJson(allocator, .create, .{ .resource = .account_monitor }));
    try std.testing.expectError(error.MissingCloudflareLoadBalancingResourceId, loadBalancingMutationPlanJson(allocator, .patch, .{ .resource = .user_pool }));
    try std.testing.expectError(error.UnsupportedCloudflareLoadBalancingMutation, loadBalancingMutationPlanJson(allocator, .preview, .{ .resource = .account_monitor_group, .account_id = "acct/1", .resource_id = "monitor-group/1" }));
}

test "cloudflare health-check endpoints map to official operation metadata" {
    try std.testing.expectEqual(EndpointHealthCheckReadEndpoint.list, EndpointHealthCheckReadEndpoint.parse("endpoint-healthchecks").?);
    try std.testing.expectEqual(EndpointHealthCheckReadEndpoint.details, EndpointHealthCheckReadEndpoint.parse("endpoint-healthcheck").?);
    try std.testing.expectEqualStrings("Endpoint Health Checks", EndpointHealthCheckReadEndpoint.list.group());
    try std.testing.expectEqualStrings("diagnostics-endpoint-healthcheck-list", EndpointHealthCheckReadEndpoint.list.operationId());
    try std.testing.expectEqualStrings("diagnostics-endpoint-healthcheck-get", EndpointHealthCheckReadEndpoint.details.operationId());
    try std.testing.expect(EndpointHealthCheckReadEndpoint.details.requiresHealthCheckId());
    try std.testing.expect(!EndpointHealthCheckReadEndpoint.list.requiresHealthCheckId());

    try std.testing.expectEqual(ZoneHealthCheckReadEndpoint.list, ZoneHealthCheckReadEndpoint.parse("healthchecks").?);
    try std.testing.expectEqual(ZoneHealthCheckReadEndpoint.details, ZoneHealthCheckReadEndpoint.parse("healthcheck").?);
    try std.testing.expectEqual(ZoneHealthCheckReadEndpoint.preview_details, ZoneHealthCheckReadEndpoint.parse("preview").?);
    try std.testing.expectEqualStrings("health-checks-list-health-checks", ZoneHealthCheckReadEndpoint.list.operationId());
    try std.testing.expectEqualStrings("health-checks-health-check-details", ZoneHealthCheckReadEndpoint.details.operationId());
    try std.testing.expectEqualStrings("health-checks-health-check-preview-details", ZoneHealthCheckReadEndpoint.preview_details.operationId());

    try std.testing.expectEqual(SmartShieldHealthCheckReadEndpoint.list, SmartShieldHealthCheckReadEndpoint.parse("healthchecks").?);
    try std.testing.expectEqual(SmartShieldHealthCheckReadEndpoint.details, SmartShieldHealthCheckReadEndpoint.parse("show").?);
    try std.testing.expectEqualStrings("smart-shield-list-health-checks", SmartShieldHealthCheckReadEndpoint.list.operationId());
    try std.testing.expectEqualStrings("smart-shield-health-check-details", SmartShieldHealthCheckReadEndpoint.details.operationId());

    try std.testing.expectEqual(HealthCheckMutationResource.endpoint, HealthCheckMutationResource.parse("endpoint-healthcheck").?);
    try std.testing.expectEqual(HealthCheckMutationResource.smart_shield, HealthCheckMutationResource.parse("smartshield").?);
    try std.testing.expectEqual(HealthCheckMutationEndpoint.delete_resource, HealthCheckMutationEndpoint.parse("remove").?);
    try std.testing.expect(HealthCheckMutationEndpoint.create.supports(.preview));
    try std.testing.expect(!HealthCheckMutationEndpoint.patch.supports(.endpoint));
    try std.testing.expect(!HealthCheckMutationEndpoint.update.supports(.preview));
    try std.testing.expectEqualStrings("diagnostics-endpoint-healthcheck-create", try HealthCheckMutationEndpoint.create.operationId(.endpoint));
    try std.testing.expectEqualStrings("health-checks-patch-health-check", try HealthCheckMutationEndpoint.patch.operationId(.zone));
    try std.testing.expectEqualStrings("smart-shield-update-health-check", try HealthCheckMutationEndpoint.update.operationId(.smart_shield));
    try std.testing.expectEqualStrings("#/components/schemas/healthchecks_query_healthcheck", (try HealthCheckMutationEndpoint.create.requestBodySchemaRef(.zone)).?);
    try std.testing.expectEqualStrings("#/components/schemas/smartshield_single_hc_response", (try HealthCheckMutationEndpoint.update.requestBodySchemaRef(.smart_shield)).?);
    try std.testing.expectError(error.UnsupportedCloudflareHealthCheckMutation, HealthCheckMutationEndpoint.patch.operationId(.endpoint));
}

test "builds Cloudflare health-check paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const endpoint_list = try endpointHealthCheckReadUrl(allocator, base_url, "acct/1", .list, null);
    defer allocator.free(endpoint_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/diagnostics/endpoint-healthchecks", endpoint_list);

    const endpoint_detail = try endpointHealthCheckReadPath(allocator, "acct/1", .details, "check/1");
    defer allocator.free(endpoint_detail);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/diagnostics/endpoint-healthchecks/check%2F1", endpoint_detail);

    const zone_preview = try zoneHealthCheckReadPath(allocator, "zone/1", .preview_details, "preview/1");
    defer allocator.free(zone_preview);
    try std.testing.expectEqualStrings("/zones/zone%2F1/healthchecks/preview/preview%2F1", zone_preview);

    const smart_shield = try smartShieldHealthCheckReadPath(allocator, "zone/1", .details, "check/1");
    defer allocator.free(smart_shield);
    try std.testing.expectEqualStrings("/zones/zone%2F1/smart_shield/healthchecks/check%2F1", smart_shield);

    const endpoint_create = try healthCheckMutationPlanJson(allocator, .create, .{ .resource = .endpoint, .account_id = "acct/1" });
    defer allocator.free(endpoint_create);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"group\":\"Endpoint Health Checks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"operation_id\":\"diagnostics-endpoint-healthcheck-create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"path\":\"/accounts/acct%2F1/diagnostics/endpoint-healthchecks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"request_body_schema\":\"#/components/schemas/magic-transit_endpoint_health_check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, endpoint_create, "\"will_execute\":false") != null);

    const zone_patch = try healthCheckMutationPlanJson(allocator, .patch, .{ .resource = .zone, .zone_id = "zone/1", .healthcheck_id = "check/1" });
    defer allocator.free(zone_patch);
    try std.testing.expect(std.mem.indexOf(u8, zone_patch, "\"operation_id\":\"health-checks-patch-health-check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_patch, "\"path\":\"/zones/zone%2F1/healthchecks/check%2F1\"") != null);

    const preview_delete = try healthCheckMutationPlanJson(allocator, .delete_resource, .{ .resource = .preview, .zone_id = "zone/1", .healthcheck_id = "preview/1" });
    defer allocator.free(preview_delete);
    try std.testing.expect(std.mem.indexOf(u8, preview_delete, "\"operation_id\":\"health-checks-delete-preview-health-check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview_delete, "\"request_body_schema\":null") != null);

    const smart_update = try healthCheckMutationPlanJson(allocator, .update, .{ .resource = .smart_shield, .zone_id = "zone/1", .healthcheck_id = "check/1" });
    defer allocator.free(smart_update);
    try std.testing.expect(std.mem.indexOf(u8, smart_update, "\"operation_id\":\"smart-shield-update-health-check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, smart_update, "\"path\":\"/zones/zone%2F1/smart_shield/healthchecks/check%2F1\"") != null);

    try std.testing.expectError(error.MissingCloudflareAccountId, healthCheckMutationPlanJson(allocator, .create, .{ .resource = .endpoint }));
    try std.testing.expectError(error.MissingCloudflareZoneId, healthCheckMutationPlanJson(allocator, .create, .{ .resource = .zone }));
    try std.testing.expectError(error.MissingCloudflareHealthCheckId, healthCheckMutationPlanJson(allocator, .update, .{ .resource = .zone, .zone_id = "zone/1" }));
    try std.testing.expectError(error.UnsupportedCloudflareHealthCheckMutation, healthCheckMutationPlanJson(allocator, .patch, .{ .resource = .endpoint, .account_id = "acct/1", .healthcheck_id = "check/1" }));
}

test "cloudflare ruleset endpoints map to official operation metadata" {
    try std.testing.expectEqual(RulesetScope.account, RulesetScope.parse("accounts").?);
    try std.testing.expectEqual(RulesetScope.zone, RulesetScope.parse("zone").?);
    try std.testing.expectEqualStrings("Account Rulesets", RulesetScope.account.group());
    try std.testing.expectEqualStrings("zone", RulesetScope.zone.idLabel());

    try std.testing.expectEqual(RulesetReadEndpoint.list, RulesetReadEndpoint.parse("rulesets").?);
    try std.testing.expectEqual(RulesetReadEndpoint.ruleset, RulesetReadEndpoint.parse("show").?);
    try std.testing.expectEqual(RulesetReadEndpoint.entrypoint_versions, RulesetReadEndpoint.parse("entry-point-versions").?);
    try std.testing.expectEqual(RulesetReadEndpoint.rules_by_tag, RulesetReadEndpoint.parse("by-tag").?);
    try std.testing.expectEqualStrings("account-ruleset-entrypoint-version", RulesetReadEndpoint.entrypoint_version.label(.account));
    try std.testing.expectEqualStrings("zone-ruleset-version-rules-by-tag", RulesetReadEndpoint.rules_by_tag.label(.zone));
    try std.testing.expectEqualStrings("listAccountRulesets", RulesetReadEndpoint.list.operationId(.account));
    try std.testing.expectEqualStrings("getZoneEntrypointRulesetVersion", RulesetReadEndpoint.entrypoint_version.operationId(.zone));
    try std.testing.expectEqualStrings("listAccountRulesetVersionRulesByTag", RulesetReadEndpoint.rules_by_tag.operationId(.account));
    try std.testing.expect(RulesetReadEndpoint.ruleset.requiresRulesetId());
    try std.testing.expect(RulesetReadEndpoint.entrypoint.requiresPhase());
    try std.testing.expect(RulesetReadEndpoint.version.requiresVersion());
    try std.testing.expect(RulesetReadEndpoint.rules_by_tag.requiresRuleTag());

    try std.testing.expectEqual(RulesetMutationEndpoint.create_ruleset, RulesetMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(RulesetMutationEndpoint.update_entrypoint, RulesetMutationEndpoint.parse("update-entry-point").?);
    try std.testing.expectEqual(RulesetMutationEndpoint.update_rule, RulesetMutationEndpoint.parse("patch-rule").?);
    try std.testing.expectEqualStrings("POST", RulesetMutationEndpoint.create_rule.method());
    try std.testing.expectEqualStrings("DELETE", RulesetMutationEndpoint.delete_version.method());
    try std.testing.expectEqualStrings("createAccountRulesetRule", RulesetMutationEndpoint.create_rule.operationId(.account));
    try std.testing.expectEqualStrings("deleteZoneRulesetVersion", RulesetMutationEndpoint.delete_version.operationId(.zone));
    try std.testing.expectEqualStrings("#/components/requestBodies/rulesets_UpdateEntrypointRuleset", RulesetMutationEndpoint.update_entrypoint.requestBodySchemaRef().?);
    try std.testing.expectEqual(@as(?[]const u8, null), RulesetMutationEndpoint.delete_rule.requestBodySchemaRef());
    try std.testing.expect(RulesetMutationEndpoint.update_rule.requiresRuleId());
    try std.testing.expect(RulesetMutationEndpoint.delete_version.requiresVersion());
}

test "builds Cloudflare ruleset paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const account_list = try rulesetReadUrl(allocator, base_url, .account, "acct/1", .list, .{});
    defer allocator.free(account_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/rulesets?per_page=50", account_list);

    const account_ruleset = try rulesetReadPath(allocator, .account, "acct/1", .ruleset, .{ .ruleset_id = "ruleset/1" });
    defer allocator.free(account_ruleset);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/rulesets/ruleset%2F1", account_ruleset);

    const account_entrypoint_version = try rulesetReadPath(allocator, .account, "acct/1", .entrypoint_version, .{ .phase = "http/request", .version = "42" });
    defer allocator.free(account_entrypoint_version);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/rulesets/phases/http%2Frequest/entrypoint/versions/42", account_entrypoint_version);

    const zone_by_tag = try rulesetReadPath(allocator, .zone, "zone/1", .rules_by_tag, .{ .ruleset_id = "ruleset/1", .version = "latest", .rule_tag = "tag/name" });
    defer allocator.free(zone_by_tag);
    try std.testing.expectEqualStrings("/zones/zone%2F1/rulesets/ruleset%2F1/versions/latest/by_tag/tag%2Fname", zone_by_tag);

    const account_create = try rulesetMutationPlanJson(allocator, .create_ruleset, .{ .scope = .account, .scope_id = "acct/1" });
    defer allocator.free(account_create);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"group\":\"Account Rulesets\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"operation_id\":\"createAccountRuleset\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"path\":\"/accounts/acct%2F1/rulesets\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"request_body_schema\":\"#/components/requestBodies/rulesets_CreateRuleset\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"will_execute\":false") != null);

    const zone_entrypoint = try rulesetMutationPlanJson(allocator, .update_entrypoint, .{ .scope = .zone, .scope_id = "zone/1", .phase = "http_request_firewall_custom" });
    defer allocator.free(zone_entrypoint);
    try std.testing.expect(std.mem.indexOf(u8, zone_entrypoint, "\"operation_id\":\"updateZoneEntrypointRuleset\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_entrypoint, "\"path\":\"/zones/zone%2F1/rulesets/phases/http_request_firewall_custom/entrypoint\"") != null);

    const zone_update_rule = try rulesetMutationPlanJson(allocator, .update_rule, .{ .scope = .zone, .scope_id = "zone/1", .ruleset_id = "ruleset/1", .rule_id = "rule/1" });
    defer allocator.free(zone_update_rule);
    try std.testing.expect(std.mem.indexOf(u8, zone_update_rule, "\"operation_id\":\"updateZoneRulesetRule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_update_rule, "\"path\":\"/zones/zone%2F1/rulesets/ruleset%2F1/rules/rule%2F1\"") != null);

    const account_delete_version = try rulesetMutationPlanJson(allocator, .delete_version, .{ .scope = .account, .scope_id = "acct/1", .ruleset_id = "ruleset/1", .version = "7" });
    defer allocator.free(account_delete_version);
    try std.testing.expect(std.mem.indexOf(u8, account_delete_version, "\"operation_id\":\"deleteAccountRulesetVersion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_delete_version, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflareRulesetId, rulesetReadPath(allocator, .zone, "zone/1", .ruleset, .{}));
    try std.testing.expectError(error.MissingCloudflareRulesetPhase, rulesetReadPath(allocator, .account, "acct/1", .entrypoint, .{}));
    try std.testing.expectError(error.MissingCloudflareRulesetVersion, rulesetReadPath(allocator, .account, "acct/1", .version, .{ .ruleset_id = "ruleset/1" }));
    try std.testing.expectError(error.MissingCloudflareRulesetRuleId, rulesetMutationPlanJson(allocator, .update_rule, .{ .scope = .account, .scope_id = "acct/1", .ruleset_id = "ruleset/1" }));
}

test "cloudforce one rule endpoints map to official operation metadata" {
    try std.testing.expectEqual(CloudforceOneRuleReadEndpoint.list, CloudforceOneRuleReadEndpoint.parse("rules").?);
    try std.testing.expectEqual(CloudforceOneRuleReadEndpoint.managed, CloudforceOneRuleReadEndpoint.parse("managed-rules").?);
    try std.testing.expectEqual(CloudforceOneRuleReadEndpoint.rule, CloudforceOneRuleReadEndpoint.parse("detail").?);
    try std.testing.expectEqualStrings("cloudforce-one-list-rules", CloudforceOneRuleReadEndpoint.list.operationId());
    try std.testing.expectEqualStrings("cloudforce-one-get-managed-rules", CloudforceOneRuleReadEndpoint.managed.operationId());
    try std.testing.expectEqualStrings("cloudforce-one-search-rules", CloudforceOneRuleReadEndpoint.search.operationId());
    try std.testing.expectEqualStrings("cloudforce-one-get-rule-stats", CloudforceOneRuleReadEndpoint.stats.operationId());
    try std.testing.expectEqualStrings("cloudforce-one-get-rule-tree", CloudforceOneRuleReadEndpoint.tree.operationId());
    try std.testing.expectEqualStrings("cloudforce-one-get-rule", CloudforceOneRuleReadEndpoint.rule.operationId());
    try std.testing.expect(CloudforceOneRuleReadEndpoint.rule.requiresRuleId());
    try std.testing.expect(CloudforceOneRuleReadEndpoint.search.requiresQuery());
    try std.testing.expect(CloudforceOneRuleReadEndpoint.list.allowsListFilters());
    try std.testing.expect(!CloudforceOneRuleReadEndpoint.stats.allowsListFilters());

    try std.testing.expectEqual(CloudforceOneRuleMutationEndpoint.delete_all, CloudforceOneRuleMutationEndpoint.parse("clear").?);
    try std.testing.expectEqualStrings("POST", CloudforceOneRuleMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", CloudforceOneRuleMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", CloudforceOneRuleMutationEndpoint.delete_rule.method());
    try std.testing.expectEqualStrings("cloudforce-one-validate-rule", CloudforceOneRuleMutationEndpoint.validate.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/cloudforce-one_CreateRule", CloudforceOneRuleMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/cloudforce-one_UpdateRule", CloudforceOneRuleMutationEndpoint.update.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("object", CloudforceOneRuleMutationEndpoint.validate.requestBodySchemaRef().?);
    try std.testing.expectEqual(@as(?[]const u8, null), CloudforceOneRuleMutationEndpoint.delete_all.requestBodySchemaRef());
    try std.testing.expect(CloudforceOneRuleMutationEndpoint.update.requiresRuleId());
}

test "builds Cloudforce One rule paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const list = try cloudforceOneRuleReadUrl(allocator, base_url, "acct/1", .list, .{ .namespace = "yara/workers", .recursive = "true", .limit = "25" });
    defer allocator.free(list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/cloudforce-one/rules?namespace=yara%2Fworkers&recursive=true&limit=25", list);

    const search = try cloudforceOneRuleReadPath(allocator, "acct/1", .search, .{ .query = "proxy worker", .mode = "hybrid", .language = "yara" });
    defer allocator.free(search);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/cloudforce-one/rules/search?query=proxy%20worker&mode=hybrid&language=yara", search);

    const show = try cloudforceOneRuleReadPath(allocator, "acct/1", .rule, .{ .rule_id = "rule/1" });
    defer allocator.free(show);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/cloudforce-one/rules/rule%2F1", show);

    const managed = try cloudforceOneRuleReadPath(allocator, "acct/1", .managed, .{});
    defer allocator.free(managed);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/cloudforce-one/rules/managed", managed);

    const stats = try cloudforceOneRuleReadPath(allocator, "acct/1", .stats, .{});
    defer allocator.free(stats);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/cloudforce-one/rules/stats", stats);

    const tree = try cloudforceOneRuleReadPath(allocator, "acct/1", .tree, .{});
    defer allocator.free(tree);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/cloudforce-one/rules/tree", tree);

    const create = try cloudforceOneRuleMutationPlanJson(allocator, .create, .{ .account_id = "acct/1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Rules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"cloudforce-one-create-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/accounts/acct%2F1/cloudforce-one/rules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/cloudforce-one_CreateRule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const update = try cloudforceOneRuleMutationPlanJson(allocator, .update, .{ .account_id = "acct/1", .rule_id = "rule/1" });
    defer allocator.free(update);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"operation_id\":\"cloudforce-one-update-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update, "\"path\":\"/accounts/acct%2F1/cloudforce-one/rules/rule%2F1\"") != null);

    const validate = try cloudforceOneRuleMutationPlanJson(allocator, .validate, .{ .account_id = "acct/1" });
    defer allocator.free(validate);
    try std.testing.expect(std.mem.indexOf(u8, validate, "\"operation_id\":\"cloudforce-one-validate-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, validate, "\"request_body_schema\":\"object\"") != null);

    const delete_all = try cloudforceOneRuleMutationPlanJson(allocator, .delete_all, .{ .account_id = "acct/1" });
    defer allocator.free(delete_all);
    try std.testing.expect(std.mem.indexOf(u8, delete_all, "\"operation_id\":\"cloudforce-one-delete-all-rules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_all, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudforceOneRuleSearchQuery, cloudforceOneRuleReadPath(allocator, "acct/1", .search, .{}));
    try std.testing.expectError(error.MissingCloudforceOneRuleId, cloudforceOneRuleReadPath(allocator, "acct/1", .rule, .{}));
    try std.testing.expectError(error.MissingCloudforceOneRuleId, cloudforceOneRuleMutationPlanJson(allocator, .delete_rule, .{ .account_id = "acct/1" }));
}

test "ip access rule endpoints map to official operation metadata" {
    try std.testing.expectEqual(IpAccessRuleScope.user, IpAccessRuleScope.parse("user").?);
    try std.testing.expectEqual(IpAccessRuleScope.account, IpAccessRuleScope.parse("accounts").?);
    try std.testing.expectEqual(IpAccessRuleScope.zone, IpAccessRuleScope.parse("zone").?);
    try std.testing.expectEqualStrings("IP Access rules for an account", IpAccessRuleScope.account.group());
    try std.testing.expect(!IpAccessRuleScope.user.usesScopeId());
    try std.testing.expect(IpAccessRuleScope.zone.usesScopeId());

    try std.testing.expectEqual(IpAccessRuleReadEndpoint.list, IpAccessRuleReadEndpoint.parse("rules").?);
    try std.testing.expectEqual(IpAccessRuleReadEndpoint.rule, IpAccessRuleReadEndpoint.parse("details").?);
    try std.testing.expectEqualStrings("ip-access-rules-for-a-user-list-ip-access-rules", (try IpAccessRuleReadEndpoint.list.operationId(.user)));
    try std.testing.expectEqualStrings("ip-access-rules-for-an-account-get-an-ip-access-rule", (try IpAccessRuleReadEndpoint.rule.operationId(.account)));
    try std.testing.expect(!IpAccessRuleReadEndpoint.rule.supports(.zone));
    try std.testing.expectError(error.UnsupportedCloudflareIpAccessRuleEndpoint, IpAccessRuleReadEndpoint.rule.operationId(.zone));

    try std.testing.expectEqual(IpAccessRuleMutationEndpoint.delete_rule, IpAccessRuleMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("POST", IpAccessRuleMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PATCH", IpAccessRuleMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("DELETE", IpAccessRuleMutationEndpoint.delete_rule.method());
    try std.testing.expectEqualStrings("ip-access-rules-for-a-zone-delete-an-ip-access-rule", IpAccessRuleMutationEndpoint.delete_rule.operationId(.zone));
    try std.testing.expectEqualStrings("#/components/schemas/firewall_schemas-rule", IpAccessRuleMutationEndpoint.update.requestBodySchemaRef(.account).?);
    try std.testing.expectEqualStrings("object", IpAccessRuleMutationEndpoint.delete_rule.requestBodySchemaRef(.zone).?);
    try std.testing.expectEqual(@as(?[]const u8, null), IpAccessRuleMutationEndpoint.delete_rule.requestBodySchemaRef(.account));
}

test "builds IP Access Rule paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const user_list = try ipAccessRuleReadUrl(allocator, base_url, .user, null, .list, .{
        .mode = "block",
        .configuration_target = "ip",
        .configuration_value = "198.51.100.4",
        .notes = "attack note",
        .match = "all",
        .per_page = "20",
    });
    defer allocator.free(user_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules?mode=block&configuration.target=ip&configuration.value=198.51.100.4&notes=attack%20note&match=all&per_page=20", user_list);

    const account_show = try ipAccessRuleReadPath(allocator, .account, "acct/1", .rule, .{ .rule_id = "rule/1" });
    defer allocator.free(account_show);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/firewall/access_rules/rules/rule%2F1", account_show);

    const zone_list = try ipAccessRuleReadPath(allocator, .zone, "zone/1", .list, .{ .order = "mode", .direction = "desc" });
    defer allocator.free(zone_list);
    try std.testing.expectEqualStrings("/zones/zone%2F1/firewall/access_rules/rules?order=mode&direction=desc", zone_list);

    const account_create = try ipAccessRuleMutationPlanJson(allocator, .create, .{ .scope = .account, .scope_id = "acct/1" });
    defer allocator.free(account_create);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"group\":\"IP Access rules for an account\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"operation_id\":\"ip-access-rules-for-an-account-create-an-ip-access-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"path\":\"/accounts/acct%2F1/firewall/access_rules/rules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"request_body_schema\":\"object\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_create, "\"will_execute\":false") != null);

    const user_update = try ipAccessRuleMutationPlanJson(allocator, .update, .{ .scope = .user, .rule_id = "rule/1" });
    defer allocator.free(user_update);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"operation_id\":\"ip-access-rules-for-a-user-update-an-ip-access-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, user_update, "\"path\":\"/user/firewall/access_rules/rules/rule%2F1\"") != null);

    const zone_delete = try ipAccessRuleMutationPlanJson(allocator, .delete_rule, .{ .scope = .zone, .scope_id = "zone/1", .rule_id = "rule/1" });
    defer allocator.free(zone_delete);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"operation_id\":\"ip-access-rules-for-a-zone-delete-an-ip-access-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"request_body_schema\":\"object\"") != null);

    try std.testing.expectError(error.UnsupportedCloudflareIpAccessRuleEndpoint, ipAccessRuleReadPath(allocator, .zone, "zone/1", .rule, .{ .rule_id = "rule/1" }));
    try std.testing.expectError(error.MissingCloudflareIpAccessRuleScopeId, ipAccessRuleReadPath(allocator, .account, null, .list, .{}));
    try std.testing.expectError(error.MissingCloudflareIpAccessRuleId, ipAccessRuleReadPath(allocator, .user, null, .rule, .{}));
    try std.testing.expectError(error.MissingCloudflareIpAccessRuleId, ipAccessRuleMutationPlanJson(allocator, .update, .{ .scope = .account, .scope_id = "acct/1" }));
}

test "zone legacy rule endpoints map to official operation metadata" {
    try std.testing.expectEqual(ZoneLegacyRuleResource.page_rules, ZoneLegacyRuleResource.parse("pagerules").?);
    try std.testing.expectEqual(ZoneLegacyRuleResource.ua_rules, ZoneLegacyRuleResource.parse("user-agent-blocking").?);
    try std.testing.expectEqual(ZoneLegacyRuleResource.zone_lockdown, ZoneLegacyRuleResource.parse("lockdowns").?);
    try std.testing.expectEqualStrings("Page Rules", ZoneLegacyRuleResource.page_rules.group());
    try std.testing.expectEqualStrings("firewall/ua_rules", ZoneLegacyRuleResource.ua_rules.collectionSuffix());

    try std.testing.expectEqual(ZoneLegacyRuleReadEndpoint.list, ZoneLegacyRuleReadEndpoint.parse("rules").?);
    try std.testing.expectEqual(ZoneLegacyRuleReadEndpoint.rule, ZoneLegacyRuleReadEndpoint.parse("details").?);
    try std.testing.expectEqualStrings("page-rules-list-page-rules", ZoneLegacyRuleReadEndpoint.list.operationId(.page_rules));
    try std.testing.expectEqualStrings("user-agent-blocking-rules-get-a-user-agent-blocking-rule", ZoneLegacyRuleReadEndpoint.rule.operationId(.ua_rules));
    try std.testing.expectEqualStrings("zone-lockdown-list-zone-lockdown-rules", ZoneLegacyRuleReadEndpoint.list.operationId(.zone_lockdown));

    try std.testing.expectEqual(ZoneLegacyRuleMutationEndpoint.delete_rule, ZoneLegacyRuleMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("POST", ZoneLegacyRuleMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", ZoneLegacyRuleMutationEndpoint.update.method());
    try std.testing.expectEqualStrings("PATCH", ZoneLegacyRuleMutationEndpoint.edit.method());
    try std.testing.expectEqualStrings("DELETE", ZoneLegacyRuleMutationEndpoint.delete_rule.method());
    try std.testing.expect(ZoneLegacyRuleMutationEndpoint.edit.supports(.page_rules));
    try std.testing.expect(!ZoneLegacyRuleMutationEndpoint.edit.supports(.ua_rules));
    try std.testing.expectEqualStrings("page-rules-edit-a-page-rule", try ZoneLegacyRuleMutationEndpoint.edit.operationId(.page_rules));
    try std.testing.expectEqualStrings("zone-lockdown-delete-a-zone-lockdown-rule", try ZoneLegacyRuleMutationEndpoint.delete_rule.operationId(.zone_lockdown));
    try std.testing.expectError(error.UnsupportedCloudflareZoneLegacyRuleMutation, ZoneLegacyRuleMutationEndpoint.edit.operationId(.zone_lockdown));
}

test "builds zone legacy rule paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const page_list = try zoneLegacyRuleReadUrl(allocator, base_url, "zone/1", .page_rules, .list, null);
    defer allocator.free(page_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2F1/pagerules", page_list);

    const ua_show = try zoneLegacyRuleReadPath(allocator, "zone/1", .ua_rules, .rule, "ua/1");
    defer allocator.free(ua_show);
    try std.testing.expectEqualStrings("/zones/zone%2F1/firewall/ua_rules/ua%2F1", ua_show);

    const lockdown_show = try zoneLegacyRuleReadPath(allocator, "zone/1", .zone_lockdown, .rule, "lock/1");
    defer allocator.free(lockdown_show);
    try std.testing.expectEqualStrings("/zones/zone%2F1/firewall/lockdowns/lock%2F1", lockdown_show);

    const page_create = try zoneLegacyRuleMutationPlanJson(allocator, .create, .{ .resource = .page_rules, .zone_id = "zone/1" });
    defer allocator.free(page_create);
    try std.testing.expect(std.mem.indexOf(u8, page_create, "\"group\":\"Page Rules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page_create, "\"operation_id\":\"page-rules-create-a-page-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page_create, "\"path\":\"/zones/zone%2F1/pagerules\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page_create, "\"request_body_schema\":\"object\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page_create, "\"will_execute\":false") != null);

    const page_edit = try zoneLegacyRuleMutationPlanJson(allocator, .edit, .{ .resource = .page_rules, .zone_id = "zone/1", .rule_id = "rule/1" });
    defer allocator.free(page_edit);
    try std.testing.expect(std.mem.indexOf(u8, page_edit, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page_edit, "\"operation_id\":\"page-rules-edit-a-page-rule\"") != null);

    const ua_update = try zoneLegacyRuleMutationPlanJson(allocator, .update, .{ .resource = .ua_rules, .zone_id = "zone/1", .rule_id = "ua/1" });
    defer allocator.free(ua_update);
    try std.testing.expect(std.mem.indexOf(u8, ua_update, "\"operation_id\":\"user-agent-blocking-rules-update-a-user-agent-blocking-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ua_update, "\"path\":\"/zones/zone%2F1/firewall/ua_rules/ua%2F1\"") != null);

    const lockdown_delete = try zoneLegacyRuleMutationPlanJson(allocator, .delete_rule, .{ .resource = .zone_lockdown, .zone_id = "zone/1", .rule_id = "lock/1" });
    defer allocator.free(lockdown_delete);
    try std.testing.expect(std.mem.indexOf(u8, lockdown_delete, "\"operation_id\":\"zone-lockdown-delete-a-zone-lockdown-rule\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, lockdown_delete, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflareZoneLegacyRuleId, zoneLegacyRuleReadPath(allocator, "zone/1", .page_rules, .rule, null));
    try std.testing.expectError(error.MissingCloudflareZoneLegacyRuleId, zoneLegacyRuleMutationPlanJson(allocator, .update, .{ .resource = .ua_rules, .zone_id = "zone/1" }));
    try std.testing.expectError(error.UnsupportedCloudflareZoneLegacyRuleMutation, zoneLegacyRuleMutationPlanJson(allocator, .edit, .{ .resource = .zone_lockdown, .zone_id = "zone/1", .rule_id = "lock/1" }));
}

test "page shield endpoints map to official operation metadata" {
    try std.testing.expectEqual(PageShieldReadEndpoint.settings, PageShieldReadEndpoint.parse("settings").?);
    try std.testing.expectEqual(PageShieldReadEndpoint.policies, PageShieldReadEndpoint.parse("policy-list").?);
    try std.testing.expectEqual(PageShieldReadEndpoint.policy, PageShieldReadEndpoint.parse("policy").?);
    try std.testing.expectEqual(PageShieldReadEndpoint.connection, PageShieldReadEndpoint.parse("connection-show").?);
    try std.testing.expectEqualStrings("page-shield-list-scripts", PageShieldReadEndpoint.scripts.operationId());
    try std.testing.expectEqualStrings("page-shield-get-cookie", PageShieldReadEndpoint.cookie.operationId());
    try std.testing.expect(PageShieldReadEndpoint.script.requiresResourceId());
    try std.testing.expect(PageShieldReadEndpoint.connections.acceptsFilters());
    try std.testing.expect(!PageShieldReadEndpoint.policy.acceptsFilters());

    try std.testing.expectEqual(PageShieldMutationEndpoint.update_settings, PageShieldMutationEndpoint.parse("settings").?);
    try std.testing.expectEqual(PageShieldMutationEndpoint.create_policy, PageShieldMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(PageShieldMutationEndpoint.delete_policy, PageShieldMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("PUT", PageShieldMutationEndpoint.update_settings.method());
    try std.testing.expectEqualStrings("POST", PageShieldMutationEndpoint.create_policy.method());
    try std.testing.expectEqualStrings("page-shield-update-policy", PageShieldMutationEndpoint.update_policy.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/page-shield_policy", PageShieldMutationEndpoint.create_policy.requestBodySchemaRef().?);
    try std.testing.expectEqual(@as(?[]const u8, null), PageShieldMutationEndpoint.delete_policy.requestBodySchemaRef());
}

test "builds Page Shield paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const settings = try pageShieldReadUrl(allocator, base_url, "zone/1", .settings, .{});
    defer allocator.free(settings);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2F1/page_shield", settings);

    const connections = try pageShieldReadPath(allocator, "zone/1", .connections, .{
        .hosts = "cdn.example.com,*.example.net",
        .page = "all",
        .per_page = "50",
        .order_by = "last_seen_at",
        .direction = "desc",
        .exclude_cdn_cgi = "true",
        .status = "active",
        .page_url = "https://example.com/checkout",
    });
    defer allocator.free(connections);
    try std.testing.expectEqualStrings("/zones/zone%2F1/page_shield/connections?hosts=cdn.example.com%2C%2A.example.net&page=all&per_page=50&order_by=last_seen_at&direction=desc&exclude_cdn_cgi=true&status=active&page_url=https%3A%2F%2Fexample.com%2Fcheckout", connections);

    const script = try pageShieldReadPath(allocator, "zone/1", .script, .{ .resource_id = "script/1" });
    defer allocator.free(script);
    try std.testing.expectEqualStrings("/zones/zone%2F1/page_shield/scripts/script%2F1", script);

    const cookies = try pageShieldReadPath(allocator, "zone/1", .cookies, .{
        .name = "session",
        .secure = "true",
        .http_only = "true",
        .same_site = "lax",
        .type_filter = "first_party",
        .path_filter = "/",
        .domain = "example.com",
    });
    defer allocator.free(cookies);
    try std.testing.expectEqualStrings("/zones/zone%2F1/page_shield/cookies?name=session&secure=true&http_only=true&same_site=lax&type=first_party&path=%2F&domain=example.com", cookies);

    const settings_plan = try pageShieldMutationPlanJson(allocator, .update_settings, .{ .zone_id = "zone/1" });
    defer allocator.free(settings_plan);
    try std.testing.expect(std.mem.indexOf(u8, settings_plan, "\"group\":\"Page Shield\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, settings_plan, "\"operation_id\":\"page-shield-update-settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, settings_plan, "\"path\":\"/zones/zone%2F1/page_shield\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, settings_plan, "\"will_execute\":false") != null);

    const create_plan = try pageShieldMutationPlanJson(allocator, .create_policy, .{ .zone_id = "zone/1" });
    defer allocator.free(create_plan);
    try std.testing.expect(std.mem.indexOf(u8, create_plan, "\"operation_id\":\"page-shield-create-policy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create_plan, "\"request_body_schema\":\"#/components/schemas/page-shield_policy\"") != null);

    const delete_plan = try pageShieldMutationPlanJson(allocator, .delete_policy, .{ .zone_id = "zone/1", .policy_id = "policy/1" });
    defer allocator.free(delete_plan);
    try std.testing.expect(std.mem.indexOf(u8, delete_plan, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_plan, "\"path\":\"/zones/zone%2F1/page_shield/policies/policy%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_plan, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflarePageShieldResourceId, pageShieldReadPath(allocator, "zone/1", .policy, .{}));
    try std.testing.expectError(error.MissingCloudflarePageShieldPolicyId, pageShieldMutationPlanJson(allocator, .update_policy, .{ .zone_id = "zone/1" }));
}

test "custom page endpoints map to official operation metadata" {
    try std.testing.expectEqual(CustomPageScope.account, CustomPageScope.parse("accounts").?);
    try std.testing.expectEqual(CustomPageScope.zone, CustomPageScope.parse("zone").?);
    try std.testing.expectEqual(CustomPageResource.pages, CustomPageResource.parse("custom-pages").?);
    try std.testing.expectEqual(CustomPageResource.assets, CustomPageResource.parse("asset").?);
    try std.testing.expectEqual(CustomPageReadEndpoint.details, CustomPageReadEndpoint.parse("show").?);
    try std.testing.expectEqualStrings("custom-pages-for-an-account-list-custom-pages", CustomPageReadEndpoint.list.operationId(.account, .pages));
    try std.testing.expectEqualStrings("custom-assets-for-a-zone-get-a-custom-asset", CustomPageReadEndpoint.details.operationId(.zone, .assets));
    try std.testing.expectEqualStrings("zone-custom-assets", CustomPageReadEndpoint.list.label(.zone, .assets));

    try std.testing.expectEqual(CustomPageMutationEndpoint.create_preview_token, CustomPageMutationEndpoint.parse("preview-token").?);
    try std.testing.expectEqual(CustomPageMutationEndpoint.delete_asset, CustomPageMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("custom-pages-for-a-zone-create-preview-token", CustomPageMutationEndpoint.create_preview_token.operationId(.zone));
    try std.testing.expectEqualStrings("custom-assets-for-an-account-update-a-custom-asset", CustomPageMutationEndpoint.update_asset.operationId(.account));
    try std.testing.expectEqualStrings("#/components/schemas/custom-pages_preview_request", CustomPageMutationEndpoint.create_preview_token.requestBodySchemaRef().?);
    try std.testing.expectEqual(@as(?[]const u8, null), CustomPageMutationEndpoint.delete_asset.requestBodySchemaRef());

    try std.testing.expectEqual(AccessCustomPageReadEndpoint.details, AccessCustomPageReadEndpoint.parse("page").?);
    try std.testing.expectEqualStrings("access-custom-pages-get-a-custom-page", AccessCustomPageReadEndpoint.details.operationId());
    try std.testing.expectEqual(AccessCustomPageMutationEndpoint.delete_page, AccessCustomPageMutationEndpoint.parse("delete").?);
    try std.testing.expectEqualStrings("#/components/schemas/access_custom_page", AccessCustomPageMutationEndpoint.update.requestBodySchemaRef().?);
}

test "builds custom page and Access custom page paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const account_pages = try customPageReadUrl(allocator, base_url, .account, "acct/1", .pages, .list, .{});
    defer allocator.free(account_pages);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/custom_pages", account_pages);

    const zone_asset = try customPageReadPath(allocator, .zone, "zone/1", .assets, .details, .{ .resource_id = "logo.svg" });
    defer allocator.free(zone_asset);
    try std.testing.expectEqualStrings("/zones/zone%2F1/custom_pages/assets/logo.svg", zone_asset);

    const preview = try customPageMutationPlanJson(allocator, .create_preview_token, .{ .scope = .zone, .scope_id = "zone/1" });
    defer allocator.free(preview);
    try std.testing.expect(std.mem.indexOf(u8, preview, "\"operation_id\":\"custom-pages-for-a-zone-create-preview-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview, "\"path\":\"/zones/zone%2F1/custom_pages/preview_tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview, "\"will_execute\":false") != null);

    const update_asset = try customPageMutationPlanJson(allocator, .update_asset, .{ .scope = .account, .scope_id = "acct/1", .resource_id = "asset/1" });
    defer allocator.free(update_asset);
    try std.testing.expect(std.mem.indexOf(u8, update_asset, "\"operation_id\":\"custom-assets-for-an-account-update-a-custom-asset\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_asset, "\"path\":\"/accounts/acct%2F1/custom_pages/assets/asset%2F1\"") != null);

    const access_list = try accessCustomPageReadUrl(allocator, base_url, "acct/1", .list, null);
    defer allocator.free(access_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/access/custom_pages", access_list);

    const access_delete = try accessCustomPageMutationPlanJson(allocator, .delete_page, .{ .account_id = "acct/1", .page_id = "page/1" });
    defer allocator.free(access_delete);
    try std.testing.expect(std.mem.indexOf(u8, access_delete, "\"operation_id\":\"access-custom-pages-delete-a-custom-page\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, access_delete, "\"path\":\"/accounts/acct%2F1/access/custom_pages/page%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, access_delete, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflareCustomPageResourceId, customPageReadPath(allocator, .zone, "zone/1", .pages, .details, .{}));
    try std.testing.expectError(error.MissingCloudflareCustomPageResourceId, customPageMutationPlanJson(allocator, .update_page, .{ .scope = .account, .scope_id = "acct/1" }));
    try std.testing.expectError(error.MissingCloudflareAccessCustomPageId, accessCustomPageReadPath(allocator, "acct/1", .details, null));
    try std.testing.expectError(error.MissingCloudflareAccessCustomPageId, accessCustomPageMutationPlanJson(allocator, .update, .{ .account_id = "acct/1" }));
}

test "access endpoints map to official operation metadata" {
    try std.testing.expectEqual(AccessScope.account, AccessScope.parse("accounts").?);
    try std.testing.expectEqual(AccessScope.zone, AccessScope.parse("zone").?);
    try std.testing.expectEqual(AccessReadEndpoint.applications_list, AccessReadEndpoint.parse("apps").?);
    try std.testing.expectEqual(AccessReadEndpoint.application_policy_details, AccessReadEndpoint.parse("app-policy").?);
    try std.testing.expectEqual(AccessReadEndpoint.identity_provider_scim_users, AccessReadEndpoint.parse("scim-users").?);
    try std.testing.expectEqual(AccessReadEndpoint.authenticator_device_aaguids, AccessReadEndpoint.parse("aaguids").?);
    try std.testing.expectEqual(AccessReadEndpoint.idp_federation_grant_details, AccessReadEndpoint.parse("federation-grant").?);
    try std.testing.expectEqual(AccessReadEndpoint.saml_certificate_pem, AccessReadEndpoint.parse("saml-pem").?);
    try std.testing.expectEqual(AccessReadEndpoint.mtls_settings, AccessReadEndpoint.parse("certificate-settings").?);
    try std.testing.expectEqualStrings("access-applications-list-access-applications", AccessReadEndpoint.applications_list.operationId(.account));
    try std.testing.expectEqualStrings("access-authenticator-device-aaguids-list", AccessReadEndpoint.authenticator_device_aaguids.operationId(.account));
    try std.testing.expectEqualStrings("access-mtls-authentication-list-mtls-certificates", AccessReadEndpoint.mtls_certificates_list.operationId(.account));
    try std.testing.expectEqualStrings("zone-level-access-service-tokens-get-a-service-token", AccessReadEndpoint.service_token_details.operationId(.zone));
    try std.testing.expectEqualStrings("Zone-Level Access mTLS authentication", AccessReadEndpoint.mtls_settings.group(.zone));
    try std.testing.expect(AccessReadEndpoint.identity_provider_scim_users.supports(.account));
    try std.testing.expect(!AccessReadEndpoint.identity_provider_scim_users.supports(.zone));
    try std.testing.expect(AccessReadEndpoint.mtls_settings.supports(.account));
    try std.testing.expect(AccessReadEndpoint.ca_details.requiresAppId());

    try std.testing.expectEqual(AccessMutationEndpoint.create_application, AccessMutationEndpoint.parse("create-app").?);
    try std.testing.expectEqual(AccessMutationEndpoint.make_policy_reusable, AccessMutationEndpoint.parse("convert-reusable").?);
    try std.testing.expectEqual(AccessMutationEndpoint.create_idp_federation_grant, AccessMutationEndpoint.parse("create-federation-grant").?);
    try std.testing.expectEqual(AccessMutationEndpoint.rotate_saml_certificate, AccessMutationEndpoint.parse("rotate-saml-cert").?);
    try std.testing.expectEqual(AccessMutationEndpoint.create_mtls_certificate, AccessMutationEndpoint.parse("create-certificate").?);
    try std.testing.expectEqualStrings("zone-level-access-applications-add-a-bookmark-application", AccessMutationEndpoint.create_application.operationId(.zone));
    try std.testing.expectEqualStrings("access-service-tokens-rotate-a-service-token", AccessMutationEndpoint.rotate_service_token.operationId(.account));
    try std.testing.expectEqualStrings("access-idp-federation-grants-create", AccessMutationEndpoint.create_idp_federation_grant.operationId(.account));
    try std.testing.expectEqualStrings("access-mtls-authentication-add-an-mtls-certificate", AccessMutationEndpoint.create_mtls_certificate.operationId(.account));
    try std.testing.expectEqualStrings("DELETE", AccessMutationEndpoint.delete_tag.method());
    try std.testing.expectEqual(@as(?[]const u8, null), AccessMutationEndpoint.rotate_keys.requestBodySchemaRef());
    try std.testing.expect(AccessMutationEndpoint.rotate_service_token.supports(.account));
    try std.testing.expect(!AccessMutationEndpoint.rotate_service_token.supports(.zone));
    try std.testing.expect(AccessMutationEndpoint.create_mtls_certificate.supports(.account));
    try std.testing.expect(AccessMutationEndpoint.update_group.requiresResourceId());
    try std.testing.expect(AccessMutationEndpoint.rotate_saml_certificate.requiresResourceId());
}

test "builds Access account and zone paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const apps = try accessReadUrl(allocator, base_url, .account, "acct/1", .applications_list, .{});
    defer allocator.free(apps);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/access/apps", apps);

    const policy = try accessReadPath(allocator, .account, "acct/1", .application_policy_details, .{ .app_id = "app/1", .policy_id = "policy/1" });
    defer allocator.free(policy);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/access/apps/app%2F1/policies/policy%2F1", policy);

    const scim = try accessReadPath(allocator, .account, "acct 1", .identity_provider_scim_groups, .{ .identity_provider_id = "idp 1" });
    defer allocator.free(scim);
    try std.testing.expectEqualStrings("/accounts/acct%201/access/identity_providers/idp%201/scim/groups", scim);

    const federation_grant = try accessReadPath(allocator, .account, "acct/1", .idp_federation_grant_details, .{ .resource_id = "grant/1" });
    defer allocator.free(federation_grant);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/access/idp_federation_grants/grant%2F1", federation_grant);

    const saml_pem = try accessReadPath(allocator, .account, "acct/1", .saml_certificate_pem, .{ .resource_id = "cert/1" });
    defer allocator.free(saml_pem);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/access/saml_certificates/cert%2F1/pem", saml_pem);

    const ca = try accessReadPath(allocator, .zone, "zone/1", .ca_details, .{ .app_id = "app/1" });
    defer allocator.free(ca);
    try std.testing.expectEqualStrings("/zones/zone%2F1/access/apps/app%2F1/ca", ca);

    const update_policy = try accessMutationPlanJson(allocator, .update_application_policy, .{ .scope = .account, .scope_id = "acct/1", .app_id = "app/1", .policy_id = "policy/1" });
    defer allocator.free(update_policy);
    try std.testing.expect(std.mem.indexOf(u8, update_policy, "\"operation_id\":\"access-policies-update-an-access-policy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_policy, "\"path\":\"/accounts/acct%2F1/access/apps/app%2F1/policies/policy%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_policy, "\"will_execute\":false") != null);

    const zone_mtls = try accessMutationPlanJson(allocator, .create_mtls_certificate, .{ .scope = .zone, .scope_id = "zone/1" });
    defer allocator.free(zone_mtls);
    try std.testing.expect(std.mem.indexOf(u8, zone_mtls, "\"operation_id\":\"zone-level-access-mtls-authentication-add-an-mtls-certificate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_mtls, "\"path\":\"/zones/zone%2F1/access/certificates\"") != null);

    const account_mtls = try accessMutationPlanJson(allocator, .create_mtls_certificate, .{ .scope = .account, .scope_id = "acct/1" });
    defer allocator.free(account_mtls);
    try std.testing.expect(std.mem.indexOf(u8, account_mtls, "\"operation_id\":\"access-mtls-authentication-add-an-mtls-certificate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_mtls, "\"path\":\"/accounts/acct%2F1/access/certificates\"") != null);

    const rotate_saml = try accessMutationPlanJson(allocator, .rotate_saml_certificate, .{ .scope = .account, .scope_id = "acct/1", .resource_id = "cert/1" });
    defer allocator.free(rotate_saml);
    try std.testing.expect(std.mem.indexOf(u8, rotate_saml, "\"operation_id\":\"access-saml-certificates-rotate-certificate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rotate_saml, "\"path\":\"/accounts/acct%2F1/access/saml_certificates/cert%2F1/rotate\"") != null);

    const account_ca = try accessMutationPlanJson(allocator, .create_ca, .{ .scope = .account, .scope_id = "acct/1", .app_id = "app/1" });
    defer allocator.free(account_ca);
    try std.testing.expect(std.mem.indexOf(u8, account_ca, "\"operation_id\":\"access-short-lived-certificate-c-as-create-a-short-lived-certificate-ca\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_ca, "\"path\":\"/accounts/acct%2F1/access/apps/app%2F1/ca\"") != null);

    const delete_tag = try accessMutationPlanJson(allocator, .delete_tag, .{ .scope = .account, .scope_id = "acct/1", .tag_name = "prod tag" });
    defer allocator.free(delete_tag);
    try std.testing.expect(std.mem.indexOf(u8, delete_tag, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_tag, "\"path\":\"/accounts/acct%2F1/access/tags/prod%20tag\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_tag, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.UnsupportedCloudflareAccessEndpoint, accessReadPath(allocator, .zone, "zone/1", .keys, .{}));
    try std.testing.expectError(error.MissingCloudflareAccessApplicationId, accessReadPath(allocator, .account, "acct/1", .application_details, .{}));
    try std.testing.expectError(error.MissingCloudflareAccessPolicyId, accessMutationPlanJson(allocator, .update_application_policy, .{ .scope = .account, .scope_id = "acct/1", .app_id = "app/1" }));
    try std.testing.expectError(error.UnsupportedCloudflareAccessMutation, accessMutationPlanJson(allocator, .rotate_service_token, .{ .scope = .zone, .scope_id = "zone/1", .service_token_id = "token/1" }));
}

test "cloudflare resource tagging endpoints map to official operation metadata" {
    try std.testing.expectEqual(ResourceTaggingAccountReadEndpoint.tags, ResourceTaggingAccountReadEndpoint.parse("tags").?);
    try std.testing.expectEqual(ResourceTaggingAccountReadEndpoint.keys, ResourceTaggingAccountReadEndpoint.parse("tag-keys").?);
    try std.testing.expectEqual(ResourceTaggingAccountReadEndpoint.resources, ResourceTaggingAccountReadEndpoint.parse("tagged-resources").?);
    try std.testing.expectEqual(ResourceTaggingAccountReadEndpoint.values, ResourceTaggingAccountReadEndpoint.parse("tag-values").?);
    try std.testing.expectEqualStrings("Resource Tagging", ResourceTaggingAccountReadEndpoint.tags.group());
    try std.testing.expectEqualStrings("tags-get", ResourceTaggingAccountReadEndpoint.tags.operationId());
    try std.testing.expectEqualStrings("tags-list-keys", ResourceTaggingAccountReadEndpoint.keys.operationId());
    try std.testing.expectEqualStrings("tags-list", ResourceTaggingAccountReadEndpoint.resources.operationId());
    try std.testing.expectEqualStrings("tags-list-values", ResourceTaggingAccountReadEndpoint.values.operationId());
    try std.testing.expect(ResourceTaggingAccountReadEndpoint.values.requiresTagKey());
    try std.testing.expect(!ResourceTaggingAccountReadEndpoint.keys.requiresTagKey());

    try std.testing.expectEqual(ResourceTaggingMutationResource.account, ResourceTaggingMutationResource.parse("account").?);
    try std.testing.expectEqual(ResourceTaggingMutationResource.zone, ResourceTaggingMutationResource.parse("zone").?);
    try std.testing.expectEqual(ResourceTaggingMutationEndpoint.set, ResourceTaggingMutationEndpoint.parse("put").?);
    try std.testing.expectEqual(ResourceTaggingMutationEndpoint.delete_resource, ResourceTaggingMutationEndpoint.parse("remove").?);
    try std.testing.expectEqualStrings("PUT", ResourceTaggingMutationEndpoint.set.method());
    try std.testing.expectEqualStrings("DELETE", ResourceTaggingMutationEndpoint.delete_resource.method());
    try std.testing.expectEqualStrings("tags-set", ResourceTaggingMutationEndpoint.set.operationId(.account));
    try std.testing.expectEqualStrings("tags-zone-delete", ResourceTaggingMutationEndpoint.delete_resource.operationId(.zone));
    try std.testing.expectEqualStrings("#/components/schemas/resource-tagging_set_tags_request_account_level", ResourceTaggingMutationEndpoint.set.requestBodySchemaRef(.account));
    try std.testing.expectEqualStrings("#/components/schemas/resource-tagging_delete_tags_request_zone_level", ResourceTaggingMutationEndpoint.delete_resource.requestBodySchemaRef(.zone));
}

test "builds Cloudflare resource tagging paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const account_tags = try resourceTaggingAccountReadUrl(allocator, base_url, "acct/1", .tags, .{
        .resource_id = "worker/1",
        .resource_type = "worker",
    });
    defer allocator.free(account_tags);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/tags?resource_id=worker%2F1&resource_type=worker", account_tags);

    const account_resources = try resourceTaggingAccountReadPath(allocator, "acct/1", .resources, .{ .type_filter = "zone" });
    defer allocator.free(account_resources);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/tags/resources?type=zone", account_resources);

    const account_values = try resourceTaggingAccountReadPath(allocator, "acct/1", .values, .{ .tag_key = "team/name" });
    defer allocator.free(account_values);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/tags/values/team%2Fname", account_values);

    const zone_tags = try resourceTaggingZoneReadPath(allocator, "zone/1", .{
        .resource_id = "zone/1",
        .resource_type = "zone",
        .access_application_id = "app 1",
    });
    defer allocator.free(zone_tags);
    try std.testing.expectEqualStrings("/zones/zone%2F1/tags?resource_id=zone%2F1&resource_type=zone&access_application_id=app%201", zone_tags);

    const account_set = try resourceTaggingMutationPlanJson(allocator, .set, .{ .resource = .account, .account_id = "acct/1" });
    defer allocator.free(account_set);
    try std.testing.expect(std.mem.indexOf(u8, account_set, "\"operation_id\":\"tags-set\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_set, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_set, "\"path\":\"/accounts/acct%2F1/tags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_set, "\"request_body_schema\":\"#/components/schemas/resource-tagging_set_tags_request_account_level\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, account_set, "\"will_execute\":false") != null);

    const zone_delete = try resourceTaggingMutationPlanJson(allocator, .delete_resource, .{ .resource = .zone, .zone_id = "zone/1" });
    defer allocator.free(zone_delete);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"operation_id\":\"tags-zone-delete\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"path\":\"/zones/zone%2F1/tags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zone_delete, "\"request_body_schema\":\"#/components/schemas/resource-tagging_delete_tags_request_zone_level\"") != null);

    try std.testing.expectError(error.MissingCloudflareTagKey, resourceTaggingAccountReadPath(allocator, "acct/1", .values, .{}));
    try std.testing.expectError(error.MissingCloudflareAccountId, resourceTaggingMutationPlanJson(allocator, .set, .{ .resource = .account }));
    try std.testing.expectError(error.MissingCloudflareZoneId, resourceTaggingMutationPlanJson(allocator, .delete_resource, .{ .resource = .zone }));
}

test "cloudflare dns record endpoints map to official operation metadata" {
    try std.testing.expectEqual(DnsRecordReadEndpoint.details, DnsRecordReadEndpoint.parse("show").?);
    try std.testing.expectEqual(DnsRecordReadEndpoint.export_records, DnsRecordReadEndpoint.parse("export-records").?);
    try std.testing.expectEqualStrings("dns-records-for-a-zone-dns-record-details", DnsRecordReadEndpoint.details.operationId());
    try std.testing.expect(DnsRecordReadEndpoint.details.requiresRecordId());
    try std.testing.expect(!DnsRecordReadEndpoint.usage.requiresRecordId());

    try std.testing.expectEqual(DnsRecordMutationEndpoint.create, DnsRecordMutationEndpoint.parse("create-record").?);
    try std.testing.expectEqual(DnsRecordMutationEndpoint.batch, DnsRecordMutationEndpoint.parse("batch").?);
    try std.testing.expectEqual(DnsRecordMutationEndpoint.apply_scan_results, DnsRecordMutationEndpoint.parse("apply-scan").?);
    try std.testing.expectEqual(DnsRecordMutationEndpoint.delete_record, DnsRecordMutationEndpoint.parse("delete").?);
    try std.testing.expectEqualStrings("DNS Records for a Zone", DnsRecordMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", DnsRecordMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("DELETE", DnsRecordMutationEndpoint.delete_record.method());
    try std.testing.expectEqualStrings("PATCH", DnsRecordMutationEndpoint.patch_record.method());
    try std.testing.expectEqualStrings("PUT", DnsRecordMutationEndpoint.update_record.method());
    try std.testing.expectEqualStrings("dns-records-for-a-zone-create-dns-record", DnsRecordMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("dns-records-for-a-zone-update-dns-record", DnsRecordMutationEndpoint.update_record.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/dns-records_dns-record-post", DnsRecordMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/dns-records_dns-record-patch", DnsRecordMutationEndpoint.patch_record.requestBodySchemaRef().?);
    try std.testing.expect(DnsRecordMutationEndpoint.delete_record.requestBodySchemaRef() == null);
    try std.testing.expect(DnsRecordMutationEndpoint.delete_record.requiresRecordId());
    try std.testing.expect(!DnsRecordMutationEndpoint.trigger_scan.requiresRecordId());
}

test "cloudflare zone mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(ZoneMutationEndpoint.create, ZoneMutationEndpoint.parse("create").?);
    try std.testing.expectEqual(ZoneMutationEndpoint.delete_zone, ZoneMutationEndpoint.parse("remove").?);
    try std.testing.expectEqual(ZoneMutationEndpoint.edit, ZoneMutationEndpoint.parse("patch").?);
    try std.testing.expectEqual(ZoneMutationEndpoint.purge_cache, ZoneMutationEndpoint.parse("purge").?);
    try std.testing.expectEqual(ZoneMutationEndpoint.purge_environment_cache, ZoneMutationEndpoint.parse("purge-environment").?);
    try std.testing.expectEqual(ZoneMutationEndpoint.activation_check, ZoneMutationEndpoint.parse("check-activation").?);
    try std.testing.expect(ZoneMutationEndpoint.parse("show") == null);

    try std.testing.expectEqualStrings("Zone", ZoneMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", ZoneMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("DELETE", ZoneMutationEndpoint.delete_zone.method());
    try std.testing.expectEqualStrings("PATCH", ZoneMutationEndpoint.edit.method());
    try std.testing.expectEqualStrings("PUT", ZoneMutationEndpoint.activation_check.method());
    try std.testing.expectEqualStrings("zones-post", ZoneMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("zones-0-delete", ZoneMutationEndpoint.delete_zone.operationId());
    try std.testing.expectEqualStrings("zones-0-patch", ZoneMutationEndpoint.edit.operationId());
    try std.testing.expectEqualStrings("zone-purge", ZoneMutationEndpoint.purge_cache.operationId());
    try std.testing.expectEqualStrings("zone-environment-purge", ZoneMutationEndpoint.purge_environment_cache.operationId());
    try std.testing.expectEqualStrings("put-zones-zone_id-activation_check", ZoneMutationEndpoint.activation_check.operationId());
    try std.testing.expectEqualStrings("inline:{name:string,account:{id:string},type?:string}", ZoneMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("inline:{paused?:bool,plan?:{id:string},type?:full|partial|secondary|internal,vanity_name_servers?:[]string}", ZoneMutationEndpoint.edit.requestBodySchemaRef().?);
    try std.testing.expect(ZoneMutationEndpoint.delete_zone.requestBodySchemaRef() == null);
    try std.testing.expect(!ZoneMutationEndpoint.create.requiresZoneId());
    try std.testing.expect(ZoneMutationEndpoint.edit.requiresZoneId());
    try std.testing.expect(ZoneMutationEndpoint.purge_environment_cache.requiresEnvironmentId());
}

test "cloudflare zone lifecycle endpoints map to official operation metadata" {
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.available_plans, ZoneLifecycleReadEndpoint.parse("plans").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.available_plan, ZoneLifecycleReadEndpoint.parse("plan").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.available_rate_plans, ZoneLifecycleReadEndpoint.parse("rate-plans").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.cache_reserve, ZoneLifecycleReadEndpoint.parse("cache-reserve").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.regional_tiered_cache, ZoneLifecycleReadEndpoint.parse("regional-tiered-cache").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.variants, ZoneLifecycleReadEndpoint.parse("cache-variants").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.environments, ZoneLifecycleReadEndpoint.parse("envs").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.hold, ZoneLifecycleReadEndpoint.parse("zone-hold").?);
    try std.testing.expectEqual(ZoneLifecycleReadEndpoint.subscription, ZoneLifecycleReadEndpoint.parse("subscription").?);
    try std.testing.expectEqualStrings("Zone Rate Plan", ZoneLifecycleReadEndpoint.available_plans.group());
    try std.testing.expectEqualStrings("Zone Cache Settings", ZoneLifecycleReadEndpoint.cache_reserve.group());
    try std.testing.expectEqualStrings("zone-rate-plan-list-available-plans", ZoneLifecycleReadEndpoint.available_plans.operationId());
    try std.testing.expectEqualStrings("zone-rate-plan-available-plan-details", ZoneLifecycleReadEndpoint.available_plan.operationId());
    try std.testing.expectEqualStrings("zone-cache-settings-get-cache-reserve-setting", ZoneLifecycleReadEndpoint.cache_reserve.operationId());
    try std.testing.expectEqualStrings("zonesEnvironmentsList", ZoneLifecycleReadEndpoint.environments.operationId());
    try std.testing.expectEqualStrings("zones-0-hold-get", ZoneLifecycleReadEndpoint.hold.operationId());
    try std.testing.expectEqualStrings("zone-subscription-zone-subscription-details", ZoneLifecycleReadEndpoint.subscription.operationId());
    try std.testing.expect(ZoneLifecycleReadEndpoint.available_plan.requiresPlanId());
    try std.testing.expect(!ZoneLifecycleReadEndpoint.available_plans.requiresPlanId());

    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.change_cache_reserve, ZoneLifecycleMutationEndpoint.parse("change-cache-reserve").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.start_cache_reserve_clear, ZoneLifecycleMutationEndpoint.parse("start-cache-reserve-clear").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.change_regional_tiered_cache, ZoneLifecycleMutationEndpoint.parse("change-regional-tiered-cache").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.delete_variants, ZoneLifecycleMutationEndpoint.parse("delete-variants").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.create_environments, ZoneLifecycleMutationEndpoint.parse("create-environments").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.rollback_environment, ZoneLifecycleMutationEndpoint.parse("rollback-environment").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.create_hold, ZoneLifecycleMutationEndpoint.parse("create-hold").?);
    try std.testing.expectEqual(ZoneLifecycleMutationEndpoint.update_subscription, ZoneLifecycleMutationEndpoint.parse("update-subscription").?);
    try std.testing.expectEqualStrings("PATCH", ZoneLifecycleMutationEndpoint.change_cache_reserve.method());
    try std.testing.expectEqualStrings("POST", ZoneLifecycleMutationEndpoint.start_cache_reserve_clear.method());
    try std.testing.expectEqualStrings("DELETE", ZoneLifecycleMutationEndpoint.delete_variants.method());
    try std.testing.expectEqualStrings("PUT", ZoneLifecycleMutationEndpoint.update_subscription.method());
    try std.testing.expectEqualStrings("zone-cache-settings-change-cache-reserve-setting", ZoneLifecycleMutationEndpoint.change_cache_reserve.operationId());
    try std.testing.expectEqualStrings("zonesEnvironmentsRollback", ZoneLifecycleMutationEndpoint.rollback_environment.operationId());
    try std.testing.expectEqualStrings("zones-0-hold-patch", ZoneLifecycleMutationEndpoint.update_hold.operationId());
    try std.testing.expectEqualStrings("zone-subscription-update-zone-subscription", ZoneLifecycleMutationEndpoint.update_subscription.operationId());
    try std.testing.expectEqualStrings("inline:{value:#/components/schemas/cache-rules_cache_reserve_value}", ZoneLifecycleMutationEndpoint.change_cache_reserve.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/kamino_environments_request", ZoneLifecycleMutationEndpoint.create_environments.requestBodySchemaRef().?);
    try std.testing.expect(ZoneLifecycleMutationEndpoint.delete_hold.requestBodySchemaRef() == null);
    try std.testing.expect(ZoneLifecycleMutationEndpoint.rollback_environment.requiresEnvironmentId());
    try std.testing.expect(!ZoneLifecycleMutationEndpoint.create_environments.requiresEnvironmentId());
}

test "cloudflare dnssec mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(DnssecMutationEndpoint.delete_records, DnssecMutationEndpoint.parse("delete").?);
    try std.testing.expectEqual(DnssecMutationEndpoint.edit_status, DnssecMutationEndpoint.parse("edit-status").?);
    try std.testing.expectEqualStrings("DNSSEC", DnssecMutationEndpoint.delete_records.group());
    try std.testing.expectEqualStrings("DELETE", DnssecMutationEndpoint.delete_records.method());
    try std.testing.expectEqualStrings("PATCH", DnssecMutationEndpoint.edit_status.method());
    try std.testing.expectEqualStrings("dnssec-delete-dnssec-records", DnssecMutationEndpoint.delete_records.operationId());
    try std.testing.expectEqualStrings("dnssec-edit-dnssec-status", DnssecMutationEndpoint.edit_status.operationId());
    try std.testing.expect(DnssecMutationEndpoint.edit_status.requestBodySchemaRef() == null);
}

test "builds Cloudflare DNSSEC dry-run plans" {
    const allocator = std.testing.allocator;
    const edit = try dnssecMutationPlanJson(allocator, .edit_status, .{ .zone_id = "zone/1" });
    defer allocator.free(edit);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"group\":\"DNSSEC\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"operation_id\":\"dnssec-edit-dnssec-status\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"path\":\"/zones/zone%2F1/dnssec\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"will_execute\":false") != null);

    const delete_records = try dnssecMutationPlanJson(allocator, .delete_records, .{ .zone_id = "zone/1" });
    defer allocator.free(delete_records);
    try std.testing.expect(std.mem.indexOf(u8, delete_records, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_records, "\"request_body_schema\":null") != null);
}

test "builds Cloudflare zone dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try zoneMutationPlanJson(allocator, .create, .{});
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Zone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"zones-post\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/zones\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"inline:{name:string,account:{id:string},type?:string}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const edit = try zoneMutationPlanJson(allocator, .edit, .{ .zone_id = "zone/1" });
    defer allocator.free(edit);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"operation_id\":\"zones-0-patch\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"path\":\"/zones/zone%2F1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, edit, "\"request_body_schema\":\"inline:{paused?:bool,plan?:{id:string},type?:full|partial|secondary|internal,vanity_name_servers?:[]string}\"") != null);

    const environment_purge = try zoneMutationPlanJson(allocator, .purge_environment_cache, .{ .zone_id = "zone/1", .environment_id = "env/1" });
    defer allocator.free(environment_purge);
    try std.testing.expect(std.mem.indexOf(u8, environment_purge, "\"operation_id\":\"zone-environment-purge\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, environment_purge, "\"path\":\"/zones/zone%2F1/environments/env%2F1/purge_cache\"") != null);

    const activation_check = try zoneMutationPlanJson(allocator, .activation_check, .{ .zone_id = "zone/1" });
    defer allocator.free(activation_check);
    try std.testing.expect(std.mem.indexOf(u8, activation_check, "\"operation_id\":\"put-zones-zone_id-activation_check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, activation_check, "\"path\":\"/zones/zone%2F1/activation_check\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, activation_check, "\"request_body_schema\":null") != null);

    try std.testing.expectError(error.MissingCloudflareZoneEnvironmentId, zoneMutationPlanJson(allocator, .purge_environment_cache, .{ .zone_id = "zone/1" }));
}

test "builds Cloudflare zone lifecycle paths and dry-run plans" {
    const allocator = std.testing.allocator;

    const read_path = try zoneLifecycleReadPath(allocator, "zone/1", .available_plan, "plan/1");
    defer allocator.free(read_path);
    try std.testing.expectEqualStrings("/zones/zone%2F1/available_plans/plan%2F1", read_path);
    try std.testing.expectError(error.MissingCloudflareZonePlanId, zoneLifecycleReadPath(allocator, "zone/1", .available_plan, null));

    const cache = try zoneLifecycleMutationPlanJson(allocator, .change_cache_reserve, .{ .zone_id = "zone/1" });
    defer allocator.free(cache);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"group\":\"Zone Cache Settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"operation_id\":\"zone-cache-settings-change-cache-reserve-setting\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"path\":\"/zones/zone%2F1/cache/cache_reserve\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"request_body_schema\":\"inline:{value:#/components/schemas/cache-rules_cache_reserve_value}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, cache, "\"will_execute\":false") != null);

    const rollback = try zoneLifecycleMutationPlanJson(allocator, .rollback_environment, .{ .zone_id = "zone/1", .environment_id = "env/1" });
    defer allocator.free(rollback);
    try std.testing.expect(std.mem.indexOf(u8, rollback, "\"operation_id\":\"zonesEnvironmentsRollback\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rollback, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rollback, "\"path\":\"/zones/zone%2F1/environments/env%2F1/rollback\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rollback, "\"request_body_schema\":null") != null);

    const subscription = try zoneLifecycleMutationPlanJson(allocator, .update_subscription, .{ .zone_id = "zone/1" });
    defer allocator.free(subscription);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"operation_id\":\"zone-subscription-update-zone-subscription\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"path\":\"/zones/zone%2F1/subscription\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"request_body_schema\":\"#/components/schemas/bill-subs-api_subscription-v2\"") != null);

    try std.testing.expectError(error.MissingCloudflareZoneEnvironmentId, zoneLifecycleMutationPlanJson(allocator, .delete_environment, .{ .zone_id = "zone/1" }));
}

test "builds Cloudflare DNS record dry-run plans" {
    const allocator = std.testing.allocator;
    const create = try dnsRecordMutationPlanJson(allocator, .create, .{ .zone_id = "zone 1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"DNS Records for a Zone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"dns-records-for-a-zone-create-dns-record\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/zones/zone%201/dns_records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const delete_record = try dnsRecordMutationPlanJson(allocator, .delete_record, .{ .zone_id = "zone 1", .dns_record_id = "record/1" });
    defer allocator.free(delete_record);
    try std.testing.expect(std.mem.indexOf(u8, delete_record, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_record, "/zones/zone%201/dns_records/record%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_record, "\"request_body_schema\":null") != null);

    const scan = try dnsRecordMutationPlanJson(allocator, .apply_scan_results, .{ .zone_id = "zone 1" });
    defer allocator.free(scan);
    try std.testing.expect(std.mem.indexOf(u8, scan, "/zones/zone%201/dns_records/scan/review") != null);
    try std.testing.expect(std.mem.indexOf(u8, scan, "\"request_body_schema\":\"#/components/schemas/dns-records_dns-request-review-scan-object\"") != null);
}

test "builds official Cloudflare URLs used by the POC" {
    const allocator = std.testing.allocator;
    const accounts = try accountsUrl(allocator, base_url);
    defer allocator.free(accounts);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts", accounts);

    const account_detail = try accountEndpointUrl(allocator, base_url, "acct-1", .details);
    defer allocator.free(account_detail);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1", account_detail);

    const account_profile = try accountEndpointUrl(allocator, base_url, "acct-1", .profile);
    defer allocator.free(account_profile);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/profile", account_profile);

    const account_orgs = try accountEndpointUrl(allocator, base_url, "acct 1", .organizations);
    defer allocator.free(account_orgs);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/organizations", account_orgs);

    const account_members = try accountCollectionUrl(allocator, base_url, "acct 1", .members);
    defer allocator.free(account_members);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/members", account_members);

    const account_member = try accountResourceUrl(allocator, base_url, "acct 1", .members, "member 1");
    defer allocator.free(account_member);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/members/member%201", account_member);

    const account_roles = try accountCollectionUrl(allocator, base_url, "acct-1", .roles);
    defer allocator.free(account_roles);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/roles", account_roles);

    const account_role = try accountResourceUrl(allocator, base_url, "acct-1", .roles, "role-1");
    defer allocator.free(account_role);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/roles/role-1", account_role);

    const account_permission_groups = try accountPermissionGroupsUrl(allocator, base_url, "acct-1");
    defer allocator.free(account_permission_groups);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/iam/permission_groups", account_permission_groups);

    const account_permission_group = try accountPermissionGroupUrl(allocator, base_url, "acct 1", "group 1");
    defer allocator.free(account_permission_group);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/iam/permission_groups/group%201", account_permission_group);

    const account_resource_groups = try accountIamCollectionUrl(allocator, base_url, "acct 1", .resource_groups);
    defer allocator.free(account_resource_groups);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/iam/resource_groups", account_resource_groups);

    const account_resource_group = try accountIamResourceUrl(allocator, base_url, "acct 1", .resource_groups, "resource 1");
    defer allocator.free(account_resource_group);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/iam/resource_groups/resource%201", account_resource_group);

    const account_user_groups = try accountIamCollectionUrl(allocator, base_url, "acct-1", .user_groups);
    defer allocator.free(account_user_groups);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/iam/user_groups", account_user_groups);

    const account_user_group = try accountIamResourceUrl(allocator, base_url, "acct-1", .user_groups, "user-group-1");
    defer allocator.free(account_user_group);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/iam/user_groups/user-group-1", account_user_group);

    const account_user_group_members = try accountUserGroupMembersUrl(allocator, base_url, "acct 1", "group/1");
    defer allocator.free(account_user_group_members);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/iam/user_groups/group%2F1/members", account_user_group_members);

    const account_user_group_member = try accountUserGroupMemberUrl(allocator, base_url, "acct 1", "group/1", "member/1");
    defer allocator.free(account_user_group_member);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/iam/user_groups/group%2F1/members/member%2F1", account_user_group_member);

    const account_tokens = try accountTokenEndpointUrl(allocator, base_url, "acct 1", .list);
    defer allocator.free(account_tokens);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/tokens", account_tokens);

    const account_token = try accountTokenUrl(allocator, base_url, "acct 1", "token 1");
    defer allocator.free(account_token);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/tokens/token%201", account_token);

    const account_token_permissions = try accountTokenEndpointUrl(allocator, base_url, "acct-1", .permission_groups);
    defer allocator.free(account_token_permissions);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/tokens/permission_groups", account_token_permissions);

    const account_token_verify = try accountTokenEndpointUrl(allocator, base_url, "acct-1", .verify);
    defer allocator.free(account_token_verify);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/tokens/verify", account_token_verify);

    const account_dns_record_usage = try accountDnsRecordUsageUrl(allocator, base_url, "acct 1");
    defer allocator.free(account_dns_record_usage);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%201/dns_records/usage", account_dns_record_usage);

    const user = try identityEndpointUrl(allocator, base_url, .user);
    defer allocator.free(user);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user", user);

    const memberships = try identityEndpointUrl(allocator, base_url, .memberships);
    defer allocator.free(memberships);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/memberships", memberships);

    const membership = try membershipUrl(allocator, base_url, "membership 1");
    defer allocator.free(membership);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/memberships/membership%201", membership);

    const token_list = try userTokenEndpointUrl(allocator, base_url, .list);
    defer allocator.free(token_list);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user/tokens", token_list);

    const token_detail = try userTokenUrl(allocator, base_url, "token 1");
    defer allocator.free(token_detail);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user/tokens/token%201", token_detail);

    const token_verify = try userTokenEndpointUrl(allocator, base_url, .verify);
    defer allocator.free(token_verify);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user/tokens/verify", token_verify);

    const token_permissions = try userTokenEndpointUrl(allocator, base_url, .permission_groups);
    defer allocator.free(token_permissions);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/user/tokens/permission_groups", token_permissions);

    const account_dns_settings = try accountDnsSettingsUrl(allocator, base_url, "acct-1");
    defer allocator.free(account_dns_settings);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct-1/dns_settings", account_dns_settings);

    const zones = try zonesUrl(allocator, base_url, "plosca.ru");
    defer allocator.free(zones);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones?name=plosca.ru&per_page=50", zones);

    const zone_detail = try zoneUrl(allocator, base_url, "zone/id");
    defer allocator.free(zone_detail);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2Fid", zone_detail);

    const dns = try dnsRecordsUrl(allocator, base_url, "zone-id");
    defer allocator.free(dns);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/dns_records?per_page=5000", dns);

    const dns_detail = try dnsRecordReadUrl(allocator, base_url, "zone id", .details, "record/id");
    defer allocator.free(dns_detail);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%20id/dns_records/record%2Fid", dns_detail);

    const dns_export = try dnsRecordReadUrl(allocator, base_url, "zone-id", .export_records, null);
    defer allocator.free(dns_export);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/dns_records/export", dns_export);

    const dns_usage = try dnsRecordReadPath(allocator, "zone-id", .usage, null);
    defer allocator.free(dns_usage);
    try std.testing.expectEqualStrings("/zones/zone-id/dns_records/usage", dns_usage);

    const settings = try zoneEndpointUrl(allocator, base_url, "zone-id", .settings);
    defer allocator.free(settings);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/settings", settings);

    const dns_settings = try zoneEndpointUrl(allocator, base_url, "zone-id", .dns_settings);
    defer allocator.free(dns_settings);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/dns_settings", dns_settings);

    const dnssec_zsk = try zoneEndpointUrl(allocator, base_url, "zone-id", .dnssec_zsk);
    defer allocator.free(dnssec_zsk);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/dnssec/zsk", dnssec_zsk);

    const aegis = try zoneEndpointUrl(allocator, base_url, "zone-id", .settings_aegis);
    defer allocator.free(aegis);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/settings/aegis", aegis);

    const origin = try zoneEndpointPath(allocator, "zone-id", .settings_origin_max_http_version);
    defer allocator.free(origin);
    try std.testing.expectEqualStrings("/zones/zone-id/settings/origin_max_http_version", origin);

    const escaped_origin = try zoneEndpointPath(allocator, "zone/id", .settings_origin_max_http_version);
    defer allocator.free(escaped_origin);
    try std.testing.expectEqualStrings("/zones/zone%2Fid/settings/origin_max_http_version", escaped_origin);

    const ssl_auto = try zoneEndpointUrl(allocator, base_url, "zone-id", .settings_ssl_automatic_mode);
    defer allocator.free(ssl_auto);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone-id/settings/ssl_automatic_mode", ssl_auto);

    const setting = try zoneSettingUrl(allocator, base_url, "zone/id", "origin max");
    defer allocator.free(setting);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2Fid/settings/origin%20max", setting);

    const available_plan = try zoneLifecycleReadUrl(allocator, base_url, "zone/id", .available_plan, "plan/id");
    defer allocator.free(available_plan);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2Fid/available_plans/plan%2Fid", available_plan);

    const cache_reserve = try zoneLifecycleReadUrl(allocator, base_url, "zone id", .cache_reserve, null);
    defer allocator.free(cache_reserve);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%20id/cache/cache_reserve", cache_reserve);

    const secondary_acls = try secondaryDnsAccountCollectionUrl(allocator, base_url, "acct/1", .acl);
    defer allocator.free(secondary_acls);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/secondary_dns/acls", secondary_acls);

    const secondary_peer = try secondaryDnsAccountResourceUrl(allocator, base_url, "acct/1", .peer, "peer/1");
    defer allocator.free(secondary_peer);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct%2F1/secondary_dns/peers/peer%2F1", secondary_peer);

    const secondary_primary = try secondaryDnsZoneReadUrl(allocator, base_url, "zone/1", .primary_status);
    defer allocator.free(secondary_primary);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/zones/zone%2F1/secondary_dns/outgoing/status", secondary_primary);
}
