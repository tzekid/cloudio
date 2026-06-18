const std = @import("std");
const app_render = @import("app_render");
const core_redact = @import("core_redact");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;

pub const default_limit = 200;

pub const Context = struct {
    gpa: Allocator,
    db: *Db,
};

pub const ProviderFilter = enum {
    all,
    cloudflare,
    hostinger,
    caddy,
    system,
    projects,
    route,

    pub fn parse(value: []const u8) ?ProviderFilter {
        if (std.mem.eql(u8, value, "all")) return .all;
        if (std.mem.eql(u8, value, "cloudflare")) return .cloudflare;
        if (std.mem.eql(u8, value, "hostinger")) return .hostinger;
        if (std.mem.eql(u8, value, "caddy")) return .caddy;
        if (std.mem.eql(u8, value, "system")) return .system;
        if (std.mem.eql(u8, value, "projects")) return .projects;
        if (std.mem.eql(u8, value, "route")) return .route;
        return null;
    }

    pub fn label(self: ProviderFilter) []const u8 {
        return switch (self) {
            .all => "all",
            .cloudflare => "cloudflare",
            .hostinger => "hostinger",
            .caddy => "caddy",
            .system => "system",
            .projects => "projects",
            .route => "route",
        };
    }

    pub fn dbValue(self: ProviderFilter) ?[]const u8 {
        return switch (self) {
            .all => null,
            .cloudflare => "cloudflare",
            .hostinger => "hostinger",
            .caddy => "caddy",
            .system => "system",
            .projects => "projects",
            .route => "route",
        };
    }
};

pub const Options = struct {
    provider: ProviderFilter = .all,
    limit: i64 = default_limit,

    pub fn normalized(self: Options) Options {
        return .{
            .provider = self.provider,
            .limit = app_render.positiveLimit(self.limit, default_limit),
        };
    }
};

pub const Totals = struct {
    groups: usize = 0,
    events: i64 = 0,
    provider_raw: i64 = 0,
    snapshots: i64 = 0,
    audit_events: i64 = 0,
    cloudflare: i64 = 0,
    hostinger: i64 = 0,
    caddy: i64 = 0,
    system: i64 = 0,
    projects: i64 = 0,
    route: i64 = 0,
    unclassified: i64 = 0,
    ok: i64 = 0,
    errors: i64 = 0,
    dry_run: i64 = 0,
    http_success: i64 = 0,
    http_error: i64 = 0,
};

pub const Evidence = struct {
    options: Options,
    summaries: db_store.ProviderEvidenceSummaryRows,
    events: db_store.ProviderEvidenceEvents,

    pub fn load(ctx: Context, options: Options) !Evidence {
        const normalized = options.normalized();
        var summaries = try ctx.db.providerEvidenceSummary(ctx.gpa, normalized.provider.dbValue());
        errdefer summaries.deinit(ctx.gpa);
        return .{
            .options = normalized,
            .summaries = summaries,
            .events = try ctx.db.providerEvidenceEvents(ctx.gpa, .{
                .provider = normalized.provider.dbValue(),
                .limit = normalized.limit,
            }),
        };
    }

    pub fn deinit(self: *Evidence, gpa: Allocator) void {
        self.summaries.deinit(gpa);
        self.events.deinit(gpa);
    }

    pub fn totals(self: Evidence) Totals {
        var out = Totals{ .groups = self.summaries.items.len };
        for (self.summaries.items) |row| {
            out.events += row.count;
            if (std.mem.eql(u8, row.source, "provider_raw")) out.provider_raw += row.count;
            if (std.mem.eql(u8, row.source, "snapshot")) out.snapshots += row.count;
            if (std.mem.eql(u8, row.source, "audit")) out.audit_events += row.count;

            if (std.mem.eql(u8, row.provider, "cloudflare")) out.cloudflare += row.count else if (std.mem.eql(u8, row.provider, "hostinger")) out.hostinger += row.count else if (std.mem.eql(u8, row.provider, "caddy")) out.caddy += row.count else if (std.mem.eql(u8, row.provider, "system")) out.system += row.count else if (std.mem.eql(u8, row.provider, "projects")) out.projects += row.count else if (std.mem.eql(u8, row.provider, "route")) out.route += row.count else out.unclassified += row.count;

            if (statusIsOk(row.status)) out.ok += row.count;
            if (statusIsError(row.status)) out.errors += row.count;
            if (statusIsDryRun(row.status)) out.dry_run += row.count;
            if (httpStatusIsSuccess(row.status)) out.http_success += row.count;
            if (httpStatusIsError(row.status)) out.http_error += row.count;
        }
        return out;
    }

    pub fn writeText(self: Evidence, gpa: Allocator, writer: anytype) !void {
        const counts = self.totals();
        try writer.writeAll("Cloudio provider evidence\n");
        try writer.print("provider={s} limit={d} groups={d} events={d} provider_raw={d} snapshots={d} audit_events={d} cloudflare={d} hostinger={d} caddy={d} system={d} projects={d} route={d} unclassified={d} ok={d} errors={d} dry_run={d} http_success={d} http_error={d}\n\n", .{
            self.options.provider.label(),
            self.options.limit,
            counts.groups,
            counts.events,
            counts.provider_raw,
            counts.snapshots,
            counts.audit_events,
            counts.cloudflare,
            counts.hostinger,
            counts.caddy,
            counts.system,
            counts.projects,
            counts.route,
            counts.unclassified,
            counts.ok,
            counts.errors,
            counts.dry_run,
            counts.http_success,
            counts.http_error,
        });

        try writer.writeAll("groups:\n");
        if (self.summaries.items.len == 0) {
            try writer.writeAll("\t(none)\n");
        } else {
            for (self.summaries.items) |row| try writeSummaryText(row, writer);
        }

        try writer.writeAll("\nrecent events:\n");
        if (self.events.items.len == 0) {
            try writer.writeAll("\t(none)\n");
        } else {
            for (self.events.items) |row| try writeEventText(gpa, row, writer);
        }
    }

    pub fn writeJson(self: Evidence, gpa: Allocator, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"provider_evidence\",");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.label(), true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try writer.writeAll("\"summary\":");
        try writeTotalsJson(self.totals(), writer);
        try writer.writeAll(",\"groups\":[");
        for (self.summaries.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeSummaryJson(row, writer);
        }
        try writer.writeAll("],\"events\":[");
        for (self.events.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeEventJson(gpa, row, writer);
        }
        try writer.writeAll("]}\n");
    }
};

