const std = @import("std");
const app_authentication = @import("app_authentication");
const app_database = @import("app_database");
const app_maintenance = @import("app_maintenance");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const core_config = @import("core_config");

const Db = app_database.Db;

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *Db,
    config: core_config.Config,
};

const Command = union(enum) {
    status: cli_render.RenderFormat,
    bootstrap: u32,
    reset: []const u8,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const command = parse(args) catch |err| {
        std.debug.print("invalid auth command: {s}\n", .{@errorName(err)});
        return err;
    };
    switch (command) {
        .status => |format| try writeStatus(ctx, format),
        .bootstrap => |ttl_seconds| try writeBootstrap(ctx, ttl_seconds),
        .reset => |backup_path| try reset(ctx, backup_path),
    }
}

fn parse(args: []const []const u8) !Command {
    if (args.len == 0 or std.mem.eql(u8, args[0], "status")) {
        var format: cli_render.RenderFormat = .text;
        var index: usize = if (args.len == 0) 0 else 1;
        while (index < args.len) : (index += 1) {
            if (try cli_args.parseFormatOption(args, &index, &format, error.MissingFormat, error.InvalidFormat)) continue;
            return error.UnexpectedAuthArgument;
        }
        return .{ .status = format };
    }
    if (std.mem.eql(u8, args[0], "bootstrap")) {
        var ttl = app_authentication.default_bootstrap_seconds;
        var index: usize = 1;
        while (index < args.len) : (index += 1) {
            if (try cli_args.parseRequiredValueArg(args, &index, .{"--ttl"}, error.MissingBootstrapTtl)) |value| {
                ttl = try parseDuration(value);
                continue;
            }
            return error.UnexpectedAuthArgument;
        }
        return .{ .bootstrap = ttl };
    }
    if (std.mem.eql(u8, args[0], "reset")) {
        var backup_path: ?[]const u8 = null;
        var confirmed = false;
        var index: usize = 1;
        while (index < args.len) : (index += 1) {
            if (try cli_args.parseRequiredValueArg(args, &index, .{"--backup"}, error.MissingBackupPath)) |value| {
                backup_path = value;
                continue;
            }
            if (std.mem.eql(u8, args[index], "--confirm")) {
                confirmed = true;
                continue;
            }
            return error.UnexpectedAuthArgument;
        }
        if (backup_path == null) return error.MissingBackupPath;
        if (!confirmed) return error.ResetConfirmationRequired;
        return .{ .reset = backup_path.? };
    }
    return error.InvalidAuthCommand;
}

fn writeStatus(ctx: Context, format: cli_render.RenderFormat) !void {
    const value = try app_authentication.status(appContext(ctx));
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    switch (format) {
        .text => try out.writer.print(
            "Cloudio passkey authentication\nconfigured={s} credentials={d} active_sessions={d} bootstrap_active={s}\norigin={s}\nrp_id={s}\n",
            .{
                if (value.configured) "yes" else "no",
                value.credential_count,
                value.active_session_count,
                if (value.bootstrap_active) "yes" else "no",
                ctx.config.auth_origin,
                ctx.config.auth_rp_id,
            },
        ),
        .json => try out.writer.print(
            "{{\"configured\":{s},\"credentials\":{d},\"active_sessions\":{d},\"bootstrap_active\":{s},\"origin\":\"{s}\",\"rp_id\":\"{s}\"}}\n",
            .{
                if (value.configured) "true" else "false",
                value.credential_count,
                value.active_session_count,
                if (value.bootstrap_active) "true" else "false",
                ctx.config.auth_origin,
                ctx.config.auth_rp_id,
            },
        ),
    }
    try cli_render.writeAll(ctx.io, out.written());
}

fn writeBootstrap(ctx: Context, ttl_seconds: u32) !void {
    const value = try app_authentication.createBootstrap(appContext(ctx), ttl_seconds);
    defer value.deinit(ctx.gpa);
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "Open this one-use setup link before it expires:\n{s}\nexpires_at={d}\n",
        .{ value.setup_url, value.expires_at },
    );
    try cli_render.writeAll(ctx.io, out.written());
}

fn reset(ctx: Context, backup_path: []const u8) !void {
    try app_maintenance.backup(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    }, backup_path);
    try app_authentication.reset(appContext(ctx));
    var out = std.Io.Writer.Allocating.init(ctx.gpa);
    defer out.deinit();
    try out.writer.print(
        "Passkey authentication reset.\nverified_backup={s}\nNext: cloudio auth bootstrap --ttl 10m\n",
        .{backup_path},
    );
    try cli_render.writeAll(ctx.io, out.written());
}

fn appContext(ctx: Context) app_authentication.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .origin = ctx.config.auth_origin,
        .rp_id = ctx.config.auth_rp_id,
    };
}

fn parseDuration(value: []const u8) !u32 {
    if (value.len == 0) return error.InvalidBootstrapTtl;
    const multiplier: u32 = switch (value[value.len - 1]) {
        's' => 1,
        'm' => 60,
        'h' => 60 * 60,
        else => 1,
    };
    const digits = if (std.ascii.isDigit(value[value.len - 1])) value else value[0 .. value.len - 1];
    const amount = std.fmt.parseInt(u32, digits, 10) catch return error.InvalidBootstrapTtl;
    const seconds = std.math.mul(u32, amount, multiplier) catch return error.InvalidBootstrapTtl;
    if (seconds == 0 or seconds > app_authentication.max_bootstrap_seconds) {
        return error.InvalidBootstrapTtl;
    }
    return seconds;
}

test "auth parser supports status bootstrap and guarded reset" {
    try std.testing.expectEqual(
        app_authentication.default_bootstrap_seconds,
        (try parse(&.{"bootstrap"})).bootstrap,
    );
    try std.testing.expectEqual(@as(u32, 600), (try parse(&.{ "bootstrap", "--ttl", "10m" })).bootstrap);
    try std.testing.expectError(
        error.ResetConfirmationRequired,
        parse(&.{ "reset", "--backup", "backup.db" }),
    );
    try std.testing.expectEqualStrings(
        "backup.db",
        (try parse(&.{ "reset", "--backup", "backup.db", "--confirm" })).reset,
    );
}
