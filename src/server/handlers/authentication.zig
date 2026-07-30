const std = @import("std");
const app_authentication = @import("app_authentication");
const core_json = @import("core_json");
const http = @import("http");
const auth = @import("../auth.zig");
const common = @import("../common.zig");
const context = @import("../context.zig");

pub fn setupOptions(
    ctx: context.Context,
    request: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    const token = request.header("x-cloudio-bootstrap") orelse return error.InvalidBootstrap;
    try app_authentication.writeSetupOptions(appContext(ctx), token, writer);
    return 200;
}

pub fn setupVerify(
    ctx: context.Context,
    request: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    extra_headers: *std.Io.Writer,
) !u16 {
    const token = request.header("x-cloudio-bootstrap") orelse return error.InvalidBootstrap;
    const input = parseRegistration(ctx.gpa, request.body, token) orelse return error.InvalidPasskeyResponse;
    defer input.parsed.deinit();
    const issued_session = (try app_authentication.finishRegistration(appContext(ctx), input.value)) orelse
        return error.InvalidPasskeyResponse;
    defer issued_session.deinit(ctx.gpa);
    try auth.writeSessionCookie(
        extra_headers,
        isSecure(ctx),
        issued_session.token,
        app_authentication.session_seconds,
    );
    try writeSessionJson(writer, issued_session);
    return 201;
}

pub fn loginOptions(
    ctx: context.Context,
    _: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    try app_authentication.writeLoginOptions(appContext(ctx), writer);
    return 200;
}

pub fn loginVerify(
    ctx: context.Context,
    request: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    extra_headers: *std.Io.Writer,
) !u16 {
    const input = parseAuthentication(ctx.gpa, request.body) orelse return error.InvalidPasskeyResponse;
    defer input.parsed.deinit();
    const issued_session = try app_authentication.finishAuthentication(appContext(ctx), input.value);
    defer issued_session.deinit(ctx.gpa);
    try auth.writeSessionCookie(
        extra_headers,
        isSecure(ctx),
        issued_session.token,
        app_authentication.session_seconds,
    );
    try writeSessionJson(writer, issued_session);
    return 200;
}

pub fn session(
    ctx: context.Context,
    _: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    const user_id = ctx.auth_user_id orelse return error.Unauthorized;
    const csrf_token = ctx.auth_csrf_token orelse return error.Unauthorized;
    try writer.writeAll("{\"authenticated\":true,\"user_id\":");
    try core_json.writeString(writer, user_id);
    try writer.writeAll(",\"csrf_token\":");
    try core_json.writeString(writer, csrf_token);
    try writer.writeAll("}\n");
    return 200;
}

