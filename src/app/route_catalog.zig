const std = @import("std");
const app_render = @import("app_render");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const default_limit = 50;
const max_metadata_bytes = 64 * 1024;

pub const ProviderFilter = provider_routes.ProviderFilter;
pub const Paths = struct {
    routes: provider_routes.Paths = .{},
    metadata: []const u8 = "coverage/generated/metadata.json",
};

pub const Options = struct {
    provider: ProviderFilter = .all,
    query: ?[]const u8 = null,
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .provider = self.provider,
            .query = self.query,
            .limit = app_render.positiveLimit(self.limit, default_limit),
        };
    }
};

pub const Metadata = struct {
    schema_version: i64,
    cloudflare_source: []u8,
    hostinger_source: []u8,
    cloudflare_operations: i64,
    hostinger_operations: i64,

    pub fn load(io: Io, gpa: Allocator, paths: Paths) !Metadata {
        const text = try Io.Dir.cwd().readFileAlloc(io, paths.metadata, gpa, .limited(max_metadata_bytes));
        defer gpa.free(text);
        return try loadFromText(gpa, text);
    }

    pub fn loadFromText(gpa: Allocator, text: []const u8) !Metadata {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, text, .{});
        defer parsed.deinit();
        const sources = core_json.field(parsed.value, "sources") orelse return error.InvalidRouteCatalogMetadata;
        const operation_counts = core_json.field(parsed.value, "operation_counts") orelse return error.InvalidRouteCatalogMetadata;
        const cloudflare_source = core_json.fieldString(sources, "cloudflare") orelse return error.InvalidRouteCatalogMetadata;
        const hostinger_source = core_json.fieldString(sources, "hostinger") orelse return error.InvalidRouteCatalogMetadata;
        return .{
            .schema_version = core_json.fieldInt(parsed.value, "schema_version") orelse return error.InvalidRouteCatalogMetadata,
            .cloudflare_source = try gpa.dupe(u8, cloudflare_source),
            .hostinger_source = try gpa.dupe(u8, hostinger_source),
            .cloudflare_operations = core_json.fieldInt(operation_counts, "cloudflare") orelse return error.InvalidRouteCatalogMetadata,
            .hostinger_operations = core_json.fieldInt(operation_counts, "hostinger") orelse return error.InvalidRouteCatalogMetadata,
        };
    }

    pub fn deinit(self: Metadata, gpa: Allocator) void {
        gpa.free(self.cloudflare_source);
        gpa.free(self.hostinger_source);
    }
};

pub const Summary = struct {
    total: usize = 0,
    visible: usize = 0,
    routable: usize = 0,
    deprecated: usize = 0,
    cloudflare: usize = 0,
    hostinger: usize = 0,
    get: usize = 0,
    post: usize = 0,
    put: usize = 0,
    patch: usize = 0,
    delete: usize = 0,
    other_methods: usize = 0,
    read: usize = 0,
    dry_run: usize = 0,
    write: usize = 0,
    none: usize = 0,
    implemented: usize = 0,
    partial: usize = 0,
    planned: usize = 0,
    blocked_permission: usize = 0,
    unsafe_mutation: usize = 0,
    deprecated_support: usize = 0,
    not_applicable: usize = 0,
    operation_ids: usize = 0,
    auth_required: usize = 0,
    anonymous: usize = 0,
    path_param_routes: usize = 0,
    query_param_routes: usize = 0,
    header_param_routes: usize = 0,
    request_body_routes: usize = 0,
    request_body_required: usize = 0,
    response_documented_routes: usize = 0,
    path_params: usize = 0,
    query_params: usize = 0,
    header_params: usize = 0,
    responses: usize = 0,

    pub fn addRoute(self: *Summary, route: provider_routes.Route, count_visible: bool) void {
        self.total += 1;
        if (count_visible) self.visible += 1;
        if (route.isRoutable()) self.routable += 1;
        if (route.deprecated) self.deprecated += 1;
        if (route.operation_id != null) self.operation_ids += 1;
        if (route.security.required) {
            self.auth_required += 1;
        } else {
            self.anonymous += 1;
        }
        if (route.path_params.len != 0) self.path_param_routes += 1;
        if (route.query_params.len != 0) self.query_param_routes += 1;
        if (route.header_params.len != 0) self.header_param_routes += 1;
        if (route.request_body.content_types.len != 0 or route.request_body.schema_refs.len != 0 or route.request_body.required) self.request_body_routes += 1;
        if (route.request_body.required) self.request_body_required += 1;
        if (route.responses.len != 0) self.response_documented_routes += 1;
        self.path_params += route.path_params.len;
        self.query_params += route.query_params.len;
        self.header_params += route.header_params.len;
        self.responses += route.responses.len;
        switch (route.provider) {
            .cloudflare => self.cloudflare += 1,
            .hostinger => self.hostinger += 1,
        }
        switch (route.method) {
            .GET => self.get += 1,
            .POST => self.post += 1,
            .PUT => self.put += 1,
            .PATCH => self.patch += 1,
            .DELETE => self.delete += 1,
            else => self.other_methods += 1,
        }
        switch (route.mode) {
            .read => self.read += 1,
            .dry_run => self.dry_run += 1,
            .write => self.write += 1,
            .none => self.none += 1,
        }
        switch (route.support) {
            .implemented => self.implemented += 1,
            .partial => self.partial += 1,
            .planned => self.planned += 1,
            .blocked_permission => self.blocked_permission += 1,
            .unsafe_mutation => self.unsafe_mutation += 1,
            .deprecated => self.deprecated_support += 1,
            .not_applicable => self.not_applicable += 1,
        }
    }
};

