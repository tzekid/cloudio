const std = @import("std");
const app_render = @import("app_render");
const evidence_common = @import("app_evidence_common");
const db_store = @import("db_store");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

pub const Context = evidence_common.Context;
pub const ProviderFilter = evidence_common.ProviderFilter;
pub const RouteCaptureOptions = evidence_common.Options;
pub const RouteCoverageOptions = evidence_common.Options;
pub const RouteCaptureSummaryOptions = evidence_common.Options;

const route_capture_summary_load_limit: i64 = 100_000;
const route_capture_summary_evidence_note = "missing_read_routes means no route.capture audit event; unresolved_read_routes excludes routes already covered by fixture/diagnostic L2 evidence";

pub const RouteCaptureTotals = struct {
    operations: usize = 0,
    captures: i64 = 0,
    cloudflare: i64 = 0,
    hostinger: i64 = 0,
    ok: i64 = 0,
    errors: i64 = 0,
};

pub const RouteCaptures = struct {
    options: RouteCaptureOptions,
    rows: db_store.RouteCaptureEvidenceRows,

    pub fn load(ctx: Context, options: RouteCaptureOptions) !RouteCaptures {
        const normalized = options.normalized();
        return .{
            .options = normalized,
            .rows = try ctx.db.routeCaptureEvidence(ctx.gpa, .{
                .provider = normalized.provider.dbValue(),
                .limit = evidence_common.storageLimit(normalized.limit),
            }),
        };
    }

    pub fn deinit(self: *RouteCaptures, gpa: Allocator) void {
        self.rows.deinit(gpa);
    }

    pub fn totals(self: RouteCaptures) RouteCaptureTotals {
        var out = RouteCaptureTotals{ .operations = self.rows.items.len };
        for (self.rows.items) |row| {
            out.captures += row.count;
            if (std.mem.eql(u8, row.provider, "cloudflare")) out.cloudflare += row.count;
            if (std.mem.eql(u8, row.provider, "hostinger")) out.hostinger += row.count;
            if (evidence_common.statusIsOk(row.status)) out.ok += row.count;
            if (evidence_common.statusIsError(row.status)) out.errors += row.count;
        }
        return out;
    }

    pub fn writeText(self: RouteCaptures, gpa: Allocator, writer: anytype) !void {
        const counts = self.totals();
        try writer.writeAll("Cloudio route capture evidence\n");
        try writer.print("provider={s} limit={d} operations={d} captures={d} cloudflare={d} hostinger={d} ok={d} errors={d}\n", .{
            self.options.provider.label(),
            self.options.limit,
            counts.operations,
            counts.captures,
            counts.cloudflare,
            counts.hostinger,
            counts.ok,
            counts.errors,
        });
        if (self.rows.items.len == 0) {
            try writer.writeAll("none\n");
            return;
        }
        for (self.rows.items) |row| {
            try writer.print("{s}\t{s}\t{s}\tstatus={s}\tcount={d}\tlatest={s}\tendpoint=", .{
                row.provider,
                evidence_common.evidenceFamily(row.provider, row.operation_id),
                row.operation_id,
                row.status,
                row.count,
                row.latest_at,
            });
            try evidence_common.writeRedactedValue(gpa, writer, row.endpoint_sample);
            try writer.writeByte('\n');
        }
    }

    pub fn writeJson(self: RouteCaptures, gpa: Allocator, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"route_capture_evidence\",");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.label(), true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try writer.writeAll("\"summary\":");
        try writeRouteCaptureTotalsJson(self.totals(), writer);
        try writer.writeAll(",\"routes\":[");
        for (self.rows.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeRouteCaptureJson(gpa, row, writer);
        }
        try writer.writeAll("]}\n");
    }
};

pub const RouteCoverageTotals = struct {
    official_operations: usize = 0,
    captured_operations: usize = 0,
    captures: i64 = 0,
    matched: usize = 0,
    missing: usize = 0,
    read: usize = 0,
    dry_run: usize = 0,
    write: usize = 0,
    deprecated: usize = 0,
    ok: i64 = 0,
    errors: i64 = 0,
};

