# Cloudio HTMX 4 Port Specification

Status: proposed

Scope: authenticated Cloudio web control plane

Implementation branch: `master`

Shared dependency: `web.zig` commit
`1efd187533be1e23b5790a59236b97f0a68aef1a`

HTMX baseline: `v4.0.0-beta6`, commit
`6ca11fbdc881a96c5fbeb0d7094a77183120ea22`

## 1. Outcome

Cloudio will remain a server-rendered Zig application. Every page request will
return a complete and immediately useful control-plane view. HTMX will enhance
navigation, filters, refreshes, mutations, detail panels, and bounded status
polling by requesting server-rendered HTML and swapping the smallest stable
region that owns the changed state.

The port is complete when the page-specific JavaScript data clients are gone,
the JSON API remains stable, and blocking HTMX does not turn an authenticated
page into an empty shell.

This is not a single-page application rewrite. HTMX is transport glue for
HTML; Zig application services, typed view models, server-side rendering,
authentication, and mutation policy remain authoritative.

## 2. Existing baseline

Cloudio already has the most important prerequisite:

- `src/server/pages.zig` renders useful authenticated first views for
  Dashboard, Apps, Routes, DNS, VPS, Docker, Audit, and Security. The planned
  appearance work adds Settings as the ninth page.
- `src/server/pipeline.zig` applies default-deny passkey authentication before
  private pages and APIs.
- `src/server/routes.zig` exposes a stable JSON API for reads and mutations.
- `src/app/*` owns application behavior; HTTP handlers are adapters.
- mutation requests already have origin, CSRF, idempotency, actor, and
  destructive-confirmation policy.
- deploy logs use bounded polling; SSE and WebSockets are intentionally absent.

The remaining frontend scripts re-fetch JSON, create DOM trees, and manually
coordinate page state after a useful server response already exists. The port
removes that duplicated browser renderer.

## 3. Product and engineering principles

The order of priorities is:

1. useful first response and correct server behavior;
2. safe control-plane mutations;
3. user-perceived performance and accessibility;
4. small, local abstractions;
5. reduced JavaScript and dependency count.

Apply YAGNI rigorously:

- no client state store;
- no component framework;
- no virtual DOM;
- no Datastar;
- no SSE or WebSockets;
- no HTMX extensions until a concrete route cannot be implemented with core;
- no generic component DSL;
- no HTTP call from an HTML handler back into Cloudio's own JSON endpoint;
- no new background-job architecture solely for this port;
- no database migration.

## 4. Non-negotiable server-first contract

### 4.1 First response

A normal `GET` to every page route must include:

- the complete authenticated shell and active navigation state;
- the page heading and available controls;
- current server-known data for the primary view;
- useful empty, unavailable, and stale states;
- native links and forms;
- validation constraints and explanatory copy;
- no loading placeholder whose only purpose is to wait for JavaScript.

No first-view information may be fetched with `hx-trigger="load"`. A blocked
HTMX asset may remove inline updates, but it must not remove the initial
information.

### 4.2 Progressive enhancement

Every enhanced link retains an `href`. Every enhanced form retains:

- `method`;
- `action`;
- named controls;
- native HTML validation where possible;
- a submit button;
- a complete non-HTMX response path.

For successful native form mutations, use Post/Redirect/Get with `303 See
Other`. For an HTMX partial mutation, return the newly rendered owning region
directly. Validation failures return the same form/region with submitted values
and field-level errors.

### 4.3 HTML is authoritative

Browser code must not reconstruct tables, cards, notices, badges, deploy rows,
or provider state from JSON. The server renders those components from the same
typed read models used by the first view.

The JSON API remains available for the CLI, automation, diagnostics, and future
non-HTML clients. It is not removed, renamed, or changed to return HTML.

### 4.4 Browser-only islands

Only the following JavaScript remains application-owned:

- WebAuthn/passkey ceremonies;
- the mobile navigation toggle if a CSS/native solution is insufficient;
- a tiny idempotent bridge that reinitializes passkey controls after an HTMX
  swap.

Passkey options and verification continue to use the JSON authentication API
because WebAuthn is a browser API. A successful ceremony may trigger an HTMX
region refresh or full navigation. It must not become a second page renderer.

