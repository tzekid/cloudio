const std = @import("std");
const sqlite = @import("sqlite");
const helpers = @import("../helpers.zig");

const Allocator = std.mem.Allocator;
const bindI64 = helpers.bindI64;
const bindI64Opt = helpers.bindI64Opt;
const bindText = helpers.bindText;
const bindTextOpt = helpers.bindTextOpt;
const dupeColumn = helpers.dupeColumn;
const stepDone = helpers.stepDone;

pub const Challenge = struct {
    id: []u8,
    purpose: []u8,
    challenge: []u8,
    user_id: []u8,
    binding_hash: []u8,
    expires_at: i64,
    used_at: ?i64,

    pub fn deinit(self: Challenge, gpa: Allocator) void {
        gpa.free(self.id);
        gpa.free(self.purpose);
        gpa.free(self.challenge);
        gpa.free(self.user_id);
        gpa.free(self.binding_hash);
    }
};

pub const Credential = struct {
    credential_id: []u8,
    user_id: []u8,
    public_key: []u8,
    algorithm: i64,
    sign_count: u32,
    transports: []u8,
    aaguid: []u8,
    backup_eligible: bool,
    backup_state: bool,
    label: []u8,
    created_at: i64,
    last_used_at: ?i64,
    revoked_at: ?i64,

    pub fn deinit(self: Credential, gpa: Allocator) void {
        gpa.free(self.credential_id);
        gpa.free(self.user_id);
        gpa.free(self.public_key);
        gpa.free(self.transports);
        gpa.free(self.aaguid);
        gpa.free(self.label);
    }
};

pub const Credentials = struct {
    items: []Credential,

    pub fn deinit(self: *Credentials, gpa: Allocator) void {
        for (self.items) |item| item.deinit(gpa);
        gpa.free(self.items);
    }
};

pub const Session = struct {
    token_hash: []u8,
    user_id: []u8,
    csrf_token: []u8,
    expires_at: i64,
    revoked_at: ?i64,

    pub fn deinit(self: Session, gpa: Allocator) void {
        gpa.free(self.token_hash);
        gpa.free(self.user_id);
        gpa.free(self.csrf_token);
    }
};

