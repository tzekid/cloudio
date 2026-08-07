const std = @import("std");
const app_dns = @import("app_dns");
const app_vps = @import("app_vps");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn dnsRecordsGet(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_dns.writeJson(context.dns(ctx), request.query("domain"), writer);
    return 200;
}

pub fn dnsRecordsPost(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const domain = common.strField(parsed.value, "domain") orelse return common.badRequest(writer);
    const record = core_json.field(parsed.value, "record") orelse return common.badRequest(writer);
    const outcome = try app_dns.mutate(context.dns(ctx), .create, domain, null, parseDnsRecord(record) orelse return common.badRequest(writer));
    try app_dns.writeMutationJson(outcome, writer);
    return outcome.status();
}

pub fn dnsRecordsPut(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const domain = common.strField(parsed.value, "domain") orelse return common.badRequest(writer);
    const record_id = common.strField(parsed.value, "record_id") orelse return common.badRequest(writer);
    const record = core_json.field(parsed.value, "record") orelse return common.badRequest(writer);
    const outcome = try app_dns.mutate(context.dns(ctx), .update, domain, record_id, parseDnsRecord(record) orelse return common.badRequest(writer));
    try app_dns.writeMutationJson(outcome, writer);
    return outcome.status();
}

pub fn dnsRecordsDelete(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const domain = request.query("domain") orelse return common.badRequest(writer);
    const record_id = request.query("record_id") orelse return common.badRequest(writer);
    const outcome = try app_dns.mutate(context.dns(ctx), .delete, domain, record_id, null);
    try app_dns.writeMutationJson(outcome, writer);
    return outcome.status();
}

fn parseDnsRecord(value: std.json.Value) ?app_dns.RecordInput {
    if (value != .object) return null;
    const record_type = core_json.fieldString(value, "type") orelse return null;
    const name = core_json.fieldString(value, "name") orelse return null;
    const content = core_json.fieldString(value, "content") orelse return null;
    const ttl = core_json.fieldInt(value, "ttl") orelse return null;
    const proxied = core_json.fieldBool(value, "proxied") orelse false;
    return .{
        .record_type = record_type,
        .name = name,
        .content = content,
        .ttl = ttl,
        .proxied = proxied,
    };
}

pub fn vpsGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_vps.writeJson(context.vps(ctx), writer);
    return 200;
}

pub fn vpsRefresh(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_vps.refresh(context.vps(ctx));
    try app_vps.writeJson(context.vps(ctx), writer);
    return 200;
}

pub fn vpsAction(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const vm_id = common.strField(parsed.value, "vm_id") orelse return common.badRequest(writer);
    const action_text = common.strField(parsed.value, "action") orelse return common.badRequest(writer);
    const action = std.meta.stringToEnum(app_vps.Action, action_text) orelse return common.badRequest(writer);
    var vps_ctx = context.vps(ctx);
    vps_ctx.write_meta = ctx.write_meta;
    const result = try app_vps.mutate(vps_ctx, vm_id, action);
    defer result.deinit(ctx.gpa);
    try app_vps.writeMutationJson(result, writer);
    return result.outcome.status();
}