pub const RouteCoverage = struct {
    options: RouteCoverageOptions,
    rows: db_store.RouteCaptureEvidenceRows,
    routes: provider_routes.RouteSet,

    pub fn load(ctx: Context, options: RouteCoverageOptions) !RouteCoverage {
        const normalized = options.normalized();
        const route_filter = try evidence_common.routeCoverageProviderFilter(normalized.provider);
        var rows = try ctx.db.routeCaptureEvidence(ctx.gpa, .{
            .provider = normalized.provider.dbValue(),
            .limit = evidence_common.storageLimit(normalized.limit),
        });
        errdefer rows.deinit(ctx.gpa);
        var routes = switch (route_filter) {
            .all => try provider_routes.loadAll(ctx.io, ctx.gpa, ctx.routes),
            .cloudflare => try provider_routes.loadProvider(ctx.io, ctx.gpa, ctx.routes, .cloudflare),
            .hostinger => try provider_routes.loadProvider(ctx.io, ctx.gpa, ctx.routes, .hostinger),
        };
        errdefer routes.deinit(ctx.gpa);
        return .{
            .options = normalized,
            .rows = rows,
            .routes = routes,
        };
    }

    pub fn deinit(self: *RouteCoverage, gpa: Allocator) void {
        self.rows.deinit(gpa);
        self.routes.deinit(gpa);
    }

    pub fn totals(self: RouteCoverage) RouteCoverageTotals {
        var out = RouteCoverageTotals{
            .official_operations = self.routes.items.len,
            .captured_operations = self.rows.items.len,
        };
        for (self.rows.items) |row| {
            out.captures += row.count;
            if (evidence_common.statusIsOk(row.status)) out.ok += row.count;
            if (evidence_common.statusIsError(row.status)) out.errors += row.count;
            if (self.findRoute(row)) |route| {
                out.matched += 1;
                if (route.deprecated) out.deprecated += 1;
                switch (route.mode) {
                    .read => out.read += 1,
                    .dry_run => out.dry_run += 1,
                    .write => out.write += 1,
                    .none => {},
                }
            } else {
                out.missing += 1;
            }
        }
        return out;
    }

    pub fn findRoute(self: RouteCoverage, row: db_store.RouteCaptureEvidenceRow) ?*const provider_routes.Route {
        const provider = provider_routes.Provider.parse(row.provider) orelse return null;
        for (self.routes.items) |*route| {
            if (route.provider != provider) continue;
            const operation_id = route.operation_id orelse continue;
            if (std.mem.eql(u8, operation_id, row.operation_id)) return route;
        }
        return null;
    }

    pub fn writeText(self: RouteCoverage, gpa: Allocator, writer: anytype) !void {
        const counts = self.totals();
        try writer.writeAll("Cloudio route coverage evidence\n");
        try writer.print("provider={s} limit={d} official_operations={d} captured_operations={d} captures={d} matched={d} missing={d} read={d} dry_run={d} write={d} deprecated={d} ok={d} errors={d}\n", .{
            self.options.provider.label(),
            self.options.limit,
            counts.official_operations,
            counts.captured_operations,
            counts.captures,
            counts.matched,
            counts.missing,
            counts.read,
            counts.dry_run,
            counts.write,
            counts.deprecated,
            counts.ok,
            counts.errors,
        });
        if (self.rows.items.len == 0) {
            try writer.writeAll("none\n");
            return;
        }
        for (self.rows.items) |row| {
            const route = self.findRoute(row);
            if (route) |matched| {
                try writer.print("{s}\t{s}\t{s}\t{s}\t{s}\t{s}\tsupport={s}\tmode={s}\ttests={s}\tdeprecated={}\tstatus={s}\tcount={d}\tlatest={s}\tendpoint=", .{
                    row.provider,
                    routeFamily(matched.*),
                    matched.tag,
                    row.operation_id,
                    matched.method.name(),
                    matched.path_template,
                    @tagName(matched.support),
                    @tagName(matched.mode),
                    matched.tests,
                    matched.deprecated,
                    row.status,
                    row.count,
                    row.latest_at,
                });
            } else {
                try writer.print("{s}\t{s}\tunmatched\t{s}\tmethod=unknown\tpath=unknown\tsupport=unknown\tmode=unknown\ttests=unknown\tdeprecated=false\tstatus={s}\tcount={d}\tlatest={s}\tendpoint=", .{
                    row.provider,
                    evidence_common.evidenceFamily(row.provider, row.operation_id),
                    row.operation_id,
                    row.status,
                    row.count,
                    row.latest_at,
                });
            }
            try evidence_common.writeRedactedValue(gpa, writer, row.endpoint_sample);
            try writer.writeByte('\n');
        }
    }

    pub fn writeJson(self: RouteCoverage, gpa: Allocator, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"route_coverage_evidence\",");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.label(), true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try writer.writeAll("\"summary\":");
        try writeRouteCoverageTotalsJson(self.totals(), writer);
        try writer.writeAll(",\"routes\":[");
        for (self.rows.items, 0..) |row, index| {
            if (index != 0) try writer.writeByte(',');
            try writeRouteCoverageRowJson(gpa, row, self.findRoute(row), writer);
        }
        try writer.writeAll("]}\n");
    }
};

