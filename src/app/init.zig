const std = @import("std");
const core_config = @import("core_config");
const core_fs = @import("core_fs");

const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    config: Config,
};

pub const Result = struct {
    config_path: []const u8,
    config_created: bool,
    db_path: []const u8,
    cwd: [:0]u8,

    pub fn deinit(self: Result, gpa: Allocator) void {
        gpa.free(self.cwd);
    }

    pub fn writeText(self: Result, writer: anytype) !void {
        if (self.config_created) {
            try writer.print("created sample config: {s}\n", .{self.config_path});
        } else {
            try writer.print("config already exists: {s}\n", .{self.config_path});
        }
        try writer.print("database ready: {s}/{s}\n", .{ self.cwd, self.db_path });
    }
};

pub fn run(ctx: Context) !Result {
    const cfg = ctx.config;
    try core_fs.ensureParentDir(ctx.io, cfg.db_path);

    const config_created = !try core_fs.fileExists(ctx.io, cfg.config_path);
    if (config_created) {
        try core_fs.ensureParentDir(ctx.io, cfg.config_path);
        try Io.Dir.cwd().writeFile(ctx.io, .{
            .sub_path = cfg.config_path,
            .data = sampleConfig,
        });
    }

    return .{
        .config_path = cfg.config_path,
        .config_created = config_created,
        .db_path = cfg.db_path,
        .cwd = try std.process.currentPathAlloc(ctx.io, ctx.gpa),
    };
}

pub fn writeText(ctx: Context, writer: anytype) !void {
    const result = try run(ctx);
    defer result.deinit(ctx.gpa);
    try result.writeText(writer);
}

pub const sampleConfig =
    \\db_path = ".cloudio/cloudio.db"
    \\log_path = ".cloudio/latest-run.log"
    \\domains = "plosca.ru"
    \\projects_root = "/home/kid/Projects"
    \\
    \\[cloudflare]
    \\api_token = ""
    \\# email = ""
    \\# api_key = ""
    \\
    \\[hostinger]
    \\api_token = ""
    \\
;

test "init creates sample config once and reports existing config later" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/nested/cloudio.local.toml", .{tmp.sub_path});
    defer allocator.free(config_path);
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/.cloudio/cloudio.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    const domains = [_][]const u8{"plosca.ru"};
    const cfg = Config{
        .db_path = db_path,
        .config_path = config_path,
        .domains = domains[0..],
    };

    var created = try run(.{ .io = std.testing.io, .gpa = allocator, .config = cfg });
    defer created.deinit(allocator);
    try std.testing.expect(created.config_created);

    const text = try Io.Dir.cwd().readFileAlloc(std.testing.io, config_path, allocator, .limited(sampleConfig.len + 1));
    defer allocator.free(text);
    try std.testing.expectEqualStrings(sampleConfig, text);

    var existing = try run(.{ .io = std.testing.io, .gpa = allocator, .config = cfg });
    defer existing.deinit(allocator);
    try std.testing.expect(!existing.config_created);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try existing.writeText(&out.writer);
    const output = try out.toOwnedSlice();
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "config already exists: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "database ready: ") != null);
}
