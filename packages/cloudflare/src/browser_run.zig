//! Cloudflare Browser Run REST support, including the Kitesurf beta engine.
//!
//! This module deliberately covers stateless Quick Actions and the documented
//! HTTP session lifecycle only. CDP control uses WebSockets; the package has no
//! WebSocket client dependency, so consumers should connect the returned
//! `web_socket_debugger_url` with a dedicated CDP/WebSocket library.

const std = @import("std");
const net_http = @import("net_http");
const transport = @import("provider_cloudflare_transport");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_json_response_bytes = net_http.max_body_bytes;
pub const max_cache_ttl_seconds: u32 = 86_400;
pub const max_navigation_timeout_ms: u32 = 60_000;
pub const max_action_timeout_ms: u32 = 120_000;
pub const max_wait_timeout_ms: u32 = 120_000;
pub const min_keep_alive_ms: u32 = 10_000;
/// Conservative cross-document cap: the generated API reference currently
/// says 1,200,000 ms, while Browser Run's session guide documents 600,000 ms.
pub const max_keep_alive_ms: u32 = 600_000;

/// Engines are always selected explicitly. There is no automatic fallback.
pub const Engine = enum {
    kitesurf,
    chromium_default,
};

/// This is a local preflight check, not a complete SSRF defense. Hostnames are
/// resolved by Cloudflare after the request leaves this process, so production
/// callers should still enforce a destination allowlist where appropriate.
pub const TargetPolicy = enum {
    public_http,
    allow_any_http,
};

pub const Source = union(enum) {
    url: []const u8,
    html: []const u8,
};

pub const WaitUntil = enum {
    load,
    domcontentloaded,
    networkidle0,
    networkidle2,
};

pub const GotoOptions = struct {
    timeout_ms: ?u32 = null,
    wait_until: ?WaitUntil = null,
};

pub const WaitForSelector = struct {
    selector: []const u8,
    timeout_ms: ?u32 = null,
    visible: bool = false,
    hidden: bool = false,
};

pub const Viewport = struct {
    width: u32,
    height: u32,
    device_scale_factor: ?f64 = null,
    is_mobile: ?bool = null,
    has_touch: ?bool = null,
    is_landscape: ?bool = null,
};

pub const BasicAuth = struct {
    username: []const u8,
    password: []const u8,
};

pub const SameSite = enum { Strict, Lax, None };

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    url: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    path: ?[]const u8 = null,
    expires: ?f64 = null,
    http_only: ?bool = null,
    secure: ?bool = null,
    same_site: ?SameSite = null,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const QuickActionOptions = struct {
    /// The API defaults to caching for five seconds. This library disables
    /// caching by default so credentials and caller-specific HTML are not
    /// accidentally reused.
    cache_ttl_seconds: u32 = 0,
    target_policy: TargetPolicy = .public_http,
    action_timeout_ms: ?u32 = null,
    goto: ?GotoOptions = null,
    wait_for_selector: ?WaitForSelector = null,
    wait_for_timeout_ms: ?u32 = null,
    viewport: ?Viewport = null,
    authenticate: ?BasicAuth = null,
    cookies: []const Cookie = &.{},
    extra_http_headers: []const Header = &.{},
    user_agent: ?[]const u8 = null,
    javascript_enabled: ?bool = null,
};

pub const ContentRequest = struct {
    source: Source,
    options: QuickActionOptions = .{},
};

pub const ScreenshotFormat = enum { png, jpeg, webp };

pub const ScreenshotOptions = struct {
    format: ScreenshotFormat = .png,
    quality: ?u8 = null,
    full_page: ?bool = null,
    omit_background: ?bool = null,
    capture_beyond_viewport: ?bool = null,
    optimize_for_speed: ?bool = null,
};

pub const ScreenshotRequest = struct {
    source: Source,
    options: QuickActionOptions = .{},
    screenshot: ScreenshotOptions = .{},
};

pub const ResponseMeta = net_http.ResponseMeta;

pub const ApiFailure = struct {
    status: std.http.Status,
    meta: ResponseMeta,
    /// Raw, caller-owned error payload. It may contain Cloudflare diagnostics
    /// and is never logged by the library.
    body: []u8,

    pub fn deinit(self: ApiFailure, allocator: Allocator) void {
        self.meta.deinit(allocator);
        allocator.free(self.body);
    }
};

pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: struct {
            value: T,
            meta: ResponseMeta,
        },
        api_error: ApiFailure,

        pub fn deinit(self: @This(), allocator: Allocator) void {
            switch (self) {
                .ok => |success| {
                    if (@hasDecl(T, "deinit")) success.value.deinit(allocator);
                    success.meta.deinit(allocator);
                },
                .api_error => |failure| failure.deinit(allocator),
            }
        }
    };
}

pub const Content = struct {
    html: []u8,
    title: ?[]u8 = null,
    origin_status: ?u16 = null,

    pub fn deinit(self: Content, allocator: Allocator) void {
        allocator.free(self.html);
        freeOptional(allocator, self.title);
    }
};

pub const BinaryReceipt = struct {
    bytes_written: usize,
};

pub const Screenshot = struct {
    bytes: []u8,

    pub fn deinit(self: Screenshot, allocator: Allocator) void {
        allocator.free(self.bytes);
    }
};

pub const Session = struct {
    session_id: []u8,
    /// Treat this URL as a bearer secret. The library never formats or logs it.
    web_socket_debugger_url: ?[]u8 = null,

    pub fn deinit(self: Session, allocator: Allocator) void {
        allocator.free(self.session_id);
        if (self.web_socket_debugger_url) |value| allocator.free(value);
    }
};

pub const SessionInfo = struct {
    session_id: []u8,
    close_reason: ?[]u8 = null,
    close_reason_text: ?[]u8 = null,
    connection_id: ?[]u8 = null,
    devtools_frontend_url: ?[]u8 = null,
    web_socket_debugger_url: ?[]u8 = null,
    connection_start_time: ?f64 = null,
    connection_end_time: ?f64 = null,
    start_time: ?f64 = null,
    end_time: ?f64 = null,
    last_updated: ?f64 = null,

    pub fn deinit(self: SessionInfo, allocator: Allocator) void {
        allocator.free(self.session_id);
        freeOptional(allocator, self.close_reason);
        freeOptional(allocator, self.close_reason_text);
        freeOptional(allocator, self.connection_id);
        freeOptional(allocator, self.devtools_frontend_url);
        freeOptional(allocator, self.web_socket_debugger_url);
    }
};

