const std = @import("std");

pub fn currentEpochSeconds() !u64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (std.os.linux.errno(rc) != .SUCCESS) return error.ClockGettimeFailed;
    if (ts.sec < 0) return error.ClockGettimeFailed;
    return @intCast(ts.sec);
}

pub fn formatUtcMinute(buf: *[17]u8, seconds: u64) ![]const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
    });
}

pub fn formatUtcSecond(buf: *[20]u8, seconds: u64) ![]const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

test "utc minute formatter emits hostinger datetime shape" {
    var buf: [17]u8 = undefined;
    const formatted = try formatUtcMinute(&buf, 1781655600);
    try std.testing.expectEqualStrings("2026-06-17T00:20Z", formatted);
}

test "utc second formatter emits rfc3339 utc shape" {
    var buf: [20]u8 = undefined;
    const formatted = try formatUtcSecond(&buf, 1781655600);
    try std.testing.expectEqualStrings("2026-06-17T00:20:00Z", formatted);
}
