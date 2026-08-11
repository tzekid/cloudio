//! Bounded Cloudflare Kitesurf Quick Actions for the authenticated web UI.
const std = @import("std");
const app_writes = @import("app_writes");
const core_config = @import("core_config");
const core_json = @import("core_json");
const db_store = @import("db_store");
const provider_cloudflare = @import("provider_cloudflare");

const Allocator = std.mem.Allocator;
const browser = provider_cloudflare.browser_run;

pub const max_artifact_bytes: usize = 8 * 1024 * 1024;
pub const max_preview_bytes: usize = 128 * 1024;
const stale_run_seconds: i64 = 10 * 60;
var run_mutex: std.atomic.Mutex = .unlocked;

pub const Error = error{
    InvalidBrowserRunRequest,
    BrowserRunTokenRequired,
    BrowserRunAccountNotObserved,
    BrowserRunDestinationPolicyRequired,
    BrowserRunDestinationDenied,
    BrowserRunBusy,
    BrowserRunArtifactNotFound,
    BrowserRunArtifactExpired,
    BrowserRunArtifactUnsafe,
};

pub const Context = struct {
    io: std.Io,
    gpa: Allocator,
    db: *db_store.Db,
    config: core_config.Config,
    write_meta: app_writes.Metadata = .{},
};

pub const Action = enum {
    content,
    screenshot,
};

pub const Input = struct {
    account_id: []const u8,
    url: []const u8,
    action: Action,
};

pub const Outcome = struct {
    id: []u8,
    status: u16,
    success: bool,
    error_code: ?[]const u8 = null,

    pub fn deinit(self: Outcome, allocator: Allocator) void {
        allocator.free(self.id);
    }
};

pub const Artifact = struct {
    path: []u8,
    filename: []u8,
    content_type: []const u8,
    size_bytes: u64,
    attachment_only: bool,

    pub fn deinit(self: Artifact, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.filename);
    }
};

const PreparedTarget = struct {
    display_url: []u8,
    host: []u8,
    sha256: []u8,
    request_pattern: []u8,

    fn deinit(self: PreparedTarget, allocator: Allocator) void {
        allocator.free(self.display_url);
        allocator.free(self.host);
        allocator.free(self.sha256);
        allocator.free(self.request_pattern);
    }
};

const StoredArtifact = struct {
    path: []u8,
    sha256: []u8,
    size_bytes: usize,

    fn deinit(self: StoredArtifact, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.sha256);
    }
};

pub fn run(ctx: Context, input: Input) !Outcome {
    if (!run_mutex.tryLock()) return error.BrowserRunBusy;
    defer run_mutex.unlock();
    if (!ctx.config.hasCloudflareApiToken()) return error.BrowserRunTokenRequired;
    if (ctx.config.browser_run_allowed_hosts.len == 0) return error.BrowserRunDestinationPolicyRequired;
    if (!try accountObserved(ctx, input.account_id)) return error.BrowserRunAccountNotObserved;
    const prepared = try prepareTarget(ctx.gpa, input.url, ctx.config.browser_run_allowed_hosts);
    defer prepared.deinit(ctx.gpa);

    const now = nowSeconds();
    try pruneExpired(ctx, now);
    _ = try ctx.db.browserRun().abandonStale(now - stale_run_seconds, now);
    const id = try newRunId(ctx.io, ctx.gpa);
    errdefer ctx.gpa.free(id);
    try ctx.db.browserRun().insert(.{
        .id = id,
        .account_id = input.account_id,
        .action = @tagName(input.action),
        .target_url = prepared.display_url,
        .target_host = prepared.host,
        .target_sha256 = prepared.sha256,
        .requested_by = ctx.write_meta.actor,
        .idempotency_key = ctx.write_meta.idempotency_key,
        .created_at = now,
        .expires_at = now + @as(i64, @intCast(ctx.config.browser_run_retention_hours)) * 60 * 60,
    });

    const cloudflare = provider_cloudflare.Client.init(.{
        .token = ctx.config.cloudflare_api_token,
        .base_url = ctx.config.cloudflare_api_base,
    });
    const client = try cloudflare.browserRun(input.account_id, .kitesurf);
    const request_patterns = [_][]const u8{prepared.request_pattern};
    return switch (input.action) {
        .content => executeContent(ctx, client, id, input.url, prepared.host, &request_patterns),
        .screenshot => executeScreenshot(ctx, client, id, input.url, prepared.host, &request_patterns),
    };
}

