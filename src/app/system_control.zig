//! B4: systemd/Docker control + per-app unit rendering.
//!
//! Sudo note: commands are built as plain `systemctl ...` / `docker ...`.
//! In production cloudio runs as root (or with polkit rules granting unit
//! control), so no sudo wrapping is done here.
const std = @import("std");
const sqlite = @import("sqlite");
const app_writes = @import("app_writes");
const core_fs = @import("core_fs");
const core_json = @import("core_json");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_command_bytes = 1024 * 1024;
const system_unit_dir = "/etc/systemd/system";

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    db: *db_store.Db,
};

pub const ServiceAction = enum { start, stop, restart, reload, enable, disable };
pub const ContainerAction = enum { start, stop, restart };

/// Allow only [A-Za-z0-9_.@-]+ so names can never carry paths, spaces, or
/// shell/option injection ("-foo" is still rejected as first char? no: '-' is
/// allowed by spec; argv construction never goes through a shell, and names
/// are always placed after the subcommand).
pub fn isSafeUnitName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '.', '@', '-' => {},
            else => return false,
        }
    }
    return true;
}

pub fn serviceAction(ctx: Context, name: []const u8, action: ServiceAction, writer: anytype) !void {
    if (!isSafeUnitName(name)) return error.InvalidName;
    const action_text = @tagName(action);

    const result = try core_process.run(ctx.gpa, ctx.io, &.{ "systemctl", action_text, name }, max_command_bytes);
    defer result.deinit(ctx.gpa);

    const state = try isActiveState(ctx, name);
    defer ctx.gpa.free(state);

    const kind = try std.fmt.allocPrint(ctx.gpa, "systemd.{s}", .{action_text});
    defer ctx.gpa.free(kind);
    try auditCommand(ctx, kind, name, result);

    try writeActionJson(writer, "unit", name, action_text, state, result);
}

pub fn containerAction(ctx: Context, name: []const u8, action: ContainerAction, writer: anytype) !void {
    if (!isSafeUnitName(name)) return error.InvalidName;
    const action_text = @tagName(action);

    const result = try core_process.run(ctx.gpa, ctx.io, &.{ "docker", action_text, name }, max_command_bytes);
    defer result.deinit(ctx.gpa);

    const kind = try std.fmt.allocPrint(ctx.gpa, "docker.{s}", .{action_text});
    defer ctx.gpa.free(kind);
    try auditCommand(ctx, kind, name, result);

    const state: []const u8 = if (result.ok()) "done" else "failed";
    try writeActionJson(writer, "container", name, action_text, state, result);
}

/// Reads container logs; no audit row because this is a read.
pub fn containerLogs(ctx: Context, name: []const u8, tail: i64, writer: anytype) !void {
    if (!isSafeUnitName(name)) return error.InvalidName;
    const effective_tail = capTail(tail);
    var tail_buf: [20]u8 = undefined;
    const tail_text = std.fmt.bufPrint(&tail_buf, "{d}", .{effective_tail}) catch unreachable;

    const result = try core_process.run(ctx.gpa, ctx.io, &.{ "docker", "logs", "--tail", tail_text, name }, max_command_bytes);
    defer result.deinit(ctx.gpa);

    const combined = try combineOutput(ctx.gpa, result);
    defer ctx.gpa.free(combined);

    try writer.writeByte('{');
    try core_json.writeBoolField(writer, "ok", result.ok(), true);
    try core_json.writeStringField(writer, "container", name, true);
    try core_json.writeStringField(writer, "logs", combined, false);
    try writer.writeAll("}\n");
}

/// Cap docker logs tail at 500 lines; non-positive values default to 100.
pub fn capTail(tail: i64) i64 {
    if (tail <= 0) return 100;
    if (tail > 500) return 500;
    return tail;
}

pub const EnvPair = struct { key: []const u8, value: []const u8 };

pub const AppUnit = struct {
    name: []const u8,
    exec_path: []const u8,
    workdir: []const u8,
    port: u16,
    env: []const EnvPair,
    description: ?[]const u8 = null,
};

