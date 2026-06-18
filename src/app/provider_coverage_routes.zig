const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const containsIgnoreCase = app_provider_coverage_render.containsIgnoreCase;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableBoolField = app_provider_coverage_render.writeJsonNullableBoolField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeJsonStringArray = app_provider_coverage_render.writeJsonStringArray;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

const max_manifest_bytes = 8 * 1024 * 1024;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const PathParam = provider_routes.PathParam;
pub const QueryParam = provider_routes.QueryParam;
pub const HeaderParam = provider_routes.HeaderParam;
pub const Request = provider_routes.Request;
pub const BodyInput = provider_routes.BodyInput;

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

pub const WorkplanFamily = enum {
    all,
    accounts,
    memberships,
    iam,
    tokens,
    zones,
    dns,
    ssl_tls,
    access,
    tunnels,
    rulesets,
    logs,
    cache,
    security,
    billing,
    domains,
    hosting,
    docker,
    hostinger_vps,
    public_keys,
    custom_pages,
    healthchecks,
    load_balancing,

    pub fn parse(value: []const u8) ?WorkplanFamily {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "accounts") or std.mem.eql(u8, value, "account")) return .accounts;
        if (std.mem.eql(u8, value, "memberships") or std.mem.eql(u8, value, "membership")) return .memberships;
        if (std.mem.eql(u8, value, "iam")) return .iam;
        if (std.mem.eql(u8, value, "tokens") or std.mem.eql(u8, value, "token")) return .tokens;
        if (std.mem.eql(u8, value, "zones") or std.mem.eql(u8, value, "zone")) return .zones;
        if (std.mem.eql(u8, value, "dns")) return .dns;
        if (std.mem.eql(u8, value, "ssl-tls") or std.mem.eql(u8, value, "ssl_tls") or std.mem.eql(u8, value, "ssl") or std.mem.eql(u8, value, "tls")) return .ssl_tls;
        if (std.mem.eql(u8, value, "access")) return .access;
        if (std.mem.eql(u8, value, "tunnels") or std.mem.eql(u8, value, "tunnel")) return .tunnels;
        if (std.mem.eql(u8, value, "rulesets") or std.mem.eql(u8, value, "ruleset") or std.mem.eql(u8, value, "rules-lists") or std.mem.eql(u8, value, "rules_lists")) return .rulesets;
        if (std.mem.eql(u8, value, "logs") or std.mem.eql(u8, value, "log")) return .logs;
        if (std.mem.eql(u8, value, "cache") or std.mem.eql(u8, value, "caching")) return .cache;
        if (std.mem.eql(u8, value, "security") or std.mem.eql(u8, value, "security-posture") or std.mem.eql(u8, value, "security_posture")) return .security;
        if (std.mem.eql(u8, value, "billing")) return .billing;
        if (std.mem.eql(u8, value, "domains") or std.mem.eql(u8, value, "domain")) return .domains;
        if (std.mem.eql(u8, value, "hosting")) return .hosting;
        if (std.mem.eql(u8, value, "docker")) return .docker;
        if (std.mem.eql(u8, value, "hostinger-vps") or std.mem.eql(u8, value, "hostinger_vps") or std.mem.eql(u8, value, "vps")) return .hostinger_vps;
        if (std.mem.eql(u8, value, "public-keys") or std.mem.eql(u8, value, "public_keys") or std.mem.eql(u8, value, "keys")) return .public_keys;
        if (std.mem.eql(u8, value, "custom-pages") or std.mem.eql(u8, value, "custom_pages")) return .custom_pages;
        if (std.mem.eql(u8, value, "healthchecks") or std.mem.eql(u8, value, "healthcheck")) return .healthchecks;
        if (std.mem.eql(u8, value, "load-balancing") or std.mem.eql(u8, value, "load_balancing") or std.mem.eql(u8, value, "load-balancers") or std.mem.eql(u8, value, "load_balancers")) return .load_balancing;
        return null;
    }

    pub fn name(self: WorkplanFamily) []const u8 {
        return switch (self) {
            .all => "all",
            .accounts => "accounts",
            .memberships => "memberships",
            .iam => "iam",
            .tokens => "tokens",
            .zones => "zones",
            .dns => "dns",
            .ssl_tls => "ssl-tls",
            .access => "access",
            .tunnels => "tunnels",
            .rulesets => "rulesets",
            .logs => "logs",
            .cache => "cache",
            .security => "security",
            .billing => "billing",
            .domains => "domains",
            .hosting => "hosting",
            .docker => "docker",
            .hostinger_vps => "hostinger-vps",
            .public_keys => "public-keys",
            .custom_pages => "custom-pages",
            .healthchecks => "healthchecks",
            .load_balancing => "load-balancing",
        };
    }
};

