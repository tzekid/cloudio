const std = @import("std");
const app_dashboard = @import("app_dashboard");
const core_json = @import("core_json");
const http = @import("http");

pub fn badRequest(writer: *std.Io.Writer) !u16 {
    try writer.writeAll("{\"error\":\"bad_request\"}\n");
    return 400;
}

pub fn jsonBody(gpa: std.mem.Allocator, body: []const u8) ?std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    if (parsed.value != .object) {
        parsed.deinit();
        return null;
    }
    return parsed;
}

pub fn strField(value: std.json.Value, name: []const u8) ?[]const u8 {
    return core_json.fieldString(value, name);
}

pub fn boolField(value: std.json.Value, name: []const u8) ?bool {
    return core_json.fieldBool(value, name);
}

pub fn intQuery(request: http.Request, key: []const u8, fallback: i64) i64 {
    const raw = request.query(key) orelse return fallback;
    return std.fmt.parseInt(i64, raw, 10) catch fallback;
}

pub fn dashboardOptions(request: http.Request, defaults: app_dashboard.Options) app_dashboard.Options {
    var out = defaults;
    if (request.query("domain")) |value| out.domain = value;
    if (request.query("issues")) |value| out.issues_only = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
    if (request.query("section")) |value| out.section = app_dashboard.Section.parse(value) orelse out.section;
    if (request.query("limit")) |value| out.limit = std.fmt.parseInt(i64, value, 10) catch out.limit;
    return out.normalized();
}

pub const ApiErrorResponse = struct {
    status: u16,
    body: []const u8,
};

pub fn mapApiError(err: anyerror) ApiErrorResponse {
    return switch (err) {
        error.AppBusy => .{ .status = 409, .body = "{\"error\":\"app_busy\"}\n" },
        error.AppExists => .{ .status = 409, .body = "{\"error\":\"app_exists\"}\n" },
        error.AppNotFound, error.DeployNotFound => .{ .status = 404, .body = "{\"error\":\"not_found\"}\n" },
        error.NoRollbackTarget => .{ .status = 409, .body = "{\"error\":\"no_rollback_target\"}\n" },
        error.ReleaseMissing => .{ .status = 422, .body = "{\"error\":\"release_missing\"}\n" },
        error.InvalidName, error.SourceRequired, error.SourceConflict, error.WorkdirMissing, error.UnknownRoute => .{ .status = 400, .body = "{\"error\":\"bad_request\"}\n" },
        else => .{ .status = 500, .body = "{\"error\":\"internal\"}\n" },
    };
}
