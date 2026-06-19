const std = @import("std");
const app_doctor = @import("app_doctor");
const app_export = @import("app_export");
const app_history = @import("app_history");
const app_init = @import("app_init");
const app_log = @import("app_log");
const app_overview = @import("app_overview");
const app_refresh = @import("app_refresh");
const app_caddy = @import("app_caddy");
const app_cloudflare = @import("app_cloudflare");
const app_database = @import("app_database");
const core_config = @import("core_config");
const core_version = @import("core_version");
const cli_args = @import("cli_args");
const cli_caddy = @import("cli_caddy");
const cli_cloudflare = @import("cli_cloudflare");
const cli_coverage = @import("cli_coverage");
const cli_evidence = @import("cli_evidence");
const cli_hostinger = @import("cli_hostinger");
const cli_inventory = @import("cli_inventory");
const cli_projects = @import("cli_projects");
const cli_render = @import("cli_render");
const cli_route = @import("cli_route");
const cli_routes = @import("cli_routes");
const cli_security = @import("cli_security");
const cli_system = @import("cli_system");
const cli_topology = @import("cli_topology");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Db = app_database.Db;

const version = core_version.value;

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        usage();
        return;
    }

    const cfg = try Config.load(init.io, arena, init.environ_map);
    var db = try app_database.openInitialized(init.io, cfg.db_path);
    defer db.close();

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        usage();
    } else if (std.mem.eql(u8, cmd, "init")) {
        try commandInit(init.io, init.gpa, cfg, &db);
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        try commandDoctor(init.io, init.gpa, cfg, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "refresh")) {
        try commandRefresh(init.io, init.gpa, cfg, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "overview")) {
        try commandOverview(init.io, init.gpa, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "topology")) {
        try cli_topology.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "history") or std.mem.eql(u8, cmd, "audit")) {
        try commandHistory(init.io, init.gpa, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "evidence")) {
        try cli_evidence.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "inventory")) {
        try cli_inventory.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "export")) {
        try commandExport(init.io, init.gpa, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "coverage")) {
        try cli_coverage.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
            .domains = cfg.domains,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "route")) {
        try cli_route.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .cloudflare_auth = .{ .cloudflare = cloudflareAuth(cfg) },
            .hostinger_token = cfg.hostinger_api_token,
            .db = &db,
            .domains = cfg.domains,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "routes")) {
        try cli_routes.run(.{
            .io = init.io,
            .gpa = init.gpa,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "log")) {
        try commandLog(init.io, init.gpa, cfg, args[2..]);
    } else if (std.mem.eql(u8, cmd, "security")) {
        try cli_security.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .config = cfg,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "cloudflare")) {
        try cli_cloudflare.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .auth = cloudflareAuth(cfg),
            .domains = cfg.domains,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "hostinger")) {
        try cli_hostinger.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .token = cfg.hostinger_api_token,
            .domains = cfg.domains,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "caddy")) {
        try cli_caddy.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .paths = caddyPaths(cfg),
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "system")) {
        try cli_system.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "projects")) {
        try cli_projects.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .projects_root = cfg.projects_root,
            .db = &db,
        }, args[2..]);
    } else {
        std.debug.print("unknown command: {s}\n\n", .{cmd});
        usage();
        return error.InvalidCliCommand;
    }
}