pub const SessionList = struct {
    items: []SessionInfo,

    pub fn deinit(self: SessionList, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const SessionLookup = struct {
    value: ?SessionInfo,

    pub fn deinit(self: SessionLookup, allocator: Allocator) void {
        if (self.value) |value| value.deinit(allocator);
    }
};

pub const Target = struct {
    id: []u8,
    kind: []u8,
    url: []u8,
    title: ?[]u8 = null,
    description: ?[]u8 = null,
    devtools_frontend_url: ?[]u8 = null,
    web_socket_debugger_url: ?[]u8 = null,

    pub fn deinit(self: Target, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.kind);
        allocator.free(self.url);
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.description);
        freeOptional(allocator, self.devtools_frontend_url);
        freeOptional(allocator, self.web_socket_debugger_url);
    }
};

pub const TargetList = struct {
    items: []Target,

    pub fn deinit(self: TargetList, allocator: Allocator) void {
        for (self.items) |item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const CloseStatus = enum { closing, closed };

pub const CreateSessionOptions = struct {
    keep_alive_ms: ?u32 = null,
};

pub const SessionListOptions = struct {
    limit: ?u16 = null,
    offset: ?u32 = null,
};

pub const Client = struct {
    auth: transport.Auth,
    base_url: []const u8,
    account_id: []const u8,
    engine: Engine,

    /// All slices are borrowed and must outlive this client and any call.
    pub fn init(auth: transport.Auth, base_url: []const u8, account_id: []const u8, engine: Engine) !Client {
        if (!auth.hasApiToken()) return error.MissingCloudflareApiToken;
        if (base_url.len == 0) return error.InvalidCloudflareBaseUrl;
        if (account_id.len == 0) return error.InvalidCloudflareAccountId;
        return .{ .auth = auth, .base_url = base_url, .account_id = account_id, .engine = engine };
    }

    pub fn content(self: Client, io: Io, allocator: Allocator, request: ContentRequest) !Result(Content) {
        try validateQuickAction(request.source, request.options);
        const url = try self.quickActionUrl(allocator, "content", request.options.cache_ttl_seconds);
        defer allocator.free(url);
        const body = try quickActionBody(allocator, request.source, request.options, null);
        defer allocator.free(body);
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .POST, url, body, &headers, .{ .buffer = max_json_response_bytes });
        return try parseContentResponse(allocator, response);
    }

    pub fn screenshotTo(
        self: Client,
        io: Io,
        allocator: Allocator,
        request: ScreenshotRequest,
        writer: *std.Io.Writer,
        max_bytes: usize,
    ) !Result(BinaryReceipt) {
        if (max_bytes == 0) return error.InvalidResponseLimit;
        try validateQuickAction(request.source, request.options);
        try validateScreenshot(request.screenshot);
        const url = try self.quickActionUrl(allocator, "screenshot", request.options.cache_ttl_seconds);
        defer allocator.free(url);
        const body = try quickActionBody(allocator, request.source, request.options, request.screenshot);
        defer allocator.free(body);
        const headers = screenshotHeaders();
        const png_types = [_][]const u8{"image/png"};
        const jpeg_types = [_][]const u8{ "image/jpeg", "image/jpg" };
        const webp_types = [_][]const u8{"image/webp"};
        const accepted: []const []const u8 = switch (request.screenshot.format) {
            .png => &png_types,
            .jpeg => &jpeg_types,
            .webp => &webp_types,
        };
        const response = try requestTokenDetailed(io, allocator, self.auth, .POST, url, body, &headers, .{
            .stream_success = .{
                .writer = writer,
                .max_bytes = max_bytes,
                .accepted_content_types = accepted,
                .fallback_max_bytes = max_json_response_bytes,
            },
        });
        return try takeBinaryResponse(allocator, response);
    }

    pub fn screenshotAlloc(
        self: Client,
        io: Io,
        allocator: Allocator,
        request: ScreenshotRequest,
        max_bytes: usize,
    ) !Result(Screenshot) {
        var output = std.Io.Writer.Allocating.init(allocator);
        defer output.deinit();
        const streamed = try self.screenshotTo(io, allocator, request, &output.writer, max_bytes);
        return switch (streamed) {
            .api_error => |failure| .{ .api_error = failure },
            .ok => |success| blk: {
                errdefer success.meta.deinit(allocator);
                const bytes = try output.toOwnedSlice();
                errdefer allocator.free(bytes);
                try validateScreenshotBytes(request.screenshot.format, bytes);
                break :blk .{ .ok = .{
                    .value = .{ .bytes = bytes },
                    .meta = success.meta,
                } };
            },
        };
    }

    pub fn createSession(self: Client, io: Io, allocator: Allocator, options: CreateSessionOptions) !Result(Session) {
        if (options.keep_alive_ms) |value| {
            if (value < min_keep_alive_ms or value > max_keep_alive_ms) return error.InvalidKeepAlive;
        }
        var url = try self.routeUrl(allocator, "devtools/browser");
        defer allocator.free(url);
        if (options.keep_alive_ms) |value| {
            const next = try appendNumberQuery(allocator, url, "keep_alive", value);
            allocator.free(url);
            url = next;
        }
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .POST, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseSessionResponse(allocator, response);
    }

    pub fn listSessions(self: Client, io: Io, allocator: Allocator, options: SessionListOptions) !Result(SessionList) {
        if (options.limit) |value| if (value == 0) return error.InvalidPagination;
        var url = try self.routeUrl(allocator, "devtools/session");
        defer allocator.free(url);
        if (options.limit) |value| {
            const next = try appendNumberQuery(allocator, url, "limit", value);
            allocator.free(url);
            url = next;
        }
        if (options.offset) |value| {
            const next = try appendNumberQuery(allocator, url, "offset", value);
            allocator.free(url);
            url = next;
        }
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .GET, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseSessionListResponse(allocator, response);
    }

    pub fn getSession(self: Client, io: Io, allocator: Allocator, session_id: []const u8) !Result(SessionLookup) {
        const url = try self.resourceUrl(allocator, "devtools/session", session_id, null);
        defer allocator.free(url);
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .GET, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseSessionLookupResponse(allocator, response);
    }

    pub fn listTargets(self: Client, io: Io, allocator: Allocator, session_id: []const u8) !Result(TargetList) {
        const url = try self.resourceUrl(allocator, "devtools/browser", session_id, "json/list");
        defer allocator.free(url);
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .GET, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseTargetListResponse(allocator, response);
    }

    pub fn newTarget(
        self: Client,
        io: Io,
        allocator: Allocator,
        session_id: []const u8,
        target_url: ?[]const u8,
        policy: TargetPolicy,
    ) !Result(Target) {
        if (target_url) |value| try validateTargetUrl(value, policy);
        var url = try self.resourceUrl(allocator, "devtools/browser", session_id, "json/new");
        defer allocator.free(url);
        if (target_url) |value| {
            const next = try appendStringQuery(allocator, url, "url", value);
            allocator.free(url);
            url = next;
        }
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .PUT, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseTargetResponse(allocator, response);
    }

    pub fn closeSession(self: Client, io: Io, allocator: Allocator, session_id: []const u8) !Result(CloseStatus) {
        const url = try self.resourceUrl(allocator, "devtools/browser", session_id, null);
        defer allocator.free(url);
        const headers = jsonHeaders();
        const response = try requestTokenDetailed(io, allocator, self.auth, .DELETE, url, null, &headers, .{ .buffer = max_json_response_bytes });
        return parseCloseResponse(allocator, response);
    }

    fn quickActionUrl(self: Client, allocator: Allocator, action: []const u8, cache_ttl: u32) ![]u8 {
        const url = try self.routeUrl(allocator, action);
        errdefer allocator.free(url);
        const next = try appendNumberQuery(allocator, url, "cacheTTL", cache_ttl);
        allocator.free(url);
        return next;
    }

    fn routeUrl(self: Client, allocator: Allocator, suffix: []const u8) ![]u8 {
        const account = try escape(allocator, self.account_id);
        defer allocator.free(account);
        const root = std.mem.trimEnd(u8, self.base_url, "/");
        var url = try std.fmt.allocPrint(allocator, "{s}/accounts/{s}/{s}/{s}", .{ root, account, enginePath(self.engine), suffix });
        errdefer allocator.free(url);
        if (self.engine == .kitesurf) {
            const next = try appendStringQuery(allocator, url, "browser", "kitesurf");
            allocator.free(url);
            url = next;
        }
        return url;
    }

    fn resourceUrl(self: Client, allocator: Allocator, prefix: []const u8, resource_id: []const u8, suffix: ?[]const u8) ![]u8 {
        if (resource_id.len == 0) return error.InvalidResourceId;
        const escaped = try escape(allocator, resource_id);
        defer allocator.free(escaped);
        const route = if (suffix) |tail|
            try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ prefix, escaped, tail })
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, escaped });
        defer allocator.free(route);
        return self.routeUrl(allocator, route);
    }
};

