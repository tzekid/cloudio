const std = @import("std");
const app_provider_coverage_workplan = @import("app_provider_coverage_workplan");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;

pub const WorkplanFamily = app_provider_coverage_workplan.WorkplanFamily;

pub const TypedModelOptions = struct {
    provider: provider_routes.ProviderFilter = .all,
    family: WorkplanFamily = .all,
    limit: usize = 25,
    include_complete: bool = false,
};

pub fn writeText(gpa: Allocator, rows: anytype, options: TypedModelOptions, writer: anytype) !void {
    sortRows(rows);
    try writer.writeAll("Cloudio typed model candidates\n");
    try writer.writeAll("evidence: L3 generic inventory rows with missing or thin typed-table projections\n");
    try writer.writeAll("rank: typed_gap + generic_inventory_candidates, grouped by provider family\n");
    try writer.print("filter={s} family={s}", .{ options.provider.name(), options.family.name() });
    if (options.include_complete) try writer.writeAll(" include_complete=true");
    try writer.writeAll(" limit=");
    if (options.limit == 0) {
        try writer.writeAll("all\n");
    } else {
        try writer.print("{d}\n", .{options.limit});
    }

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_complete: usize = 0;
    var hidden_family: usize = 0;
    for (rows) |row| {
        if (!familyIncludes(options.family, row)) {
            if (row.evidence.l3_generic_inventory_candidates != 0) hidden_family += 1;
            continue;
        }
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!options.include_complete and typedGap(row) == 0) {
            hidden_complete += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeTextRow(gpa, row, writer);
    }

    if (visible == 0) {
        try writer.writeAll("no typed model candidates for filter\n");
    } else {
        if (omitted != 0) try writer.print("omitted={d}\n", .{omitted});
        if (hidden_family != 0) try writer.print("family_filtered_rows_hidden={d}\n", .{hidden_family});
        if (hidden_complete != 0) try writer.print("typed_or_complete_rows_hidden={d}\n", .{hidden_complete});
    }
}

pub fn writeJson(gpa: Allocator, rows: anytype, options: TypedModelOptions, writer: anytype) !void {
    sortRows(rows);
    try writer.writeByte('{');
    try writeJsonField(writer, "kind", "coverage_typed_model_candidates", true);
    try writeJsonField(writer, "filter", options.provider.name(), true);
    try writeJsonField(writer, "family", options.family.name(), true);
    try writeJsonCountField(writer, "limit", options.limit, true);
    try writeJsonBoolField(writer, "include_complete", options.include_complete, true);
    try writeJsonField(writer, "evidence", "L3 generic inventory rows with missing or thin typed-table projections", true);
    try writeJsonField(writer, "rank", "typed_gap + generic_inventory_candidates, grouped by provider family", true);
    try writer.writeAll("\"items\":[");

    var visible: usize = 0;
    var omitted: usize = 0;
    var hidden_complete: usize = 0;
    var hidden_family: usize = 0;
    var first = true;
    for (rows) |row| {
        if (!familyIncludes(options.family, row)) {
            if (row.evidence.l3_generic_inventory_candidates != 0) hidden_family += 1;
            continue;
        }
        if (row.evidence.l3_generic_inventory_candidates == 0) continue;
        if (!options.include_complete and typedGap(row) == 0) {
            hidden_complete += 1;
            continue;
        }
        if (options.limit != 0 and visible >= options.limit) {
            omitted += 1;
            continue;
        }
        visible += 1;
        try writeMaybeJsonComma(writer, &first);
        try writeJsonRow(gpa, row, writer);
    }

    try writer.writeAll("],");
    try writeJsonCountField(writer, "visible", visible, true);
    try writeJsonCountField(writer, "omitted", omitted, true);
    try writeJsonCountField(writer, "family_filtered_rows_hidden", hidden_family, true);
    try writeJsonCountField(writer, "typed_or_complete_rows_hidden", hidden_complete, false);
    try writer.writeByte('}');
    try writer.writeByte('\n');
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
    try writer.print("{s} | {s}: typed_gap={d} L3_generic={d} typed={d} L2_read_evidence={d} family={s}\n", .{
        row.provider,
        row.tag,
        typedGap(row),
        row.evidence.l3_generic_inventory_candidates,
        row.evidence.l3_typed_table_evidence,
        row.evidence.l2_read_evidence,
        if (family) |value| value.name() else "-",
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
    try writeJsonCountField(writer, "typed_gap", typedGap(row), true);
    try writeJsonCountField(writer, "l3_generic_inventory_candidates", row.evidence.l3_generic_inventory_candidates, true);
    try writeJsonCountField(writer, "l3_typed_table_evidence", row.evidence.l3_typed_table_evidence, true);
    try writeJsonCountField(writer, "l2_read_evidence", row.evidence.l2_read_evidence, true);
    try writeJsonField(writer, "status", if (typedGap(row) == 0) "typed" else "candidate", true);
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

fn tagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    return app_provider_coverage_workplan.tagFamily(provider, tag);
}

fn writeJsonField(writer: anytype, name: []const u8, value: []const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try core_json.writeString(writer, value);
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonCountField(writer: anytype, name: []const u8, value: usize, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.print(":{d}", .{value});
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
    if (trailing_comma) try writer.writeByte(',');
}

fn writeJsonNullableStringField(writer: anytype, name: []const u8, value: ?[]const u8, trailing_comma: bool) !void {
    try core_json.writeString(writer, name);
    try writer.writeByte(':');
    if (value) |text| {
        try core_json.writeString(writer, text);
    } else {
        try writer.writeAll("null");
    }
    if (trailing_comma) try writer.writeByte(',');
}

fn writeMaybeJsonComma(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
    } else {
        try writer.writeByte(',');
    }
}

fn writeShellArg(writer: anytype, value: []const u8) !void {
    try writer.writeByte('\'');
    for (value) |byte| {
        if (byte == '\'') {
            try writer.writeAll("'\\''");
        } else {
            try writer.writeByte(byte);
        }
    }
    try writer.writeByte('\'');
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
            .evidence = .{},
        },
    };

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    const text_rows: []TestRow = rows[0..];
    try writeText(allocator, text_rows, .{ .provider = .all, .family = .dns, .limit = 5 }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio typed model candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | DNS Records: typed_gap=1 L3_generic=3 typed=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "review-bundle: cloudio coverage workplan cloudflare --family dns --limit 5 --candidate-limit 10 --bundle --plans --json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "family_filtered_rows_hidden=5") == null);

    var json_rows = rows;
    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    const json_slice: []TestRow = json_rows[0..];
    try writeJson(allocator, json_slice, .{ .provider = .all, .limit = 0, .include_complete = true }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_typed_model_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"typed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage routes cloudflare 'DNS Records' --support partial --mode read --detail\"") != null);
}
