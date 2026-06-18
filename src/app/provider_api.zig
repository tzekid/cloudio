const std = @import("std");
const app_render = @import("app_render");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Route = provider_routes.Route;
pub const RouteFamilyClassifier = *const fn (route: Route) ?[]const u8;

pub const SummaryOptions = struct {
    seed_labels: []const []const u8 = &.{},
    classifier: RouteFamilyClassifier,
};

pub const ApiRouteTotals = struct {
    official_routes: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    write_routes: usize = 0,
    not_applicable_routes: usize = 0,
    deprecated_routes: usize = 0,
    blocked_permission_routes: usize = 0,
};

pub const ApiFamilyStatusTotals = struct {
    observed_read_families: usize = 0,
    missing_read_families: usize = 0,
    blocked_or_missing_families: usize = 0,
    dry_run_only_families: usize = 0,
    not_applicable_families: usize = 0,
    observed_unmapped_families: usize = 0,
};

pub const ApiFamilySummary = struct {
    label: []u8,
    official_routes: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    write_routes: usize = 0,
    not_applicable_routes: usize = 0,
    deprecated_routes: usize = 0,
    blocked_permission_routes: usize = 0,
    observed_items: i64 = 0,
    observed_kinds: usize = 0,

    fn deinit(self: ApiFamilySummary, gpa: Allocator) void {
        gpa.free(self.label);
    }

    fn addRoute(self: *ApiFamilySummary, route: Route) void {
        self.official_routes += 1;
        if (route.deprecated or route.support == .deprecated) self.deprecated_routes += 1;
        if (route.support == .not_applicable) self.not_applicable_routes += 1;
        if (route.support == .blocked_permission) self.blocked_permission_routes += 1;
        switch (route.mode) {
            .read => self.read_routes += 1,
            .dry_run => self.dry_run_routes += 1,
            .write => self.write_routes += 1,
            .none => {},
        }
    }

    pub fn addObserved(self: *ApiFamilySummary, count: i64) void {
        if (count <= 0) return;
        self.observed_items += count;
        self.observed_kinds += 1;
    }

    pub fn status(self: ApiFamilySummary) []const u8 {
        if (self.official_routes == 0 and self.observed_items != 0) return "observed_unmapped";
        if (self.read_routes == 0 and self.dry_run_routes != 0) return "dry_run_only";
        if (self.not_applicable_routes != 0 and self.read_routes == 0 and self.dry_run_routes == 0 and self.write_routes == 0) return "not_applicable";
        if (self.observed_items != 0) return "observed";
        if (self.blocked_permission_routes != 0) return "blocked_or_missing";
        return "missing_read";
    }
};

