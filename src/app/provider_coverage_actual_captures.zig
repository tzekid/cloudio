const std = @import("std");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_actual_commands = @import("app_provider_coverage_actual_commands");
const app_provider_coverage_actual_inputs = @import("app_provider_coverage_actual_inputs");
const app_provider_coverage_actual_plan = @import("app_provider_coverage_actual_plan");
const app_provider_coverage_actual_ready = @import("app_provider_coverage_actual_ready");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const app_provider_route_capture = @import("app_provider_route_capture");
const core_json = @import("core_json");
const db_store = @import("db_store");
const provider_auth = @import("provider_auth");
const provider_capabilities = @import("provider_capabilities");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableBoolField = app_provider_coverage_render.writeJsonNullableBoolField;
const writeJsonNullableCountField = app_provider_coverage_render.writeJsonNullableCountField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

const default_capture_max_pages = 25;

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;
pub const Auth = provider_auth.Auth;
pub const CaptureOptions = app_provider_route_capture.CaptureOptions;

const ActualCaptureState = app_provider_coverage_actual_inputs.CaptureState;
const ActualCaptureSourceSummary = app_provider_coverage_actual_inputs.SourceSummary;
const ActualCaptureHints = app_provider_coverage_actual_inputs.Hints;
const ActualCaptureInputSource = app_provider_coverage_actual_inputs.InputSource;
const ActualCaptureSourceBodyEvidence = app_provider_coverage_actual_inputs.SourceBodyEvidence;
pub const ActualCaptureOptions = app_provider_coverage_actual_plan.ActualCaptureOptions;
pub const ActualCaptureFocus = app_provider_coverage_actual_plan.ActualCaptureFocus;
const ActualCapturePlan = app_provider_coverage_actual_plan.ActualCapturePlan;
const ActualCaptureTotals = app_provider_coverage_actual_plan.ActualCaptureTotals;
const ActualCaptureCandidateRank = app_provider_coverage_actual_plan.ActualCaptureCandidateRank;
const loadActualCapturePlanFromFiles = app_provider_coverage_actual_plan.loadActualCapturePlanFromFiles;
const loadActualCapturePlanFromText = app_provider_coverage_actual_plan.loadActualCapturePlanFromText;

const actualCaptureRouteFilter = app_provider_coverage_actual_inputs.actualCaptureRouteFilter;
const actualCaptureState = app_provider_coverage_actual_inputs.actualCaptureState;
const actualRouteCaptureStatus = app_provider_coverage_actual_inputs.actualRouteCaptureStatus;
const actualCaptureReady = app_provider_coverage_actual_inputs.actualCaptureReady;
const actualCaptureReadyWithPolicy = app_provider_coverage_actual_inputs.actualCaptureReadyWithPolicy;
const actualCaptureUsesDiagnosticRead = app_provider_coverage_actual_inputs.actualCaptureUsesDiagnosticRead;
const actualCaptureMissingInputCount = app_provider_coverage_actual_inputs.actualCaptureMissingInputCount;
const actualCapturePathParamHint = app_provider_coverage_actual_inputs.actualCapturePathParamHint;
const actualCaptureHasQueryParamHint = app_provider_coverage_actual_inputs.actualCaptureHasQueryParamHint;
const actualCaptureQueryParamHint = app_provider_coverage_actual_inputs.actualCaptureQueryParamHint;
const actualCaptureMissingInputSources = app_provider_coverage_actual_inputs.actualCaptureMissingInputSources;
const actualCaptureFindRouteByOperationId = app_provider_coverage_actual_inputs.actualCaptureFindRouteByOperationId;
const actualCaptureUnmappedSourceResult = app_provider_coverage_actual_inputs.actualCaptureUnmappedSourceResult;
const actualCaptureUnmappedSourceNextAction = app_provider_coverage_actual_inputs.actualCaptureUnmappedSourceNextAction;
const actualCaptureUnmappedSourcePurpose = app_provider_coverage_actual_inputs.actualCaptureUnmappedSourcePurpose;
const actualCaptureFindSourceEvidence = app_provider_coverage_actual_inputs.actualCaptureFindSourceEvidence;
const actualCaptureSourceBodyEvidence = app_provider_coverage_actual_inputs.actualCaptureSourceBodyEvidence;
const actualCaptureSourceResult = app_provider_coverage_actual_inputs.actualCaptureSourceResult;
const actualCaptureSourceNextAction = app_provider_coverage_actual_inputs.actualCaptureSourceNextAction;
const actualCaptureSourceHintCount = app_provider_coverage_actual_inputs.actualCaptureSourceHintCount;
const actualCaptureCommand = app_provider_coverage_actual_commands.actualCaptureCommand;

pub const ActualReadyCaptureOptions = app_provider_coverage_actual_ready.ActualReadyCaptureOptions;

fn writeActualCapturePlanText(plan: ActualCapturePlan, gpa: Allocator, writer: anytype) !void {
    const totals_value = plan.totals();
    const source_summary = try plan.sourceSummary(gpa);
    var order = try plan.candidateOrder(gpa);
    defer order.deinit(gpa);
    try writer.writeAll("Cloudio actual route capture plan\n");
    try writer.writeAll("rank: family static read gaps, ready capture inputs, then official GET/read routes missing an OK route.capture audit event\n");
    try writer.print("filter provider={s} focus={s}", .{ plan.options.filter.provider.name(), plan.options.focus.name() });
    if (plan.options.filter.tag_query) |query| try writer.print(" tag_query={s}", .{query});
    if (plan.options.filter.family != .all) try writer.print(" family={s}", .{plan.options.filter.family.name()});
    if (plan.options.filter.support) |support| try writer.print(" support={s}", .{support.name()});
    if (plan.options.include_plans) try writer.writeAll(" plans=true");
    try writer.writeAll(" limit=");
    if (plan.options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{plan.options.limit});
    }
    try writer.print("loaded_capture_operation_status_rows={d} loaded_source_evidence_rows={d} configured_domain_hints={d} cloudflare_account_hints={d} cloudflare_zone_hints={d} cloudflare_resource_hints={d} cloudflare_inventory_hints={d} hostinger_vps_hints={d} hostinger_resource_hints={d} hostinger_inventory_hints={d}\n", .{ plan.captures.items.len, plan.source_evidence.items.len, plan.options.configured_domains.len, plan.cloudflareAccountRows().len, plan.cloudflareZoneRows().len, plan.cloudflareResourceRows().len, plan.cloudflareInventoryRows().len, plan.hostingerVpsRows().len, plan.hostingerResourceRows().len, plan.hostingerInventoryRows().len });
    try writer.print("summary official_read_routes={d} ok_read_routes={d} non_ok_read_routes={d} missing_read_routes={d} candidate_routes={d} ready_candidates={d} capture_events={d}\n", .{
        totals_value.official_read_routes,
        totals_value.ok_read_routes,
        totals_value.non_ok_read_routes,
        totals_value.missing_read_routes,
        totals_value.candidate_routes,
        totals_value.ready_candidates,
        totals_value.capture_events,
    });
    try writer.print("source_summary total={d} captured_with_hints={d} captured_empty={d} captured_without_hints={d} captured_unknown_body={d} ready_to_capture={d} waiting_for_inputs={d} diagnostic_blocked={d} captured_error={d} no_official_source={d} not_in_catalog={d} unmapped={d} not_eligible={d} body_array={d} body_data_array={d} body_error_object={d} body_no_evidence={d} body_other={d}\n", .{
        source_summary.total_sources,
        source_summary.captured_with_hints,
        source_summary.captured_empty,
        source_summary.captured_without_hints,
        source_summary.captured_unknown_body,
        source_summary.ready_to_capture,
        source_summary.waiting_for_inputs,
        source_summary.diagnostic_blocked,
        source_summary.captured_error,
        source_summary.no_official_source,
        source_summary.not_in_catalog,
        source_summary.unmapped,
        source_summary.not_eligible,
        source_summary.body_array,
        source_summary.body_data_array,
        source_summary.body_error_object,
        source_summary.body_no_evidence,
        source_summary.body_other,
    });

    var visible: usize = 0;
    var omitted: usize = 0;
    var current_provider: ?[]const u8 = null;
    var current_tag: ?[]const u8 = null;
    const hints_value = plan.hints();
    for (order.items) |rank| {
        const row = plan.routes.items[rank.route_index];
        const state = rank.state;
        if (plan.options.limit != 0 and visible >= plan.options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        const provider_name = row.route.provider.name();
        if (current_provider == null or !std.mem.eql(u8, current_provider.?, provider_name)) {
            current_provider = provider_name;
            current_tag = null;
            try writer.print("\n{s}\n", .{provider_name});
        }
        if (current_tag == null or !std.mem.eql(u8, current_tag.?, row.route.tag)) {
            current_tag = row.route.tag;
            try writer.print("  {s}\n", .{row.route.tag});
        }
        const route_status = actualRouteCaptureStatus(provider_name, row.route.operation_id.?, plan.captures.items);
        const review = try actualCaptureCandidateReview(gpa, row.route, state, plan.source_routes.items, plan.captures.items, plan.source_evidence.items, hints_value);
        try writer.print("    {s} {s} | state={s} review={s} support={s} op={s} events={d} family_priority={d} family_pending_read_gaps={d} family_ready={d}/{d}", .{
            row.route.method.name(),
            row.route.path_template,
            state.name(),
            review.status,
            @tagName(row.route.support),
            row.route.operation_id.?,
            route_status.events,
            rank.familyPriority(),
            rank.family_pending_read_gaps,
            rank.family_ready_candidates,
            rank.family_candidate_routes,
        });
        if (route_status.latest_at.len != 0) try writer.print(" latest={s}", .{route_status.latest_at});
        try writer.writeByte('\n');
        try writer.writeAll("      required_path=");
        try writeRequiredParamNamesText(writer, row.route.path_params);
        try writer.writeAll(" required_query=");
        try writeRequiredParamNamesText(writer, row.route.query_params);
        try writer.writeAll(" required_header=");
        try writeRequiredParamNamesText(writer, row.route.header_params);
        try writer.print(" pagination={s}\n", .{routePaginationKind(row.route) orelse "none"});
        try writer.print("      ready={s} live_read_supported={s} missing_inputs=", .{
            if (actualCaptureReady(row.route, hints_value)) "true" else "false",
            if (provider_capabilities.routeLiveReadSupported(row.route)) "true" else "false",
        });
        try writeActualMissingInputsText(writer, row.route, hints_value);
        try writer.writeByte('\n');
        try writer.print("      next: {s}\n", .{review.next_action});
        if (actualCaptureMissingInputCount(row.route, hints_value) != 0) {
            try writeActualMissingInputSourcesText(gpa, writer, row.route, plan.source_routes.items, plan.captures.items, plan.source_evidence.items, hints_value);
        }
        const command = try actualCaptureCommand(gpa, row.route, hints_value);
        defer gpa.free(command);
        try writer.print("      capture: {s}\n", .{command});
        if (plan.options.include_plans) {
            const route_plan = try routeReadPlanJson(gpa, row.route);
            defer gpa.free(route_plan);
            try writer.print("      read-plan: {s}\n", .{route_plan});
        }
    }

    if (totals_value.candidate_routes == 0) {
        try writer.writeAll("no actual capture gaps for filter\n");
    } else if (omitted != 0) {
        try writer.print("omitted={d}\n", .{omitted});
    }
}

