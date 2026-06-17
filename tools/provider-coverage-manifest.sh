#!/usr/bin/env sh
set -eu

CLOUDFLARE_OPENAPI_URL="${CLOUDFLARE_OPENAPI_URL:-https://raw.githubusercontent.com/cloudflare/api-schemas/main/openapi.json}"
HOSTINGER_OPENAPI_URL="${HOSTINGER_OPENAPI_URL:-https://raw.githubusercontent.com/hostinger/api/main/openapi.json}"
COVERAGE_OVERRIDE_DIR="${COVERAGE_OVERRIDE_DIR:-coverage/overrides}"
MODE="${1:-generate}"
OUT_DIR="${2:-coverage/generated}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

operation_count() {
  jq '[.paths | to_entries[] | .value | to_entries[] | select(.value | type == "object")] | length'
}

validate_overrides() {
  file="$1"
  if [ ! -f "$file" ]; then
    printf 'missing provider coverage overrides: %s\n' "$file" >&2
    exit 1
  fi
  jq -e -s '
    def valid_support:
      ["implemented", "partial", "planned", "blocked_permission", "unsafe_mutation", "deprecated", "not_applicable"];
    def valid_mode:
      ["read", "dry_run", "write", "none"];
    all(.[]; . as $row | (
      ($row.method | type == "string") and
      ($row.method == ($row.method | ascii_upcase)) and
      ($row.path | type == "string") and
      (valid_support | index($row.support)) and
      (valid_mode | index($row.mode)) and
      ($row.tests | type == "string") and
      ($row.notes | type == "string")
    )) and
    ((map(.method + " " + .path) | length) == (map(.method + " " + .path) | unique | length))
  ' "$file" >/dev/null
}

validate_override_matches_spec() {
  provider="$1"
  spec="$2"
  overrides="$3"
  jq -e --arg provider "$provider" --slurpfile overrides "$overrides" '
    [
      .paths
      | to_entries[]
      | .key as $path
      | .value
      | to_entries[]
      | select(.value | type == "object")
      | { method: (.key | ascii_upcase), path: $path }
    ] as $operations
    | all($overrides[]; . as $override |
      any($operations[]; .method == $override.method and .path == $override.path)
    )
  ' "$spec" >/dev/null || {
    printf 'provider coverage override no longer matches official spec: %s (%s)\n' "$overrides" "$provider" >&2
    exit 1
  }
}

