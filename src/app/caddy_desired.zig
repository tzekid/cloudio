//! Cloudio-owned Caddy fragment desired state and fail-safe apply workflow.
const std = @import("std");
const sqlite = @import("sqlite");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_json = @import("core_json");
const core_process = @import("core_process");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const max_file_bytes = 8 * 1024 * 1024;
const max_command_bytes = 4 * 1024 * 1024;
const owned_marker = "# Managed by Cloudio. Changes are replaced on apply.";
var caddy_mutex: std.atomic.Mutex = .unlocked;

pub const Error = error{
    SqliteBind,
    SqliteStep,
    InvalidRouteRequest,
    RouteAlreadyExists,
    RouteNotObserved,
    RouteNotOwned,
    RouteNeedsAdoption,
    CaddyBusy,
    CaddyWriteUnavailable,
    CaddyObservationChanged,
    CaddyFragmentInvalid,
    CaddyValidationFailed,
    CaddyWriteFailed,
    CaddyReloadFailed,
    CaddyVerificationFailed,
    CaddyRecoveryFailed,
};

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: app_writes.Metadata = .{},
};

pub const Action = enum { create, update, toggle, delete, adopt };

pub const RouteInput = struct {
    host: []const u8,
    upstream: ?[]const u8 = null,
    enabled: ?bool = null,
};

pub const ApplyOptions = struct {
    caddy_executable: []const u8 = "caddy",
    curl_executable: []const u8 = "curl",
};

pub const ApplyResult = struct {
    validated: bool,
    reloaded: bool,
    verified: bool,
    bytes: usize,
    backup_path: ?[]u8,

    pub fn deinit(self: ApplyResult, gpa: Allocator) void {
        if (self.backup_path) |path| gpa.free(path);
    }
};

pub const Capability = struct {
    refresh: bool,
    write: bool,
    apply: bool,
    code: []const u8,
    reason: []const u8,
};

const DesiredRoute = struct {
    host: []u8,
    upstream: []u8,
    kind: []u8,
    extra: []u8,
    raw: []u8,
    enabled: bool,
    updated_at: []u8,

    fn deinit(self: DesiredRoute, gpa: Allocator) void {
        gpa.free(self.host);
        gpa.free(self.upstream);
        gpa.free(self.kind);
        gpa.free(self.extra);
        gpa.free(self.raw);
        gpa.free(self.updated_at);
    }
};

const DesiredRoutes = struct {
    items: []DesiredRoute,

    fn deinit(self: *DesiredRoutes, gpa: Allocator) void {
        for (self.items) |route| route.deinit(gpa);
        gpa.free(self.items);
    }
};

const ObservedRoute = struct {
    host: []u8,
    upstream: []u8,

    fn deinit(self: ObservedRoute, gpa: Allocator) void {
        gpa.free(self.host);
        gpa.free(self.upstream);
    }
};

const ObservedRoutes = struct {
    items: []ObservedRoute,

    fn deinit(self: *ObservedRoutes, gpa: Allocator) void {
        for (self.items) |route| route.deinit(gpa);
        gpa.free(self.items);
    }
};

const Fragment = struct {
    exists: bool,
    text: []u8,

    fn deinit(self: Fragment, gpa: Allocator) void {
        gpa.free(self.text);
    }
};

const DiffKind = enum { addition, change, removal, unchanged, unadopted };

pub const NobRouteOwnership = enum { managed, adopted };
pub const NobRouteOperation = enum { enable, disable, remove };

pub const NobRouteRequest = struct {
    operation_id: []const u8,
    resource_id: []const u8,
    ownership: NobRouteOwnership,
    operation: NobRouteOperation,
    host: []const u8,
    upstream: []const u8,
    now: i64,
    caddy_executable: []const u8 = "caddy",
    curl_executable: []const u8 = "curl",
};

pub const NobRouteTransition = struct {
    before_enabled: ?bool,
    after_enabled: ?bool,
    created: bool,
    removed: bool,
};

pub fn refresh(ctx: Context) !void {
    if (!caddy_mutex.tryLock()) return error.CaddyBusy;
    defer caddy_mutex.unlock();
    const fragment = readFragment(ctx) catch |err| {
        try recordObservationFailure(ctx, "Could not read the configured Cloudio fragment.");
        return err;
    };
    defer fragment.deinit(ctx.gpa);
    if (fragment.exists) {
        if (!hasOwnershipMarker(fragment.text)) {
            try recordObservationFailure(ctx, "The configured fragment does not carry Cloudio's ownership marker.");
            return error.CaddyFragmentInvalid;
        }
        var parsed = parseOwnedFragment(ctx.gpa, fragment.text) catch {
            try recordObservationFailure(ctx, "The configured fragment is not a supported Cloudio route fragment.");
            return error.CaddyFragmentInvalid;
        };
        parsed.deinit(ctx.gpa);
    }
    const summary = if (fragment.exists)
        "Observed the configured Cloudio-owned Caddy fragment."
    else
        "The configured Cloudio-owned Caddy fragment is absent and may be initialized.";
    _ = try ctx.db.insertSnapshot("caddy", "owned-fragment", ctx.config.caddy_owned_path, "ok", summary, null, fragment.text);
}

