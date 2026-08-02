const std = @import("std");
const core_config = @import("core_config");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const ExtraEnvironment = struct {
    key: []const u8,
    value: []const u8,
};

pub const Limits = struct {
    stdout_bytes: usize,
    stderr_bytes: usize,
    timeout_seconds: u32,
};

pub const Result = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    pub fn deinit(self: Result, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }

    pub fn successful(self: Result) bool {
        return self.term.success();
    }
};

pub const Monitor = struct {
    context: *anyopaque,
    poll: *const fn (context: *anyopaque) anyerror!bool,
};

pub const InputResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,
    canceled: bool,
    timed_out: bool,

    pub fn deinit(self: InputResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub fn makeEnvironment(
    allocator: Allocator,
    base: core_config.RuntimeEnvironment,
    extras: []const ExtraEnvironment,
) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(allocator);
    errdefer environment.deinit();
    try environment.put("PATH", base.path);
    try putOptional(&environment, "HOME", base.home);
    try putOptional(&environment, "USER", base.user);
    try putOptional(&environment, "LANG", base.lang);
    try putOptional(&environment, "LC_ALL", base.lc_all);
    try putOptional(&environment, "LC_CTYPE", base.lc_ctype);
    try putOptional(&environment, "TZ", base.tz);
    try putOptional(&environment, "XDG_CONFIG_HOME", base.xdg_config_home);
    try putOptional(&environment, "XDG_STATE_HOME", base.xdg_state_home);
    try putOptional(&environment, "XDG_CACHE_HOME", base.xdg_cache_home);
    try putOptional(&environment, "XDG_RUNTIME_DIR", base.xdg_runtime_dir);
    try putOptional(&environment, "DBUS_SESSION_BUS_ADDRESS", base.dbus_session_bus_address);
    for (extras) |extra| {
        if (!isAllowedExtra(extra.key)) return error.UnsafeEnvironmentKey;
        try environment.put(extra.key, extra.value);
    }
    return environment;
}

pub fn run(
    allocator: Allocator,
    io: Io,
    argv: []const []const u8,
    cwd: []const u8,
    environment: *const std.process.Environ.Map,
    limits: Limits,
) !Result {
    if (argv.len == 0 or !std.fs.path.isAbsolute(argv[0])) return error.ExecutableMustBeAbsolute;
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .expand_arg0 = .no_expand,
        .stdout_limit = .limited(limits.stdout_bytes),
        .stderr_limit = .limited(limits.stderr_bytes),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(limits.timeout_seconds), .clock = .awake } },
    });
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

pub fn runWithInput(
    allocator: Allocator,
    io: Io,
    argv: []const []const u8,
    cwd: []const u8,
    environment: *const std.process.Environ.Map,
    input: []const u8,
    limits: Limits,
    monitor: ?Monitor,
) !InputResult {
    if (argv.len == 0 or !std.fs.path.isAbsolute(argv[0])) return error.ExecutableMustBeAbsolute;
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .expand_arg0 = .no_expand,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);
    {
        const stdin_file = child.stdin.?;
        var buffer: [16 * 1024]u8 = undefined;
        var writer = stdin_file.writer(io, &buffer);
        try writer.interface.writeAll(input);
        try writer.interface.flush();
        stdin_file.close(io);
        child.stdin = null;
    }

    var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    multi_reader.init(allocator, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();
    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);
    const deadline = Io.Clock.Timestamp.fromNow(io, .{ .raw = .fromSeconds(limits.timeout_seconds), .clock = .awake });
    var cancel_sent = false;
    var cancel_deadline: ?Io.Clock.Timestamp = null;
    var timed_out = false;
    var forcibly_killed = false;

    read_loop: while (true) {
        multi_reader.fill(64, .{ .duration = .{ .raw = .fromMilliseconds(250), .clock = .awake } }) catch |err| switch (err) {
            error.EndOfStream => break :read_loop,
            error.Timeout => {},
            else => |other| return other,
        };
        if (limits.stdout_bytes < stdout_reader.buffered().len or limits.stderr_bytes < stderr_reader.buffered().len) {
            return error.StreamTooLong;
        }
        const now = Io.Clock.Timestamp.now(io, .awake);
        if (deadline.compare(.lte, now)) {
            timed_out = true;
            child.kill(io);
            forcibly_killed = true;
            break :read_loop;
        }
        if (!cancel_sent and monitor != null and try monitor.?.poll(monitor.?.context)) {
            cancel_sent = true;
            cancel_deadline = Io.Clock.Timestamp.fromNow(io, .{ .raw = .fromSeconds(5), .clock = .awake });
            if (child.id) |id| std.posix.kill(id, .INT) catch {};
        }
        if (cancel_deadline) |grace| {
            if (grace.compare(.lte, now)) {
                child.kill(io);
                forcibly_killed = true;
                break :read_loop;
            }
        }
    }
    try multi_reader.checkAnyError();
    const term = if (forcibly_killed) std.process.Child.Term{ .exited = if (cancel_sent) 130 else 10 } else try child.wait(io);
    const stdout = try multi_reader.toOwnedSlice(0);
    errdefer allocator.free(stdout);
    const stderr = try multi_reader.toOwnedSlice(1);
    return .{
        .stdout = stdout,
        .stderr = stderr,
        .term = term,
        .canceled = cancel_sent,
        .timed_out = timed_out,
    };
}

