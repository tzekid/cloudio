const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const core_time = @import("core_time");
const db_store = @import("db_store");
const provider_capabilities = @import("provider_capabilities");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const containsIgnoreCase = app_provider_coverage_render.containsIgnoreCase;
const eqlIgnoreCase = app_provider_coverage_render.eqlIgnoreCase;

const actual_capture_cloudflare_scope_hint_limit: i64 = 200;
const actual_capture_cloudflare_resource_hint_limit: i64 = 5000;
const actual_capture_hostinger_vps_hint_limit: i64 = 50;
const actual_capture_hostinger_hint_limit: i64 = 5000;

pub const ProviderFilter = provider_routes.ProviderFilter;
pub const RouteFilter = app_provider_coverage_routes.RouteFilter;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;

pub const RouteStatus = struct {
    any: bool = false,
    ok: bool = false,
    err: bool = false,
    events: i64 = 0,
    latest_at: []const u8 = "",
};

pub const CaptureState = enum {
    ok,
    missing,
    non_ok,

    pub fn name(self: CaptureState) []const u8 {
        return switch (self) {
            .ok => "ok",
            .missing => "missing",
            .non_ok => "non_ok",
        };
    }
};

pub const SourceSummary = struct {
    total_sources: usize = 0,
    captured_with_hints: usize = 0,
    captured_empty: usize = 0,
    captured_without_hints: usize = 0,
    captured_unknown_body: usize = 0,
    ready_to_capture: usize = 0,
    waiting_for_inputs: usize = 0,
    diagnostic_blocked: usize = 0,
    captured_error: usize = 0,
    no_official_source: usize = 0,
    not_in_catalog: usize = 0,
    unmapped: usize = 0,
    not_eligible: usize = 0,
    body_array: usize = 0,
    body_data_array: usize = 0,
    body_error_object: usize = 0,
    body_no_evidence: usize = 0,
    body_other: usize = 0,
};

pub const Hints = struct {
    configured_domains: []const []const u8 = &.{},
    cloudflare_accounts: []const db_store.CloudflareAccountRow = &.{},
    cloudflare_zones: []const db_store.CloudflareZoneRow = &.{},
    cloudflare_resources: []const db_store.CloudflareResourceHintRow = &.{},
    cloudflare_inventory: []const db_store.CloudflareInventoryHintRow = &.{},
    hostinger_vps: []const db_store.HostingerVpsRow = &.{},
    hostinger_resources: []const db_store.HostingerResourceHintRow = &.{},
    hostinger_inventory: []const db_store.HostingerInventoryHintRow = &.{},
};

pub const InputSource = struct {
    operation_id: []const u8,
    hint_kind: []const u8,
    purpose: []const u8,
};

pub const SourceBodyEvidence = struct {
    shape: []const u8 = "no_evidence",
    item_count: ?usize = null,
    body_bytes: usize = 0,
};

const hostinger_domain_sources = [_]InputSource{.{
    .operation_id = "domains_getDomainListV1",
    .hint_kind = "domains_getDomainListV1",
    .purpose = "discover account domains",
}};

const hostinger_vps_sources = [_]InputSource{.{
    .operation_id = "VPS_getVirtualMachinesV1",
    .hint_kind = "VPS_getVirtualMachinesV1",
    .purpose = "discover VPS ids",
}};

const hostinger_action_sources = [_]InputSource{.{
    .operation_id = "VPS_getActionsV1",
    .hint_kind = "VPS_getActionsV1",
    .purpose = "discover VPS action ids",
}};

const hostinger_template_sources = [_]InputSource{.{
    .operation_id = "VPS_getTemplatesV1",
    .hint_kind = "VPS_getTemplatesV1",
    .purpose = "discover VPS template ids",
}};

const hostinger_firewall_sources = [_]InputSource{.{
    .operation_id = "VPS_getFirewallListV1",
    .hint_kind = "VPS_getFirewallListV1",
    .purpose = "discover VPS firewall ids",
}};

const hostinger_post_install_sources = [_]InputSource{.{
    .operation_id = "VPS_getPostInstallScriptsV1",
    .hint_kind = "VPS_getPostInstallScriptsV1",
    .purpose = "discover post-install script ids",
}};

const hostinger_dns_snapshot_sources = [_]InputSource{.{
    .operation_id = "DNS_getDNSSnapshotListV1",
    .hint_kind = "DNS_getDNSSnapshotListV1",
    .purpose = "discover DNS snapshot ids for the selected domain",
}};

const hostinger_whois_sources = [_]InputSource{.{
    .operation_id = "domains_getWHOISProfileListV1",
    .hint_kind = "domains_getWHOISProfileListV1",
    .purpose = "discover WHOIS profile ids",
}};

const hostinger_username_sources = [_]InputSource{.{
    .operation_id = "hosting_listWebsitesV1",
    .hint_kind = "hosting_listWebsitesV1",
    .purpose = "discover hosting account usernames from websites",
}};

const hostinger_order_sources = [_]InputSource{
    .{
        .operation_id = "hosting_listOrdersV1",
        .hint_kind = "hosting_listOrdersV1",
        .purpose = "discover hosting order ids",
    },
    .{
        .operation_id = "hosting_listWebsitesV1",
        .hint_kind = "hosting_listWebsitesV1",
        .purpose = "reuse website inventory related order ids",
    },
};

const hostinger_database_sources = [_]InputSource{.{
    .operation_id = "hosting_listAccountDatabasesV1",
    .hint_kind = "hosting_listAccountDatabasesV1",
    .purpose = "discover database names for a hosting account",
}};

const hostinger_nodejs_build_sources = [_]InputSource{.{
    .operation_id = "hosting_listNodeJSBuildsV1",
    .hint_kind = "hosting_listNodeJSBuildsV1",
    .purpose = "discover NodeJS build UUIDs for a website",
}};

const hostinger_docker_project_sources = [_]InputSource{.{
    .operation_id = "VPS_getProjectListV1",
    .hint_kind = "VPS_getProjectListV1",
    .purpose = "discover Docker Manager project names for a VPS",
}};

const hostinger_reach_profile_sources = [_]InputSource{.{
    .operation_id = "reach_listProfilesV1",
    .hint_kind = "reach_listProfilesV1",
    .purpose = "discover Reach profile UUIDs",
}};

const hostinger_reach_segment_sources = [_]InputSource{.{
    .operation_id = "reach_listSegmentsV1",
    .hint_kind = "reach_listSegmentsV1",
    .purpose = "discover Reach segment UUIDs",
}};

const cloudflare_account_organization_sources = [_]InputSource{.{
    .operation_id = "Accounts_listAccountOrganizations",
    .hint_kind = "Accounts_listAccountOrganizations",
    .purpose = "discover organization ids linked to the selected account",
}};

const cloudflare_account_user_group_sources = [_]InputSource{.{
    .operation_id = "account-user-group-list",
    .hint_kind = "account-user-group-list",
    .purpose = "discover account IAM user group ids",
}};

const cloudflare_account_user_group_member_sources = [_]InputSource{.{
    .operation_id = "account-user-group-member-list",
    .hint_kind = "account-user-group-member-list",
    .purpose = "discover account IAM user group member ids",
}};

const cloudflare_user_invite_sources = [_]InputSource{.{
    .operation_id = "user'-s-invites-list-invitations",
    .hint_kind = "user'-s-invites-list-invitations",
    .purpose = "discover Cloudflare user invitation ids",
}};

const cloudflare_membership_sources = [_]InputSource{.{
    .operation_id = "user'-s-account-memberships-list-memberships",
    .hint_kind = "user'-s-account-memberships-list-memberships",
    .purpose = "discover Cloudflare account membership ids",
}};

const cloudflare_account_custom_csr_sources = [_]InputSource{.{
    .operation_id = "custom-csrs-for-an-account-list-custom-csrs",
    .hint_kind = "custom-csrs-for-an-account-list-custom-csrs",
    .purpose = "discover account custom CSR ids",
}};

const cloudflare_zone_custom_csr_sources = [_]InputSource{.{
    .operation_id = "custom-csrs-for-a-zone-list-custom-csrs",
    .hint_kind = "custom-csrs-for-a-zone-list-custom-csrs",
    .purpose = "discover zone custom CSR ids",
}};

const cloudflare_account_custom_asset_sources = [_]InputSource{.{
    .operation_id = "custom-assets-for-an-account-list-custom-assets",
    .hint_kind = "custom-assets-for-an-account-list-custom-assets",
    .purpose = "discover account custom asset names",
}};

const cloudflare_zone_custom_asset_sources = [_]InputSource{.{
    .operation_id = "custom-assets-for-a-zone-list-custom-assets",
    .hint_kind = "custom-assets-for-a-zone-list-custom-assets",
    .purpose = "discover zone custom asset names",
}};

const cloudflare_zone_custom_hostname_sources = [_]InputSource{.{
    .operation_id = "custom-hostname-for-a-zone-list-custom-hostnames",
    .hint_kind = "custom-hostname-for-a-zone-list-custom-hostnames",
    .purpose = "discover zone custom hostname ids",
}};

const cloudflare_zone_ua_rule_sources = [_]InputSource{.{
    .operation_id = "user-agent-blocking-rules-list-user-agent-blocking-rules",
    .hint_kind = "user-agent-blocking-rules-list-user-agent-blocking-rules",
    .purpose = "discover user-agent blocking rule ids",
}};

const cloudflare_zone_lockdown_sources = [_]InputSource{.{
    .operation_id = "zone-lockdown-list-zone-lockdown-rules",
    .hint_kind = "zone-lockdown-list-zone-lockdown-rules",
    .purpose = "discover zone lockdown rule ids",
}};

const cloudflare_zone_setting_sources = [_]InputSource{.{
    .operation_id = "zone-settings-get-all-zone-settings",
    .hint_kind = "zone-settings-get-all-zone-settings",
    .purpose = "discover zone setting ids",
}};

const cloudflare_zone_snippet_sources = [_]InputSource{.{
    .operation_id = "listZoneSnippets",
    .hint_kind = "listZoneSnippets",
    .purpose = "discover zone snippet names",
}};

const cloudflare_client_certificate_sources = [_]InputSource{.{
    .operation_id = "client-certificate-for-a-zone-list-client-certificates",
    .hint_kind = "client-certificate-for-a-zone-list-client-certificates",
    .purpose = "discover zone client certificate ids",
}};

const cloudflare_certificate_pack_sources = [_]InputSource{.{
    .operation_id = "certificate-packs-list-certificate-packs",
    .hint_kind = "certificate-packs-list-certificate-packs",
    .purpose = "discover zone certificate pack ids",
}};

const cloudflare_custom_ssl_sources = [_]InputSource{.{
    .operation_id = "custom-ssl-for-a-zone-list-ssl-configurations",
    .hint_kind = "custom-ssl-for-a-zone-list-ssl-configurations",
    .purpose = "discover zone custom SSL certificate ids",
}};

const cloudflare_keyless_ssl_sources = [_]InputSource{.{
    .operation_id = "keyless-ssl-for-a-zone-list-keyless-ssl-configurations",
    .hint_kind = "keyless-ssl-for-a-zone-list-keyless-ssl-configurations",
    .purpose = "discover zone Keyless SSL certificate ids",
}};

const cloudflare_per_hostname_tls_sources = [_]InputSource{.{
    .operation_id = "per-hostname-tls-settings-list",
    .hint_kind = "per-hostname-tls-settings-list",
    .purpose = "discover per-hostname TLS setting ids and hostnames",
}};

const cloudflare_access_account_saml_sources = [_]InputSource{.{
    .operation_id = "access-saml-certificates-list-certificate-sets",
    .hint_kind = "access-saml-certificates-list-certificate-sets",
    .purpose = "discover Access SAML certificate set ids",
}};

const cloudflare_access_account_application_sources = [_]InputSource{.{
    .operation_id = "access-applications-list-access-applications",
    .hint_kind = "access-applications-list-access-applications",
    .purpose = "discover account Access application ids",
}};

const cloudflare_access_zone_application_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-applications-list-access-applications",
    .hint_kind = "zone-level-access-applications-list-access-applications",
    .purpose = "discover zone Access application ids",
}};

const cloudflare_access_account_identity_provider_sources = [_]InputSource{.{
    .operation_id = "access-identity-providers-list-access-identity-providers",
    .hint_kind = "access-identity-providers-list-access-identity-providers",
    .purpose = "discover account Access identity provider ids",
}};

const cloudflare_access_zone_identity_provider_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-identity-providers-list-access-identity-providers",
    .hint_kind = "zone-level-access-identity-providers-list-access-identity-providers",
    .purpose = "discover zone Access identity provider ids",
}};

const cloudflare_access_account_custom_page_sources = [_]InputSource{.{
    .operation_id = "access-custom-pages-list-custom-pages",
    .hint_kind = "access-custom-pages-list-custom-pages",
    .purpose = "discover account Access custom page ids",
}};

const cloudflare_access_account_group_sources = [_]InputSource{.{
    .operation_id = "access-groups-list-access-groups",
    .hint_kind = "access-groups-list-access-groups",
    .purpose = "discover account Access group ids",
}};

const cloudflare_access_zone_group_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-groups-list-access-groups",
    .hint_kind = "zone-level-access-groups-list-access-groups",
    .purpose = "discover zone Access group ids",
}};

const cloudflare_access_account_application_policy_sources = [_]InputSource{.{
    .operation_id = "access-policies-list-access-app-policies",
    .hint_kind = "access-policies-list-access-app-policies",
    .purpose = "discover account Access application policy ids",
}};

const cloudflare_access_zone_application_policy_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-policies-list-access-policies",
    .hint_kind = "zone-level-access-policies-list-access-policies",
    .purpose = "discover zone Access application policy ids",
}};

const cloudflare_access_account_reusable_policy_sources = [_]InputSource{.{
    .operation_id = "access-policies-list-access-reusable-policies",
    .hint_kind = "access-policies-list-access-reusable-policies",
    .purpose = "discover account Access reusable policy ids",
}};

const cloudflare_access_account_tag_sources = [_]InputSource{.{
    .operation_id = "access-tags-list-tags",
    .hint_kind = "access-tags-list-tags",
    .purpose = "discover account Access tag names",
}};

const cloudflare_access_account_infra_target_sources = [_]InputSource{.{
    .operation_id = "infra-targets-list",
    .hint_kind = "infra-targets-list",
    .purpose = "discover account Access infrastructure target ids",
}};

const cloudflare_access_account_service_token_sources = [_]InputSource{.{
    .operation_id = "access-service-tokens-list-service-tokens",
    .hint_kind = "access-service-tokens-list-service-tokens",
    .purpose = "discover account Access service token ids",
}};

const cloudflare_access_zone_service_token_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-service-tokens-list-service-tokens",
    .hint_kind = "zone-level-access-service-tokens-list-service-tokens",
    .purpose = "discover zone Access service token ids",
}};

const cloudflare_access_idp_federation_grant_sources = [_]InputSource{.{
    .operation_id = "access-idp-federation-grants-list",
    .hint_kind = "access-idp-federation-grants-list",
    .purpose = "discover Access IdP federation grant ids",
}};

const cloudflare_scim_user_sources = [_]InputSource{.{
    .operation_id = "scim-users-list",
    .hint_kind = "scim-users-list",
    .purpose = "discover SCIM user ids",
}};

const cloudflare_zero_trust_user_sources = [_]InputSource{.{
    .operation_id = "zero-trust-users-get-users",
    .hint_kind = "zero-trust-users-get-users",
    .purpose = "discover Zero Trust user ids",
}};

const cloudflare_zero_trust_user_session_sources = [_]InputSource{.{
    .operation_id = "zero-trust-users-get-active-sessions",
    .hint_kind = "zero-trust-users-get-active-sessions",
    .purpose = "discover Zero Trust user active session nonces",
}};

const cloudflare_access_account_mtls_sources = [_]InputSource{.{
    .operation_id = "access-mtls-authentication-list-mtls-certificates",
    .hint_kind = "access-mtls-authentication-list-mtls-certificates",
    .purpose = "discover account Access mTLS certificate ids",
}};

const cloudflare_access_zone_mtls_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-mtls-authentication-list-mtls-certificates",
    .hint_kind = "zone-level-access-mtls-authentication-list-mtls-certificates",
    .purpose = "discover zone Access mTLS certificate ids",
}};

const cloudflare_access_account_ca_sources = [_]InputSource{.{
    .operation_id = "access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
    .hint_kind = "access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
    .purpose = "discover account Access short-lived CA app ids",
}};

const cloudflare_access_zone_ca_sources = [_]InputSource{.{
    .operation_id = "zone-level-access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
    .hint_kind = "zone-level-access-short-lived-certificate-c-as-list-short-lived-certificate-c-as",
    .purpose = "discover zone Access short-lived CA app ids",
}};

const cloudflare_zero_trust_certificate_sources = [_]InputSource{.{
    .operation_id = "zero-trust-certificates-list-zero-trust-certificates",
    .hint_kind = "zero-trust-certificates-list-zero-trust-certificates",
    .purpose = "discover Zero Trust certificate ids",
}};

const cloudflare_mtls_certificate_sources = [_]InputSource{.{
    .operation_id = "m-tls-certificate-management-list-m-tls-certificates",
    .hint_kind = "m-tls-certificate-management-list-m-tls-certificates",
    .purpose = "discover account mTLS certificate ids",
}};

const cloudflare_origin_ca_certificate_sources = [_]InputSource{.{
    .operation_id = "origin-ca-list-certificates",
    .hint_kind = "origin-ca-list-certificates",
    .purpose = "discover Origin CA certificate ids",
}};

const cloudflare_hostname_aop_certificate_sources = [_]InputSource{.{
    .operation_id = "per-hostname-authenticated-origin-pull-list-certificates",
    .hint_kind = "per-hostname-authenticated-origin-pull-list-certificates",
    .purpose = "discover per-hostname authenticated origin pull certificate ids",
}};

const cloudflare_zone_aop_certificate_sources = [_]InputSource{.{
    .operation_id = "zone-level-authenticated-origin-pulls-list-certificates",
    .hint_kind = "zone-level-authenticated-origin-pulls-list-certificates",
    .purpose = "discover zone authenticated origin pull certificate ids",
}};

const cloudflare_radar_authority_sources = [_]InputSource{.{
    .operation_id = "radar-get-certificate-authorities",
    .hint_kind = "radar-get-certificate-authorities",
    .purpose = "discover Radar certificate authority slugs",
}};

const cloudflare_radar_log_sources = [_]InputSource{.{
    .operation_id = "radar-get-certificate-logs",
    .hint_kind = "radar-get-certificate-logs",
    .purpose = "discover Radar certificate log slugs",
}};

const cloudflare_ai_gateway_sources = [_]InputSource{.{
    .operation_id = "aig-config-list-gateway",
    .hint_kind = "aig-config-list-gateway",
    .purpose = "discover AI Gateway ids",
}};

const cloudflare_ai_gateway_log_sources = [_]InputSource{.{
    .operation_id = "aig-config-list-gateway-logs",
    .hint_kind = "aig-config-list-gateway-logs",
    .purpose = "discover AI Gateway log ids",
}};

const cloudflare_log_explorer_account_dataset_sources = [_]InputSource{
    .{
        .operation_id = "accounts-logs-explorer-datasets-list",
        .hint_kind = "accounts-logs-explorer-datasets-list",
        .purpose = "discover account Log Explorer dataset ids",
    },
    .{
        .operation_id = "accounts-logs-explorer-datasets-available-list",
        .hint_kind = "accounts-logs-explorer-datasets-available-list",
        .purpose = "discover account Log Explorer available dataset ids",
    },
};

const cloudflare_log_explorer_zone_dataset_sources = [_]InputSource{
    .{
        .operation_id = "zones-logs-explorer-datasets-list",
        .hint_kind = "zones-logs-explorer-datasets-list",
        .purpose = "discover zone Log Explorer dataset ids",
    },
    .{
        .operation_id = "zones-logs-explorer-datasets-available-list",
        .hint_kind = "zones-logs-explorer-datasets-available-list",
        .purpose = "discover zone Log Explorer available dataset ids",
    },
};

const cloudflare_dns_view_sources = [_]InputSource{.{
    .operation_id = "dns-views-for-an-account-list-internal-dns-views",
    .hint_kind = "dns-views-for-an-account-list-internal-dns-views",
    .purpose = "discover account DNS internal view ids",
}};

const cloudflare_secondary_dns_acl_sources = [_]InputSource{.{
    .operation_id = "secondary-dns-(-acl)-list-ac-ls",
    .hint_kind = "secondary-dns-(-acl)-list-ac-ls",
    .purpose = "discover Secondary DNS ACL ids",
}};

const cloudflare_secondary_dns_peer_sources = [_]InputSource{.{
    .operation_id = "secondary-dns-(-peer)-list-peers",
    .hint_kind = "secondary-dns-(-peer)-list-peers",
    .purpose = "discover Secondary DNS peer ids",
}};

const cloudflare_secondary_dns_tsig_sources = [_]InputSource{.{
    .operation_id = "secondary-dns-(-tsig)-list-tsi-gs",
    .hint_kind = "secondary-dns-(-tsig)-list-tsi-gs",
    .purpose = "discover Secondary DNS TSIG ids",
}};

const cloudflare_logpush_account_job_sources = [_]InputSource{.{
    .operation_id = "get-accounts-account_id-logpush-jobs",
    .hint_kind = "get-accounts-account_id-logpush-jobs",
    .purpose = "discover account Logpush job ids",
}};

const cloudflare_logpush_zone_job_sources = [_]InputSource{.{
    .operation_id = "get-zones-zone_id-logpush-jobs",
    .hint_kind = "get-zones-zone_id-logpush-jobs",
    .purpose = "discover zone Logpush job ids",
}};

const cloudflare_worker_script_sources = [_]InputSource{.{
    .operation_id = "worker-script-list-workers",
    .hint_kind = "worker-script-list-workers",
    .purpose = "discover Worker script names",
}};

const cloudflare_cloudforce_event_sources = [_]InputSource{.{
    .operation_id = "get_EventListGet",
    .hint_kind = "get_EventListGet",
    .purpose = "discover Cloudforce One event node ids and node types",
}};

const cloudflare_cloudforce_tag_sources = [_]InputSource{.{
    .operation_id = "get_TagList",
    .hint_kind = "get_TagList",
    .purpose = "discover Cloudforce One tag UUIDs",
}};

const cloudflare_magic_bgp_filter_profile_sources = [_]InputSource{.{
    .operation_id = "magic-bgp-list-filter-profiles",
    .hint_kind = "magic-bgp-list-filter-profiles",
    .purpose = "discover Magic BGP filter profile ids",
}};

