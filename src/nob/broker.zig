const std = @import("std");
const app_caddy_desired = @import("app_caddy_desired");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_time = @import("core_time");
const db_store = @import("db_store");
const managed_unit = @import("nob_managed_unit");
const systemd = @import("nob_systemd");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;
const max_frame_bytes = nob.broker.max_frame_bytes;

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    config: core_config.Config,
    operation_id: []const u8,
    actor: []const u8,
    idempotency_key: ?[]const u8,
    operation_dir: []const u8,
    artifact_dir: []const u8,
    manifest: *const nob.types.Manifest,
    plan: *const nob.types.Plan,
};

pub const Server = struct {
    shared: *Shared,
    thread: ?std.Thread,
    stopped: bool = false,

    pub fn start(ctx: Context) !Server {
        if (ctx.plan.broker_requests.len == 0) return error.BrokerNotRequired;
        const socket_path = try std.fs.path.join(ctx.gpa, &.{ ctx.operation_dir, "broker.sock" });
        errdefer ctx.gpa.free(socket_path);
        const token_path = try std.fs.path.join(ctx.gpa, &.{ ctx.operation_dir, "broker.token" });
        errdefer ctx.gpa.free(token_path);
        std.Io.Dir.cwd().deleteFile(ctx.io, socket_path) catch {};
        std.Io.Dir.cwd().deleteFile(ctx.io, token_path) catch {};
        errdefer std.Io.Dir.cwd().deleteFile(ctx.io, socket_path) catch {};
        errdefer std.Io.Dir.cwd().deleteFile(ctx.io, token_path) catch {};

        var random: [32]u8 = undefined;
        try ctx.io.randomSecure(&random);
        const token_size = std.base64.url_safe_no_pad.Encoder.calcSize(random.len);
        const token = try ctx.gpa.alloc(u8, token_size);
        errdefer ctx.gpa.free(token);
        _ = std.base64.url_safe_no_pad.Encoder.encode(token, &random);
        {
            const token_file = try std.Io.Dir.cwd().createFile(ctx.io, token_path, .{
                .exclusive = true,
                .permissions = @fromBackingInt(@intCast(0o400)),
            });
            defer token_file.close(ctx.io);
            try token_file.writeStreamingAll(ctx.io, token);
        }

        const address = try std.Io.net.UnixAddress.init(socket_path);
        var listener = try address.listen(ctx.io, .{ .kernel_backlog = 4 });
        errdefer listener.deinit(ctx.io);
        try std.Io.Dir.cwd().setFilePermissions(ctx.io, socket_path, @fromBackingInt(@intCast(0o600)), .{ .follow_symlinks = false });
        const shared = try ctx.gpa.create(Shared);
        errdefer ctx.gpa.destroy(shared);
        shared.* = .{
            .io = ctx.io,
            .gpa = ctx.gpa,
            .config = ctx.config,
            .operation_id = ctx.operation_id,
            .actor = ctx.actor,
            .idempotency_key = ctx.idempotency_key,
            .operation_dir = ctx.operation_dir,
            .artifact_dir = ctx.artifact_dir,
            .manifest = ctx.manifest,
            .plan = ctx.plan,
            .socket_path = socket_path,
            .token_path = token_path,
            .token = token,
            .listener = listener,
        };
        const thread = try std.Thread.spawn(.{}, serve, .{shared});
        return .{ .shared = shared, .thread = thread };
    }

    pub fn socketPath(self: *const Server) []const u8 {
        return self.shared.socket_path;
    }

    pub fn tokenPath(self: *const Server) []const u8 {
        return self.shared.token_path;
    }

    pub fn childStarted(self: *Server, child_id: std.process.Child.Id) void {
        if (@import("builtin").os.tag == .windows or @TypeOf(child_id) == void) return;
        self.shared.expected_pid.store(@intCast(child_id), .release);
    }

    pub fn stop(self: *Server) !void {
        if (self.stopped) {
            if (self.shared.failed.load(.acquire)) return error.BrokerFailed;
            return;
        }
        self.stopped = true;
        self.shared.stopping.store(true, .release);
        const wake_address: ?std.Io.net.UnixAddress = std.Io.net.UnixAddress.init(self.shared.socket_path) catch null;
        if (wake_address) |address| {
            const wake_stream = address.connect(self.shared.io) catch null;
            if (wake_stream) |stream| stream.close(self.shared.io);
        }
        if (self.thread) |thread| thread.join();
        self.thread = null;
        self.shared.listener.deinit(self.shared.io);
        if (self.shared.failed.load(.acquire)) return error.BrokerFailed;
    }

    pub fn deinit(self: *Server) void {
        self.stop() catch {};
        std.Io.Dir.cwd().deleteFile(self.shared.io, self.shared.socket_path) catch {};
        std.Io.Dir.cwd().deleteFile(self.shared.io, self.shared.token_path) catch {};
        self.shared.gpa.free(self.shared.socket_path);
        self.shared.gpa.free(self.shared.token_path);
        self.shared.gpa.free(self.shared.token);
        const allocator = self.shared.gpa;
        allocator.destroy(self.shared);
        self.* = undefined;
    }
};