pub fn mutate(ctx: Context, action: Action, input: RouteInput) !void {
    if (!caddy_mutex.tryLock()) return error.CaddyBusy;
    defer caddy_mutex.unlock();
    try requireWriteCapability(ctx);
    if (!validHost(input.host)) return error.InvalidRouteRequest;
    if (input.upstream) |upstream| if (!validUpstream(upstream)) return error.InvalidRouteRequest;

    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    const current = findDesired(desired.items, input.host);
    const observed_text = (try latestObservedText(ctx)) orelse return error.CaddyWriteUnavailable;
    defer ctx.gpa.free(observed_text);
    var observed = try parseObservedOrEmpty(ctx.gpa, observed_text);
    defer observed.deinit(ctx.gpa);
    const active = findObserved(observed.items, input.host);

    switch (action) {
        .create => {
            const upstream = input.upstream orelse return error.InvalidRouteRequest;
            if (current != null) return error.RouteAlreadyExists;
            if (active != null) return error.RouteNeedsAdoption;
            try insertDesired(ctx, input.host, upstream, "manual", true);
            try recordRouteMutation(ctx, "caddy.route.create", input.host, upstream);
        },
        .update => {
            const upstream = input.upstream orelse return error.InvalidRouteRequest;
            const route = current orelse return error.RouteNotObserved;
            if (!std.mem.eql(u8, route.kind, "manual")) return error.RouteNotOwned;
            try updateDesiredUpstream(ctx, input.host, upstream);
            try recordRouteMutation(ctx, "caddy.route.update", input.host, upstream);
        },
        .toggle => {
            const enabled = input.enabled orelse return error.InvalidRouteRequest;
            const route = current orelse return error.RouteNotObserved;
            if (!std.mem.eql(u8, route.kind, "manual")) return error.RouteNotOwned;
            try updateDesiredEnabled(ctx, input.host, enabled);
            try recordRouteMutation(ctx, "caddy.route.toggle", input.host, if (enabled) "enabled" else "disabled");
        },
        .delete => {
            const route = current orelse return error.RouteNotObserved;
            if (!std.mem.eql(u8, route.kind, "manual")) return error.RouteNotOwned;
            if (active == null) {
                try deleteDesiredExact(ctx, input.host);
            } else {
                try markDesiredForDeletion(ctx, input.host);
            }
            try recordRouteMutation(ctx, "caddy.route.delete", input.host, "pending apply");
        },
        .adopt => {
            if (current != null) return error.RouteAlreadyExists;
            const route = active orelse return error.RouteNotObserved;
            try insertDesired(ctx, route.host, route.upstream, "manual", true);
            try recordRouteMutation(ctx, "caddy.route.adopt", route.host, route.upstream);
        },
    }
}

pub fn apply(ctx: Context, opts: ApplyOptions) !ApplyResult {
    if (!caddy_mutex.tryLock()) return error.CaddyBusy;
    defer caddy_mutex.unlock();
    return applyLocked(ctx, opts) catch |err| {
        try recordApplyFailure(ctx, err);
        return err;
    };
}

fn applyLocked(ctx: Context, opts: ApplyOptions) !ApplyResult {
    const capability = try evaluateCapability(ctx);
    if (!capability.apply) return error.CaddyWriteUnavailable;
    const before = try readFragment(ctx);
    defer before.deinit(ctx.gpa);
    const observed_text = (try latestObservedText(ctx)) orelse return error.CaddyWriteUnavailable;
    defer ctx.gpa.free(observed_text);
    if (!std.mem.eql(u8, before.text, observed_text)) return error.CaddyObservationChanged;

    const rendered = try render(ctx, ctx.gpa);
    defer ctx.gpa.free(rendered);
    const temp_path = try temporaryPath(ctx.io, ctx.gpa, ctx.config.caddy_owned_path, "tmp");
    defer ctx.gpa.free(temp_path);
    Io.Dir.cwd().deleteFile(ctx.io, temp_path) catch {};
    errdefer Io.Dir.cwd().deleteFile(ctx.io, temp_path) catch {};
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = temp_path, .data = rendered }) catch return error.CaddyWriteFailed;
    Io.Dir.cwd().setFilePermissions(ctx.io, temp_path, @fromBackingInt(@intCast(0o640)), .{ .follow_symlinks = false }) catch return error.CaddyWriteFailed;

    const fragment_adapted = try adaptConfig(ctx, opts.caddy_executable, temp_path);
    ctx.gpa.free(fragment_adapted);
    const previous_runtime = try adaptConfig(ctx, opts.caddy_executable, ctx.config.caddyfile_path);
    defer ctx.gpa.free(previous_runtime);

    var backup_path: ?[]u8 = null;
    errdefer if (backup_path) |path| ctx.gpa.free(path);
    if (before.exists) {
        const path = try temporaryPath(ctx.io, ctx.gpa, ctx.config.caddy_owned_path, "bak");
        Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = before.text }) catch {
            ctx.gpa.free(path);
            return error.CaddyWriteFailed;
        };
        backup_path = path;
    }

    Io.Dir.cwd().rename(temp_path, Io.Dir.cwd(), ctx.config.caddy_owned_path, ctx.io) catch return error.CaddyWriteFailed;
    const expected_runtime = adaptConfig(ctx, opts.caddy_executable, ctx.config.caddyfile_path) catch |err| {
        try restoreAndReload(ctx, opts, before, previous_runtime);
        return err;
    };
    defer ctx.gpa.free(expected_runtime);
    reloadConfig(ctx, opts.caddy_executable) catch |err| {
        try restoreAndReload(ctx, opts, before, previous_runtime);
        return err;
    };
    verifyRuntime(ctx, opts.curl_executable, expected_runtime) catch |err| {
        try restoreAndReload(ctx, opts, before, previous_runtime);
        return err;
    };

    try deleteAppliedTombstones(ctx);
    _ = try ctx.db.insertSnapshot("caddy", "owned-fragment", ctx.config.caddy_owned_path, "ok", "Applied and verified the Cloudio-owned Caddy fragment.", null, rendered);
    const detail = try std.fmt.allocPrint(ctx.gpa, "fragment={s}; bytes={d}; validate=ok; reload=ok; verify=ok", .{ ctx.config.caddy_owned_path, rendered.len });
    defer ctx.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "caddy.apply", ctx.config.caddy_owned_path, null, .ok, detail);
    return .{ .validated = true, .reloaded = true, .verified = true, .bytes = rendered.len, .backup_path = backup_path };
}

