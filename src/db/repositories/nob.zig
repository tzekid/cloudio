const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");
const model = @import("nob_model");

const Allocator = std.mem.Allocator;
const bindI64 = helpers.bindI64;
const bindI64Opt = helpers.bindI64Opt;
const bindText = helpers.bindText;
const bindTextOpt = helpers.bindTextOpt;
const columnText = helpers.columnText;
const stepDone = helpers.stepDone;

pub const ResourceDeclaration = struct {
    resource_id: []const u8,
    kind: []const u8,
    label: []const u8,
    ownership: []const u8,
    controls_json: []const u8,
    declaration_json: []const u8,
};

pub const ActionDeclaration = struct {
    action_id: []const u8,
    label: []const u8,
    effect: []const u8,
    confirmation: []const u8,
    declaration_json: []const u8,
};

pub const ActionAvailability = struct {
    action_id: []const u8,
    available: bool,
    reason: ?[]const u8,
};

pub const AcceptedRunner = struct {
    project_id: i64,
    manifest_sha256: []const u8,
    runner_path: []const u8,
    runner_sha256: []const u8,
    runner_detail: []const u8,
    repository_kind: []const u8,
    repository_identity: []const u8,
    head_revision: ?[]const u8,
    source_fingerprint: []const u8,
    source_dirty: bool,
    actions: []const ActionAvailability,
    now: i64,
};

pub const ResourceObservation = struct {
    resource_id: []const u8,
    status: []const u8,
    summary: []const u8,
    observation_json: []const u8,
};

pub const AcceptedObservation = struct {
    project_id: i64,
    manifest_sha256: []const u8,
    project_status: []const u8,
    project_summary: []const u8,
    repository_kind: []const u8,
    repository_identity: []const u8,
    head_revision: ?[]const u8,
    source_fingerprint: []const u8,
    source_dirty: bool,
    resources: []const ResourceObservation,
    now: i64,
};

pub const DiscoveryRecord = struct {
    declared_id: ?[]const u8,
    display_name: []const u8,
    kind: []const u8,
    root_path: []const u8,
    manifest_path: ?[]const u8,
    manifest_sha256: ?[]const u8,
    manifest_json: ?[]const u8,
    discovery_state: model.DiscoveryState,
    diagnosis: ?[]const u8 = null,
    protocol_major: ?i64 = null,
    protocol_minor: ?i64 = null,
    scan_id: []const u8,
    seen_at: i64,
    replace_declarations: bool = false,
    resources: []const ResourceDeclaration = &.{},
    actions: []const ActionDeclaration = &.{},
};