const Shared = struct {
    io: std.Io,
    gpa: Allocator,
    config: core_config.Config,
    operation_id: []const u8,
    actor: []const u8,
    idempotency_key: ?[]const u8,
    operation_dir: []const u8,
    artifact_dir: []const u8,
    manifest: *const nob.types.Manifest,
    plan: *const nob.types.Plan,
    socket_path: []u8,
    token_path: []u8,
    token: []u8,
    listener: std.Io.net.Server,
    expected_pid: std.atomic.Value(i32) = .init(0),
    stopping: std.atomic.Value(bool) = .init(false),
    failed: std.atomic.Value(bool) = .init(false),
};

fn serve(shared: *Shared) void {
    var db = db_store.Db.open(shared.io, shared.config.db_path) catch {
        shared.failed.store(true, .release);
        return;
    };
    defer db.close();
    while (!shared.stopping.load(.acquire)) {
        const stream = shared.listener.accept(shared.io) catch |err| switch (err) {
            error.SocketNotListening, error.Canceled => return,
            else => {
                if (!shared.stopping.load(.acquire)) shared.failed.store(true, .release);
                return;
            },
        };
        if (shared.stopping.load(.acquire)) {
            stream.close(shared.io);
            return;
        }
        handleConnection(shared, &db, stream) catch {
            shared.failed.store(true, .release);
        };
    }
}

fn handleConnection(shared: *Shared, db: *db_store.Db, stream: std.Io.net.Stream) !void {
    defer stream.close(shared.io);
    if (!peerIsRunner(shared, stream)) {
        try audit(shared, db, "denied", "peer_mismatch");
        return;
    }
    var read_buffer: [max_frame_bytes]u8 = undefined;
    var reader = stream.reader(shared.io, &read_buffer);
    const frame = reader.interface.takeDelimiter('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.BrokerFrameTooLarge,
        else => |other| return other,
    } orelse return error.BrokerClosedWithoutRequest;
    var parsed = std.json.parseFromSlice(nob.broker.Request, shared.gpa, frame, .{
        .allocate = .alloc_always,
        .max_value_len = max_frame_bytes,
    }) catch {
        try audit(shared, db, "denied", "invalid_request");
        return;
    };
    defer parsed.deinit();
    const request = &parsed.value;
    var write_buffer: [4096]u8 = undefined;
    var stream_writer = stream.writer(shared.io, &write_buffer);
    const writer = &stream_writer.interface;
    if (!std.mem.eql(u8, request.schema, nob.broker.request_schema) or
        !std.mem.eql(u8, request.operation_id, shared.operation_id) or
        !constantTimeEqual(request.token, shared.token))
    {
        try writeDenied(writer, request.request_id, "authorization_denied");
        try stream_writer.interface.flush();
        try audit(shared, db, "denied", "identity_or_token");
        return;
    }
    const authorization = findAuthorization(shared.plan.broker_requests, request.authorization_id) orelse {
        try writeDenied(writer, request.request_id, "authorization_unknown");
        try stream_writer.interface.flush();
        try audit(shared, db, "denied", "authorization_unknown");
        return;
    };
    switch (authorization.capability) {
        .@"systemd.control" => try serveSystemdControl(shared, db, writer, request, authorization),
        .@"systemd.unit" => try serveSystemdUnit(shared, db, writer, request, authorization),
        .@"caddy.route" => try serveCaddyRoute(shared, db, writer, request, authorization),
    }
    try stream_writer.interface.flush();
}

