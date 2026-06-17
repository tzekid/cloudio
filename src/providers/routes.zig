const std = @import("std");
const core_json = @import("core_json");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const max_manifest_bytes = 8 * 1024 * 1024;

pub const cloudflare_base_url = "https://api.cloudflare.com/client/v4";
pub const hostinger_base_url = "https://developers.hostinger.com";

pub const Paths = struct {
    cloudflare_manifest: []const u8 = "coverage/generated/cloudflare.jsonl",
    hostinger_manifest: []const u8 = "coverage/generated/hostinger.jsonl",

    pub fn manifestPath(self: Paths, provider: Provider) []const u8 {
        return switch (provider) {
            .cloudflare => self.cloudflare_manifest,
            .hostinger => self.hostinger_manifest,
        };
    }
};

pub const Provider = enum {
    cloudflare,
    hostinger,

    pub fn parse(value: []const u8) ?Provider {
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        return null;
    }

    pub fn name(self: Provider) []const u8 {
        return @tagName(self);
    }

    pub fn baseUrl(self: Provider) []const u8 {
        return switch (self) {
            .cloudflare => cloudflare_base_url,
            .hostinger => hostinger_base_url,
        };
    }
};

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,

    pub fn parse(value: []const u8) ?Method {
        inline for (std.meta.fields(Method)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn name(self: Method) []const u8 {
        return @tagName(self);
    }
};

pub const Support = enum {
    implemented,
    partial,
    planned,
    blocked_permission,
    unsafe_mutation,
    deprecated,
    not_applicable,

    pub fn parse(value: []const u8) ?Support {
        inline for (std.meta.fields(Support)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const Mode = enum {
    read,
    dry_run,
    write,
    none,

    pub fn parse(value: []const u8) ?Mode {
        inline for (std.meta.fields(Mode)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const PathParam = struct {
    name: []const u8,
    value: []const u8,
};

pub const QueryParam = struct {
    name: []const u8,
    value: []const u8,
};

pub const HeaderParam = struct {
    name: []const u8,
    value: []const u8,
};

pub fn parsePathParamAssignment(value: []const u8) !PathParam {
    const parsed = try splitParamAssignment(value);
    return .{ .name = parsed.name, .value = parsed.value };
}

pub fn parseQueryParamAssignment(value: []const u8) !QueryParam {
    const parsed = try splitParamAssignment(value);
    return .{ .name = parsed.name, .value = parsed.value };
}

pub fn parseHeaderParamAssignment(value: []const u8) !HeaderParam {
    const parsed = try splitParamAssignment(value);
    return .{ .name = parsed.name, .value = parsed.value };
}

pub const BodyInput = struct {
    present: bool = false,
    content_type: ?[]const u8 = null,
};

pub const Request = struct {
    path_params: []const PathParam = &.{},
    query_params: []const QueryParam = &.{},
    header_params: []const HeaderParam = &.{},
    body: BodyInput = .{},
};

pub const RouteParam = struct {
    name: []u8,
    required: bool,
};

pub const RequestBody = struct {
    required: bool,
    content_types: [][]u8,
    schema_refs: [][]u8,

    pub fn primarySchemaRef(self: RequestBody) ?[]const u8 {
        if (self.schema_refs.len == 0) return null;
        return self.schema_refs[0];
    }

    pub fn acceptsContentType(self: RequestBody, content_type: []const u8) bool {
        const candidate = contentTypeBase(content_type);
        for (self.content_types) |allowed| {
            if (std.ascii.eqlIgnoreCase(contentTypeBase(allowed), candidate)) return true;
        }
        return false;
    }
};

pub const Response = struct {
    status: []u8,
    content_types: [][]u8,
    schema_refs: [][]u8,

    pub fn primarySchemaRef(self: Response) ?[]const u8 {
        if (self.schema_refs.len == 0) return null;
        return self.schema_refs[0];
    }
};

pub const SecurityAlternative = struct {
    schemes: [][]u8,

    pub fn isAnonymous(self: SecurityAlternative) bool {
        return self.schemes.len == 0;
    }
};

pub const Security = struct {
    required: bool,
    alternatives: []SecurityAlternative,

    pub fn acceptsSchemeSet(self: Security, schemes: []const []const u8) bool {
        if (!self.required) return true;
        for (self.alternatives) |alternative| {
            if (alternativeAcceptsSchemeSet(alternative, schemes)) return true;
        }
        return false;
    }

    pub fn hasAnonymousAlternative(self: Security) bool {
        for (self.alternatives) |alternative| {
            if (alternative.isAnonymous()) return true;
        }
        return false;
    }
};

pub const Route = struct {
    provider: Provider,
    tag: []u8,
    method: Method,
    path_template: []u8,
    operation_id: ?[]u8,
    path_params: []RouteParam,
    query_params: []RouteParam,
    header_params: []RouteParam,
    request_body: RequestBody,
    responses: []Response,
    security: Security,
    support: Support,
    mode: Mode,
    deprecated: bool,

    pub fn init(gpa: Allocator, expected_provider: Provider, value: std.json.Value) !Route {
        const provider_name = core_json.fieldString(value, "provider") orelse return error.InvalidProviderRoute;
        const provider = Provider.parse(provider_name) orelse return error.InvalidProviderRoute;
        if (provider != expected_provider) return error.InvalidProviderRoute;

        const tag = core_json.fieldString(value, "tag") orelse return error.InvalidProviderRoute;
        const method_text = core_json.fieldString(value, "method") orelse return error.InvalidProviderRoute;
        const path = core_json.fieldString(value, "path") orelse return error.InvalidProviderRoute;
        const operation_id = core_json.fieldString(value, "operation_id");
        const support_text = core_json.fieldString(value, "support") orelse return error.InvalidProviderRoute;
        const mode_text = core_json.fieldString(value, "mode") orelse return error.InvalidProviderRoute;
        const deprecated = core_json.fieldBool(value, "deprecated") orelse return error.InvalidProviderRoute;
        const method = Method.parse(method_text) orelse return error.InvalidProviderRoute;
        const support = Support.parse(support_text) orelse return error.InvalidProviderRoute;
        const mode = Mode.parse(mode_text) orelse return error.InvalidProviderRoute;

        const tag_owned = try gpa.dupe(u8, tag);
        errdefer gpa.free(tag_owned);
        const path_owned = try gpa.dupe(u8, path);
        errdefer gpa.free(path_owned);
        const operation_id_owned = if (operation_id) |id| try gpa.dupe(u8, id) else null;
        errdefer if (operation_id_owned) |id| gpa.free(id);
        const path_params = try parseRouteParams(gpa, value, "path_params");
        errdefer freeRouteParams(gpa, path_params);
        const query_params = try parseRouteParams(gpa, value, "query_params");
        errdefer freeRouteParams(gpa, query_params);
        const header_params = try parseRouteParams(gpa, value, "header_params");
        errdefer freeRouteParams(gpa, header_params);
        const request_body = try parseRequestBody(gpa, value);
        errdefer freeRequestBody(gpa, request_body);
        const responses = try parseResponses(gpa, value);
        errdefer freeResponses(gpa, responses);
        const security = try parseSecurity(gpa, value);
        errdefer freeSecurity(gpa, security);

        return .{
            .provider = provider,
            .tag = tag_owned,
            .method = method,
            .path_template = path_owned,
            .operation_id = operation_id_owned,
            .path_params = path_params,
            .query_params = query_params,
            .header_params = header_params,
            .request_body = request_body,
            .responses = responses,
            .security = security,
            .support = support,
            .mode = mode,
            .deprecated = deprecated,
        };
    }

    pub fn deinit(self: Route, gpa: Allocator) void {
        gpa.free(self.tag);
        gpa.free(self.path_template);
        if (self.operation_id) |id| gpa.free(id);
        freeRouteParams(gpa, self.path_params);
        freeRouteParams(gpa, self.query_params);
        freeRouteParams(gpa, self.header_params);
        freeRequestBody(gpa, self.request_body);
        freeResponses(gpa, self.responses);
        freeSecurity(gpa, self.security);
    }

    pub fn isRoutable(self: Route) bool {
        return !self.deprecated and self.support != .not_applicable and self.mode != .none;
    }

    pub fn isDryRunMutation(self: Route) bool {
        return self.mode == .dry_run and self.method != .GET and self.method != .HEAD;
    }

    pub fn parameterNames(self: Route, gpa: Allocator) ![][]u8 {
        return try templateParameterNames(gpa, self.path_template);
    }

    pub fn hasRequiredQueryParameters(self: Route) bool {
        for (self.query_params) |param| {
            if (param.required) return true;
        }
        return false;
    }

    pub fn renderPath(self: Route, gpa: Allocator, params: []const PathParam) ![]u8 {
        try validatePathParams(self.path_params, params);
        return try renderTemplatePath(gpa, self.path_template, params);
    }

    pub fn renderPathWithQuery(self: Route, gpa: Allocator, path_params: []const PathParam, query_params: []const QueryParam) ![]u8 {
        return try self.renderRequestPath(gpa, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn renderRequestPath(self: Route, gpa: Allocator, request: Request) ![]u8 {
        const path = try self.renderPath(gpa, request.path_params);
        defer gpa.free(path);
        return try appendRouteQuery(gpa, path, self.query_params, request.query_params);
    }

    pub fn renderUrl(self: Route, gpa: Allocator, base_url_override: ?[]const u8, params: []const PathParam) ![]u8 {
        return try self.renderUrlWithQuery(gpa, base_url_override, params, &.{});
    }

    pub fn renderUrlWithQuery(self: Route, gpa: Allocator, base_url_override: ?[]const u8, path_params: []const PathParam, query_params: []const QueryParam) ![]u8 {
        return try self.renderRequestUrl(gpa, base_url_override, .{ .path_params = path_params, .query_params = query_params });
    }

    pub fn renderRequestUrl(self: Route, gpa: Allocator, base_url_override: ?[]const u8, request: Request) ![]u8 {
        const path = try self.renderRequestPath(gpa, request);
        defer gpa.free(path);
        const base_url = base_url_override orelse self.provider.baseUrl();
        return try std.fmt.allocPrint(gpa, "{s}{s}", .{ base_url, path });
    }

    pub fn findResponse(self: Route, status: []const u8) ?*const Response {
        for (self.responses) |*response| {
            if (std.mem.eql(u8, response.status, status)) return response;
        }
        return null;
    }

    pub fn findResponseForStatus(self: Route, status: std.http.Status) ?*const Response {
        return self.findResponseForStatusCode(@intFromEnum(status));
    }

    pub fn findResponseForStatusCode(self: Route, status_code: u16) ?*const Response {
        for (self.responses) |*response| {
            if (responseStatusExact(response.status, status_code)) return response;
        }
        for (self.responses) |*response| {
            if (responseStatusFamily(response.status, status_code)) return response;
        }
        for (self.responses) |*response| {
            if (responseStatusDefault(response.status)) return response;
        }
        return null;
    }

    pub fn validateProvidedBodyInput(self: Route, request: Request) !void {
        if (!request.body.present and request.body.content_type == null) return;
        if (!request.body.present and request.body.content_type != null) return error.UnexpectedRouteRequestBodyContentType;
        if (self.request_body.content_types.len == 0) return error.UnexpectedRouteRequestBody;

        const content_type = request.body.content_type orelse return error.MissingRouteRequestBodyContentType;
        if (!self.request_body.acceptsContentType(content_type)) return error.UnsupportedRouteRequestBodyContentType;
    }

    pub fn validateRequestHeaders(self: Route, request: Request) !void {
        try validateHeaderParams(self.header_params, request.header_params);
    }
};

pub const RouteSet = struct {
    items: []Route,

    pub fn deinit(self: *RouteSet, gpa: Allocator) void {
        for (self.items) |row| row.deinit(gpa);
        gpa.free(self.items);
    }

    pub fn findByOperationId(self: RouteSet, operation_id: []const u8) ?*const Route {
        for (self.items) |*row| {
            if (row.operation_id) |id| {
                if (std.mem.eql(u8, id, operation_id)) return row;
            }
        }
        return null;
    }

    pub fn findByTemplate(self: RouteSet, method: Method, path_template: []const u8) ?*const Route {
        for (self.items) |*row| {
            if (row.method == method and std.mem.eql(u8, row.path_template, path_template)) return row;
        }
        return null;
    }

    pub fn countRoutable(self: RouteSet) usize {
        var count: usize = 0;
        for (self.items) |row| {
            if (row.isRoutable()) count += 1;
        }
        return count;
    }
};

pub fn loadProvider(io: Io, gpa: Allocator, paths: Paths, provider: Provider) !RouteSet {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try loadProviderFromText(gpa, provider, text);
}

pub fn loadProviderFromText(gpa: Allocator, provider: Provider, text: []const u8) !RouteSet {
    var rows = std.ArrayList(Route).empty;
    errdefer deinitRouteList(&rows, gpa);
    try appendProvider(gpa, provider, text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn loadAll(io: Io, gpa: Allocator, paths: Paths) !RouteSet {
    const cloudflare_text = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(cloudflare_text);
    const hostinger_text = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(hostinger_text);
    return try loadAllFromText(gpa, cloudflare_text, hostinger_text);
}

pub fn loadAllFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !RouteSet {
    var rows = std.ArrayList(Route).empty;
    errdefer deinitRouteList(&rows, gpa);
    try appendProvider(gpa, .cloudflare, cloudflare_text, &rows);
    try appendProvider(gpa, .hostinger, hostinger_text, &rows);
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

pub fn findByOperationId(io: Io, gpa: Allocator, paths: Paths, provider: Provider, operation_id: []const u8) !?Route {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try findByOperationIdFromText(gpa, provider, text, operation_id);
}

pub fn findByOperationIdFromText(gpa: Allocator, provider: Provider, text: []const u8, operation_id: []const u8) !?Route {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_operation_id = core_json.fieldString(parsed.value, "operation_id") orelse continue;
        if (!std.mem.eql(u8, row_operation_id, operation_id)) continue;
        return try Route.init(gpa, provider, parsed.value);
    }
    return null;
}

pub fn findByTemplate(io: Io, gpa: Allocator, paths: Paths, provider: Provider, method: Method, path_template: []const u8) !?Route {
    const text = try Io.Dir.cwd().readFileAlloc(io, paths.manifestPath(provider), gpa, .limited(max_manifest_bytes));
    defer gpa.free(text);
    return try findByTemplateFromText(gpa, provider, text, method, path_template);
}

pub fn findByTemplateFromText(gpa: Allocator, provider: Provider, text: []const u8, method: Method, path_template: []const u8) !?Route {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row_method = Method.parse(core_json.fieldString(parsed.value, "method") orelse return error.InvalidProviderRoute) orelse return error.InvalidProviderRoute;
        if (row_method != method) continue;
        const row_path = core_json.fieldString(parsed.value, "path") orelse return error.InvalidProviderRoute;
        if (!std.mem.eql(u8, row_path, path_template)) continue;
        return try Route.init(gpa, provider, parsed.value);
    }
    return null;
}

pub fn templateParameterNames(gpa: Allocator, path_template: []const u8) ![][]u8 {
    var names = std.ArrayList([]u8).empty;
    errdefer deinitParamNames(&names, gpa);

    var index: usize = 0;
    while (index < path_template.len) {
        const open_rel = std.mem.indexOfScalar(u8, path_template[index..], '{') orelse break;
        const open = index + open_rel;
        if (std.mem.indexOfScalar(u8, path_template[index..open], '}') != null) return error.InvalidRouteTemplate;
        const close_rel = std.mem.indexOfScalar(u8, path_template[open + 1 ..], '}') orelse return error.InvalidRouteTemplate;
        const close = open + 1 + close_rel;
        const name = path_template[open + 1 .. close];
        if (name.len == 0) return error.InvalidRouteTemplate;
        if (!containsParamName(names.items, name)) {
            const owned = try gpa.dupe(u8, name);
            errdefer gpa.free(owned);
            try names.append(gpa, owned);
        }
        index = close + 1;
    }
    if (std.mem.indexOfScalar(u8, path_template[index..], '}') != null) return error.InvalidRouteTemplate;
    return try names.toOwnedSlice(gpa);
}

pub fn freeParameterNames(gpa: Allocator, names: [][]u8) void {
    for (names) |name| gpa.free(name);
    gpa.free(names);
}

pub fn renderTemplatePath(gpa: Allocator, path_template: []const u8, params: []const PathParam) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();

    var index: usize = 0;
    while (index < path_template.len) {
        const open_rel = std.mem.indexOfScalar(u8, path_template[index..], '{') orelse {
            if (std.mem.indexOfScalar(u8, path_template[index..], '}') != null) return error.InvalidRouteTemplate;
            try out.writer.writeAll(path_template[index..]);
            return try out.toOwnedSlice();
        };
        const open = index + open_rel;
        if (std.mem.indexOfScalar(u8, path_template[index..open], '}') != null) return error.InvalidRouteTemplate;
        try out.writer.writeAll(path_template[index..open]);

        const close_rel = std.mem.indexOfScalar(u8, path_template[open + 1 ..], '}') orelse return error.InvalidRouteTemplate;
        const close = open + 1 + close_rel;
        const name = path_template[open + 1 .. close];
        if (name.len == 0) return error.InvalidRouteTemplate;

        const value = findParam(params, name) orelse return error.MissingRouteParameter;
        const escaped = try pathEscape(gpa, value);
        defer gpa.free(escaped);
        try out.writer.writeAll(escaped);
        index = close + 1;
    }
    return try out.toOwnedSlice();
}

pub fn pathEscape(gpa: Allocator, value: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try (std.Uri.Component{ .raw = value }).formatEscaped(&out.writer);
    return try out.toOwnedSlice();
}

pub fn queryEscape(gpa: Allocator, value: []const u8) ![]u8 {
    return try pathEscape(gpa, value);
}

pub fn appendRouteQuery(gpa: Allocator, base: []const u8, allowed_params: []const RouteParam, params: []const QueryParam) ![]u8 {
    for (params) |param| {
        if (!containsRouteParamName(allowed_params, param.name)) return error.UnknownRouteQueryParameter;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and !containsQueryParam(params, allowed.name)) return error.MissingRouteQueryParameter;
    }
    if (params.len == 0) return try gpa.dupe(u8, base);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.writeAll(base);
    var wrote_any = std.mem.indexOfScalar(u8, base, '?') != null;
    for (params) |param| {
        try out.writer.writeByte(if (wrote_any) '&' else '?');
        wrote_any = true;

        const escaped_name = try queryEscape(gpa, param.name);
        defer gpa.free(escaped_name);
        const escaped_value = try queryEscape(gpa, param.value);
        defer gpa.free(escaped_value);

        try out.writer.writeAll(escaped_name);
        try out.writer.writeByte('=');
        try out.writer.writeAll(escaped_value);
    }
    return try out.toOwnedSlice();
}

fn validatePathParams(allowed_params: []const RouteParam, params: []const PathParam) !void {
    for (params) |param| {
        if (!containsRouteParamName(allowed_params, param.name)) return error.UnknownRouteParameter;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and findParam(params, allowed.name) == null) return error.MissingRouteParameter;
    }
}

fn validateHeaderParams(allowed_params: []const RouteParam, params: []const HeaderParam) !void {
    for (params) |param| {
        if (!containsRouteParamNameIgnoreCase(allowed_params, param.name)) return error.UnknownRouteHeaderParameter;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and !containsHeaderParam(params, allowed.name)) return error.MissingRouteHeaderParameter;
    }
}

fn appendProvider(gpa: Allocator, provider: Provider, text: []const u8, rows: *std.ArrayList(Route)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer parsed.deinit();

        const row = try Route.init(gpa, provider, parsed.value);
        errdefer row.deinit(gpa);
        try rows.append(gpa, row);
    }
}

fn parseRouteParams(gpa: Allocator, value: std.json.Value, field_name: []const u8) ![]RouteParam {
    const field_value = core_json.field(value, field_name) orelse return try gpa.alloc(RouteParam, 0);
    if (field_value != .array) return error.InvalidProviderRoute;

    var rows = std.ArrayList(RouteParam).empty;
    errdefer deinitRouteParamList(&rows, gpa);
    for (field_value.array.items) |item| {
        const name = core_json.fieldString(item, "name") orelse return error.InvalidProviderRoute;
        const required = core_json.fieldBool(item, "required") orelse return error.InvalidProviderRoute;
        if (containsRouteParamName(rows.items, name)) continue;

        const owned = try gpa.dupe(u8, name);
        errdefer gpa.free(owned);
        try rows.append(gpa, .{ .name = owned, .required = required });
    }
    return try rows.toOwnedSlice(gpa);
}

fn parseRequestBody(gpa: Allocator, value: std.json.Value) !RequestBody {
    const field_value = core_json.field(value, "request_body") orelse {
        const content_types = try gpa.alloc([]u8, 0);
        errdefer gpa.free(content_types);
        const schema_refs = try gpa.alloc([]u8, 0);
        return .{
            .required = false,
            .content_types = content_types,
            .schema_refs = schema_refs,
        };
    };
    if (field_value != .object) return error.InvalidProviderRoute;
    const required = core_json.fieldBool(field_value, "required") orelse return error.InvalidProviderRoute;
    const content_types = try parseStringArray(gpa, field_value, "content_types");
    errdefer freeStringArray(gpa, content_types);
    const schema_refs = try parseStringArray(gpa, field_value, "schema_refs");
    errdefer freeStringArray(gpa, schema_refs);
    return .{
        .required = required,
        .content_types = content_types,
        .schema_refs = schema_refs,
    };
}

fn parseResponses(gpa: Allocator, value: std.json.Value) ![]Response {
    const field_value = core_json.field(value, "responses") orelse return error.InvalidProviderRoute;
    if (field_value != .array) return error.InvalidProviderRoute;

    var rows = std.ArrayList(Response).empty;
    errdefer deinitResponseList(&rows, gpa);
    for (field_value.array.items) |item| {
        if (item != .object) return error.InvalidProviderRoute;
        const status = core_json.fieldString(item, "status") orelse return error.InvalidProviderRoute;
        if (containsResponseStatus(rows.items, status)) continue;
        const status_owned = try gpa.dupe(u8, status);
        errdefer gpa.free(status_owned);
        const content_types = try parseStringArray(gpa, item, "content_types");
        errdefer freeStringArray(gpa, content_types);
        const schema_refs = try parseStringArray(gpa, item, "schema_refs");
        errdefer freeStringArray(gpa, schema_refs);
        try rows.append(gpa, .{
            .status = status_owned,
            .content_types = content_types,
            .schema_refs = schema_refs,
        });
    }
    return try rows.toOwnedSlice(gpa);
}

fn parseSecurity(gpa: Allocator, value: std.json.Value) !Security {
    const field_value = core_json.field(value, "security") orelse {
        const alternatives = try gpa.alloc(SecurityAlternative, 0);
        return .{ .required = false, .alternatives = alternatives };
    };
    if (field_value != .object) return error.InvalidProviderRoute;
    const required = core_json.fieldBool(field_value, "required") orelse return error.InvalidProviderRoute;
    const alternatives_value = core_json.field(field_value, "alternatives") orelse return error.InvalidProviderRoute;
    if (alternatives_value != .array) return error.InvalidProviderRoute;

    var alternatives = std.ArrayList(SecurityAlternative).empty;
    errdefer deinitSecurityAlternativeList(&alternatives, gpa);
    for (alternatives_value.array.items) |item| {
        const schemes = try parseStringArrayValue(gpa, item);
        errdefer freeStringArray(gpa, schemes);
        try alternatives.append(gpa, .{ .schemes = schemes });
    }
    return .{ .required = required, .alternatives = try alternatives.toOwnedSlice(gpa) };
}

fn parseStringArray(gpa: Allocator, value: std.json.Value, field_name: []const u8) ![][]u8 {
    const field_value = core_json.field(value, field_name) orelse return error.InvalidProviderRoute;
    return try parseStringArrayValue(gpa, field_value);
}

fn parseStringArrayValue(gpa: Allocator, value: std.json.Value) ![][]u8 {
    if (value != .array) return error.InvalidProviderRoute;
    var rows = std.ArrayList([]u8).empty;
    errdefer deinitStringList(&rows, gpa);
    for (value.array.items) |item| {
        if (item != .string) return error.InvalidProviderRoute;
        if (containsParamName(rows.items, item.string)) continue;
        const owned = try gpa.dupe(u8, item.string);
        errdefer gpa.free(owned);
        try rows.append(gpa, owned);
    }
    return try rows.toOwnedSlice(gpa);
}

fn freeRouteParams(gpa: Allocator, params: []RouteParam) void {
    for (params) |param| gpa.free(param.name);
    gpa.free(params);
}

fn freeRequestBody(gpa: Allocator, body: RequestBody) void {
    freeStringArray(gpa, body.content_types);
    freeStringArray(gpa, body.schema_refs);
}

fn freeResponses(gpa: Allocator, responses: []Response) void {
    for (responses) |response| {
        gpa.free(response.status);
        freeStringArray(gpa, response.content_types);
        freeStringArray(gpa, response.schema_refs);
    }
    gpa.free(responses);
}

fn freeSecurity(gpa: Allocator, security: Security) void {
    for (security.alternatives) |alternative| {
        freeStringArray(gpa, alternative.schemes);
    }
    gpa.free(security.alternatives);
}

fn freeStringArray(gpa: Allocator, items: [][]u8) void {
    for (items) |item| gpa.free(item);
    gpa.free(items);
}

fn deinitRouteList(rows: *std.ArrayList(Route), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitRouteParamList(rows: *std.ArrayList(RouteParam), gpa: Allocator) void {
    for (rows.items) |param| gpa.free(param.name);
    rows.deinit(gpa);
}

fn deinitStringList(rows: *std.ArrayList([]u8), gpa: Allocator) void {
    for (rows.items) |item| gpa.free(item);
    rows.deinit(gpa);
}

fn deinitResponseList(rows: *std.ArrayList(Response), gpa: Allocator) void {
    for (rows.items) |response| {
        gpa.free(response.status);
        freeStringArray(gpa, response.content_types);
        freeStringArray(gpa, response.schema_refs);
    }
    rows.deinit(gpa);
}

fn deinitSecurityAlternativeList(rows: *std.ArrayList(SecurityAlternative), gpa: Allocator) void {
    for (rows.items) |alternative| {
        freeStringArray(gpa, alternative.schemes);
    }
    rows.deinit(gpa);
}

fn deinitParamNames(rows: *std.ArrayList([]u8), gpa: Allocator) void {
    for (rows.items) |name| gpa.free(name);
    rows.deinit(gpa);
}

fn containsParamName(names: []const []u8, candidate: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn containsRouteParamName(params: []const RouteParam, candidate: []const u8) bool {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, candidate)) return true;
    }
    return false;
}

fn containsRouteParamNameIgnoreCase(params: []const RouteParam, candidate: []const u8) bool {
    for (params) |param| {
        if (std.ascii.eqlIgnoreCase(param.name, candidate)) return true;
    }
    return false;
}

fn containsQueryParam(params: []const QueryParam, candidate: []const u8) bool {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, candidate)) return true;
    }
    return false;
}

fn containsHeaderParam(params: []const HeaderParam, candidate: []const u8) bool {
    for (params) |param| {
        if (std.ascii.eqlIgnoreCase(param.name, candidate)) return true;
    }
    return false;
}

fn containsResponseStatus(responses: []const Response, candidate: []const u8) bool {
    for (responses) |response| {
        if (std.mem.eql(u8, response.status, candidate)) return true;
    }
    return false;
}

fn alternativeAcceptsSchemeSet(alternative: SecurityAlternative, schemes: []const []const u8) bool {
    for (alternative.schemes) |required_scheme| {
        if (!containsScheme(schemes, required_scheme)) return false;
    }
    return true;
}

fn containsScheme(schemes: []const []const u8, candidate: []const u8) bool {
    for (schemes) |scheme| {
        if (std.mem.eql(u8, scheme, candidate)) return true;
    }
    return false;
}

fn responseStatusExact(status: []const u8, status_code: u16) bool {
    if (status.len != 3) return false;
    const parsed = std.fmt.parseInt(u16, status, 10) catch return false;
    return parsed == status_code;
}

fn responseStatusFamily(status: []const u8, status_code: u16) bool {
    if (status.len != 3) return false;
    if (!std.ascii.isDigit(status[0])) return false;
    if (std.ascii.toUpper(status[1]) != 'X' or std.ascii.toUpper(status[2]) != 'X') return false;
    return status_code / 100 == status[0] - '0';
}

fn responseStatusDefault(status: []const u8) bool {
    return std.ascii.eqlIgnoreCase(status, "default");
}

fn contentTypeBase(content_type: []const u8) []const u8 {
    const semicolon = std.mem.indexOfScalar(u8, content_type, ';') orelse content_type.len;
    return std.mem.trim(u8, content_type[0..semicolon], " \t\r\n");
}

const ParamAssignment = struct {
    name: []const u8,
    value: []const u8,
};

fn splitParamAssignment(value: []const u8) !ParamAssignment {
    const equals = std.mem.indexOfScalar(u8, value, '=') orelse return error.InvalidRouteParameterAssignment;
    const name = std.mem.trim(u8, value[0..equals], " \t\r\n");
    const param_value = std.mem.trim(u8, value[equals + 1 ..], " \t\r\n");
    if (name.len == 0) return error.InvalidRouteParameterAssignment;
    return .{ .name = name, .value = param_value };
}

fn findParam(params: []const PathParam, name: []const u8) ?[]const u8 {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return param.value;
    }
    return null;
}

