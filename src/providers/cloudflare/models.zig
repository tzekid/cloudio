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

pub const ResourceRow = struct {
    key: []u8,
    kind: []u8,
    resource_id: []u8,
    scope: ?[]u8,
    scope_id: ?[]u8,
    name: ?[]u8,
    status: ?[]u8,
    resource_type: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: ResourceRow, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        if (self.scope) |value| allocator.free(value);
        if (self.scope_id) |value| allocator.free(value);
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.resource_type) |value| allocator.free(value);
        allocator.free(self.raw_json);
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
pub const ResourceRows = Rows(ResourceRow);

pub fn parseAccountRows(gpa: Allocator, body: []const u8) !AccountRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(AccountRow);
    defer parsed.deinit();
    const result = core_json.field(parsed.value, "result") orelse return emptyRows(AccountRow);
    var rows = std.ArrayList(AccountRow).empty;
    errdefer deinitPartial(AccountRow, &rows, gpa);

    switch (result) {
        .array => |items| for (items.items) |item| try appendAccountRow(gpa, &rows, item),
        .object => try appendAccountRow(gpa, &rows, result),
        else => {},
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseZoneRows(gpa: Allocator, body: []const u8) !ZoneRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(ZoneRow);
    defer parsed.deinit();
    const result = core_json.field(parsed.value, "result") orelse return emptyRows(ZoneRow);
    var rows = std.ArrayList(ZoneRow).empty;
    errdefer deinitPartial(ZoneRow, &rows, gpa);

    switch (result) {
        .array => |items| for (items.items) |item| try appendZoneRow(gpa, &rows, item),
        .object => try appendZoneRow(gpa, &rows, result),
        else => {},
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseDnsRecordRows(gpa: Allocator, zone_id: []const u8, body: []const u8) !DnsRecordRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(DnsRecordRow);
    defer parsed.deinit();
    const result = core_json.field(parsed.value, "result") orelse return emptyRows(DnsRecordRow);
    var rows = std.ArrayList(DnsRecordRow).empty;
    errdefer deinitPartial(DnsRecordRow, &rows, gpa);

    switch (result) {
        .array => |items| for (items.items) |item| try appendDnsRecordRow(gpa, &rows, zone_id, item),
        .object => try appendDnsRecordRow(gpa, &rows, zone_id, result),
        else => {},
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn appendAccountRow(gpa: Allocator, rows: *std.ArrayList(AccountRow), item: std.json.Value) !void {
    const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse return);
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

fn appendZoneRow(gpa: Allocator, rows: *std.ArrayList(ZoneRow), item: std.json.Value) !void {
    const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse return);
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

fn appendDnsRecordRow(gpa: Allocator, rows: *std.ArrayList(DnsRecordRow), zone_id: []const u8, item: std.json.Value) !void {
    const id = try dupeRequired(gpa, core_json.fieldString(item, "id") orelse return);
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

pub fn parseResourceIdRows(gpa: Allocator, body: []const u8) !IdRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(IdRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(IdRow);
    var rows = std.ArrayList(IdRow).empty;
    errdefer deinitPartial(IdRow, &rows, gpa);

    for (items.items) |item| {
        const id = try resourceIdValue(gpa, item) orelse continue;
        errdefer gpa.free(id);
        try rows.append(gpa, .{ .id = id });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseResourceIdRowsMatchingString(gpa: Allocator, body: []const u8, field_name: []const u8, expected_value: []const u8) !IdRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(IdRow);
    defer parsed.deinit();
    const items = core_json.resultArray(parsed.value) orelse return emptyRows(IdRow);
    var rows = std.ArrayList(IdRow).empty;
    errdefer deinitPartial(IdRow, &rows, gpa);

    for (items.items) |item| {
        const actual = core_json.fieldString(item, field_name) orelse continue;
        if (!std.mem.eql(u8, actual, expected_value)) continue;
        const id = try resourceIdValue(gpa, item) orelse continue;
        errdefer gpa.free(id);
        try rows.append(gpa, .{ .id = id });
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseResourceRows(gpa: Allocator, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, body: []const u8) !ResourceRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(ResourceRow);
    defer parsed.deinit();

    var rows = std.ArrayList(ResourceRow).empty;
    errdefer deinitPartial(ResourceRow, &rows, gpa);
    try appendResourceRowsFromValue(gpa, &rows, kind, scope, scope_id, parsed.value);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn appendResourceRowsFromValue(gpa: Allocator, rows: *std.ArrayList(ResourceRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendResourceRow(gpa, rows, kind, scope, scope_id, item);
        },
        .object => |object| {
            if (object.get("result")) |result| {
                try appendResourceRowsFromValue(gpa, rows, kind, scope, scope_id, result);
            } else if (object.get("data")) |data| {
                try appendResourceRowsFromValue(gpa, rows, kind, scope, scope_id, data);
            } else {
                try appendResourceRow(gpa, rows, kind, scope, scope_id, value);
            }
        },
        else => {},
    }
}

fn appendResourceRow(gpa: Allocator, rows: *std.ArrayList(ResourceRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, item: std.json.Value) !void {
    if (item != .object) return;
    const resource_id = try resourceIdValue(gpa, item) orelse return;
    errdefer gpa.free(resource_id);
    const key = try resourceKey(gpa, kind, scope, scope_id, resource_id);
    errdefer gpa.free(key);
    const kind_owned = try gpa.dupe(u8, kind);
    errdefer gpa.free(kind_owned);
    const scope_owned = try dupeOptional(gpa, scope);
    errdefer if (scope_owned) |value| gpa.free(value);
    const scope_id_owned = try dupeOptional(gpa, scope_id);
    errdefer if (scope_id_owned) |value| gpa.free(value);
    const name = try resourceName(gpa, item);
    errdefer if (name) |value| gpa.free(value);
    const status = try resourceStatus(gpa, item);
    errdefer if (status) |value| gpa.free(value);
    const resource_type = try resourceType(gpa, item);
    errdefer if (resource_type) |value| gpa.free(value);
    const raw = try core_json.stringifyValue(gpa, item);
    errdefer gpa.free(raw);
    try rows.append(gpa, .{
        .key = key,
        .kind = kind_owned,
        .resource_id = resource_id,
        .scope = scope_owned,
        .scope_id = scope_id_owned,
        .name = name,
        .status = status,
        .resource_type = resource_type,
        .raw_json = raw,
    });
}

fn resourceKey(gpa: Allocator, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, resource_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}|{s}|{s}|{s}", .{ kind, scope orelse "", scope_id orelse "", resource_id });
}

fn resourceName(gpa: Allocator, item: std.json.Value) !?[]u8 {
    const fields = [_][]const u8{
        "name",
        "hostname",
        "domain",
        "title",
        "zone_name",
        "account_name",
        "dataset",
        "key",
    };
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceStatus(gpa: Allocator, item: std.json.Value) !?[]u8 {
    const fields = [_][]const u8{
        "status",
        "state",
        "phase",
        "mode",
    };
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return try gpa.dupe(u8, value);
    }
    if (core_json.fieldBool(item, "enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "is_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "active")) |active| return try gpa.dupe(u8, if (active) "active" else "inactive");
    if (core_json.fieldBool(item, "paused")) |paused| return try gpa.dupe(u8, if (paused) "paused" else "active");
    return null;
}

fn resourceType(gpa: Allocator, item: std.json.Value) !?[]u8 {
    const fields = [_][]const u8{
        "type",
        "kind",
        "resource_type",
        "target_type",
        "product",
        "dataset",
    };
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceIdValue(gpa: Allocator, item: std.json.Value) !?[]u8 {
    const fields = [_][]const u8{
        "id",
        "uid",
        "issue_id",
        "operation_id",
        "discovery_id",
        "client_certificate_id",
        "uuid",
        "dataset_id",
        "dataset",
        "hostname",
        "name",
    };
    for (fields) |field_name| {
        const value = core_json.field(item, field_name) orelse continue;
        return switch (value) {
            .string => |text| try gpa.dupe(u8, text),
            .integer => |number| try std.fmt.allocPrint(gpa, "{d}", .{number}),
            else => continue,
        };
    }
    return null;
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

test "parses Cloudflare account result object row" {
    const allocator = std.testing.allocator;
    var rows = try parseAccountRows(allocator,
        \\{"result":{"id":"acct-1","name":"Main","type":"standard","status":"active"}}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("acct-1", rows.items[0].id);
    try std.testing.expectEqualStrings("Main", rows.items[0].name orelse "");
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

test "parses Cloudflare zone result object row" {
    const allocator = std.testing.allocator;
    var rows = try parseZoneRows(allocator,
        \\{"result":{"id":"zone-1","name":"plosca.ru","status":"active","paused":false,"type":"full","account":{"id":"acct-1"}}}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("zone-1", rows.items[0].id);
    try std.testing.expectEqualStrings("acct-1", rows.items[0].account_id orelse "");
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

test "parses Cloudflare DNS record result object row" {
    const allocator = std.testing.allocator;
    var rows = try parseDnsRecordRows(allocator, "zone-1",
        \\{"result":{"id":"dns-1","name":"plosca.ru","type":"A","content":"76.13.130.170","ttl":1,"proxied":true}}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("dns-1", rows.items[0].id);
    try std.testing.expectEqualStrings("zone-1", rows.items[0].zone_id);
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

test "parses generic Cloudflare resource ids from common id fields" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceIdRows(allocator,
        \\{"result":[{"id":"page-id"},{"id":42},{"uid":"access-uid"},{"issue_id":"insight-issue"},{"operation_id":"api-op"},{"discovery_id":"discovery-op"},{"client_certificate_id":"client-cert"},{"uuid":"audit-uuid"},{"dataset_id":"dataset-id"},{"dataset":"dataset-name"},{"hostname":"www.example.test"},{"name":"asset-name"},{"description":"missing"}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 12), rows.items.len);
    try std.testing.expectEqualStrings("page-id", rows.items[0].id);
    try std.testing.expectEqualStrings("42", rows.items[1].id);
    try std.testing.expectEqualStrings("access-uid", rows.items[2].id);
    try std.testing.expectEqualStrings("insight-issue", rows.items[3].id);
    try std.testing.expectEqualStrings("api-op", rows.items[4].id);
    try std.testing.expectEqualStrings("discovery-op", rows.items[5].id);
    try std.testing.expectEqualStrings("client-cert", rows.items[6].id);
    try std.testing.expectEqualStrings("audit-uuid", rows.items[7].id);
    try std.testing.expectEqualStrings("dataset-id", rows.items[8].id);
    try std.testing.expectEqualStrings("dataset-name", rows.items[9].id);
    try std.testing.expectEqualStrings("www.example.test", rows.items[10].id);
    try std.testing.expectEqualStrings("asset-name", rows.items[11].id);
}

test "parses generic Cloudflare resource ids matching a string field" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceIdRowsMatchingString(allocator,
        \\{"result":[{"id":"cloudflare-source","subnet_type":"cloudflare_source"},{"id":"warp-a","subnet_type":"warp"},{"uid":"warp-b","subnet_type":"warp"},{"id":"deleted","subnet_type":"deleted"}]}
    , "subnet_type", "warp");
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("warp-a", rows.items[0].id);
    try std.testing.expectEqualStrings("warp-b", rows.items[1].id);
}

test "parses normalized Cloudflare resource rows from result arrays" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceRows(allocator, "dns-records", "zone", "zone-1",
        \\{"result":[{"id":"record-1","name":"plosca.ru","type":"A","status":"active"},{"id":"record-2","hostname":"www.plosca.ru","type":"CNAME","proxied":false}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("dns-records|zone|zone-1|record-1", rows.items[0].key);
    try std.testing.expectEqualStrings("record-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("zone", rows.items[0].scope orelse "");
    try std.testing.expectEqualStrings("zone-1", rows.items[0].scope_id orelse "");
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("active", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("A", rows.items[0].resource_type orelse "");
}

test "parses normalized Cloudflare resource rows from result objects" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceRows(allocator, "zone-detail", "zone", "zone-1",
        \\{"success":true,"result":{"id":"zone-1","name":"plosca.ru","paused":false,"type":"full"}}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("zone-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("active", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("full", rows.items[0].resource_type orelse "");
}
