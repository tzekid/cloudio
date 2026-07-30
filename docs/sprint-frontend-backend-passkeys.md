# Cloudio frontend, backend, and passkey sprint specification

Status: Milestones 1 and 2 complete; Milestone 3 proposed
Date: 2026-07-30
Product name: Cloudio (`cloudio`)
Current Git remote: `tzekid/claudio`

## 1. Executive decision

This sprint is three sequential milestones:

1. Replace the split frontend with one coherent, compact visual system based on the current DNS, VPS, Docker, and Audit pages.
2. Refactor the backend into a small HTTP server library, thin route handlers, reusable application services, domain repositories, and standalone provider packages that are mirrored to public Git repositories.
3. Replace the platform-token login with passkey-only WebAuthn authentication, short-lived server-side sessions, default-deny authorization, CSRF protection, and a one-time setup flow.

Each milestone must leave the running application deployable. This is not a
big-bang rewrite. Existing endpoint behavior is frozen with tests, moved behind
the new boundary one route group at a time, and deleted from the old location
only after the replacement passes the same tests.

The governing principles are:

- KISS: use plain HTML, CSS, JavaScript, Zig, SQLite, and Caddy. Do not introduce
  a frontend framework, an ORM, a dependency-injection container, or
  microservices.
- YAGNI: build only the abstractions with at least two real callers or one clear
  security boundary. Do not model every upstream API endpoint, add roles for a
  one-user system, or make the repository mirror bidirectional.
- One source of truth: one UI shell, one request wrapper, one server route table,
  one authentication pipeline, and the Cloudio monorepo as the canonical source
  for provider packages.
- Preserve behavior while moving it: structural refactors do not also redesign
  provider behavior or database semantics.
- Delete replaced code promptly. Compatibility shims have an explicit removal
  step in the same milestone.

## 2. Current-state diagnosis

### 2.1 Frontend

The application is a static multi-page interface with seven authenticated pages
and one login page:

- Dashboard: `web/index.html`
- Apps: `web/apps.html`
- Routes: `web/routes.html`
- DNS: `web/dns.html`
- VPS: `web/vps.html`
- Docker: `web/docker.html`
- Audit: `web/audit.html`
- Login: `web/login.html`

The split is concrete:

- Dashboard, Apps, and Routes use `web/assets/app.css` and ask
  `web/assets/app.js` to inject a sidebar, title bar, and content wrapper.
- DNS, VPS, Docker, and Audit each contain their own sidebar markup and between
  30 and 40 lines of inline CSS.
- The preferred DNS/VPS/Docker/Audit style is a compact, GitHub-like dark
  interface with monospace typography, an approximately 180-pixel sidebar,
  padded panels, compact tables, blue accents, and muted secondary text.
- The shared stylesheet currently describes a different shell and visual
  hierarchy.
- Datastar is loaded by every authenticated page but is used only by the Apps
  and Routes create forms.
- Page scripts repeat fetch wrappers, escaping helpers, status helpers, badges,
  table rendering, and error states.
- Many pages construct provider-derived content with HTML strings. Although
  escaping is usually attempted, this is an unnecessary cross-site-scripting
  surface.
- Inline styles, inline scripts, and inline event expressions prevent a strict
  Content Security Policy later.
- The `cloudio` brand in the preferred pages is a non-clickable `div`.

### 2.2 Backend

`src/app/serve.zig` is currently 1,356 lines and owns all of the following:

- TCP listener and thread-per-connection lifecycle
- HTTP request parsing
- response serialization
- static-file serving
- route declaration and matching
- platform-token authentication
- mutation idempotency and destructive confirmation policy
- JSON body/query parsing
- all API adapters
- SSE streams
- refresh scheduling and storage maintenance scheduling
- error-to-HTTP mapping

The route table is a good foundation, but it resolves to an enum and then one
large switch containing every handler. Some handlers call application services;
others query SQLite and manually serialize JSON directly in the HTTP file.

Other backend concentration points are:

- `src/db/store.zig`: approximately 3,500 lines
- `build.zig`: approximately 1,635 lines of manually wired modules
- `src/providers/cloudflare/routes.zig`: approximately 13,000 lines
- `src/providers/cloudflare/client.zig`: a very large re-export facade
- `src/providers/hostinger/routes.zig`: approximately 3,000 lines
- `src/providers/routes.zig`: approximately 1,900 lines of Cloudio-specific
  generated-manifest behavior

The provider clients are not yet standalone libraries. They import Cloudio
modules such as `net_http`, `core_json`, `core_time`, `net_pagination`, and
`provider_typed_routes`.

### 2.3 Existing authentication

Authentication is not absent, but it is not the desired security model:

- A configured platform token gates API routes and authenticated static pages.
- `/api/login`, `/login.html`, and all `/assets/*` files are public.
- A successful login places the platform token itself in the
  `cloudio_token` cookie.
- The cookie is `HttpOnly` and `SameSite=Strict`, but it is not a revocable
  server-side session, has no explicit expiration, and is not marked `Secure`.
- Bearer-token and cookie authentication share the same permanent secret.
- There is no CSRF token, exact-origin enforcement, login rate limit, passkey
  credential lifecycle, or session revocation table.

Milestone 3 replaces this model rather than layering a passkey on top of it.

## 3. Target architecture

```text
Browser
  |
  | HTTPS (terminated by Caddy)
  v
Cloudio server adapter
  route table -> fixed policy pipeline -> domain handler
                         |
                         +-> session / CSRF / idempotency / confirmation
  |
  +-> application use cases
        |
        +-> concrete SQLite repositories
        +-> Cloudflare package
        +-> Hostinger package
        +-> system/Caddy/process adapters

Cloudio monorepo (canonical)
  packages/cloudflare/  --one-way split--> public cloudflare repository
  packages/hostinger/   --one-way split--> public hostinger repository
```

The server-side request pipeline is deliberately fixed rather than implemented
as a generic middleware framework:

```text
parse and bound request
  -> match declared route
  -> authenticate (default required)
  -> validate exact origin and CSRF for unsafe methods
  -> enforce idempotency and destructive confirmation
  -> invoke thin handler
  -> map typed error
  -> attach security headers
  -> write response or SSE stream
```

## 4. Milestone 1: frontend unification

### 4.1 Goal

Every page must look and behave like one product. The chosen visual direction is
the existing DNS/VPS/Docker/Audit direction, refined into a complete responsive
system. Dashboard, Apps, and Routes move to that system; the preferred pages
lose their duplicated inline implementations.

There are no backend endpoint changes in this milestone.

Implementation status: completed on 2026-07-30.

The delivered frontend uses one shared shell, one stylesheet, and one
dependency-free page module per screen. Datastar, inline styles, inline scripts,
duplicated navigation, native `confirm()` calls, and dynamic `innerHTML`
rendering were removed. The shared module now owns safe DOM helpers, request
policy headers, status vocabulary, notifications, responsive navigation, and a
native confirmation dialog. `zig build web-check` enforces the structural
contract and JavaScript syntax.

### 4.2 Design language

Use these characteristics:

- Dark, compact, operational-console presentation
- Monospace-first typography:
  `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`
- Approximately 180-pixel desktop sidebar
- Blue primary accent, green success, amber warning, red danger
- One-pixel neutral borders and six-pixel radii
- Dense tables and forms suitable for infrastructure data
- Clear page heading and optional page-local actions
- Muted secondary text and IDs
- Minimal animation, with `prefers-reduced-motion` respected

`web/assets/app.css` becomes the only authenticated application stylesheet and
owns:

- design tokens
- shell and responsive navigation
- page header
- panels and cards
- tables and overflow wrappers
- forms and validation
- buttons and destructive states
- status pills/badges
- notices, empty states, loading states, and errors
- toasts
- native `dialog` confirmation styling
- logs and code blocks
- login/setup cards
- focus-visible states
- mobile layout

No page may contain a `<style>` block or a `style="..."` attribute after the
milestone.

### 4.3 Shared shell

`web/assets/app.js` remains a small dependency-free shared module. It creates one
shell from a page declaration:

```js
cloudio.mount({
  title: "DNS",
  active: "dns",
  actions: [...]
});
```

The shell contains:

- a single navigation source
- a responsive menu control
- a page heading
- an action slot
- a content mount point
- a toast region
- a dialog region

The brand is an anchor on every authenticated page:

```html
<a class="brand" href="/" aria-label="Cloudio dashboard">cloud<span>io</span></a>
```

Clicking it always navigates to the dashboard. It must be keyboard focusable and
must not use a JavaScript click handler.

The existing global refresh action remains available, but it moves into a
consistent shell action rather than defining a second title-bar style.

### 4.4 JavaScript organization

Target layout:

```text
web/
  index.html
  apps.html
  routes.html
  dns.html
  vps.html
  docker.html
  audit.html
  login.html
  assets/
    app.css
    app.js
    pages/
      dashboard.js
      apps.js
      routes.js
      dns.js
      vps.js
      docker.js
      audit.js
      login.js
```

`app.js` owns only shared behavior:

- shell/navigation mounting
- `api()` request wrapper
- JSON/error normalization
- mutation idempotency header creation
- destructive confirmation header creation
- toasts/notices
- status badge mapping
- time/SHA formatting
- safe DOM construction helpers
- the shared native-dialog confirmation function

Each page module owns its page state and endpoint calls. Provider values, app
names, logs, audit details, and errors must be inserted using `textContent` or
DOM node properties. Dynamic values must not be concatenated into `innerHTML`.
Static table skeletons may remain in HTML.

### 4.5 Remove Datastar

Datastar currently serves only two small form interactions and introduces a
second state/event model. Replace those form bindings with normal
`addEventListener`, `FormData`, and disabled-button state.

Delete:

- `web/assets/datastar.js`
- every Datastar script import
- every `data-signals`, `data-bind-*`, `data-show`, `data-on-*`, and
  `data-attr-*` attribute

No replacement frontend framework is added.

### 4.6 Page-by-page work

#### Dashboard

- Render compact summary cards using the preferred card/panel language.
- Put domain filter, issues-only filter, refresh time, and refresh action in one
  responsive toolbar.
- Wrap the topology table for horizontal scrolling on small screens.
- Use one status badge vocabulary shared with the other pages.
- Preserve automatic refresh/SSE behavior.

#### Apps

- Convert the create form to ordinary DOM events.
- Use the preferred padded-panel treatment instead of split panel headings.
- Keep app actions visually compact and group destructive Delete separately.
- Make deploy history and log detail readable without changing API behavior.
- Use the shared confirmation dialog for rollback, service controls, and delete.
- On mobile, stack app metadata and actions rather than compressing seven table
  columns below readability.

#### Routes

- Convert the create form away from Datastar.
- Align add-route, route list, preview, import, and apply controls with the DNS
  form/table vocabulary.
- Preserve destructive confirmation for apply and delete.
- Render Caddy preview in the shared log/code treatment.

#### DNS

- Remove its inline stylesheet and hand-written shell.
- Use shared buttons, tables, notices, forms, pills, and confirmation dialog.
- Preserve record editing, proxy toggling, cache purge, SSL, and HTTPS controls.
- Make long TXT values wrap or scroll without breaking layout.

#### VPS

- Remove its inline stylesheet and hand-written shell.
- Normalize machine cards, metrics tables, firewall sections, rule forms, and
  action buttons.
- Use the same status colors as Dashboard and Docker.
- Keep potentially destructive VPS/firewall actions visually and behaviorally
  distinct.

#### Docker

- Remove its inline stylesheet and hand-written shell.
- Normalize container selection, actions, log tail controls, and log viewer.
- Preserve row selection and action confirmation.

#### Audit

- Remove its inline stylesheet and hand-written shell.
- Normalize filters, result badges, expandable detail, request detail, actor,
  and idempotency-key presentation.
- Keep long JSON bounded in scrollable code blocks.

#### Login