test "loads generated route metadata for both providers" {
    const allocator = std.testing.allocator;
    var routes = try loadAll(std.testing.io, allocator, .{});
    defer routes.deinit(allocator);

    try std.testing.expect(routes.items.len > 3000);
    try std.testing.expect(routes.countRoutable() > 3000);

    const cloudflare_accounts = routes.findByOperationId("accounts-list-accounts") orelse return error.TestExpectedRoute;
    try std.testing.expectEqual(Provider.cloudflare, cloudflare_accounts.provider);
    try std.testing.expectEqual(Method.GET, cloudflare_accounts.method);
    try std.testing.expectEqualStrings("/accounts", cloudflare_accounts.path_template);

    const hostinger_vps = routes.findByOperationId("VPS_getVirtualMachinesV1") orelse return error.TestExpectedRoute;
    try std.testing.expectEqual(Provider.hostinger, hostinger_vps.provider);
    try std.testing.expectEqual(Method.GET, hostinger_vps.method);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines", hostinger_vps.path_template);
    try std.testing.expect(hostinger_vps.responses.len > 0);
}

test "body-required GET routes are not generic read-routable" {
    const allocator = std.testing.allocator;
    var routes = try loadAll(std.testing.io, allocator, .{});
    defer routes.deinit(allocator);

    for (routes.items) |route| {
        if (route.method == .GET and route.request_body.required) {
            try std.testing.expectEqual(Support.not_applicable, route.support);
            try std.testing.expectEqual(Mode.none, route.mode);
            try std.testing.expect(!route.isRoutable());
        }
        if (route.mode == .read) {
            try std.testing.expect(!route.request_body.required);
        }
    }

    const cloudflare_route = routes.findByOperationId("tunnel-virtual-network-get") orelse return error.TestExpectedRoute;
    try std.testing.expect(cloudflare_route.request_body.required);
    try std.testing.expectEqual(Support.not_applicable, cloudflare_route.support);

    const hostinger_route = routes.findByOperationId("v2_getDomainVerificationsDIRECT") orelse return error.TestExpectedRoute;
    try std.testing.expect(hostinger_route.request_body.required);
    try std.testing.expectEqual(Support.not_applicable, hostinger_route.support);
}

