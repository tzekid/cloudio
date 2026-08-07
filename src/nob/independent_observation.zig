const std = @import("std");
const core_config = @import("core_config");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Status = nob.types.Status;

const max_caddyfile_bytes = 8 * 1024 * 1024;
const max_caddy_runtime_bytes = 4 * 1024 * 1024;

pub const Resource = struct {
    resource_id: []u8,
    status: Status,
    summary: []u8,
    observation_json: []u8,

    pub fn deinit(self: Resource, allocator: Allocator) void {
        allocator.free(self.resource_id);
        allocator.free(self.summary);
        allocator.free(self.observation_json);
    }
};

pub const Result = struct {
    status: Status,
    summary: []u8,
    resources: []Resource,

    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.summary);
        for (self.resources) |resource| resource.deinit(allocator);
        allocator.free(self.resources);
    }
};

const Evidence = struct {
    status: Status,
    summary: []u8,
    json: []u8,

    fn deinit(self: Evidence, allocator: Allocator) void {
        allocator.free(self.summary);
        allocator.free(self.json);
    }
};

pub fn run(
    io: Io,
    allocator: Allocator,
    root_path: []const u8,
    manifest_sha256: []const u8,
    config: core_config.Config,
    runner: *const nob.types.Observation,
) !Result {
    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "nob.json" });
    defer allocator.free(manifest_path);
    const bytes = try Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(nob.manifest.max_manifest_bytes));
    defer allocator.free(bytes);
    var document = try nob.parseManifest(allocator, bytes);
    defer document.deinit();
    var digest_buffer: [64]u8 = undefined;
    if (!std.mem.eql(u8, document.sha256Hex(&digest_buffer), manifest_sha256)) return error.ManifestDigestMismatch;
    const manifest = document.value();
    if (!std.mem.eql(u8, runner.project_id, manifest.project.id)) return error.ProjectIdentityMismatch;
    if (!std.mem.eql(u8, runner.manifest_sha256, manifest_sha256)) return error.ManifestIdentityMismatch;

    const resources = try allocator.alloc(Resource, manifest.resources.len);
    errdefer allocator.free(resources);
    var initialized: usize = 0;
    errdefer for (resources[0..initialized]) |resource| resource.deinit(allocator);

    var overall = runner.status;
    for (manifest.resources, 0..) |resource, index| {
        const evidence = probeResource(io, allocator, root_path, config, manifest, resource) catch |err|
            try unavailable(allocator, resource, "Cloudio could not complete this independent check", err);
        defer evidence.deinit(allocator);
        const runner_resource = findRunnerResource(runner.resources, resource.id);
        const effective = mergeStatus(if (runner_resource) |value| value.status else .unknown, evidence.status);
        const summary = try mergeSummary(
            allocator,
            if (runner_resource) |value| value.summary else "runner omitted this resource",
            if (runner_resource) |value| value.status else .unknown,
            evidence.summary,
            evidence.status,
            effective,
        );
        resources[index] = .{
            .resource_id = try allocator.dupe(u8, resource.id),
            .status = effective,
            .summary = summary,
            .observation_json = try allocator.dupe(u8, evidence.json),
        };
        initialized += 1;
        overall = mergeProjectStatus(overall, effective);
    }

    const summary = if (overall == runner.status)
        try allocator.dupe(u8, runner.summary)
    else
        try std.fmt.allocPrint(
            allocator,
            "runner reported {s}; Cloudio verification resolved project status to {s}",
            .{ @tagName(runner.status), @tagName(overall) },
        );
    return .{ .status = overall, .summary = summary, .resources = resources };
}

fn probeResource(
    io: Io,
    allocator: Allocator,
    root_path: []const u8,
    config: core_config.Config,
    manifest: *const nob.types.Manifest,
    resource: nob.types.Resource,
) !Evidence {
    const runtime = config.runtime_environment;
    return switch (resource.kind) {
        .@"systemd.service" => probeSystemd(io, allocator, runtime, resource),
        .@"endpoint.http" => probeHttp(io, allocator, runtime, resource),
        .@"endpoint.tcp" => probeTcp(io, allocator, resource),
        .@"release.directory" => probeRelease(io, allocator, root_path, runtime, resource),
        .@"artifact.executable" => probeArtifact(io, allocator, root_path, runtime, manifest, resource),
        .@"data.path" => probeDataPath(io, allocator, root_path, runtime, resource),
        .process => probeProcess(io, allocator, root_path, runtime, resource),
        .@"docker.compose" => inspectCompose(io, allocator, root_path, resource),
        .@"caddy.route" => probeCaddyRoute(io, allocator, config, resource),
    };
}