- Apply the same visual identity without showing authenticated navigation.
- Keep current token behavior until Milestone 3.
- Move its inline script to `assets/pages/login.js`, preparing for a strict CSP.

### 4.7 Responsive and accessibility contract

- Desktop reference widths: 1440 and 1024 pixels.
- Mobile reference widths: 390 and 430 pixels.
- Below the mobile breakpoint, the sidebar becomes a labelled menu/drawer and
  page content uses the full width.
- Tables are placed in an overflow container; the document itself must not
  acquire a horizontal scrollbar.
- Every form control has a label.
- Every icon-only control, if introduced, has an accessible name.
- Focus is visible on anchors, buttons, form controls, rows acting as controls,
  and dialogs.
- Notices and mutation results use an `aria-live` region.
- Color is not the sole status indicator.
- The native dialog traps focus; Escape cancels; the destructive action is not
  the default focused button.

### 4.8 Verification

Add a zero-dependency structural check that fails if an authenticated page
contains:

- inline styles
- inline scripts
- inline event handlers
- Datastar attributes/imports
- a duplicated sidebar/nav
- a missing shared stylesheet, shared script, page script, title, or viewport

This check is implemented as `tools/web-ui-check.mjs` and is wired into both
`zig build web-check` and the main `zig build check` gate.

Run:

- `node --check` on every JavaScript module
- existing Zig/backend tests
- an authenticated HTTP smoke for all seven pages
- manual visual checks at the four reference widths in current Safari and Chrome

The final visual review must include loading, non-empty, empty, error, disabled,
success, and destructive-confirmation states.

### 4.9 Acceptance criteria

- All seven authenticated pages share one shell and one stylesheet.
- Dashboard, Apps, and Routes visibly follow the DNS/VPS/Docker/Audit direction.
- The Cloudio brand is a real link to `/`.
- No inline style/script/event code remains.
- Datastar is removed.
- No provider-derived text is inserted as dynamic HTML.
- Existing reads, writes, confirmations, idempotency headers, and SSE refreshes
  still work.
- Pages remain usable at 390 pixels and with keyboard-only navigation.

### 4.10 Explicit non-goals

- No SPA conversion
- No React/Vue/Svelte/HTMX replacement
- No CSS framework
- No theme switcher
- No new product features or API changes
- No speculative component library published as a package

## 5. Milestone 2: backend and provider-library refactor

### 5.1 Goal

End with:

- a reusable internal HTTP server package containing protocol concerns
- thin, grouped Cloudio HTTP handlers
- authentication and request policy in one fixed pipeline
- schedulers outside the HTTP server
- application logic outside handlers
- concrete, domain-sized SQLite repositories
- standalone Cloudflare and provider-B Zig packages
- public one-way mirror repositories generated from the monorepo packages

The root program, CLI, and web server keep the same behavior during the move.

### 5.2 Provider naming decision

The current repository contains **Hostinger**, not Hetzner, integrations:

- `src/providers/hostinger`
- Hostinger hPanel/VPS routes
- `CLOUDIO_HOSTINGER_API_TOKEN`
- Hostinger tables and collectors

This specification assumes the voice-transcribed “Hetzner” means the existing
Hostinger provider and calls the package `hostinger-zig`. If actual Hetzner
Cloud support is intended, that is a new provider package and cannot be
described as an extraction of the current code. It should be added only after
the extraction pattern is complete. Do not publish a provider-B repository
until this name is confirmed.

### 5.3 Target source layout

```text
packages/
  cloudflare/
    build.zig
    build.zig.zon
    LICENSE
    README.md
    CHANGELOG.md
    src/
      root.zig
      auth.zig
      client.zig
      http.zig
      error.zig
      pagination.zig
      models/
      routes/
    examples/
    tests/
    .github/workflows/test.yml
  hostinger/
    ...same package-level contract...

src/
  core/
  http/
    root.zig
    request.zig
    response.zig
    headers.zig
    router.zig
    server.zig
    static.zig
    sse.zig
  server/
    root.zig
    context.zig
    routes.zig
    pipeline.zig
    errors.zig
    handlers/
      dashboard.zig
      topology.zig
      apps.zig
      caddy.zig
      dns.zig
      vps.zig
      docker.zig
      audit.zig
      refresh.zig
      events.zig
  runtime/
    scheduler.zig
  app/
  integrations/
    cloudflare.zig
    hostinger.zig
  collectors/
  db/
    root.zig
    connection.zig
    migrations.zig
    repositories/
      audit.zig
      deploy.zig
      inventory.zig
      provider.zig
      system.zig
      topology.zig
  cli/
```

Names may be adjusted during implementation, but dependency direction may not.

### 5.4 Internal HTTP library contract

`src/http` contains no imports from Cloudio app, database, provider, collector,
or CLI modules.

It owns:

- bounded HTTP/1.1 request-line, header, and body parsing
- normalized method/path/query access
- case-insensitive header lookup
- path-parameter extraction for literal and `:segment` routes
- 404 versus 405 matching
- buffered JSON/text/file responses
- cookie construction helpers
- status text
- static-file MIME/cache handling
- SSE framing
- connection lifecycle

It does not own:

- Cloudio route paths
- authentication policy
- database handles
- JSON schemas
- provider logic
- application errors
- refresh scheduling

The current thread-per-connection model and `Connection: close` behavior may
remain. Caddy already owns public TLS and HTTP/2/3. Adding an event loop,
keep-alive pool, TLS stack, or generic plugin system is outside this sprint.

### 5.5 Router and handler contract

Replace enum-plus-global-switch dispatch with route records carrying a typed
handler:

```zig
pub const Route = struct {
    method: Method,
    pattern: []const u8,
    access: Access = .authenticated,
    mutation: MutationPolicy = .none,
    response: ResponseKind = .json,
    handler: *const fn (*server.Context, http.Request, http.Params) anyerror!http.Response,
};
```

Exact types can differ, but the semantics remain:

- access is authenticated unless explicitly public
- mutation policy declares idempotency and confirmation requirements
- response kind distinguishes normal and streaming routes
- path parameters replace ad hoc prefix slicing
- the route record points directly to the grouped handler

Handlers:

- parse path/query/body input
- call one application use case
- translate the result to the endpoint response type
- map known domain errors

Handlers do not:

- execute provider HTTP directly
- invoke `systemctl`, Docker, Caddy, or Git directly
- own SQL
- own authentication/session logic
- schedule background work

### 5.6 Fixed request policy pipeline

`src/server/pipeline.zig` applies policy exactly once:

1. Determine the route.
2. Authenticate according to its declared access.
3. Resolve actor identity.
4. For unsafe methods, enforce origin and CSRF policy once Milestone 3 lands.
5. Enforce idempotency for declared mutations.
6. Enforce destructive confirmation for declared destructive mutations.
7. Invoke the handler.
8. Store idempotent success or mapped failure.
9. Apply common response/security headers.

Do not build a general middleware registration framework. There is one Cloudio
pipeline with compile-time route metadata.

### 5.7 Move direct data work out of HTTP

The current HTTP switch directly queries/serializes VPS, firewall, container,
DNS, and audit rows. Add or complete application read models so the server
handlers call app-level functions just as CLI adapters do.

Application modules should return typed results when practical. Existing
streaming writers may stay temporarily for large read models, but they must not
know HTTP status codes, headers, cookies, or routes.

Do not rename every existing app module. Keep modules that already have a clear
single responsibility. Refactor only actual boundary violations and oversized
concentration points.

### 5.8 Split SQLite storage without an ORM

Keep one connection wrapper and append-only migrations. Split `store.zig` into
concrete repository functions by bounded context.

Examples:

- audit/mutation requests
- applications/deployments/operation locks
- provider inventory and raw captures
- topology state/history
- local system/Caddy/project state
- maintenance statistics

Use direct SQL and explicit row structs. Do not add:

- a generic repository interface
- runtime query builders
- active-record models
- a second database

Transactions stay explicit at the use-case boundary.

### 5.9 Simplify the Zig build graph

The current build file registers nearly every file as an individual named
module. Each new package should expose one `root.zig`; internal files use
relative imports.

Target root build responsibilities:

- target/optimization selection
- SQLite translation/linking
- package root imports
- executable/library/test artifacts
- architecture and coverage commands

Move repeated construction into small build helpers. Do not generate `build.zig`
from another tool.

Success guardrails:

- root `build.zig` is small enough to review as build configuration rather than
  an application dependency graph
- package tests can be run from each `packages/*` directory independently
- root tests still exercise integrated behavior

### 5.10 Public provider package contract

Each package must be independently usable by another Zig 0.16 project.

Required public surface:

- `Client`
- provider authentication type
- typed request options for the Cloudio-used endpoint families
- raw request escape hatch for unsupported endpoints
- response/error type
- pagination representation
- selected typed models
- base URL override for tests

Library rules:

- no Cloudio configuration/environment lookup
- no SQLite
- no Cloudio audit or redaction model
- no CLI output
- no global mutable state
- no provider credential in errors or logs
- caller-owned or clearly documented allocations
- no live API calls in default tests
- only documented public exports from `root.zig`

Cloudio-specific generated support status, evidence, dry-run policy, coverage
manifests, and collector normalization remain in the Cloudio monorepo. They are
not part of the provider library's stable API.

### 5.11 Cloudflare package

Refactor the current giant route/client facade into:

- `auth.zig`: API token and legacy email/key authentication
- `client.zig`: request execution and provider-envelope/error handling
- `http.zig`: the minimal `std.http.Client` wrapper required by this standalone
  package
- `pagination.zig`: Cloudflare result-info/cursor envelopes
- `models/`: account, zone, DNS, and other models actually consumed by Cloudio
- `routes/`: endpoint-family files instead of one 13,000-line file
- `root.zig`: the intentionally small stable public API

The first release does not promise typed coverage for all approximately 3,200
official operations. A raw request escape hatch plus typed support for current
Cloudio use cases is sufficient.

### 5.12 Hostinger package

Use the same package-level shape, but keep Hostinger semantics independent:

- bearer token authentication
- hPanel/VPS endpoint families
- Hostinger pagination/envelopes
- VPS, firewall, DNS, hosting, Docker, billing, domain, and related models that
  Cloudio currently consumes

Do not create a shared public provider framework. Two providers with different
authentication, envelopes, and pagination do not justify forcing a generic API.
Small duplicated `std.http` wrappers are preferable to a third public package.

### 5.13 Standalone public Git repositories

Yes, the monorepo can remain the source of truth while each package is also a
normal public repository.

Recommended model:

- Canonical edits happen only under `packages/cloudflare` and
  `packages/hostinger` in Cloudio.
- A GitHub Actions workflow tests the complete monorepo and each package in
  isolation.
- After `master` passes, the workflow creates a history containing only the
  package prefix and pushes it to the corresponding public repository.
- The split repository root contains the package's `build.zig`, source, tests,
  README example, license, and workflow.
- Standalone repositories state clearly that development and pull requests
  happen in the Cloudio monorepo.
- Direct pushes to split-repository `master` are blocked.
- Synchronization is one-way. There is no automatic import of standalone PRs.

One-way is important. Bidirectional subtree synchronization creates ambiguous
ownership, conflict handling, and release ordering without adding product
value.

GitHub documents that a subfolder can be split into a repository while retaining
its relevant history:
https://docs.github.com/en/get-started/using-git/splitting-a-subfolder-out-into-a-new-repository

For ongoing publishing, use a deterministic subtree split of
`packages/<provider>` in CI. The built-in `GITHUB_TOKEN` is scoped to the current
repository. Each public mirror therefore has one unique write-enabled deploy
key whose private half is stored only as an Actions secret on the canonical
repository. An active ruleset blocks ordinary updates, deletion, and force
pushes to `master`; deploy keys are the only publishing bypass. No personal
access token is stored.

### 5.14 Package release flow