fn writeActualCapturePlanJson(plan: ActualCapturePlan, gpa: Allocator, writer: anytype) !void {
    const totals_value = plan.totals();
    const source_summary = try plan.sourceSummary(gpa);
    var order = try plan.candidateOrder(gpa);
    defer order.deinit(gpa);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_actual_captures", true);
    try writer.writeAll("\"filter\":");
    try writeRouteFilterJson(actualCaptureRouteFilter(plan.options.filter), writer);
    try writer.writeByte(',');
    try writeJsonField(writer, "focus", plan.options.focus.name(), true);
    try writeJsonCountField(writer, "limit", plan.options.limit, true);
    try writeJsonBoolField(writer, "include_plans", plan.options.include_plans, true);
    try writeJsonField(writer, "rank", "family static read gaps, ready capture inputs, then official GET/read routes missing an OK route.capture audit event", true);
    try writeJsonCountField(writer, "loaded_capture_operation_status_rows", plan.captures.items.len, true);
    try writeJsonCountField(writer, "loaded_source_evidence_rows", plan.source_evidence.items.len, true);
    try writeJsonCountField(writer, "configured_domain_hints", plan.options.configured_domains.len, true);
    try writeJsonCountField(writer, "cloudflare_account_hints", plan.cloudflareAccountRows().len, true);
    try writeJsonCountField(writer, "cloudflare_zone_hints", plan.cloudflareZoneRows().len, true);
    try writeJsonCountField(writer, "cloudflare_resource_hints", plan.cloudflareResourceRows().len, true);
    try writeJsonCountField(writer, "cloudflare_inventory_hints", plan.cloudflareInventoryRows().len, true);
    try writeJsonCountField(writer, "hostinger_vps_hints", plan.hostingerVpsRows().len, true);
    try writeJsonCountField(writer, "hostinger_resource_hints", plan.hostingerResourceRows().len, true);
    try writeJsonCountField(writer, "hostinger_inventory_hints", plan.hostingerInventoryRows().len, true);
    try writer.writeAll("\"summary\":");
    try writeActualCaptureTotalsJson(totals_value, writer);
    try writer.writeAll(",\"source_summary\":");
    try writeActualCaptureSourceSummaryJson(source_summary, writer);
    try writer.writeAll(",\"candidates\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var first = true;
    const hints_value = plan.hints();
    for (order.items) |rank| {
        const row = plan.routes.items[rank.route_index];
        const state = rank.state;
        if (plan.options.limit != 0 and visible >= plan.options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeActualCaptureCandidateJson(gpa, row, state, rank, plan.source_routes.items, plan.captures.items, plan.source_evidence.items, hints_value, plan.options, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

pub fn writeActualCapturesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, options);
    defer plan.deinit(gpa);
    try writeActualCapturePlanText(plan, gpa, writer);
}

pub fn writeActualCapturesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromFiles(io, gpa, paths, db, options);
    defer plan.deinit(gpa);
    try writeActualCapturePlanJson(plan, gpa, writer);
}

pub fn writeActualCapturesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, options);
    defer plan.deinit(gpa);
    try writeActualCapturePlanText(plan, gpa, writer);
}

pub fn writeActualCapturesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    var plan = try loadActualCapturePlanFromText(gpa, cloudflare_text, hostinger_text, db, options);
    defer plan.deinit(gpa);
    try writeActualCapturePlanJson(plan, gpa, writer);
}

pub fn actualReadyCaptureJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    return try app_provider_coverage_actual_ready.actualReadyCaptureJsonFromFiles(io, gpa, paths, db, auth, options);
}

pub fn actualReadyCaptureJsonFromText(io: Io, gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    return try app_provider_coverage_actual_ready.actualReadyCaptureJsonFromText(io, gpa, cloudflare_text, hostinger_text, db, auth, options);
}

fn writeActualMissingInputsText(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    var wrote = false;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("path:{s}", .{param.name});
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("query:{s}", .{param.name});
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.print("header:{s}", .{param.name});
    }
    if (!wrote) try writer.writeAll("-");
}

fn writeActualMissingInputsJson(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    try writer.writeByte('[');
    var first = true;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "path", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "query", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeMaybeJsonComma(writer, &first);
        try writer.writeByte('{');
        try writeJsonField(writer, "source", "header", true);
        try writeJsonField(writer, "name", param.name, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeActualMissingInputSourcesText(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !void {
    var wrote = false;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "path", param.name, &wrote);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "query", param.name, &wrote);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeActualMissingInputSourceRowsText(gpa, writer, route, routes, captures, source_evidence, hints, "header", param.name, &wrote);
    }
    if (!wrote) try writer.writeAll("      source: -\n");
}

fn writeActualMissingInputSourceRowsText(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    wrote: *bool,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        wrote.* = true;
        const result = actualCaptureUnmappedSourceResult(route, input_source, input_name);
        try writer.print("      source: {s}:{s} <- {s} result={s} evidence=no_evidence items=- bytes=0 next=\"{s}\" purpose=", .{
            input_source,
            input_name,
            result,
            result,
            actualCaptureUnmappedSourceNextAction(route, input_source, input_name),
        });
        try writer.writeAll(actualCaptureUnmappedSourcePurpose(route, input_source, input_name));
        try writer.writeByte('\n');
        return;
    }
    for (sources) |source| {
        wrote.* = true;
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        if (source_route) |found| {
            const source_state = actualCaptureState(found, captures);
            const command = try actualCaptureCommand(gpa, found, hints);
            defer gpa.free(command);
            const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
            const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
            const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
            try writer.print("      source: {s}:{s} <- {s} state={s} result={s} ready={s} diagnostic_ready={s} hint_count={d} evidence={s} items=", .{
                input_source,
                input_name,
                source.operation_id,
                if (source_state) |state| state.name() else "unknown",
                actualCaptureSourceResult(found, source_state, hints, hint_count, body),
                if (actualCaptureReady(found, hints)) "true" else "false",
                if (actualCaptureReadyWithPolicy(found, hints, true)) "true" else "false",
                hint_count,
                body.shape,
            });
            if (body.item_count) |count| try writer.print("{d}", .{count}) else try writer.writeAll("-");
            try writer.print(" bytes={d} next=\"{s}\" capture: {s}\n", .{
                body.body_bytes,
                actualCaptureSourceNextAction(found, source_state, hints, hint_count, body),
                command,
            });
        } else {
            const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
            const body = ActualCaptureSourceBodyEvidence{};
            try writer.print("      source: {s}:{s} <- {s} state=not_in_catalog result=not_in_catalog hint_kind={s} hint_count={d} evidence={s} items=- bytes=0 next=\"{s}\" purpose=", .{
                input_source,
                input_name,
                source.operation_id,
                source.hint_kind,
                hint_count,
                body.shape,
                actualCaptureSourceNextAction(null, null, hints, hint_count, body),
            });
            try writer.writeAll(source.purpose);
            try writer.writeByte('\n');
        }
    }
}

fn writeActualMissingInputSourcesJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !void {
    try writer.writeByte('[');
    var first = true;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "path", param.name, &first);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "query", param.name, &first);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try writeActualMissingInputSourceRowsJson(gpa, writer, route, routes, captures, source_evidence, hints, "header", param.name, &first);
    }
    try writer.writeByte(']');
}

fn writeActualMissingInputSourceRowsJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    first: *bool,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        const result = actualCaptureUnmappedSourceResult(route, input_source, input_name);
        try writeMaybeJsonComma(writer, first);
        try writer.writeByte('{');
        try writeJsonField(writer, "input_source", input_source, true);
        try writeJsonField(writer, "input_name", input_name, true);
        try writeJsonNullableStringField(writer, "source_operation_id", null, true);
        try writeJsonNullableStringField(writer, "hint_kind", null, true);
        try writeJsonCountField(writer, "hint_count", 0, true);
        try writeJsonField(writer, "result", result, true);
        try writeJsonField(writer, "next_action", actualCaptureUnmappedSourceNextAction(route, input_source, input_name), true);
        try writeJsonNullableStringField(writer, "source_status", null, true);
        try writeJsonNullableStringField(writer, "source_target", null, true);
        try writeJsonNullableStringField(writer, "source_captured_at", null, true);
        try writeJsonField(writer, "body_shape", "no_evidence", true);
        try writeJsonNullableCountField(writer, "body_item_count", null, true);
        try writeJsonCountField(writer, "body_bytes", 0, true);
        try writeJsonField(writer, "purpose", actualCaptureUnmappedSourcePurpose(route, input_source, input_name), true);
        try writeJsonField(writer, "catalog_state", result, true);
        try writeJsonNullableStringField(writer, "actual_state", null, true);
        try writeJsonNullableBoolField(writer, "ready", null, true);
        try writeJsonNullableBoolField(writer, "diagnostic_ready", null, true);
        try writeJsonNullableBoolField(writer, "live_read_supported", null, true);
        try writeJsonNullableBoolField(writer, "diagnostic_read_supported", null, true);
        try writeJsonNullableStringField(writer, "capture_command", null, false);
        try writer.writeByte('}');
        return;
    }

    for (sources) |source| {
        try writeMaybeJsonComma(writer, first);
        try writeActualMissingInputSourceJson(gpa, writer, route, routes, captures, source_evidence, hints, input_source, input_name, source);
    }
}

