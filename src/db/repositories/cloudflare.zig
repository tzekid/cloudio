const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");
const models = @import("../models.zig");

const Allocator = std.mem.Allocator;
const DbError = models.DbError;
const NameValueRow = models.NameValueRow;
const NameValueRows = models.NameValueRows;
const TopologyRow = models.TopologyRow;
const TopologyRows = models.TopologyRows;
const CloudflareAccountRow = models.CloudflareAccountRow;
const CloudflareAccountRows = models.CloudflareAccountRows;
const CloudflareZoneRow = models.CloudflareZoneRow;
const CloudflareZoneRows = models.CloudflareZoneRows;
const CloudflareDnsRecordRow = models.CloudflareDnsRecordRow;
const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
const ContainerRow = models.ContainerRow;
const ContainerRows = models.ContainerRows;
const HostingerVpsRow = models.HostingerVpsRow;
const HostingerVpsRows = models.HostingerVpsRows;
const bindI64 = helpers.bindI64;
const bindI64Opt = helpers.bindI64Opt;
const bindBoolOpt = helpers.bindBoolOpt;
const bindText = helpers.bindText;
const bindTextOpt = helpers.bindTextOpt;
const stepDone = helpers.stepDone;
const deinitNameValueList = helpers.deinitNameValueList;
const deinitTopologyRowList = helpers.deinitTopologyRowList;
const deinitCloudflareAccountRowList = helpers.deinitCloudflareAccountRowList;
const deinitCloudflareZoneRowList = helpers.deinitCloudflareZoneRowList;
const deinitCloudflareDnsRecordRowList = helpers.deinitCloudflareDnsRecordRowList;
const deinitHostingerVpsRowList = helpers.deinitHostingerVpsRowList;
const cloudflareAccountRowFromStmt = helpers.cloudflareAccountRowFromStmt;
const cloudflareZoneRowFromStmt = helpers.cloudflareZoneRowFromStmt;
const cloudflareDnsRecordRowFromStmt = helpers.cloudflareDnsRecordRowFromStmt;
const hostingerVpsRowFromStmt = helpers.hostingerVpsRowFromStmt;
const nameValueRowFromStmt = helpers.nameValueRowFromStmt;
const topologyRowFromStmt = helpers.topologyRowFromStmt;
const dupeColumn = helpers.dupeColumn;
const positiveLimit = helpers.positiveLimit;
const columnText = helpers.columnText;
const isKnownTable = helpers.isKnownTable;

pub const Repository = struct {
    handle: *sqlite.sqlite3,

    fn prepare(self: Repository, sql: []const u8) !*sqlite.sqlite3_stmt {
        return helpers.prepare(self.handle, sql);
    }

    pub fn upsertCloudflareAccount(self: Repository, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_accounts(id, name, type, status, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, type=excluded.type, status=excluded.status, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, typ);
        try bindTextOpt(stmt, 4, status);
        try bindText(stmt, 5, raw);
        try stepDone(stmt);
    }

    pub fn upsertCloudflareZone(self: Repository, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_zones(id, name, account_id, status, paused, type, name_servers, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, account_id=excluded.account_id, status=excluded.status, paused=excluded.paused, type=excluded.type, name_servers=excluded.name_servers, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, account_id);
        try bindTextOpt(stmt, 4, status);
        try bindBoolOpt(stmt, 5, paused);
        try bindTextOpt(stmt, 6, typ);
        try bindTextOpt(stmt, 7, name_servers);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn upsertDnsRecord(self: Repository, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO cloudflare_dns_records(id, zone_id, name, type, content, ttl, proxied, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET zone_id=excluded.zone_id, name=excluded.name, type=excluded.type, content=excluded.content, ttl=excluded.ttl, proxied=excluded.proxied, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindText(stmt, 2, zone_id);
        try bindTextOpt(stmt, 3, name);
        try bindTextOpt(stmt, 4, typ);
        try bindTextOpt(stmt, 5, content);
        try bindI64Opt(stmt, 6, ttl);
        try bindBoolOpt(stmt, 7, proxied);
        try bindText(stmt, 8, raw);
        try stepDone(stmt);
    }

    pub fn deleteDnsRecordsForZone(self: Repository, zone_id: []const u8) !void {
        const stmt = try self.prepare("DELETE FROM cloudflare_dns_records WHERE zone_id = ?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, zone_id);
        try stepDone(stmt);
    }

    pub fn cloudflareAccountRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareAccountRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(type,''), COALESCE(status,''), updated_at
            \\FROM cloudflare_accounts
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareAccountRow).empty;
        errdefer deinitCloudflareAccountRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareAccountRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareZoneRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareZoneRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(account_id,''), COALESCE(status,''),
            \\       CASE WHEN paused IS NULL THEN '' WHEN paused != 0 THEN 'true' ELSE 'false' END,
            \\       COALESCE(type,''), COALESCE(name_servers,''), updated_at
            \\FROM cloudflare_zones
            \\ORDER BY updated_at DESC, name, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareZoneRow).empty;
        errdefer deinitCloudflareZoneRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareZoneRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    pub fn cloudflareDnsRecordRows(self: Repository, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(zone_id,''), COALESCE(name,''), COALESCE(type,''), COALESCE(content,''),
            \\       COALESCE(CAST(ttl AS TEXT), ''),
            \\       CASE WHEN proxied IS NULL THEN '' WHEN proxied != 0 THEN 'true' ELSE 'false' END,
            \\       updated_at
            \\FROM cloudflare_dns_records
            \\ORDER BY updated_at DESC, name, type, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(CloudflareDnsRecordRow).empty;
        errdefer deinitCloudflareDnsRecordRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try cloudflareDnsRecordRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }

    fn nameValueRows(self: Repository, gpa: Allocator, sql: []const u8) !NameValueRows {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        var rows = std.ArrayList(NameValueRow).empty;
        errdefer deinitNameValueList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try nameValueRowFromStmt(gpa, stmt);
            rows.append(gpa, row) catch |err| {
                row.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try rows.toOwnedSlice(gpa) };
    }
};