fn enginePath(engine: Engine) []const u8 {
    return switch (engine) {
        .kitesurf => "browser-run",
        .chromium_default => "browser-rendering",
    };
}

/// Browser Run documents API-token authentication only. This helper is local
/// to the module so the existing transport's legacy fallback remains unchanged.
fn requestTokenDetailed(
    io: Io,
    allocator: Allocator,
    auth: transport.Auth,
    method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
    headers: []const std.http.Header,
    body_mode: net_http.BodyMode,
) !net_http.DetailedResponse {
    const token = auth.token orelse return error.MissingCloudflareApiToken;
    if (token.len == 0) return error.MissingCloudflareApiToken;
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
    defer allocator.free(auth_header);
    const privileged = [_]std.http.Header{.{ .name = "Authorization", .value = auth_header }};
    return net_http.requestDetailed(allocator, io, method, url, body, headers, &privileged, body_mode);
}

fn jsonHeaders() [2]std.http.Header {
    return .{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    };
}

fn screenshotHeaders() [2]std.http.Header {
    return .{
        .{ .name = "Accept", .value = "image/png, image/jpeg, image/webp, application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    };
}

fn validateQuickAction(source: Source, options: QuickActionOptions) !void {
    if (options.cache_ttl_seconds > max_cache_ttl_seconds) return error.InvalidCacheTtl;
    switch (source) {
        .url => |url| try validateTargetUrl(url, options.target_policy),
        .html => |html| if (html.len == 0) return error.EmptyHtml,
    }
    if (options.action_timeout_ms) |value| if (value > max_action_timeout_ms) return error.InvalidActionTimeout;
    if (options.goto) |goto| {
        if (goto.timeout_ms) |value| if (value > max_navigation_timeout_ms) return error.InvalidNavigationTimeout;
    }
    if (options.wait_for_timeout_ms) |value| if (value > max_wait_timeout_ms) return error.InvalidWaitTimeout;
    if (options.wait_for_selector) |selector| {
        if (selector.selector.len == 0) return error.InvalidSelector;
        if (selector.visible and selector.hidden) return error.InvalidSelectorOptions;
        if (selector.timeout_ms) |value| if (value > max_wait_timeout_ms) return error.InvalidWaitTimeout;
    }
    if (options.viewport) |viewport| {
        if (viewport.width == 0 or viewport.height == 0) return error.InvalidViewport;
        if (viewport.device_scale_factor) |value| if (!std.math.isFinite(value) or value <= 0) return error.InvalidViewport;
    }
    if (options.authenticate) |auth| {
        if (auth.username.len == 0 or auth.password.len == 0) return error.InvalidTargetCredentials;
    }
    for (options.cookies) |cookie| {
        if (cookie.name.len == 0) return error.InvalidCookie;
        if (cookie.url) |url| try validateTargetUrl(url, options.target_policy);
    }
    for (options.extra_http_headers) |header| {
        if (header.name.len == 0 or containsControl(header.name) or containsControl(header.value) or std.mem.indexOfScalar(u8, header.name, ':') != null)
            return error.InvalidTargetHeader;
    }
}

fn validateScreenshot(options: ScreenshotOptions) !void {
    if (options.quality) |quality| {
        if (options.format == .png or quality > 100) return error.InvalidScreenshotQuality;
    }
}

fn validateScreenshotBytes(format: ScreenshotFormat, bytes: []const u8) !void {
    const valid = switch (format) {
        .png => bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n"),
        .jpeg => bytes.len >= 3 and std.mem.eql(u8, bytes[0..3], "\xff\xd8\xff"),
        .webp => bytes.len >= 12 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP"),
    };
    if (!valid) return error.InvalidScreenshotPayload;
}

pub fn validateTargetUrl(value: []const u8, policy: TargetPolicy) !void {
    if (value.len == 0) return error.InvalidTargetUrl;
    const uri = std.Uri.parse(value) catch return error.InvalidTargetUrl;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "http") and !std.ascii.eqlIgnoreCase(uri.scheme, "https")) return error.InvalidTargetUrl;
    if (uri.user != null or uri.password != null or uri.host == null) return error.InvalidTargetUrl;
    if (policy == .allow_any_http) return;

    const host = componentRaw(uri.host.?) orelse return error.InvalidTargetUrl;
    if (host.len == 0) return error.InvalidTargetUrl;
    if (std.ascii.eqlIgnoreCase(host, "localhost") or
        endsWithIgnoreCase(host, ".localhost") or
        endsWithIgnoreCase(host, ".local") or
        endsWithIgnoreCase(host, ".internal")) return error.PrivateTargetRejected;

    if (parseAddress(host)) |address| {
        if (!isPublicAddress(address)) return error.PrivateTargetRejected;
    }
}

fn parseAddress(host: []const u8) ?std.Io.net.IpAddress {
    return std.Io.net.IpAddress.parseLiteral(host) catch
        (std.Io.net.IpAddress.parse(host, 0) catch null);
}

fn isPublicAddress(address: std.Io.net.IpAddress) bool {
    return switch (address) {
        .ip4 => |ip| isPublicIp4(ip.bytes),
        .ip6 => |ip| isPublicIp6(ip.bytes),
    };
}