pub const RouteCaptureSummaryTotals = struct {
    families: usize = 0,
    official_read_routes: usize = 0,
    captured_read_routes: usize = 0,
    evidence_covered_read_routes: usize = 0,
    diagnostic_read_routes: usize = 0,
    ok_read_routes: usize = 0,
    error_read_routes: usize = 0,
    missing_read_routes: usize = 0,
    unresolved_read_routes: usize = 0,
    capture_events: i64 = 0,
    cloudflare_read_routes: usize = 0,
    hostinger_read_routes: usize = 0,
};

pub const RouteCaptureSummaryRow = struct {
    provider: []const u8,
    family: []const u8,
    official_read_routes: usize = 0,
    captured_read_routes: usize = 0,
    evidence_covered_read_routes: usize = 0,
    diagnostic_read_routes: usize = 0,
    ok_read_routes: usize = 0,
    error_read_routes: usize = 0,
    missing_read_routes: usize = 0,
    unresolved_read_routes: usize = 0,
    capture_events: i64 = 0,
    latest_at: []const u8 = "",
    sample_missing_operation: []const u8 = "",
    sample_unresolved_operation: []const u8 = "",

    pub fn capturedPercent(self: RouteCaptureSummaryRow) usize {
        if (self.official_read_routes == 0) return 0;
        return (self.captured_read_routes * 100) / self.official_read_routes;
    }
};

