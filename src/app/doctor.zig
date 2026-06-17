const std = @import("std");
const core_config = @import("core_config");
const core_fs = @import("core_fs");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Db = db_store.Db;
const Io = std.Io;

const max_tool_output_bytes = 64 * 1024;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    version: []const u8,
    config: Config,
    db: *Db,
};

pub const ToolCheck = struct {
    name: []const u8,
    status: []u8,

    pub fn deinit(self: ToolCheck, gpa: Allocator) void {
        gpa.free(self.status);
    }
};

pub const Report = struct {
    version: []const u8,
    db_path: []const u8,
    log_path: []const u8,
    config_path: []const u8,
    config_present: bool,
    loaded_dotenv: bool,
    loaded_fish_env: bool,
    snapshot_count: i64,
    cloudflare_auth: bool,
    hostinger_auth: bool,
    domains: []const []const u8,
    tool_checks: []ToolCheck,
    caddyfile_path: []const u8,
    caddyfile_present: bool,
    caddy_sites_path: []const u8,
    caddy_sites_present: bool,
    caddy_admin_socket: []const u8,
    caddy_admin_socket_present: bool,

    pub fn deinit(self: *Report, gpa: Allocator) void {
        for (self.tool_checks) |check| check.deinit(gpa);
        gpa.free(self.tool_checks);
    }

    pub fn writeText(self: Report, writer: anytype) !void {
        try writer.print("cloudio {s}\n", .{self.version});
        try writer.print("db: {s}\n", .{self.db_path});
        try writer.print("run log: {s}\n", .{self.log_path});
        try writer.print("config: {s} ({s})\n", .{ self.config_path, presentLabel(self.config_present) });
        try writer.print(".env: {s}\n", .{loadedLabel(self.loaded_dotenv)});
        try writer.print(".env.fish: {s}\n", .{loadedLabel(self.loaded_fish_env)});
        try writer.print("sqlite snapshots: {d}\n", .{self.snapshot_count});
        try writer.print("cloudflare auth: {s}\n", .{configuredLabel(self.cloudflare_auth)});
        try writer.print("hostinger auth: {s}\n", .{configuredLabel(self.hostinger_auth)});
        try writer.writeAll("domains: ");
        for (self.domains, 0..) |domain, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.writeAll(domain);
        }
        try writer.writeByte('\n');

        for (self.tool_checks) |check| {
            try writer.print("{s}: {s}\n", .{ check.name, check.status });
        }

        try writer.print("caddyfile: {s} ({s})\n", .{ self.caddyfile_path, presentLabel(self.caddyfile_present) });
        try writer.print("caddy sites: {s} ({s})\n", .{ self.caddy_sites_path, presentLabel(self.caddy_sites_present) });
        try writer.print("caddy admin socket: {s} ({s})\n", .{ self.caddy_admin_socket, presentLabel(self.caddy_admin_socket_present) });
    }
};

