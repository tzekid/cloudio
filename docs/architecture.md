# Cloudio architecture

Status: current implementation boundary after the 2026-08-03 anti-churn pass.

Cloudio is one Zig executable with a server-rendered web UI, a host CLI,
background work, and SQLite persistence. The architecture optimizes for
auditable operator workflows on one host, not for reuse as a framework.

## Dependency direction

```text
main
  -> cli
       -> server/runtime
       -> app
            -> collectors
            -> providers and standalone provider packages
            -> db
       -> core

server
  -> app
  -> reusable http

collectors
  -> providers
  -> db

providers
  -> core/net and standalone provider packages
```

Dependencies point toward smaller owner modules. The executable does not expose
a public library facade: no supported embedder exists, and maintaining a mirror
of every internal module would make normal refactors more expensive.

`tools/architecture-check.sh` enforces the important edges:

- `core`, `net`, and reusable `http` do not depend on Cloudio application
  or persistence layers;
- database code does not import providers, collectors, app services, or CLI;
- providers and standalone packages do not import persistence or application
  layers;
- collectors do not import app or CLI code or write terminal output;
- HTTP handlers delegate domain work to app services;
- app services do not import CLI adapters; and
- CLI modules do not bypass app services to reach persistence or collectors.

These checks protect ownership boundaries. They are not a demand for one file
per type or function.

## Process and adapters

`src/main.zig` only enters `cli/root.zig`. The CLI loads configuration,
opens the initialized database, and dispatches to command-family adapters.
Adapters parse arguments and render output; application behavior stays in
`src/app`.

`cloudio serve` starts:

- the bounded reusable server in `src/http`;
- the Cloudio route and security pipeline in `src/server`;
- the refresh/retention scheduler in `src/runtime/scheduler.zig`; and
- persisted `nob.zig` workers in `src/runtime/nob_workers.zig`.

There is one route table in `src/server/routes.zig`. The shipped route list is
maintained in `docs/http-route-inventory.md`.

## HTTP and page rendering

`src/http` owns bounded HTTP/1.1 parsing, static responses, routing, security
headers, and connection lifecycle without knowing Cloudio policy.

`src/server/pipeline.zig` is the single request-policy boundary. It owns:

- public versus authenticated route selection;
- session lookup and expiry;
- exact-origin enforcement;
- CSRF validation;
- idempotency lookup, fingerprinting, and response replay;
- explicit destructive confirmation;
- body and header limits;
- stable HTML redirects or JSON errors; and
- audit metadata passed to application writes.

Grouped handlers translate HTTP input to app-service calls. They do not own SQL
or provider transports. Native form workflows use `303 See Other` and
server-rendered result state; JSON routes return explicit status and error
payloads.

`src/server/pages.zig` loads the authored `<main>` from `web/*.html`,
injects escaped current data, and wraps it in one authenticated shell. Dynamic
text, attributes, and URLs go through the context-safe HTML writer.

The browser boundary is deliberately small:

- `web/assets/app.js` manages only responsive navigation;
- login and setup scripts own WebAuthn ceremonies for their public page;
- `web/assets/pages/security.js` alone owns authenticated credential
  ceremony requests and its revoke dialog; and
- every other authenticated page uses native links and forms with no
  page-specific script.

There is no client-side store, page bootstrap fetch, polling loop, global API
facade, or duplicated client renderer.

## Application workflows

`src/app` owns product behavior and reusable read models. Important owners
include:

- `dashboard.zig` and `topology.zig` for reconciled health;
- `caddy_desired.zig` for the owned-fragment desired/apply transaction;
- `dns.zig`, `vps.zig`, and `system_control.zig` for typed,
  capability-checked mutations;
- `browser_run.zig` for allowlisted, bounded Kitesurf actions and private
  artifact lifecycle;
- `provider_writes.zig` for the fixed provider mutation allowlist;
- `authentication.zig` for passkey ceremonies and sessions;
- `maintenance.zig` for backup, retention, and compaction policy;
- `nob_projects.zig`, `nob_runtime.zig`, `nob_actions.zig`,
  `nob_worker.zig`, and `nob_secrets.zig` for project lifecycle state; and
- `writes.zig` for idempotent mutation and audit records.

