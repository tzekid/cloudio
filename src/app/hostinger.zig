const std = @import("std");
const collector_hostinger = @import("collector_hostinger");
const app_hostinger_overview = @import("app_hostinger_overview");
const app_provider_list = @import("app_provider_list");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_hostinger = @import("provider_hostinger");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Output = core_output.Output;
pub const VmEndpoint = provider_hostinger.VmEndpoint;
pub const VpsMutationEndpoint = provider_hostinger.VpsMutationEndpoint;
pub const VpsMutationArgs = provider_hostinger.VpsMutationArgs;
pub const VpsInventoryEndpoint = provider_hostinger.VpsInventoryEndpoint;
pub const VpsInventoryDetailEndpoint = provider_hostinger.VpsInventoryDetailEndpoint;
pub const VpsResourceMutationEndpoint = provider_hostinger.VpsResourceMutationEndpoint;
pub const VpsResourceMutationArgs = provider_hostinger.VpsResourceMutationArgs;
pub const FirewallMutationEndpoint = provider_hostinger.FirewallMutationEndpoint;
pub const FirewallMutationArgs = provider_hostinger.FirewallMutationArgs;
pub const DockerEndpoint = provider_hostinger.DockerEndpoint;
pub const DockerMutationEndpoint = provider_hostinger.DockerMutationEndpoint;
pub const DockerMutationArgs = provider_hostinger.DockerMutationArgs;
pub const BillingEndpoint = provider_hostinger.BillingEndpoint;
pub const BillingMutationEndpoint = provider_hostinger.BillingMutationEndpoint;
pub const BillingMutationArgs = provider_hostinger.BillingMutationArgs;
pub const DnsEndpoint = provider_hostinger.DnsEndpoint;
pub const DnsMutationEndpoint = provider_hostinger.DnsMutationEndpoint;
pub const DnsMutationArgs = provider_hostinger.DnsMutationArgs;
pub const DomainEndpoint = provider_hostinger.DomainEndpoint;
pub const DomainMutationEndpoint = provider_hostinger.DomainMutationEndpoint;
pub const DomainMutationArgs = provider_hostinger.DomainMutationArgs;
pub const HostingEndpoint = provider_hostinger.HostingEndpoint;
pub const HostingArgs = provider_hostinger.HostingArgs;
pub const HostingMutationEndpoint = provider_hostinger.HostingMutationEndpoint;
pub const HostingMutationArgs = provider_hostinger.HostingMutationArgs;
pub const EcommerceEndpoint = provider_hostinger.EcommerceEndpoint;
pub const EcommerceMutationEndpoint = provider_hostinger.EcommerceMutationEndpoint;
pub const HorizonsEndpoint = provider_hostinger.HorizonsEndpoint;
pub const HorizonsMutationEndpoint = provider_hostinger.HorizonsMutationEndpoint;
pub const ReachEndpoint = provider_hostinger.ReachEndpoint;
pub const ReachArgs = provider_hostinger.ReachArgs;
pub const ReachMutationEndpoint = provider_hostinger.ReachMutationEndpoint;
pub const ReachMutationArgs = provider_hostinger.ReachMutationArgs;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    token: ?[]const u8,
    domains: []const []const u8,
    db: *Db,
};

pub const VpsOverviewOptions = app_hostinger_overview.VpsOverviewOptions;
pub const AccountOverviewOptions = app_hostinger_overview.AccountOverviewOptions;
pub const HostingerFamily = app_hostinger_overview.HostingerFamily;
pub const HostingerFamilySummary = app_hostinger_overview.HostingerFamilySummary;
pub const AccountOverviewSummary = app_hostinger_overview.AccountOverviewSummary;
pub const VpsOverviewSummary = app_hostinger_overview.VpsOverviewSummary;
pub const AccountOverview = app_hostinger_overview.AccountOverview;
pub const VpsOverview = app_hostinger_overview.VpsOverview;
pub const OverviewContext = app_hostinger_overview.Context;

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
    return try app_provider_list.resources(providerListContext(ctx), .hostinger);
}

pub fn listInventoryItems(ctx: Context) !Output {
    return try app_provider_list.inventoryItems(providerListContext(ctx), .hostinger);
}

