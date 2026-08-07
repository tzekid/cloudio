//! Minimal bounded decoder for native HTML form posts.

const std = @import("std");
const http = @import("http");

pub const max_body_bytes: usize = 80 * 1024;
pub const max_fields: usize = 80;

pub const Error = error{
    BodyTooLarge,
    TooManyFields,
    MalformedEncoding,
    DuplicateField,
    MissingField,
};

pub const Entry = struct {
    name: []const u8,
    value: []const u8,
};

pub const Form = struct {
    entries: []const Entry,

    pub fn get(self: Form, name: []const u8) Error![]const u8 {
        var found: ?[]const u8 = null;
        for (self.entries) |entry| {
            if (!std.mem.eql(u8, entry.name, name)) continue;
            if (found != null) return error.DuplicateField;
            found = entry.value;
        }
        return found orelse error.MissingField;
    }
};

pub fn hasUrlEncodedBody(request: http.Request) bool {
    const content_type = request.header("content-type") orelse return false;
    const expected = "application/x-www-form-urlencoded";
    if (!std.ascii.startsWithIgnoreCase(content_type, expected)) return false;
    if (content_type.len == expected.len) return true;
    return content_type[expected.len] == ';' or content_type[expected.len] == ' ' or
        content_type[expected.len] == '\t';
}

pub fn parse(arena: std.mem.Allocator, body: []const u8) (Error || std.mem.Allocator.Error)!Form {
    if (body.len > max_body_bytes) return error.BodyTooLarge;
    var entries = std.ArrayList(Entry).empty;
    defer entries.deinit(arena);

    var fields = std.mem.splitScalar(u8, body, '&');
    while (fields.next()) |field| {
        if (field.len == 0) continue;
        if (entries.items.len >= max_fields) return error.TooManyFields;
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse field.len;
        try entries.append(arena, .{
            .name = try decode(arena, field[0..equals]),
            .value = try decode(arena, if (equals < field.len) field[equals + 1 ..] else ""),
        });
    }
    return .{ .entries = try arena.dupe(Entry, entries.items) };
}

fn decode(arena: std.mem.Allocator, encoded: []const u8) (Error || std.mem.Allocator.Error)![]const u8 {
    const decoded = try arena.alloc(u8, encoded.len);
    var read_index: usize = 0;
    var write_index: usize = 0;
    while (read_index < encoded.len) : (read_index += 1) {
        switch (encoded[read_index]) {
            '+' => decoded[write_index] = ' ',
            '%' => {
                if (read_index + 2 >= encoded.len) return error.MalformedEncoding;
                const high = std.fmt.charToDigit(encoded[read_index + 1], 16) catch
                    return error.MalformedEncoding;
                const low = std.fmt.charToDigit(encoded[read_index + 2], 16) catch
                    return error.MalformedEncoding;
                decoded[write_index] = @as(u8, high) * 16 + @as(u8, low);
                read_index += 2;
            },
            else => |byte| decoded[write_index] = byte,
        }
        write_index += 1;
    }
    return decoded[0..write_index];
}

test "form decoder handles browser encoding and unique lookup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const form = try parse(arena.allocator(), "theme=system&csrf_token=a%2Bb+c");
    try std.testing.expectEqualStrings("system", try form.get("theme"));
    try std.testing.expectEqualStrings("a+b c", try form.get("csrf_token"));
}

test "form decoder rejects malformed duplicate and oversized input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.MalformedEncoding, parse(arena.allocator(), "theme=%Q0"));
    const duplicate = try parse(arena.allocator(), "theme=dark&theme=light");
    try std.testing.expectError(error.DuplicateField, duplicate.get("theme"));
    var oversized: [max_body_bytes + 1]u8 = @splat('x');
    try std.testing.expectError(error.BodyTooLarge, parse(arena.allocator(), &oversized));
}

test "form content type is explicit" {
    const accepted: http.Request = .{
        .method = "POST",
        .target = "/settings/theme",
        .headers = &.{.{
            .name = "Content-Type",
            .value = "application/x-www-form-urlencoded; charset=UTF-8",
        }},
        .body = "theme=light",
    };
    try std.testing.expect(hasUrlEncodedBody(accepted));
    var rejected = accepted;
    rejected.headers = &.{.{ .name = "Content-Type", .value = "application/json" }};
    try std.testing.expect(!hasUrlEncodedBody(rejected));
}