fn usage() void {
    std.debug.print(
        \\cloudio {s}
        \\
        \\Usage:
        \\  cloudio init
        \\  cloudio doctor [--json|--format json]
        \\  cloudio refresh [--all|--cloudflare|--hostinger|--caddy|--system|--projects]
        \\  cloudio overview [--json|--format json]
        \\  cloudio topology [--limit <n>] [--json|--format json]
        \\  cloudio history|audit [--limit <n>] [--audit-limit <n>] [--snapshot-limit <n>] [--json|--format json]
        \\  cloudio evidence [events|matrix|routes|coverage|capture-summary] [all|cloudflare|hostinger|caddy|system|projects|route] [--provider <scope>] [--limit <n>] [--json|--format json]
        \\  cloudio inventory [summary|facets] [cloudflare|hostinger] [query] [--provider <provider>] [--domain <domain>] [--query <text>] [--limit <n>] [--json|--format json]
        \\  cloudio export [snapshots|history] [--limit <n>] [--audit-limit <n>] [--snapshot-limit <n>] [--json]
        \\  cloudio coverage summary [--json|--format json]
        \\  cloudio coverage tags [all|cloudflare|hostinger] [--json|--format json]
        \\  cloudio coverage l1 [all|cloudflare|hostinger] [--json|--format json]
        \\  cloudio coverage capture-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>] [--plans] [--json|--format json]
        \\  cloudio coverage dry-run-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>] [--plans] [--json|--format json]
        \\  cloudio coverage families [all|cloudflare|hostinger] [--focus all|control-plane] [--limit <n>] [--json|--format json]
        \\  cloudio coverage typed-models [all|cloudflare|hostinger] [--family <family>] [--limit <n>] [--include-complete] [--json|--format json]
        \\  cloudio coverage workplan [all|cloudflare|hostinger] [all|control-plane|<family>] [--focus all|control-plane] [--family <family>] [--limit <n>] [--plans] [--bundle] [--candidate-limit <n>] [--json|--format json]
        \\  cloudio coverage routes [all|cloudflare|hostinger] [tag-query] [--family <family>] [--operation <id>] [--method <method>] [--path <template>] [--support <status>] [--mode <mode>] [--json|--format json]
        \\  cloudio coverage actual-captures [all|cloudflare|hostinger] [tag-query] [--family <family>] [--operation <id>] [--limit <n>] [--plans] [--json|--format json]
        \\  cloudio coverage gaps|levels|level-tags [all|cloudflare|hostinger] [--limit <n>] [--json|--format json]
        \\  cloudio coverage help
        \\  cloudio coverage plan <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--body-content-type <type>]
        \\  cloudio routes [list|catalog|groups|families|summary|tags] [all|cloudflare|hostinger] [query] [--provider <provider>] [--query <text>] [--limit <n>] [--json|--format json]
        \\  cloudio route plan|read|capture|dry-run <cloudflare|hostinger> --operation <id> [--path-param name=value] [--query-param name=value] [--header-param name=value] [--paginate] [--max-pages <n>] [--body-present|--body-content-type <type>]
        \\  cloudio route capture-ready <cloudflare|hostinger> [all|control-plane] [tag-query] [--focus all|control-plane] [--family <family>] [--operation <id>] [--limit <n>] [--max-pages <n>] [--execute]
        \\  cloudio log [--json|--format json]
        \\  cloudio security [redaction|secrets|audit] [--json|--format json]
        \\  cloudio cloudflare account [list]|account show <account-id>|account profile <account-id>|account organizations <account-id>
        \\  cloudio cloudflare account dns-record-usage <account-id>
        \\  cloudio cloudflare account members|roles <account-id>|account member|role <account-id> <resource-id>
        \\  cloudio cloudflare account tokens|token-permission-groups|token-verify <account-id>
        \\  cloudio cloudflare account token <account-id> <token-id>
        \\  cloudio cloudflare account permission-groups|resource-groups|user-groups <account-id>
        \\  cloudio cloudflare account permission-group|resource-group|user-group <account-id> <resource-id>
        \\  cloudio cloudflare account user-group-members <account-id> <user-group-id>
        \\  cloudio cloudflare account user-group-member <account-id> <user-group-id> <member-id>
        \\  cloudio cloudflare inventory|resources|ips [jdcloud]|user|tenants|memberships|membership <membership-id>|token [list]|token show <token-id>|token verify|token permission-groups|zone [domain]|zone show <zone-id>|setting <setting-id> [domain]|diagnose [domain]
        \\  cloudio cloudflare zone available-plans|available-rate-plans|cache-reserve|cache-reserve-clear|regional-tiered-cache|variants|environments|hold|subscription <zone-id>
        \\  cloudio cloudflare zone argo-analytics|argo-analytics-colos|argo-smart-routing|argo-tiered-caching|smart-tiered-cache|origin-post-quantum|smart-shield|smart-shield-cache-reserve-clear|cloud-connector-rules <zone-id>
        \\  cloudio cloudflare zone available-plan <zone-id> <plan-id>
        \\  cloudio cloudflare secondary-dns acls|peers|tsigs <account-id>
        \\  cloudio cloudflare secondary-dns acl|peer|tsig <account-id> <resource-id>
        \\  cloudio cloudflare secondary-dns primary|primary-status|secondary <zone-id>
        \\  cloudio cloudflare dns-analytics report|bytime <zone-id>
        \\  cloudio cloudflare dns-firewall list <account-id>|show|reverse-dns <account-id> <dns-firewall-id>
        \\  cloudio cloudflare dns-firewall analytics report|bytime <account-id> <dns-firewall-id>
        \\  cloudio cloudflare load-balancing account monitor-groups|monitors|pools|regions|search <account-id> [query]
        \\  cloudio cloudflare load-balancing account monitor-group|monitor-group-references|monitor|monitor-references|preview-result|pool|pool-health|pool-references|region <account-id> <resource-id>
        \\  cloudio cloudflare load-balancing user monitors|pools|healthcheck-events
        \\  cloudio cloudflare load-balancing user monitor|monitor-references|preview-result|pool|pool-health|pool-references <resource-id>
        \\  cloudio cloudflare load-balancing zone load-balancers <zone-id>|zone load-balancer <zone-id> <load-balancer-id>
        \\  cloudio cloudflare health-checks endpoint list <account-id>|endpoint show <account-id> <healthcheck-id>
        \\  cloudio cloudflare health-checks zone list <zone-id>|zone show|preview <zone-id> <healthcheck-id>
        \\  cloudio cloudflare health-checks smart-shield list <zone-id>|smart-shield show <zone-id> <healthcheck-id>
        \\  cloudio cloudflare resource-tags account tags|keys|resources|values <account-id> [resource-type] [resource-id]
        \\  cloudio cloudflare resource-tags zone tags <zone-id> [resource-type] [resource-id]
        \\  cloudio cloudflare rulesets account|zone list <scope-id>|show <scope-id> <ruleset-id>|versions <scope-id> <ruleset-id>
        \\  cloudio cloudflare rulesets account|zone entrypoint|entrypoint-versions <scope-id> <phase>|entrypoint-version <scope-id> <phase> <version>
        \\  cloudio cloudflare rulesets account|zone version <scope-id> <ruleset-id> <version>|rules-by-tag <scope-id> <ruleset-id> <version> <tag>
        \\  cloudio cloudflare cloudforce-one-rules list|managed|stats|tree <account-id> [key=value...]
        \\  cloudio cloudflare cloudforce-one-rules search <account-id> <query> [key=value...]|show <account-id> <rule-id>
        \\  cloudio cloudflare ip-access user list [key=value...]|user show <rule-id>
        \\  cloudio cloudflare ip-access account list <account-id> [key=value...]|account show <account-id> <rule-id>
        \\  cloudio cloudflare ip-access zone list <zone-id> [key=value...]
        \\  cloudio cloudflare page-rules|ua-rules|zone-lockdown list <zone-id>
        \\  cloudio cloudflare page-rules|ua-rules|zone-lockdown show <zone-id> <rule-id>
        \\  cloudio cloudflare page-shield settings|policies|connections|scripts|cookies <zone-id> [key=value...]
        \\  cloudio cloudflare page-shield policy|connection|script|cookie <zone-id> <resource-id>
        \\  cloudio cloudflare custom-pages account|zone pages|assets list <scope-id>
        \\  cloudio cloudflare custom-pages account|zone pages|assets show <scope-id> <resource-id>
        \\  cloudio cloudflare access-custom-pages list <account-id>|show <account-id> <custom-page-id>
        \\  cloudio cloudflare access account|zone applications|groups|identity-providers|service-tokens <scope-id>
        \\  cloudio cloudflare access account|zone application|group|identity-provider|service-token|mtls-certificate|ca <scope-id> <resource-id>
        \\  cloudio cloudflare access account idp-federation-grant|saml-certificate|saml-certificate-pem <account-id> <resource-id>
        \\  cloudio cloudflare access account reusable-policies|tags|authenticator-aaguids|idp-federation-grants|saml-certificates|scim-update-logs|keys|authentication-logs|mtls-certificates|mtls-settings|cas <account-id>
        \\  cloudio cloudflare access zone mtls-certificates|mtls-settings|cas <zone-id>
        \\  cloudio cloudflare tunnel cfd-tunnels|all-tunnels|warp-connectors|routes|virtual-networks|connectivity-settings|hostname-routes|subnets <account-id>
        \\  cloudio cloudflare tunnel cfd-tunnel|cfd-configurations|cfd-connections|cfd-token|warp-connector|warp-configurations|warp-connections|warp-token <account-id> <tunnel-id>
        \\  cloudio cloudflare tunnel cfd-connector|warp-connector-detail <account-id> <tunnel-id> <connector-id>
        \\  cloudio cloudflare tunnel route|hostname-route|subnet <account-id> <resource-id>|route-ip <account-id> <ip-or-cidr>
        \\  cloudio cloudflare zero-trust gateway|device-settings|gateway-configuration|gateway-egress-cidr-pairs|gateway-logging|dns-destination-ips|app-types|categories|operations|locations|proxy-endpoints|rules|tenant-rules|ssh-settings|apps-review-status|certificates|pacfiles|lists|organization|organization-doh|users <account-id> [key=value...]
        \\  cloudio cloudflare zero-trust operation|location|proxy-endpoint|rule|certificate|pacfile|list|list-items|user|user-active-sessions|user-active-session|user-failed-logins|user-last-seen-identity <account-id> <resource-id> [nonce]
        \\  cloudio cloudflare security-center account|zone issue-types|insights|class|severity|type|audit-log <scope-id> [key=value...]
        \\  cloudio cloudflare security-center account|zone context|insight-audit-log <scope-id> <issue-id> [key=value...]
        \\  cloudio cloudflare email-routing account addresses|address <account-id> [address-id] [key=value...]
        \\  cloudio cloudflare email-routing zone settings|dns|rules|rule|catch-all <zone-id> [rule-id] [key=value...]
        \\  cloudio cloudflare email-auth dmarc-reports|spf-inspect <zone-id> [spf-record-id]
        \\  cloudio cloudflare email-sending account limits <account-id>|zone subdomains|subdomain|subdomain-dns|subdomain-dns-status <zone-id> [subdomain-id]
        \\  cloudio cloudflare email-security settings allow-policies|allow-policy|blocked-senders|blocked-sender|domains|domain|impersonation-registry|impersonation-registry-entry|sending-domain-restrictions|sending-domain-restriction|trusted-domains|trusted-domain|url-ignore-patterns|url-ignore-pattern <account-id> [resource-id] [key=value...]
        \\  cloudio cloudflare audit-logs account <account-id> [key=value...]|account-v2 <account-id> since=<rfc3339> before=<rfc3339> [key=value...]|organization-v2 <organization-id> since=<rfc3339> before=<rfc3339> [key=value...]|user [key=value...]
        \\  cloudio cloudflare logpush account|zone jobs <scope-id>|job <scope-id> <job-id>|dataset-jobs|dataset-fields <scope-id> <dataset-id>
        \\  cloudio cloudflare log-explorer account|zone datasets|available <scope-id> [include_zones=true]|dataset <scope-id> <dataset-id>
        \\  cloudio cloudflare logs-received retention-flag|fields <zone-id>|received <zone-id> end=<rfc3339> [start=<rfc3339> count=true fields=... sample=... timestamps=...]|rayid <zone-id> <ray-id> [fields=... timestamps=...]
        \\  cloudio cloudflare tls zone automatic-ssl|certificate-packs|certificate-pack-quota|custom-csrs|custom-origin-trust-store|custom-ssl|keyless-ssl|hostname-aop|hostname-aop-certificates|ssl-verification|total-tls|universal-ssl|zone-aop-certificates|zone-aop-settings <zone-id> [key=value...]
        \\  cloudio cloudflare tls zone certificate-pack|custom-csr|custom-origin-trust-store-detail|custom-ssl-certificate|keyless-ssl-certificate|hostname-aop-certificate|zone-aop-certificate <zone-id> <resource-id>
        \\  cloudio cloudflare tls zone per-hostname-tls <zone-id> <setting-id>|per-hostname-tls-setting <zone-id> <setting-id> <hostname>|hostname-aop-status <zone-id> <hostname>
        \\  cloudio cloudflare tls account custom-csrs <account-id>|custom-csr <account-id> <custom-csr-id>
        \\  cloudio cloudflare tls origin-ca certificates <zone-id>|certificate <zone-id> <certificate-id>
        \\  cloudio cloudflare dns [domain]|dns list|export|usage|scan-review [domain]|dns show <record-id> [domain]
        \\  cloudio cloudflare dnssec [domain]|dnssec zsk [domain]
        \\  cloudio cloudflare dry-run dns create|batch|import|apply-scan-results|trigger-scan <zone-id>
        \\  cloudio cloudflare dry-run dns delete|patch|update <zone-id> <record-id>
        \\  cloudio cloudflare dry-run dnssec delete|edit-status <zone-id>
        \\  cloudio cloudflare dry-run zone create
        \\  cloudio cloudflare dry-run zone delete|edit|purge-cache|activation-check <zone-id>
        \\  cloudio cloudflare dry-run zone purge-environment-cache <zone-id> <environment-id>
        \\  cloudio cloudflare dry-run zone-lifecycle cache-reserve-change|cache-reserve-clear-start|regional-tiered-cache-change|variants-delete|variants-change <zone-id>
        \\  cloudio cloudflare dry-run zone-lifecycle argo-smart-routing-change|argo-tiered-caching-change|smart-tiered-cache-create|smart-tiered-cache-change|smart-tiered-cache-delete|origin-post-quantum-change|smart-shield-change|smart-shield-cache-reserve-clear-start|cloud-connector-rules-update <zone-id>
        \\  cloudio cloudflare dry-run zone-lifecycle environments-create|environments-edit|environments-update|hold-create|hold-update|hold-delete|subscription-create|subscription-update <zone-id>
        \\  cloudio cloudflare dry-run zone-lifecycle environment-delete|environment-rollback <zone-id> <environment-id>
        \\  cloudio cloudflare dry-run secondary-dns-account acl|peer|tsig create <account-id>
        \\  cloudio cloudflare dry-run secondary-dns-account acl|peer|tsig update|delete <account-id> <resource-id>
        \\  cloudio cloudflare dry-run secondary-dns-zone primary-create|primary-update|primary-delete|primary-enable|primary-disable|primary-force-notify <zone-id>
        \\  cloudio cloudflare dry-run secondary-dns-zone secondary-create|secondary-update|secondary-delete|secondary-force-axfr <zone-id>
        \\  cloudio cloudflare dry-run dns-firewall create <account-id>
        \\  cloudio cloudflare dry-run dns-firewall update|delete|update-reverse-dns <account-id> <dns-firewall-id>
        \\  cloudio cloudflare dry-run dns-settings account <account-id>|zone <zone-id>
        \\  cloudio cloudflare dry-run load-balancing account-monitor-group create <account-id>|update|patch|delete <account-id> <monitor-group-id>
        \\  cloudio cloudflare dry-run load-balancing account-monitor create <account-id>|update|patch|delete|preview <account-id> <monitor-id>
        \\  cloudio cloudflare dry-run load-balancing account-pool create|patch-all <account-id>|update|patch|delete|preview <account-id> <pool-id>
        \\  cloudio cloudflare dry-run load-balancing user-monitor create|update|patch|delete|preview [monitor-id]
        \\  cloudio cloudflare dry-run load-balancing user-pool create|patch-all|update|patch|delete|preview [pool-id]
        \\  cloudio cloudflare dry-run load-balancing zone-load-balancer create <zone-id>|update|patch|delete <zone-id> <load-balancer-id>
        \\  cloudio cloudflare dry-run health-checks endpoint create <account-id>|update|delete <account-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run health-checks zone create <zone-id>|update|patch|delete <zone-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run health-checks preview create <zone-id>|delete <zone-id> <preview-id>
        \\  cloudio cloudflare dry-run health-checks smart-shield create <zone-id>|update|patch|delete <zone-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run resource-tags account set|delete <account-id>
        \\  cloudio cloudflare dry-run resource-tags zone set|delete <zone-id>
        \\  cloudio cloudflare dry-run rulesets account|zone create <scope-id>|update|delete <scope-id> <ruleset-id>|update-entrypoint <scope-id> <phase>
        \\  cloudio cloudflare dry-run rulesets account|zone create-rule <scope-id> <ruleset-id>|update-rule|delete-rule <scope-id> <ruleset-id> <rule-id>|delete-version <scope-id> <ruleset-id> <version>
        \\  cloudio cloudflare dry-run cloudforce-one-rules create|delete-all|validate <account-id>
        \\  cloudio cloudflare dry-run cloudforce-one-rules update|delete <account-id> <rule-id>
        \\  cloudio cloudflare dry-run ip-access user create|user update|delete <rule-id>
        \\  cloudio cloudflare dry-run ip-access account|zone create <scope-id>
        \\  cloudio cloudflare dry-run ip-access account|zone update|delete <scope-id> <rule-id>
        \\  cloudio cloudflare dry-run page-rules create <zone-id>|update|edit|delete <zone-id> <rule-id>
        \\  cloudio cloudflare dry-run ua-rules|zone-lockdown create <zone-id>|update|delete <zone-id> <rule-id>
        \\  cloudio cloudflare dry-run page-shield update-settings|create-policy <zone-id>
        \\  cloudio cloudflare dry-run page-shield update-policy|delete-policy <zone-id> <policy-id>
        \\  cloudio cloudflare dry-run custom-pages account|zone update-page <scope-id> <page-id>
        \\  cloudio cloudflare dry-run custom-pages account|zone create-preview-token|create-asset <scope-id>
        \\  cloudio cloudflare dry-run custom-pages account|zone update-asset|delete-asset <scope-id> <asset-name>
        \\  cloudio cloudflare dry-run access-custom-pages create <account-id>|update|delete <account-id> <custom-page-id>
        \\  cloudio cloudflare dry-run access account|zone create-application|update-application|delete-application <scope-id> [application-id]
        \\  cloudio cloudflare dry-run access account|zone create-application-policy|update-application-policy|delete-application-policy <scope-id> <application-id> [policy-id]
        \\  cloudio cloudflare dry-run access account create-reusable-policy|create-tag|update-keys|rotate-keys|start-policy-test|create-idp-federation-grant|create-mtls-certificate|update-mtls-settings <account-id>
        \\  cloudio cloudflare dry-run access account delete-idp-federation-grant|rotate-saml-certificate <account-id> <resource-id>
        \\  cloudio cloudflare dry-run access account create-ca|delete-ca <account-id> <application-id>
        \\  cloudio cloudflare dry-run access zone create-mtls-certificate|update-mtls-settings <zone-id>
        \\  cloudio cloudflare dry-run token create
        \\  cloudio cloudflare dry-run token delete|update|roll <token-id>
        \\  cloudio cloudflare dry-run account create|batch-move
        \\  cloudio cloudflare dry-run account update|delete|move|profile <account-id>
        \\  cloudio cloudflare dry-run membership update|delete <membership-id>
        \\  cloudio cloudflare dry-run account-token create <account-id>
        \\  cloudio cloudflare dry-run account-token delete|update|roll <account-id> <token-id>
        \\  cloudio cloudflare dry-run account-member create <account-id>
        \\  cloudio cloudflare dry-run account-member update|delete <account-id> <member-id>
        \\  cloudio cloudflare dry-run resource-group|user-group create <account-id>
        \\  cloudio cloudflare dry-run resource-group|user-group update|delete <account-id> <resource-id>
        \\  cloudio cloudflare dry-run account-user-group-member create|update <account-id> <user-group-id>
        \\  cloudio cloudflare dry-run account-user-group-member delete <account-id> <user-group-id> <member-id>
        \\  cloudio hostinger vps [list|show <vm-id>|<vm-id>]|metrics <vm-id>|actions <vm-id>|action <vm-id> <action-id>|security <vm-id>|inventory|resources
        \\  cloudio hostinger dry-run vps purchase|start|stop|restart|setup|recreate|start-recovery|stop-recovery|set-hostname|reset-hostname|set-nameservers|set-root-password|set-panel-password [vm-id]
        \\  cloudio hostinger dry-run vps create-ptr|delete-ptr <vm-id> <ip-address-id>
        \\  cloudio hostinger dry-run vps restore-backup <vm-id> <backup-id>
        \\  cloudio hostinger dry-run vps create-snapshot|delete-snapshot|restore-snapshot|install-monarx|uninstall-monarx <vm-id>
        \\  cloudio hostinger dry-run firewall create
        \\  cloudio hostinger dry-run firewall delete|create-rule <firewall-id>
        \\  cloudio hostinger dry-run firewall activate|deactivate|sync <firewall-id> <vm-id>
        \\  cloudio hostinger dry-run firewall update-rule|delete-rule <firewall-id> <rule-id>
        \\  cloudio hostinger dry-run docker create <vm-id>
        \\  cloudio hostinger dry-run docker delete|start|stop|restart|update <vm-id> <project-name>
        \\  cloudio hostinger dry-run public-key create
        \\  cloudio hostinger dry-run public-key attach <vm-id>|delete <public-key-id>
        \\  cloudio hostinger dry-run post-install-script create
        \\  cloudio hostinger dry-run post-install-script update|delete <script-id>
        \\  cloudio hostinger dry-run billing set-default-payment-method|delete-payment-method <payment-method-id>
        \\  cloudio hostinger dry-run billing enable-auto-renewal|disable-auto-renewal <subscription-id>
        \\  cloudio hostinger dry-run dns update|delete|reset|validate <domain>|restore-snapshot <domain> <snapshot-id>
        \\  cloudio hostinger dry-run domain availability|purchase-domain|create-forwarding|create-whois-profile
        \\  cloudio hostinger dry-run domain delete-forwarding|enable-domain-lock|disable-domain-lock|update-nameservers|enable-privacy-protection|disable-privacy-protection <domain>
        \\  cloudio hostinger dry-run domain delete-whois-profile <whois-id>
        \\  cloudio hostinger dry-run hosting create-website|generate-free-subdomain|verify-domain-ownership
        \\  cloudio hostinger dry-run hosting install-wordpress|create-database <username>
        \\  cloudio hostinger dry-run hosting delete-database|change-database-password|repair-database <username> <database>
        \\  cloudio hostinger dry-run hosting create-parked-domain|create-subdomain|create-nodejs-build-from-archive <username> <domain>
        \\  cloudio hostinger dry-run hosting delete-parked-domain|delete-subdomain <username> <domain> <name>
        \\  cloudio hostinger dry-run ecommerce create-store
        \\  cloudio hostinger dry-run horizons create-website
        \\  cloudio hostinger dry-run reach create-segment
        \\  cloudio hostinger dry-run reach delete-contact <contact-uuid>|create-profile-contacts <profile-uuid>
        \\  cloudio hostinger billing-catalog|billing-payment-methods|billing-subscriptions
        \\  cloudio hostinger dns [domain]|dns-snapshots [domain]|dns-snapshot <domain> <snapshot-id>
        \\  cloudio hostinger domains|domain [domain]|domain-forwarding [domain]|whois [tld]|whois-profile <whois-id>|whois-usage <whois-id>
        \\  cloudio hostinger hosting-orders|hosting-websites|hosting-wordpress|hosting-datacenters <order-id>
        \\  cloudio hostinger hosting-databases <username>|hosting-phpmyadmin <username> <database>
        \\  cloudio hostinger hosting-parked-domains <username> <domain>|hosting-subdomains <username> <domain>
        \\  cloudio hostinger hosting-node-builds <username> <domain>|hosting-node-logs <username> <domain> <build-uuid> [from-line]
        \\  cloudio hostinger ecommerce-stores|horizons-website <website-id>
        \\  cloudio hostinger reach-contacts|reach-profiles|reach-segments|reach-segment <segment-uuid>
        \\  cloudio hostinger reach-segment-contacts <segment-uuid>|reach-profile-segment-contacts <profile-uuid> <segment-uuid>
        \\  cloudio hostinger docker <vm-id>|docker-project <vm-id> <name>|docker-containers <vm-id> <name>|docker-logs <vm-id> <name>
        \\  cloudio hostinger data-centers|firewalls|public-keys|templates|post-install-scripts
        \\  cloudio hostinger firewall <id>|template <id>|post-install-script <id>
        \\  cloudio caddy sites|upstreams|render|diff|validate
        \\  cloudio system summary|services|ports|containers|metrics|logs [unit]
        \\  cloudio projects list|show <name>|correlate [--json|--format json]
        \\
    , .{version});
}

