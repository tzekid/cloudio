# Cloudio Execution Plan

## Sprint milestone status

- Milestone 1 — coherent frontend: complete.
- Milestone 2 — backend boundaries and provider libraries: complete as of
  2026-07-30. HTTP protocol code is isolated in `src/http`, Cloudio policy and
  grouped handlers live in `src/server`, scheduling lives in `src/runtime`,
  SQLite is split into concrete repositories, and the independently buildable
  Cloudflare/Hostinger packages live under `packages/` with one-way public
  mirror automation.
- Milestone 3 — passkey-only authentication: implemented as of 2026-07-30.
  Cloudio now defaults every route and request to denied, uses discoverable
  WebAuthn passkeys for setup and sign-in, protects authenticated mutations
  with strict-origin and CSRF checks, and provides both CLI-authorized
  bootstrap enrollment and a one-time browser setup flow. Production rollout
  and the owner's first physical passkey ceremony are tracked by the
  milestone runbook.

Cloudio work should move in broad, reviewable slices. A slice is a coherent subsystem or provider family, not one endpoint at a time, unless the change is a narrow bug fix needed to unblock the broader goal.

## Long-Term Goal

1. Simplify internals and eliminate churn without losing feature coverage.
   - Keep the CLI thin over reusable `app/*` workflows.
   - Keep provider clients HTTP/JSON-only.
   - Keep collectors as internal capture/normalization details.
   - Keep read models and render helpers shared by CLI and future UI/API callers.
   - Delete repeated parsing, rendering, config, redaction, logging, and repository code when a shared helper can express the same contract clearly.

2. Cover Cloudflare and Hostinger APIs in broad official-doc-backed groups.
   - Always refresh against the latest official OpenAPI/reference surfaces before provider behavior changes.
   - Use generated manifests to expose upstream drift instead of relying on memory.
   - Advance by upstream tag group or Cloudio control-plane family: accounts, tokens, DNS, SSL/TLS, security, Access, tunnels, rulesets, logs, cache, Hostinger VPS, domains, DNS, hosting, billing, Docker, Reach, ecommerce, and provider security.
   - Reads may execute only when they are bodyless, credential-safe, redacted, and useful to Cloudio.
   - Generic provider-manifest mutations remain no-execute dry-run plans. The platform exposes only a small typed live-write allowlist, protected by authentication, idempotency keys, explicit destructive confirmation, actor-aware redacted audits, and per-app operation locks.

3. Preserve a clean internal API for a future larger app.
   - `cloudio.zig` is the embedding facade for web or native UI work.
   - App modules expose stable inputs, read models, and JSON writers.
   - CLI modules own only parsing and terminal rendering.
   - Future UI/API code should not import collectors or scrape CLI text.

## Slice Rules

- Prefer a whole family, layer, or read-model slice over an endpoint-sized task.
- Provider work starts from `zig build api-summary`, `zig build coverage-manifest`, `zig build coverage-check`, and the relevant `cloudio coverage ... --json` review surface.
- Provider read work should usually close an L2 capture gap for a whole tag/family or mark the whole group as blocked/not-applicable with evidence.
- Provider dry-run work should usually cover all related mutation routes in the family, with shared request validation and no live writes.
- Refactor work should remove visible duplication across several modules and add or preserve tests.
- Database work should include migration tests and a read-model smoke path.
- Every goal turn ends with a commit and push to `origin/master`.

## Current Baseline

The POC already has:

- A Zig CLI with SQLite-backed state.
- Redacted config, dotenv, fish-env, logging, snapshots, and provider raw storage.
- Generated provider route metadata for Cloudflare and Hostinger.
- Generic route plan/read/capture/dry-run surfaces.
- L0/L1/L2/L3 provider coverage review commands.
- DB-backed actual route-capture planning with pre-limit `review_summary`, provider/family `review_groups` totals, group-level `next_action` and no-execute commands, generated enum parameter defaults, read-only family-scoped source-route mappings for child-resource IDs, plus candidate-level `actual_state`, `review_status`, and `next_action` fields for family triage.
- Provider evidence read models over raw-capture metadata, snapshots, audit events, and route-capture/generated-route matching.
- Broad Cloudflare and Hostinger inventory projections.
- Caddy, system, project, project-correlation, overview, export, log, and doctor workflows.
- A redaction audit command, `cloudio security redaction`, that checks configured API token/key bytes against Cloudio output/storage surfaces without printing those bytes.
- A public `cloudio.zig` facade that keeps collectors out of future embedding code.
- A shipped local HTTP platform and browser UI over app-level JSON contracts.
- Passkey-only authentication with hashed server-side sessions, one-time
  hashed bootstrap capabilities, challenge expiry, strict origin/RP
  validation, and credential management through the shared app-service
  boundary.
