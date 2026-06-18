const std = @import("std");
const core_json = @import("core_json");
const db_store = @import("db_store");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
pub const Provider = provider_routes.Provider;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const ListOptions = struct {
    provider: ?Provider = null,
    domain: ?[]const u8 = null,
    query: ?[]const u8 = null,
    limit: i64 = 200,
};

pub fn list(ctx: Context, options: ListOptions) !db_store.InventoryItems {
    return try ctx.db.inventoryItems(ctx.gpa, .{
        .provider = providerName(options.provider),
        .domain = options.domain,
        .query = options.query,
        .limit = options.limit,
    });
}

pub fn summary(ctx: Context, options: ListOptions) !db_store.InventoryFacets {
    return try ctx.db.inventoryFacets(ctx.gpa, .{
        .provider = providerName(options.provider),
        .domain = options.domain,
        .query = options.query,
        .limit = options.limit,
    });
}

fn providerName(provider: ?Provider) ?[]const u8 {
    const value = provider orelse return null;
    return value.name();
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

pub fn writeJson(ctx: Context, options: ListOptions, writer: anytype) !void {
    var rows = try list(ctx, options);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"items\":[");
    for (rows.items, 0..) |item, index| {
        if (index != 0) try writer.writeByte(',');
        try writeItemJson(item, writer);
    }
    try writer.writeAll("]}");
    try writer.writeByte('\n');
}

pub fn writeSummaryText(ctx: Context, options: ListOptions, writer: anytype) !void {
    var rows = try summary(ctx, options);
    defer rows.deinit(ctx.gpa);
    if (rows.items.len == 0) {
        try writer.writeAll("inventory summary: no facets\n");
        return;
    }
    try writer.writeAll("inventory summary\n");
    for (rows.items) |row| try writeFacet(row, writer);
}

pub fn writeSummaryJson(ctx: Context, options: ListOptions, writer: anytype) !void {
    var rows = try summary(ctx, options);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"facets\":[");
    for (rows.items, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writeFacetJson(row, writer);
    }
    try writer.writeAll("]}");
    try writer.writeByte('\n');
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

fn writeItemJson(item: db_store.InventoryItem, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "provider", item.provider, true);
    try writeJsonStringField(writer, "kind", item.kind, true);
    try writeJsonStringField(writer, "resource_id", item.resource_id, true);
    try writeJsonStringField(writer, "display_name", item.display_name, true);
    try writeJsonStringField(writer, "status", item.status, true);
    try writeJsonStringField(writer, "category", item.category, true);
    try writeJsonStringField(writer, "domain", item.domain, true);
    try writeJsonStringField(writer, "scope", item.scope, true);
    try writeJsonStringField(writer, "scope_id", item.scope_id, true);
    try writeJsonStringField(writer, "username", item.username, true);
    try writeJsonStringField(writer, "account_id", item.account_id, true);
    try writeJsonStringField(writer, "zone_id", item.zone_id, true);
    try writeJsonStringField(writer, "related_id", item.related_id, true);
    try writeJsonStringField(writer, "flag", item.flag, true);
    try writeJsonStringField(writer, "created_at_source", item.created_at_source, true);
    try writeJsonStringField(writer, "updated_at_source", item.updated_at_source, true);
    try writeJsonStringField(writer, "expires_at_source", item.expires_at_source, true);
    try writeJsonStringField(writer, "updated_at", item.updated_at, false);
    try writer.writeByte('}');
}

fn writeFacet(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.print("{s}\t{s}", .{ row.provider, row.kind });
    try writer.print("\tcount={d}", .{row.count});
    if (row.domains != 0) try writer.print("\tdomains={d}", .{row.domains});
    try writeField(writer, "status", row.status);
    try writeField(writer, "category", row.category);
    try writeField(writer, "latest", row.latest_updated);
    try writer.writeByte('\n');
}

fn writeFacetJson(row: db_store.InventoryFacet, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonStringField(writer, "provider", row.provider, true);
    try writeJsonStringField(writer, "kind", row.kind, true);
    try writeJsonStringField(writer, "status", row.status, true);
    try writeJsonStringField(writer, "category", row.category, true);
    try writer.writeAll("\"count\":");
    try writer.print("{d}", .{row.count});
    try writer.writeByte(',');
    try writer.writeAll("\"domains\":");
    try writer.print("{d}", .{row.domains});
    try writer.writeByte(',');
    try writeJsonStringField(writer, "latest_updated", row.latest_updated, false);
    try writer.writeByte('}');
}

fn writeJsonStringField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
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

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeJson(.{ .gpa = allocator, .db = &db }, .{ .provider = .hostinger }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"items\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger-websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"username\":\"u123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"cloudflare\"") == null);
}

test "inventory app renders provider-neutral typed row facets" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-inventory-summary.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.upsertCloudflareInventoryItem("dns-records|zone|zone-1|record-1", "dns-records", "record-1", "zone", "zone-1", "plosca.ru", "active", "A", "plosca.ru", "acct-1", "zone-1", "76.13.130.170", "dns_only", null, "2026-06-17T00:00:00Z", null, "{\"id\":\"record-1\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||plosca.ru", "hostinger-websites", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "12345", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"plosca.ru\"}");
    try db.upsertHostingerInventoryItem("hostinger-websites||sparkdate.love", "hostinger-websites", "sparkdate.love", "sparkdate.love", "enabled", "main", "sparkdate.love", "u123", "12346", "enabled", "2026-01-01T00:00:00Z", null, null, "{\"domain\":\"sparkdate.love\"}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeSummaryText(.{ .gpa = allocator, .db = &db }, .{ .provider = .hostinger }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "inventory summary\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger\thostinger-websites\tcount=2\tdomains=2\tstatus=enabled\tcategory=main") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeSummaryJson(.{ .gpa = allocator, .db = &db }, .{ .provider = .hostinger }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"facets\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"hostinger-websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"domains\":2") != null);
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
    try writeText(.{ .gpa = allocator, .db = &db }, .{ .provider = .cloudflare }, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expectEqualStrings("inventory: no items\n", text);
}