fn isPublicIp4(bytes: [4]u8) bool {
    const a = bytes[0];
    const b = bytes[1];
    if (a == 0 or a == 10 or a == 127 or a >= 224) return false;
    if (a == 100 and b >= 64 and b <= 127) return false;
    if (a == 169 and b == 254) return false;
    if (a == 172 and b >= 16 and b <= 31) return false;
    if (a == 192 and (b == 0 or b == 168)) return false;
    if (a == 198 and (b == 18 or b == 19 or (b == 51 and bytes[2] == 100))) return false;
    if (a == 203 and b == 0 and bytes[2] == 113) return false;
    return true;
}

fn isPublicIp6(bytes: [16]u8) bool {
    if (std.mem.allEqual(u8, &bytes, 0)) return false;
    if (std.mem.allEqual(u8, bytes[0..15], 0) and bytes[15] == 1) return false;
    if (bytes[0] & 0xfe == 0xfc) return false;
    if (bytes[0] == 0xfe and bytes[1] & 0xc0 == 0x80) return false;
    if (bytes[0] == 0xff) return false;
    if (std.mem.eql(u8, bytes[0..4], &.{ 0x20, 0x01, 0x0d, 0xb8 })) return false;
    if (std.mem.eql(u8, bytes[0..12], &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff }))
        return isPublicIp4(bytes[12..16].*);
    return true;
}

fn quickActionBody(allocator: Allocator, source: Source, options: QuickActionOptions, screenshot: ?ScreenshotOptions) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeByte('{');
    var first = true;
    switch (source) {
        .url => |value| try jsonField(writer, &first, "url", value),
        .html => |value| try jsonField(writer, &first, "html", value),
    }
    if (options.action_timeout_ms) |value| try jsonField(writer, &first, "actionTimeout", value);
    if (options.goto) |value| {
        try jsonFieldName(writer, &first, "gotoOptions");
        try writer.writeByte('{');
        var nested = true;
        if (value.timeout_ms) |timeout| try jsonField(writer, &nested, "timeout", timeout);
        if (value.wait_until) |wait| try jsonField(writer, &nested, "waitUntil", @tagName(wait));
        try writer.writeByte('}');
    }
    if (options.wait_for_selector) |value| {
        try jsonFieldName(writer, &first, "waitForSelector");
        try writer.writeByte('{');
        var nested = true;
        try jsonField(writer, &nested, "selector", value.selector);
        if (value.timeout_ms) |timeout| try jsonField(writer, &nested, "timeout", timeout);
        if (value.visible) try jsonField(writer, &nested, "visible", true);
        if (value.hidden) try jsonField(writer, &nested, "hidden", true);
        try writer.writeByte('}');
    }
    if (options.wait_for_timeout_ms) |value| try jsonField(writer, &first, "waitForTimeout", value);
    if (options.viewport) |value| {
        try jsonFieldName(writer, &first, "viewport");
        try writer.writeByte('{');
        var nested = true;
        try jsonField(writer, &nested, "width", value.width);
        try jsonField(writer, &nested, "height", value.height);
        if (value.device_scale_factor) |scale| try jsonField(writer, &nested, "deviceScaleFactor", scale);
        if (value.is_mobile) |mobile| try jsonField(writer, &nested, "isMobile", mobile);
        if (value.has_touch) |touch| try jsonField(writer, &nested, "hasTouch", touch);
        if (value.is_landscape) |landscape| try jsonField(writer, &nested, "isLandscape", landscape);
        try writer.writeByte('}');
    }
    if (options.authenticate) |value| {
        try jsonFieldName(writer, &first, "authenticate");
        try writer.writeByte('{');
        var nested = true;
        try jsonField(writer, &nested, "username", value.username);
        try jsonField(writer, &nested, "password", value.password);
        try writer.writeByte('}');
    }
    if (options.cookies.len != 0) {
        try jsonFieldName(writer, &first, "cookies");
        try writer.writeByte('[');
        for (options.cookies, 0..) |cookie, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            var nested = true;
            try jsonField(writer, &nested, "name", cookie.name);
            try jsonField(writer, &nested, "value", cookie.value);
            if (cookie.url) |value| try jsonField(writer, &nested, "url", value);
            if (cookie.domain) |value| try jsonField(writer, &nested, "domain", value);
            if (cookie.path) |value| try jsonField(writer, &nested, "path", value);
            if (cookie.expires) |value| try jsonField(writer, &nested, "expires", value);
            if (cookie.http_only) |value| try jsonField(writer, &nested, "httpOnly", value);
            if (cookie.secure) |value| try jsonField(writer, &nested, "secure", value);
            if (cookie.same_site) |value| try jsonField(writer, &nested, "sameSite", @tagName(value));
            try writer.writeByte('}');
        }
        try writer.writeByte(']');
    }
    if (options.extra_http_headers.len != 0) {
        try jsonFieldName(writer, &first, "setExtraHTTPHeaders");
        try writer.writeByte('{');
        for (options.extra_http_headers, 0..) |header, index| {
            if (index != 0) try writer.writeByte(',');
            try std.json.Stringify.value(header.name, .{}, writer);
            try writer.writeByte(':');
            try std.json.Stringify.value(header.value, .{}, writer);
        }
        try writer.writeByte('}');
    }
    if (options.user_agent) |value| try jsonField(writer, &first, "userAgent", value);
    if (options.javascript_enabled) |value| try jsonField(writer, &first, "setJavaScriptEnabled", value);
    if (screenshot) |value| {
        try jsonFieldName(writer, &first, "screenshotOptions");
        try writer.writeByte('{');
        var nested = true;
        try jsonField(writer, &nested, "type", @tagName(value.format));
        try jsonField(writer, &nested, "encoding", "binary");
        if (value.quality) |quality| try jsonField(writer, &nested, "quality", quality);
        if (value.full_page) |full_page| try jsonField(writer, &nested, "fullPage", full_page);
        if (value.omit_background) |omit| try jsonField(writer, &nested, "omitBackground", omit);
        if (value.capture_beyond_viewport) |capture| try jsonField(writer, &nested, "captureBeyondViewport", capture);
        if (value.optimize_for_speed) |optimize| try jsonField(writer, &nested, "optimizeForSpeed", optimize);
        try writer.writeByte('}');
    }
    try writer.writeByte('}');
    return output.toOwnedSlice();
}

fn jsonField(writer: *std.Io.Writer, first: *bool, name: []const u8, value: anytype) !void {
    try jsonFieldName(writer, first, name);
    try std.json.Stringify.value(value, .{}, writer);
}

fn jsonFieldName(writer: *std.Io.Writer, first: *bool, name: []const u8) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try std.json.Stringify.value(name, .{}, writer);
    try writer.writeByte(':');
}