fn probeSystemd(io: Io, allocator: Allocator, runtime: core_config.RuntimeEnvironment, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const scope = stringField(spec, "scope") orelse return error.InvalidResourceSpec;
    const unit = stringField(spec, "unit") orelse return error.InvalidResourceSpec;
    const systemctl = subprocess.resolveExecutable(io, allocator, "systemctl", runtime.path) catch |err|
        return unavailable(allocator, resource, "systemctl is unavailable", err);
    defer allocator.free(systemctl);
    var environment = try subprocess.makeEnvironment(allocator, runtime, &.{});
    defer environment.deinit();
    const properties = "LoadState,ActiveState,SubState,UnitFileState,FragmentPath,MainPID";
    const user_args = [_][]const u8{ systemctl, "--user", "show", "--no-pager", "--property", properties, unit };
    const system_args = [_][]const u8{ systemctl, "show", "--no-pager", "--property", properties, unit };
    const args: []const []const u8 = if (std.mem.eql(u8, scope, "user")) &user_args else &system_args;
    const command = subprocess.run(allocator, io, args, "/", &environment, .{
        .stdout_bytes = 64 * 1024,
        .stderr_bytes = 16 * 1024,
        .timeout_seconds = 15,
    }) catch |err| return unavailable(allocator, resource, "systemd query failed", err);
    defer command.deinit(allocator);

    const state = parseSystemdShow(command.stdout);
    const desired = spec.get("desired").?.object;
    const desired_active = boolField(desired, "active");
    const desired_enabled = boolField(desired, "enabled");
    var status: Status = if (std.mem.eql(u8, state.load, "not-found"))
        .missing
    else if (std.mem.eql(u8, state.active, "active"))
        .healthy
    else if (std.mem.eql(u8, state.active, "failed"))
        .degraded
    else if (std.mem.eql(u8, state.active, "inactive") or std.mem.eql(u8, state.active, "deactivating"))
        .stopped
    else
        .unknown;
    const enabled = enabledState(state.unit_file);
    const active = std.mem.eql(u8, state.active, "active");
    const active_mismatch = if (desired_active) |wanted| wanted != active else false;
    const enabled_mismatch = if (desired_enabled) |wanted| wanted != enabled else false;
    if (status == .healthy and (active_mismatch or enabled_mismatch)) status = .degraded;
    if (!command.successful() and state.load.len == 0) status = .unknown;

    const summary = if (state.load.len == 0)
        "systemd returned no unit state"
    else if (status == .missing)
        "declared systemd unit was not found"
    else if (active_mismatch or enabled_mismatch)
        "systemd unit differs from its declared desired state"
    else if (status == .healthy)
        "systemd unit is active and matches its declared state"
    else if (status == .stopped)
        "systemd unit is not active"
    else if (status == .degraded)
        "systemd unit is failed"
    else
        "systemd unit state is unknown";
    const facts = .{
        .scope = scope,
        .unit = unit,
        .load_state = state.load,
        .active_state = state.active,
        .sub_state = state.sub,
        .unit_file_state = state.unit_file,
        .fragment_path = state.fragment,
        .main_pid = state.main_pid,
        .desired_active = desired_active,
        .desired_enabled = desired_enabled,
        .active_mismatch = active_mismatch,
        .enabled_mismatch = enabled_mismatch,
    };
    return makeEvidence(allocator, resource, status, summary, facts);
}

fn probeHttp(io: Io, allocator: Allocator, runtime: core_config.RuntimeEnvironment, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const url = stringField(spec, "url") orelse return error.InvalidResourceSpec;
    const method = stringField(spec, "method") orelse return error.InvalidResourceSpec;
    const timeout_ms = intField(spec, "timeout_ms") orelse return error.InvalidResourceSpec;
    const curl = subprocess.resolveExecutable(io, allocator, "curl", runtime.path) catch |err|
        return unavailable(allocator, resource, "curl is unavailable", err);
    defer allocator.free(curl);
    const timeout_seconds = try std.fmt.allocPrint(allocator, "{d}", .{@max(1, @divTrunc(timeout_ms + 999, 1000))});
    defer allocator.free(timeout_seconds);
    var environment = try subprocess.makeEnvironment(allocator, runtime, &.{});
    defer environment.deinit();
    const args = [_][]const u8{
        curl,
        "--disable",
        "--silent",
        "--show-error",
        "--noproxy",
        "*",
        "--max-time",
        timeout_seconds,
        "--output",
        "/dev/null",
        "--write-out",
        "%{http_code}",
        "--request",
        method,
        url,
    };
    const command = subprocess.run(allocator, io, &args, "/", &environment, .{
        .stdout_bytes = 64,
        .stderr_bytes = 16 * 1024,
        .timeout_seconds = @intCast(@max(2, @divTrunc(timeout_ms + 1999, 1000))),
    }) catch |err| return unavailable(allocator, resource, "HTTP probe failed", err);
    defer command.deinit(allocator);
    const code = std.fmt.parseInt(u16, std.mem.trim(u8, command.stdout, " \t\r\n"), 10) catch 0;
    const expected = expectedHttpStatus(spec, code);
    const status: Status = if (!command.successful()) .stopped else if (expected) .healthy else .degraded;
    const summary = if (!command.successful())
        "loopback HTTP endpoint did not respond"
    else if (expected)
        "loopback HTTP endpoint returned an expected status"
    else
        "loopback HTTP endpoint returned an unexpected status";
    return makeEvidence(allocator, resource, status, summary, .{
        .url = url,
        .method = method,
        .status_code = code,
        .expected = expected,
    });
}

