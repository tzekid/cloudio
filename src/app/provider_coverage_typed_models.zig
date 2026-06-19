const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_workplan = @import("app_provider_coverage_workplan");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeJsonNullableStringField = app_provider_coverage_render.writeJsonNullableStringField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;
const writeShellArg = app_provider_coverage_render.writeShellArg;

pub const WorkplanFamily = app_provider_coverage_workplan.WorkplanFamily;
pub const WorkplanFocus = app_provider_coverage_workplan.WorkplanFocus;

pub const TypedModelOptions = struct {
    provider: provider_routes.ProviderFilter = .all,
    family: WorkplanFamily = .all,
    focus: WorkplanFocus = .all,
    limit: usize = 25,
    include_complete: bool = false,
};

pub const TypedModelSummary = struct {
    generic_inventory_rows: usize = 0,
    control_plane_generic_inventory_rows: usize = 0,
    outside_control_plane_generic_inventory_rows: usize = 0,
    typed_gap: usize = 0,
    control_plane_typed_gap: usize = 0,
    outside_control_plane_typed_gap: usize = 0,
    visible: usize = 0,
    omitted: usize = 0,
    focus_filtered_rows_hidden: usize = 0,
    family_filtered_rows_hidden: usize = 0,
    typed_or_complete_rows_hidden: usize = 0,
};

pub fn writeText(gpa: Allocator, rows: anytype, options: TypedModelOptions, writer: anytype) !void {
    sortRows(rows);
    const active_focus = effectiveFocus(options);
    const summary = summarizeRows(rows, options);
    try writer.writeAll("Cloudio typed model candidates\n");
    try writer.writeAll("evidence: L3 generic inventory rows with missing or thin typed-table projections\n");
    try writer.writeAll("rank: required control-plane typed gaps first, then typed_gap + generic_inventory_candidates\n");
    try writer.writeAll("scope: control-plane typed gaps are required for this goal; outside-control-plane gaps are optional generic inventory backlog\n");
    try writer.print("filter={s} focus={s} family={s}", .{ options.provider.name(), active_focus.name(), options.family.name() });
    if (options.include_complete) try writer.writeAll(" include_complete=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }
    try writer.print("summary: L3_generic_rows={d} control_plane_rows={d} outside_control_plane_rows={d} typed_gap={d} control_plane_typed_gap={d} outside_control_plane_typed_gap={d}\n", .{
        summary.generic_inventory_rows,
        summary.control_plane_generic_inventory_rows,
        summary.outside_control_plane_generic_inventory_rows,
        summary.typed_gap,
        summary.control_plane_typed_gap,
        summary.outside_control_plane_typed_gap,
    });

    var visible: usize = 0;
    for (rows) |row| {
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!focusIncludes(active_focus, row)) continue;
        if (!familyIncludes(options.family, row)) {
            continue;
        }
        if (!options.include_complete and typedGap(row) == 0) {
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            continue;
        }
        visible += 1;
        try writeTextRow(gpa, row, writer);
    }

    if (visible == 0) {
        try writer.writeAll("no typed model candidates for filter\n");
    }
    if (summary.omitted != 0) try writer.print("omitted={d}\n", .{summary.omitted});
    if (summary.focus_filtered_rows_hidden != 0) try writer.print("focus_filtered_rows_hidden={d}\n", .{summary.focus_filtered_rows_hidden});
    if (summary.family_filtered_rows_hidden != 0) try writer.print("family_filtered_rows_hidden={d}\n", .{summary.family_filtered_rows_hidden});
    if (summary.typed_or_complete_rows_hidden != 0) try writer.print("typed_or_complete_rows_hidden={d}\n", .{summary.typed_or_complete_rows_hidden});
}

