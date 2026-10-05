const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = b.addTranslateC(.{
        .root_source_file = b.path("c/sqlite.h"),
        .target = target,
        .optimize = optimize,
    });
    sqlite.linkSystemLibrary("sqlite3", .{});

    const cloudio = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite.createModule() },
            .{ .name = "passcay", .module = dependency(b, "passcay", target, optimize).module("passcay") },
            .{ .name = "zbor", .module = dependency(b, "zbor", target, optimize).module("zbor") },
            .{ .name = "web_html", .module = dependency(b, "web", target, optimize).module("web_html") },
            .{ .name = "nob", .module = dependency(b, "nob", target, optimize).module("nob") },
            .{ .name = "cloudflare", .module = dependency(b, "cloudflare", target, optimize).module("cloudflare") },
            .{ .name = "hostinger", .module = dependency(b, "hostinger", target, optimize).module("hostinger") },
        },
    });
    cloudio.linkSystemLibrary("sqlite3", .{});

    const exe = b.addExecutable(.{ .name = "cloudio", .root_module = cloudio });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    b.step("run", "Run cloudio").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run Cloudio and provider package unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = cloudio })).step);
    const package_optimize = b.fmt("-Doptimize={s}", .{@tagName(optimize)});
    for ([_][]const u8{ "vendor/cloudflare", "vendor/hostinger" }) |package| {
        const package_test = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "test", package_optimize });
        package_test.setCwd(b.path(package));
        test_step.dependOn(&package_test.step);
    }

    const web_check = b.addSystemCommand(&.{ "node", "tools/web-ui-check.mjs" });
    b.step("web-check", "Check page templates and browser scripts").dependOn(&web_check.step);

    const check = b.step("check", "Build cloudio and run unit and web checks");
    check.dependOn(&exe.step);
    check.dependOn(test_step);
    check.dependOn(&web_check.step);

    const acceptance = b.addSystemCommand(&.{ "bash", "tests/product-acceptance.sh" });
    acceptance.addArtifactArg(exe);
    const acceptance_step = b.step("product-acceptance", "Run authenticated browser acceptance checks");
    acceptance_step.dependOn(&acceptance.step);

    const release_check = b.step("release-check", "Run every check including browser acceptance");
    release_check.dependOn(check);
    release_check.dependOn(acceptance_step);
}

fn dependency(b: *std.Build, name: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Dependency {
    return b.dependency(name, .{ .target = target, .optimize = optimize });
}