fn probeTcp(io: Io, allocator: Allocator, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const host = stringField(spec, "host") orelse return error.InvalidResourceSpec;
    const port: u16 = @intCast(intField(spec, "port") orelse return error.InvalidResourceSpec);
    const timeout_ms: u32 = @intCast(intField(spec, "timeout_ms") orelse return error.InvalidResourceSpec);
    nob.health.probeTcp(io, host, port, timeout_ms) catch |err| {
        return makeEvidence(allocator, resource, .stopped, "loopback TCP endpoint is not accepting connections", .{
            .host = host,
            .port = port,
            .reachable = false,
            .error_name = @errorName(err),
        });
    };
    return makeEvidence(allocator, resource, .healthy, "loopback TCP endpoint accepted a connection", .{
        .host = host,
        .port = port,
        .reachable = true,
        .error_name = @as(?[]const u8, null),
    });
}

fn probeRelease(io: Io, allocator: Allocator, root_path: []const u8, runtime: core_config.RuntimeEnvironment, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const root = try expandPath(allocator, stringField(spec, "root") orelse return error.InvalidResourceSpec, root_path, runtime);
    defer allocator.free(root);
    const current_name = stringField(spec, "current") orelse return error.InvalidResourceSpec;
    const current = try std.fs.path.join(allocator, &.{ root, current_name });
    defer allocator.free(current);
    const root_stat = Io.Dir.cwd().statFile(io, root, .{ .follow_symlinks = true }) catch null;
    const current_stat = Io.Dir.cwd().statFile(io, current, .{ .follow_symlinks = true }) catch null;
    const root_exists = root_stat != null and root_stat.?.kind == .directory;
    const current_exists = current_stat != null and current_stat.?.kind == .directory;
    const status: Status = if (!root_exists) .missing else if (!current_exists) .stopped else .healthy;
    const summary = if (!root_exists)
        "release root does not exist"
    else if (!current_exists)
        "current release does not resolve to a directory"
    else
        "current release directory is available";
    return makeEvidence(allocator, resource, status, summary, .{
        .root = root,
        .current = current,
        .root_exists = root_exists,
        .current_exists = current_exists,
    });
}

fn probeArtifact(
    io: Io,
    allocator: Allocator,
    root_path: []const u8,
    runtime: core_config.RuntimeEnvironment,
    manifest: *const nob.types.Manifest,
    resource: nob.types.Resource,
) !Evidence {
    const spec = resource.spec.object;
    const release_id = stringField(spec, "release_resource") orelse return error.InvalidResourceSpec;
    const relative = stringField(spec, "path") orelse return error.InvalidResourceSpec;
    const release = findManifestResource(manifest.resources, release_id) orelse return error.UnknownResource;
    const release_root = try expandPath(allocator, stringField(release.spec.object, "root") orelse return error.InvalidResourceSpec, root_path, runtime);
    defer allocator.free(release_root);
    const current = stringField(release.spec.object, "current") orelse return error.InvalidResourceSpec;
    const path = try std.fs.path.join(allocator, &.{ release_root, current, relative });
    defer allocator.free(path);
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch null;
    const exists = stat != null and stat.?.kind == .file;
    const executable = exists and (@backingInt(stat.?.permissions) & 0o111 != 0);
    const status: Status = if (!exists) .missing else if (!executable) .degraded else .healthy;
    const summary = if (!exists) "declared executable is missing" else if (!executable) "declared artifact is not executable" else "declared executable is available";
    return makeEvidence(allocator, resource, status, summary, .{
        .path = path,
        .exists = exists,
        .executable = executable,
    });
}

fn probeDataPath(io: Io, allocator: Allocator, root_path: []const u8, runtime: core_config.RuntimeEnvironment, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const path = try expandPath(allocator, stringField(spec, "path") orelse return error.InvalidResourceSpec, root_path, runtime);
    defer allocator.free(path);
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch null;
    const status: Status = if (stat == null) .missing else .healthy;
    return makeEvidence(allocator, resource, status, if (stat == null) "declared data path is missing" else "declared data path exists", .{
        .path = path,
        .exists = stat != null,
        .kind = if (stat) |value| @tagName(value.kind) else null,
        .size = if (stat) |value| value.size else null,
        .classification = stringField(spec, "classification").?,
        .backup_policy = stringField(spec, "backup_policy").?,
    });
}

