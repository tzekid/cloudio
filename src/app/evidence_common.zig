const std = @import("std");
const app_provider_family = @import("app_provider_family");
const app_render = @import("app_render");
const core_redact = @import("core_redact");
const db_store = @import("db_store");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const default_limit = 200;
pub const unbounded_storage_limit = 100_000;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    routes: provider_routes.Paths = .{},
};

pub const ProviderFilter = enum {
    all,
    cloudflare,
    hostinger,
    caddy,
    system,
    projects,
    route,

    pub fn parse(value: []const u8) ?ProviderFilter {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        if (std.mem.eql(u8, value, "caddy")) return .caddy;
        if (std.mem.eql(u8, value, "system")) return .system;
        if (std.mem.eql(u8, value, "projects")) return .projects;
        if (std.mem.eql(u8, value, "route")) return .route;
        return null;
    }

    pub fn label(self: ProviderFilter) []const u8 {
        return switch (self) {
            .all => "all",
            .cloudflare => "cloudflare",
            .hostinger => "hostinger",
            .caddy => "caddy",
            .system => "system",
            .projects => "projects",
            .route => "route",
        };
    }

    pub fn dbValue(self: ProviderFilter) ?[]const u8 {
        return switch (self) {
            .all => null,
            .cloudflare => "cloudflare",
            .hostinger => "hostinger",
            .caddy => "caddy",
            .system => "system",
            .projects => "projects",
            .route => "route",
        };
    }
};

pub const Options = struct {
    provider: ProviderFilter = .all,
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .provider = self.provider,
            .limit = if (self.limit == 0) 0 else app_render.positiveLimit(self.limit, default_limit),
        };
    }
};

pub fn storageLimit(limit: i64) i64 {
    return if (limit == 0) unbounded_storage_limit else app_render.positiveLimit(limit, default_limit);
}

pub fn displayLimit(limit: i64, row_count: usize) usize {
    return if (limit == 0) row_count else @intCast(app_render.positiveLimit(limit, default_limit));
}

pub fn writeRedactedTextField(gpa: Allocator, writer: anytype, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try writer.print("\t{s}=", .{label});
    try writeRedactedValue(gpa, writer, value);
}

pub fn writeRedactedJsonStringField(gpa: Allocator, writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    const redacted = try core_redact.secrets(gpa, value);
    defer gpa.free(redacted);
    try app_render.writeJsonStringField(writer, name, std.mem.trimEnd(u8, redacted, "\n"), trailing_comma);
}

pub fn writeRedactedValue(gpa: Allocator, writer: anytype, value: []const u8) !void {
    const redacted = try core_redact.secrets(gpa, value);
    defer gpa.free(redacted);
    try writer.writeAll(std.mem.trimEnd(u8, redacted, "\n"));
}

pub fn statusClass(status: []const u8) []const u8 {
    if (statusIsDryRun(status)) return "dry_run";
    if (statusIsOk(status)) return "ok";
    if (statusIsError(status)) return "error";
    return "other";
}

pub fn statusIsDryRun(status: []const u8) bool {
    return std.mem.indexOf(u8, status, "dry") != null or std.mem.eql(u8, status, "planned");
}

pub fn statusIsOk(status: []const u8) bool {
    return std.mem.eql(u8, status, "ok") or
        std.mem.eql(u8, status, "success") or
        std.mem.eql(u8, status, "done") or
        httpStatusIsSuccess(status);
}

pub fn statusIsError(status: []const u8) bool {
    return httpStatusIsError(status) or
        std.mem.indexOf(u8, status, "error") != null or
        std.mem.indexOf(u8, status, "fail") != null or
        std.mem.indexOf(u8, status, "denied") != null or
        std.mem.indexOf(u8, status, "blocked") != null or
        std.mem.indexOf(u8, status, "permission") != null or
        std.mem.indexOf(u8, status, "not_found") != null or
        std.mem.indexOf(u8, status, "missing") != null;
}

pub fn httpStatusIsSuccess(status: []const u8) bool {
    const code = std.fmt.parseInt(i64, status, 10) catch return false;
    return code >= 200 and code < 400;
}

pub fn httpStatusIsError(status: []const u8) bool {
    const code = std.fmt.parseInt(i64, status, 10) catch return false;
    return code >= 400;
}

pub fn evidenceFamily(provider: []const u8, kind: []const u8) []const u8 {
    if (std.mem.eql(u8, provider, "caddy")) return "caddy";
    if (std.mem.eql(u8, provider, "system")) return "system";
    if (std.mem.eql(u8, provider, "projects")) return "projects";
    if (app_provider_family.tagFamily(provider, kind)) |family| return family.name();
    if (std.mem.eql(u8, provider, "hostinger")) return hostingerFamily(kind);
    if (std.mem.eql(u8, provider, "cloudflare")) return cloudflareFamily(kind);
    return "unclassified";
}

