const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_config_bytes = 256 * 1024;

pub const Config = struct {
    db_path: []const u8 = ".cloudio/cloudio.db",
    log_path: []const u8 = ".cloudio/latest-run.log",
    config_path: []const u8 = "cloudio.local.toml",
    loaded_dotenv: bool = false,
    loaded_fish_env: bool = false,
    domains: []const []const u8,
    caddyfile_path: []const u8 = "/etc/caddy/Caddyfile",
    caddy_sites_path: []const u8 = "/etc/caddy/conf.d/sites.caddy",
    caddy_admin_socket: []const u8 = "/run/caddy/admin.socket",
    projects_root: []const u8 = "/home/kid/Projects",
    cloudflare_api_token: ?[]const u8 = null,
    cloudflare_email: ?[]const u8 = null,
    cloudflare_api_key: ?[]const u8 = null,
    hostinger_api_token: ?[]const u8 = null,

    pub fn load(io: Io, arena: Allocator, env: *std.process.Environ.Map) !Config {
        var cfg = Config{ .domains = try parseList(arena, "plosca.ru") };
        if (env.get("CLOUDIO_CONFIG")) |value| cfg.config_path = try arena.dupe(u8, value);

        if (try readFileMaybe(io, arena, cfg.config_path, max_config_bytes)) |text| {
            try applyConfigText(arena, &cfg, text);
        }

        cfg.loaded_dotenv = try applyEnvFileIfPresent(io, arena, &cfg, ".env", .dotenv);
        cfg.loaded_fish_env = try applyEnvFileIfPresent(io, arena, &cfg, ".env.fish", .fish);

        try applyProcessEnv(arena, &cfg, env);
        return cfg;
    }

    pub fn hasCloudflareAuth(self: Config) bool {
        return self.cloudflare_api_token != null or (self.cloudflare_email != null and self.cloudflare_api_key != null);
    }

    pub fn hasHostingerAuth(self: Config) bool {
        return self.hostinger_api_token != null;
    }
};

const EnvFileKind = enum { dotenv, fish };

fn applyProcessEnv(arena: Allocator, cfg: *Config, env: *std.process.Environ.Map) !void {
    if (env.get("CLOUDIO_DB")) |value| try applyEnvSetting(arena, cfg, "CLOUDIO_DB", value);
    if (env.get("CLOUDIO_LOG")) |value| try applyEnvSetting(arena, cfg, "CLOUDIO_LOG", value);
    if (env.get("CLOUDIO_DOMAINS")) |value| try applyEnvSetting(arena, cfg, "CLOUDIO_DOMAINS", value);
    if (env.get("DOMAINS")) |value| try applyEnvSetting(arena, cfg, "DOMAINS", value);
    if (env.get("DOMAIN")) |value| try applyEnvSetting(arena, cfg, "DOMAIN", value);
    if (env.get("CLOUDFLARE_API_TOKEN")) |value| try applyEnvSetting(arena, cfg, "CLOUDFLARE_API_TOKEN", value);
    if (env.get("CLOUDFLARE_EMAIL")) |value| try applyEnvSetting(arena, cfg, "CLOUDFLARE_EMAIL", value);
    if (env.get("CLOUDFLARE_API_KEY")) |value| try applyEnvSetting(arena, cfg, "CLOUDFLARE_API_KEY", value);
    if (env.get("HOSTINGER_API_TOKEN")) |value| try applyEnvSetting(arena, cfg, "HOSTINGER_API_TOKEN", value);
    if (env.get("HAPI_API_TOKEN")) |value| try applyEnvSetting(arena, cfg, "HAPI_API_TOKEN", value);
}

fn applyEnvFileIfPresent(io: Io, arena: Allocator, cfg: *Config, path: []const u8, kind: EnvFileKind) !bool {
    const text = (try readFileMaybe(io, arena, path, max_config_bytes)) orelse return false;
    try applyEnvFileText(arena, cfg, text, kind);
    return true;
}