pub const RouteFilter = struct {
    provider: ProviderFilter = .all,
    tag_query: ?[]const u8 = null,
    family: WorkplanFamily = .all,
    operation_id: ?[]const u8 = null,
    method: ?provider_routes.Method = null,
    path_template: ?[]const u8 = null,
    support: ?SupportFilter = null,
    mode: ?ModeFilter = null,
    detail: bool = false,
};

pub const RoutePlanInput = struct {
    filter: RouteFilter,
    request: Request = .{},
};

pub const CoverageRoute = struct {
    route: provider_routes.Route,
    tests: []u8,
    notes: []u8,

    pub fn init(gpa: Allocator, provider: []const u8, value: std.json.Value) !CoverageRoute {
        const expected_provider = provider_routes.Provider.parse(provider) orelse return error.InvalidCoverageProvider;
        const route = try provider_routes.Route.init(gpa, expected_provider, value);
        errdefer route.deinit(gpa);
        const tests = core_json.fieldString(value, "tests") orelse return error.InvalidCoverageRow;
        const notes = core_json.fieldString(value, "notes") orelse return error.InvalidCoverageRow;
        const tests_owned = try gpa.dupe(u8, tests);
        errdefer gpa.free(tests_owned);
        const notes_owned = try gpa.dupe(u8, notes);
        errdefer gpa.free(notes_owned);

        return .{
            .route = route,
            .tests = tests_owned,
            .notes = notes_owned,
        };
    }

    pub fn deinit(self: CoverageRoute, gpa: Allocator) void {
        self.route.deinit(gpa);
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

    pub fn writeText(self: CoverageRoutes, writer: anytype, detail: bool) !void {
        try writer.writeAll("Cloudio provider coverage routes\n");
        if (self.items.len == 0) {
            try writer.writeAll("no matching routes\n");
            return;
        }

        var current_provider: ?[]const u8 = null;
        var current_tag: ?[]const u8 = null;
        for (self.items) |row| {
            const provider_name = row.route.provider.name();
            if (current_provider == null or !std.mem.eql(u8, current_provider.?, provider_name)) {
                current_provider = provider_name;
                current_tag = null;
                try writer.print("\n{s}\n", .{provider_name});
            }
            if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
                current_tag = row.route.tag;
                try writer.print("  {s}\n", .{row.route.tag});
            }
            try writer.print("    {s} {s} | support={s} mode={s} tests={s}", .{ row.route.method.name(), row.route.path_template, @tagName(row.route.support), @tagName(row.route.mode), row.tests });
            if (row.route.deprecated) try writer.writeAll(" deprecated=true");
            if (row.route.operation_id) |id| try writer.print(" op={s}", .{id});
            try writer.writeByte('\n');
            if (detail) try writeRouteDetail(writer, row.route);
            if (row.notes.len != 0) try writer.print("      notes: {s}\n", .{row.notes});
        }
    }

    pub fn writeJson(self: CoverageRoutes, writer: anytype, filter: RouteFilter) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "coverage_routes", true);
        try writer.writeAll("\"filter\":");
        try writeRouteFilterJson(filter, writer);
        try writer.writeByte(',');
        try writeJsonCountField(writer, "count", self.items.len, true);
        try writer.writeAll("\"routes\":[");
        var first = true;
        for (self.items) |row| {
            try writeMaybeJsonComma(writer, &first);
            try writeCoverageRouteJson(row, writer);
        }
        try writer.writeAll("]}");
        try writer.writeByte('\n');
    }
};

pub fn parseRouteMethod(value: []const u8) ?provider_routes.Method {
    return provider_routes.Method.parse(value);
}

pub fn parsePathParamAssignment(value: []const u8) !PathParam {
    return provider_routes.parsePathParamAssignment(value);
}

pub fn parseQueryParamAssignment(value: []const u8) !QueryParam {
    return provider_routes.parseQueryParamAssignment(value);
}

pub fn parseHeaderParamAssignment(value: []const u8) !HeaderParam {
    return provider_routes.parseHeaderParamAssignment(value);
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
    try routes.writeText(writer, filter.detail);
}

