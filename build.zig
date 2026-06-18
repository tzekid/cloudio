const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_c = b.addTranslateC(.{
        .root_source_file = b.path("c/sqlite.h"),
        .target = target,
        .optimize = optimize,
    });
    sqlite_c.linkSystemLibrary("sqlite3", .{});
    const sqlite_mod = sqlite_c.createModule();

    const core_config_mod = b.createModule(.{
        .root_source_file = b.path("src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_json_mod = b.createModule(.{
        .root_source_file = b.path("src/core/json.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_output_mod = b.createModule(.{
        .root_source_file = b.path("src/core/output.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_fs_mod = b.createModule(.{
        .root_source_file = b.path("src/core/fs.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_time_mod = b.createModule(.{
        .root_source_file = b.path("src/core/time.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_version_mod = b.createModule(.{
        .root_source_file = b.path("src/core/version.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_redact_mod = b.createModule(.{
        .root_source_file = b.path("src/core/redact.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_log_mod = b.createModule(.{
        .root_source_file = b.path("src/core/log.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
        },
    });
    const core_process_mod = b.createModule(.{
        .root_source_file = b.path("src/core/process.zig"),
        .target = target,
        .optimize = optimize,
    });
    const net_http_mod = b.createModule(.{
        .root_source_file = b.path("src/net/http.zig"),
        .target = target,
        .optimize = optimize,
    });
    const net_pagination_mod = b.createModule(.{
        .root_source_file = b.path("src/net/pagination.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
        },
    });
    const provider_routes_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/routes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
        },
    });
    const db_schema_mod = b.createModule(.{
        .root_source_file = b.path("src/db/schema.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
        },
    });
    linkSqlite(db_schema_mod);
    const db_store_mod = b.createModule(.{
        .root_source_file = b.path("src/db/store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "db_schema", .module = db_schema_mod },
            .{ .name = "sqlite", .module = sqlite_mod },
        },
    });
    linkSqlite(db_store_mod);
    const collector_capture_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/capture.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    linkSqlite(collector_capture_mod);
    const provider_cloudflare_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/cloudflare/client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    const provider_cloudflare_models_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/cloudflare/models.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
        },
    });
    const collector_caddy_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/caddy.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(collector_caddy_mod);
    const collector_system_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/system.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(collector_system_mod);
    const collector_projects_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/projects.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(collector_projects_mod);
    const provider_hostinger_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/hostinger/client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    const provider_hostinger_models_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/hostinger/models.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "net_pagination", .module = net_pagination_mod },
        },
    });
    const collector_capture_normalize_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/capture_normalize.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_cloudflare_models", .module = provider_cloudflare_models_mod },
            .{ .name = "provider_hostinger_models", .module = provider_hostinger_models_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(collector_capture_normalize_mod);
    const collector_cloudflare_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/cloudflare.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "collector_capture", .module = collector_capture_mod },
            .{ .name = "collector_capture_normalize", .module = collector_capture_normalize_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_cloudflare_models", .module = provider_cloudflare_models_mod },
        },
    });
    linkSqlite(collector_cloudflare_mod);
    const provider_dispatch_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/dispatch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    const collector_hostinger_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/hostinger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "collector_capture", .module = collector_capture_mod },
            .{ .name = "collector_capture_normalize", .module = collector_capture_normalize_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
            .{ .name = "provider_hostinger_models", .module = provider_hostinger_models_mod },
        },
    });
    linkSqlite(collector_hostinger_mod);

    const app_refresh_mod = b.createModule(.{
        .root_source_file = b.path("src/app/refresh.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "collector_caddy", .module = collector_caddy_mod },
            .{ .name = "collector_cloudflare", .module = collector_cloudflare_mod },
            .{ .name = "collector_hostinger", .module = collector_hostinger_mod },
            .{ .name = "collector_projects", .module = collector_projects_mod },
            .{ .name = "collector_system", .module = collector_system_mod },
            .{ .name = "core_log", .module = core_log_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_refresh_mod);

    const app_render_mod = b.createModule(.{
        .root_source_file = b.path("src/app/render.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_render_mod);

    const app_overview_mod = b.createModule(.{
        .root_source_file = b.path("src/app/overview.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_overview_mod);

    const app_history_mod = b.createModule(.{
        .root_source_file = b.path("src/app/history.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_history_mod);

    const app_evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/app/evidence.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_evidence_mod);

    const app_export_mod = b.createModule(.{
        .root_source_file = b.path("src/app/export.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_history", .module = app_history_mod },
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_export_mod);

    const app_provider_l1_mod = b.createModule(.{
        .root_source_file = b.path("src/app/provider_l1.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "provider_dispatch", .module = provider_dispatch_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });

    const app_coverage_mod = b.createModule(.{
        .root_source_file = b.path("src/app/coverage.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_provider_l1", .module = app_provider_l1_mod },
            .{ .name = "collector_capture", .module = collector_capture_mod },
            .{ .name = "collector_capture_normalize", .module = collector_capture_normalize_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_pagination", .module = net_pagination_mod },
            .{ .name = "provider_dispatch", .module = provider_dispatch_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_coverage_mod);

    const app_doctor_mod = b.createModule(.{
        .root_source_file = b.path("src/app/doctor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_doctor_mod);

    const app_init_mod = b.createModule(.{
        .root_source_file = b.path("src/app/init.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
        },
    });

    const app_log_mod = b.createModule(.{
        .root_source_file = b.path("src/app/log.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_log", .module = core_log_mod },
        },
    });
    linkSqlite(app_log_mod);

    const app_caddy_mod = b.createModule(.{
        .root_source_file = b.path("src/app/caddy.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "collector_caddy", .module = collector_caddy_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_caddy_mod);

    const app_projects_mod = b.createModule(.{
        .root_source_file = b.path("src/app/projects.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "collector_projects", .module = collector_projects_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_projects_mod);

    const app_system_mod = b.createModule(.{
        .root_source_file = b.path("src/app/system.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "collector_system", .module = collector_system_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_system_mod);

    const app_provider_list_mod = b.createModule(.{
        .root_source_file = b.path("src/app/provider_list.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_provider_list_mod);

    const app_provider_api_mod = b.createModule(.{
        .root_source_file = b.path("src/app/provider_api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_provider_api_mod);

    const app_cloudflare_mod = b.createModule(.{
        .root_source_file = b.path("src/app/cloudflare.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "collector_cloudflare", .module = collector_cloudflare_mod },
            .{ .name = "app_provider_api", .module = app_provider_api_mod },
            .{ .name = "app_provider_list", .module = app_provider_list_mod },
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
        },
    });
    linkSqlite(app_cloudflare_mod);

    const app_hostinger_mod = b.createModule(.{
        .root_source_file = b.path("src/app/hostinger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "collector_hostinger", .module = collector_hostinger_mod },
            .{ .name = "app_provider_api", .module = app_provider_api_mod },
            .{ .name = "app_provider_list", .module = app_provider_list_mod },
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
        },
    });
    linkSqlite(app_hostinger_mod);

    const app_inventory_mod = b.createModule(.{
        .root_source_file = b.path("src/app/inventory.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_inventory_mod);

    const app_topology_mod = b.createModule(.{
        .root_source_file = b.path("src/app/topology.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_topology_mod);

    const app_route_catalog_mod = b.createModule(.{
        .root_source_file = b.path("src/app/route_catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });

    const cloudio_mod = b.createModule(.{
        .root_source_file = b.path("src/cloudio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_caddy", .module = app_caddy_mod },
            .{ .name = "app_cloudflare", .module = app_cloudflare_mod },
            .{ .name = "app_coverage", .module = app_coverage_mod },
            .{ .name = "app_doctor", .module = app_doctor_mod },
            .{ .name = "app_evidence", .module = app_evidence_mod },
            .{ .name = "app_export", .module = app_export_mod },
            .{ .name = "app_history", .module = app_history_mod },
            .{ .name = "app_hostinger", .module = app_hostinger_mod },
            .{ .name = "app_init", .module = app_init_mod },
            .{ .name = "app_inventory", .module = app_inventory_mod },
            .{ .name = "app_log", .module = app_log_mod },
            .{ .name = "app_overview", .module = app_overview_mod },
            .{ .name = "app_projects", .module = app_projects_mod },
            .{ .name = "app_provider_list", .module = app_provider_list_mod },
            .{ .name = "app_refresh", .module = app_refresh_mod },
            .{ .name = "app_route_catalog", .module = app_route_catalog_mod },
            .{ .name = "app_system", .module = app_system_mod },
            .{ .name = "app_topology", .module = app_topology_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_log", .module = core_log_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "core_version", .module = core_version_mod },
            .{ .name = "db_schema", .module = db_schema_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "net_pagination", .module = net_pagination_mod },
            .{ .name = "provider_dispatch", .module = provider_dispatch_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_cloudflare_models", .module = provider_cloudflare_models_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
            .{ .name = "provider_hostinger_models", .module = provider_hostinger_models_mod },
        },
    });
    linkSqlite(cloudio_mod);

    const cli_render_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/render.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cli_args_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/args.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cli_render", .module = cli_render_mod },
        },
    });
    const cli_coverage_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/coverage.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_coverage", .module = app_coverage_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
        },
    });
    const cli_route_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/route.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_coverage", .module = app_coverage_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_coverage", .module = cli_coverage_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
        },
    });
    const cli_routes_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/routes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_route_catalog", .module = app_route_catalog_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
        },
    });
    const cli_caddy_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/caddy.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_caddy", .module = app_caddy_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_caddy_mod);
    const cli_cloudflare_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/cloudflare.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_cloudflare", .module = app_cloudflare_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_cloudflare_mod);
    const cli_hostinger_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/hostinger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_hostinger", .module = app_hostinger_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_hostinger_mod);
    const cli_evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/evidence.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_evidence", .module = app_evidence_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_evidence_mod);
    const cli_inventory_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/inventory.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_inventory", .module = app_inventory_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_inventory_mod);
    const cli_projects_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/projects.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_projects", .module = app_projects_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_projects_mod);
    const cli_system_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/system.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_system", .module = app_system_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_system_mod);
    const cli_topology_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/topology.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_topology", .module = app_topology_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_topology_mod);
    const cli_root_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_doctor", .module = app_doctor_mod },
            .{ .name = "app_export", .module = app_export_mod },
            .{ .name = "app_history", .module = app_history_mod },
            .{ .name = "app_init", .module = app_init_mod },
            .{ .name = "app_log", .module = app_log_mod },
            .{ .name = "app_overview", .module = app_overview_mod },
            .{ .name = "app_refresh", .module = app_refresh_mod },
            .{ .name = "app_caddy", .module = app_caddy_mod },
            .{ .name = "app_cloudflare", .module = app_cloudflare_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_caddy", .module = cli_caddy_mod },
            .{ .name = "cli_cloudflare", .module = cli_cloudflare_mod },
            .{ .name = "cli_coverage", .module = cli_coverage_mod },
            .{ .name = "cli_evidence", .module = cli_evidence_mod },
            .{ .name = "cli_hostinger", .module = cli_hostinger_mod },
            .{ .name = "cli_inventory", .module = cli_inventory_mod },
            .{ .name = "cli_projects", .module = cli_projects_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "cli_route", .module = cli_route_mod },
            .{ .name = "cli_routes", .module = cli_routes_mod },
            .{ .name = "cli_system", .module = cli_system_mod },
            .{ .name = "cli_topology", .module = cli_topology_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_version", .module = core_version_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(cli_root_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cli_root", .module = cli_root_mod },
        },
    });
    linkSqlite(exe_mod);

    const exe = b.addExecutable(.{
        .name = "cloudio",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run cloudio").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    addModuleTest(b, test_step, cli_root_mod);
    addModuleTest(b, test_step, cli_args_mod);
    addModuleTest(b, test_step, cli_render_mod);
    addModuleTest(b, test_step, cli_coverage_mod);
    addModuleTest(b, test_step, cli_route_mod);
    addModuleTest(b, test_step, cli_caddy_mod);
    addModuleTest(b, test_step, cli_cloudflare_mod);
    addModuleTest(b, test_step, cli_evidence_mod);
    addModuleTest(b, test_step, cli_hostinger_mod);
    addModuleTest(b, test_step, cli_inventory_mod);
    addModuleTest(b, test_step, cli_projects_mod);
    addModuleTest(b, test_step, cli_routes_mod);
    addModuleTest(b, test_step, cli_system_mod);
    addModuleTest(b, test_step, cli_topology_mod);
    addModuleTest(b, test_step, cloudio_mod);
    addModuleTest(b, test_step, app_overview_mod);
    addModuleTest(b, test_step, app_export_mod);
    addModuleTest(b, test_step, app_history_mod);
    addModuleTest(b, test_step, app_coverage_mod);
    addModuleTest(b, test_step, app_doctor_mod);
    addModuleTest(b, test_step, app_evidence_mod);
    addModuleTest(b, test_step, app_init_mod);
    addModuleTest(b, test_step, app_log_mod);
    addModuleTest(b, test_step, app_caddy_mod);
    addModuleTest(b, test_step, app_projects_mod);
    addModuleTest(b, test_step, app_system_mod);
    addModuleTest(b, test_step, app_topology_mod);
    addModuleTest(b, test_step, app_provider_api_mod);
    addModuleTest(b, test_step, app_provider_l1_mod);
    addModuleTest(b, test_step, app_provider_list_mod);
    addModuleTest(b, test_step, app_render_mod);
    addModuleTest(b, test_step, app_route_catalog_mod);
    addModuleTest(b, test_step, app_cloudflare_mod);
    addModuleTest(b, test_step, app_hostinger_mod);
    addModuleTest(b, test_step, app_inventory_mod);
    addModuleTest(b, test_step, app_refresh_mod);
    addModuleTest(b, test_step, core_config_mod);
    addModuleTest(b, test_step, core_fs_mod);
    addModuleTest(b, test_step, core_json_mod);
    addModuleTest(b, test_step, core_log_mod);
    addModuleTest(b, test_step, core_output_mod);
    addModuleTest(b, test_step, core_process_mod);
    addModuleTest(b, test_step, core_redact_mod);
    addModuleTest(b, test_step, core_time_mod);
    addModuleTest(b, test_step, core_version_mod);
    addModuleTest(b, test_step, net_http_mod);
    addModuleTest(b, test_step, net_pagination_mod);
    addModuleTest(b, test_step, provider_dispatch_mod);
    addModuleTest(b, test_step, provider_routes_mod);
    addModuleTest(b, test_step, provider_cloudflare_mod);
    addModuleTest(b, test_step, provider_cloudflare_models_mod);
    addModuleTest(b, test_step, provider_hostinger_mod);
    addModuleTest(b, test_step, provider_hostinger_models_mod);
    addModuleTest(b, test_step, db_schema_mod);
    addModuleTest(b, test_step, db_store_mod);
    addModuleTest(b, test_step, collector_capture_mod);
    addModuleTest(b, test_step, collector_capture_normalize_mod);
    addModuleTest(b, test_step, collector_caddy_mod);
    addModuleTest(b, test_step, collector_projects_mod);
    addModuleTest(b, test_step, collector_system_mod);
    addModuleTest(b, test_step, collector_cloudflare_mod);
    addModuleTest(b, test_step, collector_hostinger_mod);

    const architecture_check = b.addSystemCommand(&.{ "sh", "tools/architecture-check.sh" });
    b.step("architecture-check", "Check internal module boundary invariants").dependOn(&architecture_check.step);

    const check = b.step("check", "Build cloudio and run unit tests");
    check.dependOn(&exe.step);
    check.dependOn(test_step);
    check.dependOn(&architecture_check.step);

    const api_summary = b.addSystemCommand(&.{ "sh", "tools/api-spec-summary.sh" });
    b.step("api-summary", "Fetch official provider OpenAPI specs and print coverage summary").dependOn(&api_summary.step);

    const coverage_manifest = b.addSystemCommand(&.{ "sh", "tools/provider-coverage-manifest.sh", "generate" });
    b.step("coverage-manifest", "Generate checked provider coverage manifests from official OpenAPI specs").dependOn(&coverage_manifest.step);

    const coverage_check = b.addSystemCommand(&.{ "sh", "tools/provider-coverage-manifest.sh", "check" });
    b.step("coverage-check", "Check provider coverage manifests against current official OpenAPI specs").dependOn(&coverage_check.step);
}

fn addModuleTest(b: *std.Build, test_step: *std.Build.Step, module: *std.Build.Module) void {
    const tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}

fn linkSqlite(module: *std.Build.Module) void {
    module.linkSystemLibrary("sqlite3", .{});
    module.link_libc = true;
}
