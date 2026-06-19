const std = @import("std");
const app_cloudflare = @import("app_cloudflare");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");

pub const OverviewParsed = struct {
    options: app_cloudflare.OverviewOptions = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn parseOverviewArgs(args: []const []const u8) !OverviewParsed {
    var parsed = OverviewParsed{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingLimit, error.InvalidLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{ "--snapshot-limit", "--snapshots" }, error.MissingSnapshotLimit, error.InvalidSnapshotLimit)) |limit| {
            parsed.options.snapshot_limit = limit;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return parsed;
}

pub fn isOverviewCommand(value: []const u8) bool {
    return std.mem.eql(u8, value, "overview") or std.mem.eql(u8, value, "summary") or std.mem.eql(u8, value, "zone-overview");
}

pub fn isKeyValue(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, '=') != null;
}

pub fn applyEmailRoutingAccountFilter(args: *app_cloudflare.EmailRoutingAccountReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "verified")) {
        args.verified = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyEmailRoutingZoneFilter(args: *app_cloudflare.EmailRoutingZoneReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "subdomain")) {
        args.subdomain = value;
    } else if (std.mem.eql(u8, key, "enabled")) {
        args.enabled = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyEmailSecuritySettingsFilter(args: *app_cloudflare.EmailSecuritySettingsReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "active_delivery_mode") or std.mem.eql(u8, key, "active-delivery-mode")) {
        args.active_delivery_mode = value;
    } else if (std.mem.eql(u8, key, "allowed_delivery_mode") or std.mem.eql(u8, key, "allowed-delivery-mode")) {
        args.allowed_delivery_mode = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "domain")) {
        args.domain = value;
    } else if (std.mem.eql(u8, key, "integration_id") or std.mem.eql(u8, key, "integration-id")) {
        args.integration_id = value;
    } else if (std.mem.eql(u8, key, "is_acceptable_sender") or std.mem.eql(u8, key, "is-acceptable-sender")) {
        args.is_acceptable_sender = value;
    } else if (std.mem.eql(u8, key, "is_exempt_recipient") or std.mem.eql(u8, key, "is-exempt-recipient")) {
        args.is_exempt_recipient = value;
    } else if (std.mem.eql(u8, key, "is_recent") or std.mem.eql(u8, key, "is-recent")) {
        args.is_recent = value;
    } else if (std.mem.eql(u8, key, "is_similarity") or std.mem.eql(u8, key, "is-similarity")) {
        args.is_similarity = value;
    } else if (std.mem.eql(u8, key, "is_trusted_sender") or std.mem.eql(u8, key, "is-trusted-sender")) {
        args.is_trusted_sender = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "pattern")) {
        args.pattern = value;
    } else if (std.mem.eql(u8, key, "pattern_type") or std.mem.eql(u8, key, "pattern-type")) {
        args.pattern_type = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "provenance")) {
        args.provenance = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "verify_sender") or std.mem.eql(u8, key, "verify-sender")) {
        args.verify_sender = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyZeroTrustReadFilter(args: *app_cloudflare.ZeroTrustReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "type") or std.mem.eql(u8, key, "list_type")) {
        args.list_type = value;
    } else if (std.mem.eql(u8, key, "email")) {
        args.email = value;
    } else if (std.mem.eql(u8, key, "name")) {
        args.name = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search = value;
    } else {
        return false;
    }
    return true;
}

