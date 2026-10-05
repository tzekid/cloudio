const std = @import("std");
const core_fs = @import("../core/fs.zig");
const sqlite = @import("sqlite");
const db_schema = @import("schema.zig");
const models = @import("models.zig");
const captures_repository = @import("repositories/captures.zig");
const audit_repository = @import("repositories/audit.zig");
const maintenance_repository = @import("repositories/maintenance.zig");
const cloudflare_repository = @import("repositories/cloudflare.zig");
const hostinger_repository = @import("repositories/hostinger.zig");
const system_repository = @import("repositories/system.zig");
const auth_repository = @import("repositories/auth.zig");
const nob_repository = @import("repositories/nob.zig");
const browser_run_repository = @import("repositories/browser_run.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
pub const DbError = models.DbError;
const Observation = models.Observation;
const NameValueRows = models.NameValueRows;
const TopologyRows = models.TopologyRows;
const ContainerRows = models.ContainerRows;
const ContainerRow = models.ContainerRow;
const CloudflareAccountRows = models.CloudflareAccountRows;
const CloudflareZoneRows = models.CloudflareZoneRows;
const CloudflareDnsRecordRows = models.CloudflareDnsRecordRows;
const HostingerVpsRows = models.HostingerVpsRows;

pub const Db = struct {
    handle: *sqlite.sqlite3,

    pub fn captures(self: *Db) captures_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn audit(self: *Db) audit_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn maintenance(self: *Db) maintenance_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn cloudflare(self: *Db) cloudflare_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn hostinger(self: *Db) hostinger_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn system(self: *Db) system_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn auth(self: *Db) auth_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn nob(self: *Db) nob_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn browserRun(self: *Db) browser_run_repository.Repository {
        return .{ .handle = self.handle };
    }

    pub fn open(io: Io, path: []const u8) !Db {
        try core_fs.ensureParentDir(io, path);
        if (path.len >= std.fs.max_path_bytes) return error.NameTooLong;
        var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        var handle: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open_v2(@ptrCast(&path_z), &handle, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqliteOpen;
        _ = sqlite.sqlite3_busy_timeout(handle.?, 5000);
        var foreign_key_error: [*c]u8 = null;
        if (sqlite.sqlite3_exec(handle.?, "PRAGMA foreign_keys=ON", null, null, &foreign_key_error) != sqlite.SQLITE_OK) {
            if (foreign_key_error != null) sqlite.sqlite3_free(foreign_key_error);
            _ = sqlite.sqlite3_close(handle.?);
            return DbError.SqliteExec;
        }
        return .{ .handle = handle.? };
    }

    pub fn close(self: *Db) void {
        _ = sqlite.sqlite3_close(self.handle);
    }

    pub fn initSchema(self: *Db) !void {
        try db_schema.apply(self.handle);
    }

    pub fn schemaVersion(self: *Db) !i64 {
        return try db_schema.latestAppliedVersion(self.handle);
    }

    pub fn exec(self: *Db, sql: []const u8) !void {
        var err: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err);
        if (rc != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return DbError.SqliteExec;
        }
    }

    pub fn prepare(self: *Db, sql: []const u8) !*sqlite.sqlite3_stmt {
        var stmt: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(self.handle, @ptrCast(sql.ptr), @intCast(sql.len), &stmt, null);
        if (rc != sqlite.SQLITE_OK) return DbError.SqlitePrepare;
        return stmt.?;
    }

    pub fn insertSnapshot(self: *Db, source: []const u8, kind: []const u8, target: ?[]const u8, status: []const u8, summary: ?[]const u8, raw_json: ?[]const u8, raw_text: ?[]const u8) !i64 {
        return self.captures().insertSnapshot(source, kind, target, status, summary, raw_json, raw_text);
    }
    pub fn insertAudit(self: *Db, action: []const u8, status: []const u8, detail: []const u8) !void {
        return self.audit().insertAudit(action, status, detail);
    }
    pub fn clear(self: *Db, table: []const u8) !void {
        return self.maintenance().clear(table);
    }
    pub fn countTable(self: *Db, table: []const u8) !i64 {
        return self.maintenance().countTable(table);
    }
    pub fn upsertCloudflareAccount(self: *Db, id: []const u8, name: ?[]const u8, typ: ?[]const u8, status: ?[]const u8, raw: []const u8) !void {
        return self.cloudflare().upsertCloudflareAccount(id, name, typ, status, raw);
    }
    pub fn upsertCloudflareZone(self: *Db, id: []const u8, name: ?[]const u8, account_id: ?[]const u8, status: ?[]const u8, paused: ?bool, typ: ?[]const u8, name_servers: ?[]const u8, raw: []const u8) !void {
        return self.cloudflare().upsertCloudflareZone(id, name, account_id, status, paused, typ, name_servers, raw);
    }
    pub fn upsertDnsRecord(self: *Db, id: []const u8, zone_id: []const u8, name: ?[]const u8, typ: ?[]const u8, content: ?[]const u8, ttl: ?i64, proxied: ?bool, raw: []const u8) !void {
        return self.cloudflare().upsertDnsRecord(id, zone_id, name, typ, content, ttl, proxied, raw);
    }
    pub fn upsertHostingerVps(self: *Db, id: []const u8, name: ?[]const u8, status: ?[]const u8, ipv4: ?[]const u8, plan: ?[]const u8, raw: []const u8) !void {
        return self.hostinger().upsertHostingerVps(id, name, status, ipv4, plan, raw);
    }
    pub fn upsertCaddySite(self: *Db, host: []const u8, source_path: []const u8, raw_block: ?[]const u8) !void {
        return self.system().upsertCaddySite(host, source_path, raw_block);
    }
    pub fn insertCaddyUpstream(self: *Db, host: []const u8, route: []const u8, upstream: []const u8) !void {
        return self.system().insertCaddyUpstream(host, route, upstream);
    }
    pub fn upsertProject(self: *Db, name: []const u8, source: []const u8, path: ?[]const u8, host: ?[]const u8, upstream: ?[]const u8, service: ?[]const u8, container: ?[]const u8, raw: ?[]const u8) !void {
        return self.system().upsertProject(name, source, path, host, upstream, service, container, raw);
    }
    pub fn upsertService(self: *Db, name: []const u8, scope: []const u8, state: ?[]const u8, sub_state: ?[]const u8, description: ?[]const u8, raw: []const u8) !void {
        return self.system().upsertService(name, scope, state, sub_state, description, raw);
    }
    pub fn insertSocket(self: *Db, proto: ?[]const u8, state: ?[]const u8, local_address: ?[]const u8, process: ?[]const u8, raw: []const u8) !void {
        return self.system().insertSocket(proto, state, local_address, process, raw);
    }
    pub fn upsertContainer(self: *Db, name: []const u8, image: ?[]const u8, status: ?[]const u8, ports: ?[]const u8, raw: []const u8) !void {
        return self.system().upsertContainer(name, image, status, ports, raw);
    }
    pub fn latestObservation(self: *Db, gpa: Allocator, source: []const u8, kind: []const u8) !?Observation {
        return self.captures().latestObservation(gpa, source, kind);
    }
    pub fn latestObservationForTarget(self: *Db, gpa: Allocator, source: []const u8, kind: []const u8, target: []const u8) !?Observation {
        return self.captures().latestObservationForTarget(gpa, source, kind, target);
    }
    pub fn topologyRows(self: *Db, gpa: Allocator, limit: i64) !TopologyRows {
        return self.system().topologyRows(gpa, limit);
    }
    pub fn serviceList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().serviceList(gpa);
    }
    pub fn containerRows(self: *Db, gpa: Allocator, limit: i64) !ContainerRows {
        return self.system().containerRows(gpa, limit);
    }
    pub fn containerRow(self: *Db, gpa: Allocator, name: []const u8) !?ContainerRow {
        return self.system().containerRow(gpa, name);
    }
    pub fn containerList(self: *Db, gpa: Allocator) !NameValueRows {
        return self.system().containerList(gpa);
    }
    pub fn cloudflareAccountRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareAccountRows {
        return self.cloudflare().cloudflareAccountRows(gpa, limit);
    }
    pub fn cloudflareZoneRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareZoneRows {
        return self.cloudflare().cloudflareZoneRows(gpa, limit);
    }
    pub fn cloudflareDnsRecordRows(self: *Db, gpa: Allocator, limit: i64) !CloudflareDnsRecordRows {
        return self.cloudflare().cloudflareDnsRecordRows(gpa, limit);
    }
    pub fn hostingerVpsRows(self: *Db, gpa: Allocator, limit: i64) !HostingerVpsRows {
        return self.hostinger().hostingerVpsRows(gpa, limit);
    }
};
