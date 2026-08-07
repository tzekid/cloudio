const std = @import("std");
const app_dashboard = @import("app_dashboard");
const app_writes = @import("app_writes");
const core_json = @import("core_json");
const http = @import("http");

pub fn badRequest(writer: *std.Io.Writer) !u16 {
    try writer.writeAll("{\"error\":\"bad_request\"}\n");
    return 400;
}

pub fn jsonBody(gpa: std.mem.Allocator, body: []const u8) ?std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    if (parsed.value != .object) {
        parsed.deinit();
        return null;
    }
    return parsed;
}

pub fn strField(value: std.json.Value, name: []const u8) ?[]const u8 {
    return core_json.fieldString(value, name);
}

pub fn boolField(value: std.json.Value, name: []const u8) ?bool {
    return core_json.fieldBool(value, name);
}

pub fn intQuery(request: http.Request, key: []const u8, fallback: i64) i64 {
    const raw = request.query(key) orelse return fallback;
    return std.fmt.parseInt(i64, raw, 10) catch fallback;
}

pub fn dashboardOptions(request: http.Request, defaults: app_dashboard.Options) app_dashboard.Options {
    var out = defaults;
    if (request.query("domain")) |value| out.domain = value;
    if (request.query("issues")) |value| out.issues_only = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
    if (request.query("section")) |value| out.section = app_dashboard.Section.parse(value) orelse out.section;
    if (request.query("limit")) |value| out.limit = std.fmt.parseInt(i64, value, 10) catch out.limit;
    return out.normalized();
}

pub fn auditOptions(request: http.Request) app_writes.AuditOptions {
    var options = app_writes.AuditOptions{};
    if (request.query("view")) |value| options.view = app_writes.AuditView.parse(value) orelse options.view;
    if (request.query("category")) |value| options.category = value;
    if (request.query("result")) |value| options.result = app_writes.AuditResultFilter.parse(value) orelse options.result;
    if (request.query("target")) |value| options.target = value;
    if (request.query("actor")) |value| options.actor = value;
    if (request.query("window")) |value| options.window = app_writes.AuditWindow.parse(value) orelse options.window;
    options.limit = intQuery(request, "limit", options.limit);
    return options.normalized();
}

pub const ApiErrorResponse = struct {
    status: u16,
    body: []const u8,
};