fn executeContent(ctx: Context, client: browser.Client, id: []u8, url: []const u8, host: []const u8, request_patterns: []const []const u8) !Outcome {
    var result = client.content(ctx.io, ctx.gpa, .{
        .source = .{ .url = url },
        .options = defaultOptions(request_patterns),
    }) catch |err| return failTransport(ctx, id, host, .content, err);
    defer result.deinit(ctx.gpa);
    switch (result) {
        .api_error => |failure| return failApi(ctx, id, host, .content, failure.status, failure.meta),
        .ok => |success| {
            if (success.value.html.len > max_artifact_bytes) {
                return fail(ctx, id, host, .content, 413, "artifact_too_large", "Rendered HTML exceeded Cloudio's 8 MiB artifact limit.", success.meta);
            }
            const stored = storeBytes(ctx, id, ".html", success.value.html) catch |err| {
                return failStorage(ctx, id, host, .content, err);
            };
            defer stored.deinit(ctx.gpa);
            try ctx.db.browserRun().finish(id, .{
                .state = "succeeded",
                .origin_status = if (success.value.origin_status) |value| value else null,
                .title = success.value.title,
                .content_type = "text/html; charset=utf-8",
                .size_bytes = @intCast(stored.size_bytes),
                .browser_ms_used = toI64(success.meta.browser_ms_used),
                .retry_after_seconds = toI64(success.meta.retry_after_seconds),
                .cf_ray = success.meta.cf_ray,
                .artifact_path = stored.path,
                .artifact_sha256 = stored.sha256,
                .finished_at = nowSeconds(),
            });
            try audit(ctx, host, .content, .ok, "Kitesurf rendered HTML successfully.");
            return .{ .id = id, .status = 303, .success = true };
        },
    }
}

fn executeScreenshot(ctx: Context, client: browser.Client, id: []u8, url: []const u8, host: []const u8, request_patterns: []const []const u8) !Outcome {
    try ensureStateRoot(ctx);
    const final_path = try artifactPath(ctx.gpa, ctx.config.browser_run_state_root, id, ".png");
    defer ctx.gpa.free(final_path);
    const partial_path = try std.fmt.allocPrint(ctx.gpa, "{s}.tmp", .{final_path});
    defer ctx.gpa.free(partial_path);
    var partial_exists = false;
    defer if (partial_exists) std.Io.Dir.cwd().deleteFile(ctx.io, partial_path) catch {};

    var file = std.Io.Dir.cwd().createFile(ctx.io, partial_path, .{
        .exclusive = true,
        .permissions = @fromBackingInt(@intCast(0o600)),
    }) catch |err| return failStorage(ctx, id, host, .screenshot, err);
    partial_exists = true;
    var file_open = true;
    defer if (file_open) file.close(ctx.io);
    var file_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writerStreaming(ctx.io, &file_buffer);
    var result = client.screenshotTo(ctx.io, ctx.gpa, .{
        .source = .{ .url = url },
        .options = defaultOptions(request_patterns),
        .screenshot = .{ .format = .png },
    }, &file_writer.interface, max_artifact_bytes) catch |err| {
        file.close(ctx.io);
        file_open = false;
        return failTransport(ctx, id, host, .screenshot, err);
    };
    defer result.deinit(ctx.gpa);
    switch (result) {
        .api_error => |failure| {
            file.close(ctx.io);
            file_open = false;
            return failApi(ctx, id, host, .screenshot, failure.status, failure.meta);
        },
        .ok => |success| {
            file_writer.interface.flush() catch |err| {
                file.close(ctx.io);
                file_open = false;
                return failStorage(ctx, id, host, .screenshot, err);
            };
            file.sync(ctx.io) catch |err| {
                file.close(ctx.io);
                file_open = false;
                return failStorage(ctx, id, host, .screenshot, err);
            };
            file.close(ctx.io);
            file_open = false;
            const bytes = std.Io.Dir.cwd().readFileAlloc(ctx.io, partial_path, ctx.gpa, .limited(max_artifact_bytes)) catch |err| {
                return failStorage(ctx, id, host, .screenshot, err);
            };
            defer ctx.gpa.free(bytes);
            if (!validPng(bytes) or bytes.len != success.value.bytes_written) {
                return fail(ctx, id, host, .screenshot, 502, "invalid_screenshot", "Cloudflare returned an invalid PNG screenshot.", success.meta);
            }
            const sha = try hashBytes(ctx.gpa, bytes);
            defer ctx.gpa.free(sha);
            std.Io.Dir.rename(.cwd(), partial_path, .cwd(), final_path, ctx.io) catch |err| {
                return failStorage(ctx, id, host, .screenshot, err);
            };
            partial_exists = false;
            try ctx.db.browserRun().finish(id, .{
                .state = "succeeded",
                .content_type = "image/png",
                .size_bytes = @intCast(bytes.len),
                .browser_ms_used = toI64(success.meta.browser_ms_used),
                .retry_after_seconds = toI64(success.meta.retry_after_seconds),
                .cf_ray = success.meta.cf_ray,
                .artifact_path = final_path,
                .artifact_sha256 = sha,
                .finished_at = nowSeconds(),
            });
            try audit(ctx, host, .screenshot, .ok, "Kitesurf captured a PNG screenshot successfully.");
            return .{ .id = id, .status = 303, .success = true };
        },
    }
}

