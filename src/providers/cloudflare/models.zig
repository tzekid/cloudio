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

pub const InventoryRow = struct {
    key: []u8,
    kind: []u8,
    resource_id: []u8,
    scope: ?[]u8,
    scope_id: ?[]u8,
    name: ?[]u8,
    status: ?[]u8,
    category: ?[]u8,
    domain: ?[]u8,
    account_id: ?[]u8,
    zone_id: ?[]u8,
    related_id: ?[]u8,
    flag: ?[]u8,
    created_at: ?[]u8,
    updated_at: ?[]u8,
    expires_at: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: InventoryRow, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        if (self.scope) |value| allocator.free(value);
        if (self.scope_id) |value| allocator.free(value);
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.category) |value| allocator.free(value);
        if (self.domain) |value| allocator.free(value);
        if (self.account_id) |value| allocator.free(value);
        if (self.zone_id) |value| allocator.free(value);
        if (self.related_id) |value| allocator.free(value);
        if (self.flag) |value| allocator.free(value);
        if (self.created_at) |value| allocator.free(value);
        if (self.updated_at) |value| allocator.free(value);
        if (self.expires_at) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const SecurityRow = struct {
    key: []u8,
    kind: []u8,
    resource_id: []u8,
    scope: ?[]u8,
    scope_id: ?[]u8,
    name: ?[]u8,
    status: ?[]u8,
    category: ?[]u8,
    severity: ?[]u8,
    action: ?[]u8,
    domain: ?[]u8,
    account_id: ?[]u8,
    zone_id: ?[]u8,
    related_id: ?[]u8,
    flag: ?[]u8,
    created_at: ?[]u8,
    updated_at: ?[]u8,
    expires_at: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: SecurityRow, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        if (self.scope) |value| allocator.free(value);
        if (self.scope_id) |value| allocator.free(value);
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.category) |value| allocator.free(value);
        if (self.severity) |value| allocator.free(value);
        if (self.action) |value| allocator.free(value);
        if (self.domain) |value| allocator.free(value);
        if (self.account_id) |value| allocator.free(value);
        if (self.zone_id) |value| allocator.free(value);
        if (self.related_id) |value| allocator.free(value);
        if (self.flag) |value| allocator.free(value);
        if (self.created_at) |value| allocator.free(value);
        if (self.updated_at) |value| allocator.free(value);
        if (self.expires_at) |value| allocator.free(value);
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
pub const InventoryRows = Rows(InventoryRow);
pub const SecurityRows = Rows(SecurityRow);

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

pub fn parseInventoryRows(gpa: Allocator, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, body: []const u8) !InventoryRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(InventoryRow);
    defer parsed.deinit();

    var rows = std.ArrayList(InventoryRow).empty;
    errdefer deinitPartial(InventoryRow, &rows, gpa);
    try appendInventoryRowsFromValue(gpa, &rows, kind, scope, scope_id, parsed.value);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseSecurityRows(gpa: Allocator, kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, body: []const u8) !SecurityRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return emptyRows(SecurityRow);
    defer parsed.deinit();

    var rows = std.ArrayList(SecurityRow).empty;
    errdefer deinitPartial(SecurityRow, &rows, gpa);
    try appendSecurityRowsFromValue(gpa, &rows, kind, scope, scope_id, parsed.value);
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

fn appendInventoryRowsFromValue(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, item);
        },
        .object => |object| {
            if (object.get("result")) |result| {
                switch (result) {
                    .array, .object => try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, result),
                    else => try appendScalarInventoryRow(gpa, rows, kind, scope, scope_id, "result", result),
                }
            } else if (object.get("data")) |data| {
                if (isDnsAnalyticsShape(value)) try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, data);
            } else if (object.get("zone_defaults")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("nameservers")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("internal_dns")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("soa")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (try appendInventoryRowWithNestedFields(gpa, rows, kind, scope, scope_id, value, object, &.{
                "roles",
                "policies",
                "permission_groups",
                "resource_groups",
                "scope",
                "objects",
                "user",
                "organizations",
                "configuration",
            })) {
                return;
            } else if (object.get("rules")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("policies")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("routes")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("connections")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("connectors")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("versions")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("settings")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("peers")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("DNSKEY")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("SigningKey")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("origins")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else if (object.get("pools")) |nested| {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
            } else {
                try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
            }
        },
        else => {},
    }
}

fn appendInventoryRowWithNestedFields(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, value: std.json.Value, object: anytype, nested_fields: []const []const u8) anyerror!bool {
    var found_nested = false;
    for (nested_fields) |field_name| {
        if (object.get(field_name) != null) {
            found_nested = true;
            break;
        }
    }
    if (!found_nested) return false;

    try appendInventoryRow(gpa, rows, kind, scope, scope_id, value);
    for (nested_fields) |field_name| {
        if (object.get(field_name)) |nested| {
            try appendInventoryRowsFromValue(gpa, rows, kind, scope, scope_id, nested);
        }
    }
    return true;
}

