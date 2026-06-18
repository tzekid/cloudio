const std = @import("std");
const cli_render = @import("cli_render");

pub const ValueArg = union(enum) {
    no_match,
    matched: []const u8,
    missing_value: []const u8,
};

pub fn matches(arg: []const u8, comptime names: anytype) bool {
    inline for (names) |name| {
        if (std.mem.eql(u8, arg, name)) return true;
    }
    return false;
}

pub fn parseValueArg(args: []const []const u8, index: *usize, comptime names: anytype) ValueArg {
    const arg = args[index.*];
    inline for (names) |name| {
        if (std.mem.eql(u8, arg, name)) {
            index.* += 1;
            if (index.* >= args.len) return .{ .missing_value = arg };
            return .{ .matched = args[index.*] };
        }
        if (std.mem.startsWith(u8, arg, name) and arg.len > name.len and arg[name.len] == '=') {
            return .{ .matched = arg[name.len + 1 ..] };
        }
    }
    return .no_match;
}

pub fn parseRequiredValueArg(args: []const []const u8, index: *usize, comptime names: anytype, missing_error: anyerror) !?[]const u8 {
    return switch (parseValueArg(args, index, names)) {
        .no_match => null,
        .matched => |value| value,
        .missing_value => missing_error,
    };
}

pub fn parseSignedI64(value: []const u8, invalid_error: anyerror) !i64 {
    return std.fmt.parseInt(i64, value, 10) catch invalid_error;
}

pub fn parseUnsignedUsize(value: []const u8, invalid_error: anyerror) !usize {
    return std.fmt.parseUnsigned(usize, value, 10) catch invalid_error;
}

pub fn parsePositiveI64(value: []const u8, invalid_error: anyerror) !i64 {
    const parsed = try parseSignedI64(value, invalid_error);
    if (parsed < 1) return invalid_error;
    return parsed;
}

pub fn parsePositiveUsize(value: []const u8, invalid_error: anyerror) !usize {
    const parsed = try parseUnsignedUsize(value, invalid_error);
    if (parsed == 0) return invalid_error;
    return parsed;
}

pub fn parsePositiveI64Arg(args: []const []const u8, index: *usize, comptime names: anytype, missing_error: anyerror, invalid_error: anyerror) !?i64 {
    if (try parseRequiredValueArg(args, index, names, missing_error)) |value| {
        return try parsePositiveI64(value, invalid_error);
    }
    return null;
}

pub fn parsePositiveUsizeArg(args: []const []const u8, index: *usize, comptime names: anytype, missing_error: anyerror, invalid_error: anyerror) !?usize {
    if (try parseRequiredValueArg(args, index, names, missing_error)) |value| {
        return try parsePositiveUsize(value, invalid_error);
    }
    return null;
}

pub fn parseFormatOption(args: []const []const u8, index: *usize, format: *cli_render.RenderFormat, missing_error: anyerror, invalid_error: anyerror) !bool {
    switch (cli_render.parseFormatArg(args, index)) {
        .matched => |parsed| {
            format.* = parsed;
            return true;
        },
        .missing_value => return missing_error,
        .invalid_value => return invalid_error,
        .no_match => return false,
    }
}

pub fn parseFormatOnly(args: []const []const u8, unexpected_error: anyerror) !cli_render.RenderFormat {
    var format: cli_render.RenderFormat = .text;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try parseFormatOption(args, &index, &format, error.MissingFormat, error.InvalidFormat)) continue;
        return unexpected_error;
    }
    return format;
}

pub const FormatLimitOptions = struct {
    format: cli_render.RenderFormat = .text,
    limit: i64,
};

pub fn parseFormatPositiveLimit(
    args: []const []const u8,
    default_limit: i64,
    comptime limit_names: anytype,
    missing_limit_error: anyerror,
    invalid_limit_error: anyerror,
    unexpected_error: anyerror,
) !FormatLimitOptions {
    var parsed: FormatLimitOptions = .{ .limit = default_limit };
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try parsePositiveI64Arg(args, &index, limit_names, missing_limit_error, invalid_limit_error)) |limit| {
            parsed.limit = limit;
            continue;
        }
        return unexpected_error;
    }
    return parsed;
}

test "matches recognizes exact aliases only" {
    try std.testing.expect(matches("--limit", .{"--limit"}));
    try std.testing.expect(matches("--path-template", .{ "--path", "--path-template" }));
    try std.testing.expect(!matches("--limit=3", .{"--limit"}));
    try std.testing.expect(!matches("--limiter", .{"--limit"}));
}