fn writeActualMissingInputSourceJson(
    gpa: Allocator,
    writer: anytype,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    source: ActualCaptureInputSource,
) !void {
    const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
    var command: ?[]u8 = null;
    defer if (command) |owned| gpa.free(owned);
    if (source_route) |found| command = try actualCaptureCommand(gpa, found, hints);
    const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
    const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
    const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
    const body = try actualCaptureSourceBodyEvidence(gpa, evidence);

    try writer.writeByte('{');
    try writeJsonField(writer, "input_source", input_source, true);
    try writeJsonField(writer, "input_name", input_name, true);
    try writeJsonNullableStringField(writer, "source_operation_id", source.operation_id, true);
    try writeJsonNullableStringField(writer, "hint_kind", source.hint_kind, true);
    try writeJsonCountField(writer, "hint_count", hint_count, true);
    try writeJsonField(writer, "result", actualCaptureSourceResult(source_route, source_state, hints, hint_count, body), true);
    try writeJsonField(writer, "next_action", actualCaptureSourceNextAction(source_route, source_state, hints, hint_count, body), true);
    try writeJsonNullableStringField(writer, "source_status", if (evidence) |row| row.status else null, true);
    try writeJsonNullableStringField(writer, "source_target", if (evidence) |row| row.target else null, true);
    try writeJsonNullableStringField(writer, "source_captured_at", if (evidence) |row| row.captured_at else null, true);
    try writeJsonField(writer, "body_shape", body.shape, true);
    try writeJsonNullableCountField(writer, "body_item_count", body.item_count, true);
    try writeJsonCountField(writer, "body_bytes", body.body_bytes, true);
    try writeJsonField(writer, "purpose", source.purpose, true);
    try writeJsonField(writer, "catalog_state", if (source_route != null) "present" else "not_in_catalog", true);
    try writeJsonNullableStringField(writer, "actual_state", if (source_state) |state| state.name() else null, true);
    try writeJsonNullableBoolField(writer, "ready", if (source_route) |found| actualCaptureReady(found, hints) else null, true);
    try writeJsonNullableBoolField(writer, "diagnostic_ready", if (source_route) |found| actualCaptureReadyWithPolicy(found, hints, true) else null, true);
    try writeJsonNullableBoolField(writer, "live_read_supported", if (source_route) |found| provider_capabilities.routeLiveReadSupported(found) else null, true);
    try writeJsonNullableBoolField(writer, "diagnostic_read_supported", if (source_route) |found| provider_capabilities.routeDiagnosticReadSupported(found) else null, true);
    try writeJsonNullableStringField(writer, "capture_command", command, false);
    try writer.writeByte('}');
}

fn writeActualCaptureTotalsJson(totals_value: ActualCaptureTotals, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "official_read_routes", totals_value.official_read_routes, true);
    try writeJsonCountField(writer, "ok_read_routes", totals_value.ok_read_routes, true);
    try writeJsonCountField(writer, "non_ok_read_routes", totals_value.non_ok_read_routes, true);
    try writeJsonCountField(writer, "missing_read_routes", totals_value.missing_read_routes, true);
    try writeJsonCountField(writer, "candidate_routes", totals_value.candidate_routes, true);
    try writeJsonCountField(writer, "ready_candidates", totals_value.ready_candidates, true);
    try core_json.writeString(writer, "capture_events");
    try writer.print(":{d}", .{totals_value.capture_events});
    try writer.writeByte('}');
}

fn writeActualCaptureSourceSummaryJson(summary: ActualCaptureSourceSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "total_sources", summary.total_sources, true);
    try writeJsonCountField(writer, "captured_with_hints", summary.captured_with_hints, true);
    try writeJsonCountField(writer, "captured_empty", summary.captured_empty, true);
    try writeJsonCountField(writer, "captured_without_hints", summary.captured_without_hints, true);
    try writeJsonCountField(writer, "captured_unknown_body", summary.captured_unknown_body, true);
    try writeJsonCountField(writer, "ready_to_capture", summary.ready_to_capture, true);
    try writeJsonCountField(writer, "waiting_for_inputs", summary.waiting_for_inputs, true);
    try writeJsonCountField(writer, "diagnostic_blocked", summary.diagnostic_blocked, true);
    try writeJsonCountField(writer, "captured_error", summary.captured_error, true);
    try writeJsonCountField(writer, "no_official_source", summary.no_official_source, true);
    try writeJsonCountField(writer, "not_in_catalog", summary.not_in_catalog, true);
    try writeJsonCountField(writer, "unmapped", summary.unmapped, true);
    try writeJsonCountField(writer, "not_eligible", summary.not_eligible, true);
    try writer.writeAll("\"body_shapes\":{");
    try writeJsonCountField(writer, "array", summary.body_array, true);
    try writeJsonCountField(writer, "data_array", summary.body_data_array, true);
    try writeJsonCountField(writer, "error_object", summary.body_error_object, true);
    try writeJsonCountField(writer, "no_evidence", summary.body_no_evidence, true);
    try writeJsonCountField(writer, "other", summary.body_other, false);
    try writer.writeAll("}}");
}

fn writeActualCaptureCandidateJson(
    gpa: Allocator,
    row: CoverageRoute,
    state: ActualCaptureState,
    rank: ActualCaptureCandidateRank,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    options: ActualCaptureOptions,
    writer: anytype,
) !void {
    const route = row.route;
    const command = try actualCaptureCommand(gpa, route, hints);
    defer gpa.free(command);
    const status = actualRouteCaptureStatus(route.provider.name(), route.operation_id.?, captures);
    const review = try actualCaptureCandidateReview(gpa, route, state, routes, captures, source_evidence, hints);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", route.provider.name(), true);
    try writeJsonField(writer, "tag", route.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (app_provider_coverage_routes.tagFamily(route.provider.name(), route.tag)) |family| family.name() else null, true);
    try writeJsonCountField(writer, "family_priority", rank.familyPriority(), true);
    try writeJsonCountField(writer, "family_candidate_routes", rank.family_candidate_routes, true);
    try writeJsonCountField(writer, "family_ready_candidates", rank.family_ready_candidates, true);
    try writeJsonCountField(writer, "family_pending_read_gaps", rank.family_pending_read_gaps, true);
    try writeJsonCountField(writer, "family_missing_tests", rank.family_missing_tests, true);
    try writeJsonField(writer, "method", route.method.name(), true);
    try writeJsonField(writer, "path_template", route.path_template, true);
    try writeJsonField(writer, "operation_id", route.operation_id.?, true);
    try writeJsonField(writer, "support", @tagName(route.support), true);
    try writeJsonField(writer, "actual_state", state.name(), true);
    try writeJsonField(writer, "review_status", review.status, true);
    try writeJsonField(writer, "next_action", review.next_action, true);
    try writeJsonCountField(writer, "capture_events", @intCast(@max(status.events, 0)), true);
    try writeJsonNullableStringField(writer, "latest_capture_at", if (status.latest_at.len == 0) null else status.latest_at, true);
    try writeJsonNullableStringField(writer, "pagination", routePaginationKind(route), true);
    try writer.writeAll("\"required_path_params\":");
    try writeRequiredParamNamesJson(writer, route.path_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_query_params\":");
    try writeRequiredParamNamesJson(writer, route.query_params);
    try writer.writeByte(',');
    try writer.writeAll("\"required_header_params\":");
    try writeRequiredParamNamesJson(writer, route.header_params);
    try writer.writeByte(',');
    try writeJsonBoolField(writer, "ready", actualCaptureReady(route, hints), true);
    try writeJsonBoolField(writer, "live_read_supported", provider_capabilities.routeLiveReadSupported(route), true);
    try writeJsonBoolField(writer, "diagnostic_read_supported", provider_capabilities.routeDiagnosticReadSupported(route), true);
    try writer.writeAll("\"missing_inputs\":");
    try writeActualMissingInputsJson(writer, route, hints);
    try writer.writeByte(',');
    try writer.writeAll("\"missing_input_sources\":");
    try writeActualMissingInputSourcesJson(gpa, writer, route, routes, captures, source_evidence, hints);
    try writer.writeByte(',');
    try writeJsonField(writer, "capture_command", command, options.include_plans);
    if (options.include_plans) {
        const plan = try routeReadPlanJson(gpa, route);
        defer gpa.free(plan);
        try writer.writeAll("\"read_plan\":");
        try writer.writeAll(plan);
    }
    try writer.writeByte('}');
}

const ActualCaptureCandidateReview = struct {
    status: []const u8,
    next_action: []const u8,
};

