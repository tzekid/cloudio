#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bin="$(realpath "${1:-$repo_dir/zig-out/bin/cloudio}")"
port="${CLOUDIO_BROWSER_TEST_PORT:-19331}"
cloudflare_port="${CLOUDIO_FAKE_CLOUDFLARE_PORT:-19332}"
hostinger_port="${CLOUDIO_FAKE_HOSTINGER_PORT:-19333}"
origin="http://localhost:${port}"
cloudflare_origin="http://127.0.0.1:${cloudflare_port}"
hostinger_origin="http://127.0.0.1:${hostinger_port}"
tmp_dir="$(mktemp -d)"
config="$tmp_dir/cloudio.toml"
database="$tmp_dir/cloudio.db"
backup_root="$tmp_dir/backups"
preflight_backup="$backup_root/preflight.db"
storage_state="$tmp_dir/storage-state.json"
caddy_root="$tmp_dir/Caddyfile"
caddy_sites="$tmp_dir/sites.caddy"
caddy_owned="$tmp_dir/cloudio.caddy"
caddy_admin_socket="$tmp_dir/caddy-admin.socket"
caddy_state="$tmp_dir/caddy-runtime.json"
caddy_control="$tmp_dir/caddy-control"
caddy_calls="$tmp_dir/caddy-calls.log"
fake_bin="$tmp_dir/bin"
fake_docker_state="$tmp_dir/docker-state.tsv"
fake_docker_control="$tmp_dir/docker-control"
fake_docker_calls="$tmp_dir/docker-calls.log"
fake_cloudflare_state="$tmp_dir/cloudflare-state.json"
fake_cloudflare_control="$tmp_dir/cloudflare-control"
fake_cloudflare_calls="$tmp_dir/cloudflare-calls.log"
fake_hostinger_state="$tmp_dir/hostinger-state.json"
fake_hostinger_control="$tmp_dir/hostinger-control"
fake_hostinger_calls="$tmp_dir/hostinger-calls.log"
projects_root="$tmp_dir/projects"
nob_state_root="$tmp_dir/nob/operations"
nob_cache_root="$tmp_dir/nob/runners"
nob_toolchains_file="$tmp_dir/nob/toolchains.json"
nob_project_root="$projects_root/reference"
nob_secret_file="$tmp_dir/nob/fixture-token"
browser_run_state_root="$tmp_dir/browser-run"
server_pid=""
cloudflare_pid=""
hostinger_pid=""

cleanup() {
  exit_status="$?"
  if [[ "$exit_status" -ne 0 ]]; then
    tail -n 80 "$tmp_dir/server.log" >&2 2>/dev/null || true
    tail -n 40 "$fake_hostinger_calls" >&2 2>/dev/null || true
  fi
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ -n "$cloudflare_pid" ]] && kill -0 "$cloudflare_pid" 2>/dev/null; then
    kill "$cloudflare_pid" 2>/dev/null || true
    wait "$cloudflare_pid" 2>/dev/null || true
  fi
  if [[ -n "$hostinger_pid" ]] && kill -0 "$hostinger_pid" 2>/dev/null; then
    kill "$hostinger_pid" 2>/dev/null || true
    wait "$hostinger_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
  return "$exit_status"
}
trap cleanup EXIT

stop_cloudio_server() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid"
    wait "$server_pid" 2>/dev/null || true
  fi
  server_pid=""
}

