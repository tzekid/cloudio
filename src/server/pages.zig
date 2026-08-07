//! Authenticated, server-rendered first views for the Cloudio control plane.
//!
//! The application services remain the single read contract. This adapter
//! renders their JSON results into the existing authored page templates so
//! useful state, navigation, and forms arrive before JavaScript runs.

const std = @import("std");
const app_authentication = @import("app_authentication");
const app_caddy_desired = @import("app_caddy_desired");
const app_dashboard = @import("app_dashboard");
const app_browser_run = @import("app_browser_run");
const app_dns = @import("app_dns");
const app_nob_actions = @import("app_nob_actions");
const app_nob_projects = @import("app_nob_projects");
const app_nob_secrets = @import("app_nob_secrets");
const app_maintenance = @import("app_maintenance");
const app_system_control = @import("app_system_control");
const app_vps = @import("app_vps");
const app_web_resources = @import("app_web_resources");
const app_writes = @import("app_writes");
const db_store = @import("db_store");
const http = @import("http");
const web_html = @import("web_html");
const common = @import("common.zig");
const context = @import("context.zig");
const form = @import("form.zig");
const theme = @import("theme.zig");

const max_template_bytes = 512 * 1024;
const favicon_link =
    "<link rel=\"icon\" href=\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%230b1220'/%3E%3Cpath d='M18 40V24h8v16h20v8H26a8 8 0 0 1-8-8Z' fill='%234fd1c5'/%3E%3C/svg%3E\">\n";

const Page = enum {
    dashboard,
    projects,
    routes,
    dns,
    browser,
    vps,
    docker,
    audit,
    security,
    settings,

    fn title(self: Page) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .projects => "Projects",
            .routes => "Routes",
            .dns => "DNS",
            .browser => "Browser Run",
            .vps => "VPS",
            .docker => "Docker",
            .audit => "Audit log",
            .security => "Security",
            .settings => "Settings",
        };
    }

    fn id(self: Page) []const u8 {
        return switch (self) {
            .dashboard => "dashboard",
            .projects => "projects",
            .routes => "routes",
            .dns => "dns",
            .browser => "browser",
            .vps => "vps",
            .docker => "docker",
            .audit => "audit",
            .security => "security",
            .settings => "settings",
        };
    }

    fn template(self: Page) []const u8 {
        return switch (self) {
            .dashboard => "web/index.html",
            .projects => "web/projects.html",
            .routes => "web/routes.html",
            .dns => "web/dns.html",
            .browser => "web/browser.html",
            .vps => "web/vps.html",
            .docker => "web/docker.html",
            .audit => "web/audit.html",
            .security => "web/security.html",
            .settings => "web/settings.html",
        };
    }
};

const nav_items = [_]struct {
    page: Page,
    href: []const u8,
    label: []const u8,
}{
    .{ .page = .dashboard, .href = "/", .label = "Dashboard" },
    .{ .page = .projects, .href = "/projects.html", .label = "Projects" },
    .{ .page = .routes, .href = "/routes.html", .label = "Routes" },
    .{ .page = .dns, .href = "/dns.html", .label = "DNS" },
    .{ .page = .browser, .href = "/browser.html", .label = "Browser" },
    .{ .page = .vps, .href = "/vps.html", .label = "VPS" },
    .{ .page = .docker, .href = "/docker.html", .label = "Docker" },
    .{ .page = .audit, .href = "/audit.html", .label = "Audit" },
    .{ .page = .security, .href = "/security.html", .label = "Security" },
    .{ .page = .settings, .href = "/settings.html", .label = "Settings" },
};

pub fn isPagePath(path: []const u8) bool {
    return pageForPath(path) != null;
}

pub fn render(
    ctx: context.Context,
    request: http.Request,
    path: []const u8,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !bool {
    const page = pageForPath(path) orelse return false;
    const template = try std.Io.Dir.cwd().readFileAlloc(
        ctx.io,
        page.template(),
        ctx.gpa,
        .limited(max_template_bytes),
    );
    defer ctx.gpa.free(template);

    var main = try extractMain(ctx.gpa, template);
    defer ctx.gpa.free(main);

    try injectPageData(ctx, request, page, preference, &main);
    try writeDocumentStart(out, page, preference);
    try writeShellStart(out, page);
    try out.writeAll(main);
    try writeShellEnd(out);
    try web_html.documentEnd(out);
    return true;
}

pub fn isPublicPagePath(path: []const u8) bool {
    return std.mem.eql(u8, path, "/login.html") or std.mem.eql(u8, path, "/setup.html");
}

pub fn renderPublic(
    ctx: context.Context,
    path: []const u8,
    preference: theme.Preference,
    out: *std.Io.Writer,
) !bool {
    const template_path: []const u8 = if (std.mem.eql(u8, path, "/login.html"))
        "web/login.html"
    else if (std.mem.eql(u8, path, "/setup.html"))
        "web/setup.html"
    else
        return false;
    const template = try std.Io.Dir.cwd().readFileAlloc(
        ctx.io,
        template_path,
        ctx.gpa,
        .limited(max_template_bytes),
    );
    defer ctx.gpa.free(template);
    const main = try extractMain(ctx.gpa, template);
    defer ctx.gpa.free(main);

    var head = std.Io.Writer.Allocating.init(ctx.gpa);
    defer head.deinit();
    try head.writer.writeAll(favicon_link);
    try head.writer.writeAll("<link rel=\"stylesheet\" href=\"/assets/app.css\">\n");
    try head.writer.writeAll("<script defer src=\"/assets/passkeys.js\"></script>\n");
    try head.writer.writeAll(if (std.mem.eql(u8, path, "/login.html"))
        "<script defer src=\"/assets/pages/login.js\"></script>\n"
    else
        "<script defer src=\"/assets/pages/setup.js\"></script>\n");
    try web_html.documentStart(out, .{
        .title = if (std.mem.eql(u8, path, "/login.html"))
            "Sign in · Cloudio"
        else
            "Set up a passkey · Cloudio",
        .html_class = preference.rootClass(),
        .head = web_html.TrustedHtml.audited(head.written()),
        .body_class = "login-page",
    });
    try out.writeAll(main);
    try web_html.documentEnd(out);
    return true;
}

fn extractMain(gpa: std.mem.Allocator, template: []const u8) ![]u8 {
    const main_start = std.mem.indexOf(u8, template, "<main") orelse
        return error.InvalidPageTemplate;
    const main_end_start = std.mem.indexOfPos(u8, template, main_start, "</main>") orelse
        return error.InvalidPageTemplate;
    return gpa.dupe(u8, template[main_start .. main_end_start + "</main>".len]);
}

fn pageForPath(path: []const u8) ?Page {
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) return .dashboard;
    if (std.mem.eql(u8, path, "/projects.html")) return .projects;
    if (std.mem.eql(u8, path, "/routes.html")) return .routes;
    if (std.mem.eql(u8, path, "/dns.html")) return .dns;
    if (std.mem.eql(u8, path, "/browser.html")) return .browser;
    if (std.mem.eql(u8, path, "/vps.html")) return .vps;
    if (std.mem.eql(u8, path, "/docker.html")) return .docker;
    if (std.mem.eql(u8, path, "/audit.html")) return .audit;
    if (std.mem.eql(u8, path, "/security.html")) return .security;
    if (std.mem.eql(u8, path, "/settings.html")) return .settings;
    return null;
}

fn writeDocumentStart(out: *std.Io.Writer, page: Page, preference: theme.Preference) !void {
    var head = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer head.deinit();
    try head.writer.writeAll(favicon_link);
    try head.writer.writeAll("<link rel=\"stylesheet\" href=\"/assets/app.css\">\n");
    try head.writer.writeAll("<script defer src=\"/assets/app.js\"></script>\n");
    if (page == .security) {
        try head.writer.writeAll("<script defer src=\"/assets/passkeys.js\"></script>\n");
        try head.writer.writeAll("<script defer src=\"/assets/pages/security.js\"></script>\n");
    }
    var title_buffer: [96]u8 = undefined;
    const title = try std.fmt.bufPrint(&title_buffer, "{s} · Cloudio", .{page.title()});
    try web_html.documentStart(out, .{
        .title = title,
        .html_class = preference.rootClass(),
        .head = web_html.TrustedHtml.audited(head.written()),
        .body_class = "server-rendered",
    });
}

fn writeShellStart(out: *std.Io.Writer, active: Page) !void {
    try out.writeAll(
        \\<a class="skip-link" href="#page-content">Skip to content</a>
        \\<div class="shell" id="app-shell">
        \\<aside id="primary-sidebar" class="sidebar" aria-label="Application navigation" data-open="false">
        \\<a class="brand" href="/" aria-label="Cloudio dashboard">cloud<span>io</span></a>
        \\<nav class="primary-nav" aria-label="Primary"><ul>
    );
    for (nav_items) |item| {
        try out.writeAll("<li><a href=\"");
        try web_html.urlAttribute(out, item.href);
        try out.writeByte('"');
        if (item.page == active) try out.writeAll(" aria-current=\"page\"");
        try out.writeByte('>');
        try web_html.text(out, item.label);
        try out.writeAll("</a></li>");
    }
    try out.writeAll(
        \\</ul></nav><div class="sidebar-meta">Control plane</div></aside>
        \\<div class="workspace">
        \\<header class="titlebar">
        \\<button type="button" class="button menu-button" aria-controls="primary-sidebar" aria-expanded="false">Menu</button>
        \\<div class="titlebar-heading"><div class="titlebar-eyebrow">Cloudio</div><h1 id="page-title">
    );
    try web_html.text(out, active.title());
    try out.writeAll("</h1></div><div class=\"titlebar-actions\">");
    try out.writeAll("</div></header>\n");
}

fn writeShellEnd(out: *std.Io.Writer) !void {
    try out.writeAll(
        \\</div></div>
        \\<button type="button" class="button sidebar-scrim" aria-label="Close navigation" data-open="false">Close navigation</button>
    );
}

fn injectPageData(
    ctx: context.Context,
    request: http.Request,
    page: Page,
    preference: theme.Preference,
    main: *[]u8,
) !void {
    switch (page) {
        .dashboard => try injectDashboard(ctx, request, main),
        .projects => try injectProjects(ctx, request, main),
        .routes => try injectRoutes(ctx, request, main),
        .dns => try injectDns(ctx, request, main),
        .browser => try injectBrowser(ctx, request, main),
        .vps => try injectVps(ctx, request, main),
        .docker => try injectDocker(ctx, request, main),
        .audit => try injectAudit(ctx, request, main),
        .security => try injectSecurity(ctx, request, main),
        .settings => try injectSettings(ctx, request, preference, main),
    }
}

fn dashboardContext(ctx: context.Context) app_dashboard.Context {
    const refresh_seconds: i64 = @intCast(ctx.config.refresh_seconds);
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
        .fresh_after_seconds = @max(refresh_seconds * 2, 60),
    };
}

fn injectDashboard(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    try injectDashboardStorage(ctx, main);
    try replaceHiddenInput(
        ctx.gpa,
        main,
        "dashboard-refresh-csrf",
        "csrf_token",
        ctx.auth_csrf_token orelse "",
    );
    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try formIdempotencyKey(ctx.io, &refresh_key_buffer, "dashboard-refresh");
    try replaceHiddenInput(
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
        try replaceElementInner(ctx.gpa, main, "dashboard-feedback", "div", escaped.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"dashboard-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"dashboard-feedback\" class=\"notice hidden\"", replacement);
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
        try replaceExact(
            ctx.gpa,
            main,
            "<input id=\"domain-filter\" name=\"domain\" type=\"text\" placeholder=\"example.com\" autocomplete=\"off\">",
            input.written(),
        );
    }
    if (request.query("issues")) |issues| {
        if (std.mem.eql(u8, issues, "1") or std.mem.eql(u8, issues, "true")) {
            try replaceExact(
                ctx.gpa,
                main,
                "<input id=\"issues-only\" name=\"issues\" value=\"1\" type=\"checkbox\">",
                "<input id=\"issues-only\" name=\"issues\" value=\"1\" type=\"checkbox\" checked>",
            );
        }
    }
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_dashboard.writeJson(
        dashboardContext(ctx),
        common.dashboardOptions(request, ctx.dashboard),
        &json.writer,
    );
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    const topology = nested(parsed.value, &.{ "summary", "topology" }) orelse .null;
    const statuses = member(topology, "statuses") orelse .null;
    var issue_total: i64 = 0;
    if (member(topology, "issues")) |issues| {
        if (issues == .object) {
            var it = issues.object.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, "project_without_runtime")) continue;
                issue_total += asInt(entry.value_ptr.*);
            }
        }
    }
    const cards = [_]struct { label: []const u8, value: i64, tone: []const u8 }{
        .{ .label = "Hosts", .value = intField(topology, "total"), .tone = "" },
        .{ .label = "Healthy", .value = intField(statuses, "healthy"), .tone = "success" },
        .{ .label = "Degraded", .value = intField(statuses, "degraded"), .tone = if (intField(statuses, "degraded") > 0) "danger" else "" },
        .{ .label = "DNS only", .value = intField(statuses, "dns_only"), .tone = if (intField(statuses, "dns_only") > 0) "warning" else "" },
        .{ .label = "Local only", .value = intField(statuses, "local_only"), .tone = if (intField(statuses, "local_only") > 0) "warning" else "" },
        .{ .label = "Needs manifest", .value = intField(statuses, "project_only"), .tone = if (intField(statuses, "project_only") > 0) "info" else "" },
        .{ .label = "Incidents", .value = issue_total, .tone = if (issue_total > 0) "danger" else "success" },
    };
    for (cards) |card| {
        try summary.writer.writeAll("<article class=\"stat-card");
        if (card.tone.len > 0) try summary.writer.print(" tone-{s}", .{card.tone});
        try summary.writer.print("\"><div class=\"stat-value\">{d}</div><div class=\"stat-label\">", .{card.value});
        try web_html.text(&summary.writer, card.label);
        try summary.writer.writeAll("</div></article>");
    }
    try replaceElementInner(ctx.gpa, main, "summary-cards", "section", summary.written());

    var source_rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer source_rows.deinit();
    const sources = arrayItems(nested(parsed.value, &.{ "summary", "sources" }));
    if (sources.len == 0) {
        try emptyRow(&source_rows.writer, 4, "No source refresh has run yet.");
    } else for (sources) |source| {
        const freshness = strField(source, "freshness");
        const collection = member(source, "collection") orelse .null;
        try source_rows.writer.writeAll("<tr data-source=\"");
        try web_html.attribute(&source_rows.writer, strField(source, "name"));
        try source_rows.writer.writeAll("\" data-freshness=\"");
        try web_html.attribute(&source_rows.writer, freshness);
        try source_rows.writer.writeAll("\"><td data-label=\"Source\"><strong>");
        try web_html.text(&source_rows.writer, strField(source, "label"));
        try source_rows.writer.writeAll("</strong><div class=\"muted\">");
        try web_html.text(&source_rows.writer, sourceTypeLabel(strField(source, "source")));
        try source_rows.writer.writeAll("</div></td><td data-label=\"Freshness\">");
        try writeStatus(&source_rows.writer, freshnessLabel(freshness));
        try source_rows.writer.writeAll("</td>");
        try dashboardCellText(&source_rows.writer, "Observed", nullableString(member(source, "observed_at")), "mono cell-nowrap", "Never");
        try source_rows.writer.writeAll("<td data-label=\"Last collection\"><strong>");
        try web_html.text(&source_rows.writer, collectionStatusLabel(strField(collection, "status")));
        try source_rows.writer.writeAll("</strong>");
        const attempted_at = nullableString(member(collection, "attempted_at"));
        if (attempted_at.len > 0) {
            try source_rows.writer.writeAll(" <span class=\"muted mono\">");
            try web_html.text(&source_rows.writer, attempted_at);
            try source_rows.writer.writeAll("</span>");
        }
        const collection_summary = strField(collection, "summary");
        if (collection_summary.len > 0) {
            try source_rows.writer.writeAll("<div class=\"muted breakable\">");
            try web_html.text(&source_rows.writer, collection_summary);
            try source_rows.writer.writeAll("</div>");
        }
        try source_rows.writer.writeAll("</td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "dashboard-sources-body", "tbody", source_rows.written());

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    const topology_rows = nested(parsed.value, &.{ "sections", "domains", "topology" });
    if (arrayItems(topology_rows).len == 0) {
        try emptyRow(&rows.writer, 8, "No topology rows match this view.");
    } else for (arrayItems(topology_rows)) |row| {
        try rows.writer.writeAll("<tr>");
        try dashboardStatusCell(&rows.writer, strField(row, "status"));
        try dashboardIdentityCell(&rows.writer, row);
        try dashboardBadgeCell(&rows.writer, "DNS match", strField(row, "dns_match"));
        try dashboardCellText(&rows.writer, "Exposure", strField(row, "exposure"), "muted", "—");
        try dashboardCellText(&rows.writer, "Upstream", strField(row, "upstream"), "mono cell-nowrap", "—");
        try dashboardDetailCell(&rows.writer, "Service", strField(row, "service"), strField(row, "service_state"));
        try dashboardDetailCell(&rows.writer, "Container", strField(row, "container"), strField(row, "container_status"));
        try rows.writer.writeAll("<td data-label=\"Diagnosis\"><div class=\"diagnosis-list\">");
        const issues = arrayItems(member(row, "issues"));
        if (issues.len == 0) try rows.writer.writeAll("<span class=\"muted\">No action needed.</span>");
        for (issues) |issue| try writeDashboardIssue(&rows.writer, asString(issue), row);
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "topology-body", "tbody", rows.written());
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
    try replaceElementInner(ctx.gpa, main, "storage-warning", "div", warning_html);
    var class_buffer: [96]u8 = undefined;
    const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"storage-warning\" class=\"notice tone-{s}\" role=\"alert\"", .{tone_name});
    try replaceExact(ctx.gpa, main, "id=\"storage-warning\" class=\"notice hidden\"", replacement);

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
    try replaceElementInner(ctx.gpa, main, "storage-recovery-body", "div", body.written());
    try replaceExact(ctx.gpa, main, "id=\"storage-recovery\" class=\"panel hidden\"", "id=\"storage-recovery\" class=\"panel\"");
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

const ProjectView = enum {
    current,
    needs_manifest,
    all,

    fn parse(value: ?[]const u8) ProjectView {
        const raw = value orelse return .current;
        if (std.mem.eql(u8, raw, "needs-manifest")) return .needs_manifest;
        if (std.mem.eql(u8, raw, "all")) return .all;
        return .current;
    }

    fn query(self: ProjectView) []const u8 {
        return switch (self) {
            .current => "current",
            .needs_manifest => "needs-manifest",
            .all => "all",
        };
    }
};

fn injectProjects(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var scan_key_buffer: [80]u8 = undefined;
    const scan_key = try formIdempotencyKey(ctx.io, &scan_key_buffer, "projects-scan");
    try replaceHiddenInput(ctx.gpa, main, "projects-scan-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "projects-scan-idempotency", "idempotency_key", scan_key);

    if (projectFeedback(request)) |feedback| {
        var message = std.Io.Writer.Allocating.init(ctx.gpa);
        defer message.deinit();
        try web_html.text(&message.writer, feedback.message);
        try replaceElementInner(ctx.gpa, main, "projects-feedback", "div", message.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"projects-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"projects-feedback\" class=\"notice hidden\"", replacement);
    }

    var projects = try app_nob_projects.list(context.nob(ctx));
    defer projects.deinit(ctx.gpa);
    const view = ProjectView.parse(request.query("view"));
    var current_count: usize = 0;
    var candidate_count: usize = 0;
    for (projects.items) |project| {
        if (project.discovery_state == .candidate) candidate_count += 1 else if (project.discovery_state != .ignored) current_count += 1;
    }

    var links = std.Io.Writer.Allocating.init(ctx.gpa);
    defer links.deinit();
    try projectViewLink(&links.writer, view, .current, "Current", current_count);
    try projectViewLink(&links.writer, view, .needs_manifest, "Needs manifest", candidate_count);
    try projectViewLink(&links.writer, view, .all, "All", projects.items.len);
    try replaceElementInner(ctx.gpa, main, "project-view-links", "div", links.written());

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    var shown: usize = 0;
    for (projects.items) |project| {
        if (!projectMatchesView(project, view)) continue;
        shown += 1;
        try rows.writer.writeAll("<tr><td data-label=\"Project\"><a class=\"button-link\" href=\"/projects.html?view=");
        try web_html.urlAttribute(&rows.writer, view.query());
        try rows.writer.writeAll("&amp;project=");
        try rows.writer.print("{d}", .{project.id});
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, project.display_name);
        try rows.writer.writeAll("</a><div class=\"muted mono breakable\">");
        try web_html.text(&rows.writer, project.declared_id orelse project.root_path);
        try rows.writer.writeAll("</div></td>");
        try cellBadge(&rows.writer, project.kind);
        try cellBadge(&rows.writer, discoveryLabel(project.discovery_state));
        try cellBadge(&rows.writer, trustLabel(project.trust_state));
        try cellStatus(&rows.writer, project.status.text());
        try cellBadge(&rows.writer, runnerLabel(project.runner_state));
        try rows.writer.writeAll("<td data-label=\"Open\"><a class=\"button button-small\" href=\"/projects.html?view=");
        try web_html.urlAttribute(&rows.writer, view.query());
        try rows.writer.writeAll("&amp;project=");
        try rows.writer.print("{d}", .{project.id});
        try rows.writer.writeAll("\">Review</a></td></tr>");
    }
    if (shown == 0) {
        try emptyRow(&rows.writer, 7, if (view == .needs_manifest)
            "No marker-only candidates need a manifest."
        else
            "No projects match this view. Scan the projects folder to begin.");
    }
    try replaceElementInner(ctx.gpa, main, "nob-projects-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "nob-projects-count", "span", shown, "project", "projects");

    const selected_reference = request.query("project") orelse return;
    var details = (try app_nob_projects.show(context.nob(ctx), selected_reference)) orelse {
        try showMissingProject(ctx, main);
        return;
    };
    defer details.deinit(ctx.gpa);
    try renderProjectDetail(ctx, request, details, main);
    if (request.query("plan")) |plan_id| try renderProjectPlan(ctx, details.project, plan_id, main);
    if (request.query("run")) |run_id| try renderProjectRun(ctx, details.project, run_id, main);
}

fn projectMatchesView(project: db_store.NobProject, view: ProjectView) bool {
    return switch (view) {
        .current => project.discovery_state != .candidate and project.discovery_state != .ignored,
        .needs_manifest => project.discovery_state == .candidate,
        .all => true,
    };
}

fn projectViewLink(out: *std.Io.Writer, active: ProjectView, item: ProjectView, label: []const u8, count: usize) !void {
    try out.writeAll("<a class=\"button button-small");
    if (active == item) try out.writeAll(" button-primary");
    try out.writeAll("\" href=\"/projects.html?view=");
    try web_html.urlAttribute(out, item.query());
    try out.writeAll("\"");
    if (active == item) try out.writeAll(" aria-current=\"page\"");
    try out.writeByte('>');
    try web_html.text(out, label);
    try out.print(" ({d})</a>", .{count});
}

fn showMissingProject(ctx: context.Context, main: *[]u8) !void {
    try replaceElementInner(ctx.gpa, main, "nob-project-detail-content", "div", "<div class=\"panel-body empty-state\">The selected project no longer exists.</div>");
    try replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-project-detail\"", "class=\"panel\" id=\"nob-project-detail\"");
}

fn renderProjectDetail(ctx: context.Context, request: http.Request, details: app_nob_projects.Details, main: *[]u8) !void {
    const project = details.project;
    var content = std.Io.Writer.Allocating.init(ctx.gpa);
    defer content.deinit();
    try content.writer.writeAll("<div class=\"panel-header\"><div><h2 id=\"nob-project-detail-title\">");
    try web_html.text(&content.writer, project.display_name);
    try content.writer.writeAll("</h2><p class=\"mono breakable\">");
    try web_html.text(&content.writer, project.declared_id orelse project.root_path);
    try content.writer.writeAll("</p></div><a class=\"button button-small\" href=\"/projects.html\">Close</a></div><div class=\"panel-body stack\">");

    try content.writer.writeAll("<dl class=\"kv-list\">");
    try projectFact(&content.writer, "Root", project.root_path, true);
    try projectFact(&content.writer, "Manifest digest", project.manifest_sha256 orelse "Unavailable", true);
    try projectFact(&content.writer, "Declaration", discoveryLabel(project.discovery_state), false);
    try projectFact(&content.writer, "Approval", trustLabel(project.trust_state), false);
    try projectFact(&content.writer, "Runner", runnerLabel(project.runner_state), false);
    try projectFact(&content.writer, "Observed state", project.status_summary orelse project.status.text(), false);
    try projectFact(&content.writer, "Source revision", project.head_revision orelse "Not observed", true);
    try projectFact(&content.writer, "Source fingerprint", project.source_fingerprint orelse "Not observed", true);
    try content.writer.writeAll("</dl>");

    try content.writer.writeAll("<div class=\"cluster\" aria-label=\"Project controls\">");
    if ((project.discovery_state == .valid or (project.discovery_state == .ignored and project.last_scan_state == .valid)) and project.manifest_sha256 != null and project.trust_state != .trusted) {
        try projectSimpleForm(ctx, &content.writer, project.id, "trust", if (project.discovery_state == .ignored) "Restore exact approval" else "Approve exact manifest", "button-primary", &.{.{ "manifest_sha256", project.manifest_sha256.? }});
    }
    if (project.discovery_state == .valid and project.trust_state == .trusted) {
        if (project.runner_state == .ready) {
            try projectSimpleForm(ctx, &content.writer, project.id, "observe", "Refresh observation", "", &.{});
        } else if (project.runner_state != .building) {
            try projectSimpleForm(ctx, &content.writer, project.id, "prepare", "Prepare and observe", "button-primary", &.{});
        }
    }
    if (project.trust_state == .trusted or project.trust_state == .@"review-required") {
        try projectConfirmedForm(ctx, &content.writer, project, "revoke", "Revoke approval");
    }
    if (project.discovery_state != .ignored) try projectConfirmedForm(ctx, &content.writer, project, "forget", "Forget project");
    try content.writer.writeAll("</div>");
    try renderProjectResources(ctx, request, project, details.resources.items, &content.writer);
    try renderProjectActions(ctx, project, details.actions.items, &content.writer);
    try renderProjectSecrets(ctx, project, &content.writer);
    try renderProjectRuns(ctx, project, &content.writer);
    try content.writer.writeAll("</div>");

    try replaceElementInner(ctx.gpa, main, "nob-project-detail-content", "div", content.written());
    try replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-project-detail\"", "class=\"panel\" id=\"nob-project-detail\"");
}

