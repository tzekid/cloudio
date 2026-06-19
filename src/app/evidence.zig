const std = @import("std");
const app_render = @import("app_render");
const evidence_common = @import("app_evidence_common");
const evidence_routes = @import("app_evidence_routes");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;

pub const default_limit = evidence_common.default_limit;
pub const Context = evidence_common.Context;
pub const ProviderFilter = evidence_common.ProviderFilter;
pub const Options = evidence_common.Options;

pub const MatrixOptions = Options;
pub const RouteCaptureOptions = evidence_routes.RouteCaptureOptions;
pub const RouteCoverageOptions = evidence_routes.RouteCoverageOptions;
pub const RouteCaptureSummaryOptions = evidence_routes.RouteCaptureSummaryOptions;
pub const RouteCaptureTotals = evidence_routes.RouteCaptureTotals;
pub const RouteCaptures = evidence_routes.RouteCaptures;
pub const RouteCoverageTotals = evidence_routes.RouteCoverageTotals;
pub const RouteCoverage = evidence_routes.RouteCoverage;
pub const RouteCaptureSummaryTotals = evidence_routes.RouteCaptureSummaryTotals;
pub const RouteCaptureSummaryRow = evidence_routes.RouteCaptureSummaryRow;
pub const RouteCaptureSummary = evidence_routes.RouteCaptureSummary;
pub const writeRouteCapturesText = evidence_routes.writeRouteCapturesText;
pub const writeRouteCapturesJson = evidence_routes.writeRouteCapturesJson;
pub const writeRouteCoverageText = evidence_routes.writeRouteCoverageText;
pub const writeRouteCoverageJson = evidence_routes.writeRouteCoverageJson;
pub const writeRouteCaptureSummaryText = evidence_routes.writeRouteCaptureSummaryText;
pub const writeRouteCaptureSummaryJson = evidence_routes.writeRouteCaptureSummaryJson;

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

