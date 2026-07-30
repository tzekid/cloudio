const std = @import("std");
const app_provider_writes = @import("app_provider_writes");
const app_web_resources = @import("app_web_resources");
const core_json = @import("core_json");
const http = @import("http");
const common = @import("../common.zig");
const context = @import("../context.zig");

fn view(ctx: context.Context) app_web_resources.Context {
    return .{ .gpa = ctx.gpa, .db = ctx.db };
}

pub fn dnsRecordsGet(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_web_resources.writeDnsRecordsJson(view(ctx), request.query("domain"), writer);
    return 200;
}

pub fn dnsRecordsPost(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const zone_id = common.strField(parsed.value, "zone_id") orelse return common.badRequest(writer);
    const record = core_json.field(parsed.value, "record") orelse return common.badRequest(writer);
    const record_json = try core_json.stringifyValue(ctx.gpa, record);
    defer ctx.gpa.free(record_json);
    try app_provider_writes.dnsRecordCreate(context.provider(ctx), zone_id, record_json, writer);
    return 200;
}

pub fn dnsRecordsPut(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const zone_id = common.strField(parsed.value, "zone_id") orelse return common.badRequest(writer);
    const record_id = common.strField(parsed.value, "record_id") orelse return common.badRequest(writer);
    const record = core_json.field(parsed.value, "record") orelse return common.badRequest(writer);
    const record_json = try core_json.stringifyValue(ctx.gpa, record);
    defer ctx.gpa.free(record_json);
    try app_provider_writes.dnsRecordUpdate(context.provider(ctx), zone_id, record_id, record_json, writer);
    return 200;
}

pub fn dnsRecordsDelete(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const zone_id = request.query("zone_id") orelse return common.badRequest(writer);
    const record_id = request.query("record_id") orelse return common.badRequest(writer);
    try app_provider_writes.dnsRecordDelete(context.provider(ctx), zone_id, record_id, writer);
    return 200;
}

pub fn cachePurge(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const zone_id = common.strField(parsed.value, "zone_id") orelse return common.badRequest(writer);
    try app_provider_writes.cachePurgeEverything(context.provider(ctx), zone_id, writer);
    return 200;
}

pub fn zoneSetting(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const zone_id = common.strField(parsed.value, "zone_id") orelse return common.badRequest(writer);
    const setting = common.strField(parsed.value, "setting") orelse return common.badRequest(writer);
    const value = core_json.field(parsed.value, "value") orelse return common.badRequest(writer);
    const value_json = try core_json.stringifyValue(ctx.gpa, value);
    defer ctx.gpa.free(value_json);
    try app_provider_writes.zoneSettingUpdate(context.provider(ctx), zone_id, setting, value_json, writer);
    return 200;
}

pub fn vpsGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_web_resources.writeVpsJson(view(ctx), writer);
    return 200;
}

pub fn vpsAction(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const vm_id = common.strField(parsed.value, "vm_id") orelse return common.badRequest(writer);
    const action_text = common.strField(parsed.value, "action") orelse return common.badRequest(writer);
    const action = std.meta.stringToEnum(app_provider_writes.VpsAction, action_text) orelse return common.badRequest(writer);
    try app_provider_writes.vpsAction(context.provider(ctx), vm_id, action, writer);
    return 200;
}

pub fn firewallsGet(ctx: context.Context, _: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    try app_web_resources.writeFirewallsJson(view(ctx), writer);
    return 200;
}

pub fn firewallRulePost(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const firewall_id = common.strField(parsed.value, "firewall_id") orelse return common.badRequest(writer);
    const rule = core_json.field(parsed.value, "rule") orelse return common.badRequest(writer);
    const rule_json = try core_json.stringifyValue(ctx.gpa, rule);
    defer ctx.gpa.free(rule_json);
    try app_provider_writes.firewallRuleCreate(context.provider(ctx), firewall_id, rule_json, writer);
    return 200;
}

pub fn firewallRulePut(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const firewall_id = common.strField(parsed.value, "firewall_id") orelse return common.badRequest(writer);
    const rule_id = common.strField(parsed.value, "rule_id") orelse return common.badRequest(writer);
    const rule = core_json.field(parsed.value, "rule") orelse return common.badRequest(writer);
    const rule_json = try core_json.stringifyValue(ctx.gpa, rule);
    defer ctx.gpa.free(rule_json);
    try app_provider_writes.firewallRuleUpdate(context.provider(ctx), firewall_id, rule_id, rule_json, writer);
    return 200;
}

pub fn firewallRuleDelete(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    const firewall_id = request.query("firewall_id") orelse return common.badRequest(writer);
    const rule_id = request.query("rule_id") orelse return common.badRequest(writer);
    try app_provider_writes.firewallRuleDelete(context.provider(ctx), firewall_id, rule_id, writer);
    return 200;
}

pub fn firewallSync(ctx: context.Context, request: http.Request, _: http.Params, writer: *std.Io.Writer, _: *std.Io.Writer) !u16 {
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return common.badRequest(writer);
    defer parsed.deinit();
    const firewall_id = common.strField(parsed.value, "firewall_id") orelse return common.badRequest(writer);
    const vm_id = common.strField(parsed.value, "vm_id") orelse return common.badRequest(writer);
    try app_provider_writes.firewallSync(context.provider(ctx), firewall_id, vm_id, writer);
    return 200;
}