## 5. Shared HTMX contract

Cloudio will import `web_htmx` from the existing pinned `web.zig` dependency.
Do not create a Cloudio-specific interpretation of HTMX headers.

### 5.1 Asset

Commit the reviewed upstream files:

```text
web/assets/vendor/htmx.min.js
web/assets/vendor/htmx.LICENSE.txt
web/assets/vendor/htmx.version
```

`htmx.version` records the exact version, commit, artifact URL, SHA-256, and
license already declared by `web_htmx`. Add a build/test assertion using
`web_htmx.verifyPinnedAsset`. Production must self-host the asset; no CDN
fallback is allowed.

Serve the asset with:

- `Content-Type: text/javascript; charset=utf-8`;
- a content-hashed query or filename;
- `Cache-Control: public, max-age=31536000, immutable`;
- the existing security headers;
- no authentication-specific content.

Use HTMX core, not `htmax`, and load no extensions.

### 5.2 Request metadata

Parse `web_htmx.Metadata` once in the inbound server pipeline and carry it in
the request context.

The representations are:

| Request | Response |
| --- | --- |
| no `HX-Request` | complete document |
| `HX-Request-Type: full` | complete document |
| `HX-Request-Type: partial` | requested stable component |
| history restore | complete document or the declared history element |

Reject malformed HTMX metadata as `400 Bad Request`; do not silently interpret
an unrecognized request type.

Any URL that varies between complete and partial HTML must send:

```http
Vary: HX-Request-Type
```

Private and mutation responses remain `Cache-Control: no-store`. The `Vary`
header is still required so reverse proxies cannot mix representations.

### 5.3 Configuration

Emit one strict configuration meta tag before the local HTMX script:

```html
<meta
  name="htmx-config"
  content='{"mode":"same-origin","defaultTimeout":15000}'
>
```

Use HTMX 4 attributes and event names. Do not enable implicit inheritance.
Attributes that should apply to descendants use the explicit HTMX 4
`:inherited` form. Do not use `hx-on`, JavaScript-valued `hx-vals`, trigger
filters, or other string-evaluation features.

Long-running deploy requests may set a reviewed per-form timeout. A timed-out
mutation is safe to retry only with the same server-issued idempotency key.

### 5.4 Stable render boundary

Create a small application-owned HTML layer:

```text
src/server/ui/
  routes.zig       # HTML/fragment route table
  handlers.zig     # thin GET and POST adapters
  security.zig     # form origin, CSRF, idempotency, confirmation
  render.zig       # document/component selection and response headers
  components.zig   # shared notices, controls, empty states
```

Page-specific render functions may remain in `src/server/pages.zig` initially,
then be split only when the file becomes harder to review. Do not reorganize
unrelated application or provider modules during this port.

Each component renderer accepts a typed view model and produces the same root
element in full and partial contexts:

```html
<section id="dns-records-region">...</section>
```

The full page calls the component renderer. The fragment route calls that same
renderer. There must not be parallel "initial HTML" and "HTMX HTML" templates.

### 5.5 Response behavior

- `200`: swap the returned success component.
- `202`: only for an operation that is already asynchronous; do not invent a
  queue for this port.
- `204`: successful action with deliberately no visible update.
- `400`: malformed request component.
- `401`: for HTMX, return `200` with `HX-Redirect: /login.html`; for normal
  HTML, retain the login redirect; for JSON, retain JSON `401`.
- `403`: render an authorization/CSRF error in the owning region without
  leaking policy details.
- `409`: render busy/idempotency conflict state.
- `422`: render field validation errors and submitted values.
- `5xx`: render a bounded recovery panel with a native retry link.

HTMX 4 swaps error responses by default. Put explicit `hx-status` behavior on
mutation forms so `422` targets the form region, `409` targets the operation
notice, and `5xx` never replaces the complete shell.

Use `HX-Location` for an in-application HTMX navigation and `HX-Redirect` when
a full browser load is required. Do not send those headers on a `3xx`; HTMX
does not process response commands from redirect responses.

### 5.6 Swaps and multi-region updates

Default to `outerHTML` on one stable owning region. Use:

- one response and one target for ordinary changes;
- `<hx-partial>` only when one mutation truly changes two independently owned
  regions, such as a table and its count;
- `HX-Trigger` only for a semantic refresh event shared by multiple regions.

Do not use out-of-band swaps as a general state propagation mechanism. Do not
return a bag of unrelated fragments.

## 6. Navigation and shell

Apply `hx-boost:inherited="true"` to authenticated shell navigation. A boosted
top-level navigation requests a full representation and replaces the body,
which preserves:

- canonical page URLs;
- normal browser history;
- document titles;
- active navigation state;
- a correct no-JavaScript fallback.

Do not boost:

- `/login.html` and `/setup.html`;
- logout;
- downloads;
- external links;
- WebAuthn ceremony actions.

The Cloudio brand remains an ordinary link to `/` and receives the same boost
behavior as the Dashboard navigation item.

## 7. Security and mutation adapter

The HTML UI route family is separate from `/api/*` so form semantics do not
weaken or complicate the JSON contract.

### 7.1 UI mutation envelope

Unsafe HTML forms submit:

- the existing session cookie;
- a server-rendered CSRF field;
- a server-issued idempotency key;
- an explicit actor value fixed by the server to `web`;
- named domain fields;
- an explicit confirmation field for destructive actions.

`src/server/ui/security.zig` must:

1. allow only the expected same-origin form content types;
2. compare CSRF in constant time;
3. validate the idempotency key using the existing policy;
4. validate explicit confirmation for destructive actions;
5. claim/replay the mutation through `app/writes.zig`;
6. set `write_meta` exactly as the JSON pipeline does.

The form adapter calls the same application service as the JSON handler. It
must not make a loopback HTTP request and must not copy provider/process/SQL
logic.

### 7.2 Confirmation

An `hx-confirm` prompt may improve the enhanced experience but is not the
security boundary. A destructive native form must also require an explicit
named checkbox or typed confirmation control. The server validates it.

Confirmation controls are required for:

- deleting an app;
- applying Caddy configuration;
- deleting a Caddy route;
- deleting DNS records;
- purging cache when classified destructive;
- VPS power actions;
- firewall deletion/synchronization;
- container stop/restart actions as classified;
- passkey revocation when it could remove the last recovery path.

### 7.3 HTML injection boundary

All user, provider, database, process, and log strings continue through
`web_html` text/attribute/url writers. No external string may become:

- an `hx-*` attribute name;
- an HTMX target or selector;
- an HTMX response header;
- trusted HTML.

Deploy log content is text, never executable markup.

## 8. Route and component plan

The exact path names may be adjusted during implementation to match the
router's parameter grammar, but the route families and ownership boundaries
below are required.

### 8.1 Dashboard

Full routes: `/`, `/index.html`

Regions:

- `#dashboard-summary-region`;
- `#dashboard-topology-region`;
- `#dashboard-refresh-state`.

Behavior:

- domain and issues filters remain a native `GET /` form;
- add `hx-get="/"`, target the combined dashboard results region, and push the
  canonical query string;
- debounce text input with HTMX trigger syntax, while Enter/submit retains the
  native path;
- `POST /ui/refresh` runs the existing refresh application service, then
  returns refreshed summary/topology components;
- no automatic whole-dashboard polling in the first port.

Remove JSON-to-DOM rendering from `pages/dashboard.js`.

### 8.2 Apps and deploys

Full route: `/apps.html`

Regions:

- `#apps-region`;
- `#app-create-region`;
- `#app-detail-region`;
- `#app-deploy-history-region`;
- `#app-deploy-log-region`.

HTML routes:

```text
GET  /ui/apps
POST /ui/apps
GET  /ui/apps/:name
POST /ui/apps/:name/deploy
POST /ui/apps/:name/rollback
POST /ui/apps/:name/service
POST /ui/apps/:name/delete
GET  /ui/apps/:name/deploys
GET  /ui/apps/:name/log
```

Behavior:

- app registration is a native/HTMX form;
- selecting an app requests its detail component;
- deploy, rollback, service, and delete return the updated app row/detail;
- deploy history is rendered by the server;
- while the latest deploy status is `running`, the log region uses bounded
  `hx-trigger="every 2s"` polling;
