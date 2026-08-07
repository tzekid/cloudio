# Provider coverage

Status: current developer and operator contract. This document intentionally
contains no static route totals; checked manifests and commands are the source
of truth.

## Purpose

Cloudio tracks Cloudflare and Hostinger OpenAPI routes so provider work begins
from an exact upstream contract. The manifests support:

- route discovery and filtering;
- required path, query, header, body, response, and security metadata;
- provider-neutral no-execute request planning;
- explicitly invoked bodyless read and redacted capture workflows; and
- evidence review for the typed collectors and product features Cloudio
  actually uses.

Coverage is not a promise to expose every provider operation. Counts show what
has been classified or evidenced; they do not prove that Dashboard, DNS, VPS,
or another product workflow is complete.

## Sources of truth

```text
official OpenAPI documents
  -> tools/provider-coverage-manifest.sh
  -> coverage/generated/{cloudflare,hostinger}.jsonl
       plus coverage/generated/metadata.json

coverage/overrides/{cloudflare,hostinger}.jsonl
  -> reviewed Cloudio support, mode, tests, and notes

src/providers/routes.zig
  -> runtime parser and validation contract
```

Generated files are checked in so normal builds and reviews stay offline and
reproducible. Overrides must still match an upstream method and path when the
manifest is regenerated.

## Classification

Allowed support values:

- `implemented`: a current typed or generic contract exists;
- `partial`: useful support exists with a documented boundary;
- `planned`: upstream read route is classified but not evidenced;
- `blocked_permission`: safe observation is known to be unavailable with the
  configured provider capability;
- `unsafe_mutation`: mutation is visible only for no-execute review;
- `deprecated`: upstream marks the route deprecated; and
- `not_applicable`: Cloudio deliberately does not model the route.

Allowed modes are `read`, `dry_run`, `write`, and `none`. Generated
non-GET operations default to `unsafe_mutation` / `dry_run`; this is a
planning classification, not write authority.

Evidence levels are review aids:

- L0: the route is classified;
- L1: parameters, auth, body, and responses form a valid request contract;
- L2: a controlled fixture, diagnostic result, or redacted live capture exists;
- L3: provider data is normalized into a useful generic or typed projection.

Only the relevant product acceptance workflow proves product behavior.

## Local review

These commands read checked-in manifests and local SQLite evidence:

```sh
cloudio coverage summary --json
cloudio coverage routes cloudflare --family dns --detail
cloudio coverage levels all --json
cloudio coverage families all --focus control-plane
cloudio coverage actual-captures hostinger --family hostinger-vps --plans

cloudio routes cloudflare dns --json
cloudio route plan cloudflare --operation <operation-id>
cloudio route read cloudflare --operation <operation-id>
cloudio route capture cloudflare --operation <operation-id>
cloudio route dry-run cloudflare --operation <operation-id> --body-present
```

`route plan` never performs I/O. `route read` and `route capture` accept
only supported bodyless GET/read contracts and configured authentication.
`route capture` stores redacted response evidence and metadata. Pagination is
bounded by an explicit maximum. Header values and raw bodies are not printed in
plans.

`route dry-run` accepts body presence and content-type metadata, not arbitrary
body content, and emits `will_execute:false`. There is no generic generated
live-mutation dispatcher.

Product writes remain a separate fixed typed allowlist in
`src/app/provider_writes.zig`; adding or reclassifying a manifest row cannot
authorize a write.

Use `cloudio coverage help` and `cloudio route help` for the complete,
current filter and parameter grammar.

## Upstream refresh

These commands access the network and are deliberately excluded from normal
build and test gates:

```sh
zig build api-summary
zig build coverage-manifest
zig build coverage-check
```

`api-summary` prints current upstream shape without changing files.
`coverage-manifest` regenerates the checked artifacts.
`coverage-check` regenerates into a temporary directory and compares it with
the repository.

Environment variables may replace the official spec URLs or output directory
for controlled review; see `tools/provider-coverage-manifest.sh`.

## Definition of done for a provider change

A provider change is done when:

1. The exact upstream route and auth/body/response shape has been reviewed.
2. Any override is narrow, truthful, and still matches the official spec.
3. Generated artifacts change only when upstream input or a reviewed override
   changed.
4. A read has a controlled fixture or deliberately redacted capture; a product
   mutation has an end-to-end product workflow.
5. Unsafe and destructive behavior remains outside generic dispatch.
6. `zig build --system zig-pkg check` passes offline.
7. `zig build coverage-check` passes when the change is specifically about
   upstream coverage.

Do not add a new family classifier, workplan alias, JSON field, or typed wrapper
solely for a hypothetical consumer. Extend the smallest existing owner only
when a current operator or product workflow needs it.
