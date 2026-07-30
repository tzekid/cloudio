#!/bin/sh
set -eu

fail=0

check_no_matches() {
    description=$1
    pattern=$2
    shift 2
    if rg -n "$pattern" "$@" >/dev/null; then
        printf '%s\n' "architecture-check failed: $description" >&2
        rg -n "$pattern" "$@" >&2
        fail=1
    fi
}

if [ -e src/providers/capture.zig ]; then
    printf '%s\n' "architecture-check failed: capture persistence belongs under src/collectors, not src/providers" >&2
    fail=1
fi

if [ -e src/app/serve.zig ]; then
    printf '%s\n' "architecture-check failed: HTTP runtime belongs under src/server, not src/app/serve.zig" >&2
    fail=1
fi

for package in cloudflare hostinger; do
    if [ ! -f "packages/$package/build.zig" ] || [ ! -f "packages/$package/LICENSE" ]; then
        printf '%s\n' "architecture-check failed: packages/$package is not independently buildable and licensed" >&2
        fail=1
    fi
done

check_no_matches \
    "core and net modules must not import persistence, provider, collector, app, CLI, or sqlite modules" \
    '@import\("(db_[^"]+|sqlite|collector_[^"]+|provider_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/core src/net

check_no_matches \
    "the reusable inbound HTTP package must not import Cloudio app, persistence, provider, collector, CLI, or sqlite modules" \
    '@import\("(db_[^"]+|sqlite|collector_[^"]+|provider_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/http

check_no_matches \
    "database modules must not import provider, collector, app, or CLI modules" \
    '@import\("(collector_[^"]+|provider_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/db

check_no_matches \
    "provider modules must not import persistence, collector, app, CLI, or sqlite modules" \
    '@import\("(db_store|sqlite|collector_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/providers

check_no_matches \
    "standalone provider packages must not import Cloudio app, persistence, collector, CLI, or sqlite modules" \
    '@import\("(db_[^"]+|sqlite|collector_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    packages/cloudflare/src packages/hostinger/src

check_no_matches \
    "collector modules must not import app or CLI modules" \
    '@import\("(app_[^"]+|cli_[^"]+)"\)' \
    src/collectors

check_no_matches \
    "collector modules must not write directly to terminal output" \
    'std\.debug\.print' \
    src/collectors

check_no_matches \
    "app modules must not import CLI modules" \
    '@import\("(cli_[^"]+)"\)' \
    src/app

check_no_matches \
    "HTTP handlers must delegate persistence, provider, and process work to application services" \
    '@import\("(db_[^"]+|sqlite|provider_[^"]+|core_process)"\)|\b(SELECT|INSERT|UPDATE|DELETE FROM|CREATE TABLE)\b' \
    src/server/handlers

check_no_matches \
    "app modules must not expose collector-owned Output types" \
    'pub const Output = collector_' \
    src/app

check_no_matches \
    "provider app modules must expose provider contracts directly, not through collectors" \
    'pub const [A-Za-z0-9_]+ = collector_(cloudflare|hostinger)\.' \
    src/app/cloudflare.zig src/app/hostinger.zig

check_no_matches \
    "provider-specific app row lists must use app/provider_list.zig" \
    '(cloudflare|hostinger)(Resource|InventoryItem)List' \
    src/app/cloudflare.zig src/app/hostinger.zig

check_no_matches \
    "app provider identity and filters must reuse provider_routes" \
    'pub const Provider(Filter)? = enum' \
    src/app/provider_list.zig src/app/inventory.zig src/app/coverage.zig

check_no_matches \
    "collector output container belongs in core/output.zig" \
    'pub const Output = struct' \
    src/collectors

check_no_matches \
    "CLI modules must delegate through app modules, not provider, collector, or database modules" \
    '@import\("(collector_[^"]+|provider_cloudflare|provider_hostinger|provider_cloudflare_models|provider_hostinger_models|db_store|db_[^"]+|sqlite)"\)' \
    src/cli

check_no_matches \
    "CLI modules must not import the public cloudio embedding facade" \
    '@import\("cloudio"\)' \
    src/cli

check_no_matches \
    "CLI output format enums must reuse cli_render.RenderFormat" \
    '(RenderFormat|OverviewFormat) = enum' \
    src/cli/root.zig src/cli/coverage.zig src/cli/inventory.zig

check_no_matches \
    "CLI command modules must use cli_render.parseFormatArg for format flags" \
    'std\.mem\.eql\(u8, arg, "--json"\)|std\.mem\.eql\(u8, arg, "--format"\)|std\.mem\.startsWith\(u8, arg, "--format="\)' \
    src/cli/root.zig src/cli/coverage.zig src/cli/inventory.zig

check_no_matches \
    "coverage and inventory CLI value options must use cli_args.parseValueArg" \
    'std\.mem\.eql\(u8, arg, "--(limit|provider|domain|query|support|family|control-plane-family|focus-family|operation|operation-id|method|path|path-template|mode|focus|candidate-limit|path-param|param|query-param|header-param|header|body-content-type|content-type)"\)|std\.mem\.startsWith\(u8, arg, "--(limit|provider|domain|query|support|family|control-plane-family|focus-family|operation|operation-id|method|path|path-template|mode|focus|candidate-limit|path-param|param|query-param|header-param|header|body-content-type|content-type)="\)' \
    src/cli/coverage.zig src/cli/inventory.zig

check_no_matches \
    "coverage and inventory CLI output must use cli_render render helpers" \
    'Writer\.Allocating\.init\(ctx\.gpa\)' \
    src/cli/coverage.zig src/cli/inventory.zig

check_no_matches \
    "public cloudio facade must not expose collector internals" \
    '@import\("(collector_[^"]+)"\)|pub const collectors' \
    src/cloudio.zig

check_no_matches \
    "SQLite schema DDL belongs in src/db/schema.zig, not src/db/store.zig" \
    'CREATE (TABLE|INDEX)|schema_meta' \
    src/db/store.zig

exit "$fail"