fn failApi(ctx: Context, id: []u8, host: []const u8, action: Action, status: std.http.Status, meta: browser.ResponseMeta) !Outcome {
    const code: u16 = @backingInt(status);
    if (code == 401 or code == 403) return fail(ctx, id, host, action, 403, "permission_denied", "The Cloudflare token was rejected or lacks Browser Rendering - Edit.", meta);
    if (code == 429) return fail(ctx, id, host, action, 429, "rate_limited", "Cloudflare rate-limited this Browser Run request.", meta);
    if (code == 422) return fail(ctx, id, host, action, 422, "provider_rejected", "Kitesurf could not process this page or action.", meta);
    return fail(ctx, id, host, action, 502, "provider_rejected", "Cloudflare rejected the Browser Run request.", meta);
}

fn failTransport(ctx: Context, id: []u8, host: []const u8, action: Action, err: anyerror) !Outcome {
    const summary = if (err == error.ApiResponseTooLarge)
        "Cloudflare's response exceeded Cloudio's bounded artifact limit."
    else
        "Cloudflare Browser Run could not be reached or returned an invalid response.";
    return fail(ctx, id, host, action, if (err == error.ApiResponseTooLarge) 413 else 503, if (err == error.ApiResponseTooLarge) "artifact_too_large" else "provider_unavailable", summary, .{});
}

fn failStorage(ctx: Context, id: []u8, host: []const u8, action: Action, _: anyerror) !Outcome {
    return fail(ctx, id, host, action, 500, "artifact_storage_failed", "Cloudio could not safely store the Browser Run artifact.", .{});
}

fn fail(ctx: Context, id: []u8, host: []const u8, action: Action, status: u16, code: []const u8, summary: []const u8, meta: browser.ResponseMeta) !Outcome {
    try ctx.db.browserRun().finish(id, .{
        .state = "failed",
        .browser_ms_used = toI64(meta.browser_ms_used),
        .retry_after_seconds = toI64(meta.retry_after_seconds),
        .cf_ray = meta.cf_ray,
        .error_code = code,
        .error_summary = summary,
        .finished_at = nowSeconds(),
    });
    try audit(ctx, host, action, .err, summary);
    return .{ .id = id, .status = status, .success = false, .error_code = code };
}

fn audit(ctx: Context, host: []const u8, action: Action, result: app_writes.Result, detail: []const u8) !void {
    const kind = switch (action) {
        .content => "browser.run.content",
        .screenshot => "browser.run.screenshot",
    };
    _ = try app_writes.recordWithMetadata(
        ctx.gpa,
        ctx.db,
        ctx.write_meta,
        kind,
        host,
        "{\"engine\":\"kitesurf\",\"source\":\"url\"}",
        result,
        detail,
    );
}