pub fn applySecurityCenterReadFilter(args: *app_cloudflare.SecurityCenterReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "dismissed")) {
        args.dismissed = value;
    } else if (std.mem.eql(u8, key, "issue_class") or std.mem.eql(u8, key, "class")) {
        args.issue_class = value;
    } else if (std.mem.eql(u8, key, "issue_class~neq") or std.mem.eql(u8, key, "class!") or std.mem.eql(u8, key, "class_neq")) {
        args.issue_class_neq = value;
    } else if (std.mem.eql(u8, key, "issue_type") or std.mem.eql(u8, key, "type")) {
        args.issue_type = value;
    } else if (std.mem.eql(u8, key, "issue_type~neq") or std.mem.eql(u8, key, "type!") or std.mem.eql(u8, key, "type_neq")) {
        args.issue_type_neq = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "product")) {
        args.product = value;
    } else if (std.mem.eql(u8, key, "product~neq") or std.mem.eql(u8, key, "product!") or std.mem.eql(u8, key, "product_neq")) {
        args.product_neq = value;
    } else if (std.mem.eql(u8, key, "severity")) {
        args.severity = value;
    } else if (std.mem.eql(u8, key, "severity~neq") or std.mem.eql(u8, key, "severity!") or std.mem.eql(u8, key, "severity_neq")) {
        args.severity_neq = value;
    } else if (std.mem.eql(u8, key, "subject")) {
        args.subject = value;
    } else if (std.mem.eql(u8, key, "subject~neq") or std.mem.eql(u8, key, "subject!") or std.mem.eql(u8, key, "subject_neq")) {
        args.subject_neq = value;
    } else if (std.mem.eql(u8, key, "before")) {
        args.before = value;
    } else if (std.mem.eql(u8, key, "changed_by") or std.mem.eql(u8, key, "changed-by")) {
        args.changed_by = value;
    } else if (std.mem.eql(u8, key, "cursor")) {
        args.cursor = value;
    } else if (std.mem.eql(u8, key, "field_changed") or std.mem.eql(u8, key, "field-changed")) {
        args.field_changed = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "since")) {
        args.since = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyAuditLogReadFilter(args: *app_cloudflare.AuditLogReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "since")) {
        args.since = value;
    } else if (std.mem.eql(u8, key, "before")) {
        args.before = value;
    } else if (std.mem.eql(u8, key, "cursor")) {
        args.cursor = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "id")) {
        args.id = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "actor_email") or std.mem.eql(u8, key, "actor.email")) {
        args.actor_email = value;
    } else if (std.mem.eql(u8, key, "actor_ip") or std.mem.eql(u8, key, "actor.ip") or std.mem.eql(u8, key, "actor_ip_address")) {
        args.actor_ip = value;
    } else if (std.mem.eql(u8, key, "action_type") or std.mem.eql(u8, key, "action.type")) {
        args.action_type = value;
    } else if (std.mem.eql(u8, key, "action_result")) {
        args.action_result = value;
    } else if (std.mem.eql(u8, key, "actor_id")) {
        args.actor_id = value;
    } else if (std.mem.eql(u8, key, "actor_type")) {
        args.actor_type = value;
    } else if (std.mem.eql(u8, key, "resource_id")) {
        args.resource_id = value;
    } else if (std.mem.eql(u8, key, "resource_product")) {
        args.resource_product = value;
    } else if (std.mem.eql(u8, key, "resource_type")) {
        args.resource_type = value;
    } else if (std.mem.eql(u8, key, "zone_id")) {
        args.zone_id = value;
    } else if (std.mem.eql(u8, key, "zone_name") or std.mem.eql(u8, key, "zone.name")) {
        args.zone_name = value;
    } else if (std.mem.eql(u8, key, "hide_user_logs") or std.mem.eql(u8, key, "hide-user-logs")) {
        args.hide_user_logs = value;
    } else if (std.mem.eql(u8, key, "export")) {
        args.export_format = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyLogExplorerReadFilter(args: *app_cloudflare.LogExplorerReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "include_zones") or std.mem.eql(u8, key, "include-zones")) {
        args.include_zones = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyLogsReceivedReadFilter(args: *app_cloudflare.LogsReceivedReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "start")) {
        args.start = value;
    } else if (std.mem.eql(u8, key, "end")) {
        args.end = value;
    } else if (std.mem.eql(u8, key, "count")) {
        args.count = value;
    } else if (std.mem.eql(u8, key, "fields")) {
        args.fields = value;
    } else if (std.mem.eql(u8, key, "sample")) {
        args.sample = value;
    } else if (std.mem.eql(u8, key, "timestamps")) {
        args.timestamps = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyTlsReadFilter(args: *app_cloudflare.TlsReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "deploy")) {
        args.deploy = value;
    } else if (std.mem.eql(u8, key, "match")) {
        args.match = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "offset")) {
        args.offset = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "retry")) {
        args.retry = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyCloudforceOneRuleFilter(args: *app_cloudflare.CloudforceOneRuleReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "namespace")) {
        args.namespace = value;
    } else if (std.mem.eql(u8, key, "recursive")) {
        args.recursive = value;
    } else if (std.mem.eql(u8, key, "search")) {
        args.search_filter = value;
    } else if (std.mem.eql(u8, key, "is_public") or std.mem.eql(u8, key, "public")) {
        args.is_public = value;
    } else if (std.mem.eql(u8, key, "limit")) {
        args.limit = value;
    } else if (std.mem.eql(u8, key, "offset")) {
        args.offset = value;
    } else if (std.mem.eql(u8, key, "query")) {
        args.query = value;
    } else if (std.mem.eql(u8, key, "mode")) {
        args.mode = value;
    } else if (std.mem.eql(u8, key, "language")) {
        args.language = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyIpAccessRuleFilter(args: *app_cloudflare.IpAccessRuleListArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "mode")) {
        args.mode = value;
    } else if (std.mem.eql(u8, key, "configuration.target") or std.mem.eql(u8, key, "target")) {
        args.configuration_target = value;
    } else if (std.mem.eql(u8, key, "configuration.value") or std.mem.eql(u8, key, "value")) {
        args.configuration_value = value;
    } else if (std.mem.eql(u8, key, "notes")) {
        args.notes = value;
    } else if (std.mem.eql(u8, key, "match")) {
        args.match = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "order")) {
        args.order = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else {
        return false;
    }
    return true;
}