pub fn writeRoutesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    var routes = try loadRoutes(io, gpa, paths, filter);
    defer routes.deinit(gpa);
    try routes.writeJson(writer, filter);
}

pub fn tagIsControlPlane(provider: []const u8, tag: []const u8) bool {
    return tagFamily(provider, tag) != null;
}

pub fn tagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    if (std.mem.eql(u8, provider, "hostinger")) {
        if (tagContainsAny(tag, &.{ "Docker", "Container" })) return .docker;
        if (tagContainsAny(tag, &.{ "Malware", "Monarx", "Firewall", "Security" })) return .security;
        if (tagContainsAny(tag, &.{ "Public key", "SSH key" })) return .public_keys;
        if (tagContainsAny(tag, &.{ "VPS", "Virtual machine", "VirtualMachine", "Post-install" })) return .hostinger_vps;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{"Domain"})) return .domains;
        if (tagContainsAny(tag, &.{ "Hosting", "Horizons" })) return .hosting;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        return null;
    }
    if (std.mem.eql(u8, provider, "cloudflare")) {
        if (tagContainsAny(tag, &.{ "Email Security", "Security Center", "Firewall", "WAF", "Bot", "Page Shield", "IP Access", "API Gateway", "Leaked Credential", "Vulnerability Scanner", "Security" })) return .security;
        if (tagContainsAny(tag, &.{"Token"})) return .tokens;
        if (tagContainsAny(tag, &.{"Membership"})) return .memberships;
        if (tagContainsAny(tag, &.{"IAM"})) return .iam;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{ "SSL", "TLS", "Certificate", "mTLS" })) return .ssl_tls;
        if (tagContainsAny(tag, &.{"Access"})) return .access;
        if (tagContainsAny(tag, &.{"Tunnel"})) return .tunnels;
        if (tagContainsAny(tag, &.{ "Ruleset", "Rules List" })) return .rulesets;
        if (cloudflareTagIsLogsFamily(tag)) return .logs;
        if (tagContainsAny(tag, &.{ "Cache", "Argo" })) return .cache;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        if (tagContainsAny(tag, &.{"Custom Pages"})) return .custom_pages;
        if (tagContainsAny(tag, &.{"Healthcheck"})) return .healthchecks;
        if (tagContainsAny(tag, &.{"Load Balancer"})) return .load_balancing;
        if (tagContainsAny(tag, &.{"Zone"})) return .zones;
        if (tagContainsAny(tag, &.{ "Account", "Organization", "User" })) return .accounts;
        return null;
    }
    return null;
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
        const operation_id = core_json.fieldString(parsed.value, "operation_id");
        const method_text = core_json.fieldString(parsed.value, "method") orelse return error.InvalidCoverageRow;
        const path_template = core_json.fieldString(parsed.value, "path") orelse return error.InvalidCoverageRow;
        const support = core_json.fieldString(parsed.value, "support") orelse return error.InvalidCoverageRow;
        const mode = core_json.fieldString(parsed.value, "mode") orelse return error.InvalidCoverageRow;
        if (filter.tag_query) |query| {
            if (!containsIgnoreCase(tag, query)) continue;
        }
        if (filter.family != .all) {
            const family = tagFamily(provider, tag) orelse continue;
            if (family != filter.family) continue;
        }
        if (filter.operation_id) |expected| {
            const actual = operation_id orelse continue;
            if (!std.mem.eql(u8, actual, expected)) continue;
        }
        if (filter.method) |expected| {
            const method = provider_routes.Method.parse(method_text) orelse return error.InvalidCoverageMethod;
            if (method != expected) continue;
        }
        if (filter.path_template) |expected| {
            if (!std.mem.eql(u8, path_template, expected)) continue;
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

fn deinitRouteList(rows: *std.ArrayList(CoverageRoute), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn tagContainsAny(tag: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (containsIgnoreCase(tag, needle)) return true;
    }
    return false;
}

fn cloudflareTagIsLogsFamily(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "AI Gateway Logs",
        "Audit Logs",
        "Instant Logs",
        "Log Explorer",
        "Logcontrol",
        "Logs",
        "Logpush",
        "Logs Received",
        "VPC Flow logs",
        "Worker Tail Logs",
    });
}