pub const Catalog = struct {
    paths: Paths,
    options: Options,
    metadata: Metadata,
    routes: provider_routes.RouteSet,

    pub fn load(io: Io, gpa: Allocator, paths: Paths, options: Options) !Catalog {
        const metadata = try Metadata.load(io, gpa, paths);
        errdefer metadata.deinit(gpa);
        var routes = switch (options.provider) {
            .all => try provider_routes.loadAll(io, gpa, paths.routes),
            .cloudflare => try provider_routes.loadProvider(io, gpa, paths.routes, .cloudflare),
            .hostinger => try provider_routes.loadProvider(io, gpa, paths.routes, .hostinger),
        };
        errdefer routes.deinit(gpa);
        return .{
            .paths = paths,
            .options = options.normalized(),
            .metadata = metadata,
            .routes = routes,
        };
    }

    pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, metadata_text: []const u8, options: Options) !Catalog {
        const metadata = try Metadata.loadFromText(gpa, metadata_text);
        errdefer metadata.deinit(gpa);
        var routes = switch (options.provider) {
            .all => try provider_routes.loadAllFromText(gpa, cloudflare_text, hostinger_text),
            .cloudflare => try provider_routes.loadProviderFromText(gpa, .cloudflare, cloudflare_text),
            .hostinger => try provider_routes.loadProviderFromText(gpa, .hostinger, hostinger_text),
        };
        errdefer routes.deinit(gpa);
        return .{
            .paths = .{},
            .options = options.normalized(),
            .metadata = metadata,
            .routes = routes,
        };
    }

    pub fn deinit(self: *Catalog, gpa: Allocator) void {
        self.metadata.deinit(gpa);
        self.routes.deinit(gpa);
    }

    pub fn summary(self: Catalog) Summary {
        var out = Summary{};
        const limit: usize = @intCast(self.options.limit);
        for (self.routes.items) |route| {
            if (!matches(route, self.options)) continue;
            out.addRoute(route, out.visible < limit);
        }
        return out;
    }

    pub fn buildGroups(self: Catalog, gpa: Allocator) ![]RouteGroup {
        var groups = std.ArrayList(RouteGroup).empty;
        errdefer groups.deinit(gpa);
        for (self.routes.items) |route| {
            if (!matches(route, self.options)) continue;
            if (findRouteGroup(groups.items, route.provider, route.tag)) |index| {
                groups.items[index].addRoute(route);
            } else {
                try groups.append(gpa, .{
                    .provider = route.provider,
                    .tag = route.tag,
                });
                groups.items[groups.items.len - 1].addRoute(route);
            }
        }
        std.mem.sort(RouteGroup, groups.items, {}, routeGroupLessThan);
        return try groups.toOwnedSlice(gpa);
    }

    pub fn writeText(self: Catalog, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Cloudio route catalog\n");
        try writer.print("source cloudflare={s} operations={d} manifest={s}\n", .{ self.metadata.cloudflare_source, self.metadata.cloudflare_operations, self.paths.routes.cloudflare_manifest });
        try writer.print("source hostinger={s} operations={d} manifest={s}\n", .{ self.metadata.hostinger_source, self.metadata.hostinger_operations, self.paths.routes.hostinger_manifest });
        try writer.print("filter provider={s} query={s} limit={d}\n", .{ self.options.provider.name(), self.options.query orelse "", self.options.limit });
        try writer.print("summary total={d} visible={d} routable={d} deprecated={d} read={d} dry_run={d} write={d} none={d}\n", .{
            counts.total,
            counts.visible,
            counts.routable,
            counts.deprecated,
            counts.read,
            counts.dry_run,
            counts.write,
            counts.none,
        });
        if (counts.total == 0) {
            try writer.writeAll("no matching routes\n");
            return;
        }

        const limit: usize = @intCast(self.options.limit);
        var written: usize = 0;
        var current_provider: ?provider_routes.Provider = null;
        for (self.routes.items) |route| {
            if (!matches(route, self.options)) continue;
            if (written >= limit) break;
            if (current_provider == null or current_provider.? != route.provider) {
                current_provider = route.provider;
                try writer.print("\n{s}\n", .{route.provider.name()});
            }
            try writer.print("  {s} {s} [{s}/{s}] {s}", .{ route.method.name(), route.path_template, @tagName(route.support), @tagName(route.mode), route.tag });
            if (route.operation_id) |operation_id| try writer.print(" op={s}", .{operation_id});
            if (route.deprecated) try writer.writeAll(" deprecated=true");
            try writer.writeByte('\n');
            written += 1;
        }
    }

    pub fn writeJson(self: Catalog, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "kind", "route_catalog", true);
        try writer.writeAll("\"source\":{");
        try app_render.writeJsonIntField(writer, "schema_version", self.metadata.schema_version, true);
        try app_render.writeJsonStringField(writer, "cloudflare_openapi", self.metadata.cloudflare_source, true);
        try app_render.writeJsonStringField(writer, "hostinger_openapi", self.metadata.hostinger_source, true);
        try app_render.writeJsonIntField(writer, "cloudflare_operations", self.metadata.cloudflare_operations, true);
        try app_render.writeJsonIntField(writer, "hostinger_operations", self.metadata.hostinger_operations, true);
        try app_render.writeJsonStringField(writer, "cloudflare_manifest", self.paths.routes.cloudflare_manifest, true);
        try app_render.writeJsonStringField(writer, "hostinger_manifest", self.paths.routes.hostinger_manifest, false);
        try writer.writeAll("},\"filter\":{");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.name(), true);
        try writeNullableJsonStringField(writer, "query", self.options.query, true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, false);
        try writer.writeAll("},\"summary\":");
        try writeSummaryJson(writer, counts);
        try writer.writeAll(",\"routes\":[");
        const limit: usize = @intCast(self.options.limit);
        var first = true;
        var written: usize = 0;
        for (self.routes.items) |route| {
            if (!matches(route, self.options)) continue;
            if (written >= limit) break;
            if (!first) try writer.writeByte(',');
            first = false;
            try writeRouteJson(writer, route);
            written += 1;
        }
        try writer.writeAll("]}\n");
    }
};