fn parseContentResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(Content) {
    if (!net_http.isOk(response.status)) return .{ .api_error = takeApiFailure(response) };
    const body = switch (response.body) {
        .bytes => |bytes| bytes,
        .streamed => unreachable,
    };
    defer allocator.free(body);
    errdefer response.meta.deinit(allocator);
    const Envelope = struct {
        const Meta = struct {
            status: ?u16 = null,
            title: ?[]const u8 = null,
        };
        result: ?[]const u8 = null,
        success: bool,
        meta: ?Meta = null,
    };
    const parsed = try std.json.parseFromSlice(Envelope, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (!parsed.value.success) return error.MalformedCloudflareResponse;
    const html = parsed.value.result orelse return error.MalformedCloudflareResponse;
    var value: Content = .{ .html = try allocator.dupe(u8, html) };
    errdefer value.deinit(allocator);
    if (parsed.value.meta) |meta| {
        value.title = try dupeOptional(allocator, meta.title);
        value.origin_status = meta.status;
    }
    return .{ .ok = .{ .value = value, .meta = response.meta } };
}

fn takeBinaryResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(BinaryReceipt) {
    if (!net_http.isOk(response.status)) return .{ .api_error = takeApiFailure(response) };
    return switch (response.body) {
        .streamed => |count| .{ .ok = .{ .value = .{ .bytes_written = count }, .meta = response.meta } },
        .bytes => |body| blk: {
            allocator.free(body);
            response.meta.deinit(allocator);
            break :blk error.UnexpectedScreenshotContentType;
        },
    };
}

fn takeApiFailure(response: net_http.DetailedResponse) ApiFailure {
    return .{
        .status = response.status,
        .meta = response.meta,
        .body = switch (response.body) {
            .bytes => |bytes| bytes,
            .streamed => unreachable,
        },
    };
}

const RawSession = struct {
    sessionId: []const u8,
    webSocketDebuggerUrl: ?[]const u8 = null,
};

const RawSessionInfo = struct {
    sessionId: []const u8,
    closeReason: ?[]const u8 = null,
    closeReasonText: ?[]const u8 = null,
    connectionId: ?[]const u8 = null,
    devtoolsFrontendUrl: ?[]const u8 = null,
    webSocketDebuggerUrl: ?[]const u8 = null,
    connectionStartTime: ?f64 = null,
    connectionEndTime: ?f64 = null,
    startTime: ?f64 = null,
    endTime: ?f64 = null,
    lastUpdated: ?f64 = null,
};

const RawTarget = struct {
    id: []const u8,
    type: []const u8,
    url: []const u8,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    devtoolsFrontendUrl: ?[]const u8 = null,
    webSocketDebuggerUrl: ?[]const u8 = null,
};

fn parseSessionResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(Session) {
    const parsed = try parseJsonResponse(RawSession, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            errdefer success.meta.deinit(allocator);
            var value: Session = .{ .session_id = try allocator.dupe(u8, success.parsed.value.sessionId) };
            errdefer value.deinit(allocator);
            value.web_socket_debugger_url = try dupeOptional(allocator, success.parsed.value.webSocketDebuggerUrl);
            break :blk .{ .ok = .{ .value = value, .meta = success.meta } };
        },
    };
}

fn parseSessionListResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(SessionList) {
    const parsed = try parseJsonResponse([]RawSessionInfo, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            errdefer success.meta.deinit(allocator);
            const items = try allocator.alloc(SessionInfo, success.parsed.value.len);
            var initialized: usize = 0;
            errdefer {
                for (items[0..initialized]) |item| item.deinit(allocator);
                allocator.free(items);
            }
            for (success.parsed.value, 0..) |raw, index| {
                items[index] = try ownSessionInfo(allocator, raw);
                initialized += 1;
            }
            break :blk .{ .ok = .{ .value = .{ .items = items }, .meta = success.meta } };
        },
    };
}

fn parseSessionLookupResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(SessionLookup) {
    const parsed = try parseJsonResponse(?RawSessionInfo, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            errdefer success.meta.deinit(allocator);
            const value = if (success.parsed.value) |raw| try ownSessionInfo(allocator, raw) else null;
            break :blk .{ .ok = .{ .value = .{ .value = value }, .meta = success.meta } };
        },
    };
}

fn parseTargetResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(Target) {
    const parsed = try parseJsonResponse(RawTarget, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            errdefer success.meta.deinit(allocator);
            break :blk .{ .ok = .{ .value = try ownTarget(allocator, success.parsed.value), .meta = success.meta } };
        },
    };
}

fn parseTargetListResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(TargetList) {
    const parsed = try parseJsonResponse([]RawTarget, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            errdefer success.meta.deinit(allocator);
            const items = try allocator.alloc(Target, success.parsed.value.len);
            var initialized: usize = 0;
            errdefer {
                for (items[0..initialized]) |item| item.deinit(allocator);
                allocator.free(items);
            }
            for (success.parsed.value, 0..) |raw, index| {
                items[index] = try ownTarget(allocator, raw);
                initialized += 1;
            }
            break :blk .{ .ok = .{ .value = .{ .items = items }, .meta = success.meta } };
        },
    };
}

fn parseCloseResponse(allocator: Allocator, response: net_http.DetailedResponse) !Result(CloseStatus) {
    const RawClose = struct { status: CloseStatus };
    const parsed = try parseJsonResponse(RawClose, allocator, response);
    return switch (parsed) {
        .api_error => |failure| .{ .api_error = failure },
        .ok => |success| blk: {
            defer success.parsed.deinit();
            break :blk .{ .ok = .{ .value = success.parsed.value.status, .meta = success.meta } };
        },
    };
}

fn ParsedJson(comptime T: type) type {
    return union(enum) {
        ok: struct { parsed: std.json.Parsed(T), meta: ResponseMeta },
        api_error: ApiFailure,
    };
}

