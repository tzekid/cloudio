const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nob_dependency = b.dependency("nob", .{ .target = target, .optimize = optimize });
    const runner_module = b.createModule(.{
        .root_source_file = b.path("src/nob.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "nob", .module = nob_dependency.module("nob") }},
    });
    const runner = b.addExecutable(.{ .name = "nob", .root_module = runner_module });
    b.step("nob", "Build the acceptance lifecycle runner").dependOn(&b.addInstallArtifact(runner, .{}).step);
}
