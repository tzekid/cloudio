const std = @import("std");
const core_json = @import("core_json");
const net_pagination = @import("net_pagination");

const Allocator = std.mem.Allocator;

pub const VpsRow = struct {
    id: []u8,
    name: ?[]u8,
    status: ?[]u8,
    ipv4: ?[]u8,
    plan: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: VpsRow, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.ipv4) |value| allocator.free(value);
        if (self.plan) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const VpsRows = struct {
    items: []VpsRow,

    pub fn deinit(self: VpsRows, allocator: Allocator) void {
        if (self.items.len == 0) return;
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const IdRows = struct {
    items: [][]u8,

    pub fn deinit(self: IdRows, allocator: Allocator) void {
        if (self.items.len == 0) return;
        for (self.items) |id| allocator.free(id);
        allocator.free(self.items);
    }
};

pub const ResourceRow = struct {
    key: []u8,
    kind: []u8,
    resource_id: []u8,
    target: ?[]u8,
    name: ?[]u8,
    status: ?[]u8,
    domain: ?[]u8,
    raw_json: []u8,

    pub fn deinit(self: ResourceRow, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.kind);
        allocator.free(self.resource_id);
        if (self.target) |value| allocator.free(value);
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.domain) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const ResourceRows = struct {
    items: []ResourceRow,

    pub fn deinit(self: ResourceRows, allocator: Allocator) void {
        if (self.items.len == 0) return;
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const InventoryRow = struct {
    key: []u8,
    kind: []u8,
    resource_id: []u8,
    name: ?[]u8,
    status: ?[]u8,
    category: ?[]u8,
    domain: ?[]u8,
    username: ?[]u8,
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
        if (self.name) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.category) |value| allocator.free(value);
        if (self.domain) |value| allocator.free(value);
        if (self.username) |value| allocator.free(value);
        if (self.related_id) |value| allocator.free(value);
        if (self.flag) |value| allocator.free(value);
        if (self.created_at) |value| allocator.free(value);
        if (self.updated_at) |value| allocator.free(value);
        if (self.expires_at) |value| allocator.free(value);
        allocator.free(self.raw_json);
    }
};

pub const InventoryRows = struct {
    items: []InventoryRow,

    pub fn deinit(self: InventoryRows, allocator: Allocator) void {
        if (self.items.len == 0) return;
        for (self.items) |row| row.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const PaginationInfo = net_pagination.PageInfo;

pub fn parseVpsRows(gpa: Allocator, body: []const u8) !VpsRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .items = &.{} };
    defer parsed.deinit();

    var rows = std.ArrayList(VpsRow).empty;
    errdefer {
        for (rows.items) |row| row.deinit(gpa);
        rows.deinit(gpa);
    }

    switch (parsed.value) {
        .array => |array| {
            for (array.items) |item| try appendVpsRow(gpa, &rows, item);
        },
        .object => |object| {
            if (object.get("data")) |data| {
                switch (data) {
                    .array => |array| for (array.items) |item| try appendVpsRow(gpa, &rows, item),
                    .object => try appendVpsRow(gpa, &rows, data),
                    else => {},
                }
            } else {
                try appendVpsRow(gpa, &rows, parsed.value);
            }
        },
        else => {},
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn appendVpsRow(gpa: Allocator, rows: *std.ArrayList(VpsRow), item: std.json.Value) !void {
    if (!isVirtualMachineResource(item)) return;
    const id = core_json.fieldAnyString(gpa, item, "id") orelse return;
    errdefer gpa.free(id);
    const raw = try core_json.stringifyValue(gpa, item);
    errdefer gpa.free(raw);
    const name = try dupeOptional(gpa, core_json.fieldString(item, "hostname") orelse core_json.fieldString(item, "name"));
    errdefer if (name) |value| gpa.free(value);
    const status = try dupeOptional(gpa, core_json.fieldString(item, "state") orelse core_json.fieldString(item, "status"));
    errdefer if (status) |value| gpa.free(value);
    const ipv4 = try dupeOptional(gpa, core_json.firstAddress(item, "ipv4") orelse core_json.fieldString(item, "ipv4") orelse core_json.fieldString(item, "ip"));
    errdefer if (ipv4) |value| gpa.free(value);
    const plan = try dupeOptional(gpa, core_json.fieldString(item, "plan") orelse core_json.fieldString(item, "product"));
    errdefer if (plan) |value| gpa.free(value);
    try rows.append(gpa, .{
        .id = id,
        .name = name,
        .status = status,
        .ipv4 = ipv4,
        .plan = plan,
        .raw_json = raw,
    });
}

pub fn parseResourceIds(gpa: Allocator, body: []const u8) !IdRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .items = &.{} };
    defer parsed.deinit();

    var rows = std.ArrayList([]u8).empty;
    errdefer {
        for (rows.items) |id| gpa.free(id);
        rows.deinit(gpa);
    }

    const items = switch (parsed.value) {
        .array => |array| array.items,
        .object => |object| blk: {
            const data = object.get("data") orelse return .{ .items = try rows.toOwnedSlice(gpa) };
            break :blk switch (data) {
                .array => |array| array.items,
                else => return .{ .items = try rows.toOwnedSlice(gpa) },
            };
        },
        else => return .{ .items = try rows.toOwnedSlice(gpa) },
    };
    for (items) |item| {
        const id = core_json.fieldAnyString(gpa, item, "id") orelse continue;
        errdefer gpa.free(id);
        try rows.append(gpa, id);
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseDockerProjectNames(gpa: Allocator, body: []const u8) !IdRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .items = &.{} };
    defer parsed.deinit();

    var rows = std.ArrayList([]u8).empty;
    errdefer {
        for (rows.items) |name| gpa.free(name);
        rows.deinit(gpa);
    }

    try appendDockerProjectNames(gpa, &rows, parsed.value);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseResourceRows(gpa: Allocator, kind: []const u8, target: ?[]const u8, body: []const u8) !ResourceRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .items = &.{} };
    defer parsed.deinit();

    var rows = std.ArrayList(ResourceRow).empty;
    errdefer {
        for (rows.items) |row| row.deinit(gpa);
        rows.deinit(gpa);
    }

    try appendResourceRowsFromValue(gpa, &rows, kind, target, parsed.value);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn parseInventoryRows(gpa: Allocator, kind: []const u8, target: ?[]const u8, body: []const u8) !InventoryRows {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .items = &.{} };
    defer parsed.deinit();

    var rows = std.ArrayList(InventoryRow).empty;
    errdefer {
        for (rows.items) |row| row.deinit(gpa);
        rows.deinit(gpa);
    }

    try appendInventoryRowsFromValue(gpa, &rows, kind, target, parsed.value);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn appendDockerProjectNames(gpa: Allocator, rows: *std.ArrayList([]u8), value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendDockerProjectName(gpa, rows, item);
        },
        .object => |object| {
            if (object.get("data")) |data| {
                try appendDockerProjectNames(gpa, rows, data);
            } else {
                try appendDockerProjectName(gpa, rows, value);
            }
        },
        else => {},
    }
}

