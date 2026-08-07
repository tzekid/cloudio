const std = @import("std");
const app_system_control = @import("app_system_control");
const core_json = @import("core_json");
const db_store = @import("db_store");

pub const Context = struct {
    gpa: std.mem.Allocator,
    db: *db_store.Db,
    fresh_after_seconds: i64 = 600,
};

pub fn writeDnsRecordsJson(ctx: Context, domain: ?[]const u8, writer: *std.Io.Writer) !void {
    var zones = try ctx.db.cloudflare().cloudflareZoneRows(ctx.gpa, 50);
    defer zones.deinit(ctx.gpa);
    var zone_id: []const u8 = "";
    if (domain) |wanted| {
        for (zones.items) |zone| {
            if (std.mem.eql(u8, zone.name, wanted)) zone_id = zone.id;
        }
    } else if (zones.items.len > 0) {
        zone_id = zones.items[0].id;
    }

    var rows = try ctx.db.cloudflare().cloudflareDnsRecordRows(ctx.gpa, 1000);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"kind\":\"dns_records\",");
    try core_json.writeStringField(writer, "zone_id", zone_id, true);
    try writer.writeAll("\"records\":[");
    var first = true;
    for (rows.items) |row| {
        if (domain) |wanted| {
            if (!dnsNameMatchesDomain(row.name, wanted)) continue;
        }
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", row.id, true);
        try core_json.writeStringField(writer, "zone_id", row.zone_id, true);
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "type", row.record_type, true);
        try core_json.writeStringField(writer, "content", row.content, true);
        const ttl: ?i64 = std.fmt.parseInt(i64, row.ttl, 10) catch null;
        try core_json.writeString(writer, "ttl");
        try writer.writeByte(':');
        if (ttl) |value| try writer.print("{d}", .{value}) else try writer.writeAll("null");
        try writer.writeByte(',');
        try core_json.writeString(writer, "proxied");
        try writer.writeByte(':');
        if (std.mem.eql(u8, row.proxied, "true")) {
            try writer.writeAll("true");
        } else if (std.mem.eql(u8, row.proxied, "false")) {
            try writer.writeAll("false");
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn writeContainersJson(ctx: Context, writer: *std.Io.Writer) !void {
    var rows = try ctx.db.system().containerRows(ctx.gpa, 200);
    defer rows.deinit(ctx.gpa);
    const observation_optional = try ctx.db.latestObservation(ctx.gpa, "system", "containers");
    defer if (observation_optional) |observation| observation.deinit(ctx.gpa);
    const freshness = containerFreshness(observation_optional, ctx.fresh_after_seconds);
    const capability_available = if (observation_optional) |observation|
        std.mem.eql(u8, observation.attempt_status, "ok")
    else
        false;
    const capability_reason: []const u8 = if (capability_available)
        "Container runtime access was confirmed by the latest collection."
    else if (observation_optional) |observation|
        if (observation.hasSuccessfulObservation())
            "Container actions are unavailable because the latest collection failed; last-good rows are read-only."
        else
            "Container actions are unavailable because the runtime has not completed a successful collection."
    else
        "Container actions are unavailable until the runtime is refreshed successfully.";

    try writer.writeAll("{\"kind\":\"container_observation\",\"source\":\"local-command\",");
    try core_json.writeStringField(writer, "freshness", freshness, true);
    try writer.writeAll("\"observed_at\":");
    if (observation_optional) |observation| {
        if (observation.hasSuccessfulObservation()) try core_json.writeString(writer, observation.observed_at) else try writer.writeAll("null");
    } else try writer.writeAll("null");
    try writer.writeAll(",\"age_seconds\":");
    if (observation_optional) |observation| {
        if (observation.age_seconds >= 0) try writer.print("{d}", .{observation.age_seconds}) else try writer.writeAll("null");
    } else try writer.writeAll("null");
    try writer.writeAll(",\"collection\":{");
    if (observation_optional) |observation| {
        try core_json.writeStringField(writer, "status", observation.attempt_status, true);
        try core_json.writeStringField(writer, "attempted_at", observation.attempted_at, true);
        try core_json.writeStringField(writer, "summary", observation.attempt_summary, false);
    } else {
        try core_json.writeStringField(writer, "status", "unavailable", true);
        try core_json.writeNullableStringField(writer, "attempted_at", null, true);
        try core_json.writeStringField(writer, "summary", "No collection has run.", false);
    }
    try writer.writeAll("},\"capability\":{");
    try core_json.writeBoolField(writer, "available", capability_available, true);
    try core_json.writeStringField(writer, "reason", capability_reason, false);
    try writer.writeAll("},\"containers\":[");
    for (rows.items, 0..) |row, index| {
        if (index != 0) try writer.writeByte(',');
        const state = app_system_control.containerState(row.status);
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "name", row.name, true);
        try core_json.writeStringField(writer, "image", row.image, true);
        try core_json.writeStringField(writer, "state", state.label(), true);
        try core_json.writeStringField(writer, "status", row.status, true);
        try core_json.writeStringField(writer, "ports", row.ports, true);
        try core_json.writeStringField(writer, "observed_at", row.updated_at, true);
        try writer.writeAll("\"actions\":{");
        const safe_target = app_system_control.isSafeContainerName(row.name);
        try core_json.writeBoolField(writer, "start", capability_available and safe_target and app_system_control.containerActionAllowed(state, .start), true);
        try core_json.writeBoolField(writer, "stop", capability_available and safe_target and app_system_control.containerActionAllowed(state, .stop), true);
        try core_json.writeBoolField(writer, "restart", capability_available and safe_target and app_system_control.containerActionAllowed(state, .restart), false);
        try writer.writeByte('}');
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn containerFreshness(observation: ?db_store.Observation, fresh_after_seconds: i64) []const u8 {
    const value = observation orelse return "unavailable";
    if (!value.hasSuccessfulObservation()) return "unavailable";
    if (!std.mem.eql(u8, value.attempt_status, "ok")) return "stale";
    return if (value.age_seconds >= 0 and value.age_seconds <= @max(fresh_after_seconds, 1)) "current" else "stale";
}

fn dnsNameMatchesDomain(name: []const u8, domain: []const u8) bool {
    if (std.mem.eql(u8, name, domain)) return true;
    return name.len > domain.len + 1 and
        std.mem.endsWith(u8, name, domain) and
        name[name.len - domain.len - 1] == '.';
}

test "DNS domain matching respects label boundaries" {
    try std.testing.expect(dnsNameMatchesDomain("api.example.com", "example.com"));
    try std.testing.expect(!dnsNameMatchesDomain("notexample.com", "example.com"));
}