const cloudflare_magic_connector_sources = [_]InputSource{.{
    .operation_id = "mconn-connector-list",
    .hint_kind = "mconn-connector-list",
    .purpose = "discover Magic Connector ids",
}};

const cloudflare_botnet_asn_sources = [_]InputSource{.{
    .operation_id = "botnet-threat-feed-list-asn",
    .hint_kind = "botnet-threat-feed-list-asn",
    .purpose = "discover Botnet Threat Feed ASNs",
}};

const cloudflare_dns_firewall_sources = [_]InputSource{.{
    .operation_id = "dns-firewall-list-dns-firewall-clusters",
    .hint_kind = "dns-firewall-list-dns-firewall-clusters",
    .purpose = "discover DNS Firewall cluster ids",
}};

const cloudflare_email_security_message_sources = [_]InputSource{.{
    .operation_id = "email_security_investigate",
    .hint_kind = "email_security_investigate",
    .purpose = "discover Email Security investigate message ids",
}};

const cloudflare_email_security_allow_policy_sources = [_]InputSource{.{
    .operation_id = "email_security_list_allow_policies",
    .hint_kind = "email_security_list_allow_policies",
    .purpose = "discover Email Security allow policy ids",
}};

const cloudflare_email_security_blocked_sender_sources = [_]InputSource{.{
    .operation_id = "email_security_list_blocked_senders",
    .hint_kind = "email_security_list_blocked_senders",
    .purpose = "discover Email Security blocked sender pattern ids",
}};

const cloudflare_email_security_domain_sources = [_]InputSource{.{
    .operation_id = "email_security_list_domains",
    .hint_kind = "email_security_list_domains",
    .purpose = "discover Email Security domain ids",
}};

const cloudflare_email_security_impersonation_sources = [_]InputSource{.{
    .operation_id = "email_security_list_impersonation_registry",
    .hint_kind = "email_security_list_impersonation_registry",
    .purpose = "discover Email Security impersonation registry ids",
}};

const cloudflare_email_security_sending_domain_sources = [_]InputSource{.{
    .operation_id = "email_security_list_sending_domain_restrictions",
    .hint_kind = "email_security_list_sending_domain_restrictions",
    .purpose = "discover Email Security sending-domain restriction ids",
}};

const cloudflare_email_security_trusted_domain_sources = [_]InputSource{.{
    .operation_id = "email_security_list_trusted_domains",
    .hint_kind = "email_security_list_trusted_domains",
    .purpose = "discover Email Security trusted domain ids",
}};

const cloudflare_email_security_url_ignore_sources = [_]InputSource{.{
    .operation_id = "email_security_list_url_ignore_patterns",
    .hint_kind = "email_security_list_url_ignore_patterns",
    .purpose = "discover Email Security URL ignore pattern ids",
}};

const cloudflare_user_ip_access_rule_sources = [_]InputSource{.{
    .operation_id = "ip-access-rules-for-a-user-list-ip-access-rules",
    .hint_kind = "ip-access-rules-for-a-user-list-ip-access-rules",
    .purpose = "discover user IP Access rule ids",
}};

const cloudflare_account_ip_access_rule_sources = [_]InputSource{.{
    .operation_id = "ip-access-rules-for-an-account-list-ip-access-rules",
    .hint_kind = "ip-access-rules-for-an-account-list-ip-access-rules",
    .purpose = "discover account IP Access rule ids",
}};

const cloudflare_zone_ip_access_rule_sources = [_]InputSource{.{
    .operation_id = "ip-access-rules-for-a-zone-list-ip-access-rules",
    .hint_kind = "ip-access-rules-for-a-zone-list-ip-access-rules",
    .purpose = "discover zone IP Access rule ids",
}};

const cloudflare_leaked_credential_detection_sources = [_]InputSource{.{
    .operation_id = "waf-product-api-leaked-credentials-list-detections",
    .hint_kind = "waf-product-api-leaked-credentials-list-detections",
    .purpose = "discover Leaked Credential Checks detection ids",
}};

const cloudflare_page_shield_connection_sources = [_]InputSource{.{
    .operation_id = "page-shield-list-connections",
    .hint_kind = "page-shield-list-connections",
    .purpose = "discover Page Shield connection ids",
}};

const cloudflare_page_shield_cookie_sources = [_]InputSource{.{
    .operation_id = "page-shield-list-cookies",
    .hint_kind = "page-shield-list-cookies",
    .purpose = "discover Page Shield cookie ids",
}};

const cloudflare_page_shield_policy_sources = [_]InputSource{.{
    .operation_id = "page-shield-list-policies",
    .hint_kind = "page-shield-list-policies",
    .purpose = "discover Page Shield policy ids",
}};

const cloudflare_page_shield_script_sources = [_]InputSource{.{
    .operation_id = "page-shield-list-scripts",
    .hint_kind = "page-shield-list-scripts",
    .purpose = "discover Page Shield script ids",
}};

const cloudflare_radar_bot_sources = [_]InputSource{.{
    .operation_id = "radar-get-bots",
    .hint_kind = "radar-get-bots",
    .purpose = "discover Radar bot slugs",
}};

const cloudflare_security_center_account_issue_sources = [_]InputSource{.{
    .operation_id = "get-security-center-insights",
    .hint_kind = "get-security-center-insights",
    .purpose = "discover account Security Center issue ids",
}};

const cloudflare_security_center_zone_issue_sources = [_]InputSource{.{
    .operation_id = "get-zone-security-center-insights",
    .hint_kind = "get-zone-security-center-insights",
    .purpose = "discover zone Security Center issue ids",
}};

const cloudflare_r2_catalog_sources = [_]InputSource{.{
    .operation_id = "list-catalogs",
    .hint_kind = "list-catalogs",
    .purpose = "discover R2 catalog bucket names",
}};

const cloudflare_r2_namespace_sources = [_]InputSource{.{
    .operation_id = "list-namespaces",
    .hint_kind = "list-namespaces",
    .purpose = "discover R2 catalog namespaces for a bucket",
}};

const cloudflare_r2_table_sources = [_]InputSource{.{
    .operation_id = "list-tables",
    .hint_kind = "list-tables",
    .purpose = "discover R2 catalog table names for a namespace",
}};

const cloudflare_audit_account_log_sources = [_]InputSource{.{
    .operation_id = "audit-logs-v2-get-account-audit-logs",
    .hint_kind = "audit-logs-v2-get-account-audit-logs",
    .purpose = "discover account audit log event ids and action timestamps",
}};

const cloudflare_audit_organization_log_sources = [_]InputSource{.{
    .operation_id = "audit-logs-v2-get-organization-audit-logs",
    .hint_kind = "audit-logs-v2-get-organization-audit-logs",
    .purpose = "discover organization audit log event ids and action timestamps",
}};

const cloudflare_account_load_balancer_monitor_group_sources = [_]InputSource{.{
    .operation_id = "account-load-balancer-monitor-groups-list-monitor-groups",
    .hint_kind = "account-load-balancer-monitor-groups-list-monitor-groups",
    .purpose = "discover account load-balancer monitor group ids",
}};

const cloudflare_account_load_balancer_monitor_sources = [_]InputSource{.{
    .operation_id = "account-load-balancer-monitors-list-monitors",
    .hint_kind = "account-load-balancer-monitors-list-monitors",
    .purpose = "discover account load-balancer monitor ids",
}};

const cloudflare_user_load_balancer_monitor_sources = [_]InputSource{.{
    .operation_id = "load-balancer-monitors-list-monitors",
    .hint_kind = "load-balancer-monitors-list-monitors",
    .purpose = "discover user load-balancer monitor ids",
}};

const cloudflare_account_load_balancer_pool_sources = [_]InputSource{.{
    .operation_id = "account-load-balancer-pools-list-pools",
    .hint_kind = "account-load-balancer-pools-list-pools",
    .purpose = "discover account load-balancer pool ids",
}};

const cloudflare_user_load_balancer_pool_sources = [_]InputSource{.{
    .operation_id = "load-balancer-pools-list-pools",
    .hint_kind = "load-balancer-pools-list-pools",
    .purpose = "discover user load-balancer pool ids",
}};

const cloudflare_zone_load_balancer_sources = [_]InputSource{.{
    .operation_id = "load-balancers-list-load-balancers",
    .hint_kind = "load-balancers-list-load-balancers",
    .purpose = "discover zone load-balancer ids",
}};

const cloudflare_account_ruleset_entrypoint_version_sources = [_]InputSource{.{
    .operation_id = "listAccountEntrypointRulesetVersions",
    .hint_kind = "listAccountEntrypointRulesetVersions",
    .purpose = "discover account entrypoint ruleset versions",
}};

const cloudflare_zone_ruleset_entrypoint_version_sources = [_]InputSource{.{
    .operation_id = "listZoneEntrypointRulesetVersions",
    .hint_kind = "listZoneEntrypointRulesetVersions",
    .purpose = "discover zone entrypoint ruleset versions",
}};

const cloudflare_account_ruleset_version_sources = [_]InputSource{.{
    .operation_id = "listAccountRulesetVersions",
    .hint_kind = "listAccountRulesetVersions",
    .purpose = "discover account ruleset versions",
}};

const cloudflare_zone_ruleset_version_sources = [_]InputSource{.{
    .operation_id = "listZoneRulesetVersions",
    .hint_kind = "listZoneRulesetVersions",
    .purpose = "discover zone ruleset versions",
}};

const cloudflare_account_ruleset_version_rule_sources = [_]InputSource{.{
    .operation_id = "getAccountRulesetVersion",
    .hint_kind = "getAccountRulesetVersion",
    .purpose = "discover account ruleset version rule tags",
}};

const cloudflare_zone_ruleset_version_rule_sources = [_]InputSource{.{
    .operation_id = "getZoneRulesetVersion",
    .hint_kind = "getZoneRulesetVersion",
    .purpose = "discover zone ruleset version rule tags",
}};

const cloudflare_token_validation_config_sources = [_]InputSource{.{
    .operation_id = "token-validation-config-list",
    .hint_kind = "token-validation-config-list",
    .purpose = "discover token validation config ids",
}};

const cloudflare_token_validation_rule_sources = [_]InputSource{.{
    .operation_id = "token-validation-rules-list",
    .hint_kind = "token-validation-rules-list",
    .purpose = "discover token validation rule ids",
}};

const cloudflare_tunnel_sources = [_]InputSource{.{
    .operation_id = "cloudflare-tunnel-list-cloudflare-tunnels",
    .hint_kind = "cloudflare-tunnel-list-cloudflare-tunnels",
    .purpose = "discover Cloudflare tunnel ids",
}};

const cloudflare_warp_connector_sources = [_]InputSource{.{
    .operation_id = "cloudflare-tunnel-list-warp-connector-tunnels",
    .hint_kind = "cloudflare-tunnel-list-warp-connector-tunnels",
    .purpose = "discover WARP connector tunnel ids",
}};

const cloudflare_gre_tunnel_sources = [_]InputSource{.{
    .operation_id = "magic-gre-tunnels-list-gre-tunnels",
    .hint_kind = "magic-gre-tunnels-list-gre-tunnels",
    .purpose = "discover Magic GRE tunnel ids",
}};

const cloudflare_ipsec_tunnel_sources = [_]InputSource{.{
    .operation_id = "magic-ipsec-tunnels-list-ipsec-tunnels",
    .hint_kind = "magic-ipsec-tunnels-list-ipsec-tunnels",
    .purpose = "discover Magic IPsec tunnel ids",
}};

const cloudflare_tunnel_route_sources = [_]InputSource{.{
    .operation_id = "tunnel-route-list-tunnel-routes",
    .hint_kind = "tunnel-route-list-tunnel-routes",
    .purpose = "discover Zero Trust tunnel route ids and IP routes",
}};

const cloudflare_tunnel_connector_sources = [_]InputSource{.{
    .operation_id = "cloudflare-tunnel-list-cloudflare-tunnel-connections",
    .hint_kind = "cloudflare-tunnel-list-cloudflare-tunnel-connections",
    .purpose = "discover Cloudflare tunnel connector ids",
}};

const cloudflare_warp_connector_connection_sources = [_]InputSource{.{
    .operation_id = "cloudflare-tunnel-list-warp-connector-tunnel-connections",
    .hint_kind = "cloudflare-tunnel-list-warp-connector-tunnel-connections",
    .purpose = "discover WARP connector connection ids",
}};

pub fn loadActualCaptureCloudflareAccountHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareAccountRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareAccountRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

pub fn loadActualCaptureCloudflareZoneHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareZoneRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareZoneRows(gpa, actual_capture_cloudflare_scope_hint_limit);
}

pub fn loadActualCaptureCloudflareResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareResourceHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareResourceHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

pub fn loadActualCaptureCloudflareInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.CloudflareInventoryHintRows {
    if (!provider.includes("cloudflare")) return null;
    return try db.cloudflareInventoryHints(gpa, actual_capture_cloudflare_resource_hint_limit);
}

pub fn loadActualCaptureHostingerHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerVpsRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerVpsRows(gpa, actual_capture_hostinger_vps_hint_limit);
}

pub fn loadActualCaptureHostingerResourceHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerResourceHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerResourceHints(gpa, actual_capture_hostinger_hint_limit);
}

pub fn loadActualCaptureHostingerInventoryHints(gpa: Allocator, db: *Db, provider: ProviderFilter) !?db_store.HostingerInventoryHintRows {
    if (!provider.includes("hostinger")) return null;
    return try db.hostingerInventoryHints(gpa, actual_capture_hostinger_hint_limit);
}

pub fn actualCaptureProviderDbValue(provider: ProviderFilter) ?[]const u8 {
    return switch (provider) {
        .all => null,
        .cloudflare => "cloudflare",
        .hostinger => "hostinger",
    };
}

pub fn actualCaptureRouteFilter(filter: RouteFilter) RouteFilter {
    var next = filter;
    next.method = .GET;
    next.mode = .read;
    next.detail = false;
    return next;
}

pub fn actualCaptureState(route: provider_routes.Route, captures: []const db_store.RouteCaptureEvidenceRow) ?CaptureState {
    if (route.deprecated or !route.isRoutable()) return null;
    if (route.method != .GET or route.mode != .read) return null;
    if (route.request_body.required) return null;
    const operation_id = route.operation_id orelse return null;
    const status = actualRouteCaptureStatus(route.provider.name(), operation_id, captures);
    if (status.ok) return .ok;
    if (status.any) return .non_ok;
    return .missing;
}

pub fn actualRouteCaptureStatus(provider: []const u8, operation_id: []const u8, captures: []const db_store.RouteCaptureEvidenceRow) RouteStatus {
    var out = RouteStatus{};
    for (captures) |capture| {
        if (!std.mem.eql(u8, capture.provider, provider)) continue;
        if (!std.mem.eql(u8, capture.operation_id, operation_id)) continue;
        out.any = true;
        out.events += capture.count;
        if (actualStatusIsOk(capture.status)) out.ok = true;
        if (actualStatusIsError(capture.status)) out.err = true;
        if (capture.latest_at.len != 0 and actualLatestAtLessThan(out.latest_at, capture.latest_at)) out.latest_at = capture.latest_at;
    }
    return out;
}

fn actualStatusIsOk(status: []const u8) bool {
    return std.mem.eql(u8, status, "ok") or
        std.mem.eql(u8, status, "success") or
        std.mem.eql(u8, status, "done") or
        actualHttpStatusIsSuccess(status);
}

fn actualStatusIsError(status: []const u8) bool {
    return actualHttpStatusIsError(status) or
        std.mem.indexOf(u8, status, "error") != null or
        std.mem.indexOf(u8, status, "fail") != null or
        std.mem.indexOf(u8, status, "denied") != null or
        std.mem.indexOf(u8, status, "blocked") != null or
        std.mem.indexOf(u8, status, "permission") != null or
        std.mem.indexOf(u8, status, "not_found") != null or
        std.mem.indexOf(u8, status, "missing") != null;
}

fn actualHttpStatusIsSuccess(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 200 and value < 300;
}

fn actualHttpStatusIsError(status: []const u8) bool {
    if (status.len != 3) return false;
    const value = std.fmt.parseInt(u16, status, 10) catch return false;
    return value >= 400;
}

fn actualLatestAtLessThan(current: []const u8, candidate: []const u8) bool {
    if (current.len == 0) return true;
    return std.mem.order(u8, current, candidate) == .lt;
}

pub fn actualCaptureReady(route: provider_routes.Route, hints: Hints) bool {
    return actualCaptureReadyWithPolicy(route, hints, false);
}

pub fn actualCaptureReadyWithPolicy(route: provider_routes.Route, hints: Hints, include_blocked: bool) bool {
    return actualCaptureRouteExecutable(route, include_blocked) and actualCaptureMissingInputCount(route, hints) == 0;
}

fn actualCaptureRouteExecutable(route: provider_routes.Route, include_blocked: bool) bool {
    return provider_capabilities.routeLiveReadSupported(route) or (include_blocked and provider_capabilities.routeDiagnosticReadSupported(route));
}

pub fn actualCaptureUsesDiagnosticRead(route: provider_routes.Route, include_blocked: bool) bool {
    return include_blocked and !provider_capabilities.routeLiveReadSupported(route) and provider_capabilities.routeDiagnosticReadSupported(route);
}

pub fn actualCaptureMissingInputCount(route: provider_routes.Route, hints: Hints) usize {
    var count: usize = 0;
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) == null) count += 1;
    }
    for (route.query_params) |param| {
        if (param.required and !actualCaptureHasQueryParamHint(route, param.name, hints)) count += 1;
    }
    for (route.header_params) |param| {
        if (param.required) count += 1;
    }
    return count;
}

pub fn actualCapturePathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    return switch (route.provider) {
        .cloudflare => actualCaptureCloudflarePathParamHint(route, name, hints),
        .hostinger => actualCaptureHostingerPathParamHint(route, name, hints),
    };
}

fn actualCaptureCloudflarePathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    if (std.mem.eql(u8, name, "account_id") or std.mem.eql(u8, name, "account_identifier")) return actualCaptureCloudflareAccountIdHint(hints);
    if (std.mem.eql(u8, name, "organization_id")) return actualCaptureCloudflareOrganizationIdHint(hints);
    if (std.mem.eql(u8, name, "zone_id") or std.mem.eql(u8, name, "zone_identifier")) return actualCaptureCloudflareZoneIdHint(hints);
    // The typed-smoke kind can exist in pre-cleanup databases. Nothing writes
    // it now; keep it readable until the planned persistence migration can
    // inventory and remove stored compatibility safely.
    if (std.mem.eql(u8, name, "dns_record_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "route-cloudflare-dns", "route-cloudflare-dns-typed-smoke", "dns", "dns-records" });
    if (std.mem.eql(u8, name, "ruleset_id")) return actualCaptureCloudflareRulesetIdHint(route, hints);
    if (std.mem.eql(u8, name, "ruleset_phase")) return actualCaptureCloudflareRulesetPhaseHint(route, hints);
    if (std.mem.eql(u8, name, "ruleset_version")) return actualCaptureCloudflareRulesetVersionHint(route, hints);
    if (std.mem.eql(u8, name, "rule_tag")) return actualCaptureCloudflareRuleTagHint(route, hints);
    if (std.mem.eql(u8, name, "identifier") and actualCaptureRoutePathContains(route, "/custom_pages/")) return actualCaptureCloudflareCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "asset_name") and actualCaptureRoutePathContains(route, "/custom_pages/assets/")) return actualCaptureCloudflareCustomAssetIdHint(route, hints);
    if (std.mem.eql(u8, name, "custom_page_id")) return actualCaptureCloudflareAccessCustomPageIdHint(route, hints);
    if (std.mem.eql(u8, name, "custom_csr_id")) return actualCaptureCloudflareCustomCsrIdHint(route, hints);
    if (std.mem.eql(u8, name, "custom_hostname_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-hostname-for-a-zone-list-custom-hostnames", "zone-custom-hostnames", "zone-custom-hostname" });
    if (std.mem.eql(u8, name, "certificate_pack_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "certificate-packs-list-certificate-packs", "tls-zone-certificate-packs", "tls-zone-certificate-pack" });
    if (std.mem.eql(u8, name, "identity_provider_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "idp_id")) return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints);
    if (std.mem.eql(u8, name, "grant_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-idp-federation-grants-list", "access-account-idp-federation-grants", "access-account-idp-federation-grant" });
    if (std.mem.eql(u8, name, "user_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-user-group-list", "account-user-groups", "account-user-group" });
    if (std.mem.eql(u8, name, "member_id") and actualCaptureRoutePathContains(route, "/iam/user_groups/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-user-group-member-list", "account-user-group-members", "account-user-group-member" });
    if (std.mem.eql(u8, name, "member_id") and containsIgnoreCase(route.tag, "Account Members")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-members"});
    if (std.mem.eql(u8, name, "role_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-roles"});
    if (std.mem.eql(u8, name, "token_id")) return actualCaptureCloudflareTokenIdHint(route, hints);
    if (std.mem.eql(u8, name, "service_token_id")) return actualCaptureCloudflareAccessServiceTokenIdHint(route, hints);
    if (std.mem.eql(u8, name, "permission_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-permission-groups", "account-token-permission-groups", "user-token-permission-groups" });
    if (std.mem.eql(u8, name, "resource_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"account-resource-groups"});
    if (std.mem.eql(u8, name, "client_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "client-certificate-for-a-zone-list-client-certificates", "zone-api-shield-client-certificates", "zone-client-certificates", "api-shield-client-certificates", "api-shield-client-certificates-for-a-zone" });
    if (std.mem.eql(u8, name, "saml_cert_set_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-saml-certificates-list-certificate-sets", "access-account-saml-certificates" });
    if (std.mem.eql(u8, name, "certificate_id")) return actualCaptureCloudflareCertificateIdHint(route, hints);
    if (std.mem.eql(u8, name, "app_id") and actualCaptureRoutePathContains(route, "/access/apps/")) return actualCaptureCloudflareAccessApplicationIdHint(route, hints);
    if (std.mem.eql(u8, name, "app_id")) return actualCaptureCloudflareAccessCaAppIdHint(route, hints);
    if (std.mem.eql(u8, name, "mtls_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "m-tls-certificate-management-list-m-tls-certificates", "access-account-mtls-certificates", "zero-trust-certificates-list-zero-trust-certificates" });
    if (std.mem.eql(u8, name, "custom_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-ssl-for-a-zone-list-ssl-configurations", "tls-zone-custom-ssl", "tls-zone-custom-ssl-certificate" });
    if (std.mem.eql(u8, name, "keyless_certificate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "keyless-ssl-for-a-zone-list-keyless-ssl-configurations", "tls-zone-keyless-ssl", "tls-zone-keyless-ssl-certificate" });
    if (std.mem.eql(u8, name, "setting_id") and actualCaptureRoutePathContains(route, "/hostnames/settings/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "per-hostname-tls-settings-list", "tls-zone-per-hostname-tls-settings", "tls-zone-per-hostname-tls-setting" });
    if (std.mem.eql(u8, name, "setting_id") and actualCaptureRoutePathContains(route, "/settings/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-settings-get-all-zone-settings", "zone-settings" });
    if (std.mem.eql(u8, name, "hostname") and actualCaptureRoutePathContains(route, "/hostnames/settings/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "per-hostname-tls-settings-list", "tls-zone-per-hostname-tls-settings", "tls-zone-per-hostname-tls-setting" });
    if (std.mem.eql(u8, name, "ca_slug")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "radar-get-certificate-authorities", "radar-certificate-authorities" });
    if (std.mem.eql(u8, name, "log_slug")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "radar-get-certificate-logs", "radar-certificate-logs" });
    if (std.mem.eql(u8, name, "dimension") and containsIgnoreCase(route.tag, "Radar Certificate Transparency")) return "CA";
    if (std.mem.eql(u8, name, "view_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "dns-views-for-an-account-list-internal-dns-views", "dns-internal-views", "dns-internal-view" });
    if (std.mem.eql(u8, name, "acl_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "secondary-dns-(-acl)-list-ac-ls", "secondary-dns-acls", "secondary-dns-acl" });
    if (std.mem.eql(u8, name, "peer_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "secondary-dns-(-peer)-list-peers", "secondary-dns-peers", "secondary-dns-peer" });
    if (std.mem.eql(u8, name, "tsig_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "secondary-dns-(-tsig)-list-tsi-gs", "secondary-dns-tsigs", "secondary-dns-tsig" });
    if (std.mem.eql(u8, name, "gateway_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "aig-config-list-gateway", "ai-gateway-gateways" });
    if (std.mem.eql(u8, name, "dataset_id")) return actualCaptureCloudflareDatasetIdHint(route, hints);
    if (std.mem.eql(u8, name, "job_id")) return actualCaptureCloudflareLogpushJobIdHint(route, hints);
    if (std.mem.eql(u8, name, "script_name")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "worker-script-list-workers", "workers-scripts", "worker-scripts" });
    if (std.mem.eql(u8, name, "script_tag")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "worker-script-list-workers", "workers-scripts", "worker-scripts" });
    if (std.mem.eql(u8, name, "profile_id") and actualCaptureRoutePathContains(route, "/magic/bgp/filter_profiles/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"magic-bgp-list-filter-profiles"});
    if (std.mem.eql(u8, name, "connector_id") and (actualCaptureRoutePathContains(route, "/cfd_tunnel/") or actualCaptureRoutePathContains(route, "/warp_connector/"))) return actualCaptureCloudflareTunnelConnectorIdHint(route, hints);
    if (std.mem.eql(u8, name, "connector_id") and actualCaptureRoutePathContains(route, "/magic/connectors/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "mconn-connector-list", "magic-connectors" });
    if (std.mem.eql(u8, name, "asn_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "botnet-threat-feed-list-asn", "botnet-threat-feed-asn" });
    if (std.mem.eql(u8, name, "dns_firewall_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "dns-firewall-list-dns-firewall-clusters", "dns-firewall-clusters", "dns-firewall-cluster" });
    if (std.mem.eql(u8, name, "investigate_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_investigate", "email-security-messages", "email-security-message" });
    if (std.mem.eql(u8, name, "policy_id") and actualCaptureRoutePathContains(route, "/email-security/settings/allow_policies/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_allow_policies", "email-security-allow-policies", "email-security-allow-policy" });
    if (std.mem.eql(u8, name, "pattern_id") and actualCaptureRoutePathContains(route, "/email-security/settings/block_senders/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_blocked_senders", "email-security-blocked-senders", "email-security-blocked-sender" });
    if (std.mem.eql(u8, name, "domain_id") and actualCaptureRoutePathContains(route, "/email-security/settings/domains/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_domains", "email-security-domains", "email-security-domain" });
    if (std.mem.eql(u8, name, "impersonation_registry_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_impersonation_registry", "email-security-impersonation-registry" });
    if (std.mem.eql(u8, name, "sending_domain_restriction_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_sending_domain_restrictions", "email-security-sending-domain-restrictions" });
    if (std.mem.eql(u8, name, "trusted_domain_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_trusted_domains", "email-security-trusted-domains" });
    if (std.mem.eql(u8, name, "pattern_id") and actualCaptureRoutePathContains(route, "/email-security/settings/url_ignore_patterns/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "email_security_list_url_ignore_patterns", "email-security-url-ignore-patterns" });
    if (std.mem.eql(u8, name, "rule_id") and actualCaptureRoutePathContains(route, "/firewall/access_rules/rules/")) return actualCaptureCloudflareIpAccessRuleIdHint(route, hints);
    if (std.mem.eql(u8, name, "detection_id") and actualCaptureRoutePathContains(route, "/leaked-credential-checks/detections/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "waf-product-api-leaked-credentials-list-detections", "leaked-credential-detections", "leaked-credential-detection" });
    if (std.mem.eql(u8, name, "connection_id") and actualCaptureRoutePathContains(route, "/page_shield/connections/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "page-shield-list-connections", "page-shield-connections", "page-shield-connection" });
    if (std.mem.eql(u8, name, "cookie_id") and actualCaptureRoutePathContains(route, "/page_shield/cookies/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "page-shield-list-cookies", "page-shield-cookies", "page-shield-cookie" });
    if (std.mem.eql(u8, name, "policy_id") and actualCaptureRoutePathContains(route, "/page_shield/policies/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "page-shield-list-policies", "page-shield-policies", "page-shield-policy" });
    if (std.mem.eql(u8, name, "script_id") and actualCaptureRoutePathContains(route, "/page_shield/scripts/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "page-shield-list-scripts", "page-shield-scripts", "page-shield-script" });
    if (std.mem.eql(u8, name, "bot_slug")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "radar-get-bots", "radar-bots", "radar-bot" });
    if (std.mem.eql(u8, name, "issue_id") and actualCaptureRoutePathContains(route, "/security-center/insights/")) return actualCaptureCloudflareSecurityCenterIssueIdHint(route, hints);
    if (std.mem.eql(u8, name, "tag_uuid") and actualCaptureRoutePathContains(route, "/cloudforce-one/events/tags/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"get_TagList"});
    if (std.mem.eql(u8, name, "user_id")) return actualCaptureCloudflareUserIdHint(route, hints);
    if (std.mem.eql(u8, name, "nonce") and actualCaptureRoutePathContains(route, "/active_sessions/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zero-trust-users-get-active-sessions", "zero-trust-user-active-sessions", "zero-trust-user-active-session" });
    if (std.mem.eql(u8, name, "group_id") and actualCaptureRoutePathContains(route, "/access/groups/")) return actualCaptureCloudflareAccessGroupIdHint(route, hints);
    if (std.mem.eql(u8, name, "policy_id") and actualCaptureRoutePathContains(route, "/access/")) return actualCaptureCloudflareAccessPolicyIdHint(route, hints);
    if (std.mem.eql(u8, name, "tag_name") and actualCaptureRoutePathContains(route, "/access/tags/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-tags-list-tags", "access-account-tags", "access-account-tag" });
    if (std.mem.eql(u8, name, "target_id") and actualCaptureRoutePathContains(route, "/infrastructure/targets/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "infra-targets-list", "access-infra-targets", "access-infra-target" });
    if (std.mem.eql(u8, name, "ua_rule_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user-agent-blocking-rules-list-user-agent-blocking-rules", "zone-user-agent-blocking-rules", "zone-user-agent-blocking-rule" });
    if (std.mem.eql(u8, name, "invite_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user'-s-invites-list-invitations", "user-invites", "user-invite" });
    if (std.mem.eql(u8, name, "membership_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user'-s-account-memberships-list-memberships", "memberships", "membership" });
    if (std.mem.eql(u8, name, "lock_downs_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-lockdown-list-zone-lockdown-rules", "zone-lockdown-rules", "zone-lockdown-rule" });
    if (std.mem.eql(u8, name, "snippet_name")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listZoneSnippets", "zone-snippets", "zone-snippet" });
    if (std.mem.eql(u8, name, "config_id") and actualCaptureRoutePathContains(route, "/token_validation/config/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "token-validation-config-list", "token-validation-configs", "token-validation-config" });
    if (std.mem.eql(u8, name, "rule_id") and actualCaptureRoutePathContains(route, "/token_validation/rules/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "token-validation-rules-list", "token-validation-rules", "token-validation-rule" });
    if (std.mem.eql(u8, name, "bucket_name") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "list-catalogs", "get-catalog-details", "r2-catalog" });
    if (std.mem.eql(u8, name, "namespace") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"list-namespaces"});
    if (std.mem.eql(u8, name, "table_name") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"list-tables"});
    if (std.mem.eql(u8, name, "id")) return actualCaptureCloudflareGenericIdHint(route, hints);
    if (std.mem.eql(u8, name, "plan_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-available-plans", "zone-available-rate-plans" });
    if (std.mem.eql(u8, name, "rule_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-rules", "email-routing-rules" });
    if (std.mem.eql(u8, name, "destination_address_identifier")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-email-routing-destination-addresses", "email-routing-destination-addresses" });
    if (std.mem.eql(u8, name, "name") and containsIgnoreCase(route.tag, "API Shield Labels")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{"zone-api-shield-labels"});
    if (std.mem.eql(u8, name, "monitor_group_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-load-balancer-monitor-groups-list-monitor-groups", "account-load-balancer-monitor-groups", "account-load-balancer-monitor-group" });
    if (std.mem.eql(u8, name, "monitor_id")) return actualCaptureCloudflareLoadBalancerMonitorIdHint(route, hints);
    if (std.mem.eql(u8, name, "pool_id")) return actualCaptureCloudflareLoadBalancerPoolIdHint(route, hints);
    if (std.mem.eql(u8, name, "load_balancer_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "load-balancers-list-load-balancers", "zone-load-balancers", "zone-load-balancer" });
    if (std.mem.eql(u8, name, "tunnel_id")) return actualCaptureCloudflareTunnelIdHint(route, hints);
    if (std.mem.eql(u8, name, "gre_tunnel_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "magic-gre-tunnels-list-gre-tunnels", "magic-gre-tunnels", "magic-gre-tunnel" });
    if (std.mem.eql(u8, name, "ipsec_tunnel_id")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "magic-ipsec-tunnels-list-ipsec-tunnels", "magic-ipsec-tunnels", "magic-ipsec-tunnel" });
    if (std.mem.eql(u8, name, "route_id") or std.mem.eql(u8, name, "ip")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "tunnel-route-list-tunnel-routes", "tunnel-routes", "tunnel-route" });
    return actualCapturePathParamEnumHint(route, name);
}

fn actualCaptureCloudflareAccountIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneAccountId(hints)) |account_id| return account_id;
    for (hints.cloudflare_accounts) |row| {
        if (row.id.len != 0) return row.id;
    }
    for (hints.cloudflare_zones) |row| {
        if (row.account_id.len != 0) return row.account_id;
    }
    return null;
}

fn actualCaptureCloudflareZoneIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureSelectedCloudflareZoneId(hints)) |zone_id| return zone_id;
    for (hints.cloudflare_zones) |row| {
        if (row.id.len != 0) return row.id;
    }
    return null;
}

fn actualCaptureCloudflareOrganizationIdHint(hints: Hints) ?[]const u8 {
    const kinds = &.{ "Accounts_listAccountOrganizations", "account-organizations", "organizations" };
    for (hints.cloudflare_resources) |row| {
        if (row.resource_id.len != 0 and actualCaptureKindIn(row.kind, kinds)) return row.resource_id;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len != 0 and actualCaptureKindIn(row.kind, kinds)) return row.resource_id;
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneId(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareZoneAccountId(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        for (hints.cloudflare_zones) |row| {
            if (row.account_id.len != 0 and eqlIgnoreCase(row.name, domain)) return row.account_id;
        }
    }
    return null;
}

fn actualCaptureSelectedCloudflareDomain(hints: Hints) ?[]const u8 {
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.cloudflare_zones) |row| {
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
    }
    return null;
}

fn actualCaptureCloudflareRulesetIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareRulesetPhaseHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset" })) |value| return value;
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        if (actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "zone-rulesets", "zone-ruleset" })) |value| return value;
    }
    return actualCaptureCloudflareResourceTypeHint(route, hints, &.{ "account-rulesets", "account-ruleset", "zone-rulesets", "zone-ruleset" });
}

fn actualCaptureCloudflareRulesetVersionHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/entrypoint/versions/")) {
        if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listAccountEntrypointRulesetVersions", "account-entrypoint-ruleset-versions", "account-entrypoint-ruleset-version" });
        if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listZoneEntrypointRulesetVersions", "zone-entrypoint-ruleset-versions", "zone-entrypoint-ruleset-version" });
    }
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listAccountRulesetVersions", "account-ruleset-versions", "account-ruleset-version" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listZoneRulesetVersions", "zone-ruleset-versions", "zone-ruleset-version" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "listAccountEntrypointRulesetVersions", "listZoneEntrypointRulesetVersions", "listAccountRulesetVersions", "listZoneRulesetVersions" });
}

fn actualCaptureCloudflareRuleTagHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "getAccountRulesetVersion", "account-ruleset-version-rules", "account-ruleset-version-rule" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "getZoneRulesetVersion", "zone-ruleset-version-rules", "zone-ruleset-version-rule" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "getAccountRulesetVersion", "getZoneRulesetVersion", "ruleset-version-rules" });
}

fn actualCaptureCloudflareCustomPageIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-custom-pages", "account-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-custom-pages", "zone-custom-page" });
    }
    return null;
}

fn actualCaptureCloudflareCustomAssetIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-assets-for-an-account-list-custom-assets", "account-custom-assets", "account-custom-asset" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-assets-for-a-zone-list-custom-assets", "zone-custom-assets", "zone-custom-asset" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-assets-for-an-account-list-custom-assets", "custom-assets-for-a-zone-list-custom-assets", "custom-assets" });
}

fn actualCaptureCloudflareAccessCustomPageIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access custom pages")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-custom-pages-list-custom-pages", "access-account-custom-pages", "access-account-custom-page", "access-custom-pages", "access-custom-page" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-zone-custom-pages", "access-zone-custom-page", "access-custom-pages", "access-custom-page" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-custom-pages-list-custom-pages", "access-account-custom-pages", "access-zone-custom-pages", "access-custom-pages", "access-custom-page" });
}

fn actualCaptureCloudflareCustomCsrIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-csrs-for-an-account-list-custom-csrs", "account-custom-csrs", "account-custom-csr" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-csrs-for-a-zone-list-custom-csrs", "zone-custom-csrs", "zone-custom-csr" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "custom-csrs-for-an-account-list-custom-csrs", "custom-csrs-for-a-zone-list-custom-csrs", "custom-csrs" });
}

fn actualCaptureCloudflareAccessApplicationIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-applications-list-access-applications", "access-zone-applications", "access-zone-application", "access-applications" });
    }
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-applications-list-access-applications", "access-account-applications", "access-account-application", "access-applications" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-applications-list-access-applications", "zone-level-access-applications-list-access-applications", "access-applications" });
}

fn actualCaptureCloudflareAccessGroupIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-groups-list-access-groups", "access-zone-groups", "access-zone-group", "access-groups" });
    }
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-groups-list-access-groups", "access-account-groups", "access-account-group", "access-groups" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-groups-list-access-groups", "zone-level-access-groups-list-access-groups", "access-groups" });
}

fn actualCaptureCloudflareAccessPolicyIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/access/apps/")) {
        if (actualCaptureCloudflareRouteZoneScoped(route)) {
            return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-policies-list-access-policies", "access-zone-application-policies", "access-zone-application-policy", "access-policies" });
        }
        if (actualCaptureCloudflareRouteAccountScoped(route)) {
            return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-policies-list-access-app-policies", "access-account-application-policies", "access-account-application-policy", "access-policies" });
        }
    }
    if (actualCaptureRoutePathContains(route, "/access/policies/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-policies-list-access-reusable-policies", "access-account-reusable-policies", "access-account-reusable-policy", "access-reusable-policies" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-policies-list-access-app-policies", "zone-level-access-policies-list-access-policies", "access-policies-list-access-reusable-policies", "access-policies" });
}

fn actualCaptureCloudflareAccessIdentityProviderIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (!containsIgnoreCase(route.tag, "Access identity providers") and !containsIgnoreCase(route.tag, "Access SCIM update")) return null;
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-identity-providers-list-access-identity-providers", "access-account-identity-providers", "access-account-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-identity-providers-list-access-identity-providers", "access-zone-identity-providers", "access-zone-identity-provider", "access-identity-providers", "access-identity-provider" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-identity-providers-list-access-identity-providers", "zone-level-access-identity-providers-list-access-identity-providers", "access-account-identity-providers", "access-zone-identity-providers", "access-identity-providers", "access-identity-provider" });
}

fn actualCaptureCloudflareTokenIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens" });
    }
    if (actualCaptureRoutePathContains(route, "/user/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "user-tokens", "user-api-tokens" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-tokens", "account-api-tokens", "account-owned-api-tokens", "user-tokens", "user-api-tokens" });
}

fn actualCaptureCloudflareAccessServiceTokenIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-service-tokens-list-service-tokens", "access-zone-service-tokens", "access-zone-service-token", "access-service-tokens" });
    }
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-service-tokens-list-service-tokens", "access-account-service-tokens", "access-account-service-token", "access-service-tokens" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-service-tokens-list-service-tokens", "zone-level-access-service-tokens-list-service-tokens", "access-service-tokens" });
}

fn actualCaptureCloudflareUserIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/scim/v2/Users/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "scim-users-list", "scim-users", "scim-user" });
    }
    if (actualCaptureRoutePathContains(route, "/access/users/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zero-trust-users-get-users", "zero-trust-users", "zero-trust-user" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "scim-users-list", "zero-trust-users-get-users", "users" });
}

fn actualCaptureCloudflareCertificateIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/origin_ca/certificates/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "origin-ca-list-certificates", "tls-origin-ca-certificates", "tls-origin-ca-certificate" });
    if (actualCaptureRoutePathContains(route, "/access/certificates/")) {
        if (actualCaptureCloudflareRouteAccountScoped(route)) {
            return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-mtls-authentication-list-mtls-certificates", "access-account-mtls-certificates", "access-account-mtls-certificate" });
        }
        if (actualCaptureCloudflareRouteZoneScoped(route)) {
            return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-mtls-authentication-list-mtls-certificates", "access-zone-mtls-certificates", "access-zone-mtls-certificate" });
        }
    }
    if (actualCaptureRoutePathContains(route, "/gateway/certificates/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zero-trust-certificates-list-zero-trust-certificates", "zero-trust-gateway-certificates", "zero-trust-gateway-certificate" });
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/hostnames/certificates/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "per-hostname-authenticated-origin-pull-list-certificates", "tls-zone-hostname-aop-certificates", "tls-zone-hostname-aop-certificate" });
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-authenticated-origin-pulls-list-certificates", "tls-zone-aop-certificates", "tls-zone-aop-certificate" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{
        "access-mtls-authentication-list-mtls-certificates",
        "zone-level-access-mtls-authentication-list-mtls-certificates",
        "zero-trust-certificates-list-zero-trust-certificates",
        "origin-ca-list-certificates",
        "per-hostname-authenticated-origin-pull-list-certificates",
        "zone-level-authenticated-origin-pulls-list-certificates",
    });
}

fn actualCaptureCloudflareAccessCaAppIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-short-lived-certificate-c-as-list-short-lived-certificate-c-as", "access-account-cas", "access-account-ca" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zone-level-access-short-lived-certificate-c-as-list-short-lived-certificate-c-as", "access-zone-cas", "access-zone-ca" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "access-short-lived-certificate-c-as-list-short-lived-certificate-c-as", "zone-level-access-short-lived-certificate-c-as-list-short-lived-certificate-c-as", "access-account-cas", "access-zone-cas" });
}

fn actualCaptureCloudflareDatasetIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "accounts-logs-explorer-datasets-list", "accounts-logs-explorer-datasets-available-list", "log-explorer-account-datasets", "log-explorer-account-available-datasets" });
    }
    if (actualCaptureCloudflareRouteZoneScoped(route)) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "zones-logs-explorer-datasets-list", "zones-logs-explorer-datasets-available-list", "log-explorer-zone-datasets", "log-explorer-zone-available-datasets" });
    }
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "accounts-logs-explorer-datasets-list", "zones-logs-explorer-datasets-list", "log-explorer-account-datasets", "log-explorer-zone-datasets" });
}

fn actualCaptureCloudflareLogpushJobIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-accounts-account_id-logpush-jobs", "logpush-account-jobs", "logpush-jobs" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-zones-zone_id-logpush-jobs", "logpush-zone-jobs", "logpush-jobs" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-accounts-account_id-logpush-jobs", "get-zones-zone_id-logpush-jobs", "logpush-account-jobs", "logpush-zone-jobs", "logpush-jobs" });
}

fn actualCaptureCloudflareLoadBalancerMonitorIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-load-balancer-monitors-list-monitors", "account-load-balancer-monitors", "account-load-balancer-monitor" });
    if (actualCaptureRoutePathContains(route, "/user/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "load-balancer-monitors-list-monitors", "user-load-balancer-monitors", "load-balancer-monitors", "load-balancer-monitor" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-load-balancer-monitors-list-monitors", "load-balancer-monitors-list-monitors", "account-load-balancer-monitors", "user-load-balancer-monitors", "load-balancer-monitors" });
}