fn appendDockerProjectName(gpa: Allocator, rows: *std.ArrayList([]u8), item: std.json.Value) !void {
    if (item != .object) return;
    const name = core_json.fieldString(item, "name") orelse
        core_json.fieldString(item, "project_name") orelse
        core_json.fieldString(item, "projectName") orelse
        return;
    if (name.len == 0 or containsText(rows.items, name)) return;
    try rows.append(gpa, try gpa.dupe(u8, name));
}

fn appendResourceRowsFromValue(gpa: Allocator, rows: *std.ArrayList(ResourceRow), kind: []const u8, target: ?[]const u8, value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendResourceRow(gpa, rows, kind, target, item);
        },
        .object => |object| {
            if (object.get("data")) |data| {
                try appendResourceRowsFromValue(gpa, rows, kind, target, data);
            } else {
                try appendResourceRow(gpa, rows, kind, target, value);
            }
        },
        else => {},
    }
}

fn appendResourceRow(gpa: Allocator, rows: *std.ArrayList(ResourceRow), kind: []const u8, target: ?[]const u8, item: std.json.Value) !void {
    if (item != .object) return;
    const resource_id = try resourceId(gpa, item) orelse return;
    errdefer gpa.free(resource_id);
    const key = try resourceKey(gpa, kind, target, resource_id);
    errdefer gpa.free(key);
    const kind_owned = try gpa.dupe(u8, kind);
    errdefer gpa.free(kind_owned);
    const target_owned = try dupeOptional(gpa, target);
    errdefer if (target_owned) |value| gpa.free(value);
    const name = try resourceName(gpa, item);
    errdefer if (name) |value| gpa.free(value);
    const status = try resourceStatus(gpa, item);
    errdefer if (status) |value| gpa.free(value);
    const domain = try resourceDomain(gpa, item, target);
    errdefer if (domain) |value| gpa.free(value);
    const raw = try core_json.stringifyValue(gpa, item);
    errdefer gpa.free(raw);
    try rows.append(gpa, .{
        .key = key,
        .kind = kind_owned,
        .resource_id = resource_id,
        .target = target_owned,
        .name = name,
        .status = status,
        .domain = domain,
        .raw_json = raw,
    });
}

