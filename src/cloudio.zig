const std = @import("std");
const core_version = @import("core_version");

pub const version = core_version.value;

pub const core = struct {
    pub const config = @import("core_config");
    pub const fs = @import("core_fs");
    pub const json = @import("core_json");
    pub const log = @import("core_log");
    pub const output = @import("core_output");
    pub const process = @import("core_process");
    pub const redact = @import("core_redact");
    pub const time = @import("core_time");
    pub const version = core_version;
};

pub const db = struct {
    pub const schema = @import("db_schema");
    pub const store = @import("db_store");
};

pub const app = struct {
    pub const caddy = @import("app_caddy");
    pub const cloudflare = @import("app_cloudflare");
    pub const coverage = @import("app_coverage");
    pub const doctor = @import("app_doctor");
    pub const evidence = @import("app_evidence");
    pub const exports = @import("app_export");
    pub const history = @import("app_history");
    pub const hostinger = @import("app_hostinger");
    pub const init = @import("app_init");
    pub const inventory = @import("app_inventory");
    pub const log = @import("app_log");
    pub const overview = @import("app_overview");
    pub const projects = @import("app_projects");
    pub const provider_list = @import("app_provider_list");
    pub const refresh = @import("app_refresh");
    pub const route_catalog = @import("app_route_catalog");
    pub const system = @import("app_system");
    pub const topology = @import("app_topology");
};

pub const net = struct {
    pub const http = @import("net_http");
    pub const pagination = @import("net_pagination");
};

pub const providers = struct {
    pub const capabilities = @import("provider_capabilities");
    pub const dispatch = @import("provider_dispatch");
    pub const route_plan = @import("provider_route_plan");
    pub const routes = @import("provider_routes");

    pub const cloudflare = struct {
        pub const client = @import("provider_cloudflare");
        pub const models = @import("provider_cloudflare_models");
    };

    pub const hostinger = struct {
        pub const client = @import("provider_hostinger");
        pub const models = @import("provider_hostinger_models");
    };
};

test "facade exposes stable integration modules" {
    try std.testing.expectEqualStrings("0.1.0-poc", version);
    _ = core.config.Config;
    _ = core.fs.ensureParentDir;
    _ = core.output.Output;
    _ = app.caddy.Context;
    _ = app.cloudflare.Context;
    _ = app.cloudflare.AccountEndpoint;
    _ = app.cloudflare.DnsRecordMutationArgs;
    _ = app.coverage.Summary;
    _ = app.coverage.CaptureOptions;
    _ = app.doctor.Report;
    _ = app.evidence.Evidence;
    _ = app.evidence.Matrix;
    _ = app.evidence.RouteCaptures;
    _ = app.evidence.RouteCoverage;
    _ = app.evidence.RouteCaptureSummary;
    _ = app.exports.writeRecentSnapshotsJson;
    _ = app.history.History;
    _ = app.hostinger.Context;
    _ = app.hostinger.HostingArgs;
    _ = app.hostinger.VmEndpoint;
    _ = app.init.Result;
    _ = app.inventory.Context;
    _ = app.inventory.Provider;
    _ = app.log.Context;
    _ = app.overview.Overview;
    _ = app.projects.Context;
    _ = app.provider_list.Options;
    _ = app.refresh.Selection;
    _ = app.route_catalog.Catalog;
    _ = app.route_catalog.GroupReport;
    _ = app.system.Context;
    _ = app.topology.Topology;
    _ = db.schema.Migration;
    _ = db.store.Db;
    _ = net.http.Response;
    _ = net.pagination.PageInfo;
    _ = providers.capabilities.RouteCapabilities;
    _ = providers.dispatch.Client;
    _ = providers.dispatch.ReadRouteResult;
    _ = providers.route_plan.planRouteJsonRequest;
    _ = providers.routes.Route;
    _ = providers.cloudflare.client.Client;
    _ = providers.cloudflare.models.AccountRow;
    _ = providers.hostinger.client.Client;
    _ = providers.hostinger.models.VpsRow;
}