test "finds routes by operation id and template without loading full tables" {
    const allocator = std.testing.allocator;

    const cloudflare_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-get-an-access-application")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    try std.testing.expectEqualStrings("Access applications", cloudflare_route.tag);
    try std.testing.expect(cloudflare_route.isRoutable());

    const hostinger_route = (try findByTemplate(std.testing.io, allocator, .{}, .hostinger, .GET, "/api/vps/v1/virtual-machines/{virtualMachineId}/metrics")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    try std.testing.expectEqualStrings("VPS: Virtual machine", hostinger_route.tag);
    try std.testing.expect(hostinger_route.isRoutable());
    try expectRouteParam(hostinger_route.path_params, "virtualMachineId", true);
    try expectRouteParam(hostinger_route.query_params, "date_from", true);
    try expectRouteParam(hostinger_route.query_params, "date_to", true);
    try std.testing.expect(hostinger_route.hasRequiredQueryParameters());
}

test "loads generated header parameter metadata" {
    const allocator = std.testing.allocator;

    const optional_header_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "r2-get-event-notification-configs")) orelse return error.TestExpectedRoute;
    defer optional_header_route.deinit(allocator);
    try expectRouteParam(optional_header_route.header_params, "cf-r2-jurisdiction", false);
    try optional_header_route.validateRequestHeaders(.{});
    try optional_header_route.validateRequestHeaders(.{ .header_params = &.{.{ .name = "CF-R2-Jurisdiction", .value = "eu" }} });
    try std.testing.expectError(error.UnknownRouteHeaderParameter, optional_header_route.validateRequestHeaders(.{ .header_params = &.{.{ .name = "x-unknown", .value = "value" }} }));

    const required_header_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "stream-videos-initiate-video-uploads-using-tus")) orelse return error.TestExpectedRoute;
    defer required_header_route.deinit(allocator);
    try expectRouteParam(required_header_route.header_params, "Tus-Resumable", true);
    try expectRouteParam(required_header_route.header_params, "Upload-Length", true);
    try std.testing.expectError(error.MissingRouteHeaderParameter, required_header_route.validateRequestHeaders(.{}));
    try required_header_route.validateRequestHeaders(.{ .header_params = &.{
        .{ .name = "tus-resumable", .value = "1.0.0" },
        .{ .name = "upload-length", .value = "123" },
    } });

    const hostinger_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), hostinger_route.header_params.len);
}