pub const RouteCaptureSummary = struct {
    options: RouteCaptureSummaryOptions,
    rows: []RouteCaptureSummaryRow,
    captures: db_store.RouteCaptureEvidenceRows,
    routes: provider_routes.RouteSet,

    pub fn load(ctx: Context, options: RouteCaptureSummaryOptions) !RouteCaptureSummary {
        const normalized = options.normalized();
        const route_filter = try evidence_common.routeCoverageProviderFilter(normalized.provider);
        var captures = try ctx.db.routeCaptureEvidence(ctx.gpa, .{
            .provider = normalized.provider.dbValue(),
            .limit = route_capture_summary_load_limit,
        });
        errdefer captures.deinit(ctx.gpa);
        var routes = switch (route_filter) {
            .all => try provider_routes.loadAll(ctx.io, ctx.gpa, ctx.routes),
            .cloudflare => try provider_routes.loadProvider(ctx.io, ctx.gpa, ctx.routes, .cloudflare),
            .hostinger => try provider_routes.loadProvider(ctx.io, ctx.gpa, ctx.routes, .hostinger),
        };
        errdefer routes.deinit(ctx.gpa);
        const rows = try buildRouteCaptureSummaryRows(ctx.gpa, routes.items, captures.items);
        errdefer ctx.gpa.free(rows);
        return .{
            .options = normalized,
            .rows = rows,
            .captures = captures,
            .routes = routes,
        };
    }

    pub fn deinit(self: *RouteCaptureSummary, gpa: Allocator) void {
        gpa.free(self.rows);
        self.captures.deinit(gpa);
        self.routes.deinit(gpa);
    }

    pub fn totals(self: RouteCaptureSummary) RouteCaptureSummaryTotals {
        var out = RouteCaptureSummaryTotals{ .families = self.rows.len };
        for (self.rows) |row| {
            out.official_read_routes += row.official_read_routes;
            out.captured_read_routes += row.captured_read_routes;
            out.evidence_covered_read_routes += row.evidence_covered_read_routes;
            out.diagnostic_read_routes += row.diagnostic_read_routes;
            out.ok_read_routes += row.ok_read_routes;
            out.error_read_routes += row.error_read_routes;
            out.missing_read_routes += row.missing_read_routes;
            out.unresolved_read_routes += row.unresolved_read_routes;
            out.capture_events += row.capture_events;
            if (std.mem.eql(u8, row.provider, "cloudflare")) out.cloudflare_read_routes += row.official_read_routes;
            if (std.mem.eql(u8, row.provider, "hostinger")) out.hostinger_read_routes += row.official_read_routes;
        }
        return out;
    }

    pub fn writeText(self: RouteCaptureSummary, writer: anytype) !void {
        const counts = self.totals();
        try writer.writeAll("Cloudio actual route capture summary\n");
        try writer.print("evidence: {s}\n", .{route_capture_summary_evidence_note});
        try writer.print("provider={s} limit={d} families={d} official_read_routes={d} captured_read_routes={d} evidence_covered_read_routes={d} diagnostic_read_routes={d} ok_read_routes={d} error_read_routes={d} missing_read_routes={d} unresolved_read_routes={d} capture_events={d} cloudflare_read_routes={d} hostinger_read_routes={d}\n", .{
            self.options.provider.label(),
            self.options.limit,
            counts.families,
            counts.official_read_routes,
            counts.captured_read_routes,
            counts.evidence_covered_read_routes,
            counts.diagnostic_read_routes,
            counts.ok_read_routes,
            counts.error_read_routes,
            counts.missing_read_routes,
            counts.unresolved_read_routes,
            counts.capture_events,
            counts.cloudflare_read_routes,
            counts.hostinger_read_routes,
        });
        if (self.rows.len == 0) {
            try writer.writeAll("none\n");
            return;
        }
        var visible: usize = 0;
        var omitted: usize = 0;
        const limit = evidence_common.displayLimit(self.options.limit, self.rows.len);
        for (self.rows) |row| {
            if (visible >= limit) {
                omitted += 1;
                continue;
            }
            visible += 1;
            try writer.print("{s}\t{s}\tread={d}\tcaptured={d}\tevidence_covered={d}\tdiagnostic={d}\tok={d}\terrors={d}\tmissing_capture={d}\tunresolved={d}\tcaptured_percent={d}\tcapture_events={d}\tlatest={s}", .{
                row.provider,
                row.family,
                row.official_read_routes,
                row.captured_read_routes,
                row.evidence_covered_read_routes,
                row.diagnostic_read_routes,
                row.ok_read_routes,
                row.error_read_routes,
                row.missing_read_routes,
                row.unresolved_read_routes,
                row.capturedPercent(),
                row.capture_events,
                if (row.latest_at.len == 0) "-" else row.latest_at,
            });
            if (row.sample_missing_operation.len != 0) try writer.print("\tsample_missing={s}", .{row.sample_missing_operation});
            if (row.sample_unresolved_operation.len != 0) try writer.print("\tsample_unresolved={s}", .{row.sample_unresolved_operation});
            try writer.writeByte('\n');
        }
        if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
    }

    pub fn writeJson(self: RouteCaptureSummary, writer: anytype) !void {
        try writer.writeAll("{\"kind\":\"route_capture_summary\",");
        try app_render.writeJsonStringField(writer, "provider", self.options.provider.label(), true);
        try app_render.writeJsonIntField(writer, "limit", self.options.limit, true);
        try app_render.writeJsonIntField(writer, "loaded_capture_operation_status_rows", self.captures.items.len, true);
        try app_render.writeJsonStringField(writer, "evidence", route_capture_summary_evidence_note, true);
        try writer.writeAll("\"summary\":");
        try writeRouteCaptureSummaryTotalsJson(self.totals(), writer);
        try writer.writeAll(",\"families\":[");
        var visible: usize = 0;
        var omitted: usize = 0;
        const limit = evidence_common.displayLimit(self.options.limit, self.rows.len);
        var first = true;
        for (self.rows) |row| {
            if (visible >= limit) {
                omitted += 1;
                continue;
            }
            if (!first) try writer.writeByte(',');
            first = false;
            visible += 1;
            try writeRouteCaptureSummaryRowJson(row, writer);
        }
        try writer.writeAll("],");
        try app_render.writeJsonIntField(writer, "visible", visible, true);
        try app_render.writeJsonIntField(writer, "omitted", omitted, false);
        try writer.writeAll("}\n");
    }
};

