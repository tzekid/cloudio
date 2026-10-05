# Cloudio

Cloudio is a self-hosted control plane for one VPS and one operator, written
in Zig. It is a single executable with a server-rendered web UI and a small
host CLI. State lives in SQLite.

It manages Caddy routes, Cloudflare DNS records, Hostinger VPS lifecycle,
local Docker containers, Cloudflare Browser Run renders, and project
lifecycles through the `nob.zig` protocol, with an audit trail of every
change. It is not a generic cloud abstraction, a remote Docker manager, or a
replacement for Caddy, systemd, or provider consoles.

## Run it

Use the Zig version pinned in `.zigversion` and system SQLite.

```sh
git submodule update --init
zig build --system zig-pkg
./zig-out/bin/cloudio init
./zig-out/bin/cloudio doctor

CLOUDIO_AUTH_ORIGIN=http://localhost:9331 \
CLOUDIO_AUTH_RP_ID=localhost \
  ./zig-out/bin/cloudio serve --port 9331
```

For the first login, print a one-use enrollment URL and register a passkey:

```sh
./zig-out/bin/cloudio auth bootstrap --ttl 10m
```

Production must use its exact HTTPS origin and relying-party ID.

## Pages

| Page | What it does |
| --- | --- |
| Dashboard | Every host reconciled across DNS, Caddy, sockets, services, containers, and projects, with diagnoses and source freshness |
| Projects | `nob.zig` discovery, trust, prepare, plan, run, cancel, resource controls, and logical secrets |
| Routes | The one Cloudio-owned Caddy fragment: edit desired routes, adopt observed ones, preview, apply with verification and rollback |
| DNS | Records of the configured Cloudflare zones: create, edit, proxy toggle, delete |
| Browser | One-shot Kitesurf HTML renders and PNG screenshots for allowlisted public hosts |
| VPS | Hostinger machines with state-aware start, stop, and restart |
| Docker | Local containers with state-aware lifecycle actions and bounded logs |
| Audit | Read-only history of mutations and control-plane events |
| Security | Passkey enrollment, rename, revoke, and sign-out |
| Settings | Light, Dark, or Device appearance |

Pages render complete HTML on the server. Every change is a native form post.
JavaScript is limited to responsive navigation and the WebAuthn calls on the
login, setup, and Security pages.

Writes are allowed only against a current, successful observation of the exact
target. A failed refresh keeps the last-good data visible and read-only.

## Safety model

Authentication is passkey-only with required user verification. Cloudio
stores public credentials and hashes of sessions and bootstrap tokens. The
session cookie is `__Host-cloudio_session` with `Secure`, `HttpOnly`,
`SameSite=Strict`, path `/`, no Domain attribute, and a fixed 12-hour
lifetime.

Every form post passes one pipeline:

- an authenticated host-only session and an exact `Origin` match;
- a session-bound CSRF token and a closed set of field names;
- a typed confirmation of the exact target for destructive actions; and
- an idempotency key: a repeat with the same body returns the stored result,
  and reuse with different input is rejected.

The actor always comes from the session. The passkey JSON endpoints under
`/api/auth/` are the only other mutation surface; they are rate limited and
require the CSRF header once signed in.

Host-side recovery:

```sh
cloudio auth status
cloudio auth bootstrap --ttl 10m
cloudio auth reset --backup .cloudio/backups/before-auth-reset.db --confirm
```

Reset verifies a new online backup before revoking credentials and sessions.
See [docs/passkey-operations.md](docs/passkey-operations.md).

## Configuration

Configuration lives in the ignored `cloudio.local.toml`:

```toml
db_path = ".cloudio/cloudio.db"
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

[hostinger]
api_token = "..."

[browser_run]
allowed_hosts = "example.com,*.example.org"
state_root = ".cloudio/browser-run"
retention_hours = 24

[storage]
auto_prune = false
backup_root = ".cloudio/backups"
disk_budget_bytes = 0
snapshot_retention_days = 14
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

Credentials may come from `CLOUDFLARE_API_TOKEN` (or `CLOUDFLARE_EMAIL` with
`CLOUDFLARE_API_KEY`) and `HOSTINGER_API_TOKEN` (or `HAPI_API_TOKEN`).
Browser Run requires an API token. Cloudio also reads ignored `.env` and
`.env.fish` files before the process environment; set
`CLOUDIO_DISABLE_ENV_FILES=1` for hermetic runs. `cloudio doctor` reports
resolved paths and capabilities without printing secrets.

## Host CLI

```text
cloudio init                     write a sample config and create the database
cloudio doctor [--json]          check configuration, tools, and paths
cloudio refresh                  observe every source once
cloudio serve [--host] [--port]  run the web UI, scheduler, and project workers
cloudio auth ...                 passkey status, bootstrap, and reset
cloudio maintenance ...          storage status, backup, prune, and compact
cloudio nob ...                  the project lifecycle, as on the Projects page
```

`cloudio help` prints the full grammar.

## Operations

**Refresh.** The server refreshes every `refresh_seconds`; the Dashboard can
refresh on demand. Each source is collected independently: Cloudflare accounts
and the DNS records of configured zones, Hostinger machines, Caddy sites,
listening sockets, systemd services, Docker containers, and projects.

**Routes.** Cloudio owns exactly `caddy_owned_path`, which the root Caddyfile
must import. Only lowercase FQDNs with loopback upstreams are accepted. Apply
validates a candidate, atomically replaces the fragment, reloads through the
admin socket, and verifies the running configuration; any failure restores
and reloads the previous fragment.

**Docker.** Lifecycle actions run as a direct argument vector against an
observed container, then recollect and verify the new state. Image builds,
Compose editing, exec, and remote daemons are out of scope.

**Browser Run.** Runs need an observed Cloudflare account and an allowlisted
public host; private addresses, localhost, credentials in URLs, and non-HTTP
schemes are rejected. Artifacts are private, capped at 8 MiB, and expire after
`retention_hours`. Rendered HTML is shown only as escaped text.

**Storage.** Manual pruning and compaction require a new verified backup.
Scheduled pruning runs only when `storage.auto_prune` is true, and Cloudio
never deletes backups. See [docs/storage-operations.md](docs/storage-operations.md).

**Projects.** `build.zig` stays the build authority; a passive `nob.json` is
safe to discover; a project-owned `src/nob.zig` runner implements actions.
Cloudio owns trust of the exact manifest digest, single-use expiring plans,
approval, workers, cancellation, secret delivery, and independent
observation. See [docs/nob-zig-spec.md](docs/nob-zig-spec.md) and
[vendor/nob/docs/adoption.md](vendor/nob/docs/adoption.md).

## Development

```sh
zig build --system zig-pkg check
tests/setup-browser-e2e.sh
zig build --system zig-pkg -Doptimize=ReleaseSafe release-check
```

`check` builds the executable, runs Cloudio's and both provider packages' unit
tests, and checks page templates and browser scripts. `release-check` adds the
browser acceptance run, which drives every page and form against fake
Cloudflare, Hostinger, Caddy, and Docker, and the host-side passkey recovery
run. It needs Chromium (`CLOUDIO_CHROMIUM_PATH` if not on a standard path).

```text
src/cli/          host command adapters
src/server/       request policy, form pipeline, passkey API, page renderers
src/app/          workflows and page read models
src/collectors/   local observation: Caddy, system, projects
src/db/           migrations and repositories
src/nob/          project protocol and host-control boundaries
src/runtime/      scheduler and project workers
src/http/         bounded HTTP/1.1 server
src/core/         configuration, redaction, process, JSON, time
packages/         standalone Cloudflare and Hostinger Zig clients, mirrored to their own repositories
web/              page templates and browser assets
tests/            browser acceptance and fakes
```

See [docs/architecture.md](docs/architecture.md) for module boundaries.
