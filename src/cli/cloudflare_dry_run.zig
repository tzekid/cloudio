const std = @import("std");
const app_cloudflare = @import("app_cloudflare");
const app_database = @import("app_database");
const cli_render = @import("cli_render");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = app_database.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    auth: app_cloudflare.Auth,
    domains: []const []const u8,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("dry-run target and operation required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "dns")) return try commandDryRunDns(ctx, args);
    if (std.mem.eql(u8, args[1], "dnssec")) return try commandDryRunDnssec(ctx, args);
    if (std.mem.eql(u8, args[1], "zone")) return try commandDryRunZone(ctx, args);
    if (std.mem.eql(u8, args[1], "zone-lifecycle")) return try commandDryRunZoneLifecycle(ctx, args);
    if (std.mem.eql(u8, args[1], "token")) return try commandDryRunToken(ctx, args);
    if (std.mem.eql(u8, args[1], "membership")) return try commandDryRunMembership(ctx, args);
    if (std.mem.eql(u8, args[1], "account")) return try commandDryRunAccount(ctx, args);
    if (std.mem.eql(u8, args[1], "account-token")) return try commandDryRunAccountToken(ctx, args);
    if (std.mem.eql(u8, args[1], "account-member") or std.mem.eql(u8, args[1], "member")) return try commandDryRunAccountMember(ctx, args);
    if (std.mem.eql(u8, args[1], "resource-group") or std.mem.eql(u8, args[1], "account-resource-group")) return try commandDryRunAccountIamGroup(ctx, args, .resource_groups);
    if (std.mem.eql(u8, args[1], "user-group") or std.mem.eql(u8, args[1], "account-user-group")) return try commandDryRunAccountIamGroup(ctx, args, .user_groups);
    if (std.mem.eql(u8, args[1], "account-user-group-member") or std.mem.eql(u8, args[1], "user-group-member")) return try commandDryRunAccountUserGroupMember(ctx, args);
    if (std.mem.eql(u8, args[1], "secondary-dns-account")) return try commandDryRunSecondaryDnsAccount(ctx, args);
    if (std.mem.eql(u8, args[1], "secondary-dns-zone")) return try commandDryRunSecondaryDnsZone(ctx, args);
    if (std.mem.eql(u8, args[1], "dns-firewall")) return try commandDryRunDnsFirewall(ctx, args);
    if (std.mem.eql(u8, args[1], "dns-settings")) return try commandDryRunDnsSettings(ctx, args);
    if (std.mem.eql(u8, args[1], "load-balancing") or std.mem.eql(u8, args[1], "lb")) return try commandDryRunLoadBalancing(ctx, args);
    if (std.mem.eql(u8, args[1], "health-checks") or std.mem.eql(u8, args[1], "health")) return try commandDryRunHealthChecks(ctx, args);
    if (std.mem.eql(u8, args[1], "resource-tags") or std.mem.eql(u8, args[1], "tags")) return try commandDryRunResourceTags(ctx, args);
    if (std.mem.eql(u8, args[1], "rulesets") or std.mem.eql(u8, args[1], "ruleset")) return try commandDryRunRulesets(ctx, args);
    if (std.mem.eql(u8, args[1], "cloudforce-one-rules") or std.mem.eql(u8, args[1], "cf1-rules")) return try commandDryRunCloudforceOneRules(ctx, args);
    if (std.mem.eql(u8, args[1], "ip-access") or std.mem.eql(u8, args[1], "access-rules")) return try commandDryRunIpAccessRules(ctx, args);
    if (app_cloudflare.ZoneLegacyRuleResource.parse(args[1])) |resource| return try commandDryRunZoneLegacyRules(ctx, args, resource);
    if (std.mem.eql(u8, args[1], "page-shield")) return try commandDryRunPageShield(ctx, args);
    if (std.mem.eql(u8, args[1], "custom-pages")) return try commandDryRunCustomPages(ctx, args);
    if (std.mem.eql(u8, args[1], "access-custom-pages")) return try commandDryRunAccessCustomPages(ctx, args);
    if (std.mem.eql(u8, args[1], "access")) return try commandDryRunAccess(ctx, args);
    std.debug.print("unknown cloudflare dry-run target: {s}\n", .{args[1]});
}

