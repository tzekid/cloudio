//! Authenticated, server-rendered first views for the Cloudio control plane.
//!
//! The application services remain the single read contract. This adapter
//! renders their JSON results into the existing authored page templates so
//! useful state, navigation, and forms arrive before JavaScript runs.

const std = @import("std");
const http = @import("../http/root.zig");
const web_html = @import("web_html");
const context = @import("context.zig");
const theme = @import("theme.zig");
const html = @import("html.zig");
const dashboard_page = @import("pages/dashboard.zig");
const projects_page = @import("pages/projects.zig");
const routes_page = @import("pages/routes.zig");
const dns_page = @import("pages/dns.zig");
const browser_page = @import("pages/browser.zig");
const vps_page = @import("pages/vps.zig");
const docker_page = @import("pages/docker.zig");
const audit_page = @import("pages/audit.zig");
const security_page = @import("pages/security.zig");
const settings_page = @import("pages/settings.zig");

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

    var main = try html.extractMain(ctx.gpa, template);
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
    const main = try html.extractMain(ctx.gpa, template);
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
        .dashboard => try dashboard_page.inject(ctx, request, main),
        .projects => try projects_page.inject(ctx, request, main),
        .routes => try routes_page.inject(ctx, request, main),
        .dns => try dns_page.inject(ctx, request, main),
        .browser => try browser_page.inject(ctx, request, main),
        .vps => try vps_page.inject(ctx, request, main),
        .docker => try docker_page.inject(ctx, request, main),
        .audit => try audit_page.inject(ctx, request, main),
        .security => try security_page.inject(ctx, request, main),
        .settings => try settings_page.inject(ctx, request, preference, main),
    }
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
    var db = try @import("../db/store.zig").Db.open(std.testing.io, db_path);
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
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "class=\"theme-light\"").? <
            std.mem.indexOf(u8, output.written(), "/assets/app.css").?);
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