pub fn writeRouteCapturesText(ctx: Context, options: RouteCaptureOptions, writer: anytype) !void {
    var captures = try RouteCaptures.load(ctx, options);
    defer captures.deinit(ctx.gpa);
    try captures.writeText(ctx.gpa, writer);
}

pub fn writeRouteCapturesJson(ctx: Context, options: RouteCaptureOptions, writer: anytype) !void {
    var captures = try RouteCaptures.load(ctx, options);
    defer captures.deinit(ctx.gpa);
    try captures.writeJson(ctx.gpa, writer);
}

pub fn writeRouteCoverageText(ctx: Context, options: RouteCoverageOptions, writer: anytype) !void {
    var coverage = try RouteCoverage.load(ctx, options);
    defer coverage.deinit(ctx.gpa);
    try coverage.writeText(ctx.gpa, writer);
}

pub fn writeRouteCoverageJson(ctx: Context, options: RouteCoverageOptions, writer: anytype) !void {
    var coverage = try RouteCoverage.load(ctx, options);
    defer coverage.deinit(ctx.gpa);
    try coverage.writeJson(ctx.gpa, writer);
}

pub fn writeRouteCaptureSummaryText(ctx: Context, options: RouteCaptureSummaryOptions, writer: anytype) !void {
    var summary = try RouteCaptureSummary.load(ctx, options);
    defer summary.deinit(ctx.gpa);
    try summary.writeText(writer);
}

pub fn writeRouteCaptureSummaryJson(ctx: Context, options: RouteCaptureSummaryOptions, writer: anytype) !void {
    var summary = try RouteCaptureSummary.load(ctx, options);
    defer summary.deinit(ctx.gpa);
    try summary.writeJson(writer);
}

fn writeRouteCaptureTotalsJson(summary: RouteCaptureTotals, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "operations", summary.operations, true);
    try app_render.writeJsonIntField(writer, "captures", summary.captures, true);
    try app_render.writeJsonIntField(writer, "cloudflare", summary.cloudflare, true);
    try app_render.writeJsonIntField(writer, "hostinger", summary.hostinger, true);
    try app_render.writeJsonIntField(writer, "ok", summary.ok, true);
    try app_render.writeJsonIntField(writer, "errors", summary.errors, false);
    try writer.writeByte('}');
}

fn writeRouteCoverageTotalsJson(summary: RouteCoverageTotals, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "official_operations", summary.official_operations, true);
    try app_render.writeJsonIntField(writer, "captured_operations", summary.captured_operations, true);
    try app_render.writeJsonIntField(writer, "captures", summary.captures, true);
    try app_render.writeJsonIntField(writer, "matched", summary.matched, true);
    try app_render.writeJsonIntField(writer, "missing", summary.missing, true);
    try app_render.writeJsonIntField(writer, "read", summary.read, true);
    try app_render.writeJsonIntField(writer, "dry_run", summary.dry_run, true);
    try app_render.writeJsonIntField(writer, "write", summary.write, true);
    try app_render.writeJsonIntField(writer, "deprecated", summary.deprecated, true);
    try app_render.writeJsonIntField(writer, "ok", summary.ok, true);
    try app_render.writeJsonIntField(writer, "errors", summary.errors, false);
    try writer.writeByte('}');
}