An app module is warranted when it owns a workflow or stable policy boundary.
Thin one-consumer wrappers are not created merely to shorten a file.

## Observation and external systems

`src/collectors` converts external or host state into atomic database
observations. Provider packages own HTTP and response parsing; collectors own
redacted persistence and normalization.

Failed refreshes do not manufacture an empty healthy state. The last successful
rows remain available with explicit freshness or capability evidence. Product
mutations consult current capability state and recollect after execution when
the result can be observed.

External process execution uses direct argument vectors and bounded output and
time. Secret-bearing values are redacted before logs, snapshots, audit details,
or runner diagnostics are persisted.

## Providers

`packages/cloudflare` and `packages/hostinger` are independently buildable
libraries. Their package tests run inside the root `check` gate.

`coverage/generated/*.jsonl` is a checked snapshot of official OpenAPI route
metadata plus reviewed overrides. `src/providers/routes.zig` parses that
contract for route inspection and generic request planning. Owner modules
`auth.zig`, `request_plan.zig`, `transport.zig`,
`route_result.zig`, and `route_plan.zig` handle the narrower steps.

Generic generated-route behavior is intentionally asymmetric:

- supported bodyless reads may be planned and explicitly executed;
- read capture stores redacted evidence;
- generated mutations may produce `will_execute:false` review plans; and
- generated metadata never authorizes a live write.

Live product writes use the small typed allowlist in
`app/provider_writes.zig`. Provider coverage is implementation evidence, not
a product-completion percentage. Upstream generation and drift checks remain
explicit networked developer commands and are not part of offline tests.

## Persistence

`src/db/schema.zig` owns ordered SQLite migrations. Concrete SQL is grouped
under `src/db/repositories`; `src/db/store.zig` is the existing composition
facade used by application code.

The database stores observations, normalized provider rows, topology, audit
events, idempotency responses, authentication state, desired Caddy state,
Browser Run metadata, and `nob.zig` lifecycle records. Browser artifacts live
as private bounded files outside SQLite and are resolved only from opaque run
IDs. Append-only data has bounded, backup-first maintenance described in
`docs/storage-operations.md`.

Legacy empty Apps/deployer tables are retained for existing SQLite files. A
schema-only cleanup now would add migration and rollback risk immediately
before the intended persistence replacement.

`docs/turso-migration-spec.md` is the protected next persistence design. It
is not current architecture and must not be implemented piecemeal during
unrelated cleanup.

## `nob.zig` trust boundary

The project lifecycle has three layers:

1. A passive `nob.json` can be discovered and reviewed without executing the
   project.
2. Trust binds canonical source identity and an exact manifest digest before a
   project runner can be built.
3. Mutations require an expiring exact-byte plan, authenticated approval, a
   persisted worker operation, and independent host observation.

The project runner owns project-specific behavior. Cloudio owns process
isolation, secret materialization, idempotency, structural events, audit,
cancellation, and narrow one-use systemd/Caddy broker capabilities. Runner
claims cannot override contradictory host evidence.

The normative contract is `docs/nob-zig-spec.md`.

## Test architecture

Confidence is layered by production value:

1. `release-check` exercises authenticated browser workflows and host-side
   recovery against controlled real processes and fixtures.
2. SQLite and provider integration tests verify persistence, parsing, and
   failure semantics.
3. Focused module tests protect parsers, security invariants, state machines,
   serializers, and pure policy.
4. Static architecture and web checks prevent forbidden dependency and
   rendering regressions.

There is no separate smoke-test suite. A compile-only test root is not a test;
the executable compile gate already provides that signal. Every registered
module test root contains tests, while the executable remains the proof that
all runtime modules compile together.

## Change rules

A new abstraction, compatibility alias, route, configuration field, fallback,
or test suite needs a current consumer and a failure mode it improves.

Prefer:

- one owner for each policy;
- server-owned state and native forms;
- explicit capability errors over optimistic fallback;
- deletion of completed plans over updating them indefinitely;
- current runbooks and inventories over aspirational roadmaps; and
- end-to-end proof for user workflows.

Do not split a large file only because of line count. Split when a stable
ownership boundary reduces dependencies or lets a workflow be tested more
directly. Do not remove compatibility state or schema without a backed-up,
rehearsed migration and rollback.
