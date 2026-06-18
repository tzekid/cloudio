const std = @import("std");
const app_hostinger = @import("app_hostinger");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    token: ?[]const u8,
    domains: []const []const u8,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("hostinger subcommand required\n", .{});
        return;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "vps")) {
        if (args.len > 1 and isVpsOverviewCommand(args[1])) return try commandVpsOverview(ctx, args[2..]);
        switch (parseVpsSelection(args[1..])) {
            .list => try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectVps(appContext(ctx))),
            .detail => |vm_id| try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectVpsDetails(appContext(ctx), vm_id)),
            .missing_id => std.debug.print("vm id required\n", .{}),
        }
    } else if (std.mem.eql(u8, sub, "dry-run")) {
        try commandDryRun(ctx, args);
    } else if (std.mem.eql(u8, sub, "metrics")) {
        try commandVmEndpoint(ctx, args, .metrics);
    } else if (std.mem.eql(u8, sub, "actions")) {
        try commandVmEndpoint(ctx, args, .actions);
    } else if (std.mem.eql(u8, sub, "action")) {
        try commandActionDetails(ctx, args);
    } else if (std.mem.eql(u8, sub, "security")) {
        try commandVmEndpoint(ctx, args, .monarx);
    } else if (isVpsOverviewCommand(sub)) {
        try commandVpsOverview(ctx, args[1..]);
    } else if (std.mem.eql(u8, sub, "inventory")) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.listInventoryItems(appContext(ctx)));
    } else if (std.mem.eql(u8, sub, "resources")) {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.listResources(appContext(ctx)));
    } else if (app_hostinger.BillingEndpoint.parse(sub)) |endpoint| {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectBillingEndpoint(appContext(ctx), endpoint));
    } else if (app_hostinger.DnsEndpoint.parse(sub)) |endpoint| {
        try commandDns(ctx, args, endpoint);
    } else if (app_hostinger.DomainEndpoint.parse(sub)) |endpoint| {
        try commandDomain(ctx, args, endpoint);
    } else if (app_hostinger.HostingEndpoint.parse(sub)) |endpoint| {
        try commandHosting(ctx, args, endpoint);
    } else if (app_hostinger.EcommerceEndpoint.parse(sub)) |endpoint| {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectEcommerceEndpoint(appContext(ctx), endpoint));
    } else if (app_hostinger.HorizonsEndpoint.parse(sub)) |endpoint| {
        try commandHorizons(ctx, args, endpoint);
    } else if (app_hostinger.ReachEndpoint.parse(sub)) |endpoint| {
        try commandReach(ctx, args, endpoint);
    } else if (app_hostinger.DockerEndpoint.parse(sub)) |endpoint| {
        try commandDocker(ctx, args, endpoint);
    } else if (app_hostinger.VpsInventoryDetailEndpoint.parse(sub)) |endpoint| {
        try commandInventoryDetail(ctx, args, endpoint);
    } else if (app_hostinger.VpsInventoryEndpoint.parse(sub)) |endpoint| {
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectVpsInventoryEndpoint(appContext(ctx), endpoint));
    } else {
        std.debug.print("unknown hostinger command: {s}\n", .{sub});
    }
}

const VpsSelection = union(enum) {
    list,
    detail: []const u8,
    missing_id,
};

const VpsOverviewParsed = struct {
    options: app_hostinger.VpsOverviewOptions = .{},
    format: cli_render.RenderFormat = .text,
};

fn parseVpsSelection(args: []const []const u8) VpsSelection {
    if (args.len == 0) return .list;
    if (std.mem.eql(u8, args[0], "list")) return .list;
    if (std.mem.eql(u8, args[0], "show")) {
        if (args.len < 2) return .missing_id;
        return .{ .detail = args[1] };
    }
    return .{ .detail = args[0] };
}