fn writeRouteCaptureSummaryTotalsJson(summary: RouteCaptureSummaryTotals, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonIntField(writer, "families", summary.families, true);
    try app_render.writeJsonIntField(writer, "official_read_routes", summary.official_read_routes, true);
    try app_render.writeJsonIntField(writer, "captured_read_routes", summary.captured_read_routes, true);
    try app_render.writeJsonIntField(writer, "evidence_covered_read_routes", summary.evidence_covered_read_routes, true);
    try app_render.writeJsonIntField(writer, "diagnostic_read_routes", summary.diagnostic_read_routes, true);
    try app_render.writeJsonIntField(writer, "ok_read_routes", summary.ok_read_routes, true);
    try app_render.writeJsonIntField(writer, "error_read_routes", summary.error_read_routes, true);
    try app_render.writeJsonIntField(writer, "missing_read_routes", summary.missing_read_routes, true);
    try app_render.writeJsonIntField(writer, "unresolved_read_routes", summary.unresolved_read_routes, true);
    try app_render.writeJsonIntField(writer, "capture_events", summary.capture_events, true);
    try app_render.writeJsonIntField(writer, "cloudflare_read_routes", summary.cloudflare_read_routes, true);
    try app_render.writeJsonIntField(writer, "hostinger_read_routes", summary.hostinger_read_routes, false);
    try writer.writeByte('}');
}

fn writeRouteCaptureJson(gpa: Allocator, row: db_store.RouteCaptureEvidenceRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "family", evidence_common.evidenceFamily(row.provider, row.operation_id), true);
    try app_render.writeJsonStringField(writer, "operation_id", row.operation_id, true);
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "status_class", evidence_common.statusClass(row.status), true);
    try evidence_common.writeRedactedJsonStringField(gpa, writer, "endpoint_sample", row.endpoint_sample, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_at", row.latest_at, false);
    try writer.writeByte('}');
}

fn writeRouteCoverageRowJson(gpa: Allocator, row: db_store.RouteCaptureEvidenceRow, route: ?*const provider_routes.Route, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "family", if (route) |matched| routeFamily(matched.*) else evidence_common.evidenceFamily(row.provider, row.operation_id), true);
    try app_render.writeJsonBoolField(writer, "matched", route != null, true);
    try app_render.writeJsonStringField(writer, "operation_id", row.operation_id, true);
    if (route) |matched| {
        try app_render.writeJsonStringField(writer, "tag", matched.tag, true);
        try app_render.writeJsonStringField(writer, "method", matched.method.name(), true);
        try app_render.writeJsonStringField(writer, "path_template", matched.path_template, true);
        try app_render.writeJsonStringField(writer, "support", @tagName(matched.support), true);
        try app_render.writeJsonStringField(writer, "mode", @tagName(matched.mode), true);
        try app_render.writeJsonStringField(writer, "tests", matched.tests, true);
        try app_render.writeJsonBoolField(writer, "deprecated", matched.deprecated, true);
        try app_render.writeJsonBoolField(writer, "routable", matched.isRoutable(), true);
    } else {
        try app_render.writeJsonStringField(writer, "tag", "", true);
        try app_render.writeJsonStringField(writer, "method", "", true);
        try app_render.writeJsonStringField(writer, "path_template", "", true);
        try app_render.writeJsonStringField(writer, "support", "unknown", true);
        try app_render.writeJsonStringField(writer, "mode", "unknown", true);
        try app_render.writeJsonStringField(writer, "tests", "unknown", true);
        try app_render.writeJsonBoolField(writer, "deprecated", false, true);
        try app_render.writeJsonBoolField(writer, "routable", false, true);
    }
    try app_render.writeJsonStringField(writer, "status", row.status, true);
    try app_render.writeJsonStringField(writer, "status_class", evidence_common.statusClass(row.status), true);
    try evidence_common.writeRedactedJsonStringField(gpa, writer, "endpoint_sample", row.endpoint_sample, true);
    try app_render.writeJsonIntField(writer, "count", row.count, true);
    try app_render.writeJsonStringField(writer, "latest_at", row.latest_at, false);
    try writer.writeByte('}');
}

