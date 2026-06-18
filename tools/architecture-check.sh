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

check_no_matches \
    "core and net modules must not import persistence, provider, collector, app, CLI, or sqlite modules" \
    '@import\("(db_[^"]+|sqlite|collector_[^"]+|provider_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/core src/net

check_no_matches \
    "database modules must not import provider, collector, app, or CLI modules" \
    '@import\("(collector_[^"]+|provider_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/db

check_no_matches \
    "provider modules must not import persistence, collector, app, CLI, or sqlite modules" \
    '@import\("(db_store|sqlite|collector_[^"]+|app_[^"]+|cli_[^"]+)"\)' \
    src/providers

check_no_matches \
    "collector modules must not import app or CLI modules" \
    '@import\("(app_[^"]+|cli_[^"]+)"\)' \
    src/collectors

check_no_matches \
    "app modules must not import CLI modules" \
    '@import\("(cli_[^"]+)"\)' \
    src/app

check_no_matches \
    "CLI modules must delegate through app modules, not provider or collector modules" \
    '@import\("(collector_[^"]+|provider_cloudflare|provider_hostinger|provider_cloudflare_models|provider_hostinger_models)"\)' \
    src/cli

check_no_matches \
    "CLI modules must not import the public cloudio embedding facade" \
    '@import\("cloudio"\)' \
    src/cli

check_no_matches \
    "public cloudio facade must not expose collector internals" \
    '@import\("(collector_[^"]+)"\)|pub const collectors' \
    src/cloudio.zig

check_no_matches \
    "SQLite schema DDL belongs in src/db/schema.zig, not src/db/store.zig" \
    'CREATE (TABLE|INDEX)|schema_meta' \
    src/db/store.zig

exit "$fail"