const FormField = struct { []const u8, []const u8 };

fn projectSimpleForm(
    ctx: context.Context,
    out: *std.Io.Writer,
    project_id: i64,
    operation: []const u8,
    label: []const u8,
    button_class: []const u8,
    extra: []const FormField,
) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, operation);
    try out.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/projects/action\">");
    try writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(out, "idempotency_key", key);
    try writeHiddenInput(out, "operation", operation);
    var project_buffer: [32]u8 = undefined;
    try writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project_id}));
    for (extra) |field| try writeHiddenInput(out, field[0], field[1]);
    try out.writeAll("<button class=\"button button-small ");
    try web_html.attribute(out, button_class);
    try out.writeAll("\" type=\"submit\">");
    try web_html.text(out, label);
    try out.writeAll("</button></form>");
}

fn projectConfirmedForm(ctx: context.Context, out: *std.Io.Writer, project: db_store.NobProject, operation: []const u8, label: []const u8) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, operation);
    var project_buffer: [32]u8 = undefined;
    const project_reference = try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id});
    const confirmation = project.declared_id orelse project_reference;
    try out.writeAll("<form class=\"inline-form confirm-form\" method=\"post\" action=\"/projects/action\">");
    try writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(out, "idempotency_key", key);
    try writeHiddenInput(out, "operation", operation);
    try writeHiddenInput(out, "project", project_reference);
    try out.writeAll("<label class=\"sr-only\">Type project ID to confirm<input name=\"confirmation\" required autocomplete=\"off\" placeholder=\"");
    try web_html.attribute(out, confirmation);
    try out.writeAll("\"></label><button class=\"button button-small button-danger\" type=\"submit\">");
    try web_html.text(out, label);
    try out.writeAll("</button></form>");
}

fn projectFact(out: *std.Io.Writer, label: []const u8, value: []const u8, mono: bool) !void {
    try out.writeAll("<div><dt>");
    try web_html.text(out, label);
    try out.writeAll("</dt><dd");
    if (mono) try out.writeAll(" class=\"mono breakable\"");
    try out.writeByte('>');
    try web_html.text(out, value);
    try out.writeAll("</dd></div>");
}

fn renderProjectResources(ctx: context.Context, request: http.Request, project: db_store.NobProject, resources: []const db_store.NobResource, out: *std.Io.Writer) !void {
    try out.writeAll("<section aria-labelledby=\"nob-resources-title\"><h3 id=\"nob-resources-title\" class=\"section-heading\">Resources</h3><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Resource</th><th scope=\"col\">Kind</th><th scope=\"col\">Ownership</th><th scope=\"col\">Status</th><th scope=\"col\">Controls or blocker</th></tr></thead><tbody>");
    if (resources.len == 0) try emptyRow(out, 5, "This project declares no resources.");
    for (resources) |resource| {
        try out.writeAll("<tr><td data-label=\"Resource\"><strong>");
        try web_html.text(out, resource.label);
        try out.writeAll("</strong><div class=\"muted mono\">");
        try web_html.text(out, resource.resource_id);
        try out.writeAll("</div></td>");
        try cellBadge(out, resource.kind);
        try cellBadge(out, resource.ownership);
        try out.writeAll("<td data-label=\"Status\">");
        try writeStatus(out, resource.effective_status.text());
        if (resource.status_summary) |summary| {
            try out.writeAll("<div class=\"muted\">");
            try web_html.text(out, summary);
            try out.writeAll("</div>");
        }
        try out.writeAll("</td><td data-label=\"Controls or blocker\"><div class=\"cluster\">");
        var parsed = std.json.parseFromSlice(std.json.Value, ctx.gpa, resource.declaration_json, .{}) catch null;
        defer if (parsed) |*value| value.deinit();
        const controls = if (parsed) |value| arrayItems(member(value.value, "controls")) else &.{};
        var mutable_controls: usize = 0;
        for (controls) |control_value| {
            const control = asString(control_value);
            if (std.mem.eql(u8, control, "logs")) {
                try out.writeAll("<a class=\"button button-small\" href=\"/projects.html?project=");
                try out.print("{d}", .{project.id});
                try out.writeAll("&amp;resource_logs=");
                try writeUrlQueryComponent(out, resource.resource_id);
                try out.writeAll("\">Logs</a>");
                continue;
            }
            mutable_controls += 1;
            if (resourceControlBlocker(ctx, resource, if (parsed) |value| value.value else .null)) |_| continue;
            var resource_fields = [_]FormField{
                .{ "resource_id", resource.resource_id },
                .{ "control_name", control },
            };
            try projectSimpleForm(ctx, out, project.id, "resource-plan", control, "", &resource_fields);
        }
        if (resourceControlBlocker(ctx, resource, if (parsed) |value| value.value else .null)) |blocker| {
            try out.writeAll("<span class=\"muted\">");
            try web_html.text(out, blocker);
            try out.writeAll("</span>");
        } else if (controls.len == 0 or (mutable_controls == 0 and !controlsContain(controls, "logs"))) {
            try out.writeAll("<span class=\"muted\">No controls declared.</span>");
        }
        try out.writeAll("</div></td></tr>");
    }
    try out.writeAll("</tbody></table></div>");
    if (request.query("resource_logs")) |resource_id| {
        try out.writeAll("<h4>Resource log tail</h4><pre class=\"log-output\">");
        var project_reference_buffer: [32]u8 = undefined;
        const project_reference = try std.fmt.bufPrint(&project_reference_buffer, "{d}", .{project.id});
        const bytes = app_nob_actions.resourceLogs(context.nobActions(ctx), project_reference, resource_id, 200) catch |err| {
            try web_html.text(out, @errorName(err));
            try out.writeAll("</pre>");
            return;
        };
        defer ctx.gpa.free(bytes);
        try web_html.text(out, bytes);
        try out.writeAll("</pre>");
    }
    try out.writeAll("</section>");
}

fn resourceControlBlocker(ctx: context.Context, resource: db_store.NobResource, declaration: std.json.Value) ?[]const u8 {
    if (std.mem.eql(u8, resource.ownership, "observed")) return "Observed-only resources cannot be changed.";
    if (!std.mem.eql(u8, resource.kind, "systemd.service")) return "Direct controls are supported only for declared user services.";
    const scope = strField(member(declaration, "spec") orelse .null, "scope");
    if (!std.mem.eql(u8, scope, "user")) return "System-scope services are outside the Projects control boundary.";
    if (!ctx.config.nob_allow_system_mutation) return "System mutation is disabled by the global kill switch.";
    return null;
}

fn controlsContain(controls: []const std.json.Value, expected: []const u8) bool {
    for (controls) |control| if (std.mem.eql(u8, asString(control), expected)) return true;
    return false;
}

fn renderProjectActions(ctx: context.Context, project: db_store.NobProject, actions: []const db_store.NobAction, out: *std.Io.Writer) !void {
    try out.writeAll("<section aria-labelledby=\"nob-actions-title\"><h3 id=\"nob-actions-title\" class=\"section-heading\">Actions</h3><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Action</th><th scope=\"col\">Effect</th><th scope=\"col\">Approval</th><th scope=\"col\">Plan</th></tr></thead><tbody>");
    if (actions.len == 0) try emptyRow(out, 4, "This project declares no actions.");
    for (actions) |action| {
        var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, action.declaration_json, .{});
        defer parsed.deinit();
        try out.writeAll("<tr><td data-label=\"Action\"><strong>");
        try web_html.text(out, action.label);
        try out.writeAll("</strong><div class=\"muted\">");
        try web_html.text(out, strField(parsed.value, "description"));
        try out.writeAll("</div><div class=\"muted mono\">");
        try web_html.text(out, action.action_id);
        try out.writeAll("</div></td>");
        try cellBadge(out, action.effect);
        try cellBadge(out, action.confirmation);
        try out.writeAll("<td data-label=\"Plan\">");
        if (project.trust_state != .trusted or project.runner_state != .ready) {
            try out.writeAll("<span class=\"muted\">Approve and prepare this exact manifest first.</span>");
        } else if (!action.available) {
            try out.writeAll("<span class=\"muted\">");
            try web_html.text(out, action.unavailable_reason orelse "Runner did not make this action available.");
            try out.writeAll("</span>");
        } else {
            var key_buffer: [80]u8 = undefined;
            const key = try formIdempotencyKey(ctx.io, &key_buffer, "project-plan");
            try out.writeAll("<form class=\"stack compact-form\" method=\"post\" action=\"/projects/action\">");
            try writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
            try writeHiddenInput(out, "idempotency_key", key);
            try writeHiddenInput(out, "operation", "plan");
            var project_buffer: [32]u8 = undefined;
            try writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id}));
            try writeHiddenInput(out, "action_id", action.action_id);
            try writeActionParameters(out, arrayItems(member(parsed.value, "parameters")));
            try out.writeAll("<p class=\"muted\">Source policy: ");
            try web_html.text(out, strField(parsed.value, "source_policy"));
            try out.writeAll(" · rollback: ");
            try web_html.text(out, strField(parsed.value, "rollback"));
            try out.print(" · timeout: {d}s</p><button class=\"button button-small button-primary\" type=\"submit\">Create reviewable plan</button></form>", .{asInt(member(parsed.value, "timeout_seconds") orelse .{ .integer = 0 })});
        }
        try out.writeAll("</td></tr>");
    }
    try out.writeAll("</tbody></table></div></section>");
}

fn writeActionParameters(out: *std.Io.Writer, parameters: []const std.json.Value) !void {
    for (parameters) |parameter| {
        const name = strField(parameter, "name");
        const parameter_type = strField(parameter, "type");
        const required = boolField(parameter, "required");
        try out.writeAll("<label>");
        try web_html.text(out, name);
        if (!required) try out.writeAll(" <span class=\"muted\">(optional)</span>");
        if (std.mem.eql(u8, parameter_type, "enum") or std.mem.eql(u8, parameter_type, "boolean")) {
            try out.writeAll("<select name=\"param.");
            try web_html.attribute(out, name);
            try out.writeAll("\"");
            if (required) try out.writeAll(" required");
            try out.writeByte('>');
            if (!required) try out.writeAll("<option value=\"\">Use default or omit</option>");
            if (std.mem.eql(u8, parameter_type, "boolean")) {
                try out.writeAll("<option value=\"true\">true</option><option value=\"false\">false</option>");
            } else for (arrayItems(member(parameter, "values"))) |candidate| {
                try out.writeAll("<option value=\"");
                try web_html.attribute(out, asString(candidate));
                try out.writeAll("\">");
                try web_html.text(out, asString(candidate));
                try out.writeAll("</option>");
            }
            try out.writeAll("</select></label>");
        } else {
            try out.writeAll("<input name=\"param.");
            try web_html.attribute(out, name);
            try out.writeAll("\" type=\"");
            try out.writeAll(if (std.mem.eql(u8, parameter_type, "integer")) "number" else "text");
            try out.writeAll("\"");
            if (required) try out.writeAll(" required");
            if (member(parameter, "min_length")) |value| if (value == .integer) try out.print(" minlength=\"{d}\"", .{value.integer});
            if (member(parameter, "max_length")) |value| if (value == .integer) try out.print(" maxlength=\"{d}\"", .{value.integer});
            if (member(parameter, "minimum")) |value| if (value == .integer) try out.print(" min=\"{d}\"", .{value.integer});
            if (member(parameter, "maximum")) |value| if (value == .integer) try out.print(" max=\"{d}\"", .{value.integer});
            try out.writeAll("></label>");
        }
    }
}

fn renderProjectSecrets(ctx: context.Context, project: db_store.NobProject, out: *std.Io.Writer) !void {
    try out.writeAll("<section aria-labelledby=\"nob-secrets-title\"><h3 id=\"nob-secrets-title\" class=\"section-heading\">Secrets</h3><p>Bindings expose only logical status and source kind. Source references and values are never returned.</p><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Secret</th><th scope=\"col\">Required for</th><th scope=\"col\">Status</th><th scope=\"col\">Manage</th></tr></thead><tbody>");
    if (project.trust_state != .trusted) {
        try emptyRow(out, 4, "Approve the current manifest to inspect or bind its declared secrets.");
        try out.writeAll("</tbody></table></div></section>");
        return;
    }
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    var project_reference_buffer: [32]u8 = undefined;
    const project_reference = try std.fmt.bufPrint(&project_reference_buffer, "{d}", .{project.id});
    app_nob_secrets.writeJson(context.nobSecrets(ctx), project_reference, &json.writer) catch |err| {
        try emptyRow(out, 4, @errorName(err));
        try out.writeAll("</tbody></table></div></section>");
        return;
    };
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const secrets = arrayItems(member(parsed.value, "items"));
    if (secrets.len == 0) try emptyRow(out, 4, "This project declares no secrets.");
    for (secrets) |secret| {
        const secret_id = strField(secret, "secret_id");
        try out.writeAll("<tr><td data-label=\"Secret\"><strong class=\"mono\">");
        try web_html.text(out, secret_id);
        try out.writeAll("</strong><div class=\"muted\">");
        try web_html.text(out, strField(secret, "purpose"));
        try out.writeAll("</div></td><td data-label=\"Required for\">");
        try writeStringArray(out, arrayItems(member(secret, "required_for")));
        try out.writeAll("</td><td data-label=\"Status\">");
        try writeBadge(out, if (boolField(secret, "bound")) if (boolField(secret, "present")) "present" else "unavailable" else "unbound");
        const source_kind = nullableString(member(secret, "source_kind"));
        if (source_kind.len > 0) {
            try out.writeAll("<div class=\"muted\">Source: ");
            try web_html.text(out, source_kind);
            try out.writeAll("</div>");
        }
        try out.writeAll("</td><td data-label=\"Manage\"><div class=\"stack\">");
        try secretBindForm(ctx, out, project.id, secret_id);
        if (boolField(secret, "bound")) {
            var fields = [_]FormField{.{ "secret_id", secret_id }};
            try projectSimpleForm(ctx, out, project.id, "secret-unbind", "Unbind", "button-danger", &fields);
        }
        try out.writeAll("</div></td></tr>");
    }
    try out.writeAll("</tbody></table></div></section>");
}

fn secretBindForm(ctx: context.Context, out: *std.Io.Writer, project_id: i64, secret_id: []const u8) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "secret-bind");
    var project_buffer: [32]u8 = undefined;
    try out.writeAll("<form class=\"stack compact-form\" method=\"post\" action=\"/projects/action\">");
    try writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(out, "idempotency_key", key);
    try writeHiddenInput(out, "operation", "secret-bind");
    try writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project_id}));
    try writeHiddenInput(out, "secret_id", secret_id);
    try out.writeAll("<label>Source kind<select name=\"source_kind\"><option value=\"file\">File</option><option value=\"process-environment\">Process environment</option></select></label><label>Absolute path or environment name<input name=\"source_ref\" required autocomplete=\"off\"></label><button class=\"button button-small\" type=\"submit\">Bind source</button></form>");
}

