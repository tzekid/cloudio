const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_config_bytes = 256 * 1024;

const Setting = enum {
    db_path,
    log_path,
    domains,
    caddyfile_path,
    caddy_sites_path,
    caddy_admin_socket,
    projects_root,
    cloudflare_api_token,
    cloudflare_email,
    cloudflare_api_key,
    hostinger_api_token,
    auth_origin,
    auth_rp_id,
    apps_root,
    port_range,
    refresh_seconds,
    storage_auto_prune,
    snapshot_retention_days,
    provider_raw_retention_days,
    metrics_retention_days,
    maintenance_interval_hours,
    maintenance_batch_rows,
};

const EnvBinding = struct {
    key: []const u8,
    setting: Setting,
};

const ConfigBinding = struct {
    section: []const u8,
    key: []const u8,
    setting: Setting,
};

const env_bindings = [_]EnvBinding{
    .{ .key = "CLOUDIO_DB", .setting = .db_path },
    .{ .key = "CLOUDIO_LOG", .setting = .log_path },
    .{ .key = "CLOUDIO_DOMAINS", .setting = .domains },
    .{ .key = "DOMAINS", .setting = .domains },
    .{ .key = "DOMAIN", .setting = .domains },
    .{ .key = "CLOUDFLARE_API_TOKEN", .setting = .cloudflare_api_token },
    .{ .key = "CLOUDFLARE_EMAIL", .setting = .cloudflare_email },
    .{ .key = "CLOUDFLARE_API_KEY", .setting = .cloudflare_api_key },
    .{ .key = "HOSTINGER_API_TOKEN", .setting = .hostinger_api_token },
    .{ .key = "HAPI_API_TOKEN", .setting = .hostinger_api_token },
    .{ .key = "CLOUDIO_AUTH_ORIGIN", .setting = .auth_origin },
    .{ .key = "CLOUDIO_AUTH_RP_ID", .setting = .auth_rp_id },
    .{ .key = "CLOUDIO_APPS_ROOT", .setting = .apps_root },
    .{ .key = "CLOUDIO_STORAGE_AUTO_PRUNE", .setting = .storage_auto_prune },
    .{ .key = "CLOUDIO_SNAPSHOT_RETENTION_DAYS", .setting = .snapshot_retention_days },
    .{ .key = "CLOUDIO_PROVIDER_RAW_RETENTION_DAYS", .setting = .provider_raw_retention_days },
    .{ .key = "CLOUDIO_METRICS_RETENTION_DAYS", .setting = .metrics_retention_days },
    .{ .key = "CLOUDIO_MAINTENANCE_INTERVAL_HOURS", .setting = .maintenance_interval_hours },
    .{ .key = "CLOUDIO_MAINTENANCE_BATCH_ROWS", .setting = .maintenance_batch_rows },
};

const config_bindings = [_]ConfigBinding{
    .{ .section = "", .key = "db_path", .setting = .db_path },
    .{ .section = "", .key = "log_path", .setting = .log_path },
    .{ .section = "", .key = "domains", .setting = .domains },
    .{ .section = "", .key = "caddyfile_path", .setting = .caddyfile_path },
    .{ .section = "", .key = "caddy_sites_path", .setting = .caddy_sites_path },
    .{ .section = "", .key = "caddy_admin_socket", .setting = .caddy_admin_socket },
    .{ .section = "", .key = "projects_root", .setting = .projects_root },
    .{ .section = "cloudflare", .key = "api_token", .setting = .cloudflare_api_token },
    .{ .section = "cloudflare", .key = "email", .setting = .cloudflare_email },
    .{ .section = "cloudflare", .key = "api_key", .setting = .cloudflare_api_key },
    .{ .section = "hostinger", .key = "api_token", .setting = .hostinger_api_token },
    .{ .section = "auth", .key = "origin", .setting = .auth_origin },
    .{ .section = "auth", .key = "rp_id", .setting = .auth_rp_id },
    .{ .section = "platform", .key = "apps_root", .setting = .apps_root },
    .{ .section = "platform", .key = "port_range", .setting = .port_range },
    .{ .section = "platform", .key = "refresh_seconds", .setting = .refresh_seconds },
    .{ .section = "storage", .key = "auto_prune", .setting = .storage_auto_prune },
    .{ .section = "storage", .key = "snapshot_retention_days", .setting = .snapshot_retention_days },
    .{ .section = "storage", .key = "provider_raw_retention_days", .setting = .provider_raw_retention_days },
    .{ .section = "storage", .key = "metrics_retention_days", .setting = .metrics_retention_days },
    .{ .section = "storage", .key = "maintenance_interval_hours", .setting = .maintenance_interval_hours },
    .{ .section = "storage", .key = "maintenance_batch_rows", .setting = .maintenance_batch_rows },
};

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
    auth_origin: []const u8 = "http://localhost:9328",
    auth_rp_id: []const u8 = "localhost",
    apps_root: []const u8 = "/home/kid/Projects",
    port_min: u16 = 42000,
    port_max: u16 = 42999,
    refresh_seconds: u32 = 300,
    storage_auto_prune: bool = false,
    snapshot_retention_days: u32 = 14,
    provider_raw_retention_days: u32 = 14,
    metrics_retention_days: u32 = 30,
    maintenance_interval_hours: u32 = 24,
    maintenance_batch_rows: u32 = 5000,

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
    for (env_bindings) |binding| {
        if (env.get(binding.key)) |value| try applySetting(arena, cfg, binding.setting, value);
    }
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
    if (envSetting(key)) |setting| try applySetting(arena, cfg, setting, raw_value);
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
        const value = parseConfigValue(trim(line[eq + 1 ..]));
        if (configSetting(section, key)) |setting| try applySetting(arena, cfg, setting, value);
    }
}