test "loads generated security metadata" {
    const allocator = std.testing.allocator;

    const token_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "account-api-tokens-verify-token")) orelse return error.TestExpectedRoute;
    defer token_route.deinit(allocator);
    try std.testing.expect(token_route.security.required);
    try std.testing.expectEqual(@as(usize, 1), token_route.security.alternatives.len);
    try expectString(token_route.security.alternatives[0].schemes, "api_token");
    try std.testing.expect(token_route.security.acceptsSchemeSet(&.{"api_token"}));
    try std.testing.expect(!token_route.security.acceptsSchemeSet(&.{ "api_email", "api_key" }));

    const legacy_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer legacy_route.deinit(allocator);
    try std.testing.expect(legacy_route.security.required);
    try expectString(legacy_route.security.alternatives[0].schemes, "api_email");
    try expectString(legacy_route.security.alternatives[0].schemes, "api_key");
    try std.testing.expect(legacy_route.security.acceptsSchemeSet(&.{ "api_email", "api_key" }));
    try std.testing.expect(!legacy_route.security.acceptsSchemeSet(&.{"api_token"}));

    const public_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "cloudflare-ips-cloudflare-ip-details")) orelse return error.TestExpectedRoute;
    defer public_route.deinit(allocator);
    try std.testing.expect(!public_route.security.required);
    try std.testing.expect(public_route.security.hasAnonymousAlternative());
    try std.testing.expect(public_route.security.acceptsSchemeSet(&.{}));

    const unsupported_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer unsupported_route.deinit(allocator);
    try std.testing.expect(unsupported_route.security.required);
    try expectString(unsupported_route.security.alternatives[0].schemes, "assets_jwt");
    try std.testing.expect(!unsupported_route.security.acceptsSchemeSet(&.{"api_token"}));

    const hostinger_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    try std.testing.expect(hostinger_route.security.required);
    try expectString(hostinger_route.security.alternatives[0].schemes, "apiToken");
    try std.testing.expect(hostinger_route.security.acceptsSchemeSet(&.{"apiToken"}));
}

