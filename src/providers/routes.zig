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
        inline for (std.meta.tags(Method)) |tag| {
            if (std.mem.eql(u8, value, @tagName(tag))) return tag;
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
        inline for (std.meta.tags(Support)) |tag| {
            if (std.mem.eql(u8, value, @tagName(tag))) return tag;
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
        inline for (std.meta.tags(Mode)) |tag| {
            if (std.mem.eql(u8, value, @tagName(tag))) return tag;
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

pub const OwnedExampleRequest = struct {
    request: Request,
    path_params: []PathParam,
    query_params: []QueryParam,
    header_params: []HeaderParam,
    values: [][]u8,

    pub fn deinit(self: OwnedExampleRequest, gpa: Allocator) void {
        for (self.values) |value| gpa.free(value);
        gpa.free(self.values);
        gpa.free(self.path_params);
        gpa.free(self.query_params);
        gpa.free(self.header_params);
    }
};

pub const RouteParam = struct {
    name: []u8,
    required: bool,
    style: ?[]u8,
    explode: ?bool,
    schema: ParamSchema,

    pub fn isArray(self: RouteParam) bool {
        return containsString(self.schema.types, "array");
    }

    pub fn queryExplodes(self: RouteParam) bool {
        return self.explode orelse true;
    }

    pub fn acceptsValue(self: RouteParam, value: []const u8) bool {
        if (self.schema.enum_values.len != 0) return containsString(self.schema.enum_values, value);
        return acceptsScalarTypeValue(self.schema.types, value);
    }
};

pub const ParamSchema = struct {
    schema_refs: [][]u8,
    types: [][]u8,
    formats: [][]u8,
    enum_values: [][]u8,
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

    pub fn containsAllSchemes(self: SecurityAlternative, schemes: []const []const u8) bool {
        for (schemes) |scheme| {
            if (!containsScheme(self.schemes, scheme)) return false;
        }
        return true;
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

    pub fn hasAlternativeContainingSchemes(self: Security, schemes: []const []const u8) bool {
        for (self.alternatives) |alternative| {
            if (alternative.containsAllSchemes(schemes)) return true;
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
    tests: []u8,
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
        const tests = core_json.fieldString(value, "tests") orelse return error.InvalidProviderRoute;
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
        const tests_owned = try gpa.dupe(u8, tests);
        errdefer gpa.free(tests_owned);
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
            .tests = tests_owned,
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
        gpa.free(self.tests);
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
        return self.findResponseForStatusCode(@backingInt(status));
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

    pub fn exampleRequest(self: Route, gpa: Allocator) !OwnedExampleRequest {
        var values = std.ArrayList([]u8).empty;
        errdefer deinitOwnedStringList(&values, gpa);
        var path_params = std.ArrayList(PathParam).empty;
        errdefer path_params.deinit(gpa);
        var query_params = std.ArrayList(QueryParam).empty;
        errdefer query_params.deinit(gpa);
        var header_params = std.ArrayList(HeaderParam).empty;
        errdefer header_params.deinit(gpa);

        try appendRequiredExamplePathParams(gpa, self.path_params, &values, &path_params);
        try appendRequiredExampleQueryParams(gpa, self.query_params, &values, &query_params);
        try appendRequiredExampleHeaderParams(gpa, self.header_params, &values, &header_params);

        const owned_path = try path_params.toOwnedSlice(gpa);
        errdefer gpa.free(owned_path);
        const owned_query = try query_params.toOwnedSlice(gpa);
        errdefer gpa.free(owned_query);
        const owned_header = try header_params.toOwnedSlice(gpa);
        errdefer gpa.free(owned_header);
        const owned_values = try values.toOwnedSlice(gpa);
        errdefer {
            for (owned_values) |value| gpa.free(value);
            gpa.free(owned_values);
        }
        const body = if (self.request_body.required and self.request_body.content_types.len != 0)
            BodyInput{ .present = true, .content_type = self.request_body.content_types[0] }
        else
            BodyInput{};

        return .{
            .request = .{
                .path_params = owned_path,
                .query_params = owned_query,
                .header_params = owned_header,
                .body = body,
            },
            .path_params = owned_path,
            .query_params = owned_query,
            .header_params = owned_header,
            .values = owned_values,
        };
    }
};

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
        const route_param = findRouteParamConst(allowed_params, param.name) orelse return error.UnknownRouteQueryParameter;
        if (!route_param.acceptsValue(param.value)) return error.InvalidRouteQueryParameterValue;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and !containsQueryParam(params, allowed.name)) return error.MissingRouteQueryParameter;
    }
    if (params.len == 0) return try gpa.dupe(u8, base);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.writeAll(base);
    var wrote_any = std.mem.indexOfScalar(u8, base, '?') != null;
    for (params, 0..) |param, index| {
        const route_param = findRouteParamConst(allowed_params, param.name) orelse return error.UnknownRouteQueryParameter;
        if (route_param.isArray() and !route_param.queryExplodes() and firstQueryParamIndex(params, param.name) != index) continue;

        try out.writer.writeByte(if (wrote_any) '&' else '?');
        wrote_any = true;

        const escaped_name = try queryEscape(gpa, param.name);
        defer gpa.free(escaped_name);
        const escaped_value = if (route_param.isArray() and !route_param.queryExplodes())
            try joinedEscapedQueryParamValues(gpa, params, param.name)
        else
            try queryEscape(gpa, param.value);
        defer gpa.free(escaped_value);

        try out.writer.writeAll(escaped_name);
        try out.writer.writeByte('=');
        try out.writer.writeAll(escaped_value);
    }
    return try out.toOwnedSlice();
}

fn joinedEscapedQueryParamValues(gpa: Allocator, params: []const QueryParam, name: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    var wrote_any = false;
    for (params) |param| {
        if (!std.mem.eql(u8, param.name, name)) continue;
        if (wrote_any) try out.writer.writeByte(',');
        wrote_any = true;
        const escaped = try queryEscape(gpa, param.value);
        defer gpa.free(escaped);
        try out.writer.writeAll(escaped);
    }
    return try out.toOwnedSlice();
}

fn firstQueryParamIndex(params: []const QueryParam, name: []const u8) usize {
    for (params, 0..) |param, index| {
        if (std.mem.eql(u8, param.name, name)) return index;
    }
    return params.len;
}

fn validatePathParams(allowed_params: []const RouteParam, params: []const PathParam) !void {
    for (params) |param| {
        const route_param = findRouteParamConst(allowed_params, param.name) orelse return error.UnknownRouteParameter;
        if (!route_param.acceptsValue(param.value)) return error.InvalidRouteParameterValue;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and findParam(params, allowed.name) == null) return error.MissingRouteParameter;
    }
}

fn validateHeaderParams(allowed_params: []const RouteParam, params: []const HeaderParam) !void {
    for (params) |param| {
        const route_param = findRouteParamConstIgnoreCase(allowed_params, param.name) orelse return error.UnknownRouteHeaderParameter;
        if (!route_param.acceptsValue(param.value)) return error.InvalidRouteHeaderParameterValue;
    }
    for (allowed_params) |allowed| {
        if (allowed.required and !containsHeaderParam(params, allowed.name)) return error.MissingRouteHeaderParameter;
    }
}

fn appendRequiredExamplePathParams(gpa: Allocator, allowed_params: []const RouteParam, values: *std.ArrayList([]u8), out: *std.ArrayList(PathParam)) !void {
    for (allowed_params) |param| {
        if (!param.required) continue;
        const value = try exampleParamValue(gpa, param);
        errdefer gpa.free(value);
        try out.append(gpa, .{ .name = param.name, .value = value });
        try values.append(gpa, value);
    }
}

fn appendRequiredExampleQueryParams(gpa: Allocator, allowed_params: []const RouteParam, values: *std.ArrayList([]u8), out: *std.ArrayList(QueryParam)) !void {
    for (allowed_params) |param| {
        if (!param.required) continue;
        const value = try exampleParamValue(gpa, param);
        errdefer gpa.free(value);
        try out.append(gpa, .{ .name = param.name, .value = value });
        try values.append(gpa, value);
    }
}

fn appendRequiredExampleHeaderParams(gpa: Allocator, allowed_params: []const RouteParam, values: *std.ArrayList([]u8), out: *std.ArrayList(HeaderParam)) !void {
    for (allowed_params) |param| {
        if (!param.required) continue;
        const value = try exampleParamValue(gpa, param);
        errdefer gpa.free(value);
        try out.append(gpa, .{ .name = param.name, .value = value });
        try values.append(gpa, value);
    }
}

fn exampleParamValue(gpa: Allocator, param: RouteParam) ![]u8 {
    if (param.schema.enum_values.len != 0) return try gpa.dupe(u8, param.schema.enum_values[0]);
    if (containsString(param.schema.types, "boolean")) return try gpa.dupe(u8, "true");
    if (containsString(param.schema.types, "integer")) return try gpa.dupe(u8, "1");
    if (containsString(param.schema.types, "number")) return try gpa.dupe(u8, "1");
    return try gpa.dupe(u8, "example");
}

fn deinitOwnedStringList(rows: *std.ArrayList([]u8), gpa: Allocator) void {
    for (rows.items) |item| gpa.free(item);
    rows.deinit(gpa);
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
        const style = if (core_json.fieldString(item, "style")) |style_text| try gpa.dupe(u8, style_text) else null;
        errdefer if (style) |owned_style| gpa.free(owned_style);
        const explode = core_json.fieldBool(item, "explode");
        const schema = try parseParamSchema(gpa, item);
        errdefer freeParamSchema(gpa, schema);

        try rows.append(gpa, .{
            .name = owned,
            .required = required,
            .style = style,
            .explode = explode,
            .schema = schema,
        });
    }
    return try rows.toOwnedSlice(gpa);
}

fn parseParamSchema(gpa: Allocator, value: std.json.Value) !ParamSchema {
    const field_value = core_json.field(value, "schema") orelse return try emptyParamSchema(gpa);
    if (field_value != .object) return error.InvalidProviderRoute;
    const schema_refs = try parseStringArray(gpa, field_value, "schema_refs");
    errdefer freeStringArray(gpa, schema_refs);
    const types = try parseStringArray(gpa, field_value, "types");
    errdefer freeStringArray(gpa, types);
    const formats = try parseStringArray(gpa, field_value, "formats");
    errdefer freeStringArray(gpa, formats);
    const enum_values = try parseStringArray(gpa, field_value, "enum_values");
    errdefer freeStringArray(gpa, enum_values);
    return .{
        .schema_refs = schema_refs,
        .types = types,
        .formats = formats,
        .enum_values = enum_values,
    };
}

fn emptyParamSchema(gpa: Allocator) !ParamSchema {
    const schema_refs = try gpa.alloc([]u8, 0);
    errdefer gpa.free(schema_refs);
    const types = try gpa.alloc([]u8, 0);
    errdefer gpa.free(types);
    const formats = try gpa.alloc([]u8, 0);
    errdefer gpa.free(formats);
    const enum_values = try gpa.alloc([]u8, 0);
    return .{
        .schema_refs = schema_refs,
        .types = types,
        .formats = formats,
        .enum_values = enum_values,
    };
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
    for (params) |param| {
        gpa.free(param.name);
        if (param.style) |style| gpa.free(style);
        freeParamSchema(gpa, param.schema);
    }
    gpa.free(params);
}

fn freeParamSchema(gpa: Allocator, schema: ParamSchema) void {
    freeStringArray(gpa, schema.schema_refs);
    freeStringArray(gpa, schema.types);
    freeStringArray(gpa, schema.formats);
    freeStringArray(gpa, schema.enum_values);
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

fn deinitRouteParamList(rows: *std.ArrayList(RouteParam), gpa: Allocator) void {
    for (rows.items) |param| {
        gpa.free(param.name);
        if (param.style) |style| gpa.free(style);
        freeParamSchema(gpa, param.schema);
    }
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

fn findRouteParamConst(params: []const RouteParam, candidate: []const u8) ?RouteParam {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, candidate)) return param;
    }
    return null;
}