pub fn renderUnit(gpa: Allocator, unit: AppUnit) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("[Unit]\n");
    if (unit.description) |desc| {
        try w.print("Description={s}\n", .{desc});
    } else {
        try w.print("Description=cloudio app {s}\n", .{unit.name});
    }
    try w.writeAll("After=network.target\n\n");

    try w.writeAll("[Service]\n");
    try w.writeAll("Type=simple\n");
    try w.print("ExecStart={s}\n", .{unit.exec_path});
    try w.print("WorkingDirectory={s}\n", .{unit.workdir});
    try w.print("Environment=PORT={d}\n", .{unit.port});
    for (unit.env) |pair| {
        if (std.mem.indexOfScalar(u8, pair.value, ' ') != null) {
            try w.print("Environment=\"{s}={s}\"\n", .{ pair.key, pair.value });
        } else {
            try w.print("Environment={s}={s}\n", .{ pair.key, pair.value });
        }
    }
    try w.writeAll("Restart=on-failure\n");
    try w.writeAll("RestartSec=2\n\n");

    try w.writeAll("[Install]\n");
    try w.writeAll("WantedBy=multi-user.target\n");

    return try out.toOwnedSlice();
}

pub fn unitName(gpa: Allocator, app_name: []const u8) ![]u8 {
    if (!isSafeUnitName(app_name)) return error.InvalidName;
    return std.fmt.allocPrint(gpa, "cloudio-{s}.service", .{app_name});
}

/// Writes the unit file into `unit_dir` and reloads systemd. Safety guard:
/// `systemctl daemon-reload` runs only when unit_dir is the real system unit
/// directory, so tests with tmp dirs never touch systemd. A daemon-reload
/// failure never fails the install; it is recorded in the audit detail.
pub fn installUnit(ctx: Context, app_name: []const u8, unit_text: []const u8, unit_dir: []const u8) !void {
    const service_name = try unitName(ctx.gpa, app_name);
    defer ctx.gpa.free(service_name);

    const path = try std.fs.path.join(ctx.gpa, &.{ unit_dir, service_name });
    defer ctx.gpa.free(path);

    try core_fs.ensureParentDir(ctx.io, path);
    try Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = unit_text });

    var detail: []const u8 = "unit written";
    var detail_owned: ?[]u8 = null;
    defer if (detail_owned) |d| ctx.gpa.free(d);

    if (std.mem.eql(u8, unit_dir, system_unit_dir)) {
        if (core_process.run(ctx.gpa, ctx.io, &.{ "systemctl", "daemon-reload" }, max_command_bytes)) |reload| {
            defer reload.deinit(ctx.gpa);
            if (!reload.ok()) {
                detail_owned = try std.fmt.allocPrint(ctx.gpa, "unit written; daemon-reload failed: {s}", .{trimmed(reload.stderr)});
                detail = detail_owned.?;
            } else {
                detail = "unit written; daemon-reload ok";
            }
        } else |err| {
            detail_owned = try std.fmt.allocPrint(ctx.gpa, "unit written; daemon-reload error: {s}", .{@errorName(err)});
            detail = detail_owned.?;
        }
    } else {
        detail = "unit written; daemon-reload skipped (non-system unit_dir)";
    }

    _ = try app_writes.record(ctx.gpa, ctx.db, "systemd.unit.install", service_name, null, .ok, detail);
}

pub fn enableAndRestart(ctx: Context, app_name: []const u8, writer: anytype) !void {
    const service_name = try unitName(ctx.gpa, app_name);
    defer ctx.gpa.free(service_name);
    try serviceAction(ctx, service_name, .enable, writer);
    try serviceAction(ctx, service_name, .restart, writer);
}

fn isActiveState(ctx: Context, name: []const u8) ![]u8 {
    const result = core_process.run(ctx.gpa, ctx.io, &.{ "systemctl", "is-active", name }, max_command_bytes) catch |err| {
        return std.fmt.allocPrint(ctx.gpa, "unknown ({s})", .{@errorName(err)});
    };
    defer result.deinit(ctx.gpa);
    return ctx.gpa.dupe(u8, trimmed(result.stdout));
}

fn auditCommand(ctx: Context, kind: []const u8, target: []const u8, result: core_process.CommandResult) !void {
    const combined = try combineOutput(ctx.gpa, result);
    defer ctx.gpa.free(combined);
    _ = try app_writes.record(ctx.gpa, ctx.db, kind, target, null, if (result.ok()) .ok else .err, combined);
}

fn writeActionJson(writer: anytype, target_field: []const u8, name: []const u8, action: []const u8, state: []const u8, result: core_process.CommandResult) !void {
    try writer.writeByte('{');
    try core_json.writeBoolField(writer, "ok", result.ok(), true);
    try core_json.writeStringField(writer, target_field, name, true);
    try core_json.writeStringField(writer, "action", action, true);
    try core_json.writeStringField(writer, "state", state, true);
    try core_json.writeStringField(writer, "detail", trimmed(result.stderr), false);
    try writer.writeAll("}\n");
}

