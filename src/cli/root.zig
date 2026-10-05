const std = @import("std");
const app_doctor = @import("app_doctor");
const app_init = @import("app_init");
const app_refresh_cycle = @import("app_refresh_cycle");
const app_database = @import("app_database");
const core_config = @import("core_config");
const core_version = @import("core_version");
const cli_args = @import("cli_args");
const cli_auth = @import("cli_auth");
const cli_maintenance = @import("cli_maintenance");
const cli_nob = @import("cli_nob");
const cli_render = @import("cli_render");
const cli_serve = @import("cli_serve");

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        usage();
        return;
    }

    const cfg = try core_config.Config.load(init.io, arena, init.environ_map);
    var db = try app_database.openInitialized(init.io, cfg.db_path);
    defer db.close();

    const cmd = args[1];
    const rest = args[2..];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        usage();
    } else if (std.mem.eql(u8, cmd, "init")) {
        var out = std.Io.Writer.Allocating.init(init.gpa);
        defer out.deinit();
        try app_init.writeText(.{ .io = init.io, .gpa = init.gpa, .config = cfg }, &out.writer);
        try cli_render.printOwned(init.io, init.gpa, &out);
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        const format = cli_args.parseFormatOnly(rest, error.UnexpectedDoctorArgument) catch |err| {
            std.debug.print("invalid doctor command: {s}\n", .{@errorName(err)});
            return err;
        };
        const ctx: app_doctor.Context = .{ .io = init.io, .gpa = init.gpa, .version = core_version.value, .config = cfg, .db = &db };
        try cli_render.printFormatted(init.io, init.gpa, format, app_doctor.writeText, app_doctor.writeJson, .{ctx});
    } else if (std.mem.eql(u8, cmd, "refresh")) {
        if (rest.len != 0) return error.UnexpectedRefreshArgument;
        const result = try app_refresh_cycle.run(.{ .io = init.io, .gpa = init.gpa, .db = &db, .config = cfg });
        var out = std.Io.Writer.Allocating.init(init.gpa);
        defer out.deinit();
        try result.writeJson(init.gpa, &db, &out.writer);
        try cli_render.printOwned(init.io, init.gpa, &out);
    } else if (std.mem.eql(u8, cmd, "auth")) {
        try cli_auth.run(.{ .io = init.io, .gpa = init.gpa, .db = &db, .config = cfg }, rest);
    } else if (std.mem.eql(u8, cmd, "maintenance")) {
        try cli_maintenance.run(.{ .io = init.io, .gpa = init.gpa, .db = &db, .config = cfg }, rest);
    } else if (std.mem.eql(u8, cmd, "nob")) {
        try cli_nob.run(.{ .io = init.io, .gpa = init.gpa, .db = &db, .config = cfg }, rest);
    } else if (std.mem.eql(u8, cmd, "serve")) {
        try cli_serve.run(.{ .io = init.io, .gpa = init.gpa, .db = &db, .config = cfg }, rest);
    } else {
        std.debug.print("unknown command: {s}\n\n", .{cmd});
        usage();
        return error.InvalidCliCommand;
    }
}

fn usage() void {
    std.debug.print(
        \\cloudio {s}
        \\
        \\Usage:
        \\  cloudio init
        \\  cloudio doctor [--json|--format json]
        \\  cloudio refresh
        \\  cloudio serve [--host 127.0.0.1] [--port 9331]
        \\  cloudio auth status [--json|--format json]
        \\  cloudio auth bootstrap [--ttl 10m]
        \\  cloudio auth reset --backup <path> --confirm
        \\  cloudio maintenance [status|prune|compact|run] [--apply --backup <path>] [--json|--format json]
        \\  cloudio maintenance backup --output <path> [--json|--format json]
        \\  cloudio nob list|show <id>|scan [--json|--format json]
        \\  cloudio nob trust <id> <manifest-sha256>|revoke <id>|forget <id> --yes|prepare <id>|observe <id>
        \\  cloudio nob plan <id> <action> [--param name=value]|run <plan-id> --yes [--follow]
        \\  cloudio nob resource <id> <resource-id> <control> --yes [--follow]
        \\  cloudio nob secrets <id> [--json|--format json]
        \\  cloudio nob secret-bind <id> <secret> <file|process-environment> <source-ref> --yes
        \\  cloudio nob secret-unbind <id> <secret> --yes
        \\
    , .{core_version.value});
}

test "sqlite schema initializes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try app_database.openInitialized(std.testing.io, db_path);
    defer db.close();
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("snapshots"));
}