fn commandVpsOverview(ctx: Context, args: []const []const u8) !void {
    const parsed = parseVpsOverviewArgs(args) catch |err| {
        std.debug.print("invalid hostinger vps overview command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_hostinger.writeVpsOverviewText, app_hostinger.writeVpsOverviewJson, .{ appContext(ctx), parsed.options });
}

fn parseVpsOverviewArgs(args: []const []const u8) !VpsOverviewParsed {
    var parsed = VpsOverviewParsed{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        switch (cli_render.parseFormatArg(args, &i)) {
            .matched => |format| {
                parsed.format = format;
                continue;
            },
            .missing_value => return error.MissingFormat,
            .invalid_value => return error.InvalidFormat,
            .no_match => {},
        }
        if (try cli_args.parsePositiveI64Arg(args, &i, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return parsed;
}

fn isVpsOverviewCommand(value: []const u8) bool {
    return std.mem.eql(u8, value, "overview") or std.mem.eql(u8, value, "summary") or std.mem.eql(u8, value, "vps-overview");
}

fn commandVmEndpoint(ctx: Context, args: []const []const u8, endpoint: app_hostinger.VmEndpoint) !void {
    if (args.len < 2) {
        std.debug.print("vm id required\n", .{});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectVmEndpoint(appContext(ctx), args[1], endpoint));
}

fn commandActionDetails(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("vm id and action id required\n", .{});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectActionDetails(appContext(ctx), args[1], args[2]));
}

fn commandDryRun(ctx: Context, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("dry-run target and operation required\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "vps")) return try commandDryRunVps(ctx, args);
    if (std.mem.eql(u8, args[1], "firewall")) return try commandDryRunFirewall(ctx, args);
    if (std.mem.eql(u8, args[1], "docker")) return try commandDryRunDocker(ctx, args);
    if (isVpsResourceDryRunTarget(args[1])) return try commandDryRunVpsResource(ctx, args);
    if (std.mem.eql(u8, args[1], "dns")) return try commandDryRunDns(ctx, args);
    if (std.mem.eql(u8, args[1], "billing")) return try commandDryRunBilling(ctx, args);
    if (std.mem.eql(u8, args[1], "domain") or std.mem.eql(u8, args[1], "domains")) return try commandDryRunDomain(ctx, args);
    if (std.mem.eql(u8, args[1], "hosting")) return try commandDryRunHosting(ctx, args);
    if (std.mem.eql(u8, args[1], "ecommerce")) return try commandDryRunEcommerce(ctx, args);
    if (std.mem.eql(u8, args[1], "horizons")) return try commandDryRunHorizons(ctx, args);
    if (std.mem.eql(u8, args[1], "reach")) return try commandDryRunReach(ctx, args);
    std.debug.print("unknown dry-run target: {s}\n", .{args[1]});
}

fn isVpsResourceDryRunTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "public-key") or
        std.mem.eql(u8, target, "public-keys") or
        std.mem.eql(u8, target, "post-install-script") or
        std.mem.eql(u8, target, "post-install-scripts") or
        std.mem.eql(u8, target, "post-install");
}

fn commandDryRunVps(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.VpsMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown vps dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresVmId() and args.len < 4) {
        std.debug.print("vm id required for dry-run vps {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresIpAddressId() and args.len < 5) {
        std.debug.print("ip address id required for dry-run vps {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresBackupId() and args.len < 5) {
        std.debug.print("backup id required for dry-run vps {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.VpsMutationArgs = .{
        .vm_id = if (endpoint.requiresVmId()) args[3] else null,
        .ip_address_id = if (endpoint.requiresIpAddressId()) args[4] else null,
        .backup_id = if (endpoint.requiresBackupId()) args[4] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planVpsMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunFirewall(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.FirewallMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown firewall dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresFirewallId() and args.len < 4) {
        std.debug.print("firewall id required for dry-run firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresVmId() and args.len < 5) {
        std.debug.print("vm id required for dry-run firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresRuleId() and args.len < 5) {
        std.debug.print("rule id required for dry-run firewall {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.FirewallMutationArgs = .{
        .firewall_id = if (endpoint.requiresFirewallId()) args[3] else null,
        .vm_id = if (endpoint.requiresVmId()) args[4] else null,
        .rule_id = if (endpoint.requiresRuleId()) args[4] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planFirewallMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunDocker(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.DockerMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown docker dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("vm id required for dry-run docker {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresProject() and args.len < 5) {
        std.debug.print("docker project name required for dry-run docker {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.DockerMutationArgs = .{
        .vm_id = args[3],
        .project_name = if (endpoint.requiresProject()) args[4] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planDockerMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunVpsResource(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.VpsResourceMutationEndpoint.parseScoped(args[1], args[2]) orelse {
        std.debug.print("unknown {s} dry-run operation: {s}\n", .{ args[1], args[2] });
        return;
    };
    if (endpoint.requiresPublicKeyId() and args.len < 4) {
        std.debug.print("public key id required for dry-run {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresPostInstallScriptId() and args.len < 4) {
        std.debug.print("post-install script id required for dry-run {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresVmId() and args.len < 4) {
        std.debug.print("vm id required for dry-run {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.VpsResourceMutationArgs = .{
        .public_key_id = if (endpoint.requiresPublicKeyId()) args[3] else null,
        .post_install_script_id = if (endpoint.requiresPostInstallScriptId()) args[3] else null,
        .vm_id = if (endpoint.requiresVmId()) args[3] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planVpsResourceMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunDns(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.DnsMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown dns dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (args.len < 4) {
        std.debug.print("domain required for dry-run dns {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresSnapshotId() and args.len < 5) {
        std.debug.print("snapshot id required for dry-run dns {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.DnsMutationArgs = .{
        .domain = args[3],
        .snapshot_id = if (endpoint.requiresSnapshotId()) args[4] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planDnsMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunBilling(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.BillingMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown billing dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresPaymentMethodId() and args.len < 4) {
        std.debug.print("payment method id required for dry-run billing {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresSubscriptionId() and args.len < 4) {
        std.debug.print("subscription id required for dry-run billing {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.BillingMutationArgs = .{
        .payment_method_id = if (endpoint.requiresPaymentMethodId()) args[3] else null,
        .subscription_id = if (endpoint.requiresSubscriptionId()) args[3] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planBillingMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunDomain(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.DomainMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown domain dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresDomain() and args.len < 4) {
        std.debug.print("domain required for dry-run domain {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresWhoisId() and args.len < 4) {
        std.debug.print("whois id required for dry-run domain {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.DomainMutationArgs = .{
        .domain = if (endpoint.requiresDomain()) args[3] else null,
        .whois_id = if (endpoint.requiresWhoisId()) args[3] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planDomainMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunHosting(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.HostingMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown hosting dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresUsername() and args.len < 4) {
        std.debug.print("username required for dry-run hosting {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresDomain() and args.len < 5) {
        std.debug.print("domain required for dry-run hosting {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresDatabaseName() and args.len < 5) {
        std.debug.print("database name required for dry-run hosting {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresParkedDomain() and args.len < 6) {
        std.debug.print("parked domain required for dry-run hosting {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresSubdomain() and args.len < 6) {
        std.debug.print("subdomain required for dry-run hosting {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.HostingMutationArgs = .{
        .username = if (endpoint.requiresUsername()) args[3] else null,
        .domain = if (endpoint.requiresDomain()) args[4] else null,
        .database_name = if (endpoint.requiresDatabaseName()) args[4] else null,
        .parked_domain = if (endpoint.requiresParkedDomain()) args[5] else null,
        .subdomain = if (endpoint.requiresSubdomain()) args[5] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planHostingMutation(appContext(ctx), endpoint, plan_args));
}

fn commandDryRunEcommerce(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.EcommerceMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown ecommerce dry-run operation: {s}\n", .{args[2]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planEcommerceMutation(appContext(ctx), endpoint));
}

fn commandDryRunHorizons(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.HorizonsMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown horizons dry-run operation: {s}\n", .{args[2]});
        return;
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planHorizonsMutation(appContext(ctx), endpoint));
}

fn commandDryRunReach(ctx: Context, args: []const []const u8) !void {
    const endpoint = app_hostinger.ReachMutationEndpoint.parse(args[2]) orelse {
        std.debug.print("unknown reach dry-run operation: {s}\n", .{args[2]});
        return;
    };
    if (endpoint.requiresContactUuid() and args.len < 4) {
        std.debug.print("contact uuid required for dry-run reach {s}\n", .{endpoint.commandName()});
        return;
    }
    if (endpoint.requiresProfileUuid() and args.len < 4) {
        std.debug.print("profile uuid required for dry-run reach {s}\n", .{endpoint.commandName()});
        return;
    }
    const plan_args: app_hostinger.ReachMutationArgs = .{
        .contact_uuid = if (endpoint.requiresContactUuid()) args[3] else null,
        .profile_uuid = if (endpoint.requiresProfileUuid()) args[3] else null,
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.planReachMutation(appContext(ctx), endpoint, plan_args));
}

fn commandInventoryDetail(ctx: Context, args: []const []const u8, endpoint: app_hostinger.VpsInventoryDetailEndpoint) !void {
    if (args.len < 2) {
        std.debug.print("{s} required\n", .{endpoint.idName()});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectVpsInventoryDetail(appContext(ctx), endpoint, args[1]));
}

fn commandDocker(ctx: Context, args: []const []const u8, endpoint: app_hostinger.DockerEndpoint) !void {
    if (args.len < 2) {
        std.debug.print("vm id required\n", .{});
        return;
    }
    if (endpoint.requiresProject() and args.len < 3) {
        std.debug.print("docker project name required\n", .{});
        return;
    }
    const project_name: ?[]const u8 = if (endpoint.requiresProject()) args[2] else null;
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDockerEndpoint(appContext(ctx), args[1], endpoint, project_name));
}

fn commandDns(ctx: Context, args: []const []const u8, endpoint: app_hostinger.DnsEndpoint) !void {
    if (endpoint.requiresSnapshotId()) {
        if (args.len < 3) {
            std.debug.print("domain and snapshot id required\n", .{});
            return;
        }
        try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDnsEndpoint(appContext(ctx), endpoint, args[1], args[2]));
        return;
    }
    const domain = if (args.len > 1) args[1] else ctx.domains[0];
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDnsEndpoint(appContext(ctx), endpoint, domain, null));
}

fn commandDomain(ctx: Context, args: []const []const u8, endpoint: app_hostinger.DomainEndpoint) !void {
    switch (endpoint) {
        .portfolio => try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDomainEndpoint(appContext(ctx), endpoint, null, null)),
        .portfolio_detail, .forwarding => {
            const domain = if (args.len > 1) args[1] else ctx.domains[0];
            try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDomainEndpoint(appContext(ctx), endpoint, domain, null));
        },
        .whois_profiles => {
            const tld: ?[]const u8 = if (args.len > 1) args[1] else null;
            try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDomainEndpoint(appContext(ctx), endpoint, null, tld));
        },
        .whois_profile, .whois_usage => {
            if (args.len < 2) {
                std.debug.print("{s} required\n", .{endpoint.pathArgName() orelse "argument"});
                return;
            }
            try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectDomainEndpoint(appContext(ctx), endpoint, args[1], null));
        },
    }
}

fn commandHosting(ctx: Context, args: []const []const u8, endpoint: app_hostinger.HostingEndpoint) !void {
    const hosting_args: app_hostinger.HostingArgs = switch (endpoint) {
        .orders, .websites, .wordpress => .{},
        .datacenters => blk: {
            if (args.len < 2) {
                std.debug.print("order id required\n", .{});
                return;
            }
            break :blk .{ .order_id = args[1] };
        },
        .databases => blk: {
            if (args.len < 2) {
                std.debug.print("username required\n", .{});
                return;
            }
            break :blk .{ .username = args[1] };
        },
        .phpmyadmin_link => blk: {
            if (args.len < 3) {
                std.debug.print("username and database required\n", .{});
                return;
            }
            break :blk .{ .username = args[1], .name = args[2] };
        },
        .parked_domains, .subdomains, .nodejs_builds => blk: {
            if (args.len < 3) {
                std.debug.print("username and domain required\n", .{});
                return;
            }
            break :blk .{ .username = args[1], .domain = args[2] };
        },
        .nodejs_logs => blk: {
            if (args.len < 4) {
                std.debug.print("username, domain, and build uuid required\n", .{});
                return;
            }
            break :blk .{ .username = args[1], .domain = args[2], .uuid = args[3], .from_line = if (args.len > 4) args[4] else null };
        },
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectHostingEndpoint(appContext(ctx), endpoint, hosting_args));
}

fn commandHorizons(ctx: Context, args: []const []const u8, endpoint: app_hostinger.HorizonsEndpoint) !void {
    if (args.len < 2) {
        std.debug.print("website id required\n", .{});
        return;
    }
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectHorizonsEndpoint(appContext(ctx), endpoint, args[1]));
}

fn commandReach(ctx: Context, args: []const []const u8, endpoint: app_hostinger.ReachEndpoint) !void {
    const reach_args: app_hostinger.ReachArgs = switch (endpoint) {
        .contacts, .profiles, .segments => .{},
        .segment, .segment_contacts => blk: {
            if (args.len < 2) {
                std.debug.print("segment uuid required\n", .{});
                return;
            }
            break :blk .{ .segment_uuid = args[1] };
        },
        .profile_segment_contacts => blk: {
            if (args.len < 3) {
                std.debug.print("profile uuid and segment uuid required\n", .{});
                return;
            }
            break :blk .{ .profile_uuid = args[1], .segment_uuid = args[2] };
        },
    };
    try cli_render.printOutput(ctx.io, ctx.gpa, try app_hostinger.collectReachEndpoint(appContext(ctx), endpoint, reach_args));
}

fn appContext(ctx: Context) app_hostinger.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .token = ctx.token,
        .domains = ctx.domains,
        .db = ctx.db,
    };
}

test "hostinger vps command accepts list and show aliases" {
    const no_args = [_][]const u8{};
    switch (parseVpsSelection(no_args[0..])) {
        .list => {},
        else => return error.ExpectedVpsList,
    }

    const list_args = [_][]const u8{"list"};
    switch (parseVpsSelection(list_args[0..])) {
        .list => {},
        else => return error.ExpectedVpsList,
    }

    const legacy_detail_args = [_][]const u8{"12345"};
    switch (parseVpsSelection(legacy_detail_args[0..])) {
        .detail => |vm_id| try std.testing.expectEqualStrings("12345", vm_id),
        else => return error.ExpectedVpsDetail,
    }

    const show_args = [_][]const u8{ "show", "12345" };
    switch (parseVpsSelection(show_args[0..])) {
        .detail => |vm_id| try std.testing.expectEqualStrings("12345", vm_id),
        else => return error.ExpectedVpsDetail,
    }

    const missing_show_args = [_][]const u8{"show"};
    switch (parseVpsSelection(missing_show_args[0..])) {
        .missing_id => {},
        else => return error.ExpectedMissingVpsId,
    }
}

test "hostinger vps overview parser accepts format and limit" {
    const default_args = [_][]const u8{};
    const defaults = try parseVpsOverviewArgs(default_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);
    try std.testing.expectEqual(@as(i64, 20), defaults.options.limit);

    const args = [_][]const u8{ "--json", "--limit=5" };
    const parsed = try parseVpsOverviewArgs(args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqual(@as(i64, 5), parsed.options.limit);

    const split_args = [_][]const u8{ "--format", "json", "--limit", "3" };
    const split = try parseVpsOverviewArgs(split_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, split.format);
    try std.testing.expectEqual(@as(i64, 3), split.options.limit);
}

test "hostinger vps overview parser rejects invalid values" {
    const missing_limit = [_][]const u8{"--limit"};
    try std.testing.expectError(error.MissingLimit, parseVpsOverviewArgs(missing_limit[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidLimit, parseVpsOverviewArgs(invalid_limit[0..]));

    const invalid_format = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(error.InvalidFormat, parseVpsOverviewArgs(invalid_format[0..]));

    const extra = [_][]const u8{"unexpected"};
    try std.testing.expectError(error.UnexpectedArgument, parseVpsOverviewArgs(extra[0..]));
}