- A default-deny HTTP policy pipeline with exact public-route exceptions,
  origin and CSRF enforcement for mutations, security headers, and bounded
  authentication rate limiting.
- Typed live-write adapters for Caddy, Cloudflare DNS/settings/cache, Hostinger VPS/firewall, Docker/systemd, and app deployment; generic provider mutation dispatch remains dry-run-only.
- Request idempotency/replay, destructive confirmation headers, actor metadata, per-app deployment locks, automatic failed-health rollback, and complete app cleanup.
- Configurable snapshot/provider-raw/metrics retention with preview, online backup, bounded prune, WAL checkpoint, and explicit compaction commands.
- A persisted typed topology projection with added/changed/removed history after refresh.

The current simplification slices added `src/app/render.zig`, migrated overview, inventory, Cloudflare, Hostinger, doctor, run-log, and provider coverage helpers away from repeated local JSON/text/shell-quoting helpers, promoted generic JSON field, nullable-field, array, and comma writer primitives into `src/core/json.zig` for app/provider/collector renderers, split Cloudflare account/zone/DNS overview read models into `src/app/cloudflare_overview.zig`, split Hostinger account/VPS overview read models into `src/app/hostinger_overview.zig`, split provider/system evidence and route evidence into `src/app/evidence.zig`, `src/app/evidence_common.zig`, and `src/app/evidence_routes.zig`, centralized coverage/evidence/UI provider-family grouping in `src/app/provider_family.zig`, aligned evidence `--limit=0` with coverage all-row semantics, moved broad Cloudflare CLI overview/filter option grammar into `src/cli/cloudflare_options.zig`, moved Cloudflare dry-run mutation command grammar into `src/cli/cloudflare_dry_run.zig`, moved provider coverage report/workplan/candidate command grammar into `src/cli/coverage_parse.zig`, moved generic provider route request parsing for `coverage plan` and `route plan/read/capture/dry-run` into `src/cli/route_request.zig`, consolidated shared provider/query/limit CLI option grammar in `src/cli/args.zig`, split provider L1 auth/result/transport ownership into `src/providers/auth.zig`, `src/providers/route_result.zig`, and `src/providers/transport.zig`, split provider-specific routes/transport/client ownership through `src/providers/typed_routes.zig`, `src/providers/cloudflare/routes.zig`, `src/providers/cloudflare/transport.zig`, `src/providers/hostinger/routes.zig`, and `src/providers/hostinger/transport.zig`, and added `src/providers/request_plan.zig` so no-execute read plans, dry-run mutation plans, and live-read URL validation share one structured planning contract. App route planning, read metadata, route capture, and dry-run rendering now import the owner modules directly instead of re-exporting those contracts through dispatch.

## Execution Phases

### Phase 1: Core Simplification

Goal: make the POC easier to review and harder to fork accidentally.

Broad slices:

- App render/output consolidation across all app read models.
- CLI argument and option parsing consolidation across command groups.
- CLI persistence-boundary consolidation so command adapters open SQLite only through `app/database.zig`, keeping schema startup reusable by a future UI/API adapter.
- Config/env/credential loading contract cleanup, including tests for `.env`, `.env.fish`, TOML, and process env precedence.
- Redaction/logging/export audit so every terminal, DB, log, diff, and export path uses the same secret policy.
- DB repository grouping so command workflows stop hand-rolling similar query loops.
- Command smoke tests for every top-level group after each consolidation.

Acceptance:

- `zig build check`
- `zig build test --summary all`
- `zig build architecture-check`
- `zig build coverage-check`
- Representative JSON smoke commands for affected app surfaces

### Phase 2: Provider Coverage By Family

Goal: cover Cloudflare and Hostinger broadly while staying read-only/dry-run.