fn appendInventoryRowsFromValue(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, target: ?[]const u8, value: std.json.Value) !void {
    switch (value) {
        .array => |array| {
            for (array.items) |item| try appendInventoryRow(gpa, rows, kind, target, item);
        },
        .object => |object| {
            if (object.get("data")) |data| {
                try appendInventoryRowsFromValue(gpa, rows, kind, target, data);
            } else {
                try appendInventoryRow(gpa, rows, kind, target, value);
            }
        },
        else => {},
    }
}

fn appendInventoryRow(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, target: ?[]const u8, item: std.json.Value) !void {
    if (item != .object) return;
    const resource_id = try resourceId(gpa, item) orelse return;
    errdefer gpa.free(resource_id);
    const key = try resourceKey(gpa, kind, target, resource_id);
    errdefer gpa.free(key);
    const kind_owned = try gpa.dupe(u8, kind);
    errdefer gpa.free(kind_owned);
    const name = try resourceName(gpa, item);
    errdefer if (name) |value| gpa.free(value);
    const status = try resourceStatus(gpa, item);
    errdefer if (status) |value| gpa.free(value);
    const category = try resourceCategory(gpa, item);
    errdefer if (category) |value| gpa.free(value);
    const domain = try resourceDomain(gpa, item, target);
    errdefer if (domain) |value| gpa.free(value);
    const username = try resourceUsername(gpa, item);
    errdefer if (username) |value| gpa.free(value);
    const related_id = resourceRelatedId(gpa, item);
    errdefer if (related_id) |value| gpa.free(value);
    const flag = try resourceFlag(gpa, item);
    errdefer if (flag) |value| gpa.free(value);
    const created_at = try dupeOptional(gpa, core_json.fieldString(item, "created_at"));
    errdefer if (created_at) |value| gpa.free(value);
    const updated_at = try dupeOptional(gpa, core_json.fieldString(item, "updated_at"));
    errdefer if (updated_at) |value| gpa.free(value);
    const expires_at = try dupeOptional(gpa, core_json.fieldString(item, "expires_at") orelse core_json.fieldString(item, "next_billing_at"));
    errdefer if (expires_at) |value| gpa.free(value);
    const raw = try core_json.stringifyValue(gpa, item);
    errdefer gpa.free(raw);

    try rows.append(gpa, .{
        .key = key,
        .kind = kind_owned,
        .resource_id = resource_id,
        .name = name,
        .status = status,
        .category = category,
        .domain = domain,
        .username = username,
        .related_id = related_id,
        .flag = flag,
        .created_at = created_at,
        .updated_at = updated_at,
        .expires_at = expires_at,
        .raw_json = raw,
    });
}