fn serveCaddyRoute(
    shared: *Shared,
    db: *db_store.Db,
    writer: *std.Io.Writer,
    request: *const nob.broker.Request,
    authorization: *const nob.types.BrokerRequest,
) !void {
    if (!shared.config.nob_allow_system_mutation) {
        try writeDenied(writer, request.request_id, "system_mutation_disabled");
        try audit(shared, db, "denied", "system_mutation_disabled");
        return;
    }
    if (request.payload != .object or request.payload.object.count() != 0) {
        try writeDenied(writer, request.request_id, "invalid_payload");
        try audit(shared, db, "denied", "invalid_payload");
        return;
    }
    const resource = findResource(shared.manifest.resources, authorization.resource_id) orelse {
        try writeDenied(writer, request.request_id, "resource_unknown");
        try audit(shared, db, "denied", "resource_unknown");
        return;
    };
    if (resource.kind != .@"caddy.route" or resource.ownership == .observed or resource.spec != .object) {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    }
    const operation = std.meta.stringToEnum(app_caddy_desired.NobRouteOperation, authorization.operation) orelse {
        try writeDenied(writer, request.request_id, "operation_denied");
        try audit(shared, db, "denied", "operation_denied");
        return;
    };
    if (operation == .remove and resource.ownership != .managed) {
        try writeDenied(writer, request.request_id, "resource_not_managed");
        try audit(shared, db, "denied", "resource_not_managed");
        return;
    }
    const host = objectString(resource.spec.object, "host") orelse {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    };
    const upstream = objectString(resource.spec.object, "upstream") orelse {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    };
    if (!try claimAuthorization(shared, db, writer, request.request_id, authorization.id)) return;
    const caddy_executable = subprocess.resolveExecutable(
        shared.io,
        shared.gpa,
        "caddy",
        shared.config.runtime_environment.path,
    ) catch {
        try writeDenied(writer, request.request_id, "caddy_unavailable");
        try audit(shared, db, "failed", authorization.id);
        return;
    };
    defer shared.gpa.free(caddy_executable);
    const systemctl_executable = subprocess.resolveExecutable(
        shared.io,
        shared.gpa,
        "systemctl",
        shared.config.runtime_environment.path,
    ) catch {
        try writeDenied(writer, request.request_id, "systemctl_unavailable");
        try audit(shared, db, "failed", authorization.id);
        return;
    };
    defer shared.gpa.free(systemctl_executable);
    const transition = app_caddy_desired.applyNobRoute(.{
        .io = shared.io,
        .gpa = shared.gpa,
        .db = db,
        .write_meta = .{ .actor = shared.actor, .idempotency_key = shared.idempotency_key },
    }, .{
        .operation_id = shared.operation_id,
        .resource_id = authorization.resource_id,
        .ownership = switch (resource.ownership) {
            .managed => .managed,
            .adopted => .adopted,
            .observed => unreachable,
        },
        .operation = operation,
        .host = host,
        .upstream = upstream,
        .caddyfile_path = shared.config.caddyfile_path,
        .now = @intCast(try core_time.currentEpochSeconds()),
        .caddy_executable = caddy_executable,
        .systemctl_executable = systemctl_executable,
    }) catch |err| {
        try writeDenied(writer, request.request_id, @errorName(err));
        try audit(shared, db, "failed", authorization.id);
        return;
    };
    try writeCaddyAllowed(writer, request.request_id, host, upstream, transition.before_enabled, transition.after_enabled);
    try audit(shared, db, "ok", authorization.id);
}

