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

(
    cd "$package_dir"
    zig build test
)

if rg -n --hidden \
    --glob '!zig-cache/**' \
    --glob '!.zig-cache/**' \
    --glob '!README.md' \
    --glob '!*.zig' \
    '(-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----|CLOUDFLARE_API_TOKEN=|HOSTINGER_API_TOKEN=)' \
    "$package_dir"; then
    printf '%s\n' "provider package contains secret-like material: $name" >&2
    exit 1
fi

printf '%s\n' "provider-package-check: $name passed"
