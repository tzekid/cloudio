const std = @import("std");

pub const max_params = 8;

pub const Param = struct {
    name: []const u8,
    value: []const u8,
};

pub const Params = struct {
    items: [max_params]Param = undefined,
    len: usize = 0,

    pub fn get(self: Params, name: []const u8) ?[]const u8 {
        for (self.items[0..self.len]) |item| {
            if (std.mem.eql(u8, item.name, name)) return item.value;
        }
        return null;
    }
};

pub fn Match(comptime Route: type) type {
    return struct {
        route: *const Route,
        params: Params,
    };
}

/// Route values need `method` and `pattern` string fields. A pattern segment
/// beginning with `:` captures exactly one path segment.
pub fn match(comptime Route: type, routes: []const Route, method: []const u8, path: []const u8) ?Match(Route) {
    for (routes) |*route| {
        if (!std.mem.eql(u8, route.method, method)) continue;
        if (matchPattern(route.pattern, path)) |params| return .{ .route = route, .params = params };
    }
    return null;
}

pub fn pathExists(comptime Route: type, routes: []const Route, path: []const u8) bool {
    for (routes) |route| {
        if (matchPattern(route.pattern, path) != null) return true;
    }
    return false;
}

fn matchPattern(pattern_raw: []const u8, path_raw: []const u8) ?Params {
    const pattern = normalized(pattern_raw);
    const path = normalized(path_raw);
    var patterns = std.mem.splitScalar(u8, std.mem.trim(u8, pattern, "/"), '/');
    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, path, "/"), '/');
    var params = Params{};
    while (true) {
        const expected = patterns.next();
        const actual = parts.next();
        if (expected == null or actual == null) {
            if (expected == null and actual == null) return params;
            return null;
        }
        if (expected.?.len > 1 and expected.?[0] == ':') {
            if (actual.?.len == 0 or params.len == max_params) return null;
            params.items[params.len] = .{ .name = expected.?[1..], .value = actual.? };
            params.len += 1;
        } else if (!std.mem.eql(u8, expected.?, actual.?)) {
            return null;
        }
    }
}

fn normalized(path: []const u8) []const u8 {
    if (path.len > 1) return std.mem.trimEnd(u8, path, "/");
    return path;
}

test "router matches exact paths named segments and method misses" {
    const Route = struct { method: []const u8, pattern: []const u8, id: u8 };
    const routes = [_]Route{
        .{ .method = "GET", .pattern = "/apps", .id = 1 },
        .{ .method = "GET", .pattern = "/apps/:name/deploys", .id = 2 },
    };
    try std.testing.expectEqual(@as(u8, 1), match(Route, &routes, "GET", "/apps").?.route.id);
    const dynamic = match(Route, &routes, "GET", "/apps/cloudio/deploys/").?;
    try std.testing.expectEqual(@as(u8, 2), dynamic.route.id);
    try std.testing.expectEqualStrings("cloudio", dynamic.params.get("name").?);
    try std.testing.expect(match(Route, &routes, "POST", "/apps") == null);
    try std.testing.expect(pathExists(Route, &routes, "/apps"));
    try std.testing.expect(!pathExists(Route, &routes, "/unknown"));
}
