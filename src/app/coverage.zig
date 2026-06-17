const std = @import("std");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_manifest_bytes = 8 * 1024 * 1024;

pub const support_names = [_][]const u8{
    "implemented",
    "partial",
    "planned",
    "blocked_permission",
    "unsafe_mutation",
    "deprecated",
    "not_applicable",
};

pub const mode_names = [_][]const u8{
    "read",
    "dry_run",
    "write",
    "none",
};

pub const Paths = struct {
    cloudflare_manifest: []const u8 = "coverage/generated/cloudflare.jsonl",
    hostinger_manifest: []const u8 = "coverage/generated/hostinger.jsonl",
};

pub const ProviderFilter = enum {
    all,
    cloudflare,
    hostinger,

    pub fn parse(value: []const u8) ?ProviderFilter {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        return null;
    }

    pub fn includes(self: ProviderFilter, provider: []const u8) bool {
        return switch (self) {
            .all => true,
            .cloudflare => std.mem.eql(u8, provider, "cloudflare"),
            .hostinger => std.mem.eql(u8, provider, "hostinger"),
        };
    }
};

pub const SupportFilter = enum {
    implemented,
    partial,
    planned,
    blocked_permission,
    unsafe_mutation,
    deprecated,
    not_applicable,

    pub fn parse(value: []const u8) ?SupportFilter {
        if (std.mem.eql(u8, value, "implemented")) return .implemented;
        if (std.mem.eql(u8, value, "partial")) return .partial;
        if (std.mem.eql(u8, value, "planned")) return .planned;
        if (std.mem.eql(u8, value, "blocked_permission")) return .blocked_permission;
        if (std.mem.eql(u8, value, "unsafe_mutation")) return .unsafe_mutation;
        if (std.mem.eql(u8, value, "deprecated")) return .deprecated;
        if (std.mem.eql(u8, value, "not_applicable")) return .not_applicable;
        return null;
    }

    pub fn name(self: SupportFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: SupportFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }
};

pub const ModeFilter = enum {
    read,
    dry_run,
    write,
    none,

    pub fn parse(value: []const u8) ?ModeFilter {
        if (std.mem.eql(u8, value, "read")) return .read;
        if (std.mem.eql(u8, value, "dry_run")) return .dry_run;
        if (std.mem.eql(u8, value, "write")) return .write;
        if (std.mem.eql(u8, value, "none")) return .none;
        return null;
    }

    pub fn name(self: ModeFilter) []const u8 {
        return @tagName(self);
    }

    pub fn matches(self: ModeFilter, value: []const u8) bool {
        return std.mem.eql(u8, self.name(), value);
    }
};

pub const ProviderSummary = struct {
    name: []const u8,
    total: usize,
    deprecated: usize,
    support_counts: [support_names.len]usize,
    mode_counts: [mode_names.len]usize,

    pub fn init(name: []const u8) ProviderSummary {
        return .{
            .name = name,
            .total = 0,
            .deprecated = 0,
            .support_counts = [_]usize{0} ** support_names.len,
            .mode_counts = [_]usize{0} ** mode_names.len,
        };
    }
};

pub const TagSummary = struct {
    provider: []const u8,
    tag: []u8,
    total: usize,
    deprecated: usize,
    support_counts: [support_names.len]usize,
    mode_counts: [mode_names.len]usize,

    pub fn init(gpa: Allocator, provider: []const u8, tag: []const u8) !TagSummary {
        return .{
            .provider = provider,
            .tag = try gpa.dupe(u8, tag),
            .total = 0,
            .deprecated = 0,
            .support_counts = [_]usize{0} ** support_names.len,
            .mode_counts = [_]usize{0} ** mode_names.len,
        };
    }

    pub fn deinit(self: TagSummary, gpa: Allocator) void {
        gpa.free(self.tag);
    }
};

pub const TagSummaries = struct {
    items: []TagSummary,

    pub fn deinit(self: *TagSummaries, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: TagSummaries, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage by tag\n");
        var current_provider: ?[]const u8 = null;
        for (self.items) |row| {
            if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.provider)) {
                current_provider = row.provider;
                try writer.print("\n{s}\n", .{row.provider});
            }
            try writer.print("  {s}: total={d}", .{ row.tag, row.total });
            try writer.writeAll(" support:");
            for (support_names, 0..) |name, index| {
                const count = row.support_counts[index];
                if (count != 0) try writer.print(" {s}={d}", .{ name, count });
            }
            try writer.writeAll(" mode:");
            for (mode_names, 0..) |name, index| {
                const count = row.mode_counts[index];
                if (count != 0) try writer.print(" {s}={d}", .{ name, count });
            }
            if (row.deprecated != 0) try writer.print(" deprecated_flags={d}", .{row.deprecated});
            try writer.writeByte('\n');
        }
    }
};