pub fn writeJson(ctx: Context, selected_id: ?[]const u8, writer: anytype) !void {
    var accounts = try ctx.db.cloudflare().cloudflareAccountRows(ctx.gpa, 100);
    defer accounts.deinit(ctx.gpa);
    var recent = try ctx.db.browserRun().recent(ctx.gpa, 20);
    defer recent.deinit(ctx.gpa);
    const selected: ?db_store.BrowserRun = if (selected_id) |id|
        if (isSafeRunId(id)) try ctx.db.browserRun().get(ctx.gpa, id) else null
    else
        null;
    defer if (selected) |run_value| run_value.deinit(ctx.gpa);

    const has_token = ctx.config.hasCloudflareApiToken();
    const has_accounts = accounts.items.len != 0;
    const has_policy = ctx.config.browser_run_allowed_hosts.len != 0;
    const available = has_token and has_accounts and has_policy;
    try writer.writeAll("{\"kind\":\"browser_run\",\"capability\":{");
    try core_json.writeBoolField(writer, "available", available, true);
    try core_json.writeBoolField(writer, "token", has_token, true);
    try core_json.writeBoolField(writer, "accounts", has_accounts, true);
    try core_json.writeBoolField(writer, "destination_policy", has_policy, true);
    try core_json.writeStringField(writer, "reason", capabilityReason(has_token, has_accounts, has_policy), false);
    try writer.writeAll("},\"engine\":\"kitesurf\",\"beta\":true,");
    try core_json.writeIntField(writer, "retention_hours", ctx.config.browser_run_retention_hours, true);
    try writer.writeAll("\"allowed_hosts\":[");
    for (ctx.config.browser_run_allowed_hosts, 0..) |host, index| {
        if (index != 0) try writer.writeByte(',');
        try core_json.writeString(writer, host);
    }
    try writer.writeAll("],\"accounts\":[");
    for (accounts.items, 0..) |account, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", account.id, true);
        try core_json.writeStringField(writer, "name", account.name, true);
        try core_json.writeStringField(writer, "status", account.status, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"selected\":");
    if (selected) |run_value| {
        try writeRunJson(ctx, writer, run_value, true);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"recent\":[");
    for (recent.items, 0..) |run_value, index| {
        if (index != 0) try writer.writeByte(',');
        try writeRunJson(ctx, writer, run_value, false);
    }
    try writer.writeAll("]}\n");
}

fn writeRunJson(ctx: Context, writer: anytype, run_value: db_store.BrowserRun, include_preview: bool) !void {
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "id", run_value.id, true);
    try core_json.writeStringField(writer, "account_id", run_value.account_id, true);
    try core_json.writeStringField(writer, "action", run_value.action, true);
    try core_json.writeStringField(writer, "engine", run_value.engine, true);
    try core_json.writeStringField(writer, "target_url", run_value.target_url, true);
    try core_json.writeStringField(writer, "target_host", run_value.target_host, true);
    try core_json.writeStringField(writer, "state", run_value.state, true);
    try writeNullableInt(writer, "origin_status", run_value.origin_status, true);
    try core_json.writeNullableStringField(writer, "title", run_value.title, true);
    try core_json.writeNullableStringField(writer, "content_type", run_value.content_type, true);
    try writeNullableInt(writer, "size_bytes", run_value.size_bytes, true);
    try writeNullableInt(writer, "browser_ms_used", run_value.browser_ms_used, true);
    try writeNullableInt(writer, "retry_after_seconds", run_value.retry_after_seconds, true);
    try core_json.writeNullableStringField(writer, "cf_ray", run_value.cf_ray, true);
    try core_json.writeNullableStringField(writer, "artifact_sha256", run_value.artifact_sha256, true);
    try core_json.writeNullableStringField(writer, "error_code", run_value.error_code, true);
    try core_json.writeNullableStringField(writer, "error_summary", run_value.error_summary, true);
    try core_json.writeIntField(writer, "created_at", run_value.created_at, true);
    try writeNullableInt(writer, "finished_at", run_value.finished_at, true);
    try core_json.writeIntField(writer, "expires_at", run_value.expires_at, true);
    try core_json.writeBoolField(writer, "expired", run_value.expires_at <= nowSeconds(), true);
    try core_json.writeBoolField(writer, "artifact", run_value.artifact_path != null, true);
    try writer.writeAll("\"preview\":");
    if (include_preview and std.mem.eql(u8, run_value.action, "content") and
        std.mem.eql(u8, run_value.state, "succeeded") and run_value.expires_at > nowSeconds())
    {
        const preview = try contentPreview(ctx, run_value);
        defer if (preview) |bytes| ctx.gpa.free(bytes);
        if (preview) |bytes| try core_json.writeString(writer, bytes) else try writer.writeAll("null");
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
}

