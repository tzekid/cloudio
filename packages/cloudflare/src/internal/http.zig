const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_body_bytes = 12 * 1024 * 1024;

pub const Response = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: Response, allocator: Allocator) void {
        allocator.free(self.body);
    }
};

pub const ResponseMeta = struct {
    content_type: ?[]u8 = null,
    content_length: ?u64 = null,
    browser_ms_used: ?u64 = null,
    retry_after_seconds: ?u64 = null,
    cf_ray: ?[]u8 = null,

    pub fn deinit(self: ResponseMeta, allocator: Allocator) void {
        if (self.content_type) |value| allocator.free(value);
        if (self.cf_ray) |value| allocator.free(value);
    }
};

pub const Body = union(enum) {
    bytes: []u8,
    streamed: usize,
};

pub const DetailedResponse = struct {
    status: std.http.Status,
    meta: ResponseMeta,
    body: Body,

    pub fn deinit(self: DetailedResponse, allocator: Allocator) void {
        self.meta.deinit(allocator);
        switch (self.body) {
            .bytes => |bytes| allocator.free(bytes),
            .streamed => {},
        }
    }
};

pub const StreamSuccess = struct {
    writer: *std.Io.Writer,
    max_bytes: usize,
    accepted_content_types: []const []const u8,
    fallback_max_bytes: usize = max_body_bytes,
};

pub const BodyMode = union(enum) {
    buffer: usize,
    stream_success: StreamSuccess,
};

pub fn get(gpa: Allocator, io: Io, url: []const u8, extra: []const std.http.Header, privileged: []const std.http.Header) !Response {
    return try request(gpa, io, .GET, url, null, extra, privileged);
}

pub fn request(gpa: Allocator, io: Io, method: std.http.Method, url: []const u8, body: ?[]const u8, extra: []const std.http.Header, privileged: []const std.http.Header) !Response {
    const detailed = try requestDetailed(gpa, io, method, url, body, extra, privileged, .{ .buffer = max_body_bytes });
    defer detailed.meta.deinit(gpa);
    return .{
        .status = detailed.status,
        .body = switch (detailed.body) {
            .bytes => |bytes| bytes,
            .streamed => unreachable,
        },
    };
}

pub fn requestDetailed(
    gpa: Allocator,
    io: Io,
    method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
    extra: []const std.http.Header,
    privileged: []const std.http.Header,
    body_mode: BodyMode,
) !DetailedResponse {
    var client = std.http.Client{ .allocator = gpa, .io = io };
    defer client.deinit();
    const uri = try std.Uri.parse(url);
    // std.http.Client refuses request bodies on methods other than POST/PUT/PATCH,
    // but Hostinger's DNS delete endpoint takes a DELETE body. For that case we
    // emit Content-Length ourselves and write the payload straight to the connection.
    const manual_body = body != null and !method.requestHasBody();
    var content_length_buf: [24]u8 = undefined;
    const sensitive_headers = privileged.len != 0 or containsSensitiveHeader(extra);
    var wire_headers: []std.http.Header = &.{};
    defer if (wire_headers.len != 0) gpa.free(wire_headers);
    if (manual_body or privileged.len != 0) {
        wire_headers = try gpa.alloc(std.http.Header, extra.len + privileged.len + @intFromBool(manual_body));
        @memcpy(wire_headers[0..extra.len], extra);
        @memcpy(wire_headers[extra.len .. extra.len + privileged.len], privileged);
    }
    if (manual_body) {
        const cl = try std.fmt.bufPrint(&content_length_buf, "{d}", .{body.?.len});
        wire_headers[extra.len + privileged.len] = .{ .name = "Content-Length", .value = cl };
    }
    var req = try client.request(method, uri, .{
        // Zig's current std.http client tracks privileged headers for redirect
        // stripping but does not emit them. Send them with the initial request
        // and disable redirects whenever credentials are present so secrets can
        // never be forwarded to another origin.
        .redirect_behavior = if (manual_body or sensitive_headers) .unhandled else @fromBackingInt(@intCast(3)),
        .headers = .{ .user_agent = .{ .override = "cloudflare-zig/0.1" } },
        .extra_headers = if (wire_headers.len != 0) wire_headers else extra,
        .privileged_headers = &.{},
    });
    defer req.deinit();
    if (manual_body) {
        try req.sendBodiless();
        const conn_writer = req.connection.?.writer();
        try conn_writer.writeAll(body.?);
        try req.connection.?.flush();
    } else if (body) |payload| {
        req.transfer_encoding = .{ .content_length = payload.len };
        var body_writer = try req.sendBodyUnflushed(&.{});
        try body_writer.writer.writeAll(payload);
        try body_writer.end();
        try req.connection.?.flush();
    } else if (method.requestHasBody()) {
        req.transfer_encoding = .{ .content_length = 0 };
        var body_writer = try req.sendBodyUnflushed(&.{});
        try body_writer.end();
        try req.connection.?.flush();
    } else {
        try req.sendBodiless();
    }
    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    const status = response.head.status;
    var meta = try cloneMeta(gpa, response.head);
    errdefer meta.deinit(gpa);

    const selected_mode: BodyMode = switch (body_mode) {
        .buffer => body_mode,
        .stream_success => |stream| if (isOk(status) and contentTypeAccepted(meta.content_type, stream.accepted_content_types))
            body_mode
        else
            .{ .buffer = stream.fallback_max_bytes },
    };
    const max_bytes = switch (selected_mode) {
        .buffer => |limit| limit,
        .stream_success => |stream| stream.max_bytes,
    };
    if (meta.content_length) |declared| {
        if (declared > max_bytes) return error.ApiResponseTooLarge;
    }

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try gpa.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try gpa.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer.len != 0) gpa.free(decompress_buffer);
    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const destination = switch (selected_mode) {
        .buffer => &out.writer,
        .stream_success => |stream| stream.writer,
    };
    const received = copyBounded(reader, destination, max_bytes) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };

    const response_body: Body = switch (selected_mode) {
        .buffer => .{ .bytes = try out.toOwnedSlice() },
        .stream_success => .{ .streamed = received },
    };
    return .{ .status = status, .meta = meta, .body = response_body };
}