fn writeRouteCaptureSummaryRowJson(row: RouteCaptureSummaryRow, writer: anytype) !void {
    try writer.writeByte('{');
    try app_render.writeJsonStringField(writer, "provider", row.provider, true);
    try app_render.writeJsonStringField(writer, "family", row.family, true);
    try app_render.writeJsonIntField(writer, "official_read_routes", row.official_read_routes, true);
    try app_render.writeJsonIntField(writer, "captured_read_routes", row.captured_read_routes, true);
    try app_render.writeJsonIntField(writer, "evidence_covered_read_routes", row.evidence_covered_read_routes, true);
    try app_render.writeJsonIntField(writer, "diagnostic_read_routes", row.diagnostic_read_routes, true);
    try app_render.writeJsonIntField(writer, "ok_read_routes", row.ok_read_routes, true);
    try app_render.writeJsonIntField(writer, "error_read_routes", row.error_read_routes, true);
    try app_render.writeJsonIntField(writer, "missing_read_routes", row.missing_read_routes, true);
    try app_render.writeJsonIntField(writer, "unresolved_read_routes", row.unresolved_read_routes, true);
    try app_render.writeJsonIntField(writer, "captured_percent", row.capturedPercent(), true);
    try app_render.writeJsonIntField(writer, "capture_events", row.capture_events, true);
    try app_render.writeJsonStringField(writer, "latest_at", row.latest_at, true);
    try app_render.writeJsonStringField(writer, "sample_missing_operation", row.sample_missing_operation, true);
    try app_render.writeJsonStringField(writer, "sample_unresolved_operation", row.sample_unresolved_operation, false);
    try writer.writeByte('}');
}

fn buildRouteCaptureSummaryRows(gpa: Allocator, routes: []const provider_routes.Route, captures: []const db_store.RouteCaptureEvidenceRow) ![]RouteCaptureSummaryRow {
    var rows = std.ArrayList(RouteCaptureSummaryRow).empty;
    errdefer rows.deinit(gpa);
    for (routes) |route| {
        if (!routeCountsForCaptureSummary(route)) continue;
        const operation_id = route.operation_id orelse continue;
        const provider = route.provider.name();
        const family = routeFamily(route);
        const row = try routeCaptureSummaryRow(gpa, &rows, provider, family);
        row.official_read_routes += 1;
        const status = routeCaptureStatus(provider, operation_id, captures);
        if (status.any) {
            row.captured_read_routes += 1;
            row.capture_events += status.events;
            if (status.ok) row.ok_read_routes += 1;
            if (status.err) row.error_read_routes += 1;
            if (status.latest_at.len != 0 and latestAtLessThan(row.latest_at, status.latest_at)) row.latest_at = status.latest_at;
        } else {
            row.missing_read_routes += 1;
            if (row.sample_missing_operation.len == 0) row.sample_missing_operation = operation_id;
            if (routeHasReadCoverageEvidence(route)) {
                row.evidence_covered_read_routes += 1;
                if (route.support == .blocked_permission) row.diagnostic_read_routes += 1;
            } else {
                row.unresolved_read_routes += 1;
                if (row.sample_unresolved_operation.len == 0) row.sample_unresolved_operation = operation_id;
            }
        }
    }
    std.mem.sort(RouteCaptureSummaryRow, rows.items, {}, routeCaptureSummaryLessThan);
    return try rows.toOwnedSlice(gpa);
}

fn routeCountsForCaptureSummary(route: provider_routes.Route) bool {
    return route.mode == .read and route.isRoutable() and route.operation_id != null;
}

fn routeHasReadCoverageEvidence(route: provider_routes.Route) bool {
    if (!hasCoverageEvidence(route.tests)) return false;
    return route.support == .partial or route.support == .blocked_permission;
}

fn hasCoverageEvidence(tests: []const u8) bool {
    return tests.len != 0 and !std.mem.eql(u8, tests, "missing");
}

fn routeCaptureSummaryRow(gpa: Allocator, rows: *std.ArrayList(RouteCaptureSummaryRow), provider: []const u8, family: []const u8) !*RouteCaptureSummaryRow {
    for (rows.items) |*row| {
        if (std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.family, family)) return row;
    }
    try rows.append(gpa, .{ .provider = provider, .family = family });
    return &rows.items[rows.items.len - 1];
}

const RouteCaptureStatus = struct {
    any: bool = false,
    ok: bool = false,
    err: bool = false,
    events: i64 = 0,
    latest_at: []const u8 = "",
};

