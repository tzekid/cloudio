//! Authenticated, server-rendered first views for the Cloudio control plane.
//!
//! The application services remain the single read contract. This adapter
//! renders their JSON results into the existing authored page templates so
//! useful state, navigation, and forms arrive before JavaScript runs.

const std = @import("std");
const app_authentication = @import("app_authentication");
const app_caddy_desired = @import("app_caddy_desired");
const app_dashboard = @import("app_dashboard");
const app_deploy = @import("app_deploy");
const app_nob_projects = @import("app_nob_projects");
const app_web_resources = @import("app_web_resources");
const app_writes = @import("app_writes");
const db_store = @import("db_store");
const http = @import("http");
const web_html = @import("web_html");
const common = @import("common.zig");
const context = @import("context.zig");
const theme = @import("theme.zig");

const max_template_bytes = 512 * 1024;
const favicon_link =
    "<link rel=\"icon\" href=\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%230b1220'/%3E%3Cpath d='M18 40V24h8v16h20v8H26a8 8 0 0 1-8-8Z' fill='%234fd1c5'/%3E%3C/svg%3E\">\n";

const Page = enum {
    dashboard,
    apps,
    projects,
    routes,
    dns,
    vps,
    docker,
    audit,
    security,
    settings,

    fn title(self: Page) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .apps => "Apps",
            .projects => "Projects",
            .routes => "Routes",
            .dns => "DNS",
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
            .apps => "apps",
            .projects => "projects",
            .routes => "routes",
            .dns => "dns",
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
            .apps => "web/apps.html",
            .projects => "web/projects.html",
            .routes => "web/routes.html",
            .dns => "web/dns.html",
            .vps => "web/vps.html",
            .docker => "web/docker.html",
            .audit => "web/audit.html",
            .security => "web/security.html",
            .settings => "web/settings.html",
        };
    }

    fn script(self: Page) []const u8 {
        return switch (self) {
            .dashboard => "/assets/pages/dashboard.js",
            .apps => "/assets/pages/apps.js",
            .projects => "/assets/pages/projects.js",
            .routes => "/assets/pages/routes.js",
            .dns => "/assets/pages/dns.js",
            .vps => "/assets/pages/vps.js",
            .docker => "/assets/pages/docker.js",
            .audit => "/assets/pages/audit.js",
            .security => "/assets/pages/security.js",
            .settings => "/assets/pages/settings.js",
        };
    }
};

const nav_items = [_]struct {
    page: Page,
    href: []const u8,
    label: []const u8,
}{
    .{ .page = .dashboard, .href = "/", .label = "Dashboard" },
    .{ .page = .apps, .href = "/apps.html", .label = "Apps" },
    .{ .page = .projects, .href = "/projects.html", .label = "Projects" },
    .{ .page = .routes, .href = "/routes.html", .label = "Routes" },
    .{ .page = .dns, .href = "/dns.html", .label = "DNS" },
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
    if (std.mem.eql(u8, path, "/apps.html")) return .apps;
    if (std.mem.eql(u8, path, "/projects.html")) return .projects;
    if (std.mem.eql(u8, path, "/routes.html")) return .routes;
    if (std.mem.eql(u8, path, "/dns.html")) return .dns;
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
    }
    try head.writer.writeAll("<script defer src=\"");
    try web_html.urlAttribute(&head.writer, page.script());
    try head.writer.writeAll("\"></script>\n");
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
    if (active != .security and active != .settings) {
        try out.writeAll(
            "<button type=\"button\" class=\"button\" id=\"refresh-data-button\" " ++
                "title=\"Collect fresh provider and system data\">Refresh data</button>",
        );
    }
    try out.writeAll("</div></header>\n");
}

fn writeShellEnd(out: *std.Io.Writer) !void {
    try out.writeAll(
        \\</div></div>
        \\<button type="button" class="button sidebar-scrim" aria-label="Close navigation" data-open="false">Close navigation</button>
        \\<div id="toast-region" class="toast-region" aria-live="polite" aria-label="Notifications"></div>
        \\<dialog aria-labelledby="confirm-dialog-title"><form class="dialog-form" method="dialog">
        \\<div class="dialog-header"><h2 id="confirm-dialog-title" class="dialog-title">Confirm action</h2></div>
        \\<div class="dialog-body">Are you sure?</div>
        \\<div class="dialog-actions"><button type="button" class="button" value="cancel">Cancel</button><button type="button" class="button button-primary" value="confirm">Confirm</button></div>
        \\</form></dialog>
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
        .apps => try injectApps(ctx, main),
        .projects => try injectProjects(ctx, main),
        .routes => try injectRoutes(ctx, main),
        .dns => try injectDns(ctx, request, main),
        .vps => try injectVps(ctx, main),
        .docker => try injectDocker(ctx, main),
        .audit => try injectAudit(ctx, request, main),
        .security => try injectSecurity(ctx, main),
        .settings => try injectSettings(ctx, request, preference, main),
    }
}

