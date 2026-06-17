const std = @import("std");
const core_process = @import("core_process");
const core_redact = @import("core_redact");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;

const max_file_bytes = 8 * 1024 * 1024;
const max_command_bytes = 4 * 1024 * 1024;
const runCommand = core_process.run;

pub const Paths = struct {
    caddyfile_path: []const u8,
    caddy_sites_path: []const u8,
    caddy_admin_socket: []const u8,
};

pub const Output = struct {
    text: ?[]u8 = null,

    pub fn deinit(self: Output, allocator: Allocator) void {
        if (self.text) |text| allocator.free(text);
    }
};

pub const Site = struct {
    host: []const u8,
    raw_block: []const u8,
    upstreams: std.ArrayList([]const u8),
};

pub const Sites = struct {
    items: []Site,

    pub fn deinit(self: *Sites, allocator: Allocator) void {
        for (self.items) |*site| {
            allocator.free(site.host);
            allocator.free(site.raw_block);
            for (site.upstreams.items) |upstream| allocator.free(upstream);
            site.upstreams.deinit(allocator);
        }
        allocator.free(self.items);
    }
};

pub fn collect(io: Io, gpa: Allocator, paths: Paths, db: *Db) !void {
    try db.clear("caddy_sites");
    try db.clear("caddy_upstreams");

    if (try readFileMaybe(io, gpa, paths.caddyfile_path, max_file_bytes)) |caddyfile| {
        defer gpa.free(caddyfile);
        const redacted = try core_redact.secrets(gpa, caddyfile);
        defer gpa.free(redacted);
        _ = try db.insertSnapshot("caddy", "caddyfile", paths.caddyfile_path, "ok", "root Caddyfile", null, redacted);
    }

    var sites = try parseSitesFromFile(io, gpa, paths.caddy_sites_path);
    defer sites.deinit(gpa);
    for (sites.items) |site| {
        const redacted_block = try core_redact.secrets(gpa, site.raw_block);
        defer gpa.free(redacted_block);
        try db.upsertCaddySite(site.host, paths.caddy_sites_path, redacted_block);
        for (site.upstreams.items) |upstream| try db.insertCaddyUpstream(site.host, "", upstream);
        try db.upsertProject(projectNameFromHost(site.host), "caddy", null, site.host, if (site.upstreams.items.len > 0) site.upstreams.items[0] else null, null, null, null);
    }

    const adapt_result = runCommand(gpa, io, &.{ "caddy", "adapt", "--config", paths.caddyfile_path, "--pretty" }, max_command_bytes) catch |err| {
        const summary = try std.fmt.allocPrint(gpa, "caddy adapt failed: {s}", .{@errorName(err)});
        defer gpa.free(summary);
        _ = try db.insertSnapshot("caddy", "adapt", paths.caddyfile_path, "error", summary, null, null);
        return;
    };
    defer adapt_result.deinit(gpa);
    const adapted = try core_redact.secrets(gpa, adapt_result.stdout);
    defer gpa.free(adapted);
    const adapt_stderr = try core_redact.secrets(gpa, adapt_result.stderr);
    defer gpa.free(adapt_stderr);
    _ = try db.insertSnapshot("caddy", "adapt", paths.caddyfile_path, if (adapt_result.ok()) "ok" else "error", "adapted Caddy JSON", adapted, adapt_stderr);

    const api = runCommand(gpa, io, &.{ "curl", "-sS", "--max-time", "5", "--unix-socket", paths.caddy_admin_socket, "http://localhost/config/" }, max_command_bytes) catch |err| {
        const summary = try std.fmt.allocPrint(gpa, "caddy admin unavailable: {s}", .{@errorName(err)});
        defer gpa.free(summary);
        _ = try db.insertSnapshot("caddy", "admin", paths.caddy_admin_socket, "skipped", summary, null, null);
        return;
    };
    defer api.deinit(gpa);
    const api_text = try core_redact.secrets(gpa, api.stdout);
    defer gpa.free(api_text);
    const api_stderr = try core_redact.secrets(gpa, api.stderr);
    defer gpa.free(api_stderr);
    _ = try db.insertSnapshot("caddy", "admin", paths.caddy_admin_socket, if (api.ok()) "ok" else "error", "runtime config from admin socket", api_text, api_stderr);
}

