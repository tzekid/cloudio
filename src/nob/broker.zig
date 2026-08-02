const std = @import("std");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const db_store = @import("db_store");
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
        const systemctl_path = subprocess.resolveExecutable(ctx.io, ctx.gpa, "systemctl", ctx.config.runtime_environment.path) catch null;
        errdefer if (systemctl_path) |path| ctx.gpa.free(path);
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
            .systemctl_path = systemctl_path,
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
        if (self.shared.systemctl_path) |path| self.shared.gpa.free(path);
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
    systemctl_path: ?[]u8,
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
        .@"systemd.unit", .@"caddy.route" => {
            try writeDenied(writer, request.request_id, "capability_not_implemented");
            try audit(shared, db, "denied", "capability_not_implemented");
        },
    }
    try stream_writer.interface.flush();
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
    const unit = systemdUnit(resource) orelse {
        try writeDenied(writer, request.request_id, "resource_invalid");
        try audit(shared, db, "denied", "resource_invalid");
        return;
    };
    if (!validSystemdOperation(resource.controls, authorization.operation)) {
        try writeDenied(writer, request.request_id, "operation_denied");
        try audit(shared, db, "denied", "operation_denied");
        return;
    }
    const executable = shared.systemctl_path orelse {
        try writeDenied(writer, request.request_id, "systemctl_unavailable");
        try audit(shared, db, "failed", "systemctl_unavailable");
        return;
    };
    var environment = try subprocess.makeEnvironment(shared.gpa, shared.config.runtime_environment, &.{});
    defer environment.deinit();
    const before = querySystemd(shared, executable, unit, &environment) catch null;
    defer if (before) |bytes| shared.gpa.free(bytes);
    const argv = [_][]const u8{ executable, "--user", "--no-ask-password", authorization.operation, "--", unit };
    const result = subprocess.run(shared.gpa, shared.io, &argv, shared.operation_dir, &environment, .{
        .stdout_bytes = 64 * 1024,
        .stderr_bytes = 64 * 1024,
        .timeout_seconds = 30,
    }) catch {
        try writeDeniedWithState(writer, request.request_id, "systemctl_failed", before, null);
        try audit(shared, db, "failed", authorization.id);
        return;
    };
    defer result.deinit(shared.gpa);
    const after = querySystemd(shared, executable, unit, &environment) catch null;
    defer if (after) |bytes| shared.gpa.free(bytes);
    if (!result.successful()) {
        try writeDeniedWithState(writer, request.request_id, "systemctl_failed", before, after);
        try audit(shared, db, "failed", authorization.id);
        return;
    }
    try writeAllowed(writer, request.request_id, unit, before, after);
    try audit(shared, db, "ok", authorization.id);
}

fn querySystemd(shared: *Shared, executable: []const u8, unit: []const u8, environment: *const std.process.Environ.Map) ![]u8 {
    const argv = [_][]const u8{
        executable,
        "--user",
        "show",
        "--no-pager",
        "--property=LoadState",
        "--property=ActiveState",
        "--property=SubState",
        "--",
        unit,
    };
    const result = try subprocess.run(shared.gpa, shared.io, &argv, shared.operation_dir, environment, .{
        .stdout_bytes = 16 * 1024,
        .stderr_bytes = 16 * 1024,
        .timeout_seconds = 10,
    });
    defer result.deinit(shared.gpa);
    if (!result.successful()) return error.SystemctlQueryFailed;
    return try shared.gpa.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"));
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

fn findAuthorization(values: []const nob.types.BrokerRequest, id: []const u8) ?*const nob.types.BrokerRequest {
    for (values) |*value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

fn findResource(values: []const nob.types.Resource, id: []const u8) ?*const nob.types.Resource {
    for (values) |*value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

fn systemdUnit(resource: *const nob.types.Resource) ?[]const u8 {
    if (resource.kind != .@"systemd.service" or resource.spec != .object) return null;
    const scope = resource.spec.object.get("scope") orelse return null;
    const unit = resource.spec.object.get("unit") orelse return null;
    if (scope != .string or unit != .string or !std.mem.eql(u8, scope.string, "user")) return null;
    return unit.string;
}

fn validSystemdOperation(controls: []const nob.types.Control, operation: []const u8) bool {
    const parsed = std.meta.stringToEnum(nob.types.Control, operation) orelse return false;
    if (parsed == .logs) return false;
    for (controls) |control| if (control == parsed) return true;
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
