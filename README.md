# Cloudio

Cloudio is a Zig CLI-first POC for reading this VPS control-plane state into SQLite.

The POC is intentionally read-only for infrastructure. It may create or update its own SQLite database, but it does not write Caddy configs, reload services, or mutate Cloudflare/Hostinger resources.

## Quick Start

```sh
zig build
zig build check
zig build run -- init
zig build run -- doctor
zig build run -- refresh --all
zig build run -- overview
zig build run -- overview --json
zig build run -- inventory
zig build run -- log
```

Optional local config lives in `cloudio.local.toml` and is ignored by git:

```toml
db_path = ".cloudio/cloudio.db"
log_path = ".cloudio/latest-run.log"
domains = "plosca.ru sparkdate.love"
projects_root = "/home/kid/Projects"

[cloudflare]
api_token = "cfut_..."
# email = "you@example.com"
# api_key = "legacy-global-key"

[hostinger]
api_token = "hapi_..."
```

Cloudio also auto-loads ignored `.env` and `.env.fish` files before reading process environment. Supported credential names are `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_EMAIL`, `CLOUDFLARE_API_KEY`, `HOSTINGER_API_TOKEN`, and `HAPI_API_TOKEN`.

Each `refresh` writes a redacted `.cloudio/latest-run.log` with collector selection, credential presence, table counts, and the snapshots captured during that refresh. Empty provider response bodies are stored as structured diagnostic JSON with the HTTP status and endpoint so failed reads do not disappear as blank logs.

Central inventory reads join the typed Cloudflare and Hostinger inventory projections without calling live provider APIs:

```sh
zig build run -- inventory
zig build run -- inventory summary
zig build run -- inventory summary hostinger --domain plosca.ru
zig build run -- inventory summary hostinger --format json
zig build run -- inventory hostinger --query plosca.ru --json
zig build run -- inventory cloudflare --domain plosca.ru
zig build run -- inventory hostinger --query plosca.ru --limit 50
```

Generic provider route dispatch:

```sh
zig build run -- route plan cloudflare --operation accounts-list-accounts
zig build run -- route read cloudflare --operation accounts-list-accounts
zig build run -- route capture cloudflare --operation accounts-list-accounts --kind route-cloudflare-accounts --target accounts --paginate --max-pages 5
zig build run -- route plan hostinger --operation VPS_getVirtualMachinesV1
zig build run -- route read hostinger --operation VPS_getVirtualMachinesV1
zig build run -- route capture hostinger --operation VPS_getVirtualMachinesV1 --kind route-hostinger-vps --target vps
zig build run -- route capture hostinger --operation VPS_getPublicKeysV1 --kind route-hostinger-public-keys --target public-keys --paginate --max-pages 5
zig build run -- route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json
zig build run -- route dry-run cloudflare --operation argo-smart-routing-patch-argo-smart-routing-setting --path-param zone_id=<zone-id> --body-content-type application/json
zig build run -- coverage --json
zig build run -- coverage tags cloudflare --json
zig build run -- coverage l1 all --json
zig build run -- coverage capture-candidates cloudflare Logs --limit 10 --json
zig build run -- coverage dry-run-candidates cloudflare "AI Gateway" --limit 10 --json
zig build run -- coverage workplan cloudflare --limit 10 --json
zig build run -- coverage workplan cloudflare --focus control-plane --limit 10 --json
zig build run -- coverage gaps all --limit 12
zig build run -- coverage gaps all --limit 12 --json
zig build run -- coverage levels all
zig build run -- coverage levels all --format json
zig build run -- coverage level-tags all --limit 12
zig build run -- coverage level-tags hostinger --limit 12 --json
zig build run -- coverage families all --limit 12 --json
zig build run -- coverage routes hostinger --method GET --path /api/vps/v1/virtual-machines --json
```

