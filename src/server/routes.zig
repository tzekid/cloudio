const http = @import("http");
const types = @import("types.zig");
const apps = @import("handlers/apps.zig");
const caddy = @import("handlers/caddy.zig");
const dashboard = @import("handlers/dashboard.zig");
const providers = @import("handlers/providers.zig");
const refresh = @import("handlers/refresh.zig");
const nob = @import("handlers/nob.zig");
const authentication = @import("handlers/authentication.zig");
const system = @import("handlers/system.zig");

pub const all = [_]types.Route{
    route("GET", "/api/dashboard", dashboard.dashboard),
    route("GET", "/api/topology", dashboard.topology),
    route("GET", "/api/topology/changes", dashboard.topologyChanges),
    route("GET", "/api/inventory", dashboard.inventory),
    route("POST", "/api/actions/plan", dashboard.actionsPlan),
    route("GET", "/api/audit", dashboard.audit),
    publicRoute("POST", "/api/auth/setup/options", authentication.setupOptions),
    publicRoute("POST", "/api/auth/setup/verify", authentication.setupVerify),
    publicRoute("POST", "/api/auth/login/options", authentication.loginOptions),
    publicRoute("POST", "/api/auth/login/verify", authentication.loginVerify),
    route("GET", "/api/auth/session", authentication.session),
    route("POST", "/api/auth/logout", authentication.logout),
    route("GET", "/api/auth/credentials", authentication.credentials),
    route("POST", "/api/auth/credentials/options", authentication.credentialOptions),
    route("POST", "/api/auth/credentials/verify", authentication.credentialVerify),
    route("PATCH", "/api/auth/credentials/:id", authentication.credentialLabel),
    route("DELETE", "/api/auth/credentials/:id", authentication.credentialRevoke),
    route("GET", "/api/caddy/routes", caddy.routesGet),
    mutation("POST", "/api/caddy/routes", caddy.routesPost, false),
    mutation("DELETE", "/api/caddy/routes", caddy.routesDelete, true),
    mutation("POST", "/api/caddy/routes/toggle", caddy.routesToggle, false),
    route("GET", "/api/caddy/preview", caddy.preview),
    mutation("POST", "/api/caddy/apply", caddy.apply, true),
    mutation("POST", "/api/caddy/import", caddy.importRoutes, false),
    route("GET", "/api/dns/records", providers.dnsRecordsGet),
    mutation("POST", "/api/dns/records", providers.dnsRecordsPost, false),
    mutation("PUT", "/api/dns/records", providers.dnsRecordsPut, false),
    mutation("DELETE", "/api/dns/records", providers.dnsRecordsDelete, true),
    mutation("POST", "/api/cache/purge", providers.cachePurge, true),
    mutation("POST", "/api/zone/setting", providers.zoneSetting, false),
    route("GET", "/api/vps", providers.vpsGet),
    mutation("POST", "/api/vps/action", providers.vpsAction, true),
    route("GET", "/api/firewalls", providers.firewallsGet),
    mutation("POST", "/api/firewall/rule", providers.firewallRulePost, false),
    mutation("PUT", "/api/firewall/rule", providers.firewallRulePut, false),
    mutation("DELETE", "/api/firewall/rule", providers.firewallRuleDelete, true),
    mutation("POST", "/api/firewall/sync", providers.firewallSync, true),
    route("GET", "/api/containers", system.containersGet),
    mutation("POST", "/api/containers/action", system.containersAction, true),
    route("GET", "/api/containers/logs", system.containersLogs),
    mutation("POST", "/api/refresh", refresh.now, false),
    route("GET", "/api/nob/projects", nob.list),
    route("GET", "/api/nob/projects/:id", nob.details),
    route("GET", "/api/nob/projects/:id/secrets", nob.secrets),
    mutation("PUT", "/api/nob/projects/:id/secrets/:secret", nob.bindSecret, true),
    mutation("DELETE", "/api/nob/projects/:id/secrets/:secret", nob.unbindSecret, true),
    mutation("POST", "/api/nob/scan", nob.scan, false),
    mutation("POST", "/api/nob/projects/:id/trust", nob.trustProject, true),
    mutation("POST", "/api/nob/projects/:id/revoke", nob.revokeProject, true),
    mutation("POST", "/api/nob/projects/:id/prepare", nob.prepareProject, false),
    mutation("POST", "/api/nob/projects/:id/observe", nob.observeProject, false),
    mutation("POST", "/api/nob/projects/:id/actions/:action/plan", nob.planAction, false),
    mutation("POST", "/api/nob/projects/:id/actions/:action/run", nob.runAction, true),
    mutation("POST", "/api/nob/projects/:id/resources/:resource/:control/plan", nob.planResourceControl, false),
    mutation("POST", "/api/nob/projects/:id/resources/:resource/:control/run", nob.runResourceControl, true),
    route("GET", "/api/nob/projects/:id/resources/:resource/logs", nob.resourceLogs),
    route("GET", "/api/nob/operations", nob.operations),
    route("GET", "/api/nob/operations/:id", nob.operationDetails),
    route("GET", "/api/nob/operations/:id/events", nob.operationEvents),
    route("GET", "/api/nob/operations/:id/log", nob.operationLog),
    mutation("POST", "/api/nob/operations/:id/cancel", nob.cancelOperation, true),
    route("GET", "/api/apps", apps.list),
    mutation("POST", "/api/apps", apps.register, false),
    route("GET", "/api/apps/:name/:action", apps.details),
    mutation("POST", "/api/apps/:name/:action", apps.action, true),
    mutation("DELETE", "/api/apps/:name", apps.delete, true),
};

fn route(method: []const u8, pattern: []const u8, handler: types.BufferedHandler) types.Route {
    return .{ .method = method, .pattern = pattern, .handler = handler };
}

fn publicRoute(method: []const u8, pattern: []const u8, handler: types.BufferedHandler) types.Route {
    return .{ .method = method, .pattern = pattern, .handler = handler, .access = .public };
}

fn mutation(method: []const u8, pattern: []const u8, handler: types.BufferedHandler, destructive: bool) types.Route {
    return .{
        .method = method,
        .pattern = pattern,
        .handler = handler,
        .mutation = if (destructive) .destructive else .idempotent,
    };
}

test "route table distinguishes match method miss and named params" {
    const deploy_match = http.router.match(types.Route, &all, "POST", "/api/apps/cloudio/deploy").?;
    try @import("std").testing.expectEqualStrings("cloudio", deploy_match.params.get("name").?);
    try @import("std").testing.expectEqualStrings("deploy", deploy_match.params.get("action").?);
    const nob_match = http.router.match(types.Route, &all, "POST", "/api/nob/projects/42/trust").?;
    try @import("std").testing.expectEqualStrings("42", nob_match.params.get("id").?);
    try @import("std").testing.expectEqual(types.Mutation.destructive, nob_match.route.mutation);
    const secret_match = http.router.match(types.Route, &all, "PUT", "/api/nob/projects/42/secrets/database-token").?;
    try @import("std").testing.expectEqualStrings("database-token", secret_match.params.get("secret").?);
    try @import("std").testing.expectEqual(types.Mutation.destructive, secret_match.route.mutation);
    try @import("std").testing.expect(http.router.match(types.Route, &all, "PATCH", "/api/apps") == null);
    try @import("std").testing.expect(http.router.pathExists(types.Route, &all, "/api/apps"));
}