fn restoreAndReload(ctx: Context, opts: ApplyOptions, before: Fragment, previous_runtime: []const u8) !void {
    if (before.exists) {
        const recovery_path = temporaryPath(ctx.io, ctx.gpa, ctx.config.caddy_owned_path, "recovery") catch
            return error.CaddyRecoveryFailed;
        defer ctx.gpa.free(recovery_path);
        Io.Dir.cwd().deleteFile(ctx.io, recovery_path) catch {};
        errdefer Io.Dir.cwd().deleteFile(ctx.io, recovery_path) catch {};
        Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = recovery_path, .data = before.text }) catch
            return error.CaddyRecoveryFailed;
        Io.Dir.cwd().setFilePermissions(ctx.io, recovery_path, @fromBackingInt(@intCast(0o640)), .{ .follow_symlinks = false }) catch
            return error.CaddyRecoveryFailed;
        Io.Dir.cwd().rename(recovery_path, Io.Dir.cwd(), ctx.config.caddy_owned_path, ctx.io) catch
            return error.CaddyRecoveryFailed;
    } else {
        Io.Dir.cwd().deleteFile(ctx.io, ctx.config.caddy_owned_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return error.CaddyRecoveryFailed,
        };
    }
    reloadConfig(ctx, opts.caddy_executable) catch return error.CaddyRecoveryFailed;
    verifyRuntime(ctx, opts.curl_executable, previous_runtime) catch return error.CaddyRecoveryFailed;
}

pub fn render(ctx: Context, gpa: Allocator) ![]u8 {
    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    if (!desiredRoutesSupported(desired.items)) return error.CaddyFragmentInvalid;
    var out = std.Io.Writer.Allocating.init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(owned_marker ++ "\n# Source: caddy_desired_routes\n");
    for (desired.items) |route| {
        if (!route.enabled or std.mem.endsWith(u8, route.kind, "-delete")) continue;
        try out.writer.writeByte('\n');
        try out.writer.writeAll(route.host);
        try out.writer.writeAll(" {\n\treverse_proxy ");
        try out.writer.writeAll(route.upstream);
        try out.writer.writeAll("\n}\n");
    }
    return try out.toOwnedSlice();
}

pub fn writeJson(ctx: Context, writer: anytype) !void {
    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    const observed_text = try latestObservedText(ctx);
    defer if (observed_text) |text| ctx.gpa.free(text);
    var observed = try parseObservedOrEmpty(ctx.gpa, observed_text orelse "");
    defer observed.deinit(ctx.gpa);
    const observation = try ctx.db.latestObservationForTarget(ctx.gpa, "caddy", "owned-fragment", ctx.config.caddy_owned_path);
    defer if (observation) |value| value.deinit(ctx.gpa);
    const capability = try evaluateCapability(ctx);

    try writer.writeAll("{\"kind\":\"caddy_owned_fragment\",\"ownership\":{");
    try core_json.writeStringField(writer, "root", ctx.config.caddyfile_path, true);
    try core_json.writeStringField(writer, "fragment", ctx.config.caddy_owned_path, true);
    try core_json.writeStringField(writer, "admin_socket", ctx.config.caddy_admin_socket, false);
    try writer.writeAll("},");
    try core_json.writeStringField(writer, "freshness", if (capability.write) "current" else if (observation != null and observation.?.hasSuccessfulObservation()) "stale" else "unavailable", true);
    try writer.writeAll("\"observation\":{");
    if (observation) |value| {
        try core_json.writeStringField(writer, "status", value.attempt_status, true);
        try core_json.writeStringField(writer, "attempted_at", value.attempted_at, true);
        try core_json.writeStringField(writer, "observed_at", value.observed_at, true);
        try core_json.writeStringField(writer, "summary", value.attempt_summary, false);
    } else {
        try core_json.writeStringField(writer, "status", "unavailable", true);
        try core_json.writeNullableStringField(writer, "attempted_at", null, true);
        try core_json.writeNullableStringField(writer, "observed_at", null, true);
        try core_json.writeStringField(writer, "summary", "The owned fragment has not been refreshed.", false);
    }
    try writer.writeAll("},\"capability\":");
    try writeCapabilityJson(capability, writer);
    try writer.writeAll(",\"routes\":[");
    for (desired.items, 0..) |route, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "host", route.host, true);
        try core_json.writeStringField(writer, "upstream", route.upstream, true);
        try core_json.writeStringField(writer, "ownership", if (std.mem.eql(u8, route.kind, "nob")) "project" else "cloudio", true);
        try core_json.writeStringField(writer, "state", if (std.mem.endsWith(u8, route.kind, "-delete")) "pending_delete" else if (route.enabled) "enabled" else "disabled", true);
        try core_json.writeBoolField(writer, "enabled", route.enabled, true);
        try core_json.writeBoolField(writer, "editable", std.mem.eql(u8, route.kind, "manual") and capability.write, true);
        try core_json.writeStringField(writer, "updated_at", route.updated_at, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"adopt_candidates\":[");
    var first = true;
    for (observed.items) |route| {
        if (findDesired(desired.items, route.host) != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "host", route.host, true);
        try core_json.writeStringField(writer, "upstream", route.upstream, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"diff\":");
    try writeDiffJson(desired.items, observed.items, writer);
    try writer.writeAll("}\n");
}

pub fn writePreviewJson(ctx: Context, writer: anytype) !void {
    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    const observed_text = try latestObservedText(ctx);
    defer if (observed_text) |text| ctx.gpa.free(text);
    var observed = try parseObservedOrEmpty(ctx.gpa, observed_text orelse "");
    defer observed.deinit(ctx.gpa);
    const rendered = try render(ctx, ctx.gpa);
    defer ctx.gpa.free(rendered);
    try writer.writeAll("{\"kind\":\"caddy_owned_preview\",");
    try core_json.writeStringField(writer, "fragment", ctx.config.caddy_owned_path, true);
    try core_json.writeStringField(writer, "rendered", rendered, true);
    try writer.writeAll("\"diff\":");
    try writeDiffJson(desired.items, observed.items, writer);
    try writer.writeAll("}\n");
}

pub fn writeCapabilityJson(capability: Capability, writer: anytype) !void {
    try writer.writeByte('{');
    try core_json.writeBoolField(writer, "refresh", capability.refresh, true);
    try core_json.writeBoolField(writer, "write", capability.write, true);
    try core_json.writeBoolField(writer, "apply", capability.apply, true);
    try core_json.writeStringField(writer, "code", capability.code, true);
    try core_json.writeStringField(writer, "reason", capability.reason, false);
    try writer.writeByte('}');
}

