const std = @import("std");
const collector_hostinger = @import("collector_hostinger");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_hostinger = @import("provider_hostinger");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Output = core_output.Output;
pub const VmEndpoint = collector_hostinger.VmEndpoint;
pub const VpsMutationEndpoint = provider_hostinger.VpsMutationEndpoint;
pub const VpsMutationArgs = provider_hostinger.VpsMutationArgs;
pub const VpsInventoryEndpoint = collector_hostinger.VpsInventoryEndpoint;
pub const VpsInventoryDetailEndpoint = collector_hostinger.VpsInventoryDetailEndpoint;
pub const VpsResourceMutationEndpoint = provider_hostinger.VpsResourceMutationEndpoint;
pub const VpsResourceMutationArgs = provider_hostinger.VpsResourceMutationArgs;
pub const FirewallMutationEndpoint = provider_hostinger.FirewallMutationEndpoint;
pub const FirewallMutationArgs = provider_hostinger.FirewallMutationArgs;
pub const DockerEndpoint = collector_hostinger.DockerEndpoint;
pub const DockerMutationEndpoint = provider_hostinger.DockerMutationEndpoint;
pub const DockerMutationArgs = provider_hostinger.DockerMutationArgs;
pub const BillingEndpoint = collector_hostinger.BillingEndpoint;
pub const BillingMutationEndpoint = provider_hostinger.BillingMutationEndpoint;
pub const BillingMutationArgs = provider_hostinger.BillingMutationArgs;
pub const DnsEndpoint = collector_hostinger.DnsEndpoint;
pub const DnsMutationEndpoint = provider_hostinger.DnsMutationEndpoint;
pub const DnsMutationArgs = provider_hostinger.DnsMutationArgs;
pub const DomainEndpoint = collector_hostinger.DomainEndpoint;
pub const DomainMutationEndpoint = provider_hostinger.DomainMutationEndpoint;
pub const DomainMutationArgs = provider_hostinger.DomainMutationArgs;
pub const HostingEndpoint = collector_hostinger.HostingEndpoint;
pub const HostingArgs = collector_hostinger.HostingArgs;
pub const HostingMutationEndpoint = provider_hostinger.HostingMutationEndpoint;
pub const HostingMutationArgs = provider_hostinger.HostingMutationArgs;
pub const EcommerceEndpoint = collector_hostinger.EcommerceEndpoint;
pub const EcommerceMutationEndpoint = provider_hostinger.EcommerceMutationEndpoint;
pub const HorizonsEndpoint = collector_hostinger.HorizonsEndpoint;
pub const HorizonsMutationEndpoint = provider_hostinger.HorizonsMutationEndpoint;
pub const ReachEndpoint = collector_hostinger.ReachEndpoint;
pub const ReachArgs = collector_hostinger.ReachArgs;
pub const ReachMutationEndpoint = provider_hostinger.ReachMutationEndpoint;
pub const ReachMutationArgs = provider_hostinger.ReachMutationArgs;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    token: ?[]const u8,
    domains: []const []const u8,
    db: *Db,
};

pub fn collectVps(ctx: Context) !Output {
    return try collector_hostinger.collectVps(ctx.io, ctx.gpa, ctx.token, ctx.db, true);
}

pub fn collectVpsDetails(ctx: Context, vm_id: []const u8) !Output {
    return try collector_hostinger.collectVpsDetails(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, true);
}

pub fn collectVmEndpoint(ctx: Context, vm_id: []const u8, endpoint: VmEndpoint) !Output {
    return try collector_hostinger.collectVmEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, endpoint, true);
}

pub fn collectActionDetails(ctx: Context, vm_id: []const u8, action_id: []const u8) !Output {
    return try collector_hostinger.collectActionDetails(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, action_id, true);
}