pub fn render(io: Io, gpa: Allocator, paths: Paths) !Output {
    const result = try runCommand(gpa, io, &.{ "caddy", "adapt", "--config", paths.caddyfile_path, "--pretty" }, max_command_bytes);
    defer result.deinit(gpa);
    const redacted = try core_redact.secrets(gpa, result.stdout);
    return .{ .text = redacted };
}

pub fn validate(io: Io, gpa: Allocator, paths: Paths) !Output {
    const result = try runCommand(gpa, io, &.{ "caddy", "validate", "--config", paths.caddyfile_path }, max_command_bytes);
    defer result.deinit(gpa);
    const stdout = try core_redact.secrets(gpa, result.stdout);
    defer gpa.free(stdout);
    const stderr = try core_redact.secrets(gpa, result.stderr);
    defer gpa.free(stderr);
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(stdout);
    try out.writer.writeAll(stderr);
    if (!result.ok()) try out.writer.writeAll("validation failed; no config was changed\n");
    return .{ .text = try out.toOwnedSlice() };
}

pub fn diff(io: Io, gpa: Allocator, paths: Paths) !Output {
    const validate_result = try runCommand(gpa, io, &.{ "caddy", "validate", "--config", paths.caddyfile_path }, max_command_bytes);
    defer validate_result.deinit(gpa);
    const adapt_result = try runCommand(gpa, io, &.{ "caddy", "adapt", "--config", paths.caddyfile_path, "--pretty" }, max_command_bytes);
    defer adapt_result.deinit(gpa);

    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    const api = runCommand(gpa, io, &.{ "curl", "-sS", "--max-time", "5", "--unix-socket", paths.caddy_admin_socket, "http://localhost/config/" }, max_command_bytes) catch |err| {
        try out.writer.print("dry-run: caddy validate {s}; adapted config bytes={d}; runtime admin unavailable: {s}\n", .{ validate_result.statusText(), adapt_result.stdout.len, @errorName(err) });
        if (!validate_result.ok()) {
            const stderr = try core_redact.secrets(gpa, validate_result.stderr);
            defer gpa.free(stderr);
            try out.writer.print("validation stderr: {s}\n", .{lastLine(stderr)});
        }
        return .{ .text = try out.toOwnedSlice() };
    };
    defer api.deinit(gpa);

    try out.writer.print("dry-run: caddy validate {s}; adapted config bytes={d}; runtime config bytes={d}; no files written and no reload issued\n", .{ validate_result.statusText(), adapt_result.stdout.len, api.stdout.len });
    if (!validate_result.ok()) {
        const stderr = try core_redact.secrets(gpa, validate_result.stderr);
        defer gpa.free(stderr);
        try out.writer.print("validation stderr: {s}\n", .{lastLine(stderr)});
    }
    return .{ .text = try out.toOwnedSlice() };
}

pub fn parseSitesFromFile(io: Io, gpa: Allocator, path: []const u8) !Sites {
    const raw = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_bytes));
    defer gpa.free(raw);
    return parseSites(gpa, raw);
}

