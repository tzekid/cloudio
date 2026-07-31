# Server-first reliability milestone

Status: complete

## Outcome

Make Cloudio's existing server-rendered first view the browser-visible source of
truth. Loading an authenticated page must not immediately request the same data
as JSON and render it again.

This is the prerequisite reliability tranche for the separately specified
HTMX port. It does not attempt to complete that whole port, redesign the UI, or
change provider behavior.

## Candidates

| Candidate | Benefit | Cost |
| --- | --- | --- |
| Keep automatic page `load()` calls | No implementation work | Duplicates server work, adds startup requests, and lets browser/server renderers drift |
| Stop automatic reads but keep explicit refresh and mutation clients | Removes the measured first-view duplication while preserving current operations | Browser renderers remain temporarily for explicit actions |
| Complete the entire HTMX port in this tranche | Removes the browser data clients completely | Expands a focused cross-project reliability pass into every Cloudio mutation and polling flow |

## Decision

Stop automatic page reads and render every control needed to begin work in the
first HTML response. Existing JSON clients may run only after an explicit user
action such as refresh, filtering, opening details, or mutation. The existing
HTMX port remains the owner of their eventual removal.

Focused HTMX fragments were reconsidered during implementation. Each filter
already has a complete, canonical GET response, while provider recollection is
already an explicit action. Adding fragment routes in this tranche would create
a second response representation without eliminating a request, so ordinary
navigation is the smaller and faster implementation. HTMX remains appropriate
when a later measured flow benefits from a local update.

Do not add a client state store, hydration format, embedded JSON bootstrap,
component framework, new database table, or new background process.

## Work

1. Remove automatic JSON reads from authenticated page startup.
2. Ensure the server-rendered rows/cards include the controls currently added
   by those startup reads, or provide an honest native control for requesting
   them.
3. Keep GET filters as ordinary forms and canonical URLs. JavaScript may debounce
   an explicit filter interaction, but the submit path must remain complete.
4. Add an isolated real-browser fixture that enrolls a virtual passkey and
   visits every authenticated page with JavaScript enabled and disabled.
5. Measure requests from navigation through load and fail if any private page
   performs a startup `fetch`/XHR.
6. Exercise at least one filter through A -> B -> A state changes and assert
   both the canonical URL and visibly different rendered results.

## Definition of done

- [x] Dashboard, Apps, Routes, DNS, VPS, Docker, Audit, Security, and Settings
      return useful HTML before JavaScript executes.
- [x] No authenticated first view performs a `fetch` or XHR before an explicit
      user action.
- [x] No first view contains a loading placeholder for server-known state.
- [x] Server-rendered operational controls remain available after removing the
      automatic reads.
- [x] Dashboard and Audit GET forms work with JavaScript disabled and preserve
      their canonical query state.
- [x] Repeated state changes prove rendered data changes, not merely selected
      control values.
- [x] Passkey setup/login, logout, CSP, CSRF/origin enforcement, and existing
      mutation safeguards remain unchanged.
- [x] The real-browser gate fails on console errors, page errors, startup API
      requests, or missing native controls.
- [x] Debug and ReleaseSafe checks pass.

## Acceptance evidence

- `zig build check -Doptimize=Debug`
- `zig build check -Doptimize=ReleaseSafe`
- `CLOUDIO_CHROMIUM_PATH=/path/to/chromium zig build browser-smoke -Doptimize=Debug`

The browser fixture uses an isolated SQLite database and loopback server. It
enrolls a virtual passkey, exercises login and logout, visits all nine private
pages with JavaScript enabled and disabled, rejects an unsafe request without a
CSRF token, measures startup fetch/XHR traffic, and proves native Dashboard and
Audit GET transitions including Audit 50 -> 100 -> 50 rendered row changes.

## Explicitly deferred

- Completing every route in `docs/htmx-port-spec.md`.
- Removing the stable JSON API used by CLI and automation clients.
- Visual redesign, a shared component system, polling changes, SSE, or
  WebSockets.
- Refactoring the server's internal JSON adapters without a measured reason or
  a typed application model already required by another consumer.