fn evaluateCapability(ctx: Context) !Capability {
    if (std.mem.eql(u8, ctx.config.caddyfile_path, ctx.config.caddy_owned_path) or
        std.mem.eql(u8, ctx.config.caddy_sites_path, ctx.config.caddy_owned_path))
    {
        return blocked(false, "unsafe_fragment_path", "The owned fragment must be separate from the root and unmanaged Caddy files.");
    }
    Io.Dir.cwd().access(ctx.io, ctx.config.caddyfile_path, .{ .read = true }) catch
        return blocked(false, "root_unreadable", "Cloudio cannot read the configured root Caddyfile.");
    const root = Io.Dir.cwd().readFileAlloc(ctx.io, ctx.config.caddyfile_path, ctx.gpa, .limited(max_file_bytes)) catch
        return blocked(false, "root_unreadable", "Cloudio cannot read the configured root Caddyfile.");
    defer ctx.gpa.free(root);
    if (!rootImportsFragment(root, ctx.config.caddy_owned_path)) {
        return blocked(false, "fragment_not_imported", "The root Caddyfile does not import the configured Cloudio fragment.");
    }
    const parent = std.fs.path.dirname(ctx.config.caddy_owned_path) orelse ".";
    Io.Dir.cwd().access(ctx.io, parent, .{ .read = true, .write = true }) catch
        return blocked(true, "fragment_parent_unwritable", "Cloudio cannot atomically replace files in the owned fragment directory.");
    const fragment = readFragment(ctx) catch
        return blocked(true, "fragment_unreadable", "Cloudio cannot read the configured owned fragment.");
    defer fragment.deinit(ctx.gpa);
    if (fragment.exists) {
        Io.Dir.cwd().access(ctx.io, ctx.config.caddy_owned_path, .{ .read = true, .write = true }) catch
            return blocked(true, "fragment_unwritable", "Cloudio cannot replace the configured owned fragment.");
        if (!hasOwnershipMarker(fragment.text)) {
            return blocked(true, "ownership_marker_missing", "The configured fragment is not marked as Cloudio-owned.");
        }
        var parsed = parseOwnedFragment(ctx.gpa, fragment.text) catch
            return blocked(true, "unsupported_fragment", "The owned fragment contains syntax outside Cloudio's simple reverse-proxy route format.");
        parsed.deinit(ctx.gpa);
    }
    Io.Dir.cwd().access(ctx.io, ctx.config.caddy_admin_socket, .{ .read = true, .write = true }) catch
        return blocked(true, "admin_socket_unavailable", "Cloudio cannot use the configured Caddy admin socket for reload and verification.");
    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    if (!desiredRoutesSupported(desired.items)) {
        return blocked(true, "unsupported_desired_route", "Stored desired state contains a route outside the owned fragment contract.");
    }
    const observation = try ctx.db.latestObservationForTarget(ctx.gpa, "caddy", "owned-fragment", ctx.config.caddy_owned_path);
    defer if (observation) |value| value.deinit(ctx.gpa);
    if (observation == null or !observation.?.hasSuccessfulObservation()) {
        return blocked(true, "observation_required", "Refresh the owned fragment before changing desired state.");
    }
    if (!std.mem.eql(u8, observation.?.attempt_status, "ok")) {
        return blocked(true, "latest_observation_failed", "The latest fragment refresh failed; recover it and refresh again.");
    }
    const observed_text = (try latestObservedText(ctx)) orelse
        return blocked(true, "observation_required", "Refresh the owned fragment before changing desired state.");
    defer ctx.gpa.free(observed_text);
    if (!std.mem.eql(u8, observed_text, fragment.text)) {
        return blocked(true, "observation_changed", "The owned fragment changed after the last refresh; refresh before continuing.");
    }
    var observed = try parseObservedOrEmpty(ctx.gpa, observed_text);
    defer observed.deinit(ctx.gpa);
    if (hasUnadopted(observed.items, desired.items)) {
        return .{
            .refresh = true,
            .write = true,
            .apply = false,
            .code = "adoption_required",
            .reason = "Adopt each exact observed route before Cloudio may replace the fragment.",
        };
    }
    return .{
        .refresh = true,
        .write = true,
        .apply = true,
        .code = "ready",
        .reason = "The owned fragment, exact observation, filesystem boundary, and Caddy admin socket are ready.",
    };
}

fn blocked(refresh_available: bool, code: []const u8, reason: []const u8) Capability {
    return .{ .refresh = refresh_available, .write = false, .apply = false, .code = code, .reason = reason };
}

fn requireWriteCapability(ctx: Context) !void {
    const capability = try evaluateCapability(ctx);
    if (!capability.write) return error.CaddyWriteUnavailable;
}

fn writeDiffJson(desired: []const DesiredRoute, observed: []const ObservedRoute, writer: anytype) !void {
    var additions: usize = 0;
    var changes: usize = 0;
    var removals: usize = 0;
    var unchanged: usize = 0;
    var unadopted: usize = 0;
    for (desired) |route| switch (diffForDesired(route, observed)) {
        .addition => additions += 1,
        .change => changes += 1,
        .removal => removals += 1,
        .unchanged => unchanged += 1,
        .unadopted => unreachable,
    };
    for (observed) |route| if (findDesired(desired, route.host) == null) {
        unadopted += 1;
    };
    try writer.writeByte('{');
    try core_json.writeIntField(writer, "additions", additions, true);
    try core_json.writeIntField(writer, "changes", changes, true);
    try core_json.writeIntField(writer, "removals", removals, true);
    try core_json.writeIntField(writer, "unchanged", unchanged, true);
    try core_json.writeIntField(writer, "unadopted", unadopted, true);
    try writer.writeAll("\"items\":[");
    var first = true;
    for (desired) |route| {
        const kind = diffForDesired(route, observed);
        if (!first) try writer.writeByte(',');
        first = false;
        try writeDiffItem(writer, @tagName(kind), route.host, route.upstream, if (findObserved(observed, route.host)) |value| value.upstream else null, if (std.mem.eql(u8, route.kind, "nob")) "project" else "cloudio");
    }
    for (observed) |route| {
        if (findDesired(desired, route.host) != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writeDiffItem(writer, "unadopted", route.host, null, route.upstream, "unadopted");
    }
    try writer.writeAll("]}");
}

fn writeDiffItem(writer: anytype, state: []const u8, host: []const u8, desired: ?[]const u8, observed: ?[]const u8, ownership: []const u8) !void {
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "state", state, true);
    try core_json.writeStringField(writer, "host", host, true);
    try core_json.writeNullableStringField(writer, "desired_upstream", desired, true);
    try core_json.writeNullableStringField(writer, "observed_upstream", observed, true);
    try core_json.writeStringField(writer, "ownership", ownership, false);
    try writer.writeByte('}');
}

