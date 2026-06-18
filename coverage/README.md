# Provider Coverage Manifests

`coverage/generated/*.jsonl` is generated from the official Cloudflare and Hostinger OpenAPI specs.
`coverage/overrides/*.jsonl` is the hand-reviewed Cloudio support overlay for routes the POC implements, partially implements, or cannot exercise with the current account/token.

Use:

```sh
zig build run -- coverage
zig build run -- coverage --json
zig build run -- coverage tags hostinger
zig build run -- coverage tags cloudflare --json
zig build run -- coverage capture-candidates cloudflare Logs --limit 10 --json
zig build run -- coverage capture-candidates cloudflare --family logs --limit 10 --json
zig build run -- coverage dry-run-candidates cloudflare "AI Gateway" --limit 10 --json
zig build run -- coverage dry-run-candidates cloudflare --family security --limit 10 --json
zig build run -- coverage workplan cloudflare --limit 10 --json
zig build run -- coverage workplan cloudflare --focus control-plane --limit 10 --json
zig build run -- coverage routes hostinger VPS
zig build run -- coverage routes hostinger VPS --detail
zig build run -- coverage routes hostinger --family hostinger-vps --json
zig build run -- coverage routes hostinger --method GET --path /api/vps/v1/virtual-machines --json
zig build run -- coverage l1 all --json
zig build run -- coverage gaps all --limit 12
zig build run -- coverage gaps all --limit 12 --json
zig build run -- coverage priorities hostinger --limit=0
zig build run -- coverage levels all
zig build run -- coverage levels all --format json
zig build run -- coverage level-tags all --limit 12
zig build run -- coverage level-tags hostinger --limit 12 --json
zig build run -- coverage evidence hostinger --limit=0
zig build run -- coverage routes hostinger --support planned --mode read
zig build run -- coverage routes cloudflare --operation accounts-list-accounts --detail
zig build run -- coverage routes hostinger --method GET --path /api/vps/v1/virtual-machines --detail
zig build run -- coverage plan hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId=123 --query-param date_from=2026-06-16T00:00:00Z --query-param date_to=2026-06-17T00:00:00Z
zig build run -- coverage plan cloudflare --operation r2-get-event-notification-configs --path-param account_id=abc --path-param bucket_name=my-bucket --header-param cf-r2-jurisdiction=eu
zig build run -- coverage plan cloudflare --operation worker-assets-upload --path-param account_id=abc --query-param base64=true --body-content-type multipart/form-data
zig build run -- route plan hostinger --operation VPS_getVirtualMachinesV1
zig build run -- route read hostinger --operation VPS_getVirtualMachinesV1
zig build run -- route capture hostinger --operation VPS_getVirtualMachinesV1 --kind route-hostinger-vps --target vps
zig build run -- route capture cloudflare --operation accounts-list-accounts --kind route-cloudflare-accounts --target accounts --paginate --max-pages 5
zig build run -- route capture hostinger --operation VPS_getPublicKeysV1 --kind route-hostinger-public-keys --target public-keys --paginate --max-pages 5
zig build run -- route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json
zig build coverage-manifest
zig build coverage-check
```