fn commandInit(io: Io, gpa: Allocator, cfg: Config, db: *Db) !void {
    _ = db;
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_init.writeText(.{
        .io = io,
        .gpa = gpa,
        .config = cfg,
    }, &out.writer);
    try cli_render.printOwned(io, gpa, &out);
}

fn commandDoctor(io: Io, gpa: Allocator, cfg: Config, db: *Db, args: []const []const u8) !void {
    const format = cli_args.parseFormatOnly(args, error.UnexpectedDoctorArgument) catch |err| {
        std.debug.print("invalid doctor command: {s}\n", .{@errorName(err)});
        return err;
    };
    const ctx: app_doctor.Context = .{
        .io = io,
        .gpa = gpa,
        .version = version,
        .config = cfg,
        .db = db,
    };
    try cli_render.printFormatted(io, gpa, format, app_doctor.writeText, app_doctor.writeJson, .{ctx});
}

fn commandRefresh(io: Io, gpa: Allocator, cfg: Config, db: *Db, args: []const []const u8) !void {
    try app_refresh.run(.{
        .io = io,
        .gpa = gpa,
        .db = db,
        .domains = cfg.domains,
        .cloudflare_auth = cloudflareAuth(cfg),
        .hostinger_token = cfg.hostinger_api_token,
        .caddy_paths = caddyPaths(cfg),
        .projects_root = cfg.projects_root,
        .log = .{
            .version = version,
            .db_path = cfg.db_path,
            .config_path = cfg.config_path,
            .log_path = cfg.log_path,
            .loaded_dotenv = cfg.loaded_dotenv,
            .loaded_fish_env = cfg.loaded_fish_env,
            .cloudflare_auth = cfg.hasCloudflareAuth(),
            .hostinger_auth = cfg.hasHostingerAuth(),
        },
    }, refreshSelectionFromArgs(args));
    try cli_render.writeAll(io, "refresh complete\n");
}