pub fn writeText(ctx: Context, options: Options, writer: anytype) !void {
    var evidence = try Evidence.load(ctx, options);
    defer evidence.deinit(ctx.gpa);
    try evidence.writeText(ctx.gpa, writer);
}

pub fn writeJson(ctx: Context, options: Options, writer: anytype) !void {
    var evidence = try Evidence.load(ctx, options);
    defer evidence.deinit(ctx.gpa);
    try evidence.writeJson(ctx.gpa, writer);
}

fn writeSummaryText(row: db_store.ProviderEvidenceSummaryRow, writer: anytype) !void {
    try writer.print("\t{s}", .{row.source});
    try app_render.writeTextField(writer, "provider", if (row.provider.len == 0) "unclassified" else row.provider);
    try app_render.writeTextField(writer, "kind", row.kind);
    try app_render.writeTextField(writer, "status", row.status);
    try writer.print("\tcount={d}", .{row.count});
    try app_render.writeTextField(writer, "latest", row.latest_at);
    try writer.writeByte('\n');
}

fn writeEventText(gpa: Allocator, row: db_store.ProviderEvidenceEvent, writer: anytype) !void {
    try writer.print("\t#{d} {s}", .{ row.row_id, row.source });
    try app_render.writeTextField(writer, "provider", if (row.provider.len == 0) "unclassified" else row.provider);
    try app_render.writeTextField(writer, "kind", row.kind);
    try writeRedactedTextField(gpa, writer, "target", row.target);
    try app_render.writeTextField(writer, "status", row.status);
    try writeRedactedTextField(gpa, writer, "detail", row.detail);
    try app_render.writeTextField(writer, "at", row.recorded_at);
    try writer.writeByte('\n');
}

fn writeTotalsJson(summary: Totals, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "groups", summary.groups, true);
    try app_render.writeJsonIntField(writer, "events", summary.events, true);
    try app_render.writeJsonIntField(writer, "provider_raw", summary.provider_raw, true);
    try app_render.writeJsonIntField(writer, "snapshots", summary.snapshots, true);
    try app_render.writeJsonIntField(writer, "audit_events", summary.audit_events, true);
    try app_render.writeJsonIntField(writer, "cloudflare", summary.cloudflare, true);
    try app_render.writeJsonIntField(writer, "hostinger", summary.hostinger, true);
    try app_render.writeJsonIntField(writer, "caddy", summary.caddy, true);
    try app_render.writeJsonIntField(writer, "system", summary.system, true);
    try app_render.writeJsonIntField(writer, "projects", summary.projects, true);
    try app_render.writeJsonIntField(writer, "route", summary.route, true);
    try app_render.writeJsonIntField(writer, "unclassified", summary.unclassified, true);
    try app_render.writeJsonIntField(writer, "ok", summary.ok, true);
    try app_render.writeJsonIntField(writer, "errors", summary.errors, true);
    try app_render.writeJsonIntField(writer, "dry_run", summary.dry_run, true);
    try app_render.writeJsonIntField(writer, "http_success", summary.http_success, true);
    try app_render.writeJsonIntField(writer, "http_error", summary.http_error, false);
    try writer.writeByte('}');
}

