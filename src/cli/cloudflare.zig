const std = @import("std");
const app_cloudflare = @import("app_cloudflare");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    auth: app_cloudflare.Auth,
    domains: []const []const u8,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("cloudflare subcommand required\n", .{});
        return;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "account")) {
        try commandAccount(ctx, args);
    } else if (std.mem.eql(u8, sub, "dry-run")) {
        try commandDryRun(ctx, args);
    } else if (std.mem.eql(u8, sub, "inventory")) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.listInventoryItems(appContext(ctx)));
    } else if (std.mem.eql(u8, sub, "resources")) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.listResources(appContext(ctx)));
    } else if (std.mem.eql(u8, sub, "ips")) {
        const networks: ?[]const u8 = if (args.len > 1) args[1] else null;
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectIps(appContext(ctx), networks));
    } else if (std.mem.eql(u8, sub, "membership")) {
        try commandMembership(ctx, args);
    } else if (app_cloudflare.IdentityEndpoint.parse(sub)) |endpoint| {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectIdentityEndpoint(appContext(ctx), endpoint));
    } else if (std.mem.eql(u8, sub, "token")) {
        try commandToken(ctx, args);
    } else if (std.mem.eql(u8, sub, "zone")) {
        try commandZone(ctx, args);
    } else if (std.mem.eql(u8, sub, "dns")) {
        try commandDns(ctx, args);
    } else if (std.mem.eql(u8, sub, "dns-analytics")) {
        try commandDnsAnalytics(ctx, args);
    } else if (std.mem.eql(u8, sub, "dns-firewall")) {
        try commandDnsFirewall(ctx, args);
    } else if (std.mem.eql(u8, sub, "load-balancing") or std.mem.eql(u8, sub, "lb")) {
        try commandLoadBalancing(ctx, args);
    } else if (std.mem.eql(u8, sub, "health-checks") or std.mem.eql(u8, sub, "health")) {
        try commandHealthChecks(ctx, args);
    } else if (std.mem.eql(u8, sub, "resource-tags") or std.mem.eql(u8, sub, "tags")) {
        try commandResourceTags(ctx, args);
    } else if (std.mem.eql(u8, sub, "rulesets") or std.mem.eql(u8, sub, "ruleset")) {
        try commandRulesets(ctx, args);
    } else if (std.mem.eql(u8, sub, "cloudforce-one-rules") or std.mem.eql(u8, sub, "cf1-rules")) {
        try commandCloudforceOneRules(ctx, args);
    } else if (std.mem.eql(u8, sub, "ip-access") or std.mem.eql(u8, sub, "access-rules")) {
        try commandIpAccessRules(ctx, args);
    } else if (app_cloudflare.ZoneLegacyRuleResource.parse(sub)) |resource| {
        try commandZoneLegacyRules(ctx, args, resource);
    } else if (std.mem.eql(u8, sub, "page-shield")) {
        try commandPageShield(ctx, args);
    } else if (std.mem.eql(u8, sub, "api-shield")) {
        try commandApiShield(ctx, args);
    } else if (std.mem.eql(u8, sub, "security-posture") or std.mem.eql(u8, sub, "zone-security")) {
        try commandZoneSecurityPosture(ctx, args);
    } else if (std.mem.eql(u8, sub, "email-security")) {
        try commandEmailSecurity(ctx, args);
    } else if (std.mem.eql(u8, sub, "email-auth")) {
        try commandEmailAuth(ctx, args);
    } else if (std.mem.eql(u8, sub, "email-sending")) {
        try commandEmailSending(ctx, args);
    } else if (std.mem.eql(u8, sub, "email-routing") or std.mem.eql(u8, sub, "email")) {
        try commandEmailRouting(ctx, args);
    } else if (std.mem.eql(u8, sub, "custom-pages")) {
        try commandCustomPages(ctx, args);
    } else if (std.mem.eql(u8, sub, "access-custom-pages")) {
        try commandAccessCustomPages(ctx, args);
    } else if (std.mem.eql(u8, sub, "access")) {
        try commandAccess(ctx, args);
    } else if (std.mem.eql(u8, sub, "tunnel") or std.mem.eql(u8, sub, "tunnels")) {
        try commandTunnel(ctx, args);
    } else if (std.mem.eql(u8, sub, "zero-trust") or std.mem.eql(u8, sub, "zerotrust") or std.mem.eql(u8, sub, "gateway")) {
        try commandZeroTrust(ctx, args);
    } else if (std.mem.eql(u8, sub, "security-center") or std.mem.eql(u8, sub, "sec-center")) {
        try commandSecurityCenter(ctx, args);
    } else if (std.mem.eql(u8, sub, "audit-logs") or std.mem.eql(u8, sub, "audit")) {
        try commandAuditLogs(ctx, args);
    } else if (std.mem.eql(u8, sub, "logpush")) {
        try commandLogpush(ctx, args);
    } else if (std.mem.eql(u8, sub, "log-explorer") or std.mem.eql(u8, sub, "logs-explorer")) {
        try commandLogExplorer(ctx, args);
    } else if (std.mem.eql(u8, sub, "logs-received") or std.mem.eql(u8, sub, "received-logs")) {
        try commandLogsReceived(ctx, args);
    } else if (std.mem.eql(u8, sub, "tls") or std.mem.eql(u8, sub, "ssl")) {
        try commandTls(ctx, args);
    } else if (std.mem.eql(u8, sub, "dnssec")) {
        try commandDnssec(ctx, args);
    } else if (std.mem.eql(u8, sub, "secondary-dns")) {
        try commandSecondaryDns(ctx, args);
    } else if (std.mem.eql(u8, sub, "setting")) {
        try commandSetting(ctx, args);
    } else if (std.mem.eql(u8, sub, "diagnose")) {
        const domain = app_cloudflare.selectedDomain(ctx.domains, args);
        try app_cloudflare.diagnose(appContext(ctx), domain);
    } else {
        std.debug.print("unknown cloudflare command: {s}\n", .{sub});
    }
}

fn commandDryRun(ctx: Context, args: []const []const u8) !void {
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

fn commandDns(ctx: Context, args: []const []const u8) !void {
    if (args.len == 1) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDns(appContext(ctx), ctx.domains[0]));
        return;
    }
    if (app_cloudflare.DnsRecordReadEndpoint.parse(args[1])) |endpoint| {
        if (endpoint.requiresRecordId() and args.len < 3) {
            std.debug.print("dns record id required for dns {s}\n", .{endpoint.commandName()});
            return;
        }
        const record_id: ?[]const u8 = if (endpoint.requiresRecordId()) args[2] else null;
        const domain = if (endpoint.requiresRecordId())
            if (args.len > 3) args[3] else ctx.domains[0]
        else if (args.len > 2) args[2] else ctx.domains[0];
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDnsRecordEndpoint(appContext(ctx), domain, endpoint, record_id));
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDns(appContext(ctx), args[1]));
}