test "value argument parser handles split inline aliases and missing values" {
    var index: usize = 0;
    const split_args = [_][]const u8{ "--limit", "25" };
    try std.testing.expectEqualStrings("25", parseValueArg(split_args[0..], &index, .{"--limit"}).matched);
    try std.testing.expectEqual(@as(usize, 1), index);

    index = 0;
    const inline_args = [_][]const u8{"--path-template=/accounts"};
    try std.testing.expectEqualStrings("/accounts", parseValueArg(inline_args[0..], &index, .{ "--path", "--path-template" }).matched);
    try std.testing.expectEqual(@as(usize, 0), index);

    index = 0;
    const missing_args = [_][]const u8{"--support"};
    switch (parseValueArg(missing_args[0..], &index, .{"--support"})) {
        .missing_value => |name| try std.testing.expectEqualStrings("--support", name),
        else => return error.ExpectedMissingValue,
    }

    index = 0;
    const other_args = [_][]const u8{"hostinger"};
    try std.testing.expectEqual(ValueArg.no_match, parseValueArg(other_args[0..], &index, .{"--provider"}));
    try std.testing.expectEqual(@as(usize, 0), index);
}

test "required value and numeric parsers share command option behavior" {
    var index: usize = 0;
    const missing_args = [_][]const u8{"--limit"};
    try std.testing.expectError(error.MissingLimit, parseRequiredValueArg(missing_args[0..], &index, .{"--limit"}, error.MissingLimit));

    index = 0;
    const inline_args = [_][]const u8{"--limit=25"};
    try std.testing.expectEqual(@as(i64, 25), (try parsePositiveI64Arg(inline_args[0..], &index, .{"--limit"}, error.MissingLimit, error.InvalidLimit)).?);
    try std.testing.expectEqual(@as(usize, 0), index);

    index = 0;
    const split_args = [_][]const u8{ "--max-pages", "3" };
    try std.testing.expectEqual(@as(usize, 3), (try parsePositiveUsizeArg(split_args[0..], &index, .{"--max-pages"}, error.MissingMaxPages, error.InvalidMaxPages)).?);
    try std.testing.expectEqual(@as(usize, 1), index);

    try std.testing.expectError(error.InvalidLimit, parsePositiveI64("0", error.InvalidLimit));
    try std.testing.expectError(error.InvalidLimit, parsePositiveI64("-1", error.InvalidLimit));
    try std.testing.expectError(error.InvalidMaxPages, parsePositiveUsize("0", error.InvalidMaxPages));
    try std.testing.expectEqual(@as(usize, 0), try parseUnsignedUsize("0", error.InvalidUnsigned));
}

test "format helpers share common command output parsing" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(cli_render.RenderFormat.text, try parseFormatOnly(no_args[0..], error.Unexpected));

    const json_args = [_][]const u8{"--json"};
    try std.testing.expectEqual(cli_render.RenderFormat.json, try parseFormatOnly(json_args[0..], error.Unexpected));

    const inline_args = [_][]const u8{"--format=text"};
    try std.testing.expectEqual(cli_render.RenderFormat.text, try parseFormatOnly(inline_args[0..], error.Unexpected));

    const missing_format = [_][]const u8{"--format"};
    try std.testing.expectError(error.MissingFormat, parseFormatOnly(missing_format[0..], error.Unexpected));

    const invalid_format = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(error.InvalidFormat, parseFormatOnly(invalid_format[0..], error.Unexpected));

    const unexpected = [_][]const u8{"extra"};
    try std.testing.expectError(error.Unexpected, parseFormatOnly(unexpected[0..], error.Unexpected));
}

test "format and positive limit helper preserves split inline behavior" {
    const default_args = [_][]const u8{};
    const defaults = try parseFormatPositiveLimit(default_args[0..], 20, .{"--limit"}, error.MissingLimit, error.InvalidLimit, error.Unexpected);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);
    try std.testing.expectEqual(@as(i64, 20), defaults.limit);

    const args = [_][]const u8{ "--json", "--limit=5" };
    const parsed = try parseFormatPositiveLimit(args[0..], 20, .{"--limit"}, error.MissingLimit, error.InvalidLimit, error.Unexpected);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqual(@as(i64, 5), parsed.limit);

    const split_args = [_][]const u8{ "--format", "json", "--limit", "3" };
    const split = try parseFormatPositiveLimit(split_args[0..], 20, .{"--limit"}, error.MissingLimit, error.InvalidLimit, error.Unexpected);
    try std.testing.expectEqual(cli_render.RenderFormat.json, split.format);
    try std.testing.expectEqual(@as(i64, 3), split.limit);

    const missing_limit = [_][]const u8{"--limit"};
    try std.testing.expectError(error.MissingLimit, parseFormatPositiveLimit(missing_limit[0..], 20, .{"--limit"}, error.MissingLimit, error.InvalidLimit, error.Unexpected));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidLimit, parseFormatPositiveLimit(invalid_limit[0..], 20, .{"--limit"}, error.MissingLimit, error.InvalidLimit, error.Unexpected));
}
