# Provider Coverage Manifests

`coverage/generated/*.jsonl` is generated from the official Cloudflare and Hostinger OpenAPI specs.
`coverage/overrides/*.jsonl` is the hand-reviewed Cloudio support overlay for routes the POC implements, partially implements, or cannot exercise with the current account/token.

Use:

```sh
zig build run -- coverage
zig build run -- coverage tags hostinger
zig build run -- coverage routes hostinger VPS
zig build run -- coverage routes hostinger --support planned --mode read
zig build coverage-manifest
zig build coverage-check
```

`cloudio coverage` reads the checked-in generated manifests and prints local support/mode counts. `cloudio coverage tags [all|cloudflare|hostinger]` groups those counts by upstream tag so provider expansions can be reviewed by tag group. `cloudio coverage routes [all|cloudflare|hostinger] [tag-query] [--support <status>] [--mode <mode>]` lists the exact manifest routes for a provider, optional tag substring, and optional support/mode filters before implementation work begins. These commands do not fetch upstream specs. Use `zig build coverage-check` when you need to confirm those generated manifests still match the latest official OpenAPI sources.

`src/providers/routes.zig` also consumes these generated JSONL manifests as the provider-neutral route metadata source. It provides lookup by operation ID or method/path template, route support/mode/deprecation state, official path/query parameter requirements, path-placeholder extraction, required-query validation, and escaped path/query/URL rendering for Cloudflare and Hostinger without invoking HTTP. `src/providers/dispatch.zig` uses that metadata to execute generic `GET`/`read` calls through provider auth and to render `will_execute:false` dry-run plans for mutation routes.

The manifest is intentionally conservative:

- upstream `GET` operations default to `planned` / `read`
- upstream non-`GET` operations default to `unsafe_mutation` / `dry_run`
- upstream deprecated operations default to `deprecated` / `none`
- known POC routes are overlaid from `coverage/overrides/*.jsonl` as `partial`, `blocked_permission`, `not_applicable`, or another explicit support status
- spec/transport contradictions are marked `not_applicable` instead of left as open-ended planned work when Cloudio intentionally does not model the upstream contract
- `path_params` and `query_params` are generated from operation/path-level OpenAPI parameters, including shared `$ref` entries under `components.parameters`

Normal `zig build test` stays offline; coverage generation and checks are explicit networked steps.

Override rows are validated during generation:

- `method` must be uppercase
- `method` + `path` must be unique per provider file
- `support` and `mode` must use the allowed coverage vocabulary
- generated `path_params` and `query_params` must be arrays of `{name, required}` objects
- every override must still match an operation in the latest official OpenAPI spec
