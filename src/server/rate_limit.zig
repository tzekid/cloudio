const std = @import("std");

const max_buckets = 256;
const max_key_bytes = 96;

const Bucket = struct {
    key_hash: u64 = 0,
    key: [max_key_bytes]u8 = undefined,
    key_len: u8 = 0,
    window_started_at: i64 = 0,
    window_seconds: i64 = 0,
    count: u32 = 0,
    occupied: bool = false,

    fn matches(bucket: *const Bucket, key_hash: u64, key: []const u8) bool {
        // The stored key bytes decide; the hash only short-circuits. Matching
        // by hash alone merged colliding clients into one quota.
        return bucket.occupied and bucket.key_hash == key_hash and
            std.mem.eql(u8, bucket.key[0..bucket.key_len], key);
    }
};

const State = struct {
    // At this std pin the only blocking mutex (std.Io.Mutex) requires an Io
    // handle this API does not carry. The critical section is a bounded
    // 256-entry scan with no syscalls, so a spin acquisition is acceptable
    // here and revisited when the callers thread Io through.
    mutex: std.atomic.Mutex = .unlocked,
    buckets: [max_buckets]Bucket = @splat(.{}),
};

var state = State{};

/// A deliberately small, process-local fixed-window limiter. Authentication is
/// single-user and Cloudio runs as one process, so a distributed limiter would
/// add moving parts without improving this deployment's safety.
pub fn allow(key: []const u8, limit: u32, window_seconds: i64, now: i64) bool {
    if (key.len == 0 or key.len > max_key_bytes) return false;
    const key_hash = std.hash.Wyhash.hash(0x434c4f5544494f, key);
    while (!state.mutex.tryLock()) std.atomic.spinLoopHint();
    defer state.mutex.unlock();

    var reusable: ?*Bucket = null;
    var oldest: *Bucket = &state.buckets[0];
    for (&state.buckets) |*bucket| {
        if (bucket.matches(key_hash, key)) {
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
        if ((!bucket.occupied or now - bucket.window_started_at >= bucket.window_seconds) and reusable == null) {
            reusable = bucket;
        }
        if (bucket.window_started_at < oldest.window_started_at) oldest = bucket;
    }

    // A full table evicts the stalest window; denying the newcomer would let
    // 256 busy clients lock the operator out of login entirely.
    const bucket = reusable orelse oldest;
    bucket.* = .{
        .key_hash = key_hash,
        .key_len = @intCast(key.len),
        .window_started_at = now,
        .window_seconds = window_seconds,
        .count = 1,
        .occupied = true,
    };
    @memcpy(bucket.key[0..key.len], key);
    return true;
}

fn resetForTests() void {
    while (!state.mutex.tryLock()) std.atomic.spinLoopHint();
    defer state.mutex.unlock();
    state.buckets = @splat(.{});
}

test "saturation evicts the oldest window instead of denying everyone" {
    resetForTests();
    defer resetForTests();
    var key_storage: [24]u8 = undefined;
    for (0..max_buckets) |index| {
        const key = std.fmt.bufPrint(&key_storage, "flood-{d}", .{index}) catch unreachable;
        try std.testing.expect(allow(key, 5, 600, 1_000 + @as(i64, @intCast(index))));
    }
    // All buckets live and unexpired: a new client (the operator logging in
    // during an attack) must still get a quota, at the cost of the stalest
    // attacker bucket.
    try std.testing.expect(allow("operator-login", 5, 600, 1_500));
    // The evicted slot was the oldest window (flood-0): its bucket is fresh
    // again, while flood-1 kept its unexpired quota state.
    try std.testing.expect(!allow("flood-1", 1, 600, 1_501));
    try std.testing.expect(allow("flood-0", 1, 600, 1_501));
}

test "hash collisions cannot merge two clients into one quota" {
    // Matching is decided by stored key bytes even when hashes are equal.
    var bucket = Bucket{ .key_hash = 42, .key_len = 5, .occupied = true };
    @memcpy(bucket.key[0..5], "alice");
    try std.testing.expect(bucket.matches(42, "alice"));
    try std.testing.expect(!bucket.matches(42, "bobby"));
    try std.testing.expect(!bucket.matches(42, "alic"));
}

test "oversized and empty keys are denied outright" {
    resetForTests();
    defer resetForTests();
    try std.testing.expect(!allow("", 5, 60, 100));
    const oversized: [max_key_bytes + 1]u8 = @splat('x');
    try std.testing.expect(!allow(&oversized, 5, 60, 100));
}

test "concurrent hammering preserves per-key limits" {
    resetForTests();
    defer resetForTests();
    const worker_count = 8;
    const attempts_per_worker = 200;
    const limit = 50;
    const Tally = struct {
        fn run(index: usize, allowed: *[worker_count]u32) void {
            var key_storage: [24]u8 = undefined;
            const key = std.fmt.bufPrint(&key_storage, "stress-{d}", .{index}) catch unreachable;
            var granted: u32 = 0;
            for (0..attempts_per_worker) |_| {
                if (allow(key, limit, 3600, 5_000)) granted += 1;
            }
            allowed[index] = granted;
        }
    };
    var allowed: [worker_count]u32 = @splat(0);
    var threads: [worker_count]std.Thread = undefined;
    for (0..worker_count) |index| {
        threads[index] = try std.Thread.spawn(.{}, Tally.run, .{ index, &allowed });
    }
    for (&threads) |*thread| thread.join();
    for (allowed) |granted| try std.testing.expectEqual(@as(u32, limit), granted);
}

test "fixed window limiter denies excess and resets after the window" {
    resetForTests();
    defer resetForTests();
    const key = "test-login-bucket";
    try std.testing.expect(allow(key, 2, 60, 100));
    try std.testing.expect(allow(key, 2, 60, 101));
    try std.testing.expect(!allow(key, 2, 60, 102));
    try std.testing.expect(allow(key, 2, 60, 160));
}
