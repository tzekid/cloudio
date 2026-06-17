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

Each `refresh` writes a redacted `.cloudio/latest-run.log` with collector selection, credential presence, table counts, and the snapshots captured during that refresh.

Useful read-only Cloudflare checks:

```sh
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

Useful read-only Hostinger checks:

```sh
zig build run -- hostinger vps list
zig build run -- hostinger vps show <vm-id>
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
