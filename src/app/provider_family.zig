const std = @import("std");

pub const WorkplanFamily = enum {
    all,
    accounts,
    memberships,
    iam,
    tokens,
    zones,
    dns,
    ssl_tls,
    access,
    tunnels,
    rulesets,
    logs,
    cache,
    security,
    billing,
    domains,
    hosting,
    docker,
    reach,
    ecommerce,
    horizons,
    verification,
    hostinger_vps,
    public_keys,
    custom_pages,
    healthchecks,
    load_balancing,

    pub fn parse(value: []const u8) ?WorkplanFamily {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "accounts") or std.mem.eql(u8, value, "account")) return .accounts;
        if (std.mem.eql(u8, value, "memberships") or std.mem.eql(u8, value, "membership")) return .memberships;
        if (std.mem.eql(u8, value, "iam")) return .iam;
        if (std.mem.eql(u8, value, "tokens") or std.mem.eql(u8, value, "token")) return .tokens;
        if (std.mem.eql(u8, value, "zones") or std.mem.eql(u8, value, "zone")) return .zones;
        if (std.mem.eql(u8, value, "dns")) return .dns;
        if (std.mem.eql(u8, value, "ssl-tls") or std.mem.eql(u8, value, "ssl_tls") or std.mem.eql(u8, value, "ssl") or std.mem.eql(u8, value, "tls")) return .ssl_tls;
        if (std.mem.eql(u8, value, "access")) return .access;
        if (std.mem.eql(u8, value, "tunnels") or std.mem.eql(u8, value, "tunnel")) return .tunnels;
        if (std.mem.eql(u8, value, "rulesets") or std.mem.eql(u8, value, "ruleset") or std.mem.eql(u8, value, "rules-lists") or std.mem.eql(u8, value, "rules_lists")) return .rulesets;
        if (std.mem.eql(u8, value, "logs") or std.mem.eql(u8, value, "log")) return .logs;
        if (std.mem.eql(u8, value, "cache") or std.mem.eql(u8, value, "caching")) return .cache;
        if (std.mem.eql(u8, value, "security") or std.mem.eql(u8, value, "security-posture") or std.mem.eql(u8, value, "security_posture")) return .security;
        if (std.mem.eql(u8, value, "billing")) return .billing;
        if (std.mem.eql(u8, value, "domains") or std.mem.eql(u8, value, "domain")) return .domains;
        if (std.mem.eql(u8, value, "hosting")) return .hosting;
        if (std.mem.eql(u8, value, "docker")) return .docker;
        if (std.mem.eql(u8, value, "reach")) return .reach;
        if (std.mem.eql(u8, value, "ecommerce") or std.mem.eql(u8, value, "e-commerce")) return .ecommerce;
        if (std.mem.eql(u8, value, "horizons") or std.mem.eql(u8, value, "horizon")) return .horizons;
        if (std.mem.eql(u8, value, "verification") or std.mem.eql(u8, value, "verifications") or std.mem.eql(u8, value, "verifier")) return .verification;
        if (std.mem.eql(u8, value, "hostinger-vps") or std.mem.eql(u8, value, "hostinger_vps") or std.mem.eql(u8, value, "vps")) return .hostinger_vps;
        if (std.mem.eql(u8, value, "public-keys") or std.mem.eql(u8, value, "public_keys") or std.mem.eql(u8, value, "keys")) return .public_keys;
        if (std.mem.eql(u8, value, "custom-pages") or std.mem.eql(u8, value, "custom_pages")) return .custom_pages;
        if (std.mem.eql(u8, value, "healthchecks") or std.mem.eql(u8, value, "healthcheck")) return .healthchecks;
        if (std.mem.eql(u8, value, "load-balancing") or std.mem.eql(u8, value, "load_balancing") or std.mem.eql(u8, value, "load-balancers") or std.mem.eql(u8, value, "load_balancers")) return .load_balancing;
        return null;
    }

    pub fn name(self: WorkplanFamily) []const u8 {
        return switch (self) {
            .all => "all",
            .accounts => "accounts",
            .memberships => "memberships",
            .iam => "iam",
            .tokens => "tokens",
            .zones => "zones",
            .dns => "dns",
            .ssl_tls => "ssl-tls",
            .access => "access",
            .tunnels => "tunnels",
            .rulesets => "rulesets",
            .logs => "logs",
            .cache => "cache",
            .security => "security",
            .billing => "billing",
            .domains => "domains",
            .hosting => "hosting",
            .docker => "docker",
            .reach => "reach",
            .ecommerce => "ecommerce",
            .horizons => "horizons",
            .verification => "verification",
            .hostinger_vps => "hostinger-vps",
            .public_keys => "public-keys",
            .custom_pages => "custom-pages",
            .healthchecks => "healthchecks",
            .load_balancing => "load-balancing",
        };
    }
};