fn diffForDesired(route: DesiredRoute, observed: []const ObservedRoute) DiffKind {
    const current = findObserved(observed, route.host);
    if (!route.enabled or std.mem.endsWith(u8, route.kind, "-delete")) return if (current == null) .unchanged else .removal;
    if (current == null) return .addition;
    return if (std.mem.eql(u8, route.upstream, current.?.upstream)) .unchanged else .change;
}

fn adaptConfig(ctx: Context, executable: []const u8, path: []const u8) ![]u8 {
    const result = core_process.run(ctx.gpa, ctx.io, &.{ executable, "adapt", "--adapter", "caddyfile", "--config", path }, max_command_bytes) catch
        return error.CaddyValidationFailed;
    defer result.deinit(ctx.gpa);
    if (!result.ok()) return error.CaddyValidationFailed;
    var parsed = std.json.parseFromSlice(std.json.Value, ctx.gpa, result.stdout, .{}) catch return error.CaddyValidationFailed;
    parsed.deinit();
    return try ctx.gpa.dupe(u8, result.stdout);
}

fn reloadConfig(ctx: Context, executable: []const u8) !void {
    const result = core_process.run(ctx.gpa, ctx.io, &.{ executable, "reload", "--adapter", "caddyfile", "--config", ctx.config.caddyfile_path, "--force" }, max_command_bytes) catch
        return error.CaddyReloadFailed;
    defer result.deinit(ctx.gpa);
    if (!result.ok()) return error.CaddyReloadFailed;
}

fn verifyRuntime(ctx: Context, curl_executable: []const u8, expected: []const u8) !void {
    const result = core_process.run(ctx.gpa, ctx.io, &.{ curl_executable, "-fsS", "--max-time", "5", "--unix-socket", ctx.config.caddy_admin_socket, "http://localhost/config/" }, max_command_bytes) catch
        return error.CaddyVerificationFailed;
    defer result.deinit(ctx.gpa);
    if (!result.ok()) return error.CaddyVerificationFailed;
    var expected_json = std.json.parseFromSlice(std.json.Value, ctx.gpa, expected, .{}) catch return error.CaddyVerificationFailed;
    defer expected_json.deinit();
    var actual_json = std.json.parseFromSlice(std.json.Value, ctx.gpa, result.stdout, .{}) catch return error.CaddyVerificationFailed;
    defer actual_json.deinit();
    if (!jsonEqual(expected_json.value, actual_json.value)) return error.CaddyVerificationFailed;
}

fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |value| value == b.bool,
        .integer => |value| value == b.integer,
        .float => |value| value == b.float,
        .number_string => |value| std.mem.eql(u8, value, b.number_string),
        .string => |value| std.mem.eql(u8, value, b.string),
        .array => |array| blk: {
            if (array.items.len != b.array.items.len) break :blk false;
            for (array.items, b.array.items) |left, right| if (!jsonEqual(left, right)) break :blk false;
            break :blk true;
        },
        .object => |object| blk: {
            if (object.count() != b.object.count()) break :blk false;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                const other = b.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!jsonEqual(entry.value_ptr.*, other)) break :blk false;
            }
            break :blk true;
        },
    };
}

fn readFragment(ctx: Context) !Fragment {
    const stat = Io.Dir.cwd().statFile(ctx.io, ctx.config.caddy_owned_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return .{ .exists = false, .text = try ctx.gpa.dupe(u8, "") },
        else => return err,
    };
    if (stat.kind != .file) return error.CaddyFragmentInvalid;
    return .{
        .exists = true,
        .text = try Io.Dir.cwd().readFileAlloc(ctx.io, ctx.config.caddy_owned_path, ctx.gpa, .limited(max_file_bytes)),
    };
}

fn hasOwnershipMarker(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const value = trim(line);
        if (value.len == 0) continue;
        return std.mem.eql(u8, value, owned_marker);
    }
    return false;
}

fn parseObservedOrEmpty(gpa: Allocator, text: []const u8) !ObservedRoutes {
    if (text.len == 0) return .{ .items = try gpa.alloc(ObservedRoute, 0) };
    return parseOwnedFragment(gpa, text);
}

fn parseOwnedFragment(gpa: Allocator, text: []const u8) !ObservedRoutes {
    if (!hasOwnershipMarker(text)) return error.CaddyFragmentInvalid;
    var rows = std.ArrayList(ObservedRoute).empty;
    errdefer deinitObservedList(&rows, gpa);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        if (!std.mem.endsWith(u8, line, "{") or std.mem.indexOfScalar(u8, line[0 .. line.len - 1], '{') != null) return error.CaddyFragmentInvalid;
        const host = trim(line[0 .. line.len - 1]);
        if (!validHost(host)) return error.CaddyFragmentInvalid;
        var upstream: ?[]const u8 = null;
        var closed = false;
        while (lines.next()) |raw_body| {
            const body = trim(raw_body);
            if (body.len == 0 or std.mem.startsWith(u8, body, "#")) continue;
            if (std.mem.eql(u8, body, "}")) {
                closed = true;
                break;
            }
            if (!std.mem.startsWith(u8, body, "reverse_proxy ") or upstream != null) return error.CaddyFragmentInvalid;
            const value = trim(body["reverse_proxy ".len..]);
            if (!validUpstream(value)) return error.CaddyFragmentInvalid;
            upstream = value;
        }
        if (!closed or upstream == null or findObserved(rows.items, host) != null) return error.CaddyFragmentInvalid;
        const host_copy = try gpa.dupe(u8, host);
        errdefer gpa.free(host_copy);
        const upstream_copy = try gpa.dupe(u8, upstream.?);
        rows.append(gpa, .{ .host = host_copy, .upstream = upstream_copy }) catch |err| {
            gpa.free(host_copy);
            gpa.free(upstream_copy);
            return err;
        };
    }
    return .{ .items = try rows.toOwnedSlice(gpa) };
}