pub fn logout(
    ctx: context.Context,
    request: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    extra_headers: *std.Io.Writer,
) !u16 {
    if (auth.sessionToken(request, isSecure(ctx))) |token| {
        try app_authentication.revokeSession(appContext(ctx), token);
    }
    try auth.writeClearedSessionCookie(extra_headers, isSecure(ctx));
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn credentialOptions(
    ctx: context.Context,
    _: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    const user_id = ctx.auth_user_id orelse return error.Unauthorized;
    try app_authentication.writeAdditionalRegistrationOptions(appContext(ctx), user_id, writer);
    return 200;
}

pub fn credentialVerify(
    ctx: context.Context,
    request: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    _ = ctx.auth_user_id orelse return error.Unauthorized;
    const input = parseRegistration(ctx.gpa, request.body, null) orelse return error.InvalidPasskeyResponse;
    defer input.parsed.deinit();
    if (try app_authentication.finishRegistration(appContext(ctx), input.value) != null) {
        return error.InvalidPasskeyResponse;
    }
    try writer.writeAll("{\"ok\":true}\n");
    return 201;
}

pub fn credentials(
    ctx: context.Context,
    _: http.Request,
    _: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    _ = ctx.auth_user_id orelse return error.Unauthorized;
    try app_authentication.writeCredentials(appContext(ctx), writer);
    return 200;
}

pub fn credentialLabel(
    ctx: context.Context,
    request: http.Request,
    params: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    _ = ctx.auth_user_id orelse return error.Unauthorized;
    const credential_id = params.get("id") orelse return error.CredentialNotFound;
    var parsed = common.jsonBody(ctx.gpa, request.body) orelse return error.InvalidCredentialLabel;
    defer parsed.deinit();
    const label = common.strField(parsed.value, "label") orelse return error.InvalidCredentialLabel;
    try app_authentication.updateCredentialLabel(appContext(ctx), credential_id, label);
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

pub fn credentialRevoke(
    ctx: context.Context,
    _: http.Request,
    params: http.Params,
    writer: *std.Io.Writer,
    _: *std.Io.Writer,
) !u16 {
    _ = ctx.auth_user_id orelse return error.Unauthorized;
    const credential_id = params.get("id") orelse return error.CredentialNotFound;
    try app_authentication.revokeCredential(appContext(ctx), credential_id);
    try writer.writeAll("{\"ok\":true}\n");
    return 200;
}

const ParsedRegistration = struct {
    parsed: std.json.Parsed(std.json.Value),
    value: app_authentication.RegistrationFinish,
};

fn parseRegistration(gpa: std.mem.Allocator, body: []const u8, bootstrap_token: ?[]const u8) ?ParsedRegistration {
    const parsed = common.jsonBody(gpa, body) orelse return null;
    const challenge_id = common.strField(parsed.value, "challenge_id") orelse {
        parsed.deinit();
        return null;
    };
    const attestation_object = common.strField(parsed.value, "attestation_object") orelse {
        parsed.deinit();
        return null;
    };
    const client_data_json = common.strField(parsed.value, "client_data_json") orelse {
        parsed.deinit();
        return null;
    };
    return .{
        .parsed = parsed,
        .value = .{
            .challenge_id = challenge_id,
            .bootstrap_token = bootstrap_token,
            .attestation_object = attestation_object,
            .client_data_json = client_data_json,
            .transports = common.strField(parsed.value, "transports") orelse "",
            .label = common.strField(parsed.value, "label") orelse "Passkey",
        },
    };
}

const ParsedAuthentication = struct {
    parsed: std.json.Parsed(std.json.Value),
    value: app_authentication.AuthenticationFinish,
};

fn parseAuthentication(gpa: std.mem.Allocator, body: []const u8) ?ParsedAuthentication {
    const parsed = common.jsonBody(gpa, body) orelse return null;
    const challenge_id = common.strField(parsed.value, "challenge_id") orelse {
        parsed.deinit();
        return null;
    };
    const credential_id = common.strField(parsed.value, "credential_id") orelse {
        parsed.deinit();
        return null;
    };
    const authenticator_data = common.strField(parsed.value, "authenticator_data") orelse {
        parsed.deinit();
        return null;
    };
    const client_data_json = common.strField(parsed.value, "client_data_json") orelse {
        parsed.deinit();
        return null;
    };
    const signature = common.strField(parsed.value, "signature") orelse {
        parsed.deinit();
        return null;
    };
    return .{
        .parsed = parsed,
        .value = .{
            .challenge_id = challenge_id,
            .credential_id = credential_id,
            .authenticator_data = authenticator_data,
            .client_data_json = client_data_json,
            .signature = signature,
        },
    };
}

fn writeSessionJson(writer: *std.Io.Writer, value: app_authentication.Session) !void {
    try writer.writeAll("{\"authenticated\":true,\"user_id\":");
    try core_json.writeString(writer, value.user_id);
    try writer.writeAll(",\"csrf_token\":");
    try core_json.writeString(writer, value.csrf_token);
    try writer.print(",\"expires_at\":{d}}}\n", .{value.expires_at});
}

fn appContext(ctx: context.Context) app_authentication.Context {
    return .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .db = ctx.db,
        .origin = ctx.config.auth_origin,
        .rp_id = ctx.config.auth_rp_id,
    };
}

fn isSecure(ctx: context.Context) bool {
    return std.mem.startsWith(u8, ctx.config.auth_origin, "https://");
}

test "flat WebAuthn response parser is strict about required fields" {
    const gpa = std.testing.allocator;
    const valid =
        \\{"challenge_id":"challenge","attestation_object":"att","client_data_json":"client","transports":"internal","label":"MacBook"}
    ;
    const parsed = parseRegistration(gpa, valid, null).?;
    defer parsed.parsed.deinit();
    try std.testing.expectEqualStrings("challenge", parsed.value.challenge_id);
    try std.testing.expectEqualStrings("MacBook", parsed.value.label);
    try std.testing.expect(parseRegistration(gpa, "{}", null) == null);
}