pub fn tagIsControlPlane(provider: []const u8, tag: []const u8) bool {
    return tagFamily(provider, tag) != null;
}

pub fn tagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    if (std.mem.eql(u8, provider, "hostinger")) {
        if (tagContainsAny(tag, &.{ "Docker", "Container" })) return .docker;
        if (tagContainsAny(tag, &.{"Reach"})) return .reach;
        if (tagContainsAny(tag, &.{"Ecommerce"})) return .ecommerce;
        if (tagContainsAny(tag, &.{"Horizons"})) return .horizons;
        if (tagContainsAny(tag, &.{ "Domain Access Verifier", "Verification", "Verifier" })) return .verification;
        if (tagContainsAny(tag, &.{ "Malware", "Monarx", "Firewall", "Security" })) return .security;
        if (tagContainsAny(tag, &.{ "Public key", "SSH key" })) return .public_keys;
        if (tagContainsAny(tag, &.{ "VPS", "Virtual machine", "VirtualMachine", "Post-install" })) return .hostinger_vps;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{"Domain"})) return .domains;
        if (tagContainsAny(tag, &.{ "Hosting", "Horizons" })) return .hosting;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        return null;
    }
    if (std.mem.eql(u8, provider, "cloudflare")) {
        if (tagContainsAny(tag, &.{ "Email Security", "Security Center", "Firewall", "WAF", "Bot", "Page Shield", "IP Access", "API Gateway", "Leaked Credential", "Vulnerability Scanner", "Security" })) return .security;
        if (tagContainsAny(tag, &.{"Token"})) return .tokens;
        if (tagContainsAny(tag, &.{"Membership"})) return .memberships;
        if (tagContainsAny(tag, &.{"IAM"})) return .iam;
        if (tagContainsAny(tag, &.{"DNS"})) return .dns;
        if (tagContainsAny(tag, &.{ "SSL", "TLS", "Certificate", "mTLS" })) return .ssl_tls;
        if (tagContainsAny(tag, &.{"Access"})) return .access;
        if (tagContainsAny(tag, &.{"Tunnel"})) return .tunnels;
        if (tagContainsAny(tag, &.{ "Ruleset", "Rules List" })) return .rulesets;
        if (cloudflareTagIsLogsFamily(tag)) return .logs;
        if (tagContainsAny(tag, &.{ "Cache", "Argo" })) return .cache;
        if (tagContainsAny(tag, &.{"Billing"})) return .billing;
        if (tagContainsAny(tag, &.{"Custom Pages"})) return .custom_pages;
        if (tagContainsAny(tag, &.{"Healthcheck"})) return .healthchecks;
        if (tagContainsAny(tag, &.{"Load Balancer"})) return .load_balancing;
        if (tagContainsAny(tag, &.{"Zone"})) return .zones;
        if (tagContainsAny(tag, &.{ "Account", "Organization", "User" })) return .accounts;
        return null;
    }
    return null;
}

fn tagContainsAny(tag: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(tag, needle) != null) return true;
    }
    return false;
}

fn cloudflareTagIsLogsFamily(tag: []const u8) bool {
    return tagContainsAny(tag, &.{
        "AI Gateway Logs",
        "Audit Logs",
        "Instant Logs",
        "Logcontrol",
        "Logs",
        "Logpush",
        "Logs Received",
        "VPC Flow logs",
        "Worker Tail Logs",
    });
}

test "classifies provider tags into shared control-plane families" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), tagFamily("cloudflare", "AI Gateway Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), tagFamily("cloudflare", "Magic Network Monitoring VPC Flow logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), tagFamily("cloudflare", "Catalog Sync"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), tagFamily("cloudflare", "Radar Certificate Transparency"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), tagFamily("cloudflare", "Token Validation Token Rules"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .access), tagFamily("cloudflare", "Infrastructure Access Targets"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .hostinger_vps), tagFamily("hostinger", "VPS: Virtual machine"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .security), tagFamily("hostinger", "Monarx Malware Scanner"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .security), tagFamily("hostinger", "VPS: Firewall"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .docker), tagFamily("hostinger", "VPS: Docker Manager"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .public_keys), tagFamily("hostinger", "VPS: Public Keys"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .reach), tagFamily("hostinger", "Reach: Segments"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .ecommerce), tagFamily("hostinger", "Ecommerce: Stores"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .horizons), tagFamily("hostinger", "Horizons: Websites"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .verification), tagFamily("hostinger", "Domain Access Verifier: Verifications"));
}