fn actualCaptureCandidateReview(
    gpa: Allocator,
    route: provider_routes.Route,
    state: ActualCaptureState,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !ActualCaptureCandidateReview {
    if (state == .ok) return .{
        .status = "captured",
        .next_action = "review existing OK capture evidence",
    };

    const ready = actualCaptureReady(route, hints);
    const diagnostic_ready = !ready and actualCaptureReadyWithPolicy(route, hints, true);
    const missing_inputs = actualCaptureMissingInputCount(route, hints);
    if (missing_inputs != 0) {
        return try actualCaptureMissingInputCandidateReview(gpa, route, routes, captures, source_evidence, hints);
    }

    switch (state) {
        .ok => unreachable,
        .missing => {
            if (ready) return .{
                .status = "ready_to_capture",
                .next_action = "run the capture command to collect this read route",
            };
            if (diagnostic_ready) return .{
                .status = "diagnostic_ready",
                .next_action = "run the diagnostic capture command to record blocked-permission evidence",
            };
            return .{
                .status = "blocked_by_policy",
                .next_action = "update route support policy or required inputs before capture",
            };
        },
        .non_ok => {
            if (!provider_capabilities.routeLiveReadSupported(route) and provider_capabilities.routeDiagnosticReadSupported(route)) {
                return .{
                    .status = "diagnostic_blocked",
                    .next_action = "review diagnostic capture evidence; live reads are disabled by support policy",
                };
            }
            if (ready) return .{
                .status = "retry_capture",
                .next_action = "rerun the capture command and inspect the previous non-OK provider response",
            };
            return .{
                .status = "capture_error",
                .next_action = "inspect existing route capture error evidence before retrying",
            };
        },
    }
}

fn actualCaptureMissingInputCandidateReview(
    gpa: Allocator,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
) !ActualCaptureCandidateReview {
    var fallback = ActualCaptureCandidateReview{
        .status = "waiting_for_inputs",
        .next_action = "capture or normalize the listed source routes to discover required identifiers",
    };
    var saw_source = false;

    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        if (try actualCaptureMissingInputSourceReview(gpa, route, routes, captures, source_evidence, hints, "path", param.name, &fallback, &saw_source)) |review| return review;
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        if (try actualCaptureMissingInputSourceReview(gpa, route, routes, captures, source_evidence, hints, "query", param.name, &fallback, &saw_source)) |review| return review;
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        if (try actualCaptureMissingInputSourceReview(gpa, route, routes, captures, source_evidence, hints, "header", param.name, &fallback, &saw_source)) |review| return review;
    }

    if (!saw_source) return .{
        .status = "no_source_mapping",
        .next_action = "add a source mapping for the required route parameter",
    };
    return fallback;
}

fn actualCaptureMissingInputSourceReview(
    gpa: Allocator,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: ActualCaptureHints,
    input_source: []const u8,
    input_name: []const u8,
    fallback: *ActualCaptureCandidateReview,
    saw_source: *bool,
) !?ActualCaptureCandidateReview {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) return null;
    saw_source.* = true;
    for (sources) |source| {
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
        const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
        const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
        const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
        const result = actualCaptureSourceResult(source_route, source_state, hints, hint_count, body);
        const next_action = actualCaptureSourceNextAction(source_route, source_state, hints, hint_count, body);
        const review = actualCaptureReviewFromSourceResult(result, next_action);
        if (actualCaptureSourceReviewIsImmediate(review.status)) return review;
        fallback.* = review;
    }
    return null;
}

fn actualCaptureReviewFromSourceResult(result: []const u8, next_action: []const u8) ActualCaptureCandidateReview {
    if (std.mem.eql(u8, result, "ready_to_capture")) return .{ .status = "source_ready", .next_action = next_action };
    if (std.mem.eql(u8, result, "captured_with_hints")) return .{ .status = "source_has_hints", .next_action = next_action };
    if (std.mem.eql(u8, result, "captured_empty")) return .{ .status = "blocked_empty_source", .next_action = next_action };
    if (std.mem.eql(u8, result, "captured_without_hints")) return .{ .status = "needs_source_normalization", .next_action = next_action };
    if (std.mem.eql(u8, result, "captured_unknown_body")) return .{ .status = "inspect_source_body", .next_action = next_action };
    if (std.mem.eql(u8, result, "diagnostic_blocked")) return .{ .status = "diagnostic_source_blocked", .next_action = next_action };
    if (std.mem.eql(u8, result, "captured_error")) return .{ .status = "source_capture_error", .next_action = next_action };
    if (std.mem.eql(u8, result, "not_in_catalog")) return .{ .status = "source_not_in_catalog", .next_action = next_action };
    if (std.mem.eql(u8, result, "not_eligible")) return .{ .status = "source_not_eligible", .next_action = next_action };
    return .{ .status = "waiting_for_inputs", .next_action = next_action };
}

fn actualCaptureSourceReviewIsImmediate(status: []const u8) bool {
    return std.mem.eql(u8, status, "source_ready") or
        std.mem.eql(u8, status, "blocked_empty_source") or
        std.mem.eql(u8, status, "needs_source_normalization") or
        std.mem.eql(u8, status, "inspect_source_body") or
        std.mem.eql(u8, status, "diagnostic_source_blocked") or
        std.mem.eql(u8, status, "source_capture_error") or
        std.mem.eql(u8, status, "source_not_in_catalog");
}

fn routeReadPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    return try app_provider_coverage_candidates.readPlanJson(gpa, route);
}

fn routePaginationKind(route: provider_routes.Route) ?[]const u8 {
    return provider_capabilities.routePaginationName(route);
}

fn writeRequiredParamNamesText(writer: anytype, params: []const provider_routes.RouteParam) !void {
    var wrote = false;
    for (params) |param| {
        if (!param.required) continue;
        if (wrote) try writer.writeByte(',');
        wrote = true;
        try writer.writeAll(param.name);
    }
    if (!wrote) try writer.writeAll("-");
}

fn writeRequiredParamNamesJson(writer: anytype, params: []const provider_routes.RouteParam) !void {
    try writer.writeByte('[');
    var first = true;
    for (params) |param| {
        if (!param.required) continue;
        try writeMaybeJsonComma(writer, &first);
        try core_json.writeString(writer, param.name);
    }
    try writer.writeByte(']');
}

fn writeRouteFilterJson(filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRouteFilterJson(filter, writer);
}

test "plans actual Hostinger VPS captures from audit evidence and DB hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-captures.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.insertAudit("route.capture", "ok", "hostinger/VPS_getVirtualMachinesV1 /api/vps/v1/virtual-machines");
    try db.insertAudit("route.capture", "http_error", "hostinger/VPS_getBackupsV1 /api/vps/v1/virtual-machines/12345/backups");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"already captured"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}","operation_id":"VPS_getVirtualMachineDetailsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"needs actual capture"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/backups","operation_id":"VPS_getBackupsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"error-only capture should retry"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires date range"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_actual_captures\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok_read_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"non_ok_read_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_read_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachinesV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getVirtualMachineDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"actual_state\":\"non_ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"review_status\":\"ready_to_capture\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"review_status\":\"retry_capture\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getVirtualMachineDetailsV1 --path-param virtualMachineId='12345'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId='12345' --query-param date_from='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "--query-param date_to='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_date_from") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_virtualMachineId") == null);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeActualCapturesTextFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 2,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio actual route capture plan\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "state=missing review=ready_to_capture support=partial op=VPS_getVirtualMachineDetailsV1 events=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "state=non_ok review=retry_capture support=partial op=VPS_getBackupsV1 events=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "next: rerun the capture command and inspect the previous non-OK provider response") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ready=true live_read_supported=true missing_inputs=-") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);
}

test "filters actual capture plans to control-plane families" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-focus.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Catalog Sync","method":"GET","path":"/accounts/{account_id}/catalog","operation_id":"catalog-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"non-control-plane provider metadata"}
        \\{"provider":"cloudflare","tag":"SSL Universal","method":"GET","path":"/zones/{zone_id}/ssl/universal/settings","operation_id":"universal-ssl-settings-for-a-zone-get-universal-ssl-settings","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"control-plane ssl"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"control-plane vps"}
        \\
    ;

    var control_out = std.Io.Writer.Allocating.init(allocator);
    defer control_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, hostinger, &db, .{
        .focus = .control_plane,
        .limit = 0,
    }, &control_out.writer);
    const control_json = try control_out.toOwnedSlice();
    defer allocator.free(control_json);
    try std.testing.expect(std.mem.indexOf(u8, control_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, control_json, "\"official_read_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, control_json, "\"focus_family\":\"ssl-tls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, control_json, "\"focus_family\":\"hostinger-vps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, control_json, "catalog-list") == null);

    var all_out = std.Io.Writer.Allocating.init(allocator);
    defer all_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, hostinger, &db, .{
        .focus = .all,
        .limit = 0,
    }, &all_out.writer);
    const all_json = try all_out.toOwnedSlice();
    defer allocator.free(all_json);
    try std.testing.expect(std.mem.indexOf(u8, all_json, "\"focus\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, all_json, "\"official_read_routes\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, all_json, "catalog-list") != null);
}

test "ranks actual captures by family coverage gaps before manifest order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-rank.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-1", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-1\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"low static priority but first in manifest"}
        \\{"provider":"cloudflare","tag":"SSL Universal","method":"GET","path":"/zones/{zone_id}/ssl/universal/settings","operation_id":"universal-ssl-settings-for-a-zone-get-universal-ssl-settings","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"high static read gap should rank first"}
        \\{"provider":"cloudflare","tag":"Access applications","method":"GET","path":"/accounts/{account_id}/access/apps","operation_id":"access-applications-list-access-applications","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ready capture but no static family gap"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .focus = .control_plane,
        .limit = 0,
        .configured_domains = &.{"plosca.ru"},
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);

    const ssl_index = std.mem.indexOf(u8, json, "\"operation_id\":\"universal-ssl-settings-for-a-zone-get-universal-ssl-settings\"") orelse return error.ExpectedSslCandidate;
    const accounts_index = std.mem.indexOf(u8, json, "\"operation_id\":\"accounts-list\"") orelse return error.ExpectedAccountsCandidate;
    const access_index = std.mem.indexOf(u8, json, "\"operation_id\":\"access-applications-list-access-applications\"") orelse return error.ExpectedAccessCandidate;
    try std.testing.expect(ssl_index < accounts_index);
    try std.testing.expect(ssl_index < access_index);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family_priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family_pending_read_gaps\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family_missing_tests\":1") != null);
}

