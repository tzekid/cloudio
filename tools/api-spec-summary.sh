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

security_counts() {
  jq -r '
    . as $root
    | [
        .paths
        | to_entries[]
        | .value
        | to_entries[]
        | select(.value | type == "object")
        | (.value.security // $root.security // []) as $security
        | if ($security | length) == 0 then
            "<anonymous>"
          else
            ($security
              | map(
                  (keys | sort) as $schemes
                  | if ($schemes | length) == 0 then "<anonymous>" else ($schemes | join("+")) end
                )
              | join(" OR "))
          end
      ]
    | group_by(.)
    | map({security: .[0], count: length})
    | sort_by(-.count, .security)[]
    | "\(.count)\t\(.security)"
  '
}

auth_dispatch_counts() {
  provider="$1"
  jq -r --arg provider "$provider" '
    def sorted_keys: keys | sort;
    def has_cf_token_or_legacy_bundle($schemes):
      ($schemes == ["api_email", "api_key", "api_token"]);
    def cf_requirement_supported($requirement):
      ($requirement | sorted_keys) as $schemes
      | ($schemes | length) == 0 or
        ($schemes == ["api_token"]) or
        ($schemes == ["bearerAuth"]) or
        ($schemes == ["api_email", "api_key"]) or
        has_cf_token_or_legacy_bundle($schemes);
    def hostinger_requirement_supported($requirement):
      ($requirement | sorted_keys) as $schemes
      | ($schemes | length) == 0 or ($schemes == ["apiToken"]);
    def requirement_supported($provider; $requirement):
      if $provider == "cloudflare" then
        cf_requirement_supported($requirement)
      else
        hostinger_requirement_supported($requirement)
      end;
    . as $root
    | [
        .paths
        | to_entries[]
        | .value
        | to_entries[]
        | select(.value | type == "object")
        | (.value.security // $root.security // []) as $security
        | if ($security | length) == 0 then
            "supported"
          elif any($security[]; requirement_supported($provider; .)) then
            "supported"
          else
            "unsupported"
          end
      ]
    | group_by(.)
    | map({support: .[0], count: length})
    | sort_by(.support)[]
    | "\(.support)=\(.count)"
  '
}

route_dispatch_counts() {
  provider="$1"
  jq -r --arg provider "$provider" '
    def pointer_token:
      gsub("~1"; "/") | gsub("~0"; "~");
    def deref($root):
      if (type == "object") and has("$ref") then
        (."$ref" | sub("^#/"; "") | split("/") | reduce .[] as $part ($root; .[$part | pointer_token]))
      else
        .
      end;
    def sorted_keys: keys | sort;
    def has_cf_token_or_legacy_bundle($schemes):
      ($schemes == ["api_email", "api_key", "api_token"]);
    def cf_requirement_supported($requirement):
      ($requirement | sorted_keys) as $schemes
      | ($schemes | length) == 0 or
        ($schemes == ["api_token"]) or
        ($schemes == ["bearerAuth"]) or
        ($schemes == ["api_email", "api_key"]) or
        has_cf_token_or_legacy_bundle($schemes);
    def hostinger_requirement_supported($requirement):
      ($requirement | sorted_keys) as $schemes
      | ($schemes | length) == 0 or ($schemes == ["apiToken"]);
    def requirement_supported($provider; $requirement):
      if $provider == "cloudflare" then
        cf_requirement_supported($requirement)
      else
        hostinger_requirement_supported($requirement)
      end;
    def auth_supported($provider; $root; $operation):
      ($operation.security // $root.security // []) as $security
      | ($security | length) == 0 or any($security[]; requirement_supported($provider; .));
    def body_required($root; $operation):
      (($operation.requestBody // {} | deref($root) | .required) == true);
    . as $root
    | [
        .paths
        | to_entries[]
        | .value
        | to_entries[]
        | select(.value | type == "object")
        | .key as $method
        | .value as $operation
        | if ($operation.deprecated // false) then
            "deprecated"
          elif ($method == "get" and body_required($root; $operation)) then
            "not_applicable"
          elif ($method == "get") then
            if auth_supported($provider; $root; $operation) then "live_read_supported" else "live_read_unsupported" end
          else
            "dry_run_supported"
          end
      ]
    | group_by(.)
    | map({support: .[0], count: length})
    | sort_by(.support)[]
    | "\(.support)=\(.count)"
  '
}

parameter_shape_summary() {
  jq -r '
    def pointer_token:
      gsub("~1"; "/") | gsub("~0"; "~");
    def deref($root):
      if (type == "object") and has("$ref") then
        (."$ref" | sub("^#/"; "") | split("/") | reduce .[] as $part ($root; .[$part | pointer_token]))
      else
        .
      end;
    . as $root
    | [
        .paths
        | to_entries[]
        | .value as $path_item
        | $path_item
        | to_entries[]
        | select(.value | type == "object")
        | .value as $operation
        | (($path_item.parameters // []) + ($operation.parameters // []))[]?
        | deref($root)
      ] as $params
    | {
        total: ($params | length),
        with_schema: ($params | map(select(.schema? != null)) | length),
        with_style: ($params | map(select(.style? != null)) | length),
        with_explode: ($params | map(select(.explode? != null)) | length),
        array_params: ($params | map(select((.schema.type? // "") == "array")) | length),
        enum_params: ($params | map(select((.schema.enum? // []) | length > 0)) | length)
      }
    | to_entries[]
    | "\(.key)=\(.value)"
  '
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

printf '\nprovider_security\n'
printf 'cloudflare\n'
security_counts < "$cloudflare_spec"
printf 'hostinger\n'
security_counts < "$hostinger_spec"

printf '\nprovider_auth_dispatch\n'
printf 'cloudflare\n'
auth_dispatch_counts cloudflare < "$cloudflare_spec"
printf 'hostinger\n'
auth_dispatch_counts hostinger < "$hostinger_spec"

printf '\nprovider_l1_dispatch\n'
printf 'cloudflare\n'
route_dispatch_counts cloudflare < "$cloudflare_spec"
printf 'hostinger\n'
route_dispatch_counts hostinger < "$hostinger_spec"

printf '\nprovider_parameter_shapes\n'
printf 'cloudflare\n'
parameter_shape_summary < "$cloudflare_spec"
printf 'hostinger\n'
parameter_shape_summary < "$hostinger_spec"

printf '\nhostinger_tags\n'
tag_counts < "$hostinger_spec"

printf '\ncloudflare_tags_top_80\n'
tag_counts < "$cloudflare_spec" | sed -n '1,80p'
