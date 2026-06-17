# Provider Coverage Manifests

`coverage/generated/*.jsonl` is generated from the official Cloudflare and Hostinger OpenAPI specs.
`coverage/overrides/*.jsonl` is the hand-reviewed Cloudio support overlay for routes the POC implements, partially implements, or cannot exercise with the current account/token.

Use:

```sh
zig build run -- coverage
zig build run -- coverage tags hostinger
zig build run -- coverage routes hostinger VPS
zig build run -- coverage routes hostinger VPS --detail
zig build run -- coverage routes hostinger --support planned --mode read
zig build run -- coverage routes cloudflare --operation accounts-list-accounts --detail
zig build run -- coverage routes hostinger --method GET --path /api/vps/v1/virtual-machines --detail
zig build run -- coverage plan hostinger --operation VPS_getMetricsV1 --path-param virtualMachineId=123 --query-param date_from=2026-06-16T00:00:00Z --query-param date_to=2026-06-17T00:00:00Z
zig build run -- coverage plan cloudflare --operation worker-assets-upload --path-param account_id=abc --query-param base64=true --body-content-type multipart/form-data
zig build coverage-manifest
zig build coverage-check
```

`cloudio coverage` reads the checked-in generated manifests and prints local support/mode counts. `cloudio coverage tags [all|cloudflare|hostinger]` groups those counts by upstream tag so provider expansions can be reviewed by tag group. `cloudio coverage routes [all|cloudflare|hostinger] [tag-query] [--operation <id>] [--method <method>] [--path <template>] [--support <status>] [--mode <mode>] [--detail]` lists the exact manifest routes for a provider, optional tag substring, optional operation ID, optional exact method/path filters, optional support/mode filters, and, with `--detail`, the generated path/query parameters, request body, and response status/schema metadata before implementation work begins. These commands do not fetch upstream specs. Use `zig build coverage-check` when you need to confirm those generated manifests still match the latest official OpenAPI sources.

`cloudio coverage plan <provider> --operation <id>` selects one generated route and renders the provider-neutral no-execute request plan. For `GET`/`read` routes, the plan validates supplied `--path-param name=value` and `--query-param name=value` values and prints the escaped provider URL without sending HTTP. For mutation routes, the same command renders the generic `will_execute:false` dry-run plan and accepts only body presence/content-type metadata through `--body-present` or `--body-content-type`; request bodies are never accepted, stored, or printed by this planner.

`src/providers/routes.zig` also consumes these generated JSONL manifests as the provider-neutral route metadata source. It provides lookup by operation ID or method/path template, route support/mode/deprecation state, official path/query parameter requirements, request-body requirements, dry-run-safe body presence/content-type validation, response status/content/schema metadata, response matching for exact codes, status families, and default responses, path-placeholder extraction, required path/query validation, a reusable path/query request object, and escaped path/query/URL rendering for Cloudflare and Hostinger without invoking HTTP. The coverage routes view now reuses this same route parser for detailed output, so human review and generic dispatch inspect one route contract. Route tests assert that generated OpenAPI path parameters and path-template placeholders match for every checked-in provider route, so generic dispatch cannot silently ignore stray path keys or omit required path values. `src/providers/dispatch.zig` uses that metadata to execute bodyless generic `GET`/`read` calls through provider auth, attach generated response metadata to read results, render metadata-only read-result JSON without printing raw response bodies, and render request/response-aware `will_execute:false` dry-run plans for mutation routes without storing or printing body contents.

The manifest is intentionally conservative:

- upstream `GET` operations default to `planned` / `read`
- upstream `GET` operations with `requestBody.required=true` default to `not_applicable` / `none` because generic read dispatch only sends bodyless GET requests
- upstream non-`GET` operations default to `unsafe_mutation` / `dry_run`
- upstream deprecated operations default to `deprecated` / `none`
- known POC routes are overlaid from `coverage/overrides/*.jsonl` as `partial`, `blocked_permission`, `not_applicable`, or another explicit support status
- spec/transport contradictions are marked `not_applicable` instead of left as open-ended planned work when Cloudio intentionally does not model the upstream contract
- `path_params` and `query_params` are generated from operation/path-level OpenAPI parameters, including shared `$ref` entries under `components.parameters`
- `request_body` is generated from inline or shared OpenAPI request bodies and records whether a body is required, accepted content types, and schema references
- `responses` is generated from inline or shared OpenAPI responses and records status, content types, and schema references

Normal `zig build test` stays offline; coverage generation and checks are explicit networked steps.

Override rows are validated during generation:

- `method` must be uppercase
- `method` + `path` must be unique per provider file
- `support` and `mode` must use the allowed coverage vocabulary
- generated `path_params` and `query_params` must be arrays of `{name, required}` objects
- generated `request_body` must be an object with `required`, `content_types`, and `schema_refs`
- generated `responses` must be arrays of `{status, content_types, schema_refs}` objects
- every override must still match an operation in the latest official OpenAPI spec
- generated path parameters must match the placeholders in the generated path template