generate_manifest() {
  provider="$1"
  spec="$2"
  overrides="$3"
  out="$4"
  jq -c --arg provider "$provider" --slurpfile overrides "$overrides" '
    def default_coverage($method; $deprecated):
      if $deprecated then
        {
          support: "deprecated",
          mode: "none",
          tests: "missing",
          notes: "Upstream marks this operation deprecated."
        }
      elif $method == "get" then
        {
          support: "planned",
          mode: "read",
          tests: "missing",
          notes: "Read-only endpoint exists upstream but Cloudio does not implement it yet."
        }
      else
        {
          support: "unsafe_mutation",
          mode: "dry_run",
          tests: "missing",
          notes: "Mutation endpoint requires explicit dry-run/write policy before implementation."
        }
      end;

    def override_coverage($method; $path):
      [ $overrides[] | select(.method == ($method | ascii_upcase) and .path == $path) ][0] // null;

    .paths
    | to_entries[]
    | .key as $path
    | .value
    | to_entries[]
    | select(.value | type == "object")
    | .key as $method
    | (.value.deprecated // false) as $deprecated
    | (override_coverage($method; $path) // default_coverage($method; $deprecated)) as $coverage
    | {
        provider: $provider,
        tag: (.value.tags[0] // "untagged"),
        method: ($method | ascii_upcase),
        path: $path,
        operation_id: (.value.operationId // null),
        support: $coverage.support,
        mode: $coverage.mode,
        tests: $coverage.tests,
        deprecated: $deprecated,
        notes: $coverage.notes
      }
  ' "$spec" | sort > "$out"
}

validate_manifest() {
  file="$1"
  jq -e -s '
    all(.[]; (. as $row | (
      ($row.provider | type == "string") and
      ($row.tag | type == "string") and
      ($row.method | type == "string") and
      ($row.path | type == "string") and
      (($row.operation_id == null) or ($row.operation_id | type == "string")) and
      (["implemented", "partial", "planned", "blocked_permission", "unsafe_mutation", "deprecated", "not_applicable"] | index($row.support)) and
      (["read", "dry_run", "write", "none"] | index($row.mode)) and
      ($row.tests | type == "string") and
      ($row.deprecated | type == "boolean") and
      ($row.notes | type == "string")
    )))
  ' "$file" >/dev/null
}

generate_all() {
  dest="$1"
  mkdir -p "$dest"
  spec_tmpdir="$(mktemp -d)"

  cloudflare_spec="$spec_tmpdir/cloudflare-openapi.json"
  hostinger_spec="$spec_tmpdir/hostinger-openapi.json"
  cloudflare_overrides="$COVERAGE_OVERRIDE_DIR/cloudflare.jsonl"
  hostinger_overrides="$COVERAGE_OVERRIDE_DIR/hostinger.jsonl"

  validate_overrides "$cloudflare_overrides"
  validate_overrides "$hostinger_overrides"

  curl -fsSL "$CLOUDFLARE_OPENAPI_URL" -o "$cloudflare_spec"
  curl -fsSL "$HOSTINGER_OPENAPI_URL" -o "$hostinger_spec"

  validate_override_matches_spec "cloudflare" "$cloudflare_spec" "$cloudflare_overrides"
  validate_override_matches_spec "hostinger" "$hostinger_spec" "$hostinger_overrides"

  cloudflare_count="$(operation_count < "$cloudflare_spec")"
  hostinger_count="$(operation_count < "$hostinger_spec")"

  jq -n \
    --arg cloudflare_url "$CLOUDFLARE_OPENAPI_URL" \
    --arg hostinger_url "$HOSTINGER_OPENAPI_URL" \
    --arg cloudflare_overrides "$cloudflare_overrides" \
    --arg hostinger_overrides "$hostinger_overrides" \
    --argjson cloudflare_operations "$cloudflare_count" \
    --argjson hostinger_operations "$hostinger_count" \
    '{
      schema_version: 1,
      sources: {
        cloudflare: $cloudflare_url,
        hostinger: $hostinger_url
      },
      operation_counts: {
        cloudflare: $cloudflare_operations,
        hostinger: $hostinger_operations
      },
      overrides: {
        cloudflare: $cloudflare_overrides,
        hostinger: $hostinger_overrides
      },
      classification_defaults: {
        "GET": "planned/read",
        "non-GET": "unsafe_mutation/dry_run",
        "deprecated": "deprecated/none"
      }
    }' > "$dest/metadata.json"

  generate_manifest cloudflare "$cloudflare_spec" "$cloudflare_overrides" "$dest/cloudflare.jsonl"
  generate_manifest hostinger "$hostinger_spec" "$hostinger_overrides" "$dest/hostinger.jsonl"
  validate_manifest "$dest/cloudflare.jsonl"
  validate_manifest "$dest/hostinger.jsonl"
  rm -rf "$spec_tmpdir"
}

need curl
need jq
need sort

case "$MODE" in
  generate)
    generate_all "$OUT_DIR"
    ;;
  check)
    if [ ! -f "$OUT_DIR/metadata.json" ] || [ ! -f "$OUT_DIR/cloudflare.jsonl" ] || [ ! -f "$OUT_DIR/hostinger.jsonl" ]; then
      printf 'coverage manifest missing; run: zig build coverage-manifest\n' >&2
      exit 1
    fi
    check_dir="$(mktemp -d)"
    trap 'rm -rf "$check_dir"' EXIT
    generate_all "$check_dir"
    diff -u "$OUT_DIR/metadata.json" "$check_dir/metadata.json"
    diff -u "$OUT_DIR/cloudflare.jsonl" "$check_dir/cloudflare.jsonl"
    diff -u "$OUT_DIR/hostinger.jsonl" "$check_dir/hostinger.jsonl"
    ;;
  *)
    printf 'usage: %s [generate|check] [out-dir]\n' "$0" >&2
    exit 2
    ;;
esac