pub fn collect(ctx: Context) !Report {
    var tool_checks = std.ArrayList(ToolCheck).empty;
    errdefer deinitToolChecks(&tool_checks, ctx.gpa);

    const checks = [_][]const []const u8{
        &.{ "zig", "version" },
        &.{ "sqlite3", "--version" },
        &.{ "caddy", "version" },
        &.{ "docker", "--version" },
        &.{ "systemctl", "--version" },
        &.{ "journalctl", "--version" },
    };
    for (checks) |argv| {
        try tool_checks.append(ctx.gpa, .{
            .name = argv[0],
            .status = try runToolCheck(ctx.io, ctx.gpa, argv),
        });
    }

    const cfg = ctx.config;
    const config_present = try core_fs.fileExists(ctx.io, cfg.config_path);
    const snapshot_count = try ctx.db.countTable("snapshots");
    const caddyfile_present = try core_fs.fileExists(ctx.io, cfg.caddyfile_path);
    const caddy_sites_present = try core_fs.fileExists(ctx.io, cfg.caddy_sites_path);
    const caddy_admin_socket_present = try core_fs.fileExists(ctx.io, cfg.caddy_admin_socket);
    const tool_check_items = try tool_checks.toOwnedSlice(ctx.gpa);

    return .{
        .version = ctx.version,
        .db_path = cfg.db_path,
        .log_path = cfg.log_path,
        .config_path = cfg.config_path,
        .config_present = config_present,
        .loaded_dotenv = cfg.loaded_dotenv,
        .loaded_fish_env = cfg.loaded_fish_env,
        .snapshot_count = snapshot_count,
        .cloudflare_auth = cfg.hasCloudflareAuth(),
        .hostinger_auth = cfg.hasHostingerAuth(),
        .domains = cfg.domains,
        .tool_checks = tool_check_items,
        .caddyfile_path = cfg.caddyfile_path,
        .caddyfile_present = caddyfile_present,
        .caddy_sites_path = cfg.caddy_sites_path,
        .caddy_sites_present = caddy_sites_present,
        .caddy_admin_socket = cfg.caddy_admin_socket,
        .caddy_admin_socket_present = caddy_admin_socket_present,
    };
}

pub fn writeText(ctx: Context, writer: anytype) !void {
    var report = try collect(ctx);
    defer report.deinit(ctx.gpa);
    try report.writeText(writer);
}

fn runToolCheck(io: Io, gpa: Allocator, argv: []const []const u8) ![]u8 {
    const result = core_process.run(gpa, io, argv, max_tool_output_bytes) catch |err| {
        return try std.fmt.allocPrint(gpa, "ERROR {s}", .{@errorName(err)});
    };
    defer result.deinit(gpa);

    const first = firstLine(result.stdout);
    if (first.len != 0) return try gpa.dupe(u8, first);
    return try gpa.dupe(u8, result.statusText());
}

fn deinitToolChecks(rows: *std.ArrayList(ToolCheck), gpa: Allocator) void {
    for (rows.items) |check| check.deinit(gpa);
    rows.deinit(gpa);
}

fn presentLabel(value: bool) []const u8 {
    return if (value) "present" else "missing";
}

fn loadedLabel(value: bool) []const u8 {
    return if (value) "loaded" else "missing";
}

fn configuredLabel(value: bool) []const u8 {
    return if (value) "configured" else "missing";
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn firstLine(value: []const u8) []const u8 {
    const clean = trim(value);
    if (std.mem.indexOfScalar(u8, clean, '\n')) |idx| return clean[0..idx];
    return clean;
}

test "doctor report renders reusable health output without credentials" {
    const allocator = std.testing.allocator;
    const domains = [_][]const u8{ "plosca.ru", "example.test" };
    var report = Report{
        .version = "0.1.0-poc",
        .db_path = ".cloudio/cloudio.db",
        .log_path = ".cloudio/latest-run.log",
        .config_path = "cloudio.local.toml",
        .config_present = true,
        .loaded_dotenv = true,
        .loaded_fish_env = false,
        .snapshot_count = 3,
        .cloudflare_auth = true,
        .hostinger_auth = false,
        .domains = domains[0..],
        .tool_checks = try allocator.dupe(ToolCheck, &.{
            .{ .name = "zig", .status = try allocator.dupe(u8, "0.16.0") },
            .{ .name = "caddy", .status = try allocator.dupe(u8, "ERROR FileNotFound") },
        }),
        .caddyfile_path = "/etc/caddy/Caddyfile",
        .caddyfile_present = true,
        .caddy_sites_path = "/etc/caddy/conf.d/sites.caddy",
        .caddy_sites_present = false,
        .caddy_admin_socket = "/run/caddy/admin.socket",
        .caddy_admin_socket_present = false,
    };
    defer report.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio 0.1.0-poc\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "domains: plosca.ru, example.test\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare auth: configured\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger auth: missing\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_token") == null);
}