test "generated path parameter metadata matches route templates" {
    const allocator = std.testing.allocator;
    var routes = try loadAll(std.testing.io, allocator, .{});
    defer routes.deinit(allocator);

    for (routes.items) |route| {
        const names = try route.parameterNames(allocator);
        defer freeParameterNames(allocator, names);

        for (route.path_params) |param| {
            try std.testing.expect(param.required);
            try std.testing.expect(containsParamName(names, param.name));
        }
        for (names) |name| {
            try std.testing.expect(containsRouteParamName(route.path_params, name));
        }
    }

    const cloudflare_route = routes.findByOperationId("access-applications-get-an-access-application") orelse return error.TestExpectedRoute;
    try expectRouteParam(cloudflare_route.path_params, "account_id", true);
    try expectRouteParam(cloudflare_route.path_params, "app_id", true);

    const hostinger_route = routes.findByOperationId("VPS_getMetricsV1") orelse return error.TestExpectedRoute;
    try expectRouteParam(hostinger_route.path_params, "virtualMachineId", true);
}

test "extracts required path parameters and renders escaped route paths" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-get-an-access-application")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const names = try route.parameterNames(allocator);
    defer freeParameterNames(allocator, names);
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("account_id", names[0]);
    try std.testing.expectEqualStrings("app_id", names[1]);
    try expectRouteParam(route.path_params, "account_id", true);
    try expectRouteParam(route.path_params, "app_id", true);

    const path = try route.renderPath(allocator, &.{
        .{ .name = "account_id", .value = "acct/1" },
        .{ .name = "app_id", .value = "app 1" },
    });
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/accounts/acct%2F1/access/apps/app%201", path);

    const url = try route.renderUrl(allocator, "https://example.test", &.{
        .{ .name = "account_id", .value = "acct/1" },
        .{ .name = "app_id", .value = "app 1" },
    });
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://example.test/accounts/acct%2F1/access/apps/app%201", url);
}

