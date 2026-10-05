const std = @import("std");
const app_database = @import("../app/database.zig");
const server = @import("../server/root.zig");
const cli_args = @import("args.zig");
const core_config = @import("../core/config.zig");
const core_fs = @import("../core/fs.zig");
const app_writes = @import("../app/writes.zig");
const runtime_nob_workers = @import("../runtime/nob_workers.zig");
const runtime_scheduler = @import("../runtime/scheduler.zig");

const Allocator = std.mem.Allocator;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    config: core_config.Config,
};

const ServeLock = struct {
    io: Io,
    file: Io.File,

    fn deinit(self: ServeLock) void {
        self.file.close(self.io);
    }
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const options = parse(args) catch |err| {
        std.debug.print("invalid serve command: {s}\n", .{@errorName(err)});
        return err;
    };
    var listener = try server.listen(ctx.io, options);
    defer listener.deinit(ctx.io);
    const serve_lock = try acquireServeLock(ctx.io, ctx.gpa, ctx.config.db_path);
    defer serve_lock.deinit();
    const interrupted_mutations = try app_writes.recoverInterruptedMutations(ctx.db);
    if (interrupted_mutations != 0) {
        const detail = try std.fmt.allocPrint(ctx.gpa, "interrupted={d}", .{interrupted_mutations});
        defer ctx.gpa.free(detail);
        try ctx.db.insertAudit("mutation.recover", "ok", detail);
    }
    if (ctx.config.refresh_seconds > 0) {
        runtime_scheduler.start(.{ .io = ctx.io, .gpa = ctx.gpa, .config = ctx.config }) catch |err| {
            std.debug.print("cloudio scheduler spawn failed: {s}\n", .{@errorName(err)});
        };
    }
    runtime_nob_workers.start(.{ .io = ctx.io, .gpa = ctx.gpa, .config = ctx.config }) catch |err| {
        std.debug.print("cloudio nob worker spawn failed: {s}\n", .{@errorName(err)});
    };
    try server.serve(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db, .config = ctx.config }, options, &listener);
}

fn acquireServeLock(io: Io, gpa: Allocator, db_path: []const u8) !ServeLock {
    const lock_path = try std.fmt.allocPrint(gpa, "{s}.serve.lock", .{db_path});
    defer gpa.free(lock_path);
    try core_fs.ensureParentDir(io, lock_path);
    const file = Io.Dir.cwd().createFile(io, lock_path, .{
        .truncate = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |err| switch (err) {
        error.WouldBlock => return error.ServerAlreadyRunning,
        else => |other| return other,
    };
    return .{ .io = io, .file = file };
}

pub fn parse(args: []const []const u8) !server.Options {
    var options = server.Options{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--host"}, error.MissingHost)) |value| {
            options.host = value;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--port"}, error.MissingPort)) |value| {
            const parsed = std.fmt.parseInt(u16, value, 10) catch return error.InvalidPort;
            if (parsed == 0) return error.InvalidPort;
            options.port = parsed;
            continue;
        }
        return error.UnexpectedServeArgument;
    }
    return options;
}

test "serve parser accepts host and port" {
    const options = try parse(&.{ "--host=127.0.0.1", "--port", "9330" });
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(@as(u16, 9330), options.port);
    try std.testing.expectError(error.UnexpectedServeArgument, parse(&.{"--once"}));
}

test "serve lock excludes a second process owner" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/serve-lock.db", .{tmp.sub_path});
    defer allocator.free(db_path);

    const first = try acquireServeLock(std.testing.io, allocator, db_path);
    defer first.deinit();
    try std.testing.expectError(error.ServerAlreadyRunning, acquireServeLock(std.testing.io, allocator, db_path));
}
