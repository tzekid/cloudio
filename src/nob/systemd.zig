const std = @import("std");
const core_config = @import("core_config");
const subprocess = @import("nob_subprocess");
const nob = @import("nob_sdk");

const Allocator = std.mem.Allocator;

pub const Scope = enum { user, system };

pub const Unit = struct {
    scope: Scope,
    name: []const u8,

    pub fn fromResource(resource: *const nob.types.Resource) !Unit {
        if (resource.kind != .@"systemd.service" or resource.spec != .object) return error.ResourceNotSystemd;
        const scope_value = resource.spec.object.get("scope") orelse return error.InvalidSystemdResource;
        const unit_value = resource.spec.object.get("unit") orelse return error.InvalidSystemdResource;
        if (scope_value != .string or unit_value != .string or !validUnitName(unit_value.string)) return error.InvalidSystemdResource;
        const scope: Scope = if (std.mem.eql(u8, scope_value.string, "user"))
            .user
        else if (std.mem.eql(u8, scope_value.string, "system"))
            .system
        else
            return error.InvalidSystemdResource;
        return .{ .scope = scope, .name = unit_value.string };
    }
};

pub const Operation = enum { start, stop, restart, reload, enable, disable };

pub const Snapshot = struct {
    raw: []u8,
    load_state: []const u8,
    active_state: []const u8,
    sub_state: []const u8,
    unit_file_state: []const u8,
    fragment_path: []const u8,
    main_pid: ?u32,

    pub fn deinit(self: Snapshot, allocator: Allocator) void {
        allocator.free(self.raw);
    }
};

pub const Transition = struct {
    before: Snapshot,
    after: Snapshot,

    pub fn deinit(self: Transition, allocator: Allocator) void {
        self.before.deinit(allocator);
        self.after.deinit(allocator);
    }
};