fn findRouteParamConstIgnoreCase(params: []const RouteParam, candidate: []const u8) ?RouteParam {
    for (params) |param| {
        if (std.ascii.eqlIgnoreCase(param.name, candidate)) return param;
    }
    return null;
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

fn containsString(items: []const []u8, candidate: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, candidate)) return true;
    }
    return false;
}

fn acceptsScalarTypeValue(types: []const []u8, value: []const u8) bool {
    if (types.len == 0) return true;
    if (containsString(types, "string")) return true;
    if (containsString(types, "object")) return true;
    if (containsString(types, "boolean") and isRouteBoolean(value)) return true;
    if (containsString(types, "integer") and isRouteInteger(value)) return true;
    if (containsString(types, "number") and isRouteNumber(value)) return true;
    if (containsString(types, "boolean") or containsString(types, "integer") or containsString(types, "number")) return false;
    return true;
}

fn isRouteBoolean(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false");
}

fn isRouteInteger(value: []const u8) bool {
    if (value.len == 0) return false;
    _ = std.fmt.parseInt(i64, value, 10) catch return false;
    return true;
}

fn isRouteNumber(value: []const u8) bool {
    if (value.len == 0) return false;
    const parsed = std.fmt.parseFloat(f64, value) catch return false;
    return std.math.isFinite(parsed);
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

fn findParam(params: []const PathParam, name: []const u8) ?[]const u8 {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return param.value;
    }
    return null;
}

test "reports missing parameters and invalid templates" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingRouteParameter, renderTemplatePath(allocator, "/accounts/{account_id}", &.{}));
    try std.testing.expectError(error.InvalidRouteTemplate, renderTemplatePath(allocator, "/accounts/{account_id", &.{.{ .name = "account_id", .value = "acct" }}));
    try std.testing.expectError(error.InvalidRouteTemplate, templateParameterNames(allocator, "/accounts/}"));
}

