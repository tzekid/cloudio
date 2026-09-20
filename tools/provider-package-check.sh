#!/bin/sh
set -eu

name=${1:-}
case "$name" in
    cloudflare|hostinger) ;;
    *)
        printf '%s\n' "usage: $0 cloudflare|hostinger" >&2
        exit 2
        ;;
esac

package_dir="packages/$name"
test -f "$package_dir/build.zig"
test -f "$package_dir/build.zig.zon"
test -f "$package_dir/LICENSE"
test -f "$package_dir/README.md"

if ! command -v rg >/dev/null 2>&1; then
    printf '%s\n' "provider-package-check requires ripgrep" >&2
    exit 1
fi

(
    cd "$package_dir"
    zig build test
)

if rg -q --hidden \
    --glob '!zig-cache/**' \
    --glob '!.zig-cache/**' \
    --glob '!README.md' \
    --glob '!*.zig' \
    '(-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----|CLOUDFLARE_API_TOKEN=|HOSTINGER_API_TOKEN=)' \
    "$package_dir"; then
    printf '%s\n' "provider package contains secret-like material: $name" >&2
    exit 1
else
    scan_status=$?
    if [ "$scan_status" -ne 1 ]; then
        printf '%s\n' "provider package scan failed: $name" >&2
        exit "$scan_status"
    fi
fi

printf '%s\n' "provider-package-check: $name passed"
