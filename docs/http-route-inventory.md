# Cloudio HTTP route inventory

Status: shipped

Last verified: 2026-08-03

This inventory describes the supported browser and JSON surface. The executable
source of truth is `src/server/routes.zig` for JSON routes and the explicit
allowlist in `src/server/pipeline.zig` for pages, assets, and native forms.
Unknown routes are not compatibility aliases: they return `404` after the
authentication boundary.

## Access and request policy

- Anonymous non-API requests redirect to `/login.html` unless the path is one
  of the public assets below. Anonymous private API requests return `401`
  before route lookup, so they cannot enumerate the private surface.
- Every response uses the shared no-store and security-header policy.
- Every unsafe request requires the configured exact `Origin` and the expected
  content type. Authenticated unsafe requests also require the session CSRF
  value.
- Routes classified as platform mutations require an `Idempotency-Key`.
  Destructive platform mutations additionally require
  `X-Cloudio-Confirm: confirmed`. The actor always comes from the session.
- WebAuthn setup/login/credential routes use single-use ceremony state and the
  authentication service's lifecycle invariants instead of the platform-write
  idempotency store. Theme selection and logout are naturally idempotent native
  session/cookie operations.
- The native forms use strict URL-encoded field allowlists and Post/Redirect/Get.
  Their platform actions generate and submit server-issued idempotency and
  typed confirmation values rather than trusting arbitrary target identity.

## Public browser surface

| Method | Path | Availability |
| --- | --- | --- |
| `GET`, `HEAD` | `/login.html` | Always |
| `GET`, `HEAD` | `/setup.html` | Only while a one-use bootstrap is active |
| `GET`, `HEAD` | `/assets/app.css` | Always |
| `GET`, `HEAD` | `/assets/passkeys.js` | Always |
| `GET`, `HEAD` | `/assets/pages/login.js` | Always |
| `GET`, `HEAD` | `/assets/pages/setup.js` | Only while bootstrap is active |

Public authentication JSON routes:

- `POST /api/auth/setup/options`
- `POST /api/auth/setup/verify`
- `POST /api/auth/login/options`
- `POST /api/auth/login/verify`

They are rate-limited and accept only JSON under the unsafe-request policy.

## Authenticated pages and assets

The authenticated page routes accept `GET` and `HEAD` only:

- `/` and `/index.html` — Dashboard
- `/projects.html` — Projects
- `/routes.html` — Routes
- `/dns.html` — DNS
- `/browser.html` — bounded Cloudflare Kitesurf actions and retained artifacts
- `/vps.html` — VPS
- `/docker.html` — Docker
- `/audit.html` — Audit
- `/security.html` — Security
- `/settings.html` — Settings

The shared `/assets/app.js` enhances responsive navigation only. Security also
loads `/assets/passkeys.js` and `/assets/pages/security.js` for WebAuthn and its
local credential dialog. No page-specific script fetches or renders the
server-owned page data. An authenticated request for `/login.html` redirects
to `/` on the server; the login script does not probe session state at startup.

## Native form routes

All routes below accept authenticated `POST` only:

- `/dashboard/refresh`
- `/projects/scan`
- `/projects/action`
- `/routes/refresh`
- `/routes/route`
- `/routes/adopt`
- `/routes/apply`
- `/dns/refresh`
- `/dns/record`
- `/browser/run`
- `/vps/refresh`
- `/vps/action`
- `/docker/refresh`
- `/docker/action`
- `/settings/theme`
- `/security/logout`

Authenticated Browser Run artifacts use `GET` or `HEAD` on
`/browser/artifact?id=<opaque-run-id>`. Rendered HTML always carries an
attachment disposition; PNG is viewable inline unless `download=1` is set.
Expired artifacts return `410`, and unknown or unsafe identifiers return
`404`.

## Authenticated JSON routes

### Read, session, and credential lifecycle

- `GET /api/dashboard`
- `GET /api/inventory`
- `GET /api/audit`
- `GET /api/auth/session`
- `POST /api/auth/logout`
- `GET /api/auth/credentials`
- `POST /api/auth/credentials/options`
- `POST /api/auth/credentials/verify`
- `PATCH /api/auth/credentials/:id`
- `DELETE /api/auth/credentials/:id`

### Routes

- `GET /api/caddy/routes`
- `POST /api/caddy/routes`
- `DELETE /api/caddy/routes`
- `POST /api/caddy/routes/toggle`
- `GET /api/caddy/preview`
- `POST /api/caddy/refresh`
- `POST /api/caddy/adopt`
- `POST /api/caddy/apply`

### DNS, VPS, Docker, and refresh

- `GET /api/dns/records`
- `POST /api/dns/records`
- `PUT /api/dns/records`
- `DELETE /api/dns/records`
- `GET /api/vps`
- `POST /api/vps/refresh`
- `POST /api/vps/action`
- `GET /api/containers`
- `POST /api/containers/refresh`
- `POST /api/containers/action`
- `GET /api/containers/logs`
- `POST /api/refresh`

### Projects

- `GET /api/nob/projects`
- `GET /api/nob/projects/:id`
- `GET /api/nob/projects/:id/secrets`
- `PUT /api/nob/projects/:id/secrets/:secret`
- `DELETE /api/nob/projects/:id/secrets/:secret`
- `POST /api/nob/scan`
- `POST /api/nob/projects/:id/trust`
- `POST /api/nob/projects/:id/revoke`
- `POST /api/nob/projects/:id/forget`
- `POST /api/nob/projects/:id/prepare`
- `POST /api/nob/projects/:id/observe`
- `POST /api/nob/projects/:id/actions/:action/plan`
- `POST /api/nob/projects/:id/actions/:action/run`
- `POST /api/nob/projects/:id/resources/:resource/:control/plan`
- `POST /api/nob/projects/:id/resources/:resource/:control/run`
- `GET /api/nob/projects/:id/resources/:resource/logs`
- `GET /api/nob/operations`
- `GET /api/nob/operations/:id`
- `GET /api/nob/operations/:id/events`
- `GET /api/nob/operations/:id/log`
- `POST /api/nob/operations/:id/cancel`

## Deliberately absent routes

There is no Apps UI/API, generic deployer, firewall mutation surface, arbitrary
Caddy import/apply surface, or Compose editor. In particular, `/apps.html`,
`/api/apps`, and the former overlapping lifecycle endpoints return `404`.
Maintenance remains a host CLI workflow; the Dashboard exposes only its
read-only storage warning and exact runbook commands.
