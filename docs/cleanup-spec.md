# Cloudio anti-churn cleanup specification

Status: completed and release-qualified, 2026-08-03.

Historical record: the September simplification pass retires source-name and
filename scans and consolidates provider test ownership. Current verification
commands are in the README; the checks listed below describe the August pass.

This document records what the anti-churn pass removed, what it deliberately
kept, and the evidence required before another cleanup expands scope. It is not
a rolling roadmap. Completed implementation plans are deleted rather than
maintained as parallel sources of truth.

## Outcome

Cloudio has one current product surface:

```text
Dashboard
Projects
Routes
DNS
VPS
Docker
Audit
Security
Settings
```

Apps is retired. Docker remains a supported, local-only product section.
Project deployment has one owner: the reviewed `nob.zig` lifecycle.

Current implementation and operations are described by `README.md`,
`docs/architecture.md`, the HTTP inventory, and the focused runbooks. The
Turso migration draft is preserved as the next persistence project.

## Product section contracts

Each navigation section has one current responsibility. Its definition of done
is behavioral and bounded; provider-wide feature parity is not a section
requirement.

| Section | Responsibility | Definition of done |
| --- | --- | --- |
| Dashboard | Reconcile public DNS, local routes, services, containers, and storage health. | The first response shows current or explicitly stale topology and storage status; filtering and a bounded refresh work with native controls; partial collector failure does not erase last-good evidence. |
| Projects | Operate discovered `nob.zig` projects through reviewable lifecycle plans. | Scan, trust/revoke/forget, secrets, prepare/observe, plan/run/cancel, resource controls, logs, and failure states work through the one project owner; no Apps or second deployer path exists. |
| Routes | Own Cloudio's Caddy fragment and its desired-versus-observed workflow. | List, create, edit, enable/disable, remove, adopt, preview, and confirmed apply work; the zero-route state explains the ownership boundary and omits inactive adoption/apply workflow; invalid or failed Caddy changes preserve the prior owned fragment and report a useful error. |
| DNS | Manage configured Cloudflare zones through a fixed typed record contract. | Zone selection, refresh, create, update, and confirmed delete work for supported record fields; missing capability, provider rejection, and stale data are explicit; no arbitrary provider write is exposed. |
| VPS | Observe configured Hostinger VPS resources and invoke the fixed lifecycle allowlist. | Refresh, selection, current state, start/stop/restart, confirmation, unsupported capability, provider failure, and audit behavior are visible and bounded to typed controls. |
| Docker | Observe and control the local container runtime. | Refresh, list, select, logs, start/stop/restart, confirmation, daemon failure, stale last-good state, and audit behavior work without adding Compose editing or remote orchestration. |
| Audit | Inspect bounded mutation and operation history. | Server-side category/result/time/actor/target filters, limits, detail context, and links back to owned resources work without client-side filtering or an unbounded export/query surface. |
| Security | Own passkey enrollment and session lifecycle. | Initial setup, login, credential list/add/rename/revoke, last-credential protection, logout, reset/recovery invalidation, CSRF/origin policy, and mobile dialog behavior pass across real browser and server boundaries. |
| Settings | Persist the three supported appearance choices. | Light, dark, and system preferences round-trip through a native form and cookie, survive authentication transitions, and render correctly with JavaScript disabled; no general preferences framework is introduced. |

Apps has no contract because it is not shipped. Requests for its former page
and API return `404` after the normal authentication boundary.

## Definition of done for this pass

The cleanup is done only when all of the following are true:

1. Every shipped web section has a bounded responsibility and is covered by the
   authenticated product acceptance workflow.
2. Authenticated first-response HTML is useful without page bootstrap requests;
   JavaScript exists only where the browser must participate.
3. No legacy Apps route, template, handler, client script, or deployment
   implementation remains.
4. No speculative embedding facade or compatibility wrapper exists without a
   current caller.
5. Every registered Zig module test root contains tests; compilation-only
   coverage comes from building the executable.
6. No separate smoke-test suite remains. Provider live-read evidence is named
   as evidence, not as a test.
7. The route inventory, architecture boundary check, and frontend structural
   check match the shipped code.
8. Debug and ReleaseSafe `release-check` pass from the pinned dependency
   layout.
9. The Turso draft is byte-for-byte unchanged and no database ownership or
   schema cutover is mixed into this work.

Passing unit tests alone is insufficient.

## Anti-churn pass contracts

