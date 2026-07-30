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
            for (array.items) |item| try appendInventoryRowsFromValue(gpa, rows, kind, target, item);
        },
        .object => |object| {
            if (object.get("data")) |data| {
                try appendInventoryRowsFromValue(gpa, rows, kind, target, data);
            } else if (object.get("snapshot")) |snapshot| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, snapshot);
            } else if (object.get("rules")) |rules| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, rules);
            } else if (object.get("prices")) |prices| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, prices);
            } else if (object.get("containers")) |containers| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, containers);
            } else if (object.get("entries")) |entries| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, entries);
            } else if (object.get("profiles")) |profiles| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, profiles);
            } else if (object.get("logs")) |logs| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, logs);
            } else if (object.get("lines")) |lines| {
                try appendInventoryRow(gpa, rows, kind, target, value);
                try appendInventoryRowsFromValue(gpa, rows, kind, target, lines);
            } else if (object.get("store")) |store| {
                try appendInventoryRowsFromValue(gpa, rows, kind, target, store);
                if (object.get("sales_channel")) |sales_channel| {
                    try appendInventoryRowsFromValue(gpa, rows, kind, target, sales_channel);
                }
            } else {
                try appendInventoryRow(gpa, rows, kind, target, value);
            }
        },
        else => {},
    }
}

fn appendInventoryRow(gpa: Allocator, rows: *std.ArrayList(InventoryRow), kind: []const u8, target: ?[]const u8, item: std.json.Value) !void {
    if (item != .object) return;
    const resource_id = try resourceId(gpa, item) orelse blk: {
        if (target) |value| {
            if (core_json.fieldString(item, "website_url") != null) break :blk try gpa.dupe(u8, value);
            if (item.object.get("logs") != null or item.object.get("lines") != null) break :blk try gpa.dupe(u8, value);
        }
        return;
    };
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
    const created_at = try dupeOptional(gpa, firstStringField(item, &.{ "created_at", "registered_at", "scan_started_at", "timestamp" }));
    errdefer if (created_at) |value| gpa.free(value);
    const updated_at = try dupeOptional(gpa, firstStringField(item, &.{ "updated_at", "scan_ended_at", "restore_time" }));
    errdefer if (updated_at) |value| gpa.free(value);
    const expires_at = try dupeOptional(gpa, firstStringField(item, &.{ "expires_at", "next_billing_at", "60_days_lock_expires_at" }));
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
    if (core_json.fieldAnyString(gpa, item, "resource_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "resourceId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "project_name")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "projectName")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "profile_uuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "profileUuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "segment_uuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "segmentUuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "website_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "websiteId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "snapshot_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "snapshotId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "whois_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "whoisId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "website_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "websiteId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "firewall_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "firewallId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "order_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "orderId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "subscription_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "subscriptionId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "code")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "name")) |name| {
        errdefer gpa.free(name);
        if (core_json.field(item, "user") != null or core_json.field(item, "permissions") != null or core_json.field(item, "disk_usage_mb") != null) return name;
        if (core_json.fieldAnyString(gpa, item, "type")) |typ| {
            defer gpa.free(typ);
            const composite = try std.fmt.allocPrint(gpa, "{s}|{s}", .{ name, typ });
            gpa.free(name);
            return composite;
        }
        gpa.free(name);
    }
    if (core_json.fieldAnyString(gpa, item, "domain")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "hostname")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "subdomain")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "parked_domain")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "address")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "title")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "email")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "url")) |value| return value;
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
    if (core_json.fieldAnyString(gpa, item, "user")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "content")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "external_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "link")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "line")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "message")) |value| return value;
    return null;
}

fn resourceKey(gpa: Allocator, kind: []const u8, target: ?[]const u8, resource_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}|{s}|{s}", .{ kind, target orelse "", resource_id });
}

fn resourceName(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "name")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "project_name")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "projectName")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "site_title")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "hostname")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "company_name")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "website_url")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "username")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "user")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "identifier")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "city")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "location")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "title")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "email")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "url")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "subdomain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "parked_domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "root_directory")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "app_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "address")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "code")) |value| return try gpa.dupe(u8, value);
    return null;
}

fn resourceStatus(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "status")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "state")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "health")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "subscription_status")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "subscriptionStatus")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldBool(item, "is_enabled")) |enabled| return try gpa.dupe(u8, if (enabled) "enabled" else "disabled");
    if (core_json.fieldBool(item, "is_disabled")) |disabled| return try gpa.dupe(u8, if (disabled) "disabled" else "enabled");
    if (core_json.fieldBool(item, "is_synced")) |synced| return try gpa.dupe(u8, if (synced) "synced" else "unsynced");
    if (core_json.fieldBool(item, "is_accessible")) |accessible| return try gpa.dupe(u8, if (accessible) "accessible" else "inaccessible");
    return null;
}