fn appendInventoryRow(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, item: std.json.Value) !void {
    if (item != .object) return;
    const resource_id = try resourceIdValue(gpa, item) orelse try fallbackInventoryResourceId(gpa, item) orelse return;
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
    const category = try resourceType(gpa, item);
    errdefer if (category) |value| gpa.free(value);
    const domain = try resourceDomain(gpa, item, name, scope, scope_id);
    errdefer if (domain) |value| gpa.free(value);
    const account_id = resourceAccountId(gpa, item, scope, scope_id);
    errdefer if (account_id) |value| gpa.free(value);
    const zone_id = resourceZoneId(gpa, item, scope, scope_id);
    errdefer if (zone_id) |value| gpa.free(value);
    const related_id = resourceRelatedId(gpa, item);
    errdefer if (related_id) |value| gpa.free(value);
    const flag = try resourceFlag(gpa, item);
    errdefer if (flag) |value| gpa.free(value);
    const created_at = try dupeOptional(gpa, firstStringField(item, &.{ "created_at", "created_on", "created", "created_time" }));
    errdefer if (created_at) |value| gpa.free(value);
    const updated_at = try dupeOptional(gpa, firstStringField(item, &.{ "updated_at", "updated_on", "modified_on", "modified", "last_updated", "last_seen", "last_active_at", "last_authenticated_at", "checked_time", "last_transferred_time" }));
    errdefer if (updated_at) |value| gpa.free(value);
    const expires_at = try dupeOptional(gpa, firstStringField(item, &.{ "expires_at", "expires_on", "expiration", "not_after", "expires" }));
    errdefer if (expires_at) |value| gpa.free(value);
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
        .category = category,
        .domain = domain,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .created_at = created_at,
        .updated_at = updated_at,
        .expires_at = expires_at,
        .raw_json = raw,
    });
}

fn appendScalarInventoryRow(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, label: []const u8, value: std.json.Value) !void {
    const resource_id = try gpa.dupe(u8, label);
    errdefer gpa.free(resource_id);
    const key = try resourceKey(gpa, kind, scope, scope_id, resource_id);
    errdefer gpa.free(key);
    const kind_owned = try gpa.dupe(u8, kind);
    errdefer gpa.free(kind_owned);
    const scope_owned = try dupeOptional(gpa, scope);
    errdefer if (scope_owned) |owned| gpa.free(owned);
    const scope_id_owned = try dupeOptional(gpa, scope_id);
    errdefer if (scope_id_owned) |owned| gpa.free(owned);
    const status = switch (value) {
        .string => |text| try gpa.dupe(u8, text),
        .bool => |flag| try gpa.dupe(u8, if (flag) "true" else "false"),
        .integer => |number| try std.fmt.allocPrint(gpa, "{d}", .{number}),
        else => null,
    };
    errdefer if (status) |owned| gpa.free(owned);
    const raw = try core_json.stringifyValue(gpa, value);
    errdefer gpa.free(raw);

    try rows.append(gpa, .{
        .key = key,
        .kind = kind_owned,
        .resource_id = resource_id,
        .scope = scope_owned,
        .scope_id = scope_id_owned,
        .name = null,
        .status = status,
        .category = null,
        .domain = null,
        .account_id = resourceAccountId(gpa, value, scope, scope_id),
        .zone_id = resourceZoneId(gpa, value, scope, scope_id),
        .related_id = null,
        .flag = null,
        .created_at = null,
        .updated_at = null,
        .expires_at = null,
        .raw_json = raw,
    });
}

fn appendSecurityRowsFromValue(gpa: Allocator, rows: *std.ArrayList(SecurityRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendSecurityRow(gpa, rows, kind, scope, scope_id, item);
        },
        .object => |object| {
            if (object.get("result")) |result| {
                try appendSecurityRowsFromValue(gpa, rows, kind, scope, scope_id, result);
            } else if (object.get("data")) |data| {
                try appendSecurityRowsFromValue(gpa, rows, kind, scope, scope_id, data);
            } else {
                try appendSecurityRow(gpa, rows, kind, scope, scope_id, value);
            }
        },
        else => {},
    }
}

fn appendSecurityRow(gpa: Allocator, rows: *std.ArrayList(SecurityRow), kind: []const u8, scope: ?[]const u8, scope_id: ?[]const u8, item: std.json.Value) !void {
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
    const name = try securityName(gpa, item);
    errdefer if (name) |value| gpa.free(value);
    const status = try resourceStatus(gpa, item);
    errdefer if (status) |value| gpa.free(value);
    const category = try securityCategory(gpa, item);
    errdefer if (category) |value| gpa.free(value);
    const severity = securitySeverity(gpa, item);
    errdefer if (severity) |value| gpa.free(value);
    const action = try securityAction(gpa, item);
    errdefer if (action) |value| gpa.free(value);
    const domain = try resourceDomain(gpa, item, name, scope, scope_id);
    errdefer if (domain) |value| gpa.free(value);
    const account_id = resourceAccountId(gpa, item, scope, scope_id);
    errdefer if (account_id) |value| gpa.free(value);
    const zone_id = resourceZoneId(gpa, item, scope, scope_id);
    errdefer if (zone_id) |value| gpa.free(value);
    const related_id = securityRelatedId(gpa, item, resource_id);
    errdefer if (related_id) |value| gpa.free(value);
    const flag = try securityFlag(gpa, item);
    errdefer if (flag) |value| gpa.free(value);
    const created_at = try dupeOptional(gpa, firstStringField(item, &.{ "created_at", "created_on", "created", "first_seen" }));
    errdefer if (created_at) |value| gpa.free(value);
    const updated_at = try dupeOptional(gpa, firstStringField(item, &.{ "updated_at", "modified_on", "modified", "last_updated", "last_seen", "detected_at" }));
    errdefer if (updated_at) |value| gpa.free(value);
    const expires_at = try dupeOptional(gpa, firstStringField(item, &.{ "expires_at", "expires_on", "expiration", "not_after", "valid_until" }));
    errdefer if (expires_at) |value| gpa.free(value);
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
        .category = category,
        .severity = severity,
        .action = action,
        .domain = domain,
        .account_id = account_id,
        .zone_id = zone_id,
        .related_id = related_id,
        .flag = flag,
        .created_at = created_at,
        .updated_at = updated_at,
        .expires_at = expires_at,
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
        "label",
        "display_name",
        "description",
        "comment",
        "title",
        "Name",
        "email",
        "aud",
        "subdomain",
        "host",
        "address",
        "colo_name",
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
        "decision",
        "health",
        "Tag",
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
        "class",
        "category",
        "risk_type",
        "rule_type",
        "profile_type",
        "phase",
        "action",
        "decision",
        "protocol",
        "service",
        "scheme",
        "mechanism",
        "ui_readable_name",
        "key_type",
        "algo",
        "zone_mode",
        "access",
        "target",
    };
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceDomain(gpa: Allocator, item: std.json.Value, name: ?[]const u8, scope: ?[]const u8, scope_id: ?[]const u8) !?[]u8 {
    const fields = [_][]const u8{ "domain", "domain_name", "hostname", "zone_name", "host", "address", "target" };
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| {
            if (isDomainLike(value)) return try gpa.dupe(u8, value);
        }
    }
    if (name) |value| {
        if (isDomainLike(value)) return try gpa.dupe(u8, value);
    }
    if (scope) |scope_name| {
        if (std.mem.eql(u8, scope_name, "zone")) {
            if (scope_id) |value| {
                if (isDomainLike(value)) return try gpa.dupe(u8, value);
            }
        }
    }
    return null;
}

