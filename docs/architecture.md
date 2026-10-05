# Cloudio architecture

Cloudio is one Zig executable: a server-rendered web UI, a host CLI,
background work, and SQLite. It is built for auditable operator workflows on
one host, not for reuse as a framework.

## Modules

`build.zig` declares one module rooted at `src/main.zig`; source files import
each other by relative path. External dependencies are SQLite (translated C),
`passcay` and `zbor` for WebAuthn, `web_html` for escaping, the `nob` SDK, and
the two provider packages.

```text
cli ─────────┐
server ──────┼──> app ──> collectors ──> db ──> core
runtime ─────┘      └───> packages/cloudflare, packages/hostinger
```

- `src/cli` parses arguments and prints results; it calls `app`.
- `src/server` is the HTTP adapter: request policy, forms, the passkey API,
  and page renderers. It calls `app`.
- `src/runtime` holds the refresh scheduler and project workers.
- `src/app` owns workflows and read models. A module exists when it owns a
  workflow or a policy boundary, not to shorten a file.
- `src/collectors` turns local host state into database rows.
- `src/db` owns migrations and SQL; `core` and `http` know nothing about
  Cloudio policy.
- `packages/cloudflare` and `packages/hostinger` are standalone libraries
  that own provider transport, routes, and response parsing. They are
  mirrored to their own repositories.

## Requests

`src/server/pipeline.zig` is the only request-policy boundary. It reads the
session, enforces the anonymous allowlist, and dispatches to:

- **pages**: `pages.zig` loads the authored `<main>` from `web/*.html`, the
  matching renderer in `server/pages/` splices in escaped data from an app
  read model, and the result is wrapped in one authenticated shell;
- **forms**: `forms.zig` runs every native form post through origin, field
  allowlist, CSRF, typed confirmation, and an idempotency claim, then either
  redirects (`303`) or re-renders the page with the outcome and status;
- **the passkey API**: `api.zig` serves the eight WebAuthn JSON endpoints the
  login, setup, and Security scripts call; and
- **static assets** and the Browser Run artifact download.

`common.zig` maps application errors to one HTTP status and stable code used
by both forms and the passkey API. Each page turns codes into feedback text.

The browser boundary is small: `app.js` toggles navigation, and the login,
setup, and Security scripts own WebAuthn ceremonies. There is no client-side
state, startup fetch, or polling.

## Observation

`app/refresh.zig` collects every source the pages read: Cloudflare accounts
and the DNS records of configured zones, Hostinger machines, Caddy sites,
sockets, services, containers, and projects. Each source records its attempt;
`app/observation.zig` derives freshness from those attempts.

A failed refresh never manufactures an empty healthy state. Last-good rows
stay visible, and writes require a current, successful observation of the
exact target. After a write, Cloudio recollects and confirms the new state,
or reports that the provider accepted it without confirmation.

External processes run as direct argument vectors with bounded output and
time. Secrets are redacted before anything is stored or logged.

## Writes

Product writes are a fixed set: Cloudflare DNS records
(`app/provider_writes.zig`), Hostinger VPS start, stop, and restart, local
Docker lifecycle (`app/system_control.zig`), the owned Caddy fragment
(`app/caddy_desired.zig`), Browser Run renders, and project operations. Each
records one audit row through `app/writes.zig`, which also holds the
idempotency store behind form replays.

## Persistence

`src/db/schema.zig` owns ordered migrations; SQL lives in
`src/db/repositories`. The database holds observations, DNS, VPS, Caddy,
service, socket, container, and project rows, audit events, idempotency
records, authentication state, desired Caddy state, Browser Run metadata, and
`nob.zig` lifecycle records. Browser artifacts and project operation state are
private files outside SQLite. Retention and backup are described in
`docs/storage-operations.md`.

## Projects

The `nob.zig` lifecycle has three layers:

1. A passive `nob.json` is discovered and reviewed without running project
   code.
2. Trust binds the canonical source identity and exact manifest digest before
   a runner is built.
3. Mutations need an expiring exact plan, approval, a persisted worker
   operation, and independent host observation.

The project runner owns project-specific behavior. Cloudio owns isolation,
secret delivery, idempotency, events, audit, cancellation, and narrow one-use
systemd and Caddy capabilities. The contract is `docs/nob-zig-spec.md`.

## Tests

1. `release-check` drives every page and form in Chromium against fake
   Cloudflare, Hostinger, Caddy, and Docker, then exercises host-side passkey
   recovery.
2. SQLite and provider tests cover persistence, parsing, and failure handling.
3. Module tests cover parsers, security invariants, and state machines.
4. `tools/web-ui-check.mjs` checks what the browser cannot: labelled controls,
   CSP-safe templates, and script syntax.

`src/main.zig` lists every file that contains tests; a single-module build
only runs tests from files a test block references.

## Change rules

A new abstraction, route, configuration field, fallback, or test needs a
current consumer and a failure it prevents. Prefer one owner per policy,
server-owned state and native forms, explicit capability errors over
optimistic fallback, and end-to-end proof for user workflows. Remove schema
only with a backed-up migration.