fn parseJsonResponse(comptime T: type, allocator: Allocator, response: net_http.DetailedResponse) !ParsedJson(T) {
    if (!net_http.isOk(response.status)) return .{ .api_error = takeApiFailure(response) };
    const body = switch (response.body) {
        .bytes => |bytes| bytes,
        .streamed => unreachable,
    };
    defer allocator.free(body);
    errdefer response.meta.deinit(allocator);
    const parsed = try std.json.parseFromSlice(T, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    return .{ .ok = .{ .parsed = parsed, .meta = response.meta } };
}

fn ownSessionInfo(allocator: Allocator, raw: RawSessionInfo) !SessionInfo {
    var value: SessionInfo = .{ .session_id = try allocator.dupe(u8, raw.sessionId) };
    errdefer value.deinit(allocator);
    value.close_reason = try dupeOptional(allocator, raw.closeReason);
    value.close_reason_text = try dupeOptional(allocator, raw.closeReasonText);
    value.connection_id = try dupeOptional(allocator, raw.connectionId);
    value.devtools_frontend_url = try dupeOptional(allocator, raw.devtoolsFrontendUrl);
    value.web_socket_debugger_url = try dupeOptional(allocator, raw.webSocketDebuggerUrl);
    value.connection_start_time = raw.connectionStartTime;
    value.connection_end_time = raw.connectionEndTime;
    value.start_time = raw.startTime;
    value.end_time = raw.endTime;
    value.last_updated = raw.lastUpdated;
    return value;
}

fn ownTarget(allocator: Allocator, raw: RawTarget) !Target {
    const id = try allocator.dupe(u8, raw.id);
    errdefer allocator.free(id);
    const kind = try allocator.dupe(u8, raw.type);
    errdefer allocator.free(kind);
    const url = try allocator.dupe(u8, raw.url);
    errdefer allocator.free(url);
    const title = try dupeOptional(allocator, raw.title);
    errdefer freeOptional(allocator, title);
    const description = try dupeOptional(allocator, raw.description);
    errdefer freeOptional(allocator, description);
    const devtools_frontend_url = try dupeOptional(allocator, raw.devtoolsFrontendUrl);
    errdefer freeOptional(allocator, devtools_frontend_url);
    const web_socket_debugger_url = try dupeOptional(allocator, raw.webSocketDebuggerUrl);
    errdefer freeOptional(allocator, web_socket_debugger_url);
    return .{
        .id = id,
        .kind = kind,
        .url = url,
        .title = title,
        .description = description,
        .devtools_frontend_url = devtools_frontend_url,
        .web_socket_debugger_url = web_socket_debugger_url,
    };
}

fn dupeOptional(allocator: Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |slice| try allocator.dupe(u8, slice) else null;
}

fn freeOptional(allocator: Allocator, value: ?[]u8) void {
    if (value) |slice| allocator.free(slice);
}

fn appendStringQuery(allocator: Allocator, url: []const u8, name: []const u8, value: []const u8) ![]u8 {
    const escaped = try escape(allocator, value);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{s}{c}{s}={s}", .{ url, querySeparator(url), name, escaped });
}

fn appendNumberQuery(allocator: Allocator, url: []const u8, name: []const u8, value: anytype) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{c}{s}={d}", .{ url, querySeparator(url), name, value });
}

fn querySeparator(url: []const u8) u8 {
    return if (std.mem.indexOfScalar(u8, url, '?') == null) '?' else '&';
}

fn escape(allocator: Allocator, value: []const u8) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try (std.Uri.Component{ .raw = value }).formatEscaped(&output.writer);
    return output.toOwnedSlice();
}

fn componentRaw(component: std.Uri.Component) ?[]const u8 {
    return switch (component) {
        .raw => |value| value,
        .percent_encoded => |value| if (std.mem.indexOfScalar(u8, value, '%') == null) value else null,
    };
}

fn containsControl(value: []const u8) bool {
    for (value) |byte| if (byte < 0x20 or byte == 0x7f) return true;
    return false;
}

fn endsWithIgnoreCase(value: []const u8, suffix: []const u8) bool {
    if (value.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(value[value.len - suffix.len ..], suffix);
}

test "Kitesurf routes use the new path and explicit engine query" {
    const allocator = std.testing.allocator;
    const client = try Client.init(.{ .token = "test" }, "https://api.example.test/client/v4", "acct/team", .kitesurf);
    const url = try client.quickActionUrl(allocator, "content", 0);
    defer allocator.free(url);
    try std.testing.expectEqualStrings(
        "https://api.example.test/client/v4/accounts/acct%2Fteam/browser-run/content?browser=kitesurf&cacheTTL=0",
        url,
    );

    const chromium = try Client.init(.{ .token = "test" }, "https://api.example.test/client/v4", "acct", .chromium_default);
    const old_url = try chromium.quickActionUrl(allocator, "screenshot", 5);
    defer allocator.free(old_url);
    try std.testing.expectEqualStrings(
        "https://api.example.test/client/v4/accounts/acct/browser-rendering/screenshot?cacheTTL=5",
        old_url,
    );
}

test "Browser Run requires an API token" {
    try std.testing.expectError(
        error.MissingCloudflareApiToken,
        Client.init(.{ .email = "user@example.com", .key = "global-key" }, "https://api.example.test/client/v4", "acct", .kitesurf),
    );
}

test "Quick Action JSON uses documented field names and binary screenshots" {
    const allocator = std.testing.allocator;
    const body = try quickActionBody(allocator, .{ .url = "https://example.com" }, .{
        .goto = .{ .timeout_ms = 45_000, .wait_until = .networkidle2 },
        .viewport = .{ .width = 1280, .height = 720 },
    }, .{ .format = .webp, .quality = 80, .full_page = true });
    defer allocator.free(body);
    try std.testing.expectEqualStrings(
        "{\"url\":\"https://example.com\",\"gotoOptions\":{\"timeout\":45000,\"waitUntil\":\"networkidle2\"},\"viewport\":{\"width\":1280,\"height\":720},\"screenshotOptions\":{\"type\":\"webp\",\"encoding\":\"binary\",\"quality\":80,\"fullPage\":true}}",
        body,
    );
}

test "target URL validation rejects local and non-HTTP destinations" {
    try validateTargetUrl("https://example.com/path", .public_http);
    try std.testing.expectError(error.PrivateTargetRejected, validateTargetUrl("http://127.0.0.1/admin", .public_http));
    try std.testing.expectError(error.PrivateTargetRejected, validateTargetUrl("http://[::1]/", .public_http));
    try std.testing.expectError(error.PrivateTargetRejected, validateTargetUrl("http://service.internal/", .public_http));
    try std.testing.expectError(error.InvalidTargetUrl, validateTargetUrl("file:///etc/passwd", .public_http));
    try validateTargetUrl("http://127.0.0.1/admin", .allow_any_http);
}

test "content and session envelopes are owned after parsing" {
    const allocator = std.testing.allocator;
    const content_body = try allocator.dupe(u8, "{\"success\":true,\"result\":\"<html>ok</html>\",\"meta\":{\"status\":200,\"title\":\"Example\"}}");
    var content = try parseContentResponse(allocator, .{
        .status = .ok,
        .meta = .{},
        .body = .{ .bytes = content_body },
    });
    defer content.deinit(allocator);
    try std.testing.expectEqualStrings("<html>ok</html>", content.ok.value.html);
    try std.testing.expectEqualStrings("Example", content.ok.value.title.?);
    try std.testing.expectEqual(@as(?u16, 200), content.ok.value.origin_status);

    const session_body = try allocator.dupe(u8, "{\"sessionId\":\"s1\",\"webSocketDebuggerUrl\":\"wss://secret\"}");
    var session = try parseSessionResponse(allocator, .{
        .status = .ok,
        .meta = .{},
        .body = .{ .bytes = session_body },
    });
    defer session.deinit(allocator);
    try std.testing.expectEqualStrings("s1", session.ok.value.session_id);
    try std.testing.expectEqualStrings("wss://secret", session.ok.value.web_socket_debugger_url.?);
}

const TestResponse = struct {
    status: std.http.Status = .ok,
    content_type: []const u8,
    body: []const u8,
    browser_ms_used: ?[]const u8 = null,
    retry_after: ?[]const u8 = null,
    cf_ray: ?[]const u8 = null,
};

const TestServer = struct {
    const State = struct {
        io: Io,
        listener: std.Io.net.Server,
        port: u16,
        response: TestResponse,
        failed: bool = false,
        method: ?std.http.Method = null,
        target: [2048]u8 = undefined,
        target_len: usize = 0,
        authorization: [512]u8 = undefined,
        authorization_len: usize = 0,
        content_type: [128]u8 = undefined,
        content_type_len: usize = 0,
        body: [32 * 1024]u8 = undefined,
        body_len: usize = 0,
    };

    allocator: Allocator,
    state: *State,
    thread: ?std.Thread,

    fn start(allocator: Allocator, response: TestResponse) !TestServer {
        const io = std.testing.io;
        var selected_port: u16 = 41_000;
        const listener = while (selected_port < 41_200) : (selected_port += 1) {
            const address = try std.Io.net.IpAddress.parse("127.0.0.1", selected_port);
            // The build runs several module test executables concurrently.
            // Exclusive listeners prevent a request from reaching a fixture in
            // another process that happened to select the same port.
            break address.listen(io, .{}) catch |err| switch (err) {
                error.AddressInUse => continue,
                else => return err,
            };
        } else return error.TestPortUnavailable;

        const state = try allocator.create(State);
        errdefer allocator.destroy(state);
        state.* = .{
            .io = io,
            .listener = listener,
            .port = selected_port,
            .response = response,
        };
        errdefer state.listener.deinit(io);
        return .{
            .allocator = allocator,
            .state = state,
            .thread = try std.Thread.spawn(.{}, serveTestRequest, .{state}),
        };
    }

    fn baseUrl(self: *const TestServer, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "http://127.0.0.1:{d}/client/v4", .{self.state.port});
    }

    fn join(self: *TestServer) *const State {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        return self.state;
    }

    fn deinit(self: *TestServer) void {
        // Close before joining so a test that fails before making its request
        // cannot leave the fixture thread blocked forever in accept().
        self.state.listener.deinit(self.state.io);
        _ = self.join();
        self.allocator.destroy(self.state);
        self.* = undefined;
    }
};

