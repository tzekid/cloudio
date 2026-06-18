const std = @import("std");

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