fn routeCaptureStatus(provider: []const u8, operation_id: []const u8, captures: []const db_store.RouteCaptureEvidenceRow) RouteCaptureStatus {
    var out = RouteCaptureStatus{};
    for (captures) |capture| {
        if (!std.mem.eql(u8, capture.provider, provider)) continue;
        if (!std.mem.eql(u8, capture.operation_id, operation_id)) continue;
        out.any = true;
        out.events += capture.count;
        if (evidence_common.statusIsOk(capture.status)) out.ok = true;
        if (evidence_common.statusIsError(capture.status)) out.err = true;
        if (capture.latest_at.len != 0 and latestAtLessThan(out.latest_at, capture.latest_at)) out.latest_at = capture.latest_at;
    }
    return out;
}

fn routeFamily(route: provider_routes.Route) []const u8 {
    const tag_family = evidence_common.evidenceFamily(route.provider.name(), route.tag);
    if (!std.mem.startsWith(u8, tag_family, "other-")) return tag_family;
    if (route.operation_id) |operation_id| {
        const operation_family = evidence_common.evidenceFamily(route.provider.name(), operation_id);
        if (!std.mem.startsWith(u8, operation_family, "other-")) return operation_family;
    }
    return tag_family;
}

fn latestAtLessThan(current: []const u8, candidate: []const u8) bool {
    if (current.len == 0) return true;
    return std.mem.order(u8, current, candidate) == .lt;
}

fn routeCaptureSummaryLessThan(_: void, lhs: RouteCaptureSummaryRow, rhs: RouteCaptureSummaryRow) bool {
    if (lhs.unresolved_read_routes != rhs.unresolved_read_routes) return lhs.unresolved_read_routes > rhs.unresolved_read_routes;
    if (lhs.missing_read_routes != rhs.missing_read_routes) return lhs.missing_read_routes > rhs.missing_read_routes;
    if (lhs.evidence_covered_read_routes != rhs.evidence_covered_read_routes) return lhs.evidence_covered_read_routes > rhs.evidence_covered_read_routes;
    if (lhs.official_read_routes != rhs.official_read_routes) return lhs.official_read_routes > rhs.official_read_routes;
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, lhs.family, rhs.family) == .lt;
}

test "route evidence read models match generated routes and redact endpoints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio-app-evidence-routes.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try db_store.Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try db.insertAudit("route.capture", "ok", "hostinger/VPS_getVirtualMachinesV1 /api/vps/v1/virtual-machines?api_token=secret-value");
    try db.insertAudit("route.capture", "http_error", "cloudflare/accounts-list-accounts /accounts");

    const ctx = Context{ .io = std.testing.io, .gpa = allocator, .db = &db };
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

    var capture_summary = try RouteCaptureSummary.load(ctx, .{ .limit = 20 });
    defer capture_summary.deinit(allocator);
    const capture_summary_totals = capture_summary.totals();
    try std.testing.expect(capture_summary_totals.official_read_routes > capture_summary_totals.captured_read_routes);
    try std.testing.expect(capture_summary_totals.captured_read_routes >= 2);
    try std.testing.expect(capture_summary_totals.missing_read_routes > 0);
    try std.testing.expectEqual(
        capture_summary_totals.official_read_routes,
        capture_summary_totals.captured_read_routes + capture_summary_totals.evidence_covered_read_routes + capture_summary_totals.unresolved_read_routes,
    );
    var capture_summary_json_out = std.Io.Writer.Allocating.init(allocator);
    defer capture_summary_json_out.deinit();
    try capture_summary.writeJson(&capture_summary_json_out.writer);
    const capture_summary_json = try capture_summary_json_out.toOwnedSlice();
    defer allocator.free(capture_summary_json);
    var parsed_capture_summary = try std.json.parseFromSlice(std.json.Value, allocator, capture_summary_json, .{});
    defer parsed_capture_summary.deinit();
    try std.testing.expectEqualStrings("route_capture_summary", parsed_capture_summary.value.object.get("kind").?.string);
    try std.testing.expect(parsed_capture_summary.value.object.get("families").?.array.items.len > 0);
    try std.testing.expect(parsed_capture_summary.value.object.get("summary").?.object.get("missing_read_routes").?.integer > 0);
    try std.testing.expect(parsed_capture_summary.value.object.get("summary").?.object.get("evidence_covered_read_routes").?.integer > 0);
    try std.testing.expect(parsed_capture_summary.value.object.get("summary").?.object.get("unresolved_read_routes").?.integer >= 0);
}