fn commandLog(io: Io, gpa: Allocator, cfg: Config, args: []const []const u8) !void {
    const format = cli_args.parseFormatOnly(args, error.UnexpectedLogArgument) catch |err| {
        std.debug.print("invalid log command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(io, gpa, format, app_log.writeText, app_log.writeJson, .{app_log.Context{
        .io = io,
        .gpa = gpa,
        .path = cfg.log_path,
    }});
}

fn commandExport(io: Io, gpa: Allocator, db: *Db, args: []const []const u8) !void {
    const parsed = parseExportOptions(args) catch |err| {
        std.debug.print("invalid export command: {s}\n", .{@errorName(err)});
        return err;
    };
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    switch (parsed.kind) {
        .snapshots => try app_export.writeRecentSnapshotsJsonWithLimit(gpa, db, parsed.history_options.snapshot_limit, &out.writer),
        .history => try app_export.writeOperationalHistoryJson(gpa, db, parsed.history_options, &out.writer),
    }
    try cli_render.printOwned(io, gpa, &out);
}

fn refreshSelectionFromArgs(args: []const []const u8) app_refresh.Selection {
    if (args.len == 0) return .all();
    var out = app_refresh.Selection.none();
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--all")) return .all();
        if (std.mem.eql(u8, arg, "--cloudflare")) out.cloudflare = true;
        if (std.mem.eql(u8, arg, "--hostinger")) out.hostinger = true;
        if (std.mem.eql(u8, arg, "--caddy")) out.caddy = true;
        if (std.mem.eql(u8, arg, "--system")) out.system = true;
        if (std.mem.eql(u8, arg, "--projects")) out.projects = true;
    }
    return out;
}

fn commandOverview(io: Io, gpa: Allocator, db: *Db, args: []const []const u8) !void {
    const format = parseOverviewFormat(args) catch |err| {
        std.debug.print("invalid overview command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(io, gpa, format, app_overview.writeText, app_overview.writeJson, .{ gpa, db });
}

fn commandHistory(io: Io, gpa: Allocator, db: *Db, args: []const []const u8) !void {
    const parsed = parseHistoryOptions(args) catch |err| {
        std.debug.print("invalid history command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(io, gpa, parsed.format, app_history.writeText, app_history.writeJson, .{ gpa, db, parsed.options });
}

fn parseOverviewFormat(args: []const []const u8) !cli_render.RenderFormat {
    return try cli_args.parseFormatOnly(args, error.UnexpectedOverviewArgument);
}

const ParsedHistoryOptions = struct {
    format: cli_render.RenderFormat = .text,
    options: app_history.Options = .{},
};

fn parseHistoryOptions(args: []const []const u8) !ParsedHistoryOptions {
    var parsed = ParsedHistoryOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingHistoryLimit, error.InvalidHistoryLimit)) |limit| {
            parsed.options.audit_limit = limit;
            parsed.options.snapshot_limit = limit;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{ "--audit-limit", "--audit-events-limit" }, error.MissingHistoryLimit, error.InvalidHistoryLimit)) |limit| {
            parsed.options.audit_limit = limit;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{ "--snapshot-limit", "--snapshots-limit" }, error.MissingHistoryLimit, error.InvalidHistoryLimit)) |limit| {
            parsed.options.snapshot_limit = limit;
            continue;
        }
        return error.UnexpectedHistoryArgument;
    }
    return parsed;
}

const ExportKind = enum {
    snapshots,
    history,
};

const ParsedExportOptions = struct {
    kind: ExportKind = .snapshots,
    history_options: app_history.Options = .{},
};

fn parseExportOptions(args: []const []const u8) !ParsedExportOptions {
    var parsed = ParsedExportOptions{};
    var saw_kind = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        var format = cli_render.RenderFormat.json;
        if (try cli_args.parseFormatOption(args, &index, &format, error.MissingFormat, error.InvalidFormat)) {
            if (format != .json) return error.InvalidExportFormat;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingExportLimit, error.InvalidExportLimit)) |limit| {
            parsed.history_options.audit_limit = limit;
            parsed.history_options.snapshot_limit = limit;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{ "--audit-limit", "--audit-events-limit" }, error.MissingExportLimit, error.InvalidExportLimit)) |limit| {
            parsed.history_options.audit_limit = limit;
            continue;
        }
        if (try cli_args.parsePositiveI64Arg(args, &index, .{ "--snapshot-limit", "--snapshots-limit" }, error.MissingExportLimit, error.InvalidExportLimit)) |limit| {
            parsed.history_options.snapshot_limit = limit;
            continue;
        }
        if (std.mem.eql(u8, args[index], "snapshots")) {
            if (saw_kind) return error.DuplicateExportKind;
            parsed.kind = .snapshots;
            saw_kind = true;
            continue;
        }
        if (std.mem.eql(u8, args[index], "history") or std.mem.eql(u8, args[index], "operational-history")) {
            if (saw_kind) return error.DuplicateExportKind;
            parsed.kind = .history;
            saw_kind = true;
            continue;
        }
        return error.UnexpectedExportArgument;
    }
    return parsed;
}

fn cloudflareAuth(cfg: Config) app_cloudflare.Auth {
    return .{
        .token = cfg.cloudflare_api_token,
        .email = cfg.cloudflare_email,
        .key = cfg.cloudflare_api_key,
    };
}

fn caddyPaths(cfg: Config) app_caddy.Paths {
    return .{
        .caddyfile_path = cfg.caddyfile_path,
        .caddy_sites_path = cfg.caddy_sites_path,
        .caddy_admin_socket = cfg.caddy_admin_socket,
    };
}

test "overview parser supports text and json formats" {
    const no_args = [_][]const u8{};
    try std.testing.expectEqual(cli_render.RenderFormat.text, try parseOverviewFormat(no_args[0..]));

    const json_args = [_][]const u8{"--json"};
    try std.testing.expectEqual(cli_render.RenderFormat.json, try parseOverviewFormat(json_args[0..]));

    const format_args = [_][]const u8{ "--format", "json" };
    try std.testing.expectEqual(cli_render.RenderFormat.json, try parseOverviewFormat(format_args[0..]));

    const inline_format_args = [_][]const u8{"--format=text"};
    try std.testing.expectEqual(cli_render.RenderFormat.text, try parseOverviewFormat(inline_format_args[0..]));

    const invalid_args = [_][]const u8{ "--format", "yaml" };
    try std.testing.expectError(error.InvalidFormat, parseOverviewFormat(invalid_args[0..]));

    const unexpected_args = [_][]const u8{"json"};
    try std.testing.expectError(error.UnexpectedOverviewArgument, parseOverviewFormat(unexpected_args[0..]));
    try std.testing.expectEqual(cli_render.RenderFormat.json, try cli_args.parseFormatOnly(json_args[0..], error.UnexpectedDoctorArgument));
    try std.testing.expectError(error.UnexpectedLogArgument, cli_args.parseFormatOnly(unexpected_args[0..], error.UnexpectedLogArgument));
}