start_cloudio_server() {
  PATH="$fake_bin:$PATH" \
    CLOUDIO_DISABLE_ENV_FILES=1 \
    CLOUDIO_FAKE_DOCKER_STATE="$fake_docker_state" \
    CLOUDIO_FAKE_DOCKER_CONTROL="$fake_docker_control" \
    CLOUDIO_FAKE_DOCKER_CALLS="$fake_docker_calls" \
    CLOUDIO_FAKE_CADDY_ROOT="$caddy_root" \
    CLOUDIO_FAKE_CADDY_STATE="$caddy_state" \
    CLOUDIO_FAKE_CADDY_CONTROL="$caddy_control" \
    CLOUDIO_FAKE_CADDY_CALLS="$caddy_calls" \
    CLOUDIO_CONFIG="$config" \
    "$app_bin" serve --host 127.0.0.1 --port "$port" \
    >>"$tmp_dir/server.log" 2>&1 &
  server_pid="$!"
  for _ in {1..150}; do
    if curl -fsS "$origin/login.html" >/dev/null 2>&1; then
      return
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$tmp_dir/server.log" >&2 || true
      echo "server exited before browser checks could run" >&2
      exit 1
    fi
    sleep 0.1
  done
  echo "server did not become ready for browser checks" >&2
  exit 1
}

if [[ ! -x "$app_bin" ]]; then
  echo "cloudio executable not found: $app_bin" >&2
  exit 1
fi
if [[ ! -d "$repo_dir/.zig-cache/browser-e2e/node_modules/playwright-core" ]]; then
  echo "run tests/setup-browser-e2e.sh before the product acceptance test" >&2
  exit 1
fi

{
  printf 'db_path = "%s"\n' "$database"
  printf 'caddyfile_path = "%s"\n' "$caddy_root"
  printf 'caddy_sites_path = "%s"\n' "$caddy_sites"
  printf 'caddy_owned_path = "%s"\n' "$caddy_owned"
  printf 'caddy_admin_socket = "%s"\n' "$caddy_admin_socket"
  printf 'projects_root = "%s"\n' "$projects_root"
  printf 'domains = "fixture.example.test"\n'
  printf '[platform]\nrefresh_seconds = 86400\n'
  printf '[storage]\nauto_prune = false\nbackup_root = "%s"\ndisk_budget_bytes = 1\n' "$backup_root"
  printf '[cloudflare]\napi_token = "fixture-token"\napi_base = "%s/client/v4"\n' "$cloudflare_origin"
  printf '[browser_run]\nallowed_hosts = "example.com"\nstate_root = "%s"\nretention_hours = 24\n' "$browser_run_state_root"
  printf '[hostinger]\napi_token = "fixture-token"\napi_base = "%s"\n' "$hostinger_origin"
  printf '[nob]\nstate_root = "%s"\ncache_root = "%s"\ntoolchains_file = "%s"\nworker_count = 1\nallow_system_mutation = false\n' "$nob_state_root" "$nob_cache_root" "$nob_toolchains_file"
  printf '[auth]\norigin = "%s"\nrp_id = "localhost"\n' "$origin"
} >"$config"

printf '{\n\tadmin off\n}\n\nimport %s/*.caddy\n' "$tmp_dir" >"$caddy_root"
printf 'unmanaged.example.test {\n\trespond "unmanaged" 200\n}\n' >"$caddy_sites"
touch "$caddy_admin_socket"
: >"$caddy_control"
: >"$caddy_calls"
caddy_root_before="$(sha256sum "$caddy_root" | awk '{print $1}')"
caddy_sites_before="$(sha256sum "$caddy_sites" | awk '{print $1}')"

mkdir -p "$fake_bin"
mkdir -p "$projects_root"
mkdir -p "$tmp_dir/vendor" "$tmp_dir/nob" "$projects_root/needs-manifest" "$projects_root/invalid"
cp -a "$repo_dir/tests/fixtures/nob-project" "$nob_project_root"
ln -s "$repo_dir/vendor/nob" "$tmp_dir/vendor/nob"
touch "$projects_root/needs-manifest/build.zig"
printf '{ invalid manifest\n' >"$projects_root/invalid/nob.json"
printf 'acceptance-secret-value-that-must-never-appear\n' >"$nob_secret_file"
chmod 600 "$nob_secret_file"
ln -s "$repo_dir/tests/fixtures/fake-docker" "$fake_bin/docker"
ln -s "$repo_dir/tests/fixtures/fake-caddy" "$fake_bin/caddy"
ln -s "$repo_dir/tests/fixtures/fake-caddy-curl" "$fake_bin/curl"
for command in hostnamectl systemctl df uptime ss uname; do
  ln -s /bin/true "$fake_bin/$command"
