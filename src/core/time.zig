const std = @import("std");

pub fn currentEpochSeconds() !u64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (std.os.linux.errno(rc) != .SUCCESS) return error.ClockGettimeFailed;
    if (ts.sec < 0) return error.ClockGettimeFailed;
    return @intCast(ts.sec);
}