Broad Cloudflare slices:

- Accounts, memberships, IAM groups, roles, and tokens.
- Zones, DNS, DNS analytics, registrar, and zone lifecycle.
- SSL/TLS, certificates, mTLS, authenticated origin pulls, and security posture.
- Rulesets, WAF-adjacent surfaces, IP access, page rules, lockdown, API Shield, and page shield.
- Zero Trust, Access, tunnels, Gateway, device policy, posture, and users.
- Logs, analytics, cache/performance, Radar, and account telemetry.

Broad Hostinger slices:

- VPS inventory, actions, metrics, backups, snapshots, public keys, firewall, PTR, recovery, Monarx, Docker manager, data centers, templates, and scripts.
- Domains, DNS zones, DNS snapshots, forwarding, WHOIS, lock/privacy/nameserver surfaces.
- Hosting orders, websites, WordPress, datacenters, databases, domains, subdomains, phpMyAdmin, NodeJS.
- Billing catalog, payment methods, subscriptions, and order-adjacent surfaces.
- Reach, ecommerce, Horizons, and provider security/verification surfaces.

Acceptance per provider slice:

- Re-check official docs/specs with `zig build api-summary`.
- Regenerate or verify manifests with `zig build coverage-manifest` and `zig build coverage-check`.
- Inspect family route contracts with `cloudio coverage routes ... --detail`.
- Use `cloudio coverage workplan <provider> --family <family> --bundle --plans --json` before implementation.
- Add fixture tests for success, pagination, error envelopes, blocked-permission envelopes, and dry-run plans.
- Smoke only read-safe commands with configured credentials.
- Confirm generic route mutation paths cannot send live provider writes; exercise typed allowlisted write adapters only in isolated fixtures or an explicitly selected environment.

### Phase 3: Typed Inventory And Correlation

Goal: turn raw provider capture into operationally useful VPS inventory.

Broad slices:

- Typed Cloudflare projections for control-plane families that are still generic-only.
- Typed Hostinger projections for VPS, DNS/domain, hosting, billing, and Docker/security groups.
- Provider-neutral inventory facets that expose family, status, scope, account, zone, domain, VM, project, and lifecycle fields.
- Caddy host/upstream to provider DNS and local socket correlation.
- Systemd unit, Docker container, compose file, process, port, and project correlation.
- Snapshot/read-model deltas so the overview can show change since last refresh.

Acceptance:

- Migration tests for every new table/index.
- Temp-DB integration tests for projection and correlation queries.
- `cloudio inventory summary ... --json`
- `cloudio overview --json`
- Targeted smoke commands for Caddy, system, projects, Cloudflare, and Hostinger.

### Phase 4: Dry-Run Management

Goal: keep generic provider management reviewable and no-execute while protecting the narrow typed platform write allowlist.

Broad slices:

- Desired-state tables for Caddy routes, provider DNS records, provider security settings, and Hostinger VPS metadata.
- Caddy render/diff/validate workflow, with apply/reload exposed only through the authenticated typed platform route.
- Provider mutation plan builders grouped by family, with validation, redaction, and `will_execute:false`.
- Audit events for every dry-run plan and render/diff action.
- Export/import of desired state for review.

Acceptance:

- Fixture tests for rendered configs and provider plans.
- Diff tests that prove secrets and env values are redacted.
- Smoke `cloudio caddy diff`, provider dry-run commands, and export commands.
- Generic provider route dispatch remains no-execute. Typed platform writes require idempotency and audit tests, and destructive writes require explicit confirmation.

### Phase 5: MVP UI Readiness

Goal: keep the shipped web UI as an adapter over existing app APIs, not a parallel implementation.

Broad slices:

- Stable app-level JSON structs/writers for overview, inventory, coverage, provider detail, Caddy, projects, system, logs, and operational history/audits.
- A compact route-catalog read model over the spec-generated manifests so UI/API callers can review L0/L1 provider metadata without scraping coverage text.
- A topology read model that joins provider DNS, Caddy routes, project metadata, sockets, services, and containers into one UI/API contract.
- Facade-level API examples that call `cloudio.app.*` directly.
- UI/API read-only command contract docs.
- Local HTTP server, cookie/bearer authentication, SSE refresh/deploy streams, and browser pages over shared app contracts.

