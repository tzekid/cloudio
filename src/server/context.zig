const std = @import("std");
const app_caddy_desired = @import("app_caddy_desired");
const app_dashboard = @import("app_dashboard");
const app_deploy = @import("app_deploy");
const app_provider_writes = @import("app_provider_writes");
const app_system_control = @import("app_system_control");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const db_store = @import("db_store");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    config: core_config.Config = .{ .domains = &.{} },
    write_meta: app_writes.Metadata = .{},
    dashboard: app_dashboard.Options = .{},
};

pub fn deploy(ctx: Context) app_deploy.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .write_meta = ctx.write_meta };
}

pub fn caddy(ctx: Context) app_caddy_desired.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .write_meta = ctx.write_meta };
}

pub fn provider(ctx: Context) app_provider_writes.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config, .write_meta = ctx.write_meta };
}

pub fn system(ctx: Context) app_system_control.Context {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .write_meta = ctx.write_meta };
}
