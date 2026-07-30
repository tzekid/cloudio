const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const json = module(b, "src/internal/json.zig", target, optimize, &.{});
    const http = module(b, "src/internal/http.zig", target, optimize, &.{});
    const typed_routes = module(b, "src/internal/typed_routes.zig", target, optimize, &.{
        .{ .name = "core_json", .module = json },
    });
    const routes = module(b, "src/routes.zig", target, optimize, &.{
        .{ .name = "provider_typed_routes", .module = typed_routes },
    });
    const transport = module(b, "src/transport.zig", target, optimize, &.{
        .{ .name = "net_http", .module = http },
    });
    const models = module(b, "src/models.zig", target, optimize, &.{
        .{ .name = "core_json", .module = json },
    });
    const cloudflare = b.addModule("cloudflare", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = http },
            .{ .name = "provider_cloudflare_models", .module = models },
            .{ .name = "provider_cloudflare_routes", .module = routes },
            .{ .name = "provider_cloudflare_transport", .module = transport },
        },
    });
    const compatibility = b.createModule(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = http },
            .{ .name = "provider_cloudflare_models", .module = models },
            .{ .name = "provider_cloudflare_routes", .module = routes },
            .{ .name = "provider_cloudflare_transport", .module = transport },
        },
    });

    const test_step = b.step("test", "Run all Cloudflare client tests");
    inline for (.{ json, http, typed_routes, routes, transport, models, compatibility, cloudflare }) |item| {
        const tests = b.addTest(.{ .root_module = item });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
    b.default_step = test_step;
}

fn module(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const std.Build.Module.Import,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });
}