fn renderProjectRuns(ctx: context.Context, project: db_store.NobProject, out: *std.Io.Writer) !void {
    var runs = try app_nob_actions.listRuns(context.nobActions(ctx), project.id, 20);
    defer runs.deinit(ctx.gpa);
    try out.writeAll("<section aria-labelledby=\"nob-runs-title\"><h3 id=\"nob-runs-title\" class=\"section-heading\">Recent operations</h3><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Operation</th><th scope=\"col\">Action</th><th scope=\"col\">State</th><th scope=\"col\">Summary</th></tr></thead><tbody>");
    if (runs.items.len == 0) try emptyRow(out, 4, "No operations have run for this project.");
    for (runs.items) |run| {
        try out.writeAll("<tr><td data-label=\"Operation\"><a class=\"mono\" href=\"/projects.html?project=");
        try out.print("{d}", .{project.id});
        try out.writeAll("&amp;run=");
        try writeUrlQueryComponent(out, run.id);
        try out.writeAll("\">");
        try web_html.text(out, run.id);
        try out.writeAll("</a></td>");
        try cellText(out, run.action_id, "mono breakable");
        try cellBadge(out, run.state);
        try cellText(out, run.summary orelse run.outcome orelse "Pending", "");
        try out.writeAll("</tr>");
    }
    try out.writeAll("</tbody></table></div></section>");
}

fn renderProjectPlan(ctx: context.Context, project: db_store.NobProject, plan_id: []const u8, main: *[]u8) !void {
    const stored = (try app_nob_actions.getPlan(context.nobActions(ctx), plan_id)) orelse return;
    defer stored.deinit(ctx.gpa);
    if (stored.project_id != project.id) return;
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, stored.plan_json, .{});
    defer parsed.deinit();
    const plan = parsed.value;
    var content = std.Io.Writer.Allocating.init(ctx.gpa);
    defer content.deinit();
    try content.writer.writeAll("<div class=\"panel-header\"><div><h2 id=\"nob-plan-review-title\">Review exact plan</h2><p>Running consumes this immutable plan once. Any manifest, runner, or source change rejects it.</p></div></div><div class=\"panel-body stack\"><dl class=\"kv-list\">");
    try projectFact(&content.writer, "Plan ID", stored.id, true);
    try projectFact(&content.writer, "Plan digest", stored.plan_sha256, true);
    try projectFact(&content.writer, "Action", stored.action_id, true);
    try projectFact(&content.writer, "Effect", stored.effect, false);
    try projectFact(&content.writer, "Confirmation", stored.confirmation, false);
    var seconds_buffer: [48]u8 = undefined;
    try projectFact(&content.writer, "Expected downtime", try std.fmt.bufPrint(&seconds_buffer, "{d} seconds", .{asInt(member(plan, "expected_downtime_seconds") orelse .{ .integer = 0 })}), false);
    try projectFact(&content.writer, "Rollback", strField(member(plan, "rollback") orelse .null, "mode"), false);
    try projectFact(&content.writer, "Source revision", stored.source_revision orelse "Filesystem snapshot", true);
    try projectFact(&content.writer, "Source fingerprint", stored.source_fingerprint orelse "Unavailable", true);
    var expiry_buffer: [48]u8 = undefined;
    try projectFact(&content.writer, "Expires at", try std.fmt.bufPrint(&expiry_buffer, "{d}", .{stored.expires_at}), true);
    try projectFact(&content.writer, "State", stored.state, false);
    try content.writer.writeAll("</dl><div><h3 class=\"section-heading\">Parameters</h3><pre class=\"log-output\">");
    try writeJsonAsEscapedText(ctx.gpa, &content.writer, member(plan, "parameters") orelse .null);
    try content.writer.writeAll("</pre></div><div><h3 class=\"section-heading\">Affected resources</h3><p>");
    try writeStringArray(&content.writer, arrayItems(member(plan, "affected_resources")));
    try content.writer.writeAll("</p></div><div><h3 class=\"section-heading\">Stages and preconditions</h3><ul>");
    for (arrayItems(member(plan, "preconditions"))) |condition| {
        try content.writer.writeAll("<li><strong>");
        try web_html.text(&content.writer, strField(condition, "status"));
        try content.writer.writeAll("</strong> — ");
        try web_html.text(&content.writer, strField(condition, "summary"));
        try content.writer.writeAll("</li>");
    }
    for (arrayItems(member(plan, "stages"))) |stage| {
        try content.writer.writeAll("<li>Stage: ");
        try web_html.text(&content.writer, strField(stage, "label"));
        try content.writer.writeAll(if (boolField(stage, "reversible")) " (reversible)</li>" else " (not reversible)</li>");
    }
    try content.writer.writeAll("</ul></div>");
    if (std.mem.eql(u8, stored.state, "ready")) try planRunForm(ctx, &content.writer, project, stored);
    try content.writer.writeAll("</div>");
    try replaceElementInner(ctx.gpa, main, "nob-plan-review-content", "div", content.written());
    try replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-plan-review\"", "class=\"panel\" id=\"nob-plan-review\"");
}

fn planRunForm(ctx: context.Context, out: *std.Io.Writer, project: db_store.NobProject, plan: db_store.NobPlan) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "project-run");
    var project_buffer: [32]u8 = undefined;
    try out.writeAll("<form class=\"stack confirm-form\" method=\"post\" action=\"/projects/action\"><h3 class=\"section-heading\">Approval</h3><p>Confirm only after reviewing the exact digest, effect, targets, downtime, rollback, parameters, and expiry above.</p>");
    try writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(out, "idempotency_key", key);
    try writeHiddenInput(out, "operation", "run");
    try writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id}));
    try writeHiddenInput(out, "action_id", plan.action_id);
    try writeHiddenInput(out, "plan_id", plan.id);
    if (plan.resource_id) |resource_id| {
        try writeHiddenInput(out, "resource_id", resource_id);
        const prefix_len = "resource:".len + resource_id.len + 1;
        try writeHiddenInput(out, "control_name", if (plan.action_id.len > prefix_len) plan.action_id[prefix_len..] else "");
    }
    if (std.mem.eql(u8, plan.confirmation, "review-plan")) {
        try out.writeAll("<label><input name=\"confirmation\" value=\"confirmed\" type=\"checkbox\" required> I reviewed this exact plan and approve its stated effects.</label>");
    } else if (std.mem.eql(u8, plan.confirmation, "type-project-id")) {
        try out.writeAll("<label>Type project ID to approve<input name=\"confirm_project_id\" required autocomplete=\"off\" placeholder=\"");
        try web_html.attribute(out, project.declared_id orelse "");
        try out.writeAll("\"></label>");
    }
    try out.writeAll("<button class=\"button button-primary\" type=\"submit\">Run reviewed plan</button></form>");
}

fn renderProjectRun(ctx: context.Context, project: db_store.NobProject, run_id: []const u8, main: *[]u8) !void {
    const run = (try app_nob_actions.getRun(context.nobActions(ctx), run_id)) orelse return;
    defer run.deinit(ctx.gpa);
    if (run.project_id != project.id) return;
    var events = try app_nob_actions.listRecentEvents(context.nobActions(ctx), run.id, 200);
    defer events.deinit(ctx.gpa);
    var artifacts = try app_nob_actions.listArtifacts(context.nobActions(ctx), run.id);
    defer artifacts.deinit(ctx.gpa);
    const log = app_nob_actions.readRunLog(context.nobActions(ctx), run.id, 64 * 1024) catch try ctx.gpa.dupe(u8, "Log is not available yet.");
    defer ctx.gpa.free(log);
    var content = std.Io.Writer.Allocating.init(ctx.gpa);
    defer content.deinit();
    try content.writer.writeAll("<div class=\"panel-header\"><div><h2 id=\"nob-run-detail-title\">Operation ");
    try web_html.text(&content.writer, run.id);
    try content.writer.writeAll("</h2><p>Retained state, events, artifacts, and a bounded log tail.</p></div></div><div class=\"panel-body stack\"><dl class=\"kv-list\">");
    try projectFact(&content.writer, "Action", run.action_id, true);
    try projectFact(&content.writer, "State", run.state, false);
    try projectFact(&content.writer, "Outcome", run.outcome orelse "Pending", false);
    try projectFact(&content.writer, "Summary", run.summary orelse "Pending", false);
    try projectFact(&content.writer, "Error", run.error_code orelse "None", true);
    var queued_buffer: [32]u8 = undefined;
    try projectFact(&content.writer, "Queued at", try std.fmt.bufPrint(&queued_buffer, "{d}", .{run.queued_at}), true);
    try content.writer.writeAll("</dl>");
    if (std.mem.eql(u8, run.state, "queued") or std.mem.eql(u8, run.state, "running")) {
        var fields = [_]FormField{.{ "run_id", run.id }};
        try projectSimpleForm(ctx, &content.writer, project.id, "cancel", "Cancel operation", "button-danger", &fields);
    }
    try content.writer.writeAll("<div><h3 class=\"section-heading\">Events</h3><ol class=\"event-list\">");
    if (events.items.len == 0) try content.writer.writeAll("<li class=\"muted\">No events retained yet.</li>");
    for (events.items) |event| {
        try content.writer.writeAll("<li><span class=\"mono\">");
        try content.writer.print("{d}", .{event.seq});
        try content.writer.writeAll("</span> <strong>");
        try web_html.text(&content.writer, event.event_type);
        try content.writer.writeAll("</strong> <span class=\"muted\">");
        try web_html.text(&content.writer, event.payload_json);
        try content.writer.writeAll("</span></li>");
    }
    try content.writer.writeAll("</ol></div><div><h3 class=\"section-heading\">Artifacts</h3><ul>");
    if (artifacts.items.len == 0) try content.writer.writeAll("<li class=\"muted\">No artifacts retained.</li>");
    for (artifacts.items) |artifact| {
        try content.writer.writeAll("<li><strong>");
        try web_html.text(&content.writer, artifact.artifact_id);
        try content.writer.writeAll("</strong> · ");
        try web_html.text(&content.writer, artifact.role);
        try content.writer.writeAll(" · <span class=\"mono\">");
        try web_html.text(&content.writer, artifact.sha256);
        try content.writer.writeAll("</span></li>");
    }
    try content.writer.writeAll("</ul></div><div><h3 class=\"section-heading\">Bounded log tail</h3><pre class=\"log-output\">");
    try web_html.text(&content.writer, log);
    try content.writer.writeAll("</pre></div></div>");
    try replaceElementInner(ctx.gpa, main, "nob-run-detail-content", "div", content.written());
    try replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-run-detail\"", "class=\"panel\" id=\"nob-run-detail\"");
}

fn writeStringArray(out: *std.Io.Writer, values: []const std.json.Value) !void {
    if (values.len == 0) {
        try out.writeAll("<span class=\"muted\">None</span>");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try out.writeAll(", ");
        try web_html.text(out, asString(value));
    }
}

fn writeJsonAsEscapedText(allocator: std.mem.Allocator, out: *std.Io.Writer, value: std.json.Value) !void {
    var json = std.Io.Writer.Allocating.init(allocator);
    defer json.deinit();
    try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &json.writer);
    try web_html.text(out, json.written());
}

const ProjectFeedback = struct { tone: []const u8, message: []const u8 };

fn projectFeedback(request: http.Request) ?ProjectFeedback {
    if (request.query("error")) |code| {
        if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The request failed its Origin or CSRF check. Reload and try again." };
        if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "The typed project confirmation did not match." };
        if (std.mem.eql(u8, code, "project_not_approved")) return .{ .tone = "warning", .message = "Approve the current manifest before continuing." };
        if (std.mem.eql(u8, code, "runner_not_ready")) return .{ .tone = "warning", .message = "Prepare the approved project runner before planning or running." };
        if (std.mem.eql(u8, code, "plan_no_longer_current")) return .{ .tone = "warning", .message = "The plan is no longer current. Review the changed manifest or source and create a new plan." };
        if (std.mem.eql(u8, code, "required_secret_unavailable")) return .{ .tone = "warning", .message = "A required logical secret is unbound or unavailable." };
        if (std.mem.eql(u8, code, "system_mutation_disabled")) return .{ .tone = "warning", .message = "The global system-mutation kill switch blocks this operation." };
        if (std.mem.eql(u8, code, "action_unavailable")) return .{ .tone = "warning", .message = "The prepared runner does not expose this action." };
        if (std.mem.eql(u8, code, "project_runner_failed")) return .{ .tone = "danger", .message = "The project runner failed. Review its retained detail and correct the project before retrying." };
        return .{ .tone = "danger", .message = "The project request was rejected. Review the current project state and try again." };
    }
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "scanned")) return .{ .tone = "success", .message = "Project discovery completed without executing project code." };
        if (std.mem.eql(u8, result, "trusted")) return .{ .tone = "success", .message = "The exact manifest digest is approved." };
        if (std.mem.eql(u8, result, "revoked")) return .{ .tone = "success", .message = "Project approval was revoked and ready plans were invalidated." };
        if (std.mem.eql(u8, result, "forgotten")) return .{ .tone = "success", .message = "Project executable state and secret bindings were removed; history and host resources remain." };
        if (std.mem.eql(u8, result, "prepared")) return .{ .tone = "success", .message = "The approved runner was prepared and independently observed." };
        if (std.mem.eql(u8, result, "observed")) return .{ .tone = "success", .message = "Project and resource observations were refreshed." };
        if (std.mem.eql(u8, result, "planned")) return .{ .tone = "success", .message = "The exact plan is ready for review." };
        if (std.mem.eql(u8, result, "queued")) return .{ .tone = "success", .message = "The reviewed plan was consumed and queued exactly once." };
        if (std.mem.eql(u8, result, "cancel_requested")) return .{ .tone = "success", .message = "Cancellation was requested and retained." };
        if (std.mem.eql(u8, result, "secret_bound")) return .{ .tone = "success", .message = "The logical secret source is bound and available. Its reference and value remain hidden." };
        if (std.mem.eql(u8, result, "secret_unbound")) return .{ .tone = "success", .message = "The logical secret was unbound; dependent actions are now blocked." };
    }
    return null;
}

fn discoveryLabel(state: db_store.NobDiscoveryState) []const u8 {
    return switch (state) {
        .candidate => "Manifest needed",
        .valid => "Ready",
        .invalid => "Invalid manifest",
        .conflict => "ID conflict",
        .missing => "Missing",
        .ignored => "Forgotten",
    };
}

fn trustLabel(state: db_store.NobTrustState) []const u8 {
    return switch (state) {
        .discovered => "Approval needed",
        .trusted => "Approved",
        .@"review-required" => "Changed — review",
        .revoked => "Revoked",
    };
}

fn runnerLabel(state: db_store.NobRunnerState) []const u8 {
    return switch (state) {
        .@"not-built" => "Not prepared",
        .building => "Preparing",
        .ready => "Ready",
        .failed => "Failed",
    };
}