fn deinitObservedList(rows: *std.ArrayList(ObservedRoute), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

fn rootImportsFragment(root: []const u8, fragment_path: []const u8) bool {
    var lines = std.mem.splitScalar(u8, root, '\n');
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (!std.mem.startsWith(u8, line, "import ")) continue;
        var tokens = std.mem.tokenizeAny(u8, line["import ".len..], " \t\r");
        const pattern = tokens.next() orelse continue;
        if (std.mem.eql(u8, pattern, fragment_path)) return true;
        if (!std.mem.endsWith(u8, pattern, "/*.caddy") or !std.mem.endsWith(u8, fragment_path, ".caddy")) continue;
        const pattern_dir = pattern[0 .. pattern.len - "/*.caddy".len];
        const fragment_dir = std.fs.path.dirname(fragment_path) orelse ".";
        if (std.mem.eql(u8, pattern_dir, fragment_dir)) return true;
    }
    return false;
}

fn validHost(host: []const u8) bool {
    if (host.len < 3 or host.len > 253 or host[0] == '.' or host[host.len - 1] == '.') return false;
    var saw_dot = false;
    var label_len: usize = 0;
    for (host, 0..) |ch, index| {
        if (ch == '.') {
            if (label_len == 0 or host[index - 1] == '-') return false;
            saw_dot = true;
            label_len = 0;
            continue;
        }
        if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '-')) return false;
        if (label_len == 0 and ch == '-') return false;
        label_len += 1;
        if (label_len > 63) return false;
    }
    return saw_dot and label_len > 0 and host[host.len - 1] != '-';
}

fn validUpstream(upstream: []const u8) bool {
    if (upstream.len < 3 or upstream.len > 128 or std.mem.indexOfAny(u8, upstream, " \t\r\n/\\") != null) return false;
    const colon = std.mem.lastIndexOfScalar(u8, upstream, ':') orelse return false;
    const host = upstream[0..colon];
    if (!(std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "[::1]"))) return false;
    const port = std.fmt.parseInt(u16, upstream[colon + 1 ..], 10) catch return false;
    return port != 0;
}

fn desiredRoutesSupported(routes: []const DesiredRoute) bool {
    for (routes) |route| {
        if (!(std.mem.eql(u8, route.kind, "manual") or std.mem.eql(u8, route.kind, "manual-delete") or std.mem.eql(u8, route.kind, "nob") or std.mem.eql(u8, route.kind, "nob-delete"))) return false;
        if (route.extra.len != 0 or route.raw.len != 0 or !validHost(route.host) or !validUpstream(route.upstream)) return false;
    }
    return true;
}

fn hasUnadopted(observed: []const ObservedRoute, desired: []const DesiredRoute) bool {
    for (observed) |route| if (findDesired(desired, route.host) == null) return true;
    return false;
}

fn findDesired(routes: []const DesiredRoute, host: []const u8) ?*const DesiredRoute {
    for (routes) |*route| if (std.mem.eql(u8, route.host, host)) return route;
    return null;
}

fn findObserved(routes: []const ObservedRoute, host: []const u8) ?*const ObservedRoute {
    for (routes) |*route| if (std.mem.eql(u8, route.host, host)) return route;
    return null;
}

fn loadDesired(ctx: Context) !DesiredRoutes {
    const stmt = try ctx.db.prepare(
        "SELECT host, COALESCE(upstream,''), kind, COALESCE(extra_directives,''), COALESCE(raw_block,''), enabled, COALESCE(updated_at,'') FROM caddy_desired_routes ORDER BY host",
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    var rows = std.ArrayList(DesiredRoute).empty;
    errdefer {
        for (rows.items) |row| row.deinit(ctx.gpa);
        rows.deinit(ctx.gpa);
    }
    while (true) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc == sqlite.SQLITE_DONE) break;
        if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
        var row = DesiredRoute{
            .host = try dupeColumn(ctx.gpa, stmt, 0),
            .upstream = undefined,
            .kind = undefined,
            .extra = undefined,
            .raw = undefined,
            .enabled = sqlite.sqlite3_column_int64(stmt, 5) != 0,
            .updated_at = undefined,
        };
        errdefer ctx.gpa.free(row.host);
        row.upstream = try dupeColumn(ctx.gpa, stmt, 1);
        errdefer ctx.gpa.free(row.upstream);
        row.kind = try dupeColumn(ctx.gpa, stmt, 2);
        errdefer ctx.gpa.free(row.kind);
        row.extra = try dupeColumn(ctx.gpa, stmt, 3);
        errdefer ctx.gpa.free(row.extra);
        row.raw = try dupeColumn(ctx.gpa, stmt, 4);
        errdefer ctx.gpa.free(row.raw);
        row.updated_at = try dupeColumn(ctx.gpa, stmt, 6);
        rows.append(ctx.gpa, row) catch |err| {
            row.deinit(ctx.gpa);
            return err;
        };
    }
    return .{ .items = try rows.toOwnedSlice(ctx.gpa) };
}

fn latestObservedText(ctx: Context) !?[]u8 {
    const stmt = try ctx.db.prepare(
        "SELECT COALESCE(raw_text,'') FROM snapshots WHERE source='caddy' AND kind='owned-fragment' AND target=? AND status='ok' ORDER BY id DESC LIMIT 1",
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, ctx.config.caddy_owned_path);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
    return try dupeColumn(ctx.gpa, stmt, 0);
}

