const std = @import("std");
const app_caddy = @import("app_caddy");
const app_caddy_desired = @import("app_caddy_desired");
const cli_render = @import("cli_render");
const app_database = @import("app_database");
const core_config = @import("core_config");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = app_database.Db;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    paths: app_caddy.Paths,
    config: core_config.Config,
    db: *Db,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    switch (try parseCommand(args)) {
        .sites => try commandSites(ctx),
        .upstreams => try commandUpstreams(ctx),
        .render => try cli_render.printOutput(ctx.io, ctx.gpa, try app_caddy.render(appContext(ctx))),
        .diff => try cli_render.printOutput(ctx.io, ctx.gpa, try app_caddy.diff(appContext(ctx))),
        .validate => try cli_render.printOutput(ctx.io, ctx.gpa, try app_caddy.validate(appContext(ctx))),
        .owned_status => try commandOwnedStatus(ctx),
        .owned_refresh => try commandOwnedRefresh(ctx),
        .owned_preview => try commandOwnedPreview(ctx),
        .owned_create => |route| try commandOwnedMutation(ctx, .create, route.host, route.upstream, null),
        .owned_delete => |host| try commandOwnedMutation(ctx, .delete, host, null, null),
        .owned_adopt => |host| try commandOwnedMutation(ctx, .adopt, host, null, null),
        .owned_enable => |host| try commandOwnedMutation(ctx, .toggle, host, null, true),
        .owned_disable => |host| try commandOwnedMutation(ctx, .toggle, host, null, false),
        .owned_apply => try commandOwnedApply(ctx),
        .unknown => |name| std.debug.print("unknown caddy command: {s}\n", .{name}),
    }
}

const Route = struct {
    host: []const u8,
    upstream: []const u8,
};

const Command = union(enum) {
    sites,
    upstreams,
    render,
    diff,
    validate,
    owned_status,
    owned_refresh,
    owned_preview,
    owned_create: Route,
    owned_delete: []const u8,
    owned_adopt: []const u8,
    owned_enable: []const u8,
    owned_disable: []const u8,
    owned_apply,
    unknown: []const u8,
};

fn parseCommand(args: []const []const u8) !Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "sites")) return .sites;
    if (std.mem.eql(u8, args[0], "upstreams")) return .upstreams;
    if (std.mem.eql(u8, args[0], "render")) return .render;
    if (std.mem.eql(u8, args[0], "diff")) return .diff;
    if (std.mem.eql(u8, args[0], "validate")) return .validate;
    if (std.mem.eql(u8, args[0], "owned-status")) {
        if (args.len != 1) return error.InvalidCaddyArguments;
        return .owned_status;
    }
    if (std.mem.eql(u8, args[0], "owned-refresh")) {
        if (args.len != 1) return error.InvalidCaddyArguments;
        return .owned_refresh;
    }
    if (std.mem.eql(u8, args[0], "owned-preview")) {
        if (args.len != 1) return error.InvalidCaddyArguments;
        return .owned_preview;
    }
    if (std.mem.eql(u8, args[0], "owned-create")) {
        if (args.len != 3) return error.InvalidCaddyArguments;
        return .{ .owned_create = .{ .host = args[1], .upstream = args[2] } };
    }
    if (std.mem.eql(u8, args[0], "owned-delete")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "--confirm") or !std.mem.eql(u8, args[3], args[1]))
            return error.CaddyDeleteConfirmationRequired;
        return .{ .owned_delete = args[1] };
    }
    if (std.mem.eql(u8, args[0], "owned-adopt")) {
        if (args.len != 2) return error.InvalidCaddyArguments;
        return .{ .owned_adopt = args[1] };
    }
    if (std.mem.eql(u8, args[0], "owned-enable")) {
        if (args.len != 2) return error.InvalidCaddyArguments;
        return .{ .owned_enable = args[1] };
    }
    if (std.mem.eql(u8, args[0], "owned-disable")) {
        if (args.len != 2) return error.InvalidCaddyArguments;
        return .{ .owned_disable = args[1] };
    }
    if (std.mem.eql(u8, args[0], "owned-apply")) {
        if (args.len != 3 or !std.mem.eql(u8, args[1], "--confirm") or !std.mem.eql(u8, args[2], "APPLY"))
            return error.CaddyApplyConfirmationRequired;
        return .owned_apply;
    }
    return .{ .unknown = args[0] };
}

