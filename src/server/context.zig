const std = @import("std");
const app_caddy_desired = @import("app_caddy_desired");
const app_dashboard = @import("app_dashboard");
const app_browser_run = @import("app_browser_run");
const app_dns = @import("app_dns");
const app_nob_projects = @import("app_nob_projects");
const app_nob_actions = @import("app_nob_actions");
const app_nob_runtime = @import("app_nob_runtime");
const app_nob_secrets = @import("app_nob_secrets");
const app_provider_writes = @import("app_provider_writes");
const app_system_control = @import("app_system_control");
const app_vps = @import("app_vps");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_version = @import("core_version");
const db_store = @import("db_store");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    config: core_config.Config = .{ .domains = &.{} },
    write_meta: app_writes.Metadata = .{},
    dashboard: app_dashboard.Options = .{},
    auth_user_id: ?[]const u8 = null,
    auth_csrf_token: ?[]const u8 = null,
    response_headers: []const u8 = "",
    trust_proxy_client_ip: bool = false,
};

pub fn caddy(ctx: Context) app_caddy_desired.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .write_meta = ctx.write_meta };
}

pub fn provider(ctx: Context) app_provider_writes.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .write_meta = ctx.write_meta };
}

pub fn dns(ctx: Context) app_dns.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .write_meta = ctx.write_meta,
    };
}

pub fn browserRun(ctx: Context) app_browser_run.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .write_meta = ctx.write_meta,
    };
}

pub fn system(ctx: Context) app_system_control.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .write_meta = ctx.write_meta };
}

pub fn vps(ctx: Context) app_vps.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .write_meta = ctx.write_meta,
    };
}

pub fn nob(ctx: Context) app_nob_projects.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

pub fn nobRuntime(ctx: Context) app_nob_runtime.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .cloudio_version = core_version.value,
    };
}

pub fn nobActions(ctx: Context) app_nob_actions.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .cloudio_version = core_version.value,
    };
}

pub fn nobSecrets(ctx: Context) app_nob_secrets.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
    };
}