fn injectRoutes(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var draft_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer draft_arena.deinit();
    const draft = parseRoutesDraft(draft_arena.allocator(), request);
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_caddy_desired.writeJson(context.caddy(ctx), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const routes = arrayItems(member(parsed.value, "routes"));
    const candidates = arrayItems(member(parsed.value, "adopt_candidates"));
    const ownership = member(parsed.value, "ownership") orelse .null;
    const observation = member(parsed.value, "observation") orelse .null;
    const capability = member(parsed.value, "capability") orelse .null;
    const diff = member(parsed.value, "diff") orelse .null;
    const diff_items = arrayItems(member(diff, "items"));

    try replaceEscapedElement(ctx.gpa, main, "routes-root", "dd", strField(ownership, "root"));
    try replaceEscapedElement(ctx.gpa, main, "routes-fragment", "dd", strField(ownership, "fragment"));
    var freshness = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness.deinit();
    try writeStatus(&freshness.writer, freshnessLabel(strField(parsed.value, "freshness")));
    try replaceElementInner(ctx.gpa, main, "routes-freshness", "dd", freshness.written());
    const observed_at = nullableString(member(observation, "observed_at"));
    try replaceEscapedElement(ctx.gpa, main, "routes-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt.deinit();
    try web_html.text(&attempt.writer, collectionStatusLabel(strField(observation, "status")));
    const attempted_at = nullableString(member(observation, "attempted_at"));
    if (attempted_at.len > 0) {
        try attempt.writer.writeAll(" · ");
        try web_html.text(&attempt.writer, attempted_at);
    }
    try replaceElementInner(ctx.gpa, main, "routes-attempt", "dd", attempt.written());
    const capability_ready = std.mem.eql(u8, strField(capability, "code"), "ready");
    try replaceEscapedElement(ctx.gpa, main, "caddy-apply-capability", "p", if (capability_ready) "Ready to manage routes." else strField(capability, "reason"));
    if (capability_ready) {
        try replaceExact(ctx.gpa, main, "id=\"caddy-apply-capability\" class=\"notice tone-warning\"", "id=\"caddy-apply-capability\" class=\"notice tone-success\"");
    }

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try formIdempotencyKey(ctx.io, &refresh_key_buffer, "routes-refresh");
    try replaceHiddenInput(ctx.gpa, main, "routes-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "routes-refresh-idempotency", "idempotency_key", refresh_key);

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (routes.len != 0) {
        for (routes) |route| {
            const host = strField(route, "host");
            const enabled = boolField(route, "enabled");
            const editable = boolField(route, "editable");
            const state = strField(route, "state");
            try rows.writer.writeAll("<tr data-route-host=\"");
            try web_html.attribute(&rows.writer, host);
            try rows.writer.writeAll("\"><td data-label=\"State\">");
            try writeBadge(&rows.writer, state);
            try rows.writer.writeAll("</td>");
            try cellText(&rows.writer, host, "mono breakable");
            try cellText(&rows.writer, strField(route, "upstream"), "mono breakable");
            try cellBadge(&rows.writer, strField(route, "ownership"));
            try cellText(&rows.writer, strField(route, "updated_at"), "muted");
            try rows.writer.writeAll("<td data-label=\"Actions\" class=\"cell-actions\"><div class=\"cluster\">");
            if (editable) {
                var toggle_key_buffer: [80]u8 = undefined;
                const toggle_key = try formIdempotencyKey(ctx.io, &toggle_key_buffer, "route-toggle");
                try rows.writer.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/routes/route\">");
                try writeHiddenInput(&rows.writer, "csrf_token", ctx.auth_csrf_token orelse "");
                try writeHiddenInput(&rows.writer, "idempotency_key", toggle_key);
                try writeHiddenInput(&rows.writer, "action", "toggle");
                try writeHiddenInput(&rows.writer, "host", host);
                try writeHiddenInput(&rows.writer, "enabled", if (enabled) "0" else "1");
                try rows.writer.writeAll("<button class=\"button button-small\" type=\"submit\">");
                try web_html.text(&rows.writer, if (enabled) "Disable" else "Enable");
                try rows.writer.writeAll("</button></form><a class=\"button button-small\" href=\"/routes.html?edit=");
                try writeUrlQueryComponent(&rows.writer, host);
                try rows.writer.writeAll("\">Edit</a><a class=\"button button-small button-danger\" href=\"/routes.html?confirm=delete&amp;host=");
                try writeUrlQueryComponent(&rows.writer, host);
                try rows.writer.writeAll("\">Remove</a>");
            } else if (std.mem.eql(u8, state, "pending_delete")) {
                try rows.writer.writeAll("<span class=\"muted\">Pending removal</span>");
            } else {
                try rows.writer.writeAll("<span class=\"muted\">Project-managed</span>");
            }
            try rows.writer.writeAll("</div></td></tr>");
        }
    }
    try replaceElementInner(ctx.gpa, main, "routes-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "routes-count", "span", routes.len, "route", "routes");
    if (routes.len != 0) {
        try replaceExact(ctx.gpa, main, "id=\"routes-empty\" class=\"panel-body route-empty-state\"", "id=\"routes-empty\" class=\"panel-body route-empty-state hidden\"");
        try replaceExact(ctx.gpa, main, "id=\"routes-table\" class=\"table-scroll hidden\"", "id=\"routes-table\" class=\"table-scroll\"");
    }

    var route_key_buffer: [80]u8 = undefined;
    const route_key = try formIdempotencyKey(ctx.io, &route_key_buffer, "route-save");
    try replaceHiddenInput(ctx.gpa, main, "route-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "route-idempotency", "idempotency_key", route_key);
    const edit_host = request.query("edit") orelse if (std.mem.eql(u8, request.query("action") orelse "", "update")) request.query("host") orelse "" else "";
    const edit_route = findJsonRoute(routes, edit_host);
    if (edit_route) |route| {
        try replaceEscapedElement(ctx.gpa, main, "route-form-title", "h2", "Edit route");
        try setInputValue(ctx.gpa, main, "route-action", "update");
        try setInputValue(ctx.gpa, main, "route-host", edit_host);
        try setInputValue(ctx.gpa, main, "route-upstream", if (draft) |value| if (std.mem.eql(u8, value.action, "update")) value.upstream else strField(route, "upstream") else strField(route, "upstream"));
        try replaceExact(ctx.gpa, main, "id=\"route-form-cancel\" class=\"button hidden\"", "id=\"route-form-cancel\" class=\"button\"");
    } else if (draft) |value| if (std.mem.eql(u8, value.action, "create")) {
        try setInputValue(ctx.gpa, main, "route-host", value.host);
        try setInputValue(ctx.gpa, main, "route-upstream", value.upstream);
    };
    if (boolField(capability, "write")) {
        try replaceExact(ctx.gpa, main, "<button id=\"add-route\" class=\"button-primary\" type=\"submit\" disabled>Save route</button>", "<button id=\"add-route\" class=\"button-primary\" type=\"submit\">Save route</button>");
    }

    var adoption = std.Io.Writer.Allocating.init(ctx.gpa);
    defer adoption.deinit();
    if (candidates.len != 0) {
        for (candidates) |candidate| {
            var adopt_key_buffer: [80]u8 = undefined;
            const adopt_key = try formIdempotencyKey(ctx.io, &adopt_key_buffer, "route-adopt");
            try adoption.writer.writeAll("<form class=\"toolbar\" method=\"post\" action=\"/routes/adopt\"><span><code>");
            try web_html.text(&adoption.writer, strField(candidate, "host"));
            try adoption.writer.writeAll("</code> → <code>");
            try web_html.text(&adoption.writer, strField(candidate, "upstream"));
            try adoption.writer.writeAll("</code></span>");
            try writeHiddenInput(&adoption.writer, "csrf_token", ctx.auth_csrf_token orelse "");
            try writeHiddenInput(&adoption.writer, "idempotency_key", adopt_key);
            try writeHiddenInput(&adoption.writer, "host", strField(candidate, "host"));
            try adoption.writer.writeAll("<button class=\"button-primary\" type=\"submit\">Adopt exact route</button></form>");
        }
    }
    try replaceElementInner(ctx.gpa, main, "adopt-routes", "div", adoption.written());
    if (candidates.len != 0) {
        try replaceExact(ctx.gpa, main, "id=\"routes-adoption-panel\" class=\"panel hidden\"", "id=\"routes-adoption-panel\" class=\"panel\"");
    }

    var diff_rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer diff_rows.deinit();
    if (diff_items.len != 0) {
        for (diff_items) |item| {
            try diff_rows.writer.writeAll("<tr><td data-label=\"Change\">");
            try writeBadge(&diff_rows.writer, strField(item, "state"));
            try diff_rows.writer.writeAll("</td>");
            try dashboardCellText(&diff_rows.writer, "Host", strField(item, "host"), "mono breakable", "—");
            try dashboardCellText(&diff_rows.writer, "Desired", nullableString(member(item, "desired_upstream")), "mono breakable", "—");
            try dashboardCellText(&diff_rows.writer, "Observed", nullableString(member(item, "observed_upstream")), "mono breakable", "—");
            try dashboardCellText(&diff_rows.writer, "Ownership", strField(item, "ownership"), "", "—");
            try diff_rows.writer.writeAll("</tr>");
        }
    }
    try replaceElementInner(ctx.gpa, main, "routes-diff-body", "tbody", diff_rows.written());
    const pending_changes = intField(diff, "additions") + intField(diff, "changes") + intField(diff, "removals");
    const has_pending_changes = pending_changes != 0;
    if (has_pending_changes) {
        try replaceExact(ctx.gpa, main, "id=\"routes-preview-panel\" class=\"panel hidden\"", "id=\"routes-preview-panel\" class=\"panel\"");
    }
    var diff_summary_buffer: [192]u8 = undefined;
    const diff_summary = try std.fmt.bufPrint(&diff_summary_buffer, "{d} additions · {d} changes · {d} removals · {d} unchanged · {d} requiring adoption", .{
        intField(diff, "additions"), intField(diff, "changes"), intField(diff, "removals"), intField(diff, "unchanged"), intField(diff, "unadopted"),
    });
    try replaceEscapedElement(ctx.gpa, main, "routes-diff-summary", "p", diff_summary);
    const rendered = try app_caddy_desired.render(context.caddy(ctx), ctx.gpa);
    defer ctx.gpa.free(rendered);
    try replaceEscapedElement(ctx.gpa, main, "preview-output", "pre", rendered);
    if (!boolField(capability, "apply")) {
        try replaceExact(ctx.gpa, main, "<a id=\"apply-btn\" class=\"button button-primary\" href=\"/routes.html?confirm=apply\" aria-describedby=\"caddy-apply-capability\">Review Apply</a>", "<span id=\"apply-btn\" class=\"button button-primary\" aria-disabled=\"true\" aria-describedby=\"caddy-apply-capability\">Review Apply</span>");
    }

    try injectRouteDeleteConfirmation(ctx, request, routes, draft, main);
    try injectRouteApplyConfirmation(ctx, request, draft, capability, has_pending_changes, main);
    if (routesFeedback(request)) |feedback| {
        try replaceEscapedElement(ctx.gpa, main, "routes-feedback", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"routes-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"routes-feedback\" class=\"notice hidden\"", replacement);
    }
}

const RoutesDraft = struct { action: []const u8, host: []const u8, upstream: []const u8, confirmation: []const u8 };

fn parseRoutesDraft(arena: std.mem.Allocator, request: http.Request) ?RoutesDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    return .{
        .action = fields.get("action") catch "",
        .host = fields.get("host") catch "",
        .upstream = fields.get("upstream") catch "",
        .confirmation = fields.get("confirmation") catch "",
    };
}

fn findJsonRoute(routes: []const std.json.Value, host: []const u8) ?std.json.Value {
    for (routes) |route| if (std.mem.eql(u8, strField(route, "host"), host)) return route;
    return null;
}

fn injectRouteDeleteConfirmation(ctx: context.Context, request: http.Request, routes: []const std.json.Value, draft: ?RoutesDraft, main: *[]u8) !void {
    if (!std.mem.eql(u8, request.query("confirm") orelse request.query("action") orelse "", "delete")) return;
    const host = request.query("host") orelse return;
    const route = findJsonRoute(routes, host) orelse return;
    if (!boolField(route, "editable")) return;
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "route-delete");
    try replaceHiddenInput(ctx.gpa, main, "route-delete-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "route-delete-idempotency", "idempotency_key", key);
    try replaceHiddenInput(ctx.gpa, main, "route-delete-host", "host", host);
    try replaceEscapedElement(ctx.gpa, main, "route-confirmation-target", "code", host);
    if (draft) |value| if (std.mem.eql(u8, value.action, "delete") and std.mem.eql(u8, value.host, host)) try setInputValue(ctx.gpa, main, "route-delete-confirmation", value.confirmation);
    try replaceExact(ctx.gpa, main, "id=\"route-confirmation-panel\" class=\"panel hidden\"", "id=\"route-confirmation-panel\" class=\"panel\"");
}

fn injectRouteApplyConfirmation(ctx: context.Context, request: http.Request, draft: ?RoutesDraft, capability: std.json.Value, has_pending_changes: bool, main: *[]u8) !void {
    const requested = std.mem.eql(u8, request.query("confirm") orelse "", "apply") or
        (std.mem.eql(u8, request.query("error") orelse "", "confirmation") and request.query("host") == null);
    if (!requested or !has_pending_changes or !boolField(capability, "apply")) return;
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "routes-apply");
    try replaceHiddenInput(ctx.gpa, main, "routes-apply-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "routes-apply-idempotency", "idempotency_key", key);
    if (draft) |value| if (value.action.len == 0) try setInputValue(ctx.gpa, main, "routes-apply-confirmation", value.confirmation);
    try replaceExact(ctx.gpa, main, "id=\"apply-confirmation-panel\" class=\"panel hidden\"", "id=\"apply-confirmation-panel\" class=\"panel\"");
}

const RoutesFeedback = struct { tone: []const u8, message: []const u8 };

fn routesFeedback(request: http.Request) ?RoutesFeedback {
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "refresh")) return .{ .tone = "success", .message = "The owned fragment observation was refreshed." };
        if (std.mem.eql(u8, result, "create")) return .{ .tone = "success", .message = "The route was added to desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "update")) return .{ .tone = "success", .message = "The route change is pending in desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "toggle")) return .{ .tone = "success", .message = "The route state changed in desired state. Review the diff before Apply." };
        if (std.mem.eql(u8, result, "delete")) return .{ .tone = "success", .message = "The route is marked for removal. It remains active until Apply succeeds." };
        if (std.mem.eql(u8, result, "adopt")) return .{ .tone = "success", .message = "The exact observed route is now part of Cloudio desired state." };
        if (std.mem.eql(u8, result, "apply")) return .{ .tone = "success", .message = "The owned fragment was validated, atomically replaced, reloaded, and verified." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The Routes request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The Routes form expired or its key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "The typed confirmation did not exactly match the required value." };
    if (std.mem.eql(u8, code, "invalid_caddy_route")) return .{ .tone = "danger", .message = "Use one lowercase hostname and a loopback upstream such as 127.0.0.1:9000." };
    if (std.mem.eql(u8, code, "caddy_adoption_required")) return .{ .tone = "warning", .message = "That observed route must be adopted explicitly before it can be changed." };
    if (std.mem.eql(u8, code, "caddy_observation_changed")) return .{ .tone = "warning", .message = "The fragment changed after observation. Refresh before retrying." };
    if (std.mem.eql(u8, code, "caddy_validation_failed")) return .{ .tone = "danger", .message = "Caddy rejected the candidate. The previous fragment remains active." };
    if (std.mem.eql(u8, code, "caddy_fragment_write_failed")) return .{ .tone = "danger", .message = "Cloudio could not atomically replace its fragment. The previous fragment remains active." };
    if (std.mem.eql(u8, code, "caddy_reload_failed")) return .{ .tone = "danger", .message = "Caddy reload failed. Cloudio restored and reloaded the previous fragment." };
    if (std.mem.eql(u8, code, "caddy_verification_failed")) return .{ .tone = "danger", .message = "Runtime verification failed. Cloudio restored and reloaded the previous fragment." };
    if (std.mem.eql(u8, code, "caddy_recovery_failed")) return .{ .tone = "danger", .message = "Automatic Caddy recovery failed. Follow the Routes recovery runbook immediately." };
    if (std.mem.eql(u8, code, "caddy_route_not_observed") or std.mem.eql(u8, code, "caddy_route_not_owned")) return .{ .tone = "danger", .message = "That exact route is not owned by the Routes workflow." };
    return .{ .tone = "warning", .message = "Routes changes are unavailable until the owned-fragment capability is current." };
}

fn injectDns(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var draft_arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer draft_arena.deinit();
    const draft = parseDnsDraft(draft_arena.allocator(), request);
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_dns.writeJson(context.dns(ctx), request.query("domain"), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const domain = strField(parsed.value, "selected_domain");
    const zones = arrayItems(member(parsed.value, "zones"));
    const records = arrayItems(member(parsed.value, "records"));
    const collection = member(parsed.value, "collection") orelse .null;
    const capability = member(parsed.value, "capability") orelse .null;

    var zone_options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer zone_options.deinit();
    if (zones.len == 0) {
        try zone_options.writer.writeAll("<option value=\"\" selected>No configured zones</option>");
    } else for (zones) |zone| {
        const configured = strField(zone, "domain");
        try zone_options.writer.writeAll("<option value=\"");
        try web_html.attribute(&zone_options.writer, configured);
        try zone_options.writer.writeByte('"');
        if (std.mem.eql(u8, configured, domain)) try zone_options.writer.writeAll(" selected");
        try zone_options.writer.writeByte('>');
        try web_html.text(&zone_options.writer, configured);
        if (nullableString(member(zone, "zone_id")).len == 0) try zone_options.writer.writeAll(" (not observed)");
        try zone_options.writer.writeAll("</option>");
    }
    try replaceElementInner(ctx.gpa, main, "domain", "select", zone_options.written());

    var source_note = std.Io.Writer.Allocating.init(ctx.gpa);
    defer source_note.deinit();
    if (domain.len == 0) {
        try source_note.writer.writeAll("No configured zone selected.");
    } else {
        try source_note.writer.writeAll("Stored Cloudflare observation for ");
        try web_html.text(&source_note.writer, domain);
        try source_note.writer.writeByte('.');
    }
    try replaceElementInner(ctx.gpa, main, "dns-source-note", "p", source_note.written());
    var freshness_status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness_status.deinit();
    try writeStatus(&freshness_status.writer, freshnessLabel(strField(parsed.value, "freshness")));
    try replaceElementInner(ctx.gpa, main, "dns-freshness", "span", freshness_status.written());
    const observed_at = nullableString(member(parsed.value, "observed_at"));
    try replaceEscapedElement(ctx.gpa, main, "dns-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt_text = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt_text.deinit();
    try web_html.text(&attempt_text.writer, collectionStatusLabel(strField(collection, "status")));
    const attempted_at = nullableString(member(collection, "attempted_at"));
    if (attempted_at.len > 0) {
        try attempt_text.writer.writeAll(" · ");
        try web_html.text(&attempt_text.writer, attempted_at);
    }
    try replaceElementInner(ctx.gpa, main, "dns-attempt", "dd", attempt_text.written());
    try replaceEscapedElement(ctx.gpa, main, "dns-capability", "p", strField(capability, "reason"));

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try formIdempotencyKey(ctx.io, &refresh_key_buffer, "dns-refresh");
    try replaceHiddenInput(ctx.gpa, main, "dns-refresh-domain", "domain", domain);
    try replaceHiddenInput(ctx.gpa, main, "dns-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "dns-refresh-idempotency", "idempotency_key", refresh_key);
    if (boolField(capability, "refresh")) {
        try replaceExact(ctx.gpa, main, "<button class=\"button-primary\" type=\"submit\" disabled>Refresh zone</button>", "<button class=\"button-primary\" type=\"submit\">Refresh zone</button>");
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (records.len == 0) {
        try emptyRow(&rows.writer, 6, if (domain.len == 0) "Choose a configured zone." else "No DNS records observed for this zone.");
    } else for (records) |record| {
        const record_id = strField(record, "id");
        const actions = member(record, "actions") orelse .null;
        try rows.writer.writeAll("<tr data-dns-record=\"");
        try web_html.attribute(&rows.writer, record_id);
        try rows.writer.writeAll("\">");
        try rows.writer.writeAll("<td data-label=\"Type\">");
        try writeBadge(&rows.writer, strField(record, "type"));
        try rows.writer.writeAll("</td>");
        try dashboardCellText(&rows.writer, "Name", strField(record, "name"), "mono breakable", "—");
        try dashboardCellText(&rows.writer, "Content", strField(record, "content"), "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"TTL\" class=\"mono\">");
        try rows.writer.print("{d}", .{intField(record, "ttl")});
        try rows.writer.writeAll("</td><td data-label=\"Proxy\">");
        try writeBadge(&rows.writer, if (boolField(record, "proxied")) "Proxied" else "DNS only");
        try rows.writer.writeAll("</td><td data-label=\"Actions\" class=\"cell-actions\"><div class=\"table-actions\">");
        if (boolField(actions, "edit")) try writeDnsRecordLink(&rows.writer, domain, "edit", record_id, "Edit", false);
        if (boolField(actions, "toggle")) {
            var toggle_key_buffer: [80]u8 = undefined;
            const toggle_key = try formIdempotencyKey(ctx.io, &toggle_key_buffer, "dns-toggle");
            try writeDnsInlineActionForm(&rows.writer, ctx.auth_csrf_token orelse "", toggle_key, domain, "toggle", record_id, if (boolField(record, "proxied")) "Set DNS only" else "Enable proxy", false);
        }
        if (boolField(actions, "delete")) try writeDnsRecordLink(&rows.writer, domain, "confirm", record_id, "Delete", true);
        if (!boolField(actions, "edit") and !boolField(actions, "toggle") and !boolField(actions, "delete")) try rows.writer.writeAll("<span class=\"muted\">Read-only</span>");
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "records-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "record-count", "span", records.len, "record", "records");

    var create_key_buffer: [80]u8 = undefined;
    const create_key = try formIdempotencyKey(ctx.io, &create_key_buffer, "dns-create");
    try replaceHiddenInput(ctx.gpa, main, "dns-create-domain", "domain", domain);
    try replaceHiddenInput(ctx.gpa, main, "dns-create-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "dns-create-idempotency", "idempotency_key", create_key);
    if (boolField(capability, "write")) try enableDnsCreateForm(ctx.gpa, main);
    if (draft) |value| if (std.mem.eql(u8, value.action, "create")) try applyDnsCreateDraft(ctx.gpa, main, value);

    try injectDnsEdit(ctx, request, domain, records, draft, main);
    try injectDnsDelete(ctx, request, domain, records, draft, main);
    if (dnsFeedback(request)) |feedback| {
        try replaceEscapedElement(ctx.gpa, main, "dns-notice", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"dns-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"dns-notice\" class=\"notice hidden\"", replacement);
    }
}

const DnsFeedback = struct { tone: []const u8, message: []const u8 };

fn dnsFeedback(request: http.Request) ?DnsFeedback {
    if (request.query("refreshed")) |value| if (std.mem.eql(u8, value, "1")) return .{ .tone = "success", .message = "The zone observation was refreshed from Cloudflare." };
    if (request.query("result")) |value| {
        if (std.mem.eql(u8, value, "create")) return .{ .tone = "success", .message = "The record was created and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "update")) return .{ .tone = "success", .message = "The record was updated and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "toggle")) return .{ .tone = "success", .message = "The proxy setting was changed and confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "delete")) return .{ .tone = "success", .message = "The record deletion was confirmed by a targeted reread." };
        if (std.mem.eql(u8, value, "accepted_unconfirmed")) return .{ .tone = "warning", .message = "Cloudflare accepted the change, but the confirmation read failed. Retained records are read-only until Refresh succeeds." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The DNS request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The DNS form expired or its key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "invalid_dns_request")) return .{ .tone = "danger", .message = "The record input is invalid. Check its type, name, content, TTL, and proxy setting." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "The confirmation did not exactly match the observed record name." };
    if (std.mem.eql(u8, code, "dns_zone_not_observed")) return .{ .tone = "warning", .message = "That configured zone has not been observed. Refresh it before changing records." };
    if (std.mem.eql(u8, code, "dns_record_not_observed")) return .{ .tone = "danger", .message = "That record is not part of the current zone observation." };
    if (std.mem.eql(u8, code, "dns_write_unavailable")) return .{ .tone = "warning", .message = "Record changes are unavailable until this exact zone has a current successful refresh." };
    if (std.mem.eql(u8, code, "dns_provider_rejected")) return .{ .tone = "danger", .message = "Cloudflare rejected the request. Existing observed records were retained." };
    if (std.mem.eql(u8, code, "dns_provider_unavailable")) return .{ .tone = "danger", .message = "Cloudflare could not be reached. Existing observed records were retained." };
    return .{ .tone = "danger", .message = "The DNS request could not be completed." };
}

fn injectBrowser(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_browser_run.writeJson(context.browserRun(ctx), request.query("run"), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const capability = member(parsed.value, "capability") orelse .null;
    const accounts = arrayItems(member(parsed.value, "accounts"));
    const allowed_hosts = arrayItems(member(parsed.value, "allowed_hosts"));
    const recent = arrayItems(member(parsed.value, "recent"));

    var status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer status.deinit();
    try writeStatus(&status.writer, if (boolField(capability, "available")) "Available" else "Unavailable");
    try replaceElementInner(ctx.gpa, main, "browser-capability-status", "span", status.written());
    try replaceEscapedElement(ctx.gpa, main, "browser-token-status", "dd", if (boolField(capability, "token")) "Configured · permission checked on run" else "API token required");
    try replaceEscapedElement(ctx.gpa, main, "browser-capability-reason", "p", strField(capability, "reason"));

    var destinations = std.Io.Writer.Allocating.init(ctx.gpa);
    defer destinations.deinit();
    if (allowed_hosts.len == 0) {
        try destinations.writer.writeAll("None configured");
    } else for (allowed_hosts, 0..) |entry, index| {
        if (index != 0) try destinations.writer.writeAll(", ");
        try web_html.text(&destinations.writer, asString(entry));
    }
    try replaceElementInner(ctx.gpa, main, "browser-destinations", "dd", destinations.written());
    var retention_buffer: [64]u8 = undefined;
    const retention_hours = intField(parsed.value, "retention_hours");
    const retention = try std.fmt.bufPrint(&retention_buffer, "{d} {s}", .{ retention_hours, if (retention_hours == 1) "hour" else "hours" });
    try replaceEscapedElement(ctx.gpa, main, "browser-retention", "dd", retention);

    var account_options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer account_options.deinit();
    if (accounts.len == 0) {
        try account_options.writer.writeAll("<option value=\"\" selected>No observed accounts</option>");
    } else for (accounts, 0..) |account, index| {
        try account_options.writer.writeAll("<option value=\"");
        try web_html.attribute(&account_options.writer, strField(account, "id"));
        try account_options.writer.writeByte('"');
        if (index == 0) try account_options.writer.writeAll(" selected");
        try account_options.writer.writeByte('>');
        const name = strField(account, "name");
        try web_html.text(&account_options.writer, if (name.len > 0) name else strField(account, "id"));
        if (strField(account, "status").len > 0) {
            try account_options.writer.writeAll(" · ");
            try web_html.text(&account_options.writer, strField(account, "status"));
        }
        try account_options.writer.writeAll("</option>");
    }
    try replaceElementInner(ctx.gpa, main, "browser-account", "select", account_options.written());
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "browser-run");
    try replaceHiddenInput(ctx.gpa, main, "browser-run-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "browser-run-idempotency", "idempotency_key", key);
    if (boolField(capability, "available")) {
        const replacements = [_][2][]const u8{
            .{ "<select id=\"browser-account\" name=\"account_id\" required disabled>", "<select id=\"browser-account\" name=\"account_id\" required>" },
            .{ "<input id=\"browser-url\" name=\"url\" type=\"url\" inputmode=\"url\" placeholder=\"https://example.com/page\" maxlength=\"4096\" autocomplete=\"off\" required disabled>", "<input id=\"browser-url\" name=\"url\" type=\"url\" inputmode=\"url\" placeholder=\"https://example.com/page\" maxlength=\"4096\" autocomplete=\"off\" required>" },
            .{ "<button id=\"browser-content-submit\" class=\"button-primary\" type=\"submit\" name=\"action\" value=\"content\" disabled>", "<button id=\"browser-content-submit\" class=\"button-primary\" type=\"submit\" name=\"action\" value=\"content\">" },
            .{ "<button id=\"browser-screenshot-submit\" type=\"submit\" name=\"action\" value=\"screenshot\" disabled>", "<button id=\"browser-screenshot-submit\" type=\"submit\" name=\"action\" value=\"screenshot\">" },
        };
        for (replacements) |replacement| try replaceExact(ctx.gpa, main, replacement[0], replacement[1]);
    }

    if (browserFeedback(request)) |feedback| {
        try replaceEscapedElement(ctx.gpa, main, "browser-notice", "div", feedback.message);
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"browser-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"browser-notice\" class=\"notice hidden\"", replacement);
    }

    if (member(parsed.value, "selected")) |selected| {
        if (selected == .object) try injectBrowserResult(ctx, selected, main);
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (recent.len == 0) {
        try emptyRow(&rows.writer, 6, "No Browser Run results yet.");
    } else for (recent) |run_value| {
        const id = strField(run_value, "id");
        try rows.writer.writeAll("<tr><td data-label=\"Started\" class=\"mono cell-nowrap\">");
        try writeEpoch(&rows.writer, intField(run_value, "created_at"));
        try rows.writer.writeAll("</td><td data-label=\"Action\">");
        try writeBadge(&rows.writer, browserActionLabel(strField(run_value, "action")));
        try rows.writer.writeAll("</td>");
        try dashboardCellText(&rows.writer, "Target", strField(run_value, "target_host"), "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"Result\"><a href=\"/browser.html?run=");
        try writeUrlQueryComponent(&rows.writer, id);
        try rows.writer.writeAll("\">");
        try writeStatus(&rows.writer, strField(run_value, "state"));
        try rows.writer.writeAll("</a></td><td data-label=\"Usage\" class=\"mono\">");
        if (intField(run_value, "browser_ms_used") > 0) try rows.writer.print("{d} ms", .{intField(run_value, "browser_ms_used")}) else try rows.writer.writeAll("—");
        try rows.writer.writeAll("</td><td data-label=\"Artifact\">");
        if (boolField(run_value, "artifact") and !boolField(run_value, "expired")) {
            try rows.writer.writeAll("<a href=\"/browser/artifact?id=");
            try writeUrlQueryComponent(&rows.writer, id);
            try rows.writer.writeAll("&amp;download=1\">Download</a>");
        } else if (boolField(run_value, "expired")) {
            try rows.writer.writeAll("<span class=\"muted\">Expired</span>");
        } else {
            try rows.writer.writeAll("<span class=\"muted\">—</span>");
        }
        try rows.writer.writeAll("</td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "browser-runs-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "browser-run-count", "span", recent.len, "run", "runs");
}

fn injectBrowserResult(ctx: context.Context, run_value: std.json.Value, main: *[]u8) !void {
    try replaceExact(ctx.gpa, main, "id=\"browser-result-panel\" class=\"panel hidden\"", "id=\"browser-result-panel\" class=\"panel\"");
    const state = strField(run_value, "state");
    const summary = if (strField(run_value, "error_summary").len > 0)
        strField(run_value, "error_summary")
    else if (strField(run_value, "title").len > 0)
        strField(run_value, "title")
    else
        "The Browser Run result was persisted by Cloudio.";
    try replaceEscapedElement(ctx.gpa, main, "browser-result-summary", "p", summary);
    var status = std.Io.Writer.Allocating.init(ctx.gpa);
    defer status.deinit();
    try writeStatus(&status.writer, state);
    try replaceElementInner(ctx.gpa, main, "browser-result-status", "span", status.written());
    try replaceEscapedElement(ctx.gpa, main, "browser-result-target", "dd", strField(run_value, "target_url"));
    try replaceEscapedElement(ctx.gpa, main, "browser-result-action", "dd", browserActionLabel(strField(run_value, "action")));
    var number_buffer: [64]u8 = undefined;
    const origin = if (intField(run_value, "origin_status") > 0) try std.fmt.bufPrint(&number_buffer, "HTTP {d}", .{intField(run_value, "origin_status")}) else "—";
    try replaceEscapedElement(ctx.gpa, main, "browser-result-origin", "dd", origin);
    var size_buffer: [64]u8 = undefined;
    const size = if (intField(run_value, "size_bytes") > 0) try formatBytes(&size_buffer, intField(run_value, "size_bytes")) else "—";
    try replaceEscapedElement(ctx.gpa, main, "browser-result-size", "dd", size);
    var usage_buffer: [64]u8 = undefined;
    const usage = if (intField(run_value, "browser_ms_used") > 0) try std.fmt.bufPrint(&usage_buffer, "{d} ms", .{intField(run_value, "browser_ms_used")}) else "Not reported";
    try replaceEscapedElement(ctx.gpa, main, "browser-result-usage", "dd", usage);
    try replaceEscapedElement(ctx.gpa, main, "browser-result-ray", "dd", if (strField(run_value, "cf_ray").len > 0) strField(run_value, "cf_ray") else "Not reported");
    try replaceEscapedElement(ctx.gpa, main, "browser-result-sha", "dd", if (strField(run_value, "artifact_sha256").len > 0) strField(run_value, "artifact_sha256") else "—");
    var expiry = std.Io.Writer.Allocating.init(ctx.gpa);
    defer expiry.deinit();
    try writeEpoch(&expiry.writer, intField(run_value, "expires_at"));
    try replaceElementInner(ctx.gpa, main, "browser-result-expiry", "dd", expiry.written());

    var output = std.Io.Writer.Allocating.init(ctx.gpa);
    defer output.deinit();
    const id = strField(run_value, "id");
    if (std.mem.eql(u8, state, "succeeded") and boolField(run_value, "artifact") and !boolField(run_value, "expired")) {
        if (std.mem.eql(u8, strField(run_value, "action"), "screenshot")) {
            try output.writer.writeAll("<figure class=\"browser-preview\"><img src=\"/browser/artifact?id=");
            try writeUrlQueryComponent(&output.writer, id);
            try output.writer.writeAll("\" alt=\"Screenshot captured by Kitesurf\"><figcaption><a href=\"/browser/artifact?id=");
            try writeUrlQueryComponent(&output.writer, id);
            try output.writer.writeAll("&amp;download=1\">Download PNG</a></figcaption></figure>");
        } else {
            try output.writer.writeAll("<div class=\"cluster\"><a class=\"button\" href=\"/browser/artifact?id=");
            try writeUrlQueryComponent(&output.writer, id);
            try output.writer.writeAll("&amp;download=1\">Download rendered HTML</a></div><pre class=\"log-viewer browser-html-preview\">");
            try web_html.text(&output.writer, strField(run_value, "preview"));
            try output.writer.writeAll("</pre>");
        }
    } else if (strField(run_value, "error_summary").len > 0) {
        try output.writer.writeAll("<div class=\"notice tone-danger\">");
        try web_html.text(&output.writer, strField(run_value, "error_summary"));
        if (intField(run_value, "retry_after_seconds") > 0) {
            try output.writer.print(" Retry after {d} seconds.", .{intField(run_value, "retry_after_seconds")});
        }
        try output.writer.writeAll("</div>");
    }
    try replaceElementInner(ctx.gpa, main, "browser-result-output", "div", output.written());
}

const BrowserFeedback = struct { tone: []const u8, message: []const u8 };

fn browserFeedback(request: http.Request) ?BrowserFeedback {
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The Browser Run request failed its Origin or CSRF check. Reload and try again." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The Browser Run form expired or its key was reused. Reload and try again." };
    if (std.mem.eql(u8, code, "invalid_request")) return .{ .tone = "danger", .message = "Choose an observed account, an allowed public URL, and one supported output." };
    if (std.mem.eql(u8, code, "token_required")) return .{ .tone = "warning", .message = "Browser Run requires a Cloudflare API token with Browser Rendering - Edit." };
    if (std.mem.eql(u8, code, "account_not_observed")) return .{ .tone = "warning", .message = "That Cloudflare account is not part of the current observation. Refresh Cloudflare first." };
    if (std.mem.eql(u8, code, "destination_denied")) return .{ .tone = "danger", .message = "That destination is outside the configured Browser Run host policy." };
    if (std.mem.eql(u8, code, "busy")) return .{ .tone = "warning", .message = "Another Browser Run is active. Wait for it to finish before starting another." };
    return .{ .tone = "danger", .message = "The Browser Run request could not be completed." };
}

fn browserActionLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "content")) return "Rendered HTML";
    if (std.mem.eql(u8, value, "screenshot")) return "Screenshot";
    return "Unknown";
}

fn formatBytes(buffer: *[64]u8, value: i64) ![]const u8 {
    if (value >= 1024 * 1024) return try std.fmt.bufPrint(buffer, "{d:.1} MiB", .{@as(f64, @floatFromInt(value)) / (1024 * 1024)});
    if (value >= 1024) return try std.fmt.bufPrint(buffer, "{d:.1} KiB", .{@as(f64, @floatFromInt(value)) / 1024});
    return try std.fmt.bufPrint(buffer, "{d} bytes", .{value});
}

fn writeEpoch(out: *std.Io.Writer, value: i64) !void {
    if (value <= 0) {
        try out.writeAll("—");
        return;
    }
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(value) };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    try out.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2} UTC", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
    });
}