`cloudio coverage` reads the checked-in generated manifests and prints local support/mode counts. Its JSON form exposes provider totals plus named support/mode count maps. `cloudio coverage tags [all|cloudflare|hostinger]` groups those counts by upstream tag so provider expansions can be reviewed by tag group; its JSON form emits one structured row per provider tag. `cloudio coverage l1 [all|cloudflare|hostinger]` audits every generated manifest row for L1 routability invariants: path-template/path-parameter agreement, response metadata, security metadata, GET/read dispatch shape, mutation dry-run shape, not-applicable/deprecated contracts, and absence of live write modes. Its JSON form exposes provider counters and every failure bucket as structured audit evidence. `cloudio coverage capture-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>]` lists generated bodyless `GET` routes with missing L2 capture evidence, required path/query/header placeholders, pagination hints, and a no-execute `cloudio route capture ...` command template; use it to choose and collect whole provider tag groups deliberately. `cloudio coverage dry-run-candidates [all|cloudflare|hostinger] [tag-query] [--family <family>] [--support <status>] [--limit <n>]`, also available as `coverage dry-run-plan` or `coverage mutation-candidates`, lists generated non-`GET` mutation routes with missing dry-run review evidence, required path/query/header placeholders, request-body content-type/schema metadata, and a no-execute `cloudio route dry-run ...` command template. `cloudio coverage workplan [all|cloudflare|hostinger] [--focus all|control-plane] [--family <family>] [--limit <n>]`, also available as `coverage slice-plan` or `coverage slices`, ranks unresolved provider tag groups and emits the exact `coverage routes`, `coverage capture-candidates`, and `coverage dry-run-candidates` commands needed to review each broad slice. Its `control-plane` focus keeps the same evidence scoring but filters to Cloudio-relevant API surfaces: accounts, zones, DNS, SSL/TLS, Access, tunnels, rulesets, logs, cache, security posture, tokens, memberships, Hostinger VPS, billing, domains, hosting, Docker, and provider security surfaces. `--family` narrows that same control-plane slice to a broad reviewable family such as `tokens`, `dns`, `security`, `access`, `cache`, `hostinger-vps`, or `docker`, and JSON rows include `focus_family` so a future UI can group slices without scraping tag strings. The same family selector also works on `coverage routes`, `coverage capture-candidates`, and `coverage dry-run-candidates`, filtering exact route and candidate rows through the shared app-level family classifier instead of CLI-only tag text. `cloudio coverage gaps [all|cloudflare|hostinger] [--limit <n>]`, also available as `coverage priorities`, ranks upstream tag groups by `planned_read + blocked_read + unsafe_dry_run`; it is a planning surface for broad slices, not a claim that those groups have typed collectors or write support. `cloudio coverage levels [all|cloudflare|hostinger]` summarizes manifest-backed L0 classified rows, L1 routable rows, L2 read evidence versus pending reads, dry-run evidence versus pending mutation dry-runs, and L3 generic/typed projection candidates by provider. `cloudio coverage level-tags [all|cloudflare|hostinger] [--limit <n>]`, also available as `coverage levels-by-tag` or `coverage evidence`, applies the same evidence accounting per upstream tag group and ranks by `pending_reads + diagnostic_blocked_reads + pending_mutation_dry_runs`; use `--limit=0` to print closed/evidence-only tag rows too. `coverage summary`, `coverage tags`, `coverage l1`, `coverage capture-candidates`, `coverage dry-run-candidates`, `coverage workplan`, `coverage gaps`, `coverage levels`, `coverage level-tags`, and `coverage routes` accept `--json` or `--format json` so future UI/API layers can consume the same review evidence without scraping text. The levels reports are review evidence from the generated manifest plus Cloudio support overlay, not final completion proof. `cloudio coverage routes [all|cloudflare|hostinger] [tag-query] [--family <family>] [--operation <id>] [--method <method>] [--path <template>] [--support <status>] [--mode <mode>] [--detail]` lists the exact manifest routes for a provider, optional tag substring, optional family, optional operation ID, optional exact method/path filters, optional support/mode filters, and, with `--detail`, the generated path/query/header parameters, parameter schema/style shapes, security alternatives, request body, and response status/schema metadata before implementation work begins. Its JSON form emits the same generated route contract as structured `routes` entries with parameters, body metadata, responses, security alternatives, support/mode, tests, and notes. These commands do not fetch upstream specs. Use `zig build api-summary` to fetch the latest official specs and print operation, security, live-auth-dispatch, L1 route-dispatch, parameter-shape, and tag counts. Use `zig build coverage-check` when you need to confirm those generated manifests still match the latest official OpenAPI sources.

`cloudio coverage families [all|cloudflare|hostinger] [--focus all|control-plane] [--limit <n>]`, also available as `coverage family-summary`, aggregates the level-tag evidence into Cloudio control-plane families and prints the matching `coverage workplan --family ...` command for each broad slice. Its JSON form emits `coverage_families` rows with provider, family, tag count, L0/L1/L2/L3 evidence, priority, and a family workplan command for future UI/API callers.

`cloudio coverage plan <provider> --operation <id>` selects one generated route and renders the provider-neutral no-execute request plan. For `GET`/`read` routes, the plan validates supplied `--path-param name=value`, `--query-param name=value`, and `--header-param name=value` values and prints the escaped provider URL without sending HTTP. Generated enum values and scalar schema types are enforced for path, query, and header parameters; booleans, integers, and numbers are checked before a plan is rendered, while string/object shapes remain permissive. Repeated `--query-param` values for array parameters are serialized through the generated OpenAPI `style`/`explode` metadata, including comma-joined `form` arrays when `explode=false`. Header values are not printed in plans. For mutation routes, the same command renders the generic `will_execute:false` dry-run plan with escaped path and provider URL, and accepts only body presence/content-type metadata through `--body-present` or `--body-content-type`; request bodies are never accepted, stored, or printed by this planner.

