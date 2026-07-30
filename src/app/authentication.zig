const std = @import("std");
const core_json = @import("core_json");
const core_time = @import("core_time");
const db_store = @import("db_store");
const security_passkeys = @import("security_passkeys");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const default_bootstrap_seconds: u32 = 10 * 60;
pub const max_bootstrap_seconds: u32 = 60 * 60;
pub const challenge_seconds: i64 = 5 * 60;
pub const session_seconds: i64 = 12 * 60 * 60;
pub const max_label_bytes: usize = 64;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
    origin: []const u8,
    rp_id: []const u8,
};

pub const Status = struct {
    configured: bool,
    credential_count: i64,
    active_session_count: i64,
    bootstrap_active: bool,
};

pub const Bootstrap = struct {
    setup_url: []u8,
    expires_at: i64,

    pub fn deinit(self: Bootstrap, gpa: Allocator) void {
        gpa.free(self.setup_url);
    }
};

pub const Session = struct {
    token: []u8,
    csrf_token: []u8,
    user_id: []u8,
    expires_at: i64,

    pub fn deinit(self: Session, gpa: Allocator) void {
        secureFree(gpa, self.token);
        secureFree(gpa, self.csrf_token);
        gpa.free(self.user_id);
    }
};

pub const RegistrationFinish = struct {
    challenge_id: []const u8,
    bootstrap_token: ?[]const u8 = null,
    attestation_object: []const u8,
    client_data_json: []const u8,
    transports: []const u8 = "",
    label: []const u8 = "Passkey",
};

pub const AuthenticationFinish = struct {
    challenge_id: []const u8,
    credential_id: []const u8,
    authenticator_data: []const u8,
    client_data_json: []const u8,
    signature: []const u8,
};

pub fn validatePolicy(origin: []const u8, rp_id: []const u8) !void {
    if (origin.len == 0 or origin.len > 255 or rp_id.len == 0 or rp_id.len > 253) {
        return error.InvalidAuthPolicy;
    }
    if (std.mem.endsWith(u8, origin, "/") or
        std.mem.startsWith(u8, rp_id, ".") or
        std.mem.endsWith(u8, rp_id, ".") or
        std.mem.indexOf(u8, rp_id, "..") != null)
    {
        return error.InvalidAuthPolicy;
    }
    for (rp_id) |byte| {
        if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '-' and byte != '.') {
            return error.InvalidAuthPolicy;
        }
    }

    const secure = std.mem.startsWith(u8, origin, "https://");
    const plain_http = std.mem.startsWith(u8, origin, "http://");
    if (!secure and !plain_http) return error.InvalidAuthPolicy;
    const scheme_bytes: usize = if (secure) "https://".len else "http://".len;
    const authority = origin[scheme_bytes..];
    if (authority.len == 0 or std.mem.indexOfAny(u8, authority, "/?#@") != null) {
        return error.InvalidAuthPolicy;
    }
    const colon = std.mem.indexOfScalar(u8, authority, ':');
    const host = if (colon) |port| authority[0..port] else authority;
    if (colon) |port| {
        const port_text = authority[port + 1 ..];
        const port_number = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidAuthPolicy;
        if (port_number == 0) return error.InvalidAuthPolicy;
    }
    if (!std.mem.eql(u8, host, rp_id)) return error.AuthRpOriginMismatch;
    if (!secure and
        !std.mem.eql(u8, host, "localhost") and
        !std.mem.eql(u8, host, "127.0.0.1"))
    {
        return error.InsecureAuthOrigin;
    }
}

pub fn status(ctx: Context) !Status {
    try validatePolicy(ctx.origin, ctx.rp_id);
    const now = try nowI64();
    const credential_count = try ctx.db.auth().activeCredentialCount();
    return .{
        .configured = credential_count > 0,
        .credential_count = credential_count,
        .active_session_count = try ctx.db.auth().activeSessionCount(now),
        .bootstrap_active = try ctx.db.auth().bootstrapActive(now),
    };
}