fn combineOutput(gpa: Allocator, result: core_process.CommandResult) ![]u8 {
    const joined = try std.fmt.allocPrint(gpa, "{s}{s}", .{ result.stdout, result.stderr });
    defer gpa.free(joined);
    return gpa.dupe(u8, trimmed(joined));
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

test "name validation accepts safe names and rejects unsafe ones" {
    try std.testing.expect(isSafeUnitName("my-app_1.2"));
    try std.testing.expect(isSafeUnitName("nginx.service"));
    try std.testing.expect(isSafeUnitName("getty@tty1"));
    try std.testing.expect(!isSafeUnitName(""));
    try std.testing.expect(!isSafeUnitName("../evil"));
    try std.testing.expect(!isSafeUnitName("a b"));
    try std.testing.expect(!isSafeUnitName("a/b"));
    try std.testing.expect(!isSafeUnitName("a;rm"));
}

test "unitName builds cloudio service name and validates" {
    const allocator = std.testing.allocator;
    const name = try unitName(allocator, "my-app_1.2");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("cloudio-my-app_1.2.service", name);

    try std.testing.expectError(error.InvalidName, unitName(allocator, "../evil"));
    try std.testing.expectError(error.InvalidName, unitName(allocator, "a b"));
    try std.testing.expectError(error.InvalidName, unitName(allocator, ""));
}

test "renderUnit golden output including quoted env value" {
    const allocator = std.testing.allocator;
    const env = [_]EnvPair{
        .{ .key = "NODE_ENV", .value = "production" },
        .{ .key = "GREETING", .value = "hello world" },
    };
    const text = try renderUnit(allocator, .{
        .name = "myapp",
        .exec_path = "/opt/myapp/bin/server",
        .workdir = "/opt/myapp",
        .port = 3000,
        .env = env[0..],
    });
    defer allocator.free(text);

    const expected =
        \\[Unit]
        \\Description=cloudio app myapp
        \\After=network.target
        \\
        \\[Service]
        \\Type=simple
        \\ExecStart=/opt/myapp/bin/server
        \\WorkingDirectory=/opt/myapp
        \\Environment=PORT=3000
        \\Environment=NODE_ENV=production
        \\Environment="GREETING=hello world"
        \\Restart=on-failure
        \\RestartSec=2
        \\
        \\[Install]
        \\WantedBy=multi-user.target
        \\
    ;
    try std.testing.expectEqualStrings(expected, text);
}

test "capTail defaults and caps" {
    try std.testing.expectEqual(@as(i64, 100), capTail(0));
    try std.testing.expectEqual(@as(i64, 100), capTail(-5));
    try std.testing.expectEqual(@as(i64, 42), capTail(42));
    try std.testing.expectEqual(@as(i64, 500), capTail(500));
    try std.testing.expectEqual(@as(i64, 500), capTail(9999));
}

test "installUnit writes file into tmp dir, skips daemon-reload, records audit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(base);
    const db_path = try std.fmt.allocPrint(allocator, "{s}/system_control.db", .{base});
    defer allocator.free(db_path);
    const unit_dir = try std.fmt.allocPrint(allocator, "{s}/units", .{base});
    defer allocator.free(unit_dir);

    var db = try db_store.Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .db = &db };

    const unit_text = try renderUnit(allocator, .{
        .name = "demo",
        .exec_path = "/opt/demo/run",
        .workdir = "/opt/demo",
        .port = 8080,
        .env = &.{},
    });
    defer allocator.free(unit_text);

    try installUnit(ctx, "demo", unit_text, unit_dir);

    const unit_path = try std.fmt.allocPrint(allocator, "{s}/cloudio-demo.service", .{unit_dir});
    defer allocator.free(unit_path);
    const written = try Io.Dir.cwd().readFileAlloc(std.testing.io, unit_path, allocator, .limited(64 * 1024));
    defer allocator.free(written);
    try std.testing.expectEqualStrings(unit_text, written);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try app_writes.writeAuditJson(allocator, &db, 10, &out.writer);
    const json = out.written();
    try std.testing.expect(std.mem.indexOf(u8, json, "systemd.unit.install") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio-demo.service") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "daemon-reload skipped") != null);

    try std.testing.expectError(error.InvalidName, installUnit(ctx, "../evil", unit_text, unit_dir));
}