fn actualCaptureCloudflareLoadBalancerPoolIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-load-balancer-pools-list-pools", "account-load-balancer-pools", "account-load-balancer-pool" });
    if (actualCaptureRoutePathContains(route, "/user/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "load-balancer-pools-list-pools", "user-load-balancer-pools", "load-balancer-pools", "load-balancer-pool" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "account-load-balancer-pools-list-pools", "load-balancer-pools-list-pools", "account-load-balancer-pools", "user-load-balancer-pools", "load-balancer-pools" });
}

fn actualCaptureCloudflareTunnelIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/warp_connector/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-warp-connector-tunnels", "warp-connector-tunnels", "warp-connector-tunnel" });
    if (actualCaptureRoutePathContains(route, "/cfd_tunnel/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-cloudflare-tunnels", "cloudflare-tunnel-list-all-tunnels", "cloudflare-tunnels", "cloudflare-tunnel" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-cloudflare-tunnels", "cloudflare-tunnel-list-all-tunnels", "cloudflare-tunnel-list-warp-connector-tunnels", "cloudflare-tunnels", "warp-connector-tunnels" });
}

fn actualCaptureCloudflareTunnelConnectorIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/warp_connector/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-warp-connector-tunnel-connections", "tunnel-warp-connections", "warp-connector-connections", "warp-connector-connection" });
    if (actualCaptureRoutePathContains(route, "/cfd_tunnel/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-cloudflare-tunnel-connections", "tunnel-cfd-connections", "cloudflare-tunnel-connections", "cloudflare-tunnel-connection" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "cloudflare-tunnel-list-cloudflare-tunnel-connections", "cloudflare-tunnel-list-warp-connector-tunnel-connections", "tunnel-cfd-connections", "tunnel-warp-connections" });
}

fn actualCaptureCloudflareIpAccessRuleIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/user/firewall/access_rules/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "ip-access-rules-for-a-user-list-ip-access-rules", "user-ip-access-rules", "ip-access-rules" });
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "ip-access-rules-for-an-account-list-ip-access-rules", "account-ip-access-rules", "ip-access-rules" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "ip-access-rules-for-a-zone-list-ip-access-rules", "zone-ip-access-rules", "ip-access-rules" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "ip-access-rules-for-a-user-list-ip-access-rules", "ip-access-rules-for-an-account-list-ip-access-rules", "ip-access-rules-for-a-zone-list-ip-access-rules", "ip-access-rules" });
}

fn actualCaptureCloudflareSecurityCenterIssueIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-zone-security-center-insights", "zone-security-center-insights", "security-center-insights" });
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-security-center-insights", "account-security-center-insights", "security-center-insights" });
    return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "get-security-center-insights", "get-zone-security-center-insights", "security-center-insights" });
}

fn actualCaptureCloudflareCloudforceEventHint(route: provider_routes.Route, hints: Hints) ?db_store.CloudflareInventoryHintRow {
    if (!std.mem.eql(u8, route.operation_id orelse "", "get_EventGraph")) return null;
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len == 0 or row.category.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, &.{"get_EventListGet"})) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row;
    }
    return null;
}

fn actualCaptureCloudflareGenericIdHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    if (actualCaptureRoutePathContains(route, "/ai-gateway/gateways/") and actualCaptureRoutePathContains(route, "/logs/")) {
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "aig-config-list-gateway-logs", "ai-gateway-logs" });
    }
    if (actualCaptureRoutePathContains(route, "/logs/audit/") and actualCaptureRoutePathContains(route, "/history")) {
        if (actualCaptureCloudflareAuditEventHint(route, hints)) |row| return row.resource_id;
        if (actualCaptureRoutePathContains(route, "/organizations/")) return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "audit-logs-v2-get-organization-audit-logs", "audit-logs-organization-v2" });
        return actualCaptureCloudflareResourceIdHint(route, hints, &.{ "audit-logs-v2-get-account-audit-logs", "audit-logs-account-v2" });
    }
    return null;
}

fn actualCaptureCloudflareAuditEventHint(route: provider_routes.Route, hints: Hints) ?db_store.CloudflareInventoryHintRow {
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len == 0 or row.updated_at.len == 0) continue;
        if (!actualCaptureCloudflareAuditListKindMatches(route, row.kind)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row;
    }
    return null;
}

fn actualCaptureCloudflareAuditListKindMatches(route: provider_routes.Route, kind: []const u8) bool {
    const operation_id = route.operation_id orelse "";
    const organization_history =
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-log-history") or
        actualCaptureRoutePathContains(route, "/organizations/");
    if (organization_history) {
        return actualCaptureKindIn(kind, &.{ "audit-logs-v2-get-organization-audit-logs", "audit-logs-organization-v2" });
    }
    return actualCaptureKindIn(kind, &.{ "audit-logs-v2-get-account-audit-logs", "audit-logs-account-v2" });
}

fn actualCaptureCloudflareResourceIdHint(route: provider_routes.Route, hints: Hints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_id;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    return null;
}

fn actualCaptureCloudflareResourceTypeHint(route: provider_routes.Route, hints: Hints, kinds: []const []const u8) ?[]const u8 {
    for (hints.cloudflare_resources) |row| {
        if (row.resource_type.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareResourceMatchesRouteScope(route, hints, row.scope, row.scope_id)) return row.resource_type;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.category.len == 0) continue;
        if (!actualCaptureKindIn(row.kind, kinds)) continue;
        if (actualCaptureCloudflareInventoryMatchesRouteScope(route, hints, row)) return row.category;
    }
    return null;
}

fn actualCaptureCloudflareResourceMatchesRouteScope(route: provider_routes.Route, hints: Hints, scope: []const u8, scope_id: []const u8) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    const organization_scoped = actualCaptureCloudflareRouteOrganizationScoped(route);
    if (!account_scoped and !zone_scoped and !organization_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(scope, "account") and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(scope, "zone") and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
            if (scope.len == 0 and actualCaptureScopeIdHasParent(scope_id, domain)) return true;
        }
    }

    if (organization_scoped) {
        if (actualCaptureCloudflareOrganizationIdHint(hints)) |organization_id| {
            if (eqlIgnoreCase(scope, "organization") and actualCaptureScopeIdHasParent(scope_id, organization_id)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareInventoryMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.CloudflareInventoryHintRow) bool {
    const account_scoped = actualCaptureCloudflareRouteAccountScoped(route);
    const zone_scoped = actualCaptureCloudflareRouteZoneScoped(route);
    const organization_scoped = actualCaptureCloudflareRouteOrganizationScoped(route);
    if (!account_scoped and !zone_scoped and !organization_scoped) return true;

    if (account_scoped) {
        if (actualCaptureCloudflareAccountIdHint(hints)) |account_id| {
            if (eqlIgnoreCase(row.account_id, account_id)) return true;
            if (eqlIgnoreCase(row.scope, "account") and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, account_id)) return true;
        }
    }

    if (zone_scoped) {
        if (actualCaptureCloudflareZoneIdHint(hints)) |zone_id| {
            if (eqlIgnoreCase(row.zone_id, zone_id)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, zone_id)) return true;
        }
        if (actualCaptureSelectedCloudflareDomain(hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.scope, "zone") and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
            if (row.scope.len == 0 and actualCaptureScopeIdHasParent(row.scope_id, domain)) return true;
        }
    }

    if (organization_scoped) {
        if (actualCaptureCloudflareOrganizationIdHint(hints)) |organization_id| {
            if (eqlIgnoreCase(row.scope, "organization") and actualCaptureScopeIdHasParent(row.scope_id, organization_id)) return true;
        }
    }

    return false;
}

fn actualCaptureCloudflareRouteAccountScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/accounts/");
}

fn actualCaptureCloudflareRouteZoneScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/zones/");
}

fn actualCaptureCloudflareRouteOrganizationScoped(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "/organizations/");
}

fn actualCaptureRoutePathContains(route: provider_routes.Route, needle: []const u8) bool {
    return std.mem.indexOf(u8, route.path_template, needle) != null;
}

fn actualCaptureScopeIdHasParent(scope_id: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(scope_id, parent)) return true;
    if (scope_id.len <= parent.len) return false;
    if (scope_id[parent.len] != '/') return false;
    return eqlIgnoreCase(scope_id[0..parent.len], parent);
}

fn actualCaptureKindIn(kind: []const u8, kinds: []const []const u8) bool {
    for (kinds) |candidate| {
        if (std.mem.eql(u8, kind, candidate)) return true;
    }
    return false;
}

fn actualCaptureHostingerPathParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) ?[]const u8 {
    if (std.mem.eql(u8, name, "virtualMachineId") and hints.hostinger_vps.len != 0) return hints.hostinger_vps[0].id;
    if (std.mem.eql(u8, name, "domain")) return actualCaptureHostingerDomainHint(route, hints);
    if (std.mem.eql(u8, name, "username")) return actualCaptureHostingerUsernameHint(route, hints);
    if (std.mem.eql(u8, name, "actionId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getActionDetailsV1", "VPS_getActionsV1");
    if (std.mem.eql(u8, name, "templateId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getTemplateDetailsV1", "VPS_getTemplatesV1");
    if (std.mem.eql(u8, name, "postInstallScriptId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getPostInstallScriptV1", "VPS_getPostInstallScriptsV1");
    if (std.mem.eql(u8, name, "firewallId")) return actualCaptureHostingerResourceHint(route, hints, "VPS_getFirewallDetailsV1", "VPS_getFirewallListV1");
    if (std.mem.eql(u8, name, "snapshotId")) return actualCaptureHostingerResourceHint(route, hints, "DNS_getDNSSnapshotV1", "DNS_getDNSSnapshotListV1");
    if (std.mem.eql(u8, name, "whoisId")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "domains_getWHOISProfileV1", "domains_getWHOISProfileUsageV1" }, "domains_getWHOISProfileListV1");
    if (std.mem.eql(u8, name, "websiteId")) return actualCaptureHostingerResourceHint(route, hints, "horizons_getWebsiteV1", "horizons_getWebsitesV1");
    if (std.mem.eql(u8, name, "name")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getPhpMyAdminLinkV1", "hosting_listAccountDatabasesV1");
    if (std.mem.eql(u8, name, "uuid")) return actualCaptureHostingerResourceHint(route, hints, "hosting_getNodeJSBuildLogsV1", "hosting_listNodeJSBuildsV1");
    if (std.mem.eql(u8, name, "projectName")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "VPS_getProjectContentsV1", "VPS_getProjectContainersV1", "VPS_getProjectLogsV1" }, "VPS_getProjectListV1");
    if (std.mem.eql(u8, name, "profileUuid")) return actualCaptureHostingerResourceHint(route, hints, "reach_listProfileSegmentContactsV1", "reach_listProfilesV1");
    if (std.mem.eql(u8, name, "segmentUuid")) return actualCaptureHostingerResourceHintForAny(route, hints, &.{ "reach_getSegmentDetailsV1", "reach_listSegmentContactsV1", "reach_listProfileSegmentContactsV1" }, "reach_listSegmentsV1");
    return actualCapturePathParamEnumHint(route, name);
}

fn actualCaptureHostingerResourceHint(route: provider_routes.Route, hints: Hints, detail_operation_id: []const u8, list_kind: []const u8) ?[]const u8 {
    if (route.operation_id == null or !std.mem.eql(u8, route.operation_id.?, detail_operation_id)) return null;
    return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
}

fn actualCaptureHostingerResourceHintForAny(route: provider_routes.Route, hints: Hints, detail_operation_ids: []const []const u8, list_kind: []const u8) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    for (detail_operation_ids) |detail_operation_id| {
        if (std.mem.eql(u8, operation_id, detail_operation_id)) return actualCaptureHostingerScopedResourceKindHint(route, hints, list_kind);
    }
    return null;
}

fn actualCaptureHostingerScopedResourceKindHint(route: provider_routes.Route, hints: Hints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerResourceMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
        if (actualCaptureHostingerInventoryMatchesRouteScope(route, hints, row)) return row.resource_id;
    }
    if (!actualCaptureHostingerUnscopedFallbackAllowed(route, hints, list_kind)) return null;
    return actualCaptureHostingerResourceKindHint(hints, list_kind);
}

fn actualCaptureHostingerResourceKindHint(hints: Hints, list_kind: []const u8) ?[]const u8 {
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, list_kind) and row.resource_id.len != 0) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerResourceMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.HostingerResourceHintRow) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        const vm_id = actualCaptureHostingerVpsIdHint(hints) orelse return false;
        return actualCaptureHostingerTargetHasParent(row.target, vm_id);
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerInventoryMatchesRouteScope(route: provider_routes.Route, hints: Hints, row: db_store.HostingerInventoryHintRow) bool {
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            if (eqlIgnoreCase(row.username, username)) return true;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            if (eqlIgnoreCase(row.domain, domain)) return true;
            if (eqlIgnoreCase(row.display_name, domain)) return true;
            if (eqlIgnoreCase(row.resource_id, domain)) return true;
        }
    }
    return true;
}

fn actualCaptureHostingerUnscopedFallbackAllowed(route: provider_routes.Route, hints: Hints, list_kind: []const u8) bool {
    if (actualCaptureHostingerRouteNeedsVps(route)) {
        if (actualCaptureHostingerVpsIdHint(hints)) |vm_id| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, vm_id)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsUsername(route)) {
        if (actualCaptureHostingerUsernameHint(route, hints)) |username| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) continue;
                saw_scoped_row = true;
                if (actualCaptureHostingerTargetHasParent(row.target, username)) return true;
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0 or row.username.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.username, username)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    if (actualCaptureHostingerRouteNeedsDomain(route)) {
        if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
            var saw_scoped_row = false;
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len != 0) {
                    saw_scoped_row = true;
                    if (eqlIgnoreCase(row.domain, domain)) return true;
                }
                if (!actualCaptureHostingerTargetLooksUnscoped(row.target, list_kind)) {
                    saw_scoped_row = true;
                    if (actualCaptureHostingerTargetHasParent(row.target, domain)) return true;
                }
            }
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, list_kind) or row.resource_id.len == 0) continue;
                if (row.domain.len == 0 and row.display_name.len == 0) continue;
                saw_scoped_row = true;
                if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.display_name, domain)) return true;
            }
            if (saw_scoped_row) return false;
        }
    }
    return true;
}

fn actualCaptureHostingerDomainHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    _ = route;
    for (hints.configured_domains) |domain| {
        if (actualCaptureLooksLikeDomain(domain)) return domain;
    }
    for (hints.hostinger_inventory) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.display_name)) return row.display_name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    for (hints.hostinger_resources) |row| {
        if (!actualCaptureHostingerKindCanCarryDomain(row.kind)) continue;
        if (actualCaptureLooksLikeDomain(row.domain)) return row.domain;
        if (actualCaptureLooksLikeDomain(row.name)) return row.name;
        if (actualCaptureLooksLikeDomain(row.resource_id)) return row.resource_id;
    }
    return null;
}

fn actualCaptureHostingerUsernameHint(route: provider_routes.Route, hints: Hints) ?[]const u8 {
    const operation_id = route.operation_id orelse return null;
    if (!containsIgnoreCase(operation_id, "hosting_")) return null;
    if (actualCaptureHostingerDomainHint(route, hints)) |domain| {
        for (hints.hostinger_inventory) |row| {
            if (row.username.len == 0) continue;
            if (eqlIgnoreCase(row.domain, domain) or eqlIgnoreCase(row.resource_id, domain) or eqlIgnoreCase(row.display_name, domain)) return row.username;
        }
    }
    for (hints.hostinger_inventory) |row| {
        if (row.username.len != 0) return row.username;
    }
    return null;
}

fn actualCaptureHostingerOrderIdHint(hints: Hints) ?[]const u8 {
    if (actualCaptureHostingerResourceKindHint(hints, "hosting_listOrdersV1")) |value| return value;
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, "hosting_listWebsitesV1") and row.related_id.len != 0) return row.related_id;
    }
    return null;
}

fn actualCaptureHostingerKindCanCarryDomain(kind: []const u8) bool {
    return std.mem.startsWith(u8, kind, "DNS_") or
        std.mem.startsWith(u8, kind, "domains_") or
        std.mem.startsWith(u8, kind, "hosting_") or
        std.mem.startsWith(u8, kind, "horizons_") or
        containsIgnoreCase(kind, "domain") or
        containsIgnoreCase(kind, "website") or
        containsIgnoreCase(kind, "wordpress");
}

fn actualCaptureHostingerVpsIdHint(hints: Hints) ?[]const u8 {
    if (hints.hostinger_vps.len != 0 and hints.hostinger_vps[0].id.len != 0) return hints.hostinger_vps[0].id;
    return actualCaptureHostingerResourceKindHint(hints, "VPS_getVirtualMachinesV1") orelse
        actualCaptureHostingerResourceKindHint(hints, "vps") orelse
        actualCaptureHostingerResourceKindHint(hints, "route-hostinger-vps");
}

fn actualCaptureHostingerRouteNeedsVps(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{virtualMachineId}");
}

fn actualCaptureHostingerRouteNeedsUsername(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{username}");
}

fn actualCaptureHostingerRouteNeedsDomain(route: provider_routes.Route) bool {
    return actualCaptureRoutePathContains(route, "{domain}");
}

fn actualCaptureHostingerTargetHasParent(target: []const u8, parent: []const u8) bool {
    if (parent.len == 0) return false;
    if (eqlIgnoreCase(target, parent)) return true;
    if (target.len <= parent.len) return false;
    if (target[parent.len] != '/') return false;
    return eqlIgnoreCase(target[0..parent.len], parent);
}

fn actualCaptureHostingerTargetLooksUnscoped(target: []const u8, list_kind: []const u8) bool {
    return target.len == 0 or eqlIgnoreCase(target, list_kind);
}

fn actualCaptureLooksLikeDomain(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.endsWith(u8, value, ".hstgr.cloud")) return false;
    if (value[0] == '.' or value[value.len - 1] == '.') return false;
    if (std.mem.indexOfScalar(u8, value, '.') == null) return false;
    for (value) |byte| {
        if (byte == '/' or byte == ':' or byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') return false;
    }
    return true;
}

pub fn actualCaptureHasQueryParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) bool {
    return switch (route.provider) {
        .cloudflare => actualCaptureHasCloudflareQueryParamHintWithHints(route, name, hints),
        .hostinger => actualCaptureHasHostingerQueryParamHint(route, name, hints),
    };
}

fn actualCaptureHasCloudflareQueryParamHintWithHints(route: provider_routes.Route, name: []const u8, hints: Hints) bool {
    const operation_id = route.operation_id orelse return false;
    if (std.mem.eql(u8, operation_id, "get_EventGraph")) {
        if (std.mem.eql(u8, name, "nodeId") or std.mem.eql(u8, name, "nodeType")) return actualCaptureCloudflareCloudforceEventHint(route, hints) != null;
    }
    if (std.mem.eql(u8, operation_id, "access-scim-update-logs-list-access-scim-update-logs") and std.mem.eql(u8, name, "idp_id")) {
        return actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints) != null;
    }
    if (actualCaptureQueryParamEnumHint(route, name) != null) return true;
    const audit_v2_window =
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-logs") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-logs") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-log-history") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-log-history");
    const audit_v2_history =
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-log-history") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-log-history");
    if (audit_v2_history and std.mem.eql(u8, name, "action_time")) return actualCaptureCloudflareAuditEventHint(route, hints) != null;
    return audit_v2_window and
        (std.mem.eql(u8, name, "before") or std.mem.eql(u8, name, "since"));
}

fn actualCaptureHasHostingerQueryParamHint(route: provider_routes.Route, name: []const u8, hints: Hints) bool {
    const operation_id = route.operation_id orelse return false;
    if (std.mem.eql(u8, operation_id, "VPS_getMetricsV1") and
        (std.mem.eql(u8, name, "date_from") or std.mem.eql(u8, name, "date_to")))
    {
        return true;
    }
    if (actualCaptureQueryParamEnumHint(route, name) != null) return true;
    return std.mem.eql(u8, operation_id, "hosting_listAvailableDatacentersV1") and
        std.mem.eql(u8, name, "order_id") and
        actualCaptureHostingerOrderIdHint(hints) != null;
}

pub fn actualCaptureQueryParamHint(gpa: Allocator, route: provider_routes.Route, name: []const u8, hints: Hints) !?[]u8 {
    if (!actualCaptureHasQueryParamHint(route, name, hints)) return null;
    if (route.provider == .cloudflare) return actualCaptureCloudflareQueryParamHint(gpa, route, name, hints);
    if (std.mem.eql(u8, route.operation_id.?, "hosting_listAvailableDatacentersV1") and std.mem.eql(u8, name, "order_id")) {
        if (actualCaptureHostingerOrderIdHint(hints)) |order_id| return try gpa.dupe(u8, order_id);
        return null;
    }
    if (actualCaptureQueryParamEnumHint(route, name)) |value| return try gpa.dupe(u8, value);
    if (!std.mem.eql(u8, route.operation_id.?, "VPS_getMetricsV1") or
        (!std.mem.eql(u8, name, "date_from") and !std.mem.eql(u8, name, "date_to")))
    {
        return null;
    }
    const now = core_time.currentEpochSeconds() catch return null;
    const day: u64 = 24 * 60 * 60;
    const timestamp = if (std.mem.eql(u8, name, "date_from") and now > day) now - day else now;
    var buf: [17]u8 = undefined;
    const formatted = try core_time.formatUtcMinute(&buf, timestamp);
    return try gpa.dupe(u8, formatted);
}

fn actualCaptureCloudflareQueryParamHint(gpa: Allocator, route: provider_routes.Route, name: []const u8, hints: Hints) !?[]u8 {
    const operation_id = route.operation_id orelse "";
    if (std.mem.eql(u8, operation_id, "get_EventGraph")) {
        if (actualCaptureCloudflareCloudforceEventHint(route, hints)) |row| {
            if (std.mem.eql(u8, name, "nodeId")) return try gpa.dupe(u8, row.resource_id);
            if (std.mem.eql(u8, name, "nodeType")) return try gpa.dupe(u8, row.category);
        }
        return null;
    }
    if (std.mem.eql(u8, operation_id, "access-scim-update-logs-list-access-scim-update-logs") and std.mem.eql(u8, name, "idp_id")) {
        if (actualCaptureCloudflareAccessIdentityProviderIdHint(route, hints)) |idp_id| return try gpa.dupe(u8, idp_id);
        return null;
    }
    if (std.mem.eql(u8, name, "action_time")) {
        if (actualCaptureCloudflareAuditEventHint(route, hints)) |row| return try gpa.dupe(u8, row.updated_at);
        return null;
    }
    if (actualCaptureQueryParamEnumHint(route, name)) |value| return try gpa.dupe(u8, value);
    const audit_v2_window =
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-logs") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-logs") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-log-history") or
        std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-log-history");
    if (!audit_v2_window or (!std.mem.eql(u8, name, "before") and !std.mem.eql(u8, name, "since"))) return null;
    const now = core_time.currentEpochSeconds() catch return null;
    const hour: u64 = 60 * 60;
    const timestamp = if (std.mem.eql(u8, name, "since") and now > hour) now - hour else now;
    var buf: [20]u8 = undefined;
    const formatted = try core_time.formatUtcSecond(&buf, timestamp);
    return try gpa.dupe(u8, formatted);
}

fn actualCapturePathParamEnumHint(route: provider_routes.Route, name: []const u8) ?[]const u8 {
    return actualCaptureParamEnumHint(route.path_params, name);
}