pub fn planVpsMutation(ctx: Context, endpoint: VpsMutationEndpoint, args: VpsMutationArgs) !Output {
    return .{ .text = try provider_hostinger.vpsMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planFirewallMutation(ctx: Context, endpoint: FirewallMutationEndpoint, args: FirewallMutationArgs) !Output {
    return .{ .text = try provider_hostinger.firewallMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planVpsResourceMutation(ctx: Context, endpoint: VpsResourceMutationEndpoint, args: VpsResourceMutationArgs) !Output {
    return .{ .text = try provider_hostinger.vpsResourceMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDockerMutation(ctx: Context, endpoint: DockerMutationEndpoint, args: DockerMutationArgs) !Output {
    return .{ .text = try provider_hostinger.dockerMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDnsMutation(ctx: Context, endpoint: DnsMutationEndpoint, args: DnsMutationArgs) !Output {
    return .{ .text = try provider_hostinger.dnsMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planBillingMutation(ctx: Context, endpoint: BillingMutationEndpoint, args: BillingMutationArgs) !Output {
    return .{ .text = try provider_hostinger.billingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planDomainMutation(ctx: Context, endpoint: DomainMutationEndpoint, args: DomainMutationArgs) !Output {
    return .{ .text = try provider_hostinger.domainMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planHostingMutation(ctx: Context, endpoint: HostingMutationEndpoint, args: HostingMutationArgs) !Output {
    return .{ .text = try provider_hostinger.hostingMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn planEcommerceMutation(ctx: Context, endpoint: EcommerceMutationEndpoint) !Output {
    return .{ .text = try provider_hostinger.ecommerceMutationPlanJson(ctx.gpa, endpoint) };
}

pub fn planHorizonsMutation(ctx: Context, endpoint: HorizonsMutationEndpoint) !Output {
    return .{ .text = try provider_hostinger.horizonsMutationPlanJson(ctx.gpa, endpoint) };
}

pub fn planReachMutation(ctx: Context, endpoint: ReachMutationEndpoint, args: ReachMutationArgs) !Output {
    return .{ .text = try provider_hostinger.reachMutationPlanJson(ctx.gpa, endpoint, args) };
}

pub fn collectDockerEndpoint(ctx: Context, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8) !Output {
    return try collector_hostinger.collectDockerEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, vm_id, endpoint, project_name, true);
}

pub fn collectBillingEndpoint(ctx: Context, endpoint: BillingEndpoint) !Output {
    return try collector_hostinger.collectBillingEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectDnsEndpoint(ctx: Context, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8) !Output {
    return try collector_hostinger.collectDnsEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, domain, snapshot_id, true);
}

pub fn collectDomainEndpoint(ctx: Context, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8) !Output {
    return try collector_hostinger.collectDomainEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, path_arg, tld, true);
}

pub fn collectHostingEndpoint(ctx: Context, endpoint: HostingEndpoint, args: HostingArgs) !Output {
    return try collector_hostinger.collectHostingEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, args, true);
}

pub fn collectEcommerceEndpoint(ctx: Context, endpoint: EcommerceEndpoint) !Output {
    return try collector_hostinger.collectEcommerceEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectHorizonsEndpoint(ctx: Context, endpoint: HorizonsEndpoint, website_id: []const u8) !Output {
    return try collector_hostinger.collectHorizonsEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, website_id, true);
}

pub fn collectReachEndpoint(ctx: Context, endpoint: ReachEndpoint, args: ReachArgs) !Output {
    return try collector_hostinger.collectReachEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, args, true);
}

pub fn collectVpsInventoryEndpoint(ctx: Context, endpoint: VpsInventoryEndpoint) !Output {
    return try collector_hostinger.collectVpsInventoryEndpoint(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, true);
}

pub fn collectVpsInventoryDetail(ctx: Context, endpoint: VpsInventoryDetailEndpoint, id: []const u8) !Output {
    return try collector_hostinger.collectVpsInventoryDetail(ctx.io, ctx.gpa, ctx.token, ctx.db, endpoint, id, true);
}

pub fn listResources(ctx: Context) !Output {
    var rows = try ctx.db.hostingerResourceList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    for (rows.items) |row| {
        try out.writer.print("{s}\t{s}\n", .{ row.name, row.value });
    }
    return .{ .text = try out.toOwnedSlice() };
}

pub fn listInventoryItems(ctx: Context) !Output {
    var rows = try ctx.db.hostingerInventoryItemList(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    for (rows.items) |row| {
        try out.writer.print("{s}\t{s}\n", .{ row.name, row.value });
    }
    return .{ .text = try out.toOwnedSlice() };
}

pub fn defaultDomain(ctx: Context) []const u8 {
    return ctx.domains[0];
}

test "hostinger app default domain uses first configured domain" {
    const domains = [_][]const u8{ "plosca.ru", "sparkdate.love" };
    var db: Db = undefined;
    const ctx = Context{
        .io = std.testing.io,
        .gpa = std.testing.allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    try std.testing.expectEqualStrings("plosca.ru", defaultDomain(ctx));
}

test "hostinger app lists normalized resources" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-resources.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerResource("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", null, "plosca.ru", "enabled", "plosca.ru", "{\"domain\":\"plosca.ru\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listResources(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "enabled plosca.ru plosca.ru") != null);
}

test "hostinger app lists typed inventory items" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };
    var output = try listInventoryItems(ctx);
    defer output.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text orelse "", "enabled enabled main plosca.ru u123 plosca.ru 12345") != null);
}