fn resourceAccountId(gpa: Allocator, item: std.json.Value, scope: ?[]const u8, scope_id: ?[]const u8) ?[]u8 {
    if (core_json.fieldAnyString(gpa, item, "account_id")) |value| return value;
    if (core_json.field(item, "account")) |account| {
        if (core_json.fieldAnyString(gpa, account, "id")) |value| return value;
    }
    if (scope) |scope_name| {
        if (std.mem.eql(u8, scope_name, "account")) {
            if (scope_id) |value| return gpa.dupe(u8, value) catch null;
        }
    }
    return null;
}

fn resourceZoneId(gpa: Allocator, item: std.json.Value, scope: ?[]const u8, scope_id: ?[]const u8) ?[]u8 {
    if (core_json.fieldAnyString(gpa, item, "zone_id")) |value| return value;
    if (core_json.field(item, "zone")) |zone| {
        if (core_json.fieldAnyString(gpa, zone, "id")) |value| return value;
    }
    if (scope) |scope_name| {
        if (std.mem.eql(u8, scope_name, "zone")) {
            if (scope_id) |value| return gpa.dupe(u8, value) catch null;
        }
    }
    return null;
}

fn resourceRelatedId(gpa: Allocator, item: std.json.Value) ?[]u8 {
    const fields = [_][]const u8{
        "ruleset_id",
        "rule_id",
        "policy_id",
        "member_id",
        "user_id",
        "role_id",
        "permission_group_id",
        "resource_group_id",
        "user_group_id",
        "colo_name",
        "client_id",
        "connector_id",
        "tunnel_id",
        "virtual_network_id",
        "route_id",
        "pattern_id",
        "domain_id",
        "trusted_domain_id",
        "impersonation_registry_id",
        "sending_domain_restriction_id",
        "app_id",
        "application_id",
        "certificate_id",
        "custom_page_id",
        "identity_provider_id",
        "service_token_id",
        "pool_id",
        "monitor_id",
        "profile_id",
        "dataset_id",
        "ray_id",
        "version",
        "phase",
        "expression",
        "endpoint",
        "address",
        "ip",
        "ip_range",
        "tsig_id",
        "aud",
        "destination",
        "source",
        "network",
        "action",
        "value",
        "target",
        "url",
        "user_agent",
        "content",
        "public_key",
        "digest",
        "ds",
        "key_tag",
        "soa_serial",
        "last_transferred_time",
        "checked_time",
        "data_lag",
        "rows",
        "pattern",
        "sender",
        "email",
        "username",
    };
    for (fields) |field_name| {
        if (core_json.fieldAnyString(gpa, item, field_name)) |value| return value;
    }
    if (core_json.field(item, "meta")) |meta| {
        if (core_json.fieldAnyString(gpa, meta, "label")) |value| return value;
        if (core_json.fieldAnyString(gpa, meta, "scopes")) |value| return value;
        if (core_json.fieldAnyString(gpa, meta, "value")) |value| return value;
        if (core_json.fieldAnyString(gpa, meta, "key")) |value| return value;
    }
    if (core_json.field(item, "user")) |user| {
        if (core_json.fieldAnyString(gpa, user, "email")) |value| return value;
        if (core_json.fieldAnyString(gpa, user, "id")) |value| return value;
    }
    return null;
}