test "ranks actual-ready capture plans with actual capture family order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-ready-rank.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-1", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-1\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"low static priority but first in manifest"}
        \\{"provider":"cloudflare","tag":"SSL Universal","method":"GET","path":"/zones/{zone_id}/ssl/universal/settings","operation_id":"universal-ssl-settings-for-a-zone-get-universal-ssl-settings","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"high static read gap should rank first"}
        \\{"provider":"cloudflare","tag":"Access applications","method":"GET","path":"/accounts/{account_id}/access/apps","operation_id":"access-applications-list-access-applications","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ready capture but no static family gap"}
        \\
    ;

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, cloudflare, "", &db, .{ .cloudflare = .{ .token = "test-token" } }, .{
        .filter = .{ .provider = .cloudflare },
        .focus = .control_plane,
        .limit = 0,
        .execute = false,
        .configured_domains = &.{"plosca.ru"},
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":3") != null);

    const ssl_index = std.mem.indexOf(u8, planned, "\"operation_id\":\"universal-ssl-settings-for-a-zone-get-universal-ssl-settings\"") orelse return error.ExpectedSslCandidate;
    const accounts_index = std.mem.indexOf(u8, planned, "\"operation_id\":\"accounts-list\"") orelse return error.ExpectedAccountsCandidate;
    const access_index = std.mem.indexOf(u8, planned, "\"operation_id\":\"access-applications-list-access-applications\"") orelse return error.ExpectedAccessCandidate;
    try std.testing.expect(ssl_index < accounts_index);
    try std.testing.expect(ssl_index < access_index);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"focus_family\":\"ssl-tls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"family_priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans derived Hostinger VPS detail captures from captured resource hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("12345", "srv12345.hstgr.cloud", "running", "76.13.130.170", "KVM 2", "{\"id\":12345}");
    try db.upsertHostingerResource("VPS_getActionsV1/99", "VPS_getActionsV1", "99", "VPS_getActionsV1", "backup_create", "success", null, "{\"id\":99}");
    try db.upsertHostingerResource("VPS_getTemplatesV1/1002", "VPS_getTemplatesV1", "1002", "VPS_getTemplatesV1", "Ubuntu 24.04", null, null, "{\"id\":1002}");
    try db.upsertHostingerResource("VPS_getFirewallListV1/55", "VPS_getFirewallListV1", "55", "VPS_getFirewallListV1", "default firewall", "active", null, "{\"id\":55}");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/actions/{actionId}","operation_id":"VPS_getActionDetailsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"actionId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/templates/{templateId}","operation_id":"VPS_getTemplateDetailsV1","path_params":[{"name":"templateId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/post-install-scripts/{postInstallScriptId}","operation_id":"VPS_getPostInstallScriptV1","path_params":[{"name":"postInstallScriptId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires script list resource"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"requires explicit date window"}
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/firewall/{firewallId}","operation_id":"VPS_getFirewallDetailsV1","path_params":[{"name":"firewallId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"detail read"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_vps_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getActionDetailsV1 --path-param virtualMachineId='12345' --path-param actionId='99'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getTemplateDetailsV1 --path-param templateId='1002'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getFirewallDetailsV1 --path-param firewallId='55'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId='12345' --query-param date_from='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_inputs\":[{\"source\":\"path\",\"name\":\"postInstallScriptId\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"review_status\":\"source_not_in_catalog\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"next_action\":\"update the route catalog or remove the stale hint mapping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_date_to") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger, .family = .hostinger_vps },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"skipped_unready\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"attempted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getActionDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getTemplateDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getFirewallDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getPostInstallScriptV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans blocked Hostinger diagnostic captures only when explicitly included" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-blocked-diagnostics.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");

    const hostinger =
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"live_read_supported\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"diagnostic_read_supported\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectListV1 --path-param virtualMachineId='1307809' --diagnostic") != null);

    const normal_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(normal_plan);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"include_blocked\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"ready_routes\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, normal_plan, "\"planned\":0") != null);

    const diagnostic_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
    });
    defer allocator.free(diagnostic_plan);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"include_blocked\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"planned\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"diagnostic_read\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "\"operation_id\":\"VPS_getProjectListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_plan, "test-token") == null);
}

test "filters Hostinger capture-ready runs to diagnostic reads only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-diagnostic-only.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const hostinger =
        \\{"provider":"hostinger","tag":"Domains: Portfolio","method":"GET","path":"/api/domains/v1/portfolio/{domain}","operation_id":"domains_getDomainDetailsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain detail"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    const mixed_plan = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(mixed_plan);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"skipped_non_diagnostic\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"planned\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"operation_id\":\"domains_getDomainDetailsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mixed_plan, "\"operation_id\":\"reach_listProfilesV1\"") != null);

    const diagnostic_only = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .include_blocked = true,
        .diagnostic_only = true,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(diagnostic_only);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"diagnostic_only\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"candidate_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"ready_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"skipped_non_diagnostic\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"planned\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "\"operation_id\":\"domains_getDomainDetailsV1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic_only, "test-token") == null);
}