pub fn writeJson(gpa: Allocator, rows: anytype, options: TypedModelOptions, writer: anytype) !void {
    sortRows(rows);
    const active_focus = effectiveFocus(options);
    const summary = summarizeRows(rows, options);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_typed_model_candidates", true);
    try writeJsonField(writer, "filter", options.provider.name(), true);
    try writeJsonField(writer, "focus", active_focus.name(), true);
    try writeJsonField(writer, "family", options.family.name(), true);
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_complete", options.include_complete, true);
    try writeJsonField(writer, "evidence", "L3 generic inventory rows with missing or thin typed-table projections", true);
    try writeJsonField(writer, "rank", "required control-plane typed gaps first, then typed_gap + generic_inventory_candidates", true);
    try writeJsonField(writer, "scope", "control-plane typed gaps are required for this goal; outside-control-plane gaps are optional generic inventory backlog", true);
    try writer.writeAll("\"summary\":");
    try writeSummaryJson(summary, writer);
    try writer.writeByte(',');
    try writer.writeAll("\"items\":[");

    var visible: usize = 0;
    var first = true;
    for (rows) |row| {
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!focusIncludes(active_focus, row)) continue;
        if (!familyIncludes(options.family, row)) {
            continue;
        }
        if (!options.include_complete and typedGap(row) == 0) {
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeJsonRow(gpa, row, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "visible", summary.visible, true);
    try writeJsonCountField(writer, "omitted", summary.omitted, true);
    try writeJsonCountField(writer, "focus_filtered_rows_hidden", summary.focus_filtered_rows_hidden, true);
    try writeJsonCountField(writer, "family_filtered_rows_hidden", summary.family_filtered_rows_hidden, true);
    try writeJsonCountField(writer, "typed_or_complete_rows_hidden", summary.typed_or_complete_rows_hidden, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
}

pub fn summarizeRows(rows: anytype, options: TypedModelOptions) TypedModelSummary {
    const active_focus = effectiveFocus(options);
    var summary = TypedModelSummary{};
    for (rows) |row| {
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        const gap = typedGap(row);
        summary.generic_inventory_rows += 1;
        summary.typed_gap += gap;
        if (requiredForGoal(row)) {
            summary.control_plane_generic_inventory_rows += 1;
            summary.control_plane_typed_gap += gap;
        } else {
            summary.outside_control_plane_generic_inventory_rows += 1;
            summary.outside_control_plane_typed_gap += gap;
        }
        if (!focusIncludes(active_focus, row)) {
            summary.focus_filtered_rows_hidden += 1;
            continue;
        }
        if (!familyIncludes(options.family, row)) {
            summary.family_filtered_rows_hidden += 1;
            continue;
        }
        if (!options.include_complete and gap == 0) {
            summary.typed_or_complete_rows_hidden += 1;
            continue;
        }
        if (options.limit != 0 and summary.visible >= options.limit) {
            summary.omitted += 1;
            continue;
        }
        summary.visible += 1;
    }
    return summary;
}

pub fn typedGap(row: anytype) usize {
    if (row.evidence.l3_generic_inventory_candidates <= row.evidence.l3_typed_table_evidence) return 0;
    return row.evidence.l3_generic_inventory_candidates - row.evidence.l3_typed_table_evidence;
}

pub fn sortRows(rows: anytype) void {
    const pointer = switch (@typeInfo(@TypeOf(rows))) {
        .pointer => |value| value,
        else => @compileError("typed model rows must be a slice"),
    };
    if (pointer.size != .slice) @compileError("typed model rows must be a slice");

    var index: usize = 1;
    while (index < rows.len) : (index += 1) {
        var cursor = index;
        while (cursor > 0 and typedModelLessThan(rows[cursor], rows[cursor - 1])) : (cursor -= 1) {
            const tmp = rows[cursor - 1];
            rows[cursor - 1] = rows[cursor];
            rows[cursor] = tmp;
        }
    }
}

fn writeTextRow(gpa: Allocator, row: anytype, writer: anytype) !void {
    const family = tagFamily(row.provider, row.tag);
    try writer.print("{s} | {s}: typed_gap={d} L3_generic={d} typed={d} L2_read_evidence={d} family={s} scope={s} required_for_goal={s} next_action={s}\n", .{
        row.provider,
        row.tag,
        typedGap(row),
        row.evidence.l3_generic_inventory_candidates,
        row.evidence.l3_typed_table_evidence,
        row.evidence.l2_read_evidence,
        if (family) |value| value.name() else "-",
        typedModelScope(row),
        if (requiredForGoal(row)) "true" else "false",
        nextAction(row),
    });
    const routes = try routesCommand(gpa, row);
    defer gpa.free(routes);
    try writer.print("  routes: {s}\n", .{routes});
    const workplan = try workplanCommand(gpa, row);
    defer gpa.free(workplan);
    try writer.print("  review-bundle: {s}\n", .{workplan});
}

fn writeJsonRow(gpa: Allocator, row: anytype, writer: anytype) !void {
    const family = tagFamily(row.provider, row.tag);
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider, true);
    try writeJsonField(writer, "tag", row.tag, true);
    try writeJsonNullableStringField(writer, "focus_family", if (family) |value| value.name() else null, true);
    try writeJsonField(writer, "scope", typedModelScope(row), true);
    try writeJsonBoolField(writer, "required_for_goal", requiredForGoal(row), true);
    try writeJsonCountField(writer, "typed_gap", typedGap(row), true);
    try writeJsonCountField(writer, "l3_generic_inventory_candidates", row.evidence.l3_generic_inventory_candidates, true);
    try writeJsonCountField(writer, "l3_typed_table_evidence", row.evidence.l3_typed_table_evidence, true);
    try writeJsonCountField(writer, "l2_read_evidence", row.evidence.l2_read_evidence, true);
    try writeJsonField(writer, "status", if (typedGap(row) == 0) "typed" else "candidate", true);
    try writeJsonField(writer, "next_action", nextAction(row), true);
    try writer.writeAll("\"commands\":[");
    var first = true;
    const routes = try routesCommand(gpa, row);
    defer gpa.free(routes);
    try app_provider_coverage_workplan.writeCommandJson(writer, &first, "routes_detail", routes);
    const workplan = try workplanCommand(gpa, row);
    defer gpa.free(workplan);
    try app_provider_coverage_workplan.writeCommandJson(writer, &first, "review_bundle", workplan);
    try writer.writeAll("]}");
}

fn routesCommand(gpa: Allocator, row: anytype) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage routes {s} ", .{row.provider});
    try writeShellArg(&out.writer, row.tag);
    try out.writer.writeAll(" --support partial --mode read --detail");
    return try out.toOwnedSlice();
}

