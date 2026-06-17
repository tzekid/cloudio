# Cloudio Architecture Target

Cloudio should become a small Zig toolkit, not a CLI-shaped monolith. The CLI remains the first product surface, but every command should delegate to internal libraries that can later be reused by a web or native UI without rewriting collectors or provider clients.

## Current State

The POC has moved the current data-gathering paths out of the original CLI-shaped executable. Core config/redaction/logging/process/time/JSON/filesystem helpers, reusable HTTP and JSON pagination helpers, SQLite migrations/storage, and the current Cloudflare, Hostinger, Caddy, system, and project collector paths are split into reviewable modules. `main.zig` is now process entry only, `cli/root.zig` owns top-level dispatch, command-group modules own deeper CLI parsing/rendering, and every CLI command group delegates domain behavior through `app/*` instead of importing collectors directly. `core/fs.zig` owns common relative-path parent creation and existence checks, `db/schema.zig` owns versioned SQLite migrations, `db/store.zig` owns connection/repository/query APIs, `net/pagination.zig` owns generic `{"data":[],"meta":{...}}` page envelope parsing/merging, `providers/routes.zig` owns generated-manifest-backed route metadata lookup, official path/query/body/response requirements, required path/query validation, path-template metadata invariants, and path/query rendering, `providers/dispatch.zig` owns provider-neutral auth dispatch for generic read calls and request/response-aware dry-run mutation plans, `app/coverage.zig` owns human-readable provider coverage summaries and detailed L1 route contract views through the shared route parser, `collectors/capture.zig` owns shared redacted API response capture into snapshots and raw-provider storage, `app/init.zig` owns reusable first-run config initialization, `app/doctor.zig` owns the reusable health-check report, `app/log.zig` owns reusable redacted run-log reading, `app/refresh.zig` owns reusable refresh orchestration, `app/overview.zig` owns the reusable overview query/read model, `app/export.zig` owns snapshot export JSON via the `app.exports` facade, and `app/caddy.zig`, `app/projects.zig`, `app/system.zig`, `app/cloudflare.zig`, and `app/hostinger.zig` own reusable command workflows for their domains. `cloudio.zig` exposes the first public library facade for future web/native integration. The next refactor goal is to keep shrinking CLI rendering and DB printing while expanding provider coverage against the checked upstream manifests.

## Target Module Boundaries

```text
src/
  main.zig                 # process setup and CLI entry only
  cloudio.zig              # public library facade for future UI/app embedding
  core/
    config.zig             # config file, dotenv, fish env, process env
    fs.zig                 # filesystem helpers for parent directories and existence checks
    redact.zig             # secret detection and output redaction
    log.zig                # run log writer and audit-safe formatting
    process.zig            # bounded command execution and result status helpers
    time.zig               # UTC windows and testable clock helpers
    json.zig               # common JSON field/extract/stringify helpers
  db/
    schema.zig             # versioned migrations and schema metadata
    store.zig              # connection, bind helpers, repositories, read models
  net/
    http.zig               # std.http wrapper, headers, status, body limits
    pagination.zig         # cursor/page handling and collection envelopes
  providers/
    routes.zig              # generated manifest-backed route lookup, params, URL rendering
    dispatch.zig            # generic provider auth dispatch and dry-run mutation plans
    cloudflare/
      client.zig           # typed Cloudflare API client
      models.zig           # response types and normalization helpers
    hostinger/
      client.zig           # typed Hostinger API client
      routes.zig           # endpoint enums, path/query construction, route tests
      models.zig
  collectors/
    capture.zig            # shared redacted response capture to snapshots/provider_raw
    cloudflare.zig         # provider -> snapshots/store
    hostinger.zig
    caddy.zig
    system.zig
    projects.zig
  app/
    caddy.zig              # reusable Caddy site/upstream workflows
    cloudflare.zig         # reusable Cloudflare provider workflows
    coverage.zig           # reusable provider coverage summary/detail workflows
    export.zig             # reusable snapshot export JSON
    doctor.zig             # reusable health-check report
    init.zig               # reusable first-run config initialization
    log.zig                # reusable redacted run-log reader
    hostinger.zig          # reusable Hostinger provider workflows
    overview.zig           # overview counts and recent-snapshot read model
    projects.zig           # reusable project list/detail workflows
    refresh.zig            # reusable refresh service for CLI and future UI/API
    system.zig             # reusable system summary/listing workflows
  cli/
    root.zig               # command dispatch
    caddy.zig              # Caddy command-group parsing and collector handoff
    cloudflare.zig         # Cloudflare command-group parsing and collector handoff
    hostinger.zig          # Hostinger command-group parsing and collector handoff
    projects.zig           # Projects command-group parsing and collector handoff
    render.zig             # terminal output only
    system.zig             # System command-group parsing and collector handoff
  ui_api/
    README.md              # future web/native API contract sketches
```