fn probeProcess(io: Io, allocator: Allocator, root_path: []const u8, runtime: core_config.RuntimeEnvironment, resource: nob.types.Resource) !Evidence {
    const spec = resource.spec.object;
    const match = stringField(spec, "match") orelse return error.InvalidResourceSpec;
    const pid = if (stringField(spec, "pid_file")) |template| pid: {
        const path = try expandPath(allocator, template, root_path, runtime);
        defer allocator.free(path);
        break :pid try pidFromFile(io, allocator, path);
    } else try findProcess(io, allocator, match);
    const running = pid != null;
    return makeEvidence(allocator, resource, if (running) .healthy else .stopped, if (running) "declared process is running" else "declared process is not running", .{
        .match = match,
        .running = running,
        .pid = pid,
    });
}

fn inspectCompose(io: Io, allocator: Allocator, root_path: []const u8, resource: nob.types.Resource) !Evidence {
    const file = stringField(resource.spec.object, "file") orelse return error.InvalidResourceSpec;
    const path = try std.fs.path.join(allocator, &.{ root_path, file });
    defer allocator.free(path);
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch null;
    return makeEvidence(allocator, resource, .unknown, "compose runtime state requires an external observer", .{
        .file = path,
        .file_exists = stat != null and stat.?.kind == .file,
        .project_name = stringField(resource.spec.object, "project_name").?,
        .supported = false,
    });
}

const CaddyfileRoute = struct {
    host_blocks: usize = 0,
    reverse_proxy_directives: usize = 0,
    exact_directives: usize = 0,
    observed_upstream: ?[]const u8 = null,

    fn exact(self: CaddyfileRoute) bool {
        return self.host_blocks == 1 and self.reverse_proxy_directives == 1 and self.exact_directives == 1;
    }
};

const CaddyRuntimeRoute = struct {
    host_routes: usize = 0,
    reverse_proxy_handlers: usize = 0,
    upstream_dials: usize = 0,
    exact_dials: usize = 0,
    observed_upstream: ?[]const u8 = null,

    fn exact(self: CaddyRuntimeRoute) bool {
        return self.host_routes == 1 and self.reverse_proxy_handlers == 1 and self.upstream_dials == 1 and self.exact_dials == 1;
    }
};