pub fn writeVpsOverviewText(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(overviewContext(ctx), options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeVpsOverviewJson(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(overviewContext(ctx), options);
    defer overview.deinit(ctx.gpa);
    try overview.writeJson(writer);
}

pub fn writeAccountOverviewText(ctx: Context, options: AccountOverviewOptions, writer: anytype) !void {
    var overview = try AccountOverview.load(overviewContext(ctx), options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeAccountOverviewJson(ctx: Context, options: AccountOverviewOptions, writer: anytype) !void {
    var overview = try AccountOverview.load(overviewContext(ctx), options);
    defer overview.deinit(ctx.gpa);
    try overview.writeJson(writer);
}

pub fn defaultDomain(ctx: Context) []const u8 {
    return ctx.domains[0];
}

fn providerListContext(ctx: Context) app_provider_list.Context {
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

fn overviewContext(ctx: Context) OverviewContext {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
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

test "hostinger app renders account overview across provider families" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-account-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerResource("billing_getSubscriptionListV1/sub-1", "billing_getSubscriptionListV1", "sub-1", "billing_getSubscriptionListV1", "KVM 2", "active", null, "{\"id\":\"sub-1\"}");
    try db.upsertHostingerInventoryItem("billing_getSubscriptionListV1/sub-1", "billing_getSubscriptionListV1", "sub-1", "KVM 2", "active", "EUR", null, null, null, "auto_renewed", null, null, null, "{\"id\":\"sub-1\"}");
    try db.upsertHostingerInventoryItem("domains_getDomainListV1/domain-1", "domains_getDomainListV1", "domain-1", "plosca.ru", "active", "domain", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"domain-1\"}");
    try db.upsertHostingerInventoryItem("DNS_getDNSRecordsV1/plosca.ru/A", "DNS_getDNSRecordsV1", "A", "plosca.ru A", "active", "A", "plosca.ru", null, null, null, null, null, null, "{\"type\":\"A\"}");
    try db.upsertHostingerInventoryItem("DNS_getDNSRecordsV1/plosca.ru/TXT", "DNS_getDNSRecordsV1", "TXT", "plosca.ru TXT", "active", "A", "plosca.ru", null, null, null, null, null, null, "{\"type\":\"TXT\"}");
    try db.upsertHostingerInventoryItem("hosting_listWebsitesV1/plosca.ru", "hosting_listWebsitesV1", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "order-1", null, null, null, null, "{\"domain\":\"plosca.ru\"}");
    try db.upsertHostingerInventoryItem("VPS_getVirtualMachineDetailsV1|12345|detail", "VPS_getVirtualMachineDetailsV1", "12345", "srv12345.hstgr.cloud", "running", "vps", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"12345\"}");
    try db.upsertHostingerInventoryItem("VPS_getProjectListV1|12345|stack", "VPS_getProjectListV1", "stack", "stack", "running", "docker", null, null, null, null, null, null, null, "{\"projectName\":\"stack\"}");
    try db.upsertHostingerInventoryItem("VPS_getScanMetricsV1|12345|monarx", "VPS_getScanMetricsV1", "monarx", "Monarx", "unsupported", "security", null, null, null, null, null, null, null, "{\"status\":\"unsupported\"}");
    try db.upsertHostingerInventoryItem("reach_listContactsV1/contact-1", "reach_listContactsV1", "contact-1", "Contact", "active", "contact", null, null, null, null, null, null, null, "{\"id\":\"contact-1\"}");
    try db.upsertHostingerInventoryItem("ecommerce_getStoresV1/store-1", "ecommerce_getStoresV1", "store-1", "Store", "active", "store", null, null, null, null, null, null, null, "{\"id\":\"store-1\"}");
    try db.upsertHostingerInventoryItem("horizons_getWebsitesV1/site-1", "horizons_getWebsitesV1", "site-1", "Site", "active", "website", "plosca.ru", null, null, null, null, null, null, "{\"id\":\"site-1\"}");
    try db.upsertHostingerInventoryItem("miscKind/item-1", "miscKind", "item-1", "Other", "active", "misc", null, null, null, null, null, null, null, "{\"id\":\"item-1\"}");
    _ = try db.insertSnapshot("hostinger", "billing", null, "ok", "billing catalog", null, null);
    _ = try db.insertSnapshot("hostinger", "dns", "plosca.ru", "ok", "dns zone", null, null);
    _ = try db.insertSnapshot("cloudflare", "zone", "plosca.ru", "ok", "zone", null, null);

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var overview = try AccountOverview.load(overviewContext(ctx), .{ .limit = 20, .snapshot_limit = 5 });
    defer overview.deinit(allocator);
    const summary = overview.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.vps);
    try std.testing.expectEqual(@as(usize, 1), summary.running_vps);
    try std.testing.expectEqual(@as(usize, 0), summary.complete_vps_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.partial_vps_core_coverage);
    try std.testing.expectEqual(@as(i64, 1), summary.resources);
    try std.testing.expectEqual(@as(i64, 12), summary.inventory_items);
    try std.testing.expectEqual(@as(usize, 1), summary.resource_kinds);
    try std.testing.expectEqual(@as(usize, 11), summary.inventory_kinds);
    try std.testing.expectEqual(@as(usize, 11), summary.inventory_facets);
    try std.testing.expectEqual(@as(usize, 2), summary.recent_snapshots);
    try std.testing.expectEqual(@as(usize, 71), summary.api_routes);
    try std.testing.expectEqual(@as(usize, 30), summary.api_read_routes);
    try std.testing.expectEqual(@as(usize, 38), summary.api_dry_run_routes);
    try std.testing.expectEqual(@as(usize, 0), summary.api_write_routes);
    try std.testing.expectEqual(@as(usize, 1), summary.api_not_applicable_routes);
    try std.testing.expectEqual(@as(usize, 2), summary.api_deprecated_routes);
    try std.testing.expectEqual(@as(usize, 6), summary.api_blocked_permission_routes);
    try std.testing.expectEqual(@as(usize, 8), summary.api_families);
    try std.testing.expectEqual(@as(usize, 7), summary.observed_read_families);
    try std.testing.expectEqual(@as(usize, 0), summary.missing_read_families);
    try std.testing.expectEqual(@as(usize, 1), summary.not_applicable_families);
    try std.testing.expectEqual(@as(i64, 1), summary.families.billing);
    try std.testing.expectEqual(@as(i64, 2), summary.families.dns);
    try std.testing.expectEqual(@as(i64, 1), summary.families.domains);
    try std.testing.expectEqual(@as(i64, 1), summary.families.hosting);
    try std.testing.expectEqual(@as(i64, 1), summary.families.vps);
    try std.testing.expectEqual(@as(i64, 1), summary.families.docker);
    try std.testing.expectEqual(@as(i64, 1), summary.families.security);
    try std.testing.expectEqual(@as(i64, 1), summary.families.reach);
    try std.testing.expectEqual(@as(i64, 1), summary.families.ecommerce);
    try std.testing.expectEqual(@as(i64, 1), summary.families.horizons);
    try std.testing.expectEqual(@as(i64, 1), summary.families.other);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeAccountOverviewText(ctx, .{ .limit = 20, .snapshot_limit = 5 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger account overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary vps=1 running_vps=1 stopped_or_other_vps=0 complete_vps_core_coverage=0 partial_vps_core_coverage=1 resources=1 inventory_items=12 resource_kinds=1 inventory_kinds=11 inventory_facets=11 recent_snapshots=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_routes total=71 read=30 dry_run=38 write=0 not_applicable=1 deprecated=2 blocked_permission=6 families=8 observed_read_families=7 missing_read_families=0 not_applicable_families=1 blocked_or_missing_families=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "families billing=1 dns=2 domains=1 hosting=1 vps=1 docker=1 security=1 reach=1 ecommerce=1 horizons=1 other=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "VPS_getProjectListV1\tfamily=docker\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "horizons_getWebsitesV1\tfamily=horizons\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "billing\tofficial_routes=7\tread_routes=3\tdry_run_routes=4\twrite_routes=0\tnot_applicable_routes=0\tdeprecated_routes=0\tblocked_permission_routes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "domain_access_verifier\tofficial_routes=1\tread_routes=0\tdry_run_routes=0\twrite_routes=0\tnot_applicable_routes=1\tdeprecated_routes=0\tblocked_permission_routes=0\tobserved_items=0\tobserved_kinds=0\tstatus=not_applicable") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "recent snapshots\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/dns\ttarget=plosca.ru\tstatus=ok\tsummary=dns zone") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/zone") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeAccountOverviewJson(ctx, .{ .limit = 20, .snapshot_limit = 5 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_account_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"vps\":1,\"running_vps\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_routes\":71,\"api_read_routes\":30,\"api_dry_run_routes\":38,\"api_write_routes\":0,\"api_not_applicable_routes\":1,\"api_deprecated_routes\":2,\"api_blocked_permission_routes\":6,\"api_families\":8,\"observed_read_families\":7,\"missing_read_families\":0,\"not_applicable_families\":1,\"blocked_or_missing_families\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"families\":{\"billing\":1,\"dns\":2,\"domains\":1,\"hosting\":1,\"vps\":1,\"docker\":1,\"security\":1,\"reach\":1,\"ecommerce\":1,\"horizons\":1,\"other\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_facets\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"VPS_getProjectListV1\",\"family\":\"docker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"horizons_getWebsitesV1\",\"family\":\"horizons\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"billing\",\"official_routes\":7,\"read_routes\":3,\"dry_run_routes\":4,\"write_routes\":0,\"not_applicable_routes\":0,\"deprecated_routes\":0,\"blocked_permission_routes\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"domain_access_verifier\",\"official_routes\":1,\"read_routes\":0,\"dry_run_routes\":0,\"write_routes\":0,\"not_applicable_routes\":1,\"deprecated_routes\":0,\"blocked_permission_routes\":0,\"observed_items\":0,\"observed_kinds\":0,\"status\":\"not_applicable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\",\"kind\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\"") == null);
}

test "hostinger app renders VPS overview from normalized storage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-app-vps-overview.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerVps("67890", "srv67890.hstgr.cloud", "stopped", "", "KVM 1", "{\"id\":67890}");
    try db.insertHostingerMetric("12345", "cpu", "0.42", "{\"cpu\":0.42}");
    try db.upsertHostingerResource("hostinger-vps-detail||12345", "vps-detail", "12345", "12345", "srv12345.hstgr.cloud", "running", null, "{\"id\":\"12345\"}");
    try db.upsertHostingerResource("hostinger-vps-actions||12345||reboot", "hostinger-vps-actions", "reboot", "12345", "Reboot", "available", null, "{\"id\":\"reboot\"}");
    try db.upsertHostingerResource("hostinger-vps-action-detail||12345/reboot||step-1", "hostinger-vps-action-detail", "step-1", "12345/reboot", "Step 1", "complete", null, "{\"id\":\"step-1\"}");
    try db.upsertHostingerResource("hostinger-vps-public-keys||12345||key-1", "public-keys", "key-1", "12345", "deploy", "attached", null, "{\"id\":\"key-1\"}");
    try db.upsertHostingerResource("hostinger-vps-docker||12345||stack", "docker", "stack", "12345", "stack", "running", null, "{\"name\":\"stack\"}");
    try db.upsertHostingerResource("hostinger-vps-monarx||12345||scan", "monarx", "scan", "12345", "Monarx", "enabled", null, "{\"state\":\"enabled\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-templates||ubuntu", "hostinger-vps-templates", "ubuntu", "Ubuntu", "available", "linux", null, null, null, "enabled", null, null, null, "{\"id\":\"ubuntu\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-data-centers||eu-west", "data-centers", "eu-west", "EU West", "available", "location", null, null, null, null, null, null, null, "{\"id\":\"eu-west\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-firewalls||fw-1", "firewalls", "fw-1", "default", "active", "firewall", null, null, null, null, null, null, null, "{\"id\":\"fw-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-post-install||script-1", "post-install-scripts", "script-1", "bootstrap", "active", "script", null, null, null, null, null, null, null, "{\"id\":\"script-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-public-keys-global||key-1", "public-keys-global", "key-1", "deploy", "active", "ssh", null, null, null, null, null, null, null, "{\"id\":\"key-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-backups|12345|backup-1", "hostinger-vps-backups", "backup-1", "Backup 1", "available", "backup", null, null, null, null, "2026-01-01T00:00:00Z", null, null, "{\"id\":\"backup-1\"}");
    try db.upsertHostingerInventoryItem("snapshot|12345|snapshot", "snapshot", "snapshot", "Snapshot", "available", "snapshot", null, null, null, null, "2026-01-02T00:00:00Z", null, null, "{\"id\":\"snapshot\"}");
    _ = try db.insertSnapshot("hostinger", "vps", null, "ok", "vps list", null, null);
    _ = try db.insertSnapshot("hostinger", "monarx", "12345", "ok", "scan metrics", null, null);
    _ = try db.insertSnapshot("cloudflare", "zone", "plosca.ru", "ok", "zone", null, null);

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var limited_overview = try VpsOverview.load(overviewContext(ctx), .{ .limit = 1, .snapshot_limit = 1 });
    defer limited_overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), limited_overview.vps.items.len);
    try std.testing.expectEqual(@as(usize, 2), limited_overview.summary().vps);
    try std.testing.expectEqual(@as(usize, 1), limited_overview.recent_snapshots.items.len);

    var overview = try VpsOverview.load(overviewContext(ctx), .{ .limit = 10, .snapshot_limit = 2 });
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), overview.vps.items.len);
    try std.testing.expectEqualStrings("12345", overview.vps.items[0].id);
    try std.testing.expectEqual(@as(usize, 6), overview.resource_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 7), overview.inventory_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 1), overview.metric_summaries.items.len);
    try std.testing.expectEqualStrings("cpu", overview.metric_summaries.items[0].metric);
    try std.testing.expectEqual(@as(usize, 9), overview.family_summaries.items.len);
    const summary = overview.summary();
    try std.testing.expectEqual(@as(usize, 2), summary.vps);
    try std.testing.expectEqual(@as(usize, 1), summary.running);
    try std.testing.expectEqual(@as(usize, 1), summary.stopped_or_other);
    try std.testing.expectEqual(@as(usize, 1), summary.complete_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.partial_core_coverage);
    try std.testing.expectEqual(@as(usize, 1), summary.with_details);
    try std.testing.expectEqual(@as(usize, 1), summary.with_metrics);
    try std.testing.expectEqual(@as(usize, 1), summary.with_actions);
    try std.testing.expectEqual(@as(usize, 1), summary.with_backups);
    try std.testing.expectEqual(@as(usize, 1), summary.with_snapshot);
    try std.testing.expectEqual(@as(usize, 1), summary.with_public_keys);
    try std.testing.expectEqual(@as(usize, 1), summary.with_security);
    try std.testing.expectEqual(@as(usize, 1), summary.with_docker);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_details);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_metrics);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_actions);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_backups);
    try std.testing.expectEqual(@as(usize, 1), summary.missing_snapshot);
    try std.testing.expectEqual(@as(usize, 6), summary.resource_kinds);
    try std.testing.expectEqual(@as(usize, 7), summary.inventory_kinds);
    try std.testing.expectEqual(@as(usize, 1), summary.metric_summaries);
    try std.testing.expectEqual(@as(usize, 9), summary.family_summaries);
    try std.testing.expectEqual(@as(usize, 2), summary.recent_snapshots);
    try std.testing.expectEqual(@as(usize, 62), summary.api_routes);
    try std.testing.expectEqual(@as(usize, 21), summary.api_read_routes);
    try std.testing.expectEqual(@as(usize, 41), summary.api_dry_run_routes);
    try std.testing.expectEqual(@as(usize, 0), summary.api_write_routes);
    try std.testing.expectEqual(@as(usize, 0), summary.api_not_applicable_routes);
    try std.testing.expectEqual(@as(usize, 0), summary.api_deprecated_routes);
    try std.testing.expectEqual(@as(usize, 6), summary.api_blocked_permission_routes);
    try std.testing.expectEqual(@as(usize, 13), summary.api_families);
    try std.testing.expectEqual(@as(usize, 11), summary.observed_read_families);
    try std.testing.expectEqual(@as(usize, 0), summary.missing_read_families);
    try std.testing.expectEqual(@as(usize, 2), summary.dry_run_only_families);
    try std.testing.expectEqual(@as(usize, 0), summary.not_applicable_families);
    try std.testing.expectEqual(@as(usize, 0), summary.blocked_or_missing_families);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeVpsOverviewText(ctx, .{ .limit = 10, .snapshot_limit = 2 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger VPS overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary vps=2 running=1 stopped_or_other=1 complete_core_coverage=1 partial_core_coverage=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_routes total=62 read=21 dry_run=41 write=0 not_applicable=0 deprecated=0 blocked_permission=6 families=13 observed_read_families=11 missing_read_families=0 dry_run_only_families=2 not_applicable_families=0 blocked_or_missing_families=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345\tname=srv12345.hstgr.cloud\tstatus=running\tipv4=76.13.130.170\tplan=KVM 2\tcoverage=complete\tdetails=true\tmetrics=true\tactions=true\tbackups=true\tsnapshot=true\tpublic_keys=true\tsecurity=true\tdocker=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "67890\tname=srv67890.hstgr.cloud\tstatus=stopped\tplan=KVM 1\tcoverage=partial\tdetails=false\tmetrics=false\tactions=false\tbackups=false\tsnapshot=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "coverage_issues=missing_details,missing_metrics,missing_actions,missing_backups,missing_snapshot") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/cpu\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "vm family\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/vps-detail\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-action-detail\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/inventory/hostinger-vps-backups\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/inventory/snapshot\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/metric/cpu\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "virtual_machine\tofficial_routes=15\tread_routes=4\tdry_run_routes=11\twrite_routes=0\tnot_applicable_routes=0\tdeprecated_routes=0\tblocked_permission_routes=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "virtual_machine\tofficial_routes=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\tstatus=observed") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ptr_records\tofficial_routes=2\tread_routes=0\tdry_run_routes=2\twrite_routes=0\tnot_applicable_routes=0\tdeprecated_routes=0\tblocked_permission_routes=0\tobserved_items=0\tobserved_kinds=0\tstatus=dry_run_only") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "recent snapshots\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger/monarx\ttarget=12345\tstatus=ok\tsummary=scan metrics") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare/zone") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeVpsOverviewJson(ctx, .{ .limit = 10, .snapshot_limit = 2 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_vps_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"vps\":2,\"running\":1,\"stopped_or_other\":1,\"complete_core_coverage\":1,\"partial_core_coverage\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_routes\":62,\"api_read_routes\":21,\"api_dry_run_routes\":41,\"api_write_routes\":0,\"api_not_applicable_routes\":0,\"api_deprecated_routes\":0,\"api_blocked_permission_routes\":6,\"api_families\":13,\"observed_read_families\":11,\"missing_read_families\":0,\"dry_run_only_families\":2,\"not_applicable_families\":0,\"blocked_or_missing_families\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"12345\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_status\":\"complete\",\"coverage\":{\"details\":true,\"metrics\":true,\"actions\":true,\"backups\":true,\"snapshot\":true,\"public_keys\":true,\"security\":true,\"docker\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"67890\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_status\":\"partial\",\"coverage\":{\"details\":false,\"metrics\":false,\"actions\":false,\"backups\":false,\"snapshot\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"coverage_issues\":[\"missing_details\",\"missing_metrics\",\"missing_actions\",\"missing_backups\",\"missing_snapshot\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"resource_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric_summaries\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric\":\"cpu\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"vm_family\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"resource\",\"kind\":\"vps-detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"resource\",\"kind\":\"hostinger-vps-actions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"inventory\",\"kind\":\"hostinger-vps-backups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"inventory\",\"kind\":\"snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"api_families\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"virtual_machine\",\"official_routes\":15,\"read_routes\":4,\"dry_run_routes\":11,\"write_routes\":0,\"not_applicable_routes\":0,\"deprecated_routes\":0,\"blocked_permission_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"recovery\",\"official_routes\":2,\"read_routes\":0,\"dry_run_routes\":2,\"write_routes\":0,\"not_applicable_routes\":0,\"deprecated_routes\":0,\"blocked_permission_routes\":0,\"observed_items\":0,\"observed_kinds\":0,\"status\":\"dry_run_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recent_snapshots\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"hostinger\",\"kind\":\"monarx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"cloudflare\"") == null);
}