fn workplanCommand(gpa: Allocator, row: anytype) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try out.writer.print("cloudio coverage workplan {s}", .{row.provider});
    if (tagFamily(row.provider, row.tag)) |family| {
        try out.writer.print(" --family {s}", .{family.name()});
    }
    try out.writer.writeAll(" --limit 5 --candidate-limit 10 --bundle --plans --json");
    return try out.toOwnedSlice();
}

fn typedModelLessThan(lhs: anytype, rhs: anytype) bool {
    const lhs_required = requiredForGoal(lhs);
    const rhs_required = requiredForGoal(rhs);
    if (lhs_required != rhs_required) return lhs_required;
    const lhs_gap = typedGap(lhs);
    const rhs_gap = typedGap(rhs);
    if (lhs_gap != rhs_gap) return lhs_gap > rhs_gap;
    if (lhs.evidence.l3_generic_inventory_candidates != rhs.evidence.l3_generic_inventory_candidates) {
        return lhs.evidence.l3_generic_inventory_candidates > rhs.evidence.l3_generic_inventory_candidates;
    }
    if (lhs.evidence.l3_typed_table_evidence != rhs.evidence.l3_typed_table_evidence) {
        return lhs.evidence.l3_typed_table_evidence < rhs.evidence.l3_typed_table_evidence;
    }
    const lhs_family = tagFamily(lhs.provider, lhs.tag);
    const rhs_family = tagFamily(rhs.provider, rhs.tag);
    const lhs_family_name = if (lhs_family) |family| family.name() else "";
    const rhs_family_name = if (rhs_family) |family| family.name() else "";
    const provider_order = std.mem.order(u8, lhs.provider, rhs.provider);
    if (provider_order != .eq) return provider_order == .lt;
    const family_order = std.mem.order(u8, lhs_family_name, rhs_family_name);
    if (family_order != .eq) return family_order == .lt;
    return std.mem.order(u8, lhs.tag, rhs.tag) == .lt;
}

fn familyIncludes(family: WorkplanFamily, row: anytype) bool {
    return app_provider_coverage_workplan.familyIncludes(family, row);
}

fn focusIncludes(focus: WorkplanFocus, row: anytype) bool {
    return app_provider_coverage_workplan.focusIncludes(focus, row);
}

fn effectiveFocus(options: TypedModelOptions) WorkplanFocus {
    if (options.family != .all) return .control_plane;
    return options.focus;
}

fn tagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    return app_provider_coverage_workplan.tagFamily(provider, tag);
}

fn requiredForGoal(row: anytype) bool {
    return focusIncludes(.control_plane, row);
}