fn contentPreview(ctx: Context, run_value: db_store.BrowserRun) !?[]u8 {
    const stored = run_value.artifact_path orelse return null;
    const expected = try artifactPath(ctx.gpa, ctx.config.browser_run_state_root, run_value.id, ".html");
    defer ctx.gpa.free(expected);
    if (!std.mem.eql(u8, stored, expected)) return error.BrowserRunArtifactUnsafe;
    const bytes = std.Io.Dir.cwd().readFileAlloc(ctx.io, expected, ctx.gpa, .limited(max_artifact_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |other| return other,
    };
    if (!std.unicode.utf8ValidateSlice(bytes)) {
        ctx.gpa.free(bytes);
        return null;
    }
    if (bytes.len <= max_preview_bytes) return bytes;
    var preview_end = max_preview_bytes;
    while (preview_end > 0 and bytes[preview_end] & 0xc0 == 0x80) preview_end -= 1;
    const preview = try ctx.gpa.dupe(u8, bytes[0..preview_end]);
    ctx.gpa.free(bytes);
    return preview;
}

pub fn artifact(ctx: Context, id: []const u8) !Artifact {
    if (!isSafeRunId(id)) return error.BrowserRunArtifactNotFound;
    const run_value = (try ctx.db.browserRun().get(ctx.gpa, id)) orelse return error.BrowserRunArtifactNotFound;
    defer run_value.deinit(ctx.gpa);
    if (!std.mem.eql(u8, run_value.state, "succeeded")) return error.BrowserRunArtifactNotFound;
    if (run_value.expires_at <= nowSeconds()) return error.BrowserRunArtifactExpired;
    const extension: []const u8 = if (std.mem.eql(u8, run_value.action, "content")) ".html" else if (std.mem.eql(u8, run_value.action, "screenshot")) ".png" else return error.BrowserRunArtifactUnsafe;
    const filename = try std.fmt.allocPrint(ctx.gpa, "browser-run-{s}{s}", .{ id, extension });
    errdefer ctx.gpa.free(filename);
    const expected = try artifactPath(ctx.gpa, ctx.config.browser_run_state_root, id, extension);
    errdefer ctx.gpa.free(expected);
    const stored = run_value.artifact_path orelse return error.BrowserRunArtifactNotFound;
    if (!std.mem.eql(u8, expected, stored)) return error.BrowserRunArtifactUnsafe;
    const stat = std.Io.Dir.cwd().statFile(ctx.io, expected, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return error.BrowserRunArtifactNotFound,
        else => |other| return other,
    };
    if (stat.kind != .file or stat.size > max_artifact_bytes) return error.BrowserRunArtifactUnsafe;
    return .{
        .path = expected,
        .filename = filename,
        .content_type = if (extension[1] == 'h') "text/html; charset=utf-8" else "image/png",
        .size_bytes = stat.size,
        .attachment_only = extension[1] == 'h',
    };
}

fn pruneExpired(ctx: Context, now: i64) !void {
    while (true) {
        var expired = try ctx.db.browserRun().expired(ctx.gpa, now, 50);
        defer expired.deinit(ctx.gpa);
        if (expired.items.len == 0) return;
        for (expired.items) |run_value| {
            if (run_value.artifact_path) |stored| {
                const extension: ?[]const u8 = if (std.mem.eql(u8, run_value.action, "content"))
                    ".html"
                else if (std.mem.eql(u8, run_value.action, "screenshot"))
                    ".png"
                else
                    null;
                if (extension) |suffix| {
                    const expected = try artifactPath(ctx.gpa, ctx.config.browser_run_state_root, run_value.id, suffix);
                    defer ctx.gpa.free(expected);
                    if (std.mem.eql(u8, stored, expected)) {
                        std.Io.Dir.cwd().deleteFile(ctx.io, expected) catch |err| switch (err) {
                            error.FileNotFound => {},
                            else => |other| return other,
                        };
                    }
                }
            }
            _ = try ctx.db.browserRun().deleteExpired(run_value.id, now);
        }
    }
}

fn prepareTarget(allocator: Allocator, raw_url: []const u8, allowed_hosts: []const []const u8) !PreparedTarget {
    const url = std.mem.trim(u8, raw_url, " \t\r\n");
    if (url.len == 0 or url.len > 4096) return error.InvalidBrowserRunRequest;
    browser.validateTargetUrl(url, .public_http) catch return error.BrowserRunDestinationDenied;
    const uri = std.Uri.parse(url) catch return error.InvalidBrowserRunRequest;
    const host_component = uri.host orelse return error.InvalidBrowserRunRequest;
    var host_buffer: [512]u8 = undefined;
    const host_raw = host_component.toRaw(&host_buffer) catch return error.InvalidBrowserRunRequest;
    const without_dot = std.mem.trimEnd(u8, host_raw, ".");
    if (without_dot.len == 0 or without_dot.len > 253 or !hostAllowed(without_dot, allowed_hosts)) return error.BrowserRunDestinationDenied;
    const host = try allocator.alloc(u8, without_dot.len);
    errdefer allocator.free(host);
    for (without_dot, 0..) |byte, index| host[index] = std.ascii.toLower(byte);
    const query = std.mem.indexOfScalar(u8, url, '?') orelse url.len;
    const fragment = std.mem.indexOfScalar(u8, url, '#') orelse url.len;
    const display_end = @min(query, fragment);
    const display_url = try allocator.dupe(u8, url[0..display_end]);
    errdefer allocator.free(display_url);
    const sha256 = try hashBytes(allocator, url);
    errdefer allocator.free(sha256);
    const request_pattern = try allowedRequestPattern(allocator, host);
    return .{ .display_url = display_url, .host = host, .sha256 = sha256, .request_pattern = request_pattern };
}

fn hostAllowed(host: []const u8, allowed_hosts: []const []const u8) bool {
    for (allowed_hosts) |raw_pattern| {
        const pattern = std.mem.trim(u8, raw_pattern, " \t\r\n.");
        if (std.mem.eql(u8, pattern, "*")) return true;
        if (std.mem.startsWith(u8, pattern, "*.") and pattern.len > 2) {
            const suffix = pattern[1..];
            if (host.len > suffix.len and std.ascii.endsWithIgnoreCase(host, suffix)) return true;
        } else if (std.ascii.eqlIgnoreCase(host, pattern)) {
            return true;
        }
    }
    return false;
}

fn accountObserved(ctx: Context, account_id: []const u8) !bool {
    if (account_id.len == 0 or account_id.len > 128) return false;
    var accounts = try ctx.db.cloudflare().cloudflareAccountRows(ctx.gpa, 100);
    defer accounts.deinit(ctx.gpa);
    for (accounts.items) |account| if (std.mem.eql(u8, account.id, account_id)) return true;
    return false;
}

fn allowedRequestPattern(allocator: Allocator, host: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("/^https?:\\/\\/");
    for (host) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-') {
            try out.writer.writeByte(byte);
        } else {
            try out.writer.writeByte('\\');
            try out.writer.writeByte(byte);
        }
    }
    try out.writer.writeAll("(?::[0-9]+)?(?:\\/|$)");
    return try out.toOwnedSlice();
}

