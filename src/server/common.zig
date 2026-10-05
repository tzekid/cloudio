const std = @import("std");
const app_writes = @import("../app/writes.zig");
const core_json = @import("../core/json.zig");
const http = @import("../http/root.zig");

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

pub fn auditOptions(request: http.Request) app_writes.AuditOptions {
    var options = app_writes.AuditOptions{};
    if (request.query("view")) |value| options.view = app_writes.AuditView.parse(value) orelse options.view;
    if (request.query("category")) |value| options.category = value;
    if (request.query("result")) |value| options.result = app_writes.AuditResultFilter.parse(value) orelse options.result;
    if (request.query("target")) |value| options.target = value;
    if (request.query("actor")) |value| options.actor = value;
    if (request.query("window")) |value| options.window = app_writes.AuditWindow.parse(value) orelse options.window;
    if (request.query("limit")) |value| options.limit = std.fmt.parseInt(i64, value, 10) catch options.limit;
    return options.normalized();
}

/// HTTP status and stable code for an application error. Pages turn the
/// code into operator feedback; the passkey API returns it as JSON.
pub const Failure = struct {
    status: u16,
    code: []const u8,
};

pub fn failure(err: anyerror) Failure {
    return switch (err) {
        // Projects
        error.ProjectNotFound => .{ .status = 404, .code = "project_not_found" },
        error.InvalidProjectForm => .{ .status = 400, .code = "request" },
        error.NobDisabled => .{ .status = 409, .code = "nob_disabled" },
        error.ProjectIdConflict => .{ .status = 409, .code = "project_id_conflict" },
        error.ProjectStateChanged => .{ .status = 409, .code = "project_state_changed" },
        error.ProjectNotTrusted => .{ .status = 409, .code = "project_not_approved" },
        error.RunnerNotReady, error.RunnerMetadataMissing => .{ .status = 409, .code = "runner_not_ready" },
        error.PlanNotFound, error.RunNotFound => .{ .status = 404, .code = "not_found" },
        error.PlanUnavailable, error.PlanBindingChanged, error.SourceChanged, error.RunnerDigestMismatch, error.PlanDigestMismatch, error.ManifestDigestMismatch => .{ .status = 409, .code = "plan_no_longer_current" },
        error.ProjectBusy => .{ .status = 409, .code = "project_busy" },
        error.RunnerCacheRootUnsafe, error.RunnerCachePathUnsafe => .{ .status = 409, .code = "runner_cache_unsafe" },
        error.PlanRouteMismatch, error.PlanActorMismatch => .{ .status = 403, .code = "plan_not_authorized" },
        error.ConfirmationRequired, error.ProjectConfirmationMismatch => .{ .status = 428, .code = "confirmation" },
        error.DuplicateRunRequest => .{ .status = 409, .code = "duplicate_run_request" },
        error.RunNotCancelable => .{ .status = 409, .code = "run_not_cancelable" },
        error.UnknownAction, error.ActionUnavailable => .{ .status = 422, .code = "action_unavailable" },
        error.SecretBindingNotFound => .{ .status = 404, .code = "secret_binding_not_found" },
        error.UndeclaredSecret => .{ .status = 422, .code = "secret_not_declared" },
        error.RequiredSecretUnavailable, error.SecretSourceUnavailable, error.ProcessEnvironmentUnavailable => .{ .status = 503, .code = "required_secret_unavailable" },
        error.InvalidSecretSourceKind, error.InvalidSecretSourceRef, error.SecretSourcePathNotAbsolute, error.InvalidEnvironmentName, error.ReservedEnvironmentName, error.InvalidSecretFile, error.InvalidSecretValue, error.SecretFilePermissionsTooBroad, error.SecretFileOwnerMismatch => .{ .status = 400, .code = "invalid_secret_binding" },
        error.SecretSourceMetadataUnavailable => .{ .status = 503, .code = "secret_source_unverifiable" },
        error.UnknownResource => .{ .status = 404, .code = "resource_not_found" },
        error.UnknownResourceControl, error.UndeclaredResourceControl, error.UnsupportedResourceControl, error.ResourceControlNotOwned, error.ResourceControlIsReadOnly, error.UnsupportedPrivilege => .{ .status = 422, .code = "resource_control_unavailable" },
        error.SystemMutationDisabled => .{ .status = 409, .code = "system_mutation_disabled" },
        error.InvalidResourcePlan, error.ResourcePlanIdentityMismatch => .{ .status = 409, .code = "resource_plan_invalid" },
        error.ManifestUnavailable, error.ProjectNotTrustable => .{ .status = 422, .code = "project_not_trustable" },
        error.ProjectManifestNotValid => .{ .status = 422, .code = "project_manifest_invalid" },
        error.RunnerBuildFailed, error.RunnerDescribeFailed, error.RunnerObserveFailed, error.RunnerPlanFailed => .{ .status = 422, .code = "project_runner_failed" },
        error.UnsupportedProtocol, error.ManifestIdentityMismatch, error.ProjectIdentityMismatch, error.SourceIdentityMismatch, error.ProtocolLimitExceeded, error.ProtocolDocumentTooLarge => .{ .status = 422, .code = "project_protocol_invalid" },
        error.InvalidZigVersion, error.InvalidZigVersionFile, error.ZigVersionMismatch, error.ToolchainMappingMissing => .{ .status = 422, .code = "project_toolchain_unavailable" },

        // Docker
        error.InvalidContainerName, error.InvalidContainerLogTail, error.ContainerObservationInvalid => .{ .status = 400, .code = "invalid_container_request" },
        error.ContainerNotObserved => .{ .status = 404, .code = "container_not_observed" },
        error.ContainerActionUnavailable => .{ .status = 409, .code = "container_action_unavailable" },
        error.ContainerRefreshInProgress => .{ .status = 409, .code = "container_refresh_in_progress" },
        error.ContainerCommandFailed => .{ .status = 502, .code = "container_command_failed" },
        error.ContainerStateUnconfirmed => .{ .status = 502, .code = "container_state_unconfirmed" },
        error.ContainerRuntimeUnavailable, error.ContainerLogsFailed => .{ .status = 503, .code = "container_runtime_unavailable" },

        // DNS
        error.InvalidDnsRequest => .{ .status = 400, .code = "invalid_dns_request" },
        error.DnsZoneNotConfigured, error.DnsZoneNotObserved => .{ .status = 404, .code = "dns_zone_not_observed" },
        error.DnsRecordNotObserved => .{ .status = 404, .code = "dns_record_not_observed" },
        error.DnsWriteUnavailable, error.DnsBusy => .{ .status = 409, .code = "dns_write_unavailable" },
        error.DnsProviderRejected => .{ .status = 502, .code = "dns_provider_rejected" },
        error.DnsProviderUnavailable => .{ .status = 503, .code = "dns_provider_unavailable" },

        // VPS
        error.InvalidVpsRequest => .{ .status = 400, .code = "invalid_vps_request" },
        error.VpsNotObserved => .{ .status = 404, .code = "vps_not_observed" },
        error.VpsActionUnavailable => .{ .status = 409, .code = "vps_action_unavailable" },
        error.VpsWriteUnavailable, error.VpsBusy => .{ .status = 409, .code = "vps_write_unavailable" },
        error.VpsProviderRejected, error.VpsActionFailed => .{ .status = 502, .code = "vps_provider_rejected" },
        error.VpsProviderUnavailable => .{ .status = 503, .code = "vps_provider_unavailable" },

        // Routes
        error.InvalidRouteRequest => .{ .status = 400, .code = "invalid_caddy_route" },
        error.RouteNotObserved => .{ .status = 404, .code = "caddy_route_not_observed" },
        error.RouteAlreadyExists => .{ .status = 409, .code = "caddy_route_exists" },
        error.RouteNeedsAdoption => .{ .status = 409, .code = "caddy_adoption_required" },
        error.RouteNotOwned => .{ .status = 409, .code = "caddy_route_not_owned" },
        error.CaddyBusy, error.CaddyWriteUnavailable => .{ .status = 409, .code = "caddy_write_unavailable" },
        error.CaddyObservationChanged => .{ .status = 409, .code = "caddy_observation_changed" },
        error.CaddyFragmentInvalid, error.CaddyValidationFailed => .{ .status = 422, .code = "caddy_validation_failed" },
        error.CaddyWriteFailed => .{ .status = 503, .code = "caddy_fragment_write_failed" },
        error.CaddyReloadFailed => .{ .status = 502, .code = "caddy_reload_failed" },
        error.CaddyVerificationFailed => .{ .status = 502, .code = "caddy_verification_failed" },
        error.CaddyRecoveryFailed => .{ .status = 500, .code = "caddy_recovery_failed" },

        // Browser Run
        error.InvalidBrowserRunRequest => .{ .status = 400, .code = "invalid_request" },
        error.BrowserRunTokenRequired => .{ .status = 409, .code = "token_required" },
        error.BrowserRunAccountNotObserved => .{ .status = 404, .code = "account_not_observed" },
        error.BrowserRunDestinationPolicyRequired, error.BrowserRunDestinationDenied => .{ .status = 403, .code = "destination_denied" },
        error.BrowserRunBusy => .{ .status = 409, .code = "busy" },

        // Dashboard
        error.RefreshInProgress => .{ .status = 409, .code = "in_progress" },

        // Passkeys
        error.InvalidAuthPolicy, error.InsecureAuthOrigin, error.AuthRpOriginMismatch => .{ .status = 500, .code = "auth_policy_invalid" },
        error.InvalidBootstrap, error.InvalidChallenge, error.InvalidPasskeyResponse, error.Unauthorized => .{ .status = 401, .code = "authentication_failed" },
        error.AuthAlreadyConfigured, error.CredentialAlreadyRegistered => .{ .status = 409, .code = "authentication_conflict" },
        error.AuthNotConfigured => .{ .status = 409, .code = "passkey_setup_required" },
        error.LastCredential => .{ .status = 409, .code = "last_passkey_cannot_be_removed" },
        error.CredentialNotFound => .{ .status = 404, .code = "credential_not_found" },
        error.InvalidCredentialLabel, error.InvalidTransports, error.InvalidBootstrapTtl => .{ .status = 400, .code = "bad_request" },
        else => .{ .status = 500, .code = "internal" },
    };
}
