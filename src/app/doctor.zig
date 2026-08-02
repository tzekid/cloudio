const std = @import("std");
const app_render = @import("app_render");
const core_config = @import("core_config");
const core_fs = @import("core_fs");
const core_process = @import("core_process");
const db_store = @import("db_store");
const nob_subprocess = @import("nob_subprocess");

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

pub const NobCheckState = enum { ready, warning, @"error", disabled };

pub const NobCheck = struct {
    name: []const u8,
    state: NobCheckState,
    detail: []u8,

    pub fn deinit(self: NobCheck, gpa: Allocator) void {
        gpa.free(self.detail);
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
    nob_enabled: bool,
    nob_ready: bool,
    nob_allow_system_mutation: bool,
    nob_state_root: []const u8,
    nob_cache_root: []const u8,
    nob_toolchains_file: []const u8,
    nob_checks: []NobCheck,

    pub fn deinit(self: *Report, gpa: Allocator) void {
        for (self.tool_checks) |check| check.deinit(gpa);
        gpa.free(self.tool_checks);
        for (self.nob_checks) |check| check.deinit(gpa);
        gpa.free(self.nob_checks);
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
        try writer.print("nob.zig: {s}; readiness: {s}; system mutation: {s}\n", .{
            if (self.nob_enabled) "enabled" else "disabled",
            if (!self.nob_enabled) "disabled" else if (self.nob_ready) "ready" else "attention required",
            if (self.nob_allow_system_mutation) "enabled" else "disabled",
        });
        try writer.print("nob state: {s}\n", .{self.nob_state_root});
        try writer.print("nob runner cache: {s}\n", .{self.nob_cache_root});
        try writer.print("nob toolchains: {s}\n", .{self.nob_toolchains_file});
        for (self.nob_checks) |check| {
            try writer.print("nob {s}: {s} — {s}\n", .{ check.name, @tagName(check.state), check.detail });
        }
    }

    pub fn writeJson(self: Report, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"doctor\",");
        try app_render.writeJsonStringField(writer, "version", self.version, true);
        try writer.writeAll("\"paths\":{");
        try app_render.writeJsonStringField(writer, "db", self.db_path, true);
        try app_render.writeJsonStringField(writer, "log", self.log_path, true);
        try writer.writeAll("\"config\":{");
        try app_render.writeJsonStringField(writer, "path", self.config_path, true);
        try app_render.writeJsonBoolField(writer, "present", self.config_present, false);
        try writer.writeAll("},\"caddyfile\":{");
        try app_render.writeJsonStringField(writer, "path", self.caddyfile_path, true);
        try app_render.writeJsonBoolField(writer, "present", self.caddyfile_present, false);
        try writer.writeAll("},\"caddy_sites\":{");
        try app_render.writeJsonStringField(writer, "path", self.caddy_sites_path, true);
        try app_render.writeJsonBoolField(writer, "present", self.caddy_sites_present, false);
        try writer.writeAll("},\"caddy_admin_socket\":{");
        try app_render.writeJsonStringField(writer, "path", self.caddy_admin_socket, true);
        try app_render.writeJsonBoolField(writer, "present", self.caddy_admin_socket_present, false);
        try writer.writeAll("}},\"env\":{");
        try app_render.writeJsonBoolField(writer, "dotenv_loaded", self.loaded_dotenv, true);
        try app_render.writeJsonBoolField(writer, "fish_env_loaded", self.loaded_fish_env, false);
        try writer.writeAll("},\"auth\":{");
        try app_render.writeJsonBoolField(writer, "cloudflare", self.cloudflare_auth, true);
        try app_render.writeJsonBoolField(writer, "hostinger", self.hostinger_auth, false);
        try writer.writeAll("},\"sqlite\":{");
        try app_render.writeJsonIntField(writer, "snapshots", self.snapshot_count, false);
        try writer.writeAll("},\"domains\":");
        try app_render.writeJsonStringArray(writer, self.domains);
        try writer.writeAll(",\"tools\":[");
        for (self.tool_checks, 0..) |check, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try app_render.writeJsonStringField(writer, "name", check.name, true);
            try app_render.writeJsonStringField(writer, "status", check.status, false);
            try writer.writeByte('}');
        }
        try writer.writeAll("],\"nob\":{");
        try app_render.writeJsonBoolField(writer, "enabled", self.nob_enabled, true);
        try app_render.writeJsonBoolField(writer, "ready", self.nob_ready, true);
        try app_render.writeJsonBoolField(writer, "system_mutation", self.nob_allow_system_mutation, true);
        try writer.writeAll("\"paths\":{");
        try app_render.writeJsonStringField(writer, "state_root", self.nob_state_root, true);
        try app_render.writeJsonStringField(writer, "cache_root", self.nob_cache_root, true);
        try app_render.writeJsonStringField(writer, "toolchains_file", self.nob_toolchains_file, false);
        try writer.writeAll("},\"checks\":[");
        for (self.nob_checks, 0..) |check, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try app_render.writeJsonStringField(writer, "name", check.name, true);
            try app_render.writeJsonStringField(writer, "state", @tagName(check.state), true);
            try app_render.writeJsonStringField(writer, "detail", check.detail, false);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}}");
    }
};