## Internal API Rules

- Provider clients do HTTP and JSON only. They must not know about SQLite, CLI rendering, terminal colors, files outside config, or Caddy/system inventory.
- `zig build architecture-check` enforces module-boundary rules: `core`/`net` modules cannot import higher layers, database modules cannot import providers/collectors/apps/CLI, provider modules cannot import persistence/collector/app/CLI modules, collectors cannot import app/CLI modules, app modules cannot import CLI modules, and CLI adapters must delegate through `app.*` instead of importing provider or collector modules.
- SQLite DDL lives in `db/schema.zig`; `db/store.zig` delegates initialization and exposes repository/read-model APIs. `zig build architecture-check` fails if schema DDL drifts back into the store module.
- SQLite-backed Zig modules should use the `linkSqlite` helper in `build.zig`; direct per-module `linkSystemLibrary("sqlite3", ...)` and `link_libc` boilerplate should not be reintroduced.
- `providers/routes.zig` owns generated-manifest-backed route metadata for Cloudflare and Hostinger: provider, tag, method, path template, operation ID, support/mode, deprecation state, official path/query parameter requirements, request-body requirements, dry-run-safe body input metadata, response status/content/schema metadata, response-status matching, operation/path lookup, path-placeholder extraction, required path/query validation, path-template metadata invariants, one reusable path/query request object, and escaped path/query/URL rendering. This is the L1 bridge for broad provider coverage and future generic dispatch.
- `providers/dispatch.zig` owns provider-neutral L1 dispatch. It renders query-aware `provider_routes.Request` values through `providers/routes.zig`, applies Cloudflare or Hostinger auth through the existing provider clients, executes only bodyless `GET`/`read` routes, and renders request/response-aware mutation routes as `will_execute:false` dry-run plans without issuing HTTP or printing request body contents.
- `app/coverage.zig` owns human-facing inspection of generated route contracts, including tag/status/mode filters and exact route selection by operation ID or method/path. CLI coverage commands should stay thin over this app surface so future UI/API views can reuse the same route addressing.
- Generic read dispatch is bodyless by design. Generated non-deprecated `GET` operations with `requestBody.required=true` must be visible in coverage as `not_applicable` / `none` until there is an explicit read-with-body transport policy.
- Provider-specific route modules own typed endpoint enums and path/query construction where hand-written wrappers improve Cloudio ergonomics. Route modules should stay pure and fixture-testable so future UI/API layers can reuse provider operations without invoking HTTP.
- Collector capture owns redacted raw API response persistence. It redacts response bodies once, writes `snapshots` and `provider_raw`, and returns the redacted body for optional CLI output or collector normalization.
- Collectors own normalization. They call provider/system libraries, pass provider responses through shared capture, and normalize selected fields into indexed tables.
- App services own cross-collector workflows and read models. They compose collectors, persistence, audit events, run logs, and typed query output behind stable inputs so CLI, web, or native surfaces can reuse the same behavior.
- CLI commands are thin adapters. `cli/root.zig` should stay limited to top-level dispatch; command-group modules parse their own subcommands, call collectors or query services, and render output.
- Redaction is core infrastructure. Any path that writes terminal output, run logs, exports, snapshots, diffs, or raw provider bodies must pass through the same redaction API unless the data is proven public.
- Time-dependent code takes a clock abstraction or has a deterministic helper test. Provider-specific default windows, such as Hostinger metrics, should live in provider code.
- Generated or checked provider coverage must be separate from hand-written client behavior. The manifest states what exists upstream, `providers/routes.zig` exposes the generic route contract, `providers/dispatch.zig` exposes the generic auth/call contract, and typed clients state what Cloudio supports ergonomically and safely today.
- Coverage review surfaces must reuse the same generated route parser as generic dispatch when showing L1 details, so docs, CLI output, and provider calls do not drift into separate interpretations of the OpenAPI manifest.
- Provider dry-run plans should be built from typed route metadata in `providers/*` and exposed through `app/*`; collectors remain responsible for live read capture and normalization.