pub const Repository = struct {
    handle: *sqlite.sqlite3,

    fn prepare(self: Repository, sql: []const u8) !*sqlite.sqlite3_stmt {
        return helpers.prepare(self.handle, sql);
    }

    pub fn activeCredentialCount(self: Repository) !i64 {
        return try self.scalar("SELECT COUNT(*) FROM auth_credentials WHERE revoked_at IS NULL");
    }

    pub fn activeSessionCount(self: Repository, now: i64) !i64 {
        const stmt = try self.prepare(
            "SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL AND expires_at > ?",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return error.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    pub fn bootstrapActive(self: Repository, now: i64) !bool {
        const stmt = try self.prepare(
            "SELECT 1 FROM auth_bootstrap WHERE id=1 AND consumed_at IS NULL AND expires_at > ?",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        return sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW;
    }

    pub fn bootstrapMatches(self: Repository, token_hash: []const u8, now: i64) !bool {
        const stmt = try self.prepare(
            "SELECT 1 FROM auth_bootstrap WHERE id=1 AND token_hash=? AND consumed_at IS NULL AND expires_at > ?",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, token_hash);
        try bindI64(stmt, 2, now);
        return sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW;
    }

    pub fn putBootstrap(self: Repository, token_hash: []const u8, created_at: i64, expires_at: i64) !void {
        const stmt = try self.prepare(
            \\INSERT INTO auth_bootstrap(id, token_hash, expires_at, created_at, consumed_at)
            \\VALUES (1, ?, ?, ?, NULL)
            \\ON CONFLICT(id) DO UPDATE SET
            \\ token_hash=excluded.token_hash,
            \\ expires_at=excluded.expires_at,
            \\ created_at=excluded.created_at,
            \\ consumed_at=NULL
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, token_hash);
        try bindI64(stmt, 2, expires_at);
        try bindI64(stmt, 3, created_at);
        try stepDone(stmt);
    }

    pub fn consumeBootstrap(self: Repository, token_hash: []const u8, used_at: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE auth_bootstrap SET consumed_at=?
            \\WHERE id=1 AND token_hash=? AND consumed_at IS NULL AND expires_at > ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, used_at);
        try bindText(stmt, 2, token_hash);
        try bindI64(stmt, 3, used_at);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn putChallenge(
        self: Repository,
        id: []const u8,
        purpose: []const u8,
        challenge: []const u8,
        user_id: ?[]const u8,
        binding_hash: ?[]const u8,
        created_at: i64,
        expires_at: i64,
    ) !void {
        const stmt = try self.prepare(
            \\INSERT INTO auth_challenges(
            \\ id, purpose, challenge, user_id, binding_hash, expires_at, created_at
            \\) VALUES (?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindText(stmt, 2, purpose);
        try bindText(stmt, 3, challenge);
        try bindTextOpt(stmt, 4, user_id);
        try bindTextOpt(stmt, 5, binding_hash);
        try bindI64(stmt, 6, expires_at);
        try bindI64(stmt, 7, created_at);
        try stepDone(stmt);
    }

    pub fn findChallenge(self: Repository, gpa: Allocator, id: []const u8) !?Challenge {
        const stmt = try self.prepare(
            \\SELECT id, purpose, challenge, COALESCE(user_id,''),
            \\ COALESCE(binding_hash,''), expires_at, used_at
            \\FROM auth_challenges WHERE id=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try challengeFromStmt(gpa, stmt);
    }

    pub fn consumeChallenge(self: Repository, id: []const u8, purpose: []const u8, used_at: i64) !bool {
        const stmt = try self.prepare(
            \\UPDATE auth_challenges SET used_at=?
            \\WHERE id=? AND purpose=? AND used_at IS NULL AND expires_at > ?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, used_at);
        try bindText(stmt, 2, id);
        try bindText(stmt, 3, purpose);
        try bindI64(stmt, 4, used_at);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn ensureUser(self: Repository, id: []const u8, display_name: []const u8, created_at: i64) !void {
        const stmt = try self.prepare(
            "INSERT OR IGNORE INTO auth_users(id, display_name, created_at) VALUES (?, ?, ?)",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, id);
        try bindText(stmt, 2, display_name);
        try bindI64(stmt, 3, created_at);
        try stepDone(stmt);
    }

    pub fn firstUserId(self: Repository, gpa: Allocator) !?[]u8 {
        const stmt = try self.prepare("SELECT id FROM auth_users ORDER BY created_at LIMIT 1");
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try dupeColumn(gpa, stmt, 0);
    }

    pub fn insertCredential(self: Repository, credential: Credential) !void {
        const stmt = try self.prepare(
            \\INSERT INTO auth_credentials(
            \\ credential_id, user_id, public_key, algorithm, sign_count,
            \\ transports, aaguid, backup_eligible, backup_state, label, created_at
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, credential.credential_id);
        try bindText(stmt, 2, credential.user_id);
        try bindText(stmt, 3, credential.public_key);
        try bindI64(stmt, 4, credential.algorithm);
        try bindI64(stmt, 5, credential.sign_count);
        try bindText(stmt, 6, credential.transports);
        try bindText(stmt, 7, credential.aaguid);
        try bindI64(stmt, 8, @intFromBool(credential.backup_eligible));
        try bindI64(stmt, 9, @intFromBool(credential.backup_state));
        try bindText(stmt, 10, credential.label);
        try bindI64(stmt, 11, credential.created_at);
        try stepDone(stmt);
    }

    pub fn findCredential(self: Repository, gpa: Allocator, credential_id: []const u8) !?Credential {
        const stmt = try self.prepare(credential_select ++ " WHERE credential_id=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, credential_id);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return try credentialFromStmt(gpa, stmt);
    }

    pub fn listCredentials(self: Repository, gpa: Allocator) !Credentials {
        const stmt = try self.prepare(credential_select ++ " ORDER BY created_at, credential_id");
        defer _ = sqlite.sqlite3_finalize(stmt);
        var items = std.ArrayList(Credential).empty;
        errdefer {
            for (items.items) |item| item.deinit(gpa);
            items.deinit(gpa);
        }
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            const item = try credentialFromStmt(gpa, stmt);
            items.append(gpa, item) catch |err| {
                item.deinit(gpa);
                return err;
            };
        }
        return .{ .items = try items.toOwnedSlice(gpa) };
    }

    pub fn updateCredentialUse(
        self: Repository,
        credential_id: []const u8,
        sign_count: u32,
        backup_state: bool,
        used_at: i64,
    ) !void {
        const stmt = try self.prepare(
            \\UPDATE auth_credentials SET sign_count=?, backup_state=?, last_used_at=?
            \\WHERE credential_id=? AND revoked_at IS NULL
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, sign_count);
        try bindI64(stmt, 2, @intFromBool(backup_state));
        try bindI64(stmt, 3, used_at);
        try bindText(stmt, 4, credential_id);
        try stepDone(stmt);
    }

    pub fn updateCredentialLabel(self: Repository, credential_id: []const u8, label: []const u8) !bool {
        const stmt = try self.prepare(
            "UPDATE auth_credentials SET label=? WHERE credential_id=? AND revoked_at IS NULL",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, label);
        try bindText(stmt, 2, credential_id);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn revokeCredential(self: Repository, credential_id: []const u8, revoked_at: i64) !bool {
        const stmt = try self.prepare(
            "UPDATE auth_credentials SET revoked_at=? WHERE credential_id=? AND revoked_at IS NULL",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, revoked_at);
        try bindText(stmt, 2, credential_id);
        try stepDone(stmt);
        return sqlite.sqlite3_changes(self.handle) == 1;
    }

    pub fn putSession(
        self: Repository,
        token_hash: []const u8,
        user_id: []const u8,
        csrf_token: []const u8,
        created_at: i64,
        expires_at: i64,
    ) !void {
        const stmt = try self.prepare(
            \\INSERT INTO auth_sessions(
            \\ token_hash, user_id, csrf_token, created_at, expires_at, last_seen_at
            \\) VALUES (?, ?, ?, ?, ?, ?)
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, token_hash);
        try bindText(stmt, 2, user_id);
        try bindText(stmt, 3, csrf_token);
        try bindI64(stmt, 4, created_at);
        try bindI64(stmt, 5, expires_at);
        try bindI64(stmt, 6, created_at);
        try stepDone(stmt);
    }

    pub fn findSession(self: Repository, gpa: Allocator, token_hash: []const u8) !?Session {
        const stmt = try self.prepare(
            \\SELECT token_hash, user_id, csrf_token, expires_at, revoked_at
            \\FROM auth_sessions WHERE token_hash=?
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindText(stmt, 1, token_hash);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return null;
        return .{
            .token_hash = try dupeColumn(gpa, stmt, 0),
            .user_id = try dupeColumn(gpa, stmt, 1),
            .csrf_token = try dupeColumn(gpa, stmt, 2),
            .expires_at = sqlite.sqlite3_column_int64(stmt, 3),
            .revoked_at = optionalI64(stmt, 4),
        };
    }

    pub fn touchSession(self: Repository, token_hash: []const u8, now: i64) !void {
        const stmt = try self.prepare("UPDATE auth_sessions SET last_seen_at=? WHERE token_hash=?");
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindText(stmt, 2, token_hash);
        try stepDone(stmt);
    }

    pub fn revokeSession(self: Repository, token_hash: []const u8, now: i64) !void {
        const stmt = try self.prepare(
            "UPDATE auth_sessions SET revoked_at=? WHERE token_hash=? AND revoked_at IS NULL",
        );
        defer _ = sqlite.sqlite3_finalize(stmt);
        try bindI64(stmt, 1, now);
        try bindText(stmt, 2, token_hash);
        try stepDone(stmt);
    }

    pub fn reset(self: Repository) !void {
        try self.exec(
            \\DELETE FROM auth_sessions;
            \\DELETE FROM auth_challenges;
            \\DELETE FROM auth_credentials;
            \\DELETE FROM auth_users;
            \\DELETE FROM auth_bootstrap;
        );
    }

    pub fn prune(self: Repository, now: i64) !void {
        const challenges = try self.prepare(
            "DELETE FROM auth_challenges WHERE expires_at <= ? OR used_at IS NOT NULL",
        );
        defer _ = sqlite.sqlite3_finalize(challenges);
        try bindI64(challenges, 1, now);
        try stepDone(challenges);

        const sessions = try self.prepare(
            "DELETE FROM auth_sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL",
        );
        defer _ = sqlite.sqlite3_finalize(sessions);
        try bindI64(sessions, 1, now);
        try stepDone(sessions);
    }

    fn scalar(self: Repository, sql: []const u8) !i64 {
        const stmt = try self.prepare(sql);
        defer _ = sqlite.sqlite3_finalize(stmt);
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_ROW) return error.SqliteStep;
        return sqlite.sqlite3_column_int64(stmt, 0);
    }

    fn exec(self: Repository, sql: []const u8) !void {
        var err: [*c]u8 = null;
        if (sqlite.sqlite3_exec(self.handle, @ptrCast(sql.ptr), null, null, &err) != sqlite.SQLITE_OK) {
            if (err != null) sqlite.sqlite3_free(err);
            return error.SqliteExec;
        }
    }
};

const credential_select =
    \\SELECT credential_id, user_id, public_key, algorithm, sign_count,
    \\ transports, aaguid, backup_eligible, backup_state, label,
    \\ created_at, last_used_at, revoked_at
    \\FROM auth_credentials
;

fn challengeFromStmt(gpa: Allocator, stmt: *sqlite.sqlite3_stmt) !Challenge {
    return .{
        .id = try dupeColumn(gpa, stmt, 0),
        .purpose = try dupeColumn(gpa, stmt, 1),
        .challenge = try dupeColumn(gpa, stmt, 2),
        .user_id = try dupeColumn(gpa, stmt, 3),
        .binding_hash = try dupeColumn(gpa, stmt, 4),
        .expires_at = sqlite.sqlite3_column_int64(stmt, 5),
        .used_at = optionalI64(stmt, 6),
    };
}

fn credentialFromStmt(gpa: Allocator, stmt: *sqlite.sqlite3_stmt) !Credential {
    return .{
        .credential_id = try dupeColumn(gpa, stmt, 0),
        .user_id = try dupeColumn(gpa, stmt, 1),
        .public_key = try dupeColumn(gpa, stmt, 2),
        .algorithm = sqlite.sqlite3_column_int64(stmt, 3),
        .sign_count = @intCast(sqlite.sqlite3_column_int64(stmt, 4)),
        .transports = try dupeColumn(gpa, stmt, 5),
        .aaguid = try dupeColumn(gpa, stmt, 6),
        .backup_eligible = sqlite.sqlite3_column_int64(stmt, 7) != 0,
        .backup_state = sqlite.sqlite3_column_int64(stmt, 8) != 0,
        .label = try dupeColumn(gpa, stmt, 9),
        .created_at = sqlite.sqlite3_column_int64(stmt, 10),
        .last_used_at = optionalI64(stmt, 11),
        .revoked_at = optionalI64(stmt, 12),
    };
}

fn optionalI64(stmt: *sqlite.sqlite3_stmt, index: c_int) ?i64 {
    if (sqlite.sqlite3_column_type(stmt, index) == sqlite.SQLITE_NULL) return null;
    return sqlite.sqlite3_column_int64(stmt, index);
}