pub const RouteFilter = struct {
    provider: ProviderFilter = .all,
    tag_query: ?[]const u8 = null,
    support: ?SupportFilter = null,
    mode: ?ModeFilter = null,
};

pub const CoverageRoute = struct {
    provider: []const u8,
    tag: []u8,
    method: []u8,
    path: []u8,
    operation_id: ?[]u8,
    support: []u8,
    mode: []u8,
    tests: []u8,
    deprecated: bool,
    notes: []u8,

    pub fn init(gpa: Allocator, provider: []const u8, value: std.json.Value) !CoverageRoute {
        const tag = core_json.fieldString(value, "tag") orelse return error.InvalidCoverageRow;
        const method = core_json.fieldString(value, "method") orelse return error.InvalidCoverageRow;
        const path = core_json.fieldString(value, "path") orelse return error.InvalidCoverageRow;
        const operation_id = core_json.fieldString(value, "operation_id");
        const support = core_json.fieldString(value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(value, "mode") orelse return error.InvalidCoverageRow;
        const tests = core_json.fieldString(value, "tests") orelse return error.InvalidCoverageRow;
        const deprecated = core_json.fieldBool(value, "deprecated") orelse return error.InvalidCoverageRow;
        const notes = core_json.fieldString(value, "notes") orelse return error.InvalidCoverageRow;
        _ = indexOfName(support_names[0..], support) orelse return error.InvalidCoverageSupport;
        _ = indexOfName(mode_names[0..], mode) orelse return error.InvalidCoverageMode;

        const tag_owned = try gpa.dupe(u8, tag);
        errdefer gpa.free(tag_owned);
        const method_owned = try gpa.dupe(u8, method);
        errdefer gpa.free(method_owned);
        const path_owned = try gpa.dupe(u8, path);
        errdefer gpa.free(path_owned);
        const operation_id_owned = if (operation_id) |id| try gpa.dupe(u8, id) else null;
        errdefer if (operation_id_owned) |id| gpa.free(id);
        const support_owned = try gpa.dupe(u8, support);
        errdefer gpa.free(support_owned);
        const mode_owned = try gpa.dupe(u8, mode);
        errdefer gpa.free(mode_owned);
        const tests_owned = try gpa.dupe(u8, tests);
        errdefer gpa.free(tests_owned);
        const notes_owned = try gpa.dupe(u8, notes);
        errdefer gpa.free(notes_owned);

        return .{
            .provider = provider,
            .tag = tag_owned,
            .method = method_owned,
            .path = path_owned,
            .operation_id = operation_id_owned,
            .support = support_owned,
            .mode = mode_owned,
            .tests = tests_owned,
            .deprecated = deprecated,
            .notes = notes_owned,
        };
    }

    pub fn deinit(self: CoverageRoute, gpa: Allocator) void {
        gpa.free(self.tag);
        gpa.free(self.method);
        gpa.free(self.path);
        if (self.operation_id) |id| gpa.free(id);
        gpa.free(self.support);
        gpa.free(self.mode);
        gpa.free(self.tests);
        gpa.free(self.notes);
    }
};

pub const CoverageRoutes = struct {
    items: []CoverageRoute,

    pub fn deinit(self: *CoverageRoutes, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn writeText(self: CoverageRoutes, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage routes\n");
        if (self.items.len == 0) {
            try writer.writeAll("no matching routes\n");
            return;
        }

        var current_provider: ?[]const u8 = null;
        var current_tag: ?[]const u8 = null;
        for (self.items) |row| {
            if (current_provider == null or !std.mem.eql(u8, current_provider.?, row.provider)) {
                current_provider = row.provider;
                current_tag = null;
                try writer.print("\n{s}\n", .{row.provider});
            }
            if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.tag)) {
                current_tag = row.tag;
                try writer.print("  {s}\n", .{row.tag});
            }
            try writer.print("    {s} {s} | support={s} mode={s} tests={s}", .{ row.method, row.path, row.support, row.mode, row.tests });
            if (row.deprecated) try writer.writeAll(" deprecated=true");
            if (row.operation_id) |id| try writer.print(" op={s}", .{id});
            try writer.writeByte('\n');
            if (row.notes.len != 0) try writer.print("      notes: {s}\n", .{row.notes});
        }
    }
};