pub fn writeRouteFilterJson(filter: RouteFilter, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", filter.provider.name(), true);
    try writeJsonNullableStringField(writer, "tag_query", filter.tag_query, true);
    try writeJsonField(writer, "family", filter.family.name(), true);
    try writeJsonNullableStringField(writer, "operation_id", filter.operation_id, true);
    try writeJsonNullableStringField(writer, "method", if (filter.method) |method| method.name() else null, true);
    try writeJsonNullableStringField(writer, "path_template", filter.path_template, true);
    try writeJsonNullableStringField(writer, "support", if (filter.support) |support| support.name() else null, true);
    try writeJsonNullableStringField(writer, "mode", if (filter.mode) |mode| mode.name() else null, true);
    try writeJsonBoolField(writer, "detail", filter.detail, false);
    try writer.writeByte('}');
}

fn writeCoverageRouteJson(row: CoverageRoute, writer: anytype) !void {
    const route = row.route;
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonNullableStringField(writer, "operation_id", route.operation_id, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "mode", @tagName(route.mode), true);
    try writeJsonBoolField(writer, "deprecated", route.deprecated, true);
    try writeJsonBoolField(writer, "routable", route.isRoutable(), true);
    try writeJsonField(writer, "tests", row.tests, true);
    try writeJsonField(writer, "notes", row.notes, true);
    try writer.writeAll("\"path_params\":");
    try writeRouteParamsJson(route.path_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"query_params\":");
    try writeRouteParamsJson(route.query_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"header_params\":");
    try writeRouteParamsJson(route.header_params, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"request_body\":");
    try writeRequestBodyJson(route.request_body, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"responses\":");
    try writeResponsesJson(route.responses, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"security\":");
    try writeSecurityJson(route.security, writer);
    try writer.writeByte('}');
}

fn writeRouteParamsJson(params: []const provider_routes.RouteParam, writer: anytype) !void {
    try writer.writeByte('[');
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "name", param.name, true);
        try writeJsonBoolField(writer, "required", param.required, true);
        try writeJsonNullableStringField(writer, "style", param.style, true);
        try writeJsonNullableBoolField(writer, "explode", param.explode, true);
        try writer.writeAll("\"schema\":");
        try writeParamSchemaJson(param.schema, writer);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeParamSchemaJson(schema: provider_routes.ParamSchema, writer: anytype) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"schema_refs\":");
    try writeJsonStringArray(writer, schema.schema_refs);
    try writer.writeByte(',');
    try writer.writeAll("\"types\":");
    try writeJsonStringArray(writer, schema.types);
    try writer.writeByte(',');
    try writer.writeAll("\"formats\":");
    try writeJsonStringArray(writer, schema.formats);
    try writer.writeByte(',');
    try writer.writeAll("\"enum_values\":");
    try writeJsonStringArray(writer, schema.enum_values);
    try writer.writeByte('}');
}

fn writeRequestBodyJson(body: provider_routes.RequestBody, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonBoolField(writer, "required", body.required, true);
    try writer.writeAll("\"content_types\":");
    try writeJsonStringArray(writer, body.content_types);
    try writer.writeByte(',');
    try writer.writeAll("\"schema_refs\":");
    try writeJsonStringArray(writer, body.schema_refs);
    try writer.writeByte('}');
}

fn writeResponsesJson(responses: []const provider_routes.Response, writer: anytype) !void {
    try writer.writeByte('[');
    for (responses, 0..) |response, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writeJsonField(writer, "status", response.status, true);
        try writer.writeAll("\"content_types\":");
        try writeJsonStringArray(writer, response.content_types);
        try writer.writeByte(',');
        try writer.writeAll("\"schema_refs\":");
        try writeJsonStringArray(writer, response.schema_refs);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeSecurityJson(security: provider_routes.Security, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonBoolField(writer, "required", security.required, true);
    try writer.writeAll("\"alternatives\":[");
    for (security.alternatives, 0..) |alternative, index| {
        if (index != 0) try writer.writeByte(',');
        try writeJsonStringArray(writer, alternative.schemes);
    }
    try writer.writeAll("]}");
}

fn writeRouteDetail(writer: anytype, route: provider_routes.Route) !void {
    try writer.writeAll("      path_params: ");
    try writeRouteParamList(writer, route.path_params);
    try writer.writeByte('\n');
    try writer.writeAll("      query_params: ");
    try writeRouteParamList(writer, route.query_params);
    try writer.writeByte('\n');
    try writer.writeAll("      header_params: ");
    try writeRouteParamList(writer, route.header_params);
    try writer.writeByte('\n');
    try writeRouteParamShapeDetails(writer, "path_param_shapes", route.path_params);
    try writeRouteParamShapeDetails(writer, "query_param_shapes", route.query_params);
    try writeRouteParamShapeDetails(writer, "header_param_shapes", route.header_params);
    try writer.print("      security: required={} alternatives=", .{route.security.required});
    try writeSecurityAlternatives(writer, route.security.alternatives);
    try writer.writeByte('\n');
    try writer.print("      request_body: required={}", .{route.request_body.required});
    try writer.writeAll(" content_types=");
    try writeStringList(writer, route.request_body.content_types);
    try writer.writeAll(" schema_refs=");
    try writeStringList(writer, route.request_body.schema_refs);
    try writer.writeByte('\n');
    try writer.writeAll("      responses:");
    if (route.responses.len == 0) {
        try writer.writeAll(" none\n");
        return;
    }
    try writer.writeByte('\n');
    for (route.responses) |response| {
        try writer.print("        {s} content_types=", .{response.status});
        try writeStringList(writer, response.content_types);
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, response.schema_refs);
        try writer.writeByte('\n');
    }
}

