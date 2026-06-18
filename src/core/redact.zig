const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn secrets(allocator: Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const inline_redacted = try redactInlineVerificationValues(allocator, line);
        defer allocator.free(inline_redacted);
        if (shouldRedactLine(inline_redacted)) {
            if (std.mem.indexOfScalar(u8, inline_redacted, '=')) |idx| {
                try out.appendSlice(allocator, inline_redacted[0 .. idx + 1]);
                try out.appendSlice(allocator, "[REDACTED]");
            } else if (std.mem.indexOf(u8, inline_redacted, "header_up")) |idx| {
                try out.appendSlice(allocator, inline_redacted[0..idx]);
                try out.appendSlice(allocator, "header_up [REDACTED]");
            } else if (std.mem.indexOfScalar(u8, inline_redacted, ':')) |idx| {
                try out.appendSlice(allocator, inline_redacted[0 .. idx + 1]);
                try out.appendSlice(allocator, " [REDACTED]");
            } else {
                try out.appendSlice(allocator, "[REDACTED secret-like line]");
            }
        } else {
            try out.appendSlice(allocator, inline_redacted);
        }
        try out.append(allocator, '\n');
    }
    const line_redacted = try out.toOwnedSlice(allocator);
    defer allocator.free(line_redacted);
    return try redactJsonSecretStringKeys(allocator, line_redacted);
}

pub fn tokenResponse(allocator: Allocator, input: []const u8) ![]u8 {
    const redacted = try providerResponse(allocator, input);
    defer allocator.free(redacted);
    return try redactJsonStringKey(allocator, redacted, "value");
}

pub fn secretResponse(allocator: Allocator, input: []const u8) ![]u8 {
    const value_redacted = try tokenResponse(allocator, input);
    defer allocator.free(value_redacted);
    return try redactJsonStringKey(allocator, value_redacted, "text");
}

pub fn providerResponse(allocator: Allocator, input: []const u8) ![]u8 {
    const redacted = try secrets(allocator, input);
    if (try redactJsonCursorContinuations(allocator, redacted)) |rewritten| {
        allocator.free(redacted);
        return rewritten;
    }
    return redacted;
}

fn redactJsonStringKey(allocator: Allocator, input: []const u8, key: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var idx: usize = 0;
    while (idx < input.len) {
        if (input[idx] == '"') {
            if (jsonKeyEnd(input, idx, key)) |key_end| {
                var scan = key_end;
                while (scan < input.len and std.ascii.isWhitespace(input[scan])) : (scan += 1) {}
                if (scan < input.len and input[scan] == ':') {
                    scan += 1;
                    while (scan < input.len and std.ascii.isWhitespace(input[scan])) : (scan += 1) {}
                    if (scan < input.len and input[scan] == '"') {
                        if (jsonStringEnd(input, scan)) |value_end| {
                            try out.appendSlice(allocator, input[idx .. scan + 1]);
                            try out.appendSlice(allocator, "[REDACTED]");
                            try out.append(allocator, '"');
                            idx = value_end;
                            continue;
                        }
                    }
                }
            }
        }
        try out.append(allocator, input[idx]);
        idx += 1;
    }
    return try out.toOwnedSlice(allocator);
}

fn redactJsonSecretStringKeys(allocator: Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var idx: usize = 0;
    while (idx < input.len) {
        if (input[idx] == '"') {
            if (jsonSimpleKey(input, idx)) |key_info| {
                var scan = key_info.end;
                while (scan < input.len and std.ascii.isWhitespace(input[scan])) : (scan += 1) {}
                if (scan < input.len and input[scan] == ':' and isSecretJsonKey(key_info.key)) {
                    scan += 1;
                    while (scan < input.len and std.ascii.isWhitespace(input[scan])) : (scan += 1) {}
                    if (scan < input.len and input[scan] == '"') {
                        if (jsonStringEnd(input, scan)) |value_end| {
                            try out.appendSlice(allocator, input[idx .. scan + 1]);
                            try out.appendSlice(allocator, "[REDACTED]");
                            try out.append(allocator, '"');
                            idx = value_end;
                            continue;
                        }
                    }
                }
            }
        }
        try out.append(allocator, input[idx]);
        idx += 1;
    }
    return try out.toOwnedSlice(allocator);
}

const CursorContext = enum {
    normal,
    result_info,
    cursor_root,
    cursors,
};