fn enableDnsCreateForm(gpa: std.mem.Allocator, main: *[]u8) !void {
    const replacements = [_][2][]const u8{
        .{ "<select id=\"record-type\" name=\"type\" disabled>", "<select id=\"record-type\" name=\"type\">" },
        .{ "<input id=\"record-name\" name=\"name\" type=\"text\" placeholder=\"www or @\" required autocomplete=\"off\" disabled>", "<input id=\"record-name\" name=\"name\" type=\"text\" placeholder=\"www or @\" required autocomplete=\"off\">" },
        .{ "<input id=\"record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\" disabled>", "<input id=\"record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\">" },
        .{ "<input id=\"record-ttl\" name=\"ttl\" type=\"number\" value=\"1\" min=\"1\" max=\"86400\" required disabled>", "<input id=\"record-ttl\" name=\"ttl\" type=\"number\" value=\"1\" min=\"1\" max=\"86400\" required>" },
        .{ "<input id=\"record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\" disabled>", "<input id=\"record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\">" },
        .{ "<button id=\"add-record\" class=\"button-primary\" type=\"submit\" disabled>Add record</button>", "<button id=\"add-record\" class=\"button-primary\" type=\"submit\">Add record</button>" },
    };
    for (replacements) |item| try replaceExact(gpa, main, item[0], item[1]);
}

const DnsDraft = struct {
    action: []const u8,
    record_id: []const u8,
    record_type: []const u8,
    name: []const u8,
    content: []const u8,
    ttl: []const u8,
    proxied: bool,
    confirmation: []const u8,
};

fn parseDnsDraft(arena: std.mem.Allocator, request: http.Request) ?DnsDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    const action = fields.get("action") catch return null;
    return .{
        .action = action,
        .record_id = fields.get("record_id") catch "",
        .record_type = fields.get("type") catch "A",
        .name = fields.get("name") catch "",
        .content = fields.get("content") catch "",
        .ttl = fields.get("ttl") catch "1",
        .proxied = if (fields.get("proxied")) |value| std.mem.eql(u8, value, "1") else |_| false,
        .confirmation = fields.get("confirmation") catch "",
    };
}

fn applyDnsCreateDraft(gpa: std.mem.Allocator, main: *[]u8, draft: DnsDraft) !void {
    if (isSupportedDnsType(draft.record_type)) try selectOption(gpa, main, "record-type", "A", draft.record_type);
    try setInputValue(gpa, main, "record-name", draft.name);
    try setInputValue(gpa, main, "record-content", draft.content);
    try setInputValue(gpa, main, "record-ttl", draft.ttl);
    try setInputChecked(gpa, main, "record-proxied", draft.proxied);
}

fn isSupportedDnsType(value: []const u8) bool {
    for ([_][]const u8{ "A", "AAAA", "CNAME", "TXT" }) |record_type| {
        if (std.mem.eql(u8, value, record_type)) return true;
    }
    return false;
}

fn writeDnsRecordLink(out: *std.Io.Writer, domain: []const u8, mode: []const u8, record_id: []const u8, label: []const u8, danger: bool) !void {
    try out.writeAll("<a class=\"button button-small");
    if (danger) try out.writeAll(" button-danger");
    try out.writeAll("\" href=\"/dns.html?domain=");
    try writeUrlQueryComponent(out, domain);
    try out.writeByte('&');
    try web_html.urlAttribute(out, mode);
    try out.writeByte('=');
    if (std.mem.eql(u8, mode, "confirm")) try out.writeAll("delete&record=");
    try writeUrlQueryComponent(out, record_id);
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</a>");
}

fn writeDnsInlineActionForm(out: *std.Io.Writer, csrf: []const u8, key: []const u8, domain: []const u8, action: []const u8, record_id: []const u8, label: []const u8, danger: bool) !void {
    try out.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/dns/record\">");
    try writeHiddenInput(out, "csrf_token", csrf);
    try writeHiddenInput(out, "idempotency_key", key);
    try writeHiddenInput(out, "domain", domain);
    try writeHiddenInput(out, "action", action);
    try writeHiddenInput(out, "record_id", record_id);
    try out.writeAll("<button type=\"submit\" class=\"button button-small");
    if (danger) try out.writeAll(" button-danger");
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</button></form>");
}

fn injectDnsEdit(ctx: context.Context, request: http.Request, domain: []const u8, records: []const std.json.Value, draft: ?DnsDraft, main: *[]u8) !void {
    const record_id = request.query("edit") orelse return;
    const record = findJsonRecord(records, record_id) orelse return;
    const actions = member(record, "actions") orelse .null;
    if (!boolField(actions, "edit")) return;
    const submitted = if (draft) |value| std.mem.eql(u8, value.action, "update") and std.mem.eql(u8, value.record_id, record_id) else false;
    const selected_record_type = if (submitted and isSupportedDnsType(draft.?.record_type)) draft.?.record_type else strField(record, "type");
    const name = if (submitted) draft.?.name else strField(record, "name");
    const content = if (submitted) draft.?.content else strField(record, "content");
    const ttl = if (submitted) draft.?.ttl else "";
    const proxied = if (submitted) draft.?.proxied else boolField(record, "proxied");
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "dns-update");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"edit-record-form\" class=\"form-grid\" method=\"post\" action=\"/dns/record\">");
    try writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(&body.writer, "idempotency_key", key);
    try writeHiddenInput(&body.writer, "domain", domain);
    try writeHiddenInput(&body.writer, "action", "update");
    try writeHiddenInput(&body.writer, "record_id", record_id);
    try body.writer.writeAll("<div class=\"field span-2\"><label for=\"edit-record-type\">Type</label><select id=\"edit-record-type\" name=\"type\">");
    for ([_][]const u8{ "A", "AAAA", "CNAME", "TXT" }) |option_type| {
        try body.writer.writeAll("<option value=\"");
        try body.writer.writeAll(option_type);
        try body.writer.writeByte('"');
        if (std.mem.eql(u8, option_type, selected_record_type)) try body.writer.writeAll(" selected");
        try body.writer.writeByte('>');
        try body.writer.writeAll(option_type);
        try body.writer.writeAll("</option>");
    }
    try body.writer.writeAll("</select></div><div class=\"field span-3\"><label for=\"edit-record-name\">Name</label><input id=\"edit-record-name\" name=\"name\" type=\"text\" required autocomplete=\"off\" value=\"");
    try web_html.attribute(&body.writer, name);
    try body.writer.writeAll("\"></div><div class=\"field span-4\"><label for=\"edit-record-content\">Content</label><input id=\"edit-record-content\" name=\"content\" type=\"text\" required autocomplete=\"off\" value=\"");
    try web_html.attribute(&body.writer, content);
    try body.writer.writeAll("\"></div><div class=\"field span-2\"><label for=\"edit-record-ttl\">TTL</label><input id=\"edit-record-ttl\" name=\"ttl\" type=\"number\" min=\"1\" max=\"86400\" required value=\"");
    if (submitted) try web_html.attribute(&body.writer, ttl) else try body.writer.print("{d}", .{intField(record, "ttl")});
    try body.writer.writeAll("\"></div><label class=\"field-inline\" for=\"edit-record-proxied\"><input id=\"edit-record-proxied\" name=\"proxied\" type=\"checkbox\" value=\"1\"");
    if (proxied) try body.writer.writeAll(" checked");
    try body.writer.writeAll("> Proxied</label><div class=\"span-12 cluster\"><button class=\"button-primary\" type=\"submit\">Save record</button><a class=\"button\" href=\"/dns.html?domain=");
    try writeUrlQueryComponent(&body.writer, domain);
    try body.writer.writeAll("\">Cancel</a></div></form>");
    try replaceElementInner(ctx.gpa, main, "edit-record-body", "div", body.written());
    try replaceExact(ctx.gpa, main, "id=\"edit-record-panel\" class=\"panel hidden\"", "id=\"edit-record-panel\" class=\"panel\"");
}

fn injectDnsDelete(ctx: context.Context, request: http.Request, domain: []const u8, records: []const std.json.Value, draft: ?DnsDraft, main: *[]u8) !void {
    if (!std.mem.eql(u8, request.query("confirm") orelse "", "delete")) return;
    const record_id = request.query("record") orelse return;
    const record = findJsonRecord(records, record_id) orelse return;
    const actions = member(record, "actions") orelse .null;
    if (!boolField(actions, "delete")) return;
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "dns-delete");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<p>Delete the ");
    try web_html.text(&body.writer, strField(record, "type"));
    try body.writer.writeAll(" record <code>");
    try web_html.text(&body.writer, strField(record, "name"));
    try body.writer.writeAll("</code>. This changes public DNS.</p><form id=\"delete-record-form\" class=\"stack\" method=\"post\" action=\"/dns/record\">");
    try writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(&body.writer, "idempotency_key", key);
    try writeHiddenInput(&body.writer, "domain", domain);
    try writeHiddenInput(&body.writer, "action", "delete");
    try writeHiddenInput(&body.writer, "record_id", record_id);
    try body.writer.writeAll("<div class=\"field\"><label for=\"dns-delete-confirmation\">Type <code>");
    try web_html.text(&body.writer, strField(record, "name"));
    try body.writer.writeAll("</code> to confirm</label><input id=\"dns-delete-confirmation\" name=\"confirmation\" type=\"text\" required autocomplete=\"off\" value=\"");
    if (draft) |value| if (std.mem.eql(u8, value.action, "delete") and std.mem.eql(u8, value.record_id, record_id)) try web_html.attribute(&body.writer, value.confirmation);
    try body.writer.writeAll("\"></div><div class=\"cluster\"><button class=\"button button-danger\" type=\"submit\">Delete record</button><a class=\"button\" href=\"/dns.html?domain=");
    try writeUrlQueryComponent(&body.writer, domain);
    try body.writer.writeAll("\">Cancel</a></div></form>");
    try replaceElementInner(ctx.gpa, main, "delete-record-body", "div", body.written());
    try replaceExact(ctx.gpa, main, "id=\"delete-record-panel\" class=\"panel hidden\"", "id=\"delete-record-panel\" class=\"panel\"");
}

fn findJsonRecord(records: []const std.json.Value, record_id: []const u8) ?std.json.Value {
    for (records) |record| if (std.mem.eql(u8, strField(record, "id"), record_id)) return record;
    return null;
}