pub fn parseSites(gpa: Allocator, raw: []const u8) !Sites {
    var sites = std.ArrayList(Site).empty;
    errdefer {
        for (sites.items) |*site| site.upstreams.deinit(gpa);
        sites.deinit(gpa);
    }

    var depth: i32 = 0;
    var current_host: ?[]const u8 = null;
    var block = std.ArrayList(u8).empty;
    defer block.deinit(gpa);
    var upstreams = std.ArrayList([]const u8).empty;
    errdefer upstreams.deinit(gpa);

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = trim(line_raw);
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        if (depth == 0 and std.mem.endsWith(u8, line, "{")) {
            const candidate = trim(line[0 .. line.len - 1]);
            if (isLikelyHost(candidate)) {
                current_host = try gpa.dupe(u8, candidate);
                block.clearRetainingCapacity();
                upstreams = .empty;
            }
        }
        if (current_host != null) {
            try block.appendSlice(gpa, line_raw);
            try block.append(gpa, '\n');
            if (std.mem.indexOf(u8, line, "reverse_proxy")) |idx| {
                const rest = trim(line[idx + "reverse_proxy".len ..]);
                const upstream = firstToken(rest);
                if (upstream.len > 0 and !std.mem.eql(u8, upstream, "{")) {
                    try upstreams.append(gpa, try gpa.dupe(u8, upstream));
                }
            }
        }
        depth += @intCast(countByte(line, '{'));
        depth -= @intCast(countByte(line, '}'));
        if (depth == 0 and current_host != null) {
            const owned_block = try block.toOwnedSlice(gpa);
            try sites.append(gpa, .{
                .host = current_host.?,
                .raw_block = owned_block,
                .upstreams = upstreams,
            });
            current_host = null;
            block = .empty;
            upstreams = .empty;
        }
    }
    return .{ .items = try sites.toOwnedSlice(gpa) };
}

fn readFileMaybe(io: Io, allocator: Allocator, path: []const u8, max_bytes: usize) !?[]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |e| return e,
    };
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn lastLine(value: []const u8) []const u8 {
    const clean = trim(value);
    if (clean.len == 0) return "";
    if (std.mem.lastIndexOfScalar(u8, clean, '\n')) |idx| return trim(clean[idx + 1 ..]);
    return clean;
}

fn firstToken(value: []const u8) []const u8 {
    var it = splitWhitespace(value);
    return it.next() orelse "";
}

fn splitWhitespace(value: []const u8) std.mem.TokenIterator(u8, .any) {
    return std.mem.tokenizeAny(u8, value, " \t\r\n");
}

fn countByte(value: []const u8, needle: u8) usize {
    var count: usize = 0;
    for (value) |ch| {
        if (ch == needle) count += 1;
    }
    return count;
}

fn isLikelyHost(candidate: []const u8) bool {
    if (candidate.len == 0) return false;
    if (std.mem.indexOfScalar(u8, candidate, ' ') != null) return false;
    if (std.mem.startsWith(u8, candidate, "http://") or std.mem.startsWith(u8, candidate, "https://")) return true;
    return std.mem.indexOfScalar(u8, candidate, '.') != null or std.mem.indexOfScalar(u8, candidate, ':') != null;
}

fn projectNameFromHost(host: []const u8) []const u8 {
    if (std.mem.startsWith(u8, host, "www.")) return host[4..];
    return host;
}

test "caddy parser extracts hosts and upstreams" {
    const allocator = std.testing.allocator;
    var parsed = try parseSites(allocator,
        \\app.example.com {
        \\  encode zstd gzip
        \\  reverse_proxy 127.0.0.1:3000
        \\}
        \\
        \\www.example.com {
        \\  redir https://example.com{uri} permanent
        \\}
    );
    defer parsed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), parsed.items.len);
    try std.testing.expectEqualStrings("app.example.com", parsed.items[0].host);
    try std.testing.expectEqualStrings("127.0.0.1:3000", parsed.items[0].upstreams.items[0]);
}

test "persists parsed caddy routes and projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/caddy.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var parsed = try parseSites(allocator,
        \\www.example.com {
        \\  reverse_proxy 127.0.0.1:3000
        \\}
    );
    defer parsed.deinit(allocator);
    for (parsed.items) |site| {
        try db.upsertCaddySite(site.host, "/tmp/sites.caddy", site.raw_block);
        for (site.upstreams.items) |upstream| try db.insertCaddyUpstream(site.host, "", upstream);
        try db.upsertProject(projectNameFromHost(site.host), "caddy", null, site.host, if (site.upstreams.items.len > 0) site.upstreams.items[0] else null, null, null, null);
    }

    try std.testing.expectEqual(@as(i64, 1), try db.countTable("caddy_sites"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("caddy_upstreams"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("projects"));
}
