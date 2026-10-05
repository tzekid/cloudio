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

    pub fn upsertHostingerVps(self: Repository, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
        const stmt = try self.prepare(
            \\INSERT INTO hostinger_vps(id, name, status, ipv4, plan, raw_json, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            \\ON CONFLICT(id) DO UPDATE SET name=excluded.name, status=excluded.status, ipv4=excluded.ipv4, plan=excluded.plan, raw_json=excluded.raw_json, updated_at=CURRENT_TIMESTAMP
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindTextOpt(stmt, 2, name);
        try bindTextOpt(stmt, 3, status);
        try bindTextOpt(stmt, 4, ipv4);
        try bindTextOpt(stmt, 5, plan);
        try bindText(stmt, 6, raw);
        try stepDone(stmt);
    }

    pub fn hostingerVpsRows(self: Repository, gpa: Allocator, limit: i64) !HostingerVpsRows {
        const stmt = try self.prepare(
            \\SELECT id, COALESCE(name,''), COALESCE(status,''), COALESCE(ipv4,''), COALESCE(plan,''), updated_at
            \\FROM hostinger_vps
            \\ORDER BY updated_at DESC, id
            \\LIMIT ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, positiveLimit(limit, 200));
        var rows = std.ArrayList(HostingerVpsRow).empty;
        errdefer deinitHostingerVpsRowList(&rows, gpa);
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            var row = try hostingerVpsRowFromStmt(gpa, stmt);
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