fn containsSensitiveHeader(headers: []const std.http.Header) bool {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "Authorization") or
            std.ascii.eqlIgnoreCase(header.name, "Cookie") or
            std.ascii.eqlIgnoreCase(header.name, "X-Auth-Key") or
            std.ascii.eqlIgnoreCase(header.name, "X-Auth-Email")) return true;
    }
    return false;
}

fn copyBounded(reader: *std.Io.Reader, writer: *std.Io.Writer, max_bytes_allowed: usize) !usize {
    var total: usize = 0;
    var buffer: [16 * 1024]u8 = undefined;
    while (true) {
        const read = try reader.readSliceShort(&buffer);
        if (read == 0) return total;
        if (read > max_bytes_allowed - total) return error.ApiResponseTooLarge;
        try writer.writeAll(buffer[0..read]);
        total += read;
    }
}

fn cloneMeta(gpa: Allocator, head: std.http.Client.Response.Head) !ResponseMeta {
    var meta: ResponseMeta = .{
        .content_length = head.content_length,
        .content_type = if (head.content_type) |value| try gpa.dupe(u8, value) else null,
    };
    errdefer meta.deinit(gpa);

    var headers = head.iterateHeaders();
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "X-Browser-Ms-Used")) {
            meta.browser_ms_used = std.fmt.parseInt(u64, header.value, 10) catch null;
        } else if (std.ascii.eqlIgnoreCase(header.name, "Retry-After")) {
            meta.retry_after_seconds = std.fmt.parseInt(u64, header.value, 10) catch null;
        } else if (std.ascii.eqlIgnoreCase(header.name, "cf-ray")) {
            if (meta.cf_ray == null) meta.cf_ray = try gpa.dupe(u8, header.value);
        }
    }
    return meta;
}

fn contentTypeAccepted(content_type: ?[]const u8, accepted: []const []const u8) bool {
    const raw = content_type orelse return false;
    const media_type = std.mem.trim(u8, std.mem.sliceTo(raw, ';'), " \t");
    for (accepted) |candidate| {
        if (std.ascii.eqlIgnoreCase(media_type, candidate)) return true;
    }
    return false;
}

pub fn statusText(status: std.http.Status) []const u8 {
    const code: u16 = @backingInt(status);
    if (code >= 200 and code < 300) return "ok";
    if (code == 401 or code == 403) return "permission";
    if (code == 404) return "not_found";
    return "http_error";
}

pub fn isOk(status: std.http.Status) bool {
    const code: u16 = @backingInt(status);
    return code >= 200 and code < 300;
}

pub fn summary(gpa: Allocator, label: []const u8, status: std.http.Status) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s} HTTP {d}", .{ label, @backingInt(status) });
}

test "status helpers classify api responses" {
    try std.testing.expectEqualStrings("ok", statusText(.ok));
    try std.testing.expectEqualStrings("permission", statusText(.unauthorized));
    try std.testing.expectEqualStrings("permission", statusText(.forbidden));
    try std.testing.expectEqualStrings("not_found", statusText(.not_found));
    try std.testing.expectEqualStrings("http_error", statusText(.unprocessable_entity));
    try std.testing.expect(isOk(.ok));
    try std.testing.expect(!isOk(.bad_request));

    const text = try summary(std.testing.allocator, "metrics", .ok);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("metrics HTTP 200", text);
}

test "sensitive request headers disable redirects" {
    try std.testing.expect(containsSensitiveHeader(&.{.{ .name = "Authorization", .value = "secret" }}));
    try std.testing.expect(containsSensitiveHeader(&.{.{ .name = "x-auth-key", .value = "secret" }}));
    try std.testing.expect(!containsSensitiveHeader(&.{.{ .name = "Accept", .value = "application/json" }}));
}