pub fn createBootstrap(ctx: Context, ttl_seconds: u32) !Bootstrap {
    try validatePolicy(ctx.origin, ctx.rp_id);
    if (ttl_seconds == 0 or ttl_seconds > max_bootstrap_seconds) return error.InvalidBootstrapTtl;

    const now = try nowI64();
    const token = try randomToken(ctx.io, ctx.gpa);
    defer secureFree(ctx.gpa, token);
    const hash = hashToken(token);
    const expires_at = now + @as(i64, ttl_seconds);

    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    if (try ctx.db.auth().activeCredentialCount() != 0) return error.AuthAlreadyConfigured;
    try ctx.db.auth().putBootstrap(&hash, now, expires_at);
    try ctx.db.insertAudit("auth.bootstrap.create", "ok", "one-use passkey enrollment authorized from CLI");
    try ctx.db.exec("COMMIT");
    committed = true;

    return .{
        .setup_url = try std.fmt.allocPrint(ctx.gpa, "{s}/setup.html#token={s}", .{ ctx.origin, token }),
        .expires_at = expires_at,
    };
}

pub fn writeSetupOptions(
    ctx: Context,
    bootstrap_token: []const u8,
    writer: anytype,
) !void {
    const now = try nowI64();
    const bootstrap_hash = hashToken(bootstrap_token);
    if (!try ctx.db.auth().bootstrapMatches(&bootstrap_hash, now)) return error.InvalidBootstrap;
    if (try ctx.db.auth().activeCredentialCount() != 0) return error.AuthAlreadyConfigured;

    const user_id = try randomToken(ctx.io, ctx.gpa);
    defer ctx.gpa.free(user_id);
    try writeRegistrationOptions(ctx, "setup", user_id, &bootstrap_hash, writer);
}

pub fn writeAdditionalRegistrationOptions(
    ctx: Context,
    user_id: []const u8,
    writer: anytype,
) !void {
    try writeRegistrationOptions(ctx, "register", user_id, null, writer);
}

pub fn writeLoginOptions(ctx: Context, writer: anytype) !void {
    if (try ctx.db.auth().activeCredentialCount() == 0) return error.AuthNotConfigured;
    const now = try nowI64();
    const challenge_id = try randomToken(ctx.io, ctx.gpa);
    defer ctx.gpa.free(challenge_id);
    const challenge = try randomToken(ctx.io, ctx.gpa);
    defer ctx.gpa.free(challenge);
    try ctx.db.auth().putChallenge(
        challenge_id,
        "login",
        challenge,
        null,
        null,
        now,
        now + challenge_seconds,
    );

    try writer.writeAll("{\"challenge_id\":");
    try core_json.writeString(writer, challenge_id);
    try writer.writeAll(",\"publicKey\":{\"challenge\":");
    try core_json.writeString(writer, challenge);
    try writer.writeAll(",\"rpId\":");
    try core_json.writeString(writer, ctx.rp_id);
    try writer.writeAll(
        ",\"timeout\":300000,\"userVerification\":\"required\",\"allowCredentials\":[]}}\n",
    );
}