fn redactJsonCursorContinuations(allocator: Allocator, input: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return null;
    defer parsed.deinit();
    redactCursorContinuations(&parsed.value, .normal);
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

fn redactCursorContinuations(value: *std.json.Value, context: CursorContext) void {
    switch (value.*) {
        .array => |*array| {
            for (array.items) |*item| redactCursorContinuations(item, .normal);
        },
        .object => |*object| {
            const object_context: CursorContext = if (context == .normal and objectHasRootCursorShape(object.*)) .cursor_root else context;
            var it = object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (shouldRedactCursorField(object_context, key)) {
                    entry.value_ptr.* = .{ .string = "[REDACTED]" };
                    continue;
                }
                const child_context: CursorContext = if (std.ascii.eqlIgnoreCase(key, "result_info"))
                    .result_info
                else if (object_context == .result_info and std.ascii.eqlIgnoreCase(key, "cursors"))
                    .cursors
                else
                    .normal;
                redactCursorContinuations(entry.value_ptr, child_context);
            }
        },
        else => {},
    }
}

fn objectHasRootCursorShape(object: std.json.ObjectMap) bool {
    if (object.get("cursor") == null) return false;
    return object.get("list_complete") != null or
        object.get("is_truncated") != null or
        object.get("keys") != null or
        object.get("items") != null or
        object.get("objects") != null or
        object.get("vectors") != null or
        object.get("data") != null;
}

fn shouldRedactCursorField(context: CursorContext, key: []const u8) bool {
    return switch (context) {
        .result_info => std.ascii.eqlIgnoreCase(key, "cursor") or
            std.ascii.eqlIgnoreCase(key, "next") or
            std.ascii.eqlIgnoreCase(key, "previous"),
        .cursor_root => std.ascii.eqlIgnoreCase(key, "cursor"),
        .cursors => true,
        .normal => false,
    };
}

const JsonKey = struct {
    key: []const u8,
    end: usize,
};

fn jsonSimpleKey(input: []const u8, start: usize) ?JsonKey {
    if (start >= input.len or input[start] != '"') return null;
    var idx = start + 1;
    while (idx < input.len) : (idx += 1) {
        if (input[idx] == '\\') return null;
        if (input[idx] == '"') return .{
            .key = input[start + 1 .. idx],
            .end = idx + 1,
        };
    }
    return null;
}

fn jsonKeyEnd(input: []const u8, start: usize, key: []const u8) ?usize {
    var idx = start + 1;
    var key_idx: usize = 0;
    while (idx < input.len) : (idx += 1) {
        const ch = input[idx];
        if (ch == '\\') return null;
        if (ch == '"') {
            if (key_idx == key.len) return idx + 1;
            return null;
        }
        if (key_idx >= key.len or ch != key[key_idx]) return null;
        key_idx += 1;
    }
    return null;
}

fn jsonStringEnd(input: []const u8, start: usize) ?usize {
    var idx = start + 1;
    while (idx < input.len) : (idx += 1) {
        if (input[idx] == '\\') {
            idx += 1;
            continue;
        }
        if (input[idx] == '"') return idx + 1;
    }
    return null;
}

fn redactInlineVerificationValues(allocator: Allocator, input: []const u8) ![]u8 {
    const markers = [_][]const u8{
        "openai-domain-verification=",
        "google-site-verification=",
        "facebook-domain-verification=",
        "slack-domain-verification=",
        "stripe-verification=",
        "apple-domain-verification=",
        "atlassian-domain-verification=",
    };
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var idx: usize = 0;
    while (idx < input.len) {
        if (matchingMarker(input[idx..], &markers)) |marker| {
            try out.appendSlice(allocator, marker);
            try out.appendSlice(allocator, "[REDACTED]");
            idx += marker.len;
            while (idx < input.len and !isInlineSecretTerminator(input[idx])) : (idx += 1) {}
            continue;
        }
        try out.append(allocator, input[idx]);
        idx += 1;
    }
    return try out.toOwnedSlice(allocator);
}

fn matchingMarker(input: []const u8, markers: []const []const u8) ?[]const u8 {
    for (markers) |marker| {
        if (input.len >= marker.len and std.ascii.eqlIgnoreCase(input[0..marker.len], marker)) return marker;
    }
    return null;
}

fn isInlineSecretTerminator(ch: u8) bool {
    return switch (ch) {
        '\\', '"', '\'', ' ', '\t', '\r', '\n', ',', ';', '&', '<', '>', '}', ']' => true,
        else => false,
    };
}

fn shouldRedactLine(line: []const u8) bool {
    if (std.mem.indexOfScalar(u8, line, '=')) |idx| {
        return containsSecretWord(line[0..idx]);
    }
    if (indexOfIgnoreCase(line, "header_up") != null and containsSecretWord(line)) return true;
    if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
        const header_name = trim(line[0..idx]);
        if (isLikelyHeaderName(header_name) and containsSecretWord(header_name)) return true;
    }
    return false;
}