fn insertDesired(ctx: Context, host: []const u8, upstream: []const u8, kind: []const u8, enabled: bool) !void {
    const stmt = try ctx.db.prepare("INSERT INTO caddy_desired_routes(host,upstream,kind,enabled) VALUES(?,?,?,?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    try bindText(stmt, 2, upstream);
    try bindText(stmt, 3, kind);
    try bindI64(stmt, 4, if (enabled) 1 else 0);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
}

fn updateDesiredUpstream(ctx: Context, host: []const u8, upstream: []const u8) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET upstream=?, updated_at=CURRENT_TIMESTAMP WHERE host=? AND kind='manual'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, upstream);
    try bindText(stmt, 2, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

fn updateDesiredEnabled(ctx: Context, host: []const u8, enabled: bool) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET enabled=?, updated_at=CURRENT_TIMESTAMP WHERE host=? AND kind='manual'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, if (enabled) 1 else 0);
    try bindText(stmt, 2, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

fn markDesiredForDeletion(ctx: Context, host: []const u8) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET kind='manual-delete', enabled=0, updated_at=CURRENT_TIMESTAMP WHERE host=? AND kind='manual'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

fn deleteDesiredExact(ctx: Context, host: []const u8) !void {
    const stmt = try ctx.db.prepare("DELETE FROM caddy_desired_routes WHERE host=? AND kind='manual'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

fn deleteAppliedTombstones(ctx: Context) !void {
    try ctx.db.exec("DELETE FROM caddy_desired_routes WHERE kind IN ('manual-delete','nob-delete')");
}

fn recordObservationFailure(ctx: Context, summary: []const u8) !void {
    _ = try ctx.db.insertSnapshot("caddy", "owned-fragment", ctx.config.caddy_owned_path, "error", summary, null, null);
}

fn recordRouteMutation(ctx: Context, kind: []const u8, host: []const u8, detail: []const u8) !void {
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, kind, host, null, .ok, detail);
}

fn recordApplyFailure(ctx: Context, err: anyerror) !void {
    const summary = if (err == error.CaddyRecoveryFailed)
        "Caddy apply and automatic recovery failed; follow the Routes recovery runbook immediately."
    else
        "Caddy apply failed; the previous owned fragment was retained or restored.";
    _ = try ctx.db.insertSnapshot("caddy", "owned-fragment", ctx.config.caddy_owned_path, "error", summary, null, null);
    _ = try app_writes.recordWithMetadata(ctx.gpa, ctx.db, ctx.write_meta, "caddy.apply", ctx.config.caddy_owned_path, null, .err, @errorName(err));
}

fn temporaryPath(io: Io, gpa: Allocator, base: []const u8, label: []const u8) ![]u8 {
    var random: [8]u8 = undefined;
    io.random(&random);
    return try std.fmt.allocPrint(gpa, "{s}.cloudio.{s}.{x}", .{ base, label, random });
}

fn bindText(stmt: *sqlite.sqlite3_stmt, index: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(stmt, index, @ptrCast(value.ptr), @intCast(value.len), sqlite.SQLITE_TRANSIENT) != sqlite.SQLITE_OK) return error.SqliteBind;
}

fn bindI64(stmt: *sqlite.sqlite3_stmt, index: c_int, value: i64) !void {
    if (sqlite.sqlite3_bind_int64(stmt, index, value) != sqlite.SQLITE_OK) return error.SqliteBind;
}

fn dupeColumn(gpa: Allocator, stmt: *sqlite.sqlite3_stmt, index: c_int) ![]u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, index) orelse return try gpa.dupe(u8, "");
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, index));
    return try gpa.dupe(u8, @as([*]const u8, @ptrCast(ptr))[0..len]);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

// Compatibility helpers used by the nob broker while it shares this exact
// owned-fragment service with the Routes page.
pub fn upsertRoute(ctx: Context, host: []const u8, upstream: ?[]const u8, kind: []const u8, extra_directives: ?[]const u8, raw_block: ?[]const u8, app_id: ?i64) !void {
    _ = app_id;
    if (!validHost(host) or upstream == null or !validUpstream(upstream.?) or extra_directives != null or raw_block != null or !std.mem.eql(u8, kind, "nob")) return error.InvalidRouteRequest;
    const stmt = try ctx.db.prepare(
        "INSERT INTO caddy_desired_routes(host,upstream,kind,enabled) VALUES(?,?,?,1) ON CONFLICT(host) DO UPDATE SET upstream=excluded.upstream,kind=excluded.kind,enabled=1,extra_directives=NULL,raw_block=NULL,updated_at=CURRENT_TIMESTAMP",
    );
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    try bindText(stmt, 2, upstream.?);
    try bindText(stmt, 3, kind);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
}

pub fn applyNobRoute(ctx: Context, request: NobRouteRequest) !NobRouteTransition {
    if (!caddy_mutex.tryLock()) return error.CaddyBusy;
    defer caddy_mutex.unlock();
    if (!validHost(request.host) or !validUpstream(request.upstream) or request.resource_id.len == 0) return error.InvalidRouteRequest;
    try requireWriteCapability(ctx);
    try ctx.db.exec("BEGIN IMMEDIATE");
    var transaction_open = true;
    defer if (transaction_open) ctx.db.exec("ROLLBACK") catch {};
    const project_id = try operationProjectId(ctx, request.operation_id);
    var desired = try loadDesired(ctx);
    defer desired.deinit(ctx.gpa);
    const route = findDesired(desired.items, request.host);
    const managed = try managedRoute(ctx, request.host);
    defer if (managed) |value| value.deinit(ctx.gpa);
    const before_enabled = if (route) |value| value.enabled else null;
    var created = false;
    var removed = false;

    switch (request.ownership) {
        .managed => if (route) |value| {
            const owner = managed orelse return error.RouteNotOwned;
            if (owner.project_id != project_id or !std.mem.eql(u8, owner.resource_id, request.resource_id) or
                !std.mem.eql(u8, owner.upstream, request.upstream) or !std.mem.eql(u8, value.kind, "nob") or
                !std.mem.eql(u8, value.upstream, request.upstream)) return error.RouteNotOwned;
        } else {
            if (managed != null or request.operation != .enable) return error.RouteNotObserved;
            try upsertRoute(ctx, request.host, request.upstream, "nob", null, null, null);
            try insertManagedRoute(ctx, project_id, request);
            created = true;
        },
        .adopted => {
            const value = route orelse return error.RouteNotObserved;
            if (managed != null or !std.mem.eql(u8, value.kind, "manual") or !std.mem.eql(u8, value.upstream, request.upstream) or request.operation == .remove) return error.RouteNotOwned;
        },
    }
    switch (request.operation) {
        .enable => if (!created) try setDesiredEnabledAny(ctx, request.host, true),
        .disable => try setDesiredEnabledAny(ctx, request.host, false),
        .remove => {
            if (request.ownership != .managed) return error.RouteNotOwned;
            try deleteManagedRoute(ctx, project_id, request.resource_id, request.host);
            try markNobForDeletion(ctx, request.host);
            removed = true;
        },
    }
    const applied = applyLocked(ctx, .{ .caddy_executable = request.caddy_executable, .curl_executable = request.curl_executable }) catch |err| {
        try ctx.db.exec("ROLLBACK");
        transaction_open = false;
        return err;
    };
    defer applied.deinit(ctx.gpa);
    try ctx.db.exec("COMMIT");
    transaction_open = false;
    return .{ .before_enabled = before_enabled, .after_enabled = if (removed) null else request.operation == .enable, .created = created, .removed = removed };
}