fn resourceId(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldAnyString(gpa, item, "id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "uuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "domain")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "hostname")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "name")) |name| {
        errdefer gpa.free(name);
        if (core_json.fieldAnyString(gpa, item, "type")) |typ| {
            defer gpa.free(typ);
            const composite = try std.fmt.allocPrint(gpa, "{s}|{s}", .{ name, typ });
            gpa.free(name);
            return composite;
        }
        return name;
    }
    if (core_json.fieldAnyString(gpa, item, "username")) |value| return value;
    return null;
}

fn resourceKey(gpa: Allocator, kind: []const u8, target: ?[]const u8, resource_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}|{s}|{s}", .{ kind, target orelse "", resource_id });
}

fn resourceName(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "name")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "hostname")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "site_title")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "username")) |value| return try gpa.dupe(u8, value);
    return null;
}

fn resourceStatus(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "status")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "state")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldBool(item, "is_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "is_synced")) |synced| return try gpa.dupe(u8, if (synced) "synced" else "unsynced");
    return null;
}

fn resourceCategory(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "category")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "vhost_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "payment_method")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "entity_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "redirect_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.field(item, "plan")) |plan| {
        if (core_json.fieldString(plan, "name")) |value| return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceDomain(gpa: Allocator, item: std.json.Value, target: ?[]const u8) !?[]u8 {
    if (core_json.fieldString(item, "domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "hostname")) |value| return try gpa.dupe(u8, value);
    if (target) |value| {
        if (isPlainDomainTarget(value)) return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceUsername(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "username")) |value| return try gpa.dupe(u8, value);
    return null;
}

fn resourceRelatedId(gpa: Allocator, item: std.json.Value) ?[]u8 {
    if (core_json.fieldAnyString(gpa, item, "subscription_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "order_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "client_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "owner_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "admin_id")) |value| return value;
    if (core_json.fieldString(item, "parent_domain")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.fieldString(item, "redirect_url")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.field(item, "records")) |records| {
        if (records == .array) {
            for (records.array.items) |record| {
                if (core_json.fieldString(record, "content")) |value| return gpa.dupe(u8, value) catch null;
            }
        }
    }
    return null;
}

fn resourceFlag(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldBool(item, "is_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "is_default")) |default| return try gpa.dupe(u8, if (default) "default" else "not_default");
    if (core_json.fieldBool(item, "is_expired")) |expired| return try gpa.dupe(u8, if (expired) "expired" else "not_expired");
    if (core_json.fieldBool(item, "is_suspended")) |suspended| return try gpa.dupe(u8, if (suspended) "suspended" else "not_suspended");
    if (core_json.fieldBool(item, "is_auto_renewed")) |auto| return try gpa.dupe(u8, if (auto) "auto_renewed" else "not_auto_renewed");
    if (core_json.fieldBool(item, "is_privacy_protected")) |protected| return try gpa.dupe(u8, if (protected) "privacy_protected" else "privacy_unprotected");
    if (core_json.fieldBool(item, "is_locked")) |locked| return try gpa.dupe(u8, if (locked) "locked" else "unlocked");
    if (core_json.fieldBool(item, "is_valid")) |valid| return try gpa.dupe(u8, if (valid) "valid" else "invalid");
    if (core_json.fieldBool(item, "is_synced")) |synced| return try gpa.dupe(u8, if (synced) "synced" else "unsynced");
    return null;
}

fn isPlainDomainTarget(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '.') != null and
        std.mem.indexOfScalar(u8, value, '/') == null and
        std.mem.indexOfScalar(u8, value, '?') == null and
        std.mem.indexOfScalar(u8, value, '=') == null;
}

fn containsText(values: []const []u8, candidate: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

pub fn paginationInfo(body: []const u8) ?PaginationInfo {
    return net_pagination.dataPageInfo(body);
}

pub fn mergePaginatedBodies(gpa: Allocator, bodies: []const []const u8) ![]u8 {
    return try net_pagination.mergeDataPages(gpa, bodies);
}

fn dupeOptional(gpa: Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |text| try gpa.dupe(u8, text) else null;
}

test "parses ids from Hostinger array and paginated data responses" {
    const allocator = std.testing.allocator;
    var direct = try parseResourceIds(allocator,
        \\[{"id": 8123712, "name": "restart"}, {"id": "8123713", "name": "stop"}]
    );
    defer direct.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), direct.items.len);
    try std.testing.expectEqualStrings("8123712", direct.items[0]);
    try std.testing.expectEqualStrings("8123713", direct.items[1]);

    var paginated = try parseResourceIds(allocator,
        \\{"data":[{"id": 65224, "name": "HTTP and SSH only"}], "meta": {"current_page": 1}}
    );
    defer paginated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), paginated.items.len);
    try std.testing.expectEqualStrings("65224", paginated.items[0]);
}