fn injectDashboard(ctx: context.Context, request: http.Request, main: *[]u8) !void {
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
        .{ .gpa = ctx.gpa, .db = ctx.db },
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
            while (it.next()) |entry| issue_total += asInt(entry.value_ptr.*);
        }
    }
    const cards = [_]struct { label: []const u8, value: i64, tone: []const u8 }{
        .{ .label = "Hosts", .value = intField(topology, "total"), .tone = "" },
        .{ .label = "Healthy", .value = intField(statuses, "healthy"), .tone = "success" },
        .{ .label = "Degraded", .value = intField(statuses, "degraded"), .tone = if (intField(statuses, "degraded") > 0) "danger" else "" },
        .{ .label = "DNS only", .value = intField(statuses, "dns_only"), .tone = if (intField(statuses, "dns_only") > 0) "warning" else "" },
        .{ .label = "Local only", .value = intField(statuses, "local_only"), .tone = if (intField(statuses, "local_only") > 0) "warning" else "" },
        .{ .label = "Project only", .value = intField(statuses, "project_only"), .tone = if (intField(statuses, "project_only") > 0) "warning" else "" },
        .{ .label = "Issues", .value = issue_total, .tone = if (issue_total > 0) "danger" else "success" },
    };
    for (cards) |card| {
        try summary.writer.writeAll("<article class=\"stat-card");
        if (card.tone.len > 0) try summary.writer.print(" tone-{s}", .{card.tone});
        try summary.writer.print("\"><div class=\"stat-value\">{d}</div><div class=\"stat-label\">", .{card.value});
        try web_html.text(&summary.writer, card.label);
        try summary.writer.writeAll("</div></article>");
    }
    try replaceElementInner(ctx.gpa, main, "summary-cards", "section", summary.written());

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    const topology_rows = nested(parsed.value, &.{ "sections", "domains", "topology" });
    if (arrayItems(topology_rows).len == 0) {
        try emptyRow(&rows.writer, 8, "No topology rows match this view.");
    } else for (arrayItems(topology_rows)) |row| {
        try rows.writer.writeAll("<tr>");
        try cellStatus(&rows.writer, strField(row, "status"));
        try cellText(&rows.writer, firstString(row, &.{ "host", "project" }), "mono cell-nowrap");
        try cellBadge(&rows.writer, strField(row, "dns_match"));
        try cellText(&rows.writer, strField(row, "exposure"), "muted");
        try cellText(&rows.writer, strField(row, "upstream"), "mono cell-nowrap");
        try cellWithDetail(&rows.writer, strField(row, "service"), strField(row, "service_state"));
        try cellWithDetail(&rows.writer, strField(row, "container"), strField(row, "container_status"));
        try rows.writer.writeAll("<td><div class=\"badge-list\">");
        for (arrayItems(member(row, "issues"))) |issue| try writeBadge(&rows.writer, asString(issue));
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "topology-body", "tbody", rows.written());
}