done
CLOUDIO_FAKE_CADDY_ROOT="$caddy_root" \
  CLOUDIO_FAKE_CADDY_STATE="$caddy_state" \
  CLOUDIO_FAKE_CADDY_CONTROL="$caddy_control" \
  CLOUDIO_FAKE_CADDY_CALLS="$caddy_calls" \
  "$fake_bin/caddy" reload --adapter caddyfile --config "$caddy_root" --force
printf '%s\t%s\t%s\t%s\n' \
  'fixture-running' 'example.invalid/running' 'Up 2 hours' '127.0.0.1:8080->80/tcp' \
  'fixture-stopped' 'example.invalid/stopped' 'Exited (0) 2 hours ago' '' \
  'fixture-baseline-stopped' 'example.invalid/baseline' 'Created' '' \
  'fixture-command-fail' 'example.invalid/failure' 'Exited (42) 1 hour ago' '' \
  'fixture-logs-fail' 'example.invalid/logs' 'Up 30 minutes' '' \
  >"$fake_docker_state"
: >"$fake_docker_control"
: >"$fake_docker_calls"
printf '%s\n' '{"next_id":0,"records":[{"id":"record-initial","zone_id":"zone-fixture","type":"A","name":"fixture.example.test","content":"192.0.2.20","ttl":60,"proxied":false}]}' >"$fake_cloudflare_state"
: >"$fake_cloudflare_control"
: >"$fake_cloudflare_calls"
printf '%s\n' '{"next_job":0,"machines":[{"id":"vm-running","hostname":"fixture-running.example.test","state":"running","ipv4":[{"address":"192.0.2.31"}],"plan":"KVM Fixture"},{"id":"vm-stopped","hostname":"fixture-stopped.example.test","state":"stopped","ipv4":[{"address":"192.0.2.32"}],"plan":"KVM Fixture"},{"id":"vm-baseline-stopped","hostname":"fixture-baseline-stopped.example.test","state":"stopped","ipv4":[{"address":"192.0.2.33"}],"plan":"KVM Fixture"}],"jobs":{}}' >"$fake_hostinger_state"
: >"$fake_hostinger_control"
: >"$fake_hostinger_calls"

python3 tests/fixtures/fake-cloudflare.py \
  "$cloudflare_port" \
  "fixture.example.test" \
  "$fake_cloudflare_state" \
  "$fake_cloudflare_control" \
  "$fake_cloudflare_calls" \
  >"$tmp_dir/cloudflare.log" 2>&1 &
cloudflare_pid="$!"
for _ in {1..100}; do
  if curl -fsS "$cloudflare_origin/client/v4/zones?name=fixture.example.test" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$cloudflare_pid" 2>/dev/null; then
    cat "$tmp_dir/cloudflare.log" >&2 || true
    echo "fake Cloudflare exited before acceptance checks" >&2
    exit 1
  fi
  sleep 0.05
done

python3 tests/fixtures/fake-hostinger.py \
  "$hostinger_port" \
  "$fake_hostinger_state" \
  "$fake_hostinger_control" \
  "$fake_hostinger_calls" \
  >"$tmp_dir/hostinger.log" 2>&1 &
hostinger_pid="$!"
for _ in {1..100}; do
  if curl -fsS "$hostinger_origin/api/vps/v1/virtual-machines" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$hostinger_pid" 2>/dev/null; then
    cat "$tmp_dir/hostinger.log" >&2 || true
    echo "fake Hostinger exited before acceptance checks" >&2
    exit 1
  fi
  sleep 0.05
done