fn commandSites(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy.writeSites(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandUpstreams(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy.collectAndWriteUpstreams(appContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandOwnedStatus(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy_desired.writeJson(desiredContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandOwnedRefresh(ctx: Context) !void {
    try app_caddy_desired.refresh(desiredContext(ctx));
    try commandOwnedStatus(ctx);
}

fn commandOwnedPreview(ctx: Context) !void {
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try app_caddy_desired.writePreviewJson(desiredContext(ctx), &out.writer);
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn commandOwnedMutation(ctx: Context, action: app_caddy_desired.Action, host: []const u8, upstream: ?[]const u8, enabled: ?bool) !void {
    try app_caddy_desired.mutate(desiredContext(ctx), action, .{ .host = host, .upstream = upstream, .enabled = enabled });
    try commandOwnedStatus(ctx);
}

fn commandOwnedApply(ctx: Context) !void {
    const result = try app_caddy_desired.apply(desiredContext(ctx), .{});
    defer result.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print("owned fragment applied: validated={any} reloaded={any} verified={any} bytes={d}", .{
        result.validated,
        result.reloaded,
        result.verified,
        result.bytes,
    });
    if (result.backup_path) |path| try out.writer.print(" backup={s}", .{path});
    try out.writer.writeByte('\n');
    try cli_render.printOwned(ctx.io, ctx.gpa, &out);
}

fn appContext(ctx: Context) app_caddy.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .paths = ctx.paths,
        .db = ctx.db,
    };
}

fn desiredContext(ctx: Context) app_caddy_desired.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .config = ctx.config,
        .write_meta = .{ .actor = "cli" },
    };
}

test "caddy command parser defaults to sites and recognizes dry-run commands" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(Command.sites, try parseCommand(no_args[0..]));

    const sites_args = [_][]const u8{"sites"};
    try std.testing.expectEqual(Command.sites, try parseCommand(sites_args[0..]));

    const upstreams_args = [_][]const u8{"upstreams"};
    try std.testing.expectEqual(Command.upstreams, try parseCommand(upstreams_args[0..]));

    const render_args = [_][]const u8{"render"};
    try std.testing.expectEqual(Command.render, try parseCommand(render_args[0..]));

    const diff_args = [_][]const u8{"diff"};
    try std.testing.expectEqual(Command.diff, try parseCommand(diff_args[0..]));

    const validate_args = [_][]const u8{"validate"};
    try std.testing.expectEqual(Command.validate, try parseCommand(validate_args[0..]));

    const unknown_args = [_][]const u8{"reload"};
    switch (try parseCommand(unknown_args[0..])) {
        .unknown => |name| try std.testing.expectEqualStrings("reload", name),
        else => return error.ExpectedUnknownCaddyCommand,
    }

    const owned_create_args = [_][]const u8{ "owned-create", "canary.example.com", "127.0.0.1:9000" };
    switch (try parseCommand(owned_create_args[0..])) {
        .owned_create => |route| {
            try std.testing.expectEqualStrings("canary.example.com", route.host);
            try std.testing.expectEqualStrings("127.0.0.1:9000", route.upstream);
        },
        else => return error.ExpectedOwnedCreate,
    }

    const owned_apply_args = [_][]const u8{ "owned-apply", "--confirm", "APPLY" };
    try std.testing.expectEqual(Command.owned_apply, try parseCommand(owned_apply_args[0..]));
    const unconfirmed_apply_args = [_][]const u8{"owned-apply"};
    try std.testing.expectError(error.CaddyApplyConfirmationRequired, parseCommand(unconfirmed_apply_args[0..]));

    const owned_delete_args = [_][]const u8{ "owned-delete", "canary.example.com", "--confirm", "canary.example.com" };
    switch (try parseCommand(owned_delete_args[0..])) {
        .owned_delete => |host| try std.testing.expectEqualStrings("canary.example.com", host),
        else => return error.ExpectedOwnedDelete,
    }
    const unconfirmed_delete_args = [_][]const u8{ "owned-delete", "canary.example.com" };
    try std.testing.expectError(error.CaddyDeleteConfirmationRequired, parseCommand(unconfirmed_delete_args[0..]));
}