fn writeSecurityAlternatives(writer: anytype, alternatives: []const provider_routes.SecurityAlternative) !void {
    if (alternatives.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (alternatives, 0..) |alternative, index| {
        if (index != 0) try writer.writeAll(" or ");
        if (alternative.schemes.len == 0) {
            try writer.writeAll("anonymous");
            continue;
        }
        for (alternative.schemes, 0..) |scheme, scheme_index| {
            if (scheme_index != 0) try writer.writeByte('+');
            try writer.writeAll(scheme);
        }
    }
}

fn writeRouteParamShapeDetails(writer: anytype, label: []const u8, params: []const provider_routes.RouteParam) !void {
    if (params.len == 0) return;
    try writer.print("      {s}:\n", .{label});
    for (params) |param| {
        try writer.print("        {s} style=", .{param.name});
        if (param.style) |style| {
            try writer.writeAll(style);
        } else {
            try writer.writeAll("default");
        }
        try writer.writeAll(" explode=");
        if (param.explode) |explode| {
            try writer.writeAll(if (explode) "true" else "false");
        } else {
            try writer.writeAll("default");
        }
        try writer.writeAll(" schema_types=");
        try writeStringList(writer, param.schema.types);
        try writer.writeAll(" schema_formats=");
        try writeStringList(writer, param.schema.formats);
        try writer.writeAll(" enum_values=");
        try writeStringList(writer, param.schema.enum_values);
        try writer.writeAll(" schema_refs=");
        try writeStringList(writer, param.schema.schema_refs);
        try writer.writeByte('\n');
    }
}

fn writeRouteParamList(writer: anytype, params: []const provider_routes.RouteParam) !void {
    if (params.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (params, 0..) |param, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}({s})", .{ param.name, if (param.required) "required" else "optional" });
    }
}

fn writeStringList(writer: anytype, values: anytype) !void {
    if (values.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(value);
    }
}

test "filters coverage routes by family and route fields" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"missing","deprecated":false,"notes":"dns"}
        \\{"provider":"cloudflare","tag":"Cache Reserve","method":"PATCH","path":"/zones/{zone_id}/cache/cache_reserve","operation_id":"cache-reserve-edit","path_params":[{"name":"zone_id","required":true}],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"cache"}
        \\
    ;
    var routes = try loadRoutesFromText(allocator, cloudflare, "", .{
        .provider = .cloudflare,
        .family = .dns,
        .method = .GET,
        .mode = .read,
    });
    defer routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), routes.items.len);
    try std.testing.expectEqualStrings("DNS Records", routes.items[0].route.tag);
}

test "classifies broad provider route families" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), tagFamily("cloudflare", "AI Gateway Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), tagFamily("cloudflare", "Magic Network Monitoring VPC Flow logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), tagFamily("cloudflare", "Catalog Sync"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), tagFamily("cloudflare", "Radar Certificate Transparency"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), tagFamily("cloudflare", "Token Validation Token Rules"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .access), tagFamily("cloudflare", "Infrastructure Access Targets"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .hostinger_vps), tagFamily("hostinger", "VPS: Virtual machine"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .security), tagFamily("hostinger", "Monarx Malware Scanner"));
}
