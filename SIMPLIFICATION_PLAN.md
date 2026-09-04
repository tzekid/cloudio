# Cloudio simplification plan

Planning snapshot: 2026-09-04. Implementation and serial review recorded below.

## Current state and evidence

- Local `ecosystem` is `96a65e9`; recorded current `origin/master` is `8ec415b`. The histories diverge (six versus two unique commits), including rate-limit/connection fixes and toolchain changes. A branch reset would discard work.
- The one-host control plane has real routes/DNS/VPS/Docker/browser/project/authentication workflows. The service currently runs a binary under this checkout's `zig-out/bin`; preserve the running artifact before building over it.
- `build.zig` has 129 module-test registrations and also runs standalone provider package suites. Provider route/transport/model modules occur in both paths. Measure overlapping execution before consolidating.
- Large route catalogs and `src/app/provider_coverage_*` files support documented CLI coverage commands, not just the web UI. `.github/workflows/provider-mirrors.yml` publishes the two provider packages separately.
- The local ecosystem branch adds a copied floor workflow with test-presence, build-step-name, and warn-only hygiene checks. The default branch already has product CI and package-mirror workflows.

## Intended result

Reduce repeated test/build wiring, internal duplication, and obsolete migration policy while retaining the documented operator journeys and exported package behavior. Do not replace the control plane, drop provider families by line count, migrate its database, or introduce another lifecycle framework.

## Implementation sequence

1. Refresh refs and inventory local/remote branch differences, existing work, deployed binary identity, and provider submodule revision. Work from current default in an isolated worktree. Evaluate the unique functional fixes individually; preserve experiments in recoverable refs rather than merging all ecosystem policy wholesale. Do not replace the original checkout until its deployment relationship is resolved.
2. Map each test root to its actual tests, imports, and product boundary. Run existing checks once with the exact pin and native dependencies to establish the baseline. Remove duplicate execution of the same provider checks: provider packages own their internal suites, while Cloudio keeps integration assertions. Preserve independent package-build qualification and distinct transport/security tests.
3. Simplify repeated build registration only where a small explicit table or a coherent module boundary removes real duplication. Do not create a generated build framework or compress the file at the expense of readable dependency wiring.
4. Trace coverage/catalog helpers through CLI dispatch, persistence, package exports, documentation, and mirror consumers. Delete only proven unreachable internals or duplicate transformations; consolidate redundant representations while preserving output meanings. Broader removal of documented commands or public provider APIs is outside this cleanup and requires a separate product decision.
5. Retire the duplicate ecosystem floor instead of copying it onto default. Keep one product CI, package mirror qualification where applicable, and meaningful formatting/security checks. Remove historical file-location bans and warn-only noise when current compiler boundaries or behavioral checks cover the risk. Preserve useful accessibility and JavaScript-syntax checks.
6. Keep SQLite schema/history intact. Leave compatibility tables until a separate data-retirement decision proves removal safe. Update current development instructions to describe only the actual surviving gates.

## Verification and delivery

- Use the existing `zig build --system zig-pkg check -j2` and ReleaseSafe authenticated `product-acceptance` path from CI. Adjust entry points only after showing which existing coverage replaces them. Check both standalone provider packages if their code/builds change.
- For runtime changes, also satisfy the documented Debug and ReleaseSafe `release-check` gates unless their verified replacements are part of this change. Keep normal verification on the checked-in provider manifests; do not introduce live OpenAPI refreshes into offline builds.
- Preserve passkey enrollment/recovery, exact-origin/CSRF/idempotency behavior, secret redaction, bounded requests, DNS/routes preview/apply/rollback, Docker state transitions, and the Nob project protocol. Controlled provider fixtures remain valuable; do not substitute live destructive cloud actions for tests.
- Self-review the final diff and negative cases; fix every release-blocking finding and repeat until a full pass finds no unresolved or new blockers. Record what was removed and which surviving check protects each important boundary.
- Push reviewed changes to the current default branch without rewriting history; verify relevant hosted gates and any triggered provider-mirror jobs. Do not edit or recreate the mirror repositories manually as part of this task.
- Test/build/documentation-only changes require no application restart. For runtime changes, stage the exact checked commit as a separate release, retain the old executable/configuration, use the existing service/Caddy arrangement, and verify executable identity, authenticated product behavior, local/public routes, fresh errors, and rollback readiness. Do not overwrite the active checkout binary in place.
- The service's working directory is this checkout, so relocating the executable must preserve configuration, credentials, relative state paths, and the working directory explicitly. Change only the necessary executable reference after preparing a reversible unit change; a generic deployment-system migration is not part of this cleanup.

