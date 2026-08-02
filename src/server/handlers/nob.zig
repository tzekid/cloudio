const std = @import("std");
const app_nob_projects = @import("app_nob_projects");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn list(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_nob_projects.writeListJson(context.nob(ctx), writer);
    return 200;
}

pub fn details(ctx: context.Context, _: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    try app_nob_projects.writeShowJson(context.nob(ctx), reference, writer);
    return 200;
}

pub fn scan(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    if (!ctx.config.nob_enabled) {
        try writer.writeAll("{\"error\":\"nob_disabled\"}\n");
        return 409;
    }
    const result = try app_nob_projects.scan(context.nob(ctx), ctx.io, ctx.config.projects_root, ctx.config.nob_scan_depth);
    try writer.writeByte('{');
    try core_json.writeStringField(writer, "kind", "nob_scan", true);
    try core_json.writeCountField(writer, "projects_seen", result.projects_seen, true);
    try core_json.writeCountField(writer, "valid", result.valid, true);
    try core_json.writeCountField(writer, "invalid", result.invalid, true);
    try core_json.writeCountField(writer, "candidates", result.candidates, true);
    try core_json.writeCountField(writer, "conflicts", result.conflicts, true);
    try core_json.writeCountField(writer, "missing", result.missing, false);
    try writer.writeAll("}\n");
    return 200;
}

pub fn action(ctx: context.Context, request: http.Request, params: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const reference = params.get("id") orelse return common.badRequest(writer);
    const operation = params.get("action") orelse return common.badRequest(writer);
    const actor = ctx.auth_user_id orelse "authenticated-web";
    if (std.mem.eql(u8, operation, "trust")) {
        var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
        defer parsed.deinit();
        const digest = common.strField(parsed.value, "manifest_sha256") orelse return common.badRequest(writer);
        try app_nob_projects.trust(context.nob(ctx), reference, digest, actor);
    } else if (std.mem.eql(u8, operation, "revoke")) {
        try app_nob_projects.revoke(context.nob(ctx), reference, actor);
    } else {
        return error.UnknownRoute;
    }
    try app_nob_projects.writeShowJson(context.nob(ctx), reference, writer);
    return 200;
}