`route plan` never sends HTTP. `route read` executes only generated bodyless `GET`/read routes with the configured provider credentials and prints response metadata without response bodies. `route capture` executes the same safe read path, redacts the response once, stores it in `snapshots` and `provider_raw`, writes a `route.capture` audit event, normalizes stable-ID resource items into `cloudflare_resources` or `hostinger_resources`, updates high-value typed tables for Cloudflare accounts/zones/DNS records and Hostinger VPS when the route shape matches, updates typed Cloudflare and Hostinger inventory rows for stable provider resources, and still prints metadata only. `route capture --paginate` follows generated `page` query parameters for recognized Cloudflare `result_info` and Hostinger `data/meta` page envelopes, and follows generated `cursor` query parameters for recognized Cloudflare cursor envelopes, up to `--max-pages`. Each page is stored as a separate redacted snapshot, normalized resources and typed rows are counted in capture metadata, and cursor token values are redacted from emitted endpoints and audit labels. `route dry-run` renders mutation plans with `will_execute:false`; it validates path/query/header/body metadata but never sends a provider write. `coverage l1` audits the generated manifests for provider-wide L1 routability invariants without calling live APIs. `coverage capture-candidates` does not call provider APIs; it lists generated bodyless `GET` routes that still need L2 capture evidence, required path/query/header placeholders, pagination hints, and a `cloudio route capture ...` command template so whole tag groups can be collected deliberately; `--plans` expands visible candidates with nested generic read plan JSON using schema-compatible example inputs and `will_execute:false`, so broad read families can be reviewed before any live provider read or snapshot capture. `coverage dry-run-candidates` does not call provider APIs; it lists generated non-`GET` mutation routes that still need dry-run review evidence, required path/query/header placeholders, request-body content-type/schema metadata, and a `cloudio route dry-run ...` command template; `--plans` expands visible candidates with nested generic `will_execute:false` plan JSON using schema-compatible example inputs, so an entire mutation family can be reviewed in one no-write bundle. `coverage workplan`, also available as `coverage slice-plan` or `coverage slices`, ranks unresolved provider tag groups and emits the exact `routes`, `capture-candidates`, and `dry-run-candidates` commands needed to review each broad slice; `--focus control-plane` keeps the same evidence scoring while filtering to Cloudio control-plane areas such as accounts, zones, DNS, SSL/TLS, Access, tunnels, rulesets, logs, cache, security posture, tokens, memberships, Hostinger VPS, billing, domains, hosting, Docker, and security surfaces. `--family` applies that shared classifier to workplans, exact routes, capture candidates, and dry-run candidates, so broad slices can be reviewed from summary down to individual operations without tag-string guesswork. `coverage gaps` ranks provider tag groups by unresolved read coverage, permission-blocked reads, and unreviewed mutation dry-runs so future API work can move in broad slices. `coverage levels` summarizes manifest-backed L0/L1/L2 evidence, dry-run review evidence, and L3 projection candidates by provider without treating that summary as final completion proof. `coverage level-tags`, also available as `coverage levels-by-tag` or `coverage evidence`, applies the same evidence accounting per upstream tag group and ranks by pending reads, diagnostic-blocked reads, and pending mutation dry-runs so review can pick whole endpoint families instead of one route at a time. `coverage families`, also available as `coverage family-summary`, rolls those tag rows up to Cloudio control-plane families and emits the matching family workplan command for each broad slice. `coverage routes --json` emits the exact generated route contract, including parameters, request body, responses, security alternatives, support/mode, and tests.
The `coverage summary`, `coverage tags`, `coverage l1`, `coverage capture-candidates`, `coverage dry-run-candidates`, `coverage workplan`, `coverage gaps`, `coverage levels`, `coverage level-tags`, `coverage families`, and `coverage routes` review surfaces accept `--json` or `--format json` for future web/native UI callers without scraping CLI text.

Useful read-only Cloudflare checks:

```sh
zig build run -- cloudflare inventory
zig build run -- cloudflare resources
zig build run -- cloudflare ips
zig build run -- cloudflare ips jdcloud
zig build run -- cloudflare account dns-record-usage <account-id>
zig build run -- cloudflare account user-group-members <account-id> <user-group-id>
zig build run -- cloudflare account user-group-member <account-id> <user-group-id> <member-id>
zig build run -- cloudflare zone plosca.ru
zig build run -- cloudflare zone show <zone-id>
zig build run -- cloudflare zone available-plans <zone-id>
zig build run -- cloudflare zone cache-reserve <zone-id>
zig build run -- cloudflare zone environments <zone-id>
zig build run -- cloudflare zone hold <zone-id>
zig build run -- cloudflare zone subscription <zone-id>
zig build run -- cloudflare secondary-dns acls <account-id>
zig build run -- cloudflare secondary-dns primary-status <zone-id>
zig build run -- cloudflare secondary-dns secondary <zone-id>
zig build run -- cloudflare dns-analytics report <zone-id>
zig build run -- cloudflare dns-firewall list <account-id>
zig build run -- cloudflare dns-firewall analytics bytime <account-id> <dns-firewall-id>
zig build run -- cloudflare load-balancing account monitors <account-id>
zig build run -- cloudflare load-balancing account pool-health <account-id> <pool-id>
zig build run -- cloudflare load-balancing user healthcheck-events
zig build run -- cloudflare load-balancing zone load-balancers <zone-id>
zig build run -- cloudflare health-checks endpoint list <account-id>
zig build run -- cloudflare health-checks endpoint show <account-id> <healthcheck-id>
zig build run -- cloudflare health-checks zone list <zone-id>
zig build run -- cloudflare health-checks zone preview <zone-id> <preview-id>
zig build run -- cloudflare health-checks smart-shield list <zone-id>
zig build run -- cloudflare resource-tags account keys <account-id>
zig build run -- cloudflare resource-tags account resources <account-id> zone
zig build run -- cloudflare resource-tags account values <account-id> managed-by
zig build run -- cloudflare resource-tags zone tags <zone-id> zone <zone-id>
zig build run -- cloudflare rulesets account list <account-id>
zig build run -- cloudflare rulesets account versions <account-id> <ruleset-id>
zig build run -- cloudflare rulesets account entrypoint <account-id> http_request_firewall_custom
zig build run -- cloudflare rulesets zone list <zone-id>
zig build run -- cloudflare rulesets zone show <zone-id> <ruleset-id>
zig build run -- cloudflare rulesets zone rules-by-tag <zone-id> <ruleset-id> <version> <tag>
zig build run -- cloudflare cloudforce-one-rules list <account-id> namespace=yara/workers recursive=true
zig build run -- cloudflare cloudforce-one-rules search <account-id> "proxy worker" mode=hybrid language=yara
zig build run -- cloudflare cloudforce-one-rules stats <account-id>
zig build run -- cloudflare cloudforce-one-rules show <account-id> <rule-id>
zig build run -- cloudflare ip-access user list mode=block target=ip value=198.51.100.4
zig build run -- cloudflare ip-access account list <account-id> notes=attack match=any
zig build run -- cloudflare ip-access account show <account-id> <rule-id>
zig build run -- cloudflare ip-access zone list <zone-id> order=mode direction=desc
zig build run -- cloudflare page-rules list <zone-id>
zig build run -- cloudflare page-rules show <zone-id> <pagerule-id>
zig build run -- cloudflare ua-rules list <zone-id>
zig build run -- cloudflare ua-rules show <zone-id> <ua-rule-id>
zig build run -- cloudflare zone-lockdown list <zone-id>
zig build run -- cloudflare zone-lockdown show <zone-id> <lockdown-id>
zig build run -- cloudflare page-shield settings <zone-id>
zig build run -- cloudflare page-shield policies <zone-id>
zig build run -- cloudflare page-shield connections <zone-id> hosts=cdn.example.com page=all
zig build run -- cloudflare page-shield scripts <zone-id> status=active exclude-cdn-cgi=true
zig build run -- cloudflare page-shield cookies <zone-id> name=session secure=true
zig build run -- cloudflare page-shield policy <zone-id> <policy-id>
zig build run -- cloudflare custom-pages account pages list <account-id>
zig build run -- cloudflare custom-pages account assets show <account-id> <asset-name>
zig build run -- cloudflare custom-pages zone pages list <zone-id>
zig build run -- cloudflare custom-pages zone assets show <zone-id> <asset-name>
zig build run -- cloudflare access-custom-pages list <account-id>
zig build run -- cloudflare access-custom-pages show <account-id> <custom-page-id>
zig build run -- cloudflare access account applications <account-id>
zig build run -- cloudflare access account application <account-id> <app-id>
zig build run -- cloudflare access account application-policies <account-id> <app-id>
zig build run -- cloudflare access account service-tokens <account-id>
zig build run -- cloudflare access account authenticator-aaguids <account-id>
zig build run -- cloudflare access account idp-federation-grants <account-id>
zig build run -- cloudflare access account saml-certificates <account-id>
zig build run -- cloudflare access account scim-update-logs <account-id>
zig build run -- cloudflare access account keys <account-id>
zig build run -- cloudflare access account mtls-certificates <account-id>
zig build run -- cloudflare access account cas <account-id>
zig build run -- cloudflare access zone applications <zone-id>
zig build run -- cloudflare access zone mtls-certificates <zone-id>
zig build run -- cloudflare access zone cas <zone-id>
zig build run -- cloudflare tunnel cfd-tunnels <account-id>
zig build run -- cloudflare tunnel cfd-configurations <account-id> <tunnel-id>
zig build run -- cloudflare tunnel all-tunnels <account-id>
zig build run -- cloudflare tunnel routes <account-id>
zig build run -- cloudflare tunnel route-ip <account-id> 10.0.0.0/24
zig build run -- cloudflare tunnel virtual-networks <account-id>
zig build run -- cloudflare tunnel connectivity-settings <account-id>
zig build run -- cloudflare tunnel hostname-routes <account-id>
zig build run -- cloudflare tunnel subnets <account-id>
zig build run -- cloudflare zero-trust gateway <account-id>
zig build run -- cloudflare zero-trust gateway-configuration <account-id>
zig build run -- cloudflare zero-trust rules <account-id>
zig build run -- cloudflare zero-trust rule <account-id> <rule-id>
zig build run -- cloudflare zero-trust lists <account-id> type=SERIAL
zig build run -- cloudflare zero-trust list-items <account-id> <list-id>
zig build run -- cloudflare zero-trust users <account-id> search=admin
zig build run -- cloudflare zero-trust user-last-seen-identity <account-id> <user-id>
zig build run -- cloudflare security-center account insights <account-id>
zig build run -- cloudflare security-center account severity <account-id> dismissed=false
zig build run -- cloudflare security-center zone insights <zone-id> severity=critical
zig build run -- cloudflare security-center account context <account-id> <issue-id>
zig build run -- cloudflare api-shield discovery-operations <zone-id>
zig build run -- cloudflare api-shield operations <zone-id>
zig build run -- cloudflare api-shield configuration <zone-id>
zig build run -- cloudflare api-shield client-certificates <zone-id>
zig build run -- cloudflare email-routing account addresses <account-id>
zig build run -- cloudflare email-routing zone settings <zone-id>
zig build run -- cloudflare email-routing zone dns <zone-id>
zig build run -- cloudflare email-routing zone rules <zone-id>
zig build run -- cloudflare email-routing zone catch-all <zone-id>
zig build run -- cloudflare email-auth dmarc-reports <zone-id>
zig build run -- cloudflare email-auth spf-inspect <zone-id> <spf-record-id>
zig build run -- cloudflare email-sending account limits <account-id>
zig build run -- cloudflare email-sending zone subdomains <zone-id>
zig build run -- cloudflare email-sending zone subdomain-dns <zone-id> <subdomain-id>
zig build run -- cloudflare email-security settings domains <account-id>
zig build run -- cloudflare email-security settings trusted-domains <account-id>
zig build run -- cloudflare email-security settings allow-policies <account-id>
zig build run -- cloudflare email-security settings blocked-senders <account-id>
zig build run -- cloudflare email-security settings url-ignore-patterns <account-id>
zig build run -- cloudflare security-posture ai-settings <zone-id>
zig build run -- cloudflare security-posture bot-management <zone-id>
zig build run -- cloudflare security-posture content-scanning-settings <zone-id>
zig build run -- cloudflare security-posture leaked-credential-detections <zone-id>
zig build run -- cloudflare audit-logs account <account-id> per-page=10
zig build run -- cloudflare audit-logs account-v2 <account-id> since=2026-06-16T00:00:00Z before=2026-06-17T23:59:00Z limit=10
zig build run -- cloudflare audit-logs user per-page=10
zig build run -- cloudflare logpush account jobs <account-id>
zig build run -- cloudflare logpush zone jobs <zone-id>
zig build run -- cloudflare logpush account dataset-fields <account-id> <dataset-id>
zig build run -- cloudflare log-explorer account datasets <account-id> include_zones=true
zig build run -- cloudflare log-explorer zone available <zone-id>
zig build run -- cloudflare logs-received fields <zone-id>
zig build run -- cloudflare logs-received received <zone-id> start=2026-06-17T00:00:00Z end=2026-06-17T01:00:00Z count=true
zig build run -- cloudflare tls zone certificate-packs <zone-id>
zig build run -- cloudflare tls zone universal-ssl <zone-id>
zig build run -- cloudflare tls zone ssl-verification <zone-id> retry=false
zig build run -- cloudflare tls zone total-tls <zone-id>
zig build run -- cloudflare tls zone custom-ssl <zone-id> status=active
zig build run -- cloudflare tls origin-ca certificates <zone-id>
zig build run -- cloudflare zone argo-analytics <zone-id>
zig build run -- cloudflare zone argo-analytics-colos <zone-id>
zig build run -- cloudflare zone argo-smart-routing <zone-id>
zig build run -- cloudflare zone argo-tiered-caching <zone-id>
zig build run -- cloudflare zone smart-tiered-cache <zone-id>
zig build run -- cloudflare zone origin-post-quantum <zone-id>
zig build run -- cloudflare zone smart-shield <zone-id>
zig build run -- cloudflare zone smart-shield-cache-reserve-clear <zone-id>
zig build run -- cloudflare zone cloud-connector-rules <zone-id>
zig build run -- cloudflare dns plosca.ru
zig build run -- cloudflare dns usage plosca.ru
zig build run -- cloudflare dns show <record-id> plosca.ru
zig build run -- cloudflare dnssec plosca.ru
zig build run -- cloudflare dnssec zsk plosca.ru
zig build run -- cloudflare token
zig build run -- cloudflare token show <token-id>
zig build run -- cloudflare dry-run dns create <zone-id>
zig build run -- cloudflare dry-run dns patch <zone-id> <record-id>
zig build run -- cloudflare dry-run dns delete <zone-id> <record-id>
zig build run -- cloudflare dry-run dns trigger-scan <zone-id>
zig build run -- cloudflare dry-run dnssec edit-status <zone-id>
zig build run -- cloudflare dry-run zone create
zig build run -- cloudflare dry-run zone edit <zone-id>
zig build run -- cloudflare dry-run zone purge-cache <zone-id>
zig build run -- cloudflare dry-run zone purge-environment-cache <zone-id> <environment-id>
zig build run -- cloudflare dry-run zone-lifecycle cache-reserve-change <zone-id>
zig build run -- cloudflare dry-run zone-lifecycle argo-smart-routing-change <zone-id>
zig build run -- cloudflare dry-run zone-lifecycle smart-tiered-cache-create <zone-id>
zig build run -- cloudflare dry-run zone-lifecycle cloud-connector-rules-update <zone-id>
zig build run -- cloudflare dry-run zone-lifecycle environments-update <zone-id>
zig build run -- cloudflare dry-run zone-lifecycle environment-rollback <zone-id> <environment-id>
zig build run -- cloudflare dry-run zone-lifecycle subscription-update <zone-id>
zig build run -- cloudflare dry-run secondary-dns-account acl create <account-id>
zig build run -- cloudflare dry-run secondary-dns-account peer update <account-id> <peer-id>
zig build run -- cloudflare dry-run secondary-dns-zone primary-force-notify <zone-id>
zig build run -- cloudflare dry-run secondary-dns-zone secondary-force-axfr <zone-id>
zig build run -- cloudflare dry-run dns-firewall create <account-id>
zig build run -- cloudflare dry-run dns-firewall update-reverse-dns <account-id> <dns-firewall-id>
zig build run -- cloudflare dry-run dns-settings account <account-id>
zig build run -- cloudflare dry-run dns-settings zone <zone-id>
zig build run -- cloudflare dry-run load-balancing account-monitor create <account-id>
zig build run -- cloudflare dry-run load-balancing account-pool patch-all <account-id>
zig build run -- cloudflare dry-run load-balancing user-monitor preview <monitor-id>
zig build run -- cloudflare dry-run load-balancing zone-load-balancer patch <zone-id> <load-balancer-id>
zig build run -- cloudflare dry-run health-checks endpoint create <account-id>
zig build run -- cloudflare dry-run health-checks zone patch <zone-id> <healthcheck-id>
zig build run -- cloudflare dry-run health-checks preview delete <zone-id> <preview-id>
zig build run -- cloudflare dry-run health-checks smart-shield update <zone-id> <healthcheck-id>
zig build run -- cloudflare dry-run resource-tags account set <account-id>
zig build run -- cloudflare dry-run resource-tags zone delete <zone-id>
zig build run -- cloudflare dry-run rulesets account create <account-id>
zig build run -- cloudflare dry-run rulesets account update-rule <account-id> <ruleset-id> <rule-id>
zig build run -- cloudflare dry-run rulesets zone update-entrypoint <zone-id> http_request_firewall_custom
zig build run -- cloudflare dry-run rulesets zone delete-version <zone-id> <ruleset-id> <version>
zig build run -- cloudflare dry-run cloudforce-one-rules create <account-id>
zig build run -- cloudflare dry-run cloudforce-one-rules update <account-id> <rule-id>
zig build run -- cloudflare dry-run cloudforce-one-rules delete-all <account-id>
zig build run -- cloudflare dry-run ip-access user create
zig build run -- cloudflare dry-run ip-access account update <account-id> <rule-id>
zig build run -- cloudflare dry-run ip-access zone delete <zone-id> <rule-id>
zig build run -- cloudflare dry-run page-rules edit <zone-id> <pagerule-id>
zig build run -- cloudflare dry-run ua-rules update <zone-id> <ua-rule-id>
zig build run -- cloudflare dry-run zone-lockdown delete <zone-id> <lockdown-id>
zig build run -- cloudflare dry-run page-shield update-settings <zone-id>
zig build run -- cloudflare dry-run page-shield create-policy <zone-id>
zig build run -- cloudflare dry-run page-shield update-policy <zone-id> <policy-id>
zig build run -- cloudflare dry-run custom-pages account update-page <account-id> <page-id>
zig build run -- cloudflare dry-run custom-pages zone create-preview-token <zone-id>
zig build run -- cloudflare dry-run custom-pages zone update-asset <zone-id> <asset-name>
zig build run -- cloudflare dry-run access-custom-pages update <account-id> <custom-page-id>
zig build run -- cloudflare dry-run access account create-application <account-id>
zig build run -- cloudflare dry-run access account update-application-policy <account-id> <app-id> <policy-id>
zig build run -- cloudflare dry-run access account rotate-keys <account-id>
zig build run -- cloudflare dry-run access account create-idp-federation-grant <account-id>
zig build run -- cloudflare dry-run access account rotate-saml-certificate <account-id> <saml-cert-set-id>
zig build run -- cloudflare dry-run access account create-mtls-certificate <account-id>
zig build run -- cloudflare dry-run access account create-ca <account-id> <app-id>
zig build run -- cloudflare dry-run access zone create-mtls-certificate <zone-id>
zig build run -- cloudflare dry-run access zone delete-ca <zone-id> <app-id>
zig build run -- cloudflare dry-run token create
zig build run -- cloudflare dry-run token roll <token-id>
zig build run -- cloudflare dry-run account create
zig build run -- cloudflare dry-run account update <account-id>
zig build run -- cloudflare dry-run account batch-move
zig build run -- cloudflare dry-run membership update <membership-id>
zig build run -- cloudflare dry-run membership delete <membership-id>
zig build run -- cloudflare dry-run account-token create <account-id>
zig build run -- cloudflare dry-run account-token roll <account-id> <token-id>
zig build run -- cloudflare dry-run account-member create <account-id>
zig build run -- cloudflare dry-run account-member update <account-id> <member-id>
zig build run -- cloudflare dry-run account-member delete <account-id> <member-id>
zig build run -- cloudflare dry-run resource-group create <account-id>
zig build run -- cloudflare dry-run resource-group update <account-id> <resource-group-id>
zig build run -- cloudflare dry-run user-group create <account-id>
zig build run -- cloudflare dry-run user-group delete <account-id> <user-group-id>
zig build run -- cloudflare dry-run account-user-group-member create <account-id> <user-group-id>
zig build run -- cloudflare dry-run account-user-group-member delete <account-id> <user-group-id> <member-id>
```

