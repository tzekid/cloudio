const std = @import("std");
const cli_root = @import("cli/root.zig");

pub fn main(init: std.process.Init) !void {
    try cli_root.run(init);
}

// A single root module only runs tests from files a test block references.
test {
    _ = @import("app/authentication.zig");
    _ = @import("app/browser_run.zig");
    _ = @import("app/caddy_desired.zig");
    _ = @import("app/dashboard.zig");
    _ = @import("app/database.zig");
    _ = @import("app/dns.zig");
    _ = @import("app/doctor.zig");
    _ = @import("app/init.zig");
    _ = @import("app/maintenance.zig");
    _ = @import("app/nob_projects.zig");
    _ = @import("app/nob_secrets.zig");
    _ = @import("app/provider_writes.zig");
    _ = @import("app/refresh.zig");
    _ = @import("app/system_control.zig");
    _ = @import("app/vps.zig");
    _ = @import("app/writes.zig");
    _ = @import("cli/args.zig");
    _ = @import("cli/auth.zig");
    _ = @import("cli/maintenance.zig");
    _ = @import("cli/nob.zig");
    _ = @import("cli/render.zig");
    _ = @import("cli/root.zig");
    _ = @import("cli/serve.zig");
    _ = @import("collectors/caddy.zig");
    _ = @import("collectors/project_manifests.zig");
    _ = @import("collectors/projects.zig");
    _ = @import("collectors/system.zig");
    _ = @import("core/config.zig");
    _ = @import("core/fs.zig");
    _ = @import("core/json.zig");
    _ = @import("core/output.zig");
    _ = @import("core/process.zig");
    _ = @import("core/redact.zig");
    _ = @import("core/time.zig");
    _ = @import("core/url.zig");
    _ = @import("core/version.zig");
    _ = @import("db/schema.zig");
    _ = @import("db/store.zig");
    _ = @import("http/request.zig");
    _ = @import("http/response.zig");
    _ = @import("http/root.zig");
    _ = @import("http/router.zig");
    _ = @import("http/static.zig");
    _ = @import("net/http.zig");
    _ = @import("nob/bootstrap.zig");
    _ = @import("nob/broker.zig");
    _ = @import("nob/id.zig");
    _ = @import("nob/independent_observation.zig");
    _ = @import("nob/managed_unit.zig");
    _ = @import("nob/model.zig");
    _ = @import("nob/protocol.zig");
    _ = @import("nob/resource_control.zig");
    _ = @import("nob/source.zig");
    _ = @import("nob/subprocess.zig");
    _ = @import("nob/systemd.zig");
    _ = @import("runtime/nob_workers.zig");
    _ = @import("security/passkeys.zig");
    _ = @import("server/api.zig");
    _ = @import("server/auth.zig");
    _ = @import("server/form.zig");
    _ = @import("server/forms.zig");
    _ = @import("server/pages.zig");
    _ = @import("server/pipeline.zig");
    _ = @import("server/rate_limit.zig");
    _ = @import("server/root.zig");
    _ = @import("server/theme.zig");
}
