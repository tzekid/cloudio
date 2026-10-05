const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const passcay_dep = b.dependency("passcay", .{
        .target = target,
        .optimize = optimize,
    });
    const passcay_mod = passcay_dep.module("passcay");
    const zbor_dep = b.dependency("zbor", .{
        .target = target,
        .optimize = optimize,
    });
    const zbor_mod = zbor_dep.module("zbor");
    const web_dep = b.dependency("web", .{
        .target = target,
        .optimize = optimize,
    });
    const web_html_mod = web_dep.module("web_html");
    const nob_dep = b.dependency("nob", .{
        .target = target,
        .optimize = optimize,
    });
    const nob_sdk_mod = nob_dep.module("nob");

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
    const http_mod = b.createModule(.{
        .root_source_file = b.path("src/http/root.zig"),
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
    const provider_typed_routes_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/typed_routes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
        },
    });
    const provider_capabilities_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/capabilities.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    const nob_model_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/model.zig"),
        .target = target,
        .optimize = optimize,
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
            .{ .name = "nob_model", .module = nob_model_mod },
            .{ .name = "sqlite", .module = sqlite_mod },
        },
    });
    linkSqlite(db_store_mod);
    const app_writes_mod = b.createModule(.{
        .root_source_file = b.path("src/app/writes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_writes_mod);
    const app_caddy_desired_mod = b.createModule(.{
        .root_source_file = b.path("src/app/caddy_desired.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_caddy_desired_mod);
    const nob_protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/protocol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
        },
    });
    const nob_id_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/id.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
        },
    });
    const nob_subprocess_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/subprocess.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
        },
    });
    const nob_source_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/source.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const nob_bootstrap_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/bootstrap.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "nob_protocol", .module = nob_protocol_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const nob_observation_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/observation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "nob_protocol", .module = nob_protocol_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const nob_action_protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/action_protocol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const nob_systemd_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/systemd.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const nob_resource_control_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/resource_control.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
        },
    });
    const nob_managed_unit_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/managed_unit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_systemd", .module = nob_systemd_mod },
        },
    });
    linkSqlite(nob_managed_unit_mod);
    const nob_broker_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/broker.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_caddy_desired", .module = app_caddy_desired_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_managed_unit", .module = nob_managed_unit_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
            .{ .name = "nob_systemd", .module = nob_systemd_mod },
        },
    });
    linkSqlite(nob_broker_mod);
    const nob_independent_observation_mod = b.createModule(.{
        .root_source_file = b.path("src/nob/independent_observation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
        },
    });
    const security_passkeys_mod = b.createModule(.{
        .root_source_file = b.path("src/security/passkeys.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "passcay", .module = passcay_mod },
            .{ .name = "zbor", .module = zbor_mod },
        },
    });
    const collector_capture_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/capture.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_output", .module = core_output_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    linkSqlite(collector_capture_mod);
    const provider_cloudflare_routes_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/routes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "provider_typed_routes", .module = provider_typed_routes_mod },
        },
    });
    const provider_cloudflare_transport_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/transport.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    const provider_cloudflare_models_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/models.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
        },
    });
    const provider_cloudflare_browser_http_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/internal/http.zig"),
        .target = target,
        .optimize = optimize,
    });
    const provider_cloudflare_browser_run_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/browser_run.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = provider_cloudflare_browser_http_mod },
            .{ .name = "provider_cloudflare_transport", .module = provider_cloudflare_transport_mod },
        },
    });
    const provider_cloudflare_mod = b.createModule(.{
        .root_source_file = b.path("packages/cloudflare/src/client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_cloudflare_models", .module = provider_cloudflare_models_mod },
            .{ .name = "provider_cloudflare_routes", .module = provider_cloudflare_routes_mod },
            .{ .name = "provider_cloudflare_transport", .module = provider_cloudflare_transport_mod },
            .{ .name = "provider_cloudflare_browser_run", .module = provider_cloudflare_browser_run_mod },
        },
    });
    const provider_auth_mod = b.createModule(.{
        .root_source_file = b.path("src/providers/auth.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "provider_capabilities", .module = provider_capabilities_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
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
    const collector_project_manifests_mod = b.createModule(.{
        .root_source_file = b.path("src/collectors/project_manifests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
        },
    });
    linkSqlite(collector_project_manifests_mod);
    const provider_hostinger_routes_mod = b.createModule(.{
        .root_source_file = b.path("packages/hostinger/src/routes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "provider_typed_routes", .module = provider_typed_routes_mod },
        },
    });
    const provider_hostinger_transport_mod = b.createModule(.{
        .root_source_file = b.path("packages/hostinger/src/transport.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "net_http", .module = net_http_mod },
        },
    });
    const provider_hostinger_models_mod = b.createModule(.{
        .root_source_file = b.path("packages/hostinger/src/models.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "net_pagination", .module = net_pagination_mod },
        },
    });
    const provider_hostinger_mod = b.createModule(.{
        .root_source_file = b.path("packages/hostinger/src/client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_hostinger_models", .module = provider_hostinger_models_mod },
            .{ .name = "provider_hostinger_routes", .module = provider_hostinger_routes_mod },
            .{ .name = "provider_hostinger_transport", .module = provider_hostinger_transport_mod },
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
            .{ .name = "collector_project_manifests", .module = collector_project_manifests_mod },
            .{ .name = "collector_projects", .module = collector_projects_mod },
            .{ .name = "collector_system", .module = collector_system_mod },
            .{ .name = "core_json", .module = core_json_mod },
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
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
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


    const app_authentication_mod = b.createModule(.{
        .root_source_file = b.path("src/app/authentication.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "security_passkeys", .module = security_passkeys_mod },
        },
    });
    linkSqlite(app_authentication_mod);

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

    const app_nob_projects_mod = b.createModule(.{
        .root_source_file = b.path("src/app/nob_projects.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "collector_project_manifests", .module = collector_project_manifests_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_nob_projects_mod);
    const app_nob_secrets_mod = b.createModule(.{
        .root_source_file = b.path("src/app/nob_secrets.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_projects", .module = app_nob_projects_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
        },
    });
    linkSqlite(app_nob_secrets_mod);
    const app_nob_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/app/nob_runtime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_projects", .module = app_nob_projects_mod },
            .{ .name = "app_nob_secrets", .module = app_nob_secrets_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_bootstrap", .module = nob_bootstrap_mod },
            .{ .name = "nob_independent_observation", .module = nob_independent_observation_mod },
            .{ .name = "nob_observation", .module = nob_observation_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
        },
    });
    linkSqlite(app_nob_runtime_mod);
    const app_nob_actions_mod = b.createModule(.{
        .root_source_file = b.path("src/app/nob_actions.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_projects", .module = app_nob_projects_mod },
            .{ .name = "app_nob_secrets", .module = app_nob_secrets_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_action_protocol", .module = nob_action_protocol_mod },
            .{ .name = "nob_bootstrap", .module = nob_bootstrap_mod },
            .{ .name = "nob_id", .module = nob_id_mod },
            .{ .name = "nob_resource_control", .module = nob_resource_control_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
            .{ .name = "nob_systemd", .module = nob_systemd_mod },
        },
    });
    linkSqlite(app_nob_actions_mod);
    const app_nob_worker_mod = b.createModule(.{
        .root_source_file = b.path("src/app/nob_worker.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_runtime", .module = app_nob_runtime_mod },
            .{ .name = "app_nob_secrets", .module = app_nob_secrets_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "nob_action_protocol", .module = nob_action_protocol_mod },
            .{ .name = "nob_bootstrap", .module = nob_bootstrap_mod },
            .{ .name = "nob_broker", .module = nob_broker_mod },
            .{ .name = "nob_resource_control", .module = nob_resource_control_mod },
            .{ .name = "nob_sdk", .module = nob_sdk_mod },
            .{ .name = "nob_source", .module = nob_source_mod },
            .{ .name = "nob_subprocess", .module = nob_subprocess_mod },
            .{ .name = "nob_systemd", .module = nob_systemd_mod },
        },
    });
    linkSqlite(app_nob_worker_mod);




    const app_database_mod = b.createModule(.{
        .root_source_file = b.path("src/app/database.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_database_mod);

    const app_maintenance_mod = b.createModule(.{
        .root_source_file = b.path("src/app/maintenance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_maintenance_mod);





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
            .{ .name = "sqlite", .module = sqlite_mod },
        },
    });
    linkSqlite(app_topology_mod);

    const app_actions_mod = b.createModule(.{
        .root_source_file = b.path("src/app/actions.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_actions_mod);

    const app_dashboard_mod = b.createModule(.{
        .root_source_file = b.path("src/app/dashboard.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_actions", .module = app_actions_mod },
            .{ .name = "app_overview", .module = app_overview_mod },
            .{ .name = "app_render", .module = app_render_mod },
            .{ .name = "app_topology", .module = app_topology_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_dashboard_mod);

    const app_system_control_mod = b.createModule(.{
        .root_source_file = b.path("src/app/system_control.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "collector_system", .module = collector_system_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_process", .module = core_process_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_system_control_mod);

    const app_provider_writes_mod = b.createModule(.{
        .root_source_file = b.path("src/app/provider_writes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_auth", .module = provider_auth_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_cloudflare_transport", .module = provider_cloudflare_transport_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
            .{ .name = "provider_hostinger_transport", .module = provider_hostinger_transport_mod },
            .{ .name = "provider_routes", .module = provider_routes_mod },
        },
    });
    linkSqlite(app_provider_writes_mod);

    const app_dns_mod = b.createModule(.{
        .root_source_file = b.path("src/app/dns.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_provider_writes", .module = app_provider_writes_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
            .{ .name = "provider_cloudflare_models", .module = provider_cloudflare_models_mod },
        },
    });
    linkSqlite(app_dns_mod);

    const app_browser_run_mod = b.createModule(.{
        .root_source_file = b.path("src/app/browser_run.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "provider_cloudflare", .module = provider_cloudflare_mod },
        },
    });
    linkSqlite(app_browser_run_mod);

    const app_vps_mod = b.createModule(.{
        .root_source_file = b.path("src/app/vps.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_provider_writes", .module = app_provider_writes_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_redact", .module = core_redact_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "net_http", .module = net_http_mod },
            .{ .name = "provider_hostinger", .module = provider_hostinger_mod },
            .{ .name = "provider_hostinger_models", .module = provider_hostinger_models_mod },
        },
    });
    linkSqlite(app_vps_mod);

    const app_web_resources_mod = b.createModule(.{
        .root_source_file = b.path("src/app/web_resources.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_system_control", .module = app_system_control_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_web_resources_mod);

    const app_refresh_cycle_mod = b.createModule(.{
        .root_source_file = b.path("src/app/refresh_cycle.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_refresh", .module = app_refresh_mod },
            .{ .name = "app_topology", .module = app_topology_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(app_refresh_cycle_mod);

    const runtime_scheduler_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/scheduler.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_maintenance", .module = app_maintenance_mod },
            .{ .name = "app_refresh_cycle", .module = app_refresh_cycle_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(runtime_scheduler_mod);
    const runtime_nob_workers_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/nob_workers.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_worker", .module = app_nob_worker_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_time", .module = core_time_mod },
            .{ .name = "core_version", .module = core_version_mod },
            .{ .name = "db_store", .module = db_store_mod },
        },
    });
    linkSqlite(runtime_nob_workers_mod);

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/server/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_actions", .module = app_nob_actions_mod },
            .{ .name = "app_authentication", .module = app_authentication_mod },
            .{ .name = "app_actions", .module = app_actions_mod },
            .{ .name = "app_caddy_desired", .module = app_caddy_desired_mod },
            .{ .name = "app_dashboard", .module = app_dashboard_mod },
            .{ .name = "app_browser_run", .module = app_browser_run_mod },
            .{ .name = "app_dns", .module = app_dns_mod },
            .{ .name = "app_vps", .module = app_vps_mod },
            .{ .name = "app_inventory", .module = app_inventory_mod },
            .{ .name = "app_maintenance", .module = app_maintenance_mod },
            .{ .name = "app_nob_projects", .module = app_nob_projects_mod },
            .{ .name = "app_nob_secrets", .module = app_nob_secrets_mod },
            .{ .name = "app_nob_runtime", .module = app_nob_runtime_mod },
            .{ .name = "app_provider_writes", .module = app_provider_writes_mod },
            .{ .name = "app_refresh_cycle", .module = app_refresh_cycle_mod },
            .{ .name = "app_system_control", .module = app_system_control_mod },
            .{ .name = "app_topology", .module = app_topology_mod },
            .{ .name = "app_web_resources", .module = app_web_resources_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_json", .module = core_json_mod },
            .{ .name = "core_version", .module = core_version_mod },
            .{ .name = "db_store", .module = db_store_mod },
            .{ .name = "http", .module = http_mod },
            .{ .name = "web_html", .module = web_html_mod },
        },
    });
    linkSqlite(server_mod);


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
    const cli_nob_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/nob.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_nob_actions", .module = app_nob_actions_mod },
            .{ .name = "app_database", .module = app_database_mod },
            .{ .name = "app_nob_projects", .module = app_nob_projects_mod },
            .{ .name = "app_nob_secrets", .module = app_nob_secrets_mod },
            .{ .name = "app_nob_runtime", .module = app_nob_runtime_mod },
            .{ .name = "app_nob_worker", .module = app_nob_worker_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_version", .module = core_version_mod },
        },
    });
    linkSqlite(cli_nob_mod);
    const cli_serve_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/serve.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_database", .module = app_database_mod },
            .{ .name = "app_dashboard", .module = app_dashboard_mod },
            .{ .name = "app_writes", .module = app_writes_mod },
            .{ .name = "server", .module = server_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_fs", .module = core_fs_mod },
            .{ .name = "runtime_nob_workers", .module = runtime_nob_workers_mod },
            .{ .name = "runtime_scheduler", .module = runtime_scheduler_mod },
        },
    });
    linkSqlite(cli_serve_mod);
    const cli_auth_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/auth.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_authentication", .module = app_authentication_mod },
            .{ .name = "app_database", .module = app_database_mod },
            .{ .name = "app_maintenance", .module = app_maintenance_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "core_config", .module = core_config_mod },
        },
    });
    linkSqlite(cli_auth_mod);
    const cli_maintenance_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/maintenance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_database", .module = app_database_mod },
            .{ .name = "app_maintenance", .module = app_maintenance_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "core_config", .module = core_config_mod },
        },
    });
    linkSqlite(cli_maintenance_mod);
    const cli_root_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app_doctor", .module = app_doctor_mod },
            .{ .name = "app_init", .module = app_init_mod },
            .{ .name = "app_refresh_cycle", .module = app_refresh_cycle_mod },
            .{ .name = "app_database", .module = app_database_mod },
            .{ .name = "cli_args", .module = cli_args_mod },
            .{ .name = "cli_auth", .module = cli_auth_mod },
            .{ .name = "cli_maintenance", .module = cli_maintenance_mod },
            .{ .name = "cli_nob", .module = cli_nob_mod },
            .{ .name = "cli_render", .module = cli_render_mod },
            .{ .name = "cli_serve", .module = cli_serve_mod },
            .{ .name = "core_config", .module = core_config_mod },
            .{ .name = "core_version", .module = core_version_mod },
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
    run_cmd.addPassthruArgs();
    b.step("run", "Run cloudio").dependOn(&run_cmd.step);

    const product_acceptance_command = b.addSystemCommand(&.{ "bash", "tests/product-acceptance.sh" });
    product_acceptance_command.addArtifactArg(exe);
    const product_acceptance_step = b.step("product-acceptance", "Run authenticated product acceptance checks");
    product_acceptance_step.dependOn(&product_acceptance_command.step);

    const test_step = b.step("test", "Run application integration and standalone provider tests");
    // Provider internals are tested by their standalone packages below.
    // These roots retain Cloudio configuration, adapters, and integration tests.
    inline for (.{
        cli_root_mod,
        cli_args_mod,
        cli_render_mod,
        cli_nob_mod,
        cli_auth_mod,
        cli_maintenance_mod,
        cli_serve_mod,
        app_overview_mod,
        app_doctor_mod,
        app_init_mod,
        app_authentication_mod,
        app_caddy_mod,
        app_nob_projects_mod,
        app_nob_secrets_mod,
        runtime_nob_workers_mod,
        app_topology_mod,
        app_actions_mod,
        app_dashboard_mod,
        server_mod,
        app_writes_mod,
        app_maintenance_mod,
        app_caddy_desired_mod,
        app_system_control_mod,
        app_provider_writes_mod,
        app_dns_mod,
        app_browser_run_mod,
        app_vps_mod,
        app_render_mod,
        app_inventory_mod,
        app_database_mod,
        app_refresh_mod,
        app_web_resources_mod,
        core_config_mod,
        core_fs_mod,
        core_json_mod,
        core_log_mod,
        core_output_mod,
        core_process_mod,
        core_redact_mod,
        core_time_mod,
        core_version_mod,
        net_http_mod,
        http_mod,
        net_pagination_mod,
        provider_capabilities_mod,
        provider_auth_mod,
        provider_routes_mod,
        provider_typed_routes_mod,
        nob_model_mod,
        nob_protocol_mod,
        nob_id_mod,
        nob_subprocess_mod,
        nob_source_mod,
        nob_bootstrap_mod,
        nob_independent_observation_mod,
        nob_systemd_mod,
        nob_resource_control_mod,
        nob_managed_unit_mod,
        nob_broker_mod,
        db_schema_mod,
        db_store_mod,
        security_passkeys_mod,
        collector_capture_mod,
        collector_capture_normalize_mod,
        collector_caddy_mod,
        collector_projects_mod,
        collector_project_manifests_mod,
        collector_system_mod,
        collector_cloudflare_mod,
        collector_hostinger_mod,
    }) |module| addModuleTest(b, test_step, module);

    const web_ui_check = b.addSystemCommand(&.{ "node", "tools/web-ui-check.mjs" });
    b.step("web-check", "Check frontend structure and JavaScript syntax").dependOn(&web_ui_check.step);

    const check = b.step("check", "Build cloudio and run application, provider, and web checks");
    check.dependOn(&exe.step);
    check.dependOn(test_step);
    check.dependOn(&web_ui_check.step);

    const package_optimize_arg = b.fmt("-Doptimize={s}", .{@tagName(optimize)});
    const cloudflare_package_test = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "test", package_optimize_arg });
    cloudflare_package_test.setCwd(b.path("packages/cloudflare"));
    test_step.dependOn(&cloudflare_package_test.step);
    const hostinger_package_test = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "test", package_optimize_arg });
    hostinger_package_test.setCwd(b.path("packages/hostinger"));
    test_step.dependOn(&hostinger_package_test.step);

    const release_check = b.step("release-check", "Run integrated and authenticated product acceptance checks");
    release_check.dependOn(check);
    release_check.dependOn(product_acceptance_step);

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