fn injectVps(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_vps.writeJson(context.vps(ctx), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const machines = arrayItems(member(parsed.value, "machines"));
    const metrics = arrayItems(member(parsed.value, "metrics"));
    const collection = member(parsed.value, "collection") orelse .null;
    const capability = member(parsed.value, "capability") orelse .null;

    var freshness = std.Io.Writer.Allocating.init(ctx.gpa);
    defer freshness.deinit();
    try writeStatus(&freshness.writer, freshnessLabel(strField(parsed.value, "freshness")));
    try replaceElementInner(ctx.gpa, main, "vps-freshness", "dd", freshness.written());
    const observed_at = nullableString(member(parsed.value, "observed_at"));
    try replaceEscapedElement(ctx.gpa, main, "vps-observed-at", "dd", if (observed_at.len > 0) observed_at else "Never");
    var attempt = std.Io.Writer.Allocating.init(ctx.gpa);
    defer attempt.deinit();
    try web_html.text(&attempt.writer, collectionStatusLabel(strField(collection, "status")));
    const attempted_at = nullableString(member(collection, "attempted_at"));
    if (attempted_at.len > 0) {
        try attempt.writer.writeAll(" · ");
        try web_html.text(&attempt.writer, attempted_at);
    }
    try replaceElementInner(ctx.gpa, main, "vps-attempt", "dd", attempt.written());
    try replaceEscapedElement(ctx.gpa, main, "vps-capability", "p", strField(capability, "reason"));

    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try formIdempotencyKey(ctx.io, &refresh_key_buffer, "vps-refresh");
    try replaceHiddenInput(ctx.gpa, main, "vps-refresh-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try replaceHiddenInput(ctx.gpa, main, "vps-refresh-idempotency", "idempotency_key", refresh_key);
    if (boolField(capability, "refresh")) try replaceExact(ctx.gpa, main, "<button class=\"button-primary\" type=\"submit\" disabled>Refresh machines</button>", "<button class=\"button-primary\" type=\"submit\">Refresh machines</button>");

    var cards = std.Io.Writer.Allocating.init(ctx.gpa);
    defer cards.deinit();
    try cards.writer.writeAll("<div id=\"machines\" class=\"resource-grid\">");
    if (machines.len == 0) {
        try cards.writer.writeAll("<div class=\"resource-card empty-state\">Refresh to observe Hostinger machines.</div>");
    } else for (machines) |machine| {
        const machine_id = strField(machine, "id");
        const actions = member(machine, "actions") orelse .null;
        try cards.writer.writeAll("<article class=\"resource-card\" data-vps-machine=\"");
        try web_html.attribute(&cards.writer, machine_id);
        try cards.writer.writeAll("\"><div class=\"resource-card-header\"><h3 class=\"resource-card-title\">");
        try web_html.text(&cards.writer, firstString(machine, &.{ "name", "id" }));
        try cards.writer.writeAll("</h3>");
        try writeStatus(&cards.writer, strField(machine, "status"));
        try cards.writer.writeAll("</div><dl class=\"kv-list\">");
        try definition(&cards.writer, "IPv4", strField(machine, "ipv4"));
        try definition(&cards.writer, "Plan", strField(machine, "plan"));
        try definition(&cards.writer, "ID", machine_id);
        try definition(&cards.writer, "Observed", strField(machine, "observed_at"));
        try cards.writer.writeAll("</dl><div class=\"resource-card-actions\">");
        var rendered_action = false;
        for ([_][]const u8{ "start", "stop", "restart" }) |action| {
            if (!boolField(actions, action)) continue;
            rendered_action = true;
            try writeVpsActionLink(&cards.writer, machine_id, action);
        }
        if (!rendered_action) {
            try cards.writer.writeAll("<span class=\"muted\">");
            try web_html.text(&cards.writer, strField(machine, "capability_reason"));
            try cards.writer.writeAll("</span>");
        }
        try cards.writer.writeAll("</div></article>");
    }
    try cards.writer.writeAll("</div>");
    try replaceExact(ctx.gpa, main, "<div id=\"machines\" class=\"resource-grid\">\n        <div class=\"resource-card empty-state loading-state\">Loading machines…</div>\n      </div>", cards.written());
    try replaceCountLabel(ctx.gpa, main, "machine-count", "p", machines.len, "machine", "machines");

    var metric_html = std.Io.Writer.Allocating.init(ctx.gpa);
    defer metric_html.deinit();
    try metric_html.writer.writeAll("<div id=\"metrics\" class=\"table-scroll\">");
    if (metrics.len == 0) {
        try metric_html.writer.writeAll("<div class=\"empty-state\">No metric rows.</div>");
    } else {
        try metric_html.writer.writeAll("<table><thead><tr><th>VM</th><th>Metric</th><th>Samples</th><th>Latest captured</th></tr></thead><tbody>");
        for (metrics) |metric| {
            try metric_html.writer.writeAll("<tr>");
            try cellText(&metric_html.writer, strField(metric, "vm_id"), "mono");
            try cellText(&metric_html.writer, strField(metric, "metric"), "");
            try cellValue(&metric_html.writer, member(metric, "count"), "");
            try cellText(&metric_html.writer, strField(metric, "latest_captured"), "muted");
            try metric_html.writer.writeAll("</tr>");
        }
        try metric_html.writer.writeAll("</tbody></table>");
    }
    try metric_html.writer.writeAll("</div>");
    try replaceExact(
        ctx.gpa,
        main,
        "<div id=\"metrics\" class=\"table-scroll\">\n        <div class=\"empty-state loading-state\">Loading metrics…</div>\n      </div>",
        metric_html.written(),
    );

    try injectVpsConfirmation(ctx, request, machines, main);
    if (vpsFeedback(request)) |feedback| {
        var message = std.Io.Writer.Allocating.init(ctx.gpa);
        defer message.deinit();
        try web_html.text(&message.writer, feedback.message);
        if (request.query("job")) |job| {
            try message.writer.writeAll(" Provider job: ");
            try web_html.text(&message.writer, job);
            try message.writer.writeByte('.');
        }
        try replaceElementInner(ctx.gpa, main, "vps-notice", "div", message.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"vps-notice\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"vps-notice\" class=\"notice hidden\"", replacement);
    }
}

fn writeVpsActionLink(out: *std.Io.Writer, machine_id: []const u8, action: []const u8) !void {
    try out.writeAll("<a class=\"button button-small");
    if (std.mem.eql(u8, action, "stop")) try out.writeAll(" button-danger");
    try out.writeAll("\" href=\"/vps.html?confirm=");
    try writeUrlQueryComponent(out, action);
    try out.writeAll("&amp;machine=");
    try writeUrlQueryComponent(out, machine_id);
    try out.writeAll("\" data-vps-action=\"");
    try web_html.attribute(out, action);
    try out.writeAll("\" data-vps-id=\"");
    try web_html.attribute(out, machine_id);
    try out.writeAll("\">");
    if (action.len > 0) try out.writeByte(std.ascii.toUpper(action[0]));
    try web_html.text(out, action[1..]);
    try out.writeAll("</a>");
}

const VpsDraft = struct { machine: []const u8, action: []const u8, confirmation: []const u8 };

fn parseVpsDraft(arena: std.mem.Allocator, request: http.Request) ?VpsDraft {
    if (!std.mem.eql(u8, request.method, "POST") or !form.hasUrlEncodedBody(request)) return null;
    const fields = form.parse(arena, request.body) catch return null;
    return .{
        .machine = fields.get("machine") catch "",
        .action = fields.get("action") catch "",
        .confirmation = fields.get("confirmation") catch "",
    };
}

fn injectVpsConfirmation(ctx: context.Context, request: http.Request, machines: []const std.json.Value, main: *[]u8) !void {
    const action_text = request.query("confirm") orelse return;
    const machine_id = request.query("machine") orelse return;
    const action = std.meta.stringToEnum(app_vps.Action, action_text) orelse return;
    const machine = findJsonMachine(machines, machine_id) orelse return;
    const actions = member(machine, "actions") orelse .null;
    if (!boolField(actions, action_text)) return;

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    try summary.writer.writeAll("Confirm ");
    try web_html.text(&summary.writer, action_text);
    try summary.writer.writeAll(" for ");
    try web_html.text(&summary.writer, firstString(machine, &.{ "name", "id" }));
    try summary.writer.writeAll(". The current observed state is ");
    try web_html.text(&summary.writer, strField(machine, "status"));
    try summary.writer.writeByte('.');
    try replaceElementInner(ctx.gpa, main, "vps-confirmation-summary", "p", summary.written());

    var draft_arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer draft_arena_state.deinit();
    const draft = parseVpsDraft(draft_arena_state.allocator(), request);
    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "vps-action");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"vps-action-form\" class=\"stack\" method=\"post\" action=\"/vps/action\">");
    try writeHiddenInput(&body.writer, "csrf_token", ctx.auth_csrf_token orelse "");
    try writeHiddenInput(&body.writer, "idempotency_key", key);
    try writeHiddenInput(&body.writer, "machine", machine_id);
    try writeHiddenInput(&body.writer, "action", action_text);
    try body.writer.writeAll("<div class=\"field\"><label for=\"vps-confirmation-value\">Type <code>");
    try web_html.text(&body.writer, machine_id);
    try body.writer.writeAll("</code> to confirm</label><input id=\"vps-confirmation-value\" name=\"confirmation\" type=\"text\" autocomplete=\"off\" required value=\"");
    if (draft) |value| if (std.mem.eql(u8, value.machine, machine_id) and std.mem.eql(u8, value.action, action_text)) try web_html.attribute(&body.writer, value.confirmation);
    try body.writer.writeAll("\"></div><div class=\"cluster\"><button type=\"submit\" class=\"button button-primary");
    if (action == .stop) try body.writer.writeAll(" button-danger");
    try body.writer.writeAll("\">");
    if (action_text.len > 0) try body.writer.writeByte(std.ascii.toUpper(action_text[0]));
    try web_html.text(&body.writer, action_text[1..]);
    try body.writer.writeAll(" machine</button><a class=\"button\" href=\"/vps.html\">Cancel</a></div></form>");
    try replaceElementInner(ctx.gpa, main, "vps-confirmation-body", "div", body.written());
    try replaceExact(ctx.gpa, main, "id=\"vps-confirmation\" class=\"panel hidden\"", "id=\"vps-confirmation\" class=\"panel\"");
}

fn findJsonMachine(machines: []const std.json.Value, machine_id: []const u8) ?std.json.Value {
    for (machines) |machine| if (std.mem.eql(u8, strField(machine, "id"), machine_id)) return machine;
    return null;
}

const VpsFeedback = struct { tone: []const u8, message: []const u8 };

fn vpsFeedback(request: http.Request) ?VpsFeedback {
    if (request.query("refreshed") != null) return .{ .tone = "success", .message = "Machine observation refreshed successfully." };
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "start")) return .{ .tone = "success", .message = "Machine start completed and the running state was confirmed." };
        if (std.mem.eql(u8, result, "stop")) return .{ .tone = "success", .message = "Machine stop completed and the stopped state was confirmed." };
        if (std.mem.eql(u8, result, "restart")) return .{ .tone = "success", .message = "Machine restart completed and the provider job plus running state were confirmed." };
        if (std.mem.eql(u8, result, "accepted_pending")) return .{ .tone = "warning", .message = "Hostinger accepted the action, but bounded reconciliation is still pending. This machine is read-only until Refresh succeeds." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The VPS request failed its Origin or CSRF check." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The form expired or its idempotency key was reused for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "Type the exact observed machine ID to confirm this lifecycle action." };
    if (std.mem.eql(u8, code, "invalid_vps_request")) return .{ .tone = "danger", .message = "The VPS request is invalid." };
    if (std.mem.eql(u8, code, "vps_not_observed")) return .{ .tone = "danger", .message = "That machine is not part of the current Hostinger observation." };
    if (std.mem.eql(u8, code, "vps_action_unavailable")) return .{ .tone = "warning", .message = "That action is not valid for the machine's observed state." };
    if (std.mem.eql(u8, code, "vps_write_unavailable")) return .{ .tone = "warning", .message = "Machine actions require a current successful observation with no pending reconciliation." };
    if (std.mem.eql(u8, code, "vps_provider_rejected")) return .{ .tone = "danger", .message = "Hostinger rejected the action or reported a failed job. The last observed state was retained." };
    if (std.mem.eql(u8, code, "vps_provider_unavailable")) return .{ .tone = "danger", .message = "Hostinger could not be reached. The last-good machine observation was retained." };
    return .{ .tone = "danger", .message = "The VPS request could not be completed." };
}

fn injectDocker(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    const refresh_seconds: i64 = @intCast(ctx.config.refresh_seconds);
    try app_web_resources.writeContainersJson(.{
        .gpa = ctx.gpa,
        .db = ctx.db,
        .fresh_after_seconds = @max(refresh_seconds * 2, 60),
    }, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const containers = arrayItems(member(parsed.value, "containers"));
    const collection = member(parsed.value, "collection") orelse .null;
    const capability = member(parsed.value, "capability") orelse .null;
    const capability_available = boolField(capability, "available");

    try replaceEscapedElement(ctx.gpa, main, "docker-freshness", "dd", strField(parsed.value, "freshness"));
    const observed_at = strField(parsed.value, "observed_at");
    try replaceEscapedElement(ctx.gpa, main, "docker-observed-at", "dd", if (observed_at.len == 0) "Never" else observed_at);
    var collection_text = std.Io.Writer.Allocating.init(ctx.gpa);
    defer collection_text.deinit();
    const collection_status = strField(collection, "status");
    const attempted_at = strField(collection, "attempted_at");
    const collection_summary = strField(collection, "summary");
    try web_html.text(&collection_text.writer, if (collection_status.len == 0) "unavailable" else collection_status);
    if (attempted_at.len > 0) {
        try collection_text.writer.writeAll(" at ");
        try web_html.text(&collection_text.writer, attempted_at);
    }
    if (collection_summary.len > 0) {
        try collection_text.writer.writeAll(" — ");
        try web_html.text(&collection_text.writer, collection_summary);
    }
    try replaceElementInner(ctx.gpa, main, "docker-collection", "dd", collection_text.written());
    try replaceEscapedElement(ctx.gpa, main, "docker-capability", "p", strField(capability, "reason"));
    if (capability_available) {
        try replaceExact(
            ctx.gpa,
            main,
            "id=\"docker-capability\" class=\"notice tone-warning\"",
            "id=\"docker-capability\" class=\"notice tone-success\"",
        );
    }

    const csrf = ctx.auth_csrf_token orelse "";
    var refresh_key_buffer: [80]u8 = undefined;
    const refresh_key = try formIdempotencyKey(ctx.io, &refresh_key_buffer, "docker-refresh");
    try replaceHiddenInput(ctx.gpa, main, "docker-refresh-csrf", "csrf_token", csrf);
    try replaceHiddenInput(ctx.gpa, main, "docker-refresh-idempotency", "idempotency_key", refresh_key);

    if (dockerFeedback(request)) |feedback| {
        var escaped = std.Io.Writer.Allocating.init(ctx.gpa);
        defer escaped.deinit();
        try web_html.text(&escaped.writer, feedback.message);
        try replaceElementInner(ctx.gpa, main, "docker-feedback", "div", escaped.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"docker-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try replaceExact(ctx.gpa, main, "id=\"docker-feedback\" class=\"notice hidden\"", replacement);
    }

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (containers.len == 0) {
        try emptyRow(&rows.writer, 5, if (observed_at.len == 0) "Refresh to observe local containers." else "No containers were observed.");
    } else for (containers) |container| {
        const container_name = strField(container, "name");
        try rows.writer.writeAll("<tr><td><a class=\"button-link mono\" data-select-container=\"");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\" href=\"/docker.html?container=");
        try web_html.urlAttribute(&rows.writer, container_name);
        try rows.writer.writeAll("&amp;tail=200\" aria-label=\"View logs for container ");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, container_name);
        try rows.writer.writeAll("</a></td>");
        try cellText(&rows.writer, strField(container, "image"), "mono breakable");
        try rows.writer.writeAll("<td>");
        try writeStatus(&rows.writer, strField(container, "state"));
        try rows.writer.writeAll("<div class=\"muted\">");
        try web_html.text(&rows.writer, strField(container, "status"));
        try rows.writer.writeAll("</div></td>");
        try cellText(&rows.writer, strField(container, "ports"), "mono breakable");
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\">");
        const actions = member(container, "actions") orelse .null;
        var rendered_action = false;
        const container_actions = [_][]const u8{ "start", "stop", "restart" };
        for (container_actions) |action| {
            if (!boolField(actions, action)) continue;
            rendered_action = true;
            try rows.writer.writeAll("<a class=\"button button-small");
            if (std.mem.eql(u8, action, "stop")) try rows.writer.writeAll(" button-danger");
            try rows.writer.writeAll("\" href=\"/docker.html?confirm=");
            try web_html.urlAttribute(&rows.writer, action);
            try rows.writer.writeAll("&amp;container=");
            try web_html.urlAttribute(&rows.writer, container_name);
            try rows.writer.writeAll("\" data-container-action=\"");
            try web_html.attribute(&rows.writer, action);
            try rows.writer.writeAll("\" data-container-name=\"");
            try web_html.attribute(&rows.writer, container_name);
            try rows.writer.writeAll("\">");
            if (action.len > 0) try rows.writer.writeByte(std.ascii.toUpper(action[0]));
            try web_html.text(&rows.writer, action[1..]);
            try rows.writer.writeAll("</a>");
        }
        if (!rendered_action) try rows.writer.writeAll("<span class=\"muted\">Read-only</span>");
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "containers-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "containers-count", "p", containers.len, "container", "containers");

    try injectDockerConfirmation(ctx, request, containers, capability_available, csrf, main);
    try injectDockerLogs(ctx, request, containers, main);
}

const DockerFeedback = struct { tone: []const u8, message: []const u8 };

fn dockerFeedback(request: http.Request) ?DockerFeedback {
    if (request.query("refreshed") != null) return .{
        .tone = "success",
        .message = "Container observation refreshed successfully.",
    };
    if (request.query("result")) |result| {
        if (std.mem.eql(u8, result, "start")) return .{ .tone = "success", .message = "Container start completed and the running state was confirmed." };
        if (std.mem.eql(u8, result, "stop")) return .{ .tone = "success", .message = "Container stop completed and the stopped state was confirmed." };
        if (std.mem.eql(u8, result, "restart")) return .{ .tone = "success", .message = "Container restart completed and the running state was confirmed." };
    }
    const code = request.query("error") orelse return null;
    if (std.mem.eql(u8, code, "invalid_container_request")) return .{ .tone = "danger", .message = "The container request was invalid. Check the selected target, action, confirmation, and log tail." };
    if (std.mem.eql(u8, code, "container_not_observed")) return .{ .tone = "danger", .message = "That container is not present in the last successful observation." };
    if (std.mem.eql(u8, code, "container_action_unavailable")) return .{ .tone = "warning", .message = "That action is not valid for the container's observed state." };
    if (std.mem.eql(u8, code, "container_refresh_in_progress")) return .{ .tone = "warning", .message = "A container refresh is already in progress." };
    if (std.mem.eql(u8, code, "container_command_failed")) return .{ .tone = "danger", .message = "The container command failed. The last-good observation was retained; see Audit for the redacted command result." };
    if (std.mem.eql(u8, code, "container_state_unconfirmed")) return .{ .tone = "danger", .message = "The command returned successfully, but the requested state could not be confirmed." };
    if (std.mem.eql(u8, code, "container_runtime_unavailable")) return .{ .tone = "danger", .message = "The local container runtime is unavailable. Last-good rows remain read-only." };
    if (std.mem.eql(u8, code, "security")) return .{ .tone = "danger", .message = "The request failed its Origin or CSRF check." };
    if (std.mem.eql(u8, code, "idempotency")) return .{ .tone = "danger", .message = "The form expired or its idempotency key was already used for different input. Reload and try again." };
    if (std.mem.eql(u8, code, "confirmation")) return .{ .tone = "danger", .message = "Type the exact observed container name to confirm this lifecycle action." };
    return .{ .tone = "danger", .message = "The container request failed." };
}