fn actualCaptureQueryParamEnumHint(route: provider_routes.Route, name: []const u8) ?[]const u8 {
    return actualCaptureParamEnumHint(route.query_params, name);
}

fn actualCaptureParamEnumHint(params: []const provider_routes.RouteParam, name: []const u8) ?[]const u8 {
    for (params) |param| {
        if (!param.required) continue;
        if (!std.mem.eql(u8, param.name, name)) continue;
        if (param.schema.enum_values.len != 0) return param.schema.enum_values[0];
    }
    return null;
}

pub fn actualCaptureSummarizeMissingInputSources(
    gpa: Allocator,
    summary: *SourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: Hints,
) !void {
    for (route.path_params) |param| {
        if (!param.required) continue;
        if (actualCapturePathParamHint(route, param.name, hints) != null) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "path", param.name);
    }
    for (route.query_params) |param| {
        if (!param.required) continue;
        if (actualCaptureHasQueryParamHint(route, param.name, hints)) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "query", param.name);
    }
    for (route.header_params) |param| {
        if (!param.required) continue;
        try actualCaptureSummarizeMissingInputSourceRows(gpa, summary, route, routes, captures, source_evidence, hints, "header", param.name);
    }
}

fn actualCaptureSummarizeMissingInputSourceRows(
    gpa: Allocator,
    summary: *SourceSummary,
    route: provider_routes.Route,
    routes: []const CoverageRoute,
    captures: []const db_store.RouteCaptureEvidenceRow,
    source_evidence: []const db_store.RouteSourceEvidenceRow,
    hints: Hints,
    input_source: []const u8,
    input_name: []const u8,
) !void {
    const sources = actualCaptureMissingInputSources(route, input_source, input_name);
    if (sources.len == 0) {
        actualCaptureAddSourceSummary(summary, actualCaptureUnmappedSourceResult(route, input_source, input_name), .{});
        return;
    }
    for (sources) |source| {
        const source_route = actualCaptureFindRouteByOperationId(routes, route.provider, source.operation_id);
        const source_state = if (source_route) |found| actualCaptureState(found, captures) else null;
        const hint_count = actualCaptureSourceHintCount(route, hints, input_source, input_name, source);
        const evidence = actualCaptureFindSourceEvidence(source_evidence, route.provider.name(), source.operation_id);
        const body = try actualCaptureSourceBodyEvidence(gpa, evidence);
        actualCaptureAddSourceSummary(summary, actualCaptureSourceResult(source_route, source_state, hints, hint_count, body), body);
    }
}

fn actualCaptureAddSourceSummary(summary: *SourceSummary, result: []const u8, body: SourceBodyEvidence) void {
    summary.total_sources += 1;
    if (std.mem.eql(u8, result, "captured_with_hints")) {
        summary.captured_with_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_empty")) {
        summary.captured_empty += 1;
    } else if (std.mem.eql(u8, result, "captured_without_hints")) {
        summary.captured_without_hints += 1;
    } else if (std.mem.eql(u8, result, "captured_unknown_body")) {
        summary.captured_unknown_body += 1;
    } else if (std.mem.eql(u8, result, "ready_to_capture")) {
        summary.ready_to_capture += 1;
    } else if (std.mem.eql(u8, result, "waiting_for_inputs")) {
        summary.waiting_for_inputs += 1;
    } else if (std.mem.eql(u8, result, "diagnostic_blocked")) {
        summary.diagnostic_blocked += 1;
    } else if (std.mem.eql(u8, result, "captured_error")) {
        summary.captured_error += 1;
    } else if (std.mem.eql(u8, result, "no_official_source")) {
        summary.no_official_source += 1;
    } else if (std.mem.eql(u8, result, "not_in_catalog")) {
        summary.not_in_catalog += 1;
    } else if (std.mem.eql(u8, result, "unmapped")) {
        summary.unmapped += 1;
    } else if (std.mem.eql(u8, result, "not_eligible")) {
        summary.not_eligible += 1;
    }

    if (std.mem.eql(u8, body.shape, "array")) {
        summary.body_array += 1;
    } else if (std.mem.eql(u8, body.shape, "data_array")) {
        summary.body_data_array += 1;
    } else if (std.mem.eql(u8, body.shape, "error_object")) {
        summary.body_error_object += 1;
    } else if (std.mem.eql(u8, body.shape, "no_evidence")) {
        summary.body_no_evidence += 1;
    } else {
        summary.body_other += 1;
    }
}

pub fn actualCaptureFindRouteByOperationId(routes: []const CoverageRoute, provider: provider_routes.Provider, operation_id: []const u8) ?provider_routes.Route {
    for (routes) |row| {
        if (row.route.provider != provider) continue;
        if (row.route.operation_id == null) continue;
        if (std.mem.eql(u8, row.route.operation_id.?, operation_id)) return row.route;
    }
    return null;
}

pub fn actualCaptureUnmappedSourceResult(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureCloudflareNoOfficialSource(route, input_source, input_name)) return "no_official_source";
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "no_official_source";
    return "unmapped";
}

pub fn actualCaptureUnmappedSourceNextAction(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureCloudflareNoOfficialSource(route, input_source, input_name)) return "provide the identifier or bounded read window explicitly";
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "provide the identifier through config or another collected official surface";
    return "add a source mapping before this input can be planned";
}

pub fn actualCaptureUnmappedSourcePurpose(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    if (actualCaptureCloudflareNoOfficialSource(route, input_source, input_name)) return actualCaptureCloudflareNoOfficialSourcePurpose(route, input_source, input_name);
    if (actualCaptureHostingerNoOfficialSource(route, input_source, input_name)) return "current Hostinger OpenAPI exposes only the Horizons website detail route, not a list route";
    return "no source mapping";
}

fn actualCaptureCloudflareNoOfficialSource(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) bool {
    if (route.provider != .cloudflare) return false;
    const operation_id = route.operation_id orelse return false;
    if (std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "ray_id") and
        std.mem.eql(u8, operation_id, "get-zones-zone_id-logs-rayids-ray_id")) return true;
    if (std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "preview_id") and
        (std.mem.eql(u8, operation_id, "account-load-balancer-monitors-preview-result") or
            std.mem.eql(u8, operation_id, "load-balancer-monitors-preview-result"))) return true;
    if (std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "policy_test_id") and
        (std.mem.eql(u8, operation_id, "access-policy-tests-get-an-update") or
            std.mem.eql(u8, operation_id, "access-policy-tests-get-a-user-page"))) return true;
    return std.mem.eql(u8, input_source, "query") and
        std.mem.eql(u8, input_name, "end") and
        std.mem.eql(u8, operation_id, "get-zones-zone_id-logs-received");
}

fn actualCaptureCloudflareNoOfficialSourcePurpose(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const u8 {
    _ = route;
    if (std.mem.eql(u8, input_source, "path") and std.mem.eql(u8, input_name, "ray_id")) return "Ray IDs come from traffic/log evidence, not a stable Cloudflare inventory list";
    if (std.mem.eql(u8, input_source, "path") and std.mem.eql(u8, input_name, "preview_id")) return "load-balancer preview IDs are produced by preview requests, not stable read inventory";
    if (std.mem.eql(u8, input_source, "path") and std.mem.eql(u8, input_name, "policy_test_id")) return "Access policy-test IDs are produced by starting a policy test, which remains dry-run only";
    if (std.mem.eql(u8, input_source, "query") and std.mem.eql(u8, input_name, "end")) return "Logs Received should be captured only with an explicit bounded window and safe optional filters";
    return "Cloudflare requires an explicit value for this read";
}

fn actualCaptureHostingerNoOfficialSource(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) bool {
    if (route.provider != .hostinger) return false;
    const operation_id = route.operation_id orelse return false;
    return std.mem.eql(u8, input_source, "path") and
        std.mem.eql(u8, input_name, "websiteId") and
        std.mem.eql(u8, operation_id, "horizons_getWebsiteV1");
}

pub fn actualCaptureFindSourceEvidence(source_evidence: []const db_store.RouteSourceEvidenceRow, provider: []const u8, operation_id: []const u8) ?db_store.RouteSourceEvidenceRow {
    for (source_evidence) |row| {
        if (!std.mem.eql(u8, row.provider, provider)) continue;
        if (!std.mem.eql(u8, row.operation_id, operation_id)) continue;
        return row;
    }
    return null;
}

pub fn actualCaptureSourceBodyEvidence(gpa: Allocator, evidence: ?db_store.RouteSourceEvidenceRow) !SourceBodyEvidence {
    const row = evidence orelse return .{};
    if (row.raw_json.len == 0) return .{ .shape = "no_body" };
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, row.raw_json, .{}) catch return .{
        .shape = "invalid_json",
        .body_bytes = row.raw_json.len,
    };
    defer parsed.deinit();
    return actualCaptureSourceBodyEvidenceFromValue(parsed.value, row.raw_json.len);
}

pub fn actualCaptureSourceBodyEvidenceFromValue(value: std.json.Value, body_bytes: usize) SourceBodyEvidence {
    return switch (value) {
        .array => |array| .{ .shape = "array", .item_count = array.items.len, .body_bytes = body_bytes },
        .object => |object| blk: {
            if (object.get("data")) |data| {
                break :blk switch (data) {
                    .array => |array| .{ .shape = "data_array", .item_count = array.items.len, .body_bytes = body_bytes },
                    .object => .{ .shape = "data_object", .item_count = 1, .body_bytes = body_bytes },
                    else => .{ .shape = "data_scalar", .body_bytes = body_bytes },
                };
            }
            if (object.get("message") != null or object.get("error") != null) {
                break :blk .{ .shape = "error_object", .body_bytes = body_bytes };
            }
            break :blk .{ .shape = "object", .item_count = 1, .body_bytes = body_bytes };
        },
        else => .{ .shape = "scalar", .body_bytes = body_bytes },
    };
}

fn actualCaptureSourceBodyIsEmptyCollection(body: SourceBodyEvidence) bool {
    if (body.item_count == null or body.item_count.? != 0) return false;
    return std.mem.eql(u8, body.shape, "array") or std.mem.eql(u8, body.shape, "data_array");
}

fn actualCaptureSourceBodyHasItems(body: SourceBodyEvidence) bool {
    if (body.item_count) |count| return count > 0;
    return false;
}

pub fn actualCaptureSourceResult(route: ?provider_routes.Route, state: ?CaptureState, hints: Hints, hint_count: usize, body: SourceBodyEvidence) []const u8 {
    const source_route = route orelse return "not_in_catalog";
    const source_state = state orelse return "not_eligible";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "captured_with_hints"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "captured_empty"
        else if (actualCaptureSourceBodyHasItems(body))
            "captured_without_hints"
        else
            "captured_unknown_body",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true)) "ready_to_capture" else "waiting_for_inputs",
        .non_ok => if (!provider_capabilities.routeLiveReadSupported(source_route) and provider_capabilities.routeDiagnosticReadSupported(source_route)) "diagnostic_blocked" else "captured_error",
    };
}

pub fn actualCaptureSourceNextAction(route: ?provider_routes.Route, state: ?CaptureState, hints: Hints, hint_count: usize, body: SourceBodyEvidence) []const u8 {
    const source_route = route orelse return "update the route catalog or remove the stale hint mapping";
    const source_state = state orelse return "source route is not an eligible read route";
    return switch (source_state) {
        .ok => if (hint_count != 0)
            "use collected identifiers for child captures"
        else if (actualCaptureSourceBodyIsEmptyCollection(body))
            "source collection is empty; no child identifiers are available"
        else if (actualCaptureSourceBodyHasItems(body))
            "extend normalization for this non-empty source response"
        else
            "inspect raw source evidence; body shape does not prove an empty collection",
        .missing => if (actualCaptureReadyWithPolicy(source_route, hints, true))
            "capture the source route to discover identifiers"
        else
            "capture the source route prerequisites first",
        .non_ok => if (!provider_capabilities.routeLiveReadSupported(source_route) and provider_capabilities.routeDiagnosticReadSupported(source_route))
            "diagnostic-only source is blocked; child identifiers are unavailable"
        else
            "inspect source capture error before child captures",
    };
}

pub fn actualCaptureSourceHintCount(
    route: provider_routes.Route,
    hints: Hints,
    input_source: []const u8,
    input_name: []const u8,
    source: InputSource,
) usize {
    if (route.provider == .cloudflare) return actualCaptureCloudflareSourceHintCount(route, hints, input_source, input_name, source);
    if (route.provider != .hostinger) return 0;
    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) {
            var count = hints.configured_domains.len;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.display_name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            for (hints.hostinger_resources) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (actualCaptureLooksLikeDomain(row.domain) or actualCaptureLooksLikeDomain(row.name) or actualCaptureLooksLikeDomain(row.resource_id)) count += 1;
            }
            return count;
        }
        if (std.mem.eql(u8, input_name, "virtualMachineId")) {
            var count = hints.hostinger_vps.len;
            count += actualCaptureHostingerKindHintCount(hints, source.hint_kind);
            return count;
        }
        if (std.mem.eql(u8, input_name, "username")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.username.len != 0) count += 1;
            }
            return count;
        }
    }

    if (std.mem.eql(u8, input_source, "query") and std.mem.eql(u8, input_name, "order_id")) {
        if (std.mem.eql(u8, source.hint_kind, "hosting_listWebsitesV1")) {
            var count: usize = 0;
            for (hints.hostinger_inventory) |row| {
                if (!std.mem.eql(u8, row.kind, source.hint_kind)) continue;
                if (row.related_id.len != 0) count += 1;
            }
            return count;
        }
    }

    return actualCaptureHostingerKindHintCount(hints, source.hint_kind);
}

fn actualCaptureCloudflareSourceHintCount(route: provider_routes.Route, hints: Hints, input_source: []const u8, input_name: []const u8, source: InputSource) usize {
    _ = input_source;
    if (std.mem.eql(u8, input_name, "account_id") or std.mem.eql(u8, input_name, "account_identifier")) return hints.cloudflare_accounts.len;
    if (std.mem.eql(u8, input_name, "zone_id") or std.mem.eql(u8, input_name, "zone_identifier")) return hints.cloudflare_zones.len;
    if (std.mem.eql(u8, input_name, "organization_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "account-organizations", "organizations" });
    if (std.mem.eql(u8, input_name, "client_certificate_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "zone-api-shield-client-certificates", "zone-client-certificates", "api-shield-client-certificates", "api-shield-client-certificates-for-a-zone" });
    if (std.mem.eql(u8, input_name, "certificate_pack_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "tls-zone-certificate-packs", "tls-zone-certificate-pack" });
    if (std.mem.eql(u8, input_name, "custom_certificate_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "tls-zone-custom-ssl", "tls-zone-custom-ssl-certificate" });
    if (std.mem.eql(u8, input_name, "keyless_certificate_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "tls-zone-keyless-ssl", "tls-zone-keyless-ssl-certificate" });
    if (std.mem.eql(u8, input_name, "saml_cert_set_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "access-account-saml-certificates" });
    if (std.mem.eql(u8, input_name, "certificate_id")) return actualCaptureCloudflareCertificateSourceHintCount(route, hints, source.hint_kind);
    if (std.mem.eql(u8, input_name, "app_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "access-account-cas", "access-zone-cas", "access-account-ca", "access-zone-ca" });
    if (std.mem.eql(u8, input_name, "mtls_certificate_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "access-account-mtls-certificates", "zero-trust-certificates-list-zero-trust-certificates" });
    if (std.mem.eql(u8, input_name, "setting_id") or std.mem.eql(u8, input_name, "hostname")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "tls-zone-per-hostname-tls-settings", "tls-zone-per-hostname-tls-setting" });
    if (std.mem.eql(u8, input_name, "ca_slug")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "radar-certificate-authorities" });
    if (std.mem.eql(u8, input_name, "log_slug")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "radar-certificate-logs" });
    if (std.mem.eql(u8, input_name, "gateway_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "ai-gateway-gateways" });
    if (std.mem.eql(u8, input_name, "dataset_id")) return actualCaptureCloudflareDatasetSourceHintCount(route, hints, source.hint_kind);
    if (std.mem.eql(u8, input_name, "job_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "logpush-account-jobs", "logpush-zone-jobs", "logpush-jobs" });
    if (std.mem.eql(u8, input_name, "script_name")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "workers-scripts", "worker-scripts" });
    if (std.mem.eql(u8, input_name, "script_tag")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "workers-scripts", "worker-scripts" });
    if (std.mem.eql(u8, input_name, "profile_id")) return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
    if (std.mem.eql(u8, input_name, "connector_id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "magic-connectors" });
    if (std.mem.eql(u8, input_name, "tag_uuid")) return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
    if (std.mem.eql(u8, input_name, "bucket_name")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "r2-catalog" });
    if (std.mem.eql(u8, input_name, "namespace")) return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
    if (std.mem.eql(u8, input_name, "table_name")) return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
    if (std.mem.eql(u8, input_name, "nodeId") or std.mem.eql(u8, input_name, "nodeType")) return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
    if (std.mem.eql(u8, input_name, "id")) return actualCaptureCloudflareKindHintCount(hints, &.{ source.hint_kind, "ai-gateway-logs", "audit-logs-account-v2", "audit-logs-organization-v2" });
    return actualCaptureCloudflareKindHintCount(hints, &.{source.hint_kind});
}

fn actualCaptureCloudflareCertificateSourceHintCount(route: provider_routes.Route, hints: Hints, source_hint_kind: []const u8) usize {
    if (actualCaptureRoutePathContains(route, "/access/certificates/")) {
        if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "access-account-mtls-certificates", "access-account-mtls-certificate" });
        if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "access-zone-mtls-certificates", "access-zone-mtls-certificate" });
    }
    if (actualCaptureRoutePathContains(route, "/gateway/certificates/")) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "zero-trust-gateway-certificates", "zero-trust-gateway-certificate" });
    if (actualCaptureRoutePathContains(route, "/origin_ca/certificates/")) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "tls-origin-ca-certificates", "tls-origin-ca-certificate" });
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/hostnames/certificates/")) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "tls-zone-hostname-aop-certificates", "tls-zone-hostname-aop-certificate" });
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/")) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "tls-zone-aop-certificates", "tls-zone-aop-certificate" });
    return actualCaptureCloudflareKindHintCount(hints, &.{source_hint_kind});
}

fn actualCaptureCloudflareDatasetSourceHintCount(route: provider_routes.Route, hints: Hints, source_hint_kind: []const u8) usize {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "log-explorer-account-datasets", "log-explorer-account-available-datasets" });
    if (actualCaptureCloudflareRouteZoneScoped(route)) return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "log-explorer-zone-datasets", "log-explorer-zone-available-datasets" });
    return actualCaptureCloudflareKindHintCount(hints, &.{ source_hint_kind, "log-explorer-account-datasets", "log-explorer-zone-datasets" });
}

fn actualCaptureCloudflareKindHintCount(hints: Hints, kinds: []const []const u8) usize {
    var count: usize = 0;
    for (hints.cloudflare_resources) |row| {
        if (row.resource_id.len != 0 and actualCaptureKindIn(row.kind, kinds)) count += 1;
    }
    for (hints.cloudflare_inventory) |row| {
        if (row.resource_id.len != 0 and actualCaptureKindIn(row.kind, kinds)) count += 1;
    }
    return count;
}

fn actualCaptureHostingerKindHintCount(hints: Hints, kind: []const u8) usize {
    var count: usize = 0;
    for (hints.hostinger_resources) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    for (hints.hostinger_inventory) |row| {
        if (std.mem.eql(u8, row.kind, kind) and row.resource_id.len != 0) count += 1;
    }
    return count;
}

pub fn actualCaptureMissingInputSources(route: provider_routes.Route, input_source: []const u8, input_name: []const u8) []const InputSource {
    const operation_id = route.operation_id orelse return &.{};
    if (route.provider == .cloudflare) return actualCaptureCloudflareMissingInputSources(route, input_source, input_name, operation_id);
    if (route.provider != .hostinger) return &.{};

    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "domain")) return hostinger_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "virtualMachineId")) return hostinger_vps_sources[0..];
        if (std.mem.eql(u8, input_name, "actionId")) return hostinger_action_sources[0..];
        if (std.mem.eql(u8, input_name, "templateId")) return hostinger_template_sources[0..];
        if (std.mem.eql(u8, input_name, "firewallId")) return hostinger_firewall_sources[0..];
        if (std.mem.eql(u8, input_name, "postInstallScriptId")) return hostinger_post_install_sources[0..];
        if (std.mem.eql(u8, input_name, "snapshotId") and std.mem.eql(u8, operation_id, "DNS_getDNSSnapshotV1")) return hostinger_dns_snapshot_sources[0..];
        if (std.mem.eql(u8, input_name, "whoisId") and (std.mem.eql(u8, operation_id, "domains_getWHOISProfileV1") or std.mem.eql(u8, operation_id, "domains_getWHOISProfileUsageV1"))) return hostinger_whois_sources[0..];
        if (std.mem.eql(u8, input_name, "username") and std.mem.startsWith(u8, operation_id, "hosting_")) return hostinger_username_sources[0..];
        if (std.mem.eql(u8, input_name, "name") and std.mem.eql(u8, operation_id, "hosting_getPhpMyAdminLinkV1")) return hostinger_database_sources[0..];
        if (std.mem.eql(u8, input_name, "uuid") and std.mem.eql(u8, operation_id, "hosting_getNodeJSBuildLogsV1")) return hostinger_nodejs_build_sources[0..];
        if (std.mem.eql(u8, input_name, "projectName") and std.mem.startsWith(u8, operation_id, "VPS_getProject")) return hostinger_docker_project_sources[0..];
        if (std.mem.eql(u8, input_name, "profileUuid") and std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1")) return hostinger_reach_profile_sources[0..];
        if (std.mem.eql(u8, input_name, "segmentUuid") and (std.mem.eql(u8, operation_id, "reach_getSegmentDetailsV1") or std.mem.eql(u8, operation_id, "reach_listSegmentContactsV1") or std.mem.eql(u8, operation_id, "reach_listProfileSegmentContactsV1"))) return hostinger_reach_segment_sources[0..];
    }

    if (std.mem.eql(u8, input_source, "query")) {
        if (std.mem.eql(u8, input_name, "order_id") and std.mem.eql(u8, operation_id, "hosting_listAvailableDatacentersV1")) return hostinger_order_sources[0..];
    }

    return &.{};
}