- Root tag: `cloudflare-v0.1.0` or `hostinger-v0.1.0`
- Verify the tag commit passes root and isolated package tests.
- Split the tagged package prefix.
- Push the split commit to the standalone repository.
- Create standalone tag `v0.1.0` on that exact split commit.
- Generate release notes from the package changelog.
- Verify a clean temporary Zig project can fetch the tag and compile the README
  example.

Use semantic versioning from the first public release. Pre-1.0 versions may
change APIs, but every change is documented.

### 5.15 Public-release security and licensing gate

The root repository currently has no license file. Before either package becomes
public:

- choose and add an explicit package license
- retain upstream notices where required
- verify generated/OpenAPI-derived material is permitted for redistribution
- do not publish Cloudio `.env`, snapshots, raw provider responses, coverage
  captures, local configuration, or database files
- scan the split working tree and split history for secrets
- inspect all examples/tests for real account IDs, zones, tokens, IPs, and
  private hostnames
- publish only after a clean-room clone builds and tests

### 5.16 Refactor sequence

#### Slice 2.1: freeze contracts

- Record every current HTTP route and policy flag in a test.
- Add golden/structural tests for endpoint status, content type, and top-level
  JSON shape.
- Add local mock-server tests around provider clients.
- No source movement yet.

#### Slice 2.2: create standalone package roots

- Move Cloudflare and Hostinger code under `packages/`.
- Remove upward imports one at a time.
- Make each package build and test alone.
- Switch Cloudio to local package-root imports.
- Keep collector and coverage semantics unchanged.

#### Slice 2.3: extract internal HTTP protocol code

- Move request/response/header/router/static/SSE concerns to `src/http`.
- Keep old handlers delegated from the old server until protocol tests pass.

#### Slice 2.4: split route groups

- Move one coherent route group per change:
  dashboard/topology, apps, Caddy, DNS, VPS/firewalls, Docker, audit, events,
  refresh.
- Add application read models where the old HTTP file currently owns SQL/JSON.
- Delete each old switch arm after its route group is live.

#### Slice 2.5: move runtime scheduling

- Move refresh and retention scheduling to `src/runtime/scheduler.zig`.
- The HTTP server receives a refresh service/event source; it does not own the
  background loop.

#### Slice 2.6: split repositories and simplify build

- Split domain repositories from `db/store.zig`.
- Collapse named-file build wiring behind package roots.
- Delete `src/app/serve.zig` after the last route migrates.
- Slim `src/cloudio.zig` so it does not re-export every provider internals.

#### Slice 2.7: publish

- Add licenses, READMEs, examples, changelogs, isolated CI, secret checks, and
  mirror workflows.
- Bootstrap public repositories.
- Publish `v0.1.0` only after clean-consumer tests.

### 5.17 Backend acceptance criteria

Implementation status (2026-07-30): **complete**. The definition of done is
the checklist below; completion requires the integrated build, all legacy and
new tests, both isolated package builds, authenticated HTTP smoke coverage, and
successful publication from the exact committed package prefixes.

- [x] No application/provider/database imports exist in `src/http`.
- [x] No SQL, provider HTTP, process control, or scheduler loop exists in server
  handlers.
- [x] All routes are declared in one table with direct handler and policy metadata.
- [x] The old global handler switch is gone.
- [x] The old `app/serve.zig` god file is gone.
- [x] Background scheduling is independent of the listener.
- [x] Provider packages build/test from their own directories.
- [x] Provider packages have small documented public roots and no Cloudio imports.
- [x] Cloudio consumes local package sources from the monorepo.
- [x] Public repositories are reproducible one-way mirrors of package directories.
- [x] Public `master` branches reject ordinary pushes and accept only the
  protected mirror workflow.
- [x] `v0.1.0` releases and canonical root tags point to the verified split
  commits, and clean consumer projects compile the README examples.
- [x] Root CLI, server behavior, database schema, and provider behavior remain
  compatible unless a separately documented fix is required.
- [x] The full pre-refactor and new contract suites pass.

Persistence completion is structural, not an ORM: one connection type delegates
to seven concrete SQL repositories, public row models and bind/decoding helpers
are separate, and `db/store.zig` is a small compatibility facade. Existing
method names remain temporarily at the connection edge to avoid a churn-only
rewrite of stable collectors.

### 5.18 Explicit non-goals

- No microservices
- No separate auth service
- No ORM or repository framework
- No generic runtime middleware/plugin system
- No server-side template engine
- No rewrite of stable collectors merely to rename them
- No complete typed implementation of every upstream API
- No common public provider superclass/framework
- No bidirectional repository synchronization
- No new Hetzner implementation unless the provider naming decision confirms it

## 6. Milestone 3: passkey-only security

### 6.1 Goal

The only interactive login mechanism is a passkey:

- Touch ID on a Mac
- Face ID or device passcode on an iPhone/iPad
- a synced passkey provider
- a compatible security key

This is WebAuthn, not “Sign in with Apple.” Apple describes passkeys as public
key credentials used with Face ID or Touch ID:
https://developer.apple.com/passkeys/

Cloudio never receives a fingerprint, face scan, or device passcode. The device
keeps the private key and signs a server challenge. Cloudio stores the public
credential and verifies the signature.

### 6.2 Standards and implementation dependency

Implement against WebAuthn Level 3:
https://www.w3.org/TR/webauthn-3/

WebAuthn requires an HTTPS origin except for `localhost`. The RP ID is a domain,
not a URL or port, and must equal or be a registrable-domain suffix of the
origin. Cloudio must validate the exact expected origin, challenge, RP-ID hash,
credential, user-presence/user-verification flags, and signature.

Do not write WebAuthn cryptographic verification from scratch.

Selected dependency: Passcay 3.1.0, pinned to tag commit
`a448bfa5613b68897e12de11e784a1d7721233a4` and Zig package hash
`passcay-3.1.0-ckLGcmQzBAC1vu-rL_dmObKye8Fbs8qHsFUeDtRAr1ni`. Its public
documentation states Zig 0.16 support, pure `std.crypto`, broad COSE support,
and FIDO2 server conformance:
https://github.com/uzyn/passcay