fn probeCaddyRoute(io: Io, allocator: Allocator, config: core_config.Config, resource: nob.types.Resource) !Evidence {
    const host = stringField(resource.spec.object, "host") orelse return error.InvalidResourceSpec;
    const upstream = stringField(resource.spec.object, "upstream") orelse return error.InvalidResourceSpec;
    const caddyfile = Io.Dir.cwd().readFileAlloc(io, config.caddy_owned_path, allocator, .limited(max_caddyfile_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |other| return unavailable(allocator, resource, "Cloudio could not read the active Caddyfile", other),
    };
    defer if (caddyfile) |bytes| allocator.free(bytes);
    const configured = if (caddyfile) |bytes| scanCaddyfileRoute(bytes, host, upstream) else CaddyfileRoute{};

    const curl = subprocess.resolveExecutable(io, allocator, "curl", config.runtime_environment.path) catch |err| {
        return makeEvidence(allocator, resource, .unknown, "Caddy runtime could not be queried because curl is unavailable", .{
            .host = host,
            .declared_upstream = upstream,
            .caddyfile_path = config.caddy_owned_path,
            .caddyfile_present = caddyfile != null,
            .configured_exactly = configured.exact(),
            .configured_host_blocks = configured.host_blocks,
            .configured_reverse_proxy_directives = configured.reverse_proxy_directives,
            .configured_observed_upstream = configured.observed_upstream,
            .admin_socket = config.caddy_admin_socket,
            .runtime_available = false,
            .error_name = @errorName(err),
        });
    };
    defer allocator.free(curl);
    var environment = try subprocess.makeEnvironment(allocator, config.runtime_environment, &.{});
    defer environment.deinit();
    const args = [_][]const u8{
        curl,
        "--disable",
        "--silent",
        "--show-error",
        "--max-time",
        "5",
        "--unix-socket",
        config.caddy_admin_socket,
        "http://localhost/config/",
    };
    const command = subprocess.run(allocator, io, &args, "/", &environment, .{
        .stdout_bytes = max_caddy_runtime_bytes,
        .stderr_bytes = 16 * 1024,
        .timeout_seconds = 8,
    }) catch |err| {
        return makeEvidence(allocator, resource, .unknown, "Caddy runtime query could not be completed", .{
            .host = host,
            .declared_upstream = upstream,
            .caddyfile_path = config.caddy_owned_path,
            .caddyfile_present = caddyfile != null,
            .configured_exactly = configured.exact(),
            .configured_host_blocks = configured.host_blocks,
            .configured_reverse_proxy_directives = configured.reverse_proxy_directives,
            .configured_observed_upstream = configured.observed_upstream,
            .admin_socket = config.caddy_admin_socket,
            .runtime_available = false,
            .error_name = @errorName(err),
        });
    };
    defer command.deinit(allocator);
    if (!command.successful()) {
        return makeEvidence(allocator, resource, .unknown, "Caddy admin socket did not return its runtime configuration", .{
            .host = host,
            .declared_upstream = upstream,
            .caddyfile_path = config.caddy_owned_path,
            .caddyfile_present = caddyfile != null,
            .configured_exactly = configured.exact(),
            .configured_host_blocks = configured.host_blocks,
            .configured_reverse_proxy_directives = configured.reverse_proxy_directives,
            .configured_observed_upstream = configured.observed_upstream,
            .admin_socket = config.caddy_admin_socket,
            .runtime_available = false,
            .error_name = @as(?[]const u8, null),
        });
    }

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, command.stdout, .{
        .allocate = .alloc_always,
        .max_value_len = max_caddy_runtime_bytes,
    }) catch |err| {
        return makeEvidence(allocator, resource, .unknown, "Caddy returned an invalid runtime configuration", .{
            .host = host,
            .declared_upstream = upstream,
            .caddyfile_path = config.caddy_owned_path,
            .caddyfile_present = caddyfile != null,
            .configured_exactly = configured.exact(),
            .configured_host_blocks = configured.host_blocks,
            .configured_reverse_proxy_directives = configured.reverse_proxy_directives,
            .configured_observed_upstream = configured.observed_upstream,
            .admin_socket = config.caddy_admin_socket,
            .runtime_available = false,
            .error_name = @errorName(err),
        });
    };
    defer parsed.deinit();
    var live = CaddyRuntimeRoute{};
    try scanCaddyRuntime(parsed.value, host, upstream, &live, 0);
    const status: Status = if (live.host_routes == 0)
        .stopped
    else if (live.exact())
        .healthy
    else
        .degraded;
    const summary = if (live.host_routes == 0)
        "declared Caddy route is not active"
    else if (!live.exact())
        "active Caddy route does not exactly match its declared upstream"
    else if (!configured.exact())
        "Caddy route is active, but the rendered Caddyfile differs from the declaration"
    else
        "Caddy route is active and exactly matches its declaration";
    return makeEvidence(allocator, resource, if (status == .healthy and !configured.exact()) .degraded else status, summary, .{
        .host = host,
        .declared_upstream = upstream,
        .caddyfile_path = config.caddy_owned_path,
        .caddyfile_present = caddyfile != null,
        .configured_exactly = configured.exact(),
        .configured_host_blocks = configured.host_blocks,
        .configured_reverse_proxy_directives = configured.reverse_proxy_directives,
        .configured_observed_upstream = configured.observed_upstream,
        .admin_socket = config.caddy_admin_socket,
        .runtime_available = true,
        .runtime_exactly = live.exact(),
        .runtime_host_routes = live.host_routes,
        .runtime_reverse_proxy_handlers = live.reverse_proxy_handlers,
        .runtime_upstream_dials = live.upstream_dials,
        .runtime_observed_upstream = live.observed_upstream,
    });
}

fn scanCaddyfileRoute(bytes: []const u8, host: []const u8, upstream: []const u8) CaddyfileRoute {
    var result = CaddyfileRoute{};
    var depth: i32 = 0;
    var target_depth: ?i32 = null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = trimCaddyLine(raw_line);
        if (line.len == 0) continue;
        if (depth == 0 and std.mem.endsWith(u8, line, "{")) {
            const label = std.mem.trim(u8, line[0 .. line.len - 1], " \t\r");
            if (std.mem.eql(u8, label, host)) {
                result.host_blocks += 1;
                target_depth = depth + 1;
            }
        } else if (target_depth != null and depth == target_depth.?) {
            var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
            const directive = tokens.next() orelse "";
            if (std.mem.eql(u8, directive, "reverse_proxy")) {
                result.reverse_proxy_directives += 1;
                const observed = tokens.next();
                if (result.observed_upstream == null) result.observed_upstream = observed;
                if (observed != null and tokens.next() == null and std.mem.eql(u8, observed.?, upstream)) {
                    result.exact_directives += 1;
                }
            }
        }
        depth += caddyBraceDelta(line);
        if (target_depth != null and depth < target_depth.?) target_depth = null;
        if (depth < 0) depth = 0;
    }
    return result;
}

fn trimCaddyLine(raw: []const u8) []const u8 {
    var quoted = false;
    var escaped = false;
    var end = raw.len;
    for (raw, 0..) |byte, index| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (byte == '\\' and quoted) {
            escaped = true;
            continue;
        }
        if (byte == '"') quoted = !quoted;
        if (byte == '#' and !quoted) {
            end = index;
            break;
        }
    }
    return std.mem.trim(u8, raw[0..end], " \t\r");
}