fn serveSystemdControl(
    shared: *Shared,
    db: *db_store.Db,
    writer: *std.Io.Writer,
    request: *const nob.broker.Request,
    authorization: *const nob.types.BrokerRequest,
) !void {
    if (!shared.config.nob_allow_system_mutation) {
        try writeDenied(writer, request.request_id, "system_mutation_disabled");
        try audit(shared, db, "denied", "system_mutation_disabled");
        return;
    }
    if (request.payload != .object or request.payload.object.count() != 0) {
        try writeDenied(writer, request.request_id, "invalid_payload");
        try audit(shared, db, "denied", "invalid_payload");
        return;
    }
    const resource = findResource(shared.manifest.resources, authorization.resource_id) orelse {
        try writeDenied(writer, request.request_id, "resource_unknown");
        try audit(shared, db, "denied", "resource_unknown");
        return;
    };
    const unit = systemd.Unit.fromResource(resource) catch {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    };
    if (!validSystemdOperation(resource.controls, authorization.operation)) {
        try writeDenied(writer, request.request_id, "operation_denied");
        try audit(shared, db, "denied", "operation_denied");
        return;
    }
    if (!try claimAuthorization(shared, db, writer, request.request_id, authorization.id)) return;
    var controller = systemd.Controller.init(shared.io, shared.gpa, shared.config, shared.operation_dir) catch {
        try writeDenied(writer, request.request_id, "systemctl_unavailable");
        try audit(shared, db, "failed", "systemctl_unavailable");
        return;
    };
    defer controller.deinit();
    const before = controller.query(unit) catch null;
    defer if (before) |snapshot| snapshot.deinit(shared.gpa);
    const operation = std.meta.stringToEnum(systemd.Operation, authorization.operation) orelse unreachable;
    const transition = controller.control(unit, operation) catch {
        const after = controller.query(unit) catch null;
        defer if (after) |snapshot| snapshot.deinit(shared.gpa);
        try writeDeniedWithState(writer, request.request_id, "systemctl_failed", if (before) |snapshot| snapshot.raw else null, if (after) |snapshot| snapshot.raw else null);
        try audit(shared, db, "failed", authorization.id);
        return;
    };
    defer transition.deinit(shared.gpa);
    try writeAllowed(writer, request.request_id, unit.name, transition.before.raw, transition.after.raw);
    try audit(shared, db, "ok", authorization.id);
}