fn serveTestRequest(state: *TestServer.State) void {
    serveTestRequestFallible(state) catch {
        state.failed = true;
    };
}

fn serveTestRequestFallible(state: *TestServer.State) !void {
    const stream = try state.listener.accept(state.io);
    defer stream.close(state.io);
    var read_buffer: [16 * 1024]u8 = undefined;
    var write_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(state.io, &read_buffer);
    var stream_writer = stream.writer(state.io, &write_buffer);
    var server = std.http.Server.init(&stream_reader.interface, &stream_writer.interface);
    var request = try server.receiveHead();

    state.method = request.head.method;
    state.target_len = copyCaptured(&state.target, request.head.target);
    var headers = request.iterateHeaders();
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "Authorization")) {
            state.authorization_len = copyCaptured(&state.authorization, header.value);
        } else if (std.ascii.eqlIgnoreCase(header.name, "Content-Type")) {
            state.content_type_len = copyCaptured(&state.content_type, header.value);
        }
    }

    var request_body = std.Io.Writer.fixed(&state.body);
    const body_reader = try request.readerExpectContinue(&.{});
    _ = try body_reader.streamRemaining(&request_body);
    state.body_len = request_body.buffered().len;

    var response_headers: [4]std.http.Header = undefined;
    var response_header_count: usize = 0;
    response_headers[response_header_count] = .{ .name = "Content-Type", .value = state.response.content_type };
    response_header_count += 1;
    if (state.response.browser_ms_used) |value| {
        response_headers[response_header_count] = .{ .name = "X-Browser-Ms-Used", .value = value };
        response_header_count += 1;
    }
    if (state.response.retry_after) |value| {
        response_headers[response_header_count] = .{ .name = "Retry-After", .value = value };
        response_header_count += 1;
    }
    if (state.response.cf_ray) |value| {
        response_headers[response_header_count] = .{ .name = "cf-ray", .value = value };
        response_header_count += 1;
    }
    try request.respond(state.response.body, .{
        .status = state.response.status,
        .keep_alive = false,
        .extra_headers = response_headers[0..response_header_count],
    });
}

fn copyCaptured(destination: []u8, source: []const u8) usize {
    const count = @min(destination.len, source.len);
    @memcpy(destination[0..count], source[0..count]);
    return count;
}

test "content performs an authenticated Kitesurf HTTP exchange" {
    const allocator = std.testing.allocator;
    var server = try TestServer.start(allocator, .{
        .content_type = "application/json; charset=utf-8",
        .body = "{\"success\":true,\"result\":\"<html>rendered</html>\"}",
        .browser_ms_used = "37",
        .cf_ray = "ray-test",
    });
    defer server.deinit();
    var base_buffer: [128]u8 = undefined;
    const base = try server.baseUrl(&base_buffer);
    const client = try Client.init(.{ .token = "api-token" }, base, "acct/one", .kitesurf);

    var result = try client.content(std.testing.io, allocator, .{ .source = .{ .url = "https://example.com" } });
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings("<html>rendered</html>", result.ok.value.html);
    try std.testing.expectEqual(@as(?u64, 37), result.ok.meta.browser_ms_used);
    try std.testing.expectEqualStrings("ray-test", result.ok.meta.cf_ray.?);

    const captured = server.join();
    try std.testing.expect(!captured.failed);
    try std.testing.expectEqual(std.http.Method.POST, captured.method.?);
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct%2Fone/browser-run/content?browser=kitesurf&cacheTTL=0",
        captured.target[0..captured.target_len],
    );
    try std.testing.expectEqualStrings("Bearer api-token", captured.authorization[0..captured.authorization_len]);
    try std.testing.expectEqualStrings("application/json", captured.content_type[0..captured.content_type_len]);
    try std.testing.expectEqualStrings("{\"url\":\"https://example.com\"}", captured.body[0..captured.body_len]);
}