pub fn finishRegistration(ctx: Context, input: RegistrationFinish) !?Session {
    try validateLabel(input.label);
    try validateTransports(input.transports);
    const now = try nowI64();
    const challenge = (try ctx.db.auth().findChallenge(ctx.gpa, input.challenge_id)) orelse
        return error.InvalidChallenge;
    defer challenge.deinit(ctx.gpa);
    const setup = std.mem.eql(u8, challenge.purpose, "setup");
    if (!setup and !std.mem.eql(u8, challenge.purpose, "register")) return error.InvalidChallenge;
    if (challenge.used_at != null or challenge.expires_at <= now) return error.InvalidChallenge;

    var bootstrap_hash: [64]u8 = undefined;
    if (setup) {
        const token = input.bootstrap_token orelse return error.InvalidBootstrap;
        bootstrap_hash = hashToken(token);
        if (!constantTimeEqual(challenge.binding_hash, &bootstrap_hash) or
            !try ctx.db.auth().bootstrapMatches(&bootstrap_hash, now))
        {
            return error.InvalidBootstrap;
        }
    } else if (input.bootstrap_token != null) {
        return error.InvalidBootstrap;
    }

    // Every verification attempt consumes its challenge, including failures.
    if (!try ctx.db.auth().consumeChallenge(input.challenge_id, challenge.purpose, now)) {
        return error.InvalidChallenge;
    }

    const verified = security_passkeys.verifyRegistration(ctx.gpa, .{
        .attestation_object = input.attestation_object,
        .client_data_json = input.client_data_json,
        .expected_challenge = challenge.challenge,
        .expected_origin = ctx.origin,
        .rp_id = ctx.rp_id,
    }) catch |err| {
        try auditFailure(ctx, "auth.passkey.register", err);
        return error.InvalidPasskeyResponse;
    };
    defer verified.deinit(ctx.gpa);

    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    if (setup) {
        if (try ctx.db.auth().activeCredentialCount() != 0 or
            !try ctx.db.auth().consumeBootstrap(&bootstrap_hash, now))
        {
            return error.InvalidBootstrap;
        }
        try ctx.db.auth().ensureUser(challenge.user_id, "Cloudio owner", now);
    }

    const credential = db_store.AuthCredential{
        .credential_id = @constCast(verified.credential_id),
        .user_id = challenge.user_id,
        .public_key = @constCast(verified.public_key),
        .algorithm = verified.algorithm,
        .sign_count = verified.sign_count,
        .transports = @constCast(input.transports),
        .aaguid = @constCast(verified.aaguid),
        .backup_eligible = verified.backup_eligible,
        .backup_state = verified.backup_state,
        .label = @constCast(input.label),
        .created_at = now,
        .last_used_at = null,
        .revoked_at = null,
    };
    ctx.db.auth().insertCredential(credential) catch return error.CredentialAlreadyRegistered;

    const issued = if (setup) try issueSession(ctx, challenge.user_id, now) else null;
    errdefer if (issued) |session_value| session_value.deinit(ctx.gpa);
    try ctx.db.insertAudit(
        if (setup) "auth.passkey.setup" else "auth.passkey.add",
        "ok",
        if (setup) "initial passkey enrolled" else "additional passkey enrolled",
    );
    try ctx.db.exec("COMMIT");
    committed = true;
    return issued;
}

pub fn finishAuthentication(ctx: Context, input: AuthenticationFinish) !Session {
    const now = try nowI64();
    const challenge = (try ctx.db.auth().findChallenge(ctx.gpa, input.challenge_id)) orelse
        return error.InvalidChallenge;
    defer challenge.deinit(ctx.gpa);
    if (!std.mem.eql(u8, challenge.purpose, "login") or
        challenge.used_at != null or
        challenge.expires_at <= now)
    {
        return error.InvalidChallenge;
    }
    if (!try ctx.db.auth().consumeChallenge(input.challenge_id, "login", now)) {
        return error.InvalidChallenge;
    }

    const credential = (try ctx.db.auth().findCredential(ctx.gpa, input.credential_id)) orelse {
        try ctx.db.insertAudit("auth.login", "denied", "unknown credential");
        return error.InvalidPasskeyResponse;
    };
    defer credential.deinit(ctx.gpa);
    if (credential.revoked_at != null) return error.InvalidPasskeyResponse;

    const verified = security_passkeys.verifyAuthentication(ctx.gpa, .{
        .authenticator_data = input.authenticator_data,
        .client_data_json = input.client_data_json,
        .signature = input.signature,
        .public_key = credential.public_key,
        .expected_challenge = challenge.challenge,
        .expected_origin = ctx.origin,
        .rp_id = ctx.rp_id,
        .known_sign_count = credential.sign_count,
    }) catch |err| {
        try auditFailure(ctx, "auth.login", err);
        return error.InvalidPasskeyResponse;
    };

    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    try ctx.db.auth().updateCredentialUse(
        credential.credential_id,
        verified.recommended_sign_count,
        verified.backup_state,
        now,
    );
    const session = try issueSession(ctx, credential.user_id, now);
    errdefer session.deinit(ctx.gpa);
    try ctx.db.insertAudit(
        "auth.login",
        if (verified.sign_count_regressed) "warning" else "ok",
        if (verified.sign_count_regressed)
            "passkey accepted; signature counter regressed"
        else
            "passkey accepted",
    );
    try ctx.db.exec("COMMIT");
    committed = true;
    return session;
}