pub const Matrix = struct {
    options: MatrixOptions,
    summaries: db_store.ProviderEvidenceSummaryRows,

    pub fn load(ctx: Context, options: MatrixOptions) !Matrix {
        const normalized = options.normalized();
        return .{
            .options = normalized,
            .summaries = try ctx.db.providerEvidenceSummary(ctx.gpa, normalized.provider.dbValue()),
        };
    }

    pub fn deinit(self: *Matrix, gpa: Allocator) void {
        self.summaries.deinit(gpa);
    }

    pub fn totals(self: Matrix) Totals {
        return totalsFromSummaries(self.summaries.items);
    }

    pub fn writeText(self: Matrix, writer: anytype) !void {
        const counts = self.totals();
        try writer.writeAll("Cloudio evidence matrix\n");
        try writer.print("provider={s} limit={d} groups={d} events={d} provider_raw={d} snapshots={d} audit_events={d} ok={d} errors={d} dry_run={d} http_success={d} http_error={d}\n", .{
            self.options.provider.label(),
            self.options.limit,
            counts.groups,
            counts.events,
            counts.provider_raw,
            counts.snapshots,
            counts.audit_events,
            counts.ok,
            counts.errors,
            counts.dry_run,
            counts.http_success,
            counts.http_error,
        });
        if (self.summaries.items.len == 0) {
            try writer.writeAll("none\n");
            return;
        }
        var visible: usize = 0;
        var omitted: usize = 0;
        const limit = evidence_common.displayLimit(self.options.limit, self.summaries.items.len);
        for (self.summaries.items) |row| {
            if (visible >= limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writer.print("{s}\t{s}\t{s}\t{s}\t{s}\tcount={d}\tlatest={s}\n", .{
                if (row.provider.len == 0) "unclassified" else row.provider,
                evidence_common.evidenceFamily(row.provider, row.kind),
                row.source,
                row.kind,
                evidence_common.statusClass(row.status),
                row.count,
                row.latest_at,
            });
        }
        if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
    }

    pub fn writeJson(self: Matrix, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"evidence_matrix\",");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.label(), true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try writer.writeAll("\"summary\":");
        try writeTotalsJson(self.totals(), writer);
        try writer.writeAll(",\"groups\":[");
        var visible: usize = 0;
        var omitted: usize = 0;
        const limit = evidence_common.displayLimit(self.options.limit, self.summaries.items.len);
        var first = true;
        for (self.summaries.items) |row| {
            if (visible >= limit) {
                omitted += 1;
                continue;
            }
            if (!first) try writer.writeByte(',');
            first = false;
            visible += 1;
            try writeMatrixRowJson(row, writer);
        }
        try writer.writeAll("],");
        try app_render.writeJsonIntField(writer, "visible", visible, true);
        try app_render.writeJsonIntField(writer, "omitted", omitted, false);
        try writer.writeAll("}\n");
    }
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
                .limit = evidence_common.storageLimit(normalized.limit),
            }),
        };
    }

    pub fn deinit(self: *Evidence, gpa: Allocator) void {
        self.summaries.deinit(gpa);
        self.events.deinit(gpa);
    }

    pub fn totals(self: Evidence) Totals {
        return totalsFromSummaries(self.summaries.items);
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

pub fn writeMatrixText(ctx: Context, options: MatrixOptions, writer: anytype) !void {
    var matrix = try Matrix.load(ctx, options);
    defer matrix.deinit(ctx.gpa);
    try matrix.writeText(writer);
}

pub fn writeMatrixJson(ctx: Context, options: MatrixOptions, writer: anytype) !void {
    var matrix = try Matrix.load(ctx, options);
    defer matrix.deinit(ctx.gpa);
    try matrix.writeJson(writer);
}

fn totalsFromSummaries(rows: []const db_store.ProviderEvidenceSummaryRow) Totals {
    var out = Totals{ .groups = rows.len };
    for (rows) |row| {
        out.events += row.count;
        if (std.mem.eql(u8, row.source, "provider_raw")) out.provider_raw += row.count;
        if (std.mem.eql(u8, row.source, "snapshot")) out.snapshots += row.count;
        if (std.mem.eql(u8, row.source, "audit")) out.audit_events += row.count;

        if (std.mem.eql(u8, row.provider, "cloudflare")) out.cloudflare += row.count else if (std.mem.eql(u8, row.provider, "hostinger")) out.hostinger += row.count else if (std.mem.eql(u8, row.provider, "caddy")) out.caddy += row.count else if (std.mem.eql(u8, row.provider, "system")) out.system += row.count else if (std.mem.eql(u8, row.provider, "projects")) out.projects += row.count else if (std.mem.eql(u8, row.provider, "route")) out.route += row.count else out.unclassified += row.count;

        if (evidence_common.statusIsOk(row.status)) out.ok += row.count;
        if (evidence_common.statusIsError(row.status)) out.errors += row.count;
        if (evidence_common.statusIsDryRun(row.status)) out.dry_run += row.count;
        if (evidence_common.httpStatusIsSuccess(row.status)) out.http_success += row.count;
        if (evidence_common.httpStatusIsError(row.status)) out.http_error += row.count;
    }
    return out;
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
    try evidence_common.writeRedactedTextField(gpa, writer, "target", row.target);
    try app_render.writeTextField(writer, "status", row.status);
    try evidence_common.writeRedactedTextField(gpa, writer, "detail", row.detail);
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

fn writeMatrixRowJson(row: db_store.ProviderEvidenceSummaryRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "family", evidence_common.evidenceFamily(row.provider, row.kind), true);
    try app_render.writeJsonStringField(writer, "source", row.source, true);
    try app_render.writeJsonStringField(writer, "kind", row.kind, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "status_class", evidence_common.statusClass(row.status), true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_at", row.latest_at, false);
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
    try evidence_common.writeRedactedJsonStringField(gpa, writer, "target", row.target, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try evidence_common.writeRedactedJsonStringField(gpa, writer, "detail", row.detail, true);
    try app_render.writeJsonStringField(writer, "recorded_at", row.recorded_at, false);
    try writer.writeByte('}');
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
    var db = try db_store.Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertProviderRaw("hostinger", "/api/vps/v1/virtual-machines", 200, "{\"data\":[]}");
    _ = try db.insertSnapshot("hostinger", "route-hostinger-vps", "vps", "ok", "captured 0 rows", null, null);
    _ = try db.insertSnapshot("cloudflare", "route-cloudflare-dns", "plosca.ru", "error", "permission denied", null, null);
    try db.insertAudit("route.capture", "ok", "hostinger api_token=secret-value captured");
    try db.insertAudit("route.capture", "ok", "hostinger/VPS_getVirtualMachinesV1 /api/vps/v1/virtual-machines?api_token=secret-value");
    try db.insertAudit("route.capture", "http_error", "cloudflare/accounts-list-accounts /accounts");
    try db.insertAudit("caddy.diff", "dry_run", "rendered only");

    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .db = &db };
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

    var matrix = try Matrix.load(ctx, .{ .limit = 10 });
    defer matrix.deinit(allocator);
    var matrix_text_out = std.Io.Writer.Allocating.init(allocator);
    defer matrix_text_out.deinit();
    try matrix.writeText(&matrix_text_out.writer);
    const matrix_text = try matrix_text_out.toOwnedSlice();
    defer allocator.free(matrix_text);
    try std.testing.expect(std.mem.indexOf(u8, matrix_text, "Cloudio evidence matrix\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, matrix_text, "hostinger-vps") != null);

    var matrix_json_out = std.Io.Writer.Allocating.init(allocator);
    defer matrix_json_out.deinit();
    try matrix.writeJson(&matrix_json_out.writer);
    const matrix_json = try matrix_json_out.toOwnedSlice();
    defer allocator.free(matrix_json);
    var parsed_matrix = try std.json.parseFromSlice(std.json.Value, allocator, matrix_json, .{});
    defer parsed_matrix.deinit();
    try std.testing.expectEqualStrings("evidence_matrix", parsed_matrix.value.object.get("kind").?.string);
    try std.testing.expect(parsed_matrix.value.object.get("groups").?.array.items.len >= 5);

    var captures = try RouteCaptures.load(ctx, .{ .provider = .hostinger, .limit = 10 });
    defer captures.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), captures.rows.items.len);
    var route_json_out = std.Io.Writer.Allocating.init(allocator);
    defer route_json_out.deinit();
    try captures.writeJson(allocator, &route_json_out.writer);
    const route_json = try route_json_out.toOwnedSlice();
    defer allocator.free(route_json);
    try std.testing.expect(std.mem.indexOf(u8, route_json, "secret-value") == null);
    var parsed_routes = try std.json.parseFromSlice(std.json.Value, allocator, route_json, .{});
    defer parsed_routes.deinit();
    try std.testing.expectEqualStrings("route_capture_evidence", parsed_routes.value.object.get("kind").?.string);
    try std.testing.expectEqual(@as(usize, 1), parsed_routes.value.object.get("routes").?.array.items.len);

    var route_coverage = try RouteCoverage.load(ctx, .{ .limit = 10 });
    defer route_coverage.deinit(allocator);
    const route_coverage_totals = route_coverage.totals();
    try std.testing.expect(route_coverage_totals.matched >= 2);
    try std.testing.expect(route_coverage_totals.missing >= 1);
    var route_coverage_json_out = std.Io.Writer.Allocating.init(allocator);
    defer route_coverage_json_out.deinit();
    try route_coverage.writeJson(allocator, &route_coverage_json_out.writer);
    const route_coverage_json = try route_coverage_json_out.toOwnedSlice();
    defer allocator.free(route_coverage_json);
    try std.testing.expect(std.mem.indexOf(u8, route_coverage_json, "secret-value") == null);
    var parsed_route_coverage = try std.json.parseFromSlice(std.json.Value, allocator, route_coverage_json, .{});
    defer parsed_route_coverage.deinit();
    try std.testing.expectEqualStrings("route_coverage_evidence", parsed_route_coverage.value.object.get("kind").?.string);
    try std.testing.expect(parsed_route_coverage.value.object.get("routes").?.array.items.len >= 2);
    try std.testing.expect(parsed_route_coverage.value.object.get("summary").?.object.get("official_operations").?.integer > 0);
    try std.testing.expect(parsed_route_coverage.value.object.get("summary").?.object.get("missing").?.integer >= 1);

    var capture_summary = try RouteCaptureSummary.load(ctx, .{ .limit = 20 });
    defer capture_summary.deinit(allocator);
    const capture_summary_totals = capture_summary.totals();
    try std.testing.expect(capture_summary_totals.official_read_routes > capture_summary_totals.captured_read_routes);
    try std.testing.expect(capture_summary_totals.captured_read_routes >= 2);
    try std.testing.expect(capture_summary_totals.missing_read_routes > 0);
    var capture_summary_json_out = std.Io.Writer.Allocating.init(allocator);
    defer capture_summary_json_out.deinit();
    try capture_summary.writeJson(&capture_summary_json_out.writer);
    const capture_summary_json = try capture_summary_json_out.toOwnedSlice();
    defer allocator.free(capture_summary_json);
    try std.testing.expect(std.mem.indexOf(u8, capture_summary_json, "secret-value") == null);
    var parsed_capture_summary = try std.json.parseFromSlice(std.json.Value, allocator, capture_summary_json, .{});
    defer parsed_capture_summary.deinit();
    try std.testing.expectEqualStrings("route_capture_summary", parsed_capture_summary.value.object.get("kind").?.string);
    try std.testing.expect(parsed_capture_summary.value.object.get("families").?.array.items.len > 0);
    try std.testing.expect(parsed_capture_summary.value.object.get("summary").?.object.get("missing_read_routes").?.integer > 0);
}