fn envSetting(key: []const u8) ?Setting {
    for (env_bindings) |binding| {
        if (std.mem.eql(u8, key, binding.key)) return binding.setting;
    }
    return null;
}

fn configSetting(section: []const u8, key: []const u8) ?Setting {
    for (config_bindings) |binding| {
        if (std.mem.eql(u8, section, binding.section) and std.mem.eql(u8, key, binding.key)) return binding.setting;
    }
    return null;
}

fn applySetting(arena: Allocator, cfg: *Config, setting: Setting, raw_value: []const u8) !void {
    const value = trim(raw_value);
    if (value.len == 0) return;
    switch (setting) {
        .domains => cfg.domains = try parseList(arena, value),
        .db_path => cfg.db_path = try arena.dupe(u8, value),
        .log_path => cfg.log_path = try arena.dupe(u8, value),
        .caddyfile_path => cfg.caddyfile_path = try arena.dupe(u8, value),
        .caddy_sites_path => cfg.caddy_sites_path = try arena.dupe(u8, value),
        .caddy_admin_socket => cfg.caddy_admin_socket = try arena.dupe(u8, value),
        .projects_root => cfg.projects_root = try arena.dupe(u8, value),
        .cloudflare_api_token => cfg.cloudflare_api_token = try arena.dupe(u8, value),
        .cloudflare_email => cfg.cloudflare_email = try arena.dupe(u8, value),
        .cloudflare_api_key => cfg.cloudflare_api_key = try arena.dupe(u8, value),
        .hostinger_api_token => cfg.hostinger_api_token = try arena.dupe(u8, value),
        .auth_origin => cfg.auth_origin = try arena.dupe(u8, value),
        .auth_rp_id => cfg.auth_rp_id = try arena.dupe(u8, value),
        .apps_root => cfg.apps_root = try arena.dupe(u8, value),
        .port_range => {
            const dash = std.mem.indexOfScalar(u8, value, '-') orelse return;
            cfg.port_min = std.fmt.parseInt(u16, trim(value[0..dash]), 10) catch return;
            cfg.port_max = std.fmt.parseInt(u16, trim(value[dash + 1 ..]), 10) catch return;
        },
        .refresh_seconds => cfg.refresh_seconds = std.fmt.parseInt(u32, value, 10) catch return,
        .storage_auto_prune => cfg.storage_auto_prune = parseBool(value) orelse return,
        .snapshot_retention_days => cfg.snapshot_retention_days = parsePositiveU32(value) orelse return,
        .provider_raw_retention_days => cfg.provider_raw_retention_days = parsePositiveU32(value) orelse return,
        .metrics_retention_days => cfg.metrics_retention_days = parsePositiveU32(value) orelse return,
        .maintenance_interval_hours => cfg.maintenance_interval_hours = parsePositiveU32(value) orelse return,
        .maintenance_batch_rows => cfg.maintenance_batch_rows = parsePositiveU32(value) orelse return,
    }
}

