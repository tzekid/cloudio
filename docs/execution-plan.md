# Cloudio Execution Plan

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
   - Mutations remain no-execute dry-run plans until write-mode policy is explicitly designed.

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
- Every goal turn ends with a commit and push to `origin/main`.

## Current Baseline

The POC already has:

- A Zig CLI with SQLite-backed state.
- Redacted config, dotenv, fish-env, logging, snapshots, and provider raw storage.
- Generated provider route metadata for Cloudflare and Hostinger.
- Generic route plan/read/capture/dry-run surfaces.
- L0/L1/L2/L3 provider coverage review commands.
- Broad Cloudflare and Hostinger inventory projections.
- Caddy, system, project, overview, export, log, and doctor workflows.
- A public `cloudio.zig` facade that keeps collectors out of future embedding code.

The current simplification slice added `src/app/render.zig` and migrated overview, inventory, Cloudflare, and Hostinger app read models away from repeated local JSON/text helpers.

## Execution Phases

### Phase 1: Core Simplification

Goal: make the POC easier to review and harder to fork accidentally.

Broad slices:

- App render/output consolidation across all app read models.
- CLI argument and option parsing consolidation across command groups.
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
- Confirm no mutation path sends live provider writes.

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

Goal: prepare management workflows without changing live infrastructure.

Broad slices:

- Desired-state tables for Caddy routes, provider DNS records, provider security settings, and Hostinger VPS metadata.
- Caddy render/diff/validate workflow that never writes or reloads unless a future policy enables it.
- Provider mutation plan builders grouped by family, with validation, redaction, and `will_execute:false`.
- Audit events for every dry-run plan and render/diff action.
- Export/import of desired state for review.

Acceptance:

- Fixture tests for rendered configs and provider plans.
- Diff tests that prove secrets and env values are redacted.
- Smoke `cloudio caddy diff`, provider dry-run commands, and export commands.
- No live Cloudflare, Hostinger, Caddy, systemd, or Docker mutation.

### Phase 5: MVP UI Readiness

Goal: make a web/native UI an adapter over existing app APIs, not a rewrite.

Broad slices:

- Stable app-level JSON structs/writers for overview, inventory, coverage, provider detail, Caddy, projects, system, logs, and audits.
- Facade-level API examples that call `cloudio.app.*` directly.
- UI/API read-only command contract docs.
- Optional local HTTP server module only after CLI/app boundaries are stable.

Acceptance:

- App module tests cover JSON schemas enough for UI consumers.
- CLI text output can evolve without breaking JSON/read-model contracts.
- No UI code imports collectors directly.

## Next Broad Slices

1. Finish app presentation consolidation.
   - Extend the new app render helper pattern to any remaining repeated app-level JSON/text rendering.
   - Keep CLI rendering separate from reusable app read-model JSON.

2. Clean command parsing and option handling.
   - Consolidate repeated `--json`, `--format`, `--limit`, `--domain`, `--query`, `--path-param`, `--query-param`, and `--header-param` handling.
   - Preserve all current command behavior with smoke tests.

3. Hostinger VPS family pass.
   - Re-check latest Hostinger docs/spec.
   - Review the full VPS family workplan bundle.
   - Tighten collection, typed projections, pagination/error handling, and dry-run plans across the whole VPS family.

4. Cloudflare account/security family pass.
   - Re-check latest Cloudflare docs/spec.
   - Review accounts, memberships, tokens, IAM, security posture, API Shield, rulesets, and related route bundles as a group.
   - Add or upgrade L2 capture evidence, typed projection, and dry-run plan evidence for the selected family.

5. Caddy/system/project correlation.
   - Produce a single read model that connects DNS records, Caddy sites, upstream sockets, systemd units, Docker containers, compose files, and project roots.

## Goal-Turn Checklist

Each future goal turn should record:

- Selected broad slice.
- Why this slice is reviewable as one unit.
- Official provider-doc/spec verification when provider behavior changes.
- Files changed.
- Test and smoke commands run.
- Whether live infrastructure mutation was impossible by design.
- Commit hash pushed to `origin/main`.
