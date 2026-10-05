const std = @import("std");
const app_caddy_desired = @import("../app/caddy_desired.zig");
const app_browser_run = @import("../app/browser_run.zig");
const app_dns = @import("../app/dns.zig");
const app_nob_projects = @import("../app/nob_projects.zig");
const app_nob_actions = @import("../app/nob_actions.zig");
const app_nob_runtime = @import("../app/nob_runtime.zig");
const app_nob_secrets = @import("../app/nob_secrets.zig");
const app_provider_writes = @import("../app/provider_writes.zig");
const app_system_control = @import("../app/system_control.zig");
const app_vps = @import("../app/vps.zig");
const app_writes = @import("../app/writes.zig");
const core_config = @import("../core/config.zig");
const core_version = @import("../core/version.zig");
const db_store = @import("../db/store.zig");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    config: core_config.Config = .{ .domains = &.{} },
    write_meta: app_writes.Metadata = .{},
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
