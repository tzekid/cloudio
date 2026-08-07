# Checked provider manifests

This directory contains reproducible OpenAPI-derived route metadata:

```text
overrides/cloudflare.jsonl
overrides/hostinger.jsonl
generated/cloudflare.jsonl
generated/hostinger.jsonl
generated/metadata.json
```

`overrides/` is the reviewed input Cloudio owns. `generated/` combines that
input with the official Cloudflare and Hostinger OpenAPI documents. Generated
files are committed so application builds and tests do not need network access.

Regenerate or compare them only with the explicit networked steps:

```sh
zig build coverage-manifest
zig build coverage-check
```

Do not hand-edit `generated/`. Do not treat row counts as product-completion
metrics, and do not use a generated mutation row as live-write authority.

The classification, safety contract, review commands, and definition of done
are maintained once in
[docs/provider-coverage.md](../docs/provider-coverage.md).
