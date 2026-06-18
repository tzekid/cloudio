const std = @import("std");
const core_output = @import("core_output");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Output = core_output.Output;

pub const Provider = enum {
    cloudflare,
    hostinger,

    pub fn name(self: Provider) []const u8 {
        return switch (self) {
            .cloudflare => "cloudflare",
            .hostinger => "hostinger",
        };
    }
};

pub const Dataset = enum {
    resources,
    inventory_items,
};

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const Options = struct {
    provider: Provider,
    dataset: Dataset,
};

pub fn rows(ctx: Context, options: Options) !db_store.NameValueRows {
    return switch (options.provider) {
        .cloudflare => switch (options.dataset) {
            .resources => try ctx.db.cloudflareResourceList(ctx.gpa),
            .inventory_items => try ctx.db.cloudflareInventoryItemList(ctx.gpa),
        },
        .hostinger => switch (options.dataset) {
            .resources => try ctx.db.hostingerResourceList(ctx.gpa),
            .inventory_items => try ctx.db.hostingerInventoryItemList(ctx.gpa),
        },
    };
}

pub fn text(ctx: Context, options: Options) !Output {
    var result = try rows(ctx, options);
    defer result.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try writeText(result, &out.writer);
    return .{ .text = try out.toOwnedSlice() };
}

pub fn writeText(result: db_store.NameValueRows, writer: anytype) !void {
    for (result.items) |row| {
        try writer.print("{s}\t{s}\n", .{ row.name, row.value });
    }
}

pub fn resources(ctx: Context, provider: Provider) !Output {
    return try text(ctx, .{ .provider = provider, .dataset = .resources });
}

pub fn inventoryItems(ctx: Context, provider: Provider) !Output {
    return try text(ctx, .{ .provider = provider, .dataset = .inventory_items });
}

test "provider list renders Cloudflare and Hostinger resource rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/provider-list-resources.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareResource("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "{\"id\":\"record-1\"}");
    try db.upsertHostingerResource("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", null, "plosca.ru", "enabled", "plosca.ru", "{\"domain\":\"plosca.ru\"}");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var cloudflare = try resources(ctx, .cloudflare);
    defer cloudflare.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "dns-records/record-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "zone zone-1 active A plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "hostinger-websites") == null);

    var hostinger = try resources(ctx, .hostinger);
    defer hostinger.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "enabled plosca.ru plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "dns-records") == null);
}

test "provider list renders typed inventory rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/provider-list-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var cloudflare = try inventoryItems(ctx, .cloudflare);
    defer cloudflare.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "dns-records/record-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "zone zone-1 active dns_only A plosca.ru plosca.ru 76.13.130.170") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare.text orelse "", "hostinger-websites") == null);

    var hostinger = try inventoryItems(ctx, .hostinger);
    defer hostinger.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "hostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "enabled enabled main plosca.ru u123 plosca.ru 12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, hostinger.text orelse "", "dns-records") == null);
}