pub const Repository = struct {
    handle: *sqlite.sqlite3,

    pub fn recordDiscovery(self: Repository, record: DiscoveryRecord) !i64 {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};

        const project_id = try self.upsertProject(record);
        if (record.replace_declarations) {
            try self.replaceDeclarations(project_id, record.resources, record.actions);
        }

        try self.exec("COMMIT");
        committed = true;
        return project_id;
    }

    pub fn markMissing(self: Repository, scan_root: []const u8, scan_id: []const u8, now: i64) !usize {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET discovery_state='missing', status='missing',
            \\    status_summary='not found during the latest passive scan',
            \\    updated_at=?
            \\WHERE (root_path=? OR substr(root_path, 1, length(?) + 1) = ? || '/')
            \\  AND (last_seen_scan_id IS NULL OR last_seen_scan_id != ?)
            \\  AND discovery_state != 'missing'
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindText(stmt, 2, scan_root);
        try bindText(stmt, 3, scan_root);
        try bindText(stmt, 4, scan_root);
        try bindText(stmt, 5, scan_id);
        try stepDone(stmt);
        return @intCast(sqlite.sqlite3_changes(self.handle));
    }

    pub fn markDeclaredIdConflicts(self: Repository, scan_id: []const u8, now: i64) !usize {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET discovery_state='conflict',
            \\    status_summary='duplicate project.id in the latest passive scan',
            \\    updated_at=?
            \\WHERE last_seen_scan_id=?
            \\  AND discovery_state='valid'
            \\  AND declared_id IN (
            \\    SELECT declared_id FROM managed_projects
            \\    WHERE last_seen_scan_id=? AND discovery_state='valid' AND declared_id IS NOT NULL
            \\    GROUP BY declared_id HAVING COUNT(*) > 1
            \\  )
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindText(stmt, 2, scan_id);
        try bindText(stmt, 3, scan_id);
        try stepDone(stmt);
        return @intCast(sqlite.sqlite3_changes(self.handle));
    }

    pub fn trust(self: Repository, project_id: i64, manifest_sha256: []const u8, actor: []const u8, now: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET trust_state='trusted', trusted_manifest_sha256=?, trusted_by=?, trusted_at=?,
            \\    updated_at=?
            \\WHERE id=? AND discovery_state='valid' AND manifest_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, manifest_sha256);
        try bindText(stmt, 2, actor);
        try bindI64(stmt, 3, now);
        try bindI64(stmt, 4, now);
        try bindI64(stmt, 5, project_id);
        try bindText(stmt, 6, manifest_sha256);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn revoke(self: Repository, project_id: i64, actor: []const u8, now: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET trust_state='revoked', trusted_by=?, trusted_at=?, runner_state='not-built',
            \\    runner_path=NULL, runner_sha256=NULL, runner_detail='trust revoked', updated_at=?
            \\WHERE id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, actor);
        try bindI64(stmt, 2, now);
        try bindI64(stmt, 3, now);
        try bindI64(stmt, 4, project_id);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn markRunnerBuilding(self: Repository, project_id: i64, manifest_sha256: []const u8, now: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET runner_state='building', runner_detail='building trusted runner', updated_at=?
            \\WHERE id=? AND discovery_state='valid' AND trust_state='trusted'
            \\  AND manifest_sha256=? AND trusted_manifest_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindI64(stmt, 2, project_id);
        try bindText(stmt, 3, manifest_sha256);
        try bindText(stmt, 4, manifest_sha256);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn markRunnerFailed(self: Repository, project_id: i64, manifest_sha256: []const u8, detail: []const u8, now: i64) !void {
        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET runner_state='failed', runner_path=NULL, runner_sha256=NULL,
            \\    runner_detail=?, status='degraded', status_summary='runner bootstrap failed', updated_at=?
            \\WHERE id=? AND manifest_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, detail);
        try bindI64(stmt, 2, now);
        try bindI64(stmt, 3, project_id);
        try bindText(stmt, 4, manifest_sha256);
        try stepDone(stmt);
    }

    pub fn acceptRunner(self: Repository, accepted: AcceptedRunner) !void {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};

        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET runner_state='ready', runner_path=?, runner_sha256=?, runner_detail=?,
            \\    repository_kind=?, repository_identity=?, head_revision=?, source_fingerprint=?, source_dirty=?, updated_at=?
            \\WHERE id=? AND discovery_state='valid' AND trust_state='trusted'
            \\  AND manifest_sha256=? AND trusted_manifest_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, accepted.runner_path);
        try bindText(stmt, 2, accepted.runner_sha256);
        try bindText(stmt, 3, accepted.runner_detail);
        try bindText(stmt, 4, accepted.repository_kind);
        try bindText(stmt, 5, accepted.repository_identity);
        try bindTextOpt(stmt, 6, accepted.head_revision);
        try bindText(stmt, 7, accepted.source_fingerprint);
        try bindI64(stmt, 8, @intFromBool(accepted.source_dirty));
        try bindI64(stmt, 9, accepted.now);
        try bindI64(stmt, 10, accepted.project_id);
        try bindText(stmt, 11, accepted.manifest_sha256);
        try bindText(stmt, 12, accepted.manifest_sha256);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.ProjectStateChanged;

        try self.setAllActionsUnavailable(accepted.project_id, "runner did not report this action", accepted.now);
        const action_stmt = try self.prepare(
            \\UPDATE project_actions SET available=?, unavailable_reason=?, described_at=?
            \\WHERE project_id=? AND action_id=?
        );
        defer _ = sqlite.sqlite3_finalize(action_stmt);
        for (accepted.actions) |action| {
            _ = sqlite.sqlite3_reset(action_stmt);
            _ = sqlite.sqlite3_clear_bindings(action_stmt);
            try bindI64(action_stmt, 1, @intFromBool(action.available));
            try bindTextOpt(action_stmt, 2, action.reason);
            try bindI64(action_stmt, 3, accepted.now);
            try bindI64(action_stmt, 4, accepted.project_id);
            try bindText(action_stmt, 5, action.action_id);
            try stepDone(action_stmt);
            if (sqlite.sqlite3_changes(self.handle) != 1) return error.UnknownAction;
        }

        try self.exec("COMMIT");
        committed = true;
    }

    pub fn acceptObservation(self: Repository, accepted: AcceptedObservation) !void {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};

        const stmt = try self.prepare(
            \\UPDATE managed_projects
            \\SET status=?, status_summary=?, repository_kind=?, repository_identity=?, head_revision=?,
            \\    source_fingerprint=?, source_dirty=?, last_observed_at=?, updated_at=?
            \\WHERE id=? AND discovery_state='valid' AND trust_state='trusted'
            \\  AND runner_state='ready' AND manifest_sha256=? AND trusted_manifest_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, accepted.project_status);
        try bindText(stmt, 2, accepted.project_summary);
        try bindText(stmt, 3, accepted.repository_kind);
        try bindText(stmt, 4, accepted.repository_identity);
        try bindTextOpt(stmt, 5, accepted.head_revision);
        try bindText(stmt, 6, accepted.source_fingerprint);
        try bindI64(stmt, 7, @intFromBool(accepted.source_dirty));
        try bindI64(stmt, 8, accepted.now);
        try bindI64(stmt, 9, accepted.now);
        try bindI64(stmt, 10, accepted.project_id);
        try bindText(stmt, 11, accepted.manifest_sha256);
        try bindText(stmt, 12, accepted.manifest_sha256);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.ProjectStateChanged;

        const reset = try self.prepare(
            \\UPDATE project_resources
            \\SET runner_observation_json=NULL, effective_status='unknown',
            \\    status_summary='runner omitted this resource', observed_at=?
            \\WHERE project_id=?
        );
        defer _ = sqlite.sqlite3_finalize(reset);
        try bindI64(reset, 1, accepted.now);
        try bindI64(reset, 2, accepted.project_id);
        try stepDone(reset);

        const resource_stmt = try self.prepare(
            \\UPDATE project_resources
            \\SET runner_observation_json=?, effective_status=?, status_summary=?, observed_at=?
            \\WHERE project_id=? AND resource_id=?
        );
        defer _ = sqlite.sqlite3_finalize(resource_stmt);
        for (accepted.resources) |resource| {
            _ = sqlite.sqlite3_reset(resource_stmt);
            _ = sqlite.sqlite3_clear_bindings(resource_stmt);
            try bindText(resource_stmt, 1, resource.observation_json);
            try bindText(resource_stmt, 2, resource.status);
            try bindText(resource_stmt, 3, resource.summary);
            try bindI64(resource_stmt, 4, accepted.now);
            try bindI64(resource_stmt, 5, accepted.project_id);
            try bindText(resource_stmt, 6, resource.resource_id);
            try stepDone(resource_stmt);
            if (sqlite.sqlite3_changes(self.handle) != 1) return error.UnknownResource;
        }

        try self.exec("COMMIT");
        committed = true;
    }

    pub fn markObservationFailed(self: Repository, project_id: i64, detail: []const u8, now: i64) !void {
        const stmt = try self.prepare(
            \\UPDATE managed_projects SET status='degraded', status_summary=?, last_observed_at=?, updated_at=?
            \\WHERE id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, detail);
        try bindI64(stmt, 2, now);
        try bindI64(stmt, 3, now);
        try bindI64(stmt, 4, project_id);
        try stepDone(stmt);
    }

    pub fn getProject(self: Repository, allocator: Allocator, project_id: i64) !?model.Project {
        const stmt = try self.prepare(project_select ++ " WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try projectFromStmt(allocator, stmt);
    }

    pub fn getProjectByRoot(self: Repository, allocator: Allocator, root_path: []const u8) !?model.Project {
        const stmt = try self.prepare(project_select ++ " WHERE root_path=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, root_path);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try projectFromStmt(allocator, stmt);
    }

    pub fn getProjectByDeclaredId(self: Repository, allocator: Allocator, declared_id: []const u8) !?model.Project {
        const stmt = try self.prepare(project_select ++ " WHERE declared_id=? ORDER BY id");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, declared_id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        const project = try projectFromStmt(allocator, stmt);
        errdefer project.deinit(allocator);
        if (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            return error.ProjectIdConflict;
        }
        return project;
    }

    pub fn listProjects(self: Repository, allocator: Allocator) !model.Projects {
        const stmt = try self.prepare(project_select ++ " ORDER BY display_name, root_path");
        defer _ = sqlite.sqlite3_finalize(stmt);

        var rows = std.ArrayList(model.Project).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) {
            switch (sqlite.sqlite3_step(stmt)) {
                sqlite.SQLITE_ROW => try rows.append(allocator, try projectFromStmt(allocator, stmt)),
                sqlite.SQLITE_DONE => break,
                else => return error.SqliteStep,
            }
        }
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    pub fn listResources(self: Repository, allocator: Allocator, project_id: i64) !model.Resources {
        const stmt = try self.prepare(
            \\SELECT resource_id, kind, label, ownership, controls_json, declaration_json,
            \\       effective_status, status_summary, observed_at
            \\FROM project_resources WHERE project_id=? ORDER BY resource_id
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);

        var rows = std.ArrayList(model.Resource).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) {
            switch (sqlite.sqlite3_step(stmt)) {
                sqlite.SQLITE_ROW => try rows.append(allocator, .{
                    .resource_id = try dupeRequired(allocator, stmt, 0),
                    .kind = try dupeRequired(allocator, stmt, 1),
                    .label = try dupeRequired(allocator, stmt, 2),
                    .ownership = try dupeRequired(allocator, stmt, 3),
                    .controls_json = try dupeRequired(allocator, stmt, 4),
                    .declaration_json = try dupeRequired(allocator, stmt, 5),
                    .effective_status = try model.parseProjectStatus(columnText(stmt, 6) orelse return error.InvalidDatabaseValue),
                    .status_summary = try dupeOptional(allocator, stmt, 7),
                    .observed_at = columnI64Optional(stmt, 8),
                }),
                sqlite.SQLITE_DONE => break,
                else => return error.SqliteStep,
            }
        }
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    pub fn listActions(self: Repository, allocator: Allocator, project_id: i64) !model.Actions {
        const stmt = try self.prepare(
            \\SELECT action_id, label, effect, confirmation, declaration_json,
            \\       available, unavailable_reason
            \\FROM project_actions WHERE project_id=? ORDER BY action_id
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);

        var rows = std.ArrayList(model.Action).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) {
            switch (sqlite.sqlite3_step(stmt)) {
                sqlite.SQLITE_ROW => try rows.append(allocator, .{
                    .action_id = try dupeRequired(allocator, stmt, 0),
                    .label = try dupeRequired(allocator, stmt, 1),
                    .effect = try dupeRequired(allocator, stmt, 2),
                    .confirmation = try dupeRequired(allocator, stmt, 3),
                    .declaration_json = try dupeRequired(allocator, stmt, 4),
                    .available = sqlite.sqlite3_column_int64(stmt, 5) != 0,
                    .unavailable_reason = try dupeOptional(allocator, stmt, 6),
                }),
                sqlite.SQLITE_DONE => break,
                else => return error.SqliteStep,
            }
        }
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    fn upsertProject(self: Repository, record: DiscoveryRecord) !i64 {
        const stmt = try self.prepare(
            \\INSERT INTO managed_projects(
            \\  declared_id, display_name, kind, root_path, manifest_path, manifest_sha256,
            \\  manifest_json, discovery_state, status_summary, protocol_major, protocol_minor,
            \\  last_seen_scan_id, last_seen_at, created_at, updated_at
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(root_path) DO UPDATE SET
            \\  declared_id=excluded.declared_id,
            \\  display_name=excluded.display_name,
            \\  kind=excluded.kind,
            \\  manifest_path=excluded.manifest_path,
            \\  manifest_sha256=excluded.manifest_sha256,
            \\  manifest_json=excluded.manifest_json,
            \\  discovery_state=excluded.discovery_state,
            \\  trust_state=CASE
            \\    WHEN managed_projects.trust_state='trusted' AND (
            \\      managed_projects.trusted_manifest_sha256 IS NOT excluded.manifest_sha256
            \\      OR excluded.discovery_state != 'valid'
            \\    ) THEN 'review-required'
            \\    ELSE managed_projects.trust_state
            \\  END,
            \\  status=CASE
            \\    WHEN managed_projects.manifest_sha256 IS NOT excluded.manifest_sha256
            \\      OR managed_projects.discovery_state='missing' THEN 'unknown'
            \\    ELSE managed_projects.status
            \\  END,
            \\  status_summary=excluded.status_summary,
            \\  protocol_major=excluded.protocol_major,
            \\  protocol_minor=excluded.protocol_minor,
            \\  runner_state=CASE
            \\    WHEN managed_projects.manifest_sha256 IS NOT excluded.manifest_sha256 THEN 'not-built'
            \\    ELSE managed_projects.runner_state
            \\  END,
            \\  runner_path=CASE
            \\    WHEN managed_projects.manifest_sha256 IS NOT excluded.manifest_sha256 THEN NULL
            \\    ELSE managed_projects.runner_path
            \\  END,
            \\  runner_sha256=CASE
            \\    WHEN managed_projects.manifest_sha256 IS NOT excluded.manifest_sha256 THEN NULL
            \\    ELSE managed_projects.runner_sha256
            \\  END,
            \\  runner_detail=CASE
            \\    WHEN managed_projects.manifest_sha256 IS NOT excluded.manifest_sha256 THEN 'manifest changed'
            \\    ELSE managed_projects.runner_detail
            \\  END,
            \\  last_seen_scan_id=excluded.last_seen_scan_id,
            \\  last_seen_at=excluded.last_seen_at,
            \\  updated_at=excluded.updated_at
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindTextOpt(stmt, 1, record.declared_id);
        try bindText(stmt, 2, record.display_name);
        try bindText(stmt, 3, record.kind);
        try bindText(stmt, 4, record.root_path);
        try bindTextOpt(stmt, 5, record.manifest_path);
        try bindTextOpt(stmt, 6, record.manifest_sha256);
        try bindTextOpt(stmt, 7, record.manifest_json);
        try bindText(stmt, 8, record.discovery_state.text());
        try bindTextOpt(stmt, 9, record.diagnosis);
        try bindI64Opt(stmt, 10, record.protocol_major);
        try bindI64Opt(stmt, 11, record.protocol_minor);
        try bindText(stmt, 12, record.scan_id);
        try bindI64(stmt, 13, record.seen_at);
        try bindI64(stmt, 14, record.seen_at);
        try bindI64(stmt, 15, record.seen_at);
        try stepDone(stmt);

        const lookup = try self.prepare("SELECT id FROM managed_projects WHERE root_path=?");
        defer _ = sqlite.sqlite3_finalize(lookup);
        try bindText(lookup, 1, record.root_path);
        if (sqlite.sqlite3_step(lookup) != sqlite.SQLITE_ROW) return error.SqliteStep;
        return sqlite.sqlite3_column_int64(lookup, 0);
    }

    fn replaceDeclarations(
        self: Repository,
        project_id: i64,
        resources: []const ResourceDeclaration,
        actions: []const ActionDeclaration,
    ) !void {
        try self.deleteForProject("DELETE FROM project_resources WHERE project_id=?", project_id);
        try self.deleteForProject("DELETE FROM project_actions WHERE project_id=?", project_id);

        const resource_stmt = try self.prepare(
            \\INSERT INTO project_resources(
            \\  project_id, resource_id, kind, label, ownership, controls_json, declaration_json
            \\) VALUES (?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(resource_stmt);
        for (resources) |resource| {
            _ = sqlite.sqlite3_reset(resource_stmt);
            _ = sqlite.sqlite3_clear_bindings(resource_stmt);
            try bindI64(resource_stmt, 1, project_id);
            try bindText(resource_stmt, 2, resource.resource_id);
            try bindText(resource_stmt, 3, resource.kind);
            try bindText(resource_stmt, 4, resource.label);
            try bindText(resource_stmt, 5, resource.ownership);
            try bindText(resource_stmt, 6, resource.controls_json);
            try bindText(resource_stmt, 7, resource.declaration_json);
            try stepDone(resource_stmt);
        }

        const action_stmt = try self.prepare(
            \\INSERT INTO project_actions(
            \\  project_id, action_id, label, effect, confirmation, declaration_json
            \\) VALUES (?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(action_stmt);
        for (actions) |action| {
            _ = sqlite.sqlite3_reset(action_stmt);
            _ = sqlite.sqlite3_clear_bindings(action_stmt);
            try bindI64(action_stmt, 1, project_id);
            try bindText(action_stmt, 2, action.action_id);
            try bindText(action_stmt, 3, action.label);
            try bindText(action_stmt, 4, action.effect);
            try bindText(action_stmt, 5, action.confirmation);
            try bindText(action_stmt, 6, action.declaration_json);
            try stepDone(action_stmt);
        }
    }

    fn setAllActionsUnavailable(self: Repository, project_id: i64, reason: []const u8, now: i64) !void {
        const stmt = try self.prepare(
            \\UPDATE project_actions SET available=0, unavailable_reason=?, described_at=?
            \\WHERE project_id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, reason);
        try bindI64(stmt, 2, now);
        try bindI64(stmt, 3, project_id);
        try stepDone(stmt);
    }

    fn deleteForProject(self: Repository, sql: []const u8, project_id: i64) !void {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);
        try stepDone(stmt);
    }

    fn exec(self: Repository, sql: []const u8) !void {
        var err: [*c]u8 = null;
        if (sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err) != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return error.SqliteExec;
        }
    }

    fn prepare(self: Repository, sql: []const u8) !*sqlite.sqlite3_stmt {
        return helpers.prepare(self.handle, sql);
    }
};

const project_select =
    \\SELECT id, declared_id, display_name, kind, root_path, manifest_path,
    \\       manifest_sha256, trusted_manifest_sha256, discovery_state, trust_state,
    \\       status, status_summary, protocol_major, protocol_minor, runner_state,
    \\       runner_path, runner_sha256, runner_detail, repository_kind,
    \\       repository_identity, head_revision, source_fingerprint, source_dirty,
    \\       last_seen_at, last_observed_at, updated_at
    \\FROM managed_projects
;

fn projectFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !model.Project {
    return .{
        .id = sqlite.sqlite3_column_int64(stmt, 0),
        .declared_id = try dupeOptional(allocator, stmt, 1),
        .display_name = try dupeRequired(allocator, stmt, 2),
        .kind = try dupeRequired(allocator, stmt, 3),
        .root_path = try dupeRequired(allocator, stmt, 4),
        .manifest_path = try dupeOptional(allocator, stmt, 5),
        .manifest_sha256 = try dupeOptional(allocator, stmt, 6),
        .trusted_manifest_sha256 = try dupeOptional(allocator, stmt, 7),
        .discovery_state = try model.parseDiscoveryState(columnText(stmt, 8) orelse return error.InvalidDatabaseValue),
        .trust_state = try model.parseTrustState(columnText(stmt, 9) orelse return error.InvalidDatabaseValue),
        .status = try model.parseProjectStatus(columnText(stmt, 10) orelse return error.InvalidDatabaseValue),
        .status_summary = try dupeOptional(allocator, stmt, 11),
        .protocol_major = columnI64Optional(stmt, 12),
        .protocol_minor = columnI64Optional(stmt, 13),
        .runner_state = try model.parseRunnerState(columnText(stmt, 14) orelse return error.InvalidDatabaseValue),
        .runner_path = try dupeOptional(allocator, stmt, 15),
        .runner_sha256 = try dupeOptional(allocator, stmt, 16),
        .runner_detail = try dupeOptional(allocator, stmt, 17),
        .repository_kind = try dupeOptional(allocator, stmt, 18),
        .repository_identity = try dupeOptional(allocator, stmt, 19),
        .head_revision = try dupeOptional(allocator, stmt, 20),
        .source_fingerprint = try dupeOptional(allocator, stmt, 21),
        .source_dirty = columnBoolOptional(stmt, 22),
        .last_seen_at = sqlite.sqlite3_column_int64(stmt, 23),
        .last_observed_at = columnI64Optional(stmt, 24),
        .updated_at = sqlite.sqlite3_column_int64(stmt, 25),
    };
}

fn dupeRequired(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, index: c_int) ![]u8 {
    const value = columnText(stmt, index) orelse return error.InvalidDatabaseValue;
    return try allocator.dupe(u8, value);
}

fn dupeOptional(allocator: Allocator, stmt: *sqlite.sqlite3_stmt, index: c_int) !?[]u8 {
    const value = columnText(stmt, index) orelse return null;
    return try allocator.dupe(u8, value);
}

fn columnI64Optional(stmt: *sqlite.sqlite3_stmt, index: c_int) ?i64 {
    if (sqlite.sqlite3_column_type(stmt, index) == sqlite.SQLITE_NULL) return null;
    return sqlite.sqlite3_column_int64(stmt, index);
}

fn columnBoolOptional(stmt: *sqlite.sqlite3_stmt, index: c_int) ?bool {
    return if (columnI64Optional(stmt, index)) |value| value != 0 else null;
}