fn parseBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "no")) return false;
    return null;
}

fn parsePositiveU32(value: []const u8) ?u32 {
    const parsed = std.fmt.parseInt(u32, value, 10) catch return null;
    if (parsed == 0) return null;
    return parsed;
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

test "config parser reads platform and passkey settings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\[platform]
        \\apps_root = "/srv/apps"
        \\port_range = "43000-43100"
        \\refresh_seconds = 60
        \\[auth]
        \\origin = "https://cloudio.example.com"
        \\rp_id = "cloudio.example.com"
    );
    try std.testing.expectEqualStrings("/srv/apps", cfg.apps_root);
    try std.testing.expectEqual(@as(u16, 43000), cfg.port_min);
    try std.testing.expectEqual(@as(u16, 43100), cfg.port_max);
    try std.testing.expectEqual(@as(u32, 60), cfg.refresh_seconds);
    try std.testing.expectEqualStrings("https://cloudio.example.com", cfg.auth_origin);
    try std.testing.expectEqualStrings("cloudio.example.com", cfg.auth_rp_id);
}

test "config parser reads storage lifecycle settings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\[storage]
        \\auto_prune = true
        \\snapshot_retention_days = 21
        \\provider_raw_retention_days = 10
        \\metrics_retention_days = 45
        \\maintenance_interval_hours = 12
        \\maintenance_batch_rows = 2500
    );
    try std.testing.expect(cfg.storage_auto_prune);
    try std.testing.expectEqual(@as(u32, 21), cfg.snapshot_retention_days);
    try std.testing.expectEqual(@as(u32, 10), cfg.provider_raw_retention_days);
    try std.testing.expectEqual(@as(u32, 45), cfg.metrics_retention_days);
    try std.testing.expectEqual(@as(u32, 12), cfg.maintenance_interval_hours);
    try std.testing.expectEqual(@as(u32, 2500), cfg.maintenance_batch_rows);
}

test "storage lifecycle settings reject zero and malformed values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\[storage]
        \\auto_prune = maybe
        \\snapshot_retention_days = 0
        \\provider_raw_retention_days = nope
    );
    try std.testing.expect(!cfg.storage_auto_prune);
    try std.testing.expectEqual(@as(u32, 14), cfg.snapshot_retention_days);
    try std.testing.expectEqual(@as(u32, 14), cfg.provider_raw_retention_days);
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

test "config parser reads path and project settings through shared bindings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyConfigText(arena.allocator(), &cfg,
        \\caddyfile_path = "/tmp/Caddyfile"
        \\caddy_sites_path = "/tmp/sites.caddy"
        \\caddy_admin_socket = "/tmp/admin.sock"
        \\projects_root = "/srv/projects"
    );
    try std.testing.expectEqualStrings("/tmp/Caddyfile", cfg.caddyfile_path);
    try std.testing.expectEqualStrings("/tmp/sites.caddy", cfg.caddy_sites_path);
    try std.testing.expectEqualStrings("/tmp/admin.sock", cfg.caddy_admin_socket);
    try std.testing.expectEqualStrings("/srv/projects", cfg.projects_root);
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

test "process env parser uses shared aliases with later aliases taking precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    defer env.deinit();
    try env.put("CLOUDIO_DB", ".cloudio/env.db");
    try env.put("CLOUDIO_DOMAINS", "one.example two.example");
    try env.put("CLOUDFLARE_API_TOKEN", "cf-token");
    try env.put("HOSTINGER_API_TOKEN", "hostinger-primary");
    try env.put("HAPI_API_TOKEN", "hostinger-alias");

    var cfg = Config{ .domains = try parseList(arena.allocator(), "plosca.ru") };
    try applyProcessEnv(arena.allocator(), &cfg, &env);

    try std.testing.expectEqualStrings(".cloudio/env.db", cfg.db_path);
    try std.testing.expectEqual(@as(usize, 2), cfg.domains.len);
    try std.testing.expectEqualStrings("one.example", cfg.domains[0]);
    try std.testing.expectEqualStrings("cf-token", cfg.cloudflare_api_token.?);
    try std.testing.expectEqualStrings("hostinger-alias", cfg.hostinger_api_token.?);
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