fn injectDockerConfirmation(
    ctx: context.Context,
    request: http.Request,
    containers: []const std.json.Value,
    capability_available: bool,
    csrf: []const u8,
    main: *[]u8,
) !void {
    const action_text = request.query("confirm") orelse return;
    const name = request.query("container") orelse return;
    const action = std.meta.stringToEnum(app_system_control.ContainerAction, action_text) orelse return;
    var selected: ?std.json.Value = null;
    for (containers) |container| {
        if (std.mem.eql(u8, strField(container, "name"), name)) {
            selected = container;
            break;
        }
    }
    const container = selected orelse return;
    const actions = member(container, "actions") orelse .null;
    if (!capability_available or !boolField(actions, action_text)) return;

    var summary = std.Io.Writer.Allocating.init(ctx.gpa);
    defer summary.deinit();
    try summary.writer.writeAll("Confirm ");
    try web_html.text(&summary.writer, action_text);
    try summary.writer.writeAll(" for ");
    try web_html.text(&summary.writer, name);
    try summary.writer.writeAll(". The current observed state is ");
    try web_html.text(&summary.writer, strField(container, "state"));
    try summary.writer.writeByte('.');
    try replaceElementInner(ctx.gpa, main, "container-confirmation-summary", "p", summary.written());

    var key_buffer: [80]u8 = undefined;
    const key = try formIdempotencyKey(ctx.io, &key_buffer, "docker-action");
    var body = std.Io.Writer.Allocating.init(ctx.gpa);
    defer body.deinit();
    try body.writer.writeAll("<form id=\"docker-action-form\" class=\"stack\" method=\"post\" action=\"/docker/action\">");
    try writeHiddenInput(&body.writer, "csrf_token", csrf);
    try writeHiddenInput(&body.writer, "idempotency_key", key);
    try writeHiddenInput(&body.writer, "container", name);
    try writeHiddenInput(&body.writer, "action", action_text);
    try body.writer.writeAll("<div class=\"field\"><label for=\"container-confirmation-value\">Type <code>");
    try web_html.text(&body.writer, name);
    try body.writer.writeAll("</code> to confirm</label><input id=\"container-confirmation-value\" name=\"confirmation\" type=\"text\" autocomplete=\"off\" required></div><div class=\"cluster\"><button type=\"submit\" class=\"button button-primary");
    if (action == .stop) try body.writer.writeAll(" button-danger");
    try body.writer.writeAll("\">");
    if (action_text.len > 0) try body.writer.writeByte(std.ascii.toUpper(action_text[0]));
    try web_html.text(&body.writer, action_text[1..]);
    try body.writer.writeAll(" container</button><a class=\"button\" href=\"/docker.html\">Cancel</a></div></form>");
    try replaceElementInner(ctx.gpa, main, "container-confirmation-body", "div", body.written());
    try replaceExact(
        ctx.gpa,
        main,
        "id=\"container-confirmation\" class=\"panel hidden\"",
        "id=\"container-confirmation\" class=\"panel\"",
    );
}

fn injectDockerLogs(
    ctx: context.Context,
    request: http.Request,
    containers: []const std.json.Value,
    main: *[]u8,
) !void {
    const selected_name = request.query("container") orelse "";
    var selected_observed = false;
    var options = std.Io.Writer.Allocating.init(ctx.gpa);
    defer options.deinit();
    try options.writer.writeAll("<option value=\"\"");
    if (selected_name.len == 0) try options.writer.writeAll(" selected");
    try options.writer.writeAll(">Select a container</option>");
    for (containers) |container| {
        const name = strField(container, "name");
        const selected = std.mem.eql(u8, name, selected_name);
        selected_observed = selected_observed or selected;
        try options.writer.writeAll("<option value=\"");
        try web_html.attribute(&options.writer, name);
        try options.writer.writeByte('"');
        if (selected) try options.writer.writeAll(" selected");
        try options.writer.writeByte('>');
        try web_html.text(&options.writer, name);
        try options.writer.writeAll("</option>");
    }
    try replaceElementInner(ctx.gpa, main, "log-container", "select", options.written());

    const raw_tail = request.query("tail");
    const parsed_tail = if (raw_tail) |raw| std.fmt.parseInt(i64, raw, 10) catch -1 else 200;
    const valid_tail_choice = parsed_tail == 100 or parsed_tail == 200 or parsed_tail == 500;
    const tail: i64 = if (valid_tail_choice) parsed_tail else 200;
    try replaceExact(ctx.gpa, main, "<option selected>200</option>", "<option>200</option>");
    var plain_buffer: [32]u8 = undefined;
    const plain = try std.fmt.bufPrint(&plain_buffer, "<option>{d}</option>", .{tail});
    var selected_buffer: [48]u8 = undefined;
    const selected = try std.fmt.bufPrint(&selected_buffer, "<option selected>{d}</option>", .{tail});
    try replaceExact(ctx.gpa, main, plain, selected);

    if (selected_name.len > 0) {
        var target = std.Io.Writer.Allocating.init(ctx.gpa);
        defer target.deinit();
        try target.writer.writeAll("Container: ");
        try web_html.text(&target.writer, selected_name);
        try replaceElementInner(ctx.gpa, main, "logs-target", "p", target.written());
    }
    if (raw_tail == null) return;

    if (!valid_tail_choice or !selected_observed) {
        try replaceEscapedElement(ctx.gpa, main, "logs-status", "span", if (!selected_observed) "Container is not observed." else "Tail must be 100, 200, or 500 lines.");
        try replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", "Logs were not read.");
        try replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"error\"");
        return;
    }

    var logs_json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer logs_json.deinit();
    app_system_control.containerLogs(context.system(ctx), selected_name, parsed_tail, &logs_json.writer) catch |err| {
        const message: []const u8 = switch (err) {
            error.ContainerLogsFailed => "The runtime rejected the bounded log read.",
            error.ContainerRuntimeUnavailable => "The local container runtime is unavailable.",
            error.ContainerNotObserved => "Container is not observed.",
            else => "Logs are unavailable.",
        };
        try replaceEscapedElement(ctx.gpa, main, "logs-status", "span", message);
        try replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", message);
        try replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"error\"");
        return;
    };
    var logs_parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, logs_json.written(), .{});
    defer logs_parsed.deinit();
    const logs = strField(logs_parsed.value, "logs");
    try replaceEscapedElement(ctx.gpa, main, "logs-status", "span", "Logs updated.");
    try replaceEscapedElement(ctx.gpa, main, "container-logs", "pre", if (logs.len == 0) "(empty log)" else logs);
    try replaceExact(ctx.gpa, main, "id=\"container-logs\" class=\"log-viewer\" data-state=\"empty\"", "id=\"container-logs\" class=\"log-viewer\" data-state=\"ready\"");
}

fn formIdempotencyKey(
    io: std.Io,
    buffer: *[80]u8,
    prefix: []const u8,
) ![]const u8 {
    var random: [24]u8 = undefined;
    try io.randomSecure(&random);
    var encoded: [std.base64.url_safe_no_pad.Encoder.calcSize(random.len)]u8 = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&encoded, &random);
    @memset(&random, 0);
    return std.fmt.bufPrint(buffer, "{s}-{s}", .{ prefix, encoded[0..] });
}

fn writeHiddenInput(out: *std.Io.Writer, name: []const u8, value: []const u8) !void {
    try out.writeAll("<input name=\"");
    try web_html.attribute(out, name);
    try out.writeAll("\" type=\"hidden\" value=\"");
    try web_html.attribute(out, value);
    try out.writeAll("\">");
}

fn replaceHiddenInput(
    gpa: std.mem.Allocator,
    main: *[]u8,
    id: []const u8,
    name: []const u8,
    value: []const u8,
) !void {
    const needle = try std.fmt.allocPrint(gpa, "<input id=\"{s}\" name=\"{s}\" type=\"hidden\" value=\"\">", .{ id, name });
    defer gpa.free(needle);
    var replacement = std.Io.Writer.Allocating.init(gpa);
    defer replacement.deinit();
    try replacement.writer.writeAll("<input id=\"");
    try web_html.attribute(&replacement.writer, id);
    try replacement.writer.writeAll("\" name=\"");
    try web_html.attribute(&replacement.writer, name);
    try replacement.writer.writeAll("\" type=\"hidden\" value=\"");
    try web_html.attribute(&replacement.writer, value);
    try replacement.writer.writeAll("\">");
    try replaceExact(gpa, main, needle, replacement.written());
}

fn replaceEscapedElement(
    gpa: std.mem.Allocator,
    main: *[]u8,
    id: []const u8,
    tag: []const u8,
    text: []const u8,
) !void {
    var escaped = std.Io.Writer.Allocating.init(gpa);
    defer escaped.deinit();
    try web_html.text(&escaped.writer, text);
    try replaceElementInner(gpa, main, id, tag, escaped.written());
}

fn injectAudit(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    const options = common.auditOptions(request);
    try selectOption(ctx.gpa, main, "audit-view", "important", @tagName(options.view));
    try selectOption(ctx.gpa, main, "audit-category", "", options.category orelse "");
    try selectOption(ctx.gpa, main, "audit-result", "all", @tagName(options.result));
    try selectOption(ctx.gpa, main, "audit-window", "24h", options.window.value());
    var default_limit_buffer: [32]u8 = undefined;
    const default_limit = try std.fmt.bufPrint(&default_limit_buffer, "{d}", .{@as(i64, 100)});
    var limit_buffer: [32]u8 = undefined;
    const limit = try std.fmt.bufPrint(&limit_buffer, "{d}", .{options.limit});
    try selectTextOption(ctx.gpa, main, "audit-limit", default_limit, limit);
    try replaceTextInputValue(ctx.gpa, main, "audit-target", "target", options.target orelse "");
    try replaceTextInputValue(ctx.gpa, main, "audit-actor", "actor", options.actor orelse "");

    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_writes.writeAuditJson(ctx.gpa, ctx.db, options, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const entries = arrayItems(member(parsed.value, "entries"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (entries.len == 0) {
        try emptyRow(&rows.writer, 6, "No entries match this view.");
    } else for (entries) |entry| {
        try rows.writer.writeAll("<tr data-audit-source=\"");
        try web_html.attribute(&rows.writer, strField(entry, "source"));
        try rows.writer.writeAll("\" data-audit-category=\"");
        try web_html.attribute(&rows.writer, strField(entry, "category"));
        try rows.writer.writeAll("\">");
        try dashboardCellText(&rows.writer, "Time", strField(entry, "created_at"), "mono cell-nowrap", "—");
        try dashboardCellText(&rows.writer, "Actor", strField(entry, "actor"), "mono", "system");
        try rows.writer.writeAll("<td data-label=\"Action\"><div>");
        try writeAuditOwnerLink(&rows.writer, entry);
        try rows.writer.writeAll("</div><span class=\"muted\">");
        try web_html.text(&rows.writer, auditCategoryLabel(strField(entry, "category")));
        try rows.writer.writeAll(" · ");
        try web_html.text(&rows.writer, if (std.mem.eql(u8, strField(entry, "source"), "mutation")) "Mutation" else "Event");
        try rows.writer.writeAll("</span></td>");
        try dashboardCellText(&rows.writer, "Target", strField(entry, "target"), "mono breakable", "—");
        try rows.writer.writeAll("<td data-label=\"Result\">");
        try writeStatus(&rows.writer, strField(entry, "result"));
        try rows.writer.writeAll("</td><td data-label=\"Detail\"><details><summary>View details</summary>");
        try detail(&rows.writer, "Request", strField(entry, "request"));
        try detail(&rows.writer, "Detail", strField(entry, "detail"));
        try detail(&rows.writer, "Idempotency key", strField(entry, "idempotency_key"));
        try detail(&rows.writer, "Entry identity", strField(entry, "id"));
        try rows.writer.writeAll("</details></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "audit-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "audit-count", "span", entries.len, "entry", "entries");
}

fn injectSecurity(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_authentication.writeCredentials(.{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .origin = ctx.config.auth_origin,
        .rp_id = ctx.config.auth_rp_id,
    }, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const credentials = arrayItems(member(parsed.value, "credentials"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (credentials.len == 0) {
        try emptyRow(&rows.writer, 5, "No passkeys are enrolled.");
    } else for (credentials) |credential| {
        try rows.writer.writeAll("<tr><td><strong>");
        try web_html.text(&rows.writer, strField(credential, "label"));
        try rows.writer.writeAll("</strong></td>");
        try cellBadge(&rows.writer, if (boolField(credential, "backup_eligible")) "Synced" else "Security key");
        try cellValue(&rows.writer, member(credential, "created_at"), "mono");
        if (member(credential, "last_used_at")) |last_used| {
            if (last_used == .null) try cellText(&rows.writer, "Never", "muted") else try cellValue(&rows.writer, last_used, "mono");
        } else try cellText(&rows.writer, "Never", "muted");
        const credential_id = strField(credential, "id");
        const credential_label = strField(credential, "label");
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\"><button type=\"button\" class=\"button button-small\" data-action=\"rename\" data-id=\"");
        try web_html.attribute(&rows.writer, credential_id);
        try rows.writer.writeAll("\">Rename</button><button type=\"button\" class=\"button button-small button-danger\" data-action=\"revoke\" data-id=\"");
        try web_html.attribute(&rows.writer, credential_id);
        try rows.writer.writeAll("\" data-label=\"");
        try web_html.attribute(&rows.writer, credential_label);
        try rows.writer.writeAll("\">Revoke</button></div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "passkeys-body", "tbody", rows.written());
    var count_buffer: [32]u8 = undefined;
    const count = try std.fmt.bufPrint(&count_buffer, "{d}", .{credentials.len});
    try replaceElementInner(ctx.gpa, main, "passkey-count", "div", count);

    var csrf_input = std.Io.Writer.Allocating.init(ctx.gpa);
    defer csrf_input.deinit();
    try csrf_input.writer.writeAll(
        "<input id=\"security-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"",
    );
    try web_html.attribute(&csrf_input.writer, ctx.auth_csrf_token orelse "");
    try csrf_input.writer.writeAll("\">");
    try replaceExact(
        ctx.gpa,
        main,
        "<input id=\"security-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"\">",
        csrf_input.written(),
    );

    const result = request.query("result") orelse "";
    const notice: ?struct { tone: []const u8, text: []const u8 } =
        if (std.mem.eql(u8, result, "added"))
            .{ .tone = "success", .text = "Passkey added." }
        else if (std.mem.eql(u8, result, "renamed"))
            .{ .tone = "success", .text = "Passkey renamed." }
        else if (std.mem.eql(u8, result, "revoked"))
            .{ .tone = "success", .text = "Passkey revoked." }
        else if (credentials.len < 2)
            .{ .tone = "warning", .text = "Add a second passkey before you need it. A phone plus a laptop or hardware key is a practical recovery pair." }
        else
            null;
    if (notice) |item| {
        var notice_html = std.Io.Writer.Allocating.init(ctx.gpa);
        defer notice_html.deinit();
        try notice_html.writer.print(
            "<div id=\"security-notice\" class=\"notice tone-{s}\" role=\"status\" aria-live=\"polite\">",
            .{item.tone},
        );
        try web_html.text(&notice_html.writer, item.text);
        try notice_html.writer.writeAll("</div>");
        try replaceExact(
            ctx.gpa,
            main,
            "<div id=\"security-notice\" class=\"notice hidden\" aria-live=\"polite\"></div>",
            notice_html.written(),
        );
    }
}

fn injectSettings(
    ctx: context.Context,
    request: http.Request,
    preference: theme.Preference,
    main: *[]u8,
) !void {
    var csrf_input = std.Io.Writer.Allocating.init(ctx.gpa);
    defer csrf_input.deinit();
    try csrf_input.writer.writeAll(
        "<input id=\"settings-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"",
    );
    try web_html.attribute(&csrf_input.writer, ctx.auth_csrf_token orelse "");
    try csrf_input.writer.writeAll("\">");
    try replaceExact(
        ctx.gpa,
        main,
        "<input id=\"settings-csrf\" name=\"csrf_token\" type=\"hidden\" value=\"\">",
        csrf_input.written(),
    );

    var selected = std.Io.Writer.Allocating.init(ctx.gpa);
    defer selected.deinit();
    try selected.writer.print(
        "<input id=\"theme-{s}\" name=\"theme\" type=\"radio\" value=\"{s}\" checked>",
        .{ preference.value(), preference.value() },
    );
    var unchecked: [96]u8 = undefined;
    const unchecked_input = try std.fmt.bufPrint(
        &unchecked,
        "<input id=\"theme-{s}\" name=\"theme\" type=\"radio\" value=\"{s}\">",
        .{ preference.value(), preference.value() },
    );
    try replaceExact(ctx.gpa, main, unchecked_input, selected.written());

    const notice: ?struct { tone: []const u8, text: []const u8 } = if (std.mem.eql(
        u8,
        request.query("saved") orelse "",
        "1",
    ))
        .{ .tone = "success", .text = "Appearance saved for this browser." }
    else if (request.query("error")) |code|
        if (std.mem.eql(u8, code, "request"))
            .{ .tone = "danger", .text = "The appearance request was invalid. Please try again." }
        else if (std.mem.eql(u8, code, "security"))
            .{ .tone = "danger", .text = "The security check failed. Reload the page and try again." }
        else
            .{ .tone = "danger", .text = "Choose Light, Dark, or Device." }
    else
        null;
    if (notice) |item| {
        var status = std.Io.Writer.Allocating.init(ctx.gpa);
        defer status.deinit();
        try status.writer.print(
            "<div id=\"settings-status\" class=\"notice tone-{s}\" role=\"{s}\" aria-live=\"polite\">",
            .{ item.tone, if (std.mem.eql(u8, item.tone, "danger")) "alert" else "status" },
        );
        try web_html.text(&status.writer, item.text);
        try status.writer.writeAll("</div>");
        try replaceExact(
            ctx.gpa,
            main,
            "<div id=\"settings-status\" class=\"notice hidden\" aria-live=\"polite\"></div>",
            status.written(),
        );
    }
}

fn member(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn nested(root: std.json.Value, path: []const []const u8) ?std.json.Value {
    var current = root;
    for (path) |name| current = member(current, name) orelse return null;
    return current;
}

fn arrayItems(value: ?std.json.Value) []const std.json.Value {
    const present = value orelse return &.{};
    if (present != .array) return &.{};
    return present.array.items;
}

fn asString(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}

fn nullableString(value: ?std.json.Value) []const u8 {
    const present = value orelse return "";
    return asString(present);
}

fn strField(value: std.json.Value, name: []const u8) []const u8 {
    return asString(member(value, name) orelse .null);
}

fn firstString(value: std.json.Value, names: []const []const u8) []const u8 {
    for (names) |name| {
        const text = strField(value, name);
        if (text.len > 0) return text;
    }
    return "—";
}

fn asInt(value: std.json.Value) i64 {
    return switch (value) {
        .integer => |integer| integer,
        .float => |float| @intFromFloat(float),
        else => 0,
    };
}

fn intField(value: std.json.Value, name: []const u8) i64 {
    return asInt(member(value, name) orelse .null);
}

fn boolField(value: std.json.Value, name: []const u8) bool {
    const present = member(value, name) orelse return false;
    return present == .bool and present.bool;
}

fn sourceTypeLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "provider")) return "Provider API";
    if (std.mem.eql(u8, value, "local-command")) return "Local command";
    return "Stored observation";
}

fn freshnessLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "current")) return "Current";
    if (std.mem.eql(u8, value, "stale")) return "Stale";
    return "Unavailable";
}

fn collectionStatusLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "ok")) return "Succeeded";
    if (std.mem.eql(u8, value, "error")) return "Failed";
    if (std.mem.eql(u8, value, "skipped")) return "Unavailable";
    return "Not run";
}

fn dashboardCellText(
    out: *std.Io.Writer,
    label: []const u8,
    value: []const u8,
    class: []const u8,
    empty: []const u8,
) !void {
    try out.writeAll("<td data-label=\"");
    try web_html.attribute(out, label);
    try out.writeByte('"');
    if (class.len > 0) {
        try out.writeAll(" class=\"");
        try web_html.attribute(out, class);
        try out.writeByte('"');
    }
    try out.writeByte('>');
    try web_html.text(out, if (value.len > 0) value else empty);
    try out.writeAll("</td>");
}

fn dashboardStatusCell(out: *std.Io.Writer, value: []const u8) !void {
    const label: []const u8 = if (std.mem.eql(u8, value, "healthy"))
        "Healthy"
    else if (std.mem.eql(u8, value, "degraded"))
        "Degraded"
    else if (std.mem.eql(u8, value, "dns_only"))
        "DNS only"
    else if (std.mem.eql(u8, value, "local_only"))
        "Local only"
    else if (std.mem.eql(u8, value, "project_only"))
        "Needs manifest"
    else
        "Unknown";
    try out.writeAll("<td data-label=\"Status\">");
    try writeStatus(out, label);
    try out.writeAll("</td>");
}

