const std = @import("std");
const collector_hostinger = @import("collector_hostinger");
const app_provider_list = @import("app_provider_list");
const app_render = @import("app_render");
const core_output = @import("core_output");
const db_store = @import("db_store");
const provider_hostinger = @import("provider_hostinger");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const positiveLimit = app_render.positiveLimit;
const writeJsonStringField = app_render.writeJsonStringField;
const writeTextField = app_render.writeTextField;

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

pub const VpsOverviewOptions = struct {
    limit: i64 = 20,
};

pub const VpsOverview = struct {
    vps: db_store.HostingerVpsRows,
    resource_kinds: db_store.HostingerKindCounts,
    inventory_kinds: db_store.HostingerKindCounts,
    metric_summaries: db_store.HostingerMetricSummaries,
    family_summaries: db_store.HostingerVpsFamilySummaries,

    pub fn load(ctx: Context, options: VpsOverviewOptions) !VpsOverview {
        const limit = positiveLimit(options.limit, 20);
        return .{
            .vps = try ctx.db.hostingerVpsRows(ctx.gpa, limit),
            .resource_kinds = try ctx.db.hostingerResourceKindCounts(ctx.gpa, limit),
            .inventory_kinds = try ctx.db.hostingerInventoryKindCounts(ctx.gpa, limit),
            .metric_summaries = try ctx.db.hostingerMetricSummaries(ctx.gpa, limit),
            .family_summaries = try ctx.db.hostingerVpsFamilySummaries(ctx.gpa, limit),
        };
    }

    pub fn deinit(self: *VpsOverview, allocator: Allocator) void {
        self.vps.deinit(allocator);
        self.resource_kinds.deinit(allocator);
        self.inventory_kinds.deinit(allocator);
        self.metric_summaries.deinit(allocator);
        self.family_summaries.deinit(allocator);
    }

    pub fn writeText(self: VpsOverview, writer: anytype) !void {
        try writer.writeAll("Hostinger VPS overview\n");
        try writer.writeAll("vps\n");
        if (self.vps.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.vps.items) |row| try writeVpsRowText(row, writer);
        }

        try writer.writeAll("resources\n");
        if (self.resource_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.resource_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("inventory\n");
        if (self.inventory_kinds.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.inventory_kinds.items) |row| try writeKindCountText(row, writer);
        }

        try writer.writeAll("metrics\n");
        if (self.metric_summaries.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.metric_summaries.items) |row| try writeMetricSummaryText(row, writer);
        }

        try writer.writeAll("vm family\n");
        if (self.family_summaries.items.len == 0) {
            try writer.writeAll("none\n");
        } else {
            for (self.family_summaries.items) |row| try writeVpsFamilySummaryText(row, writer);
        }
    }

    pub fn writeJson(self: VpsOverview, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"hostinger_vps_overview\",\"vps\":[");
        for (self.vps.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsRowJson(row, writer);
        }
        try writer.writeAll("],\"resource_kinds\":[");
        for (self.resource_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"inventory_kinds\":[");
        for (self.inventory_kinds.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeKindCountJson(row, writer);
        }
        try writer.writeAll("],\"metric_summaries\":[");
        for (self.metric_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeMetricSummaryJson(row, writer);
        }
        try writer.writeAll("],\"vm_family\":[");
        for (self.family_summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeVpsFamilySummaryJson(row, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
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
    return try app_provider_list.resources(providerListContext(ctx), .hostinger);
}

pub fn listInventoryItems(ctx: Context) !Output {
    return try app_provider_list.inventoryItems(providerListContext(ctx), .hostinger);
}

pub fn writeVpsOverviewText(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(ctx, options);
    defer overview.deinit(ctx.gpa);
    try overview.writeText(writer);
}

pub fn writeVpsOverviewJson(ctx: Context, options: VpsOverviewOptions, writer: anytype) !void {
    var overview = try VpsOverview.load(ctx, options);
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

fn writeVpsRowText(row: db_store.HostingerVpsRow, writer: anytype) !void {
    try writer.print("{s}", .{row.id});
    try writeTextField(writer, "name", row.name);
    try writeTextField(writer, "status", row.status);
    try writeTextField(writer, "ipv4", row.ipv4);
    try writeTextField(writer, "plan", row.plan);
    try writeTextField(writer, "updated", row.updated_at);
    try writer.writeByte('\n');
}

fn writeKindCountText(row: db_store.HostingerKindCount, writer: anytype) !void {
    try writer.print("{s}\tcount={d}", .{ row.kind, row.count });
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeMetricSummaryText(row: db_store.HostingerMetricSummary, writer: anytype) !void {
    try writer.print("{s}/{s}\tcount={d}", .{ row.vm_id, row.metric, row.count });
    try writeTextField(writer, "latest", row.latest_captured);
    try writer.writeByte('\n');
}

fn writeVpsFamilySummaryText(row: db_store.HostingerVpsFamilySummary, writer: anytype) !void {
    try writer.print("{s}/{s}/{s}\tcount={d}", .{ row.vm_id, row.source, row.kind, row.count });
    try writeTextField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeVpsRowJson(row: db_store.HostingerVpsRow, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "id", row.id, true);
    try writeJsonStringField(writer, "name", row.name, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "ipv4", row.ipv4, true);
    try writeJsonStringField(writer, "plan", row.plan, true);
    try writeJsonStringField(writer, "updated_at", row.updated_at, false);
    try writer.writeByte('}');
}

fn writeKindCountJson(row: db_store.HostingerKindCount, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeMetricSummaryJson(row: db_store.HostingerMetricSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try writeJsonStringField(writer, "metric", row.metric, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_captured", row.latest_captured, false);
    try writer.writeByte('}');
}

fn writeVpsFamilySummaryJson(row: db_store.HostingerVpsFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "vm_id", row.vm_id, true);
    try writeJsonStringField(writer, "source", row.source, true);
    try writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
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
    try db.insertHostingerMetric("12345", "cpu", "0.42", "{\"cpu\":0.42}");
    try db.upsertHostingerResource("hostinger-vps-actions||12345||reboot", "hostinger-vps-actions", "reboot", "12345", "Reboot", "available", null, "{\"id\":\"reboot\"}");
    try db.upsertHostingerResource("hostinger-vps-action-detail||12345/reboot||step-1", "hostinger-vps-action-detail", "step-1", "12345/reboot", "Step 1", "complete", null, "{\"id\":\"step-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-templates||ubuntu", "hostinger-vps-templates", "ubuntu", "Ubuntu", "available", "linux", null, null, null, "enabled", null, null, null, "{\"id\":\"ubuntu\"}");
    try db.upsertHostingerInventoryItem("hostinger-vps-backups|12345|backup-1", "hostinger-vps-backups", "backup-1", "Backup 1", "available", "backup", null, null, null, null, "2026-01-01T00:00:00Z", null, null, "{\"id\":\"backup-1\"}");

    const domains = [_][]const u8{"plosca.ru"};
    const ctx = Context{
        .io = std.testing.io,
        .gpa = allocator,
        .token = null,
        .domains = domains[0..],
        .db = &db,
    };

    var overview = try VpsOverview.load(ctx, .{ .limit = 10 });
    defer overview.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), overview.vps.items.len);
    try std.testing.expectEqualStrings("12345", overview.vps.items[0].id);
    try std.testing.expectEqual(@as(usize, 2), overview.resource_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 2), overview.inventory_kinds.items.len);
    try std.testing.expectEqual(@as(usize, 1), overview.metric_summaries.items.len);
    try std.testing.expectEqualStrings("cpu", overview.metric_summaries.items[0].metric);
    try std.testing.expectEqual(@as(usize, 4), overview.family_summaries.items.len);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeVpsOverviewText(ctx, .{ .limit = 10 }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hostinger VPS overview\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345\tname=srv12345.hstgr.cloud\tstatus=running\tipv4=76.13.130.170\tplan=KVM 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/cpu\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "vm family\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-actions\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/resource/hostinger-vps-action-detail\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/inventory/hostinger-vps-backups\tcount=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "12345/metric/cpu\tcount=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeVpsOverviewJson(ctx, .{ .limit = 10 }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger_vps_overview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"12345\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"resource_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"inventory_kinds\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric_summaries\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metric\":\"cpu\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"vm_family\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"resource\",\"kind\":\"hostinger-vps-actions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\":\"inventory\",\"kind\":\"hostinger-vps-backups\"") != null);
}