pub fn applyPageShieldFilter(args: *app_cloudflare.PageShieldReadArgs, raw: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return false;
    const key = raw[0..eq];
    const value = raw[eq + 1 ..];
    if (std.mem.eql(u8, key, "exclude_urls") or std.mem.eql(u8, key, "exclude-urls")) {
        args.exclude_urls = value;
    } else if (std.mem.eql(u8, key, "urls")) {
        args.urls = value;
    } else if (std.mem.eql(u8, key, "hosts")) {
        args.hosts = value;
    } else if (std.mem.eql(u8, key, "page")) {
        args.page = value;
    } else if (std.mem.eql(u8, key, "per_page") or std.mem.eql(u8, key, "per-page")) {
        args.per_page = value;
    } else if (std.mem.eql(u8, key, "order_by") or std.mem.eql(u8, key, "order-by")) {
        args.order_by = value;
    } else if (std.mem.eql(u8, key, "direction")) {
        args.direction = value;
    } else if (std.mem.eql(u8, key, "prioritize_malicious") or std.mem.eql(u8, key, "prioritize-malicious")) {
        args.prioritize_malicious = value;
    } else if (std.mem.eql(u8, key, "exclude_cdn_cgi") or std.mem.eql(u8, key, "exclude-cdn-cgi")) {
        args.exclude_cdn_cgi = value;
    } else if (std.mem.eql(u8, key, "exclude_duplicates") or std.mem.eql(u8, key, "exclude-duplicates")) {
        args.exclude_duplicates = value;
    } else if (std.mem.eql(u8, key, "status")) {
        args.status = value;
    } else if (std.mem.eql(u8, key, "page_url") or std.mem.eql(u8, key, "page-url")) {
        args.page_url = value;
    } else if (std.mem.eql(u8, key, "export")) {
        args.export_format = value;
    } else if (std.mem.eql(u8, key, "name")) {
        args.name = value;
    } else if (std.mem.eql(u8, key, "secure")) {
        args.secure = value;
    } else if (std.mem.eql(u8, key, "http_only") or std.mem.eql(u8, key, "http-only")) {
        args.http_only = value;
    } else if (std.mem.eql(u8, key, "same_site") or std.mem.eql(u8, key, "same-site")) {
        args.same_site = value;
    } else if (std.mem.eql(u8, key, "type")) {
        args.type_filter = value;
    } else if (std.mem.eql(u8, key, "path")) {
        args.path_filter = value;
    } else if (std.mem.eql(u8, key, "domain")) {
        args.domain = value;
    } else {
        return false;
    }
    return true;
}

test "cloudflare overview parser accepts format and limit" {
    const default_args = [_][]const u8{};
    const defaults = try parseOverviewArgs(default_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);
    try std.testing.expectEqual(@as(i64, 20), defaults.options.limit);
    try std.testing.expectEqual(@as(i64, 12), defaults.options.snapshot_limit);

    const args = [_][]const u8{ "--json", "--limit=5", "--snapshot-limit", "2" };
    const parsed = try parseOverviewArgs(args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);
    try std.testing.expectEqual(@as(i64, 5), parsed.options.limit);
    try std.testing.expectEqual(@as(i64, 2), parsed.options.snapshot_limit);

    const split_args = [_][]const u8{ "--format", "json", "--limit", "3", "--snapshots=4" };
    const split = try parseOverviewArgs(split_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, split.format);
    try std.testing.expectEqual(@as(i64, 3), split.options.limit);
    try std.testing.expectEqual(@as(i64, 4), split.options.snapshot_limit);

    try std.testing.expect(isOverviewCommand("overview"));
    try std.testing.expect(isOverviewCommand("summary"));
    try std.testing.expect(isOverviewCommand("zone-overview"));
}