test "validates required and known route path parameters" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-get-an-access-application")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try std.testing.expectError(
        error.MissingRouteParameter,
        route.renderPath(allocator, &.{.{ .name = "account_id", .value = "acct" }}),
    );
    try std.testing.expectError(
        error.UnknownRouteParameter,
        route.renderPath(
            allocator,
            &.{
                .{ .name = "account_id", .value = "acct" },
                .{ .name = "app_id", .value = "app" },
                .{ .name = "extra", .value = "ignored" },
            },
        ),
    );
}

test "loads request body metadata from generated manifests" {
    const allocator = std.testing.allocator;

    const cloudflare_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "access-applications-add-an-application")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    try std.testing.expect(cloudflare_route.request_body.required);
    try expectString(cloudflare_route.request_body.content_types, "application/json");
    try expectString(cloudflare_route.request_body.schema_refs, "#/components/schemas/access_app_request");
    try std.testing.expectEqualStrings("#/components/schemas/access_app_request", cloudflare_route.request_body.primarySchemaRef() orelse "");

    const hostinger_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_purchaseNewVirtualMachineV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    try std.testing.expect(hostinger_route.request_body.required);
    try expectString(hostinger_route.request_body.content_types, "application/json");
    try expectString(hostinger_route.request_body.schema_refs, "#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest");

    const multipart_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer multipart_route.deinit(allocator);
    try std.testing.expect(multipart_route.request_body.required);
    try expectString(multipart_route.request_body.content_types, "multipart/form-data");
    try std.testing.expectEqual(@as(usize, 0), multipart_route.request_body.schema_refs.len);
    try std.testing.expect(multipart_route.request_body.acceptsContentType("multipart/form-data; boundary=abc"));
    try std.testing.expect(!multipart_route.request_body.acceptsContentType("application/json"));
}