fn serveSystemdUnit(
    shared: *Shared,
    db: *db_store.Db,
    writer: *std.Io.Writer,
    request: *const nob.broker.Request,
    authorization: *const nob.types.BrokerRequest,
) !void {
    if (!shared.config.nob_allow_system_mutation) {
        try writeDenied(writer, request.request_id, "system_mutation_disabled");
        try audit(shared, db, "denied", "system_mutation_disabled");
        return;
    }
    const resource = findResource(shared.manifest.resources, authorization.resource_id) orelse {
        try writeDenied(writer, request.request_id, "resource_unknown");
        try audit(shared, db, "denied", "resource_unknown");
        return;
    };
    if (resource.ownership != .managed) {
        try writeDenied(writer, request.request_id, "resource_not_managed");
        try audit(shared, db, "denied", "resource_not_managed");
        return;
    }
    const unit = systemd.Unit.fromResource(resource) catch {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    };
    if (unit.scope != .user or authorization.metadata == null or authorization.metadata.? != .object) {
        try writeDenied(writer, request.request_id, "authorization_invalid");
        try audit(shared, db, "denied", "authorization_invalid");
        return;
    }
    var existing_record = try db.nob().getManagedUnitForOperation(shared.gpa, shared.operation_id, authorization.resource_id);
    defer if (existing_record) |record| record.deinit(shared.gpa);
    const context = managed_unit.Context{
        .io = shared.io,
        .allocator = shared.gpa,
        .config = shared.config,
        .operation_id = shared.operation_id,
        .operation_dir = shared.operation_dir,
        .artifact_dir = shared.artifact_dir,
        .project_id = shared.manifest.project.id,
        .resource_id = authorization.resource_id,
        .unit = unit,
    };

    if (std.mem.eql(u8, authorization.operation, "install")) {
        const metadata = authorization.metadata.?.object;
        const rendered = objectString(metadata, "rendered_unit") orelse {
            try writeDenied(writer, request.request_id, "authorization_invalid");
            try audit(shared, db, "denied", "authorization_invalid");
            return;
        };
        const approved_sha256 = objectString(metadata, "sha256") orelse {
            try writeDenied(writer, request.request_id, "authorization_invalid");
            try audit(shared, db, "denied", "authorization_invalid");
            return;
        };
        if (request.payload != .object or request.payload.object.count() != 2) {
            try writeDenied(writer, request.request_id, "invalid_payload");
            try audit(shared, db, "denied", "invalid_payload");
            return;
        }
        const artifact_path = objectString(request.payload.object, "path") orelse {
            try writeDenied(writer, request.request_id, "invalid_payload");
            try audit(shared, db, "denied", "invalid_payload");
            return;
        };
        const payload_sha256 = objectString(request.payload.object, "sha256") orelse {
            try writeDenied(writer, request.request_id, "invalid_payload");
            try audit(shared, db, "denied", "invalid_payload");
            return;
        };
        if (!std.mem.eql(u8, payload_sha256, approved_sha256) or
            !onlyObjectKeys(request.payload.object, &.{ "path", "sha256" }))
        {
            try writeDenied(writer, request.request_id, "payload_not_approved");
            try audit(shared, db, "denied", "payload_not_approved");
            return;
        }
        if (!try claimAuthorization(shared, db, writer, request.request_id, authorization.id)) return;
        const transition = managed_unit.install(context, artifact_path, rendered, approved_sha256, if (existing_record) |*record| record else null) catch |err| {
            try writeDenied(writer, request.request_id, @errorName(err));
            try audit(shared, db, "failed", authorization.id);
            return;
        };
        defer transition.deinit(shared.gpa);
        const now: i64 = @intCast(try core_time.currentEpochSeconds());
        db.nob().upsertManagedUnit(.{
            .operation_id = shared.operation_id,
            .resource_id = authorization.resource_id,
            .scope = "user",
            .unit = unit.name,
            .fragment_path = transition.fragment_path,
            .sha256 = transition.afterDigest().?,
            .updated_at = now,
        }) catch |err| {
            try writeDenied(writer, request.request_id, @errorName(err));
            try audit(shared, db, "failed", authorization.id);
            return;
        };
        try writeUnitAllowed(writer, request.request_id, unit.name, transition.fragment_path, transition.beforeDigest(), transition.afterDigest());
        try audit(shared, db, "ok", authorization.id);
        return;
    }

    if (std.mem.eql(u8, authorization.operation, "remove")) {
        if (request.payload != .object or request.payload.object.count() != 0) {
            try writeDenied(writer, request.request_id, "invalid_payload");
            try audit(shared, db, "denied", "invalid_payload");
            return;
        }
        const record = if (existing_record) |*value| value else {
            try writeDenied(writer, request.request_id, "managed_unit_not_found");
            try audit(shared, db, "denied", "managed_unit_not_found");
            return;
        };
        const current_sha256 = objectString(authorization.metadata.?.object, "current_sha256") orelse {
            try writeDenied(writer, request.request_id, "authorization_invalid");
            try audit(shared, db, "denied", "authorization_invalid");
            return;
        };
        if (!try claimAuthorization(shared, db, writer, request.request_id, authorization.id)) return;
        const transition = managed_unit.remove(context, current_sha256, record) catch |err| {
            try writeDenied(writer, request.request_id, @errorName(err));
            try audit(shared, db, "failed", authorization.id);
            return;
        };
        defer transition.deinit(shared.gpa);
        db.nob().deleteManagedUnitForOperation(shared.operation_id, authorization.resource_id) catch |err| {
            try writeDenied(writer, request.request_id, @errorName(err));
            try audit(shared, db, "failed", authorization.id);
            return;
        };
        try writeUnitAllowed(writer, request.request_id, unit.name, transition.fragment_path, transition.beforeDigest(), null);
        try audit(shared, db, "ok", authorization.id);
        return;
    }

    try writeDenied(writer, request.request_id, "operation_denied");
    try audit(shared, db, "denied", "operation_denied");
}