Acceptance:

- App module tests cover JSON schemas enough for UI consumers.
- CLI text output can evolve without breaking JSON/read-model contracts.
- No UI code imports collectors directly.
- Mutation integration tests prove idempotent replay, confirmation policy, actor audit metadata, deployment locking, rollback, health failure, recovery, and cleanup.

## Next Broad Slices

1. Operate and verify passkey recovery.
   - Complete the owner's first passkey ceremony from the one-time setup URL.
   - Enroll a second passkey on a different device or hardware key before it
     is needed.
   - Exercise the documented offline backup and `auth reset` recovery drill
     without weakening the normal browser route policy.
   - Keep passwords, bearer tokens, email recovery, OAuth, teams, roles, and
     remote administrative bypasses out of scope until a real requirement
     exists.

2. Maintain app presentation consolidation.
   - Extend the app render helper pattern to any remaining repeated app-level JSON/text rendering.
   - Keep CLI rendering separate from reusable app read-model JSON.
   - Use `cloudio history --json` and `cloudio export history --json` as the first operational-history contract for UI/API consumers.
   - Use `cloudio evidence --json` as the provider/system capture evidence contract over raw-capture metadata, snapshots, and audit events.
   - Use `cloudio evidence matrix --json`, `cloudio evidence routes --json`, and `cloudio evidence capture-summary --json` to review DB-backed family/status evidence, operation-level L2 route capture evidence, and the split between raw capture gaps, fixture/diagnostic-covered gaps, and truly unresolved L2 read work.
   - Use `cloudio coverage typed-models --focus control-plane --json` to prove the required L3 typed-model backlog separately from optional outside-control-plane generic inventory modeling.
   - Use `cloudio routes --json` as the compact provider-route metadata contract for UI/API consumers.
   - Use `cloudio topology --json` as the operational graph contract for UI/API consumers; it joins provider DNS, Caddy routes, projects, sockets, services, and containers, then derives row status, exposure, DNS match type, capabilities, and issue arrays.
   - Use `cloudio topology changes --json` for persisted added/changed/removed operational deltas.
   - Keep browser API behavior in `web/assets/app.js`; page scripts must not grow independent fetch/auth/idempotency parsers.

3. Maintain command parsing and option handling.
   - Consolidate repeated `--json`, `--format`, `--limit`, `--domain`, `--query`, `--path-param`, `--query-param`, and `--header-param` handling.
   - Preserve all current command behavior with smoke tests.

4. Hostinger VPS family pass.
   - Re-check latest Hostinger docs/spec.
   - Review the full VPS family workplan bundle.
   - Review `cloudio coverage actual-captures hostinger --family hostinger-vps --limit=0 --plans --json` before editing, and classify work by `review_status` across the whole VPS family.
   - Treat `ready_to_capture` and `retry_capture` as capture work, `blocked_empty_source` and `diagnostic_blocked` as evidence to document, and source-normalization statuses as typed-input/modeling work.
   - When an endpoint needs child IDs, add the list-source mapping for the whole Hostinger resource group in one patch before capturing individual child routes.
   - Tighten collection, typed projections, pagination/error handling, and dry-run plans across the whole VPS family.

5. Cloudflare account/security family pass.
   - Re-check latest Cloudflare docs/spec.
   - Review accounts, memberships, tokens, IAM, security posture, API Shield, rulesets, and related route bundles as a group.
   - Prefer broad source-mapping slices that cover an entire route family at once, as with load-balancing monitor/pool/load-balancer details and tunnel/tunnel-route/connector details.
   - Add or upgrade L2 capture evidence, typed projection, and dry-run plan evidence for the selected family.

6. Caddy/system/project correlation.
   - The unified topology read model and persisted delta projection now connect DNS records, Caddy sites, upstream sockets, systemd units, Docker containers, compose files, and project roots. Continue enriching fields through typed projections rather than page-specific joins.

## Goal-Turn Checklist

Each future goal turn should record:

- Selected broad slice.
- Why this slice is reviewable as one unit.
- Official provider-doc/spec verification when provider behavior changes.
- Files changed.
- Test and smoke commands run.
- Whether live infrastructure mutation was impossible by design.
- Commit hash pushed to `origin/master`.