fn resourceCategory(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "category")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "vhost_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "payment_method")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "entity_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "redirect_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "protocol")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "source")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "app_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "package_manager")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "version")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "period_unit")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "currency")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "currency_code")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "default_currency_code")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "country")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "source_type")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "tld")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "reason")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "validation_error")) |value| return try gpa.dupe(u8, value);
    if (core_json.field(item, "plan")) |plan| {
        if (core_json.fieldString(plan, "name")) |value| return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceDomain(gpa: Allocator, item: std.json.Value, target: ?[]const u8) !?[]u8 {
    if (core_json.fieldString(item, "domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "hostname")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "website_domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "parent_domain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "subdomain")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "parked_domain")) |value| return try gpa.dupe(u8, value);
    if (target) |value| {
        if (isPlainDomainTarget(value)) return try gpa.dupe(u8, value);
    }
    return null;
}

fn resourceUsername(gpa: Allocator, item: std.json.Value) !?[]u8 {
    if (core_json.fieldString(item, "username")) |value| return try gpa.dupe(u8, value);
    if (core_json.fieldString(item, "user")) |value| return try gpa.dupe(u8, value);
    return null;
}

fn resourceRelatedId(gpa: Allocator, item: std.json.Value) ?[]u8 {
    if (core_json.fieldAnyString(gpa, item, "profile_uuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "profileUuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "segment_uuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "segmentUuid")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "resource_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "resourceId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "subscription_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "subscriptionId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "order_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "orderId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "website_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "websiteId")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "client_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "owner_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "admin_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "h_panel_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "external_id")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "website_url")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "company_name")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "identifier")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "ptr")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "address")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "link")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "url")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "email")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "title")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "code")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "source_detail")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "source")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "port")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "node_version")) |value| return value;
    if (core_json.fieldAnyString(gpa, item, "entry_file")) |value| return value;
    if (core_json.fieldString(item, "parent_domain")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.fieldString(item, "redirect_url")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.fieldString(item, "root_directory")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.fieldString(item, "location")) |value| return gpa.dupe(u8, value) catch null;
    if (core_json.field(item, "plan")) |plan| {
        if (core_json.fieldString(plan, "name")) |value| return gpa.dupe(u8, value) catch null;
    }
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
    if (core_json.fieldBool(item, "is_disabled")) |disabled| return try gpa.dupe(u8, if (disabled) "disabled" else "enabled");
    if (core_json.fieldBool(item, "is_default")) |default| return try gpa.dupe(u8, if (default) "default" else "not_default");
    if (core_json.fieldBool(item, "is_expired")) |expired| return try gpa.dupe(u8, if (expired) "expired" else "not_expired");
    if (core_json.fieldBool(item, "is_suspended")) |suspended| return try gpa.dupe(u8, if (suspended) "suspended" else "not_suspended");
    if (core_json.fieldBool(item, "is_auto_renewed")) |auto| return try gpa.dupe(u8, if (auto) "auto_renewed" else "not_auto_renewed");
    if (core_json.fieldBool(item, "is_privacy_protected")) |protected| return try gpa.dupe(u8, if (protected) "privacy_protected" else "privacy_unprotected");
    if (core_json.fieldBool(item, "is_locked")) |locked| return try gpa.dupe(u8, if (locked) "locked" else "unlocked");
    if (core_json.fieldBool(item, "is_lockable")) |lockable| return try gpa.dupe(u8, if (lockable) "lockable" else "not_lockable");
    if (core_json.fieldBool(item, "is_valid")) |valid| return try gpa.dupe(u8, if (valid) "valid" else "invalid");
    if (core_json.fieldBool(item, "is_available")) |available| return try gpa.dupe(u8, if (available) "available" else "unavailable");
    if (core_json.fieldBool(item, "is_alternative")) |alternative| return try gpa.dupe(u8, if (alternative) "alternative" else "primary");
    if (core_json.fieldBool(item, "is_synced")) |synced| return try gpa.dupe(u8, if (synced) "synced" else "unsynced");
    if (core_json.fieldBool(item, "is_accessible")) |accessible| return try gpa.dupe(u8, if (accessible) "accessible" else "inaccessible");
    if (core_json.fieldBool(item, "sync")) |sync| return try gpa.dupe(u8, if (sync) "sync" else "async");
    return null;
}

