# Cloudio

Cloudio is a self-hosted VPS control plane written in Zig. It provides a
server-rendered web UI and a host CLI for Caddy routes, Cloudflare DNS,
Hostinger VPS instances, bounded Cloudflare Browser Run actions, local Docker
containers, reviewed project lifecycles, and operational audit history. Runtime
state is stored in SQLite.

Cloudio intentionally targets one operator and one host. It is not a generic
cloud abstraction, a remote Docker manager, a Compose editor, or a replacement
for Caddy, systemd, provider APIs, or project-owned build logic.

## Run it

Use the pinned Zig version from `.zigversion`.

```sh
zig build --system zig-pkg
./zig-out/bin/cloudio init
./zig-out/bin/cloudio doctor

CLOUDIO_AUTH_ORIGIN=http://localhost:9331 \
CLOUDIO_AUTH_RP_ID=localhost \
  ./zig-out/bin/cloudio serve --port 9331
```

For a local first login:

```sh
./zig-out/bin/cloudio auth bootstrap --ttl 10m
```

Open the one-use URL printed by the command and enroll a passkey. Production
must use its exact HTTPS origin and relying-party ID.

## Product surface

Authenticated pages are rendered with useful first-response HTML. Native
links and forms are the state model. The shared browser script only manages
responsive navigation; Security has a small, page-local WebAuthn and credential
management island.

| Section | Bounded responsibility |
| --- | --- |
| Dashboard | Reconciled DNS, local route, service, project, VPS, and container health |
| Projects | Reviewed `nob.zig` scan, trust, plan, run, rollback, resource, and secret workflows |
| Routes | One Cloudio-owned Caddy fragment with preview, apply, verification, and rollback |
| DNS | Cloudflare DNS observation plus explicitly allowed create, edit, and delete operations |
| Browser | One-shot Kitesurf HTML renders and PNG screenshots for explicitly allowed public hosts |
| VPS | Hostinger VPS observation and capability-checked lifecycle actions |
| Docker | Local container observation, valid lifecycle actions, and bounded log reads |
| Audit | Read-only mutation and operational history |
| Security | Passkey enrollment, rename, revoke, logout, and host-controlled recovery |
| Settings | Server-owned Light, Dark, or Device appearance preference |

The old Apps deployer was removed. Project deployment belongs to the reviewed
`nob.zig` lifecycle, so a second systemd-writing deployment path would create
conflicting ownership. Its empty legacy SQLite tables remain only for existing
database compatibility and will be considered during the planned Turso
cutover.

The canonical HTTP surface is
[docs/http-route-inventory.md](docs/http-route-inventory.md).

## Safety model

Authentication is passkey-only. Cloudio requires user verification and stores
public credentials plus hashes of sessions and bootstrap tokens. Unsafe
authenticated requests require:

- an authenticated host-only session;
- exact-origin validation;
- a session-bound CSRF token;
- an `Idempotency-Key`; and
- `X-Cloudio-Confirm: confirmed` for destructive operations.

The authenticated actor comes from the session. Caller-provided actor headers
are not trusted. A repeated idempotency key returns the original response only
when the request fingerprint matches; conflicting reuse is rejected.

The production session cookie is `__Host-cloudio_session` with `Secure`,
`HttpOnly`, `SameSite=Strict`, path `/`, no Domain attribute, and a fixed
12-hour lifetime.

Host-side authentication operations:

```sh
cloudio auth status
cloudio auth bootstrap --ttl 10m
cloudio auth reset --backup .cloudio/backups/before-auth-reset.db --confirm
```

Reset creates and verifies a new online SQLite backup before revoking
credentials and sessions. It does not silently reopen setup. See
[docs/passkey-operations.md](docs/passkey-operations.md).

## Configuration

Local configuration lives in ignored `cloudio.local.toml`. Common settings:

