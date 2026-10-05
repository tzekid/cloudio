const app_dashboard = @import("../../app/dashboard.zig");
const app_maintenance = @import("../../app/maintenance.zig");
const context = @import("../context.zig");
const db_store = @import("../../db/store.zig");
const form = @import("../form.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const url = @import("../../core/url.zig");
const web_html = @import("web_html");

pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    try injectDashboardStorage(ctx, main);
    try html.replaceHiddenInput(
        ctx.gpa,
        main,
        "dashboard-refresh-csrf",
        "csrf_token",
        ctx.auth_csrf_token orelse "",
    );
    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try html.formIdempotencyKey(ctx.io, &refresh_key_buffer, "dashboard-refresh");
    try html.replaceHiddenInput(
        ctx.gpa,
        main,
        "dashboard-refresh-idempotency",
        "idempotency_key",
        refresh_key,
    );
    if (dashboardFeedback(request)) |feedback| {
        var escaped = std.Io.Writer.Allocating.init(ctx.gpa);
        defer escaped.deinit();
        try web_html.text(&escaped.writer, feedback.message);
        try html.replaceElementInner(ctx.gpa, main, "dashboard-feedback", "div", escaped.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"dashboard-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"dashboard-feedback\" class=\"notice hidden\"", replacement);
    }
    if (request.query("domain")) |domain| {
        var input = std.Io.Writer.Allocating.init(ctx.gpa);
        defer input.deinit();
        try input.writer.writeAll(
            "<input id=\"domain-filter\" name=\"domain\" type=\"text\" " ++
                "placeholder=\"example.com\" autocomplete=\"off\" value=\"",
        );
        try web_html.attribute(&input.writer, domain);
        try input.writer.writeAll("\">");
        try html.replaceExact(
            ctx.gpa,
            main,
            "<input id=\"domain-filter\" name=\"domain\" type=\"text\" placeholder=\"example.com\" autocomplete=\"off\">",
            input.written(),
        );
    }
    if (request.query("issues")) |issues| {
        if (std.mem.eql(u8, issues, "1") or std.mem.eql(u8, issues, "true")) {
            try html.replaceExact(
                ctx.gpa,
                main,
                "<input id=\"issues-only\" name=\"issues\" value=\"1\" type=\"checkbox\">",
                "<input id=\"issues-only\" name=\"issues\" value=\"1\" type=\"checkbox\" checked>",
            );
        }
    }
    const refresh_seconds: i64 = @intCast(ctx.config.refresh_seconds);
    var dashboard = try app_dashboard.Dashboard.load(ctx.gpa, ctx.db, .{
        .domain = request.query("domain"),
        .issues_only = std.mem.eql(u8, request.query("issues") orelse "", "1"),
    }, @max(refresh_seconds * 2, 60));
    defer dashboard.deinit(ctx.gpa);

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    const counts = dashboard.summary;
    const cards = [_]struct { label: []const u8, value: usize, tone: []const u8 }{
        .{ .label = "Hosts", .value = counts.hosts, .tone = "" },
        .{ .label = "Healthy", .value = counts.healthy, .tone = "success" },
        .{ .label = "Degraded", .value = counts.degraded, .tone = if (counts.degraded > 0) "danger" else "" },
        .{ .label = "DNS only", .value = counts.dns_only, .tone = if (counts.dns_only > 0) "warning" else "" },
        .{ .label = "Local only", .value = counts.local_only, .tone = if (counts.local_only > 0) "warning" else "" },
        .{ .label = "Needs manifest", .value = counts.project_only, .tone = if (counts.project_only > 0) "info" else "" },
        .{ .label = "Incidents", .value = counts.incidents, .tone = if (counts.incidents > 0) "danger" else "success" },
    };
    for (cards) |card| {
        try summary.writer.writeAll("<article class=\"stat-card");
        if (card.tone.len > 0) try summary.writer.print(" tone-{s}", .{card.tone});
        try summary.writer.print("\"><div class=\"stat-value\">{d}</div><div class=\"stat-label\">", .{card.value});
        try web_html.text(&summary.writer, card.label);
        try summary.writer.writeAll("</div></article>");
    }
    try html.replaceElementInner(ctx.gpa, main, "summary-cards", "section", summary.written());

    var source_rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer source_rows.deinit();
    for (dashboard.sources) |source| {
        try source_rows.writer.writeAll("<tr data-source=\"");
        try web_html.attribute(&source_rows.writer, source.name);
        try source_rows.writer.writeAll("\" data-freshness=\"");
        try web_html.attribute(&source_rows.writer, @tagName(source.freshness));
        try source_rows.writer.writeAll("\"><td data-label=\"Source\"><strong>");
        try web_html.text(&source_rows.writer, source.label);
        try source_rows.writer.writeAll("</strong><div class=\"muted\">");
        try web_html.text(&source_rows.writer, if (source.local) "Local command" else "Provider API");
        try source_rows.writer.writeAll("</div></td><td data-label=\"Freshness\">");
        try html.writeStatus(&source_rows.writer, switch (source.freshness) {
            .current => "Current",
            .stale => "Stale",
            .unavailable => "Unavailable",
        });
        try source_rows.writer.writeAll("</td>");
        const observation = source.observation;
        const observed_at = if (observation) |value| (if (value.hasSuccessfulObservation()) value.observed_at else "") else "";
        try html.dashboardCellText(&source_rows.writer, "Observed", observed_at, "mono cell-nowrap", "Never");
        try source_rows.writer.writeAll("<td data-label=\"Last collection\"><strong>");
        try web_html.text(&source_rows.writer, html.collectionStatusLabel(if (observation) |value| value.attempt_status else ""));
        try source_rows.writer.writeAll("</strong>");
        if (observation) |value| {
            if (value.attempted_at.len > 0) {
                try source_rows.writer.writeAll(" <span class=\"muted mono\">");
                try web_html.text(&source_rows.writer, value.attempted_at);
                try source_rows.writer.writeAll("</span>");
            }
            if (value.attempt_summary.len > 0) {
                try source_rows.writer.writeAll("<div class=\"muted breakable\">");
                try web_html.text(&source_rows.writer, value.attempt_summary);
                try source_rows.writer.writeAll("</div>");
            }
        } else {
            try source_rows.writer.writeAll("<div class=\"muted breakable\">No refresh has run for this source.</div>");
        }
        try source_rows.writer.writeAll("</td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "dashboard-sources-body", "tbody", source_rows.written());

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (dashboard.rows.len == 0) try html.emptyRow(&rows.writer, 8, "No topology rows match this view.");
    for (dashboard.rows) |row| {
        try rows.writer.writeAll("<tr>");
        try dashboardStatusCell(&rows.writer, app_dashboard.status(row));
        try dashboardIdentityCell(&rows.writer, row);
        try dashboardBadgeCell(&rows.writer, "DNS match", app_dashboard.dnsMatch(row));
        try html.dashboardCellText(&rows.writer, "Exposure", app_dashboard.exposure(row), "muted", "—");
        try html.dashboardCellText(&rows.writer, "Upstream", row.upstream, "mono cell-nowrap", "—");
        try dashboardDetailCell(&rows.writer, "Service", row.service, row.service_state);
        try dashboardDetailCell(&rows.writer, "Container", row.container, row.container_status);
        try rows.writer.writeAll("<td data-label=\"Diagnosis\"><div class=\"diagnosis-list\">");
        const row_issues = app_dashboard.issues(row);
        if (row_issues.count() == 0) try rows.writer.writeAll("<span class=\"muted\">No action needed.</span>");
        var it = row_issues.iterator();
        while (it.next()) |issue| try writeDashboardIssue(&rows.writer, issue, row);
        try rows.writer.writeAll("</div></td></tr>");
    }
    try html.replaceElementInner(ctx.gpa, main, "topology-body", "tbody", rows.written());
}
fn injectDashboardStorage(ctx: context.Context, main: *[]u8) !void {
    const policy = app_maintenance.Policy.fromConfig(ctx.config);
    const stats = app_maintenance.inspect(.{ .io = ctx.io, .gpa = ctx.gpa, .db = ctx.db }, policy) catch |err| {
        var warning = std.Io.Writer.Allocating.init(ctx.gpa);
        defer warning.deinit();
        try warning.writer.writeAll("Storage accounting is unavailable (");
        try web_html.text(&warning.writer, @errorName(err));
        try warning.writer.writeAll("). Run <code>cloudio maintenance status</code> on the host and <a href=\"#storage-recovery\">review the recovery steps</a>.");
        try showDashboardStorageWarning(ctx, main, warning.written(), "danger", policy, null);
        return;
    };
    if (!stats.budgetWarning()) return;

    var warning = std.Io.Writer.Allocating.init(ctx.gpa);
    defer warning.deinit();
    try warning.writer.print(
        "Cloudio manages {d} bytes against a {d}-byte disk budget; safe maintenance needs about {d} additional bytes. <a href=\"#storage-recovery\">Review the exact recovery steps</a>.",
        .{ stats.managedBytes(), stats.disk_budget_bytes, stats.maintenanceHeadroomBytes() },
    );
    try showDashboardStorageWarning(ctx, main, warning.written(), "warning", policy, stats);
}
fn showDashboardStorageWarning(
    ctx: context.Context,
    main: *[]u8,
    warning_html: []const u8,
    tone_name: []const u8,
    policy: app_maintenance.Policy,
    stats: ?app_maintenance.Stats,
) !void {
    try html.replaceElementInner(ctx.gpa, main, "storage-warning", "div", warning_html);
    var class_buffer: [96]u8 = undefined;
    const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"storage-warning\" class=\"notice tone-{s}\" role=\"alert\"", .{tone_name});
    try html.replaceExact(ctx.gpa, main, "id=\"storage-warning\" class=\"notice hidden\"", replacement);

    const example_backup = try std.fs.path.join(ctx.gpa, &.{ policy.backup_root, "cloudio-YYYYMMDD-HHMMSS.db" });
    defer ctx.gpa.free(example_backup);
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<ol><li>Inspect every managed store: <code>cloudio maintenance status</code>.</li><li>Preview row eligibility: <code>cloudio maintenance run</code>.</li><li>When enough temporary space is available, run <code>cloudio maintenance run --apply --backup ");
    try web_html.text(&body.writer, example_backup);
    try body.writer.writeAll("</code>. The destination must not already exist.</li><li>If anything fails, stop and retain both the original database and verified backup; reopen with <code>cloudio doctor</code> before retrying.</li></ol><p>Cloudio never prunes files under <code>");
    try web_html.text(&body.writer, policy.backup_root);
    try body.writer.writeAll("</code>; backup retention is operator-managed. See <code>docs/storage-operations.md</code> for the full runbook.</p>");
    if (stats) |value| {
        try body.writer.print("<p>Current estimate: <strong>{d} bytes managed</strong>; reserve at least <strong>{d} additional bytes</strong> for backup and compaction.</p>", .{ value.managedBytes(), value.maintenanceHeadroomBytes() });
    }
    try html.replaceElementInner(ctx.gpa, main, "storage-recovery-body", "div", body.written());
    try html.replaceExact(ctx.gpa, main, "id=\"storage-recovery\" class=\"panel hidden\"", "id=\"storage-recovery\" class=\"panel\"");
}
const DashboardFeedback = struct { tone: []const u8, message: []const u8 };
fn dashboardFeedback(request: http.Request) ?DashboardFeedback {
    const result = request.query("refresh") orelse return null;
    if (std.mem.eql(u8, result, "ok")) return .{ .tone = "success", .message = "Every dashboard source refreshed successfully." };
    if (std.mem.eql(u8, result, "partial")) return .{ .tone = "warning", .message = "Dashboard refresh completed with source failures. Last-good observations were retained; review the source table below." };
    if (std.mem.eql(u8, result, "failed")) return .{ .tone = "danger", .message = "No dashboard source refreshed successfully. Existing observations were retained." };
    if (std.mem.eql(u8, result, "in_progress")) return .{ .tone = "warning", .message = "A dashboard refresh is already in progress." };
    if (std.mem.eql(u8, result, "security")) return .{ .tone = "danger", .message = "The refresh failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, result, "request")) return .{ .tone = "danger", .message = "The refresh form was invalid. Reload and try again." };
    if (std.mem.eql(u8, result, "idempotency")) return .{ .tone = "danger", .message = "The refresh form expired or its key was reused for different input. Reload and try again." };
    return null;
}
fn dashboardStatusCell(out: *std.Io.Writer, value: app_dashboard.Status) !void {
    try out.writeAll("<td data-label=\"Status\">");
    try html.writeStatus(out, switch (value) {
        .healthy => "Healthy",
        .degraded => "Degraded",
        .dns_only => "DNS only",
        .local_only => "Local only",
        .project_only => "Needs manifest",
    });
    try out.writeAll("</td>");
}
fn dashboardBadgeCell(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    try out.writeAll("<td data-label=\"");
    try web_html.attribute(out, label);
    try out.writeAll("\">");
    if (value.len == 0 or std.mem.eql(u8, value, "none")) {
        try out.writeAll("<span class=\"muted\">None</span>");
    } else {
        try html.writeBadge(out, value);
    }
    try out.writeAll("</td>");
}
fn dashboardDetailCell(out: *std.Io.Writer, label: []const u8, primary: []const u8, secondary: []const u8) !void {
    try out.writeAll("<td data-label=\"");
    try web_html.attribute(out, label);
    try out.writeAll("\">");
    try web_html.text(out, if (primary.len > 0) primary else "—");
    if (secondary.len > 0) {
        try out.writeAll(" <span class=\"muted\">(");
        try web_html.text(out, secondary);
        try out.writeAll(")</span>");
    }
    try out.writeAll("</td>");
}
fn dashboardIdentityCell(out: *std.Io.Writer, row: db_store.TopologyRow) !void {
    const identity = if (row.host.len > 0) row.host else row.project;
    try out.writeAll("<td data-label=\"Host\" class=\"mono cell-nowrap\">");
    if (identity.len == 0) {
        try out.writeAll("(unnamed)");
    } else if (row.container.len > 0) {
        try html.link(out, "/docker.html", "container", row.container, identity);
    } else if (row.project.len > 0) {
        try html.link(out, "/projects.html", "query", row.project, identity);
    } else if (row.upstream.len > 0 or row.caddy_source.len > 0) {
        try html.link(out, "/routes.html", "host", identity, identity);
    } else if (row.dns_name.len > 0) {
        try html.link(out, "/dns.html", "domain", row.dns_name, identity);
    } else {
        try web_html.text(out, identity);
    }
    try out.writeAll("</td>");
}
/// Each diagnosis names its problem and links to the one page that owns the fix.
fn writeDashboardIssue(out: *std.Io.Writer, issue: app_dashboard.Issue, row: db_store.TopologyRow) !void {
    const Diagnosis = struct { title: []const u8, description: []const u8, owner: []const u8, path: []const u8, query_name: []const u8, query_value: []const u8, tone: []const u8 };
    const diagnosis: Diagnosis = switch (issue) {
        .dns_without_local_target => .{ .title = "DNS has no local target", .description = "This public DNS name has no matching route or managed project.", .owner = "Routes", .path = "/routes.html", .query_name = "host", .query_value = if (row.dns_name.len > 0) row.dns_name else row.host, .tone = "danger" },
        .caddy_without_dns => .{ .title = "Route has no DNS record", .description = "Caddy knows this host, but the configured DNS observations do not.", .owner = "DNS", .path = "/dns.html", .query_name = "domain", .query_value = row.host, .tone = "danger" },
        .upstream_without_socket => .{ .title = "Upstream is not listening", .description = "The route points to an address with no observed listening socket.", .owner = "Routes", .path = "/routes.html", .query_name = "host", .query_value = row.host, .tone = "danger" },
        .project_without_runtime => .{ .title = "Project needs a manifest", .description = "This directory was discovered but is not enrolled as a managed runtime.", .owner = "Projects", .path = "/projects.html", .query_name = "query", .query_value = row.project, .tone = "info" },
        .service_not_running => .{ .title = "Service is not running", .description = "The observed service state is not active or running.", .owner = "Projects", .path = "/projects.html", .query_name = "query", .query_value = if (row.project.len > 0) row.project else row.service, .tone = "danger" },
        .container_not_running => .{ .title = "Container is not running", .description = "The observed Docker container is stopped, restarting, or unhealthy.", .owner = "Docker", .path = "/docker.html", .query_name = "container", .query_value = row.container, .tone = "danger" },
    };
    try out.writeAll("<div class=\"diagnosis tone-");
    try web_html.attribute(out, diagnosis.tone);
    try out.writeAll("\" data-issue=\"");
    try web_html.attribute(out, @tagName(issue));
    try out.writeAll("\"><strong>");
    try web_html.text(out, diagnosis.title);
    try out.writeAll("</strong><span>");
    try web_html.text(out, diagnosis.description);
    try out.writeAll("</span>");
    var owner_buffer: [64]u8 = undefined;
    try html.link(out, diagnosis.path, diagnosis.query_name, diagnosis.query_value, try std.fmt.bufPrint(&owner_buffer, "Open {s}", .{diagnosis.owner}));
    try out.writeAll("</div>");
}