## Planning review

- Pass 1 found blockers in treating provider catalogs as internal-only, assuming a build could safely overwrite the live artifact, and omitting documented release-mode qualification. Package export compatibility, separate artifact staging with preserved working-directory semantics, and the required release checks are now explicit.
- Pass 2 compared the revised scope with provider mirror scripts, current development gates, offline-manifest behavior, and the live unit paths. No unresolved or new planning blockers were found. Test duplication and runtime savings must still be measured during implementation.

## Implementation and adversarial review

- Implemented on current `origin/master` (`8ec415b`) in an isolated worktree because the original `ecosystem` checkout supplies the running binary. Original branch, files, and executable remain intact.
- Replaced 129 repeated test registrations with an explicit list of 123 application roots. The six removed provider roots exercise the same package source files already owned by standalone provider suites. Both package suites now belong to `test`, so `check` and `release-check` retain them. Cloudio's own JSON, HTTP, adapter, security, and product integration checks remain: package-internal helper copies are not all identical to Cloudio's helpers.
- Removed historical architecture/name scans and eight obsolete frontend assertions. Kept CSP, authored control labels, native dialog, CSRF, unsafe DOM construction, route inventory, styling, and JavaScript syntax checks. A source containing `web_html.text` never proved that every dynamic value was escaped; removing that literal-name assertion changes no rendering code.
- Reviewed CLI dispatch and provider mirror consumers: catalogs and public APIs are in use and retained. No schema, application source, provider source, submodule, or generated asset changed. No ecosystem floor was copied onto default.
- Branch review rejected promotion of two unrelated experiments: the connection pool lacks shutdown cleanup and permits extra fresh handles when full; oldest-bucket limiter eviction can reset active quotas under churn. They remain recoverable on `ecosystem`. This cleanup introduces neither behavior.
- Baseline `check`: 266/266 steps, 518/518 top-level tests. Revised Debug `release-check`: 256/256 steps plus successful authenticated product and host-side recovery acceptance. Counts exclude nested standalone-package summaries; the smaller graph is not a claim of fewer unique behavioral assertions or measured runtime improvement.
- Review pass 1 checked suite ownership, actual differing helper dependencies, browser/authentication coverage, mirror triggers, and the live service path. Review pass 2 checked the final dependency graph, removed-rule callers, package boundaries, and absence of runtime/dependency/schema changes. No unresolved or new blockers remained in the final pass.
- Deployment is unnecessary for this build/test/documentation change. Preserve the currently running service rather than rebuilding over its executable.

### Completed qualification

- Debug `release-check` passed (256/256 steps), including product and authentication-recovery browser acceptance.
- ReleaseSafe product and authentication-recovery acceptance passed. The compile-heavy aggregate run was stopped after those succeeded and its remaining `check` resumed with six jobs and cached artifacts: 253/253 steps succeeded, 116/116 newly executed top-level tests passed; other test runs were cached. This is component qualification of the same release gate, not a claim that the interrupted aggregate command exited successfully.
- `zig fmt --check build.zig`, `git diff --check`, exact registration-set comparison (123 retained, six standalone-owned removed), and unchanged runtime/package/submodule diff checks passed.
- Push the reviewed commit to `master` and verify its hosted CI before advancing to the next project. The delivery record outside this source commit holds the resulting commit/run identifiers, avoiding a documentation-only CI rerun to record its own hash.
