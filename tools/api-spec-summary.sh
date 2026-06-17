#!/usr/bin/env sh
set -eu

CLOUDFLARE_OPENAPI_URL="${CLOUDFLARE_OPENAPI_URL:-https://raw.githubusercontent.com/cloudflare/api-schemas/main/openapi.json}"
HOSTINGER_OPENAPI_URL="${HOSTINGER_OPENAPI_URL:-https://raw.githubusercontent.com/hostinger/api/main/openapi.json}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

operation_count() {
  jq '[.paths | to_entries[] | .value | to_entries[] | select(.value | type == "object")] | length'
}

tag_counts() {
  jq -r '.paths | to_entries[] | .value | to_entries[] | select(.value | type == "object") | (.value.tags[0] // "untagged")' |
    sort |
    uniq -c |
    sort -nr
}

need curl
need jq

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cloudflare_spec="$tmpdir/cloudflare-openapi.json"
hostinger_spec="$tmpdir/hostinger-openapi.json"

curl -fsSL "$CLOUDFLARE_OPENAPI_URL" -o "$cloudflare_spec"
curl -fsSL "$HOSTINGER_OPENAPI_URL" -o "$hostinger_spec"

printf 'Cloudio provider API summary\n'
printf 'checked_at=%s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

printf 'sources\n'
printf 'cloudflare=%s\n' "$CLOUDFLARE_OPENAPI_URL"
printf 'hostinger=%s\n\n' "$HOSTINGER_OPENAPI_URL"

printf 'operation_counts\n'
printf 'cloudflare='
operation_count < "$cloudflare_spec"
printf 'hostinger='
operation_count < "$hostinger_spec"

printf '\nhostinger_tags\n'
tag_counts < "$hostinger_spec"

printf '\ncloudflare_tags_top_80\n'
tag_counts < "$cloudflare_spec" | sed -n '1,80p'