fn resourceFlag(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldBool(item, "enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "is_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "active")) |active| return try gpa.dupe(u8, if (active) "active" else "inactive");
    if (core_json.fieldBool(item, "paused")) |paused| return try gpa.dupe(u8, if (paused) "paused" else "active");
    if (core_json.fieldBool(item, "proxied")) |proxied| return try gpa.dupe(u8, if (proxied) "proxied" else "dns_only");
    if (core_json.fieldBool(item, "default")) |default| return try gpa.dupe(u8, if (default) "default" else "not_default");
    if (core_json.fieldBool(item, "is_default")) |default| return try gpa.dupe(u8, if (default) "default" else "not_default");
    if (core_json.fieldBool(item, "verified")) |verified| return try gpa.dupe(u8, if (verified) "verified" else "unverified");
    if (core_json.fieldBool(item, "healthy")) |healthy| return try gpa.dupe(u8, if (healthy) "healthy" else "unhealthy");
    if (core_json.fieldBool(item, "ixfr_enable")) |enabled| return try gpa.dupe(u8, if (enabled) "ixfr_enabled" else "ixfr_disabled");
    if (core_json.fieldBool(item, "dnssec_multi_signer")) |enabled| return try gpa.dupe(u8, if (enabled) "multi_signer" else "single_signer");
    if (core_json.fieldBool(item, "dnssec_presigned")) |enabled| return try gpa.dupe(u8, if (enabled) "presigned" else "live_signed");
    if (core_json.fieldBool(item, "dnssec_use_nsec3")) |enabled| return try gpa.dupe(u8, if (enabled) "nsec3" else "nsec");
    if (core_json.fieldBool(item, "enforce_dns_only")) |enabled| return try gpa.dupe(u8, if (enabled) "dns_only_enforced" else "dns_only_not_enforced");
    if (core_json.fieldBool(item, "flatten_all_cnames")) |enabled| return try gpa.dupe(u8, if (enabled) "flatten_all_cnames" else "flatten_apex_cname");
    if (core_json.fieldBool(item, "foundation_dns")) |enabled| return try gpa.dupe(u8, if (enabled) "foundation_dns" else "standard_dns");
    if (core_json.fieldBool(item, "multi_provider")) |enabled| return try gpa.dupe(u8, if (enabled) "multi_provider" else "single_provider");
    if (core_json.fieldBool(item, "secondary_overrides")) |enabled| return try gpa.dupe(u8, if (enabled) "secondary_overrides" else "no_secondary_overrides");
    if (core_json.fieldBool(item, "two_factor_authentication_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "2fa_enabled" else "2fa_disabled");
    if (core_json.fieldBool(item, "two_factor_authentication_locked")) |locked| return try gpa.dupe(u8, if (locked) "2fa_locked" else "2fa_unlocked");
    if (core_json.fieldBool(item, "suspended")) |suspended| return try gpa.dupe(u8, if (suspended) "suspended" else "not_suspended");
    if (core_json.fieldBool(item, "has_business_zones")) |has| return try gpa.dupe(u8, if (has) "has_business_zones" else "no_business_zones");
    if (core_json.fieldBool(item, "has_enterprise_zones")) |has| return try gpa.dupe(u8, if (has) "has_enterprise_zones" else "no_enterprise_zones");
    if (core_json.fieldBool(item, "has_pro_zones")) |has| return try gpa.dupe(u8, if (has) "has_pro_zones" else "no_pro_zones");
    if (core_json.fieldBool(item, "is_deleted")) |deleted| return try gpa.dupe(u8, if (deleted) "deleted" else "not_deleted");
    if (core_json.fieldBool(item, "deleted")) |deleted| return try gpa.dupe(u8, if (deleted) "deleted" else "not_deleted");
    if (core_json.fieldBool(item, "temporary")) |temporary| return try gpa.dupe(u8, if (temporary) "temporary" else "persistent");
    if (core_json.fieldBool(item, "required")) |required| return try gpa.dupe(u8, if (required) "required" else "optional");
    return null;
}

fn securityName(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (try resourceName(gpa, item)) |value| return value;
    return firstAnyStringField(gpa, item, &.{ "description", "summary", "pattern", "email", "sender", "username", "value" });
}

fn securityCategory(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (try resourceType(gpa, item)) |value| return value;
    return firstAnyStringField(gpa, item, &.{ "finding_type", "issue_type", "threat_type", "policy_type", "rule_category" });
}

fn securitySeverity(gpa: Allocator, item: std.json.Value) ?[]u8 {
    return firstAnyStringField(gpa, item, &.{ "severity", "risk", "risk_level", "priority", "confidence", "score" });
}

fn securityAction(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (firstAnyStringField(gpa, item, &.{ "action", "disposition", "mitigation", "policy_action", "recommended_action" })) |value| return value;
    if (core_json.fieldBool(item, "allowed")) |allowed| return try gpa.dupe(u8, if (allowed) "allowed" else "blocked");
    if (core_json.fieldBool(item, "allow")) |allow| return try gpa.dupe(u8, if (allow) "allow" else "deny");
    if (core_json.fieldBool(item, "blocked")) |blocked| return try gpa.dupe(u8, if (blocked) "blocked" else "not_blocked");
    return null;
}

fn securityRelatedId(gpa: Allocator, item: std.json.Value, resource_id: []const u8) ?[]u8 {
    const supporting_fields = [_][]const u8{
        "pattern",
        "sender",
        "email",
        "username",
        "value",
        "target",
        "content",
        "rule_id",
        "ruleset_id",
        "app_id",
        "application_id",
        "profile_id",
        "dataset_id",
        "ray_id",
        "phase",
    };
    for (supporting_fields) |field_name| {
        const value = core_json.fieldAnyString(gpa, item, field_name) orelse continue;
        if (!std.mem.eql(u8, value, resource_id)) return value;
        gpa.free(value);
    }
    if (resourceRelatedId(gpa, item)) |value| {
        if (!std.mem.eql(u8, value, resource_id)) return value;
        gpa.free(value);
    }
    return null;
}

fn securityFlag(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (try resourceFlag(gpa, item)) |value| return value;
    if (core_json.fieldBool(item, "dismissed")) |dismissed| return try gpa.dupe(u8, if (dismissed) "dismissed" else "not_dismissed");
    if (core_json.fieldBool(item, "mitigated")) |mitigated| return try gpa.dupe(u8, if (mitigated) "mitigated" else "not_mitigated");
    if (core_json.fieldBool(item, "verified")) |verified| return try gpa.dupe(u8, if (verified) "verified" else "unverified");
    return null;
}

fn firstAnyStringField(gpa: Allocator, item: std.json.Value, fields: []const []const u8) ?[]u8 {
    for (fields) |field_name| {
        if (core_json.fieldAnyString(gpa, item, field_name)) |value| return value;
    }
    return null;
}

fn firstStringField(item: std.json.Value, fields: []const []const u8) ?[]const u8 {
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return value;
    }
    return null;
}

