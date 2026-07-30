const std = @import("std");
const app_database = @import("app_database");
const app_maintenance = @import("app_maintenance");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const core_config = @import("core_config");

const Allocator = std.mem.Allocator;
const Db = app_database.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    config: core_config.Config,
};

pub const Parsed = struct {
    options: app_maintenance.Options = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid maintenance command: {s}\n", .{@errorName(err)});
        return err;
    };
    const policy = app_maintenance.Policy.fromConfig(ctx.config);
    const result = try app_maintenance.execute(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
    }, policy, parsed.options);
    try cli_render.printFormatted(
        ctx.io,
        ctx.gpa,
        parsed.format,
        app_maintenance.writeText,
        app_maintenance.writeJson,
        .{ result, policy },
    );
}

pub fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var index: usize = 0;
    if (args.len != 0 and !std.mem.startsWith(u8, args[0], "-")) {
        parsed.options.operation = parseOperation(args[0]) orelse return error.InvalidMaintenanceOperation;
        index = 1;
    }
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parseRequiredValueArg(args, &index, .{ "--backup", "--output" }, error.MissingBackupPath)) |value| {
            parsed.options.backup_path = value;
            continue;
        }
        if (std.mem.eql(u8, args[index], "--apply")) {
            parsed.options.apply = true;
            continue;
        }
        return error.UnexpectedMaintenanceArgument;
    }
    if (parsed.options.operation == .backup and parsed.options.backup_path == null) return error.MissingBackupPath;
    if (parsed.options.operation == .status and parsed.options.apply) return error.StatusCannotApply;
    return parsed;
}

fn parseOperation(value: []const u8) ?app_maintenance.Operation {
    if (std.mem.eql(u8, value, "status") or std.mem.eql(u8, value, "preview")) return .status;
    if (std.mem.eql(u8, value, "backup")) return .backup;
    if (std.mem.eql(u8, value, "prune")) return .prune;
    if (std.mem.eql(u8, value, "compact") or std.mem.eql(u8, value, "vacuum")) return .compact;
    if (std.mem.eql(u8, value, "run") or std.mem.eql(u8, value, "maintain")) return .run;
    return null;
}

test "maintenance parser defaults to status preview" {
    const parsed = try parse(&.{});
    try std.testing.expectEqual(app_maintenance.Operation.status, parsed.options.operation);
    try std.testing.expect(!parsed.options.apply);
    try std.testing.expectEqual(cli_render.RenderFormat.text, parsed.format);
}

test "maintenance parser accepts safe apply with backup" {
    const args = [_][]const u8{ "run", "--apply", "--backup", ".cloudio/backups/before.db", "--json" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(app_maintenance.Operation.run, parsed.options.operation);
    try std.testing.expect(parsed.options.apply);
    try std.testing.expectEqualStrings(".cloudio/backups/before.db", parsed.options.backup_path.?);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
}

test "maintenance parser validates operations and backup arguments" {
    try std.testing.expectError(error.InvalidMaintenanceOperation, parse(&.{"explode"}));
    try std.testing.expectError(error.MissingBackupPath, parse(&.{"backup"}));
    try std.testing.expectError(error.StatusCannotApply, parse(&.{ "status", "--apply" }));
}