pub fn collect(ctx: Context) !Report {
    var tool_checks = std.ArrayList(ToolCheck).empty;
    errdefer deinitToolChecks(&tool_checks, ctx.gpa);
    var nob_checks = std.ArrayList(NobCheck).empty;
    errdefer deinitNobChecks(&nob_checks, ctx.gpa);
    const cfg = ctx.config;

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

    if (!cfg.nob_enabled) {
        try appendNobCheck(&nob_checks, ctx.gpa, "control-plane", .disabled, "disabled by configuration");
    } else {
        try nob_checks.append(ctx.gpa, try runNobCommandCheck(ctx, "runner-zig", "zig", &.{"version"}, .@"error"));
        try nob_checks.append(ctx.gpa, try directoryCheck(ctx.io, ctx.gpa, "state-root", cfg.nob_state_root));
        try nob_checks.append(ctx.gpa, try directoryCheck(ctx.io, ctx.gpa, "runner-cache", cfg.nob_cache_root));
        try nob_checks.append(ctx.gpa, try toolchainsCheck(ctx.io, ctx.gpa, cfg.nob_toolchains_file));
        try nob_checks.append(ctx.gpa, try runNobCommandCheck(
            ctx,
            "systemd-user-manager",
            "systemctl",
            &.{ "--user", "show", "--no-pager", "--property=Version" },
            .warning,
        ));
        if (cfg.nob_allow_system_mutation) {
            try appendNobCheck(&nob_checks, ctx.gpa, "system-mutation", .ready, "enabled; every mutation still requires an approved, exact broker request");
            try nob_checks.append(ctx.gpa, try runNobCommandCheck(
                ctx,
                "caddy-config",
                "caddy",
                &.{ "validate", "--config", cfg.caddyfile_path },
                .@"error",
            ));
            try nob_checks.append(ctx.gpa, try runNobCommandCheck(
                ctx,
                "caddy-service",
                "systemctl",
                &.{ "--system", "--no-ask-password", "show", "--no-pager", "--property=LoadState", "caddy.service" },
                .@"error",
            ));
            try nob_checks.append(ctx.gpa, try requiredPathCheck(ctx.io, ctx.gpa, "caddy-admin-socket", cfg.caddy_admin_socket));
        } else {
            try appendNobCheck(&nob_checks, ctx.gpa, "system-mutation", .disabled, "systemd and Caddy changes are blocked by the global kill switch");
        }
    }

    const config_present = try core_fs.fileExists(ctx.io, cfg.config_path);
    const snapshot_count = try ctx.db.countTable("snapshots");
    const caddyfile_present = try core_fs.fileExists(ctx.io, cfg.caddyfile_path);
    const caddy_sites_present = try core_fs.fileExists(ctx.io, cfg.caddy_sites_path);
    const caddy_admin_socket_present = try core_fs.fileExists(ctx.io, cfg.caddy_admin_socket);
    const tool_check_items = try tool_checks.toOwnedSlice(ctx.gpa);
    errdefer {
        for (tool_check_items) |check| check.deinit(ctx.gpa);
        ctx.gpa.free(tool_check_items);
    }
    const nob_check_items = try nob_checks.toOwnedSlice(ctx.gpa);
    const nob_ready = cfg.nob_enabled and !hasNobErrors(nob_check_items);

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
        .nob_enabled = cfg.nob_enabled,
        .nob_ready = nob_ready,
        .nob_allow_system_mutation = cfg.nob_allow_system_mutation,
        .nob_state_root = cfg.nob_state_root,
        .nob_cache_root = cfg.nob_cache_root,
        .nob_toolchains_file = cfg.nob_toolchains_file,
        .nob_checks = nob_check_items,
    };
}

pub fn writeText(ctx: Context, writer: anytype) !void {
    var report = try collect(ctx);
    defer report.deinit(ctx.gpa);
    try report.writeText(writer);
}

pub fn writeJson(ctx: Context, writer: anytype) !void {
    var report = try collect(ctx);
    defer report.deinit(ctx.gpa);
    try report.writeJson(writer);
}

