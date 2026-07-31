const std = @import("std");

const max_buckets = 256;

const Bucket = struct {
    key_hash: u64 = 0,
    window_started_at: i64 = 0,
    window_seconds: i64 = 0,
    count: u32 = 0,
    occupied: bool = false,
};

const State = struct {
    mutex: std.atomic.Mutex = .unlocked,
    buckets: [max_buckets]Bucket = @splat(.{}),
};

var state = State{};

/// A deliberately small, process-local fixed-window limiter. Authentication is
/// single-user and Cloudio runs as one process, so a distributed limiter would
/// add moving parts without improving this deployment's safety.
pub fn allow(key: []const u8, limit: u32, window_seconds: i64, now: i64) bool {
    const key_hash = std.hash.Wyhash.hash(0x434c4f5544494f, key);
    while (!state.mutex.tryLock()) std.atomic.spinLoopHint();
    defer state.mutex.unlock();

    var empty: ?*Bucket = null;
    for (&state.buckets) |*bucket| {
        if (bucket.occupied and bucket.key_hash == key_hash) {
            if (now - bucket.window_started_at >= window_seconds or now < bucket.window_started_at) {
                bucket.window_started_at = now;
                bucket.window_seconds = window_seconds;
                bucket.count = 1;
                return true;
            }
            if (bucket.count >= limit) return false;
            bucket.count += 1;
            return true;
        }
        if ((!bucket.occupied or now - bucket.window_started_at >= bucket.window_seconds) and empty == null) {
            empty = bucket;
        }
    }

    const bucket = empty orelse return false;
    bucket.* = .{
        .key_hash = key_hash,
        .window_started_at = now,
        .window_seconds = window_seconds,
        .count = 1,
        .occupied = true,
    };
    return true;
}

test "fixed window limiter denies excess and resets after the window" {
    const key = "test-login-bucket";
    try std.testing.expect(allow(key, 2, 60, 100));
    try std.testing.expect(allow(key, 2, 60, 101));
    try std.testing.expect(!allow(key, 2, 60, 102));
    try std.testing.expect(allow(key, 2, 60, 160));
}
