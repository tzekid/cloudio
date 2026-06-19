const std = @import("std");
const app_render = @import("app_render");
const core_config = @import("core_config");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Db = db_store.Db;
const Io = std.Io;

pub const default_log_scan_bytes = 8 * 1024 * 1024;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    config: Config,
    db: *Db,
};

pub const Options = struct {
    max_log_bytes: usize = default_log_scan_bytes,
};

const SecretProbe = struct {
    label: []const u8,
    value: []const u8,
};

pub const Finding = struct {
    secret_label: []const u8,
    surface: []const u8,
    count: i64,
};

pub const Report = struct {
    probe_count: usize,
    checked_surfaces: usize,
    run_log_checked: bool,
    findings: []Finding,

    pub fn deinit(self: *Report, gpa: Allocator) void {
        gpa.free(self.findings);
    }

    pub fn status(self: Report) []const u8 {
        if (self.probe_count == 0) return "no_secret_probes";
        if (self.findings.len != 0) return "leak_detected";
        return "ok";
    }

    pub fn totalMatches(self: Report) i64 {
        var total: i64 = 0;
        for (self.findings) |finding| total += finding.count;
        return total;
    }

    pub fn writeText(self: Report, writer: anytype) !void {
        try writer.writeAll("Cloudio redaction audit\n");
        try writer.print("status={s} probes={d} checked_surfaces={d} findings={d} matches={d} run_log={s}\n", .{
            self.status(),
            self.probe_count,
            self.checked_surfaces,
            self.findings.len,
            self.totalMatches(),
            if (self.run_log_checked) "checked" else "missing",
        });
        if (self.probe_count == 0) {
            try writer.writeAll("no configured API tokens or keys available as audit probes\n");
            return;
        }
        if (self.findings.len == 0) {
            try writer.writeAll("no configured secret bytes found in Cloudio output storage\n");
            return;
        }
        for (self.findings) |finding| {
            try writer.print("{s}\t{s}\tcount={d}\n", .{ finding.secret_label, finding.surface, finding.count });
        }
    }

    pub fn writeJson(self: Report, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"redaction_audit\",");
        try app_render.writeJsonStringField(writer, "status", self.status(), true);
        try app_render.writeJsonIntField(writer, "probes", self.probe_count, true);
        try app_render.writeJsonIntField(writer, "checked_surfaces", self.checked_surfaces, true);
        try app_render.writeJsonBoolField(writer, "run_log_checked", self.run_log_checked, true);
        try app_render.writeJsonIntField(writer, "matches", self.totalMatches(), true);
        try writer.writeAll("\"findings\":[");
        for (self.findings, 0..) |finding, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try app_render.writeJsonStringField(writer, "secret", finding.secret_label, true);
            try app_render.writeJsonStringField(writer, "surface", finding.surface, true);
            try app_render.writeJsonIntField(writer, "count", finding.count, false);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}\n");
    }
};

pub fn collect(ctx: Context, options: Options) !Report {
    const probes = try configuredSecretProbes(ctx.gpa, ctx.config);
    defer ctx.gpa.free(probes);

    var findings = std.ArrayList(Finding).empty;
    errdefer findings.deinit(ctx.gpa);

    for (probes) |probe| {
        for (db_store.secret_scan_surfaces) |surface| {
            const count = try ctx.db.countSecretNeedle(surface, probe.value);
            if (count > 0) {
                try findings.append(ctx.gpa, .{
                    .secret_label = probe.label,
                    .surface = surface.label(),
                    .count = count,
                });
            }
        }
    }

    const run_log_checked = try scanRunLog(ctx, options, probes, &findings);

    return .{
        .probe_count = probes.len,
        .checked_surfaces = db_store.secret_scan_surfaces.len + @intFromBool(run_log_checked),
        .run_log_checked = run_log_checked,
        .findings = try findings.toOwnedSlice(ctx.gpa),
    };
}

pub fn writeText(ctx: Context, options: Options, writer: anytype) !void {
    var report = try collect(ctx, options);
    defer report.deinit(ctx.gpa);
    try report.writeText(writer);
}

pub fn writeJson(ctx: Context, options: Options, writer: anytype) !void {
    var report = try collect(ctx, options);
    defer report.deinit(ctx.gpa);
    try report.writeJson(writer);
}

fn configuredSecretProbes(gpa: Allocator, config: Config) ![]SecretProbe {
    var probes = std.ArrayList(SecretProbe).empty;
    errdefer probes.deinit(gpa);
    try appendProbe(gpa, &probes, "cloudflare_api_token", config.cloudflare_api_token);
    try appendProbe(gpa, &probes, "cloudflare_api_key", config.cloudflare_api_key);
    try appendProbe(gpa, &probes, "hostinger_api_token", config.hostinger_api_token);
    return try probes.toOwnedSlice(gpa);
}

fn appendProbe(gpa: Allocator, probes: *std.ArrayList(SecretProbe), label: []const u8, value_opt: ?[]const u8) !void {
    const value = value_opt orelse return;
    if (value.len < 8 or std.mem.eql(u8, value, "[REDACTED]")) return;
    for (probes.items) |existing| {
        if (std.mem.eql(u8, existing.value, value)) return;
    }
    try probes.append(gpa, .{ .label = label, .value = value });
}

fn scanRunLog(ctx: Context, options: Options, probes: []const SecretProbe, findings: *std.ArrayList(Finding)) !bool {
    const text = Io.Dir.cwd().readFileAlloc(ctx.io, ctx.config.log_path, ctx.gpa, .limited(options.max_log_bytes)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    defer ctx.gpa.free(text);

    for (probes) |probe| {
        const count = countOccurrences(text, probe.value);
        if (count > 0) {
            try findings.append(ctx.gpa, .{
                .secret_label = probe.label,
                .surface = "run_log.file",
                .count = @intCast(count),
            });
        }
    }
    return true;
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0 or needle.len > haystack.len) return 0;
    var count: usize = 0;
    var start: usize = 0;
    while (std.mem.indexOf(u8, haystack[start..], needle)) |relative| {
        count += 1;
        start += relative + needle.len;
        if (start >= haystack.len) break;
    }
    return count;
}

test "security audit reports configured secret leaks without printing secret bytes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-security.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    const log_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/latest-run.log", .{tmp.sub_path});
    defer allocator.free(log_path);

    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const secret = "top-secret-token-value";
    _ = try db.insertSnapshot("hostinger", "raw", "/api/vps", "ok", "safe summary", "{\"token\":\"top-secret-token-value\"}", null);
    try Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = log_path, .data = "leaked top-secret-token-value\n" });

    const domains = [_][]const u8{"plosca.ru"};
    const config = Config{
        .db_path = db_path,
        .log_path = log_path,
        .domains = domains[0..],
        .hostinger_api_token = secret,
    };
    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .config = config, .db = &db };

    var report = try collect(ctx, .{});
    defer report.deinit(allocator);
    try std.testing.expectEqualStrings("leak_detected", report.status());
    try std.testing.expectEqual(@as(usize, 1), report.probe_count);
    try std.testing.expectEqual(@as(usize, 2), report.findings.len);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer);
    try report.writeJson(&out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, secret) == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger_api_token") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "snapshots.raw_json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "run_log.file") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"kind\":\"redaction_audit\"") != null);
}