fn injectApps(ctx: context.Context, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_deploy.writeAppsJson(context.deploy(ctx), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const apps = arrayItems(member(parsed.value, "apps"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (apps.len == 0) {
        try emptyRow(&rows.writer, 7, "No applications registered yet.");
    } else for (apps) |app| {
        try rows.writer.writeAll("<tr>");
        const app_name = strField(app, "name");
        try rows.writer.writeAll("<td><button type=\"button\" class=\"button-link mono\" data-open-app=\"");
        try web_html.attribute(&rows.writer, app_name);
        try rows.writer.writeAll("\" aria-label=\"Open details for ");
        try web_html.attribute(&rows.writer, app_name);
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, app_name);
        try rows.writer.writeAll("</button></td>");
        try cellStatus(&rows.writer, strField(app, "status"));
        try cellValue(&rows.writer, member(app, "port"), "mono");
        try cellText(&rows.writer, strField(app, "alias_host"), "breakable");
        try cellText(&rows.writer, strField(app, "toolchain"), "muted");
        try rows.writer.writeAll("<td>");
        if (member(app, "last_deploy")) |deploy| {
            if (deploy != .null) {
                try writeBadge(&rows.writer, strField(deploy, "status"));
                try rows.writer.writeAll(" <span class=\"mono\">");
                const sha = strField(deploy, "git_sha");
                try web_html.text(&rows.writer, sha[0..@min(sha.len, 8)]);
                try rows.writer.writeAll("</span> <span class=\"muted\">");
                try web_html.text(&rows.writer, firstString(deploy, &.{ "finished_at", "started_at" }));
                try rows.writer.writeAll("</span>");
            } else try rows.writer.writeAll("<span class=\"muted\">Never</span>");
        } else try rows.writer.writeAll("<span class=\"muted\">Never</span>");
        try rows.writer.writeAll("</td><td class=\"cell-actions\"><div class=\"table-actions\">");
        const actions = [_]struct { label: []const u8, action: []const u8, kind: []const u8 }{
            .{ .label = "Deploy", .action = "deploy", .kind = " button-primary" },
            .{ .label = "Start", .action = "start", .kind = "" },
            .{ .label = "Stop", .action = "stop", .kind = "" },
            .{ .label = "Restart", .action = "restart", .kind = "" },
            .{ .label = "Rollback", .action = "rollback", .kind = "" },
            .{ .label = "Delete", .action = "delete", .kind = " button-danger" },
        };
        for (actions) |action| {
            try rows.writer.print("<button type=\"button\" class=\"button button-small{s}\" data-action=\"{s}\" data-app=\"", .{ action.kind, action.action });
            try web_html.attribute(&rows.writer, app_name);
            try rows.writer.writeAll("\">");
            try web_html.text(&rows.writer, action.label);
            try rows.writer.writeAll("</button>");
        }
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "apps-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "apps-count", "span", apps.len, "app", "apps");
}

fn injectProjects(ctx: context.Context, main: *[]u8) !void {
    var projects = try app_nob_projects.list(context.nob(ctx));
    defer projects.deinit(ctx.gpa);

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (projects.items.len == 0) {
        try emptyRow(&rows.writer, 7, "No projects discovered yet. Scan the projects folder to begin.");
    } else for (projects.items) |project| {
        try rows.writer.writeAll("<tr><td><button type=\"button\" class=\"button-link\" data-open-nob-project=\"");
        try rows.writer.print("{d}", .{project.id});
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, project.display_name);
        try rows.writer.writeAll("</button><div class=\"muted mono\">");
        try web_html.text(&rows.writer, project.declared_id orelse "Not enrolled");
        try rows.writer.writeAll("</div></td>");
        try cellBadge(&rows.writer, project.kind);
        try cellBadge(&rows.writer, discoveryLabel(project.discovery_state));
        try cellBadge(&rows.writer, trustLabel(project.trust_state));
        try cellStatus(&rows.writer, project.status.text());
        try cellBadge(&rows.writer, runnerLabel(project.runner_state));
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\">");
        try rows.writer.writeAll("<button type=\"button\" class=\"button button-small\" data-open-nob-project=\"");
        try rows.writer.print("{d}", .{project.id});
        try rows.writer.writeAll("\">Details</button>");
        if (project.discovery_state == .valid and project.manifest_sha256 != null and project.trust_state != .trusted) {
            try rows.writer.writeAll("<button type=\"button\" class=\"button button-small button-primary\" data-nob-action=\"trust\" data-project-id=\"");
            try rows.writer.print("{d}", .{project.id});
            try rows.writer.writeAll("\" data-manifest-digest=\"");
            try web_html.attribute(&rows.writer, project.manifest_sha256.?);
            try rows.writer.writeAll("\">Approve</button>");
        }
        if (project.trust_state == .trusted or project.trust_state == .@"review-required") {
            try rows.writer.writeAll("<button type=\"button\" class=\"button button-small button-danger\" data-nob-action=\"revoke\" data-project-id=\"");
            try rows.writer.print("{d}", .{project.id});
            try rows.writer.writeAll("\">Revoke</button>");
        }
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "nob-projects-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "nob-projects-count", "span", projects.items.len, "project", "projects");
}

fn discoveryLabel(state: db_store.NobDiscoveryState) []const u8 {
    return switch (state) {
        .candidate => "Manifest needed",
        .valid => "Ready",
        .invalid => "Invalid manifest",
        .conflict => "ID conflict",
        .missing => "Missing",
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

fn injectRoutes(ctx: context.Context, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_caddy_desired.writeRoutesJson(context.caddy(ctx), &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const routes = arrayItems(member(parsed.value, "routes"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (routes.len == 0) {
        try emptyRow(&rows.writer, 6, "No desired routes.");
    } else for (routes) |route| {
        const host = strField(route, "host");
        const enabled = boolField(route, "enabled");
        try rows.writer.writeAll("<tr><td><input type=\"checkbox\" data-toggle-host=\"");
        try web_html.attribute(&rows.writer, host);
        try rows.writer.writeAll("\" aria-label=\"");
        try web_html.attribute(&rows.writer, if (enabled) "Disable route" else "Enable route");
        if (enabled) try rows.writer.writeAll("\" checked></td>") else try rows.writer.writeAll("\"></td>");
        try cellText(&rows.writer, host, "mono breakable");
        try cellText(&rows.writer, strField(route, "upstream"), "mono breakable");
        try cellBadge(&rows.writer, strField(route, "kind"));
        try cellText(&rows.writer, strField(route, "updated_at"), "muted");
        if (std.mem.eql(u8, strField(route, "kind"), "app")) {
            try rows.writer.writeAll("<td class=\"muted\">Managed by app</td></tr>");
        } else {
            try rows.writer.writeAll("<td class=\"cell-actions\"><button type=\"button\" class=\"button button-small button-danger\" data-delete-host=\"");
            try web_html.attribute(&rows.writer, host);
            try rows.writer.writeAll("\">Delete</button></td></tr>");
        }
    }
    try replaceElementInner(ctx.gpa, main, "routes-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "routes-count", "span", routes.len, "route", "routes");
}

fn injectDns(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    const domain = request.query("domain");
    if (domain) |selected| {
        var input = std.Io.Writer.Allocating.init(ctx.gpa);
        defer input.deinit();
        try input.writer.writeAll(
            "<input id=\"domain\" name=\"domain\" type=\"text\" " ++
                "placeholder=\"example.com\" required autocomplete=\"off\" value=\"",
        );
        try web_html.attribute(&input.writer, selected);
        try input.writer.writeAll("\">");
        try replaceExact(
            ctx.gpa,
            main,
            "<input id=\"domain\" name=\"domain\" type=\"text\" placeholder=\"example.com\" required autocomplete=\"off\">",
            input.written(),
        );
    }
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_web_resources.writeDnsRecordsJson(.{ .gpa = ctx.gpa, .db = ctx.db }, domain, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const records = arrayItems(member(parsed.value, "records"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (records.len == 0) {
        try emptyRow(&rows.writer, 6, "No DNS records found.");
    } else for (records) |record| {
        try rows.writer.writeAll("<tr>");
        try cellBadge(&rows.writer, strField(record, "type"));
        try cellText(&rows.writer, strField(record, "name"), "mono breakable");
        try cellText(&rows.writer, strField(record, "content"), "mono breakable");
        try cellValue(&rows.writer, member(record, "ttl"), "mono");
        try cellBadge(&rows.writer, if (boolField(record, "proxied")) "proxied" else "DNS only");
        try rows.writer.writeAll("<td class=\"muted\">Refresh data to manage</td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "records-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "record-count", "span", records.len, "record", "records");
    try replaceElementInner(ctx.gpa, main, "source-note", "span", "Stored provider snapshot");
}

fn injectVps(ctx: context.Context, main: *[]u8) !void {
    var vps_json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer vps_json.deinit();
    try app_web_resources.writeVpsJson(.{ .gpa = ctx.gpa, .db = ctx.db }, &vps_json.writer);
    var vps_parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, vps_json.written(), .{});
    defer vps_parsed.deinit();
    const machines = arrayItems(member(vps_parsed.value, "machines"));

    var cards = std.Io.Writer.Allocating.init(ctx.gpa);
    defer cards.deinit();
    try cards.writer.writeAll("<div id=\"machines\" class=\"resource-grid\">");
    if (machines.len == 0) {
        try cards.writer.writeAll("<div class=\"resource-card empty-state\">No machines found.</div>");
    } else for (machines) |machine| {
        try cards.writer.writeAll("<article class=\"resource-card\"><div class=\"resource-card-header\"><h3 class=\"resource-card-title\">");
        try web_html.text(&cards.writer, firstString(machine, &.{ "name", "id" }));
        try cards.writer.writeAll("</h3>");
        try writeStatus(&cards.writer, strField(machine, "status"));
        try cards.writer.writeAll("</div><dl class=\"kv-list\">");
        try definition(&cards.writer, "IPv4", strField(machine, "ipv4"));
        try definition(&cards.writer, "Plan", strField(machine, "plan"));
        try definition(&cards.writer, "ID", strField(machine, "id"));
        const machine_id = strField(machine, "id");
        try cards.writer.writeAll("</dl><div class=\"resource-card-actions\">");
        const machine_actions = [_][]const u8{ "start", "stop", "restart" };
        for (machine_actions) |action| {
            try cards.writer.writeAll("<button type=\"button\" class=\"button button-small");
            if (std.mem.eql(u8, action, "stop")) try cards.writer.writeAll(" button-danger");
            try cards.writer.writeAll("\" data-machine-action=\"");
            try web_html.attribute(&cards.writer, action);
            try cards.writer.writeAll("\" data-machine-id=\"");
            try web_html.attribute(&cards.writer, machine_id);
            try cards.writer.writeAll("\">");
            if (action.len > 0) try cards.writer.writeByte(std.ascii.toUpper(action[0]));
            try web_html.text(&cards.writer, action[1..]);
            try cards.writer.writeAll("</button>");
        }
        try cards.writer.writeAll("</div></article>");
    }
    try cards.writer.writeAll("</div>");
    try replaceExact(
        ctx.gpa,
        main,
        "<div id=\"machines\" class=\"resource-grid\">\n        <div class=\"resource-card empty-state loading-state\">Loading machines…</div>\n      </div>",
        cards.written(),
    );

    var firewall_json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer firewall_json.deinit();
    try app_web_resources.writeFirewallsJson(.{ .gpa = ctx.gpa, .db = ctx.db }, &firewall_json.writer);
    var firewall_parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, firewall_json.written(), .{});
    defer firewall_parsed.deinit();
    const firewalls = arrayItems(member(firewall_parsed.value, "firewalls"));
    var blocks = std.Io.Writer.Allocating.init(ctx.gpa);
    defer blocks.deinit();
    try blocks.writer.writeAll("<div id=\"firewalls\" class=\"stack\">");
    if (firewalls.len == 0) {
        try blocks.writer.writeAll("<div class=\"empty-state\">No firewall snapshots found.</div>");
    } else for (firewalls) |firewall| {
        try blocks.writer.writeAll("<article class=\"resource-card\"><div class=\"resource-card-header\"><h3 class=\"resource-card-title\">");
        try web_html.text(&blocks.writer, firstString(firewall, &.{ "name", "id" }));
        try blocks.writer.writeAll("</h3>");
        try writeStatus(&blocks.writer, strField(firewall, "status"));
        try blocks.writer.writeAll("</div><dl class=\"kv-list\">");
        try definition(&blocks.writer, "Kind", strField(firewall, "kind"));
        try definition(&blocks.writer, "ID", strField(firewall, "id"));
        try definition(&blocks.writer, "Target", strField(firewall, "target"));
        try blocks.writer.writeAll("</dl></article>");
    }
    try blocks.writer.writeAll("</div>");
    try replaceExact(
        ctx.gpa,
        main,
        "<div id=\"firewalls\" class=\"stack\">\n          <div class=\"empty-state loading-state\">Loading firewalls…</div>\n        </div>",
        blocks.written(),
    );

    var dashboard_json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer dashboard_json.deinit();
    try app_dashboard.writeJson(.{ .gpa = ctx.gpa, .db = ctx.db }, .{ .section = .vps }, &dashboard_json.writer);
    var dashboard = try std.json.parseFromSlice(std.json.Value, ctx.gpa, dashboard_json.written(), .{});
    defer dashboard.deinit();
    const metrics = arrayItems(nested(dashboard.value, &.{ "sections", "vps", "metrics" }));
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
}

fn injectDocker(ctx: context.Context, main: *[]u8) !void {
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_web_resources.writeContainersJson(.{ .gpa = ctx.gpa, .db = ctx.db }, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const containers = arrayItems(member(parsed.value, "containers"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (containers.len == 0) {
        try emptyRow(&rows.writer, 5, "No containers found.");
    } else for (containers) |container| {
        const container_name = strField(container, "name");
        try rows.writer.writeAll("<tr><td><button type=\"button\" class=\"button-link mono\" data-select-container=\"");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\" aria-label=\"View logs for container ");
        try web_html.attribute(&rows.writer, container_name);
        try rows.writer.writeAll("\">");
        try web_html.text(&rows.writer, container_name);
        try rows.writer.writeAll("</button></td>");
        try cellText(&rows.writer, strField(container, "image"), "mono breakable");
        try cellStatus(&rows.writer, strField(container, "status"));
        try cellText(&rows.writer, strField(container, "ports"), "mono breakable");
        try rows.writer.writeAll("<td class=\"cell-actions\"><div class=\"table-actions\">");
        const container_actions = [_][]const u8{ "start", "stop", "restart" };
        for (container_actions) |action| {
            try rows.writer.writeAll("<button type=\"button\" class=\"button button-small");
            if (std.mem.eql(u8, action, "stop")) try rows.writer.writeAll(" button-danger");
            try rows.writer.writeAll("\" data-container-action=\"");
            try web_html.attribute(&rows.writer, action);
            try rows.writer.writeAll("\" data-container-name=\"");
            try web_html.attribute(&rows.writer, container_name);
            try rows.writer.writeAll("\">");
            if (action.len > 0) try rows.writer.writeByte(std.ascii.toUpper(action[0]));
            try web_html.text(&rows.writer, action[1..]);
            try rows.writer.writeAll("</button>");
        }
        try rows.writer.writeAll("</div></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "containers-body", "tbody", rows.written());
}

fn injectAudit(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    const limit = @min(@max(common.intQuery(request, "limit", 100), 1), 500);
    if (limit != 100) {
        try replaceExact(ctx.gpa, main, "<option selected>100</option>", "<option>100</option>");
        var selected_buffer: [48]u8 = undefined;
        const plain = try std.fmt.bufPrint(&selected_buffer, "<option>{d}</option>", .{limit});
        var replacement_buffer: [64]u8 = undefined;
        const selected = try std.fmt.bufPrint(&replacement_buffer, "<option selected>{d}</option>", .{limit});
        if (std.mem.indexOf(u8, main.*, plain) != null) {
            try replaceExact(ctx.gpa, main, plain, selected);
        }
    }
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    try app_writes.writeAuditJson(ctx.gpa, ctx.db, limit, &json.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const actions = arrayItems(member(parsed.value, "actions"));

    var rows = std.Io.Writer.Allocating.init(ctx.gpa);
    defer rows.deinit();
    if (actions.len == 0) {
        try emptyRow(&rows.writer, 6, "No audit entries.");
    } else for (actions) |action| {
        try rows.writer.writeAll("<tr>");
        try cellText(&rows.writer, strField(action, "created_at"), "mono cell-nowrap");
        try cellText(&rows.writer, strField(action, "actor"), "mono");
        try cellText(&rows.writer, strField(action, "action"), "");
        try cellText(&rows.writer, strField(action, "target"), "mono breakable");
        try cellBadge(&rows.writer, strField(action, "result"));
        try rows.writer.writeAll("<td><details><summary>Details</summary>");
        try detail(&rows.writer, "Request", strField(action, "request"));
        try detail(&rows.writer, "Detail", strField(action, "detail"));
        try detail(&rows.writer, "Idempotency key", strField(action, "idempotency_key"));
        try rows.writer.writeAll("</details></td></tr>");
    }
    try replaceElementInner(ctx.gpa, main, "audit-body", "tbody", rows.written());
    try replaceCountLabel(ctx.gpa, main, "audit-count", "span", actions.len, "entry", "entries");
}

fn injectSecurity(ctx: context.Context, main: *[]u8) !void {
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
        std.ascii.eqlIgnoreCase(value, "ok") or
        std.ascii.eqlIgnoreCase(value, "enabled"))
        return "success";
    if (std.ascii.eqlIgnoreCase(value, "degraded") or
        std.ascii.eqlIgnoreCase(value, "failed") or
        std.ascii.eqlIgnoreCase(value, "error") or
        std.ascii.eqlIgnoreCase(value, "disabled"))
        return "danger";
    if (std.ascii.eqlIgnoreCase(value, "stopped") or
        std.ascii.eqlIgnoreCase(value, "dns_only") or
        std.ascii.eqlIgnoreCase(value, "local_only"))
        return "warning";
    if (std.ascii.eqlIgnoreCase(value, "app") or
        std.ascii.eqlIgnoreCase(value, "proxied") or
        std.ascii.eqlIgnoreCase(value, "synced"))
        return "info";
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
        "running",
        "8080/tcp",
        "{}",
    );

    const paths = [_][]const u8{
        "/",
        "/apps.html",
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
    }
}