fn writeAllowed(writer: *std.Io.Writer, request_id: u64, unit: []const u8, before: ?[]const u8, after: ?[]const u8) !void {
    try writer.print("{{\"schema\":\"{s}\",\"request_id\":{d},\"ok\":true,\"before\":{{\"unit\":", .{ nob.broker.response_schema, request_id });
    try std.json.Stringify.value(unit, .{}, writer);
    try writer.writeAll(",\"state\":");
    try std.json.Stringify.value(before, .{}, writer);
    try writer.writeAll("},\"after\":{\"unit\":");
    try std.json.Stringify.value(unit, .{}, writer);
    try writer.writeAll(",\"state\":");
    try std.json.Stringify.value(after, .{}, writer);
    try writer.writeAll("},\"error\":null}\n");
}

fn writeDenied(writer: *std.Io.Writer, request_id: u64, code: []const u8) !void {
    return writeDeniedWithState(writer, request_id, code, null, null);
}

fn writeDeniedWithState(writer: *std.Io.Writer, request_id: u64, code: []const u8, before: ?[]const u8, after: ?[]const u8) !void {
    try writer.print("{{\"schema\":\"{s}\",\"request_id\":{d},\"ok\":false,\"before\":", .{ nob.broker.response_schema, request_id });
    try std.json.Stringify.value(before, .{}, writer);
    try writer.writeAll(",\"after\":");
    try std.json.Stringify.value(after, .{}, writer);
    try writer.writeAll(",\"error\":{\"code\":");
    try std.json.Stringify.value(code, .{}, writer);
    try writer.writeAll("}}\n");
}

fn writeUnitAllowed(
    writer: *std.Io.Writer,
    request_id: u64,
    unit: []const u8,
    path: []const u8,
    before_sha256: ?[]const u8,
    after_sha256: ?[]const u8,
) !void {
    try writer.print("{{\"schema\":\"{s}\",\"request_id\":{d},\"ok\":true,\"before\":{{\"unit\":", .{ nob.broker.response_schema, request_id });
    try std.json.Stringify.value(unit, .{}, writer);
    try writer.writeAll(",\"path\":");
    try std.json.Stringify.value(path, .{}, writer);
    try writer.writeAll(",\"sha256\":");
    try std.json.Stringify.value(before_sha256, .{}, writer);
    try writer.writeAll("},\"after\":{\"unit\":");
    try std.json.Stringify.value(unit, .{}, writer);
    try writer.writeAll(",\"path\":");
    try std.json.Stringify.value(path, .{}, writer);
    try writer.writeAll(",\"sha256\":");
    try std.json.Stringify.value(after_sha256, .{}, writer);
    try writer.writeAll("},\"error\":null}\n");
}

fn writeCaddyAllowed(
    writer: *std.Io.Writer,
    request_id: u64,
    host: []const u8,
    upstream: []const u8,
    before_enabled: ?bool,
    after_enabled: ?bool,
) !void {
    try writer.print("{{\"schema\":\"{s}\",\"request_id\":{d},\"ok\":true,\"before\":{{\"host\":", .{ nob.broker.response_schema, request_id });
    try std.json.Stringify.value(host, .{}, writer);
    try writer.writeAll(",\"upstream\":");
    try std.json.Stringify.value(upstream, .{}, writer);
    try writer.writeAll(",\"enabled\":");
    try std.json.Stringify.value(before_enabled, .{}, writer);
    try writer.writeAll("},\"after\":{\"host\":");
    try std.json.Stringify.value(host, .{}, writer);
    try writer.writeAll(",\"upstream\":");
    try std.json.Stringify.value(upstream, .{}, writer);
    try writer.writeAll(",\"enabled\":");
    try std.json.Stringify.value(after_enabled, .{}, writer);
    try writer.writeAll("},\"error\":null}\n");
}