- the terminal log response returns the same component without a polling
  trigger, which stops subsequent requests;
- background tabs and navigation naturally stop polling when the region leaves
  the document;
- log polling remains bounded by existing server limits.

The first implementation does not convert synchronous deployment into a job
queue. The long-running form shows a request indicator and uses idempotent
retry semantics.

Remove table/card/detail/log rendering and manual intervals from
`pages/apps.js`.

### 8.3 Caddy routes

Full route: `/routes.html`

Regions:

- `#caddy-routes-region`;
- `#caddy-route-form-region`;
- `#caddy-preview-region`;
- `#caddy-operation-notice`.

HTML routes:

```text
GET  /ui/caddy/routes
POST /ui/caddy/routes
POST /ui/caddy/routes/:host/toggle
POST /ui/caddy/routes/:host/delete
GET  /ui/caddy/preview
POST /ui/caddy/import
POST /ui/caddy/apply
```

Add, toggle, delete, import, preview, and apply all return server-rendered
components. Preview remains an explicit user action; it is not loaded after
first paint. Apply requires explicit destructive confirmation and refreshes
both preview and route state only if both truly changed.

Remove JSON fetching and DOM assembly from `pages/routes.js`.

### 8.4 DNS

Full route: `/dns.html`

Regions:

- `#dns-records-region`;
- `#dns-record-form-region`;
- `#dns-zone-tools-region`;
- `#dns-operation-notice`.

HTML routes:

```text
GET  /ui/dns/records?domain=...
POST /ui/dns/records
POST /ui/dns/records/update
POST /ui/dns/records/delete
POST /ui/dns/cache/purge
POST /ui/dns/zone-setting
```

The domain selector remains a native GET form and pushes its canonical query
URL when enhanced. Add/edit/delete return the records component and a concise
notice. Zone settings return only the tools component. Cloudflare identifiers
are server data fields, not client-owned state.

Remove record and tool rendering from `pages/dns.js`.

### 8.5 VPS and firewalls

Full route: `/vps.html`

Regions:

- `#vps-machines-region`;
- `#vps-metrics-region`;
- `#firewalls-region`;
- `#firewall-rule-form-region`;
- `#vps-operation-notice`.

HTML routes:

```text
GET  /ui/vps
POST /ui/vps/action
GET  /ui/firewalls
POST /ui/firewalls/rules
POST /ui/firewalls/rules/update
POST /ui/firewalls/rules/delete
POST /ui/firewalls/sync
```

Machine actions replace the affected machine component and derived metrics.
Firewall add/update/delete/sync replaces the owning firewall card or firewall
region. Preserve explicit confirmation for high-impact operations.

Remove provider-state reconstruction from `pages/vps.js`.

### 8.6 Docker

Full route: `/docker.html`

Regions:

- `#containers-region`;
- `#container-log-controls-region`;
- `#container-log-region`;
- `#container-operation-notice`.

HTML routes:

```text
GET  /ui/containers
POST /ui/containers/:name/action
GET  /ui/containers/:name/logs?tail=...
```

Container actions replace the affected row and current log header. Selecting a
container or tail size issues an HTMX GET for escaped text inside the log
component. Logs are never automatically polled in the initial port; the
existing explicit refresh remains.

Remove container/log DOM rendering from `pages/docker.js`.

### 8.7 Audit

Full route: `/audit.html`

Region: `#audit-region`

Behavior:

- limit remains a native `GET /audit.html` form;
- enhanced filter changes target the audit region and push the query URL;
- optional auto-refresh uses `hx-trigger="every 10s"` on the audit region;
- disabling auto-refresh replaces the component with a version that has no
  polling trigger;
- collapse/detail disclosure uses native `<details>` rather than JavaScript.

Remove manual polling and row expansion code from `pages/audit.js`.

### 8.8 Security and passkeys

Full route: `/security.html`

Regions:

- `#passkeys-region`;
- `#security-operation-notice`;
- `#session-region`.

HTML routes:

```text
GET  /ui/security/passkeys
POST /ui/security/passkeys/:id/label
POST /ui/security/passkeys/:id/revoke
POST /ui/logout
```

