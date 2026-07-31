const std = @import("std");
const core_json = @import("core_json");
const db_store = @import("db_store");

pub const Context = struct {
    gpa: std.mem.Allocator,
    db: *db_store.Db,
};

pub fn writeDnsRecordsJson(ctx: Context, domain: ?[]const u8, writer: *std.Io.Writer) !void {
    var zones = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 50);
    defer zones.deinit(ctx.gpa);
    var zone_id: []const u8 = "";
    if (domain) |wanted| {
        for (zones.items) |zone| {
            if (std.mem.eql(u8, zone.name, wanted)) zone_id = zone.id;
        }
    } else if (zones.items.len > 0) {
        zone_id = zones.items[0].id;
    }

    var rows = try ctx.db.cloudflare().cloudflareDnsRecordRows(ctx.gpa, 1000);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"dns_records\",");
    try core_json.writeStringField(writer, "zone_id", zone_id, true);
    try writer.writeAll("\"records\":[");
    var first = true;
    for (rows.items) |row| {
        if (domain) |wanted| {
            if (!dnsNameMatchesDomain(row.name, wanted)) continue;
        }
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", row.id, true);
        try core_json.writeStringField(writer, "zone_id", row.zone_id, true);
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "type", row.record_type, true);
        try core_json.writeStringField(writer, "content", row.content, true);
        const ttl: ?i64 = std.fmt.parseInt(i64, row.ttl, 10) catch null;
        try core_json.writeString(writer, "ttl");
        try writer.writeByte(':');
        if (ttl) |value| try writer.print("{d}", .{value}) else try writer.writeAll("null");
        try writer.writeByte(',');
        try core_json.writeString(writer, "proxied");
        try writer.writeByte(':');
        if (std.mem.eql(u8, row.proxied, "true")) {
            try writer.writeAll("true");
        } else if (std.mem.eql(u8, row.proxied, "false")) {
            try writer.writeAll("false");
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeVpsJson(ctx: Context, writer: *std.Io.Writer) !void {
    var rows = try ctx.db.hostinger().hostingerVpsRows(ctx.gpa, 100);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"vps\",\"machines\":[");
    for (rows.items, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", row.id, true);
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "status", row.status, true);
        try core_json.writeStringField(writer, "ipv4", row.ipv4, true);
        try core_json.writeStringField(writer, "plan", row.plan, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeFirewallsJson(ctx: Context, writer: *std.Io.Writer) !void {
    var rows = try ctx.db.hostinger().hostingerResourceHints(ctx.gpa, 5000);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"firewalls\",\"firewalls\":[");
    var first = true;
    for (rows.items) |row| {
        if (indexOfIgnoreCase(row.kind, "firewall") == null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "kind", row.kind, true);
        try core_json.writeStringField(writer, "id", row.resource_id, true);
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "status", row.status, true);
        try core_json.writeStringField(writer, "target", row.target, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeContainersJson(ctx: Context, writer: *std.Io.Writer) !void {
    var rows = try ctx.db.system().containerRows(ctx.gpa, 200);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"containers\",\"containers\":[");
    for (rows.items, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "image", row.image, true);
        try core_json.writeStringField(writer, "status", row.status, true);
        try core_json.writeStringField(writer, "ports", row.ports, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn dnsNameMatchesDomain(name: []const u8, domain: []const u8) bool {
    if (std.mem.eql(u8, name, domain)) return true;
    return name.len > domain.len + 1 and
        std.mem.endsWith(u8, name, domain) and
        name[name.len - domain.len - 1] == '.';
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

test "DNS domain matching respects label boundaries" {
    try std.testing.expect(dnsNameMatchesDomain("api.example.com", "example.com"));
    try std.testing.expect(!dnsNameMatchesDomain("notexample.com", "example.com"));
}