fn findAuthorization(values: []const nob.types.BrokerRequest, id: []const u8) ?*const nob.types.BrokerRequest {
    for (values) |*value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

fn findResource(values: []const nob.types.Resource, id: []const u8) ?*const nob.types.Resource {
    for (values) |*value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

fn validSystemdOperation(controls: []const nob.types.Control, operation: []const u8) bool {
    const parsed = std.meta.stringToEnum(nob.types.Control, operation) orelse return false;
    if (parsed == .logs) return false;
    for (controls) |control| if (control == parsed) return true;
    return false;
}

fn objectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn onlyObjectKeys(object: std.json.ObjectMap, allowed: []const []const u8) bool {
    if (object.count() != allowed.len) return false;
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var found = false;
        for (allowed) |key| if (std.mem.eql(u8, key, entry.key_ptr.*)) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn claimAuthorization(shared: *Shared, db: *db_store.Db, writer: *std.Io.Writer, request_id: u64, authorization_id: []const u8) !bool {
    const now: i64 = @intCast(try core_time.currentEpochSeconds());
    if (try db.nob().claimBrokerAuthorization(shared.operation_id, authorization_id, now)) return true;
    try writeDenied(writer, request_id, "authorization_already_used");
    try audit(shared, db, "denied", "authorization_already_used");
    return false;
}

fn peerIsRunner(shared: *Shared, stream: std.Io.net.Stream) bool {
    if (@import("builtin").os.tag != .linux) return false;
    const expected = shared.expected_pid.load(.acquire);
    if (expected <= 0) return false;
    const Ucred = extern struct { pid: i32, uid: u32, gid: u32 };
    var credential: Ucred = undefined;
    var length: std.c.socklen_t = @sizeOf(Ucred);
    if (std.c.getsockopt(stream.socket.handle, std.c.SOL.SOCKET, std.c.SO.PEERCRED, &credential, &length) != 0) return false;
    return length == @sizeOf(Ucred) and credential.pid == expected;
}

fn constantTimeEqual(left: []const u8, right: []const u8) bool {
    var difference: u8 = @truncate(left.len ^ right.len);
    const length = @max(left.len, right.len);
    var index: usize = 0;
    while (index < length) : (index += 1) {
        const a = if (index < left.len) left[index] else 0;
        const b = if (index < right.len) right[index] else 0;
        difference |= a ^ b;
    }
    return difference == 0;
}

fn audit(shared: *Shared, db: *db_store.Db, status: []const u8, authorization_id: []const u8) !void {
    const detail = try std.fmt.allocPrint(
        shared.gpa,
        "run={s} authorization={s} actor={s} idempotency={s}",
        .{ shared.operation_id, authorization_id, shared.actor, shared.idempotency_key orelse "-" },
    );
    defer shared.gpa.free(detail);
    _ = try app_writes.recordWithMetadata(
        shared.gpa,
        db,
        .{ .actor = shared.actor, .idempotency_key = shared.idempotency_key },
        "nob.broker",
        shared.operation_id,
        null,
        if (std.mem.eql(u8, status, "ok")) .ok else .err,
        detail,
    );
}

test "broker token comparison includes length without an early return" {
    try std.testing.expect(constantTimeEqual("aaaaaaaa", "aaaaaaaa"));
    try std.testing.expect(!constantTimeEqual("aaaaaaaa", "aaaaaaab"));
    try std.testing.expect(!constantTimeEqual("aaaaaaaa", "aaaaaaaaa"));
}

test "systemd broker operations must be explicitly declared" {
    try std.testing.expect(validSystemdOperation(&.{ .start, .restart }, "restart"));
    try std.testing.expect(!validSystemdOperation(&.{.restart}, "stop"));
    try std.testing.expect(!validSystemdOperation(&.{.logs}, "logs"));
}