test "parses Docker Manager project names from Hostinger envelopes" {
    const allocator = std.testing.allocator;
    var rows = try parseDockerProjectNames(allocator,
        \\{"data":[
        \\  {"name":"plosca"},
        \\  {"project_name":"workers"},
        \\  {"projectName":"legacy"},
        \\  {"name":"plosca"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), rows.items.len);
    try std.testing.expectEqualStrings("plosca", rows.items[0]);
    try std.testing.expectEqualStrings("workers", rows.items[1]);
    try std.testing.expectEqualStrings("legacy", rows.items[2]);

    var unsupported = try parseDockerProjectNames(allocator, "{\"message\":\"Unsupported OS\"}");
    defer unsupported.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), unsupported.items.len);
}

test "parses Hostinger pagination envelopes" {
    const info = paginationInfo(
        \\{"data":[{"id": 1}, {"id": 2}], "meta": {"current_page": 1, "per_page": 2, "total": 5}}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expectEqual(@as(usize, 1), info.current_page);
    try std.testing.expectEqual(@as(usize, 2), info.per_page);
    try std.testing.expectEqual(@as(usize, 5), info.total);
    try std.testing.expectEqual(@as(usize, 2), info.data_len);
    try std.testing.expect(info.hasNext());

    const last = paginationInfo(
        \\{"data":[{"id": 5}], "meta": {"current_page": 3, "per_page": 2, "total": 5}}
    ) orelse return error.TestExpectedPagination;
    try std.testing.expect(!last.hasNext());
    try std.testing.expect(paginationInfo("[{\"id\": 1}]") == null);
}

test "merges Hostinger paginated data bodies for CLI output" {
    const allocator = std.testing.allocator;
    const bodies = [_][]const u8{
        \\{"data":[{"id": 1}, {"id": 2}], "meta": {"current_page": 1, "per_page": 2, "total": 3}}
        ,
        \\{"data":[{"id": 3}], "meta": {"current_page": 2, "per_page": 2, "total": 3}}
        ,
    };
    const merged = try mergePaginatedBodies(allocator, &bodies);
    defer allocator.free(merged);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"id\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, merged, "\"pages\":2") != null);
}

test "parses normalized Hostinger resources from arrays data envelopes and single resources" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceRows(allocator, "hostinger-dns-zone", "plosca.ru",
        \\[
        \\  {"name":"@","type":"A","ttl":14400,"records":[{"content":"1.2.3.4"}]},
        \\  {"name":"www","type":"CNAME","ttl":14400,"records":[{"content":"plosca.ru"}]}
        \\]
    );
    defer rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("hostinger-dns-zone", rows.items[0].kind);
    try std.testing.expectEqualStrings("@|A", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].target orelse "");
    try std.testing.expectEqualStrings("plosca.ru", rows.items[0].domain orelse "");

    var data_rows = try parseResourceRows(allocator, "hostinger-websites", null,
        \\{"data":[{"domain":"example.com","username":"u123","is_enabled":true},{"domain":"disabled.test","username":"u456","is_enabled":false}]}
    );
    defer data_rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), data_rows.items.len);
    try std.testing.expectEqualStrings("example.com", data_rows.items[0].resource_id);
    try std.testing.expectEqualStrings("enabled", data_rows.items[0].status orelse "");

    var single = try parseResourceRows(allocator, "hostinger-subscription", null,
        \\{"id":"sub-1","name":"KVM 1","status":"active"}
    );
    defer single.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), single.items.len);
    try std.testing.expectEqualStrings("sub-1", single.items[0].resource_id);
    try std.testing.expectEqualStrings("KVM 1", single.items[0].name orelse "");
    try std.testing.expectEqualStrings("active", single.items[0].status orelse "");
}

