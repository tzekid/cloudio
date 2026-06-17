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
        .object => try appendVpsRow(gpa, &rows, parsed.value),
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