fn defaultOptions(request_patterns: []const []const u8) browser.QuickActionOptions {
    return .{
        .cache_ttl_seconds = 0,
        .target_policy = .public_http,
        .action_timeout_ms = 60_000,
        .goto = .{ .timeout_ms = 30_000, .wait_until = .domcontentloaded },
        .allow_request_patterns = request_patterns,
    };
}

fn ensureStateRoot(ctx: Context) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, ctx.config.browser_run_state_root);
    var root = try std.Io.Dir.cwd().openDir(ctx.io, ctx.config.browser_run_state_root, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer root.close(ctx.io);
    try root.setPermissions(ctx.io, @fromBackingInt(@intCast(0o700)));
}

fn storeBytes(ctx: Context, id: []const u8, extension: []const u8, bytes: []const u8) !StoredArtifact {
    try ensureStateRoot(ctx);
    const final_path = try artifactPath(ctx.gpa, ctx.config.browser_run_state_root, id, extension);
    errdefer ctx.gpa.free(final_path);
    const partial_path = try std.fmt.allocPrint(ctx.gpa, "{s}.tmp", .{final_path});
    defer ctx.gpa.free(partial_path);
    var partial_exists = false;
    defer if (partial_exists) std.Io.Dir.cwd().deleteFile(ctx.io, partial_path) catch {};
    var file = try std.Io.Dir.cwd().createFile(ctx.io, partial_path, .{
        .exclusive = true,
        .permissions = @fromBackingInt(@intCast(0o600)),
    });
    partial_exists = true;
    var file_open = true;
    defer if (file_open) file.close(ctx.io);
    try file.writeStreamingAll(ctx.io, bytes);
    try file.sync(ctx.io);
    file.close(ctx.io);
    file_open = false;
    std.Io.Dir.rename(.cwd(), partial_path, .cwd(), final_path, ctx.io) catch |err| return err;
    partial_exists = false;
    const sha256 = try hashBytes(ctx.gpa, bytes);
    return .{ .path = final_path, .sha256 = sha256, .size_bytes = bytes.len };
}

