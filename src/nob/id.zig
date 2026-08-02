const std = @import("std");

const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

pub fn generate(io: std.Io, epoch_milliseconds: u64) [26]u8 {
    var bytes: [16]u8 = undefined;
    const timestamp = epoch_milliseconds & 0x0000ffffffffffff;
    bytes[0] = @truncate(timestamp >> 40);
    bytes[1] = @truncate(timestamp >> 32);
    bytes[2] = @truncate(timestamp >> 24);
    bytes[3] = @truncate(timestamp >> 16);
    bytes[4] = @truncate(timestamp >> 8);
    bytes[5] = @truncate(timestamp);
    io.random(bytes[6..]);

    var value: u128 = 0;
    for (bytes) |byte| value = (value << 8) | byte;
    var encoded: [26]u8 = undefined;
    var index: usize = encoded.len;
    while (index > 0) {
        index -= 1;
        encoded[index] = alphabet[@intCast(value & 31)];
        value >>= 5;
    }
    return encoded;
}

test "generated identifiers are protocol-compatible ULIDs" {
    const nob = @import("nob_sdk");
    const first = generate(std.testing.io, 1_700_000_000_000);
    const second = generate(std.testing.io, 1_700_000_000_000);
    try std.testing.expect(nob.plan.validUlid(&first));
    try std.testing.expect(nob.plan.validUlid(&second));
    try std.testing.expect(!std.mem.eql(u8, &first, &second));
}
