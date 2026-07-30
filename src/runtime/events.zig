const std = @import("std");

var refresh_epoch = std.atomic.Value(u64).init(0);

pub fn current() u64 {
    return refresh_epoch.load(.monotonic);
}

pub fn publishRefresh() u64 {
    return refresh_epoch.fetchAdd(1, .monotonic) + 1;
}

test "event source is monotonic" {
    const before = current();
    const after = publishRefresh();
    try std.testing.expect(after > before);
}