fn dashboardBadgeCell(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    try out.writeAll("<td data-label=\"");
    try web_html.attribute(out, label);
    try out.writeAll("\">");
    if (value.len == 0 or std.mem.eql(u8, value, "none")) {
        try out.writeAll("<span class=\"muted\">None</span>");
    } else {
        try writeBadge(out, value);
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

fn dashboardIdentityCell(out: *std.Io.Writer, row: std.json.Value) !void {
    const identity = firstNonEmpty(row, &.{ "host", "project" });
    try out.writeAll("<td data-label=\"Host\" class=\"mono cell-nowrap\">");
    if (identity.len == 0) {
        try out.writeAll("(unnamed)");
    } else if (strField(row, "container").len > 0) {
        try writeDashboardLink(out, "/docker.html", "container", strField(row, "container"), identity);
    } else if (strField(row, "project").len > 0) {
        try writeDashboardLink(out, "/projects.html", "query", strField(row, "project"), identity);
    } else if (strField(row, "upstream").len > 0 or strField(row, "caddy_source").len > 0) {
        try writeDashboardLink(out, "/routes.html", "host", identity, identity);
    } else if (strField(row, "dns_name").len > 0) {
        try writeDashboardLink(out, "/dns.html", "domain", strField(row, "dns_name"), identity);
    } else {
        try web_html.text(out, identity);
    }
    try out.writeAll("</td>");
}

const DashboardIssue = struct {
    title: []const u8,
    description: []const u8,
    owner: []const u8,
    path: []const u8,
    query_name: []const u8,
    query_value: []const u8,
    tone: []const u8,
};

fn dashboardIssue(issue: []const u8, row: std.json.Value) !DashboardIssue {
    if (std.mem.eql(u8, issue, "dns_without_local_target")) return .{
        .title = "DNS has no local target",
        .description = "This public DNS name has no matching route or managed project.",
        .owner = "Routes",
        .path = "/routes.html",
        .query_name = "host",
        .query_value = firstNonEmpty(row, &.{ "dns_name", "host" }),
        .tone = "danger",
    };
    if (std.mem.eql(u8, issue, "caddy_without_dns")) return .{
        .title = "Route has no DNS record",
        .description = "Caddy knows this host, but the configured DNS observations do not.",
        .owner = "DNS",
        .path = "/dns.html",
        .query_name = "domain",
        .query_value = strField(row, "host"),
        .tone = "danger",
    };
    if (std.mem.eql(u8, issue, "upstream_without_socket")) return .{
        .title = "Upstream is not listening",
        .description = "The route points to an address with no observed listening socket.",
        .owner = "Routes",
        .path = "/routes.html",
        .query_name = "host",
        .query_value = strField(row, "host"),
        .tone = "danger",
    };
    if (std.mem.eql(u8, issue, "project_without_runtime")) return .{
        .title = "Project needs a manifest",
        .description = "This directory was discovered but is not enrolled as a managed runtime.",
        .owner = "Projects",
        .path = "/projects.html",
        .query_name = "query",
        .query_value = strField(row, "project"),
        .tone = "info",
    };
    if (std.mem.eql(u8, issue, "service_not_running")) return .{
        .title = "Service is not running",
        .description = "The observed service state is not active or running.",
        .owner = "Projects",
        .path = "/projects.html",
        .query_name = "query",
        .query_value = firstNonEmpty(row, &.{ "project", "service" }),
        .tone = "danger",
    };
    if (std.mem.eql(u8, issue, "container_not_running")) return .{
        .title = "Container is not running",
        .description = "The observed Docker container is stopped, restarting, or unhealthy.",
        .owner = "Docker",
        .path = "/docker.html",
        .query_name = "container",
        .query_value = strField(row, "container"),
        .tone = "danger",
    };
    return error.UnmappedTopologyIssue;
}

fn writeDashboardIssue(out: *std.Io.Writer, issue_code: []const u8, row: std.json.Value) !void {
    const issue = try dashboardIssue(issue_code, row);
    try out.writeAll("<div class=\"diagnosis tone-");
    try web_html.attribute(out, issue.tone);
    try out.writeAll("\" data-issue=\"");
    try web_html.attribute(out, issue_code);
    try out.writeAll("\"><strong>");
    try web_html.text(out, issue.title);
    try out.writeAll("</strong><span>");
    try web_html.text(out, issue.description);
    try out.writeAll("</span>");
    var owner_buffer: [64]u8 = undefined;
    const owner_label = try std.fmt.bufPrint(&owner_buffer, "Open {s}", .{issue.owner});
    try writeDashboardLink(out, issue.path, issue.query_name, issue.query_value, owner_label);
    try out.writeAll("</div>");
}

fn writeDashboardLink(
    out: *std.Io.Writer,
    path: []const u8,
    query_name: []const u8,
    query_value: []const u8,
    label: []const u8,
) !void {
    try out.writeAll("<a href=\"");
    try web_html.urlAttribute(out, path);
    if (query_value.len > 0) {
        try out.writeByte('?');
        try web_html.urlAttribute(out, query_name);
        try out.writeByte('=');
        try writeUrlQueryComponent(out, query_value);
    }
    try out.writeAll("\">");
    try web_html.text(out, label);
    try out.writeAll("</a>");
}

fn writeUrlQueryComponent(out: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_' or byte == '~') {
            try out.writeByte(byte);
        } else {
            try out.writeByte('%');
            try out.writeByte(hex[byte >> 4]);
            try out.writeByte(hex[byte & 0x0f]);
        }
    }
}

fn firstNonEmpty(value: std.json.Value, names: []const []const u8) []const u8 {
    for (names) |name| {
        const text = strField(value, name);
        if (text.len > 0) return text;
    }
    return "";
}

fn cellText(out: *std.Io.Writer, value: []const u8, class: []const u8) !void {
    try out.writeAll("<td");
    if (class.len > 0) {
        try out.writeAll(" class=\"");
        try web_html.attribute(out, class);
        try out.writeByte('"');
    }
    try out.writeByte('>');
    try web_html.text(out, if (value.len > 0) value else "—");
    try out.writeAll("</td>");
}

fn cellValue(out: *std.Io.Writer, value: ?std.json.Value, class: []const u8) !void {
    try out.writeAll("<td");
    if (class.len > 0) try out.print(" class=\"{s}\"", .{class});
    try out.writeByte('>');
    if (value) |present| switch (present) {
        .string => |text| try web_html.text(out, text),
        .integer => |integer| try out.print("{d}", .{integer}),
        .float => |float| try out.print("{d}", .{float}),
        .bool => |boolean| try out.writeAll(if (boolean) "yes" else "no"),
        else => try out.writeAll("—"),
    } else try out.writeAll("—");
    try out.writeAll("</td>");
}

fn cellStatus(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<td>");
    try writeStatus(out, value);
    try out.writeAll("</td>");
}

fn writeStatus(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<span class=\"status");
    if (tone(value)) |class| try out.print(" tone-{s}", .{class});
    try out.writeAll("\">");
    try web_html.text(out, if (value.len > 0) value else "unknown");
    try out.writeAll("</span>");
}

fn cellBadge(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<td>");
    try writeBadge(out, value);
    try out.writeAll("</td>");
}

fn writeBadge(out: *std.Io.Writer, value: []const u8) !void {
    try out.writeAll("<span class=\"badge");
    if (tone(value)) |class| try out.print(" tone-{s}", .{class});
    try out.writeAll("\">");
    try web_html.text(out, if (value.len > 0) value else "unknown");
    try out.writeAll("</span>");
}

fn tone(value: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(value, "healthy") or
        std.ascii.eqlIgnoreCase(value, "running") or
        std.ascii.eqlIgnoreCase(value, "active") or
        std.ascii.eqlIgnoreCase(value, "current") or
        std.ascii.eqlIgnoreCase(value, "ok") or
        std.ascii.eqlIgnoreCase(value, "available") or
        std.ascii.eqlIgnoreCase(value, "succeeded") or
        std.ascii.eqlIgnoreCase(value, "enabled"))
        return "success";
    if (std.ascii.eqlIgnoreCase(value, "degraded") or
        std.ascii.eqlIgnoreCase(value, "failed") or
        std.ascii.eqlIgnoreCase(value, "failure") or
        std.ascii.eqlIgnoreCase(value, "error") or
        std.ascii.eqlIgnoreCase(value, "permission") or
        std.ascii.eqlIgnoreCase(value, "denied") or
        std.ascii.eqlIgnoreCase(value, "rejected") or
        std.ascii.eqlIgnoreCase(value, "disabled"))
        return "danger";
    if (std.ascii.eqlIgnoreCase(value, "stopped") or
        std.ascii.eqlIgnoreCase(value, "stale") or
        std.ascii.eqlIgnoreCase(value, "skipped") or
        std.ascii.eqlIgnoreCase(value, "pending") or
        std.ascii.eqlIgnoreCase(value, "dns_only") or
        std.ascii.eqlIgnoreCase(value, "local_only"))
        return "warning";
    if (std.ascii.eqlIgnoreCase(value, "app") or
        std.ascii.eqlIgnoreCase(value, "proxied") or
        std.ascii.eqlIgnoreCase(value, "needs manifest") or
        std.ascii.eqlIgnoreCase(value, "synced"))
        return "info";
    if (std.ascii.eqlIgnoreCase(value, "unavailable")) return "danger";
    return null;
}

fn cellWithDetail(out: *std.Io.Writer, primary: []const u8, secondary: []const u8) !void {
    try out.writeAll("<td>");
    try web_html.text(out, if (primary.len > 0) primary else "—");
    if (secondary.len > 0) {
        try out.writeAll(" <span class=\"muted\">(");
        try web_html.text(out, secondary);
        try out.writeAll(")</span>");
    }
    try out.writeAll("</td>");
}

fn definition(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    try out.writeAll("<div class=\"kv-row\"><dt>");
    try web_html.text(out, label);
    try out.writeAll("</dt><dd class=\"mono\">");
    try web_html.text(out, if (value.len > 0) value else "—");
    try out.writeAll("</dd></div>");
}

fn detail(out: *std.Io.Writer, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try out.writeAll("<div class=\"detail-block\"><div class=\"detail-label\">");
    try web_html.text(out, label);
    try out.writeAll("</div><pre class=\"code-block\">");
    try web_html.text(out, value);
    try out.writeAll("</pre></div>");
}

fn writeAuditOwnerLink(out: *std.Io.Writer, entry: std.json.Value) !void {
    const action = strField(entry, "action");
    const target = strField(entry, "target");
    const category = strField(entry, "category");
    if (std.mem.eql(u8, category, "dashboard"))
        return writeDashboardLink(out, "/", "", "", action);
    if (std.mem.eql(u8, category, "projects"))
        return writeDashboardLink(out, "/projects.html", "query", target, action);
    if (std.mem.eql(u8, category, "routes")) {
        if (std.mem.startsWith(u8, action, "caddy.route."))
            return writeDashboardLink(out, "/routes.html", "host", target, action);
        return writeDashboardLink(out, "/routes.html", "", "", action);
    }
    if (std.mem.eql(u8, category, "dns"))
        return writeDashboardLink(out, "/dns.html", "", "", action);
    if (std.mem.eql(u8, category, "browser"))
        return writeDashboardLink(out, "/browser.html", "", "", action);
    if (std.mem.eql(u8, category, "vps"))
        return writeDashboardLink(out, "/vps.html", "", "", action);
    if (std.mem.eql(u8, category, "docker"))
        return writeDashboardLink(out, "/docker.html", "container", target, action);
    if (std.mem.eql(u8, category, "security"))
        return writeDashboardLink(out, "/security.html", "", "", action);
    if (std.mem.eql(u8, category, "settings"))
        return writeDashboardLink(out, "/settings.html", "", "", action);
    try web_html.text(out, action);
}

fn auditCategoryLabel(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "dashboard")) return "Dashboard";
    if (std.mem.eql(u8, value, "projects")) return "Projects";
    if (std.mem.eql(u8, value, "routes")) return "Routes";
    if (std.mem.eql(u8, value, "dns")) return "DNS";
    if (std.mem.eql(u8, value, "browser")) return "Browser";
    if (std.mem.eql(u8, value, "vps")) return "VPS";
    if (std.mem.eql(u8, value, "docker")) return "Docker";
    if (std.mem.eql(u8, value, "security")) return "Security";
    if (std.mem.eql(u8, value, "settings")) return "Settings";
    return "Other";
}

fn emptyRow(out: *std.Io.Writer, columns: usize, message: []const u8) !void {
    try out.print("<tr><td class=\"empty-state\" colspan=\"{d}\">", .{columns});
    try web_html.text(out, message);
    try out.writeAll("</td></tr>");
}

fn replaceCountLabel(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    tag: []const u8,
    count: usize,
    singular: []const u8,
    plural: []const u8,
) !void {
    var buffer: [96]u8 = undefined;
    const label = try std.fmt.bufPrint(
        &buffer,
        "{d} {s}",
        .{ count, if (count == 1) singular else plural },
    );
    try replaceElementInner(gpa, source, id, tag, label);
}

fn replaceElementInner(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    tag: []const u8,
    replacement: []const u8,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const open_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const close_marker = try std.fmt.allocPrint(gpa, "</{s}>", .{tag});
    defer gpa.free(close_marker);
    const close_start = std.mem.indexOfPos(u8, source.*, open_end + 1, close_marker) orelse
        return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0 .. open_end + 1],
        replacement,
        source.*[close_start..],
    });
    gpa.free(source.*);
    source.* = next;
}

fn replaceExact(
    gpa: std.mem.Allocator,
    source: *[]u8,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const start = std.mem.indexOf(u8, source.*, needle) orelse return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0..start],
        replacement,
        source.*[start + needle.len ..],
    });
    gpa.free(source.*);
    source.* = next;
}

fn selectOption(
    gpa: std.mem.Allocator,
    source: *[]u8,
    select_id: []const u8,
    default_value: []const u8,
    selected_value: []const u8,
) !void {
    if (std.mem.eql(u8, default_value, selected_value)) return;
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{select_id});
    defer gpa.free(id_marker);
    const select_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const default_selected = try std.fmt.allocPrint(gpa, "<option value=\"{s}\" selected>", .{default_value});
    defer gpa.free(default_selected);
    const default_plain = try std.fmt.allocPrint(gpa, "<option value=\"{s}\">", .{default_value});
    defer gpa.free(default_plain);
    try replaceExactAfter(gpa, source, select_start, default_selected, default_plain);

    const selected_plain = try std.fmt.allocPrint(gpa, "<option value=\"{s}\">", .{selected_value});
    defer gpa.free(selected_plain);
    const selected_selected = try std.fmt.allocPrint(gpa, "<option value=\"{s}\" selected>", .{selected_value});
    defer gpa.free(selected_selected);
    try replaceExactAfter(gpa, source, select_start, selected_plain, selected_selected);
}

fn selectTextOption(
    gpa: std.mem.Allocator,
    source: *[]u8,
    select_id: []const u8,
    default_value: []const u8,
    selected_value: []const u8,
) !void {
    if (std.mem.eql(u8, default_value, selected_value)) return;
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{select_id});
    defer gpa.free(id_marker);
    const select_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const default_selected = try std.fmt.allocPrint(gpa, "<option selected>{s}</option>", .{default_value});
    defer gpa.free(default_selected);
    const default_plain = try std.fmt.allocPrint(gpa, "<option>{s}</option>", .{default_value});
    defer gpa.free(default_plain);
    try replaceExactAfter(gpa, source, select_start, default_selected, default_plain);

    const selected_plain = try std.fmt.allocPrint(gpa, "<option>{s}</option>", .{selected_value});
    defer gpa.free(selected_plain);
    const selected_selected = try std.fmt.allocPrint(gpa, "<option selected>{s}</option>", .{selected_value});
    defer gpa.free(selected_selected);
    try replaceExactAfter(gpa, source, select_start, selected_plain, selected_selected);
}

fn replaceExactAfter(
    gpa: std.mem.Allocator,
    source: *[]u8,
    start: usize,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const match_start = std.mem.indexOfPos(u8, source.*, start, needle) orelse return error.InvalidPageTemplate;
    const next = try std.mem.concat(gpa, u8, &.{
        source.*[0..match_start],
        replacement,
        source.*[match_start + needle.len ..],
    });
    gpa.free(source.*);
    source.* = next;
}

fn setInputValue(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    value: []const u8,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const input_start = std.mem.lastIndexOf(u8, source.*[0..id_start], "<input") orelse return error.InvalidPageTemplate;
    const input_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const opening = source.*[input_start..input_end];
    const marker = " value=\"";
    var escaped = std.Io.Writer.Allocating.init(gpa);
    defer escaped.deinit();
    try web_html.attribute(&escaped.writer, value);
    if (std.mem.indexOf(u8, opening, marker)) |relative| {
        const value_start = input_start + relative + marker.len;
        const value_end = std.mem.indexOfScalarPos(u8, source.*, value_start, '"') orelse return error.InvalidPageTemplate;
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..value_start], escaped.written(), source.*[value_end..] });
        gpa.free(source.*);
        source.* = next;
        return;
    }
    var attribute = std.Io.Writer.Allocating.init(gpa);
    defer attribute.deinit();
    try attribute.writer.writeAll(" value=\"");
    try attribute.writer.writeAll(escaped.written());
    try attribute.writer.writeByte('"');
    const next = try std.mem.concat(gpa, u8, &.{ source.*[0..input_end], attribute.written(), source.*[input_end..] });
    gpa.free(source.*);
    source.* = next;
}

fn setInputChecked(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    checked: bool,
) !void {
    const id_marker = try std.fmt.allocPrint(gpa, "id=\"{s}\"", .{id});
    defer gpa.free(id_marker);
    const id_start = std.mem.indexOf(u8, source.*, id_marker) orelse return error.InvalidPageTemplate;
    const input_start = std.mem.lastIndexOf(u8, source.*[0..id_start], "<input") orelse return error.InvalidPageTemplate;
    const input_end = std.mem.indexOfScalarPos(u8, source.*, id_start, '>') orelse return error.InvalidPageTemplate;
    const checked_marker = " checked";
    const present = std.mem.indexOf(u8, source.*[input_start..input_end], checked_marker);
    if (checked and present == null) {
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..input_end], checked_marker, source.*[input_end..] });
        gpa.free(source.*);
        source.* = next;
    } else if (!checked and present != null) {
        const start = input_start + present.?;
        const next = try std.mem.concat(gpa, u8, &.{ source.*[0..start], source.*[start + checked_marker.len ..] });
        gpa.free(source.*);
        source.* = next;
    }
}

fn replaceTextInputValue(
    gpa: std.mem.Allocator,
    source: *[]u8,
    id: []const u8,
    name: []const u8,
    value: []const u8,
) !void {
    if (value.len == 0) return;
    const needle = try std.fmt.allocPrint(gpa, "<input id=\"{s}\" name=\"{s}\" type=\"text\" autocomplete=\"off\">", .{ id, name });
    defer gpa.free(needle);
    var replacement = std.Io.Writer.Allocating.init(gpa);
    defer replacement.deinit();
    try replacement.writer.writeAll("<input id=\"");
    try web_html.attribute(&replacement.writer, id);
    try replacement.writer.writeAll("\" name=\"");
    try web_html.attribute(&replacement.writer, name);
    try replacement.writer.writeAll("\" type=\"text\" autocomplete=\"off\" value=\"");
    try web_html.attribute(&replacement.writer, value);
    try replacement.writer.writeAll("\">");
    try replaceExact(gpa, source, needle, replacement.written());
}

test "authenticated page allowlist is explicit" {
    try std.testing.expect(isPagePath("/"));
    try std.testing.expect(isPagePath("/security.html"));
    try std.testing.expect(isPagePath("/projects.html"));
    try std.testing.expect(isPagePath("/settings.html"));
    try std.testing.expect(!isPagePath("/login.html"));
    try std.testing.expect(isPublicPagePath("/login.html"));
    try std.testing.expect(!isPagePath("/assets/app.js"));
}

test "every authenticated page has a useful server-rendered empty state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/pages.db",
        .{tmp.sub_path},
    );
    defer allocator.free(db_path);
    var db = try @import("db_store").Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertContainer(
        "<script>alert(1)</script>",
        "registry.invalid/example",
        "Up 1 minute",
        "8080/tcp",
        "{}",
    );
    try db.upsertContainer("fixture-stopped", "registry.invalid/safe", "Exited (0)", "", "{}");
    _ = try db.insertSnapshot("system", "containers", null, "ok", "observed 2 containers", null, null);

    const paths = [_][]const u8{
        "/",
        "/projects.html",
        "/routes.html",
        "/dns.html",
        "/vps.html",
        "/docker.html",
        "/audit.html",
        "/security.html",
        "/settings.html",
    };
    for (paths) |path| {
        var output = std.Io.Writer.Allocating.init(allocator);
        defer output.deinit();
        const request: http.Request = .{
            .method = "GET",
            .target = path,
            .headers = &.{},
            .body = "",
        };
        try std.testing.expect(try render(.{
            .io = std.testing.io,
            .gpa = allocator,
            .db = &db,
            .config = .{ .domains = &.{} },
        }, request, path, .light, &output.writer));
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "id=\"app-shell\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "aria-current=\"page\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "loading-state") == null);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "class=\"theme-light\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "class=\"theme-light\"") <
            std.mem.indexOf(u8, output.written(), "/assets/app.css"));
        if (std.mem.eql(u8, path, "/docker.html")) {
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "&lt;script&gt;alert(1)&lt;/script&gt;") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "<script>alert(1)</script>") == null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "data-select-container") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "data-container-action") != null);
        }
        if (std.mem.eql(u8, path, "/routes.html")) {
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "No routes are managed by Cloudio yet.") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "id=\"routes-table\" class=\"table-scroll hidden\"") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "id=\"routes-adoption-panel\" class=\"panel hidden\"") != null);
            try std.testing.expect(std.mem.indexOf(u8, output.written(), "id=\"routes-preview-panel\" class=\"panel hidden\"") != null);
        }
    }
}