fn commandDnsAnalytics(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("dns-analytics report|bytime <zone-id> required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.DnsAnalyticsEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown dns-analytics command: {s}\n", .{args[1]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDnsAnalyticsEndpoint(appContext(ctx), args[2], endpoint));
}

fn commandDnsFirewall(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("dns-firewall command required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "analytics")) {
        if (args.len < 5) {
            std.debug.print("dns-firewall analytics report|bytime <account-id> <dns-firewall-id> required\n", .{});
            return;
        }
        const endpoint = app_cloudflare.DnsAnalyticsEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown dns-firewall analytics command: {s}\n", .{args[2]});
            return;
        };
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDnsFirewallAnalyticsEndpoint(appContext(ctx), args[3], args[4], endpoint));
        return;
    }
    const endpoint = app_cloudflare.DnsFirewallReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown dns-firewall command: {s}\n", .{args[1]});
        return;
    };
    if (args.len < 3) {
        std.debug.print("account id required for dns-firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresFirewallId() and args.len < 4) {
        std.debug.print("dns firewall id required for dns-firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectDnsFirewallReadEndpoint(appContext(ctx), args[2], endpoint, if (endpoint.requiresFirewallId()) args[3] else null));
}

fn commandLoadBalancing(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("load-balancing account|user|zone command required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "account")) {
        const endpoint = app_cloudflare.LoadBalancingAccountReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown load-balancing account command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("account id required for load-balancing account {s}\n", .{endpoint.commandName()});
            return;
        }
        const resource_index: usize = 4;
        if (endpoint.requiresResourceId() and args.len <= resource_index) {
            std.debug.print("resource id required for load-balancing account {s}\n", .{endpoint.commandName()});
            return;
        }
        const search_query: ?[]const u8 = if (endpoint == .search and args.len > resource_index) args[resource_index] else null;
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLoadBalancingAccountEndpoint(appContext(ctx), args[3], endpoint, if (endpoint.requiresResourceId()) args[resource_index] else null, search_query));
        return;
    }
    if (std.mem.eql(u8, args[1], "user")) {
        const endpoint = app_cloudflare.LoadBalancingUserReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown load-balancing user command: {s}\n", .{args[2]});
            return;
        };
        if (endpoint.requiresResourceId() and args.len < 4) {
            std.debug.print("resource id required for load-balancing user {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLoadBalancingUserEndpoint(appContext(ctx), endpoint, if (endpoint.requiresResourceId()) args[3] else null));
        return;
    }
    if (std.mem.eql(u8, args[1], "zone")) {
        const endpoint = app_cloudflare.LoadBalancingZoneReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown load-balancing zone command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("zone id required for load-balancing zone {s}\n", .{endpoint.commandName()});
            return;
        }
        if (endpoint.requiresLoadBalancerId() and args.len < 5) {
            std.debug.print("load balancer id required for load-balancing zone {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLoadBalancingZoneEndpoint(appContext(ctx), args[3], endpoint, if (endpoint.requiresLoadBalancerId()) args[4] else null));
        return;
    }
    std.debug.print("unknown load-balancing scope: {s}\n", .{args[1]});
}

fn commandHealthChecks(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("health-checks endpoint|zone|smart-shield command required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "endpoint") or std.mem.eql(u8, args[1], "account")) {
        const endpoint = app_cloudflare.EndpointHealthCheckReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown health-checks endpoint command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("account id required for health-checks endpoint {s}\n", .{endpoint.commandName()});
            return;
        }
        if (endpoint.requiresHealthCheckId() and args.len < 5) {
            std.debug.print("health check id required for health-checks endpoint {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEndpointHealthCheck(appContext(ctx), args[3], endpoint, if (endpoint.requiresHealthCheckId()) args[4] else null));
        return;
    }
    if (std.mem.eql(u8, args[1], "zone")) {
        const endpoint = app_cloudflare.ZoneHealthCheckReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown health-checks zone command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("zone id required for health-checks zone {s}\n", .{endpoint.commandName()});
            return;
        }
        if (endpoint.requiresHealthCheckId() and args.len < 5) {
            std.debug.print("health check id required for health-checks zone {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneHealthCheck(appContext(ctx), args[3], endpoint, if (endpoint.requiresHealthCheckId()) args[4] else null));
        return;
    }
    if (std.mem.eql(u8, args[1], "smart-shield") or std.mem.eql(u8, args[1], "smartshield")) {
        const endpoint = app_cloudflare.SmartShieldHealthCheckReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown health-checks smart-shield command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("zone id required for health-checks smart-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        if (endpoint.requiresHealthCheckId() and args.len < 5) {
            std.debug.print("health check id required for health-checks smart-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectSmartShieldHealthCheck(appContext(ctx), args[3], endpoint, if (endpoint.requiresHealthCheckId()) args[4] else null));
        return;
    }
    std.debug.print("unknown health-checks scope: {s}\n", .{args[1]});
}

fn commandResourceTags(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("resource-tags account|zone command required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "account")) {
        const endpoint = app_cloudflare.ResourceTaggingAccountReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown resource-tags account command: {s}\n", .{args[2]});
            return;
        };
        if (args.len < 4) {
            std.debug.print("account id required for resource-tags account {s}\n", .{endpoint.commandName()});
            return;
        }
        if (endpoint.requiresTagKey() and args.len < 5) {
            std.debug.print("tag key required for resource-tags account {s}\n", .{endpoint.commandName()});
            return;
        }
        const read_args: app_cloudflare.ResourceTaggingAccountReadArgs = switch (endpoint) {
            .tags => .{
                .resource_type = if (args.len > 4) args[4] else null,
                .resource_id = if (args.len > 5) args[5] else null,
                .worker_id = if (args.len > 6) args[6] else null,
            },
            .keys => .{},
            .resources => .{ .type_filter = if (args.len > 4) args[4] else null },
            .values => .{ .tag_key = args[4] },
        };
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectResourceTaggingAccountEndpoint(appContext(ctx), args[3], endpoint, read_args));
        return;
    }
    if (std.mem.eql(u8, args[1], "zone")) {
        if (args.len < 4) {
            std.debug.print("zone id required for resource-tags zone tags\n", .{});
            return;
        }
        if (!std.mem.eql(u8, args[2], "tags") and !std.mem.eql(u8, args[2], "get")) {
            std.debug.print("unknown resource-tags zone command: {s}\n", .{args[2]});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectResourceTaggingZoneTags(appContext(ctx), args[3], .{
            .resource_type = if (args.len > 4) args[4] else null,
            .resource_id = if (args.len > 5) args[5] else null,
            .access_application_id = if (args.len > 6) args[6] else null,
        }));
        return;
    }
    std.debug.print("unknown resource-tags scope: {s}\n", .{args[1]});
}

fn commandRulesets(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("rulesets account|zone command and id required\n", .{});
        return;
    }
    const scope = app_cloudflare.RulesetScope.parse(args[1]) orelse {
        std.debug.print("unknown rulesets scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.RulesetReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown rulesets command: {s}\n", .{args[2]});
        return;
    };
    const scope_id = args[3];
    var index: usize = 4;
    var read_args: app_cloudflare.RulesetReadArgs = .{};

    if (endpoint.requiresRulesetId()) {
        if (args.len <= index) {
            std.debug.print("ruleset id required for rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.ruleset_id = args[index];
        index += 1;
    }
    if (endpoint.requiresPhase()) {
        if (args.len <= index) {
            std.debug.print("ruleset phase required for rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.phase = args[index];
        index += 1;
    }
    if (endpoint.requiresVersion()) {
        if (args.len <= index) {
            std.debug.print("ruleset version required for rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.version = args[index];
        index += 1;
    }
    if (endpoint.requiresRuleTag()) {
        if (args.len <= index) {
            std.debug.print("rule tag required for rulesets {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.rule_tag = args[index];
    }

    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectRulesetEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn commandCloudforceOneRules(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("cloudforce-one-rules command and account id required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.CloudforceOneRuleReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown cloudforce-one-rules command: {s}\n", .{args[1]});
        return;
    };
    const account_id = args[2];
    var index: usize = 3;
    var read_args: app_cloudflare.CloudforceOneRuleReadArgs = .{};

    if (endpoint.requiresRuleId()) {
        if (args.len <= index) {
            std.debug.print("rule id required for cloudforce-one-rules {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.rule_id = args[index];
        index += 1;
    } else if (endpoint.requiresQuery() and args.len > index and !isKeyValue(args[index])) {
        read_args.query = args[index];
        index += 1;
    }

    while (index < args.len) : (index += 1) {
        if (!applyCloudforceOneRuleFilter(&read_args, args[index])) {
            std.debug.print("unknown cloudforce-one-rules filter: {s}\n", .{args[index]});
            return;
        }
    }

    if (endpoint.requiresQuery() and read_args.query == null) {
        std.debug.print("query required for cloudforce-one-rules search\n", .{});
        return;
    }

    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectCloudforceOneRuleEndpoint(appContext(ctx), account_id, endpoint, read_args));
}

fn commandIpAccessRules(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("ip-access user|account|zone command required\n", .{});
        return;
    }
    const scope = app_cloudflare.IpAccessRuleScope.parse(args[1]) orelse {
        std.debug.print("unknown ip-access scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.IpAccessRuleReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown ip-access command: {s}\n", .{args[2]});
        return;
    };
    if (!endpoint.supports(scope)) {
        std.debug.print("ip-access {s} {s} is not present in the current Cloudflare API schema\n", .{ scope.commandName(), endpoint.commandName() });
        return;
    }
    var index: usize = 3;
    var scope_id: ?[]const u8 = null;
    var read_args: app_cloudflare.IpAccessRuleListArgs = .{};

    if (scope.usesScopeId()) {
        if (args.len <= index) {
            std.debug.print("{s} id required for ip-access {s} {s}\n", .{ scope.idLabel(), scope.commandName(), endpoint.commandName() });
            return;
        }
        scope_id = args[index];
        index += 1;
    }
    if (endpoint.requiresRuleId()) {
        if (args.len <= index) {
            std.debug.print("rule id required for ip-access {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.rule_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyIpAccessRuleFilter(&read_args, args[index])) {
            std.debug.print("unknown ip-access filter: {s}\n", .{args[index]});
            return;
        }
    }

    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectIpAccessRuleEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn commandZoneLegacyRules(ctx: Context, args: []const []const u8, resource: app_cloudflare.ZoneLegacyRuleResource) !void {
    if (args.len < 3) {
        std.debug.print("{s} list|show command and zone id required\n", .{resource.commandName()});
        return;
    }
    const endpoint = app_cloudflare.ZoneLegacyRuleReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown {s} command: {s}\n", .{ resource.commandName(), args[1] });
        return;
    };
    const zone_id = args[2];
    var rule_id: ?[]const u8 = null;
    if (endpoint.requiresRuleId()) {
        if (args.len < 4) {
            std.debug.print("{s} id required for {s} {s}\n", .{ resource.idLabel(), resource.commandName(), endpoint.commandName() });
            return;
        }
        rule_id = args[3];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneLegacyRuleEndpoint(appContext(ctx), zone_id, resource, endpoint, rule_id));
}

fn commandPageShield(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("page-shield settings|policies|policy|connections|connection|scripts|script|cookies|cookie command and zone id required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.PageShieldReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown page-shield command: {s}\n", .{args[1]});
        return;
    };
    var read_args: app_cloudflare.PageShieldReadArgs = .{};
    const zone_id = args[2];
    var index: usize = 3;
    if (endpoint.requiresResourceId()) {
        if (args.len <= index) {
            std.debug.print("{s} id required for page-shield {s}\n", .{ endpoint.idLabel(), endpoint.commandName() });
            return;
        }
        read_args.resource_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!endpoint.acceptsFilters()) {
            std.debug.print("page-shield {s} does not accept filters: {s}\n", .{ endpoint.commandName(), args[index] });
            return;
        }
        if (!applyPageShieldFilter(&read_args, args[index])) {
            std.debug.print("unknown page-shield filter: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectPageShieldEndpoint(appContext(ctx), zone_id, endpoint, read_args));
}

fn commandApiShield(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("api-shield discovery-openapi|discovery-operations|discovery-operation|operations|operation|schemas|labels|managed-label|user-label|configuration|client-certificates|client-certificate|hostname-associations command and zone id required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.ApiShieldReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown api-shield command: {s}\n", .{args[1]});
        return;
    };
    const zone_id = args[2];
    var read_args: app_cloudflare.ApiShieldReadArgs = .{};
    var index: usize = 3;
    if (endpoint.requiresDiscoveryId()) {
        if (args.len <= index) {
            std.debug.print("discovery id required for api-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.discovery_id = args[index];
        index += 1;
    }
    if (endpoint.requiresOperationId()) {
        if (args.len <= index) {
            std.debug.print("operation id required for api-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.operation_id = args[index];
        index += 1;
    }
    if (endpoint.requiresLabelName()) {
        if (args.len <= index) {
            std.debug.print("label name required for api-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.label_name = args[index];
        index += 1;
    }
    if (endpoint.requiresClientCertificateId()) {
        if (args.len <= index) {
            std.debug.print("client certificate id required for api-shield {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.client_certificate_id = args[index];
        index += 1;
    }
    if (index != args.len) {
        std.debug.print("unexpected api-shield argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectApiShieldEndpoint(appContext(ctx), zone_id, endpoint, read_args));
}

fn commandZoneSecurityPosture(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("security-posture ai-custom-topics|ai-settings|bot-management|content-scanning-payloads|content-scanning-settings|leaked-credential-status|leaked-credential-detections|leaked-credential-detection|fraud-detection-settings|csam-scanner|ct-alerting command and zone id required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.ZoneSecurityPostureReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown security-posture command: {s}\n", .{args[1]});
        return;
    };
    const zone_id = args[2];
    var read_args: app_cloudflare.ZoneSecurityPostureReadArgs = .{};
    var index: usize = 3;
    if (endpoint.requiresDetectionId()) {
        if (args.len <= index) {
            std.debug.print("detection id required for security-posture {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.detection_id = args[index];
        index += 1;
    }
    if (index != args.len) {
        std.debug.print("unexpected security-posture argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneSecurityPostureEndpoint(appContext(ctx), zone_id, endpoint, read_args));
}

fn commandEmailSecurity(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4 or !std.mem.eql(u8, args[1], "settings")) {
        std.debug.print("email-security settings allow-policies|allow-policy|blocked-senders|blocked-sender|domains|domain|impersonation-registry|impersonation-registry-entry|sending-domain-restrictions|sending-domain-restriction|trusted-domains|trusted-domain|url-ignore-patterns|url-ignore-pattern <account-id> [resource-id] [key=value...] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.EmailSecuritySettingsReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown email-security settings command: {s}\n", .{args[2]});
        return;
    };
    const account_id = args[3];
    var read_args: app_cloudflare.EmailSecuritySettingsReadArgs = .{};
    var index: usize = 4;
    if (endpoint.requiresResourceId()) {
        if (args.len <= index) {
            std.debug.print("resource id required for email-security settings {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.resource_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!endpoint.acceptsFilters()) {
            std.debug.print("email-security settings {s} does not accept filters: {s}\n", .{ endpoint.commandName(), args[index] });
            return;
        }
        if (!applyEmailSecuritySettingsFilter(&read_args, args[index])) {
            std.debug.print("unknown email-security settings filter: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailSecuritySettingsEndpoint(appContext(ctx), account_id, endpoint, read_args));
}

fn commandEmailRouting(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("email-routing account addresses|address <account-id> [address-id] [key=value...] or email-routing zone settings|dns|rules|rule|catch-all <zone-id> [rule-id] [key=value...] required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "account")) {
        const endpoint = app_cloudflare.EmailRoutingAccountReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown email-routing account command: {s}\n", .{args[2]});
            return;
        };
        const account_id = args[3];
        var read_args: app_cloudflare.EmailRoutingAccountReadArgs = .{};
        var index: usize = 4;
        if (endpoint.requiresAddressId()) {
            if (args.len <= index) {
                std.debug.print("destination address id required for email-routing account {s}\n", .{endpoint.commandName()});
                return;
            }
            read_args.destination_address_identifier = args[index];
            index += 1;
        }
        while (index < args.len) : (index += 1) {
            if (!endpoint.acceptsFilters()) {
                std.debug.print("email-routing account {s} does not accept filters: {s}\n", .{ endpoint.commandName(), args[index] });
                return;
            }
            if (!applyEmailRoutingAccountFilter(&read_args, args[index])) {
                std.debug.print("unknown email-routing account filter: {s}\n", .{args[index]});
                return;
            }
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailRoutingAccountEndpoint(appContext(ctx), account_id, endpoint, read_args));
        return;
    }
    if (std.mem.eql(u8, args[1], "zone")) {
        const endpoint = app_cloudflare.EmailRoutingZoneReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown email-routing zone command: {s}\n", .{args[2]});
            return;
        };
        const zone_id = args[3];
        var read_args: app_cloudflare.EmailRoutingZoneReadArgs = .{};
        var index: usize = 4;
        if (endpoint.requiresRuleId()) {
            if (args.len <= index) {
                std.debug.print("rule id required for email-routing zone {s}\n", .{endpoint.commandName()});
                return;
            }
            read_args.rule_identifier = args[index];
            index += 1;
        }
        while (index < args.len) : (index += 1) {
            if (!endpoint.acceptsFilters()) {
                std.debug.print("email-routing zone {s} does not accept filters: {s}\n", .{ endpoint.commandName(), args[index] });
                return;
            }
            if (!applyEmailRoutingZoneFilter(&read_args, args[index])) {
                std.debug.print("unknown email-routing zone filter: {s}\n", .{args[index]});
                return;
            }
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailRoutingZoneEndpoint(appContext(ctx), zone_id, endpoint, read_args));
        return;
    }
    std.debug.print("unknown email-routing scope: {s}\n", .{args[1]});
}

fn commandEmailAuth(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("email-auth dmarc-reports|spf-inspect <zone-id> [spf-record-id] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.EmailAuthReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown email-auth command: {s}\n", .{args[1]});
        return;
    };
    const zone_id = args[2];
    var read_args: app_cloudflare.EmailAuthReadArgs = .{};
    if (endpoint.requiresSpfRecordId()) {
        if (args.len < 4) {
            std.debug.print("spf record id required for email-auth {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.spf_record_id = args[3];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailAuthEndpoint(appContext(ctx), zone_id, endpoint, read_args));
}

fn commandEmailSending(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("email-sending account limits <account-id> or email-sending zone subdomains|subdomain|subdomain-dns|subdomain-dns-status <zone-id> [subdomain-id] required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "account")) {
        const endpoint = app_cloudflare.EmailSendingAccountReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown email-sending account command: {s}\n", .{args[2]});
            return;
        };
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailSendingAccountEndpoint(appContext(ctx), args[3], endpoint, .{}));
        return;
    }
    if (std.mem.eql(u8, args[1], "zone")) {
        const endpoint = app_cloudflare.EmailSendingZoneReadEndpoint.parse(args[2]) orelse {
            std.debug.print("unknown email-sending zone command: {s}\n", .{args[2]});
            return;
        };
        const zone_id = args[3];
        var read_args: app_cloudflare.EmailSendingZoneReadArgs = .{};
        if (endpoint.requiresSubdomainId()) {
            if (args.len < 5) {
                std.debug.print("subdomain id required for email-sending zone {s}\n", .{endpoint.commandName()});
                return;
            }
            read_args.subdomain_id = args[4];
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectEmailSendingZoneEndpoint(appContext(ctx), zone_id, endpoint, read_args));
        return;
    }
    std.debug.print("unknown email-sending scope: {s}\n", .{args[1]});
}

fn commandCustomPages(ctx: Context, args: []const []const u8) !void {
    if (args.len < 5) {
        std.debug.print("custom-pages account|zone pages|assets list|show <scope-id> [resource-id] required\n", .{});
        return;
    }
    const scope = app_cloudflare.CustomPageScope.parse(args[1]) orelse {
        std.debug.print("unknown custom-pages scope: {s}\n", .{args[1]});
        return;
    };
    const resource = app_cloudflare.CustomPageResource.parse(args[2]) orelse {
        std.debug.print("unknown custom-pages resource: {s}\n", .{args[2]});
        return;
    };
    const endpoint = app_cloudflare.CustomPageReadEndpoint.parse(args[3]) orelse {
        std.debug.print("unknown custom-pages command: {s}\n", .{args[3]});
        return;
    };
    var read_args: app_cloudflare.CustomPageReadArgs = .{};
    const scope_id = args[4];
    if (endpoint.requiresResourceId()) {
        if (args.len < 6) {
            std.debug.print("{s} id required for custom-pages {s} {s} {s}\n", .{ resource.idLabel(), scope.commandName(), resource.commandName(), endpoint.commandName() });
            return;
        }
        read_args.resource_id = args[5];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectCustomPageEndpoint(appContext(ctx), scope, scope_id, resource, endpoint, read_args));
}

fn commandAccessCustomPages(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("access-custom-pages list|show <account-id> [custom-page-id] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.AccessCustomPageReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown access-custom-pages command: {s}\n", .{args[1]});
        return;
    };
    const account_id = args[2];
    var page_id: ?[]const u8 = null;
    if (endpoint.requiresPageId()) {
        if (args.len < 4) {
            std.debug.print("custom page id required for access-custom-pages {s}\n", .{endpoint.commandName()});
            return;
        }
        page_id = args[3];
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccessCustomPageEndpoint(appContext(ctx), account_id, endpoint, page_id));
}

fn commandAccess(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("access account|zone <route> <scope-id> [ids...] required\n", .{});
        return;
    }
    const scope = app_cloudflare.AccessScope.parse(args[1]) orelse {
        std.debug.print("unknown access scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.AccessReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown access route: {s}\n", .{args[2]});
        return;
    };
    if (!endpoint.supports(scope)) {
        std.debug.print("access route {s} is not supported for {s} scope\n", .{ endpoint.commandName(), scope.commandName() });
        return;
    }
    var read_args: app_cloudflare.AccessReadArgs = .{};
    const scope_id = args[3];
    var index: usize = 4;
    if (endpoint.requiresAppId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "application id");
        read_args.app_id = args[index];
        index += 1;
    }
    if (endpoint.requiresPolicyId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "policy id");
        read_args.policy_id = args[index];
        index += 1;
    }
    if (endpoint.requiresResourceId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "resource id");
        read_args.resource_id = args[index];
        index += 1;
    }
    if (endpoint.requiresIdentityProviderId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "identity provider id");
        read_args.identity_provider_id = args[index];
        index += 1;
    }
    if (endpoint.requiresServiceTokenId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "service token id");
        read_args.service_token_id = args[index];
        index += 1;
    }
    if (endpoint.requiresTagName()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "tag name");
        read_args.tag_name = args[index];
        index += 1;
    }
    if (endpoint.requiresPolicyTestId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "policy test id");
        read_args.policy_test_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCertificateId()) {
        if (index >= args.len) return printMissingAccessReadArg(scope, endpoint, "certificate id");
        read_args.certificate_id = args[index];
        index += 1;
    }
    if (index < args.len) {
        std.debug.print("unused access argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccessEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn printMissingAccessReadArg(scope: app_cloudflare.AccessScope, endpoint: app_cloudflare.AccessReadEndpoint, label: []const u8) void {
    std.debug.print("{s} required for access {s} {s}\n", .{ label, scope.commandName(), endpoint.commandName() });
}

fn printMissingAccessMutationArg(scope: app_cloudflare.AccessScope, endpoint: app_cloudflare.AccessMutationEndpoint, label: []const u8) void {
    std.debug.print("{s} required for dry-run access {s} {s}\n", .{ label, scope.commandName(), endpoint.commandName() });
}

fn commandTunnel(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("tunnel <route> <account-id> [ids...] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.TunnelReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown tunnel route: {s}\n", .{args[1]});
        return;
    };
    const account_id = args[2];
    var read_args: app_cloudflare.TunnelReadArgs = .{};
    var index: usize = 3;
    if (endpoint.requiresTunnelId()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "tunnel id");
        read_args.tunnel_id = args[index];
        index += 1;
    }
    if (endpoint.requiresConnectorId()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "connector id");
        read_args.connector_id = args[index];
        index += 1;
    }
    if (endpoint.requiresRouteId()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "route id");
        read_args.route_id = args[index];
        index += 1;
    }
    if (endpoint.requiresIp()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "IP or CIDR");
        read_args.ip = args[index];
        index += 1;
    }
    if (endpoint.requiresHostnameRouteId()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "hostname route id");
        read_args.hostname_route_id = args[index];
        index += 1;
    }
    if (endpoint.requiresSubnetId()) {
        if (index >= args.len) return printMissingTunnelReadArg(endpoint, "subnet id");
        read_args.subnet_id = args[index];
        index += 1;
    }
    if (index < args.len) {
        std.debug.print("unused tunnel argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectTunnelEndpoint(appContext(ctx), account_id, endpoint, read_args));
}

fn printMissingTunnelReadArg(endpoint: app_cloudflare.TunnelReadEndpoint, label: []const u8) void {
    std.debug.print("{s} required for tunnel {s}\n", .{ label, endpoint.commandName() });
}

fn commandZeroTrust(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("zero-trust <route> <account-id> [ids...] [key=value...] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.ZeroTrustReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown zero-trust route: {s}\n", .{args[1]});
        return;
    };
    const account_id = args[2];
    var read_args: app_cloudflare.ZeroTrustReadArgs = .{};
    var index: usize = 3;
    if (endpoint.requiresOperationId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "operation id");
        read_args.operation_id = args[index];
        index += 1;
    }
    if (endpoint.requiresLocationId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "location id");
        read_args.location_id = args[index];
        index += 1;
    }
    if (endpoint.requiresProxyEndpointId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "proxy endpoint id");
        read_args.proxy_endpoint_id = args[index];
        index += 1;
    }
    if (endpoint.requiresRuleId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "rule id");
        read_args.rule_id = args[index];
        index += 1;
    }
    if (endpoint.requiresPacfileId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "PAC file id");
        read_args.pacfile_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCertificateId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "certificate id");
        read_args.certificate_id = args[index];
        index += 1;
    }
    if (endpoint.requiresListId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "list id");
        read_args.list_id = args[index];
        index += 1;
    }
    if (endpoint.requiresUserId()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "user id");
        read_args.user_id = args[index];
        index += 1;
    }
    if (endpoint.requiresNonce()) {
        if (index >= args.len) return printMissingZeroTrustReadArg(endpoint, "session nonce");
        read_args.nonce = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyZeroTrustReadFilter(&read_args, args[index])) {
            std.debug.print("unused zero-trust argument: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZeroTrustEndpoint(appContext(ctx), account_id, endpoint, read_args));
}

fn printMissingZeroTrustReadArg(endpoint: app_cloudflare.ZeroTrustReadEndpoint, label: []const u8) void {
    std.debug.print("{s} required for zero-trust {s}\n", .{ label, endpoint.commandName() });
}

fn commandSecurityCenter(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("security-center account|zone <route> <scope-id> [issue-id] [key=value...] required\n", .{});
        return;
    }
    const scope = app_cloudflare.SecurityCenterScope.parse(args[1]) orelse {
        std.debug.print("unknown security-center scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.SecurityCenterReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown security-center route: {s}\n", .{args[2]});
        return;
    };
    const scope_id = args[3];
    var read_args: app_cloudflare.SecurityCenterReadArgs = .{};
    var index: usize = 4;
    if (endpoint.requiresIssueId()) {
        if (index >= args.len) {
            std.debug.print("issue id required for security-center {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.issue_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applySecurityCenterReadFilter(&read_args, args[index])) {
            std.debug.print("unused security-center argument: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectSecurityCenterEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn commandAuditLogs(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("audit-logs account|account-v2|organization-v2|user [id] [key=value...] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.AuditLogReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown audit-logs route: {s}\n", .{args[1]});
        return;
    };
    var read_args: app_cloudflare.AuditLogReadArgs = .{};
    var index: usize = 2;
    if (endpoint.requiresAccountId()) {
        if (index >= args.len) {
            std.debug.print("account id required for audit-logs {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.account_id = args[index];
        index += 1;
    }
    if (endpoint.requiresOrganizationId()) {
        if (index >= args.len) {
            std.debug.print("organization id required for audit-logs {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.organization_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyAuditLogReadFilter(&read_args, args[index])) {
            std.debug.print("unused audit-logs argument: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAuditLogEndpoint(appContext(ctx), endpoint, read_args));
}

fn commandLogpush(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("logpush account|zone jobs|job|dataset-jobs|dataset-fields <scope-id> [job-id|dataset-id] required\n", .{});
        return;
    }
    const scope = app_cloudflare.ObservabilityScope.parse(args[1]) orelse {
        std.debug.print("unknown logpush scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.LogpushReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown logpush route: {s}\n", .{args[2]});
        return;
    };
    const scope_id = args[3];
    var read_args: app_cloudflare.LogpushReadArgs = .{};
    var index: usize = 4;
    if (endpoint.requiresJobId()) {
        if (index >= args.len) {
            std.debug.print("job id required for logpush {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.job_id = args[index];
        index += 1;
    }
    if (endpoint.requiresDatasetId()) {
        if (index >= args.len) {
            std.debug.print("dataset id required for logpush {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.dataset_id = args[index];
        index += 1;
    }
    if (index < args.len) {
        std.debug.print("unused logpush argument: {s}\n", .{args[index]});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLogpushEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn commandLogExplorer(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("log-explorer account|zone datasets|available|dataset <scope-id> [dataset-id] [key=value...] required\n", .{});
        return;
    }
    const scope = app_cloudflare.ObservabilityScope.parse(args[1]) orelse {
        std.debug.print("unknown log-explorer scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.LogExplorerReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown log-explorer route: {s}\n", .{args[2]});
        return;
    };
    const scope_id = args[3];
    var read_args: app_cloudflare.LogExplorerReadArgs = .{};
    var index: usize = 4;
    if (endpoint.requiresDatasetId()) {
        if (index >= args.len) {
            std.debug.print("dataset id required for log-explorer {s} {s}\n", .{ scope.commandName(), endpoint.commandName() });
            return;
        }
        read_args.dataset_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyLogExplorerReadFilter(&read_args, args[index])) {
            std.debug.print("unused log-explorer argument: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLogExplorerEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn commandLogsReceived(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("logs-received retention-flag|received|fields|rayid <zone-id> [ray-id] [key=value...] required\n", .{});
        return;
    }
    const endpoint = app_cloudflare.LogsReceivedReadEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown logs-received route: {s}\n", .{args[1]});
        return;
    };
    const zone_id = args[2];
    var read_args: app_cloudflare.LogsReceivedReadArgs = .{};
    var index: usize = 3;
    if (endpoint.requiresRayId()) {
        if (index >= args.len) {
            std.debug.print("ray id required for logs-received {s}\n", .{endpoint.commandName()});
            return;
        }
        read_args.ray_id = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyLogsReceivedReadFilter(&read_args, args[index])) {
            std.debug.print("unused logs-received argument: {s}\n", .{args[index]});
            return;
        }
    }
    if (endpoint == .received and read_args.end == null) {
        std.debug.print("end=<rfc3339> required for logs-received received\n", .{});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectLogsReceivedEndpoint(appContext(ctx), zone_id, endpoint, read_args));
}

fn commandTls(ctx: Context, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("tls account|zone|origin-ca <route> <scope-id> [ids...] [key=value...] required\n", .{});
        return;
    }
    const scope = app_cloudflare.TlsScope.parse(args[1]) orelse {
        std.debug.print("unknown tls scope: {s}\n", .{args[1]});
        return;
    };
    const endpoint = app_cloudflare.TlsReadEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown tls route: {s}\n", .{args[2]});
        return;
    };
    if (!endpoint.supports(scope)) {
        std.debug.print("tls route {s} does not support scope {s}\n", .{ endpoint.commandName(), scope.commandName() });
        return;
    }
    const scope_id = args[3];
    var read_args: app_cloudflare.TlsReadArgs = .{};
    var index: usize = 4;
    if (endpoint.requiresCertificatePackId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "certificate pack id");
        read_args.certificate_pack_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCustomCsrId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "custom CSR id");
        read_args.custom_csr_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCustomOriginTrustStoreId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "custom origin trust store id");
        read_args.custom_origin_trust_store_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCustomCertificateId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "custom certificate id");
        read_args.custom_certificate_id = args[index];
        index += 1;
    }
    if (endpoint.requiresKeylessCertificateId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "keyless certificate id");
        read_args.keyless_certificate_id = args[index];
        index += 1;
    }
    if (endpoint.requiresCertificateId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "certificate id");
        read_args.certificate_id = args[index];
        index += 1;
    }
    if (endpoint.requiresSettingId()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "setting id");
        read_args.setting_id = args[index];
        index += 1;
    }
    if (endpoint.requiresHostname()) {
        if (index >= args.len) return printMissingTlsReadArg(scope, endpoint, "hostname");
        read_args.hostname = args[index];
        index += 1;
    }
    while (index < args.len) : (index += 1) {
        if (!applyTlsReadFilter(&read_args, args[index])) {
            std.debug.print("unused tls argument: {s}\n", .{args[index]});
            return;
        }
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectTlsEndpoint(appContext(ctx), scope, scope_id, endpoint, read_args));
}

fn printMissingTlsReadArg(scope: app_cloudflare.TlsScope, endpoint: app_cloudflare.TlsReadEndpoint, label: []const u8) void {
    std.debug.print("{s} required for tls {s} {s}\n", .{ label, scope.commandName(), endpoint.commandName() });
}

fn commandDnssec(ctx: Context, args: []const []const u8) !void {
    if (args.len > 1 and std.mem.eql(u8, args[1], "zsk")) {
        const domain = if (args.len > 2) args[2] else ctx.domains[0];
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneEndpoint(appContext(ctx), domain, .dnssec_zsk));
        return;
    }
    const domain = app_cloudflare.selectedDomain(ctx.domains, args);
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneEndpoint(appContext(ctx), domain, .dnssec));
}

fn commandMembership(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectIdentityEndpoint(appContext(ctx), .memberships));
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectMembership(appContext(ctx), args[1]));
}

fn commandZone(ctx: Context, args: []const []const u8) !void {
    if (args.len > 1 and (std.mem.eql(u8, args[1], "show") or std.mem.eql(u8, args[1], "detail") or std.mem.eql(u8, args[1], "details"))) {
        if (args.len < 3) {
            std.debug.print("zone id required for zone {s}\n", .{args[1]});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneById(appContext(ctx), args[2]));
        return;
    }
    if (args.len > 1) {
        if (app_cloudflare.ZoneLifecycleReadEndpoint.parse(args[1])) |endpoint| {
            if (args.len < 3) {
                std.debug.print("zone id required for zone {s}\n", .{endpoint.commandName()});
                return;
            }
            if (endpoint.requiresPlanId() and args.len < 4) {
                std.debug.print("plan id required for zone {s}\n", .{endpoint.commandName()});
                return;
            }
            try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneLifecycleReadEndpoint(appContext(ctx), args[2], endpoint, if (endpoint.requiresPlanId()) args[3] else null));
            return;
        }
    }
    const domain = app_cloudflare.selectedDomain(ctx.domains, args);
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZone(appContext(ctx), domain));
}

fn commandSecondaryDns(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("secondary-dns command required\n", .{});
        return;
    }
    if (app_cloudflare.SecondaryDnsAccountResource.parseListCommand(args[1])) |resource| {
        if (args.len < 3) {
            std.debug.print("account id required for secondary-dns {s}\n", .{resource.listCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectSecondaryDnsAccountCollection(appContext(ctx), args[2], resource));
        return;
    }
    if (app_cloudflare.SecondaryDnsAccountResource.parseDetailCommand(args[1])) |resource| {
        if (args.len < 4) {
            std.debug.print("account id and resource id required for secondary-dns {s}\n", .{resource.detailCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectSecondaryDnsAccountResource(appContext(ctx), args[2], resource, args[3]));
        return;
    }
    if (app_cloudflare.SecondaryDnsZoneReadEndpoint.parse(args[1])) |endpoint| {
        if (args.len < 3) {
            std.debug.print("zone id required for secondary-dns {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectSecondaryDnsZoneEndpoint(appContext(ctx), args[2], endpoint));
        return;
    }
    std.debug.print("unknown secondary-dns command: {s}\n", .{args[1]});
}

fn commandAccount(ctx: Context, args: []const []const u8) !void {
    if (args.len == 1 or std.mem.eql(u8, args[1], "list")) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccounts(appContext(ctx)));
        return;
    }
    if (std.mem.eql(u8, args[1], "dns-record-usage") or std.mem.eql(u8, args[1], "dns-usage")) {
        if (args.len < 3) {
            std.debug.print("account id required for account dns-record-usage\n", .{});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountDnsRecordUsage(appContext(ctx), args[2]));
        return;
    }
    if (app_cloudflare.AccountCollection.parseListCommand(args[1])) |collection| {
        if (args.len < 3) {
            std.debug.print("account id required for account {s}\n", .{collection.listCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountCollection(appContext(ctx), args[2], collection));
        return;
    }
    if (app_cloudflare.AccountCollection.parseDetailCommand(args[1])) |collection| {
        if (args.len < 4) {
            std.debug.print("account id and resource id required for account {s}\n", .{collection.detailCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountResource(appContext(ctx), args[2], collection, args[3]));
        return;
    }
    if (app_cloudflare.AccountTokenEndpoint.parse(args[1])) |endpoint| {
        if (args.len < 3) {
            std.debug.print("account id required for account {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountTokenEndpoint(appContext(ctx), args[2], endpoint));
        return;
    }
    if (std.mem.eql(u8, args[1], "token")) {
        if (args.len < 4) {
            std.debug.print("account id and token id required for account token\n", .{});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountToken(appContext(ctx), args[2], args[3]));
        return;
    }
    if (std.mem.eql(u8, args[1], "user-group-members")) {
        if (args.len < 4) {
            std.debug.print("account id and user group id required for account user-group-members\n", .{});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountUserGroupMembers(appContext(ctx), args[2], args[3]));
        return;
    }
    if (std.mem.eql(u8, args[1], "user-group-member")) {
        if (args.len < 5) {
            std.debug.print("account id, user group id, and member id required for account user-group-member\n", .{});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountUserGroupMember(appContext(ctx), args[2], args[3], args[4]));
        return;
    }
    if (app_cloudflare.AccountIamCollection.parseListCommand(args[1])) |collection| {
        if (args.len < 3) {
            std.debug.print("account id required for account {s}\n", .{collection.listCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountIamCollection(appContext(ctx), args[2], collection));
        return;
    }
    if (app_cloudflare.AccountIamCollection.parseDetailCommand(args[1])) |collection| {
        if (args.len < 4) {
            std.debug.print("account id and resource id required for account {s}\n", .{collection.detailCommandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountIamResource(appContext(ctx), args[2], collection, args[3]));
        return;
    }
    const endpoint = app_cloudflare.AccountEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown account command: {s}\n", .{args[1]});
        return;
    };
    if (args.len < 3) {
        std.debug.print("account id required for account {s}\n", .{endpoint.commandName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectAccountEndpoint(appContext(ctx), args[2], endpoint));
}

fn commandToken(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectUserTokenEndpoint(appContext(ctx), .list));
        return;
    }
    const endpoint = app_cloudflare.UserTokenEndpoint.parse(args[1]) orelse {
        std.debug.print("unknown token command: {s}\n", .{args[1]});
        return;
    };
    if (endpoint.requiresTokenId()) {
        if (args.len < 3) {
            std.debug.print("token id required for token {s}\n", .{endpoint.commandName()});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectUserToken(appContext(ctx), args[2]));
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectUserTokenEndpoint(appContext(ctx), endpoint));
}

fn commandSetting(ctx: Context, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("setting id required\n", .{});
        return;
    }
    const domain = if (args.len > 2) args[2] else ctx.domains[0];
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_cloudflare.collectZoneSetting(appContext(ctx), domain, args[1]));
}

fn isKeyValue(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '=') != null;
}

fn applyEmailRoutingAccountFilter(args: *app_cloudflare.EmailRoutingAccountReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "verified")) {
        args.verified = value;
    } else {
        return false;
    }
    return true;
}

fn applyEmailRoutingZoneFilter(args: *app_cloudflare.EmailRoutingZoneReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "subdomain")) {
        args.subdomain = value;
    } else if (std.mem.eql(u8, key, "enabled")) {
        args.enabled = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else {
        return false;
    }
    return true;
}

fn applyEmailSecuritySettingsFilter(args: *app_cloudflare.EmailSecuritySettingsReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "active_delivery_mode") or std.mem.eql(u8, key, "active-delivery-mode")) {
        args.active_delivery_mode = value;
    } else if (std.mem.eql(u8, key, "allowed_delivery_mode") or std.mem.eql(u8, key, "allowed-delivery-mode")) {
        args.allowed_delivery_mode = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "domain")) {
        args.domain = value;
    } else if (std.mem.eql(u8, key, "integration_id") or std.mem.eql(u8, key, "integration-id")) {
        args.integration_id = value;
    } else if (std.mem.eql(u8, key, "is_acceptable_sender") or std.mem.eql(u8, key, "is-acceptable-sender")) {
        args.is_acceptable_sender = value;
    } else if (std.mem.eql(u8, key, "is_exempt_recipient") or std.mem.eql(u8, key, "is-exempt-recipient")) {
        args.is_exempt_recipient = value;
    } else if (std.mem.eql(u8, key, "is_recent") or std.mem.eql(u8, key, "is-recent")) {
        args.is_recent = value;
    } else if (std.mem.eql(u8, key, "is_similarity") or std.mem.eql(u8, key, "is-similarity")) {
        args.is_similarity = value;
    } else if (std.mem.eql(u8, key, "is_trusted_sender") or std.mem.eql(u8, key, "is-trusted-sender")) {
        args.is_trusted_sender = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "pattern")) {
        args.pattern = value;
    } else if (std.mem.eql(u8, key, "pattern_type") or std.mem.eql(u8, key, "pattern-type")) {
        args.pattern_type = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "provenance")) {
        args.provenance = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "verify_sender") or std.mem.eql(u8, key, "verify-sender")) {
        args.verify_sender = value;
    } else {
        return false;
    }
    return true;
}

fn applyZeroTrustReadFilter(args: *app_cloudflare.ZeroTrustReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "type") or std.mem.eql(u8, key, "list_type")) {
        args.list_type = value;
    } else if (std.mem.eql(u8, key, "email")) {
        args.email = value;
    } else if (std.mem.eql(u8, key, "name")) {
        args.name = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search = value;
    } else {
        return false;
    }
    return true;
}

fn applySecurityCenterReadFilter(args: *app_cloudflare.SecurityCenterReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "dismissed")) {
        args.dismissed = value;
    } else if (std.mem.eql(u8, key, "issue_class") or std.mem.eql(u8, key, "class")) {
        args.issue_class = value;
    } else if (std.mem.eql(u8, key, "issue_class~neq") or std.mem.eql(u8, key, "class!") or std.mem.eql(u8, key, "class_neq")) {
        args.issue_class_neq = value;
    } else if (std.mem.eql(u8, key, "issue_type") or std.mem.eql(u8, key, "type")) {
        args.issue_type = value;
    } else if (std.mem.eql(u8, key, "issue_type~neq") or std.mem.eql(u8, key, "type!") or std.mem.eql(u8, key, "type_neq")) {
        args.issue_type_neq = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "product")) {
        args.product = value;
    } else if (std.mem.eql(u8, key, "product~neq") or std.mem.eql(u8, key, "product!") or std.mem.eql(u8, key, "product_neq")) {
        args.product_neq = value;
    } else if (std.mem.eql(u8, key, "severity")) {
        args.severity = value;
    } else if (std.mem.eql(u8, key, "severity~neq") or std.mem.eql(u8, key, "severity!") or std.mem.eql(u8, key, "severity_neq")) {
        args.severity_neq = value;
    } else if (std.mem.eql(u8, key, "subject")) {
        args.subject = value;
    } else if (std.mem.eql(u8, key, "subject~neq") or std.mem.eql(u8, key, "subject!") or std.mem.eql(u8, key, "subject_neq")) {
        args.subject_neq = value;
    } else if (std.mem.eql(u8, key, "before")) {
        args.before = value;
    } else if (std.mem.eql(u8, key, "changed_by") or std.mem.eql(u8, key, "changed-by")) {
        args.changed_by = value;
    } else if (std.mem.eql(u8, key, "cursor")) {
        args.cursor = value;
    } else if (std.mem.eql(u8, key, "field_changed") or std.mem.eql(u8, key, "field-changed")) {
        args.field_changed = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "since")) {
        args.since = value;
    } else {
        return false;
    }
    return true;
}

