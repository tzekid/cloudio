const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const core_time = @import("core_time");
const db_store = @import("db_store");
const provider_dispatch = @import("provider_dispatch");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const containsIgnoreCase = app_provider_coverage_render.containsIgnoreCase;
const eqlIgnoreCase = app_provider_coverage_render.eqlIgnoreCase;

const actual_capture_cloudflare_scope_hint_limit: i64 = 200;
const actual_capture_cloudflare_resource_hint_limit: i64 = 5000;
const actual_capture_hostinger_vps_hint_limit: i64 = 50;
const actual_capture_hostinger_hint_limit: i64 = 5000;

pub const ProviderFilter = provider_routes.ProviderFilter;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;

pub const RouteStatus = struct {
    any: bool = false,
    ok: bool = false,
    err: bool = false,
    events: i64 = 0,
    latest_at: []const u8 = "",
};

pub const CaptureState = enum {
    ok,
    missing,
    non_ok,

    pub fn name(self: CaptureState) []const u8 {
        return switch (self) {
            .ok => "ok",
            .missing => "missing",
            .non_ok => "non_ok",
        };
    }
};

pub const SourceSummary = struct {
    total_sources: usize = 0,
    captured_with_hints: usize = 0,
    captured_empty: usize = 0,
    captured_without_hints: usize = 0,
    captured_unknown_body: usize = 0,
    ready_to_capture: usize = 0,
    waiting_for_inputs: usize = 0,
    diagnostic_blocked: usize = 0,
    captured_error: usize = 0,
    no_official_source: usize = 0,
    not_in_catalog: usize = 0,
    unmapped: usize = 0,
    not_eligible: usize = 0,
    body_array: usize = 0,
    body_data_array: usize = 0,
    body_error_object: usize = 0,
    body_no_evidence: usize = 0,
    body_other: usize = 0,
};

pub const Hints = struct {
    configured_domains: []const []const u8 = &.{},
    cloudflare_accounts: []const db_store.CloudflareAccountRow = &.{},
    cloudflare_zones: []const db_store.CloudflareZoneRow = &.{},
    cloudflare_resources: []const db_store.CloudflareResourceHintRow = &.{},
    cloudflare_inventory: []const db_store.CloudflareInventoryHintRow = &.{},
    hostinger_vps: []const db_store.HostingerVpsRow = &.{},
    hostinger_resources: []const db_store.HostingerResourceHintRow = &.{},
    hostinger_inventory: []const db_store.HostingerInventoryHintRow = &.{},
};

pub const InputSource = struct {
    operation_id: []const u8,
    hint_kind: []const u8,
    purpose: []const u8,
};

pub const SourceBodyEvidence = struct {
    shape: []const u8 = "no_evidence",
    item_count: ?usize = null,
    body_bytes: usize = 0,
};

const hostinger_domain_sources = [_]InputSource{.{
    .operation_id = "domains_getDomainListV1",
    .hint_kind = "domains_getDomainListV1",
    .purpose = "discover account domains",
}};

const hostinger_vps_sources = [_]InputSource{.{
    .operation_id = "VPS_getVirtualMachinesV1",
    .hint_kind = "VPS_getVirtualMachinesV1",
    .purpose = "discover VPS ids",
}};

const hostinger_action_sources = [_]InputSource{.{
    .operation_id = "VPS_getActionsV1",
    .hint_kind = "VPS_getActionsV1",
    .purpose = "discover VPS action ids",
}};

const hostinger_template_sources = [_]InputSource{.{
    .operation_id = "VPS_getTemplatesV1",
    .hint_kind = "VPS_getTemplatesV1",
    .purpose = "discover VPS template ids",
}};

const hostinger_firewall_sources = [_]InputSource{.{
    .operation_id = "VPS_getFirewallListV1",
    .hint_kind = "VPS_getFirewallListV1",
    .purpose = "discover VPS firewall ids",
}};

const hostinger_post_install_sources = [_]InputSource{.{
    .operation_id = "VPS_getPostInstallScriptsV1",
    .hint_kind = "VPS_getPostInstallScriptsV1",
    .purpose = "discover post-install script ids",
}};

const hostinger_dns_snapshot_sources = [_]InputSource{.{
    .operation_id = "DNS_getDNSSnapshotListV1",
    .hint_kind = "DNS_getDNSSnapshotListV1",
    .purpose = "discover DNS snapshot ids for the selected domain",
}};

const hostinger_whois_sources = [_]InputSource{.{
    .operation_id = "domains_getWHOISProfileListV1",
    .hint_kind = "domains_getWHOISProfileListV1",
    .purpose = "discover WHOIS profile ids",
}};

const hostinger_username_sources = [_]InputSource{.{
    .operation_id = "hosting_listWebsitesV1",
    .hint_kind = "hosting_listWebsitesV1",
    .purpose = "discover hosting account usernames from websites",
}};

const hostinger_order_sources = [_]InputSource{
    .{
        .operation_id = "hosting_listOrdersV1",
        .hint_kind = "hosting_listOrdersV1",
        .purpose = "discover hosting order ids",
    },
    .{
        .operation_id = "hosting_listWebsitesV1",
        .hint_kind = "hosting_listWebsitesV1",
        .purpose = "reuse website inventory related order ids",
    },
};

const hostinger_database_sources = [_]InputSource{.{
    .operation_id = "hosting_listAccountDatabasesV1",
    .hint_kind = "hosting_listAccountDatabasesV1",
    .purpose = "discover database names for a hosting account",
}};

const hostinger_nodejs_build_sources = [_]InputSource{.{
    .operation_id = "hosting_listNodeJSBuildsV1",
    .hint_kind = "hosting_listNodeJSBuildsV1",
    .purpose = "discover NodeJS build UUIDs for a website",
}};

const hostinger_docker_project_sources = [_]InputSource{.{
    .operation_id = "VPS_getProjectListV1",
    .hint_kind = "VPS_getProjectListV1",
    .purpose = "discover Docker Manager project names for a VPS",
}};

const hostinger_reach_profile_sources = [_]InputSource{.{
    .operation_id = "reach_listProfilesV1",
    .hint_kind = "reach_listProfilesV1",
    .purpose = "discover Reach profile UUIDs",
}};

const hostinger_reach_segment_sources = [_]InputSource{.{
    .operation_id = "reach_listSegmentsV1",
    .hint_kind = "reach_listSegmentsV1",
    .purpose = "discover Reach segment UUIDs",
}};

pub fn loadActualCaptureCloudflareAccountHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareAccountRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareAccountRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

pub fn loadActualCaptureCloudflareZoneHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareZoneRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareZoneRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

pub fn loadActualCaptureCloudflareResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareResourceHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareResourceHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

pub fn loadActualCaptureCloudflareInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareInventoryHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareInventoryHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

pub fn loadActualCaptureHostingerHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerVpsRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerVpsRows(gpa, actual_capture_hostinger_vps_hint_limit);
}

pub fn loadActualCaptureHostingerResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerResourceHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerResourceHints(gpa, actual_capture_hostinger_hint_limit);
}

pub fn loadActualCaptureHostingerInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerInventoryHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerInventoryHints(gpa, actual_capture_hostinger_hint_limit);
}

pub fn actualCaptureProviderDbValue(provider: ProviderFilter) ?[]const u8 {
    return switch (provider) {
        .all => null,
        .cloudflare => "cloudflare",
        .hostinger => "hostinger",
    };
}

pub fn actualCaptureRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

pub fn actualCaptureState(route: provider_routes.Route, captures: []const db_store.RouteCaptureEvidenceRow) ?CaptureState {
    if (route.deprecated or !route.isRoutable()) return null;
    if (route.method != .GET or route.mode != .read) return null;
    if (route.request_body.required) return null;
    const operation_id = route.operation_id orelse return null;
    const status = actualRouteCaptureStatus(route.provider.name(), operation_id, captures);
    if (status.ok) return .ok;
    if (status.any) return .non_ok;
    return .missing;
}

pub fn actualRouteCaptureStatus(provider: []const u8, operation_id: []const u8, captures: []const db_store.RouteCaptureEvidenceRow) RouteStatus {
    var out = RouteStatus{};
    for (captures) |capture| {
        if (!std.mem.eql(u8, capture.provider, provider)) continue;
        if (!std.mem.eql(u8, capture.operation_id, operation_id)) continue;
        out.any = true;
        out.events += capture.count;
        if (actualStatusIsOk(capture.status)) out.ok = true;
        if (actualStatusIsError(capture.status)) out.err = true;
        if (capture.latest_at.len != 0 and actualLatestAtLessThan(out.latest_at, capture.latest_at)) out.latest_at = capture.latest_at;
    }
    return out;
}

fn actualStatusIsOk(status: []const u8) bool {
    return std.mem.eql(u8, status, "ok") or
        std.mem.eql(u8, status, "success") or
        std.mem.eql(u8, status, "done") or
        actualHttpStatusIsSuccess(status);
}

fn actualStatusIsError(status: []const u8) bool {
    return actualHttpStatusIsError(status) or
        std.mem.indexOf(u8, status, "error") != null or
        std.mem.indexOf(u8, status, "fail") != null or
        std.mem.indexOf(u8, status, "denied") != null or
        std.mem.indexOf(u8, status, "blocked") != null or
        std.mem.indexOf(u8, status, "permission") != null or
        std.mem.indexOf(u8, status, "not_found") != null or
        std.mem.indexOf(u8, status, "missing") != null;
}

fn actualHttpStatusIsSuccess(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 200 and value < 300;
}

fn actualHttpStatusIsError(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 400;
}

fn actualLatestAtLessThan(current: []const u8, candidate: []const u8) bool {
    if (current.len == 0) return true;
    return std.mem.order(u8, current, candidate) == .lt;
}

pub fn actualCaptureReady(route: provider_routes.Route, hints: Hints) bool {
    return actualCaptureReadyWithPolicy(route, hints, false);
}

pub fn actualCaptureReadyWithPolicy(route: provider_routes.Route, hints: Hints, include_blocked: bool) bool {
    return actualCaptureRouteExecutable(route, include_blocked) and actualCaptureMissingInputCount(route, hints) == 0;
}

fn actualCaptureRouteExecutable(route: provider_routes.Route, include_blocked: bool) bool {
    return provider_dispatch.routeLiveCallSupported(route) or (include_blocked and provider_dispatch.routeDiagnosticReadSupported(route));
}

pub fn actualCaptureUsesDiagnosticRead(route: provider_routes.Route, include_blocked: bool) bool {
    return include_blocked and !provider_dispatch.routeLiveCallSupported(route) and provider_dispatch.routeDiagnosticReadSupported(route);
}

pub fn actualCaptureMissingInputCount(route: provider_routes.Route, hints: Hints) usize {
    var count: usize = 0;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) == null) count += 1;
    }
    for (route.query_params) |param| {
        if (param.required and !actualCaptureHasQueryParamHint(route, param.name, hints)) count += 1;
    }
    for (route.header_params) |param| {
        if (param.required) count += 1;
    }
    return count;
}

pub fn actualCapturePathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    return switch (route.provider) {
        .cloudflare => actualCaptureCloudflarePathParamHint(route, name, hints),
        .hostinger => actualCaptureHostingerPathParamHint(route, name, hints),
    };
}

fn actualCaptureCloudflarePathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    if (std.mem.eql(u8, name, "account_id") or std.mem.eql(u8, name, "account_identifier")) return actualCaptureCloudflareAccountIdHint(hints);
    if (std.mem.eql(u8, name, "zone_id") or std.mem.eql(u8, name, "zone_identifier")) return actualCaptureCloudflareZoneIdHint(hints);
    if (std.mem.eql(u8, name, "dns_record_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "route-cloudflare-dns", "route-cloudflare-dns-typed-smoke", "dns", "dns-records" });
    if (std.mem.eql(u8, name, "ruleset_id")) return actualCaptureCloudflareRulesetIdHint(route, hints);
    if (std.mem.eql(u8, name, "ruleset_phase")) return actualCaptureCloudflareRulesetPhaseHint(route, hints);
    if (std.mem.eql(u8, name, "identifier") and actualCaptureRoutePathContains(route, "/custom_pages/")) return actualCaptureCloudflareCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "custom_page_id")) return actualCaptureCloudflareAccessCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "certificate_pack_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "tls-zone-certificate-packs", "tls-zone-certificate-pack" });
    if (std.mem.eql(u8, name, "identity_provider_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "idp_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "member_id") and containsIgnoreCase(route.tag, "Account Members")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-members"});
    if (std.mem.eql(u8, name, "role_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-roles"});
    if (std.mem.eql(u8, name, "token_id")) return actualCaptureCloudflareTokenIdHint(route, hints);
    if (std.mem.eql(u8, name, "permission_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-permission-groups", "account-token-permission-groups", "user-token-permission-groups" });
    if (std.mem.eql(u8, name, "resource_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-resource-groups"});
    if (std.mem.eql(u8, name, "client_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-client-certificates", "api-shield-client-certificates", "api-shield-client-certificates-for-a-zone" });
    if (std.mem.eql(u8, name, "certificate_id") and actualCaptureRoutePathContains(route, "/origin_ca/certificates/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "tls-origin-ca-certificates", "tls-origin-ca-certificate" });
    if (std.mem.eql(u8, name, "plan_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-available-plans", "zone-available-rate-plans" });
    if (std.mem.eql(u8, name, "rule_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-rules", "email-routing-rules" });
    if (std.mem.eql(u8, name, "destination_address_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-destination-addresses", "email-routing-destination-addresses" });
    if (std.mem.eql(u8, name, "name") and containsIgnoreCase(route.tag, "API Shield Labels")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"zone-api-shield-labels"});
    return null;
}

fn actualCaptureCloudflareAccountIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneAccountId(hints)) |account_id| return account_id;
    for (hints.cloudflare_accounts) |row| {
        if (row.id.len != 0) return row.id;
    }
    for (hints.cloudflare_zones) |row| {
        if (row.account_id.len != 0) return row.account_id;
    }
    return null;
}

fn actualCaptureCloudflareZoneIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneId(hints)) |zone_id| return zone_id;
    for (hints.cloudflare_zones) |row| {
        if (row.id.len != 0) return row.id;
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneId(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneAccountId(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.account_id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.account_id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareDomain(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.cloudflare_zones) |row| {
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
    }
    return null;
}

fn actualCaptureCloudflareRulesetIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareRulesetPhaseHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareCustomPageIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-custom-pages", "account-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-custom-pages", "zone-custom-page" });
    }
    return null;
}

fn actualCaptureCloudflareAccessCustomPageIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access custom pages")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-custom-pages", "access-account-custom-page", "access-custom-pages", "access-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-zone-custom-pages", "access-zone-custom-page", "access-custom-pages", "access-custom-page" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-custom-pages", "access-zone-custom-pages", "access-custom-pages", "access-custom-page" });
}

fn actualCaptureCloudflareAccessIdentityProviderIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access identity providers") and !containsIgnoreCase(route.tag, "Access SCIM update")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-identity-providers", "access-account-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-zone-identity-providers", "access-zone-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-account-identity-providers", "access-zone-identity-providers", "access-identity-providers", "access-identity-provider" });
}

fn actualCaptureCloudflareTokenIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens" });
    }
    if (actualCaptureRoutePathContains(route, "/user/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user-tokens", "user-api-tokens" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens", "user-tokens", "user-api-tokens" });
}

fn actualCaptureCloudflareResourceIdHint(route: provider_routes.Route, hints: Hints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_id;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    return null;
}

fn actualCaptureCloudflareResourceTypeHint(route: provider_routes.Route, hints: Hints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_type.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_type;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.category.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.category;
    }
    return null;
}

fn actualCaptureCloudflareResourceMatchesRouteScope(route: provider_routes.Route, hints: Hints, scope: []const u8, scope_id: []const u8) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    if (!account_scoped and !zone_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(scope, "account") and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareInventoryMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.CloudflareInventoryHintRow) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    if (!account_scoped and !zone_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(row.account_id, account_id)) return true;
            if (eqlIgnoreCase(row.scope, "account") and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(row.zone_id, zone_id)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareRouteAccountScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/accounts/");
}

fn actualCaptureCloudflareRouteZoneScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/zones/");
}

fn actualCaptureRoutePathContains(route: provider_routes.Route, needle: []const u8) bool {
    return std.mem.indexOf(u8, route.path_template, needle) != null;
}

fn actualCaptureScopeIdHasParent(scope_id: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(scope_id, parent)) return true;
    if (scope_id.len <= parent.len) return false;
    if (scope_id[parent.len] != '/') return false;
    return eqlIgnoreCase(scope_id[0..parent.len], parent);
}

fn actualCaptureKindIn(kind: []const u8, kinds: []const []const u8) bool {
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
}

fn actualCaptureHostingerPathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    if (std.mem.eql(u8, name, "virtualMachineId") and hints.hostinger_vps.len != 0) return hints.hostinger_vps[0].id;
    if (std.mem.eql(u8, name, "domain")) return actualCaptureHostingerDomainHint(route, hints);
    if (std.mem.eql(u8, name, "username")) return actualCaptureHostingerUsernameHint(route, hints);
    if (std.mem.eql(u8, name, "actionId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getActionDetailsV1", "VPS_getActionsV1");
    if (std.mem.eql(u8, name, "templateId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getTemplateDetailsV1", "VPS_getTemplatesV1");
    if (std.mem.eql(u8, name, "postInstallScriptId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getPostInstallScriptV1", "VPS_getPostInstallScriptsV1");
    if (std.mem.eql(u8, name, "firewallId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getFirewallDetailsV1", "VPS_getFirewallListV1");
    if (std.mem.eql(u8, name, "snapshotId")) return actualCaptureHostingerResourceHint(route, hints, "DNS_getDNSSnapshotV1", "DNS_getDNSSnapshotListV1");
    if (std.mem.eql(u8, name, "whoisId")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "domains_getWHOISProfileV1", "domains_getWHOISProfileUsageV1" }, "domains_getWHOISProfileListV1");
    if (std.mem.eql(u8, name, "websiteId")) return actualCaptureHostingerResourceHint(route, hints, "horizons_getWebsiteV1", "horizons_getWebsitesV1");
    if (std.mem.eql(u8, name, "name")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getPhpMyAdminLinkV1", "hosting_listAccountDatabasesV1");
    if (std.mem.eql(u8, name, "uuid")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getNodeJSBuildLogsV1", "hosting_listNodeJSBuildsV1");
    if (std.mem.eql(u8, name, "projectName")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "VPS_getProjectContentsV1", "VPS_getProjectContainersV1", "VPS_getProjectLogsV1" }, "VPS_getProjectListV1");
    if (std.mem.eql(u8, name, "profileUuid")) return actualCaptureHostingerResourceHint(route, hints, "reach_listProfileSegmentContactsV1", "reach_listProfilesV1");
    if (std.mem.eql(u8, name, "segmentUuid")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "reach_getSegmentDetailsV1", "reach_listSegmentContactsV1", "reach_listProfileSegmentContactsV1" }, "reach_listSegmentsV1");
    return null;
}

fn actualCaptureHostingerResourceHint(route: provider_routes.Route, hints: Hints, detail_operation_id: []const u8, list_kind: []const u8) ?[]const u8 {
    if (route.operation_id == null or !std.mem.eql(u8, route.operation_id.?, detail_operation_id)) return null;
    return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
}

fn actualCaptureHostingerResourceHintForAny(route: provider_routes.Route, hints: Hints, detail_operation_ids: []const []const u8, list_kind: []const u8) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    for (detail_operation_ids) |detail_operation_id| {
        if (std.mem.eql(u8, operation_id, detail_operation_id)) return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
    }
    return null;
}

fn actualCaptureHostingerScopedResourceKindHint(route: provider_routes.Route, hints: Hints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerResourceMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    if (!actualCaptureHostingerUnscopedFallbackAllowed(route, hints, list_kind)) return null;
    return actualCaptureHostingerResourceKindHint(hints, list_kind);
}

fn actualCaptureHostingerResourceKindHint(hints: Hints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerResourceMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.HostingerResourceHintRow) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        const vm_id = actualCaptureHostingerVpsIdHint(hints) orelse return false;
        return actualCaptureHostingerTargetHasParent(row.target, vm_id);
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerInventoryMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.HostingerInventoryHintRow) bool {
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (eqlIgnoreCase(row.username, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.display_name, domain)) return true;
            if (eqlIgnoreCase(row.resource_id, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerUnscopedFallbackAllowed(route: provider_routes.Route, hints: Hints, list_kind: []const u8) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        if (actualCaptureHostingerVpsIdHint(hints)) |vm_id| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, vm_id)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0 or row.username.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.username, username)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len != 0) {
                    saw_scoped_row = true;
                    if (eqlIgnoreCase(row.domain, domain)) return true;
                }
                if (!actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) {
                    saw_scoped_row = true;
                    if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
                }
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len == 0 and row.display_name.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.display_name, domain)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    return true;
}

fn actualCaptureHostingerDomainHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    _ = route;
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.hostinger_inventory) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.display_name)) return row.display_name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    for (hints.hostinger_resources) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerUsernameHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    if (!containsIgnoreCase(operation_id, "hosting_")) return null;
    if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
        for (hints.hostinger_inventory) |row| {
            if (row.username.len == 0) continue;
            if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.resource_id, domain) or eqlIgnoreCase(row.display_name, domain)) return row.username;
        }
    }
    for (hints.hostinger_inventory) |row| {
        if (row.username.len != 0) return row.username;
    }
    return null;
}

fn actualCaptureHostingerOrderIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureHostingerResourceKindHint(hints, "hosting_listOrdersV1")) |value| return value;
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, "hosting_listWebsitesV1") and row.related_id.len != 0) return row.related_id;
    }
    return null;
}

fn actualCaptureHostingerKindCanCarryDomain(kind: []const u8) bool {
    return std.mem.startsWith(u8, kind, "DNS_") or
        std.mem.startsWith(u8, kind, "domains_") or
        std.mem.startsWith(u8, kind, "hosting_") or
        std.mem.startsWith(u8, kind, "horizons_") or
        containsIgnoreCase(kind, "domain") or
        containsIgnoreCase(kind, "website") or
        containsIgnoreCase(kind, "wordpress");
}

fn actualCaptureHostingerVpsIdHint(hints: Hints) ?[]const u8 {
    if (hints.hostinger_vps.len != 0 and hints.hostinger_vps[0].id.len != 0) return hints.hostinger_vps[0].id;
    return actualCaptureHostingerResourceKindHint(hints, "VPS_getVirtualMachinesV1") orelse
        actualCaptureHostingerResourceKindHint(hints, "vps") orelse
        actualCaptureHostingerResourceKindHint(hints, "route-hostinger-vps");
}

fn actualCaptureHostingerRouteNeedsVps(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{virtualMachineId}");
}

fn actualCaptureHostingerRouteNeedsUsername(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{username}");
}

fn actualCaptureHostingerRouteNeedsDomain(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{domain}");
}

fn actualCaptureHostingerTargetHasParent(target: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(target, parent)) return true;
    if (target.len <= parent.len) return false;
    if (target[parent.len] != '/') return false;
    return eqlIgnoreCase(target[0..parent.len], parent);
}

fn actualCaptureHostingerTargetLooksUnscoped(target: []const u8, list_kind: []const u8) bool {
    return target.len == 0 or eqlIgnoreCase(target, list_kind);
}

fn actualCaptureLooksLikeDomain(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.endsWith(u8, value, ".hstgr.cloud")) return false;
    if (value[0] == '.' or value[value.len - 1] == '.') return false;
    if (std.mem.indexOfScalar(u8, value, '.') == null) return false;
    for (value) |byte| {
        if (byte == '/' or byte == ':' or byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') return false;
    }
    return true;
}

pub fn actualCaptureHasQueryParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) bool {
    if (route.provider != .hostinger or route.operation_id == null) return false;
    if (std.mem.eql(u8, route.operation_id.?, "VPS_getMetricsV1") and
        (std.mem.eql(u8, name, "date_from") or std.mem.eql(u8, name, "date_to")))
    {
        return true;
    }
    return std.mem.eql(u8, route.operation_id.?, "hosting_listAvailableDatacentersV1") and
        std.mem.eql(u8, name, "order_id") and
        actualCaptureHostingerOrderIdHint(hints) != null;
}

pub fn actualCaptureQueryParamHint(gpa: Allocator, route: provider_routes.Route, name: []const u8, hints: Hints) !?[]u8 {
    if (!actualCaptureHasQueryParamHint(route, name, hints)) return null;
    if (std.mem.eql(u8, route.operation_id.?, "hosting_listAvailableDatacentersV1") and std.mem.eql(u8, name, "order_id")) {
        if (actualCaptureHostingerOrderIdHint(hints)) |order_id| return try gpa.dupe(u8, order_id);
        return null;
    }
    const now = core_time.currentEpochSeconds() catch return null;
    const day: u64 = 24 * 60 * 60;
    const timestamp = if (std.mem.eql(u8, name, "date_from") and now > day) now - day else now;
    var buf: [17]u8 = undefined;
    const formatted = try core_time.formatUtcMinute(&buf, timestamp);
    return try gpa.dupe(u8, formatted);
}

pub fn actualCaptureSummarizeMissingInputSources(
    gpa: Allocator,
    summary: *SourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: Hints,
) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "path", param.name);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "query", param.name);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "header", param.name);
    }
}

fn actualCaptureSummarizeMissingInputSourceRows(
    gpa: Allocator,
    summary: *SourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: Hints,
    input_source: []const u8,
    input_name: []const u8,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        actualCaptureAddSourceSummary(summary, actualCaptureUnmappedSourceResult(route, input_source, input_name), .{});
        return;
    }
    for (sources) |source| {
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
        const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
        const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
        const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
        actualCaptureAddSourceSummary(summary, actualCaptureSourceResult(source_route, source_state, hints, hint_count, body), body);
    }
}

fn actualCaptureAddSourceSummary(summary: *SourceSummary, result: []const u8, body: SourceBodyEvidence) void {
    summary.total_sources += 1;
    if (std.mem.eql(u8, result, "captured_with_hints")) {
        summary.captured_with_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_empty")) {
        summary.captured_empty += 1;
    } else if (std.mem.eql(u8, result, "captured_without_hints")) {
        summary.captured_without_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_unknown_body")) {
        summary.captured_unknown_body += 1;
    } else if (std.mem.eql(u8, result, "ready_to_capture")) {
        summary.ready_to_capture += 1;
    } else if (std.mem.eql(u8, result, "waiting_for_inputs")) {
        summary.waiting_for_inputs += 1;
    } else if (std.mem.eql(u8, result, "diagnostic_blocked")) {
        summary.diagnostic_blocked += 1;
    } else if (std.mem.eql(u8, result, "captured_error")) {
        summary.captured_error += 1;
    } else if (std.mem.eql(u8, result, "no_official_source")) {
        summary.no_official_source += 1;
    } else if (std.mem.eql(u8, result, "not_in_catalog")) {
        summary.not_in_catalog += 1;
    } else if (std.mem.eql(u8, result, "unmapped")) {
        summary.unmapped += 1;
    } else if (std.mem.eql(u8, result, "not_eligible")) {
        summary.not_eligible += 1;
    }

    if (std.mem.eql(u8, body.shape, "array")) {
        summary.body_array += 1;
    } else if (std.mem.eql(u8, body.shape, "data_array")) {
        summary.body_data_array += 1;
    } else if (std.mem.eql(u8, body.shape, "error_object")) {
        summary.body_error_object += 1;
    } else if (std.mem.eql(u8, body.shape, "no_evidence")) {
        summary.body_no_evidence += 1;
    } else {
        summary.body_other += 1;
    }
}

pub fn actualCaptureFindRouteByOperationId(routes: []const CoverageRoute, provider: provider_routes.Provider, operation_id: []const u8) ?provider_routes.Route {
    for (routes) |row| {
        if (row.route.provider != provider) continue;
        if (row.route.operation_id == null) continue;
        if (std.mem.eql(u8, row.route.operation_id.?, operation_id)) return row.route;
    }
    return null;
}

pub fn actualCaptureUnmappedSourceResult(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "no_official_source";
    return "unmapped";
}

pub fn actualCaptureUnmappedSourceNextAction(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "provide the identifier through config or another collected official surface";
    return "add a source mapping before this input can be planned";
}

pub fn actualCaptureUnmappedSourcePurpose(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "current Hostinger OpenAPI exposes only the Horizons website detail route, not a list route";
    return "no source mapping";
}

fn actualCaptureHostingerNoOfficialSource(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) bool {
    if (route.provider != .hostinger) return false;
    const operation_id = route.operation_id orelse return false;
    return std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "websiteId") and
        std.mem.eql(u8, operation_id, "horizons_getWebsiteV1");
}

pub fn actualCaptureFindSourceEvidence(source_evidence: []const db_store.RouteSourceEvidenceRow, provider: []const u8, operation_id: []const u8) ?db_store.RouteSourceEvidenceRow {
    for (source_evidence) |row| {
        if (!std.mem.eql(u8, row.provider, provider)) continue;
        if (!std.mem.eql(u8, row.operation_id, operation_id)) continue;
        return row;
    }
    return null;
}

pub fn actualCaptureSourceBodyEvidence(gpa: Allocator, evidence: ?db_store.RouteSourceEvidenceRow) !SourceBodyEvidence {
    const row = evidence orelse return .{};
    if (row.raw_json.len == 0) return .{ .shape = "no_body" };
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, row.raw_json, .{}) catch return .{
        .shape = "invalid_json",
        .body_bytes = row.raw_json.len,
    };
    defer parsed.deinit();
    return actualCaptureSourceBodyEvidenceFromValue(parsed.value, row.raw_json.len);
}

pub fn actualCaptureSourceBodyEvidenceFromValue(value: std.json.Value, body_bytes: usize) SourceBodyEvidence {
    return switch (value) {
        .array => |array| .{ .shape = "array", .item_count = array.items.len, .body_bytes = body_bytes },
        .object => |object| blk: {
            if (object.get("data")) |data| {
                break :blk switch (data) {
                    .array => |array| .{ .shape = "data_array", .item_count = array.items.len, .body_bytes = body_bytes },
                    .object => .{ .shape = "data_object", .item_count = 1, .body_bytes = body_bytes },
                    else => .{ .shape = "data_scalar", .body_bytes = body_bytes },
                };
            }
            if (object.get("message") != null or object.get("error") != null) {
                break :blk .{ .shape = "error_object", .body_bytes = body_bytes };
            }
            break :blk .{ .shape = "object", .item_count = 1, .body_bytes = body_bytes };
        },
        else => .{ .shape = "scalar", .body_bytes = body_bytes },
    };
}

fn actualCaptureSourceBodyIsEmptyCollection(body: SourceBodyEvidence) bool {
    if (body.item_count == null or body.item_count.? != 0) return false;
    return std.mem.eql(u8, body.shape, "array") or std.mem.eql(u8, body.shape, "data_array");
}

fn actualCaptureSourceBodyHasItems(body: SourceBodyEvidence) bool {
    if (body.item_count) |count| return count > 0;
    return false;
}

pub fn actualCaptureSourceResult(route: ?provider_routes.Route, state: ?CaptureState, hints: Hints, hint_count: usize, body: SourceBodyEvidence) []const u8 {
    const source_route = route orelse return "not_in_catalog";
    const source_state = state orelse return "not_eligible";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "captured_with_hints"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "captured_empty"
        else if (actualCaptureSourceBodyHasItems(body))
            "captured_without_hints"
        else
            "captured_unknown_body",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true)) "ready_to_capture" else "waiting_for_inputs",
        .non_ok => if (!provider_dispatch.routeLiveCallSupported(source_route) and provider_dispatch.routeDiagnosticReadSupported(source_route)) "diagnostic_blocked" else "captured_error",
    };
}

pub fn actualCaptureSourceNextAction(route: ?provider_routes.Route, state: ?CaptureState, hints: Hints, hint_count: usize, body: SourceBodyEvidence) []const u8 {
    const source_route = route orelse return "update the route catalog or remove the stale hint mapping";
    const source_state = state orelse return "source route is not an eligible read route";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "use collected identifiers for child captures"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "source collection is empty; no child identifiers are available"
        else if (actualCaptureSourceBodyHasItems(body))
            "extend normalization for this non-empty source response"
        else
            "inspect raw source evidence; body shape does not prove an empty collection",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true))
            "capture the source route to discover identifiers"
        else
            "capture the source route prerequisites first",
        .non_ok => if (!provider_dispatch.routeLiveCallSupported(source_route) and provider_dispatch.routeDiagnosticReadSupported(source_route))
            "diagnostic-only source is blocked; child identifiers are unavailable"
        else
            "inspect source capture error before child captures",
    };
}

pub fn actualCaptureSourceHintCount(
    route: provider_routes.Route,
    hints: Hints,
    input_source: []const u8,
    input_name: []const u8,
    source: InputSource,
) usize {
    if (route.provider != .hostinger) return 0;
    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) {
            var count = hints.configured_domains.len;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.display_name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            return count;
        }
        if (std.mem.eql(u8, input_name, "virtualMachineId")) {
            var count = hints.hostinger_vps.len;
            count += actualCaptureHostingerKindHintCount(hints, source.hint_kind);
            return count;
        }
        if (std.mem.eql(u8, input_name, "username")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.username.len != 0) count += 1;
            }
            return count;
        }
    }

    if (std.mem.eql(u8, input_source, "query") and std.mem.eql(u8, input_name, "order_id")) {
        if (std.mem.eql(u8, source.hint_kind, "hosting_listWebsitesV1")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.related_id.len != 0) count += 1;
            }
            return count;
        }
    }

    return actualCaptureHostingerKindHintCount(hints, source.hint_kind);
}

fn actualCaptureHostingerKindHintCount(hints: Hints, kind: []const u8) usize {
    var count: usize = 0;
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    return count;
}

pub fn actualCaptureMissingInputSources(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const InputSource {
    if (route.provider != .hostinger) return &.{};
    const operation_id = route.operation_id orelse return &.{};

    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) return hostinger_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "virtualMachineId")) return hostinger_vps_sources[0..];
        if (std.mem.eql(u8, input_name, "actionId")) return hostinger_action_sources[0..];
        if (std.mem.eql(u8, input_name, "templateId")) return hostinger_template_sources[0..];
        if (std.mem.eql(u8, input_name, "firewallId")) return hostinger_firewall_sources[0..];
        if (std.mem.eql(u8, input_name, "postInstallScriptId")) return hostinger_post_install_sources[0..];
        if (std.mem.eql(u8, input_name, "snapshotId") and std.mem.eql(u8, operation_id, "DNS_getDNSSnapshotV1")) return hostinger_dns_snapshot_sources[0..];
        if (std.mem.eql(u8, input_name, "whoisId") and (std.mem.eql(u8, operation_id, "domains_getWHOISProfileV1") or std.mem.eql(u8, operation_id, "domains_getWHOISProfileUsageV1"))) return hostinger_whois_sources[0..];
        if (std.mem.eql(u8, input_name, "username") and std.mem.startsWith(u8, operation_id, "hosting_")) return hostinger_username_sources[0..];
        if (std.mem.eql(u8, input_name, "name") and std.mem.eql(u8, operation_id, "hosting_getPhpMyAdminLinkV1")) return hostinger_database_sources[0..];
        if (std.mem.eql(u8, input_name, "uuid") and std.mem.eql(u8, operation_id, "hosting_getNodeJSBuildLogsV1")) return hostinger_nodejs_build_sources[0..];
        if (std.mem.eql(u8, input_name, "projectName") and std.mem.startsWith(u8, operation_id, "VPS_getProject")) return hostinger_docker_project_sources[0..];
        if (std.mem.eql(u8, input_name, "profileUuid") and std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1")) return hostinger_reach_profile_sources[0..];
        if (std.mem.eql(u8, input_name, "segmentUuid") and (std.mem.eql(u8, operation_id, "reach_getSegmentDetailsV1") or std.mem.eql(u8, operation_id, "reach_listSegmentContactsV1") or std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1"))) return hostinger_reach_segment_sources[0..];
    }

    if (std.mem.eql(u8, input_source, "query")) {
        if (std.mem.eql(u8, input_name, "order_id") and std.mem.eql(u8, operation_id, "hosting_listAvailableDatacentersV1")) return hostinger_order_sources[0..];
    }

    return &.{};
}

test "plans Hostinger VPS metrics inputs from VPS and synthetic date hints" {
    const allocator = std.testing.allocator;
    const route_json =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, route_json, .{});
    defer parsed.deinit();
    const route = try provider_routes.Route.init(allocator, .hostinger, parsed.value);
    defer route.deinit(allocator);

    var vps_rows = [_]db_store.HostingerVpsRow{.{
        .id = @constCast("1307809"),
        .name = @constCast("plosca"),
        .status = @constCast("running"),
        .ipv4 = @constCast(""),
        .plan = @constCast(""),
        .updated_at = @constCast(""),
    }};
    const hints = Hints{ .hostinger_vps = vps_rows[0..] };

    try std.testing.expect(actualCaptureReady(route, hints));
    try std.testing.expectEqualStrings("1307809", actualCapturePathParamHint(route, "virtualMachineId", hints) orelse "");
    try std.testing.expect(actualCaptureHasQueryParamHint(route, "date_from", hints));
    try std.testing.expect(actualCaptureHasQueryParamHint(route, "date_to", hints));

    const date_from = (try actualCaptureQueryParamHint(allocator, route, "date_from", hints)) orelse return error.ExpectedDateFromHint;
    defer allocator.free(date_from);
    const date_to = (try actualCaptureQueryParamHint(allocator, route, "date_to", hints)) orelse return error.ExpectedDateToHint;
    defer allocator.free(date_to);
    try std.testing.expectEqual(@as(usize, 17), date_from.len);
    try std.testing.expectEqual(@as(usize, 17), date_to.len);
    try std.testing.expect(date_from[10] == 'T' and date_from[16] == 'Z');
    try std.testing.expect(date_to[10] == 'T' and date_to[16] == 'Z');
}