cd "$repo_dir"
CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" "$app_bin" init >/dev/null
python3 - "$database" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
connection = sqlite3.connect(database)
connection.execute(
    "INSERT INTO caddy_desired_routes(host,upstream,kind,enabled) VALUES(?,?,?,?)",
    ("fixture.example.test", "127.0.0.1:19001", "manual", 1),
)
connection.execute(
    "INSERT INTO caddy_sites(host,source_path,raw_block) VALUES(?,?,?)",
    ("broken.example.test", "/fixture/sites.caddy", "broken.example.test { reverse_proxy 127.0.0.1:19002 }"),
)
connection.execute(
    "INSERT INTO caddy_upstreams(host,route,upstream) VALUES(?,?,?)",
    ("broken.example.test", "", "127.0.0.1:19002"),
)
connection.execute(
    "INSERT INTO cloudflare_dns_records(id,zone_id,name,type,content,ttl,proxied,raw_json) VALUES(?,?,?,?,?,?,?,?)",
    ("fixture-dns-only", "fixture-zone", "old.example.test", "A", "192.0.2.10", 300, 0, "{}"),
)
connection.execute(
    "INSERT INTO cloudflare_accounts(id,name,type,status,raw_json) VALUES(?,?,?,?,?)",
    ("account-fixture", "Fixture account", "standard", "active", "{}"),
)
connection.executemany(
    "INSERT INTO snapshots(source,kind,status,summary) VALUES(?,?,?,?)",
    [
        ("refresh", "cloudflare", "ok", "fixture provider observation"),
        ("refresh", "hostinger", "error", "fixture credentials unavailable"),
        ("refresh", "caddy", "ok", "fixture local observation"),
        ("refresh", "projects", "ok", "fixture project observation"),
    ],
)
connection.execute(
    "INSERT INTO snapshots(source,kind,status,summary,captured_at) VALUES(?,?,?,?,datetime('now','-3 days'))",
    ("refresh", "system", "ok", "fixture last-good observation"),
)
connection.execute(
    "INSERT INTO snapshots(source,kind,status,summary) VALUES(?,?,?,?)",
    ("refresh", "system", "error", "fixture command failed"),
)
connection.executemany(
    "INSERT INTO audit_actions(kind,target,result,detail,actor) VALUES(?,?,?,?,?)",
    [
        (f"fixture.action.{index:03d}", f"fixture-{index:03d}", "ok", f"detail-{index:03d}", "browser-fixture")
        for index in range(1, 76)
    ],
)
connection.executemany(
    "INSERT INTO audit_events(action,status,detail) VALUES(?,?,?)",
    [
        ("cloudflare.collect", "error", '{"api_token":"fixture-super-secret","reason":"permission denied"}'),
        ("cloudflare.collect", "ok", "fixture provider refresh succeeded"),
    ],
)
connection.commit()
connection.close()
PY

PATH="$fake_bin:$PATH" \
  CLOUDIO_DISABLE_ENV_FILES=1 \
  CLOUDIO_FAKE_DOCKER_STATE="$fake_docker_state" \
  CLOUDIO_FAKE_DOCKER_CONTROL="$fake_docker_control" \
  CLOUDIO_FAKE_DOCKER_CALLS="$fake_docker_calls" \
  CLOUDIO_FAKE_CADDY_ROOT="$caddy_root" \
  CLOUDIO_FAKE_CADDY_STATE="$caddy_state" \
  CLOUDIO_FAKE_CADDY_CONTROL="$caddy_control" \
  CLOUDIO_FAKE_CADDY_CALLS="$caddy_calls" \
  CLOUDIO_CONFIG="$config" \
  "$app_bin" system containers >/dev/null

CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" maintenance backup --output "$preflight_backup" >/dev/null
CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" maintenance status --json | python3 -c '
import json, sys
report = json.load(sys.stdin)
before = report["before"]
assert report["policy"]["backup_retention"] == "operator-managed"
assert before["database_file_bytes"] > 0
assert before["wal_bytes"] >= 0
assert before["backups"]["files"] == 1
assert before["managed_bytes"] > 0
assert before["maintenance_headroom_bytes"] > 0
assert before["budget_warning"] is True
'