fn caddyBraceDelta(line: []const u8) i32 {
    var delta: i32 = 0;
    var quoted = false;
    var escaped = false;
    for (line) |byte| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (byte == '\\' and quoted) {
            escaped = true;
            continue;
        }
        if (byte == '"') {
            quoted = !quoted;
            continue;
        }
        if (quoted) continue;
        if (byte == '{') delta += 1;
        if (byte == '}') delta -= 1;
    }
    return delta;
}

fn scanCaddyRuntime(value: std.json.Value, host: []const u8, upstream: []const u8, result: *CaddyRuntimeRoute, depth: usize) !void {
    if (depth > 128) return error.CaddyRuntimeTooDeep;
    switch (value) {
        .object => |object| {
            if (object.get("match") != null and object.get("handle") != null and routeMatchesHost(object, host)) {
                result.host_routes += 1;
                try scanCaddyHandlers(object.get("handle").?, upstream, result, depth + 1);
            }
            var iterator = object.iterator();
            while (iterator.next()) |entry| try scanCaddyRuntime(entry.value_ptr.*, host, upstream, result, depth + 1);
        },
        .array => |array| for (array.items) |item| try scanCaddyRuntime(item, host, upstream, result, depth + 1),
        else => {},
    }
}

fn routeMatchesHost(object: std.json.ObjectMap, host: []const u8) bool {
    const matches = object.get("match") orelse return false;
    if (matches != .array) return false;
    for (matches.array.items) |matcher| {
        if (matcher != .object) continue;
        const hosts = matcher.object.get("host") orelse continue;
        if (hosts != .array) continue;
        for (hosts.array.items) |candidate| {
            if (candidate == .string and std.mem.eql(u8, candidate.string, host)) return true;
        }
    }
    return false;
}

fn scanCaddyHandlers(value: std.json.Value, upstream: []const u8, result: *CaddyRuntimeRoute, depth: usize) !void {
    if (depth > 128) return error.CaddyRuntimeTooDeep;
    switch (value) {
        .object => |object| {
            if (object.get("handler")) |handler| {
                if (handler == .string and std.mem.eql(u8, handler.string, "reverse_proxy")) {
                    result.reverse_proxy_handlers += 1;
                    if (object.get("upstreams")) |upstreams| {
                        if (upstreams == .array) for (upstreams.array.items) |candidate| {
                            if (candidate != .object) continue;
                            const dial = candidate.object.get("dial") orelse continue;
                            if (dial != .string) continue;
                            result.upstream_dials += 1;
                            if (result.observed_upstream == null) result.observed_upstream = dial.string;
                            if (std.mem.eql(u8, dial.string, upstream)) result.exact_dials += 1;
                        };
                    }
                }
            }
            var iterator = object.iterator();
            while (iterator.next()) |entry| try scanCaddyHandlers(entry.value_ptr.*, upstream, result, depth + 1);
        },
        .array => |array| for (array.items) |item| try scanCaddyHandlers(item, upstream, result, depth + 1),
        else => {},
    }
}

fn unsupported(allocator: Allocator, resource: nob.types.Resource, summary: []const u8) !Evidence {
    return makeEvidence(allocator, resource, .unknown, summary, .{ .supported = false });
}

fn unavailable(allocator: Allocator, resource: nob.types.Resource, summary: []const u8, err: anyerror) !Evidence {
    return makeEvidence(allocator, resource, .unknown, summary, .{ .supported = true, .error_name = @errorName(err) });
}

fn makeEvidence(allocator: Allocator, resource: nob.types.Resource, status: Status, summary: []const u8, facts: anytype) !Evidence {
    const owned_summary = try allocator.dupe(u8, summary);
    errdefer allocator.free(owned_summary);
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try std.json.Stringify.value(.{
        .schema = "nob.zig/cloudio-observe/v1",
        .observer = "cloudio",
        .resource_id = resource.id,
        .kind = @tagName(resource.kind),
        .status = @tagName(status),
        .summary = summary,
        .facts = facts,
    }, .{}, &output.writer);
    return .{ .status = status, .summary = owned_summary, .json = try output.toOwnedSlice() };
}

const SystemdState = struct {
    load: []const u8 = "",
    active: []const u8 = "",
    sub: []const u8 = "",
    unit_file: []const u8 = "",
    fragment: []const u8 = "",
    main_pid: ?u32 = null,
};

fn parseSystemdShow(bytes: []const u8) SystemdState {
    var state: SystemdState = .{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..separator];
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t\r");
        if (std.mem.eql(u8, key, "LoadState")) state.load = value;
        if (std.mem.eql(u8, key, "ActiveState")) state.active = value;
        if (std.mem.eql(u8, key, "SubState")) state.sub = value;
        if (std.mem.eql(u8, key, "UnitFileState")) state.unit_file = value;
        if (std.mem.eql(u8, key, "FragmentPath")) state.fragment = value;
        if (std.mem.eql(u8, key, "MainPID")) state.main_pid = std.fmt.parseInt(u32, value, 10) catch null;
    }
    return state;
}