The passkey list, rename form, revoke result, count, and notices are
server-rendered. WebAuthn creation remains a browser island:

1. JavaScript requests creation options from the JSON auth API.
2. The browser runs `navigator.credentials.create`.
3. JavaScript submits verification to the JSON auth API.
4. On success it dispatches `cloudio:passkeys-changed`.
5. The passkey region declares an HTMX trigger for that event and re-fetches
   server-rendered HTML.

Avoid `window.prompt`; use an ordinary visible label form. Logout is a native
form, enhanced by HTMX only to perform the final redirect.

`/login.html` and `/setup.html` keep their passkey islands and are not converted
into faux no-JavaScript authentication. Their server-rendered instructions,
errors, and bootstrap safety remain intact.

### 8.9 Settings and appearance

Full route: `/settings.html`

Region: `#appearance-settings-region`

The Light/Dark/Device preference and its server-owned cookie contract are
specified in `docs/theme-settings-spec.md`. The native form posts to
`/settings/theme` and remains authoritative.

After the HTMX foundation is available, enhance the same form. A successful
partial request sets the cookie and returns `HX-Refresh: true` because the
theme class lives on the root document element. Do not patch CSS variables or
theme classes with browser code. Validation and CSRF failures target only the
appearance settings region.

Settings does not expose the global provider refresh action and does not add a
page-specific JavaScript file.

## 9. CSS and interaction states

Extend the existing design system only with:

- `.htmx-indicator`;
- `.htmx-request`;
- stable region busy styling;
- inline validation/error styling;
- a reduced-motion-safe swap transition if it measurably helps.

Each request-producing control must:

- expose a visible in-flight state;
- be disabled or synchronized while its request is active;
- retain readable text at 200% zoom;
- keep focus visible;
- return focus to a logical control after replacement.

Use semantic tables, headings, labels, fieldsets, `aria-live="polite"` notices,
and `role="alert"` validation failures. Polling regions must not repeatedly
steal focus or announce unchanged content.

## 10. Performance budgets

- The initial HTML remains one request plus already-required CSS/assets.
- No first-view data request is added.
- HTMX is served compressed and content-hash cached.
- A component request returns only its owning region.
- No component endpoint performs more provider or database work than its full
  page already needs.
- No polling is added except deploy progress and opt-in audit refresh.
- Polling responses may use ETag/conditional reads when easy to implement, but
  this is not required for the first port.
- Remove page-specific JavaScript only after its route family reaches parity;
  do not ship both renderers indefinitely.

## 11. Implementation slices

### Slice 1: foundation

1. Import `web_htmx`.
2. Vendor and verify the exact HTMX asset and license.
3. Add HTMX metadata to the request context.
4. Add full/partial response helpers and `Vary` support.
5. Add the HTML UI route table and shared form-security adapter.
6. Add contract tests before converting a page.

Definition of done:

- normal, HTMX full, HTMX partial, malformed, and history requests are tested;
- auth-expiry behavior is tested;
- JSON API responses are byte/shape compatible;
- asset verification fails on a changed byte.

### Slice 2: read-only interactions

Convert boosted navigation, Dashboard filters, DNS selection, Docker logs,
Audit filters, app details/history, and Caddy preview.

Definition of done:

- all converted routes work with HTMX blocked;
- partial responses contain exactly one documented root region;
- browser history and query strings are correct;
- no converted script fetches JSON or creates data rows.

### Slice 3: low-risk mutations

Convert refresh, app registration, route add/toggle/import, DNS add/update,
firewall add/update, and label/preferences-style changes.

Definition of done:

- native PRG and HTMX fragment paths share the application service;
- validation retains form values;
- CSRF and idempotency rejection tests pass;
- double submission does not duplicate an operation.

### Slice 4: destructive and long-running operations

Convert deploy, rollback, app delete, Caddy apply/delete, DNS delete/cache
purge, VPS actions, firewall delete/sync, container actions, and passkey revoke.

Definition of done:

- confirmation policy is equivalent to or stronger than the JSON API;
- timeout/retry behavior is documented and idempotent;
- deploy progress polling stops at terminal state;
- audit actor/idempotency metadata remains correct.