fn isLikelyHeaderName(value: []const u8) bool {
    if (value.len == 0 or value.len > 80) return false;
    for (value) |ch| {
        const ok = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_';
        if (!ok) return false;
    }
    return true;
}

fn containsSecretWord(line: []const u8) bool {
    const words = [_][]const u8{
        "token",
        "secret",
        "password",
        "api_key",
        "apikey",
        "x-api-key",
        "authorization",
        "bearer",
        "private_key",
        "privatekey",
        "privkey",
        "client_secret",
        "refresh_token",
        "access_token",
        "stream_key",
        "streamkey",
        "ingest_key",
        "ingestkey",
    };
    for (words) |word| {
        if (indexOfIgnoreCase(line, word) != null) return true;
    }
    return false;
}

fn isSecretJsonKey(key: []const u8) bool {
    if (containsSecretWord(key)) return true;
    return std.ascii.eqlIgnoreCase(key, "kek");
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
    }
    return null;
}

test "redaction hides secret-like values" {
    const allocator = std.testing.allocator;
    const redacted = try secrets(allocator, "CLOUDFLARE_API_KEY=abc123\nnormal=value\nAuthorization: Bearer abc\nhostinger/vps\t[skipped]\tmissing Hostinger API token\t2026-06-17 00:11:38\n");
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "abc123") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "Bearer abc") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "normal=value") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "missing Hostinger API token") != null);
}

test "redaction hides DNS verification TXT values inside JSON" {
    const allocator = std.testing.allocator;
    const input =
        \\{"result":[{"type":"TXT","content":"\"openai-domain-verification=dv-example1234567890\""},{"type":"TXT","content":"\"google-site-verification=google-example1234567890\""},{"type":"TXT","content":"\"v=spf1 include:spf.messagingengine.com ?all\""}],"success":true}
    ;
    const redacted = try secrets(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "dv-example1234567890") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "google-example1234567890") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "openai-domain-verification=[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "google-site-verification=[REDACTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "v=spf1 include:spf.messagingengine.com ?all") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"success\":true") != null);
}

test "redaction hides JSON private key material without hiding DNSSEC public keys" {
    const allocator = std.testing.allocator;
    const input =
        \\{"result":[{"SigningKey":{"pubkey":"public-zsk","privkey":"private-zsk","kek":"core-kek"},"DNSKEY":{"PublicKey":"dns-public-key"}}],"success":true}
    ;
    const redacted = try secrets(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "private-zsk") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "core-kek") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"privkey\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"kek\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"pubkey\":\"public-zsk\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"PublicKey\":\"dns-public-key\"") != null);
}

test "token response redaction hides JSON token value fields" {
    const allocator = std.testing.allocator;
    const input =
        \\{"result":{"id":"abc","value":"abcdefghijklmnopqrstuvwxyz0123456789abcd","name":"token"},"success":true}
    ;
    const redacted = try tokenResponse(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "abcdefghijklmnopqrstuvwxyz0123456789abcd") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"value\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"name\":\"token\"") != null);
}

test "secret response redaction hides JSON secret text and value fields" {
    const allocator = std.testing.allocator;
    const input =
        \\{"result":{"name":"myBinding","type":"secret_text","text":"plain-secret","value":"secret-value"},"success":true}
    ;
    const redacted = try secretResponse(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "plain-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "secret-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"text\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"value\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"name\":\"myBinding\"") != null);
}

test "provider response redaction hides realtime stream keys without hiding public keys" {
    const allocator = std.testing.allocator;
    const input =
        \\{"data":{"stream_key":"rtmp-secret-key","ingestKey":"ingest-secret-key","playback_url":"https://example.com/live.m3u8","public_key":"public-material"},"success":true}
    ;
    const redacted = try providerResponse(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "rtmp-secret-key") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "ingest-secret-key") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"stream_key\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"ingestKey\":\"[REDACTED]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "\"public_key\":\"public-material\"") != null);
}

test "provider response redaction hides cursor continuations without hiding unrelated after fields" {
    const allocator = std.testing.allocator;
    const input =
        \\{"after":"2026-06-17T00:00:00Z","result":[],"result_info":{"cursor":"root-token","next":"next-token","cursors":{"after":"after-token","before":"before-token"}},"keys":[],"list_complete":false,"cursor":"root-page-token"}
    ;
    const redacted = try providerResponse(allocator, input);
    defer allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "root-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "next-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "after-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "before-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "root-page-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "2026-06-17T00:00:00Z") != null);
}