fn enabledState(value: []const u8) bool {
    return std.mem.eql(u8, value, "enabled") or std.mem.eql(u8, value, "enabled-runtime") or std.mem.eql(u8, value, "linked") or std.mem.eql(u8, value, "linked-runtime");
}

fn expectedHttpStatus(spec: std.json.ObjectMap, actual: u16) bool {
    const value = spec.get("expected_status") orelse return false;
    if (value != .array) return false;
    for (value.array.items) |item| if (item == .integer and item.integer == actual) return true;
    return false;
}

fn expandPath(
    allocator: Allocator,
    template: []const u8,
    root_path: []const u8,
    runtime: core_config.RuntimeEnvironment,
) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, template, cursor, "${")) |start| {
        try output.writer.writeAll(template[cursor..start]);
        const end = std.mem.indexOfPos(u8, template, start + 2, "}") orelse return error.InvalidPathTemplate;
        const name = template[start + 2 .. end];
        try writePathVariable(&output.writer, allocator, name, root_path, runtime);
        cursor = end + 1;
    }
    try output.writer.writeAll(template[cursor..]);
    const path = try output.toOwnedSlice();
    errdefer allocator.free(path);
    if (!std.fs.path.isAbsolute(path)) return error.ExpandedPathNotAbsolute;
    return path;
}

fn writePathVariable(
    writer: *std.Io.Writer,
    allocator: Allocator,
    name: []const u8,
    root_path: []const u8,
    runtime: core_config.RuntimeEnvironment,
) !void {
    if (std.mem.eql(u8, name, "PROJECT_ROOT")) return writer.writeAll(root_path);
    if (std.mem.eql(u8, name, "HOME")) return writer.writeAll(runtime.home orelse return error.PathVariableUnavailable);
    const value = if (std.mem.eql(u8, name, "XDG_CONFIG_HOME"))
        runtime.xdg_config_home
    else if (std.mem.eql(u8, name, "XDG_STATE_HOME"))
        runtime.xdg_state_home
    else if (std.mem.eql(u8, name, "XDG_CACHE_HOME"))
        runtime.xdg_cache_home
    else
        return error.InvalidPathTemplate;
    if (value) |present| return writer.writeAll(present);
    const home = runtime.home orelse return error.PathVariableUnavailable;
    const suffix = if (std.mem.eql(u8, name, "XDG_CONFIG_HOME")) ".config" else if (std.mem.eql(u8, name, "XDG_STATE_HOME")) ".local/state" else ".cache";
    const fallback = try std.fs.path.join(allocator, &.{ home, suffix });
    defer allocator.free(fallback);
    return writer.writeAll(fallback);
}

fn pidFromFile(io: Io, allocator: Allocator, path: []const u8) !?u32 {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64)) catch return null;
    defer allocator.free(bytes);
    const pid = std.fmt.parseInt(u32, std.mem.trim(u8, bytes, " \t\r\n"), 10) catch return null;
    return if (try processExists(io, allocator, pid)) pid else null;
}

fn findProcess(io: Io, allocator: Allocator, match: []const u8) !?u32 {
    var proc = try Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true });
    defer proc.close(io);
    var iterator = proc.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;
        const path = try std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid});
        defer allocator.free(path);
        const bytes = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256)) catch continue;
        defer allocator.free(bytes);
        if (std.mem.eql(u8, std.mem.trim(u8, bytes, " \t\r\n"), match)) return pid;
    }
    return null;
}

fn processExists(io: Io, allocator: Allocator, pid: u32) !bool {
    const path = try std.fmt.allocPrint(allocator, "/proc/{d}", .{pid});
    defer allocator.free(path);
    const stat = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return false;
    return stat.kind == .directory;
}

fn findRunnerResource(resources: []const nob.types.ResourceObservation, id: []const u8) ?nob.types.ResourceObservation {
    for (resources) |resource| if (std.mem.eql(u8, resource.id, id)) return resource;
    return null;
}

fn findManifestResource(resources: []const nob.types.Resource, id: []const u8) ?nob.types.Resource {
    for (resources) |resource| if (std.mem.eql(u8, resource.id, id)) return resource;
    return null;
}

fn mergeStatus(runner: Status, cloudio: Status) Status {
    if (cloudio == .unknown) return runner;
    if (runner == .unknown) return cloudio;
    if (runner == cloudio) return runner;
    if (runner == .healthy) return cloudio;
    if (cloudio == .healthy) return runner;
    return .degraded;
}