Adoption review completed on 2026-07-30:

- the exact tag source and MIT license were reviewed
- all 80 upstream tests passed locally and the tagged upstream CI run passed
- Cloudio's adapter adds bounded inputs, cross-origin/top-origin rejection,
  backup-flag consistency, and an ES256/RS256 allowlist around Passcay's exact
  challenge/origin/RP-ID/UP/UV/signature verification
- `zbor` 0.21.2 is pinned solely to read the verified COSE algorithm identifier
- no fork or vendored cryptographic implementation was necessary

### 6.3 Passkey policy

Registration options:

- RP ID: explicit configuration, for example `cloudio.example.com`
- origin: exact explicit HTTPS origin, for example
  `https://cloudio.example.com`
- random opaque 32-byte user handle
- `residentKey: "required"`
- `requireResidentKey: true`
- `userVerification: "required"`
- `attestation: "none"`
- ES256 first, RS256 fallback
- leave `authenticatorAttachment` unset so platform, cross-device, and security
  key authenticators remain usable

Authentication options:

- random 32-byte challenge
- empty `allowCredentials` for username-less/discoverable login
- exact RP ID
- `userVerification: "required"`
- no conditional mediation in the first release

This is a single-user system, but it permits multiple credentials for that one
user so a Mac, iPhone-synced passkey, and hardware security key can coexist.

### 6.4 Database migration

Add append-only migrations for:

```text
auth_users
  id TEXT PRIMARY KEY
  display_name TEXT NOT NULL
  created_at INTEGER NOT NULL

auth_credentials
  credential_id TEXT PRIMARY KEY
  user_id TEXT NOT NULL
  public_key TEXT NOT NULL
  algorithm INTEGER NOT NULL
  sign_count INTEGER NOT NULL DEFAULT 0
  transports TEXT
  aaguid TEXT
  backup_eligible INTEGER
  backup_state INTEGER
  label TEXT
  created_at INTEGER NOT NULL
  last_used_at INTEGER
  revoked_at INTEGER

auth_challenges
  id TEXT PRIMARY KEY
  purpose TEXT NOT NULL
  challenge TEXT NOT NULL
  user_id TEXT
  binding_hash TEXT
  expires_at INTEGER NOT NULL
  used_at INTEGER

auth_sessions
  token_hash TEXT PRIMARY KEY
  user_id TEXT NOT NULL
  csrf_token TEXT NOT NULL
  created_at INTEGER NOT NULL
  expires_at INTEGER NOT NULL
  last_seen_at INTEGER NOT NULL
  revoked_at INTEGER

auth_bootstrap
  id INTEGER PRIMARY KEY CHECK (id = 1)
  token_hash TEXT NOT NULL
  expires_at INTEGER NOT NULL
  created_at INTEGER NOT NULL
  consumed_at INTEGER
```

Opaque binary values are encoded as canonical unpadded base64url text and
token digests as lowercase SHA-256 hex; timestamps are epoch seconds. This
keeps SQLite inspection and the small repository layer straightforward without
changing the security properties. Raw session/bootstrap tokens are never stored.
The session-bound CSRF token may be stored because it cannot authenticate
without the separate HttpOnly session cookie. Challenges are short-lived and
single-use.

### 6.5 One-time bootstrap

There is no permanently open registration page.

An operator with shell access runs:

```text
cloudio auth bootstrap --ttl 10m
```

The command:

1. Refuses if an active credential already exists unless an explicit reset flow
   was used.
2. Generates a cryptographically random 32-byte bootstrap token.
3. Stores only its hash and expiry.
4. Prints a one-time URL such as:
   `https://cloudio.example.com/setup.html#token=<base64url>`
5. Audits bootstrap creation without logging the token.

The token is in the URL fragment, so browsers do not send it in the initial HTTP
request, access logs, or Referer header. Setup JavaScript reads it into memory,
immediately removes it from the visible URL with `history.replaceState`, and
sends it only in a dedicated bootstrap authorization header over HTTPS.

The setup surface is available only when:

- no active passkey credential exists
- an unconsumed bootstrap token exists
- its ten-minute TTL has not expired

Every verification attempt atomically consumes its challenge before expensive
cryptographic verification, so failures cannot be replayed. After successful
verification, credential creation, bootstrap consumption, and first-session
creation happen in one database transaction. Further anonymous setup requests
are removed from the public static allowlist.

An unexpired token is still high entropy; the ten-minute window is not treated
as the security boundary.

### 6.6 Authentication endpoints

Exact names may be adjusted, but the contract is:

```text
POST /api/auth/setup/options    public + valid bootstrap token
POST /api/auth/setup/verify     public + valid bootstrap token
POST /api/auth/login/options    public + rate limited
POST /api/auth/login/verify     public + rate limited
POST /api/auth/logout           authenticated + CSRF
GET  /api/auth/session          authenticated

POST /api/auth/credentials/options   authenticated + CSRF
POST /api/auth/credentials/verify    authenticated + CSRF
GET  /api/auth/credentials            authenticated
PATCH /api/auth/credentials/:id       authenticated + CSRF
DELETE /api/auth/credentials/:id      authenticated + CSRF + confirmation
```

The credential-management endpoints support adding, labelling, and revoking a
second passkey. The web application must refuse to delete the last active
credential.

### 6.7 Registration ceremony

Options:

1. Validate the bootstrap session or authenticated session.
2. Generate a random challenge.
3. Store it with purpose and a five-minute expiry.
4. Return WebAuthn creation options.

Verification:

1. Decode bounded base64url fields.
2. Atomically consume the matching unexpired challenge.
3. Verify `type = webauthn.create`.
4. Verify exact challenge and origin.
5. Verify RP-ID hash.
6. Require user presence and user verification.
7. Verify the returned public key/algorithm are supported.
8. Reject an existing credential ID.
9. Store credential ID, public key, algorithm, sign count, transports, and
   backup metadata.
