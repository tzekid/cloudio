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
    runner_observation_json: ?[]const u8,
    cloudio_observation_json: ?[]const u8,
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

pub const NewPlan = struct {
    id: []const u8,
    project_id: i64,
    action_id: []const u8,
    resource_id: ?[]const u8,
    input_json: []const u8,
    plan_json: []const u8,
    plan_sha256: []const u8,
    manifest_sha256: []const u8,
    source_fingerprint: []const u8,
    effect: []const u8,
    confirmation: []const u8,
    requested_by: []const u8,
    runner_sha256: []const u8,
    source_revision: ?[]const u8,
    source_dirty: bool,
    created_at: i64,
    expires_at: i64,
};

pub const BrokerAuthorization = struct {
    authorization_id: []const u8,
    capability: []const u8,
    resource_id: []const u8,
    operation: []const u8,
    metadata_json: ?[]const u8,
};

pub const NewRun = struct {
    id: []const u8,
    plan_id: []const u8,
    project_id: i64,
    action_id: []const u8,
    resource_id: ?[]const u8,
    effect: []const u8,
    requested_by: []const u8,
    idempotency_key: ?[]const u8,
    runner_path: []const u8,
    manifest_sha256: []const u8,
    source_fingerprint: []const u8,
    runner_sha256: []const u8,
    plan_sha256: []const u8,
    authorizations: []const BrokerAuthorization,
    queued_at: i64,
};

pub const RunFinish = struct {
    state: []const u8,
    outcome: []const u8,
    summary: []const u8,
    error_code: ?[]const u8,
    log_path: ?[]const u8,
    stderr_path: ?[]const u8,
    finished_at: i64,
};

pub const NewRunEvent = struct {
    operation_id: []const u8,
    seq: i64,
    event_type: []const u8,
    level: ?[]const u8,
    payload_json: []const u8,
    received_at: i64,
};

pub const NewArtifact = struct {
    operation_id: []const u8,
    resource_id: ?[]const u8,
    artifact_id: []const u8,
    role: []const u8,
    path: ?[]const u8,
    sha256: []const u8,
    size_bytes: ?i64,
    metadata_json: ?[]const u8,
    created_at: i64,
};

pub const ManagedUnit = struct {
    project_id: i64,
    resource_id: []u8,
    scope: []u8,
    unit: []u8,
    fragment_path: []u8,
    sha256: []u8,
    installed_operation_id: []u8,
    updated_at: i64,

    pub fn deinit(self: ManagedUnit, allocator: Allocator) void {
        allocator.free(self.resource_id);
        allocator.free(self.scope);
        allocator.free(self.unit);
        allocator.free(self.fragment_path);
        allocator.free(self.sha256);
        allocator.free(self.installed_operation_id);
    }
};

pub const ManagedUnitUpdate = struct {
    operation_id: []const u8,
    resource_id: []const u8,
    scope: []const u8,
    unit: []const u8,
    fragment_path: []const u8,
    sha256: []const u8,
    updated_at: i64,
};