fn mergeProjectStatus(project: Status, resource: Status) Status {
    if (resource == .unknown or resource == .healthy) return project;
    if (project == .unknown or project == .healthy) return resource;
    if (project == resource) return project;
    return .degraded;
}

fn mergeSummary(
    allocator: Allocator,
    runner_summary: []const u8,
    runner_status: Status,
    cloudio_summary: []const u8,
    cloudio_status: Status,
    effective: Status,
) ![]u8 {
    if (cloudio_status == .unknown) return try allocator.dupe(u8, runner_summary);
    if (runner_status == .unknown) return try allocator.dupe(u8, cloudio_summary);
    return try std.fmt.allocPrint(
        allocator,
        "runner ({s}): {s}; Cloudio ({s}): {s}; effective: {s}",
        .{ @tagName(runner_status), runner_summary, @tagName(cloudio_status), cloudio_summary, @tagName(effective) },
    );
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return if (value == .string) value.string else null;
}

fn intField(object: std.json.ObjectMap, name: []const u8) ?i64 {
    const value = object.get(name) orelse return null;
    return if (value == .integer) value.integer else null;
}

fn boolField(object: std.json.ObjectMap, name: []const u8) ?bool {
    const value = object.get(name) orelse return null;
    return if (value == .bool) value.bool else null;
}

test "status merge preserves independent contradictions" {
    try std.testing.expectEqual(Status.stopped, mergeStatus(.healthy, .stopped));
    try std.testing.expectEqual(Status.degraded, mergeStatus(.stopped, .missing));
    try std.testing.expectEqual(Status.healthy, mergeStatus(.healthy, .unknown));
    try std.testing.expectEqual(Status.degraded, mergeProjectStatus(.healthy, .degraded));
}

test "systemd show parsing is exact and bounded to requested properties" {
    const state = parseSystemdShow(
        "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\nFragmentPath=/home/example/.config/systemd/user/demo.service\nMainPID=42\n",
    );
    try std.testing.expectEqualStrings("loaded", state.load);
    try std.testing.expectEqualStrings("active", state.active);
    try std.testing.expectEqual(@as(?u32, 42), state.main_pid);
    try std.testing.expect(enabledState(state.unit_file));
}

test "path templates expand with XDG fallbacks" {
    const path = try expandPath(std.testing.allocator, "${XDG_STATE_HOME}/demo", "/srv/demo", .{ .home = "/home/example" });
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/example/.local/state/demo", path);
    const project = try expandPath(std.testing.allocator, "${PROJECT_ROOT}/data", "/srv/demo", .{});
    defer std.testing.allocator.free(project);
    try std.testing.expectEqualStrings("/srv/demo/data", project);
}

test "Caddyfile route scan requires one exact host and upstream directive" {
    const exact = scanCaddyfileRoute(
        \\{
        \\    admin unix//run/caddy/admin.socket
        \\}
        \\# another route must not leak into the result
        \\other.example.test {
        \\    reverse_proxy 127.0.0.1:41000
        \\}
        \\app.example.test {
        \\    reverse_proxy 127.0.0.1:42000 # generated route
        \\}
    , "app.example.test", "127.0.0.1:42000");
    try std.testing.expect(exact.exact());
    try std.testing.expectEqual(@as(usize, 1), exact.host_blocks);
    try std.testing.expectEqualStrings("127.0.0.1:42000", exact.observed_upstream.?);

    const ambiguous = scanCaddyfileRoute(
        \\app.example.test {
        \\    reverse_proxy 127.0.0.1:42000
        \\    reverse_proxy 127.0.0.1:42001
        \\}
    , "app.example.test", "127.0.0.1:42000");
    try std.testing.expect(!ambiguous.exact());
    try std.testing.expectEqual(@as(usize, 2), ambiguous.reverse_proxy_directives);
}

test "Caddy runtime scan associates an exact host with its own proxy" {
    const fixture =
        \\{
        \\  "apps": {"http": {"servers": {"srv0": {"routes": [
        \\    {"match":[{"host":["other.example.test"]}],"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:41000"}]}]},
        \\    {"match":[{"host":["app.example.test"]}],"handle":[{"handler":"subroute","routes":[{"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:42000"}]}]}]}]}
        \\  ]}}}}
        \\}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    var exact = CaddyRuntimeRoute{};
    try scanCaddyRuntime(parsed.value, "app.example.test", "127.0.0.1:42000", &exact, 0);
    try std.testing.expect(exact.exact());
    try std.testing.expectEqual(@as(usize, 1), exact.host_routes);
    try std.testing.expectEqualStrings("127.0.0.1:42000", exact.observed_upstream.?);

    var mismatch = CaddyRuntimeRoute{};
    try scanCaddyRuntime(parsed.value, "app.example.test", "127.0.0.1:42999", &mismatch, 0);
    try std.testing.expect(!mismatch.exact());
    try std.testing.expectEqual(@as(usize, 0), mismatch.exact_dials);
}
