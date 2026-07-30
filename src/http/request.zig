const std = @import("std");

const Allocator = std.mem.Allocator;

pub const default_max_body_bytes = 1024 * 1024;
pub const default_max_header_count = 64;

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []const Header,
    body: []const u8,

    pub fn path(self: Request) []const u8 {
        const index = std.mem.indexOfScalar(u8, self.target, '?') orelse return self.target;
        return self.target[0..index];
    }

    pub fn header(self: Request, name: []const u8) ?[]const u8 {
        for (self.headers) |item| {
            if (std.ascii.eqlIgnoreCase(item.name, name)) return item.value;
        }
        return null;
    }

    pub fn query(self: Request, key: []const u8) ?[]const u8 {
        const query_start = std.mem.indexOfScalar(u8, self.target, '?') orelse return null;
        var items = std.mem.splitScalar(u8, self.target[query_start + 1 ..], '&');
        while (items.next()) |pair| {
            if (pair.len == 0) continue;
            const equals = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
            if (std.mem.eql(u8, pair[0..equals], key)) {
                return if (equals < pair.len) pair[equals + 1 ..] else "";
            }
        }
        return null;
    }
};

pub const Limits = struct {
    max_body_bytes: usize = default_max_body_bytes,
    max_headers: usize = default_max_header_count,
};

pub const ReadError = error{
    BadRequest,
    BodyTooLarge,
    TooManyHeaders,
    ReadFailed,
    StreamTooLong,
} || std.Io.Reader.ReadAllocError;

/// Parses one bounded HTTP/1.x request. Returned slices live in `arena`.
/// A null request means the peer closed the connection before sending a line.
pub fn read(arena: Allocator, reader: *std.Io.Reader, limits: Limits) ReadError!?Request {
    const line = (try reader.takeDelimiter('\n')) orelse return null;
    const parsed = parseRequestLine(line) orelse return error.BadRequest;
    var headers = std.ArrayList(Header).empty;
    defer headers.deinit(arena);
    var content_length: ?usize = null;

    while (true) {
        const header_line = (try reader.takeDelimiter('\n')) orelse return error.BadRequest;
        const trimmed = trimLineEnding(header_line);
        if (trimmed.len == 0) break;
        if (headers.items.len >= limits.max_headers) return error.TooManyHeaders;
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return error.BadRequest;
        const name = std.mem.trim(u8, trimmed[0..colon], " \t");
        const value = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
        if (name.len == 0) return error.BadRequest;
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            content_length = std.fmt.parseInt(usize, value, 10) catch return error.BadRequest;
        }
        try headers.append(arena, .{
            .name = try arena.dupe(u8, name),
            .value = try arena.dupe(u8, value),
        });
    }

    const body = if (content_length) |len| blk: {
        if (len > limits.max_body_bytes) return error.BodyTooLarge;
        break :blk try reader.readAlloc(arena, len);
    } else "";
    return .{
        .method = try arena.dupe(u8, parsed.method),
        .target = try arena.dupe(u8, parsed.target),
        .headers = try arena.dupe(Header, headers.items),
        .body = body,
    };
}

const RequestLine = struct {
    method: []const u8,
    target: []const u8,
};

fn parseRequestLine(line: []const u8) ?RequestLine {
    const trimmed = trimLineEnding(line);
    var items = std.mem.splitScalar(u8, trimmed, ' ');
    const method = items.next() orelse return null;
    const target = items.next() orelse return null;
    const version = items.next() orelse return null;
    if (method.len == 0 or target.len == 0) return null;
    if (!std.mem.startsWith(u8, version, "HTTP/1.")) return null;
    return .{ .method = method, .target = target };
}

fn trimLineEnding(line: []const u8) []const u8 {
    if (line.len != 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

test "bounded request parser retains arbitrary headers body and query" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const raw = "POST /things/42?verbose=true HTTP/1.1\r\nContent-Length: 2\r\nX-Trace: abc\r\n\r\n{}";
    var reader = std.Io.Reader.fixed(raw);
    const request = (try read(arena_state.allocator(), &reader, .{})).?;
    try std.testing.expectEqualStrings("POST", request.method);
    try std.testing.expectEqualStrings("/things/42", request.path());
    try std.testing.expectEqualStrings("true", request.query("verbose").?);
    try std.testing.expectEqualStrings("abc", request.header("x-trace").?);
    try std.testing.expectEqualStrings("{}", request.body);
}

test "request parser rejects invalid and oversized requests" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var invalid = std.Io.Reader.fixed("GET / HTTP/2\r\n\r\n");
    try std.testing.expectError(error.BadRequest, read(arena_state.allocator(), &invalid, .{}));
    var large = std.Io.Reader.fixed("POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\n");
    try std.testing.expectError(error.BodyTooLarge, read(arena_state.allocator(), &large, .{ .max_body_bytes = 3 }));
}
