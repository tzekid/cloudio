const std = @import("std");
const cloudflare = @import("cloudflare");

pub fn main(init: std.process.Init) !void {
    const enabled = init.environ_map.get("CLOUDFLARE_BROWSER_RUN_LIVE") orelse return error.LiveTestNotEnabled;
    if (!std.mem.eql(u8, enabled, "1")) return error.LiveTestNotEnabled;
    const token = init.environ_map.get("CLOUDFLARE_API_TOKEN") orelse return error.MissingCloudflareApiToken;
    const account_id = init.environ_map.get("CLOUDFLARE_ACCOUNT_ID") orelse return error.MissingCloudflareAccountId;

    const root_client = cloudflare.Client.init(.{ .token = token });
    const client = try root_client.browserRun(account_id, .kitesurf);

    var content = try client.content(init.io, init.gpa, .{
        .source = .{ .html = "<!doctype html><title>Kitesurf live test</title><h1 data-test=ready>ready</h1>" },
    });
    defer content.deinit(init.gpa);
    switch (content) {
        .api_error => |failure| return reportFailure("content", failure),
        .ok => |success| if (std.mem.indexOf(u8, success.value.html, "data-test=\"ready\"") == null and
            std.mem.indexOf(u8, success.value.html, "data-test=ready") == null) return error.LiveContentMismatch,
    }

    var screenshot = try client.screenshotAlloc(init.io, init.gpa, .{
        .source = .{ .html = "<!doctype html><style>body{background:#f48120}</style><h1>Kitesurf</h1>" },
        .screenshot = .{ .format = .png },
    }, 8 * 1024 * 1024);
    defer screenshot.deinit(init.gpa);
    switch (screenshot) {
        .api_error => |failure| return reportFailure("screenshot", failure),
        .ok => |success| {
            if (success.value.bytes.len < 8 or !std.mem.eql(u8, success.value.bytes[0..8], "\x89PNG\r\n\x1a\n"))
                return error.LiveScreenshotMismatch;
        },
    }

    var created = try client.createSession(init.io, init.gpa, .{ .keep_alive_ms = 60_000 });
    defer created.deinit(init.gpa);
    const session_id = switch (created) {
        .api_error => |failure| return reportFailure("create session", failure),
        .ok => |success| success.value.session_id,
    };
    var cleanup_required = true;
    defer if (cleanup_required) closeBestEffort(client, init, session_id);

    var sessions = try client.listSessions(init.io, init.gpa, .{ .limit = 100 });
    defer sessions.deinit(init.gpa);
    switch (sessions) {
        .api_error => |failure| return reportFailure("list sessions", failure),
        .ok => |success| {
            var found = false;
            for (success.value.items) |item| {
                if (std.mem.eql(u8, item.session_id, session_id)) found = true;
            }
            if (!found) return error.LiveSessionNotListed;
        },
    }

    var target = try client.newTarget(init.io, init.gpa, session_id, null, .public_http);
    defer target.deinit(init.gpa);
    switch (target) {
        .api_error => |failure| return reportFailure("new target", failure),
        .ok => {},
    }

    var targets = try client.listTargets(init.io, init.gpa, session_id);
    defer targets.deinit(init.gpa);
    switch (targets) {
        .api_error => |failure| return reportFailure("list targets", failure),
        .ok => |success| if (success.value.items.len == 0) return error.LiveTargetNotListed,
    }

    var closed = try client.closeSession(init.io, init.gpa, session_id);
    defer closed.deinit(init.gpa);
    switch (closed) {
        .api_error => |failure| return reportFailure("close session", failure),
        .ok => {},
    }
    cleanup_required = false;

    std.debug.print("Kitesurf live test passed: content, PNG screenshot, session, target, cleanup\n", .{});
}

fn reportFailure(operation: []const u8, failure: cloudflare.browser_run.ApiFailure) error{LiveApiFailure} {
    std.debug.print(
        "Kitesurf live test {s} failed: HTTP {d}, retry-after={?d}, cf-ray={?s}\n",
        .{ operation, @backingInt(failure.status), failure.meta.retry_after_seconds, failure.meta.cf_ray },
    );
    return error.LiveApiFailure;
}

fn closeBestEffort(client: cloudflare.browser_run.Client, init: std.process.Init, session_id: []const u8) void {
    var closed = client.closeSession(init.io, init.gpa, session_id) catch return;
    closed.deinit(init.gpa);
}