10. Create or retain the single user.
11. Issue a fresh server-side session.

Attestation is `none`; Cloudio does not identify or allowlist device models.

### 6.8 Authentication ceremony

Options:

1. Apply rate limits.
2. Generate and store a five-minute single-use challenge.
3. Return discoverable-credential request options without a username.

Verification:

1. Decode bounded inputs.
2. Atomically consume the matching challenge.
3. Resolve the credential ID and its single user.
4. Verify `type = webauthn.get`.
5. Verify exact challenge, origin, and RP-ID hash.
6. Require user presence and user verification.
7. Verify the signature against the stored public key.
8. Apply the verifier's sign-counter recommendation and audit anomalies.
9. Update last-used and backup-state metadata.
10. Rotate/create the server-side session.

Synced passkeys may legitimately use a zero/non-incrementing sign counter.
Cloudio follows the verifier's multi-device-aware recommendation rather than
inventing a counter rule.

### 6.9 Sessions and cookies

Production session behavior:

- random 32-byte token
- only SHA-256 token hash stored in SQLite
- fixed 12-hour lifetime
- rotation on every successful login
- revocation on logout, credential reset, or operator reset
- expired/revoked rows rejected and periodically removed

Cookie:

```text
__Host-cloudio_session=<token>;
Path=/;
Secure;
HttpOnly;
SameSite=Strict;
Max-Age=43200
```

Do not set `Domain`. Do not place credential IDs, user data, or authorization
claims in the cookie.

Development may use an insecure cookie only for an explicitly configured
`http://localhost:<port>` or loopback origin. Every other origin must be HTTPS,
and the configured origin host must exactly equal the RP ID.

### 6.10 Authorization coverage

The server route type defaults to authenticated. Public access is an explicit
exception.

Public allowlist:

- `/login.html`
- `/setup.html` only while setup is active
- the minimal CSS/JS needed by those pages
- four setup/login ceremony endpoints

Everything else is authenticated:

- all app HTML
- all app JavaScript/CSS
- every read API
- every mutation API
- all SSE endpoints
- topology, logs, audit, and static assets

Unknown API paths requested without a session return 401 before revealing route
existence. Browser navigation without a session redirects to login.

If a health endpoint is required, bind it to loopback and do not proxy it through
Caddy. It is not a public application route.

Add a test that enumerates every route and fails if the public set differs from
the reviewed allowlist.

### 6.11 CSRF and origin protection

Cookie authentication requires CSRF protection even with `SameSite=Strict`.

- Each session has a random CSRF token.
- `/api/auth/session` returns the raw token to the authenticated same-origin
  application.
- `app.js` adds it as `X-Cloudio-CSRF` on every unsafe method.
- The server compares it with the session-bound stored token in constant time.
- Every unsafe request must also carry an `Origin` header exactly matching the
  configured origin.
- CORS is not enabled.
- Existing idempotency and destructive-confirmation policies remain.

SSE and safe GET/HEAD requests require a valid session but not a CSRF token.
Public setup/login ceremony POSTs require the exact Origin and their
bootstrap/challenge/rate-limit controls, but cannot require a session CSRF token.

### 6.12 Security headers

All responses receive an appropriate subset of:

```text
Content-Security-Policy:
  default-src 'self';
  script-src 'self';
  style-src 'self';
  connect-src 'self';
  img-src 'self' data:;
  object-src 'none';
  base-uri 'none';
  frame-ancestors 'none';
  form-action 'self'

X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Cache-Control: no-store            # auth and API responses
X-Frame-Options: DENY
Cross-Origin-Opener-Policy: same-origin
Permissions-Policy: publickey-credentials-create/get=(self);
                    camera/geolocation/microphone/payment/usb=()
```

Caddy owns HSTS at the HTTPS boundary. Inline scripts/styles were removed in
Milestone 1 specifically so `unsafe-inline` is unnecessary.

### 6.13 Rate limits and audit

Rate-limit login options and verification:

- per remote address
- a small global ceiling suitable for a single-user service
- tighter limits for bootstrap verification

Trust `X-Forwarded-For` only when the server is explicitly bound to loopback;
always retain a separate global ceiling so forwarding-header or address churn
cannot bypass the limiter. Non-proxied operation uses the global ceiling
because the reusable HTTP connection callback intentionally does not expose
application policy.

Audit:

- bootstrap created/expired/consumed
- registration success/failure
- login success/failure
- logout
- credential added/renamed/revoked
- session revoked/reset
- counter anomaly

Do not record challenges, bootstrap tokens, session tokens, CSRF tokens,
credential public keys, signatures, or raw WebAuthn payloads.

### 6.14 Recovery and reset

There is no password, email recovery, recovery question, TOTP fallback, or
permanent bearer-token fallback.

Recovery requires shell access to the host:

```text
cloudio auth reset --backup <new-backup-path> --confirm
cloudio auth bootstrap --ttl 10m
```

Reset:

- creates a verified database backup first
- revokes all sessions
- revokes/removes WebAuthn credentials
- creates no public setup window by itself
- writes an audit event

The UI strongly recommends registering at least two usable passkeys. The last
credential cannot be removed through HTTP.

### 6.15 Rollout

1. Require working HTTPS and freeze the final RP ID/origin.
2. Back up the database.
3. Deploy schema and passkey code with all app routes closed.
4. Run `cloudio auth bootstrap --ttl 10m` over SSH.
5. Open the one-time setup link and register the first passkey.
6. Verify logout and passkey login from the intended Mac/iPhone.
7. Add a second credential if available.
8. Confirm `CLOUDIO_PLATFORM_TOKEN`, the old login endpoint, raw-token cookie,
   bearer-token path, and password input no longer exist.
9. Verify the default-deny route matrix.

There is no indefinite dual-auth period. The local reset/bootstrap commands are
the rollback and recovery mechanism.

### 6.16 Testing

Unit/verification cases:

- valid registration and authentication vectors
- wrong challenge
- replayed challenge
- expired challenge
- wrong origin
- wrong RP ID
- cross-origin client data
- missing user-verification flag
- unknown/revoked credential
- bad signature
- unsupported algorithm
- malformed/truncated CBOR and authenticator data
- bounded oversized fields
- sign-counter anomaly behavior

Session/policy cases:

- missing, expired, revoked, and rotated sessions
- secure cookie attributes
- missing/wrong CSRF
- missing/wrong Origin
- public allowlist exact match
- every authenticated HTML/API/SSE route denied without a session
- login/bootstrap rate limiting
- bootstrap expiration and one-time consumption
- inability to remove the last credential

End-to-end:

- use a browser virtual authenticator to register, log out, log in, call a
  protected API, reject a CSRF-less mutation, and revoke a second credential
- manually verify Safari/macOS Touch ID
- manually verify Safari/iOS passkey or cross-device sign-in
- verify setup is unreachable after registration

### 6.17 Security acceptance criteria

- [x] The platform token is no longer an interactive or API credential.
- [x] Login is passkey-only with user verification required.
- [x] The first credential is enrolled through a 10-minute, high-entropy, one-time
  bootstrap link.
- [x] Cloudio stores no biometric/passcode/private-key material.
- [x] Every non-allowlisted route requires a valid revocable session.
- [x] Every unsafe cookie-authenticated request requires exact Origin and CSRF.
- [x] Session cookies are host-only, Secure, HttpOnly, Strict, expiring, and
  server-side revocable.
- [x] Challenges are unpredictable, single-use, and expiring.
- [x] No inline code is required by CSP.
- [x] SSH reset creates and verifies a backup before credential removal.

### 6.17.1 Definition of done

- [x] Migration 12 is append-only and preserves all existing operational data.
- [x] The reviewed WebAuthn dependency and transitive CBOR parser are exact-pin
  dependencies with third-party notices.
- [x] CLI status, bootstrap, and backup-gated reset workflows are implemented.
- [x] The setup secret is fragment-only in navigation, removed immediately
  from browser history, sent only in a dedicated HTTPS header, and stored only
  as a hash.
- [x] Login, setup, and Security pages match the Milestone 1 design system and
  remain keyboard/mobile/reduced-motion compatible.
- [x] Multiple credentials, labels, revocation, last-credential protection,
  logout, and session revocation are implemented.
- [x] All HTTP, API, static, and SSE surfaces are default-deny except the
  reviewed login/setup allowlist.
- [x] Security headers, exact-origin enforcement, CSRF, one-use challenges,
  rate limits, bounded parsing, and safe audit events are implemented.
- [x] Full integrated checks, production backup/deployment, HSTS, bootstrap,
  and external route verification are complete.
- [ ] A real owner passkey has been enrolled and login/logout verified by the
  operator (requires the operator's biometric/passcode interaction).

### 6.18 Explicit non-goals

- No usernames/passwords
- No “Sign in with Apple” OAuth
- No multi-user registration or roles
- No organization/team model
- No email/SMS/TOTP recovery
- No JWT sessions
- No API/service tokens
- No authenticator attestation allowlist
- No custom WebAuthn cryptography
- No conditional passkey autofill in the first release

## 7. Cross-milestone delivery discipline

### 7.1 Change order

1. Milestone 1 lands and is visually accepted before backend source movement.
2. Milestone 2 freezes HTTP contracts before moving routes.
3. Provider packages build standalone before public repositories are created.
4. The new fixed route policy pipeline exists before passkey work.
5. Milestone 3 lands only with HTTPS/RP configuration and SSH recovery tested.

### 7.2 Change size

Use reviewable vertical slices. A slice moves one behavior completely and deletes
its old path. Avoid a long-lived second implementation.

Suggested checkpoints:

- M1 shell/tokens
- M1 page migrations and Datastar deletion
- M1 responsive/accessibility polish
- M2 provider package roots
- M2 internal HTTP protocol package
- M2 route groups
- M2 repositories/build graph
- M2 public mirrors
- M3 verifier/schema/bootstrap
- M3 sessions/policy
- M3 credential management/hardening
- M3 token removal

### 7.3 Required checks at every checkpoint

- `zig fmt`
- `zig build check`
- `zig build coverage-check` when provider manifests are touched
- `node --check` for frontend JavaScript
- frontend structural check after Milestone 1 starts
- `git diff --check`
- isolated package tests after Milestone 2 starts
- route authorization matrix after Milestone 3 starts

## 8. Sprint definition of done

At the end of the sprint:

- Cloudio has one coherent frontend based on the compact preferred style.
- The brand navigates to the dashboard.
- There is one frontend shell, stylesheet, API wrapper, and confirmation path.
- Datastar and duplicate page CSS/JS are gone.
- HTTP protocol code is isolated from Cloudio domain code.
- Route policy is declared once and applied by one fixed pipeline.
- Handlers are small adapters; app services and repositories own behavior/data.
- Refresh/maintenance scheduling is not part of the HTTP listener.
- Cloudflare and current provider-B code are standalone Zig packages inside the
  monorepo.
- The package directories are reproducibly mirrored to public repositories.
- The only interactive authentication is a passkey.
- A one-time ten-minute bootstrap creates the first passkey.
- Every sensitive route is default-deny and session protected.
- Unsafe requests have CSRF, Origin, idempotency, and destructive-confirmation
  controls as applicable.
- The old permanent-token login path is deleted.

## 9. Primary references

- W3C WebAuthn Level 3:
  https://www.w3.org/TR/webauthn-3/
- Apple Passkeys:
  https://developer.apple.com/passkeys/
- FIDO Alliance Passkeys:
  https://fidoalliance.org/passkeys/
- Candidate Zig RP verifier, Passcay:
  https://github.com/uzyn/passcay
- GitHub subfolder splitting:
  https://docs.github.com/en/get-started/using-git/splitting-a-subfolder-out-into-a-new-repository
- GitHub App authentication across repositories:
  https://docs.github.com/en/enterprise-cloud@latest/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow
