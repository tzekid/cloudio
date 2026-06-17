const std = @import("std");
const core_process = @import("core_process");
const core_redact = @import("core_redact");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

const max_command_bytes = 4 * 1024 * 1024;

pub const Output = struct {
    text: ?[]u8 = null,

    pub fn deinit(self: Output, allocator: Allocator) void {
        if (self.text) |text| allocator.free(text);
    }
};

pub fn collect(io: Io, gpa: Allocator, db: *Db) !void {
    try collectMetrics(io, gpa, db);
    try collectServices(io, gpa, db);
    try collectSockets(io, gpa, db);
    try collectContainers(io, gpa, db);
}

pub fn collectMetrics(io: Io, gpa: Allocator, db: *Db) !void {
    const commands = [_]struct { kind: []const u8, argv: []const []const u8 }{
        .{ .kind = "uname", .argv = &.{ "uname", "-a" } },
        .{ .kind = "hostnamectl", .argv = &.{"hostnamectl"} },
        .{ .kind = "system-running", .argv = &.{ "systemctl", "is-system-running" } },
        .{ .kind = "df", .argv = &.{ "df", "-hP" } },
        .{ .kind = "uptime", .argv = &.{ "uptime", "-p" } },
    };
    for (commands) |command| {
        const result = core_process.run(gpa, io, command.argv, max_command_bytes) catch |err| {
            const summary = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ command.kind, @errorName(err) });
            defer gpa.free(summary);
            _ = try db.insertSnapshot("system", command.kind, null, "error", summary, null, null);
            continue;
        };
        defer result.deinit(gpa);
        const redacted = try core_redact.secrets(gpa, result.stdout);
        defer gpa.free(redacted);
        _ = try db.insertSnapshot("system", command.kind, null, if (result.ok()) "ok" else "error", firstLine(redacted), null, redacted);
    }

    const loadavg_result = core_process.run(gpa, io, &.{ "cat", "/proc/loadavg" }, 1024) catch null;
    if (loadavg_result) |result| {
        defer result.deinit(gpa);
        try db.insertSystemMetric("loadavg", trim(result.stdout), null);
    }
    const meminfo_result = core_process.run(gpa, io, &.{ "cat", "/proc/meminfo" }, 128 * 1024) catch null;
    if (meminfo_result) |result| {
        defer result.deinit(gpa);
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const clean = trim(line);
            if (std.mem.startsWith(u8, clean, "MemTotal:") or std.mem.startsWith(u8, clean, "MemAvailable:") or std.mem.startsWith(u8, clean, "SwapTotal:") or std.mem.startsWith(u8, clean, "SwapFree:")) {
                if (std.mem.indexOfScalar(u8, clean, ':')) |idx| {
                    try db.insertSystemMetric(clean[0..idx], trim(clean[idx + 1 ..]), null);
                }
            }
        }
    }
}

pub fn collectServices(io: Io, gpa: Allocator, db: *Db) !void {
    try db.clear("services");
    const scopes = [_]struct { scope: []const u8, argv: []const []const u8 }{
        .{ .scope = "system", .argv = &.{ "systemctl", "list-units", "--type=service", "--state=running", "--no-pager", "--plain" } },
        .{ .scope = "user", .argv = &.{ "systemctl", "--user", "list-units", "--type=service", "--state=running", "--no-pager", "--plain" } },
    };
    for (scopes) |scope| {
        const result = core_process.run(gpa, io, scope.argv, max_command_bytes) catch continue;
        defer result.deinit(gpa);
        const redacted = try core_redact.secrets(gpa, result.stdout);
        defer gpa.free(redacted);
        _ = try db.insertSnapshot("system", "services", scope.scope, if (result.ok()) "ok" else "error", "running services", null, redacted);
        var lines = std.mem.splitScalar(u8, redacted, '\n');
        while (lines.next()) |line| try persistServiceLine(db, scope.scope, line);
    }
}

pub fn collectSockets(io: Io, gpa: Allocator, db: *Db) !void {
    try db.clear("sockets");
    const result = core_process.run(gpa, io, &.{ "ss", "-tulpen" }, max_command_bytes) catch |err| {
        const summary = try std.fmt.allocPrint(gpa, "ss failed: {s}", .{@errorName(err)});
        defer gpa.free(summary);
        _ = try db.insertSnapshot("system", "sockets", null, "error", summary, null, null);
        return;
    };
    defer result.deinit(gpa);
    const redacted = try core_redact.secrets(gpa, result.stdout);
    defer gpa.free(redacted);
    _ = try db.insertSnapshot("system", "sockets", null, if (result.ok()) "ok" else "error", "listening sockets", null, redacted);
    var lines = std.mem.splitScalar(u8, redacted, '\n');
    while (lines.next()) |line| try persistSocketLine(db, line);
}

pub fn collectContainers(io: Io, gpa: Allocator, db: *Db) !void {
    try db.clear("containers");
    const result = core_process.run(gpa, io, &.{ "docker", "ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" }, max_command_bytes) catch |err| {
        const summary = try std.fmt.allocPrint(gpa, "docker ps failed: {s}", .{@errorName(err)});
        defer gpa.free(summary);
        _ = try db.insertSnapshot("system", "containers", null, "error", summary, null, null);
        return;
    };
    defer result.deinit(gpa);
    const redacted = try core_redact.secrets(gpa, result.stdout);
    defer gpa.free(redacted);
    _ = try db.insertSnapshot("system", "containers", null, if (result.ok()) "ok" else "error", "docker containers", null, redacted);
    var lines = std.mem.splitScalar(u8, redacted, '\n');
    while (lines.next()) |line| try persistContainerLine(db, line);
}

pub fn logs(io: Io, gpa: Allocator, db: *Db, unit: []const u8) !Output {
    const unit_arg = try std.fmt.allocPrint(gpa, "{s}.service", .{unit});
    defer gpa.free(unit_arg);
    const result = try core_process.run(gpa, io, &.{ "journalctl", "-u", unit_arg, "-n", "80", "--no-pager", "--output", "short-iso" }, max_command_bytes);
    defer result.deinit(gpa);

    var raw = std.Io.Writer.Allocating.init(gpa);
    errdefer raw.deinit();
    try raw.writer.writeAll(result.stdout);
    try raw.writer.writeAll(result.stderr);
    const raw_text = try raw.toOwnedSlice();
    defer gpa.free(raw_text);

    const redacted = try core_redact.secrets(gpa, raw_text);
    errdefer gpa.free(redacted);
    _ = try db.insertSnapshot("system", "logs", unit, if (result.ok()) "ok" else "error", "bounded journal read", null, redacted);
    return .{ .text = redacted };
}

fn persistServiceLine(db: *Db, scope: []const u8, line: []const u8) !void {
    const clean = trim(line);
    if (clean.len == 0 or std.mem.startsWith(u8, clean, "UNIT ") or std.mem.startsWith(u8, clean, "Legend:") or std.mem.indexOf(u8, clean, " loaded units listed") != null) return;
    var fields = splitWhitespace(clean);
    const name = fields.next() orelse return;
    if (!std.mem.endsWith(u8, name, ".service")) return;
    const load = fields.next() orelse return;
    _ = load;
    const active = fields.next() orelse null;
    const sub = fields.next() orelse null;
    const desc_start = if (sub) |s| std.mem.indexOf(u8, clean, s) orelse 0 else 0;
    const sub_len = if (sub) |s| s.len else 0;
    const desc = if (desc_start + sub_len < clean.len) trim(clean[desc_start + sub_len ..]) else "";
    try db.upsertService(name, scope, active, sub, desc, clean);
}

fn persistSocketLine(db: *Db, line: []const u8) !void {
    const clean = trim(line);
    if (clean.len == 0 or std.mem.startsWith(u8, clean, "Netid ")) return;
    var fields = splitWhitespace(clean);
    const proto = fields.next();
    const state = fields.next();
    _ = fields.next();
    _ = fields.next();
    const local = fields.next();
    _ = fields.next();
    const process = restAfterNthToken(clean, 6);
    try db.insertSocket(proto, state, local, if (process.len > 0) process else null, clean);
}

fn persistContainerLine(db: *Db, line: []const u8) !void {
    const clean = trim(line);
    if (clean.len == 0) return;
    var fields = std.mem.splitScalar(u8, clean, '\t');
    const name = fields.next() orelse return;
    try db.upsertContainer(name, fields.next(), fields.next(), fields.next(), clean);
    try db.upsertProject(name, "docker", null, null, null, null, name, clean);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn firstLine(value: []const u8) []const u8 {
    const clean = trim(value);
    if (std.mem.indexOfScalar(u8, clean, '\n')) |idx| return clean[0..idx];
    return clean;
}

fn splitWhitespace(value: []const u8) std.mem.TokenIterator(u8, .any) {
    return std.mem.tokenizeAny(u8, value, " \t\r\n");
}

fn restAfterNthToken(value: []const u8, n: usize) []const u8 {
    var seen: usize = 0;
    var in_token = false;
    for (value, 0..) |ch, idx| {
        const ws = ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
        if (!ws and !in_token) {
            in_token = true;
            if (seen == n) return trim(value[idx..]);
            seen += 1;
        } else if (ws) {
            in_token = false;
        }
    }
    return "";
}

test "persists parsed system inventory rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/system.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistServiceLine(&db, "system", "caddy.service loaded active running Caddy web server");
    try persistServiceLine(&db, "system", "ACTIVE = The high-level unit activation state");
    try persistSocketLine(&db, "tcp LISTEN 0 4096 127.0.0.1:443 0.0.0.0:* users:((\"caddy\",pid=1,fd=3))");
    try persistContainerLine(&db, "web\tnginx:latest\tUp 2 hours\t0.0.0.0:80->80/tcp");

    try std.testing.expectEqual(@as(i64, 1), try db.countTable("services"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("sockets"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("containers"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("projects"));
}