fn firstStringField(item: std.json.Value, fields: []const []const u8) ?[]const u8 {
    for (fields) |field_name| {
        if (core_json.fieldString(item, field_name)) |value| return value;
    }
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

test "parses official Hostinger nested DNS snapshot and firewall inventory shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "hostinger-control-plane", "plosca.ru",
        \\{"data":[
        \\  {"id":5341,"reason":"Zone records update request","created_at":"2025-02-27T11:54:22Z","snapshot":[
        \\    {"name":"@","type":"A","ttl":14400,"records":[{"content":"76.13.130.170","is_disabled":false}]},
        \\    {"name":"www","type":"CNAME","ttl":14400,"records":[{"content":"plosca.ru","is_disabled":true}]}
        \\  ]},
        \\  {"id":65224,"name":"HTTP and SSH only","is_synced":false,"created_at":"2021-09-01T12:00:00Z","updated_at":"2021-09-02T12:00:00Z","rules":[
        \\    {"id":1,"action":"accept","port":"22","protocol":"TCP","source":"custom","source_detail":"76.13.130.170"}
        \\  ]}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), rows.items.len);
    try std.testing.expectEqualStrings("5341", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("Zone records update request", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("@|A", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[1].related_id orelse "");
    try std.testing.expectEqualStrings("www|CNAME", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("plosca.ru", rows.items[2].related_id orelse "");
    try std.testing.expectEqualStrings("65224", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("unsynced", rows.items[3].status orelse "");
    try std.testing.expectEqualStrings("1", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("TCP", rows.items[4].category orelse "");
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[4].related_id orelse "");
}

test "parses official Hostinger billing domain hosting and VPS support shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "hostinger-control-plane", null,
        \\{"data":[
        \\  {"id":"hostingercom-vps-kvm2","name":"KVM 2","category":"VPS","prices":[{"id":"price-1","name":"Monthly","period":1,"period_unit":"month","currency":"USD","price":1799}]},
        \\  {"id":"pm-1","identifier":"**** 4242","payment_method":"card","is_default":true,"is_expired":false,"expires_at":"2028-01-01T00:00:00Z"},
        \\  {"domain":"plosca.ru","status":"active","is_privacy_protected":true,"registered_at":"2025-01-01T00:00:00Z","60_days_lock_expires_at":"2025-03-02T00:00:00Z"},
        \\  {"id":99,"country":"LT","entity_type":"individual","tld":"ru","created_at":"2026-01-01T00:00:00Z"},
        \\  {"name":"db1","user":"u123","domain":"plosca.ru","disk_usage_mb":64,"updated_at":"2026-01-02T00:00:00Z"},
        \\  {"uuid":"69f07fe2-197a-4fb3-9dae-606f965ad13d","state":"completed","options":{"app_type":"node","entry_file":"server.js","node_version":"20"},"created_at":"2024-05-29T05:49:49Z"},
        \\  {"id":1389040,"address":"76.13.130.170","ptr":"srv1307809.hstgr.cloud"},
        \\  {"id":7,"name":"Provision","state":"done","updated_at":"2026-01-03T00:00:00Z"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 9), rows.items.len);
    try std.testing.expectEqualStrings("hostingercom-vps-kvm2", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("VPS", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("price-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("month", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("pm-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("**** 4242", rows.items[2].related_id orelse "");
    try std.testing.expectEqualStrings("default", rows.items[2].flag orelse "");
    try std.testing.expectEqualStrings("plosca.ru", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("privacy_protected", rows.items[3].flag orelse "");
    try std.testing.expectEqualStrings("2025-03-02T00:00:00Z", rows.items[3].expires_at orelse "");
    try std.testing.expectEqualStrings("99", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("individual", rows.items[4].category orelse "");
    try std.testing.expectEqualStrings("db1", rows.items[5].resource_id);
    try std.testing.expectEqualStrings("u123", rows.items[5].username orelse "");
    try std.testing.expectEqualStrings("69f07fe2-197a-4fb3-9dae-606f965ad13d", rows.items[6].resource_id);
    try std.testing.expectEqualStrings("completed", rows.items[6].status orelse "");
    try std.testing.expectEqualStrings("1389040", rows.items[7].resource_id);
    try std.testing.expectEqualStrings("76.13.130.170", rows.items[7].name orelse "");
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", rows.items[7].related_id orelse "");
    try std.testing.expectEqualStrings("7", rows.items[8].resource_id);
    try std.testing.expectEqualStrings("done", rows.items[8].status orelse "");
}

test "parses official Hostinger ecommerce and Horizons website shapes" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "hostinger-websites", "site-id-1",
        \\{"data":[
        \\  {"id":"store_01J8Z5F8W9K8M4A7B3C2D1E0FG","name":"My Store","created_at":"2026-01-21T07:35:04.000000Z","updated_at":"2026-01-22T07:35:04.000000Z","version":"v2_standalone","company_name":"My Company"},
        \\  {"store":{"id":"store_2","name":null,"company_name":"Second Company","h_panel_id":"1234567","created_at":"2026-01-23T07:35:04.000000Z","default_currency_code":"usd"},"sales_channel":{"id":"scha_1","type":"custom","external_id":"channel-1"}},
        \\  {"website_url":"https://horizons.hostinger.com/123e4567-e89b-12d3-a456-426614174000?location=chatgpt"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), rows.items.len);
    try std.testing.expectEqualStrings("store_01J8Z5F8W9K8M4A7B3C2D1E0FG", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("My Store", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("v2_standalone", rows.items[0].category orelse "");
    try std.testing.expectEqualStrings("My Company", rows.items[0].related_id orelse "");
    try std.testing.expectEqualStrings("2026-01-21T07:35:04.000000Z", rows.items[0].created_at orelse "");
    try std.testing.expectEqualStrings("2026-01-22T07:35:04.000000Z", rows.items[0].updated_at orelse "");
    try std.testing.expectEqualStrings("store_2", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("Second Company", rows.items[1].name orelse "");
    try std.testing.expectEqualStrings("usd", rows.items[1].category orelse "");
    try std.testing.expectEqualStrings("1234567", rows.items[1].related_id orelse "");
    try std.testing.expectEqualStrings("scha_1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("custom", rows.items[2].category orelse "");
    try std.testing.expectEqualStrings("channel-1", rows.items[2].related_id orelse "");
    try std.testing.expectEqualStrings("site-id-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("https://horizons.hostinger.com/123e4567-e89b-12d3-a456-426614174000?location=chatgpt", rows.items[3].name orelse "");
    try std.testing.expectEqualStrings("https://horizons.hostinger.com/123e4567-e89b-12d3-a456-426614174000?location=chatgpt", rows.items[3].related_id orelse "");
}

test "parses current Hostinger schema fields across reach hosting datacenters and logs" {
    const allocator = std.testing.allocator;
    var rows = try parseInventoryRows(allocator, "hostinger-current-schema", "build-uuid-1",
        \\{"data":[
        \\  {"code":"uk-fast","title":"Europe (UK)","coordinates":{"latitude":51.5,"longitude":-0.1}},
        \\  {"uuid":"contact-1","name":"Ada","surname":"Lovelace","email":"ada@example.com","subscription_status":"subscribed","source":"manual"},
        \\  {"resource_id":44340307,"status":"active","expires_at":"2027-10-21T05:38:23.000000Z","profiles":[{"uuid":"profile-1","domain":"plosca.ru","created_at":"2026-01-21T07:35:04.000000Z","updated_at":"2026-01-22T07:35:04.000000Z"}]},
        \\  {"id":"wp-1","username":"u123","domain":"plosca.ru","site_title":"Cloudio","url":"https://plosca.ru","email":"owner@example.com","is_valid":true,"validation_error":null,"created_at":"2026-01-01T00:00:00Z"},
        \\  {"domain":"plosca.dev","is_available":true,"is_alternative":false,"restriction":null},
        \\  {"website_id":"site-1","website_url":"https://horizons.hostinger.com/site-1"},
        \\  {"logs":"added 10 packages\\n","lines":2},
        \\  {"line":"container log line"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 9), rows.items.len);
    try std.testing.expectEqualStrings("uk-fast", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("Europe (UK)", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("Europe (UK)", rows.items[0].related_id orelse "");
    try std.testing.expectEqualStrings("contact-1", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("Ada", rows.items[1].name orelse "");
    try std.testing.expectEqualStrings("subscribed", rows.items[1].status orelse "");
    try std.testing.expectEqualStrings("ada@example.com", rows.items[1].related_id orelse "");
    try std.testing.expectEqualStrings("44340307", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("profile-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("plosca.ru", rows.items[3].domain orelse "");
    try std.testing.expectEqualStrings("wp-1", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("Cloudio", rows.items[4].name orelse "");
    try std.testing.expectEqualStrings("valid", rows.items[4].flag orelse "");
    try std.testing.expectEqualStrings("https://plosca.ru", rows.items[4].related_id orelse "");
    try std.testing.expectEqualStrings("plosca.dev", rows.items[5].resource_id);
    try std.testing.expectEqualStrings("available", rows.items[5].flag orelse "");
    try std.testing.expectEqualStrings("site-1", rows.items[6].resource_id);
    try std.testing.expectEqualStrings("https://horizons.hostinger.com/site-1", rows.items[6].name orelse "");
    try std.testing.expectEqualStrings("build-uuid-1", rows.items[7].resource_id);
    try std.testing.expectEqualStrings("container log line", rows.items[8].resource_id);
}

test "parses Hostinger Docker and Reach child identifier spellings" {
    const allocator = std.testing.allocator;
    var rows = try parseResourceRows(allocator, "hostinger-child-resources", "1307809",
        \\{"data":[
        \\  {"projectName":"cloudio-stack","status":"running"},
        \\  {"project_name":"worker-stack","status":"stopped"},
        \\  {"profileUuid":"profile-1","name":"Main profile","status":"active"},
        \\  {"segmentUuid":"segment-1","name":"Customers","status":"enabled"},
        \\  {"profile_uuid":"profile-2","segment_uuid":"segment-2","name":"Dormant contacts"}
        \\]}
    );
    defer rows.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), rows.items.len);
    try std.testing.expectEqualStrings("cloudio-stack", rows.items[0].resource_id);
    try std.testing.expectEqualStrings("cloudio-stack", rows.items[0].name orelse "");
    try std.testing.expectEqualStrings("running", rows.items[0].status orelse "");
    try std.testing.expectEqualStrings("worker-stack", rows.items[1].resource_id);
    try std.testing.expectEqualStrings("worker-stack", rows.items[1].name orelse "");
    try std.testing.expectEqualStrings("profile-1", rows.items[2].resource_id);
    try std.testing.expectEqualStrings("1307809", rows.items[2].target orelse "");
    try std.testing.expectEqualStrings("segment-1", rows.items[3].resource_id);
    try std.testing.expectEqualStrings("1307809", rows.items[3].target orelse "");
    try std.testing.expectEqualStrings("profile-2", rows.items[4].resource_id);
    try std.testing.expectEqualStrings("1307809", rows.items[4].target orelse "");

    var inventory = try parseInventoryRows(allocator, "hostinger-child-inventory", "1307809",
        \\{"data":[
        \\  {"projectName":"cloudio-stack","status":"running","compose":"services:\\n  web:\\n    image: caddy:latest"},
        \\  {"project_name":"worker-stack","state":"stopped","containers":[{"id":"ctr-1","name":"worker","image":"worker:latest","status":"running"}]},
        \\  {"logs":"pulled image\\nstarted worker\\n","lines":2},
        \\  {"line":"worker log line"},
        \\  {"profileUuid":"profile-1","name":"Main profile","status":"active"},
        \\  {"segmentUuid":"segment-1","name":"Customers","status":"enabled"},
        \\  {"profile_uuid":"profile-2","segment_uuid":"segment-2","name":"Dormant contacts"}
        \\]}
    );
    defer inventory.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 8), inventory.items.len);
    try std.testing.expectEqualStrings("cloudio-stack", inventory.items[0].resource_id);
    try std.testing.expectEqualStrings("running", inventory.items[0].status orelse "");
    try std.testing.expectEqualStrings("worker-stack", inventory.items[1].resource_id);
    try std.testing.expectEqualStrings("stopped", inventory.items[1].status orelse "");
    try std.testing.expectEqualStrings("ctr-1", inventory.items[2].resource_id);
    try std.testing.expectEqualStrings("worker", inventory.items[2].name orelse "");
    try std.testing.expectEqualStrings("running", inventory.items[2].status orelse "");
    try std.testing.expectEqualStrings("1307809", inventory.items[3].resource_id);
    try std.testing.expectEqualStrings("worker log line", inventory.items[4].resource_id);
    try std.testing.expectEqualStrings("profile-1", inventory.items[5].resource_id);
    try std.testing.expectEqualStrings("profile-1", inventory.items[5].related_id orelse "");
    try std.testing.expectEqualStrings("segment-1", inventory.items[6].resource_id);
    try std.testing.expectEqualStrings("segment-1", inventory.items[6].related_id orelse "");
    try std.testing.expectEqualStrings("profile-2", inventory.items[7].resource_id);
    try std.testing.expectEqualStrings("profile-2", inventory.items[7].related_id orelse "");
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