test "history parser supports shared format and limit options" {
    const no_args = [_][]const u8{};
    const defaults = try parseHistoryOptions(no_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);
    try std.testing.expectEqual(@as(i64, app_history.default_audit_limit), defaults.options.audit_limit);
    try std.testing.expectEqual(@as(i64, app_history.default_snapshot_limit), defaults.options.snapshot_limit);

    const json_args = [_][]const u8{ "--json", "--limit", "25" };
    const limited = try parseHistoryOptions(json_args[0..]);
    try std.testing.expectEqual(cli_render.RenderFormat.json, limited.format);
    try std.testing.expectEqual(@as(i64, 25), limited.options.audit_limit);
    try std.testing.expectEqual(@as(i64, 25), limited.options.snapshot_limit);

    const split_args = [_][]const u8{ "--audit-limit=3", "--snapshot-limit", "4" };
    const split = try parseHistoryOptions(split_args[0..]);
    try std.testing.expectEqual(@as(i64, 3), split.options.audit_limit);
    try std.testing.expectEqual(@as(i64, 4), split.options.snapshot_limit);

    const invalid_args = [_][]const u8{ "--limit", "0" };
    try std.testing.expectError(error.InvalidHistoryLimit, parseHistoryOptions(invalid_args[0..]));
    const unexpected_args = [_][]const u8{"raw"};
    try std.testing.expectError(error.UnexpectedHistoryArgument, parseHistoryOptions(unexpected_args[0..]));
}

test "export parser keeps snapshots default and supports history json" {
    const no_args = [_][]const u8{};
    const defaults = try parseExportOptions(no_args[0..]);
    try std.testing.expectEqual(ExportKind.snapshots, defaults.kind);

    const history_args = [_][]const u8{ "history", "--json", "--audit-limit", "5", "--snapshot-limit=6" };
    const history = try parseExportOptions(history_args[0..]);
    try std.testing.expectEqual(ExportKind.history, history.kind);
    try std.testing.expectEqual(@as(i64, 5), history.history_options.audit_limit);
    try std.testing.expectEqual(@as(i64, 6), history.history_options.snapshot_limit);

    const text_args = [_][]const u8{ "history", "--format", "text" };
    try std.testing.expectError(error.InvalidExportFormat, parseExportOptions(text_args[0..]));
    const duplicate_args = [_][]const u8{ "history", "snapshots" };
    try std.testing.expectError(error.DuplicateExportKind, parseExportOptions(duplicate_args[0..]));
}

test "sqlite schema initializes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try app_database.openInitialized(std.testing.io, db_path);
    defer db.close();
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("snapshots"));
}