fn commandDryRunDns(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.DnsRecordMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown dns dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("zone id required for dry-run dns {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresRecordId() and args.len < 5) {
        std.debug.print("dns record id required for dry-run dns {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_cloudflare.DnsRecordMutationArgs = .{
        .zone_id = args[3],
        .dns_record_id = if (endpoint.requiresRecordId()) args[4] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planDnsRecordMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunDnssec(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.DnssecMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown dnssec dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("zone id required for dry-run dnssec {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planDnssecMutation(appContext(ctx), endpoint, .{ .zone_id = args[3] }));
}

fn commandDryRunZone(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.ZoneMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown zone dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresZoneId() and args.len < 4) {
        std.debug.print("zone id required for dry-run zone {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresEnvironmentId() and args.len < 5) {
        std.debug.print("environment id required for dry-run zone {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planZoneMutation(appContext(ctx), endpoint, .{
        .zone_id = if (endpoint.requiresZoneId()) args[3] else null,
        .environment_id = if (endpoint.requiresEnvironmentId()) args[4] else null,
    }));
}

fn commandDryRunZoneLifecycle(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.ZoneLifecycleMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown zone-lifecycle dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("zone id required for dry-run zone-lifecycle {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresEnvironmentId() and args.len < 5) {
        std.debug.print("environment id required for dry-run zone-lifecycle {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planZoneLifecycleMutation(appContext(ctx), endpoint, .{
        .zone_id = args[3],
        .environment_id = if (endpoint.requiresEnvironmentId()) args[4] else null,
    }));
}

fn commandDryRunToken(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.UserTokenMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown token dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresTokenId() and args.len < 4) {
        std.debug.print("token id required for dry-run token {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planUserTokenMutation(appContext(ctx), endpoint, .{
        .token_id = if (endpoint.requiresTokenId()) args[3] else null,
    }));
}

fn commandDryRunMembership(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.MembershipMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown membership dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("membership id required for dry-run membership {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planMembershipMutation(appContext(ctx), endpoint, .{ .membership_id = args[3] }));
}

fn commandDryRunAccount(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.AccountMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown account dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresAccountId() and args.len < 4) {
        std.debug.print("account id required for dry-run account {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccountMutation(appContext(ctx), endpoint, .{
        .account_id = if (endpoint.requiresAccountId()) args[3] else null,
    }));
}

fn commandDryRunAccountToken(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.AccountTokenMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown account token dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("account id required for dry-run account-token {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresTokenId() and args.len < 5) {
        std.debug.print("token id required for dry-run account-token {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccountTokenMutation(appContext(ctx), endpoint, .{
        .account_id = args[3],
        .token_id = if (endpoint.requiresTokenId()) args[4] else null,
    }));
}

fn commandDryRunAccountMember(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.AccountMemberMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown account member dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("account id required for dry-run account-member {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresMemberId() and args.len < 5) {
        std.debug.print("member id required for dry-run account-member {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccountMemberMutation(appContext(ctx), endpoint, .{
        .account_id = args[3],
        .member_id = if (endpoint.requiresMemberId()) args[4] else null,
    }));
}

fn commandDryRunAccountIamGroup(ctx: Context, args: []const []const u8, collection: app_cloudflare.AccountIamCollection) !void {
    const endpoint = app_cloudflare.AccountIamGroupMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown {s} dry-run operation: {s}\n", .{ collection.detailCommandName(), args[2] });
        return;
    };
    if (args.len < 4) {
        std.debug.print("account id required for dry-run {s} {s}\n", .{ collection.detailCommandName(), endpoint.commandName() });
        return;
    }
    if (endpoint.requiresResourceId() and args.len < 5) {
        std.debug.print("resource id required for dry-run {s} {s}\n", .{ collection.detailCommandName(), endpoint.commandName() });
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccountIamGroupMutation(appContext(ctx), endpoint, .{
        .collection = collection,
        .account_id = args[3],
        .resource_id = if (endpoint.requiresResourceId()) args[4] else null,
    }));
}

fn commandDryRunAccountUserGroupMember(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_cloudflare.AccountUserGroupMemberMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown account user-group member dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 5) {
        std.debug.print("account id and user group id required for dry-run account-user-group-member {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresMemberId() and args.len < 6) {
        std.debug.print("member id required for dry-run account-user-group-member {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccountUserGroupMemberMutation(appContext(ctx), endpoint, .{
        .account_id = args[3],
        .user_group_id = args[4],
        .member_id = if (endpoint.requiresMemberId()) args[5] else null,
    }));
}