bootstrap_output="$(CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" "$app_bin" auth bootstrap --ttl 10m)"
setup_url="$(printf '%s\n' "$bootstrap_output" | awk '/^http:\/\// { print; exit }')"
if [[ -z "$setup_url" ]]; then
  echo "Cloudio did not produce a setup URL" >&2
  exit 1
fi

: >"$tmp_dir/server.log"
start_cloudio_server

node tests/product-acceptance.cjs \
  "$origin" \
  "$setup_url" \
  "$storage_state" \
  "$fake_docker_state" \
  "$fake_docker_control" \
  "$fake_docker_calls" \
  "$fake_cloudflare_state" \
  "$fake_cloudflare_control" \
  "$fake_cloudflare_calls" \
  "$fake_hostinger_state" \
  "$fake_hostinger_control" \
  "$fake_hostinger_calls" \
  "$caddy_owned" \
  "$caddy_control" \
  "$caddy_calls" \
  "$nob_project_root" \
  "$nob_secret_file" \
  "$database"

CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" maintenance status --json | python3 -c '
import json, sys
before = json.load(sys.stdin)["before"]
assert before["backups"]["files"] >= 1
assert before["nob_operation_state"]["files"] > 0
assert before["nob_runner_cache"]["files"] > 0
assert before["budget_warning"] is True
'

CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth status --json | python3 -c '
import json, sys
status = json.load(sys.stdin)
assert status["configured"] is True
assert status["credentials"] == 1
assert status["bootstrap_active"] is False
'
if CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth bootstrap --ttl 10m >"$tmp_dir/unexpected-bootstrap.log" 2>&1; then
  echo "auth bootstrap succeeded while a credential still existed" >&2
  exit 1
fi

stop_cloudio_server
auth_reset_backup="$backup_root/before-auth-reset.db"
CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth reset --backup "$auth_reset_backup" --confirm >/dev/null
test "$(stat -c '%a' "$auth_reset_backup")" = "600"
python3 - "$auth_reset_backup" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
assert connection.execute("SELECT COUNT(*) FROM auth_credentials WHERE revoked_at IS NULL").fetchone()[0] == 1
connection.close()
PY
CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth status --json | python3 -c '
import json, sys
status = json.load(sys.stdin)
assert status["configured"] is False
assert status["credentials"] == 0
assert status["active_sessions"] == 0
'

recovery_bootstrap="$(CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" "$app_bin" auth bootstrap --ttl 10m)"
recovery_setup_url="$(printf '%s\n' "$recovery_bootstrap" | awk '/^http:\/\// { print; exit }')"
if [[ -z "$recovery_setup_url" ]]; then
  echo "Cloudio did not produce a recovery setup URL" >&2
  exit 1
fi
start_cloudio_server
node tests/auth-recovery-acceptance.cjs "$origin" "$recovery_setup_url" "$storage_state"
if CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth bootstrap --ttl 10m >"$tmp_dir/unexpected-recovery-bootstrap.log" 2>&1; then
  echo "auth bootstrap succeeded after recovery enrollment" >&2
  exit 1
fi
CLOUDIO_DISABLE_ENV_FILES=1 CLOUDIO_CONFIG="$config" \
  "$app_bin" auth status --json | python3 -c '
import json, sys
status = json.load(sys.stdin)
assert status["configured"] is True
assert status["credentials"] == 1
assert status["active_sessions"] == 1
assert status["bootstrap_active"] is False
'

test "$(sha256sum "$caddy_root" | awk '{print $1}')" = "$caddy_root_before"
test "$(sha256sum "$caddy_sites" | awk '{print $1}')" = "$caddy_sites_before"
test -s "$caddy_owned"
grep -Eq '^ps -a( |$)' "$fake_docker_calls"
