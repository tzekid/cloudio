const std = @import("std");

pub const version = "0.1.0-poc";

pub const core = struct {
    pub const config = @import("core_config");
    pub const fs = @import("core_fs");
    pub const json = @import("core_json");
    pub const log = @import("core_log");
    pub const process = @import("core_process");
    pub const redact = @import("core_redact");
    pub const time = @import("core_time");
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
    pub const exports = @import("app_export");
    pub const hostinger = @import("app_hostinger");
    pub const init = @import("app_init");
    pub const log = @import("app_log");
    pub const overview = @import("app_overview");
    pub const projects = @import("app_projects");
    pub const refresh = @import("app_refresh");
    pub const system = @import("app_system");
};

pub const net = struct {
    pub const http = @import("net_http");
    pub const pagination = @import("net_pagination");
};

pub const providers = struct {
    pub const dispatch = @import("provider_dispatch");
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

pub const collectors = struct {
    pub const capture = @import("collector_capture");
    pub const caddy = @import("collector_caddy");
    pub const cloudflare = @import("collector_cloudflare");
    pub const hostinger = @import("collector_hostinger");
    pub const projects = @import("collector_projects");
    pub const system = @import("collector_system");
};

test "facade exposes stable integration modules" {
    try std.testing.expectEqualStrings("0.1.0-poc", version);
    _ = core.config.Config;
    _ = core.fs.ensureParentDir;
    _ = app.caddy.Context;
    _ = app.cloudflare.Context;
    _ = app.coverage.Summary;
    _ = app.coverage.CaptureOptions;
    _ = app.doctor.Report;
    _ = app.exports.writeRecentSnapshotsJson;
    _ = app.hostinger.Context;
    _ = app.init.Result;
    _ = app.log.Context;
    _ = app.overview.Overview;
    _ = app.projects.Context;
    _ = app.refresh.Selection;
    _ = app.system.Context;
    _ = db.schema.Migration;
    _ = db.store.Db;
    _ = net.http.Response;
    _ = net.pagination.PageInfo;
    _ = providers.dispatch.Client;
    _ = providers.dispatch.ReadRouteResult;
    _ = providers.routes.Route;
    _ = providers.cloudflare.client.Client;
    _ = providers.hostinger.client.Client;
    _ = collectors.capture.Output;
    _ = collectors.caddy.Paths;
}
