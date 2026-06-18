const std = @import("std");
const app_provider_coverage_actual_inputs = @import("app_provider_coverage_actual_inputs");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const provider_capabilities = @import("provider_capabilities");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const ActualCaptureHints = app_provider_coverage_actual_inputs.Hints;
const actualCapturePathParamHint = app_provider_coverage_actual_inputs.actualCapturePathParamHint;
const actualCaptureQueryParamHint = app_provider_coverage_actual_inputs.actualCaptureQueryParamHint;
const writeShellArg = app_provider_coverage_render.writeShellArg;

pub fn actualCaptureCommand(gpa: Allocator, route: provider_routes.Route, hints: ActualCaptureHints) ![]u8 {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("cloudio route capture {s}", .{route.provider.name()});
    if (route.operation_id) |id| {
        try writer.print(" --operation {s}", .{id});
    } else {
        try writer.print(" --method {s} --path ", .{route.method.name()});
        try writeShellArg(writer, route.path_template);
    }
    try writeActualPathParams(writer, route, hints);
    try writeActualQueryParams(gpa, writer, route, hints);
    try writeActualRequiredParamPlaceholders(writer, "--header-param", route.header_params);
    if (routePaginationKind(route) != null) try writer.writeAll(" --paginate");
    if (provider_capabilities.routeDiagnosticReadSupported(route)) try writer.writeAll(" --diagnostic");
    return try out.toOwnedSlice();
}

fn writeActualPathParams(writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        try writer.print(" --path-param {s}=", .{param.name});
        if (actualCapturePathParamHint(route, param.name, hints)) |hint| {
            try writeShellArg(writer, hint);
        } else {
            try writer.print("REPLACE_{s}", .{param.name});
        }
    }
}

fn writeActualQueryParams(gpa: Allocator, writer: anytype, route: provider_routes.Route, hints: ActualCaptureHints) !void {
    for (route.query_params) |param| {
        if (!param.required) continue;
        try writer.print(" --query-param {s}=", .{param.name});
        if (try actualCaptureQueryParamHint(gpa, route, param.name, hints)) |hint| {
            defer gpa.free(hint);
            try writeShellArg(writer, hint);
        } else {
            try writer.print("REPLACE_{s}", .{param.name});
        }
    }
}

fn writeActualRequiredParamPlaceholders(writer: anytype, option: []const u8, params: []const provider_routes.RouteParam) !void {
    for (params) |param| {
        if (!param.required) continue;
        try writer.print(" {s} {s}=REPLACE_{s}", .{ option, param.name, param.name });
    }
}

fn routePaginationKind(route: provider_routes.Route) ?[]const u8 {
    return provider_capabilities.routePaginationName(route);
}