pub fn routeCoverageProviderFilter(provider: ProviderFilter) !provider_routes.ProviderFilter {
    return switch (provider) {
        .all => .all,
        .cloudflare => .cloudflare,
        .hostinger => .hostinger,
        .caddy, .system, .projects, .route => error.InvalidRouteCoverageProvider,
    };
}

fn cloudflareFamily(kind: []const u8) []const u8 {
    if (contains(kind, "dns")) return "dns";
    if (contains(kind, "tls") or contains(kind, "ssl") or contains(kind, "certificate") or contains(kind, "cert")) return "ssl-tls";
    if (contains(kind, "access")) return "access";
    if (contains(kind, "tunnel") or contains(kind, "zero-trust") or contains(kind, "gateway") or contains(kind, "warp")) return "zero-trust";
    if (contains(kind, "ruleset") or contains(kind, "page-rule") or contains(kind, "ua-rule") or contains(kind, "lockdown")) return "rulesets";
    if (contains(kind, "log") or contains(kind, "audit")) return "logs";
    if (contains(kind, "cache") or contains(kind, "argo") or contains(kind, "tiered") or contains(kind, "smart-shield") or contains(kind, "variant")) return "cache";
    if (contains(kind, "security") or contains(kind, "api-shield") or contains(kind, "page-shield") or contains(kind, "bot") or contains(kind, "cloudforce") or contains(kind, "ip-access")) return "security";
    if (contains(kind, "token")) return "tokens";
    if (contains(kind, "membership") or contains(kind, "member")) return "memberships";
    if (contains(kind, "account")) return "accounts";
    if (contains(kind, "zone")) return "zones";
    if (contains(kind, "billing")) return "billing";
    if (contains(kind, "email")) return "email";
    if (contains(kind, "load-balanc") or contains(kind, "healthcheck") or contains(kind, "health-check")) return "load-balancing";
    if (contains(kind, "resource-tag")) return "resource-tags";
    if (contains(kind, "custom-page")) return "custom-pages";
    return "other-cloudflare";
}

fn hostingerFamily(kind: []const u8) []const u8 {
    if (contains(kind, "billing") or contains(kind, "subscription") or contains(kind, "payment")) return "billing";
    if (contains(kind, "dns")) return "dns";
    if (contains(kind, "domain") or contains(kind, "whois") or contains(kind, "forwarding")) return "domains";
    if (contains(kind, "hosting") or contains(kind, "wordpress") or contains(kind, "website")) return "hosting";
    if (contains(kind, "docker")) return "docker";
    if (contains(kind, "public-key") or contains(kind, "public_keys")) return "public-keys";
    if (contains(kind, "vps") or contains(kind, "virtualmachine") or contains(kind, "virtual-machine") or contains(kind, "actions") or contains(kind, "metrics") or contains(kind, "backup") or contains(kind, "snapshot") or contains(kind, "firewall") or contains(kind, "monarx") or contains(kind, "template") or contains(kind, "data-center") or contains(kind, "post-install")) return "hostinger-vps";
    if (contains(kind, "reach")) return "reach";
    if (contains(kind, "ecommerce")) return "ecommerce";
    return "other-hostinger";
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return indexOfIgnoreCase(haystack, needle) != null;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

test "provider filter parser accepts evidence scopes" {
    try std.testing.expectEqual(ProviderFilter.all, ProviderFilter.parse("all").?);
    try std.testing.expectEqual(ProviderFilter.cloudflare, ProviderFilter.parse("cloudflare").?);
    try std.testing.expectEqual(ProviderFilter.hostinger, ProviderFilter.parse("hostinger").?);
    try std.testing.expectEqual(ProviderFilter.caddy, ProviderFilter.parse("caddy").?);
    try std.testing.expectEqual(ProviderFilter.system, ProviderFilter.parse("system").?);
    try std.testing.expectEqual(ProviderFilter.projects, ProviderFilter.parse("projects").?);
    try std.testing.expectEqual(ProviderFilter.route, ProviderFilter.parse("route").?);
    try std.testing.expect(ProviderFilter.parse("other") == null);
}

test "status and family helpers classify evidence consistently" {
    try std.testing.expectEqualStrings("ok", statusClass("200"));
    try std.testing.expectEqualStrings("error", statusClass("not_found"));
    try std.testing.expectEqualStrings("dry_run", statusClass("dry_run"));
    try std.testing.expectEqualStrings("hostinger-vps", evidenceFamily("hostinger", "VPS_getVirtualMachinesV1"));
    try std.testing.expectEqualStrings("security", evidenceFamily("hostinger", "VPS: Firewall"));
    try std.testing.expectEqualStrings("docker", evidenceFamily("hostinger", "VPS: Docker Manager"));
    try std.testing.expectEqualStrings("dns", evidenceFamily("cloudflare", "DNS Records for a Zone"));
}