test "validates dry-run-safe request body input metadata" {
    const allocator = std.testing.allocator;

    const body_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "worker-assets-upload")) orelse return error.TestExpectedRoute;
    defer body_route.deinit(allocator);
    try body_route.validateProvidedBodyInput(.{ .body = .{ .present = true, .content_type = "multipart/form-data; boundary=test" } });
    try std.testing.expectError(error.MissingRouteRequestBodyContentType, body_route.validateProvidedBodyInput(.{ .body = .{ .present = true } }));
    try std.testing.expectError(error.UnsupportedRouteRequestBodyContentType, body_route.validateProvidedBodyInput(.{ .body = .{ .present = true, .content_type = "application/json" } }));
    try std.testing.expectError(error.UnexpectedRouteRequestBodyContentType, body_route.validateProvidedBodyInput(.{ .body = .{ .content_type = "multipart/form-data" } }));

    const read_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer read_route.deinit(allocator);
    try read_route.validateProvidedBodyInput(.{});
    try std.testing.expectError(error.UnexpectedRouteRequestBody, read_route.validateProvidedBodyInput(.{ .body = .{ .present = true, .content_type = "application/json" } }));
}

test "loads response metadata from generated manifests" {
    const allocator = std.testing.allocator;

    const cloudflare_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    const cloudflare_success = cloudflare_route.findResponse("200") orelse return error.TestExpectedResponse;
    try expectString(cloudflare_success.content_types, "application/json");
    try expectString(cloudflare_success.schema_refs, "#/components/schemas/iam_response_collection_accounts");
    try std.testing.expectEqualStrings("#/components/schemas/iam_response_collection_accounts", cloudflare_success.primarySchemaRef() orelse "");
    const cloudflare_error = cloudflare_route.findResponse("4XX") orelse return error.TestExpectedResponse;
    try expectString(cloudflare_error.schema_refs, "#/components/schemas/iam_api-response-common-failure");

    const hostinger_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    const hostinger_success = hostinger_route.findResponse("200") orelse return error.TestExpectedResponse;
    try expectString(hostinger_success.content_types, "application/json");
    try expectString(hostinger_success.schema_refs, "#/components/schemas/VPS.V1.VirtualMachine.VirtualMachineCollection");
    const hostinger_auth_error = hostinger_route.findResponse("401") orelse return error.TestExpectedResponse;
    try std.testing.expectEqual(@as(usize, 0), hostinger_auth_error.schema_refs.len);
}

