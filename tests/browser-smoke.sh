#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bin="$(realpath "${1:-$repo_dir/zig-out/bin/cloudio}")"
port="${CLOUDIO_BROWSER_TEST_PORT:-19331}"
origin="http://localhost:${port}"
tmp_dir="$(mktemp -d)"
config="$tmp_dir/cloudio.toml"
database="$tmp_dir/cloudio.db"
storage_state="$tmp_dir/storage-state.json"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ ! -x "$app_bin" ]]; then
  echo "cloudio executable not found: $app_bin" >&2
  exit 1
fi
if [[ ! -d "$repo_dir/.zig-cache/browser-e2e/node_modules/playwright-core" ]]; then
  echo "run tests/setup-browser-e2e.sh before the browser smoke test" >&2
  exit 1
fi

{
  printf 'db_path = "%s"\n' "$database"
  printf '[platform]\nrefresh_seconds = 86400\n'
  printf '[auth]\norigin = "%s"\nrp_id = "localhost"\n' "$origin"
} >"$config"

cd "$repo_dir"
CLOUDIO_CONFIG="$config" "$app_bin" init >/dev/null
python3 - "$database" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
connection = sqlite3.connect(database)
connection.execute(
    "INSERT INTO containers(name,image,status,ports,raw_text) VALUES(?,?,?,?,?)",
    ("fixture-web", "example.invalid/cloudio", "running", "8080/tcp", "{}"),
)
connection.execute(
    "INSERT INTO apps(name,workdir,toolchain,port,alias_host,status) VALUES(?,?,?,?,?,?)",
    ("fixture-app", "/srv/fixture-app", "zig", 19001, "fixture.example.test", "running"),
)
connection.execute(
    "INSERT INTO caddy_desired_routes(host,upstream,kind,enabled) VALUES(?,?,?,?)",
    ("fixture.example.test", "127.0.0.1:19001", "manual", 1),
)
connection.executemany(
    "INSERT INTO audit_actions(kind,target,result,detail,actor) VALUES(?,?,?,?,?)",
    [
        (f"fixture.action.{index:03d}", f"fixture-{index:03d}", "ok", f"detail-{index:03d}", "browser-fixture")
        for index in range(1, 76)
    ],
)
connection.commit()
connection.close()
PY

bootstrap_output="$(CLOUDIO_CONFIG="$config" "$app_bin" auth bootstrap --ttl 10m)"
setup_url="$(printf '%s\n' "$bootstrap_output" | awk '/^http:\/\// { print; exit }')"
if [[ -z "$setup_url" ]]; then
  echo "Cloudio did not produce a setup URL" >&2
  exit 1
fi

CLOUDIO_CONFIG="$config" "$app_bin" serve --host 127.0.0.1 --port "$port" \
  >"$tmp_dir/server.log" 2>&1 &
server_pid="$!"
for _ in {1..150}; do
  if curl -fsS "$origin/login.html" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$tmp_dir/server.log" >&2 || true
    echo "server exited before browser checks could run" >&2
    exit 1
  fi
  sleep 0.1
done

node tests/browser-smoke.cjs "$origin" "$setup_url" "$storage_state"