```toml
db_path = ".cloudio/cloudio.db"
log_path = ".cloudio/latest-run.log"
domains = "example.com"
projects_root = "/srv/projects"

caddyfile_path = "/etc/caddy/Caddyfile"
caddy_sites_path = "/etc/caddy/conf.d/sites.caddy"
caddy_owned_path = "/etc/caddy/conf.d/cloudio.caddy"
caddy_admin_socket = "/run/caddy/admin.socket"

[platform]
refresh_seconds = 300

[auth]
origin = "https://cloudio.example.com"
rp_id = "cloudio.example.com"

[cloudflare]
api_token = "..."

[browser_run]
allowed_hosts = "example.com,*.example.org"
state_root = ".cloudio/browser-run"
retention_hours = 24

[hostinger]
api_token = "..."

[storage]
auto_prune = false
backup_root = ".cloudio/backups"
disk_budget_bytes = 0
snapshot_retention_days = 14
provider_raw_retention_days = 14
metrics_retention_days = 30
maintenance_interval_hours = 24
maintenance_batch_rows = 5000

[nob]
enabled = true
scan_depth = 3
observe_seconds = 300
plan_ttl_seconds = 600
plan_retention_days = 7
operation_retention_days = 30
min_operations_per_project = 20
worker_count = 1
max_run_log_bytes = 67108864
allow_system_mutation = false
```

Credential environment names are `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_EMAIL`, `CLOUDFLARE_API_KEY`, `HOSTINGER_API_TOKEN`, and
`HAPI_API_TOKEN`. `CLOUDIO_AUTH_ORIGIN` and `CLOUDIO_AUTH_RP_ID` override
their auth settings.

Browser Run requires `CLOUDFLARE_API_TOKEN`; legacy email/global-key
authentication is not accepted. `CLOUDIO_BROWSER_RUN_ALLOWED_HOSTS`,
`CLOUDIO_BROWSER_RUN_STATE_ROOT`, and
`CLOUDIO_BROWSER_RUN_RETENTION_HOURS` override the corresponding section.
An empty host allowlist disables the Browser page's actions.

Cloudio also reads ignored `.env` and `.env.fish` files before the process
environment. Set `CLOUDIO_DISABLE_ENV_FILES=1` for hermetic invocations.
`cloudio doctor` reports resolved paths and capability checks without
printing secrets.

## Operator workflows

Run `cloudio help` for the exact command grammar. The stable command families
are:

```text
init          doctor       serve         refresh
dashboard     topology     inventory     history
audit         evidence     actions       export
caddy         cloudflare   hostinger     system
projects      nob          auth          security
maintenance   routes       route         coverage
```

### Caddy routes

Cloudio owns exactly `caddy_owned_path`. The root Caddyfile must import that
file directly or through an exact same-directory `*.caddy` pattern. Cloudio
does not rewrite the root or unmanaged fragments.

Create, edit, enable, disable, adopt, and delete change desired state. Preview
shows the pending diff. Apply validates a sibling temporary fragment, saves the
previous bytes, atomically replaces the owned file, reloads through the
configured admin socket, and verifies the running JSON configuration. A failed
validation, reload, or verification restores and reloads the prior fragment.

```sh
cloudio caddy owned-refresh
cloudio caddy owned-status
cloudio caddy owned-preview
cloudio caddy owned-create app.example.com 127.0.0.1:9000
cloudio caddy owned-delete app.example.com --confirm app.example.com
cloudio caddy owned-apply --confirm APPLY
```

Only lowercase FQDNs and loopback upstreams are accepted. Global options,
arbitrary directives, and hand-maintained sites are outside this workflow.

### Docker

Docker support is local and deliberately narrow. Refresh runs one bounded
`docker ps -a --no-trunc` observation and atomically stores the result. A
failed refresh preserves the last successful inventory, marks it stale, and
disables mutations until capability is proven again.

Start, stop, and restart are exposed only when valid for the observed state.
Cloudio executes a direct argument vector, recollects, verifies the result, and
records one redacted audit action. Log reads require an observed container and
a tail between 1 and 500. Image builds, pulls, Compose editing, exec terminals,
remote daemons, and automatic mutation retries are out of scope.

### Browser Run

The Browser page exposes only rendered HTML and PNG screenshots through
Cloudflare Kitesurf. The engine is selected explicitly and remains visibly
beta; Cloudio never switches to Chromium or retries automatically. A run
requires an observed Cloudflare account and an explicit destination allowlist.
Exact hosts and `*.subdomain` patterns are supported; private/reserved IP
literals, localhost names, URL credentials, and non-HTTP schemes are rejected.

