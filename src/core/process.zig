const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    pub fn ok(self: CommandResult) bool {
        return switch (self.term) {
            .exited => |code| code == 0,
            else => false,
        };
    }

    pub fn statusText(self: CommandResult) []const u8 {
        return if (self.ok()) "ok" else "failed";
    }

    pub fn deinit(self: CommandResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub fn run(gpa: Allocator, io: Io, argv: []const []const u8, limit: usize) !CommandResult {
    const result = try std.process.run(gpa, io, .{
        .argv = argv,
        .expand_arg0 = .expand,
        .stdout_limit = .limited(limit),
        .stderr_limit = .limited(limit),
    });
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

test "command result reports exit status" {
    const ok_result = CommandResult{ .stdout = @constCast(""), .stderr = @constCast(""), .term = .{ .exited = 0 } };
    const failed_result = CommandResult{ .stdout = @constCast(""), .stderr = @constCast(""), .term = .{ .exited = 1 } };

    try std.testing.expect(ok_result.ok());
    try std.testing.expectEqualStrings("ok", ok_result.statusText());
    try std.testing.expect(!failed_result.ok());
    try std.testing.expectEqualStrings("failed", failed_result.statusText());
}