fn isDomainLike(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '.') != null and
        std.mem.indexOfScalar(u8, value, '/') == null and
        std.mem.indexOfScalar(u8, value, '?') == null and
        std.mem.indexOfScalar(u8, value, '=') == null;
}

fn resourceIdValue(gpa: Allocator, item: std.json.Value) !?[]u8 {
    const fields = [_][]const u8{
        "id",
        "uid",
        "policy_id",
        "rule_id",
        "ruleset_id",
        "client_id",
        "connector_id",
        "tunnel_id",
        "route_id",
        "virtual_network_id",
        "key_tag",
        "pattern_id",
        "domain_id",
        "trusted_domain_id",
        "impersonation_registry_id",
        "sending_domain_restriction_id",
        "issue_id",
        "operation_id",
        "discovery_id",
        "client_certificate_id",
        "detection_id",
        "expression_id",
        "uuid",
        "dataset_id",
        "dataset",
        "hostname",
        "Name",
        "key",
        "network",
        "cidr",
        "prefix",
        "name",
        "tag",
        "address",
        "target",
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

fn fallbackInventoryResourceId(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (isDnsAnalyticsShape(item)) return try gpa.dupe(u8, "dns-analytics");
    if (core_json.field(item, "metrics") != null) {
        if (core_json.field(item, "dimensions")) |dimensions| {
            return try core_json.stringifyValue(gpa, dimensions);
        }
        return try gpa.dupe(u8, "dns-analytics-row");
    }
    if (core_json.field(item, "zone_defaults") != null) return try gpa.dupe(u8, "account-dns-settings");
    if (isDnsSettingsShape(item)) return try gpa.dupe(u8, "dns-settings");
    if (core_json.field(item, "nameservers") != null) return try gpa.dupe(u8, "nameservers");
    if (core_json.field(item, "ns_set") != null) return try gpa.dupe(u8, "nameservers");
    if (core_json.field(item, "internal_dns") != null) return try gpa.dupe(u8, "internal-dns");
    if (core_json.field(item, "soa") != null) return try gpa.dupe(u8, "soa");
    if (core_json.field(item, "primary_ns") != null) return try gpa.dupe(u8, "soa");
    if (core_json.field(item, "DNSKEY") != null) return try gpa.dupe(u8, "dnskey");
    if (core_json.field(item, "SigningKey") != null) return try gpa.dupe(u8, "signing-key");
    return null;
}

fn isDnsAnalyticsShape(item: std.json.Value) bool {
    return core_json.field(item, "query") != null and
        (core_json.field(item, "totals") != null or
            core_json.field(item, "time_intervals") != null or
            core_json.field(item, "data_lag") != null or
            core_json.field(item, "rows") != null);
}

fn isDnsSettingsShape(item: std.json.Value) bool {
    return core_json.field(item, "flatten_all_cnames") != null or
        core_json.field(item, "foundation_dns") != null or
        core_json.field(item, "multi_provider") != null or
        core_json.field(item, "secondary_overrides") != null or
        core_json.field(item, "zone_mode") != null or
        core_json.field(item, "enforce_dns_only") != null or
        core_json.field(item, "ns_ttl") != null or
        core_json.field(item, "auto_refresh_seconds") != null or
        core_json.field(item, "soa_serial") != null;
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
        \\{"result":[{"id":"page-id"},{"id":42},{"uid":"access-uid"},{"issue_id":"insight-issue"},{"operation_id":"api-op"},{"discovery_id":"discovery-op"},{"client_certificate_id":"client-cert"},{"detection_id":"leaked-detection"},{"expression_id":"scan-expression"},{"uuid":"audit-uuid"},{"dataset_id":"dataset-id"},{"dataset":"dataset-name"},{"hostname":"www.example.test"},{"name":"asset-name"},{"tag":"email-sending-tag"},{"description":"missing"}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 15), rows.items.len);
    try std.testing.expectEqualStrings("page-id", rows.items[0].id);
    try std.testing.expectEqualStrings("42", rows.items[1].id);
    try std.testing.expectEqualStrings("access-uid", rows.items[2].id);
    try std.testing.expectEqualStrings("insight-issue", rows.items[3].id);
    try std.testing.expectEqualStrings("api-op", rows.items[4].id);
    try std.testing.expectEqualStrings("discovery-op", rows.items[5].id);
    try std.testing.expectEqualStrings("client-cert", rows.items[6].id);
    try std.testing.expectEqualStrings("leaked-detection", rows.items[7].id);
    try std.testing.expectEqualStrings("scan-expression", rows.items[8].id);
    try std.testing.expectEqualStrings("audit-uuid", rows.items[9].id);
    try std.testing.expectEqualStrings("dataset-id", rows.items[10].id);
    try std.testing.expectEqualStrings("dataset-name", rows.items[11].id);
    try std.testing.expectEqualStrings("www.example.test", rows.items[12].id);
    try std.testing.expectEqualStrings("asset-name", rows.items[13].id);
    try std.testing.expectEqualStrings("email-sending-tag", rows.items[14].id);
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

test "parses typed Cloudflare inventory rows from broad result shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "cloudflare-inventory", "zone", "zone-1",
        \\{"result":[
        \\  {"id":"dns-1","zone_id":"zone-1","name":"plosca.ru","type":"A","content":"76.13.130.170","proxied":false,"modified_on":"2026-06-17T00:00:00Z"},
        \\  {"id":"ruleset-1","phase":"http_request_firewall_custom","kind":"zone","name":"Custom rules","last_updated":"2026-06-17T01:00:00Z"},
        \\  {"uid":"access-app-1","domain":"ssh.plosca.ru","type":"ssh","enabled":true,"account_id":"acct-1","created_at":"2026-06-16T00:00:00Z"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), rows.items.len);
    try std.testing.expectEqualStrings("cloudflare-inventory|zone|zone-1|dns-1", rows.items[0].key);
    try std.testing.expectEqualStrings("dns-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("A", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].domain orelse "");
    try std.testing.expectEqualStrings("zone-1", rows.items[0].zone_id orelse "");
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[0].related_id orelse "");
    try std.testing.expectEqualStrings("dns_only", rows.items[0].flag orelse "");
    try std.testing.expectEqualStrings("ruleset-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("http_request_firewall_custom", rows.items[1].status orelse "");
    try std.testing.expectEqualStrings("zone", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("access-app-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("acct-1", rows.items[2].account_id orelse "");
    try std.testing.expectEqualStrings("ssh.plosca.ru", rows.items[2].domain orelse "");
    try std.testing.expectEqualStrings("enabled", rows.items[2].flag orelse "");
}

test "parses typed Cloudflare inventory rows from control plane nested shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "cloudflare-control-plane", "account", "acct-1",
        \\{"result":[
        \\  {"id":"ruleset-1","name":"HTTP custom rules","kind":"zone","phase":"http_request_firewall_custom","last_updated":"2026-06-17T00:00:00Z","rules":[
        \\    {"id":"rule-1","action":"block","expression":"ip.src eq 203.0.113.10","enabled":true}
        \\  ]},
        \\  {"id":"tun-1","name":"plosca-tunnel","status":"healthy","tun_type":"cfd_tunnel","account_id":"acct-1","connections":[
        \\    {"client_id":"client-1","colo_name":"WAW","is_pending_reconnect":false,"origin_ip":"76.13.130.170","opened_at":"2026-06-17T01:00:00Z"}
        \\  ]},
        \\  {"route_id":"route-1","network":"10.0.0.0/24","virtual_network_id":"vnet-1","comment":"private subnet","deleted":false},
        \\  {"id":"access-app-1","name":"SSH","domain":"ssh.plosca.ru","type":"ssh","aud":"aud-1","policies":[
        \\    {"id":"policy-1","name":"Admins","decision":"allow","include":[{"email":"kid@example.com"}]}
        \\  ]},
        \\  {"id":"lb-pool-1","name":"origin pool","enabled":true,"origins":[
        \\    {"name":"origin-1","address":"76.13.130.170","enabled":true}
        \\  ]},
        \\  {"id":"cache_reserve","value":"on","editable":true,"modified_on":"2026-06-17T02:00:00Z"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 10), rows.items.len);
    try std.testing.expectEqualStrings("ruleset-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("http_request_firewall_custom", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("zone", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("rule-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("enabled", rows.items[1].status orelse "");
    try std.testing.expectEqualStrings("block", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("ip.src eq 203.0.113.10", rows.items[1].related_id orelse "");
    try std.testing.expectEqualStrings("tun-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("healthy", rows.items[2].status orelse "");
    try std.testing.expectEqualStrings("acct-1", rows.items[2].account_id orelse "");
    try std.testing.expectEqualStrings("client-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("WAW", rows.items[3].related_id orelse "");
    try std.testing.expectEqualStrings("route-1", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("vnet-1", rows.items[4].related_id orelse "");
    try std.testing.expectEqualStrings("not_deleted", rows.items[4].flag orelse "");
    try std.testing.expectEqualStrings("access-app-1", rows.items[5].resource_id);
    try std.testing.expectEqualStrings("ssh.plosca.ru", rows.items[5].domain orelse "");
    try std.testing.expectEqualStrings("aud-1", rows.items[5].related_id orelse "");
    try std.testing.expectEqualStrings("policy-1", rows.items[6].resource_id);
    try std.testing.expectEqualStrings("allow", rows.items[6].status orelse "");
    try std.testing.expectEqualStrings("lb-pool-1", rows.items[7].resource_id);
    try std.testing.expectEqualStrings("enabled", rows.items[7].flag orelse "");
    try std.testing.expectEqualStrings("origin-1", rows.items[8].resource_id);
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[8].related_id orelse "");
    try std.testing.expectEqualStrings("cache_reserve", rows.items[9].resource_id);
    try std.testing.expectEqualStrings("on", rows.items[9].related_id orelse "");
    try std.testing.expectEqualStrings("2026-06-17T02:00:00Z", rows.items[9].updated_at orelse "");
}

test "parses typed Cloudflare DNS control plane inventory shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "cloudflare-dns", "zone", "zone-1",
        \\{"result":[
        \\  {"status":"active","key_tag":12345,"key_type":"ksk","algorithm":"ECDSAP256SHA256","digest":"abc123","dnssec_presigned":false,"modified_on":"2026-06-17T00:00:00Z"},
        \\  {"Name":"zsk_default","Tag":"active","Location":"hsm","DNSKEY":{"flags":256,"protocol":3,"algorithm":13,"public_key":"pubkey"},"SigningKey":{"status":"active","key_tag":23456}},
        \\  {"id":"acl-1","name":"office","ip_range":"203.0.113.0/24"},
        \\  {"id":"peer-1","name":"primary","ip":"203.0.113.53","port":53,"ixfr_enable":true,"tsig_id":"tsig-1"},
        \\  {"id":"tsig-1","name":"xfr","algo":"hmac-sha256","secret":"[REDACTED]"},
        \\  {"id":"zone-1","name":"plosca.ru","peers":["peer-1"],"checked_time":"2026-06-17T01:00:00Z","last_transferred_time":"2026-06-17T00:55:00Z","soa_serial":42},
        \\  {"id":"zone-2","name":"secondary.plosca.ru","peers":["peer-1"],"auto_refresh_seconds":3600},
        \\  {"zone_defaults":{"flatten_all_cnames":true,"foundation_dns":false,"multi_provider":true,"secondary_overrides":false,"zone_mode":"standard","nameservers":{"type":"cloudflare.standard","ns_set":1},"soa":{"primary_ns":"a.ns.cloudflare.com"}}},
        \\  {"rows":1,"totals":{"queryCount":12},"min":{},"max":{},"data_lag":60,"query":{"dimensions":["queryName"],"metrics":["queryCount"]},"data":[{"dimensions":["plosca.ru"],"metrics":[12]}]}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 12), rows.items.len);
    try std.testing.expectEqualStrings("12345", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("active", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("ksk", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("abc123", rows.items[0].related_id orelse "");
    try std.testing.expectEqualStrings("live_signed", rows.items[0].flag orelse "");
    try std.testing.expectEqualStrings("2026-06-17T00:00:00Z", rows.items[0].updated_at orelse "");
    try std.testing.expectEqualStrings("zsk_default", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("zsk_default", rows.items[1].name orelse "");
    try std.testing.expectEqualStrings("active", rows.items[1].status orelse "");
    try std.testing.expectEqualStrings("acl-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("203.0.113.0/24", rows.items[2].related_id orelse "");
    try std.testing.expectEqualStrings("peer-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("203.0.113.53", rows.items[3].related_id orelse "");
    try std.testing.expectEqualStrings("ixfr_enabled", rows.items[3].flag orelse "");
    try std.testing.expectEqualStrings("tsig-1", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("hmac-sha256", rows.items[4].category orelse "");
    try std.testing.expectEqualStrings("zone-1", rows.items[5].resource_id);
    try std.testing.expectEqualStrings("42", rows.items[5].related_id orelse "");
    try std.testing.expectEqualStrings("2026-06-17T01:00:00Z", rows.items[5].updated_at orelse "");
    try std.testing.expectEqualStrings("zone-2", rows.items[6].resource_id);
    try std.testing.expectEqualStrings("dns-settings", rows.items[8].resource_id);
    try std.testing.expectEqualStrings("standard", rows.items[8].category orelse "");
    try std.testing.expectEqualStrings("flatten_all_cnames", rows.items[8].flag orelse "");
    try std.testing.expectEqualStrings("nameservers", rows.items[9].resource_id);
    try std.testing.expectEqualStrings("cloudflare.standard", rows.items[9].category orelse "");
    try std.testing.expectEqualStrings("dns-analytics", rows.items[10].resource_id);
    try std.testing.expectEqualStrings("60", rows.items[10].related_id orelse "");
    try std.testing.expectEqualStrings("[\"plosca.ru\"]", rows.items[11].resource_id);

    var scalar = try parseInventoryRows(allocator, "cloudflare-dns-status", "zone", "zone-1",
        \\{"result":"Enabled"}
    );
    defer scalar.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), scalar.items.len);
    try std.testing.expectEqualStrings("result", scalar.items[0].resource_id);
    try std.testing.expectEqualStrings("Enabled", scalar.items[0].status orelse "");
    try std.testing.expectEqualStrings("zone-1", scalar.items[0].zone_id orelse "");
}

test "parses typed Cloudflare account IAM inventory shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "cloudflare-account", "account", "acct-1",
        \\{"result":[
        \\  {"id":"member-1","email":"owner@example.com","status":"accepted","user":{"id":"user-1","email":"owner@example.com","first_name":"Kid","two_factor_authentication_enabled":true},"roles":[{"id":"role-1","name":"Account Administrator","description":"Administrative access"}],"policies":[{"id":"policy-1","access":"allow","permission_groups":[{"id":"pg-1","name":"DNS Read","meta":{"label":"dns_read","scopes":"com.cloudflare.api.account"}}],"resource_groups":[{"id":"rg-1","name":"Account resources","scope":[{"key":"com.cloudflare.api.account.acct-1","objects":[{"key":"com.cloudflare.api.zone.zone-1"}]}]}]}]},
        \\  {"id":"ug-1","name":"Admins","created_on":"2026-06-17T00:00:00Z","modified_on":"2026-06-17T01:00:00Z","policies":[{"id":"policy-2","access":"allow","permission_groups":[{"id":"pg-2"}],"resource_groups":[{"id":"rg-2"}]}]},
        \\  {"id":"ug-member-1","email":"ops@example.com","status":"pending","created_at":"2026-06-17T02:00:00Z","user":{"id":"user-2","email":"ops@example.com","first_name":"Ops"}},
        \\  {"name":"logo.svg","description":"Logo asset","url":"https://assets.example/logo.svg","last_updated":"2026-06-17T03:00:00Z"},
        \\  {"id":"ua-1","mode":"block","paused":false,"description":"Bad crawler","configuration":{"target":"ua","value":"BadBot"}},
        \\  {"id":"current-user","email":"kid@example.com","first_name":"Kid","two_factor_authentication_enabled":true,"suspended":false,"organizations":[{"id":"org-1","name":"Main Org","status":"active","roles":["Super Administrator"]}]}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 19), rows.items.len);
    try std.testing.expectEqualStrings("member-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("owner@example.com", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("accepted", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("acct-1", rows.items[0].account_id orelse "");
    try std.testing.expectEqualStrings("role-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("Account Administrator", rows.items[1].name orelse "");
    try std.testing.expectEqualStrings("policy-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("allow", rows.items[2].category orelse "");
    try std.testing.expectEqualStrings("pg-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("DNS Read", rows.items[3].name orelse "");
    try std.testing.expectEqualStrings("dns_read", rows.items[3].related_id orelse "");
    try std.testing.expectEqualStrings("rg-1", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("Account resources", rows.items[4].name orelse "");
    try std.testing.expectEqualStrings("com.cloudflare.api.account.acct-1", rows.items[5].resource_id);
    try std.testing.expectEqualStrings("com.cloudflare.api.zone.zone-1", rows.items[6].resource_id);
    try std.testing.expectEqualStrings("user-1", rows.items[7].resource_id);
    try std.testing.expectEqualStrings("owner@example.com", rows.items[7].name orelse "");
    try std.testing.expectEqualStrings("2fa_enabled", rows.items[7].flag orelse "");
    try std.testing.expectEqualStrings("ug-1", rows.items[8].resource_id);
    try std.testing.expectEqualStrings("Admins", rows.items[8].name orelse "");
    try std.testing.expectEqualStrings("2026-06-17T00:00:00Z", rows.items[8].created_at orelse "");
    try std.testing.expectEqualStrings("2026-06-17T01:00:00Z", rows.items[8].updated_at orelse "");
    try std.testing.expectEqualStrings("policy-2", rows.items[9].resource_id);
    try std.testing.expectEqualStrings("pg-2", rows.items[10].resource_id);
    try std.testing.expectEqualStrings("rg-2", rows.items[11].resource_id);
    try std.testing.expectEqualStrings("ug-member-1", rows.items[12].resource_id);
    try std.testing.expectEqualStrings("pending", rows.items[12].status orelse "");
    try std.testing.expectEqualStrings("2026-06-17T02:00:00Z", rows.items[12].created_at orelse "");
    try std.testing.expectEqualStrings("user-2", rows.items[13].resource_id);
    try std.testing.expectEqualStrings("logo.svg", rows.items[14].resource_id);
    try std.testing.expectEqualStrings("logo.svg", rows.items[14].name orelse "");
    try std.testing.expectEqualStrings("https://assets.example/logo.svg", rows.items[14].related_id orelse "");
    try std.testing.expectEqualStrings("2026-06-17T03:00:00Z", rows.items[14].updated_at orelse "");
    try std.testing.expectEqualStrings("ua-1", rows.items[15].resource_id);
    try std.testing.expectEqualStrings("block", rows.items[15].status orelse "");
    try std.testing.expectEqualStrings("Bad crawler", rows.items[15].name orelse "");
    try std.testing.expectEqualStrings("active", rows.items[15].flag orelse "");
    try std.testing.expectEqualStrings("ua", rows.items[16].resource_id);
    try std.testing.expectEqualStrings("BadBot", rows.items[16].related_id orelse "");
    try std.testing.expectEqualStrings("current-user", rows.items[17].resource_id);
    try std.testing.expectEqualStrings("kid@example.com", rows.items[17].name orelse "");
    try std.testing.expectEqualStrings("2fa_enabled", rows.items[17].flag orelse "");
    try std.testing.expectEqualStrings("org-1", rows.items[18].resource_id);
    try std.testing.expectEqualStrings("active", rows.items[18].status orelse "");
}

test "parses typed Cloudflare security rows from broad security result shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseSecurityRows(allocator, "cloudflare-security", "account", "acct-1",
        \\{"result":[
        \\  {"policy_id":"policy-1","name":"Trusted sender","is_enabled":true,"action":"allow","pattern":"*@example.com","domain":"example.com","created_at":"2026-06-17T00:00:00Z"},
        \\  {"issue_id":"issue-1","severity":"high","status":"open","class":"dns","domain":"plosca.ru","dismissed":false,"last_seen":"2026-06-17T01:00:00Z"},
        \\  {"id":"cred-1","domain":"admin.plosca.ru","risk_level":"critical","username":"kid@example.com","created_at":"2026-06-17T02:00:00Z"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), rows.items.len);
    try std.testing.expectEqualStrings("cloudflare-security|account|acct-1|policy-1", rows.items[0].key);
    try std.testing.expectEqualStrings("Trusted sender", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("enabled", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("allow", rows.items[0].action orelse "");
    try std.testing.expectEqualStrings("example.com", rows.items[0].domain orelse "");
    try std.testing.expectEqualStrings("*@example.com", rows.items[0].related_id orelse "");
    try std.testing.expectEqualStrings("acct-1", rows.items[0].account_id orelse "");
    try std.testing.expectEqualStrings("issue-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("dns", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("high", rows.items[1].severity orelse "");
    try std.testing.expectEqualStrings("not_dismissed", rows.items[1].flag orelse "");
    try std.testing.expectEqualStrings("2026-06-17T01:00:00Z", rows.items[1].updated_at orelse "");
    try std.testing.expectEqualStrings("cred-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("critical", rows.items[2].severity orelse "");
    try std.testing.expectEqualStrings("admin.plosca.ru", rows.items[2].domain orelse "");
    try std.testing.expectEqualStrings("kid@example.com", rows.items[2].related_id orelse "");
}