test "cloudflare overview parser rejects invalid values" {
    const missing_limit = [_][]const u8{"--limit"};
    try std.testing.expectError(error.MissingLimit, parseOverviewArgs(missing_limit[0..]));

    const missing_snapshot_limit = [_][]const u8{"--snapshot-limit"};
    try std.testing.expectError(error.MissingSnapshotLimit, parseOverviewArgs(missing_snapshot_limit[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidLimit, parseOverviewArgs(invalid_limit[0..]));

    const invalid_snapshot_limit = [_][]const u8{"--snapshots=0"};
    try std.testing.expectError(error.InvalidSnapshotLimit, parseOverviewArgs(invalid_snapshot_limit[0..]));

    const invalid_format = [_][]const u8{"--format=yaml"};
    try std.testing.expectError(error.InvalidFormat, parseOverviewArgs(invalid_format[0..]));

    const extra = [_][]const u8{"unexpected"};
    try std.testing.expectError(error.UnexpectedArgument, parseOverviewArgs(extra[0..]));
}

test "cloudforce one rule filters parse key value arguments" {
    var args: app_cloudflare.CloudforceOneRuleReadArgs = .{};
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "namespace=yara/workers"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "recursive=true"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "search=malicious"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "public=false"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "limit=25"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "offset=10"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "query=proxy worker"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "mode=hybrid"));
    try std.testing.expect(applyCloudforceOneRuleFilter(&args, "language=yara"));
    try std.testing.expect(!applyCloudforceOneRuleFilter(&args, "unknown=value"));
    try std.testing.expect(!applyCloudforceOneRuleFilter(&args, "namespace"));
    try std.testing.expectEqualStrings("yara/workers", args.namespace.?);
    try std.testing.expectEqualStrings("malicious", args.search_filter.?);
    try std.testing.expectEqualStrings("proxy worker", args.query.?);
}

test "email routing filters parse key value arguments" {
    var account_args: app_cloudflare.EmailRoutingAccountReadArgs = .{};
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "direction=desc"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "page=2"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "per-page=50"));
    try std.testing.expect(applyEmailRoutingAccountFilter(&account_args, "verified=true"));
    try std.testing.expect(!applyEmailRoutingAccountFilter(&account_args, "unknown=value"));
    try std.testing.expect(!applyEmailRoutingAccountFilter(&account_args, "verified"));
    try std.testing.expectEqualStrings("desc", account_args.direction.?);
    try std.testing.expectEqualStrings("50", account_args.per_page.?);

    var zone_args: app_cloudflare.EmailRoutingZoneReadArgs = .{};
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "subdomain=mail.example.test"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "enabled=false"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "page=3"));
    try std.testing.expect(applyEmailRoutingZoneFilter(&zone_args, "per_page=100"));
    try std.testing.expect(!applyEmailRoutingZoneFilter(&zone_args, "unknown=value"));
    try std.testing.expect(!applyEmailRoutingZoneFilter(&zone_args, "enabled"));
    try std.testing.expectEqualStrings("mail.example.test", zone_args.subdomain.?);
    try std.testing.expectEqualStrings("false", zone_args.enabled.?);
}

test "email security settings filters parse key value arguments" {
    var args: app_cloudflare.EmailSecuritySettingsReadArgs = .{};
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "active-delivery-mode=DIRECT"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "allowed_delivery_mode=API"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "direction=desc"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "domain=plosca.ru"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "integration-id=abc"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-acceptable-sender=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is_exempt_recipient=false"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-recent=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is_similarity=false"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "is-trusted-sender=true"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "order=pattern"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "page=2"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "pattern=example.com"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "pattern-type=DOMAIN"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "per-page=50"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "provenance=AUTO"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "search=partner"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "status=active"));
    try std.testing.expect(applyEmailSecuritySettingsFilter(&args, "verify-sender=true"));
    try std.testing.expect(!applyEmailSecuritySettingsFilter(&args, "unknown=value"));
    try std.testing.expect(!applyEmailSecuritySettingsFilter(&args, "search"));
    try std.testing.expectEqualStrings("DIRECT", args.active_delivery_mode.?);
    try std.testing.expectEqualStrings("API", args.allowed_delivery_mode.?);
    try std.testing.expectEqualStrings("DOMAIN", args.pattern_type.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("true", args.verify_sender.?);
}