fn applyEnvFileText(arena: Allocator, cfg: *Config, text: []const u8, kind: EnvFileKind) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = trim(stripComment(line_raw));
        if (line.len == 0 or std.mem.startsWith(u8, line, "#!") or std.mem.startsWith(u8, line, "#")) continue;
        switch (kind) {
            .dotenv => {
                const assignment = if (std.mem.startsWith(u8, line, "export ")) trim(line["export ".len..]) else line;
                const eq = std.mem.indexOfScalar(u8, assignment, '=') orelse continue;
                const key = trim(assignment[0..eq]);
                const value = parseEnvValue(trim(assignment[eq + 1 ..]));
                try applyEnvSetting(arena, cfg, key, value);
            },
            .fish => {
                if (!std.mem.startsWith(u8, line, "set ")) continue;
                var idx: usize = "set ".len;
                skipSpaces(line, &idx);
                while (idx < line.len and line[idx] == '-') {
                    skipToken(line, &idx);
                    skipSpaces(line, &idx);
                }
                const key_start = idx;
                skipToken(line, &idx);
                if (idx <= key_start) continue;
                const key = line[key_start..idx];
                const value = parseEnvValue(trim(line[idx..]));
                try applyEnvSetting(arena, cfg, key, value);
            },
        }
    }
}

fn applyEnvSetting(arena: Allocator, cfg: *Config, key: []const u8, raw_value: []const u8) !void {
    const value = trim(raw_value);
    if (value.len == 0) return;
    const owned = try arena.dupe(u8, value);
    if (std.mem.eql(u8, key, "CLOUDIO_DB")) {
        cfg.db_path = owned;
    } else if (std.mem.eql(u8, key, "CLOUDIO_LOG")) {
        cfg.log_path = owned;
    } else if (std.mem.eql(u8, key, "DOMAINS") or std.mem.eql(u8, key, "DOMAIN") or std.mem.eql(u8, key, "CLOUDIO_DOMAINS")) {
        cfg.domains = try parseList(arena, owned);
    } else if (std.mem.eql(u8, key, "CLOUDFLARE_API_TOKEN")) {
        cfg.cloudflare_api_token = owned;
    } else if (std.mem.eql(u8, key, "CLOUDFLARE_EMAIL")) {
        cfg.cloudflare_email = owned;
    } else if (std.mem.eql(u8, key, "CLOUDFLARE_API_KEY")) {
        cfg.cloudflare_api_key = owned;
    } else if (std.mem.eql(u8, key, "HOSTINGER_API_TOKEN") or std.mem.eql(u8, key, "HAPI_API_TOKEN")) {
        cfg.hostinger_api_token = owned;
    }
}

fn applyConfigText(arena: Allocator, cfg: *Config, text: []const u8) !void {
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line_without_comment = stripComment(line_raw);
        const line = trim(line_without_comment);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "[") and std.mem.endsWith(u8, line, "]")) {
            section = trim(line[1 .. line.len - 1]);
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trim(line[0..eq]);
        const value = try arena.dupe(u8, parseConfigValue(trim(line[eq + 1 ..])));
        if (value.len == 0) continue;
        if (std.mem.eql(u8, section, "")) {
            if (std.mem.eql(u8, key, "db_path")) cfg.db_path = value;
            if (std.mem.eql(u8, key, "log_path")) cfg.log_path = value;
            if (std.mem.eql(u8, key, "domains")) cfg.domains = try parseList(arena, value);
            if (std.mem.eql(u8, key, "caddyfile_path")) cfg.caddyfile_path = value;
            if (std.mem.eql(u8, key, "caddy_sites_path")) cfg.caddy_sites_path = value;
            if (std.mem.eql(u8, key, "caddy_admin_socket")) cfg.caddy_admin_socket = value;
            if (std.mem.eql(u8, key, "projects_root")) cfg.projects_root = value;
        } else if (std.mem.eql(u8, section, "cloudflare")) {
            if (std.mem.eql(u8, key, "api_token")) cfg.cloudflare_api_token = value;
            if (std.mem.eql(u8, key, "email")) cfg.cloudflare_email = value;
            if (std.mem.eql(u8, key, "api_key")) cfg.cloudflare_api_key = value;
        } else if (std.mem.eql(u8, section, "hostinger")) {
            if (std.mem.eql(u8, key, "api_token")) cfg.hostinger_api_token = value;
        }
    }
}