pub const RouteGroup = struct {
    provider: provider_routes.Provider,
    tag: []const u8,
    summary: Summary = .{},

    pub fn addRoute(self: *RouteGroup, route: provider_routes.Route) void {
        self.summary.addRoute(route, true);
    }
};

pub const GroupSummary = struct {
    groups_total: usize = 0,
    groups_visible: usize = 0,
    route_summary: Summary = .{},
};

pub const GroupReport = struct {
    catalog: Catalog,
    groups: []RouteGroup,

    pub fn load(io: Io, gpa: Allocator, paths: Paths, options: Options) !GroupReport {
        var catalog = try Catalog.load(io, gpa, paths, options);
        errdefer catalog.deinit(gpa);
        const groups = try catalog.buildGroups(gpa);
        errdefer gpa.free(groups);
        return .{ .catalog = catalog, .groups = groups };
    }

    pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, metadata_text: []const u8, options: Options) !GroupReport {
        var catalog = try Catalog.loadFromText(gpa, cloudflare_text, hostinger_text, metadata_text, options);
        errdefer catalog.deinit(gpa);
        const groups = try catalog.buildGroups(gpa);
        errdefer gpa.free(groups);
        return .{ .catalog = catalog, .groups = groups };
    }

    pub fn deinit(self: *GroupReport, gpa: Allocator) void {
        gpa.free(self.groups);
        self.catalog.deinit(gpa);
    }

    pub fn summary(self: GroupReport) GroupSummary {
        const limit: usize = @intCast(self.catalog.options.limit);
        const out = GroupSummary{
            .groups_total = self.groups.len,
            .groups_visible = @min(self.groups.len, limit),
            .route_summary = self.catalog.summary(),
        };
        return out;
    }

    pub fn writeText(self: GroupReport, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeAll("Cloudio route catalog groups\n");
        try writer.print("source cloudflare={s} operations={d} manifest={s}\n", .{ self.catalog.metadata.cloudflare_source, self.catalog.metadata.cloudflare_operations, self.catalog.paths.routes.cloudflare_manifest });
        try writer.print("source hostinger={s} operations={d} manifest={s}\n", .{ self.catalog.metadata.hostinger_source, self.catalog.metadata.hostinger_operations, self.catalog.paths.routes.hostinger_manifest });
        try writer.print("filter provider={s} query={s} limit={d}\n", .{ self.catalog.options.provider.name(), self.catalog.options.query orelse "", self.catalog.options.limit });
        try writer.print("summary groups={d} visible={d} routes={d} routable={d} read={d} dry_run={d} deprecated={d} auth_required={d} request_body_required={d}\n", .{
            counts.groups_total,
            counts.groups_visible,
            counts.route_summary.total,
            counts.route_summary.routable,
            counts.route_summary.read,
            counts.route_summary.dry_run,
            counts.route_summary.deprecated,
            counts.route_summary.auth_required,
            counts.route_summary.request_body_required,
        });
        if (self.groups.len == 0) {
            try writer.writeAll("no matching route groups\n");
            return;
        }
        const limit: usize = @intCast(self.catalog.options.limit);
        for (self.groups[0..@min(self.groups.len, limit)]) |group| {
            try writer.print("{s}\t{s}\toperations={d}\troutable={d}\tread={d}\tdry_run={d}\tnone={d}\tdeprecated={d}\tpath_params={d}\tquery_params={d}\tbody_required={d}\tresponses={d}\tauth_required={d}\n", .{
                group.provider.name(),
                group.tag,
                group.summary.total,
                group.summary.routable,
                group.summary.read,
                group.summary.dry_run,
                group.summary.none,
                group.summary.deprecated,
                group.summary.path_params,
                group.summary.query_params,
                group.summary.request_body_required,
                group.summary.responses,
                group.summary.auth_required,
            });
        }
    }

    pub fn writeJson(self: GroupReport, writer: anytype) !void {
        const counts = self.summary();
        try writer.writeByte('{');
        try app_render.writeJsonStringField(writer, "kind", "route_catalog_groups", true);
        try writer.writeAll("\"source\":{");
        try app_render.writeJsonIntField(writer, "schema_version", self.catalog.metadata.schema_version, true);
        try app_render.writeJsonStringField(writer, "cloudflare_openapi", self.catalog.metadata.cloudflare_source, true);
        try app_render.writeJsonStringField(writer, "hostinger_openapi", self.catalog.metadata.hostinger_source, true);
        try app_render.writeJsonIntField(writer, "cloudflare_operations", self.catalog.metadata.cloudflare_operations, true);
        try app_render.writeJsonIntField(writer, "hostinger_operations", self.catalog.metadata.hostinger_operations, true);
        try app_render.writeJsonStringField(writer, "cloudflare_manifest", self.catalog.paths.routes.cloudflare_manifest, true);
        try app_render.writeJsonStringField(writer, "hostinger_manifest", self.catalog.paths.routes.hostinger_manifest, false);
        try writer.writeAll("},\"filter\":{");
        try app_render.writeJsonStringField(writer, "provider", self.catalog.options.provider.name(), true);
        try writeNullableJsonStringField(writer, "query", self.catalog.options.query, true);
        try app_render.writeJsonIntField(writer, "limit", self.catalog.options.limit, false);
        try writer.writeAll("},\"summary\":{");
        try app_render.writeJsonIntField(writer, "groups_total", counts.groups_total, true);
        try app_render.writeJsonIntField(writer, "groups_visible", counts.groups_visible, true);
        try writer.writeAll("\"routes\":");
        try writeSummaryJson(writer, counts.route_summary);
        try writer.writeAll("},\"groups\":[");
        const limit: usize = @intCast(self.catalog.options.limit);
        var first = true;
        for (self.groups[0..@min(self.groups.len, limit)]) |group| {
            if (!first) try writer.writeByte(',');
            first = false;
            try writeRouteGroupJson(writer, group);
        }
        try writer.writeAll("]}\n");
    }
};

pub fn writeText(io: Io, gpa: Allocator, paths: Paths, options: Options, writer: anytype) !void {
    var catalog = try Catalog.load(io, gpa, paths, options);
    defer catalog.deinit(gpa);
    try catalog.writeText(writer);
}

pub fn writeJson(io: Io, gpa: Allocator, paths: Paths, options: Options, writer: anytype) !void {
    var catalog = try Catalog.load(io, gpa, paths, options);
    defer catalog.deinit(gpa);
    try catalog.writeJson(writer);
}

pub fn writeGroupsText(io: Io, gpa: Allocator, paths: Paths, options: Options, writer: anytype) !void {
    var report = try GroupReport.load(io, gpa, paths, options);
    defer report.deinit(gpa);
    try report.writeText(writer);
}

pub fn writeGroupsJson(io: Io, gpa: Allocator, paths: Paths, options: Options, writer: anytype) !void {
    var report = try GroupReport.load(io, gpa, paths, options);
    defer report.deinit(gpa);
    try report.writeJson(writer);
}

fn matches(route: provider_routes.Route, options: Options) bool {
    if (!options.provider.includesProvider(route.provider)) return false;
    if (options.query) |query| {
        if (containsIgnoreCase(route.tag, query)) return true;
        if (containsIgnoreCase(route.path_template, query)) return true;
        if (route.operation_id) |operation_id| {
            if (containsIgnoreCase(operation_id, query)) return true;
        }
        return false;
    }
    return true;
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

fn findRouteGroup(groups: []const RouteGroup, provider: provider_routes.Provider, tag: []const u8) ?usize {
    for (groups, 0..) |group, index| {
        if (group.provider == provider and std.mem.eql(u8, group.tag, tag)) return index;
    }
    return null;
}

fn routeGroupLessThan(_: void, lhs: RouteGroup, rhs: RouteGroup) bool {
    const lhs_provider = @intFromEnum(lhs.provider);
    const rhs_provider = @intFromEnum(rhs.provider);
    if (lhs_provider != rhs_provider) return lhs_provider < rhs_provider;
    const tag_order = std.mem.order(u8, lhs.tag, rhs.tag);
    if (tag_order != .eq) return tag_order == .lt;
    return lhs.summary.total > rhs.summary.total;
}

fn writeSummaryJson(writer: anytype, counts: Summary) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "total", counts.total, true);
    try app_render.writeJsonIntField(writer, "visible", counts.visible, true);
    try app_render.writeJsonIntField(writer, "routable", counts.routable, true);
    try app_render.writeJsonIntField(writer, "deprecated", counts.deprecated, true);
    try writer.writeAll("\"providers\":{");
    try app_render.writeJsonIntField(writer, "cloudflare", counts.cloudflare, true);
    try app_render.writeJsonIntField(writer, "hostinger", counts.hostinger, false);
    try writer.writeAll("},\"methods\":{");
    try app_render.writeJsonIntField(writer, "GET", counts.get, true);
    try app_render.writeJsonIntField(writer, "POST", counts.post, true);
    try app_render.writeJsonIntField(writer, "PUT", counts.put, true);
    try app_render.writeJsonIntField(writer, "PATCH", counts.patch, true);
    try app_render.writeJsonIntField(writer, "DELETE", counts.delete, true);
    try app_render.writeJsonIntField(writer, "other", counts.other_methods, false);
    try writer.writeAll("},\"modes\":{");
    try app_render.writeJsonIntField(writer, "read", counts.read, true);
    try app_render.writeJsonIntField(writer, "dry_run", counts.dry_run, true);
    try app_render.writeJsonIntField(writer, "write", counts.write, true);
    try app_render.writeJsonIntField(writer, "none", counts.none, false);
    try writer.writeAll("},\"support\":{");
    try app_render.writeJsonIntField(writer, "implemented", counts.implemented, true);
    try app_render.writeJsonIntField(writer, "partial", counts.partial, true);
    try app_render.writeJsonIntField(writer, "planned", counts.planned, true);
    try app_render.writeJsonIntField(writer, "blocked_permission", counts.blocked_permission, true);
    try app_render.writeJsonIntField(writer, "unsafe_mutation", counts.unsafe_mutation, true);
    try app_render.writeJsonIntField(writer, "deprecated", counts.deprecated_support, true);
    try app_render.writeJsonIntField(writer, "not_applicable", counts.not_applicable, false);
    try writer.writeAll("},\"contract\":{");
    try app_render.writeJsonIntField(writer, "operation_ids", counts.operation_ids, true);
    try app_render.writeJsonIntField(writer, "auth_required", counts.auth_required, true);
    try app_render.writeJsonIntField(writer, "anonymous", counts.anonymous, true);
    try app_render.writeJsonIntField(writer, "path_param_routes", counts.path_param_routes, true);
    try app_render.writeJsonIntField(writer, "query_param_routes", counts.query_param_routes, true);
    try app_render.writeJsonIntField(writer, "header_param_routes", counts.header_param_routes, true);
    try app_render.writeJsonIntField(writer, "request_body_routes", counts.request_body_routes, true);
    try app_render.writeJsonIntField(writer, "request_body_required", counts.request_body_required, true);
    try app_render.writeJsonIntField(writer, "response_documented_routes", counts.response_documented_routes, true);
    try app_render.writeJsonIntField(writer, "path_params", counts.path_params, true);
    try app_render.writeJsonIntField(writer, "query_params", counts.query_params, true);
    try app_render.writeJsonIntField(writer, "header_params", counts.header_params, true);
    try app_render.writeJsonIntField(writer, "responses", counts.responses, false);
    try writer.writeAll("}}");
}

fn writeRouteJson(writer: anytype, route: provider_routes.Route) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", route.provider.name(), true);
    try app_render.writeJsonStringField(writer, "tag", route.tag, true);
    try app_render.writeJsonStringField(writer, "method", route.method.name(), true);
    try app_render.writeJsonStringField(writer, "path_template", route.path_template, true);
    try writeNullableJsonStringField(writer, "operation_id", route.operation_id, true);
    try app_render.writeJsonStringField(writer, "support", @tagName(route.support), true);
    try app_render.writeJsonStringField(writer, "mode", @tagName(route.mode), true);
    try app_render.writeJsonStringField(writer, "tests", route.tests, true);
    try app_render.writeJsonBoolField(writer, "deprecated", route.deprecated, true);
    try app_render.writeJsonBoolField(writer, "routable", route.isRoutable(), true);
    try app_render.writeJsonIntField(writer, "path_params", route.path_params.len, true);
    try app_render.writeJsonIntField(writer, "query_params", route.query_params.len, true);
    try app_render.writeJsonIntField(writer, "header_params", route.header_params.len, true);
    try app_render.writeJsonBoolField(writer, "request_body_required", route.request_body.required, true);
    try app_render.writeJsonIntField(writer, "responses", route.responses.len, false);
    try writer.writeByte('}');
}

fn writeRouteGroupJson(writer: anytype, group: RouteGroup) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", group.provider.name(), true);
    try app_render.writeJsonStringField(writer, "tag", group.tag, true);
    try writer.writeAll("\"summary\":");
    try writeSummaryJson(writer, group.summary);
    try writer.writeByte('}');
}

fn writeNullableJsonStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try app_render.writeJsonString(writer, name);
    try writer.writeByte(':');
    if (value) |text| {
        try app_render.writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

const metadata_fixture =
    \\{"schema_version":6,"sources":{"cloudflare":"https://raw.githubusercontent.com/cloudflare/api-schemas/main/openapi.json","hostinger":"https://raw.githubusercontent.com/hostinger/api/main/openapi.json"},"operation_counts":{"cloudflare":3151,"hostinger":133}}
;

const cloudflare_fixture =
    \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":[]}}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"fixture"}
    \\
;

const hostinger_fixture =
    \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"fixture"}
    \\
;

test "route catalog summarizes provider metadata for UI consumers" {
    const allocator = std.testing.allocator;
    var catalog = try Catalog.loadFromText(allocator, cloudflare_fixture, hostinger_fixture, metadata_fixture, .{ .limit = 1 });
    defer catalog.deinit(allocator);

    const counts = catalog.summary();
    try std.testing.expectEqual(@as(usize, 2), counts.total);
    try std.testing.expectEqual(@as(usize, 1), counts.visible);
    try std.testing.expectEqual(@as(usize, 2), counts.routable);
    try std.testing.expectEqual(@as(usize, 1), counts.cloudflare);
    try std.testing.expectEqual(@as(usize, 1), counts.hostinger);
    try std.testing.expectEqual(@as(usize, 1), counts.read);
    try std.testing.expectEqual(@as(usize, 1), counts.dry_run);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try catalog.writeText(&text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route catalog\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source cloudflare=https://raw.githubusercontent.com/cloudflare/api-schemas/main/openapi.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /zones/{zone_id}/dns_records") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try catalog.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("route_catalog", parsed.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("summary").?.object.get("total").?.integer);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("summary").?.object.get("contract").?.object.get("operation_ids").?.integer);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("summary").?.object.get("contract").?.object.get("auth_required").?.integer);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("summary").?.object.get("contract").?.object.get("path_param_routes").?.integer);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("summary").?.object.get("contract").?.object.get("request_body_required").?.integer);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("routes").?.array.items.len);
}

test "route catalog groups expose tag-level L1 contract summaries" {
    const allocator = std.testing.allocator;
    var report = try GroupReport.loadFromText(allocator, cloudflare_fixture, hostinger_fixture, metadata_fixture, .{ .limit = 10 });
    defer report.deinit(allocator);

    const counts = report.summary();
    try std.testing.expectEqual(@as(usize, 2), counts.groups_total);
    try std.testing.expectEqual(@as(usize, 2), counts.groups_visible);
    try std.testing.expectEqual(@as(usize, 2), counts.route_summary.total);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try report.writeText(&text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route catalog groups\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary groups=2 visible=2 routes=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare\tDNS Records\toperations=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger\tVPS\toperations=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "body_required=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(&json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("route_catalog_groups", parsed.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("summary").?.object.get("groups_total").?.integer);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("summary").?.object.get("routes").?.object.get("total").?.integer);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.get("groups").?.array.items.len);
    const first_group = parsed.value.object.get("groups").?.array.items[0];
    try std.testing.expectEqualStrings("cloudflare", first_group.object.get("provider").?.string);
    try std.testing.expectEqualStrings("DNS Records", first_group.object.get("tag").?.string);
    try std.testing.expectEqual(@as(i64, 1), first_group.object.get("summary").?.object.get("contract").?.object.get("path_param_routes").?.integer);
}

test "route catalog filters by provider and query" {
    const allocator = std.testing.allocator;
    var catalog = try Catalog.loadFromText(allocator, cloudflare_fixture, hostinger_fixture, metadata_fixture, .{
        .provider = .hostinger,
        .query = "purchase",
        .limit = 10,
    });
    defer catalog.deinit(allocator);

    const counts = catalog.summary();
    try std.testing.expectEqual(@as(usize, 1), counts.total);
    try std.testing.expectEqual(@as(usize, 0), counts.cloudflare);
    try std.testing.expectEqual(@as(usize, 1), counts.hostinger);
    try std.testing.expectEqual(@as(usize, 1), counts.unsafe_mutation);
}