pub fn validateSession(ctx: Context, raw_token: []const u8) !?Session {
    if (raw_token.len < 32 or raw_token.len > 128) return null;
    const now = try nowI64();
    const hash = hashToken(raw_token);
    const stored = (try ctx.db.auth().findSession(ctx.gpa, &hash)) orelse return null;
    defer stored.deinit(ctx.gpa);
    if (stored.revoked_at != null or stored.expires_at <= now) return null;
    try ctx.db.auth().touchSession(&hash, now);
    return .{
        .token = try ctx.gpa.dupe(u8, raw_token),
        .csrf_token = try ctx.gpa.dupe(u8, stored.csrf_token),
        .user_id = try ctx.gpa.dupe(u8, stored.user_id),
        .expires_at = stored.expires_at,
    };
}

pub fn revokeSession(ctx: Context, raw_token: []const u8) !void {
    const hash = hashToken(raw_token);
    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    try ctx.db.auth().revokeSession(&hash, try nowI64());
    try ctx.db.insertAudit("auth.logout", "ok", "session revoked");
    try ctx.db.exec("COMMIT");
    committed = true;
}

pub fn updateCredentialLabel(ctx: Context, credential_id: []const u8, label: []const u8) !void {
    try validateLabel(label);
    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    if (!try ctx.db.auth().updateCredentialLabel(credential_id, label)) return error.CredentialNotFound;
    try ctx.db.insertAudit("auth.passkey.label", "ok", "passkey label changed");
    try ctx.db.exec("COMMIT");
    committed = true;
}