fn artifactPath(allocator: Allocator, root: []const u8, id: []const u8, extension: []const u8) ![]u8 {
    if (!isSafeRunId(id)) return error.BrowserRunArtifactUnsafe;
    const name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ id, extension });
    defer allocator.free(name);
    return try std.fs.path.join(allocator, &.{ root, name });
}

fn newRunId(io: std.Io, allocator: Allocator) ![]u8 {
    var random: [24]u8 = undefined;
    try io.randomSecure(&random);
    var encoded: [std.base64.url_safe_no_pad.Encoder.calcSize(random.len)]u8 = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&encoded, &random);
    @memset(&random, 0);
    return try allocator.dupe(u8, &encoded);
}

fn isSafeRunId(id: []const u8) bool {
    if (id.len != std.base64.url_safe_no_pad.Encoder.calcSize(24)) return false;
    for (id) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') return false;
    return true;
}

fn hashBytes(allocator: Allocator, bytes: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return try std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn validPng(bytes: []const u8) bool {
    return bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n");
}

fn capabilityReason(has_token: bool, has_accounts: bool, has_policy: bool) []const u8 {
    if (!has_token) return "Configure a Cloudflare API token with Browser Rendering - Edit.";
    if (!has_accounts) return "Refresh Cloudflare observations before running a browser action.";
    if (!has_policy) return "Configure an explicit Browser Run destination allowlist.";
    return "Kitesurf is available for the observed account and configured destinations. Token permission is checked on each run.";
}

fn writeNullableInt(writer: anytype, name: []const u8, value: ?i64, trailing: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |present| try writer.print("{d}", .{present}) else try writer.writeAll("null");
    if (trailing) try writer.writeByte(',');
}

fn toI64(value: ?u64) ?i64 {
    const present = value orelse return null;
    if (present > std.math.maxInt(i64)) return null;
    return @intCast(present);
}

fn nowSeconds() i64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.REALTIME, &ts);
    if (std.os.linux.errno(rc) != .SUCCESS or ts.sec < 0) return 0;
    return @intCast(ts.sec);
}

test "Browser Run host policy is exact unless a wildcard is explicit" {
    try std.testing.expect(hostAllowed("example.com", &.{"example.com"}));
    try std.testing.expect(!hostAllowed("sub.example.com", &.{"example.com"}));
    try std.testing.expect(hostAllowed("sub.example.com", &.{"*.example.com"}));
    try std.testing.expect(!hostAllowed("example.com", &.{"*.example.com"}));
    try std.testing.expect(hostAllowed("anything.invalid", &.{"*"}));
}

test "Browser Run remote request policy anchors navigation to the selected host" {
    const pattern = try allowedRequestPattern(std.testing.allocator, "sub.example.com");
    defer std.testing.allocator.free(pattern);
    try std.testing.expectEqualStrings("/^https?:\\/\\/sub\\.example\\.com(?::[0-9]+)?(?:\\/|$)", pattern);
}

test "Browser Run targets remove query secrets from stored display URLs" {
    const allocator = std.testing.allocator;
    const target = try prepareTarget(allocator, "https://example.com/page?token=secret#fragment", &.{"example.com"});
    defer target.deinit(allocator);
    try std.testing.expectEqualStrings("example.com", target.host);
    try std.testing.expectEqualStrings("https://example.com/page", target.display_url);
    try std.testing.expectEqual(@as(usize, 64), target.sha256.len);
}