test "zero trust read filters parse key value arguments" {
    var args: app_cloudflare.ZeroTrustReadArgs = .{};
    try std.testing.expect(applyZeroTrustReadFilter(&args, "type=SERIAL"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "email=admin@example.test"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "name=Admin User"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "page=2"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "per-page=50"));
    try std.testing.expect(applyZeroTrustReadFilter(&args, "search=admin"));
    try std.testing.expect(!applyZeroTrustReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyZeroTrustReadFilter(&args, "search"));
    try std.testing.expectEqualStrings("SERIAL", args.list_type.?);
    try std.testing.expectEqualStrings("admin@example.test", args.email.?);
    try std.testing.expectEqualStrings("Admin User", args.name.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("admin", args.search.?);
}

test "security center read filters parse key value arguments" {
    var args: app_cloudflare.SecurityCenterReadArgs = .{};
    try std.testing.expect(applySecurityCenterReadFilter(&args, "dismissed=false"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "class=compliance"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "class!=informational"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "type=weak_tls"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "product=waf"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "severity=critical"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "subject=plosca.ru"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "per-page=50"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "changed-by=system"));
    try std.testing.expect(applySecurityCenterReadFilter(&args, "field-changed=status"));
    try std.testing.expect(!applySecurityCenterReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applySecurityCenterReadFilter(&args, "severity"));
    try std.testing.expectEqualStrings("false", args.dismissed.?);
    try std.testing.expectEqualStrings("compliance", args.issue_class.?);
    try std.testing.expectEqualStrings("informational", args.issue_class_neq.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("system", args.changed_by.?);
}

test "audit log read filters parse key value arguments" {
    var args: app_cloudflare.AuditLogReadArgs = .{};
    try std.testing.expect(applyAuditLogReadFilter(&args, "since=2026-06-01T00:00:00Z"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "before=2026-06-17T00:00:00Z"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "actor.email=admin@example.test"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "actor_ip_address=198.51.100.2"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "action.type=edit"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "resource_id=zone/1"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "zone.name=plosca.ru"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "hide-user-logs=true"));
    try std.testing.expect(applyAuditLogReadFilter(&args, "per-page=25"));
    try std.testing.expect(!applyAuditLogReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyAuditLogReadFilter(&args, "since"));
    try std.testing.expectEqualStrings("admin@example.test", args.actor_email.?);
    try std.testing.expectEqualStrings("198.51.100.2", args.actor_ip.?);
    try std.testing.expectEqualStrings("edit", args.action_type.?);
    try std.testing.expectEqualStrings("zone/1", args.resource_id.?);
    try std.testing.expectEqualStrings("true", args.hide_user_logs.?);
}

test "log explorer and logs received filters parse key value arguments" {
    var explorer_args: app_cloudflare.LogExplorerReadArgs = .{};
    try std.testing.expect(applyLogExplorerReadFilter(&explorer_args, "include-zones=true"));
    try std.testing.expect(!applyLogExplorerReadFilter(&explorer_args, "unknown=value"));
    try std.testing.expect(!applyLogExplorerReadFilter(&explorer_args, "include-zones"));
    try std.testing.expectEqualStrings("true", explorer_args.include_zones.?);

    var received_args: app_cloudflare.LogsReceivedReadArgs = .{};
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "start=2026-06-17T00:00:00Z"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "end=2026-06-17T01:00:00Z"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "count=true"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "fields=ClientIP,EdgeStartTimestamp"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "sample=0.1"));
    try std.testing.expect(applyLogsReceivedReadFilter(&received_args, "timestamps=rfc3339"));
    try std.testing.expect(!applyLogsReceivedReadFilter(&received_args, "unknown=value"));
    try std.testing.expect(!applyLogsReceivedReadFilter(&received_args, "start"));
    try std.testing.expectEqualStrings("2026-06-17T00:00:00Z", received_args.start.?);
    try std.testing.expectEqualStrings("2026-06-17T01:00:00Z", received_args.end.?);
    try std.testing.expectEqualStrings("true", received_args.count.?);
    try std.testing.expectEqualStrings("ClientIP,EdgeStartTimestamp", received_args.fields.?);
    try std.testing.expectEqualStrings("rfc3339", received_args.timestamps.?);
}

test "tls read filters parse key value arguments" {
    var args: app_cloudflare.TlsReadArgs = .{};
    try std.testing.expect(applyTlsReadFilter(&args, "deploy=true"));
    try std.testing.expect(applyTlsReadFilter(&args, "match=plosca.ru"));
    try std.testing.expect(applyTlsReadFilter(&args, "status=active"));
    try std.testing.expect(applyTlsReadFilter(&args, "limit=10"));
    try std.testing.expect(applyTlsReadFilter(&args, "offset=20"));
    try std.testing.expect(applyTlsReadFilter(&args, "page=2"));
    try std.testing.expect(applyTlsReadFilter(&args, "per-page=50"));
    try std.testing.expect(applyTlsReadFilter(&args, "retry=false"));
    try std.testing.expect(!applyTlsReadFilter(&args, "unknown=value"));
    try std.testing.expect(!applyTlsReadFilter(&args, "status"));
    try std.testing.expectEqualStrings("true", args.deploy.?);
    try std.testing.expectEqualStrings("plosca.ru", args.match.?);
    try std.testing.expectEqualStrings("active", args.status.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("false", args.retry.?);
}

test "ip access rule filters parse key value arguments" {
    var args: app_cloudflare.IpAccessRuleListArgs = .{};
    try std.testing.expect(applyIpAccessRuleFilter(&args, "mode=block"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "target=ip"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "value=198.51.100.4"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "notes=attack"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "match=all"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "page=2"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "per-page=50"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "order=mode"));
    try std.testing.expect(applyIpAccessRuleFilter(&args, "direction=desc"));
    try std.testing.expect(!applyIpAccessRuleFilter(&args, "unknown=value"));
    try std.testing.expect(!applyIpAccessRuleFilter(&args, "mode"));
    try std.testing.expectEqualStrings("block", args.mode.?);
    try std.testing.expectEqualStrings("ip", args.configuration_target.?);
    try std.testing.expectEqualStrings("198.51.100.4", args.configuration_value.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
}

test "page shield filters parse key value arguments" {
    var args: app_cloudflare.PageShieldReadArgs = .{};
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-urls=https://example.com/a.js"));
    try std.testing.expect(applyPageShieldFilter(&args, "urls=https://cdn.example.com/app.js"));
    try std.testing.expect(applyPageShieldFilter(&args, "hosts=cdn.example.com"));
    try std.testing.expect(applyPageShieldFilter(&args, "page=all"));
    try std.testing.expect(applyPageShieldFilter(&args, "per-page=50"));
    try std.testing.expect(applyPageShieldFilter(&args, "order-by=last_seen_at"));
    try std.testing.expect(applyPageShieldFilter(&args, "direction=desc"));
    try std.testing.expect(applyPageShieldFilter(&args, "prioritize-malicious=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-cdn-cgi=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "exclude-duplicates=false"));
    try std.testing.expect(applyPageShieldFilter(&args, "status=active"));
    try std.testing.expect(applyPageShieldFilter(&args, "page-url=https://example.com/checkout"));
    try std.testing.expect(applyPageShieldFilter(&args, "export=csv"));
    try std.testing.expect(applyPageShieldFilter(&args, "name=session"));
    try std.testing.expect(applyPageShieldFilter(&args, "secure=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "http-only=true"));
    try std.testing.expect(applyPageShieldFilter(&args, "same-site=lax"));
    try std.testing.expect(applyPageShieldFilter(&args, "type=first_party"));
    try std.testing.expect(applyPageShieldFilter(&args, "path=/"));
    try std.testing.expect(applyPageShieldFilter(&args, "domain=example.com"));
    try std.testing.expect(!applyPageShieldFilter(&args, "unknown=value"));
    try std.testing.expect(!applyPageShieldFilter(&args, "hosts"));
    try std.testing.expectEqualStrings("cdn.example.com", args.hosts.?);
    try std.testing.expectEqualStrings("50", args.per_page.?);
    try std.testing.expectEqualStrings("last_seen_at", args.order_by.?);
    try std.testing.expectEqualStrings("true", args.exclude_cdn_cgi.?);
    try std.testing.expectEqualStrings("session", args.name.?);
    try std.testing.expectEqualStrings("first_party", args.type_filter.?);
}