pub fn writeCredentials(ctx: Context, writer: anytype) !void {
    var rows = try ctx.db.auth().listCredentials(ctx.gpa);
    defer rows.deinit(ctx.gpa);
    try writer.writeAll("{\"credentials\":[");
    var first = true;
    for (rows.items) |row| {
        if (row.revoked_at != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try core_json.writeStringField(writer, "id", row.credential_id, true);
        try core_json.writeStringField(writer, "label", row.label, true);
        try core_json.writeStringField(writer, "transports", row.transports, true);
        try core_json.writeIntField(writer, "created_at", row.created_at, true);
        try writer.writeAll("\"last_used_at\":");
        if (row.last_used_at) |value| try writer.print("{d}", .{value}) else try writer.writeAll("null");
        try writer.writeByte(',');
        try core_json.writeBoolField(writer, "backup_eligible", row.backup_eligible, true);
        try core_json.writeBoolField(writer, "backup_state", row.backup_state, false);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub fn revokeCredential(ctx: Context, credential_id: []const u8) !void {
    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    if (try ctx.db.auth().activeCredentialCount() <= 1) return error.LastCredential;
    if (!try ctx.db.auth().revokeCredential(credential_id, try nowI64())) return error.CredentialNotFound;
    try ctx.db.insertAudit("auth.passkey.revoke", "ok", "passkey revoked");
    try ctx.db.exec("COMMIT");
    committed = true;
}

pub fn reset(ctx: Context) !void {
    try ctx.db.exec("BEGIN IMMEDIATE");
    var committed = false;
    defer if (!committed) ctx.db.exec("ROLLBACK") catch {};
    try ctx.db.auth().reset();
    try ctx.db.insertAudit("auth.reset", "ok", "passkey authentication reset after verified backup");
    try ctx.db.exec("COMMIT");
    committed = true;
}

fn writeRegistrationOptions(
    ctx: Context,
    purpose: []const u8,
    user_id: []const u8,
    binding_hash: ?[]const u8,
    writer: anytype,
) !void {
    const now = try nowI64();
    const challenge_id = try randomToken(ctx.io, ctx.gpa);
    defer ctx.gpa.free(challenge_id);
    const challenge = try randomToken(ctx.io, ctx.gpa);
    defer ctx.gpa.free(challenge);
    try ctx.db.auth().putChallenge(
        challenge_id,
        purpose,
        challenge,
        user_id,
        binding_hash,
        now,
        now + challenge_seconds,
    );

    var credentials = try ctx.db.auth().listCredentials(ctx.gpa);
    defer credentials.deinit(ctx.gpa);
    try writer.writeAll("{\"challenge_id\":");
    try core_json.writeString(writer, challenge_id);
    try writer.writeAll(",\"publicKey\":{\"challenge\":");
    try core_json.writeString(writer, challenge);
    try writer.writeAll(",\"rp\":{\"name\":\"Cloudio\",\"id\":");
    try core_json.writeString(writer, ctx.rp_id);
    try writer.writeAll("},\"user\":{\"id\":");
    try core_json.writeString(writer, user_id);
    try writer.writeAll(
        ",\"name\":\"owner\",\"displayName\":\"Cloudio owner\"},\"pubKeyCredParams\":[{\"type\":\"public-key\",\"alg\":-7},{\"type\":\"public-key\",\"alg\":-257}],\"timeout\":300000,\"attestation\":\"none\",\"authenticatorSelection\":{\"residentKey\":\"required\",\"requireResidentKey\":true,\"userVerification\":\"required\"},\"excludeCredentials\":[",
    );
    var first = true;
    for (credentials.items) |credential| {
        if (credential.revoked_at != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeAll("{\"type\":\"public-key\",\"id\":");
        try core_json.writeString(writer, credential.credential_id);
        try writer.writeAll(",\"transports\":");
        try writeTransportsArray(writer, credential.transports);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}}\n");
}

fn issueSession(ctx: Context, user_id: []const u8, now: i64) !Session {
    const token = try randomToken(ctx.io, ctx.gpa);
    errdefer secureFree(ctx.gpa, token);
    const csrf_token = try randomToken(ctx.io, ctx.gpa);
    errdefer secureFree(ctx.gpa, csrf_token);
    const token_hash = hashToken(token);
    const expires_at = now + session_seconds;
    try ctx.db.auth().putSession(&token_hash, user_id, csrf_token, now, expires_at);
    return .{
        .token = token,
        .csrf_token = csrf_token,
        .user_id = try ctx.gpa.dupe(u8, user_id),
        .expires_at = expires_at,
    };
}

fn randomToken(io: Io, gpa: Allocator) ![]u8 {
    var bytes: [32]u8 = undefined;
    try io.randomSecure(&bytes);
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(bytes.len);
    const encoded = try gpa.alloc(u8, size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(encoded, &bytes);
    @memset(&bytes, 0);
    return encoded;
}

pub fn hashToken(token: []const u8) [64]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn constantTimeEqual(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    var difference: u8 = 0;
    for (left, right) |a, b| difference |= a ^ b;
    return difference == 0;
}

fn validateLabel(label: []const u8) !void {
    if (label.len == 0 or label.len > max_label_bytes or !std.unicode.utf8ValidateSlice(label)) {
        return error.InvalidCredentialLabel;
    }
    for (label) |byte| if (byte < 0x20 or byte == 0x7f) return error.InvalidCredentialLabel;
}

fn validateTransports(value: []const u8) !void {
    if (value.len > 128) return error.InvalidTransports;
    var parts = std.mem.splitScalar(u8, value, ',');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (!std.mem.eql(u8, part, "internal") and
            !std.mem.eql(u8, part, "hybrid") and
            !std.mem.eql(u8, part, "usb") and
            !std.mem.eql(u8, part, "nfc") and
            !std.mem.eql(u8, part, "ble"))
        {
            return error.InvalidTransports;
        }
    }
}

fn writeTransportsArray(writer: anytype, value: []const u8) !void {
    try writer.writeByte('[');
    var first = true;
    var parts = std.mem.splitScalar(u8, value, ',');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try core_json.writeString(writer, part);
    }
    try writer.writeByte(']');
}

fn nowI64() !i64 {
    return @intCast(try core_time.currentEpochSeconds());
}

fn auditFailure(ctx: Context, action: []const u8, err: anyerror) !void {
    const detail = try std.fmt.allocPrint(ctx.gpa, "verification denied: {s}", .{@errorName(err)});
    defer ctx.gpa.free(detail);
    try ctx.db.insertAudit(action, "denied", detail);
}

fn secureFree(gpa: Allocator, value: []u8) void {
    @memset(value, 0);
    gpa.free(value);
}

test "auth policy permits HTTPS and explicit localhost development only" {
    try validatePolicy("https://cloudio.example.test", "cloudio.example.test");
    try validatePolicy("http://localhost:9328", "localhost");
    try validatePolicy("http://127.0.0.1:9328", "127.0.0.1");
    try std.testing.expectError(
        error.InsecureAuthOrigin,
        validatePolicy("http://cloudio.example.test", "cloudio.example.test"),
    );
    try std.testing.expectError(
        error.InsecureAuthOrigin,
        validatePolicy("http://localhost.evil.test", "localhost.evil.test"),
    );
    try std.testing.expectError(
        error.InvalidAuthPolicy,
        validatePolicy("https://cloudio.example.test:", "cloudio.example.test"),
    );
    try std.testing.expectError(
        error.AuthRpOriginMismatch,
        validatePolicy("https://cloudio.example.test", "example.test"),
    );
}

test "tokens are hashed deterministically and compared in constant time" {
    const first = hashToken("secret");
    const second = hashToken("secret");
    const third = hashToken("different");
    try std.testing.expect(constantTimeEqual(&first, &second));
    try std.testing.expect(!constantTimeEqual(&first, &third));
}

test "credential labels and transports are deliberately narrow" {
    try validateLabel("MacBook Air");
    try std.testing.expectError(error.InvalidCredentialLabel, validateLabel(""));
    try validateTransports("internal,hybrid");
    try std.testing.expectError(error.InvalidTransports, validateTransports("serial"));
}

test "bootstrap stores a hash and issues an expiring fragment URL" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/cloudio-auth-bootstrap.db",
        .{tmp.sub_path},
    );
    defer gpa.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    const ctx = Context{
        .io = std.testing.io,
        .gpa = gpa,
        .db = &db,
        .origin = "https://cloudio.example.test",
        .rp_id = "cloudio.example.test",
    };

    const bootstrap = try createBootstrap(ctx, 600);
    defer bootstrap.deinit(gpa);
    const marker = "#token=";
    const marker_index = std.mem.indexOf(u8, bootstrap.setup_url, marker).?;
    const raw_token = bootstrap.setup_url[marker_index + marker.len ..];
    try std.testing.expect(raw_token.len >= 32);
    const token_hash = hashToken(raw_token);
    try std.testing.expect(try db.auth().bootstrapMatches(&token_hash, try nowI64()));
    try std.testing.expect(std.mem.indexOf(u8, &token_hash, raw_token) == null);

    const current = try status(ctx);
    try std.testing.expect(!current.configured);
    try std.testing.expect(current.bootstrap_active);
}

test "sessions store hashes and validate opaque cookie values" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/cloudio-auth-session.db",
        .{tmp.sub_path},
    );
    defer gpa.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    const ctx = Context{
        .io = std.testing.io,
        .gpa = gpa,
        .db = &db,
        .origin = "https://cloudio.example.test",
        .rp_id = "cloudio.example.test",
    };
    const now = try nowI64();
    try db.auth().ensureUser("owner-id", "Cloudio owner", now);
    const issued = try issueSession(ctx, "owner-id", now);
    defer issued.deinit(gpa);
    const token_hash = hashToken(issued.token);
    const stored = (try db.auth().findSession(gpa, &token_hash)).?;
    defer stored.deinit(gpa);
    try std.testing.expect(!std.mem.eql(u8, stored.token_hash, issued.token));

    const validated = (try validateSession(ctx, issued.token)).?;
    defer validated.deinit(gpa);
    try std.testing.expectEqualStrings("owner-id", validated.user_id);
    try std.testing.expectEqualStrings(issued.csrf_token, validated.csrf_token);
}