pub const ApiFamilySummaries = struct {
    items: []ApiFamilySummary,

    pub fn deinit(self: *ApiFamilySummaries, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn addObservedByLabel(self: *ApiFamilySummaries, label: []const u8, count: i64) bool {
        const index = familyIndexByLabel(self.items, label) orelse return false;
        self.items[index].addObserved(count);
        return true;
    }

    pub fn routeTotals(self: ApiFamilySummaries) ApiRouteTotals {
        var out = ApiRouteTotals{};
        for (self.items) |row| {
            out.official_routes += row.official_routes;
            out.read_routes += row.read_routes;
            out.dry_run_routes += row.dry_run_routes;
            out.write_routes += row.write_routes;
            out.not_applicable_routes += row.not_applicable_routes;
            out.deprecated_routes += row.deprecated_routes;
            out.blocked_permission_routes += row.blocked_permission_routes;
        }
        return out;
    }

    pub fn statusTotals(self: ApiFamilySummaries) ApiFamilyStatusTotals {
        var out = ApiFamilyStatusTotals{};
        for (self.items) |row| {
            if (row.official_routes == 0 and row.observed_items != 0) {
                out.observed_unmapped_families += 1;
            } else if (row.read_routes == 0 and row.dry_run_routes != 0) {
                out.dry_run_only_families += 1;
            } else if (row.not_applicable_routes != 0 and row.read_routes == 0 and row.dry_run_routes == 0 and row.write_routes == 0) {
                out.not_applicable_families += 1;
            } else if (row.read_routes != 0 and row.observed_items != 0) {
                out.observed_read_families += 1;
            } else if (row.read_routes != 0 and row.blocked_permission_routes != 0) {
                out.blocked_or_missing_families += 1;
            } else if (row.read_routes != 0) {
                out.missing_read_families += 1;
            }
        }
        return out;
    }
};

pub fn loadProvider(io: Io, gpa: Allocator, paths: provider_routes.Paths, provider: provider_routes.Provider, options: SummaryOptions) !ApiFamilySummaries {
    var routes = try provider_routes.loadProvider(io, gpa, paths, provider);
    defer routes.deinit(gpa);
    return try fromRoutes(gpa, routes.items, options);
}

pub fn fromRoutes(gpa: Allocator, routes: []const Route, options: SummaryOptions) !ApiFamilySummaries {
    var rows = std.ArrayList(ApiFamilySummary).empty;
    errdefer deinitApiFamilySummaryList(&rows, gpa);

    for (options.seed_labels) |label| {
        if (familyIndexByLabel(rows.items, label) == null) {
            try appendApiFamilySummary(&rows, gpa, label);
        }
    }

    for (routes) |route| {
        const label = options.classifier(route) orelse continue;
        const index = try ensureApiFamilySummary(&rows, gpa, label);
        rows.items[index].addRoute(route);
    }

    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeApiFamilySummaryText(row: ApiFamilySummary, writer: anytype) !void {
    try writer.print("{s}\tofficial_routes={d}\tread_routes={d}\tdry_run_routes={d}\twrite_routes={d}\tnot_applicable_routes={d}\tdeprecated_routes={d}\tblocked_permission_routes={d}\tobserved_items={d}\tobserved_kinds={d}\tstatus={s}\n", .{
        row.label,
        row.official_routes,
        row.read_routes,
        row.dry_run_routes,
        row.write_routes,
        row.not_applicable_routes,
        row.deprecated_routes,
        row.blocked_permission_routes,
        row.observed_items,
        row.observed_kinds,
        row.status(),
    });
}

pub fn writeApiFamilySummaryJson(row: ApiFamilySummary, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "label", row.label, true);
    try app_render.writeJsonIntField(writer, "official_routes", row.official_routes, true);
    try app_render.writeJsonIntField(writer, "read_routes", row.read_routes, true);
    try app_render.writeJsonIntField(writer, "dry_run_routes", row.dry_run_routes, true);
    try app_render.writeJsonIntField(writer, "write_routes", row.write_routes, true);
    try app_render.writeJsonIntField(writer, "not_applicable_routes", row.not_applicable_routes, true);
    try app_render.writeJsonIntField(writer, "deprecated_routes", row.deprecated_routes, true);
    try app_render.writeJsonIntField(writer, "blocked_permission_routes", row.blocked_permission_routes, true);
    try app_render.writeJsonIntField(writer, "observed_items", row.observed_items, true);
    try app_render.writeJsonIntField(writer, "observed_kinds", row.observed_kinds, true);
    try app_render.writeJsonStringField(writer, "status", row.status(), false);
    try writer.writeByte('}');
}

fn ensureApiFamilySummary(rows: *std.ArrayList(ApiFamilySummary), gpa: Allocator, label: []const u8) !usize {
    if (familyIndexByLabel(rows.items, label)) |index| return index;
    try appendApiFamilySummary(rows, gpa, label);
    return rows.items.len - 1;
}

fn appendApiFamilySummary(rows: *std.ArrayList(ApiFamilySummary), gpa: Allocator, label: []const u8) !void {
    const owned = try gpa.dupe(u8, label);
    errdefer gpa.free(owned);
    try rows.append(gpa, .{ .label = owned });
}

fn familyIndexByLabel(rows: []const ApiFamilySummary, label: []const u8) ?usize {
    for (rows, 0..) |row, index| {
        if (std.mem.eql(u8, row.label, label)) return index;
    }
    return null;
}

fn deinitApiFamilySummaryList(rows: *std.ArrayList(ApiFamilySummary), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn testVpsClassifier(route: Route) ?[]const u8 {
    if (containsIgnoreCase(route.tag, "virtual machine")) return "virtual_machine";
    if (containsIgnoreCase(route.tag, "firewall")) return "firewall";
    return null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

test "provider api summaries load route families from generated manifests" {
    const allocator = std.testing.allocator;
    const labels = [_][]const u8{ "virtual_machine", "firewall" };
    var summaries = try loadProvider(std.testing.io, allocator, .{}, .hostinger, .{
        .seed_labels = labels[0..],
        .classifier = testVpsClassifier,
    });
    defer summaries.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), summaries.items.len);
    try std.testing.expectEqualStrings("virtual_machine", summaries.items[0].label);
    try std.testing.expect(summaries.items[0].official_routes > 0);
    try std.testing.expect(summaries.items[0].read_routes > 0);
    try std.testing.expect(summaries.addObservedByLabel("virtual_machine", 3));
    try std.testing.expectEqual(@as(i64, 3), summaries.items[0].observed_items);

    const totals = summaries.routeTotals();
    try std.testing.expect(totals.official_routes > 0);
    const status_totals = summaries.statusTotals();
    try std.testing.expectEqual(@as(usize, 1), status_totals.observed_read_families);
}