`cloudio route plan|read|capture|dry-run <provider> --operation <id>` is the first-class CLI surface for that same generated route contract. `route plan` is no-execute, `route read` executes only supported bodyless `GET`/read routes with configured credentials and emits response metadata without raw bodies, `route capture` executes the same safe read path while persisting the redacted response into `snapshots` and `provider_raw` plus a `route.capture` audit event, and `route dry-run` validates mutation inputs and emits `will_execute:false` plans without sending writes. `route capture --paginate --max-pages <n>` follows routes with generated optional `page` or `cursor` query parameters, recognizes Cloudflare offset `result_info`, Cloudflare cursor `result_info`, Cloudflare root cursor envelopes, and Hostinger `data/meta` page envelopes, stores each redacted page separately, and stops on non-2xx, missing pagination metadata, no next page, or the max-page cap. Page metadata includes the recognized `pagination_envelope` but never includes raw response bodies or cursor token values. It intentionally reuses the `coverage plan` argument grammar so future web/native UI code can call one provider-neutral request shape instead of one handwritten endpoint at a time.

`src/providers/routes.zig` also consumes these generated JSONL manifests as the provider-neutral route metadata source. It provides lookup by operation ID or method/path template, route support/mode/deprecation state, official path/query/header parameter requirements and schema/style shapes, OpenAPI security alternatives, request-body requirements, dry-run-safe body presence/content-type validation, response status/content/schema metadata, response matching for exact codes, status families, and default responses, path-placeholder extraction, required path/query/header validation, generated enum/scalar validation for path/query/header inputs, a reusable request object, and escaped path/query/URL rendering for Cloudflare and Hostinger without invoking HTTP. Query rendering honors generated array `style`/`explode` metadata when callers provide repeated query values. The coverage routes view now reuses this same route parser for detailed text and JSON output, so human review, future UI/API code, and generic dispatch inspect one route contract. Route tests assert that generated OpenAPI path parameters and path-template placeholders match for every checked-in provider route, so generic dispatch cannot silently ignore stray path keys or omit required path values. `src/providers/dispatch.zig` uses that metadata to validate official auth requirements, execute bodyless generic `GET`/`read` calls through provider auth or Cloudflare public reads when the spec marks auth optional, attach generated response metadata to read results, render metadata-only read-result JSON without printing raw response bodies, and render request/response-aware `will_execute:false` dry-run plans with full provider URLs for mutation routes without storing or printing body contents. Plans include a dispatch capability object so future UI/API callers can distinguish live read support from dry-run mutation support even when a mutation uses an auth scheme Cloudio cannot execute live. Dispatch keeps the raw OpenAPI security alternatives visible, but explicitly treats Cloudflare `bearerAuth` as API-token bearer auth and treats the combined `api_email+api_key+api_token` requirement shape as compatible with either API-token bearer auth or legacy email/global-key auth because those are the Cloudflare credential forms Cloudio can send.

The manifest is intentionally conservative:

- upstream `GET` operations default to `planned` / `read`
- upstream `GET` operations with `requestBody.required=true` default to `not_applicable` / `none` because generic read dispatch only sends bodyless GET requests
- upstream non-`GET` operations default to `unsafe_mutation` / `dry_run`
- upstream deprecated operations default to `deprecated` / `none`
- known POC routes are overlaid from `coverage/overrides/*.jsonl` as `partial`, `blocked_permission`, `not_applicable`, or another explicit support status
- spec/transport contradictions are marked `not_applicable` instead of left as open-ended planned work when Cloudio intentionally does not model the upstream contract
- `path_params`, `query_params`, and `header_params` are generated from operation/path-level OpenAPI parameters, including shared `$ref` entries under `components.parameters`, with `style`, `explode`, schema refs, schema types, formats, and enum values
- `request_body` is generated from inline or shared OpenAPI request bodies and records whether a body is required, accepted content types, and schema references
- `responses` is generated from inline or shared OpenAPI responses and records status, content types, and schema references
- `security` is generated from operation-level OpenAPI security with root security fallback and records whether auth is required plus acceptable scheme alternatives. Generated rows keep Cloudflare combined auth scheme bundles and named `bearerAuth` alternatives intact; provider dispatch owns the explicit API-token/legacy compatibility mapping.

Normal `zig build test` stays offline; coverage generation and checks are explicit networked steps.

Override rows are validated during generation:

- `method` must be uppercase
- `method` + `path` must be unique per provider file
- `support` and `mode` must use the allowed coverage vocabulary
- generated `path_params`, `query_params`, and `header_params` must be arrays of objects with `name`, `required`, `style`, `explode`, and schema summary metadata
- generated `request_body` must be an object with `required`, `content_types`, and `schema_refs`
- generated `responses` must be arrays of `{status, content_types, schema_refs}` objects
- generated `security` must be an object with `required` and nested scheme alternatives
- every override must still match an operation in the latest official OpenAPI spec
- generated path parameters must match the placeholders in the generated path template