test "plans Cloudflare account and zone captures from configured scope hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-scope-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-other", "sparkdate.love", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-other\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts Logs Audit","method":"GET","path":"/accounts/{account_id}/logs/audit","operation_id":"audit-logs-get-account-audit-logs","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account scoped"}
        \\{"provider":"cloudflare","tag":"Custom pages for an account","method":"GET","path":"/accounts/{account_identifier}/custom_pages","operation_id":"custom-pages-for-an-account-list-custom-pages","path_params":[{"name":"account_identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account identifier spelling"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone scoped"}
        \\{"provider":"cloudflare","tag":"Zones Settings","method":"GET","path":"/zones/{zone_id}/settings","operation_id":"zone-settings-get-all","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone settings"}
        \\{"provider":"cloudflare","tag":"Cache Cache Reserve","method":"GET","path":"/zones/{zone_id}/cache/cache_reserve","operation_id":"cache-cache-reserve-get-cache-reserve-setting","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"cache setting"}
        \\{"provider":"cloudflare","tag":"SSL Universal","method":"GET","path":"/zones/{zone_id}/ssl/universal/settings","operation_id":"universal-ssl-settings-for-a-zone-get-universal-ssl-settings","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ssl setting"}
        \\{"provider":"cloudflare","tag":"Custom pages for a zone","method":"GET","path":"/zones/{zone_identifier}/custom_pages","operation_id":"custom-pages-for-a-zone-list-custom-pages","path_params":[{"name":"zone_identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone identifier spelling"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"configured_domain_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_account_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_zone_hints\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation audit-logs-get-account-audit-logs --path-param account_id='acct-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-an-account-list-custom-pages --path-param account_identifier='acct-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation dns-records-for-a-zone-list-dns-records --path-param zone_id='zone-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-a-zone-list-custom-pages --path-param zone_identifier='zone-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zone-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, cloudflare, "", &db, .{ .cloudflare = .{ .token = "test-token" } }, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"cache-cache-reserve-get-cache-reserve-setting\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"universal-ssl-settings-for-a-zone-get-universal-ssl-settings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans Cloudflare child resource captures from resource and inventory hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-child-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-other", "sparkdate.love", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-other\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");
    try db.upsertCloudflareResource("dns|zone-other|record-other", "route-cloudflare-dns", "record-other", "zone", "zone-other", "sparkdate.love", "active", "A", "{\"id\":\"record-other\"}");
    try db.upsertCloudflareResource("dns|zone-plosca|record-plosca", "route-cloudflare-dns", "record-plosca", "zone", "zone-plosca", "plosca.ru", "active", "A", "{\"id\":\"record-plosca\"}");
    try db.upsertCloudflareResource("zone-rulesets|plosca|ruleset", "zone-rulesets", "zone-ruleset-1", "zone", "plosca.ru", "default", "active", "http_request_cache_settings", "{\"id\":\"zone-ruleset-1\"}");
    try db.upsertCloudflareResource("account-rulesets|acct|ruleset", "account-rulesets", "account-ruleset-1", "account", "acct-1", "managed", "active", "http_request_firewall_custom", "{\"id\":\"account-ruleset-1\"}");
    try db.upsertCloudflareResource("zone-custom-pages|plosca|1000", "zone-custom-pages", "1000_errors", "zone", "plosca.ru", "1000 Errors", "default", null, "{\"id\":\"1000_errors\"}");
    try db.upsertCloudflareResource("account-custom-pages|acct|500", "account-custom-pages", "500_errors", "account", "acct-1", "500 Errors", "default", null, "{\"id\":\"500_errors\"}");
    try db.upsertCloudflareResource("tls-zone-certificate-packs|plosca|certpack", "tls-zone-certificate-packs", "certpack-1", "zone", "plosca.ru", "Universal SSL", "active", "universal", "{\"id\":\"certpack-1\"}");
    try db.upsertCloudflareResource("access-zone-identity-providers|plosca|idp", "access-zone-identity-providers", "idp-1", "zone", "plosca.ru", "One-time PIN", "active", "onetimepin", "{\"id\":\"idp-1\"}");
    try db.upsertCloudflareResource("account-members|acct|member", "account-members", "member-1", "account", "acct-1", "Alice", "accepted", null, "{\"id\":\"member-1\"}");
    try db.upsertCloudflareResource("account-roles|acct|role", "account-roles", "role-1", "account", "acct-1", "Administrator", "active", null, "{\"id\":\"role-1\"}");
    try db.upsertCloudflareResource("account-tokens|acct|token", "account-tokens", "token-1", "account", "acct-1", "Read token", "active", null, "{\"id\":\"token-1\"}");
    try db.upsertCloudflareResource("account-permission-groups|acct|permission", "account-permission-groups", "permission-1", "account", "acct-1", "Zone Read", "active", null, "{\"id\":\"permission-1\"}");
    try db.upsertCloudflareInventoryItem("account-resource-groups|acct|rg", "account-resource-groups", "resource-group-1", "account", "acct-1", "All zones", "active", "iam", null, "acct-1", null, null, null, null, null, null, "{\"id\":\"resource-group-1\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records/{dns_record_id}","operation_id":"dns-records-for-a-zone-dns-record-details","path_params":[{"name":"zone_id","required":true},{"name":"dns_record_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"dns record detail"}
        \\{"provider":"cloudflare","tag":"Zone Rulesets","method":"GET","path":"/zones/{zone_id}/rulesets/{ruleset_id}","operation_id":"getZoneRuleset","path_params":[{"name":"zone_id","required":true},{"name":"ruleset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone ruleset detail"}
        \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/{ruleset_id}","operation_id":"getAccountRuleset","path_params":[{"name":"account_id","required":true},{"name":"ruleset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account ruleset detail"}
        \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/phases/{ruleset_phase}/entrypoint","operation_id":"getAccountEntrypointRuleset","path_params":[{"name":"account_id","required":true},{"name":"ruleset_phase","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account ruleset phase"}
        \\{"provider":"cloudflare","tag":"Custom pages for a zone","method":"GET","path":"/zones/{zone_identifier}/custom_pages/{identifier}","operation_id":"custom-pages-for-a-zone-get-custom-page","path_params":[{"name":"zone_identifier","required":true},{"name":"identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone custom page detail"}
        \\{"provider":"cloudflare","tag":"Custom pages for an account","method":"GET","path":"/accounts/{account_identifier}/custom_pages/{identifier}","operation_id":"custom-pages-for-an-account-get-custom-page","path_params":[{"name":"account_identifier","required":true},{"name":"identifier","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account custom page detail"}
        \\{"provider":"cloudflare","tag":"SSL Certificate Packs","method":"GET","path":"/zones/{zone_id}/ssl/certificate_packs/{certificate_pack_id}","operation_id":"certificate-packs-get-certificate-pack","path_params":[{"name":"zone_id","required":true},{"name":"certificate_pack_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"certificate pack detail"}
        \\{"provider":"cloudflare","tag":"Access identity providers","method":"GET","path":"/zones/{zone_id}/access/identity_providers/{identity_provider_id}","operation_id":"access-identity-providers-get-an-access-identity-provider","path_params":[{"name":"zone_id","required":true},{"name":"identity_provider_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone access idp detail"}
        \\{"provider":"cloudflare","tag":"Account Members","method":"GET","path":"/accounts/{account_id}/members/{member_id}","operation_id":"account-members-member-details","path_params":[{"name":"account_id","required":true},{"name":"member_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"member detail"}
        \\{"provider":"cloudflare","tag":"Account Roles","method":"GET","path":"/accounts/{account_id}/roles/{role_id}","operation_id":"account-roles-role-details","path_params":[{"name":"account_id","required":true},{"name":"role_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"role detail"}
        \\{"provider":"cloudflare","tag":"Account Owned API Tokens","method":"GET","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"account-api-tokens-token-details","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account token detail"}
        \\{"provider":"cloudflare","tag":"Account Permission Groups","method":"GET","path":"/accounts/{account_id}/iam/permission_groups/{permission_group_id}","operation_id":"account-permission-group-details","path_params":[{"name":"account_id","required":true},{"name":"permission_group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"permission group detail"}
        \\{"provider":"cloudflare","tag":"Account Resource Groups","method":"GET","path":"/accounts/{account_id}/iam/resource_groups/{resource_group_id}","operation_id":"account-resource-group-details","path_params":[{"name":"account_id","required":true},{"name":"resource_group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"inventory-backed resource group detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_resource_hints\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cloudflare_inventory_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation dns-records-for-a-zone-dns-record-details --path-param zone_id='zone-plosca' --path-param dns_record_id='record-plosca'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation getZoneRuleset --path-param zone_id='zone-plosca' --path-param ruleset_id='zone-ruleset-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation getAccountEntrypointRuleset --path-param account_id='acct-1' --path-param ruleset_phase='http_request_firewall_custom'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation custom-pages-for-a-zone-get-custom-page --path-param zone_identifier='zone-plosca' --path-param identifier='1000_errors'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation certificate-packs-get-certificate-pack --path-param zone_id='zone-plosca' --path-param certificate_pack_id='certpack-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation access-identity-providers-get-an-access-identity-provider --path-param zone_id='zone-plosca' --path-param identity_provider_id='idp-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation account-api-tokens-token-details --path-param account_id='acct-1' --path-param token_id='token-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation account-resource-group-details --path-param account_id='acct-1' --path-param resource_group_id='resource-group-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "record-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zone-other") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, cloudflare, "", &db, .{ .cloudflare = .{ .token = "test-token" } }, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"account-resource-group-details\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "explains Cloudflare SSL and log missing inputs with official source routes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-source-map.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Certificate Packs","method":"GET","path":"/zones/{zone_id}/ssl/certificate_packs","operation_id":"certificate-packs-list-certificate-packs","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"certificate pack list"}
        \\{"provider":"cloudflare","tag":"Certificate Packs","method":"GET","path":"/zones/{zone_id}/ssl/certificate_packs/{certificate_pack_id}","operation_id":"certificate-packs-get-certificate-pack","path_params":[{"name":"zone_id","required":true},{"name":"certificate_pack_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"certificate pack detail"}
        \\{"provider":"cloudflare","tag":"Access mTLS authentication","method":"GET","path":"/accounts/{account_id}/access/certificates","operation_id":"access-mtls-authentication-list-mtls-certificates","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account mtls list"}
        \\{"provider":"cloudflare","tag":"Access mTLS authentication","method":"GET","path":"/accounts/{account_id}/access/certificates/{certificate_id}","operation_id":"access-mtls-authentication-get-an-mtls-certificate","path_params":[{"name":"account_id","required":true},{"name":"certificate_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"account mtls detail"}
        \\{"provider":"cloudflare","tag":"Log Explorer Datasets","method":"GET","path":"/zones/{zone_id}/logs/explorer/datasets","operation_id":"zones-logs-explorer-datasets-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone datasets"}
        \\{"provider":"cloudflare","tag":"Log Explorer Datasets","method":"GET","path":"/zones/{zone_id}/logs/explorer/datasets/{dataset_id}","operation_id":"zones-logs-explorer-datasets-get","path_params":[{"name":"zone_id","required":true},{"name":"dataset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone dataset detail"}
        \\{"provider":"cloudflare","tag":"Logpush jobs for a zone","method":"GET","path":"/zones/{zone_id}/logpush/jobs","operation_id":"get-zones-zone_id-logpush-jobs","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone logpush jobs"}
        \\{"provider":"cloudflare","tag":"Logpush jobs for a zone","method":"GET","path":"/zones/{zone_id}/logpush/jobs/{job_id}","operation_id":"get-zones-zone_id-logpush-jobs-job_id","path_params":[{"name":"zone_id","required":true},{"name":"job_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone logpush detail"}
        \\{"provider":"cloudflare","tag":"AI Gateway Logs","method":"GET","path":"/accounts/{account_id}/ai-gateway/gateways","operation_id":"aig-config-list-gateway","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ai gateways"}
        \\{"provider":"cloudflare","tag":"AI Gateway Logs","method":"GET","path":"/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs","operation_id":"aig-config-list-gateway-logs","path_params":[{"name":"account_id","required":true},{"name":"gateway_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ai gateway logs"}
        \\{"provider":"cloudflare","tag":"AI Gateway Logs","method":"GET","path":"/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs/{id}","operation_id":"aig-config-get-gateway-log-detail","path_params":[{"name":"account_id","required":true},{"name":"gateway_id","required":true},{"name":"id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ai gateway log detail"}
        \\{"provider":"cloudflare","tag":"Audit Logs","method":"GET","path":"/accounts/{account_id}/logs/audit","operation_id":"audit-logs-v2-get-account-audit-logs","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"before","required":true},{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"audit v2 list"}
        \\{"provider":"cloudflare","tag":"Audit Logs","method":"GET","path":"/accounts/{account_id}/logs/audit/{id}/history","operation_id":"audit-logs-v2-get-account-audit-log-history","path_params":[{"name":"account_id","required":true},{"name":"id","required":true}],"query_params":[{"name":"action_time","required":true},{"name":"before","required":true},{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"audit v2 history"}
        \\{"provider":"cloudflare","tag":"Logs Received","method":"GET","path":"/zones/{zone_id}/logs/rayids/{ray_id}","operation_id":"get-zones-zone_id-logs-rayids-ray_id","path_params":[{"name":"zone_id","required":true},{"name":"ray_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ray detail"}
        \\{"provider":"cloudflare","tag":"Logs Received","method":"GET","path":"/zones/{zone_id}/logs/received","operation_id":"get-zones-zone_id-logs-received","path_params":[{"name":"zone_id","required":true}],"query_params":[{"name":"end","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"logs received"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"unmapped\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"certificate_pack_id\",\"source_operation_id\":\"certificate-packs-list-certificate-packs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"certificate_id\",\"source_operation_id\":\"access-mtls-authentication-list-mtls-certificates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"dataset_id\",\"source_operation_id\":\"zones-logs-explorer-datasets-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"job_id\",\"source_operation_id\":\"get-zones-zone_id-logpush-jobs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"gateway_id\",\"source_operation_id\":\"aig-config-list-gateway\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"id\",\"source_operation_id\":\"aig-config-list-gateway-logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"action_time\",\"source_operation_id\":\"audit-logs-v2-get-account-audit-logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"ray_id\",\"source_operation_id\":null,\"hint_kind\":null,\"hint_count\":0,\"result\":\"no_official_source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"end\",\"source_operation_id\":null,\"hint_kind\":null,\"hint_count\":0,\"result\":\"no_official_source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation audit-logs-v2-get-account-audit-logs --path-param account_id='acct-1' --query-param before='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "--query-param since='") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_before") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_since") == null);
}

test "plans Cloudflare SSL and log child captures from broad source hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-cloudflare-source-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertCloudflareAccount("acct-1", "Main account", "standard", "active", "{\"id\":\"acct-1\"}");
    try db.upsertCloudflareZone("zone-plosca", "plosca.ru", "acct-1", "active", false, "full", "ns1.example,ns2.example", "{\"id\":\"zone-plosca\"}");
    try db.upsertCloudflareResource("certificate-packs-list-certificate-packs|zone|pack", "certificate-packs-list-certificate-packs", "pack-1", "zone", "zone-plosca", "Universal SSL", "active", "universal", "{\"id\":\"pack-1\"}");
    try db.upsertCloudflareResource("access-mtls-authentication-list-mtls-certificates|acct|cert", "access-mtls-authentication-list-mtls-certificates", "cert-1", "account", "acct-1", "Client cert", "active", "mtls", "{\"id\":\"cert-1\"}");
    try db.upsertCloudflareResource("zones-logs-explorer-datasets-list|zone|dataset", "zones-logs-explorer-datasets-list", "http_requests", "zone", "zone-plosca", "HTTP requests", "active", "dataset", "{\"dataset_id\":\"http_requests\"}");
    try db.upsertCloudflareResource("get-zones-zone_id-logpush-jobs|zone|job", "get-zones-zone_id-logpush-jobs", "77", "zone", "zone-plosca", "HTTP logs", "enabled", "logpush", "{\"id\":77}");
    try db.upsertCloudflareResource("aig-config-list-gateway|acct|gateway", "aig-config-list-gateway", "gateway-1", "account", "acct-1", "AI Gateway", "active", "gateway", "{\"id\":\"gateway-1\"}");
    try db.upsertCloudflareResource("worker-script-list-workers|acct|worker", "worker-script-list-workers", "edge-worker", "account", "acct-1", "edge-worker", "active", "worker", "{\"id\":\"edge-worker\"}");

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Certificate Packs","method":"GET","path":"/zones/{zone_id}/ssl/certificate_packs/{certificate_pack_id}","operation_id":"certificate-packs-get-certificate-pack","path_params":[{"name":"zone_id","required":true},{"name":"certificate_pack_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"certificate pack detail"}
        \\{"provider":"cloudflare","tag":"Access mTLS authentication","method":"GET","path":"/accounts/{account_id}/access/certificates/{certificate_id}","operation_id":"access-mtls-authentication-get-an-mtls-certificate","path_params":[{"name":"account_id","required":true},{"name":"certificate_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"mtls detail"}
        \\{"provider":"cloudflare","tag":"Log Explorer Datasets","method":"GET","path":"/zones/{zone_id}/logs/explorer/datasets/{dataset_id}","operation_id":"zones-logs-explorer-datasets-get","path_params":[{"name":"zone_id","required":true},{"name":"dataset_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"dataset detail"}
        \\{"provider":"cloudflare","tag":"Logpush jobs for a zone","method":"GET","path":"/zones/{zone_id}/logpush/jobs/{job_id}","operation_id":"get-zones-zone_id-logpush-jobs-job_id","path_params":[{"name":"zone_id","required":true},{"name":"job_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"logpush detail"}
        \\{"provider":"cloudflare","tag":"AI Gateway Logs","method":"GET","path":"/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs","operation_id":"aig-config-list-gateway-logs","path_params":[{"name":"account_id","required":true},{"name":"gateway_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"gateway logs"}
        \\{"provider":"cloudflare","tag":"Worker Tail Logs","method":"GET","path":"/accounts/{account_id}/workers/scripts/{script_name}/tails","operation_id":"worker-tail-logs-list-tails","path_params":[{"name":"account_id","required":true},{"name":"script_name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"worker tails"}
        \\{"provider":"cloudflare","tag":"Radar Certificate Transparency","method":"GET","path":"/radar/ct/summary/{dimension}","operation_id":"radar-get-ct-summary","path_params":[{"name":"dimension","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"radar summary"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, cloudflare, "", &db, .{
        .filter = .{ .provider = .cloudflare },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation certificate-packs-get-certificate-pack --path-param zone_id='zone-plosca' --path-param certificate_pack_id='pack-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation access-mtls-authentication-get-an-mtls-certificate --path-param account_id='acct-1' --path-param certificate_id='cert-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation zones-logs-explorer-datasets-get --path-param zone_id='zone-plosca' --path-param dataset_id='http_requests'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation get-zones-zone_id-logpush-jobs-job_id --path-param zone_id='zone-plosca' --path-param job_id='77'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation aig-config-list-gateway-logs --path-param account_id='acct-1' --path-param gateway_id='gateway-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation worker-tail-logs-list-tails --path-param account_id='acct-1' --path-param script_name='edge-worker'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture cloudflare --operation radar-get-ct-summary --path-param dimension='CA'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);
}

test "plans Hostinger DNS domain hosting and Horizons captures from domain and inventory hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hosting-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerInventoryItem("hosting_listWebsitesV1/plosca.ru", "hosting_listWebsitesV1", "plosca.ru", "plosca.ru", "enabled", "main", "plosca.ru", "u123", "order-123", null, null, null, null, "{\"domain\":\"plosca.ru\"}");
    try db.upsertHostingerInventoryItem("hosting_listOrdersV1/order-123", "hosting_listOrdersV1", "order-123", "Premium Web Hosting", "active", "hosting", null, "u123", null, null, null, null, null, "{\"id\":\"order-123\"}");
    try db.upsertHostingerResource("DNS_getDNSSnapshotListV1/snap-1", "DNS_getDNSSnapshotListV1", "snap-1", "plosca.ru", "Before deploy", null, "plosca.ru", "{\"id\":\"snap-1\"}");
    try db.upsertHostingerResource("domains_getWHOISProfileListV1/whois-77", "domains_getWHOISProfileListV1", "whois-77", "domains_getWHOISProfileListV1", "Registrant", "active", null, "{\"id\":\"whois-77\"}");
    try db.upsertHostingerResource("hosting_listAccountDatabasesV1/db_main", "hosting_listAccountDatabasesV1", "db_main", "u123", "db_main", "active", "plosca.ru", "{\"name\":\"db_main\"}");
    try db.upsertHostingerResource("hosting_listNodeJSBuildsV1/build-abc", "hosting_listNodeJSBuildsV1", "build-abc", "u123/plosca.ru", "build-abc", "finished", "plosca.ru", "{\"uuid\":\"build-abc\"}");
    try db.upsertHostingerResource("horizons_getWebsitesV1/site-42", "horizons_getWebsitesV1", "site-42", "horizons_getWebsitesV1", "plosca.ru", "active", "plosca.ru", "{\"id\":\"site-42\"}");

    const hostinger =
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}","operation_id":"DNS_getDNSSnapshotListV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain read"}
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}/{snapshotId}","operation_id":"DNS_getDNSSnapshotV1","path_params":[{"name":"domain","required":true},{"name":"snapshotId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"snapshot detail"}
        \\{"provider":"hostinger","tag":"DNS: Zone","method":"GET","path":"/api/dns/v1/zones/{domain}","operation_id":"DNS_getDNSRecordsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"zone detail"}
        \\{"provider":"hostinger","tag":"Domains: Portfolio","method":"GET","path":"/api/domains/v1/portfolio/{domain}","operation_id":"domains_getDomainDetailsV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain detail"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois/{whoisId}","operation_id":"domains_getWHOISProfileV1","path_params":[{"name":"whoisId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois detail"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases","operation_id":"hosting_listAccountDatabasesV1","path_params":[{"name":"username","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database list"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases/{name}/phpmyadmin-link","operation_id":"hosting_getPhpMyAdminLinkV1","path_params":[{"name":"username","required":true},{"name":"name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database detail"}
        \\{"provider":"hostinger","tag":"Hosting: Datacenters","method":"GET","path":"/api/hosting/v1/datacenters","operation_id":"hosting_listAvailableDatacentersV1","path_params":[],"query_params":[{"name":"order_id","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"order scoped"}
        \\{"provider":"hostinger","tag":"Hosting: Domains","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/subdomains","operation_id":"hosting_listWebsiteSubdomainsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website child list"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds/{uuid}/logs","operation_id":"hosting_getNodeJSBuildLogsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true},{"name":"uuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"node build logs"}
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites/{websiteId}","operation_id":"horizons_getWebsiteV1","path_params":[{"name":"websiteId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"configured_domain_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_inventory_hints\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation DNS_getDNSSnapshotV1 --path-param domain='plosca.ru' --path-param snapshotId='snap-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation domains_getWHOISProfileV1 --path-param whoisId='whois-77'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_getPhpMyAdminLinkV1 --path-param username='u123' --path-param name='db_main'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_listAvailableDatacentersV1 --query-param order_id='order-123'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_getNodeJSBuildLogsV1 --path-param username='u123' --path-param domain='plosca.ru' --path-param uuid='build-abc'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation horizons_getWebsiteV1 --path-param websiteId='site-42'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
        .configured_domains = configured_domains[0..],
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"hosting_listWebsiteSubdomainsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"horizons_getWebsiteV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);
}

test "plans Hostinger Docker and Reach child captures from scoped resource hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-child-hints.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try db.upsertHostingerResource("VPS_getProjectListV1/999999/wrong-project", "VPS_getProjectListV1", "wrong-project", "999999", "wrong-project", "running", null, "{\"projectName\":\"wrong-project\"}");
    try db.upsertHostingerResource("VPS_getProjectListV1/1307809/cloudio-stack", "VPS_getProjectListV1", "cloudio-stack", "1307809", "cloudio-stack", "running", null, "{\"projectName\":\"cloudio-stack\"}");
    try db.upsertHostingerResource("reach_listProfilesV1/profile-1", "reach_listProfilesV1", "profile-1", "reach_listProfilesV1", "Main profile", "active", null, "{\"profileUuid\":\"profile-1\"}");
    try db.upsertHostingerResource("reach_listSegmentsV1/segment-1", "reach_listSegmentsV1", "segment-1", "reach_listSegmentsV1", "Customers", "enabled", null, "{\"segmentUuid\":\"segment-1\"}");

    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project list"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}","operation_id":"VPS_getProjectContentsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project contents"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}/containers","operation_id":"VPS_getProjectContainersV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project containers"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}/logs","operation_id":"VPS_getProjectLogsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"project logs"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"profile list"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments","operation_id":"reach_listSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment list"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments/{segmentUuid}","operation_id":"reach_getSegmentDetailsV1","path_params":[{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment detail"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listSegmentContactsV1","path_params":[{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"segment contacts"}
        \\{"provider":"hostinger","tag":"Reach: Segmentation","method":"GET","path":"/api/reach/v1/profiles/{profileUuid}/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listProfileSegmentContactsV1","path_params":[{"name":"profileUuid","required":true},{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"profile segment contacts"}
        \\
    ;

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_vps_hints\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hostinger_resource_hints\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"official_read_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ready_candidates\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectContentsV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectContainersV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectLogsV1 --path-param virtualMachineId='1307809' --path-param projectName='cloudio-stack'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation reach_getSegmentDetailsV1 --path-param segmentUuid='segment-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation reach_listProfileSegmentContactsV1 --path-param profileUuid='profile-1' --path-param segmentUuid='segment-1'") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "wrong-project") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "REPLACE_") == null);

    const planned = try actualReadyCaptureJsonFromText(std.testing.io, allocator, "", hostinger, &db, .{ .hostinger = "test-token" }, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .execute = false,
    });
    defer allocator.free(planned);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"candidate_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"ready_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"planned\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"VPS_getProjectContentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "\"operation_id\":\"reach_listProfileSegmentContactsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "wrong-project") == null);
    try std.testing.expect(std.mem.indexOf(u8, planned, "test-token") == null);

    const wrong_db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-wrong-child-hints.db", .{tmp.sub_path});
    defer allocator.free(wrong_db_path);
    var wrong_db = try Db.open(std.testing.io, wrong_db_path);
    defer wrong_db.close();
    try wrong_db.initSchema();
    try wrong_db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try wrong_db.upsertHostingerResource("VPS_getProjectListV1/999999/wrong-project", "VPS_getProjectListV1", "wrong-project", "999999", "wrong-project", "running", null, "{\"projectName\":\"wrong-project\"}");

    var wrong_json_out = std.Io.Writer.Allocating.init(allocator);
    defer wrong_json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &wrong_db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
    }, &wrong_json_out.writer);
    const wrong_json = try wrong_json_out.toOwnedSlice();
    defer allocator.free(wrong_json);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"candidate_routes\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"ready_candidates\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"operation_id\":\"VPS_getProjectContentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "\"missing_inputs\":[{\"source\":\"path\",\"name\":\"projectName\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrong_json, "cloudio route capture hostinger --operation VPS_getProjectContentsV1 --path-param virtualMachineId='1307809' --path-param projectName='wrong-project'") == null);
}

test "explains Hostinger missing input source routes for broad child groups" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/actual-capture-hostinger-source-plan.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try db.upsertHostingerVps("1307809", "srv1307809.hstgr.cloud", "running", "76.13.130.170", "KVM 4", "{\"id\":1307809}");
    try db.insertAudit("route.capture", "ok", "hostinger/domains_getWHOISProfileListV1 /api/domains/v1/whois");
    _ = try db.insertSnapshot("hostinger", "domains_getWHOISProfileListV1", "/api/domains/v1/whois", "ok", "domains_getWHOISProfileListV1 HTTP 200", "[]", null);
    try db.insertAudit("route.capture", "ok", "hostinger/hosting_listAccountDatabasesV1 /api/hosting/v1/accounts/u123/databases");
    _ = try db.insertSnapshot("hostinger", "hosting_listAccountDatabasesV1", "/api/hosting/v1/accounts/u123/databases", "ok", "hosting_listAccountDatabasesV1 HTTP 200", "{\"data\":[{\"unsupported\":\"db-main\"}],\"meta\":{\"total\":1}}", null);
    try db.insertAudit("route.capture", "permission", "hostinger/reach_listProfilesV1 /api/reach/v1/profiles");
    try db.insertAudit("route.capture", "http_error", "hostinger/VPS_getProjectListV1 /api/vps/v1/virtual-machines/1307809/docker");

    const hostinger =
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}","operation_id":"DNS_getDNSSnapshotListV1","path_params":[{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"domain read"}
        \\{"provider":"hostinger","tag":"DNS: Snapshot","method":"GET","path":"/api/dns/v1/snapshots/{domain}/{snapshotId}","operation_id":"DNS_getDNSSnapshotV1","path_params":[{"name":"domain","required":true},{"name":"snapshotId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"snapshot detail"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois","operation_id":"domains_getWHOISProfileListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois list"}
        \\{"provider":"hostinger","tag":"Domains: WHOIS","method":"GET","path":"/api/domains/v1/whois/{whoisId}","operation_id":"domains_getWHOISProfileV1","path_params":[{"name":"whoisId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"whois detail"}
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites/{websiteId}","operation_id":"horizons_getWebsiteV1","path_params":[{"name":"websiteId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website detail"}
        \\{"provider":"hostinger","tag":"Hosting: Websites","method":"GET","path":"/api/hosting/v1/websites","operation_id":"hosting_listWebsitesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"website list"}
        \\{"provider":"hostinger","tag":"Hosting: Orders","method":"GET","path":"/api/hosting/v1/orders","operation_id":"hosting_listOrdersV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"orders"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases","operation_id":"hosting_listAccountDatabasesV1","path_params":[{"name":"username","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database list"}
        \\{"provider":"hostinger","tag":"Hosting: Databases","method":"GET","path":"/api/hosting/v1/accounts/{username}/databases/{name}/phpmyadmin-link","operation_id":"hosting_getPhpMyAdminLinkV1","path_params":[{"name":"username","required":true},{"name":"name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"database detail"}
        \\{"provider":"hostinger","tag":"Hosting: Datacenters","method":"GET","path":"/api/hosting/v1/datacenters","operation_id":"hosting_listAvailableDatacentersV1","path_params":[],"query_params":[{"name":"order_id","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"order-scoped"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds","operation_id":"hosting_listNodeJSBuildsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"build list"}
        \\{"provider":"hostinger","tag":"Hosting: NodeJS","method":"GET","path":"/api/hosting/v1/accounts/{username}/websites/{domain}/nodejs/builds/{uuid}/logs","operation_id":"hosting_getNodeJSBuildLogsV1","path_params":[{"name":"username","required":true},{"name":"domain","required":true},{"name":"uuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"build logs"}
        \\{"provider":"hostinger","tag":"Reach: Profiles","method":"GET","path":"/api/reach/v1/profiles","operation_id":"reach_listProfilesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/segmentation/segments","operation_id":"reach_listSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/profiles/{profileUuid}/segmentation/segments/{segmentUuid}/contacts","operation_id":"reach_listProfileSegmentContactsV1","path_params":[{"name":"profileUuid","required":true},{"name":"segmentUuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked child"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker/{projectName}","operation_id":"VPS_getProjectContentsV1","path_params":[{"name":"virtualMachineId","required":true},{"name":"projectName","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"400","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"project detail"}
        \\{"provider":"hostinger","tag":"VPS: Firewall","method":"GET","path":"/api/vps/v1/firewall","operation_id":"VPS_getFirewallListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"firewall list"}
        \\{"provider":"hostinger","tag":"VPS: Firewall","method":"GET","path":"/api/vps/v1/firewall/{firewallId}","operation_id":"VPS_getFirewallDetailsV1","path_params":[{"name":"firewallId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"firewall detail"}
        \\{"provider":"hostinger","tag":"VPS: Post-install scripts","method":"GET","path":"/api/vps/v1/post-install-scripts","operation_id":"VPS_getPostInstallScriptsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"scripts"}
        \\{"provider":"hostinger","tag":"VPS: Post-install scripts","method":"GET","path":"/api/vps/v1/post-install-scripts/{postInstallScriptId}","operation_id":"VPS_getPostInstallScriptV1","path_params":[{"name":"postInstallScriptId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"script detail"}
        \\
    ;
    const configured_domains = [_][]const u8{"plosca.ru"};

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeActualCapturesJsonFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source_summary\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"no_official_source\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shapes\":{\"array\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"missing_input_sources\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"snapshotId\",\"source_operation_id\":\"DNS_getDNSSnapshotListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"ready_to_capture\",\"next_action\":\"capture the source route to discover identifiers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"whoisId\",\"source_operation_id\":\"domains_getWHOISProfileListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"review_status\":\"blocked_empty_source\",\"next_action\":\"source collection is empty; no child identifiers are available\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"captured_empty\",\"next_action\":\"source collection is empty; no child identifiers are available\",\"source_status\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shape\":\"array\",\"body_item_count\":0,\"body_bytes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"websiteId\",\"source_operation_id\":null,\"hint_kind\":null,\"hint_count\":0,\"result\":\"no_official_source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "horizons_getWebsitesV1") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"username\",\"source_operation_id\":\"hosting_listWebsitesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"name\",\"source_operation_id\":\"hosting_listAccountDatabasesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"captured_without_hints\",\"next_action\":\"extend normalization for this non-empty source response\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_shape\":\"data_array\",\"body_item_count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"order_id\",\"source_operation_id\":\"hosting_listOrdersV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"uuid\",\"source_operation_id\":\"hosting_listNodeJSBuildsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"profileUuid\",\"source_operation_id\":\"reach_listProfilesV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"segmentUuid\",\"source_operation_id\":\"reach_listSegmentsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"projectName\",\"source_operation_id\":\"VPS_getProjectListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":\"diagnostic_blocked\",\"next_action\":\"diagnostic-only source is blocked; child identifiers are unavailable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"firewallId\",\"source_operation_id\":\"VPS_getFirewallListV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"input_name\":\"postInstallScriptId\",\"source_operation_id\":\"VPS_getPostInstallScriptsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation hosting_listWebsitesV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "cloudio route capture hostinger --operation VPS_getProjectListV1 --path-param virtualMachineId='1307809' --diagnostic") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"diagnostic_ready\":true") != null);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeActualCapturesTextFromText(allocator, "", hostinger, &db, .{
        .filter = .{ .provider = .hostinger },
        .limit = 0,
        .configured_domains = configured_domains[0..],
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "source_summary total=") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "no_official_source=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:snapshotId <- DNS_getDNSSnapshotListV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:websiteId <- no_official_source result=no_official_source") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:projectName <- VPS_getProjectListV1 state=non_ok result=diagnostic_blocked ready=false diagnostic_ready=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:whoisId <- domains_getWHOISProfileListV1 state=ok result=captured_empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "source: path:name <- hosting_listAccountDatabasesV1 state=ok result=captured_without_hints") != null);
}