pub const Summary = struct {
    cloudflare: ProviderSummary,
    hostinger: ProviderSummary,

    pub fn init() Summary {
        return .{
            .cloudflare = ProviderSummary.init("cloudflare"),
            .hostinger = ProviderSummary.init("hostinger"),
        };
    }

    pub fn total(self: Summary) usize {
        return self.cloudflare.total + self.hostinger.total;
    }

    pub fn writeText(self: Summary, writer: anytype) !void {
        try writer.writeAll("Cloudio provider coverage\n");
        try writer.print("total operations: {d}\n\n", .{self.total()});
        try writeProvider(self.cloudflare, writer);
        try writer.writeByte('\n');
        try writeProvider(self.hostinger, writer);
    }
};

pub fn load(io: Io, gpa: Allocator, paths: Paths) !Summary {
    const cloudflare_text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(cloudflare_text);
    const hostinger_text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(hostinger_text);
    return try loadFromText(gpa, cloudflare_text, hostinger_text);
}

pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !Summary {
    var summary = Summary.init();
    try summarizeProvider(gpa, "cloudflare", cloudflare_text, &summary.cloudflare);
    try summarizeProvider(gpa, "hostinger", hostinger_text, &summary.hostinger);
    return summary;
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, writer: anytype) !void {
    const summary = try load(io, gpa, paths);
    try summary.writeText(writer);
}

pub fn loadTags(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !TagSummaries {
    var rows = std.ArrayList(TagSummary).empty;
    errdefer deinitTagList(&rows, gpa);

    if (filter.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderTags(gpa, "cloudflare", text, &rows);
    }
    if (filter.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try summarizeProviderTags(gpa, "hostinger", text, &rows);
    }

    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !TagSummaries {
    var rows = std.ArrayList(TagSummary).empty;
    errdefer deinitTagList(&rows, gpa);
    if (filter.includes("cloudflare")) try summarizeProviderTags(gpa, "cloudflare", cloudflare_text, &rows);
    if (filter.includes("hostinger")) try summarizeProviderTags(gpa, "hostinger", hostinger_text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeTagsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    var rows = try loadTags(io, gpa, paths, filter);
    defer rows.deinit(gpa);
    try rows.writeText(writer);
}

pub fn loadRoutes(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter) !CoverageRoutes {
    var rows = std.ArrayList(CoverageRoute).empty;
    errdefer deinitRouteList(&rows, gpa);

    if (filter.provider.includes("cloudflare")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try appendProviderRoutes(gpa, "cloudflare", text, filter, &rows);
    }
    if (filter.provider.includes("hostinger")) {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
        defer gpa.free(text);
        try appendProviderRoutes(gpa, "hostinger", text, filter, &rows);
    }

    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: RouteFilter) !CoverageRoutes {
    var rows = std.ArrayList(CoverageRoute).empty;
    errdefer deinitRouteList(&rows, gpa);
    if (filter.provider.includes("cloudflare")) try appendProviderRoutes(gpa, "cloudflare", cloudflare_text, filter, &rows);
    if (filter.provider.includes("hostinger")) try appendProviderRoutes(gpa, "hostinger", hostinger_text, filter, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn writeRoutesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    var routes = try loadRoutes(io, gpa, paths, filter);
    defer routes.deinit(gpa);
    try routes.writeText(writer);
}

fn summarizeProvider(gpa: Allocator, provider: []const u8, text: []const u8, summary: *ProviderSummary) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        const deprecated = core_json.fieldBool(parsed.value, "deprecated") orelse return error.InvalidCoverageRow;

        summary.total += 1;
        summary.support_counts[indexOfName(support_names[0..], support) orelse return error.InvalidCoverageSupport] += 1;
        summary.mode_counts[indexOfName(mode_names[0..], mode) orelse return error.InvalidCoverageMode] += 1;
        if (deprecated) summary.deprecated += 1;
    }
}

fn summarizeProviderTags(gpa: Allocator, provider: []const u8, text: []const u8, rows: *std.ArrayList(TagSummary)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const tag = core_json.fieldString(parsed.value, "tag") orelse return error.InvalidCoverageRow;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        const deprecated = core_json.fieldBool(parsed.value, "deprecated") orelse return error.InvalidCoverageRow;

        const row = try tagRow(gpa, rows, provider, tag);
        row.total += 1;
        row.support_counts[indexOfName(support_names[0..], support) orelse return error.InvalidCoverageSupport] += 1;
        row.mode_counts[indexOfName(mode_names[0..], mode) orelse return error.InvalidCoverageMode] += 1;
        if (deprecated) row.deprecated += 1;
    }
}

fn appendProviderRoutes(gpa: Allocator, provider: []const u8, text: []const u8, filter: RouteFilter, rows: *std.ArrayList(CoverageRoute)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_provider = core_json.fieldString(parsed.value, "provider") orelse return error.InvalidCoverageRow;
        if (!std.mem.eql(u8, row_provider, provider)) return error.InvalidCoverageProvider;
        const tag = core_json.fieldString(parsed.value, "tag") orelse return error.InvalidCoverageRow;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        if (filter.tag_query) |query| {
            if (!containsIgnoreCase(tag, query)) continue;
        }
        if (filter.support) |expected| {
            if (!expected.matches(support)) continue;
        }
        if (filter.mode) |expected| {
            if (!expected.matches(mode)) continue;
        }

        const row = try CoverageRoute.init(gpa, provider, parsed.value);
        errdefer row.deinit(gpa);
        try rows.append(gpa, row);
    }
}