fn actualCaptureCloudflareMissingInputSources(route: provider_routes.Route, input_source: []const u8, input_name: []const u8, operation_id: []const u8) []const InputSource {
    if (std.mem.eql(u8, input_source, "path")) {
        if (std.mem.eql(u8, input_name, "organization_id")) return cloudflare_account_organization_sources[0..];
        if (std.mem.eql(u8, input_name, "user_group_id")) return cloudflare_account_user_group_sources[0..];
        if (std.mem.eql(u8, input_name, "member_id") and actualCaptureRoutePathContains(route, "/iam/user_groups/")) return cloudflare_account_user_group_member_sources[0..];
        if (std.mem.eql(u8, input_name, "invite_id")) return cloudflare_user_invite_sources[0..];
        if (std.mem.eql(u8, input_name, "membership_id")) return cloudflare_membership_sources[0..];
        if (std.mem.eql(u8, input_name, "custom_csr_id")) return actualCaptureCloudflareCustomCsrSources(route);
        if (std.mem.eql(u8, input_name, "asset_name") and actualCaptureRoutePathContains(route, "/custom_pages/assets/")) return actualCaptureCloudflareCustomAssetSources(route);
        if (std.mem.eql(u8, input_name, "custom_hostname_id")) return cloudflare_zone_custom_hostname_sources[0..];
        if (std.mem.eql(u8, input_name, "client_certificate_id")) return cloudflare_client_certificate_sources[0..];
        if (std.mem.eql(u8, input_name, "certificate_pack_id")) return cloudflare_certificate_pack_sources[0..];
        if (std.mem.eql(u8, input_name, "custom_certificate_id")) return cloudflare_custom_ssl_sources[0..];
        if (std.mem.eql(u8, input_name, "keyless_certificate_id")) return cloudflare_keyless_ssl_sources[0..];
        if (std.mem.eql(u8, input_name, "setting_id") and actualCaptureRoutePathContains(route, "/hostnames/settings/")) return cloudflare_per_hostname_tls_sources[0..];
        if (std.mem.eql(u8, input_name, "setting_id") and actualCaptureRoutePathContains(route, "/settings/")) return cloudflare_zone_setting_sources[0..];
        if (std.mem.eql(u8, input_name, "hostname") and actualCaptureRoutePathContains(route, "/hostnames/settings/")) return cloudflare_per_hostname_tls_sources[0..];
        if (std.mem.eql(u8, input_name, "saml_cert_set_id")) return cloudflare_access_account_saml_sources[0..];
        if (std.mem.eql(u8, input_name, "app_id") and actualCaptureRoutePathContains(route, "/access/apps/")) return actualCaptureCloudflareAccessApplicationSources(route);
        if (std.mem.eql(u8, input_name, "certificate_id")) return actualCaptureCloudflareCertificateSources(route, operation_id);
        if (std.mem.eql(u8, input_name, "app_id")) return actualCaptureCloudflareAccessCaSources(route, operation_id);
        if (std.mem.eql(u8, input_name, "mtls_certificate_id")) return cloudflare_mtls_certificate_sources[0..];
        if (std.mem.eql(u8, input_name, "identity_provider_id")) return actualCaptureCloudflareAccessIdentityProviderSources(route);
        if (std.mem.eql(u8, input_name, "idp_id")) return actualCaptureCloudflareAccessIdentityProviderSources(route);
        if (std.mem.eql(u8, input_name, "grant_id")) return cloudflare_access_idp_federation_grant_sources[0..];
        if (std.mem.eql(u8, input_name, "custom_page_id")) return cloudflare_access_account_custom_page_sources[0..];
        if (std.mem.eql(u8, input_name, "group_id") and actualCaptureRoutePathContains(route, "/access/groups/")) return actualCaptureCloudflareAccessGroupSources(route);
        if (std.mem.eql(u8, input_name, "policy_id") and actualCaptureRoutePathContains(route, "/access/")) return actualCaptureCloudflareAccessPolicySources(route);
        if (std.mem.eql(u8, input_name, "tag_name") and actualCaptureRoutePathContains(route, "/access/tags/")) return cloudflare_access_account_tag_sources[0..];
        if (std.mem.eql(u8, input_name, "target_id") and actualCaptureRoutePathContains(route, "/infrastructure/targets/")) return cloudflare_access_account_infra_target_sources[0..];
        if (std.mem.eql(u8, input_name, "service_token_id")) return actualCaptureCloudflareAccessServiceTokenSources(route);
        if (std.mem.eql(u8, input_name, "user_id")) return actualCaptureCloudflareUserSources(route);
        if (std.mem.eql(u8, input_name, "nonce") and actualCaptureRoutePathContains(route, "/active_sessions/")) return cloudflare_zero_trust_user_session_sources[0..];
        if (std.mem.eql(u8, input_name, "ca_slug")) return cloudflare_radar_authority_sources[0..];
        if (std.mem.eql(u8, input_name, "log_slug")) return cloudflare_radar_log_sources[0..];
        if (std.mem.eql(u8, input_name, "view_id")) return cloudflare_dns_view_sources[0..];
        if (std.mem.eql(u8, input_name, "acl_id")) return cloudflare_secondary_dns_acl_sources[0..];
        if (std.mem.eql(u8, input_name, "peer_id")) return cloudflare_secondary_dns_peer_sources[0..];
        if (std.mem.eql(u8, input_name, "tsig_id")) return cloudflare_secondary_dns_tsig_sources[0..];
        if (std.mem.eql(u8, input_name, "gateway_id")) return cloudflare_ai_gateway_sources[0..];
        if (std.mem.eql(u8, input_name, "dataset_id")) return actualCaptureCloudflareDatasetSources(route);
        if (std.mem.eql(u8, input_name, "job_id")) return actualCaptureCloudflareLogpushJobSources(route);
        if (std.mem.eql(u8, input_name, "script_name")) return cloudflare_worker_script_sources[0..];
        if (std.mem.eql(u8, input_name, "script_tag")) return cloudflare_worker_script_sources[0..];
        if (std.mem.eql(u8, input_name, "profile_id") and actualCaptureRoutePathContains(route, "/magic/bgp/filter_profiles/")) return cloudflare_magic_bgp_filter_profile_sources[0..];
        if (std.mem.eql(u8, input_name, "connector_id") and (actualCaptureRoutePathContains(route, "/cfd_tunnel/") or actualCaptureRoutePathContains(route, "/warp_connector/"))) return actualCaptureCloudflareTunnelConnectorSources(route);
        if (std.mem.eql(u8, input_name, "connector_id") and actualCaptureRoutePathContains(route, "/magic/connectors/")) return cloudflare_magic_connector_sources[0..];
        if (std.mem.eql(u8, input_name, "asn_id")) return cloudflare_botnet_asn_sources[0..];
        if (std.mem.eql(u8, input_name, "dns_firewall_id")) return cloudflare_dns_firewall_sources[0..];
        if (std.mem.eql(u8, input_name, "investigate_id")) return cloudflare_email_security_message_sources[0..];
        if (std.mem.eql(u8, input_name, "policy_id") and actualCaptureRoutePathContains(route, "/email-security/settings/allow_policies/")) return cloudflare_email_security_allow_policy_sources[0..];
        if (std.mem.eql(u8, input_name, "pattern_id") and actualCaptureRoutePathContains(route, "/email-security/settings/block_senders/")) return cloudflare_email_security_blocked_sender_sources[0..];
        if (std.mem.eql(u8, input_name, "domain_id") and actualCaptureRoutePathContains(route, "/email-security/settings/domains/")) return cloudflare_email_security_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "impersonation_registry_id")) return cloudflare_email_security_impersonation_sources[0..];
        if (std.mem.eql(u8, input_name, "sending_domain_restriction_id")) return cloudflare_email_security_sending_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "trusted_domain_id")) return cloudflare_email_security_trusted_domain_sources[0..];
        if (std.mem.eql(u8, input_name, "pattern_id") and actualCaptureRoutePathContains(route, "/email-security/settings/url_ignore_patterns/")) return cloudflare_email_security_url_ignore_sources[0..];
        if (std.mem.eql(u8, input_name, "rule_id") and actualCaptureRoutePathContains(route, "/firewall/access_rules/rules/")) return actualCaptureCloudflareIpAccessRuleSources(route);
        if (std.mem.eql(u8, input_name, "detection_id") and actualCaptureRoutePathContains(route, "/leaked-credential-checks/detections/")) return cloudflare_leaked_credential_detection_sources[0..];
        if (std.mem.eql(u8, input_name, "connection_id") and actualCaptureRoutePathContains(route, "/page_shield/connections/")) return cloudflare_page_shield_connection_sources[0..];
        if (std.mem.eql(u8, input_name, "cookie_id") and actualCaptureRoutePathContains(route, "/page_shield/cookies/")) return cloudflare_page_shield_cookie_sources[0..];
        if (std.mem.eql(u8, input_name, "policy_id") and actualCaptureRoutePathContains(route, "/page_shield/policies/")) return cloudflare_page_shield_policy_sources[0..];
        if (std.mem.eql(u8, input_name, "script_id") and actualCaptureRoutePathContains(route, "/page_shield/scripts/")) return cloudflare_page_shield_script_sources[0..];
        if (std.mem.eql(u8, input_name, "bot_slug")) return cloudflare_radar_bot_sources[0..];
        if (std.mem.eql(u8, input_name, "issue_id") and actualCaptureRoutePathContains(route, "/security-center/insights/")) return actualCaptureCloudflareSecurityCenterIssueSources(route);
        if (std.mem.eql(u8, input_name, "ua_rule_id")) return cloudflare_zone_ua_rule_sources[0..];
        if (std.mem.eql(u8, input_name, "lock_downs_id")) return cloudflare_zone_lockdown_sources[0..];
        if (std.mem.eql(u8, input_name, "snippet_name")) return cloudflare_zone_snippet_sources[0..];
        if (std.mem.eql(u8, input_name, "config_id") and actualCaptureRoutePathContains(route, "/token_validation/config/")) return cloudflare_token_validation_config_sources[0..];
        if (std.mem.eql(u8, input_name, "rule_id") and actualCaptureRoutePathContains(route, "/token_validation/rules/")) return cloudflare_token_validation_rule_sources[0..];
        if (std.mem.eql(u8, input_name, "ruleset_version")) return actualCaptureCloudflareRulesetVersionSources(route);
        if (std.mem.eql(u8, input_name, "rule_tag")) return actualCaptureCloudflareRulesetRuleTagSources(route);
        if (std.mem.eql(u8, input_name, "tag_uuid") and actualCaptureRoutePathContains(route, "/cloudforce-one/events/tags/")) return cloudflare_cloudforce_tag_sources[0..];
        if (std.mem.eql(u8, input_name, "bucket_name") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return cloudflare_r2_catalog_sources[0..];
        if (std.mem.eql(u8, input_name, "namespace") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return cloudflare_r2_namespace_sources[0..];
        if (std.mem.eql(u8, input_name, "table_name") and actualCaptureRoutePathContains(route, "/r2-catalog/")) return cloudflare_r2_table_sources[0..];
        if (std.mem.eql(u8, input_name, "monitor_group_id")) return cloudflare_account_load_balancer_monitor_group_sources[0..];
        if (std.mem.eql(u8, input_name, "monitor_id")) return actualCaptureCloudflareLoadBalancerMonitorSources(route);
        if (std.mem.eql(u8, input_name, "pool_id")) return actualCaptureCloudflareLoadBalancerPoolSources(route);
        if (std.mem.eql(u8, input_name, "load_balancer_id")) return cloudflare_zone_load_balancer_sources[0..];
        if (std.mem.eql(u8, input_name, "tunnel_id")) return actualCaptureCloudflareTunnelSources(route);
        if (std.mem.eql(u8, input_name, "gre_tunnel_id")) return cloudflare_gre_tunnel_sources[0..];
        if (std.mem.eql(u8, input_name, "ipsec_tunnel_id")) return cloudflare_ipsec_tunnel_sources[0..];
        if (std.mem.eql(u8, input_name, "route_id") or std.mem.eql(u8, input_name, "ip")) return cloudflare_tunnel_route_sources[0..];
        if (std.mem.eql(u8, input_name, "id")) return actualCaptureCloudflareIdSources(route, operation_id);
    }

    if (std.mem.eql(u8, input_source, "query")) {
        if ((std.mem.eql(u8, input_name, "nodeId") or std.mem.eql(u8, input_name, "nodeType")) and std.mem.eql(u8, operation_id, "get_EventGraph")) return cloudflare_cloudforce_event_sources[0..];
        if (std.mem.eql(u8, input_name, "idp_id") and std.mem.eql(u8, operation_id, "access-scim-update-logs-list-access-scim-update-logs")) return actualCaptureCloudflareAccessIdentityProviderSources(route);
        if (std.mem.eql(u8, input_name, "action_time")) return actualCaptureCloudflareAuditSources(route, operation_id);
    }

    return &.{};
}

fn actualCaptureCloudflareCustomCsrSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_custom_csr_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_custom_csr_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareCustomAssetSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_custom_asset_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_custom_asset_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessApplicationSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_application_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_application_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessIdentityProviderSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_identity_provider_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_identity_provider_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessGroupSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_group_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_group_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessPolicySources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/access/apps/")) {
        if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_application_policy_sources[0..];
        if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_application_policy_sources[0..];
    }
    if (actualCaptureRoutePathContains(route, "/access/policies/")) return cloudflare_access_account_reusable_policy_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessServiceTokenSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_service_token_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_service_token_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareUserSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/scim/v2/Users/")) return cloudflare_scim_user_sources[0..];
    if (actualCaptureRoutePathContains(route, "/access/users/")) return cloudflare_zero_trust_user_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareRulesetVersionSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/entrypoint/versions/")) {
        if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_ruleset_entrypoint_version_sources[0..];
        if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_ruleset_entrypoint_version_sources[0..];
    }
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_ruleset_version_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_ruleset_version_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareRulesetRuleTagSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_ruleset_version_rule_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_ruleset_version_rule_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareLoadBalancerMonitorSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_load_balancer_monitor_sources[0..];
    if (actualCaptureRoutePathContains(route, "/user/")) return cloudflare_user_load_balancer_monitor_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareLoadBalancerPoolSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_load_balancer_pool_sources[0..];
    if (actualCaptureRoutePathContains(route, "/user/")) return cloudflare_user_load_balancer_pool_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareTunnelSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/warp_connector/")) return cloudflare_warp_connector_sources[0..];
    if (actualCaptureRoutePathContains(route, "/cfd_tunnel/")) return cloudflare_tunnel_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareTunnelConnectorSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/warp_connector/")) return cloudflare_warp_connector_connection_sources[0..];
    if (actualCaptureRoutePathContains(route, "/cfd_tunnel/")) return cloudflare_tunnel_connector_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareIpAccessRuleSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureRoutePathContains(route, "/user/firewall/access_rules/")) return cloudflare_user_ip_access_rule_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_account_ip_access_rule_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_zone_ip_access_rule_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareSecurityCenterIssueSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_security_center_zone_issue_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_security_center_account_issue_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareCertificateSources(route: provider_routes.Route, operation_id: []const u8) []const InputSource {
    if (std.mem.eql(u8, operation_id, "access-mtls-authentication-get-an-mtls-certificate")) return cloudflare_access_account_mtls_sources[0..];
    if (std.mem.eql(u8, operation_id, "zone-level-access-mtls-authentication-get-an-mtls-certificate")) return cloudflare_access_zone_mtls_sources[0..];
    if (std.mem.eql(u8, operation_id, "zero-trust-certificates-zero-trust-certificate-details")) return cloudflare_zero_trust_certificate_sources[0..];
    if (std.mem.eql(u8, operation_id, "origin-ca-get-certificate")) return cloudflare_origin_ca_certificate_sources[0..];
    if (std.mem.eql(u8, operation_id, "per-hostname-authenticated-origin-pull-get-the-hostname-client-certificate")) return cloudflare_hostname_aop_certificate_sources[0..];
    if (std.mem.eql(u8, operation_id, "zone-level-authenticated-origin-pulls-get-certificate-details")) return cloudflare_zone_aop_certificate_sources[0..];
    if (actualCaptureRoutePathContains(route, "/access/certificates/")) {
        if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_mtls_sources[0..];
        if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_mtls_sources[0..];
    }
    if (actualCaptureRoutePathContains(route, "/gateway/certificates/")) return cloudflare_zero_trust_certificate_sources[0..];
    if (actualCaptureRoutePathContains(route, "/origin_ca/certificates/")) return cloudflare_origin_ca_certificate_sources[0..];
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/hostnames/certificates/")) return cloudflare_hostname_aop_certificate_sources[0..];
    if (actualCaptureRoutePathContains(route, "/origin_tls_client_auth/")) return cloudflare_zone_aop_certificate_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareAccessCaSources(route: provider_routes.Route, operation_id: []const u8) []const InputSource {
    if (std.mem.eql(u8, operation_id, "access-short-lived-certificate-c-as-get-a-short-lived-certificate-ca")) return cloudflare_access_account_ca_sources[0..];
    if (std.mem.eql(u8, operation_id, "zone-level-access-short-lived-certificate-c-as-get-a-short-lived-certificate-ca")) return cloudflare_access_zone_ca_sources[0..];
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_access_account_ca_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_access_zone_ca_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareDatasetSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_log_explorer_account_dataset_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_log_explorer_zone_dataset_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareLogpushJobSources(route: provider_routes.Route) []const InputSource {
    if (actualCaptureCloudflareRouteAccountScoped(route)) return cloudflare_logpush_account_job_sources[0..];
    if (actualCaptureCloudflareRouteZoneScoped(route)) return cloudflare_logpush_zone_job_sources[0..];
    return &.{};
}

fn actualCaptureCloudflareIdSources(route: provider_routes.Route, operation_id: []const u8) []const InputSource {
    if (std.mem.eql(u8, operation_id, "aig-config-get-gateway-log-detail") or
        std.mem.eql(u8, operation_id, "aig-config-get-gateway-log-request") or
        std.mem.eql(u8, operation_id, "aig-config-get-gateway-log-response")) return cloudflare_ai_gateway_log_sources[0..];
    return actualCaptureCloudflareAuditSources(route, operation_id);
}

fn actualCaptureCloudflareAuditSources(route: provider_routes.Route, operation_id: []const u8) []const InputSource {
    if (std.mem.eql(u8, operation_id, "audit-logs-v2-get-account-audit-log-history")) return cloudflare_audit_account_log_sources[0..];
    if (std.mem.eql(u8, operation_id, "audit-logs-v2-get-organization-audit-log-history")) return cloudflare_audit_organization_log_sources[0..];
    if (actualCaptureRoutePathContains(route, "/organizations/")) return cloudflare_audit_organization_log_sources[0..];
    if (actualCaptureRoutePathContains(route, "/accounts/")) return cloudflare_audit_account_log_sources[0..];
    return &.{};
}

test "plans Hostinger VPS metrics inputs from VPS and synthetic date hints" {
    const allocator = std.testing.allocator;
    const route_json =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, route_json, .{});
    defer parsed.deinit();
    const route = try provider_routes.Route.init(allocator, .hostinger, parsed.value);
    defer route.deinit(allocator);

    var vps_rows = [_]db_store.HostingerVpsRow{.{
        .id = @constCast("1307809"),
        .name = @constCast("plosca"),
        .status = @constCast("running"),
        .ipv4 = @constCast(""),
        .plan = @constCast(""),
        .updated_at = @constCast(""),
    }};
    const hints = Hints{ .hostinger_vps = vps_rows[0..] };

    try std.testing.expect(actualCaptureReady(route, hints));
    try std.testing.expectEqualStrings("1307809", actualCapturePathParamHint(route, "virtualMachineId", hints) orelse "");
    try std.testing.expect(actualCaptureHasQueryParamHint(route, "date_from", hints));
    try std.testing.expect(actualCaptureHasQueryParamHint(route, "date_to", hints));

    const date_from = (try actualCaptureQueryParamHint(allocator, route, "date_from", hints)) orelse return error.ExpectedDateFromHint;
    defer allocator.free(date_from);
    const date_to = (try actualCaptureQueryParamHint(allocator, route, "date_to", hints)) orelse return error.ExpectedDateToHint;
    defer allocator.free(date_to);
    try std.testing.expectEqual(@as(usize, 17), date_from.len);
    try std.testing.expectEqual(@as(usize, 17), date_to.len);
    try std.testing.expect(date_from[10] == 'T' and date_from[16] == 'Z');
    try std.testing.expect(date_to[10] == 'T' and date_to[16] == 'Z');
}

test "plans actual captures from generated enum parameter metadata" {
    const allocator = std.testing.allocator;
    const enum_path_json =
        \\{"provider":"cloudflare","tag":"Radar Bots","method":"GET","path":"/radar/bots/{dimension}/summary","operation_id":"radar-enum-path","path_params":[{"name":"dimension","required":true,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":["CONTENT_TYPE","USER_AGENT"]}}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var enum_path_parsed = try std.json.parseFromSlice(std.json.Value, allocator, enum_path_json, .{});
    defer enum_path_parsed.deinit();
    const enum_path_route = try provider_routes.Route.init(allocator, .cloudflare, enum_path_parsed.value);
    defer enum_path_route.deinit(allocator);
    try std.testing.expect(actualCaptureReady(enum_path_route, .{}));
    try std.testing.expectEqualStrings("CONTENT_TYPE", actualCapturePathParamHint(enum_path_route, "dimension", .{}) orelse "");

    const enum_query_json =
        \\{"provider":"cloudflare","tag":"Radar Bots","method":"GET","path":"/radar/bots/summary","operation_id":"radar-enum-query","path_params":[],"query_params":[{"name":"format","required":true,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":["JSON","CSV"]}}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var enum_query_parsed = try std.json.parseFromSlice(std.json.Value, allocator, enum_query_json, .{});
    defer enum_query_parsed.deinit();
    const enum_query_route = try provider_routes.Route.init(allocator, .cloudflare, enum_query_parsed.value);
    defer enum_query_route.deinit(allocator);
    try std.testing.expect(actualCaptureReady(enum_query_route, .{}));
    try std.testing.expect(actualCaptureHasQueryParamHint(enum_query_route, "format", .{}));
    const format = (try actualCaptureQueryParamHint(allocator, enum_query_route, "format", .{})) orelse return error.ExpectedFormatHint;
    defer allocator.free(format);
    try std.testing.expectEqualStrings("JSON", format);
}

test "maps Cloudflare load-balancer and tunnel child captures to list sources" {
    const allocator = std.testing.allocator;
    const route_jsons = [_][]const u8{
        \\{"provider":"cloudflare","tag":"Account Load Balancer Monitors","method":"GET","path":"/accounts/{account_id}/load_balancers/monitors","operation_id":"account-load-balancer-monitors-list-monitors","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Account Load Balancer Monitors","method":"GET","path":"/accounts/{account_id}/load_balancers/monitors/{monitor_id}","operation_id":"account-load-balancer-monitors-monitor-details","path_params":[{"name":"account_id","required":true},{"name":"monitor_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Load Balancer Monitors","method":"GET","path":"/user/load_balancers/monitors","operation_id":"load-balancer-monitors-list-monitors","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Load Balancer Monitors","method":"GET","path":"/user/load_balancers/monitors/{monitor_id}","operation_id":"load-balancer-monitors-monitor-details","path_params":[{"name":"monitor_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Account Load Balancer Pools","method":"GET","path":"/accounts/{account_id}/load_balancers/pools","operation_id":"account-load-balancer-pools-list-pools","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Account Load Balancer Pools","method":"GET","path":"/accounts/{account_id}/load_balancers/pools/{pool_id}","operation_id":"account-load-balancer-pools-pool-details","path_params":[{"name":"account_id","required":true},{"name":"pool_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Load Balancers","method":"GET","path":"/zones/{zone_id}/load_balancers","operation_id":"load-balancers-list-load-balancers","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Load Balancers","method":"GET","path":"/zones/{zone_id}/load_balancers/{load_balancer_id}","operation_id":"load-balancers-load-balancer-details","path_params":[{"name":"zone_id","required":true},{"name":"load_balancer_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/cfd_tunnel","operation_id":"cloudflare-tunnel-list-cloudflare-tunnels","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/cfd_tunnel/{tunnel_id}","operation_id":"cloudflare-tunnel-get-a-cloudflare-tunnel","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/warp_connector","operation_id":"cloudflare-tunnel-list-warp-connector-tunnels","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/warp_connector/{tunnel_id}","operation_id":"cloudflare-tunnel-get-a-warp-connector-tunnel","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Magic GRE tunnels","method":"GET","path":"/accounts/{account_id}/magic/gre_tunnels","operation_id":"magic-gre-tunnels-list-gre-tunnels","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Magic GRE tunnels","method":"GET","path":"/accounts/{account_id}/magic/gre_tunnels/{gre_tunnel_id}","operation_id":"magic-gre-tunnels-list-gre-tunnel-details","path_params":[{"name":"account_id","required":true},{"name":"gre_tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Magic IPsec tunnels","method":"GET","path":"/accounts/{account_id}/magic/ipsec_tunnels","operation_id":"magic-ipsec-tunnels-list-ipsec-tunnels","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Magic IPsec tunnels","method":"GET","path":"/accounts/{account_id}/magic/ipsec_tunnels/{ipsec_tunnel_id}","operation_id":"magic-ipsec-tunnels-list-ipsec-tunnel-details","path_params":[{"name":"account_id","required":true},{"name":"ipsec_tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Tunnel Routing","method":"GET","path":"/accounts/{account_id}/teamnet/routes","operation_id":"tunnel-route-list-tunnel-routes","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Tunnel Routing","method":"GET","path":"/accounts/{account_id}/teamnet/routes/{route_id}","operation_id":"tunnel-route-get-tunnel-route","path_params":[{"name":"account_id","required":true},{"name":"route_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/connections","operation_id":"cloudflare-tunnel-list-cloudflare-tunnel-connections","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/connections/{connector_id}","operation_id":"cloudflare-tunnel-get-cloudflare-tunnel-connector","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true},{"name":"connector_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/warp_connector/{tunnel_id}/connections","operation_id":"cloudflare-tunnel-list-warp-connector-tunnel-connections","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
        ,
        \\{"provider":"cloudflare","tag":"Cloudflare Tunnel","method":"GET","path":"/accounts/{account_id}/warp_connector/{tunnel_id}/connections/{connector_id}","operation_id":"cloudflare-tunnel-get-warp-connector-tunnel-connector","path_params":[{"name":"account_id","required":true},{"name":"tunnel_id","required":true},{"name":"connector_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    };
    var routes: [route_jsons.len]provider_routes.Route = undefined;
    for (route_jsons, 0..) |route_json, idx| {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, route_json, .{});
        defer parsed.deinit();
        routes[idx] = try provider_routes.Route.init(allocator, .cloudflare, parsed.value);
    }
    defer for (routes) |route| route.deinit(allocator);

    var account_rows = [_]db_store.CloudflareAccountRow{.{
        .id = @constCast("acct-1"),
        .name = @constCast("Main account"),
        .account_type = @constCast("standard"),
        .status = @constCast("active"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var zone_rows = [_]db_store.CloudflareZoneRow{.{
        .id = @constCast("zone-1"),
        .name = @constCast("plosca.ru"),
        .account_id = @constCast("acct-1"),
        .status = @constCast("active"),
        .paused = @constCast("false"),
        .zone_type = @constCast("full"),
        .name_servers = @constCast("ns1.example,ns2.example"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    const scope_hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_zones = zone_rows[0..],
    };

    try std.testing.expect(actualCaptureReady(routes[0], scope_hints));
    try std.testing.expect(actualCaptureReady(routes[2], scope_hints));
    try std.testing.expect(actualCaptureReady(routes[6], scope_hints));
    try std.testing.expectEqualStrings("account-load-balancer-monitors-list-monitors", actualCaptureMissingInputSources(routes[1], "path", "monitor_id")[0].operation_id);
    try std.testing.expectEqualStrings("load-balancer-monitors-list-monitors", actualCaptureMissingInputSources(routes[3], "path", "monitor_id")[0].operation_id);
    try std.testing.expectEqualStrings("account-load-balancer-pools-list-pools", actualCaptureMissingInputSources(routes[5], "path", "pool_id")[0].operation_id);
    try std.testing.expectEqualStrings("load-balancers-list-load-balancers", actualCaptureMissingInputSources(routes[7], "path", "load_balancer_id")[0].operation_id);
    try std.testing.expectEqualStrings("cloudflare-tunnel-list-cloudflare-tunnels", actualCaptureMissingInputSources(routes[9], "path", "tunnel_id")[0].operation_id);
    try std.testing.expectEqualStrings("cloudflare-tunnel-list-warp-connector-tunnels", actualCaptureMissingInputSources(routes[11], "path", "tunnel_id")[0].operation_id);
    try std.testing.expectEqualStrings("magic-gre-tunnels-list-gre-tunnels", actualCaptureMissingInputSources(routes[13], "path", "gre_tunnel_id")[0].operation_id);
    try std.testing.expectEqualStrings("magic-ipsec-tunnels-list-ipsec-tunnels", actualCaptureMissingInputSources(routes[15], "path", "ipsec_tunnel_id")[0].operation_id);
    try std.testing.expectEqualStrings("tunnel-route-list-tunnel-routes", actualCaptureMissingInputSources(routes[17], "path", "route_id")[0].operation_id);
    try std.testing.expectEqualStrings("cloudflare-tunnel-list-cloudflare-tunnel-connections", actualCaptureMissingInputSources(routes[19], "path", "connector_id")[0].operation_id);
    try std.testing.expectEqualStrings("cloudflare-tunnel-list-warp-connector-tunnel-connections", actualCaptureMissingInputSources(routes[21], "path", "connector_id")[0].operation_id);

    var resource_rows = [_]db_store.CloudflareResourceHintRow{
        .{ .kind = @constCast("account-load-balancer-monitors-list-monitors"), .resource_id = @constCast("acct-monitor-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Account monitor"), .status = @constCast("active"), .resource_type = @constCast("monitor"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("load-balancer-monitors-list-monitors"), .resource_id = @constCast("user-monitor-1"), .scope = @constCast("user"), .scope_id = @constCast("user"), .name = @constCast("User monitor"), .status = @constCast("active"), .resource_type = @constCast("monitor"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("account-load-balancer-pools-list-pools"), .resource_id = @constCast("pool-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Pool"), .status = @constCast("active"), .resource_type = @constCast("pool"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("load-balancers-list-load-balancers"), .resource_id = @constCast("lb-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Load balancer"), .status = @constCast("active"), .resource_type = @constCast("load_balancer"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("cloudflare-tunnel-list-cloudflare-tunnels"), .resource_id = @constCast("tunnel-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Tunnel"), .status = @constCast("active"), .resource_type = @constCast("tunnel"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("cloudflare-tunnel-list-warp-connector-tunnels"), .resource_id = @constCast("warp-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("WARP"), .status = @constCast("active"), .resource_type = @constCast("warp_connector"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("cloudflare-tunnel-list-cloudflare-tunnel-connections"), .resource_id = @constCast("cfd-connector-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("CFD connector"), .status = @constCast("connected"), .resource_type = @constCast("connector"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("cloudflare-tunnel-list-warp-connector-tunnel-connections"), .resource_id = @constCast("warp-connector-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("WARP connector"), .status = @constCast("connected"), .resource_type = @constCast("connector"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("magic-gre-tunnels-list-gre-tunnels"), .resource_id = @constCast("gre-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("GRE"), .status = @constCast("active"), .resource_type = @constCast("gre_tunnel"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("magic-ipsec-tunnels-list-ipsec-tunnels"), .resource_id = @constCast("ipsec-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("IPsec"), .status = @constCast("active"), .resource_type = @constCast("ipsec_tunnel"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("tunnel-route-list-tunnel-routes"), .resource_id = @constCast("route-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Route"), .status = @constCast("active"), .resource_type = @constCast("route"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
    };
    const resource_hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_zones = zone_rows[0..],
        .cloudflare_resources = resource_rows[0..],
    };

    try std.testing.expect(actualCaptureReady(routes[1], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[3], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[5], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[7], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[9], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[11], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[13], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[15], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[17], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[18], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[19], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[20], resource_hints));
    try std.testing.expect(actualCaptureReady(routes[21], resource_hints));
    try std.testing.expectEqualStrings("acct-monitor-1", actualCapturePathParamHint(routes[1], "monitor_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("user-monitor-1", actualCapturePathParamHint(routes[3], "monitor_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("pool-1", actualCapturePathParamHint(routes[5], "pool_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("lb-1", actualCapturePathParamHint(routes[7], "load_balancer_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("tunnel-1", actualCapturePathParamHint(routes[9], "tunnel_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("warp-1", actualCapturePathParamHint(routes[11], "tunnel_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("gre-1", actualCapturePathParamHint(routes[13], "gre_tunnel_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("ipsec-1", actualCapturePathParamHint(routes[15], "ipsec_tunnel_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("route-1", actualCapturePathParamHint(routes[17], "route_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("cfd-connector-1", actualCapturePathParamHint(routes[19], "connector_id", resource_hints) orelse "");
    try std.testing.expectEqualStrings("warp-connector-1", actualCapturePathParamHint(routes[21], "connector_id", resource_hints) orelse "");
}

test "maps Cloudflare security child captures to list sources" {
    const allocator = std.testing.allocator;
    const Case = struct {
        route_json: []const u8,
        input_name: []const u8,
        expected_source: []const u8,
        expected_value: []const u8,
    };
    const cases = [_]Case{
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Botnet Threat Feed","method":"GET","path":"/accounts/{account_id}/botnet_feed/asn/{asn_id}/day_report","operation_id":"botnet-threat-feed-get-day-report","path_params":[{"name":"account_id","required":true},{"name":"asn_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "asn_id",
            .expected_source = "botnet-threat-feed-list-asn",
            .expected_value = "64512",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"DNS Firewall","method":"GET","path":"/accounts/{account_id}/dns_firewall/{dns_firewall_id}","operation_id":"dns-firewall-dns-firewall-cluster-details","path_params":[{"name":"account_id","required":true},{"name":"dns_firewall_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "dns_firewall_id",
            .expected_source = "dns-firewall-list-dns-firewall-clusters",
            .expected_value = "dnsfw-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security","method":"GET","path":"/accounts/{account_id}/email-security/investigate/{investigate_id}","operation_id":"email_security_get_message","path_params":[{"name":"account_id","required":true},{"name":"investigate_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "investigate_id",
            .expected_source = "email_security_investigate",
            .expected_value = "msg-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/allow_policies/{policy_id}","operation_id":"email_security_get_allow_policy","path_params":[{"name":"account_id","required":true},{"name":"policy_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "policy_id",
            .expected_source = "email_security_list_allow_policies",
            .expected_value = "allow-policy-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/block_senders/{pattern_id}","operation_id":"email_security_get_blocked_sender","path_params":[{"name":"account_id","required":true},{"name":"pattern_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "pattern_id",
            .expected_source = "email_security_list_blocked_senders",
            .expected_value = "blocked-pattern-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/domains/{domain_id}","operation_id":"email_security_get_domain","path_params":[{"name":"account_id","required":true},{"name":"domain_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "domain_id",
            .expected_source = "email_security_list_domains",
            .expected_value = "domain-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/impersonation_registry/{impersonation_registry_id}","operation_id":"email_security_get_impersonation_registry","path_params":[{"name":"account_id","required":true},{"name":"impersonation_registry_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "impersonation_registry_id",
            .expected_source = "email_security_list_impersonation_registry",
            .expected_value = "impersonation-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/sending_domain_restrictions/{sending_domain_restriction_id}","operation_id":"email_security_get_sending_domain_restriction","path_params":[{"name":"account_id","required":true},{"name":"sending_domain_restriction_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "sending_domain_restriction_id",
            .expected_source = "email_security_list_sending_domain_restrictions",
            .expected_value = "sending-domain-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/trusted_domains/{trusted_domain_id}","operation_id":"email_security_get_trusted_domain","path_params":[{"name":"account_id","required":true},{"name":"trusted_domain_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "trusted_domain_id",
            .expected_source = "email_security_list_trusted_domains",
            .expected_value = "trusted-domain-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/url_ignore_patterns/{pattern_id}","operation_id":"email_security_get_url_ignore_pattern","path_params":[{"name":"account_id","required":true},{"name":"pattern_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "pattern_id",
            .expected_source = "email_security_list_url_ignore_patterns",
            .expected_value = "url-pattern-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"IP Access rules for a user","method":"GET","path":"/user/firewall/access_rules/rules/{rule_id}","operation_id":"ip-access-rules-for-a-user-get-an-ip-access-rule","path_params":[{"name":"rule_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "rule_id",
            .expected_source = "ip-access-rules-for-a-user-list-ip-access-rules",
            .expected_value = "user-rule-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"IP Access rules for an account","method":"GET","path":"/accounts/{account_id}/firewall/access_rules/rules/{rule_id}","operation_id":"ip-access-rules-for-an-account-get-an-ip-access-rule","path_params":[{"name":"account_id","required":true},{"name":"rule_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "rule_id",
            .expected_source = "ip-access-rules-for-an-account-list-ip-access-rules",
            .expected_value = "account-rule-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Leaked Credential Checks","method":"GET","path":"/zones/{zone_id}/leaked-credential-checks/detections/{detection_id}","operation_id":"waf-product-api-leaked-credentials-get-detection","path_params":[{"name":"zone_id","required":true},{"name":"detection_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "detection_id",
            .expected_source = "waf-product-api-leaked-credentials-list-detections",
            .expected_value = "detection-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Page Shield","method":"GET","path":"/zones/{zone_id}/page_shield/connections/{connection_id}","operation_id":"page-shield-get-connection","path_params":[{"name":"zone_id","required":true},{"name":"connection_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "connection_id",
            .expected_source = "page-shield-list-connections",
            .expected_value = "connection-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Page Shield","method":"GET","path":"/zones/{zone_id}/page_shield/cookies/{cookie_id}","operation_id":"page-shield-get-cookie","path_params":[{"name":"zone_id","required":true},{"name":"cookie_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "cookie_id",
            .expected_source = "page-shield-list-cookies",
            .expected_value = "cookie-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Page Shield","method":"GET","path":"/zones/{zone_id}/page_shield/policies/{policy_id}","operation_id":"page-shield-get-policy","path_params":[{"name":"zone_id","required":true},{"name":"policy_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "policy_id",
            .expected_source = "page-shield-list-policies",
            .expected_value = "page-policy-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Page Shield","method":"GET","path":"/zones/{zone_id}/page_shield/scripts/{script_id}","operation_id":"page-shield-get-script","path_params":[{"name":"zone_id","required":true},{"name":"script_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "script_id",
            .expected_source = "page-shield-list-scripts",
            .expected_value = "script-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Radar Bots","method":"GET","path":"/radar/bots/{bot_slug}","operation_id":"radar-get-bot-details","path_params":[{"name":"bot_slug","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "bot_slug",
            .expected_source = "radar-get-bots",
            .expected_value = "googlebot",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Security Center Audit Log","method":"GET","path":"/accounts/{account_id}/security-center/insights/{issue_id}/audit-log","operation_id":"get-security-center-issue-audit-log","path_params":[{"name":"account_id","required":true},{"name":"issue_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "issue_id",
            .expected_source = "get-security-center-insights",
            .expected_value = "account-issue-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Security Center Audit Log","method":"GET","path":"/zones/{zone_id}/security-center/insights/{issue_id}/audit-log","operation_id":"get-zone-security-center-issue-audit-log","path_params":[{"name":"zone_id","required":true},{"name":"issue_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "issue_id",
            .expected_source = "get-zone-security-center-insights",
            .expected_value = "zone-issue-1",
        },
    };

    var account_rows = [_]db_store.CloudflareAccountRow{.{
        .id = @constCast("acct-1"),
        .name = @constCast("Main account"),
        .account_type = @constCast("standard"),
        .status = @constCast("active"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var zone_rows = [_]db_store.CloudflareZoneRow{.{
        .id = @constCast("zone-1"),
        .name = @constCast("plosca.ru"),
        .account_id = @constCast("acct-1"),
        .status = @constCast("active"),
        .paused = @constCast("false"),
        .zone_type = @constCast("full"),
        .name_servers = @constCast("ns1.example,ns2.example"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var resource_rows = [_]db_store.CloudflareResourceHintRow{
        .{ .kind = @constCast("botnet-threat-feed-list-asn"), .resource_id = @constCast("64512"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("AS64512"), .status = @constCast("active"), .resource_type = @constCast("asn"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("dns-firewall-list-dns-firewall-clusters"), .resource_id = @constCast("dnsfw-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("DNS Firewall"), .status = @constCast("active"), .resource_type = @constCast("dns_firewall"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_investigate"), .resource_id = @constCast("msg-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Message"), .status = @constCast("active"), .resource_type = @constCast("email_message"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_allow_policies"), .resource_id = @constCast("allow-policy-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Allow policy"), .status = @constCast("enabled"), .resource_type = @constCast("allow_policy"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_blocked_senders"), .resource_id = @constCast("blocked-pattern-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Blocked sender"), .status = @constCast("enabled"), .resource_type = @constCast("blocked_sender"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_domains"), .resource_id = @constCast("domain-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Domain"), .status = @constCast("enabled"), .resource_type = @constCast("domain"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_impersonation_registry"), .resource_id = @constCast("impersonation-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Impersonation"), .status = @constCast("enabled"), .resource_type = @constCast("impersonation"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_sending_domain_restrictions"), .resource_id = @constCast("sending-domain-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Sending domain"), .status = @constCast("enabled"), .resource_type = @constCast("sending_domain"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_trusted_domains"), .resource_id = @constCast("trusted-domain-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Trusted domain"), .status = @constCast("enabled"), .resource_type = @constCast("trusted_domain"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("email_security_list_url_ignore_patterns"), .resource_id = @constCast("url-pattern-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("URL ignore"), .status = @constCast("enabled"), .resource_type = @constCast("url_pattern"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("ip-access-rules-for-a-user-list-ip-access-rules"), .resource_id = @constCast("user-rule-1"), .scope = @constCast("user"), .scope_id = @constCast("user"), .name = @constCast("User rule"), .status = @constCast("active"), .resource_type = @constCast("ip_access_rule"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("ip-access-rules-for-an-account-list-ip-access-rules"), .resource_id = @constCast("account-rule-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Account rule"), .status = @constCast("active"), .resource_type = @constCast("ip_access_rule"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("waf-product-api-leaked-credentials-list-detections"), .resource_id = @constCast("detection-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Detection"), .status = @constCast("active"), .resource_type = @constCast("detection"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("page-shield-list-connections"), .resource_id = @constCast("connection-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Connection"), .status = @constCast("active"), .resource_type = @constCast("connection"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("page-shield-list-cookies"), .resource_id = @constCast("cookie-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Cookie"), .status = @constCast("active"), .resource_type = @constCast("cookie"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("page-shield-list-policies"), .resource_id = @constCast("page-policy-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Page policy"), .status = @constCast("active"), .resource_type = @constCast("policy"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("page-shield-list-scripts"), .resource_id = @constCast("script-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Script"), .status = @constCast("active"), .resource_type = @constCast("script"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("radar-get-bots"), .resource_id = @constCast("googlebot"), .scope = @constCast("global"), .scope_id = @constCast("global"), .name = @constCast("Googlebot"), .status = @constCast("active"), .resource_type = @constCast("bot"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("get-security-center-insights"), .resource_id = @constCast("account-issue-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Account issue"), .status = @constCast("open"), .resource_type = @constCast("issue"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("get-zone-security-center-insights"), .resource_id = @constCast("zone-issue-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Zone issue"), .status = @constCast("open"), .resource_type = @constCast("issue"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
    };
    const hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_zones = zone_rows[0..],
        .cloudflare_resources = resource_rows[0..],
    };

    for (cases) |case| {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, case.route_json, .{});
        defer parsed.deinit();
        var route = try provider_routes.Route.init(allocator, .cloudflare, parsed.value);
        defer route.deinit(allocator);

        const sources = actualCaptureMissingInputSources(route, "path", case.input_name);
        try std.testing.expect(sources.len > 0);
        try std.testing.expectEqualStrings(case.expected_source, sources[0].operation_id);
        try std.testing.expect(actualCaptureReady(route, hints));
        try std.testing.expectEqualStrings(case.expected_value, actualCapturePathParamHint(route, case.input_name, hints) orelse "");
    }
}

test "maps Cloudflare named control-plane child captures to list sources" {
    const allocator = std.testing.allocator;
    const Case = struct {
        route_json: []const u8,
        input_source: []const u8 = "path",
        input_name: []const u8,
        expected_source: []const u8,
        expected_value: []const u8,
    };
    const cases = [_]Case{
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Account User Groups","method":"GET","path":"/accounts/{account_id}/iam/user_groups/{user_group_id}","operation_id":"account-user-group-details","path_params":[{"name":"account_id","required":true},{"name":"user_group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "user_group_id",
            .expected_source = "account-user-group-list",
            .expected_value = "user-group-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Account User Group Members","method":"GET","path":"/accounts/{account_id}/iam/user_groups/{user_group_id}/members/{member_id}","operation_id":"account-user-group-member-get","path_params":[{"name":"account_id","required":true},{"name":"user_group_id","required":true},{"name":"member_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "member_id",
            .expected_source = "account-user-group-member-list",
            .expected_value = "member-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Custom CSRs for an Account","method":"GET","path":"/accounts/{account_id}/custom_csrs/{custom_csr_id}","operation_id":"custom-csrs-for-an-account-custom-csr-details","path_params":[{"name":"account_id","required":true},{"name":"custom_csr_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "custom_csr_id",
            .expected_source = "custom-csrs-for-an-account-list-custom-csrs",
            .expected_value = "csr-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Custom Hostname for a Zone","method":"GET","path":"/zones/{zone_id}/custom_hostnames/{custom_hostname_id}","operation_id":"custom-hostname-for-a-zone-custom-hostname-details","path_params":[{"name":"zone_id","required":true},{"name":"custom_hostname_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "custom_hostname_id",
            .expected_source = "custom-hostname-for-a-zone-list-custom-hostnames",
            .expected_value = "custom-hostname-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"SCIM Users","method":"GET","path":"/accounts/{account_id}/scim/v2/Users/{user_id}","operation_id":"scim-users-get","path_params":[{"name":"account_id","required":true},{"name":"user_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "user_id",
            .expected_source = "scim-users-list",
            .expected_value = "scim-user-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Zero Trust users","method":"GET","path":"/accounts/{account_id}/access/users/{user_id}/active_sessions/{nonce}","operation_id":"zero-trust-users-get-active-session","path_params":[{"name":"account_id","required":true},{"name":"user_id","required":true},{"name":"nonce","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "nonce",
            .expected_source = "zero-trust-users-get-active-sessions",
            .expected_value = "nonce-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Access SCIM update logs","method":"GET","path":"/accounts/{account_id}/access/logs/scim/updates","operation_id":"access-scim-update-logs-list-access-scim-update-logs","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"idp_id","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_source = "query",
            .input_name = "idp_id",
            .expected_source = "access-identity-providers-list-access-identity-providers",
            .expected_value = "idp-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Access groups","method":"GET","path":"/accounts/{account_id}/access/groups/{group_id}","operation_id":"access-groups-get-an-access-group","path_params":[{"name":"account_id","required":true},{"name":"group_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "group_id",
            .expected_source = "access-groups-list-access-groups",
            .expected_value = "access-group-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Zone-Level Access policies","method":"GET","path":"/zones/{zone_id}/access/apps/{app_id}/policies/{policy_id}","operation_id":"zone-level-access-policies-get-an-access-policy","path_params":[{"name":"zone_id","required":true},{"name":"app_id","required":true},{"name":"policy_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "policy_id",
            .expected_source = "zone-level-access-policies-list-access-policies",
            .expected_value = "zone-policy-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"DNS Internal Views for an Account","method":"GET","path":"/accounts/{account_id}/dns_settings/views/{view_id}","operation_id":"dns-views-for-an-account-get-internal-dns-view","path_params":[{"name":"account_id","required":true},{"name":"view_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "view_id",
            .expected_source = "dns-views-for-an-account-list-internal-dns-views",
            .expected_value = "view-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Secondary DNS (ACL)","method":"GET","path":"/accounts/{account_id}/secondary_dns/acls/{acl_id}","operation_id":"secondary-dns-(-acl)-acl-details","path_params":[{"name":"account_id","required":true},{"name":"acl_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "acl_id",
            .expected_source = "secondary-dns-(-acl)-list-ac-ls",
            .expected_value = "acl-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Token Validation Token Configuration","method":"GET","path":"/zones/{zone_id}/token_validation/config/{config_id}","operation_id":"token-validation-config-get","path_params":[{"name":"zone_id","required":true},{"name":"config_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "config_id",
            .expected_source = "token-validation-config-list",
            .expected_value = "config-1",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/{ruleset_id}/versions/{ruleset_version}","operation_id":"getAccountRulesetVersion","path_params":[{"name":"account_id","required":true},{"name":"ruleset_id","required":true},{"name":"ruleset_version","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "ruleset_version",
            .expected_source = "listAccountRulesetVersions",
            .expected_value = "42",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"Account Rulesets","method":"GET","path":"/accounts/{account_id}/rulesets/{ruleset_id}/versions/{ruleset_version}/by_tag/{rule_tag}","operation_id":"listAccountRulesetVersionRulesByTag","path_params":[{"name":"account_id","required":true},{"name":"ruleset_id","required":true},{"name":"ruleset_version","required":true},{"name":"rule_tag","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "rule_tag",
            .expected_source = "getAccountRulesetVersion",
            .expected_value = "managed",
        },
        .{
            .route_json =
            \\{"provider":"cloudflare","tag":"User's Account Memberships","method":"GET","path":"/memberships/{membership_id}","operation_id":"user'-s-account-memberships-membership-details","path_params":[{"name":"membership_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
            ,
            .input_name = "membership_id",
            .expected_source = "user'-s-account-memberships-list-memberships",
            .expected_value = "membership-1",
        },
    };

    var account_rows = [_]db_store.CloudflareAccountRow{.{
        .id = @constCast("acct-1"),
        .name = @constCast("Main account"),
        .account_type = @constCast("standard"),
        .status = @constCast("active"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var zone_rows = [_]db_store.CloudflareZoneRow{.{
        .id = @constCast("zone-1"),
        .name = @constCast("plosca.ru"),
        .account_id = @constCast("acct-1"),
        .status = @constCast("active"),
        .paused = @constCast("false"),
        .zone_type = @constCast("full"),
        .name_servers = @constCast("ns1.example,ns2.example"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var resource_rows = [_]db_store.CloudflareResourceHintRow{
        .{ .kind = @constCast("account-user-group-list"), .resource_id = @constCast("user-group-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Operators"), .status = @constCast("active"), .resource_type = @constCast("user_group"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("account-user-group-member-list"), .resource_id = @constCast("member-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/user-group-1"), .name = @constCast("Member"), .status = @constCast("active"), .resource_type = @constCast("member"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("custom-csrs-for-an-account-list-custom-csrs"), .resource_id = @constCast("csr-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("CSR"), .status = @constCast("pending"), .resource_type = @constCast("csr"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("custom-hostname-for-a-zone-list-custom-hostnames"), .resource_id = @constCast("custom-hostname-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("app.example.com"), .status = @constCast("active"), .resource_type = @constCast("custom_hostname"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("scim-users-list"), .resource_id = @constCast("scim-user-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("SCIM user"), .status = @constCast("active"), .resource_type = @constCast("user"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("zero-trust-users-get-users"), .resource_id = @constCast("zero-user-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Zero Trust user"), .status = @constCast("active"), .resource_type = @constCast("user"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("zero-trust-users-get-active-sessions"), .resource_id = @constCast("nonce-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/zero-user-1"), .name = @constCast("Session"), .status = @constCast("active"), .resource_type = @constCast("session"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("access-identity-providers-list-access-identity-providers"), .resource_id = @constCast("idp-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("IdP"), .status = @constCast("active"), .resource_type = @constCast("idp"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("access-groups-list-access-groups"), .resource_id = @constCast("access-group-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Access group"), .status = @constCast("active"), .resource_type = @constCast("group"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("zone-level-access-applications-list-access-applications"), .resource_id = @constCast("zone-app-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Zone app"), .status = @constCast("active"), .resource_type = @constCast("app"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("zone-level-access-policies-list-access-policies"), .resource_id = @constCast("zone-policy-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Zone policy"), .status = @constCast("active"), .resource_type = @constCast("policy"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("dns-views-for-an-account-list-internal-dns-views"), .resource_id = @constCast("view-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("View"), .status = @constCast("active"), .resource_type = @constCast("dns_view"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("secondary-dns-(-acl)-list-ac-ls"), .resource_id = @constCast("acl-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("ACL"), .status = @constCast("active"), .resource_type = @constCast("acl"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("token-validation-config-list"), .resource_id = @constCast("config-1"), .scope = @constCast("zone"), .scope_id = @constCast("zone-1"), .name = @constCast("Config"), .status = @constCast("active"), .resource_type = @constCast("config"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("account-rulesets"), .resource_id = @constCast("ruleset-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Ruleset"), .status = @constCast("active"), .resource_type = @constCast("http_request_firewall_custom"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("listAccountRulesetVersions"), .resource_id = @constCast("42"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/ruleset-1"), .name = @constCast("Version 42"), .status = @constCast("active"), .resource_type = @constCast("version"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("getAccountRulesetVersion"), .resource_id = @constCast("managed"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/ruleset-1/42"), .name = @constCast("Managed tag"), .status = @constCast("active"), .resource_type = @constCast("rule_tag"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("user'-s-account-memberships-list-memberships"), .resource_id = @constCast("membership-1"), .scope = @constCast("user"), .scope_id = @constCast("user"), .name = @constCast("Membership"), .status = @constCast("active"), .resource_type = @constCast("membership"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
    };
    const hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_zones = zone_rows[0..],
        .cloudflare_resources = resource_rows[0..],
    };

    for (cases) |case| {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, case.route_json, .{});
        defer parsed.deinit();
        var route = try provider_routes.Route.init(allocator, .cloudflare, parsed.value);
        defer route.deinit(allocator);

        const sources = actualCaptureMissingInputSources(route, case.input_source, case.input_name);
        try std.testing.expect(sources.len > 0);
        try std.testing.expectEqualStrings(case.expected_source, sources[0].operation_id);
        try std.testing.expect(actualCaptureReady(route, hints));
        if (std.mem.eql(u8, case.input_source, "query")) {
            const value = (try actualCaptureQueryParamHint(allocator, route, case.input_name, hints)) orelse return error.ExpectedQueryHint;
            defer allocator.free(value);
            try std.testing.expectEqualStrings(case.expected_value, value);
        } else {
            try std.testing.expectEqualStrings(case.expected_value, actualCapturePathParamHint(route, case.input_name, hints) orelse "");
        }
    }
}

test "plans Cloudflare audit history inputs from matching event timestamps" {
    const allocator = std.testing.allocator;
    const account_route_json =
        \\{"provider":"cloudflare","tag":"Audit Logs","method":"GET","path":"/accounts/{account_id}/logs/audit/{id}/history","operation_id":"audit-logs-v2-get-account-audit-log-history","path_params":[{"name":"account_id","required":true},{"name":"id","required":true}],"query_params":[{"name":"action_time","required":true},{"name":"before","required":true},{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var account_parsed = try std.json.parseFromSlice(std.json.Value, allocator, account_route_json, .{});
    defer account_parsed.deinit();
    const account_route = try provider_routes.Route.init(allocator, .cloudflare, account_parsed.value);
    defer account_route.deinit(allocator);

    const organization_route_json =
        \\{"provider":"cloudflare","tag":"Audit Logs","method":"GET","path":"/organizations/{organization_id}/logs/audit/{id}/history","operation_id":"audit-logs-v2-get-organization-audit-log-history","path_params":[{"name":"organization_id","required":true},{"name":"id","required":true}],"query_params":[{"name":"action_time","required":true},{"name":"before","required":true},{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false}
    ;
    var organization_parsed = try std.json.parseFromSlice(std.json.Value, allocator, organization_route_json, .{});
    defer organization_parsed.deinit();
    const organization_route = try provider_routes.Route.init(allocator, .cloudflare, organization_parsed.value);
    defer organization_route.deinit(allocator);

    var account_rows = [_]db_store.CloudflareAccountRow{.{
        .id = @constCast("acct-1"),
        .name = @constCast("Main account"),
        .account_type = @constCast("standard"),
        .status = @constCast("active"),
        .updated_at = @constCast("2026-06-18T00:00:00Z"),
    }};
    var organization_rows = [_]db_store.CloudflareResourceHintRow{.{
        .kind = @constCast("Accounts_listAccountOrganizations"),
        .resource_id = @constCast("org-1"),
        .scope = @constCast("account"),
        .scope_id = @constCast("acct-1"),
        .name = @constCast("Org"),
        .status = @constCast("active"),
        .resource_type = @constCast("organization"),
        .updated_at = @constCast("2026-06-18T00:00:00Z"),
    }};
    var audit_events = [_]db_store.CloudflareInventoryHintRow{
        .{
            .kind = @constCast("audit-logs-v2-get-account-audit-logs"),
            .resource_id = @constCast("audit-account-1"),
            .scope = @constCast("account"),
            .scope_id = @constCast("acct-1"),
            .display_name = @constCast(""),
            .status = @constCast("success"),
            .category = @constCast("update"),
            .domain = @constCast(""),
            .account_id = @constCast("acct-1"),
            .zone_id = @constCast(""),
            .related_id = @constCast(""),
            .flag = @constCast(""),
            .updated_at = @constCast("2026-06-18T12:34:56Z"),
        },
        .{
            .kind = @constCast("audit-logs-v2-get-organization-audit-logs"),
            .resource_id = @constCast("audit-org-1"),
            .scope = @constCast("organization"),
            .scope_id = @constCast("org-1"),
            .display_name = @constCast(""),
            .status = @constCast("success"),
            .category = @constCast("view"),
            .domain = @constCast(""),
            .account_id = @constCast(""),
            .zone_id = @constCast(""),
            .related_id = @constCast(""),
            .flag = @constCast(""),
            .updated_at = @constCast("2026-06-18T13:45:07Z"),
        },
    };
    const hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_resources = organization_rows[0..],
        .cloudflare_inventory = audit_events[0..],
    };

    try std.testing.expect(actualCaptureReady(account_route, hints));
    try std.testing.expectEqualStrings("acct-1", actualCapturePathParamHint(account_route, "account_id", hints) orelse "");
    try std.testing.expectEqualStrings("audit-account-1", actualCapturePathParamHint(account_route, "id", hints) orelse "");
    const account_action_time = (try actualCaptureQueryParamHint(allocator, account_route, "action_time", hints)) orelse return error.ExpectedAccountActionTimeHint;
    defer allocator.free(account_action_time);
    try std.testing.expectEqualStrings("2026-06-18T12:34:56Z", account_action_time);

    try std.testing.expect(actualCaptureReady(organization_route, hints));
    try std.testing.expectEqualStrings("org-1", actualCapturePathParamHint(organization_route, "organization_id", hints) orelse "");
    try std.testing.expectEqualStrings("audit-org-1", actualCapturePathParamHint(organization_route, "id", hints) orelse "");
    const organization_action_time = (try actualCaptureQueryParamHint(allocator, organization_route, "action_time", hints)) orelse return error.ExpectedOrganizationActionTimeHint;
    defer allocator.free(organization_action_time);
    try std.testing.expectEqualStrings("2026-06-18T13:45:07Z", organization_action_time);
}

test "plans remaining Cloudflare global read inputs from collected parent inventory" {
    const allocator = std.testing.allocator;
    const route_jsons = [_][]const u8{
        \\{"provider":"cloudflare","tag":"Email Routing routing rules","method":"GET","path":"/accounts/{account_id}/email/routing/rules","operation_id":"email-routing-routing-rules-list-account-routing-rules","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"account read"}
        ,
        \\{"provider":"cloudflare","tag":"Magic BGP Filter Profiles","method":"GET","path":"/accounts/{account_id}/magic/bgp/filter_profiles","operation_id":"magic-bgp-list-filter-profiles","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"profile list"}
        ,
        \\{"provider":"cloudflare","tag":"Magic BGP Settings","method":"GET","path":"/accounts/{account_id}/magic/bgp/settings","operation_id":"magic-bgp-get-settings","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"settings"}
        ,
        \\{"provider":"cloudflare","tag":"Magic BGP Filter Profiles","method":"GET","path":"/accounts/{account_id}/magic/bgp/filter_profiles/{profile_id}","operation_id":"magic-bgp-get-filter-profile","path_params":[{"name":"account_id","required":true},{"name":"profile_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"profile detail"}
        ,
        \\{"provider":"cloudflare","tag":"Magic Connectors","method":"GET","path":"/accounts/{account_id}/magic/connectors/{connector_id}/interrupts","operation_id":"mconn-connector-interrupt-list","path_params":[{"name":"account_id","required":true},{"name":"connector_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"connector interrupts"}
        ,
        \\{"provider":"cloudflare","tag":"Tag","method":"GET","path":"/accounts/{account_id}/cloudforce-one/events/tags/{tag_uuid}/indicators","operation_id":"get_TagIndicatorsList","path_params":[{"name":"account_id","required":true},{"name":"tag_uuid","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"tag indicators"}
        ,
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/builds/workers/{script_tag}","operation_id":"getWorkerBuild","path_params":[{"name":"account_id","required":true},{"name":"script_tag","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"worker build"}
        ,
        \\{"provider":"cloudflare","tag":"Events","method":"GET","path":"/accounts/{account_id}/cloudforce-one/events/graph","operation_id":"get_EventGraph","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"nodeId","required":true},{"name":"nodeType","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"event graph"}
        ,
        \\{"provider":"cloudflare","tag":"Table Management","method":"GET","path":"/accounts/{account_id}/r2-catalog/{bucket_name}/namespaces/{namespace}/tables/{table_name}","operation_id":"get-table","path_params":[{"name":"account_id","required":true},{"name":"bucket_name","required":true},{"name":"namespace","required":true},{"name":"table_name","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"table detail"}
        ,
    };

    var routes: [route_jsons.len]provider_routes.Route = undefined;
    for (route_jsons, 0..) |route_json, idx| {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, route_json, .{});
        defer parsed.deinit();
        routes[idx] = try provider_routes.Route.init(allocator, .cloudflare, parsed.value);
    }
    defer for (routes) |route| route.deinit(allocator);

    var account_rows = [_]db_store.CloudflareAccountRow{.{
        .id = @constCast("acct-1"),
        .name = @constCast("Main account"),
        .account_type = @constCast("standard"),
        .status = @constCast("active"),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    var resource_rows = [_]db_store.CloudflareResourceHintRow{
        .{ .kind = @constCast("magic-bgp-list-filter-profiles"), .resource_id = @constCast("profile-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("BGP profile"), .status = @constCast("active"), .resource_type = @constCast("profile"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("mconn-connector-list"), .resource_id = @constCast("connector-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Connector"), .status = @constCast("active"), .resource_type = @constCast("connector"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("get_TagList"), .resource_id = @constCast("tag-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("Tag"), .status = @constCast("active"), .resource_type = @constCast("tag"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("worker-script-list-workers"), .resource_id = @constCast("script-tag-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("worker"), .status = @constCast("active"), .resource_type = @constCast("worker"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("list-catalogs"), .resource_id = @constCast("bucket-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1"), .name = @constCast("bucket-1"), .status = @constCast("active"), .resource_type = @constCast("r2-catalog"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("list-namespaces"), .resource_id = @constCast("namespace-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/bucket-1"), .name = @constCast("namespace-1"), .status = @constCast("active"), .resource_type = @constCast("namespace"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
        .{ .kind = @constCast("list-tables"), .resource_id = @constCast("table-1"), .scope = @constCast("account"), .scope_id = @constCast("acct-1/bucket-1/namespace-1"), .name = @constCast("table-1"), .status = @constCast("active"), .resource_type = @constCast("table"), .updated_at = @constCast("2026-06-19T00:00:00Z") },
    };
    var inventory_rows = [_]db_store.CloudflareInventoryHintRow{.{
        .kind = @constCast("get_EventListGet"),
        .resource_id = @constCast("event-1"),
        .scope = @constCast("account"),
        .scope_id = @constCast("acct-1"),
        .display_name = @constCast("Cloudforce event"),
        .status = @constCast("active"),
        .category = @constCast("event"),
        .domain = @constCast(""),
        .account_id = @constCast("acct-1"),
        .zone_id = @constCast(""),
        .related_id = @constCast(""),
        .flag = @constCast(""),
        .updated_at = @constCast("2026-06-19T00:00:00Z"),
    }};
    const hints = Hints{
        .cloudflare_accounts = account_rows[0..],
        .cloudflare_resources = resource_rows[0..],
        .cloudflare_inventory = inventory_rows[0..],
    };

    for (routes) |route| try std.testing.expect(actualCaptureReady(route, hints));
    try std.testing.expectEqualStrings("profile-1", actualCapturePathParamHint(routes[3], "profile_id", hints) orelse "");
    try std.testing.expectEqualStrings("connector-1", actualCapturePathParamHint(routes[4], "connector_id", hints) orelse "");
    try std.testing.expectEqualStrings("tag-1", actualCapturePathParamHint(routes[5], "tag_uuid", hints) orelse "");
    try std.testing.expectEqualStrings("script-tag-1", actualCapturePathParamHint(routes[6], "script_tag", hints) orelse "");
    try std.testing.expectEqualStrings("bucket-1", actualCapturePathParamHint(routes[8], "bucket_name", hints) orelse "");
    try std.testing.expectEqualStrings("namespace-1", actualCapturePathParamHint(routes[8], "namespace", hints) orelse "");
    try std.testing.expectEqualStrings("table-1", actualCapturePathParamHint(routes[8], "table_name", hints) orelse "");

    const node_id = (try actualCaptureQueryParamHint(allocator, routes[7], "nodeId", hints)) orelse return error.ExpectedNodeIdHint;
    defer allocator.free(node_id);
    const node_type = (try actualCaptureQueryParamHint(allocator, routes[7], "nodeType", hints)) orelse return error.ExpectedNodeTypeHint;
    defer allocator.free(node_type);
    try std.testing.expectEqualStrings("event-1", node_id);
    try std.testing.expectEqualStrings("event", node_type);

    try std.testing.expectEqualStrings("magic-bgp-list-filter-profiles", actualCaptureMissingInputSources(routes[3], "path", "profile_id")[0].operation_id);
    try std.testing.expectEqualStrings("mconn-connector-list", actualCaptureMissingInputSources(routes[4], "path", "connector_id")[0].operation_id);
    try std.testing.expectEqualStrings("get_TagList", actualCaptureMissingInputSources(routes[5], "path", "tag_uuid")[0].operation_id);
    try std.testing.expectEqualStrings("worker-script-list-workers", actualCaptureMissingInputSources(routes[6], "path", "script_tag")[0].operation_id);
    try std.testing.expectEqualStrings("get_EventListGet", actualCaptureMissingInputSources(routes[7], "query", "nodeId")[0].operation_id);
    try std.testing.expectEqualStrings("list-catalogs", actualCaptureMissingInputSources(routes[8], "path", "bucket_name")[0].operation_id);
    try std.testing.expectEqualStrings("list-namespaces", actualCaptureMissingInputSources(routes[8], "path", "namespace")[0].operation_id);
    try std.testing.expectEqualStrings("list-tables", actualCaptureMissingInputSources(routes[8], "path", "table_name")[0].operation_id);
}