test "matches generated response metadata by HTTP status code" {
    const allocator = std.testing.allocator;

    const cloudflare_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "accounts-list-accounts")) orelse return error.TestExpectedRoute;
    defer cloudflare_route.deinit(allocator);
    const exact_success = cloudflare_route.findResponseForStatus(.ok) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("200", exact_success.status);
    const family_error = cloudflare_route.findResponseForStatus(.forbidden) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("4XX", family_error.status);
    try std.testing.expect(cloudflare_route.findResponseForStatus(.internal_server_error) == null);

    const lower_family_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "spectrum-analytics-(-summary)-get-analytics-summary")) orelse return error.TestExpectedRoute;
    defer lower_family_route.deinit(allocator);
    const lower_family_error = lower_family_route.findResponseForStatus(.unprocessable_entity) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("4xx", lower_family_error.status);

    const five_family_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "origin-cloud-regions-batch-delete")) orelse return error.TestExpectedRoute;
    defer five_family_route.deinit(allocator);
    const five_family_error = five_family_route.findResponseForStatus(.bad_gateway) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("5XX", five_family_error.status);

    const default_route = (try findByOperationId(std.testing.io, allocator, .{}, .cloudflare, "magic-pcap-collection-download-simple-pcap")) orelse return error.TestExpectedRoute;
    defer default_route.deinit(allocator);
    const default_success = default_route.findResponseForStatus(.ok) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("200", default_success.status);
    const default_error = default_route.findResponseForStatus(.bad_gateway) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("default", default_error.status);

    const hostinger_route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getVirtualMachinesV1")) orelse return error.TestExpectedRoute;
    defer hostinger_route.deinit(allocator);
    const hostinger_exact = hostinger_route.findResponseForStatus(.unauthorized) orelse return error.TestExpectedResponse;
    try std.testing.expectEqualStrings("401", hostinger_exact.status);
    try std.testing.expect(hostinger_route.findResponseForStatus(.not_found) == null);
}

test "renders validated query parameters for route paths and urls" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const path = try route.renderPathWithQuery(
        allocator,
        &.{.{ .name = "virtualMachineId", .value = "vm/1" }},
        &.{
            .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
            .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
        },
    );
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines/vm%2F1/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", path);

    const url = try route.renderUrlWithQuery(
        allocator,
        "https://example.test",
        &.{.{ .name = "virtualMachineId", .value = "vm/1" }},
        &.{
            .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
            .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
        },
    );
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://example.test/api/vps/v1/virtual-machines/vm%2F1/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", url);
}

test "parses route parameter assignments without allocation" {
    const path_param = try parsePathParamAssignment(" account_id = acct/1 ");
    try std.testing.expectEqualStrings("account_id", path_param.name);
    try std.testing.expectEqualStrings("acct/1", path_param.value);

    const query_param = try parseQueryParamAssignment("date_from=2026-06-16T00:00:00Z");
    try std.testing.expectEqualStrings("date_from", query_param.name);
    try std.testing.expectEqualStrings("2026-06-16T00:00:00Z", query_param.value);

    const empty_value = try parseQueryParamAssignment("flag=");
    try std.testing.expectEqualStrings("flag", empty_value.name);
    try std.testing.expectEqualStrings("", empty_value.value);

    const header_param = try parseHeaderParamAssignment("CF-R2-Jurisdiction=eu");
    try std.testing.expectEqualStrings("CF-R2-Jurisdiction", header_param.name);
    try std.testing.expectEqualStrings("eu", header_param.value);

    try std.testing.expectError(error.InvalidRouteParameterAssignment, parsePathParamAssignment("missing-equals"));
    try std.testing.expectError(error.InvalidRouteParameterAssignment, parseQueryParamAssignment("=value"));
}

test "renders route request objects for paths and urls" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    const request = Request{
        .path_params = &.{.{ .name = "virtualMachineId", .value = "vm/1" }},
        .query_params = &.{
            .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
            .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
        },
    };

    const path = try route.renderRequestPath(allocator, request);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines/vm%2F1/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", path);

    const url = try route.renderRequestUrl(allocator, "https://example.test", request);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://example.test/api/vps/v1/virtual-machines/vm%2F1/metrics?date_from=2026-06-16T00%3A00%3A00Z&date_to=2026-06-17T00%3A00%3A00Z", url);
}

test "validates required and known query parameters" {
    const allocator = std.testing.allocator;

    const route = (try findByOperationId(std.testing.io, allocator, .{}, .hostinger, "VPS_getMetricsV1")) orelse return error.TestExpectedRoute;
    defer route.deinit(allocator);

    try std.testing.expectError(
        error.MissingRouteQueryParameter,
        route.renderPathWithQuery(
            allocator,
            &.{.{ .name = "virtualMachineId", .value = "vm" }},
            &.{.{ .name = "date_from", .value = "2026-06-16T00:00:00Z" }},
        ),
    );
    try std.testing.expectError(
        error.UnknownRouteQueryParameter,
        route.renderPathWithQuery(
            allocator,
            &.{.{ .name = "virtualMachineId", .value = "vm" }},
            &.{
                .{ .name = "date_from", .value = "2026-06-16T00:00:00Z" },
                .{ .name = "date_to", .value = "2026-06-17T00:00:00Z" },
                .{ .name = "extra", .value = "ignored" },
            },
        ),
    );
}

test "reports missing parameters and invalid templates" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingRouteParameter, renderTemplatePath(allocator, "/accounts/{account_id}", &.{}));
    try std.testing.expectError(error.InvalidRouteTemplate, renderTemplatePath(allocator, "/accounts/{account_id", &.{.{ .name = "account_id", .value = "acct" }}));
    try std.testing.expectError(error.InvalidRouteTemplate, templateParameterNames(allocator, "/accounts/}"));
}

fn expectRouteParam(params: []const RouteParam, name: []const u8, required: bool) !void {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) {
            try std.testing.expectEqual(required, param.required);
            return;
        }
    }
    return error.TestExpectedRouteParam;
}

fn expectString(items: []const []u8, expected: []const u8) !void {
    for (items) |item| {
        if (std.mem.eql(u8, item, expected)) return;
    }
    return error.TestExpectedString;
}