fn commandDryRunSecondaryDnsAccount(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("resource, operation, and account id required for dry-run secondary-dns-account\n", .{});
        return;
    }
    const resource = app_cloudflare.SecondaryDnsAccountResource.parseDetailCommand(args[2]) orelse {
        std.debug.print("unknown secondary-dns-account resource: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.SecondaryDnsAccountMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown secondary-dns-account dry-run operation: {s}\n", .{args[3]});
        return;
    };
    if (endpoint.requiresResourceId() and args.len < 6) {
        std.debug.print("resource id required for dry-run secondary-dns-account {s} {s}\n", .{ resource.detailCommandName(), endpoint.commandName() });
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planSecondaryDnsAccountMutation(appContext(ctx), endpoint, .{
        .resource = resource,
        .account_id = args[4],
        .resource_id = if (endpoint.requiresResourceId()) args[5] else null,
    }));
}

fn commandDryRunSecondaryDnsZone(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("operation and zone id required for dry-run secondary-dns-zone\n", .{});
        return;
    }
    const endpoint = app_cloudflare.SecondaryDnsZoneMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown secondary-dns-zone dry-run operation: {s}\n", .{args[2]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planSecondaryDnsZoneMutation(appContext(ctx), endpoint, .{ .zone_id = args[3] }));
}

fn commandDryRunDnsFirewall(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("operation and account id required for dry-run dns-firewall\n", .{});
        return;
    }
    const endpoint = app_cloudflare.DnsFirewallMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown dns-firewall dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresFirewallId() and args.len < 5) {
        std.debug.print("dns firewall id required for dry-run dns-firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planDnsFirewallMutation(appContext(ctx), endpoint, .{
        .account_id = args[3],
        .dns_firewall_id = if (endpoint.requiresFirewallId()) args[4] else null,
    }));
}

fn commandDryRunDnsSettings(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("scope and id required for dry-run dns-settings\n", .{});
        return;
    }
    const endpoint = app_cloudflare.DnsSettingsMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown dns-settings dry-run scope: {s}\n", .{args[2]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planDnsSettingsMutation(appContext(ctx), endpoint, .{
        .account_id = if (endpoint == .account) args[3] else null,
        .zone_id = if (endpoint == .zone) args[3] else null,
    }));
}