fn runToolCheck(io: Io, gpa: Allocator, argv: []const []const u8) ![]u8 {
    const result = core_process.run(gpa, io, argv, max_tool_output_bytes) catch |err| {
        return try std.fmt.allocPrint(gpa, "ERROR {s}", .{@errorName(err)});
    };
    defer result.deinit(gpa);

    if (!result.ok()) {
        const detail = firstLine(if (trim(result.stderr).len != 0) result.stderr else result.stdout);
        if (detail.len != 0) return try std.fmt.allocPrint(gpa, "ERROR {s}: {s}", .{ result.statusText(), detail });
        return try std.fmt.allocPrint(gpa, "ERROR {s}", .{result.statusText()});
    }
    const first = firstLine(if (trim(result.stdout).len != 0) result.stdout else result.stderr);
    if (first.len != 0) return try gpa.dupe(u8, first);
    return try gpa.dupe(u8, result.statusText());
}

fn runNobCommandCheck(
    ctx: Context,
    name: []const u8,
    executable_name: []const u8,
    suffix: []const []const u8,
    failure_state: NobCheckState,
) !NobCheck {
    const executable = nob_subprocess.resolveExecutable(
        ctx.io,
        ctx.gpa,
        executable_name,
        ctx.config.runtime_environment.path,
    ) catch |err| return ownedNobCheck(ctx.gpa, name, failure_state, try std.fmt.allocPrint(
        ctx.gpa,
        "{s} is unavailable in the sanitized runtime PATH ({s})",
        .{ executable_name, @errorName(err) },
    ));
    defer ctx.gpa.free(executable);
    const argv = try ctx.gpa.alloc([]const u8, suffix.len + 1);
    defer ctx.gpa.free(argv);
    argv[0] = executable;
    @memcpy(argv[1..], suffix);
    var environment = try nob_subprocess.makeEnvironment(ctx.gpa, ctx.config.runtime_environment, &.{});
    defer environment.deinit();
    const result = nob_subprocess.run(ctx.gpa, ctx.io, argv, "/", &environment, .{
        .stdout_bytes = max_tool_output_bytes,
        .stderr_bytes = max_tool_output_bytes,
        .timeout_seconds = 15,
    }) catch |err| return ownedNobCheck(ctx.gpa, name, failure_state, try std.fmt.allocPrint(
        ctx.gpa,
        "check could not run ({s})",
        .{@errorName(err)},
    ));
    defer result.deinit(ctx.gpa);
    const output = firstLine(if (trim(result.stdout).len != 0) result.stdout else result.stderr);
    if (!result.successful()) {
        const detail = if (output.len == 0) "command failed without diagnostic output" else output;
        return ownedNobCheck(ctx.gpa, name, failure_state, try ctx.gpa.dupe(u8, detail));
    }
    return ownedNobCheck(ctx.gpa, name, .ready, try ctx.gpa.dupe(u8, if (output.len == 0) "check passed" else output));
}

fn directoryCheck(io: Io, gpa: Allocator, name: []const u8, path: []const u8) !NobCheck {
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return ownedNobCheck(gpa, name, .warning, try std.fmt.allocPrint(gpa, "{s} does not exist yet; Cloudio will create it on first use", .{path})),
        else => |other| return ownedNobCheck(gpa, name, .@"error", try std.fmt.allocPrint(gpa, "{s} cannot be inspected ({s})", .{ path, @errorName(other) })),
    };
    if (stat.kind != .directory) return ownedNobCheck(gpa, name, .@"error", try std.fmt.allocPrint(gpa, "{s} exists but is not a real directory", .{path}));
    return ownedNobCheck(gpa, name, .ready, try std.fmt.allocPrint(gpa, "{s} is a real directory", .{path}));
}

fn requiredPathCheck(io: Io, gpa: Allocator, name: []const u8, path: []const u8) !NobCheck {
    const present = core_fs.fileExists(io, path) catch |err| {
        return ownedNobCheck(gpa, name, .@"error", try std.fmt.allocPrint(gpa, "{s} cannot be inspected ({s})", .{ path, @errorName(err) }));
    };
    if (!present) return ownedNobCheck(gpa, name, .@"error", try std.fmt.allocPrint(gpa, "{s} is missing", .{path}));
    return ownedNobCheck(gpa, name, .ready, try std.fmt.allocPrint(gpa, "{s} is present", .{path}));
}