test "screenshot streams binary data and enforces an explicit bound" {
    const allocator = std.testing.allocator;
    const png = "\x89PNG\r\n\x1a\nfixture";
    var server = try TestServer.start(allocator, .{
        .content_type = "image/png",
        .body = png,
        .browser_ms_used = "12",
    });
    defer server.deinit();
    var base_buffer: [128]u8 = undefined;
    const client = try Client.init(.{ .token = "api-token" }, try server.baseUrl(&base_buffer), "acct", .kitesurf);

    var result = try client.screenshotAlloc(std.testing.io, allocator, .{
        .source = .{ .html = "<h1>Hello</h1>" },
        .screenshot = .{ .format = .png, .full_page = true },
    }, 1024);
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings(png, result.ok.value.bytes);
    try std.testing.expectEqualStrings("image/png", result.ok.meta.content_type.?);
    try std.testing.expectEqual(@as(?u64, 12), result.ok.meta.browser_ms_used);

    const captured = server.join();
    try std.testing.expect(!captured.failed);
    try std.testing.expect(std.mem.indexOf(u8, captured.body[0..captured.body_len], "\"encoding\":\"binary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, captured.body[0..captured.body_len], "\"fullPage\":true") != null);

    var limited_server = try TestServer.start(allocator, .{ .content_type = "image/png", .body = png });
    defer limited_server.deinit();
    var limited_base: [128]u8 = undefined;
    const limited_client = try Client.init(.{ .token = "api-token" }, try limited_server.baseUrl(&limited_base), "acct", .kitesurf);
    try std.testing.expectError(error.ApiResponseTooLarge, limited_client.screenshotAlloc(std.testing.io, allocator, .{
        .source = .{ .html = "<h1>Hello</h1>" },
    }, 8));
    try std.testing.expect(!limited_server.join().failed);
}

test "rate limits are returned without an automatic retry" {
    const allocator = std.testing.allocator;
    var server = try TestServer.start(allocator, .{
        .status = .too_many_requests,
        .content_type = "application/json",
        .body = "{\"success\":false,\"errors\":[{\"code\":2001,\"message\":\"Rate limit exceeded\"}]}",
        .retry_after = "9",
        .cf_ray = "rate-ray",
    });
    defer server.deinit();
    var base_buffer: [128]u8 = undefined;
    const client = try Client.init(.{ .token = "api-token" }, try server.baseUrl(&base_buffer), "acct", .kitesurf);

    var result = try client.content(std.testing.io, allocator, .{ .source = .{ .html = "<p>hello</p>" } });
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.too_many_requests, result.api_error.status);
    try std.testing.expectEqual(@as(?u64, 9), result.api_error.meta.retry_after_seconds);
    try std.testing.expectEqualStrings("rate-ray", result.api_error.meta.cf_ray.?);
    try std.testing.expect(std.mem.indexOf(u8, result.api_error.body, "Rate limit exceeded") != null);
    const captured = server.join();
    try std.testing.expect(!captured.failed);
}

test "session and target lifecycle use documented HTTP routes" {
    const allocator = std.testing.allocator;

    var create_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "{\"sessionId\":\"session-1\",\"webSocketDebuggerUrl\":\"wss://secret/session-1\"}",
    });
    defer create_server.deinit();
    var create_base: [128]u8 = undefined;
    const create_client = try Client.init(.{ .token = "api-token" }, try create_server.baseUrl(&create_base), "acct", .kitesurf);
    var created = try create_client.createSession(std.testing.io, allocator, .{ .keep_alive_ms = 60_000 });
    defer created.deinit(allocator);
    try std.testing.expectEqualStrings("session-1", created.ok.value.session_id);
    const create_capture = create_server.join();
    try std.testing.expectEqual(std.http.Method.POST, create_capture.method.?);
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/browser?browser=kitesurf&keep_alive=60000",
        create_capture.target[0..create_capture.target_len],
    );

    var list_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "[{\"sessionId\":\"session-1\",\"startTime\":1}]",
    });
    defer list_server.deinit();
    var list_base: [128]u8 = undefined;
    const list_client = try Client.init(.{ .token = "api-token" }, try list_server.baseUrl(&list_base), "acct", .kitesurf);
    var sessions = try list_client.listSessions(std.testing.io, allocator, .{ .limit = 10, .offset = 20 });
    defer sessions.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), sessions.ok.value.items.len);
    const list_capture = list_server.join();
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/session?browser=kitesurf&limit=10&offset=20",
        list_capture.target[0..list_capture.target_len],
    );

    var get_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "{\"sessionId\":\"session-1\",\"connectionId\":\"connection-1\"}",
    });
    defer get_server.deinit();
    var get_base: [128]u8 = undefined;
    const get_client = try Client.init(.{ .token = "api-token" }, try get_server.baseUrl(&get_base), "acct", .kitesurf);
    var looked_up = try get_client.getSession(std.testing.io, allocator, "session-1");
    defer looked_up.deinit(allocator);
    try std.testing.expectEqualStrings("connection-1", looked_up.ok.value.value.?.connection_id.?);
    const get_capture = get_server.join();
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/session/session-1?browser=kitesurf",
        get_capture.target[0..get_capture.target_len],
    );

    var target_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "{\"id\":\"target-1\",\"type\":\"page\",\"url\":\"https://example.com\"}",
    });
    defer target_server.deinit();
    var target_base: [128]u8 = undefined;
    const target_client = try Client.init(.{ .token = "api-token" }, try target_server.baseUrl(&target_base), "acct", .kitesurf);
    var target = try target_client.newTarget(std.testing.io, allocator, "session/1", "https://example.com", .public_http);
    defer target.deinit(allocator);
    try std.testing.expectEqualStrings("target-1", target.ok.value.id);
    const target_capture = target_server.join();
    try std.testing.expectEqual(std.http.Method.PUT, target_capture.method.?);
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/browser/session%2F1/json/new?browser=kitesurf&url=https%3A%2F%2Fexample.com",
        target_capture.target[0..target_capture.target_len],
    );

    var targets_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "[{\"id\":\"target-1\",\"type\":\"page\",\"url\":\"https://example.com\"}]",
    });
    defer targets_server.deinit();
    var targets_base: [128]u8 = undefined;
    const targets_client = try Client.init(.{ .token = "api-token" }, try targets_server.baseUrl(&targets_base), "acct", .kitesurf);
    var targets = try targets_client.listTargets(std.testing.io, allocator, "session-1");
    defer targets.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), targets.ok.value.items.len);
    const targets_capture = targets_server.join();
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/browser/session-1/json/list?browser=kitesurf",
        targets_capture.target[0..targets_capture.target_len],
    );

    var close_server = try TestServer.start(allocator, .{
        .content_type = "application/json",
        .body = "{\"status\":\"closing\"}",
    });
    defer close_server.deinit();
    var close_base: [128]u8 = undefined;
    const close_client = try Client.init(.{ .token = "api-token" }, try close_server.baseUrl(&close_base), "acct", .kitesurf);
    var closed = try close_client.closeSession(std.testing.io, allocator, "session-1");
    defer closed.deinit(allocator);
    try std.testing.expectEqual(CloseStatus.closing, closed.ok.value);
    const close_capture = close_server.join();
    try std.testing.expectEqual(std.http.Method.DELETE, close_capture.method.?);
    try std.testing.expectEqualStrings(
        "/client/v4/accounts/acct/browser-run/devtools/browser/session-1?browser=kitesurf",
        close_capture.target[0..close_capture.target_len],
    );
}