## Provider Coverage Contract

Every provider endpoint should have one generated coverage row with:

- `provider`
- `tag` or upstream group
- `method`
- `path`
- `operation_id` when available
- `path_params`: generated `{name, required}` path parameters
- `query_params`: generated `{name, required}` query parameters
- `request_body`: generated required flag, accepted content types, and schema refs
- `responses`: generated status, accepted content types, and schema refs
- `support`: `implemented`, `partial`, `planned`, `blocked_permission`, `unsafe_mutation`, `deprecated`, or `not_applicable`
- `mode`: `read`, `dry_run`, `write`, or `none`
- `tests`: fixture, live smoke, or missing
- `notes`

Coverage rows are checked against the latest official OpenAPI source before provider work begins. If an upstream endpoint appears or disappears, `zig build coverage-check` should show that drift explicitly.
Route-library tests also check that every generated `path_params` entry is required and exactly matches a placeholder in the generated path template. Route rendering rejects unknown path keys and missing required path values before generic dispatch can build an HTTP URL or dry-run plan.

## Review Shape

Small reviews should usually touch one layer:

- core extraction with unit tests and no behavior change
- DB repository/schema change with migration tests
- provider endpoint support with fixture response tests and one live dry-run/read-only smoke command
- collector normalization with SQLite integration tests
- CLI rendering with command smoke tests

Large provider coverage expansions should be split by upstream tag group, not by HTTP method.

## Refactor Order

1. Extract `core.redact`, `core.time`, `core.config`, `core.json`, `core.fs`, `core.log`, `net.http`, and `net.pagination` because they have narrow dependencies and good existing tests. This tranche is split out.
2. Extract `db.store` while preserving the current schema and temp-DB tests. This is split out as the first database module, and `db/schema.zig` now owns versioned migrations with schema metadata and read-model indexes.
3. Move Hostinger into `providers/hostinger` first because the current endpoint set is smaller and recently verified. The read-only HTTP client, route/path construction, VPS model parsing, and current POC collector have moved; broader typed models and generated coverage still need to follow.
4. Move Cloudflare into `providers/cloudflare`. The read-only account/zone/DNS URL/auth client, response normalization, and current collector have moved. The generated coverage manifest now exists; broad endpoint expansion should proceed against that manifest by upstream tag group.
5. Move Caddy, system, and project collectors out of `main.zig`. This tranche is split out.
6. Split CLI dispatch/rendering into `cli/` modules now that collector behavior has module boundaries. This tranche is split out as `cli/root.zig`, `cli/render.zig`, `cli/caddy.zig`, `cli/cloudflare.zig`, `cli/hostinger.zig`, `cli/projects.zig`, and `cli/system.zig`; those CLI modules now call `app/*` APIs rather than collectors directly.
7. Add `cloudio.zig` facade once CLI dispatch no longer owns application behavior. The initial facade exists and now exposes `app.refresh`, `app.overview`, `app.exports`, `app.caddy`, `app.projects`, `app.system`, `app.cloudflare`, and `app.hostinger`; it should grow cautiously as stable app-facing APIs emerge.
8. Continue moving provider behavior from collector-shaped raw workflows toward typed app/query services as Cloudflare and Hostinger client coverage expands by upstream tag group. The shared `collectors.capture` helper now handles redacted snapshot/provider_raw persistence for current Cloudflare and Hostinger API response paths while provider modules stay HTTP/JSON-only.
9. Continue Cloudflare and Hostinger provider expansion by upstream tag group, using `zig build coverage-check` before each provider change.