Cloudflare Email Sending inventory routes currently require API Email + Global API Key auth in the official schema. Token-only or unauthorized credentials are stored as skipped/permission diagnostics; send operations remain dry-run only.

Useful read-only Hostinger checks:

```sh
zig build run -- hostinger vps list
zig build run -- hostinger vps show <vm-id>
zig build run -- hostinger inventory
zig build run -- hostinger resources
zig build run -- hostinger dry-run vps restart <vm-id>
zig build run -- hostinger dry-run vps start-recovery <vm-id>
zig build run -- hostinger dry-run vps create-ptr <vm-id> <ip-address-id>
zig build run -- hostinger dry-run vps restore-backup <vm-id> <backup-id>
zig build run -- hostinger dry-run vps create-snapshot <vm-id>
zig build run -- hostinger dry-run vps install-monarx <vm-id>
zig build run -- hostinger dry-run firewall create
zig build run -- hostinger dry-run firewall activate <firewall-id> <vm-id>
zig build run -- hostinger dry-run firewall update-rule <firewall-id> <rule-id>
zig build run -- hostinger dry-run docker create <vm-id>
zig build run -- hostinger dry-run docker restart <vm-id> <project-name>
zig build run -- hostinger dry-run docker delete <vm-id> <project-name>
zig build run -- hostinger dry-run public-key create
zig build run -- hostinger dry-run public-key attach <vm-id>
zig build run -- hostinger dry-run public-key delete <public-key-id>
zig build run -- hostinger dry-run post-install-script create
zig build run -- hostinger dry-run post-install-script update <script-id>
zig build run -- hostinger dry-run post-install-script delete <script-id>
zig build run -- hostinger dry-run billing set-default-payment-method <payment-method-id>
zig build run -- hostinger dry-run billing enable-auto-renewal <subscription-id>
zig build run -- hostinger dry-run dns validate plosca.ru
zig build run -- hostinger dry-run dns restore-snapshot plosca.ru <snapshot-id>
zig build run -- hostinger dry-run domain availability
zig build run -- hostinger dry-run domain purchase-domain
zig build run -- hostinger dry-run domain create-forwarding plosca.ru
zig build run -- hostinger dry-run domain delete-forwarding plosca.ru
zig build run -- hostinger dry-run domain update-nameservers plosca.ru
zig build run -- hostinger dry-run domain delete-whois-profile <whois-id>
zig build run -- hostinger dry-run hosting create-website
zig build run -- hostinger dry-run hosting install-wordpress <username>
zig build run -- hostinger dry-run hosting change-database-password <username> <database>
zig build run -- hostinger dry-run hosting delete-parked-domain <username> plosca.ru <parked-domain>
zig build run -- hostinger dry-run hosting create-nodejs-build-from-archive <username> plosca.ru
zig build run -- hostinger dry-run ecommerce create-store
zig build run -- hostinger dry-run horizons create-website
zig build run -- hostinger dry-run reach create-segment
zig build run -- hostinger dry-run reach create-profile-contacts <profile-uuid>
zig build run -- hostinger dry-run reach delete-contact <contact-uuid>
zig build run -- hostinger billing-catalog
zig build run -- hostinger billing-payment-methods
zig build run -- hostinger billing-subscriptions
zig build run -- hostinger domains
zig build run -- hostinger domain plosca.ru
zig build run -- hostinger domain-forwarding plosca.ru
zig build run -- hostinger whois
zig build run -- hostinger whois com
zig build run -- hostinger whois-profile <whois-id>
zig build run -- hostinger whois-usage <whois-id>
zig build run -- hostinger hosting-orders
zig build run -- hostinger hosting-websites
zig build run -- hostinger hosting-wordpress
zig build run -- hostinger hosting-datacenters <order-id>
zig build run -- hostinger hosting-databases <username>
zig build run -- hostinger hosting-phpmyadmin <username> <database>
zig build run -- hostinger hosting-parked-domains <username> <domain>
zig build run -- hostinger hosting-subdomains <username> <domain>
zig build run -- hostinger hosting-node-builds <username> <domain>
zig build run -- hostinger hosting-node-logs <username> <domain> <build-uuid> [from-line]
zig build run -- hostinger ecommerce-stores
zig build run -- hostinger horizons-website <website-id>
zig build run -- hostinger reach-contacts
zig build run -- hostinger reach-profiles
zig build run -- hostinger reach-segments
zig build run -- hostinger reach-segment <segment-uuid>
zig build run -- hostinger reach-segment-contacts <segment-uuid>
zig build run -- hostinger reach-profile-segment-contacts <profile-uuid> <segment-uuid>
zig build run -- hostinger dns plosca.ru
zig build run -- hostinger dns-snapshots plosca.ru
zig build run -- hostinger dns-snapshot plosca.ru <snapshot-id>
zig build run -- hostinger docker <vm-id>
zig build run -- hostinger docker-project <vm-id> <project-name>
zig build run -- hostinger docker-containers <vm-id> <project-name>
zig build run -- hostinger docker-logs <vm-id> <project-name>
zig build run -- hostinger data-centers
zig build run -- hostinger templates
zig build run -- hostinger firewalls
zig build run -- hostinger firewall <firewall-id>
zig build run -- hostinger public-keys
zig build run -- hostinger post-install-scripts
zig build run -- hostinger post-install-script <script-id>
zig build run -- hostinger template <template-id>
```

## Development

- [Architecture target](docs/architecture.md) describes the intended internal library boundaries.
- [Provider coverage baseline](docs/provider-coverage.md) tracks current Cloudflare and Hostinger API coverage against official documentation.
- `zig build api-summary` fetches the current official Cloudflare and Hostinger OpenAPI specs and prints operation/tag counts. It is networked and intentionally separate from normal tests.