fn tagRow(gpa: Allocator, rows: *std.ArrayList(TagSummary), provider: []const u8, tag: []const u8) !*TagSummary {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.tag, tag)) return row;
    }
    const row = try TagSummary.init(gpa, provider, tag);
    errdefer row.deinit(gpa);
    try rows.append(gpa, row);
    return &rows.items[rows.items.len - 1];
}

fn deinitTagList(rows: *std.ArrayList(TagSummary), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitRouteList(rows: *std.ArrayList(CoverageRoute), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

fn writeProvider(summary: ProviderSummary, writer: anytype) !void {
    try writer.print("{s}: {d} operations\n", .{ summary.name, summary.total });
    try writer.writeAll("  support:");
    for (support_names, 0..) |name, index| {
        try writer.print(" {s}={d}", .{ name, summary.support_counts[index] });
    }
    try writer.writeByte('\n');
    try writer.writeAll("  mode:");
    for (mode_names, 0..) |name, index| {
        try writer.print(" {s}={d}", .{ name, summary.mode_counts[index] });
    }
    try writer.print("\n  upstream deprecated flags={d}\n", .{summary.deprecated});
}

fn indexOfName(names: []const []const u8, value: []const u8) ?usize {
    for (names, 0..) |name, index| {
        if (std.mem.eql(u8, name, value)) return index;
    }
    return null;
}

test "summarizes provider coverage jsonl by status and mode" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"cloudflare","tag":"Zone Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":null,"support":"deprecated","mode":"read","tests":"fixture","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"no write"}
        \\
    ;

    const summary = try loadFromText(allocator, cloudflare, hostinger);
    try std.testing.expectEqual(@as(usize, 4), summary.total());
    try std.testing.expectEqual(@as(usize, 2), summary.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.deprecated);
    try std.testing.expectEqual(@as(usize, 1), summary.cloudflare.support_counts[indexOfName(support_names[0..], "partial").?]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.support_counts[indexOfName(support_names[0..], "unsafe_mutation").?]);
    try std.testing.expectEqual(@as(usize, 1), summary.hostinger.mode_counts[indexOfName(mode_names[0..], "dry_run").?]);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try summary.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: 2 operations\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unsafe_mutation=1") != null);
}

test "summarizes provider coverage by tag with provider filters" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"POST","path":"/accounts","operation_id":null,"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"no write"}
        \\{"provider":"cloudflare","tag":"Zone Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":null,"support":"deprecated","mode":"read","tests":"fixture","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":null,"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var rows = try loadTagsFromText(allocator, cloudflare, hostinger, .cloudflare);
    defer rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("cloudflare", rows.items[0].provider);
    try std.testing.expectEqualStrings("Accounts", rows.items[0].tag);
    try std.testing.expectEqual(@as(usize, 2), rows.items[0].total);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[indexOfName(support_names[0..], "partial").?]);
    try std.testing.expectEqual(@as(usize, 1), rows.items[0].support_counts[indexOfName(support_names[0..], "unsafe_mutation").?]);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try rows.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage by tag\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Accounts: total=2 support: partial=1 unsafe_mutation=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger") == null);
}

test "lists provider coverage routes by provider and tag query" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"vps_getVirtualMachineListV1","support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads VPS inventory."}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads billing catalog."}
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"vps_createVirtualMachineV1","support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes in POC."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .tag_query = "vps", .support = .partial, .mode = .read });
    defer routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), routes.items.len);
    try std.testing.expectEqualStrings("hostinger", routes.items[0].provider);
    try std.testing.expectEqualStrings("VPS: Virtual machine", routes.items[0].tag);
    try std.testing.expectEqualStrings("GET", routes.items[0].method);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try routes.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage routes\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /api/vps/v1/virtual-machines | support=partial mode=read") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Billing: Catalog") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines") == null);

    var mutations = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .support = .unsafe_mutation, .mode = .dry_run });
    defer mutations.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), mutations.items.len);
    try std.testing.expectEqualStrings("POST", mutations.items[0].method);
}
