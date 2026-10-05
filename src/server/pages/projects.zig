const app_nob_actions = @import("../../app/nob_actions.zig");
const app_nob_projects = @import("../../app/nob_projects.zig");
const app_nob_secrets = @import("../../app/nob_secrets.zig");
const context = @import("../context.zig");
const db_store = @import("../../db/store.zig");
const form = @import("../form.zig");
const html = @import("../html.zig");
const http = @import("../../http/root.zig");
const std = @import("std");
const url = @import("../../core/url.zig");
const web_html = @import("web_html");

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
pub fn inject(ctx: context.Context, request: http.Request, main: *[]u8) !void {
    var scan_key_buffer: [80]u8 = undefined;
    const scan_key = try html.formIdempotencyKey(ctx.io, &scan_key_buffer, "projects-scan");
    try html.replaceHiddenInput(ctx.gpa, main, "projects-scan-csrf", "csrf_token", ctx.auth_csrf_token orelse "");
    try html.replaceHiddenInput(ctx.gpa, main, "projects-scan-idempotency", "idempotency_key", scan_key);

    if (projectFeedback(request)) |feedback| {
        var message = std.Io.Writer.Allocating.init(ctx.gpa);
        defer message.deinit();
        try web_html.text(&message.writer, feedback.message);
        try html.replaceElementInner(ctx.gpa, main, "projects-feedback", "div", message.written());
        var class_buffer: [96]u8 = undefined;
        const replacement = try std.fmt.bufPrint(&class_buffer, "id=\"projects-feedback\" class=\"notice tone-{s}\"", .{feedback.tone});
        try html.replaceExact(ctx.gpa, main, "id=\"projects-feedback\" class=\"notice hidden\"", replacement);
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
    try html.replaceElementInner(ctx.gpa, main, "project-view-links", "div", links.written());

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
        try html.cellBadge(&rows.writer, project.kind);
        try html.cellBadge(&rows.writer, discoveryLabel(project.discovery_state));
        try html.cellBadge(&rows.writer, trustLabel(project.trust_state));
        try html.cellStatus(&rows.writer, project.status.text());
        try html.cellBadge(&rows.writer, runnerLabel(project.runner_state));
        try rows.writer.writeAll("<td data-label=\"Open\"><a class=\"button button-small\" href=\"/projects.html?view=");
        try web_html.urlAttribute(&rows.writer, view.query());
        try rows.writer.writeAll("&amp;project=");
        try rows.writer.print("{d}", .{project.id});
        try rows.writer.writeAll("\">Review</a></td></tr>");
    }
    if (shown == 0) {
        try html.emptyRow(&rows.writer, 7, if (view == .needs_manifest)
            "No marker-only candidates need a manifest."
        else
            "No projects match this view. Scan the projects folder to begin.");
    }
    try html.replaceElementInner(ctx.gpa, main, "nob-projects-body", "tbody", rows.written());
    try html.replaceCountLabel(ctx.gpa, main, "nob-projects-count", "span", shown, "project", "projects");

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
    try html.replaceElementInner(ctx.gpa, main, "nob-project-detail-content", "div", "<div class=\"panel-body empty-state\">The selected project no longer exists.</div>");
    try html.replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-project-detail\"", "class=\"panel\" id=\"nob-project-detail\"");
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

    try html.replaceElementInner(ctx.gpa, main, "nob-project-detail-content", "div", content.written());
    try html.replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-project-detail\"", "class=\"panel\" id=\"nob-project-detail\"");
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
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, operation);
    try out.writeAll("<form class=\"inline-form\" method=\"post\" action=\"/projects/action\">");
    try html.writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(out, "idempotency_key", key);
    try html.writeHiddenInput(out, "operation", operation);
    var project_buffer: [32]u8 = undefined;
    try html.writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project_id}));
    for (extra) |field| try html.writeHiddenInput(out, field[0], field[1]);
    try out.writeAll("<button class=\"button button-small ");
    try web_html.attribute(out, button_class);
    try out.writeAll("\" type=\"submit\">");
    try web_html.text(out, label);
    try out.writeAll("</button></form>");
}
fn projectConfirmedForm(ctx: context.Context, out: *std.Io.Writer, project: db_store.NobProject, operation: []const u8, label: []const u8) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, operation);
    var project_buffer: [32]u8 = undefined;
    const project_reference = try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id});
    const confirmation = project.declared_id orelse project_reference;
    try out.writeAll("<form class=\"inline-form confirm-form\" method=\"post\" action=\"/projects/action\">");
    try html.writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(out, "idempotency_key", key);
    try html.writeHiddenInput(out, "operation", operation);
    try html.writeHiddenInput(out, "project", project_reference);
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
    if (resources.len == 0) try html.emptyRow(out, 5, "This project declares no resources.");
    for (resources) |resource| {
        try out.writeAll("<tr><td data-label=\"Resource\"><strong>");
        try web_html.text(out, resource.label);
        try out.writeAll("</strong><div class=\"muted mono\">");
        try web_html.text(out, resource.resource_id);
        try out.writeAll("</div></td>");
        try html.cellBadge(out, resource.kind);
        try html.cellBadge(out, resource.ownership);
        try out.writeAll("<td data-label=\"Status\">");
        try html.writeStatus(out, resource.effective_status.text());
        if (resource.status_summary) |summary| {
            try out.writeAll("<div class=\"muted\">");
            try web_html.text(out, summary);
            try out.writeAll("</div>");
        }
        try out.writeAll("</td><td data-label=\"Controls or blocker\"><div class=\"cluster\">");
        var parsed = std.json.parseFromSlice(std.json.Value, ctx.gpa, resource.declaration_json, .{}) catch null;
        defer if (parsed) |*value| value.deinit();
        const controls = if (parsed) |value| html.arrayItems(html.member(value.value, "controls")) else &.{};
        var mutable_controls: usize = 0;
        for (controls) |control_value| {
            const control = html.asString(control_value);
            if (std.mem.eql(u8, control, "logs")) {
                try out.writeAll("<a class=\"button button-small\" href=\"/projects.html?project=");
                try out.print("{d}", .{project.id});
                try out.writeAll("&amp;resource_logs=");
                try url.writeComponent(out, resource.resource_id);
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
    const scope = html.strField(html.member(declaration, "spec") orelse .null, "scope");
    if (!std.mem.eql(u8, scope, "user")) return "System-scope services are outside the Projects control boundary.";
    if (!ctx.config.nob_allow_system_mutation) return "System mutation is disabled by the global kill switch.";
    return null;
}
fn controlsContain(controls: []const std.json.Value, expected: []const u8) bool {
    for (controls) |control| if (std.mem.eql(u8, html.asString(control), expected)) return true;
    return false;
}
fn renderProjectActions(ctx: context.Context, project: db_store.NobProject, actions: []const db_store.NobAction, out: *std.Io.Writer) !void {
    try out.writeAll("<section aria-labelledby=\"nob-actions-title\"><h3 id=\"nob-actions-title\" class=\"section-heading\">Actions</h3><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Action</th><th scope=\"col\">Effect</th><th scope=\"col\">Approval</th><th scope=\"col\">Plan</th></tr></thead><tbody>");
    if (actions.len == 0) try html.emptyRow(out, 4, "This project declares no actions.");
    for (actions) |action| {
        var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, action.declaration_json, .{});
        defer parsed.deinit();
        try out.writeAll("<tr><td data-label=\"Action\"><strong>");
        try web_html.text(out, action.label);
        try out.writeAll("</strong><div class=\"muted\">");
        try web_html.text(out, html.strField(parsed.value, "description"));
        try out.writeAll("</div><div class=\"muted mono\">");
        try web_html.text(out, action.action_id);
        try out.writeAll("</div></td>");
        try html.cellBadge(out, action.effect);
        try html.cellBadge(out, action.confirmation);
        try out.writeAll("<td data-label=\"Plan\">");
        if (project.trust_state != .trusted or project.runner_state != .ready) {
            try out.writeAll("<span class=\"muted\">Approve and prepare this exact manifest first.</span>");
        } else if (!action.available) {
            try out.writeAll("<span class=\"muted\">");
            try web_html.text(out, action.unavailable_reason orelse "Runner did not make this action available.");
            try out.writeAll("</span>");
        } else {
            var key_buffer: [80]u8 = undefined;
            const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "project-plan");
            try out.writeAll("<form class=\"stack compact-form\" method=\"post\" action=\"/projects/action\">");
            try html.writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
            try html.writeHiddenInput(out, "idempotency_key", key);
            try html.writeHiddenInput(out, "operation", "plan");
            var project_buffer: [32]u8 = undefined;
            try html.writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id}));
            try html.writeHiddenInput(out, "action_id", action.action_id);
            try writeActionParameters(out, html.arrayItems(html.member(parsed.value, "parameters")));
            try out.writeAll("<p class=\"muted\">Source policy: ");
            try web_html.text(out, html.strField(parsed.value, "source_policy"));
            try out.writeAll(" · rollback: ");
            try web_html.text(out, html.strField(parsed.value, "rollback"));
            try out.print(" · timeout: {d}s</p><button class=\"button button-small button-primary\" type=\"submit\">Create reviewable plan</button></form>", .{html.asInt(html.member(parsed.value, "timeout_seconds") orelse .{ .integer = 0 })});
        }
        try out.writeAll("</td></tr>");
    }
    try out.writeAll("</tbody></table></div></section>");
}
fn writeActionParameters(out: *std.Io.Writer, parameters: []const std.json.Value) !void {
    for (parameters) |parameter| {
        const name = html.strField(parameter, "name");
        const parameter_type = html.strField(parameter, "type");
        const required = html.boolField(parameter, "required");
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
            } else for (html.arrayItems(html.member(parameter, "values"))) |candidate| {
                try out.writeAll("<option value=\"");
                try web_html.attribute(out, html.asString(candidate));
                try out.writeAll("\">");
                try web_html.text(out, html.asString(candidate));
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
            if (html.member(parameter, "min_length")) |value| if (value == .integer) try out.print(" minlength=\"{d}\"", .{value.integer});
            if (html.member(parameter, "max_length")) |value| if (value == .integer) try out.print(" maxlength=\"{d}\"", .{value.integer});
            if (html.member(parameter, "minimum")) |value| if (value == .integer) try out.print(" min=\"{d}\"", .{value.integer});
            if (html.member(parameter, "maximum")) |value| if (value == .integer) try out.print(" max=\"{d}\"", .{value.integer});
            try out.writeAll("></label>");
        }
    }
}
fn renderProjectSecrets(ctx: context.Context, project: db_store.NobProject, out: *std.Io.Writer) !void {
    try out.writeAll("<section aria-labelledby=\"nob-secrets-title\"><h3 id=\"nob-secrets-title\" class=\"section-heading\">Secrets</h3><p>Bindings expose only logical status and source kind. Source references and values are never returned.</p><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Secret</th><th scope=\"col\">Required for</th><th scope=\"col\">Status</th><th scope=\"col\">Manage</th></tr></thead><tbody>");
    if (project.trust_state != .trusted) {
        try html.emptyRow(out, 4, "Approve the current manifest to inspect or bind its declared secrets.");
        try out.writeAll("</tbody></table></div></section>");
        return;
    }
    var json = std.Io.Writer.Allocating.init(ctx.gpa);
    defer json.deinit();
    var project_reference_buffer: [32]u8 = undefined;
    const project_reference = try std.fmt.bufPrint(&project_reference_buffer, "{d}", .{project.id});
    app_nob_secrets.writeJson(context.nobSecrets(ctx), project_reference, &json.writer) catch |err| {
        try html.emptyRow(out, 4, @errorName(err));
        try out.writeAll("</tbody></table></div></section>");
        return;
    };
    var parsed = try std.json.parseFromSlice(std.json.Value, ctx.gpa, json.written(), .{});
    defer parsed.deinit();
    const secrets = html.arrayItems(html.member(parsed.value, "items"));
    if (secrets.len == 0) try html.emptyRow(out, 4, "This project declares no secrets.");
    for (secrets) |secret| {
        const secret_id = html.strField(secret, "secret_id");
        try out.writeAll("<tr><td data-label=\"Secret\"><strong class=\"mono\">");
        try web_html.text(out, secret_id);
        try out.writeAll("</strong><div class=\"muted\">");
        try web_html.text(out, html.strField(secret, "purpose"));
        try out.writeAll("</div></td><td data-label=\"Required for\">");
        try writeStringArray(out, html.arrayItems(html.member(secret, "required_for")));
        try out.writeAll("</td><td data-label=\"Status\">");
        try html.writeBadge(out, if (html.boolField(secret, "bound")) if (html.boolField(secret, "present")) "present" else "unavailable" else "unbound");
        const source_kind = html.nullableString(html.member(secret, "source_kind"));
        if (source_kind.len > 0) {
            try out.writeAll("<div class=\"muted\">Source: ");
            try web_html.text(out, source_kind);
            try out.writeAll("</div>");
        }
        try out.writeAll("</td><td data-label=\"Manage\"><div class=\"stack\">");
        try secretBindForm(ctx, out, project.id, secret_id);
        if (html.boolField(secret, "bound")) {
            var fields = [_]FormField{.{ "secret_id", secret_id }};
            try projectSimpleForm(ctx, out, project.id, "secret-unbind", "Unbind", "button-danger", &fields);
        }
        try out.writeAll("</div></td></tr>");
    }
    try out.writeAll("</tbody></table></div></section>");
}
fn secretBindForm(ctx: context.Context, out: *std.Io.Writer, project_id: i64, secret_id: []const u8) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "secret-bind");
    var project_buffer: [32]u8 = undefined;
    try out.writeAll("<form class=\"stack compact-form\" method=\"post\" action=\"/projects/action\">");
    try html.writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(out, "idempotency_key", key);
    try html.writeHiddenInput(out, "operation", "secret-bind");
    try html.writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project_id}));
    try html.writeHiddenInput(out, "secret_id", secret_id);
    try out.writeAll("<label>Source kind<select name=\"source_kind\"><option value=\"file\">File</option><option value=\"process-environment\">Process environment</option></select></label><label>Absolute path or environment name<input name=\"source_ref\" required autocomplete=\"off\"></label><button class=\"button button-small\" type=\"submit\">Bind source</button></form>");
}
fn renderProjectRuns(ctx: context.Context, project: db_store.NobProject, out: *std.Io.Writer) !void {
    var runs = try app_nob_actions.listRuns(context.nobActions(ctx), project.id, 20);
    defer runs.deinit(ctx.gpa);
    try out.writeAll("<section aria-labelledby=\"nob-runs-title\"><h3 id=\"nob-runs-title\" class=\"section-heading\">Recent operations</h3><div class=\"table-scroll\"><table><thead><tr><th scope=\"col\">Operation</th><th scope=\"col\">Action</th><th scope=\"col\">State</th><th scope=\"col\">Summary</th></tr></thead><tbody>");
    if (runs.items.len == 0) try html.emptyRow(out, 4, "No operations have run for this project.");
    for (runs.items) |run| {
        try out.writeAll("<tr><td data-label=\"Operation\"><a class=\"mono\" href=\"/projects.html?project=");
        try out.print("{d}", .{project.id});
        try out.writeAll("&amp;run=");
        try url.writeComponent(out, run.id);
        try out.writeAll("\">");
        try web_html.text(out, run.id);
        try out.writeAll("</a></td>");
        try html.cellText(out, run.action_id, "mono breakable");
        try html.cellBadge(out, run.state);
        try html.cellText(out, run.summary orelse run.outcome orelse "Pending", "");
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
    try projectFact(&content.writer, "Expected downtime", try std.fmt.bufPrint(&seconds_buffer, "{d} seconds", .{html.asInt(html.member(plan, "expected_downtime_seconds") orelse .{ .integer = 0 })}), false);
    try projectFact(&content.writer, "Rollback", html.strField(html.member(plan, "rollback") orelse .null, "mode"), false);
    try projectFact(&content.writer, "Source revision", stored.source_revision orelse "Filesystem snapshot", true);
    try projectFact(&content.writer, "Source fingerprint", stored.source_fingerprint orelse "Unavailable", true);
    var expiry_buffer: [48]u8 = undefined;
    try projectFact(&content.writer, "Expires at", try std.fmt.bufPrint(&expiry_buffer, "{d}", .{stored.expires_at}), true);
    try projectFact(&content.writer, "State", stored.state, false);
    try content.writer.writeAll("</dl><div><h3 class=\"section-heading\">Parameters</h3><pre class=\"log-output\">");
    try writeJsonAsEscapedText(ctx.gpa, &content.writer, html.member(plan, "parameters") orelse .null);
    try content.writer.writeAll("</pre></div><div><h3 class=\"section-heading\">Affected resources</h3><p>");
    try writeStringArray(&content.writer, html.arrayItems(html.member(plan, "affected_resources")));
    try content.writer.writeAll("</p></div><div><h3 class=\"section-heading\">Stages and preconditions</h3><ul>");
    for (html.arrayItems(html.member(plan, "preconditions"))) |condition| {
        try content.writer.writeAll("<li><strong>");
        try web_html.text(&content.writer, html.strField(condition, "status"));
        try content.writer.writeAll("</strong> — ");
        try web_html.text(&content.writer, html.strField(condition, "summary"));
        try content.writer.writeAll("</li>");
    }
    for (html.arrayItems(html.member(plan, "stages"))) |stage| {
        try content.writer.writeAll("<li>Stage: ");
        try web_html.text(&content.writer, html.strField(stage, "label"));
        try content.writer.writeAll(if (html.boolField(stage, "reversible")) " (reversible)</li>" else " (not reversible)</li>");
    }
    try content.writer.writeAll("</ul></div>");
    if (std.mem.eql(u8, stored.state, "ready")) try planRunForm(ctx, &content.writer, project, stored);
    try content.writer.writeAll("</div>");
    try html.replaceElementInner(ctx.gpa, main, "nob-plan-review-content", "div", content.written());
    try html.replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-plan-review\"", "class=\"panel\" id=\"nob-plan-review\"");
}
fn planRunForm(ctx: context.Context, out: *std.Io.Writer, project: db_store.NobProject, plan: db_store.NobPlan) !void {
    var key_buffer: [80]u8 = undefined;
    const key = try html.formIdempotencyKey(ctx.io, &key_buffer, "project-run");
    var project_buffer: [32]u8 = undefined;
    try out.writeAll("<form class=\"stack confirm-form\" method=\"post\" action=\"/projects/action\"><h3 class=\"section-heading\">Approval</h3><p>Confirm only after reviewing the exact digest, effect, targets, downtime, rollback, parameters, and expiry above.</p>");
    try html.writeHiddenInput(out, "csrf_token", ctx.auth_csrf_token orelse "");
    try html.writeHiddenInput(out, "idempotency_key", key);
    try html.writeHiddenInput(out, "operation", "run");
    try html.writeHiddenInput(out, "project", try std.fmt.bufPrint(&project_buffer, "{d}", .{project.id}));
    try html.writeHiddenInput(out, "action_id", plan.action_id);
    try html.writeHiddenInput(out, "plan_id", plan.id);
    if (plan.resource_id) |resource_id| {
        try html.writeHiddenInput(out, "resource_id", resource_id);
        const prefix_len = "resource:".len + resource_id.len + 1;
        try html.writeHiddenInput(out, "control_name", if (plan.action_id.len > prefix_len) plan.action_id[prefix_len..] else "");
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
    try html.replaceElementInner(ctx.gpa, main, "nob-run-detail-content", "div", content.written());
    try html.replaceExact(ctx.gpa, main, "class=\"panel hidden\" id=\"nob-run-detail\"", "class=\"panel\" id=\"nob-run-detail\"");
}
fn writeStringArray(out: *std.Io.Writer, values: []const std.json.Value) !void {
    if (values.len == 0) {
        try out.writeAll("<span class=\"muted\">None</span>");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try out.writeAll(", ");
        try web_html.text(out, html.asString(value));
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