fn parseList(arena: Allocator, value: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).empty;
    errdefer list.deinit(arena);
    var start: usize = 0;
    for (value, 0..) |ch, idx| {
        if (ch == ',' or ch == ';' or ch == '|' or ch == '\n' or ch == ' ' or ch == '\t') {
            const item = trim(value[start..idx]);
            if (item.len > 0) try list.append(arena, try arena.dupe(u8, item));
            start = idx + 1;
        }
    }
    const item = trim(value[start..]);
    if (item.len > 0) try list.append(arena, try arena.dupe(u8, item));
    if (list.items.len == 0) try list.append(arena, try arena.dupe(u8, "plosca.ru"));
    return try list.toOwnedSlice(arena);
}

fn readFileMaybe(io: Io, allocator: Allocator, path: []const u8, max_bytes: usize) !?[]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |e| return e,
    };
}

fn stripComment(line: []const u8) []const u8 {
    var in_quote = false;
    for (line, 0..) |ch, idx| {
        if (ch == '"') in_quote = !in_quote;
        if (!in_quote and ch == '#') return line[0..idx];
    }
    return line;
}

fn parseConfigValue(value: []const u8) []const u8 {
    return parseEnvValue(value);
}

fn parseEnvValue(value_raw: []const u8) []const u8 {
    var value = trim(value_raw);
    if (std.mem.endsWith(u8, value, ";")) value = trim(value[0 .. value.len - 1]);
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn skipSpaces(value: []const u8, idx: *usize) void {
    while (idx.* < value.len and (value[idx.*] == ' ' or value[idx.*] == '\t')) idx.* += 1;
}

fn skipToken(value: []const u8, idx: *usize) void {
    while (idx.* < value.len and value[idx.*] != ' ' and value[idx.*] != '\t' and value[idx.*] != '\r' and value[idx.*] != '\n') idx.* += 1;
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

test "parse list supports mixed separators" {
    const allocator = std.testing.allocator;
    const list = try parseList(allocator, "plosca.ru sparkdate.love,example.com|other.test");
    defer {
        for (list) |item| allocator.free(item);
        allocator.free(list);
    }
    try std.testing.expectEqual(@as(usize, 4), list.len);
    try std.testing.expectEqualStrings("plosca.ru", list[0]);
    try std.testing.expectEqualStrings("sparkdate.love", list[1]);
}

test "config parser reads provider settings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\db_path = ".cloudio/test.db"
        \\domains = "plosca.ru sparkdate.love"
        \\[cloudflare]
        \\api_token = "token"
        \\[hostinger]
        \\api_token = "hapi"
    );
    try std.testing.expectEqualStrings(".cloudio/test.db", cfg.db_path);
    try std.testing.expectEqual(@as(usize, 2), cfg.domains.len);
    try std.testing.expect(cfg.hasCloudflareAuth());
    try std.testing.expect(cfg.hasHostingerAuth());
}

test "empty provider config values do not configure auth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\[cloudflare]
        \\api_token = ""
        \\email = ""
        \\api_key = ""
        \\[hostinger]
        \\api_token = ""
    );
    try std.testing.expect(!cfg.hasCloudflareAuth());
    try std.testing.expect(!cfg.hasHostingerAuth());
}

test "dotenv parser reads canonical env names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyEnvFileText(arena.allocator(), &cfg,
        \\CLOUDFLARE_EMAIL=me@example.com
        \\CLOUDFLARE_API_KEY='legacy'
        \\HOSTINGER_API_TOKEN="hostinger"
        \\DOMAINS="plosca.ru sparkdate.love"
        \\CLOUDIO_LOG=".cloudio/test-run.log"
    , .dotenv);
    try std.testing.expect(cfg.hasCloudflareAuth());
    try std.testing.expect(cfg.hasHostingerAuth());
    try std.testing.expectEqual(@as(usize, 2), cfg.domains.len);
    try std.testing.expectEqualStrings(".cloudio/test-run.log", cfg.log_path);
}

test "fish env parser reads set exports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyEnvFileText(arena.allocator(), &cfg,
        \\set -x CLOUDFLARE_EMAIL me@example.com
        \\set -x CLOUDFLARE_API_KEY legacy
        \\set -x HOSTINGER_API_TOKEN hostinger
        \\set -x DOMAINS "plosca.ru sparkdate.love"
    , .fish);
    try std.testing.expect(cfg.hasCloudflareAuth());
    try std.testing.expect(cfg.hasHostingerAuth());
    try std.testing.expectEqual(@as(usize, 2), cfg.domains.len);
}