const ManagedRoute = struct {
    project_id: i64,
    resource_id: []u8,
    upstream: []u8,
    fn deinit(self: ManagedRoute, gpa: Allocator) void {
        gpa.free(self.resource_id);
        gpa.free(self.upstream);
    }
};

fn operationProjectId(ctx: Context, operation_id: []const u8) !i64 {
    const stmt = try ctx.db.prepare("SELECT project_id FROM project_operations WHERE id=?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, operation_id);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return error.RouteNotObserved;
    return sqlite.sqlite3_column_int64(stmt, 0);
}

fn managedRoute(ctx: Context, host: []const u8) !?ManagedRoute {
    const stmt = try ctx.db.prepare("SELECT project_id,resource_id,upstream FROM project_managed_routes WHERE host=?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    const rc = sqlite.sqlite3_step(stmt);
    if (rc == sqlite.SQLITE_DONE) return null;
    if (rc != sqlite.SQLITE_ROW) return error.SqliteStep;
    return .{ .project_id = sqlite.sqlite3_column_int64(stmt, 0), .resource_id = try dupeColumn(ctx.gpa, stmt, 1), .upstream = try dupeColumn(ctx.gpa, stmt, 2) };
}

fn insertManagedRoute(ctx: Context, project_id: i64, request: NobRouteRequest) !void {
    const stmt = try ctx.db.prepare("INSERT INTO project_managed_routes(project_id,resource_id,host,upstream,installed_operation_id,updated_at) VALUES(?,?,?,?,?,?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, project_id);
    try bindText(stmt, 2, request.resource_id);
    try bindText(stmt, 3, request.host);
    try bindText(stmt, 4, request.upstream);
    try bindText(stmt, 5, request.operation_id);
    try bindI64(stmt, 6, request.now);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) return error.SqliteStep;
}

fn deleteManagedRoute(ctx: Context, project_id: i64, resource_id: []const u8, host: []const u8) !void {
    const stmt = try ctx.db.prepare("DELETE FROM project_managed_routes WHERE project_id=? AND resource_id=? AND host=?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, project_id);
    try bindText(stmt, 2, resource_id);
    try bindText(stmt, 3, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotOwned;
}

fn setDesiredEnabledAny(ctx: Context, host: []const u8, enabled: bool) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET enabled=?,updated_at=CURRENT_TIMESTAMP WHERE host=?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindI64(stmt, 1, if (enabled) 1 else 0);
    try bindText(stmt, 2, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

fn markNobForDeletion(ctx: Context, host: []const u8) !void {
    const stmt = try ctx.db.prepare("UPDATE caddy_desired_routes SET kind='nob-delete',enabled=0,updated_at=CURRENT_TIMESTAMP WHERE host=? AND kind='nob'");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try bindText(stmt, 1, host);
    if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE or sqlite.sqlite3_changes(ctx.db.handle) != 1) return error.RouteNotObserved;
}

test "owned fragment parser accepts only exact generated reverse proxies" {
    const allocator = std.testing.allocator;
    var routes = try parseOwnedFragment(allocator, owned_marker ++ "\n# Source: caddy_desired_routes\n\napp.example.test {\n\treverse_proxy 127.0.0.1:9000\n}\n");
    defer routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), routes.items.len);
    try std.testing.expectEqualStrings("app.example.test", routes.items[0].host);
    try std.testing.expectError(error.CaddyFragmentInvalid, parseOwnedFragment(allocator, owned_marker ++ "\napp.example.test {\n\trespond 200\n}\n"));
    try std.testing.expect(!validHost("*.example.test"));
    try std.testing.expect(validUpstream("127.0.0.1:9000"));
    try std.testing.expect(!validUpstream("http://127.0.0.1:9000"));
}

test "root import matching is exact and bounded to caddy fragments" {
    try std.testing.expect(rootImportsFragment("import /etc/caddy/conf.d/*.caddy\n", "/etc/caddy/conf.d/cloudio.caddy"));
    try std.testing.expect(rootImportsFragment("import /tmp/cloudio.caddy\n", "/tmp/cloudio.caddy"));
    try std.testing.expect(!rootImportsFragment("import /etc/caddy/conf.d/*.caddy\n", "/tmp/cloudio.caddy"));
    try std.testing.expect(!rootImportsFragment("import /etc/caddy/conf.d/*\n", "/etc/caddy/conf.d/cloudio.caddy"));
}

test "semantic JSON verification ignores object order and formatting" {
    const allocator = std.testing.allocator;
    var left = try std.json.parseFromSlice(std.json.Value, allocator, "{\"a\":1,\"b\":[true,null]}", .{});
    defer left.deinit();
    var right = try std.json.parseFromSlice(std.json.Value, allocator, "{ \"b\" : [true, null], \"a\": 1 }", .{});
    defer right.deinit();
    try std.testing.expect(jsonEqual(left.value, right.value));
}