Artifacts are private files below `browser_run.state_root`, bounded to 8 MiB,
and expire after `retention_hours`. Expired files and rows are removed in
bounded batches before the next accepted run. Returned HTML is displayed only
as escaped text and downloaded as an attachment. Cloudio does not accept
cookies, credentials, arbitrary headers, inline HTML, CDP sessions, Puppeteer,
Playwright, or MCP connections through this UI.

### Storage

```sh
cloudio maintenance status
cloudio maintenance backup --output .cloudio/backups/cloudio.db
cloudio maintenance prune --apply --backup .cloudio/backups/before-prune.db
cloudio maintenance run --apply --backup .cloudio/backups/before-maintenance.db
```

Manual pruning and compaction require a new verified backup. Scheduled pruning
is disabled unless `storage.auto_prune` is true. Cloudio never deletes files
under `storage.backup_root`. Read
[docs/storage-operations.md](docs/storage-operations.md) before applying
maintenance or restoring data.

### Projects and `nob.zig`

Cloudio uses a hybrid project lifecycle:

- `build.zig` remains the build and installation source of truth;
- a passive `nob.json` is safe to discover before project code runs;
- a project-owned `src/nob.zig` runner implements project-specific actions;
- Cloudio owns trust, exact-byte plans, approval, persistence, workers,
  cancellation, audit, secret delivery, and independent host observation.

Enrollment is explicit:

```sh
cloudio nob scan
cloudio nob show dev.example.service
cloudio nob trust dev.example.service <manifest-sha256>
cloudio nob prepare dev.example.service
cloudio nob observe dev.example.service
cloudio nob plan dev.example.service check --json
cloudio nob run <plan-id> --yes --follow
```

Trust binds the canonical repository and exact manifest digest. A manifest
change requires review and invalidates ready plans. Plans expire and are
single-use. Interrupted mutations are not automatically retried. System-scope
commands, `sudo`, arbitrary root execution, and generic Compose mutation are
not protocol features.

Repository adoption is documented in
[vendor/nob/docs/adoption.md](vendor/nob/docs/adoption.md); the complete
Cloudio-side contract is [docs/nob-zig-spec.md](docs/nob-zig-spec.md).

### Provider coverage

Checked-in Cloudflare and Hostinger OpenAPI manifests support route review and
safe, explicit generic read planning. They do not authorize generated live
writes, and coverage counts are not product-completion claims.

Normal builds are offline. Upstream spec refresh and drift checks are explicit
networked operations:

```sh
zig build api-summary
zig build coverage-manifest
zig build coverage-check
```

See [docs/provider-coverage.md](docs/provider-coverage.md).

## Development gates

```sh
zig build -l
zig build --system zig-pkg -Doptimize=Debug check
tests/setup-browser-e2e.sh
zig build --system zig-pkg -Doptimize=Debug release-check
zig build --system zig-pkg -Doptimize=ReleaseSafe release-check
```

`check` compiles the executable, runs module tests, checks architectural
boundaries and web structure, and tests both standalone provider packages.
`release-check` adds authenticated browser product acceptance and host-side
recovery acceptance. There is no separate smoke suite: release confidence
comes from the real end-to-end workflows.

## Repository map

```text
src/core/          configuration, redaction, logging, process, time, JSON
src/http/          reusable bounded HTTP/1.1 server
src/server/        route table, security pipeline, pages, thin handlers
src/app/           application workflows and read models
src/db/            migrations, repositories, and current store facade
src/collectors/    external and local observation
src/providers/     generated-route planning and provider-neutral transport
src/nob/           project protocol and host-control boundaries
src/runtime/       scheduler and nob workers
src/cli/           host command adapters
packages/          standalone Cloudflare and Hostinger Zig packages
web/               authored page templates and bounded browser assets
tests/             product and recovery acceptance with controlled fixtures
coverage/          generated provider manifests and reviewed overrides
```

The current architecture and anti-churn rules are in
[docs/architecture.md](docs/architecture.md) and
[docs/cleanup-spec.md](docs/cleanup-spec.md). The protected
[Turso migration draft](docs/turso-migration-spec.md) is the intended next
persistence project after this cleanup; it is not implemented by the current
SQLite code.
