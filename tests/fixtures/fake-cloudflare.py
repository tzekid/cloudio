#!/usr/bin/env python3
import json
import os
import sys
import threading
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


if len(sys.argv) != 6:
    raise SystemExit("usage: fake-cloudflare.py PORT DOMAIN STATE CONTROL CALLS")

port = int(sys.argv[1])
domain = sys.argv[2]
state_path = sys.argv[3]
control_path = sys.argv[4]
calls_path = sys.argv[5]
zone_id = "zone-fixture"
lock = threading.Lock()
pixel_png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def control():
    try:
        with open(control_path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return ""


def read_state():
    with open(state_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_state(value):
    temporary = state_path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, separators=(",", ":"), sort_keys=True)
    os.replace(temporary, state_path)


class Handler(BaseHTTPRequestHandler):
    server_version = "fixture"
    sys_version = ""

    def log_message(self, _format, *_args):
        return

    def record_call(self, body=""):
        with lock:
            with open(calls_path, "a", encoding="utf-8") as handle:
                handle.write(f"{self.command} {self.path} {body}\n")

    def response(self, status, payload):
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def browser_response(self, status, content_type, encoded):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("X-Browser-Ms-Used", "42")
        self.send_header("CF-Ray", "browser-fixture-ray")
        self.end_headers()
        self.wfile.write(encoded)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        self.record_call(raw)
        try:
            return json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return None

    def reject_or_disconnect(self, mutation=False):
        mode = control()
        if mode == "disconnect":
            self.record_call()
            self.connection.shutdown(2)
            self.connection.close()
            return True
        if mode == "reject" and mutation:
            self.record_call()
            self.response(403, {"success": False, "errors": [{"code": 10000, "message": "fixture rejection"}], "result": None})
            return True
        if mode in ("read-reject", "accept-unconfirmed") and not mutation:
            self.record_call()
            self.response(503, {"success": False, "errors": [{"code": 10001, "message": "fixture read unavailable"}], "result": None})
            return True
        return False

    def do_GET(self):
        if self.reject_or_disconnect(False):
            return
        parsed = urlparse(self.path)
        if parsed.path == "/client/v4/zones":
            self.record_call()
            requested = parse_qs(parsed.query).get("name", [""])[0]
            result = [] if requested != domain else [{
                "id": zone_id,
                "name": domain,
                "status": "active",
                "paused": False,
                "type": "full",
                "account": {"id": "account-fixture"},
                "name_servers": ["ns1.example.invalid", "ns2.example.invalid"],
            }]
            self.response(200, {"success": True, "errors": [], "messages": [], "result": result})
            return
        if parsed.path == f"/client/v4/zones/{zone_id}/dns_records":
            self.record_call()
            with lock:
                records = read_state()["records"]
            self.response(200, {"success": True, "errors": [], "messages": [], "result": records})
            return
        self.record_call()
        self.response(404, {"success": False, "errors": [{"message": "not found"}], "result": None})

    def do_POST(self):
        if self.reject_or_disconnect(True):
            return
        parsed = urlparse(self.path)
        body = self.body()
        browser_prefix = "/client/v4/accounts/account-fixture/browser-run/"
        if parsed.path.startswith(browser_prefix):
            query = parse_qs(parsed.query)
            if body is None or query.get("browser") != ["kitesurf"] or query.get("cacheTTL") != ["0"]:
                self.response(400, {"success": False, "errors": [{"message": "invalid browser run request"}], "result": None})
                return
            if body.get("url") != "https://example.com/browser-run?fixture=secret":
                self.response(422, {"success": False, "errors": [{"message": "unexpected target"}], "result": None})
                return
            action = parsed.path[len(browser_prefix):]
            if action == "content":
                payload = {
                    "success": True,
                    "result": "<!doctype html><title>Fixture page</title><main>Rendered fixture</main><script>window.__browserRunArtifactExecuted=true</script>",
                    "meta": {"status": 200, "title": "Fixture page"},
                }
                self.browser_response(200, "application/json; charset=utf-8", json.dumps(payload, separators=(",", ":")).encode("utf-8"))
                return
            if action == "screenshot":
                self.browser_response(200, "image/png", pixel_png)
                return
            self.response(404, {"success": False, "errors": [{"message": "unknown browser action"}], "result": None})
            return
        if parsed.path != f"/client/v4/zones/{zone_id}/dns_records" or body is None:
            self.response(400, {"success": False, "errors": [{"message": "bad request"}], "result": None})
            return
        with lock:
            state = read_state()
            state["next_id"] += 1
            record = dict(body)
            record["id"] = f"record-created-{state['next_id']}"
            record["zone_id"] = zone_id
            state["records"].append(record)
            write_state(state)
        self.response(200, {"success": True, "errors": [], "messages": [], "result": record})

    def do_PUT(self):
        if self.reject_or_disconnect(True):
            return
        parsed = urlparse(self.path)
        body = self.body()
        prefix = f"/client/v4/zones/{zone_id}/dns_records/"
        if not parsed.path.startswith(prefix) or body is None:
            self.response(400, {"success": False, "errors": [{"message": "bad request"}], "result": None})
            return
        record_id = parsed.path[len(prefix):]
        updated = None
        with lock:
            state = read_state()
            for index, record in enumerate(state["records"]):
                if record["id"] != record_id:
                    continue
                updated = dict(body)
                updated["id"] = record_id
                updated["zone_id"] = zone_id
                state["records"][index] = updated
                break
            if updated is not None:
                write_state(state)
        if updated is None:
            self.response(404, {"success": False, "errors": [{"message": "record missing"}], "result": None})
            return
        self.response(200, {"success": True, "errors": [], "messages": [], "result": updated})

    def do_DELETE(self):
        if self.reject_or_disconnect(True):
            return
        parsed = urlparse(self.path)
        self.record_call()
        prefix = f"/client/v4/zones/{zone_id}/dns_records/"
        if not parsed.path.startswith(prefix):
            self.response(400, {"success": False, "errors": [{"message": "bad request"}], "result": None})
            return
        record_id = parsed.path[len(prefix):]
        removed = False
        with lock:
            state = read_state()
            next_records = [record for record in state["records"] if record["id"] != record_id]
            removed = len(next_records) != len(state["records"])
            state["records"] = next_records
            if removed:
                write_state(state)
        if not removed:
            self.response(404, {"success": False, "errors": [{"message": "record missing"}], "result": None})
            return
        self.response(200, {"success": True, "errors": [], "messages": [], "result": {"id": record_id}})


ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
