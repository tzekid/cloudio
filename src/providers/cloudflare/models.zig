const std = @import("std");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;

pub const AccountRow = struct {
    id: []u8,
    name: ?[]u8,
    typ: ?[]u8,
    status: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: AccountRow, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.name) |value| allocator.free(value);
        if (self.typ) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const ZoneRow = struct {
    id: []u8,
    name: ?[]u8,
    account_id: ?[]u8,
    status: ?[]u8,
    paused: ?bool,
    typ: ?[]u8,
    name_servers: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: ZoneRow, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.name) |value| allocator.free(value);
        if (self.account_id) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.typ) |value| allocator.free(value);
        if (self.name_servers) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const DnsRecordRow = struct {
    id: []u8,
    zone_id: []u8,
    name: ?[]u8,
    typ: ?[]u8,
    content: ?[]u8,
    ttl: ?i64,
    proxied: ?bool,
    raw_json: []u8,

    pub fn deinit(self: DnsRecordRow, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.zone_id);
        if (self.name) |value| allocator.free(value);
        if (self.typ) |value| allocator.free(value);
        if (self.content) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const IdRow = struct {
    id: []u8,

    pub fn deinit(self: IdRow, allocator: Allocator) void {
        allocator.free(self.id);
    }
};

pub fn Rows(comptime T: type) type {
    return struct {
        items: []T,

        pub fn deinit(self: @This(), allocator: Allocator) void {
            if (self.items.len == 0) return;
            for (self.items) |row| row.deinit(allocator);
            allocator.free(self.items);
        }
    };
}

pub const AccountRows = Rows(AccountRow);
pub const ZoneRows = Rows(ZoneRow);
pub const DnsRecordRows = Rows(DnsRecordRow);
pub const IdRows = Rows(IdRow);

pub fn parseAccountRows(gpa: Allocator, body: []const u8) !AccountRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(AccountRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(AccountRow);
    var rows = std.ArrayList(AccountRow).empty;
    errdefer deinitPartial(AccountRow, &rows, gpa);

    for (items.items) |item| {
        const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse continue);
        errdefer gpa.free(id);
        const raw = try core_json.stringifyValue(gpa, item);
        errdefer gpa.free(raw);
        const name = try dupeOptional(gpa, core_json.fieldString(item, "name"));
        errdefer if (name) |value| gpa.free(value);
        const typ = try dupeOptional(gpa, core_json.fieldString(item, "type"));
        errdefer if (typ) |value| gpa.free(value);
        const status = try dupeOptional(gpa, core_json.fieldString(item, "status"));
        errdefer if (status) |value| gpa.free(value);
        try rows.append(gpa, .{ .id = id, .name = name, .typ = typ, .status = status, .raw_json = raw });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseZoneRows(gpa: Allocator, body: []const u8) !ZoneRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(ZoneRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(ZoneRow);
    var rows = std.ArrayList(ZoneRow).empty;
    errdefer deinitPartial(ZoneRow, &rows, gpa);

    for (items.items) |item| {
        const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse continue);
        errdefer gpa.free(id);
        const raw = try core_json.stringifyValue(gpa, item);
        errdefer gpa.free(raw);
        const name = try dupeOptional(gpa, core_json.fieldString(item, "name"));
        errdefer if (name) |value| gpa.free(value);
        const account_id = try dupeOptional(gpa, if (core_json.field(item, "account")) |acct| core_json.fieldString(acct, "id") else null);
        errdefer if (account_id) |value| gpa.free(value);
        const status = try dupeOptional(gpa, core_json.fieldString(item, "status"));
        errdefer if (status) |value| gpa.free(value);
        const typ = try dupeOptional(gpa, core_json.fieldString(item, "type"));
        errdefer if (typ) |value| gpa.free(value);
        const name_servers = if (core_json.field(item, "name_servers")) |value| try core_json.stringifyValue(gpa, value) else null;
        errdefer if (name_servers) |value| gpa.free(value);
        try rows.append(gpa, .{
            .id = id,
            .name = name,
            .account_id = account_id,
            .status = status,
            .paused = core_json.fieldBool(item, "paused"),
            .typ = typ,
            .name_servers = name_servers,
            .raw_json = raw,
        });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseDnsRecordRows(gpa: Allocator, zone_id: []const u8, body: []const u8) !DnsRecordRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(DnsRecordRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(DnsRecordRow);
    var rows = std.ArrayList(DnsRecordRow).empty;
    errdefer deinitPartial(DnsRecordRow, &rows, gpa);

    for (items.items) |item| {
        const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse continue);
        errdefer gpa.free(id);
        const row_zone_id = try gpa.dupe(u8, zone_id);
        errdefer gpa.free(row_zone_id);
        const raw = try core_json.stringifyValue(gpa, item);
        errdefer gpa.free(raw);
        const name = try dupeOptional(gpa, core_json.fieldString(item, "name"));
        errdefer if (name) |value| gpa.free(value);
        const typ = try dupeOptional(gpa, core_json.fieldString(item, "type"));
        errdefer if (typ) |value| gpa.free(value);
        const content = try dupeOptional(gpa, core_json.fieldString(item, "content"));
        errdefer if (content) |value| gpa.free(value);
        try rows.append(gpa, .{
            .id = id,
            .zone_id = row_zone_id,
            .name = name,
            .typ = typ,
            .content = content,
            .ttl = core_json.fieldInt(item, "ttl"),
            .proxied = core_json.fieldBool(item, "proxied"),
            .raw_json = raw,
        });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseIdRows(gpa: Allocator, body: []const u8) !IdRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(IdRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(IdRow);
    var rows = std.ArrayList(IdRow).empty;
    errdefer deinitPartial(IdRow, &rows, gpa);

    for (items.items) |item| {
        const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse continue);
        errdefer gpa.free(id);
        try rows.append(gpa, .{ .id = id });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn zoneIdFromResponse(gpa: Allocator, body: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    if (core_json.resultArray(parsed.value)) |items| {
        if (items.items.len == 0) return null;
        if (core_json.fieldString(items.items[0], "id")) |id| return try gpa.dupe(u8, id);
    }
    return null;
}

fn emptyRows(comptime T: type) Rows(T) {
    return .{ .items = &.{} };
}

fn deinitPartial(comptime T: type, rows: *std.ArrayList(T), allocator: Allocator) void {
    for (rows.items) |row| row.deinit(allocator);
    rows.deinit(allocator);
}

fn dupeRequired(gpa: Allocator, value: []const u8) ![]u8 {
    return try gpa.dupe(u8, value);
}

fn dupeOptional(gpa: Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |text| try gpa.dupe(u8, text) else null;
}

test "parses Cloudflare account rows" {
    const allocator = std.testing.allocator;
    var rows = try parseAccountRows(allocator,
        \\{"result":[{"id":"acct-1","name":"Main","type":"standard","status":"active"}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("acct-1", rows.items[0].id);
    try std.testing.expectEqualStrings("Main", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("standard", rows.items[0].typ orelse "");
    try std.testing.expectEqualStrings("active", rows.items[0].status orelse "");
}

test "parses Cloudflare zone rows and zone id" {
    const allocator = std.testing.allocator;
    const body =
        \\{"result":[{"id":"zone-1","name":"plosca.ru","status":"active","paused":false,"type":"full","account":{"id":"acct-1"},"name_servers":["a.ns.cloudflare.com","b.ns.cloudflare.com"]}]}
    ;
    var rows = try parseZoneRows(allocator, body);
    defer rows.deinit(allocator);
    const zone_id = try zoneIdFromResponse(allocator, body) orelse return error.TestExpectedZoneId;
    defer allocator.free(zone_id);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("zone-1", rows.items[0].id);
    try std.testing.expectEqualStrings("acct-1", rows.items[0].account_id orelse "");
    try std.testing.expectEqual(false, rows.items[0].paused orelse true);
    try std.testing.expect(std.mem.indexOf(u8, rows.items[0].name_servers orelse "", "a.ns.cloudflare.com") != null);
    try std.testing.expectEqualStrings("zone-1", zone_id);
}

test "parses Cloudflare DNS record rows" {
    const allocator = std.testing.allocator;
    var rows = try parseDnsRecordRows(allocator, "zone-1",
        \\{"result":[{"id":"dns-1","name":"plosca.ru","type":"A","content":"76.13.130.170","ttl":1,"proxied":true}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("dns-1", rows.items[0].id);
    try std.testing.expectEqualStrings("zone-1", rows.items[0].zone_id);
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("A", rows.items[0].typ orelse "");
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[0].content orelse "");
    try std.testing.expectEqual(@as(i64, 1), rows.items[0].ttl orelse -1);
    try std.testing.expectEqual(true, rows.items[0].proxied orelse false);
}

test "parses generic Cloudflare result ids" {
    const allocator = std.testing.allocator;
    var rows = try parseIdRows(allocator,
        \\{"result":[{"id":"first"},{"name":"missing"},{"id":"second"}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("first", rows.items[0].id);
    try std.testing.expectEqualStrings("second", rows.items[1].id);
}