| Pass | Definition of done |
| --- | --- |
| Product ownership | The nine contracts above each have one implementation owner and acceptance evidence; overlapping Apps/deployer behavior is absent. |
| Frontend | Server-known state arrives in useful HTML; shared JavaScript owns navigation only; browser-only passkey behavior stays page-local; there is no startup state fetch, client store, or duplicate renderer. |
| Server and HTTP | One explicit route table and one policy pipeline own authentication, origin, CSRF, idempotency, confirmation, and response behavior; the checked inventory matches every shipped route. |
| Modules and compatibility | Every build module is executable-reachable, and hypothetical public facades or one-caller compatibility wrappers are absent. |
| Build and tests | Registered roots contain meaningful tests; compile confidence comes from the executable build; focused tests plus product/recovery acceptance cover production failure modes without a separate smoke layer. |
| Providers and operations | Generic tooling can read or produce no-execute plans only; live writes stay on typed allowlists; evidence names and runbooks describe current behavior rather than completion claims. |
| Persistence and configuration | Existing database and configuration compatibility remains deliberate and tested; no speculative migration is mixed in; the Turso draft remains byte-identical. |
| Documentation | Each remaining document owns one stable contract, inventory, decision, or runbook; completed plans and duplicated prose are absent; local links and commands verify. |

## Implemented decisions

### Product surface

Removed:

- the unused Apps page and navigation item;
- the legacy Apps JSON/form handlers;
- the second deployment engine and system-level unit writer; and
- the page-specific client renderer for Apps.

Kept:

- Projects as the single reviewed deployment/lifecycle surface;
- Docker as a bounded local runtime observer/controller; and
- the empty legacy Apps/deployer tables until a backed-up persistence
  migration can remove them safely.

Boundary: no replacement Apps abstraction, migration shim, or hidden route was
added.

### Frontend

Removed:

- client-rendered table and shell code for server-known state;
- page scripts for Dashboard, Projects, Routes, DNS, VPS, Docker, Audit,
  Settings, and the retired Apps page;
- the global `window.cloudio` API/dialog/toast facade;
- Security controls injected into every authenticated page; and
- the old browser smoke scripts.

Kept:

- one shared stylesheet and server-rendered shell;
- a 50-line navigation-only shared script;
- public login/setup WebAuthn scripts; and
- one Security-local credential island using the server-rendered CSRF token,
  native `<dialog method="dialog">`, and no startup fetch.

Boundary: a new page script requires browser-only behavior that cannot be
expressed by a native link/form response. It must not become a second state
model.

### Server and HTTP

Kept:

- one route table;
- one default-deny authentication/origin/CSRF/idempotency/confirmation
  pipeline;
- grouped thin handlers;
- server-owned native form redirects and result state; and
- the explicit HTTP route inventory.

Deferred:

- extracting repeated native-form security parsing; and
- splitting `pages.zig` or `pipeline.zig` merely because they are large.

Reason: central policy ownership currently reduces the risk of route-specific
security drift. A file-size refactor without a stronger owner boundary would
create more imports, build wiring, and review surface without changing user
behavior.

Trigger for extraction: at least three handlers share an identical parse and
validation contract that can be represented without optional fallback policy.
Definition of done: every affected native form and JSON error path remains
covered by product acceptance, including JS-disabled behavior.

### Modules and compatibility

Removed:

- `src/cloudio.zig`, a public facade maintained only for hypothetical
  embedders; and
- `src/providers/dispatch.zig`, a compatibility wrapper whose only caller was
  that facade.

The live CLI/server already imports the smaller owner modules directly. A
static import-graph audit found every remaining build module reachable from
the executable.

Boundary: introduce a public library surface only with a real external
consumer, a versioned contract, and tests written from that consumer's point
of view.

### Build and tests

Removed from the root test graph:

- one duplicate server-root registration;
- the deleted facade and dispatch roots;
- standalone roots with zero test declarations; and
- compile-only provider client roots already compiled by the executable and
  their standalone packages.

Every remaining registered root contains tests. The roots are explicit because
the pinned Zig test runner does not discover dependency-module tests merely by
importing an aggregate module.

Kept:

- focused unit tests for parsers, serializers, safety policy, and state
  machines;
- SQLite and provider integration coverage;
- standalone package tests;
- structural architecture/web checks; and
- the authenticated product and recovery acceptance workflow.

Boundary: do not add a smoke layer between compile checks and product
acceptance. Do not delete focused tests just to reduce a count; remove them
only when a higher-value test proves the same failure mode and the lower test
has no faster diagnostic value.

### Provider coverage

Kept:

- checked OpenAPI manifests and reviewed overrides;
- the current route parser and explicit generic read/capture tools;
- no-execute mutation planning; and
- the typed product write allowlist.

Removed:

- static provider-count prose that immediately drifted; and
- the misleading `live_smoke*` evidence label, renamed mechanically to
  `live_read*`.

Boundary: coverage rows and L0-L3 summaries are implementation evidence, not
product completion. Do not add another family classifier, planning alias,
JSON field, or generated live-write path without a current operator workflow.

### Persistence and configuration

Kept unchanged:

- the current SQLite migration sequence and repository layout;
- accepted configuration/environment compatibility names;
- legacy empty tables; and
- the read-only `route-cloudflare-dns-typed-smoke` stored-kind match for
  databases created before evidence terminology was corrected; and
- backup-first retention and recovery behavior.

Reason: speculative schema or config cleanup now would require data migration,
rollback, and operational compatibility work immediately before the intended
Turso change.

Boundary: do not remove a table, column, config key, or environment alias based
only on source search. Require an inventory of actual databases/configuration,
a verified copy, a rehearsal, and rollback evidence.

### Documentation

Deleted completed or superseded plans:

- the provider execution roadmap;
- the product completion plan;
- the HTMX port specification;
- the server-first reliability milestone;
- the frontend/backend/passkey sprint plan; and
- the standalone theme/settings specification.

Replaced:

- the command encyclopedia README with a product/operator entry point;
- the historical architecture/refactor narrative with current boundaries;
- static provider coverage baselines with a live-command contract; and
- completed `nob.zig` delivery milestones and cross-repository adoption plans
  with protocol conformance criteria.

Kept:

- the exact HTTP route inventory;
- passkey and storage runbooks;
- the normative `nob.zig` protocol;
- the concise provider coverage contract; and
- the protected Turso migration draft.

Boundary: a new document must own a stable contract, runbook, inventory, or
accepted decision. Temporary execution plans are deleted at completion.

## Completion evidence

The completed tree passed all of the following on 2026-08-03:

- the static build audit: 145 build modules executable-reachable and 128
  unique, nonempty registered test roots;
- the architecture boundary check and frontend structural/syntax check;
- local links across the README and all eight retained documents;
- provider manifest drift validation with `zig build coverage-check`;
- `zig build --system zig-pkg -Doptimize=Debug release-check`; and
- `zig build --system zig-pkg -Doptimize=ReleaseSafe release-check`.

Both release gates include the authenticated product acceptance workflow and
the authentication recovery workflow. The protected Turso draft SHA-256 was
`5f96cbd761b9211f526b51ae0f23fcc64e0961530bc98f9dc8362163c658684f` before
and after the pass.

## Deliberately retained complexity

The following code is large but currently justified:

- the request pipeline, because it centralizes security and replay policy;
- server page rendering, because it provides complete first-response states for
  nine sections;
- provider route metadata, because current CLI planning/capture and typed
  provider summaries consume it;
- `nob.zig`, because it replaces unsafe deployment guessing with persisted,
  reviewable operations; and
- the product acceptance fixture, because it proves passkeys, CSRF,
  idempotency, Caddy rollback, DNS/VPS/Docker state changes, Projects, storage,
  CSP, and JS-disabled behavior across real process boundaries.

Large line count alone is not deletion evidence. Each retained area has a
current consumer and a production failure mode it prevents.

## Turso handoff

`docs/turso-migration-spec.md` remains the authority for the next persistence
phase. This pass neither edits the draft nor implements part of it.

Before Turso work begins:

1. Finish this cleanup with both release gates green.
2. Re-inventory the then-current SQLite schema and all connection owners.
3. Use verified copies and the draft's exclusive cutover rules.
4. Keep one writer and rehearse rollback; do not introduce dual-write or sync
   as a shortcut.
5. Decide legacy-table removal inside that migration, where copy validation and
   rollback already exist.

This is a sequencing boundary, not permission to broaden the Turso scope.

## Rules for later anti-churn passes

For each candidate:

1. Name the current consumer and failure mode.
2. Measure imports, routes, test discovery, stored compatibility, and operator
   usage before editing.
3. Classify it as remove, keep, or defer with one reason.
4. Prefer deletion or direct owner-module use over a new abstraction.
5. Verify the narrow user workflow and the relevant release gate.
6. Update a stable contract only when behavior changed; do not open a new
   perpetual plan.

A later pass is done when its named workflow is simpler, its compatibility
boundary is explicit, and no unrelated migration, platform, test framework, or
fallback was added.