fn applyAuditLogReadFilter(args: *app_cloudflare.AuditLogReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "since")) {
        args.since = value;
    } else if (std.mem.eql(u8, key, "before")) {
        args.before = value;
    } else if (std.mem.eql(u8, key, "cursor")) {
        args.cursor = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "id")) {
        args.id = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "actor_email") or std.mem.eql(u8, key, "actor.email")) {
        args.actor_email = value;
    } else if (std.mem.eql(u8, key, "actor_ip") or std.mem.eql(u8, key, "actor.ip") or std.mem.eql(u8, key, "actor_ip_address")) {
        args.actor_ip = value;
    } else if (std.mem.eql(u8, key, "action_type") or std.mem.eql(u8, key, "action.type")) {
        args.action_type = value;
    } else if (std.mem.eql(u8, key, "action_result")) {
        args.action_result = value;
    } else if (std.mem.eql(u8, key, "actor_id")) {
        args.actor_id = value;
    } else if (std.mem.eql(u8, key, "actor_type")) {
        args.actor_type = value;
    } else if (std.mem.eql(u8, key, "resource_id")) {
        args.resource_id = value;
    } else if (std.mem.eql(u8, key, "resource_product")) {
        args.resource_product = value;
    } else if (std.mem.eql(u8, key, "resource_type")) {
        args.resource_type = value;
    } else if (std.mem.eql(u8, key, "zone_id")) {
        args.zone_id = value;
    } else if (std.mem.eql(u8, key, "zone_name") or std.mem.eql(u8, key, "zone.name")) {
        args.zone_name = value;
    } else if (std.mem.eql(u8, key, "hide_user_logs") or std.mem.eql(u8, key, "hide-user-logs")) {
        args.hide_user_logs = value;
    } else if (std.mem.eql(u8, key, "export")) {
        args.export_format = value;
    } else {
        return false;
    }
    return true;
}

fn applyLogExplorerReadFilter(args: *app_cloudflare.LogExplorerReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "include_zones") or std.mem.eql(u8, key, "include-zones")) {
        args.include_zones = value;
    } else {
        return false;
    }
    return true;
}

fn applyLogsReceivedReadFilter(args: *app_cloudflare.LogsReceivedReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "start")) {
        args.start = value;
    } else if (std.mem.eql(u8, key, "end")) {
        args.end = value;
    } else if (std.mem.eql(u8, key, "count")) {
        args.count = value;
    } else if (std.mem.eql(u8, key, "fields")) {
        args.fields = value;
    } else if (std.mem.eql(u8, key, "sample")) {
        args.sample = value;
    } else if (std.mem.eql(u8, key, "timestamps")) {
        args.timestamps = value;
    } else {
        return false;
    }
    return true;
}

fn applyTlsReadFilter(args: *app_cloudflare.TlsReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "deploy")) {
        args.deploy = value;
    } else if (std.mem.eql(u8, key, "match")) {
        args.match = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "offset")) {
        args.offset = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "retry")) {
        args.retry = value;
    } else {
        return false;
    }
    return true;
}

fn applyCloudforceOneRuleFilter(args: *app_cloudflare.CloudforceOneRuleReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "namespace")) {
        args.namespace = value;
    } else if (std.mem.eql(u8, key, "recursive")) {
        args.recursive = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search_filter = value;
    } else if (std.mem.eql(u8, key, "is_public") or std.mem.eql(u8, key, "public")) {
        args.is_public = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "offset")) {
        args.offset = value;
    } else if (std.mem.eql(u8, key, "query")) {
        args.query = value;
    } else if (std.mem.eql(u8, key, "mode")) {
        args.mode = value;
    } else if (std.mem.eql(u8, key, "language")) {
        args.language = value;
    } else {
        return false;
    }
    return true;
}

fn applyIpAccessRuleFilter(args: *app_cloudflare.IpAccessRuleListArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "mode")) {
        args.mode = value;
    } else if (std.mem.eql(u8, key, "configuration.target") or std.mem.eql(u8, key, "target")) {
        args.configuration_target = value;
    } else if (std.mem.eql(u8, key, "configuration.value") or std.mem.eql(u8, key, "value")) {
        args.configuration_value = value;
    } else if (std.mem.eql(u8, key, "notes")) {
        args.notes = value;
    } else if (std.mem.eql(u8, key, "match")) {
        args.match = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else {
        return false;
    }
    return true;
}

fn applyPageShieldFilter(args: *app_cloudflare.PageShieldReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "exclude_urls") or std.mem.eql(u8, key, "exclude-urls")) {
        args.exclude_urls = value;
    } else if (std.mem.eql(u8, key, "urls")) {
        args.urls = value;
    } else if (std.mem.eql(u8, key, "hosts")) {
        args.hosts = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "order_by") or std.mem.eql(u8, key, "order-by")) {
        args.order_by = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "prioritize_malicious") or std.mem.eql(u8, key, "prioritize-malicious")) {
        args.prioritize_malicious = value;
    } else if (std.mem.eql(u8, key, "exclude_cdn_cgi") or std.mem.eql(u8, key, "exclude-cdn-cgi")) {
        args.exclude_cdn_cgi = value;
    } else if (std.mem.eql(u8, key, "exclude_duplicates") or std.mem.eql(u8, key, "exclude-duplicates")) {
        args.exclude_duplicates = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "page_url") or std.mem.eql(u8, key, "page-url")) {
        args.page_url = value;
    } else if (std.mem.eql(u8, key, "export")) {
        args.export_format = value;
    } else if (std.mem.eql(u8, key, "name")) {
        args.name = value;
    } else if (std.mem.eql(u8, key, "secure")) {
        args.secure = value;
    } else if (std.mem.eql(u8, key, "http_only") or std.mem.eql(u8, key, "http-only")) {
        args.http_only = value;
    } else if (std.mem.eql(u8, key, "same_site") or std.mem.eql(u8, key, "same-site")) {
        args.same_site = value;
    } else if (std.mem.eql(u8, key, "type")) {
        args.type_filter = value;
    } else if (std.mem.eql(u8, key, "path")) {
        args.path_filter = value;
    } else if (std.mem.eql(u8, key, "domain")) {
        args.domain = value;
    } else {
        return false;
    }
    return true;
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

test "cloudflare domain commands use explicit or default domain" {
    const configured = [_][]const u8{ "plosca.ru", "example.com" };
    const zone_default = [_][]const u8{"zone"};
    try std.testing.expectEqualStrings("plosca.ru", app_cloudflare.selectedDomain(configured[0..], zone_default[0..]));

    const zone_explicit = [_][]const u8{ "zone", "example.net" };
    try std.testing.expectEqualStrings("example.net", app_cloudflare.selectedDomain(configured[0..], zone_explicit[0..]));
}

test "cloudforce one rule filters parse key value arguments" {
    var args: app_cloudflare.CloudforceOneRuleReadArgs = .{};
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "namespace=yara/workers"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "recursive=true"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "search=malicious"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "public=false"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "limit=25"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "offset=10"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "query=proxy worker"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "mode=hybrid"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "language=yara"));
    try std.testing.expect(!applyCloudforceOneRuleFilter(&args, "unknown=value"));
    try std.testing.expect(!applyCloudforceOneRuleFilter(&args, "namespace"));
    try std.testing.expectEqualStrings("yara/workers", args.namespace.?);
    try std.testing.expectEqualStrings("malicious", args.search_filter.?);
    try std.testing.expectEqualStrings("proxy worker", args.query.?);
}

test "email routing filters parse key value arguments" {
    var account_args: app_cloudflare.EmailRoutingAccountReadArgs = .{};
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "direction=desc"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "page=2"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "per-page=50"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "verified=true"));
    try std.testing.expect(!applyEmailRoutingAccountFilter(&account_args, "unknown=value"));
    try std.testing.expect(!applyEmailRoutingAccountFilter(&account_args, "verified"));
    try std.testing.expectEqualStrings("desc", account_args.direction.?);
    try std.testing.expectEqualStrings("50", account_args.per_page.?);

    var zone_args: app_cloudflare.EmailRoutingZoneReadArgs = .{};
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "subdomain=mail.example.test"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "enabled=false"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "page=3"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "per_page=100"));
    try std.testing.expect(!applyEmailRoutingZoneFilter(&zone_args, "unknown=value"));
    try std.testing.expect(!applyEmailRoutingZoneFilter(&zone_args, "enabled"));
    try std.testing.expectEqualStrings("mail.example.test", zone_args.subdomain.?);
    try std.testing.expectEqualStrings("false", zone_args.enabled.?);
}

test "email security settings filters parse key value arguments" {
    var args: app_cloudflare.EmailSecuritySettingsReadArgs = .{};
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "active-delivery-mode=DIRECT"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "allowed_delivery_mode=API"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "direction=desc"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "domain=plosca.ru"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "integration-id=abc"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-acceptable-sender=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is_exempt_recipient=false"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-recent=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is_similarity=false"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-trusted-sender=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "order=pattern"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "page=2"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "pattern=example.com"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "pattern-type=DOMAIN"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "per-page=50"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "provenance=AUTO"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "search=partner"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "status=active"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "verify-sender=true"));
    try std.testing.expect(!applyEmailSecuritySettingsFilter(&args, "unknown=value"));
    try std.testing.expect(!applyEmailSecuritySettingsFilter(&args, "search"));
    try std.testing.expectEqualStrings("DIRECT", args.active_delivery_mode.?);
    try std.testing.expectEqualStrings("API", args.allowed_delivery_mode.?);
    try std.testing.expectEqualStrings("DOMAIN", args.pattern_type.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("true", args.verify_sender.?);
}

test "zero trust read filters parse key value arguments" {
    var args: app_cloudflare.ZeroTrustReadArgs = .{};
    try std.testing.expect(applyZeroTrustReadFilter(&args, "type=SERIAL"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "email=admin@example.test"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "name=Admin User"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "page=2"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "per-page=50"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "search=admin"));
    try std.testing.expect(!applyZeroTrustReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyZeroTrustReadFilter(&args, "search"));
    try std.testing.expectEqualStrings("SERIAL", args.list_type.?);
    try std.testing.expectEqualStrings("admin@example.test", args.email.?);
    try std.testing.expectEqualStrings("Admin User", args.name.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("admin", args.search.?);
}

test "security center read filters parse key value arguments" {
    var args: app_cloudflare.SecurityCenterReadArgs = .{};
    try std.testing.expect(applySecurityCenterReadFilter(&args, "dismissed=false"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "class=compliance"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "class!=informational"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "type=weak_tls"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "product=waf"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "severity=critical"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "subject=plosca.ru"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "per-page=50"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "changed-by=system"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "field-changed=status"));
    try std.testing.expect(!applySecurityCenterReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applySecurityCenterReadFilter(&args, "severity"));
    try std.testing.expectEqualStrings("false", args.dismissed.?);
    try std.testing.expectEqualStrings("compliance", args.issue_class.?);
    try std.testing.expectEqualStrings("informational", args.issue_class_neq.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("system", args.changed_by.?);
}

test "audit log read filters parse key value arguments" {
    var args: app_cloudflare.AuditLogReadArgs = .{};
    try std.testing.expect(applyAuditLogReadFilter(&args, "since=2026-06-01T00:00:00Z"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "before=2026-06-17T00:00:00Z"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "actor.email=admin@example.test"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "actor_ip_address=198.51.100.2"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "action.type=edit"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "resource_id=zone/1"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "zone.name=plosca.ru"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "hide-user-logs=true"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "per-page=25"));
    try std.testing.expect(!applyAuditLogReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyAuditLogReadFilter(&args, "since"));
    try std.testing.expectEqualStrings("admin@example.test", args.actor_email.?);
    try std.testing.expectEqualStrings("198.51.100.2", args.actor_ip.?);
    try std.testing.expectEqualStrings("edit", args.action_type.?);
    try std.testing.expectEqualStrings("zone/1", args.resource_id.?);
    try std.testing.expectEqualStrings("true", args.hide_user_logs.?);
}

test "log explorer and logs received filters parse key value arguments" {
    var explorer_args: app_cloudflare.LogExplorerReadArgs = .{};
    try std.testing.expect(applyLogExplorerReadFilter(&explorer_args, "include-zones=true"));
    try std.testing.expect(!applyLogExplorerReadFilter(&explorer_args, "unknown=value"));
    try std.testing.expect(!applyLogExplorerReadFilter(&explorer_args, "include-zones"));
    try std.testing.expectEqualStrings("true", explorer_args.include_zones.?);

    var received_args: app_cloudflare.LogsReceivedReadArgs = .{};
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "start=2026-06-17T00:00:00Z"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "end=2026-06-17T01:00:00Z"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "count=true"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "fields=ClientIP,EdgeStartTimestamp"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "sample=0.1"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "timestamps=rfc3339"));
    try std.testing.expect(!applyLogsReceivedReadFilter(&received_args, "unknown=value"));
    try std.testing.expect(!applyLogsReceivedReadFilter(&received_args, "start"));
    try std.testing.expectEqualStrings("2026-06-17T00:00:00Z", received_args.start.?);
    try std.testing.expectEqualStrings("2026-06-17T01:00:00Z", received_args.end.?);
    try std.testing.expectEqualStrings("true", received_args.count.?);
    try std.testing.expectEqualStrings("ClientIP,EdgeStartTimestamp", received_args.fields.?);
    try std.testing.expectEqualStrings("rfc3339", received_args.timestamps.?);
}

test "tls read filters parse key value arguments" {
    var args: app_cloudflare.TlsReadArgs = .{};
    try std.testing.expect(applyTlsReadFilter(&args, "deploy=true"));
    try std.testing.expect(applyTlsReadFilter(&args, "match=plosca.ru"));
    try std.testing.expect(applyTlsReadFilter(&args, "status=active"));
    try std.testing.expect(applyTlsReadFilter(&args, "limit=10"));
    try std.testing.expect(applyTlsReadFilter(&args, "offset=20"));
    try std.testing.expect(applyTlsReadFilter(&args, "page=2"));
    try std.testing.expect(applyTlsReadFilter(&args, "per-page=50"));
    try std.testing.expect(applyTlsReadFilter(&args, "retry=false"));
    try std.testing.expect(!applyTlsReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyTlsReadFilter(&args, "status"));
    try std.testing.expectEqualStrings("true", args.deploy.?);
    try std.testing.expectEqualStrings("plosca.ru", args.match.?);
    try std.testing.expectEqualStrings("active", args.status.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("false", args.retry.?);
}

test "ip access rule filters parse key value arguments" {
    var args: app_cloudflare.IpAccessRuleListArgs = .{};
    try std.testing.expect(applyIpAccessRuleFilter(&args, "mode=block"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "target=ip"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "value=198.51.100.4"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "notes=attack"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "match=all"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "page=2"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "per-page=50"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "order=mode"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "direction=desc"));
    try std.testing.expect(!applyIpAccessRuleFilter(&args, "unknown=value"));
    try std.testing.expect(!applyIpAccessRuleFilter(&args, "mode"));
    try std.testing.expectEqualStrings("block", args.mode.?);
    try std.testing.expectEqualStrings("ip", args.configuration_target.?);
    try std.testing.expectEqualStrings("198.51.100.4", args.configuration_value.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
}

test "page shield filters parse key value arguments" {
    var args: app_cloudflare.PageShieldReadArgs = .{};
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-urls=https://example.com/a.js"));
    try std.testing.expect(applyPageShieldFilter(&args, "urls=https://cdn.example.com/app.js"));
    try std.testing.expect(applyPageShieldFilter(&args, "hosts=cdn.example.com"));
    try std.testing.expect(applyPageShieldFilter(&args, "page=all"));
    try std.testing.expect(applyPageShieldFilter(&args, "per-page=50"));
    try std.testing.expect(applyPageShieldFilter(&args, "order-by=last_seen_at"));
    try std.testing.expect(applyPageShieldFilter(&args, "direction=desc"));
    try std.testing.expect(applyPageShieldFilter(&args, "prioritize-malicious=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-cdn-cgi=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-duplicates=false"));
    try std.testing.expect(applyPageShieldFilter(&args, "status=active"));
    try std.testing.expect(applyPageShieldFilter(&args, "page-url=https://example.com/checkout"));
    try std.testing.expect(applyPageShieldFilter(&args, "export=csv"));
    try std.testing.expect(applyPageShieldFilter(&args, "name=session"));
    try std.testing.expect(applyPageShieldFilter(&args, "secure=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "http-only=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "same-site=lax"));
    try std.testing.expect(applyPageShieldFilter(&args, "type=first_party"));
    try std.testing.expect(applyPageShieldFilter(&args, "path=/"));
    try std.testing.expect(applyPageShieldFilter(&args, "domain=example.com"));
    try std.testing.expect(!applyPageShieldFilter(&args, "unknown=value"));
    try std.testing.expect(!applyPageShieldFilter(&args, "hosts"));
    try std.testing.expectEqualStrings("cdn.example.com", args.hosts.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("last_seen_at", args.order_by.?);
    try std.testing.expectEqualStrings("true", args.exclude_cdn_cgi.?);
    try std.testing.expectEqualStrings("session", args.name.?);
    try std.testing.expectEqualStrings("first_party", args.type_filter.?);
}