### Slice 5: remove the old renderer

Delete or reduce:

```text
web/assets/pages/dashboard.js
web/assets/pages/apps.js
web/assets/pages/routes.js
web/assets/pages/dns.js
web/assets/pages/vps.js
web/assets/pages/docker.js
web/assets/pages/audit.js
web/assets/app.js
```

Keep only reviewed passkey/browser-island code. Remove dead DOM helpers, API
wrappers, timers, dialogs, and compatibility paths. Update architecture docs
to describe HTML fragments rather than JSON-to-DOM enhancement.

## 12. Verification matrix

### Unit and contract tests

- `web_htmx.Metadata` integration and malformed header handling;
- normal/full/partial renderer parity from the same typed model;
- exact stable root IDs;
- `Vary: HX-Request-Type`;
- cache policy by public/private/mutation response;
- HTML escaping in every new component;
- origin, CSRF, idempotency, confirmation, and actor policy;
- normal `303` versus HTMX direct fragment;
- HTMX auth redirect versus JSON `401`;
- terminal deploy log removes its poll trigger;
- no JSON API route or response contract changes.

### Browser tests

Run each critical flow in three modes:

1. normal browser with HTMX;
2. JavaScript blocked after an authenticated session exists;
3. throttled low-bandwidth/low-CPU profile.

Cover:

- page navigation and back/forward;
- dashboard and audit filters;
- app register/detail/deploy/log/rollback/delete;
- route add/preview/apply/delete;
- DNS select/add/update/delete/settings;
- VPS and firewall mutations;
- container action and logs;
- passkey add/rename/revoke and logout;
- expired session during a partial request;
- server validation, conflict, and simulated `5xx`.

### Repository gates

The existing gates remain mandatory:

```text
zig build test
zig build architecture-check
zig build deploy-smoke
```

Add an asset/HTML audit that rejects:

- external HTMX URLs;
- an unreviewed HTMX version;
- missing native form actions or link hrefs;
- `hx-on` and JavaScript-valued HTMX attributes;
- `EventSource`, `WebSocket`, Datastar, or new frontend frameworks;
- page scripts that fetch Cloudio data APIs after their route family is ported.

## 13. Deployment and rollback

Deploy slices independently on `master`. For each slice:

1. commit the server renderer, fragment route, tests, and markup together;
2. deploy to production;
3. exercise the native and HTMX paths;
4. inspect redacted server logs and audit events;
5. remove the superseded page script only after parity is proven.

Rollback is application-level:

- remove the HTMX script/config and attributes;
- leave native links/forms and complete documents in place;
- restore the prior page script only for a route family whose native mutation
  path is incomplete.

No database rollback is involved.

## 14. Complete definition of done

The Cloudio port is done only when:

- all nine authenticated pages, including Settings, return complete useful
  first views;
- top-level navigation, filters, detail panels, refreshes, and mutations use
  server-rendered HTML through HTMX when available;
- ordinary links/forms remain the functional baseline;
- the JSON API and CLI remain compatible;
- passkey JavaScript is the only substantial browser-specific application
  island;
- page-specific JSON fetching and DOM construction are removed;
- deploy and audit polling are bounded and HTMX-owned;
- no SSE, WebSocket, Datastar, client store, or frontend framework exists;
- exact HTMX provenance and checksum are enforced;
- auth, CSRF, idempotency, confirmation, and audit policy remain intact;
- accessibility and throttled-network browser checks pass;
- all build, architecture, test, smoke, deployment, and production checks pass;
- documentation describes the implemented state, not the transition.

## References

- [HTMX 4 documentation](https://four.htmx.org/docs)
- [HTMX 4 `HX-Request-Type`](https://four.htmx.org/reference/headers/HX-Request-Type)
- [HTMX 4 `hx-trigger`](https://four.htmx.org/reference/attributes/hx-trigger)
- [HTMX 4 beta 6 release](https://github.com/bigskysoftware/htmx/releases/tag/v4.0.0-beta6)
- [HTMX security guidance](https://four.htmx.org/docs#best-practices)
- [HTMX caching guidance](https://four.htmx.org/docs#caching)