fn writeSummaryJson(row: db_store.ProviderEvidenceSummaryRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_at", row.latest_at, false);
    try writer.writeByte('}');
}

fn writeEventJson(gpa: Allocator, row: db_store.ProviderEvidenceEvent, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "row_id", row.row_id, true);
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "kind", row.kind, true);
    try writeRedactedJsonStringField(gpa, writer, "target", row.target, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try writeRedactedJsonStringField(gpa, writer, "detail", row.detail, true);
    try app_render.writeJsonStringField(writer, "recorded_at", row.recorded_at, false);
    try writer.writeByte('}');
}

fn writeRedactedTextField(gpa: Allocator, writer: anytype, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try writer.print("\t{s}=", .{label});
    try writeRedactedValue(gpa, writer, value);
}

fn writeRedactedJsonStringField(gpa: Allocator, writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    const redacted = try core_redact.secrets(gpa, value);
    defer gpa.free(redacted);
    try app_render.writeJsonStringField(writer, name, std.mem.trimEnd(u8, redacted, "\n"), trailing_comma);
}

fn writeRedactedValue(gpa: Allocator, writer: anytype, value: []const u8) !void {
    const redacted = try core_redact.secrets(gpa, value);
    defer gpa.free(redacted);
    try writer.writeAll(std.mem.trimEnd(u8, redacted, "\n"));
}

fn statusIsDryRun(status: []const u8) bool {
    return std.mem.indexOf(u8, status, "dry") != null or std.mem.eql(u8, status, "planned");
}

fn statusIsOk(status: []const u8) bool {
    return std.mem.eql(u8, status, "ok") or
        std.mem.eql(u8, status, "success") or
        std.mem.eql(u8, status, "done") or
        httpStatusIsSuccess(status);
}

fn statusIsError(status: []const u8) bool {
    return httpStatusIsError(status) or
        std.mem.indexOf(u8, status, "error") != null or
        std.mem.indexOf(u8, status, "fail") != null or
        std.mem.indexOf(u8, status, "denied") != null or
        std.mem.indexOf(u8, status, "blocked") != null or
        std.mem.indexOf(u8, status, "missing") != null;
}

fn httpStatusIsSuccess(status: []const u8) bool {
    const code = std.fmt.parseInt(i64, status, 10) catch return false;
    return code >= 200 and code < 400;
}

fn httpStatusIsError(status: []const u8) bool {
    const code = std.fmt.parseInt(i64, status, 10) catch return false;
    return code >= 400;
}

test "provider filter parser accepts evidence scopes" {
    try std.testing.expectEqual(ProviderFilter.all, ProviderFilter.parse("all").?);
    try std.testing.expectEqual(ProviderFilter.cloudflare, ProviderFilter.parse("cloudflare").?);
    try std.testing.expectEqual(ProviderFilter.hostinger, ProviderFilter.parse("hostinger").?);
    try std.testing.expectEqual(ProviderFilter.caddy, ProviderFilter.parse("caddy").?);
    try std.testing.expectEqual(ProviderFilter.system, ProviderFilter.parse("system").?);
    try std.testing.expectEqual(ProviderFilter.projects, ProviderFilter.parse("projects").?);
    try std.testing.expectEqual(ProviderFilter.route, ProviderFilter.parse("route").?);
    try std.testing.expect(ProviderFilter.parse("other") == null);
}

test "evidence read model summarizes and redacts event details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-evidence.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertProviderRaw("hostinger", "/api/vps/v1/virtual-machines", 200, "{\"data\":[]}");
    _ = try db.insertSnapshot("hostinger", "route-hostinger-vps", "vps", "ok", "captured 0 rows", null, null);
    _ = try db.insertSnapshot("cloudflare", "route-cloudflare-dns", "plosca.ru", "error", "permission denied", null, null);
    try db.insertAudit("route.capture", "ok", "hostinger api_token=secret-value captured");
    try db.insertAudit("caddy.diff", "dry_run", "rendered only");

    const ctx = Context{ .gpa = allocator, .db = &db };
    var evidence = try Evidence.load(ctx, .{ .limit = 20 });
    defer evidence.deinit(allocator);
    const totals = evidence.totals();
    try std.testing.expect(totals.events >= 5);
    try std.testing.expectEqual(@as(i64, 1), totals.provider_raw);
    try std.testing.expect(totals.hostinger >= 3);
    try std.testing.expectEqual(@as(i64, 1), totals.dry_run);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try evidence.writeText(allocator, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider evidence\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "secret-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[REDACTED]") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try evidence.writeJson(allocator, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "secret-value") == null);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("provider_evidence", parsed.value.object.get("kind").?.string);
    try std.testing.expect(parsed.value.object.get("groups").?.array.items.len >= 5);
    try std.testing.expect(parsed.value.object.get("events").?.array.items.len >= 5);
}