test "parses typed Hostinger inventory rows across control plane groups" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "hostinger-inventory", "plosca.ru",
        \\{"data":[
        \\  {"id":"sub-1","name":"KVM 4","status":"active","billing_period":1,"is_auto_renewed":true,"created_at":"2026-01-01T00:00:00Z","expires_at":"2027-01-01T00:00:00Z"},
        \\  {"domain":"plosca.ru","status":"active","type":"domain","is_locked":true,"expires_at":"2027-02-01T00:00:00Z"},
        \\  {"name":"@","type":"A","ttl":14400,"records":[{"content":"76.13.130.170"}]},
        \\  {"domain":"plosca.ru","username":"u123","vhost_type":"main","is_enabled":true,"order_id":12345}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), rows.items.len);
    try std.testing.expectEqualStrings("sub-1", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("auto_renewed", rows.items[0].flag orelse "");
    try std.testing.expectEqualStrings("2027-01-01T00:00:00Z", rows.items[0].expires_at orelse "");
    try std.testing.expectEqualStrings("domain", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("locked", rows.items[1].flag orelse "");
    try std.testing.expectEqualStrings("@|A", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[2].related_id orelse "");
    try std.testing.expectEqualStrings("main", rows.items[3].category orelse "");
    try std.testing.expectEqualStrings("u123", rows.items[3].username orelse "");
    try std.testing.expectEqualStrings("12345", rows.items[3].related_id orelse "");
}

fn isVirtualMachineResource(value: std.json.Value) bool {
    return value == .object and value.object.get("id") != null and value.object.get("hostname") != null and value.object.get("state") != null;
}

test "parses Hostinger virtual machine collection rows" {
    const allocator = std.testing.allocator;
    var rows = try parseVpsRows(allocator,
        \\[{
        \\  "id": 1307809,
        \\  "plan": "KVM 4",
        \\  "hostname": "srv1307809.hstgr.cloud",
        \\  "state": "running",
        \\  "ipv4": [{"id": 1389040, "address": "76.13.130.170"}],
        \\  "template": {"id": 1034, "name": "Arch Linux"}
        \\}]
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("1307809", rows.items[0].id);
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("running", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[0].ipv4 orelse "");
    try std.testing.expectEqualStrings("KVM 4", rows.items[0].plan orelse "");
    try std.testing.expect(std.mem.indexOf(u8, rows.items[0].raw_json, "\"template\"") != null);
}

test "parses Hostinger virtual machine data envelope rows" {
    const allocator = std.testing.allocator;
    var rows = try parseVpsRows(allocator,
        \\{"data":[{"id":1307809,"plan":"KVM 4","hostname":"srv1307809.hstgr.cloud","state":"running","ipv4":[{"address":"76.13.130.170"}]}]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("1307809", rows.items[0].id);
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", rows.items[0].name orelse "");
}

test "ignores nested template-shaped objects" {
    const allocator = std.testing.allocator;
    var rows = try parseVpsRows(allocator,
        \\[
        \\  {"id": 1034, "name": "Arch Linux"},
        \\  {"id": 1307809, "hostname": "srv1307809.hstgr.cloud", "state": "running"}
        \\]
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("1307809", rows.items[0].id);
}

test "parses Hostinger virtual machine detail row" {
    const allocator = std.testing.allocator;
    var rows = try parseVpsRows(allocator,
        \\{
        \\  "id": 1307809,
        \\  "plan": "KVM 4",
        \\  "hostname": "srv1307809.hstgr.cloud",
        \\  "state": "running",
        \\  "ipv4": [{"id": 1389040, "address": "76.13.130.170"}]
        \\}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("1307809", rows.items[0].id);
}
