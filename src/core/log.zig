const std = @import("std");
const core_fs = @import("core_fs");
const redact = @import("core_redact");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const RefreshHeader = struct {
    version: []const u8,
    selection: []const u8,
    db_path: []const u8,
    config_path: []const u8,
    loaded_dotenv: bool,
    loaded_fish_env: bool,
    cloudflare_auth: bool,
    hostinger_auth: bool,
};

pub const Buffer = struct {
    out: std.Io.Writer.Allocating,

    pub fn init(allocator: Allocator) Buffer {
        return .{ .out = std.Io.Writer.Allocating.init(allocator) };
    }

    pub fn deinit(self: *Buffer) void {
        self.out.deinit();
    }

    pub fn writer(self: *Buffer) *std.Io.Writer {
        return &self.out.writer;
    }

    pub fn toOwnedSlice(self: *Buffer) ![]u8 {
        return try self.out.toOwnedSlice();
    }
};

pub fn writeRefreshHeader(writer: *std.Io.Writer, header: RefreshHeader) !void {
    try writer.print("cloudio refresh log\nversion={s}\nmode=read-only\nselection={s}\n", .{
        header.version,
        header.selection,
    });
    try writer.print("db={s}\nconfig={s}\ndotenv={s}\ndotenv_fish={s}\ncloudflare_auth={s}\nhostinger_auth={s}\n", .{
        header.db_path,
        header.config_path,
        loadedLabel(header.loaded_dotenv),
        loadedLabel(header.loaded_fish_env),
        configuredLabel(header.cloudflare_auth),
        configuredLabel(header.hostinger_auth),
    });
}

pub fn writeRedactedFile(io: Io, allocator: Allocator, path: []const u8, bytes: []const u8) !void {
    try core_fs.ensureParentDir(io, path);
    const redacted = try redact.secrets(allocator, bytes);
    defer allocator.free(redacted);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = redacted });
}

pub fn readRedactedFile(io: Io, allocator: Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const text = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes));
    defer allocator.free(text);
    return try redact.secrets(allocator, text);
}

fn loadedLabel(value: bool) []const u8 {
    return if (value) "loaded" else "missing";
}

fn configuredLabel(value: bool) []const u8 {
    return if (value) "configured" else "missing";
}

test "refresh header uses stable labels" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.init(allocator);
    defer buffer.deinit();

    try writeRefreshHeader(buffer.writer(), .{
        .version = "0.1.0-poc",
        .selection = "selected",
        .db_path = ".cloudio/cloudio.db",
        .config_path = "cloudio.local.toml",
        .loaded_dotenv = true,
        .loaded_fish_env = false,
        .cloudflare_auth = true,
        .hostinger_auth = false,
    });

    const text = try buffer.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "mode=read-only\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "selection=selected\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dotenv=loaded\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dotenv_fish=missing\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare_auth=configured\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger_auth=missing\n") != null);
}

test "redacted file io never returns secret-like values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/latest-run.log", .{tmp.sub_path});
    defer allocator.free(path);

    try writeRedactedFile(std.testing.io, allocator, path, "Authorization: Bearer abc123\nnormal=value\n");
    const text = try readRedactedFile(std.testing.io, allocator, path, 1024);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "abc123") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "normal=value") != null);
}
