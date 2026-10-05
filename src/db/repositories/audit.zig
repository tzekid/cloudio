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

    pub fn insertAudit(self: Repository, action: []const u8, status: []const u8, detail: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO audit_events(action, status, detail) VALUES (?, ?, ?)");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, action);
        try bindText(stmt, 2, status);
        try bindText(stmt, 3, detail);
        try stepDone(stmt);
    }

};