fn toolchainsCheck(io: Io, gpa: Allocator, path: []const u8) !NobCheck {
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return ownedNobCheck(gpa, "toolchain-map", .ready, try std.fmt.allocPrint(gpa, "{s} is optional and is not present", .{path})),
        else => |other| return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} cannot be inspected ({s})", .{ path, @errorName(other) })),
    };
    if (stat.kind != .file) return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} is not a regular file", .{path}));
    if (@backingInt(stat.permissions) & 0o022 != 0) return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} is group- or world-writable", .{path}));
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024)) catch |err| {
        return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} cannot be read ({s})", .{ path, @errorName(err) }));
    };
    defer gpa.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, bytes, .{ .allocate = .alloc_always }) catch |err| {
        return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} is not valid JSON ({s})", .{ path, @errorName(err) }));
    };
    defer parsed.deinit();
    if (parsed.value != .object or parsed.value.object.count() != 2) return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} does not match nob.zig/toolchains/v1", .{path}));
    const schema = parsed.value.object.get("schema") orelse return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} has no schema", .{path}));
    const zig = parsed.value.object.get("zig") orelse return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} has no Zig mappings", .{path}));
    if (schema != .string or !std.mem.eql(u8, schema.string, "nob.zig/toolchains/v1") or zig != .object) {
        return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} does not match nob.zig/toolchains/v1", .{path}));
    }
    var mappings = zig.object.iterator();
    while (mappings.next()) |entry| {
        const version = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        if (version.len == 0 or version.len > 128 or value != .string or !std.fs.path.isAbsolute(value.string)) {
            return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "{s} contains an invalid Zig mapping for {s}", .{ path, version }));
        }
        const canonical = Io.Dir.cwd().realPathFileAlloc(io, value.string, gpa) catch |err| {
            return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "Zig {s} cannot be resolved ({s})", .{ version, @errorName(err) }));
        };
        defer gpa.free(canonical);
        const executable = Io.Dir.cwd().statFile(io, canonical, .{ .follow_symlinks = false }) catch |err| {
            return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "Zig {s} cannot be inspected ({s})", .{ version, @errorName(err) }));
        };
        if (executable.kind != .file or @backingInt(executable.permissions) & 0o111 == 0) {
            return ownedNobCheck(gpa, "toolchain-map", .@"error", try std.fmt.allocPrint(gpa, "Zig {s} does not resolve to an executable file", .{version}));
        }
    }
    return ownedNobCheck(gpa, "toolchain-map", .ready, try std.fmt.allocPrint(gpa, "{s} contains {d} pinned Zig toolchain mapping(s)", .{ path, zig.object.count() }));
}

fn appendNobCheck(rows: *std.ArrayList(NobCheck), gpa: Allocator, name: []const u8, state: NobCheckState, detail: []const u8) !void {
    try rows.append(gpa, try ownedNobCheck(gpa, name, state, try gpa.dupe(u8, detail)));
}

fn ownedNobCheck(gpa: Allocator, name: []const u8, state: NobCheckState, owned_detail: []u8) !NobCheck {
    _ = gpa;
    return .{ .name = name, .state = state, .detail = owned_detail };
}

fn hasNobErrors(checks: []const NobCheck) bool {
    for (checks) |check| if (check.state == .@"error") return true;
    return false;
}

fn deinitToolChecks(rows: *std.ArrayList(ToolCheck), gpa: Allocator) void {
    for (rows.items) |check| check.deinit(gpa);
    rows.deinit(gpa);
}

fn deinitNobChecks(rows: *std.ArrayList(NobCheck), gpa: Allocator) void {
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
        .nob_enabled = true,
        .nob_ready = true,
        .nob_allow_system_mutation = false,
        .nob_state_root = "/home/example/.local/state/cloudio/nob/operations",
        .nob_cache_root = "/home/example/.cache/cloudio/nob/runners",
        .nob_toolchains_file = "/home/example/.config/cloudio/nob/toolchains.json",
        .nob_checks = try allocator.dupe(NobCheck, &.{
            .{ .name = "runner-zig", .state = .ready, .detail = try allocator.dupe(u8, "0.17.0-dev") },
            .{ .name = "system-mutation", .state = .disabled, .detail = try allocator.dupe(u8, "blocked by the global kill switch") },
        }),
    };
    defer report.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer);
    try report.writeJson(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio 0.1.0-poc\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "domains: plosca.ru, example.test\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare auth: configured\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger auth: missing\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "nob.zig: enabled; readiness: ready; system mutation: disabled\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "nob runner-zig: ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"kind\":\"doctor\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"domains\":[\"plosca.ru\",\"example.test\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"cloudflare\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"hostinger\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"nob\":{\"enabled\":true,\"ready\":true,\"system_mutation\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"state\":\"disabled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "api_token") == null);
}