fn typedModelScope(row: anytype) []const u8 {
    return if (requiredForGoal(row)) "control-plane" else "outside-control-plane";
}

fn nextAction(row: anytype) []const u8 {
    if (typedGap(row) == 0) return "review_typed_evidence";
    if (requiredForGoal(row)) return "promote_control_plane_inventory_to_typed_model";
    return "optional_generic_inventory_modeling";
}

fn writeSummaryJson(summary: TypedModelSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "generic_inventory_rows", summary.generic_inventory_rows, true);
    try writeJsonCountField(writer, "control_plane_generic_inventory_rows", summary.control_plane_generic_inventory_rows, true);
    try writeJsonCountField(writer, "outside_control_plane_generic_inventory_rows", summary.outside_control_plane_generic_inventory_rows, true);
    try writeJsonCountField(writer, "typed_gap", summary.typed_gap, true);
    try writeJsonCountField(writer, "control_plane_typed_gap", summary.control_plane_typed_gap, true);
    try writeJsonCountField(writer, "outside_control_plane_typed_gap", summary.outside_control_plane_typed_gap, true);
    try writeJsonCountField(writer, "visible", summary.visible, true);
    try writeJsonCountField(writer, "omitted", summary.omitted, true);
    try writeJsonCountField(writer, "focus_filtered_rows_hidden", summary.focus_filtered_rows_hidden, true);
    try writeJsonCountField(writer, "family_filtered_rows_hidden", summary.family_filtered_rows_hidden, true);
    try writeJsonCountField(writer, "typed_or_complete_rows_hidden", summary.typed_or_complete_rows_hidden, false);
    try writer.writeByte('}');
}

const TestEvidence = struct {
    l2_read_evidence: usize = 0,
    l3_generic_inventory_candidates: usize = 0,
    l3_typed_table_evidence: usize = 0,
};

const TestRow = struct {
    provider: []const u8,
    tag: []const u8,
    evidence: TestEvidence,
};

test "renders typed model candidates by provider family and typed gap" {
    const allocator = std.testing.allocator;
    var rows = [_]TestRow{
        .{
            .provider = "cloudflare",
            .tag = "DNS Records",
            .evidence = .{
                .l2_read_evidence = 3,
                .l3_generic_inventory_candidates = 3,
                .l3_typed_table_evidence = 2,
            },
        },
        .{
            .provider = "hostinger",
            .tag = "VPS: Virtual machine",
            .evidence = .{
                .l2_read_evidence = 5,
                .l3_generic_inventory_candidates = 5,
                .l3_typed_table_evidence = 5,
            },
        },
        .{
            .provider = "cloudflare",
            .tag = "Workers",
            .evidence = .{
                .l2_read_evidence = 2,
                .l3_generic_inventory_candidates = 2,
                .l3_typed_table_evidence = 0,
            },
        },
    };

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    const text_rows: []TestRow = rows[0..];
    try writeText(allocator, text_rows, .{ .provider = .all, .family = .dns, .limit = 5 }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio typed model candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "filter=all focus=control-plane family=dns") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "summary: L3_generic_rows=3 control_plane_rows=2 outside_control_plane_rows=1 typed_gap=3 control_plane_typed_gap=1 outside_control_plane_typed_gap=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | DNS Records: typed_gap=1 L3_generic=3 typed=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "scope=control-plane required_for_goal=true next_action=promote_control_plane_inventory_to_typed_model") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "review-bundle: cloudio coverage workplan cloudflare --family dns --limit 5 --candidate-limit 10 --bundle --plans --json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "focus_filtered_rows_hidden=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "family_filtered_rows_hidden=1") != null);

    var json_rows = rows;
    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    const json_slice: []TestRow = json_rows[0..];
    try writeJson(allocator, json_slice, .{ .provider = .all, .limit = 0, .include_complete = true }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_typed_model_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"generic_inventory_rows\":3,\"control_plane_generic_inventory_rows\":2,\"outside_control_plane_generic_inventory_rows\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scope\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"required_for_goal\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"next_action\":\"promote_control_plane_inventory_to_typed_model\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scope\":\"outside-control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"required_for_goal\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"next_action\":\"optional_generic_inventory_modeling\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"typed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage routes cloudflare 'DNS Records' --support partial --mode read --detail\"") != null);
}