pub const Controller = struct {
    io: std.Io,
    allocator: Allocator,
    config: core_config.Config,
    cwd: []const u8,
    systemctl_path: []u8,
    journalctl_path: ?[]u8,

    pub fn init(io: std.Io, allocator: Allocator, config: core_config.Config, cwd: []const u8) !Controller {
        const systemctl_path = try subprocess.resolveExecutable(io, allocator, "systemctl", config.runtime_environment.path);
        errdefer allocator.free(systemctl_path);
        return .{
            .io = io,
            .allocator = allocator,
            .config = config,
            .cwd = cwd,
            .systemctl_path = systemctl_path,
            .journalctl_path = subprocess.resolveExecutable(io, allocator, "journalctl", config.runtime_environment.path) catch null,
        };
    }

    pub fn deinit(self: *Controller) void {
        self.allocator.free(self.systemctl_path);
        if (self.journalctl_path) |path| self.allocator.free(path);
        self.* = undefined;
    }

    pub fn query(self: *Controller, unit: Unit) !Snapshot {
        const scope = try scopeArgument(unit.scope);
        var environment = try subprocess.makeEnvironment(self.allocator, self.config.runtime_environment, &.{});
        defer environment.deinit();
        const args = [_][]const u8{
            self.systemctl_path,
            scope,
            "show",
            "--no-pager",
            "--property=LoadState",
            "--property=ActiveState",
            "--property=SubState",
            "--property=UnitFileState",
            "--property=FragmentPath",
            "--property=MainPID",
            "--",
            unit.name,
        };
        const result = try subprocess.run(self.allocator, self.io, &args, self.cwd, &environment, .{
            .stdout_bytes = 32 * 1024,
            .stderr_bytes = 32 * 1024,
            .timeout_seconds = 10,
        });
        defer result.deinit(self.allocator);
        if (!result.successful() and result.stdout.len == 0) return error.SystemctlQueryFailed;
        const raw = try self.allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"));
        errdefer self.allocator.free(raw);
        return parseSnapshot(raw);
    }

    pub fn control(self: *Controller, unit: Unit, operation: Operation) !Transition {
        if (!self.config.nob_allow_system_mutation) return error.SystemMutationDisabled;
        const scope = try mutationScopeArgument(unit.scope);
        const before = try self.query(unit);
        errdefer before.deinit(self.allocator);
        var environment = try subprocess.makeEnvironment(self.allocator, self.config.runtime_environment, &.{});
        defer environment.deinit();
        const args = [_][]const u8{
            self.systemctl_path,
            scope,
            "--no-ask-password",
            @tagName(operation),
            "--",
            unit.name,
        };
        const result = try subprocess.run(self.allocator, self.io, &args, self.cwd, &environment, .{
            .stdout_bytes = 64 * 1024,
            .stderr_bytes = 64 * 1024,
            .timeout_seconds = 30,
        });
        defer result.deinit(self.allocator);
        if (!result.successful()) return error.SystemctlFailed;
        const after = try self.waitForState(unit, operation);
        return .{ .before = before, .after = after };
    }

    pub fn logs(self: *Controller, unit: Unit, lines: u16) ![]u8 {
        if (lines == 0 or lines > 2000) return error.InvalidLogLimit;
        if (unit.scope != .user) return error.UnsupportedPrivilege;
        const executable = self.journalctl_path orelse return error.JournalctlUnavailable;
        var line_buffer: [8]u8 = undefined;
        const encoded_lines = try std.fmt.bufPrint(&line_buffer, "{d}", .{lines});
        const unit_argument = try std.fmt.allocPrint(self.allocator, "--user-unit={s}", .{unit.name});
        defer self.allocator.free(unit_argument);
        var environment = try subprocess.makeEnvironment(self.allocator, self.config.runtime_environment, &.{});
        defer environment.deinit();
        const args = [_][]const u8{
            executable,
            unit_argument,
            "--no-pager",
            "--output=short-iso",
            "--lines",
            encoded_lines,
        };
        const result = try subprocess.run(self.allocator, self.io, &args, self.cwd, &environment, .{
            .stdout_bytes = 1024 * 1024,
            .stderr_bytes = 64 * 1024,
            .timeout_seconds = 15,
        });
        defer result.deinit(self.allocator);
        if (!result.successful()) return error.JournalctlFailed;
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn waitForState(self: *Controller, unit: Unit, operation: Operation) !Snapshot {
        const deadline = std.Io.Clock.Timestamp.fromNow(self.io, .{ .raw = .fromSeconds(10), .clock = .awake });
        while (true) {
            const state = try self.query(unit);
            if (stateMatches(state, operation)) return state;
            if (deadline.compare(.lte, std.Io.Clock.Timestamp.now(self.io, .awake))) {
                state.deinit(self.allocator);
                return error.SystemdStateTimeout;
            }
            state.deinit(self.allocator);
            try self.io.sleep(.fromMilliseconds(250), .awake);
        }
    }
};

pub fn operationFromControl(control: nob.types.Control) !Operation {
    return switch (control) {
        .start => .start,
        .stop => .stop,
        .restart => .restart,
        .reload => .reload,
        .enable => .enable,
        .disable => .disable,
        .logs => error.InvalidSystemdControl,
    };
}

pub fn validUnitName(name: []const u8) bool {
    if (name.len == 0 or name.len > 255 or name[0] == '-') return false;
    for (name) |character| switch (character) {
        'A'...'Z', 'a'...'z', '0'...'9', ':', '_', '.', '@', '-' => {},
        else => return false,
    };
    return std.mem.endsWith(u8, name, ".service");
}

fn scopeArgument(scope: Scope) ![]const u8 {
    return switch (scope) {
        .user => "--user",
        .system => "--system",
    };
}

fn mutationScopeArgument(scope: Scope) ![]const u8 {
    if (scope != .user) return error.UnsupportedPrivilege;
    return "--user";
}

fn parseSnapshot(raw: []u8) Snapshot {
    var snapshot = Snapshot{
        .raw = raw,
        .load_state = "",
        .active_state = "",
        .sub_state = "",
        .unit_file_state = "",
        .fragment_path = "",
        .main_pid = null,
    };
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..separator];
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t\r");
        if (std.mem.eql(u8, key, "LoadState")) snapshot.load_state = value;
        if (std.mem.eql(u8, key, "ActiveState")) snapshot.active_state = value;
        if (std.mem.eql(u8, key, "SubState")) snapshot.sub_state = value;
        if (std.mem.eql(u8, key, "UnitFileState")) snapshot.unit_file_state = value;
        if (std.mem.eql(u8, key, "FragmentPath")) snapshot.fragment_path = value;
        if (std.mem.eql(u8, key, "MainPID")) snapshot.main_pid = std.fmt.parseInt(u32, value, 10) catch null;
    }
    return snapshot;
}

fn stateMatches(state: Snapshot, operation: Operation) bool {
    return switch (operation) {
        .start, .restart, .reload => std.mem.eql(u8, state.active_state, "active"),
        .stop => std.mem.eql(u8, state.active_state, "inactive") or std.mem.eql(u8, state.active_state, "failed"),
        .enable => enabled(state.unit_file_state),
        .disable => !enabled(state.unit_file_state),
    };
}

fn enabled(value: []const u8) bool {
    return std.mem.eql(u8, value, "enabled") or std.mem.eql(u8, value, "enabled-runtime") or
        std.mem.eql(u8, value, "linked") or std.mem.eql(u8, value, "linked-runtime");
}

test "scoped systemd resources reject system mutation and option-shaped units" {
    try std.testing.expect(validUnitName("example@blue.service"));
    try std.testing.expect(!validUnitName("-example.service"));
    try std.testing.expect(!validUnitName("../example.service"));
    try std.testing.expectError(error.UnsupportedPrivilege, mutationScopeArgument(.system));
}

test "systemd snapshot parser retains exact fields" {
    const raw = try std.testing.allocator.dupe(u8, "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\nFragmentPath=/tmp/demo.service\nMainPID=42");
    const state = parseSnapshot(raw);
    defer state.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("loaded", state.load_state);
    try std.testing.expectEqualStrings("active", state.active_state);
    try std.testing.expectEqual(@as(?u32, 42), state.main_pid);
    try std.testing.expect(stateMatches(state, .restart));
}