pub fn resolveExecutable(io: Io, allocator: Allocator, name: []const u8, path_value: []const u8) ![]u8 {
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "/\\") != null) return error.InvalidExecutableName;
    var paths = std.mem.splitScalar(u8, path_value, std.fs.path.delimiter);
    while (paths.next()) |directory| {
        if (directory.len == 0 or !std.fs.path.isAbsolute(directory)) continue;
        const candidate = try std.fs.path.join(allocator, &.{ directory, name });
        defer allocator.free(candidate);
        const canonical = Io.Dir.cwd().realPathFileAlloc(io, candidate, allocator) catch continue;
        defer allocator.free(canonical);
        const stat = Io.Dir.cwd().statFile(io, canonical, .{ .follow_symlinks = false }) catch continue;
        if (stat.kind != .file or @backingInt(stat.permissions) & 0o111 == 0) continue;
        return try allocator.dupe(u8, canonical);
    }
    return error.ExecutableNotFound;
}

fn putOptional(environment: *std.process.Environ.Map, key: []const u8, value: ?[]const u8) !void {
    if (value) |present| try environment.put(key, present);
}

fn isAllowedExtra(key: []const u8) bool {
    return std.mem.startsWith(u8, key, "NOB_");
}

test "sanitized environment retains only the allowlist and nob variables" {
    var environment = try makeEnvironment(std.testing.allocator, .{
        .path = "/usr/bin:/bin",
        .home = "/home/example",
        .lang = "C.UTF-8",
    }, &.{.{ .key = "NOB_PROJECT_ROOT", .value = "/srv/project" }});
    defer environment.deinit();
    try std.testing.expectEqualStrings("/usr/bin:/bin", environment.get("PATH").?);
    try std.testing.expectEqualStrings("/srv/project", environment.get("NOB_PROJECT_ROOT").?);
    try std.testing.expect(environment.get("CLOUDFLARE_API_TOKEN") == null);
    try std.testing.expectError(error.UnsafeEnvironmentKey, makeEnvironment(
        std.testing.allocator,
        .{},
        &.{.{ .key = "CLOUDFLARE_API_TOKEN", .value = "secret" }},
    ));
}

test "PATH resolution returns an ordinarily owned canonical executable path" {
    const resolved = try resolveExecutable(std.testing.io, std.testing.allocator, "sh", "/usr/bin:/bin");
    defer std.testing.allocator.free(resolved);
    try std.testing.expect(std.fs.path.isAbsolute(resolved));
    const stat = try Io.Dir.cwd().statFile(std.testing.io, resolved, .{ .follow_symlinks = false });
    try std.testing.expectEqual(Io.File.Kind.file, stat.kind);
}

test "bounded subprocess input is delivered over a closed stdin pipe" {
    const shell = try resolveExecutable(std.testing.io, std.testing.allocator, "sh", "/usr/bin:/bin");
    defer std.testing.allocator.free(shell);
    var environment = try makeEnvironment(std.testing.allocator, .{}, &.{});
    defer environment.deinit();
    const args = [_][]const u8{ shell, "-c", "IFS= read -r value; printf '%s' \"$value\"" };
    const result = try runWithInput(
        std.testing.allocator,
        std.testing.io,
        &args,
        "/",
        &environment,
        "hello\n",
        .{ .stdout_bytes = 64, .stderr_bytes = 64, .timeout_seconds = 5 },
        null,
    );
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.term.success());
    try std.testing.expectEqualStrings("hello", result.stdout);
}
