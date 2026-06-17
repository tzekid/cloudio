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
        const common = jsonHeaders();
        if (self.auth.token) |token| {
            if (token.len == 0) return error.MissingCloudflareAuth;
            const auth_header = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
            defer gpa.free(auth_header);
            const privileged = [_]std.http.Header{.{ .name = "Authorization", .value = auth_header }};
            return try net_http.get(gpa, io, url, &common, &privileged);
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
        return try net_http.get(gpa, io, url, &legacy, &.{});
    }

    pub fn getPublic(self: Client, io: Io, gpa: Allocator, url: []const u8) !net_http.Response {
        _ = self;
        const common = jsonHeaders();
        return try net_http.get(gpa, io, url, &common, &.{});
    }
};

fn jsonHeaders() [2]std.http.Header {
    return .{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    };
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