pub fn mapApiError(err: anyerror) ApiErrorResponse {
    return switch (err) {
        error.AppBusy => .{ .status = 409, .body = "{\"error\":\"app_busy\"}\n" },
        error.AppExists => .{ .status = 409, .body = "{\"error\":\"app_exists\"}\n" },
        error.AppNotFound, error.DeployNotFound => .{ .status = 404, .body = "{\"error\":\"not_found\"}\n" },
        error.ProjectNotFound => .{ .status = 404, .body = "{\"error\":\"project_not_found\"}\n" },
        error.InvalidProjectForm => .{ .status = 400, .body = "{\"error\":\"bad_request\"}\n" },
        error.NobDisabled => .{ .status = 409, .body = "{\"error\":\"nob_disabled\"}\n" },
        error.ProjectIdConflict => .{ .status = 409, .body = "{\"error\":\"project_id_conflict\"}\n" },
        error.ManifestDigestMismatch => .{ .status = 409, .body = "{\"error\":\"manifest_changed\"}\n" },
        error.ProjectStateChanged => .{ .status = 409, .body = "{\"error\":\"project_state_changed\"}\n" },
        error.ProjectNotTrusted => .{ .status = 409, .body = "{\"error\":\"project_not_approved\"}\n" },
        error.RunnerNotReady, error.RunnerMetadataMissing => .{ .status = 409, .body = "{\"error\":\"runner_not_ready\"}\n" },
        error.PlanNotFound, error.RunNotFound => .{ .status = 404, .body = "{\"error\":\"not_found\"}\n" },
        error.PlanUnavailable, error.PlanBindingChanged, error.SourceChanged, error.RunnerDigestMismatch, error.PlanDigestMismatch => .{ .status = 409, .body = "{\"error\":\"plan_no_longer_current\"}\n" },
        error.ProjectBusy => .{ .status = 409, .body = "{\"error\":\"project_busy\"}\n" },
        error.RunnerCacheRootUnsafe, error.RunnerCachePathUnsafe => .{ .status = 409, .body = "{\"error\":\"runner_cache_unsafe\"}\n" },
        error.PlanRouteMismatch, error.PlanActorMismatch => .{ .status = 403, .body = "{\"error\":\"plan_not_authorized\"}\n" },
        error.ConfirmationRequired => .{ .status = 428, .body = "{\"error\":\"confirmation_required\"}\n" },
        error.ProjectConfirmationMismatch => .{ .status = 428, .body = "{\"error\":\"project_confirmation_mismatch\"}\n" },
        error.DuplicateRunRequest => .{ .status = 409, .body = "{\"error\":\"duplicate_run_request\"}\n" },
        error.RunNotCancelable => .{ .status = 409, .body = "{\"error\":\"run_not_cancelable\"}\n" },
        error.InvalidOperationLogPath => .{ .status = 409, .body = "{\"error\":\"operation_log_unavailable\"}\n" },
        error.UnknownAction, error.ActionUnavailable => .{ .status = 422, .body = "{\"error\":\"action_unavailable\"}\n" },
        error.SecretBindingNotFound => .{ .status = 404, .body = "{\"error\":\"secret_binding_not_found\"}\n" },
        error.UndeclaredSecret => .{ .status = 422, .body = "{\"error\":\"secret_not_declared\"}\n" },
        error.RequiredSecretUnavailable, error.SecretSourceUnavailable, error.ProcessEnvironmentUnavailable => .{ .status = 503, .body = "{\"error\":\"required_secret_unavailable\"}\n" },
        error.InvalidSecretSourceKind, error.InvalidSecretSourceRef, error.SecretSourcePathNotAbsolute, error.InvalidEnvironmentName, error.ReservedEnvironmentName, error.InvalidSecretFile, error.InvalidSecretValue, error.SecretFilePermissionsTooBroad, error.SecretFileOwnerMismatch => .{ .status = 400, .body = "{\"error\":\"invalid_secret_binding\"}\n" },
        error.SecretSourceMetadataUnavailable => .{ .status = 503, .body = "{\"error\":\"secret_source_unverifiable\"}\n" },
        error.UnknownResource => .{ .status = 404, .body = "{\"error\":\"resource_not_found\"}\n" },
        error.UnknownResourceControl, error.UndeclaredResourceControl, error.UnsupportedResourceControl, error.ResourceControlNotOwned, error.ResourceControlIsReadOnly, error.UnsupportedPrivilege => .{ .status = 422, .body = "{\"error\":\"resource_control_unavailable\"}\n" },
        error.SystemMutationDisabled => .{ .status = 409, .body = "{\"error\":\"system_mutation_disabled\"}\n" },
        error.InvalidResourcePlan, error.ResourcePlanIdentityMismatch => .{ .status = 409, .body = "{\"error\":\"resource_plan_invalid\"}\n" },
        error.JournalctlUnavailable, error.JournalctlFailed => .{ .status = 503, .body = "{\"error\":\"resource_logs_unavailable\"}\n" },
        error.ManifestUnavailable, error.ProjectNotTrustable => .{ .status = 422, .body = "{\"error\":\"project_not_trustable\"}\n" },
        error.ProjectManifestNotValid => .{ .status = 422, .body = "{\"error\":\"project_manifest_invalid\"}\n" },
        error.RunnerBuildFailed, error.RunnerDescribeFailed, error.RunnerObserveFailed => .{ .status = 422, .body = "{\"error\":\"project_runner_failed\"}\n" },
        error.UnsupportedProtocol, error.ManifestIdentityMismatch, error.ProjectIdentityMismatch, error.SourceIdentityMismatch, error.ProtocolLimitExceeded, error.ProtocolDocumentTooLarge => .{ .status = 422, .body = "{\"error\":\"project_protocol_invalid\"}\n" },
        error.InvalidZigVersion, error.InvalidZigVersionFile, error.ZigVersionMismatch, error.ToolchainMappingMissing => .{ .status = 422, .body = "{\"error\":\"project_toolchain_unavailable\"}\n" },
        error.NoRollbackTarget => .{ .status = 409, .body = "{\"error\":\"no_rollback_target\"}\n" },
        error.ReleaseMissing => .{ .status = 422, .body = "{\"error\":\"release_missing\"}\n" },
        error.InvalidName, error.SourceRequired, error.SourceConflict, error.WorkdirMissing, error.UnknownRoute => .{ .status = 400, .body = "{\"error\":\"bad_request\"}\n" },
        error.InvalidContainerName, error.InvalidContainerLogTail, error.ContainerObservationInvalid => .{ .status = 400, .body = "{\"error\":\"invalid_container_request\"}\n" },
        error.ContainerNotObserved => .{ .status = 404, .body = "{\"error\":\"container_not_observed\"}\n" },
        error.ContainerActionUnavailable => .{ .status = 409, .body = "{\"error\":\"container_action_unavailable\"}\n" },
        error.ContainerRefreshInProgress => .{ .status = 409, .body = "{\"error\":\"container_refresh_in_progress\"}\n" },
        error.RefreshInProgress => .{ .status = 409, .body = "{\"error\":\"refresh_in_progress\"}\n" },
        error.ContainerCommandFailed => .{ .status = 502, .body = "{\"error\":\"container_command_failed\"}\n" },
        error.ContainerStateUnconfirmed => .{ .status = 502, .body = "{\"error\":\"container_state_unconfirmed\"}\n" },
        error.ContainerRuntimeUnavailable, error.ContainerLogsFailed => .{ .status = 503, .body = "{\"error\":\"container_runtime_unavailable\"}\n" },
        error.InvalidDnsRequest => .{ .status = 400, .body = "{\"error\":\"invalid_dns_request\"}\n" },
        error.DnsZoneNotConfigured, error.DnsZoneNotObserved => .{ .status = 404, .body = "{\"error\":\"dns_zone_not_observed\"}\n" },
        error.DnsRecordNotObserved => .{ .status = 404, .body = "{\"error\":\"dns_record_not_observed\"}\n" },
        error.DnsWriteUnavailable, error.DnsBusy => .{ .status = 409, .body = "{\"error\":\"dns_write_unavailable\"}\n" },
        error.DnsProviderRejected => .{ .status = 502, .body = "{\"error\":\"dns_provider_rejected\"}\n" },
        error.DnsProviderUnavailable => .{ .status = 503, .body = "{\"error\":\"dns_provider_unavailable\"}\n" },
        error.InvalidVpsRequest => .{ .status = 400, .body = "{\"error\":\"invalid_vps_request\"}\n" },
        error.VpsNotObserved => .{ .status = 404, .body = "{\"error\":\"vps_not_observed\"}\n" },
        error.VpsActionUnavailable => .{ .status = 409, .body = "{\"error\":\"vps_action_unavailable\"}\n" },
        error.VpsWriteUnavailable, error.VpsBusy => .{ .status = 409, .body = "{\"error\":\"vps_write_unavailable\"}\n" },
        error.VpsProviderRejected, error.VpsActionFailed => .{ .status = 502, .body = "{\"error\":\"vps_provider_rejected\"}\n" },
        error.VpsProviderUnavailable => .{ .status = 503, .body = "{\"error\":\"vps_provider_unavailable\"}\n" },
        error.InvalidRouteRequest => .{ .status = 400, .body = "{\"error\":\"invalid_caddy_route\"}\n" },
        error.RouteNotObserved => .{ .status = 404, .body = "{\"error\":\"caddy_route_not_observed\"}\n" },
        error.RouteAlreadyExists, error.RouteNeedsAdoption, error.RouteNotOwned, error.CaddyBusy, error.CaddyWriteUnavailable, error.CaddyObservationChanged => .{ .status = 409, .body = "{\"error\":\"caddy_write_unavailable\"}\n" },
        error.CaddyFragmentInvalid, error.CaddyValidationFailed => .{ .status = 422, .body = "{\"error\":\"caddy_validation_failed\"}\n" },
        error.CaddyWriteFailed => .{ .status = 503, .body = "{\"error\":\"caddy_fragment_write_failed\"}\n" },
        error.CaddyReloadFailed, error.CaddyVerificationFailed => .{ .status = 502, .body = "{\"error\":\"caddy_apply_failed\"}\n" },
        error.CaddyRecoveryFailed => .{ .status = 500, .body = "{\"error\":\"caddy_recovery_failed\"}\n" },
        error.InvalidAuthPolicy, error.InsecureAuthOrigin, error.AuthRpOriginMismatch => .{ .status = 500, .body = "{\"error\":\"auth_policy_invalid\"}\n" },
        error.InvalidBootstrap, error.InvalidChallenge, error.InvalidPasskeyResponse, error.Unauthorized => .{ .status = 401, .body = "{\"error\":\"authentication_failed\"}\n" },
        error.AuthAlreadyConfigured, error.CredentialAlreadyRegistered => .{ .status = 409, .body = "{\"error\":\"authentication_conflict\"}\n" },
        error.AuthNotConfigured => .{ .status = 409, .body = "{\"error\":\"passkey_setup_required\"}\n" },
        error.LastCredential => .{ .status = 409, .body = "{\"error\":\"last_passkey_cannot_be_removed\"}\n" },
        error.CredentialNotFound => .{ .status = 404, .body = "{\"error\":\"credential_not_found\"}\n" },
        error.InvalidCredentialLabel, error.InvalidTransports, error.InvalidBootstrapTtl => .{ .status = 400, .body = "{\"error\":\"bad_request\"}\n" },
        else => .{ .status = 500, .body = "{\"error\":\"internal\"}\n" },
    };
}