pub const SecretBindingUpdate = struct {
    project_id: i64,
    secret_id: []const u8,
    source_kind: []const u8,
    source_ref: []const u8,
    present: bool,
    bound_by: []const u8,
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
        const invalidate = try self.prepare(
            "UPDATE project_plans SET state='invalidated' WHERE project_id=? AND state='ready' AND manifest_sha256 IS NOT ?",
        );
        defer _ = sqlite.sqlite3_finalize(invalidate);
        try bindI64(invalidate, 1, project_id);
        try bindTextOpt(invalidate, 2, record.manifest_sha256);
        try stepDone(invalidate);
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
            \\  AND discovery_state NOT IN ('missing','ignored')
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
            \\SET discovery_state=CASE WHEN discovery_state='ignored' THEN 'valid' ELSE discovery_state END,
            \\    trust_state='trusted', trusted_manifest_sha256=?, trusted_by=?, trusted_at=?,
            \\    status='unknown',
            \\    status_summary=CASE WHEN discovery_state='ignored' THEN 'approval restored; runner preparation required' ELSE status_summary END,
            \\    updated_at=?
            \\WHERE id=?
            \\  AND (discovery_state='valid' OR (discovery_state='ignored' AND last_scan_state='valid'))
            \\  AND manifest_sha256=?
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

    /// Leave a persistent discovery tombstone while removing all credentials
    /// and executable state owned by Cloudio. Historical operations and host
    /// resources are deliberately retained.
    pub fn forget(self: Repository, project_id: i64, actor: []const u8, now: i64) !bool {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};

        const busy = try self.prepare(
            \\SELECT 1 FROM managed_projects p
            \\WHERE p.id=? AND (
            \\  p.runner_state='building' OR EXISTS(
            \\    SELECT 1 FROM project_operation_locks l WHERE l.project_id=p.id
            \\  )
            \\)
        );
        defer _ = sqlite.sqlite3_finalize(busy);
        try bindI64(busy, 1, project_id);
        if (sqlite.sqlite3_step(busy) == sqlite.SQLITE_ROW) return error.ProjectBusy;

        const update = try self.prepare(
            \\UPDATE managed_projects
            \\SET discovery_state='ignored', trust_state='revoked',
            \\    trusted_manifest_sha256=NULL, trusted_by=?, trusted_at=?,
            \\    status='unknown', status_summary='forgotten by operator; passive scans will ignore this project',
            \\    runner_state='not-built', runner_path=NULL, runner_sha256=NULL,
            \\    runner_detail='project forgotten', updated_at=?
            \\WHERE id=?
        );
        defer _ = sqlite.sqlite3_finalize(update);
        try bindText(update, 1, actor);
        try bindI64(update, 2, now);
        try bindI64(update, 3, now);
        try bindI64(update, 4, project_id);
        try stepDone(update);
        if (sqlite.sqlite3_changes(self.handle) != 1) return false;

        const invalidate = try self.prepare("UPDATE project_plans SET state='invalidated' WHERE project_id=? AND state='ready'");
        defer _ = sqlite.sqlite3_finalize(invalidate);
        try bindI64(invalidate, 1, project_id);
        try stepDone(invalidate);
        const unavailable = try self.prepare(
            "UPDATE project_actions SET available=0, unavailable_reason='project forgotten' WHERE project_id=?",
        );
        defer _ = sqlite.sqlite3_finalize(unavailable);
        try bindI64(unavailable, 1, project_id);
        try stepDone(unavailable);
        const secrets = try self.prepare("DELETE FROM project_secret_bindings WHERE project_id=?");
        defer _ = sqlite.sqlite3_finalize(secrets);
        try bindI64(secrets, 1, project_id);
        try stepDone(secrets);

        try self.exec("COMMIT");
        committed = true;
        return true;
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
            \\SET runner_observation_json=NULL, cloudio_observation_json=NULL,
            \\    effective_status='unknown', status_summary='observation omitted this resource', observed_at=?
            \\WHERE project_id=?
        );
        defer _ = sqlite.sqlite3_finalize(reset);
        try bindI64(reset, 1, accepted.now);
        try bindI64(reset, 2, accepted.project_id);
        try stepDone(reset);

        const resource_stmt = try self.prepare(
            \\UPDATE project_resources
            \\SET runner_observation_json=?, cloudio_observation_json=?, effective_status=?, status_summary=?, observed_at=?
            \\WHERE project_id=? AND resource_id=?
        );
        defer _ = sqlite.sqlite3_finalize(resource_stmt);
        for (accepted.resources) |resource| {
            _ = sqlite.sqlite3_reset(resource_stmt);
            _ = sqlite.sqlite3_clear_bindings(resource_stmt);
            try bindTextOpt(resource_stmt, 1, resource.runner_observation_json);
            try bindTextOpt(resource_stmt, 2, resource.cloudio_observation_json);
            try bindText(resource_stmt, 3, resource.status);
            try bindText(resource_stmt, 4, resource.summary);
            try bindI64(resource_stmt, 5, accepted.now);
            try bindI64(resource_stmt, 6, accepted.project_id);
            try bindText(resource_stmt, 7, resource.resource_id);
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

    pub fn insertPlan(self: Repository, value: NewPlan) !void {
        const stmt = try self.prepare(
            \\INSERT INTO project_plans(
            \\  id, project_id, action_id, resource_id, input_json, plan_json, plan_sha256,
            \\  manifest_sha256, source_fingerprint, effect, confirmation, state, requested_by,
            \\  created_at, expires_at, runner_sha256, source_revision, source_dirty
            \\) VALUES(?,?,?,?,?,?,?,?,?,?,?,'ready',?,?,?,?,?,?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, value.id);
        try bindI64(stmt, 2, value.project_id);
        try bindText(stmt, 3, value.action_id);
        try bindTextOpt(stmt, 4, value.resource_id);
        try bindText(stmt, 5, value.input_json);
        try bindText(stmt, 6, value.plan_json);
        try bindText(stmt, 7, value.plan_sha256);
        try bindText(stmt, 8, value.manifest_sha256);
        try bindText(stmt, 9, value.source_fingerprint);
        try bindText(stmt, 10, value.effect);
        try bindText(stmt, 11, value.confirmation);
        try bindText(stmt, 12, value.requested_by);
        try bindI64(stmt, 13, value.created_at);
        try bindI64(stmt, 14, value.expires_at);
        try bindText(stmt, 15, value.runner_sha256);
        try bindTextOpt(stmt, 16, value.source_revision);
        try bindI64(stmt, 17, @intFromBool(value.source_dirty));
        try stepDone(stmt);
    }

    pub fn getPlan(self: Repository, allocator: Allocator, id: []const u8) !?model.Plan {
        const stmt = try self.prepare(plan_select ++ " WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try planFromStmt(allocator, stmt);
    }

    pub fn expirePlans(self: Repository, now: i64) !usize {
        const stmt = try self.prepare("UPDATE project_plans SET state='expired' WHERE state='ready' AND expires_at<=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try stepDone(stmt);
        return @intCast(sqlite.sqlite3_changes(self.handle));
    }

    pub fn invalidatePlan(self: Repository, id: []const u8) !void {
        const stmt = try self.prepare("UPDATE project_plans SET state='invalidated' WHERE id=? AND state='ready'");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try stepDone(stmt);
    }

    pub fn queueRun(self: Repository, value: NewRun) !void {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};

        const busy = try self.prepare("SELECT 1 FROM project_operation_locks WHERE project_id=?");
        defer _ = sqlite.sqlite3_finalize(busy);
        try bindI64(busy, 1, value.project_id);
        if (sqlite.sqlite3_step(busy) == sqlite.SQLITE_ROW) return error.ProjectBusy;

        if (value.idempotency_key) |key| {
            const existing = try self.prepare("SELECT 1 FROM project_operations WHERE project_id=? AND idempotency_key=?");
            defer _ = sqlite.sqlite3_finalize(existing);
            try bindI64(existing, 1, value.project_id);
            try bindText(existing, 2, key);
            if (sqlite.sqlite3_step(existing) == sqlite.SQLITE_ROW) return error.DuplicateRunRequest;
        }

        const consume = try self.prepare(
            \\UPDATE project_plans SET state='consumed', consumed_at=?
            \\WHERE id=? AND project_id=? AND state='ready' AND expires_at>?
            \\  AND manifest_sha256=? AND source_fingerprint=? AND runner_sha256=? AND plan_sha256=?
        );
        defer _ = sqlite.sqlite3_finalize(consume);
        try bindI64(consume, 1, value.queued_at);
        try bindText(consume, 2, value.plan_id);
        try bindI64(consume, 3, value.project_id);
        try bindI64(consume, 4, value.queued_at);
        try bindText(consume, 5, value.manifest_sha256);
        try bindText(consume, 6, value.source_fingerprint);
        try bindText(consume, 7, value.runner_sha256);
        try bindText(consume, 8, value.plan_sha256);
        try stepDone(consume);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.PlanUnavailable;

        const insert = try self.prepare(
            \\INSERT INTO project_operations(
            \\  id, project_id, plan_id, action_id, resource_id, state, effect, requested_by,
            \\  idempotency_key, runner_path, queued_at, manifest_sha256, source_fingerprint,
            \\  runner_sha256, plan_sha256
            \\) VALUES(?,?,?,?,?,'queued',?,?,?,?,?,?,?,?,?)
        );
        defer _ = sqlite.sqlite3_finalize(insert);
        try bindText(insert, 1, value.id);
        try bindI64(insert, 2, value.project_id);
        try bindText(insert, 3, value.plan_id);
        try bindText(insert, 4, value.action_id);
        try bindTextOpt(insert, 5, value.resource_id);
        try bindText(insert, 6, value.effect);
        try bindText(insert, 7, value.requested_by);
        try bindTextOpt(insert, 8, value.idempotency_key);
        try bindText(insert, 9, value.runner_path);
        try bindI64(insert, 10, value.queued_at);
        try bindText(insert, 11, value.manifest_sha256);
        try bindText(insert, 12, value.source_fingerprint);
        try bindText(insert, 13, value.runner_sha256);
        try bindText(insert, 14, value.plan_sha256);
        try stepDone(insert);

        const authorization = try self.prepare(
            \\INSERT INTO project_broker_authorizations(
            \\  operation_id, authorization_id, capability, resource_id, operation, metadata_json
            \\) VALUES(?,?,?,?,?,?)
        );
        defer _ = sqlite.sqlite3_finalize(authorization);
        for (value.authorizations) |item| {
            _ = sqlite.sqlite3_reset(authorization);
            _ = sqlite.sqlite3_clear_bindings(authorization);
            try bindText(authorization, 1, value.id);
            try bindText(authorization, 2, item.authorization_id);
            try bindText(authorization, 3, item.capability);
            try bindText(authorization, 4, item.resource_id);
            try bindText(authorization, 5, item.operation);
            try bindTextOpt(authorization, 6, item.metadata_json);
            try stepDone(authorization);
        }

        const lock = try self.prepare("INSERT INTO project_operation_locks(project_id, operation_id, acquired_at) VALUES(?,?,?)");
        defer _ = sqlite.sqlite3_finalize(lock);
        try bindI64(lock, 1, value.project_id);
        try bindText(lock, 2, value.id);
        try bindI64(lock, 3, value.queued_at);
        try stepDone(lock);

        try self.exec("COMMIT");
        committed = true;
    }

    pub fn claimNextRun(self: Repository, allocator: Allocator, now: i64) !?model.Run {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};
        const select = try self.prepare(run_select ++
            \\ WHERE state='queued'
            \\   AND EXISTS(
            \\     SELECT 1 FROM project_operation_locks l
            \\     WHERE l.project_id=project_operations.project_id AND l.operation_id=project_operations.id
            \\   )
            \\ ORDER BY queued_at, id LIMIT 1
        );
        defer _ = sqlite.sqlite3_finalize(select);
        if (sqlite.sqlite3_step(select) != sqlite.SQLITE_ROW) {
            try self.exec("COMMIT");
            committed = true;
            return null;
        }
        var run = try runFromStmt(allocator, select);
        errdefer run.deinit(allocator);
        const update = try self.prepare("UPDATE project_operations SET state='running', started_at=?, heartbeat_at=? WHERE id=? AND state='queued'");
        defer _ = sqlite.sqlite3_finalize(update);
        try bindI64(update, 1, now);
        try bindI64(update, 2, now);
        try bindText(update, 3, run.id);
        try stepDone(update);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.RunStateChanged;
        allocator.free(run.state);
        run.state = try allocator.dupe(u8, "running");
        run.started_at = now;
        run.heartbeat_at = now;
        try self.exec("COMMIT");
        committed = true;
        return run;
    }

    pub fn heartbeatRun(self: Repository, id: []const u8, now: i64) !void {
        const stmt = try self.prepare("UPDATE project_operations SET heartbeat_at=? WHERE id=? AND state='running'");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindText(stmt, 2, id);
        try stepDone(stmt);
    }

    pub fn finishRun(self: Repository, id: []const u8, finish: RunFinish) !void {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};
        const stmt = try self.prepare(
            \\UPDATE project_operations
            \\SET state=?, outcome=?, summary=?, error_code=?, log_path=?, stderr_path=?,
            \\    finished_at=?, heartbeat_at=?
            \\WHERE id=? AND state='running'
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, finish.state);
        try bindText(stmt, 2, finish.outcome);
        try bindText(stmt, 3, finish.summary);
        try bindTextOpt(stmt, 4, finish.error_code);
        try bindTextOpt(stmt, 5, finish.log_path);
        try bindTextOpt(stmt, 6, finish.stderr_path);
        try bindI64(stmt, 7, finish.finished_at);
        try bindI64(stmt, 8, finish.finished_at);
        try bindText(stmt, 9, id);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.RunStateChanged;
        const unlock = try self.prepare("DELETE FROM project_operation_locks WHERE operation_id=?");
        defer _ = sqlite.sqlite3_finalize(unlock);
        try bindText(unlock, 1, id);
        try stepDone(unlock);
        const invalidate = try self.prepare(
            \\UPDATE project_plans SET state='invalidated'
            \\WHERE state='ready' AND project_id=(SELECT project_id FROM project_operations WHERE id=?)
        );
        defer _ = sqlite.sqlite3_finalize(invalidate);
        try bindText(invalidate, 1, id);
        try stepDone(invalidate);
        try self.exec("COMMIT");
        committed = true;
    }

    pub fn requestRunCancellation(self: Repository, id: []const u8, now: i64) !bool {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};
        const stmt = try self.prepare(
            \\UPDATE project_operations
            \\SET cancel_requested_at=?,
            \\    state=CASE WHEN state='queued' THEN 'canceled' ELSE state END,
            \\    outcome=CASE WHEN state='queued' THEN 'canceled' ELSE outcome END,
            \\    summary=CASE WHEN state='queued' THEN 'run canceled before it started' ELSE summary END,
            \\    finished_at=CASE WHEN state='queued' THEN ? ELSE finished_at END
            \\WHERE id=? AND state IN ('queued','running')
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindI64(stmt, 2, now);
        try bindText(stmt, 3, id);
        try stepDone(stmt);
        const changed = sqlite.sqlite3_changes(self.handle) == 1;
        if (changed) {
            const unlock = try self.prepare(
                \\DELETE FROM project_operation_locks
                \\WHERE operation_id=? AND EXISTS(
                \\  SELECT 1 FROM project_operations WHERE id=? AND state='canceled'
                \\)
            );
            defer _ = sqlite.sqlite3_finalize(unlock);
            try bindText(unlock, 1, id);
            try bindText(unlock, 2, id);
            try stepDone(unlock);
        }
        try self.exec("COMMIT");
        committed = true;
        return changed;
    }

    pub fn runCancellationRequested(self: Repository, id: []const u8) !bool {
        const stmt = try self.prepare("SELECT cancel_requested_at IS NOT NULL FROM project_operations WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return false;
        return sqlite.sqlite3_column_int64(stmt, 0) != 0;
    }

    pub fn recoverStaleRuns(self: Repository, stale_before: i64, now: i64) !usize {
        try self.exec("BEGIN IMMEDIATE");
        var committed = false;
        defer if (!committed) self.exec("ROLLBACK") catch {};
        const update = try self.prepare(
            \\UPDATE project_operations
            \\SET state='interrupted', outcome='interrupted', summary='worker heartbeat expired',
            \\    error_code='stale_worker', finished_at=?
            \\WHERE state='running' AND (heartbeat_at IS NULL OR heartbeat_at<?)
        );
        defer _ = sqlite.sqlite3_finalize(update);
        try bindI64(update, 1, now);
        try bindI64(update, 2, stale_before);
        try stepDone(update);
        const count: usize = @intCast(sqlite.sqlite3_changes(self.handle));
        const unlock = try self.prepare(
            \\DELETE FROM project_operation_locks
            \\WHERE operation_id IN (SELECT id FROM project_operations WHERE state='interrupted' AND error_code='stale_worker')
        );
        defer _ = sqlite.sqlite3_finalize(unlock);
        try stepDone(unlock);
        try self.exec("COMMIT");
        committed = true;
        return count;
    }

    pub fn appendRunEvent(self: Repository, value: NewRunEvent) !void {
        const stmt = try self.prepare(
            \\INSERT INTO project_operation_events(operation_id, seq, event_type, level, payload_json, received_at)
            \\VALUES(?,?,?,?,?,?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, value.operation_id);
        try bindI64(stmt, 2, value.seq);
        try bindText(stmt, 3, value.event_type);
        try bindTextOpt(stmt, 4, value.level);
        try bindText(stmt, 5, value.payload_json);
        try bindI64(stmt, 6, value.received_at);
        try stepDone(stmt);
    }

    pub fn getRun(self: Repository, allocator: Allocator, id: []const u8) !?model.Run {
        const stmt = try self.prepare(run_select ++ " WHERE id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try runFromStmt(allocator, stmt);
    }

    pub fn listRuns(self: Repository, allocator: Allocator, project_id: ?i64, limit: i64) !model.Runs {
        const sql = if (project_id == null)
            run_select ++ " ORDER BY queued_at DESC LIMIT ?"
        else
            run_select ++ " WHERE project_id=? ORDER BY queued_at DESC LIMIT ?";
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (project_id) |id| {
            try bindI64(stmt, 1, id);
            try bindI64(stmt, 2, limit);
        } else try bindI64(stmt, 1, limit);
        var rows = std.ArrayList(model.Run).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) switch (sqlite.sqlite3_step(stmt)) {
            sqlite.SQLITE_ROW => try rows.append(allocator, try runFromStmt(allocator, stmt)),
            sqlite.SQLITE_DONE => break,
            else => return error.SqliteStep,
        };
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    pub fn listRunEvents(self: Repository, allocator: Allocator, operation_id: []const u8) !model.RunEvents {
        return self.listRunEventsQuery(allocator,
            \\SELECT operation_id, seq, event_type, level, payload_json, received_at
            \\FROM project_operation_events WHERE operation_id=? ORDER BY seq
        , operation_id, null, null);
    }

    pub fn listRunEventsAfter(self: Repository, allocator: Allocator, operation_id: []const u8, after_seq: i64, limit: i64) !model.RunEvents {
        return self.listRunEventsQuery(allocator,
            \\SELECT operation_id, seq, event_type, level, payload_json, received_at
            \\FROM project_operation_events
            \\WHERE operation_id=? AND seq>? ORDER BY seq LIMIT ?
        , operation_id, after_seq, limit);
    }

    pub fn listRecentRunEvents(self: Repository, allocator: Allocator, operation_id: []const u8, limit: i64) !model.RunEvents {
        const rows = try self.listRunEventsQuery(allocator,
            \\SELECT operation_id, seq, event_type, level, payload_json, received_at
            \\FROM project_operation_events
            \\WHERE operation_id=? ORDER BY seq DESC LIMIT ?
        , operation_id, null, limit);
        std.mem.reverse(model.RunEvent, rows.items);
        return rows;
    }

    fn listRunEventsQuery(
        self: Repository,
        allocator: Allocator,
        sql: []const u8,
        operation_id: []const u8,
        after_seq: ?i64,
        limit: ?i64,
    ) !model.RunEvents {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, operation_id);
        var parameter: c_int = 2;
        if (after_seq) |value| {
            try bindI64(stmt, parameter, value);
            parameter += 1;
        }
        if (limit) |value| try bindI64(stmt, parameter, value);
        var rows = std.ArrayList(model.RunEvent).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) switch (sqlite.sqlite3_step(stmt)) {
            sqlite.SQLITE_ROW => try rows.append(allocator, .{
                .operation_id = try dupeRequired(allocator, stmt, 0),
                .seq = sqlite.sqlite3_column_int64(stmt, 1),
                .event_type = try dupeRequired(allocator, stmt, 2),
                .level = try dupeOptional(allocator, stmt, 3),
                .payload_json = try dupeRequired(allocator, stmt, 4),
                .received_at = sqlite.sqlite3_column_int64(stmt, 5),
            }),
            sqlite.SQLITE_DONE => break,
            else => return error.SqliteStep,
        };
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    pub fn appendArtifact(self: Repository, value: NewArtifact) !void {
        const stmt = try self.prepare(
            \\INSERT INTO project_artifacts(
            \\  operation_id, project_id, resource_id, artifact_id, role, path,
            \\  sha256, size_bytes, metadata_json, created_at
            \\)
            \\SELECT ?, project_id, ?, ?, ?, ?, ?, ?, ?, ?
            \\FROM project_operations WHERE id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, value.operation_id);
        try bindTextOpt(stmt, 2, value.resource_id);
        try bindText(stmt, 3, value.artifact_id);
        try bindText(stmt, 4, value.role);
        try bindTextOpt(stmt, 5, value.path);
        try bindText(stmt, 6, value.sha256);
        try bindI64Opt(stmt, 7, value.size_bytes);
        try bindTextOpt(stmt, 8, value.metadata_json);
        try bindI64(stmt, 9, value.created_at);
        try bindText(stmt, 10, value.operation_id);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.RunNotFound;
    }

    pub fn listArtifacts(self: Repository, allocator: Allocator, operation_id: []const u8) !model.Artifacts {
        const stmt = try self.prepare(
            \\SELECT id, operation_id, project_id, resource_id, artifact_id, role,
            \\       path, sha256, size_bytes, metadata_json, created_at
            \\FROM project_artifacts WHERE operation_id=? ORDER BY id
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, operation_id);
        var rows = std.ArrayList(model.Artifact).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) switch (sqlite.sqlite3_step(stmt)) {
            sqlite.SQLITE_ROW => try rows.append(allocator, .{
                .id = sqlite.sqlite3_column_int64(stmt, 0),
                .operation_id = try dupeRequired(allocator, stmt, 1),
                .project_id = sqlite.sqlite3_column_int64(stmt, 2),
                .resource_id = try dupeOptional(allocator, stmt, 3),
                .artifact_id = try dupeRequired(allocator, stmt, 4),
                .role = try dupeRequired(allocator, stmt, 5),
                .path = try dupeOptional(allocator, stmt, 6),
                .sha256 = try dupeRequired(allocator, stmt, 7),
                .size_bytes = columnI64Optional(stmt, 8),
                .metadata_json = try dupeOptional(allocator, stmt, 9),
                .created_at = sqlite.sqlite3_column_int64(stmt, 10),
            }),
            sqlite.SQLITE_DONE => break,
            else => return error.SqliteStep,
        };
        return .{ .items = try rows.toOwnedSlice(allocator) };
    }

    pub fn getManagedUnitForOperation(
        self: Repository,
        allocator: Allocator,
        operation_id: []const u8,
        resource_id: []const u8,
    ) !?ManagedUnit {
        const stmt = try self.prepare(
            \\SELECT managed.project_id, managed.resource_id, managed.scope, managed.unit,
            \\       managed.fragment_path, managed.sha256, managed.installed_operation_id,
            \\       managed.updated_at
            \\FROM project_managed_units managed
            \\JOIN project_operations operation ON operation.project_id=managed.project_id
            \\WHERE operation.id=? AND managed.resource_id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, operation_id);
        try bindText(stmt, 2, resource_id);
        const result = sqlite.sqlite3_step(stmt);
        if (result == sqlite.SQLITE_DONE) return null;
        if (result != sqlite.SQLITE_ROW) return error.SqliteStep;
        return .{
            .project_id = sqlite.sqlite3_column_int64(stmt, 0),
            .resource_id = try dupeRequired(allocator, stmt, 1),
            .scope = try dupeRequired(allocator, stmt, 2),
            .unit = try dupeRequired(allocator, stmt, 3),
            .fragment_path = try dupeRequired(allocator, stmt, 4),
            .sha256 = try dupeRequired(allocator, stmt, 5),
            .installed_operation_id = try dupeRequired(allocator, stmt, 6),
            .updated_at = sqlite.sqlite3_column_int64(stmt, 7),
        };
    }

    pub fn upsertManagedUnit(self: Repository, value: ManagedUnitUpdate) !void {
        const stmt = try self.prepare(
            \\INSERT INTO project_managed_units(
            \\  project_id, resource_id, scope, unit, fragment_path, sha256,
            \\  installed_operation_id, updated_at
            \\) VALUES ((SELECT project_id FROM project_operations WHERE id=?), ?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(project_id, resource_id) DO UPDATE SET
            \\  scope=excluded.scope,
            \\  unit=excluded.unit,
            \\  fragment_path=excluded.fragment_path,
            \\  sha256=excluded.sha256,
            \\  installed_operation_id=excluded.installed_operation_id,
            \\  updated_at=excluded.updated_at
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, value.operation_id);
        try bindText(stmt, 2, value.resource_id);
        try bindText(stmt, 3, value.scope);
        try bindText(stmt, 4, value.unit);
        try bindText(stmt, 5, value.fragment_path);
        try bindText(stmt, 6, value.sha256);
        try bindText(stmt, 7, value.operation_id);
        try bindI64(stmt, 8, value.updated_at);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.RunNotFound;
    }

    pub fn deleteManagedUnitForOperation(self: Repository, operation_id: []const u8, resource_id: []const u8) !void {
        const stmt = try self.prepare(
            \\DELETE FROM project_managed_units
            \\WHERE project_id=(SELECT project_id FROM project_operations WHERE id=?)
            \\  AND resource_id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, operation_id);
        try bindText(stmt, 2, resource_id);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.ManagedUnitNotFound;
    }

    pub fn claimBrokerAuthorization(self: Repository, operation_id: []const u8, authorization_id: []const u8, used_at: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE project_broker_authorizations SET used_at=?
            \\WHERE operation_id=? AND authorization_id=? AND used_at IS NULL
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, used_at);
        try bindText(stmt, 2, operation_id);
        try bindText(stmt, 3, authorization_id);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn upsertSecretBinding(self: Repository, value: SecretBindingUpdate) !void {
        const stmt = try self.prepare(
            \\INSERT INTO project_secret_bindings(
            \\  project_id, secret_id, source_kind, source_ref, present,
            \\  bound_by, bound_at, checked_at
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(project_id, secret_id) DO UPDATE SET
            \\  source_kind=excluded.source_kind,
            \\  source_ref=excluded.source_ref,
            \\  present=excluded.present,
            \\  bound_by=excluded.bound_by,
            \\  bound_at=excluded.bound_at,
            \\  checked_at=excluded.checked_at
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, value.project_id);
        try bindText(stmt, 2, value.secret_id);
        try bindText(stmt, 3, value.source_kind);
        try bindText(stmt, 4, value.source_ref);
        try bindI64(stmt, 5, @intFromBool(value.present));
        try bindText(stmt, 6, value.bound_by);
        try bindI64(stmt, 7, value.now);
        try bindI64(stmt, 8, value.now);
        try stepDone(stmt);
    }

    pub fn deleteSecretBinding(self: Repository, project_id: i64, secret_id: []const u8) !bool {
        const stmt = try self.prepare("DELETE FROM project_secret_bindings WHERE project_id=? AND secret_id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);
        try bindText(stmt, 2, secret_id);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn updateSecretPresence(self: Repository, project_id: i64, secret_id: []const u8, present: bool, checked_at: i64) !void {
        const stmt = try self.prepare(
            \\UPDATE project_secret_bindings SET present=?, checked_at=?
            \\WHERE project_id=? AND secret_id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, @intFromBool(present));
        try bindI64(stmt, 2, checked_at);
        try bindI64(stmt, 3, project_id);
        try bindText(stmt, 4, secret_id);
        try stepDone(stmt);
        if (sqlite.sqlite3_changes(self.handle) != 1) return error.SecretBindingNotFound;
    }

    pub fn listSecretBindings(self: Repository, allocator: Allocator, project_id: i64) !model.SecretBindings {
        const stmt = try self.prepare(
            \\SELECT project_id, secret_id, source_kind, source_ref, present,
            \\       bound_by, bound_at, checked_at
            \\FROM project_secret_bindings WHERE project_id=? ORDER BY secret_id
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, project_id);
        var rows = std.ArrayList(model.SecretBinding).empty;
        errdefer {
            for (rows.items) |row| row.deinit(allocator);
            rows.deinit(allocator);
        }
        while (true) switch (sqlite.sqlite3_step(stmt)) {
            sqlite.SQLITE_ROW => try rows.append(allocator, .{
                .project_id = sqlite.sqlite3_column_int64(stmt, 0),
                .secret_id = try dupeRequired(allocator, stmt, 1),
                .source_kind = try dupeRequired(allocator, stmt, 2),
                .source_ref = try dupeRequired(allocator, stmt, 3),
                .present = sqlite.sqlite3_column_int64(stmt, 4) != 0,
                .bound_by = try dupeRequired(allocator, stmt, 5),
                .bound_at = sqlite.sqlite3_column_int64(stmt, 6),
                .checked_at = columnI64Optional(stmt, 7),
            }),
            sqlite.SQLITE_DONE => break,
            else => return error.SqliteStep,
        };
        return .{ .items = try rows.toOwnedSlice(allocator) };
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
        const stmt = try self.prepare(project_select ++ " WHERE declared_id=? AND discovery_state!='ignored' ORDER BY id");
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
            \\       runner_observation_json, cloudio_observation_json,
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
                    .runner_observation_json = try dupeOptional(allocator, stmt, 6),
                    .cloudio_observation_json = try dupeOptional(allocator, stmt, 7),
                    .effective_status = try model.parseProjectStatus(columnText(stmt, 8) orelse return error.InvalidDatabaseValue),
                    .status_summary = try dupeOptional(allocator, stmt, 9),
                    .observed_at = columnI64Optional(stmt, 10),
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
            \\  last_seen_scan_id, last_seen_at, created_at, updated_at, last_scan_state
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(root_path) DO UPDATE SET
            \\  declared_id=excluded.declared_id,
            \\  display_name=excluded.display_name,
            \\  kind=excluded.kind,
            \\  manifest_path=excluded.manifest_path,
            \\  manifest_sha256=excluded.manifest_sha256,
            \\  manifest_json=excluded.manifest_json,
            \\  discovery_state=CASE
            \\    WHEN managed_projects.discovery_state='ignored' THEN 'ignored'
            \\    ELSE excluded.discovery_state
            \\  END,
            \\  last_scan_state=excluded.last_scan_state,
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
            \\  status_summary=CASE
            \\    WHEN managed_projects.discovery_state='ignored' THEN managed_projects.status_summary
            \\    ELSE excluded.status_summary
            \\  END,
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
        try bindText(stmt, 16, record.discovery_state.text());
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
    \\       last_seen_at, last_observed_at, updated_at,
    \\       COALESCE(last_scan_state, discovery_state)
    \\FROM managed_projects
;

const plan_select =
    \\SELECT id, project_id, action_id, resource_id, input_json, plan_json, plan_sha256,
    \\       manifest_sha256, source_fingerprint, effect, confirmation, state, requested_by,
    \\       runner_sha256, source_revision, source_dirty, created_at, expires_at, consumed_at
    \\FROM project_plans
;

const run_select =
    \\SELECT id, project_id, plan_id, action_id, resource_id, state, outcome, effect,
    \\       requested_by, idempotency_key, runner_path, log_path, stderr_path, summary,
    \\       error_code, manifest_sha256, source_fingerprint, runner_sha256, plan_sha256,
    \\       queued_at, started_at, finished_at, cancel_requested_at, heartbeat_at
    \\FROM project_operations
;

fn planFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !model.Plan {
    return .{
        .id = try dupeRequired(allocator, stmt, 0),
        .project_id = sqlite.sqlite3_column_int64(stmt, 1),
        .action_id = try dupeRequired(allocator, stmt, 2),
        .resource_id = try dupeOptional(allocator, stmt, 3),
        .input_json = try dupeRequired(allocator, stmt, 4),
        .plan_json = try dupeRequired(allocator, stmt, 5),
        .plan_sha256 = try dupeRequired(allocator, stmt, 6),
        .manifest_sha256 = try dupeRequired(allocator, stmt, 7),
        .source_fingerprint = try dupeOptional(allocator, stmt, 8),
        .effect = try dupeRequired(allocator, stmt, 9),
        .confirmation = try dupeRequired(allocator, stmt, 10),
        .state = try dupeRequired(allocator, stmt, 11),
        .requested_by = try dupeRequired(allocator, stmt, 12),
        .runner_sha256 = try dupeOptional(allocator, stmt, 13),
        .source_revision = try dupeOptional(allocator, stmt, 14),
        .source_dirty = columnBoolOptional(stmt, 15),
        .created_at = sqlite.sqlite3_column_int64(stmt, 16),
        .expires_at = sqlite.sqlite3_column_int64(stmt, 17),
        .consumed_at = columnI64Optional(stmt, 18),
    };
}

fn runFromStmt(allocator: Allocator, stmt: *sqlite.sqlite3_stmt) !model.Run {
    return .{
        .id = try dupeRequired(allocator, stmt, 0),
        .project_id = sqlite.sqlite3_column_int64(stmt, 1),
        .plan_id = try dupeOptional(allocator, stmt, 2),
        .action_id = try dupeRequired(allocator, stmt, 3),
        .resource_id = try dupeOptional(allocator, stmt, 4),
        .state = try dupeRequired(allocator, stmt, 5),
        .outcome = try dupeOptional(allocator, stmt, 6),
        .effect = try dupeRequired(allocator, stmt, 7),
        .requested_by = try dupeRequired(allocator, stmt, 8),
        .idempotency_key = try dupeOptional(allocator, stmt, 9),
        .runner_path = try dupeOptional(allocator, stmt, 10),
        .log_path = try dupeOptional(allocator, stmt, 11),
        .stderr_path = try dupeOptional(allocator, stmt, 12),
        .summary = try dupeOptional(allocator, stmt, 13),
        .error_code = try dupeOptional(allocator, stmt, 14),
        .manifest_sha256 = try dupeOptional(allocator, stmt, 15),
        .source_fingerprint = try dupeOptional(allocator, stmt, 16),
        .runner_sha256 = try dupeOptional(allocator, stmt, 17),
        .plan_sha256 = try dupeOptional(allocator, stmt, 18),
        .queued_at = sqlite.sqlite3_column_int64(stmt, 19),
        .started_at = columnI64Optional(stmt, 20),
        .finished_at = columnI64Optional(stmt, 21),
        .cancel_requested_at = columnI64Optional(stmt, 22),
        .heartbeat_at = columnI64Optional(stmt, 23),
    };
}

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
        .last_scan_state = try model.parseDiscoveryState(columnText(stmt, 26) orelse return error.InvalidDatabaseValue),
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