fn commandDryRunLoadBalancing(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("resource and operation required for dry-run load-balancing\n", .{});
        return;
    }
    const resource = app_cloudflare.LoadBalancingMutationResource.parse(args[2]) orelse {
        std.debug.print("unknown load-balancing dry-run resource: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.LoadBalancingMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown load-balancing dry-run operation: {s}\n", .{args[3]});
        return;
    };
    if (!endpoint.supports(resource)) {
        std.debug.print("unsupported load-balancing dry-run operation: {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
        return;
    }

    var index: usize = 4;
    var account_id: ?[]const u8 = null;
    var zone_id: ?[]const u8 = null;
    if (resource.usesAccountId()) {
        if (args.len <= index) {
            std.debug.print("account id required for dry-run load-balancing {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
            return;
        }
        account_id = args[index];
        index += 1;
    } else if (resource.usesZoneId()) {
        if (args.len <= index) {
            std.debug.print("zone id required for dry-run load-balancing {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
            return;
        }
        zone_id = args[index];
        index += 1;
    }

    if (endpoint.requiresResourceId() and args.len <= index) {
        std.debug.print("{s} id required for dry-run load-balancing {s} {s}\n", .{ resource.resourceLabel(), resource.commandName(), endpoint.commandName() });
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planLoadBalancingMutation(appContext(ctx), endpoint, .{
        .resource = resource,
        .account_id = account_id,
        .zone_id = zone_id,
        .resource_id = if (endpoint.requiresResourceId()) args[index] else null,
    }));
}

fn commandDryRunHealthChecks(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("resource and operation required for dry-run health-checks\n", .{});
        return;
    }
    const resource = app_cloudflare.HealthCheckMutationResource.parse(args[2]) orelse {
        std.debug.print("unknown health-checks dry-run resource: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.HealthCheckMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown health-checks dry-run operation: {s}\n", .{args[3]});
        return;
    };
    if (!endpoint.supports(resource)) {
        std.debug.print("unsupported health-checks dry-run operation: {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
        return;
    }

    var index: usize = 4;
    var account_id: ?[]const u8 = null;
    var zone_id: ?[]const u8 = null;
    if (resource.usesAccountId()) {
        if (args.len <= index) {
            std.debug.print("account id required for dry-run health-checks {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
            return;
        }
        account_id = args[index];
        index += 1;
    } else if (resource.usesZoneId()) {
        if (args.len <= index) {
            std.debug.print("zone id required for dry-run health-checks {s} {s}\n", .{ resource.commandName(), endpoint.commandName() });
            return;
        }
        zone_id = args[index];
        index += 1;
    }

    if (endpoint.requiresHealthCheckId() and args.len <= index) {
        std.debug.print("{s} id required for dry-run health-checks {s} {s}\n", .{ resource.resourceLabel(), resource.commandName(), endpoint.commandName() });
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planHealthCheckMutation(appContext(ctx), endpoint, .{
        .resource = resource,
        .account_id = account_id,
        .zone_id = zone_id,
        .healthcheck_id = if (endpoint.requiresHealthCheckId()) args[index] else null,
    }));
}

fn commandDryRunResourceTags(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("scope, operation, and id required for dry-run resource-tags\n", .{});
        return;
    }
    const resource = app_cloudflare.ResourceTaggingMutationResource.parse(args[2]) orelse {
        std.debug.print("unknown resource-tags dry-run scope: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.ResourceTaggingMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown resource-tags dry-run operation: {s}\n", .{args[3]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planResourceTaggingMutation(appContext(ctx), endpoint, .{
        .resource = resource,
        .account_id = if (resource.usesAccountId()) args[4] else null,
        .zone_id = if (resource.usesAccountId()) null else args[4],
    }));
}

fn commandDryRunRulesets(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("scope, operation, and id required for dry-run rulesets\n", .{});
        return;
    }
    const scope = app_cloudflare.RulesetScope.parse(args[2]) orelse {
        std.debug.print("unknown rulesets dry-run scope: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.RulesetMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown rulesets dry-run operation: {s}\n", .{args[3]});
        return;
    };

    var index: usize = 5;
    var mutation_args: app_cloudflare.RulesetMutationArgs = .{
        .scope = scope,
        .scope_id = args[4],
    };

    if (endpoint.requiresRulesetId()) {
        if (args.len <= index) {
            std.debug.print("ruleset id required for dry-run rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.ruleset_id = args[index];
        index += 1;
    }
    if (endpoint.requiresPhase()) {
        if (args.len <= index) {
            std.debug.print("ruleset phase required for dry-run rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.phase = args[index];
        index += 1;
    }
    if (endpoint.requiresRuleId()) {
        if (args.len <= index) {
            std.debug.print("rule id required for dry-run rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.rule_id = args[index];
        index += 1;
    }
    if (endpoint.requiresVersion()) {
        if (args.len <= index) {
            std.debug.print("ruleset version required for dry-run rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.version = args[index];
    }

    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planRulesetMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunCloudforceOneRules(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("operation and account id required for dry-run cloudforce-one-rules\n", .{});
        return;
    }
    const endpoint = app_cloudflare.CloudforceOneRuleMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown cloudforce-one-rules dry-run operation: {s}\n", .{args[2]});
        return;
    };
    var mutation_args: app_cloudflare.CloudforceOneRuleMutationArgs = .{ .account_id = args[3] };
    if (endpoint.requiresRuleId()) {
        if (args.len < 5) {
            std.debug.print("rule id required for dry-run cloudforce-one-rules {s}\n", .{endpoint.commandName()});
            return;
        }
        mutation_args.rule_id = args[4];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planCloudforceOneRuleMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunIpAccessRules(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("scope and operation required for dry-run ip-access\n", .{});
        return;
    }
    const scope = app_cloudflare.IpAccessRuleScope.parse(args[2]) orelse {
        std.debug.print("unknown ip-access dry-run scope: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.IpAccessRuleMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown ip-access dry-run operation: {s}\n", .{args[3]});
        return;
    };
    var index: usize = 4;
    var mutation_args: app_cloudflare.IpAccessRuleMutationArgs = .{ .scope = scope };
    if (scope.usesScopeId()) {
        if (args.len <= index) {
            std.debug.print("{s} id required for dry-run ip-access {s} {s}\n", .{ scope.idLabel(), scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.scope_id = args[index];
        index += 1;
    }
    if (endpoint.requiresRuleId()) {
        if (args.len <= index) {
            std.debug.print("rule id required for dry-run ip-access {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.rule_id = args[index];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planIpAccessRuleMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunZoneLegacyRules(ctx: Context, args: []const []const u8, resource: app_cloudflare.ZoneLegacyRuleResource) !void {
    if (args.len < 4) {
        std.debug.print("operation and zone id required for dry-run {s}\n", .{resource.commandName()});
        return;
    }
    const endpoint = app_cloudflare.ZoneLegacyRuleMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown {s} dry-run operation: {s}\n", .{ resource.commandName(), args[2] });
        return;
    };
    if (!endpoint.supports(resource)) {
        std.debug.print("{s} dry-run operation is not present in the current Cloudflare API schema: {s}\n", .{ resource.commandName(), endpoint.commandName() });
        return;
    }
    var mutation_args: app_cloudflare.ZoneLegacyRuleMutationArgs = .{
        .resource = resource,
        .zone_id = args[3],
    };
    if (endpoint.requiresRuleId()) {
        if (args.len < 5) {
            std.debug.print("{s} id required for dry-run {s} {s}\n", .{ resource.idLabel(), resource.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.rule_id = args[4];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planZoneLegacyRuleMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunPageShield(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("operation and zone id required for dry-run page-shield\n", .{});
        return;
    }
    const endpoint = app_cloudflare.PageShieldMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown page-shield dry-run operation: {s}\n", .{args[2]});
        return;
    };
    var mutation_args: app_cloudflare.PageShieldMutationArgs = .{ .zone_id = args[3] };
    if (endpoint.requiresPolicyId()) {
        if (args.len < 5) {
            std.debug.print("policy id required for dry-run page-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        mutation_args.policy_id = args[4];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planPageShieldMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunCustomPages(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("scope, operation, and scope id required for dry-run custom-pages\n", .{});
        return;
    }
    const scope = app_cloudflare.CustomPageScope.parse(args[2]) orelse {
        std.debug.print("unknown custom-pages dry-run scope: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.CustomPageMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown custom-pages dry-run operation: {s}\n", .{args[3]});
        return;
    };
    var mutation_args: app_cloudflare.CustomPageMutationArgs = .{
        .scope = scope,
        .scope_id = args[4],
    };
    if (endpoint.requiresResourceId()) {
        if (args.len < 6) {
            std.debug.print("resource id required for dry-run custom-pages {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        mutation_args.resource_id = args[5];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planCustomPageMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunAccessCustomPages(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("operation and account id required for dry-run access-custom-pages\n", .{});
        return;
    }
    const endpoint = app_cloudflare.AccessCustomPageMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown access-custom-pages dry-run operation: {s}\n", .{args[2]});
        return;
    };
    var mutation_args: app_cloudflare.AccessCustomPageMutationArgs = .{ .account_id = args[3] };
    if (endpoint.requiresPageId()) {
        if (args.len < 5) {
            std.debug.print("custom page id required for dry-run access-custom-pages {s}\n", .{endpoint.commandName()});
            return;
        }
        mutation_args.page_id = args[4];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccessCustomPageMutation(appContext(ctx), endpoint, mutation_args));
}

fn commandDryRunAccess(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("scope, operation, and scope id required for dry-run access\n", .{});
        return;
    }
    const scope = app_cloudflare.AccessScope.parse(args[2]) orelse {
        std.debug.print("unknown access dry-run scope: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.AccessMutationEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown access dry-run operation: {s}\n", .{args[3]});
        return;
    };
    if (!endpoint.supports(scope)) {
        std.debug.print("access dry-run operation {s} is not supported for {s} scope\n", .{ endpoint.commandName(), scope.commandName() });
        return;
    }
    var mutation_args: app_cloudflare.AccessMutationArgs = .{
        .scope = scope,
        .scope_id = args[4],
    };
    var index: usize = 5;
    if (endpoint.requiresAppId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "application id");
        mutation_args.app_id = args[index];
        index += 1;
    }
    if (endpoint.requiresPolicyId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "policy id");
        mutation_args.policy_id = args[index];
        index += 1;
    }
    if (endpoint.requiresResourceId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "resource id");
        mutation_args.resource_id = args[index];
        index += 1;
    }
    if (endpoint.requiresIdentityProviderId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "identity provider id");
        mutation_args.identity_provider_id = args[index];
        index += 1;
    }
    if (endpoint.requiresServiceTokenId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "service token id");
        mutation_args.service_token_id = args[index];
        index += 1;
    }
    if (endpoint.requiresTagName()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "tag name");
        mutation_args.tag_name = args[index];
        index += 1;
    }
    if (endpoint.requiresCertificateId()) {
        if (index >= args.len) return printMissingAccessMutationArg(scope, endpoint, "certificate id");
        mutation_args.certificate_id = args[index];
        index += 1;
    }
    if (index < args.len) {
        std.debug.print("unused access dry-run argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.planAccessMutation(appContext(ctx), endpoint, mutation_args));
}

fn printMissingAccessMutationArg(scope: app_cloudflare.AccessScope, endpoint: app_cloudflare.AccessMutationEndpoint, label: []const u8) void {
    std.debug.print("{s} required for dry-run access {s} {s}\n", .{ label, scope.commandName(), endpoint.commandName() });
}

fn appContext(ctx: Context) app_cloudflare.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .auth = ctx.auth,
        .domains = ctx.domains,
        .db = ctx.db,
    };
}
