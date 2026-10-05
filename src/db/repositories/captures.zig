const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");
const models = @import("../models.zig");

const Allocator = std.mem.Allocator;
const DbError = models.DbError;
const Observation = models.Observation;
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

    pub fn insertSnapshot(self: Repository, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
        const stmt = try self.prepare(
            \\INSERT INTO snapshots(source, kind, target, status, summary, raw_json, raw_text)
            \\VALUES (?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindText(stmt, 2, kind);
        try bindTextOpt(stmt, 3, target);
        try bindText(stmt, 4, status);
        try bindTextOpt(stmt, 5, summary);
        try bindTextOpt(stmt, 6, raw_json);
        try bindTextOpt(stmt, 7, raw_text);
        try stepDone(stmt);
        return sqlite.sqlite3_last_insert_rowid(self.handle);
    }

    pub fn latestObservation(self: Repository, gpa: Allocator, source: []const u8, kind: []const u8) !?Observation {
        const stmt = try self.prepare(
            \\SELECT latest.source,
            \\       latest.kind,
            \\       latest.status,
            \\       COALESCE(latest.summary, ''),
            \\       latest.captured_at,
            \\       COALESCE((
            \\         SELECT successful.captured_at
            \\         FROM snapshots AS successful
            \\         WHERE successful.source = latest.source
            \\           AND successful.kind = latest.kind
            \\           AND successful.status = 'ok'
            \\         ORDER BY successful.id DESC
            \\         LIMIT 1
            \\       ), ''),
            \\       COALESCE(
            \\         CAST(strftime('%s','now') AS INTEGER) - CAST(strftime('%s', (
            \\           SELECT successful.captured_at
            \\           FROM snapshots AS successful
            \\           WHERE successful.source = latest.source
            \\             AND successful.kind = latest.kind
            \\             AND successful.status = 'ok'
            \\           ORDER BY successful.id DESC
            \\           LIMIT 1
            \\         )) AS INTEGER),
            \\         -1
            \\       )
            \\FROM snapshots AS latest
            \\WHERE latest.source = ? AND latest.kind = ?
            \\ORDER BY latest.id DESC
            \\LIMIT 1
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindText(stmt, 2, kind);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;

        const source_copy = try dupeColumn(gpa, stmt, 0);
        errdefer gpa.free(source_copy);
        const kind_copy = try dupeColumn(gpa, stmt, 1);
        errdefer gpa.free(kind_copy);
        const attempt_status = try dupeColumn(gpa, stmt, 2);
        errdefer gpa.free(attempt_status);
        const attempt_summary = try dupeColumn(gpa, stmt, 3);
        errdefer gpa.free(attempt_summary);
        const attempted_at = try dupeColumn(gpa, stmt, 4);
        errdefer gpa.free(attempted_at);
        const observed_at = try dupeColumn(gpa, stmt, 5);
        errdefer gpa.free(observed_at);
        return .{
            .source = source_copy,
            .kind = kind_copy,
            .attempt_status = attempt_status,
            .attempt_summary = attempt_summary,
            .attempted_at = attempted_at,
            .observed_at = observed_at,
            .age_seconds = sqlite.sqlite3_column_int64(stmt, 6),
        };
    }

    pub fn latestObservationForTarget(
        self: Repository,
        gpa: Allocator,
        source: []const u8,
        kind: []const u8,
        target: []const u8,
    ) !?Observation {
        const stmt = try self.prepare(
            \\SELECT latest.source,
            \\       latest.kind,
            \\       latest.status,
            \\       COALESCE(latest.summary, ''),
            \\       latest.captured_at,
            \\       COALESCE((
            \\         SELECT successful.captured_at
            \\         FROM snapshots AS successful
            \\         WHERE successful.source = latest.source
            \\           AND successful.kind = latest.kind
            \\           AND COALESCE(successful.target, '') = COALESCE(latest.target, '')
            \\           AND successful.status = 'ok'
            \\         ORDER BY successful.id DESC LIMIT 1
            \\       ), ''),
            \\       COALESCE(
            \\         CAST(strftime('%s','now') AS INTEGER) - CAST(strftime('%s', (
            \\           SELECT successful.captured_at
            \\           FROM snapshots AS successful
            \\           WHERE successful.source = latest.source
            \\             AND successful.kind = latest.kind
            \\             AND COALESCE(successful.target, '') = COALESCE(latest.target, '')
            \\             AND successful.status = 'ok'
            \\           ORDER BY successful.id DESC LIMIT 1
            \\         )) AS INTEGER), -1
            \\       )
            \\FROM snapshots AS latest
            \\WHERE latest.source = ? AND latest.kind = ? AND COALESCE(latest.target, '') = ?
            \\ORDER BY latest.id DESC LIMIT 1
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, source);
        try bindText(stmt, 2, kind);
        try bindText(stmt, 3, target);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;

        const source_copy = try dupeColumn(gpa, stmt, 0);
        errdefer gpa.free(source_copy);
        const kind_copy = try dupeColumn(gpa, stmt, 1);
        errdefer gpa.free(kind_copy);
        const attempt_status = try dupeColumn(gpa, stmt, 2);
        errdefer gpa.free(attempt_status);
        const attempt_summary = try dupeColumn(gpa, stmt, 3);
        errdefer gpa.free(attempt_summary);
        const attempted_at = try dupeColumn(gpa, stmt, 4);
        errdefer gpa.free(attempted_at);
        const observed_at = try dupeColumn(gpa, stmt, 5);
        errdefer gpa.free(observed_at);
        return .{
            .source = source_copy,
            .kind = kind_copy,
            .attempt_status = attempt_status,
            .attempt_summary = attempt_summary,
            .attempted_at = attempted_at,
            .observed_at = observed_at,
            .age_seconds = sqlite.sqlite3_column_int64(stmt, 6),
        };
    }

};
