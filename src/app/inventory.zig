const std = @import("std");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const ListOptions = struct {
    provider: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    query: ?[]const u8 = null,
    limit: i64 = 200,
};

pub fn list(ctx: Context, options: ListOptions) !db_store.InventoryItems {
    return try ctx.db.inventoryItems(ctx.gpa, .{
        .provider = options.provider,
        .domain = options.domain,
        .query = options.query,
        .limit = options.limit,
    });
}

pub fn writeText(ctx: Context, options: ListOptions, writer: anytype) !void {
    var rows = try list(ctx, options);
    defer rows.deinit(ctx.gpa);
    if (rows.items.len == 0) {
        try writer.writeAll("inventory: no items\n");
        return;
    }
    for (rows.items) |item| try writeItem(item, writer);
}

fn writeItem(item: db_store.InventoryItem, writer: anytype) !void {
    try writer.print("{s}\t{s}/{s}", .{ item.provider, item.kind, item.resource_id });
    try writeField(writer, "name", item.display_name);
    try writeField(writer, "status", item.status);
    try writeField(writer, "category", item.category);
    try writeField(writer, "domain", item.domain);
    try writeScope(writer, item);
    try writeField(writer, "username", item.username);
    try writeField(writer, "account", item.account_id);
    try writeField(writer, "zone", item.zone_id);
    try writeField(writer, "related", item.related_id);
    try writeField(writer, "flag", item.flag);
    try writeField(writer, "created", item.created_at_source);
    try writeField(writer, "source_updated", item.updated_at_source);
    try writeField(writer, "expires", item.expires_at_source);
    try writeField(writer, "collected", item.updated_at);
    try writer.writeByte('\n');
}

fn writeScope(writer: anytype, item: db_store.InventoryItem) !void {
    if (item.scope.len == 0 and item.scope_id.len == 0) return;
    try writer.writeAll("\tscope=");
    if (item.scope.len != 0) try writer.writeAll(item.scope);
    if (item.scope.len != 0 and item.scope_id.len != 0) try writer.writeByte('/');
    if (item.scope_id.len != 0) try writer.writeAll(item.scope_id);
}

fn writeField(writer: anytype, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try writer.print("\t{s}={s}", .{ label, value });
}

test "inventory app renders provider-neutral typed rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeText(.{ .gpa = allocator, .db = &db }, .{ .domain = "plosca.ru" }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare\tdns-records/record-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "scope=zone/zone-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger\thostinger-websites/plosca.ru") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "username=u123") != null);
}

test "inventory app reports empty filtered results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-inventory-empty.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeText(.{ .gpa = allocator, .db = &db }, .{ .provider = "cloudflare" }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expectEqualStrings("inventory: no items\n", text);
}
