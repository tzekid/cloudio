const std = @import("std");
const app_refresh = @import("app_refresh");
const app_topology = @import("app_topology");
const core_config = @import("core_config");
const db_store = @import("db_store");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    config: core_config.Config,
};

pub fn run(ctx: Context) !void {
    try app_refresh.run(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .domains = ctx.config.domains,
        .cloudflare_auth = .{
            .token = ctx.config.cloudflare_api_token,
            .email = ctx.config.cloudflare_email,
            .key = ctx.config.cloudflare_api_key,
        },
        .hostinger_token = ctx.config.hostinger_api_token,
        .caddy_paths = .{
            .caddyfile_path = ctx.config.caddyfile_path,
            .caddy_sites_path = ctx.config.caddy_sites_path,
            .caddy_admin_socket = ctx.config.caddy_admin_socket,
        },
        .projects_root = ctx.config.projects_root,
        .log = .{
            .version = "serve",
            .db_path = ctx.config.db_path,
            .config_path = ctx.config.config_path,
            .log_path = ctx.config.log_path,
            .loaded_dotenv = ctx.config.loaded_dotenv,
            .loaded_fish_env = ctx.config.loaded_fish_env,
            .cloudflare_auth = ctx.config.hasCloudflareAuth(),
            .hostinger_auth = ctx.config.hasHostingerAuth(),
        },
    }, .{});
    const delta = try app_topology.captureDeltas(.{ .gpa = ctx.gpa, .db = ctx.db }, .{});
    if (delta.totalChanges() != 0) {
        std.debug.print(
            "cloudio topology delta: added={d} changed={d} removed={d}\n",
            .{ delta.added, delta.changed, delta.removed },
        );
    }
}
