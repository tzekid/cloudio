#!/usr/bin/env python3
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


PORT = int(sys.argv[1])
STATE_PATH = Path(sys.argv[2])
CONTROL_PATH = Path(sys.argv[3])
CALLS_PATH = Path(sys.argv[4])
PREFIX = "/api/vps/v1/virtual-machines"


def load_state():
    return json.loads(STATE_PATH.read_text())


def save_state(state):
    STATE_PATH.write_text(json.dumps(state, separators=(",", ":")) + "\n")


def mode():
    return CONTROL_PATH.read_text().strip() if CONTROL_PATH.exists() else ""


def record(method, path):
    with CALLS_PATH.open("a") as calls:
        calls.write(f"{method} {path}\n")


def machine_by_id(state, machine_id):
    return next((item for item in state["machines"] if str(item["id"]) == machine_id), None)


def apply_job(state, job):
    machine = machine_by_id(state, job["machine_id"])
    if machine is None:
        return
    if job["action"] in ("start", "restart"):
        machine["state"] = "running"
    elif job["action"] == "stop":
        machine["state"] = "stopped"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def send_json(self, status, value):
        payload = (json.dumps(value, separators=(",", ":")) + "\n").encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def reject_bad_authorization(self):
        if self.headers.get("Authorization") == "Bearer fixture-token":
            return False
        record(self.command, urlparse(self.path).path)
        self.send_json(401, {"message": "invalid fixture authorization"})
        return True

    def disconnect(self):
        self.connection.shutdown(1)
        self.connection.close()

    def do_GET(self):
        if self.reject_bad_authorization():
            return
        path = urlparse(self.path).path
        record("GET", path)
        current_mode = mode()
        if current_mode == "disconnect-read":
            self.disconnect()
            return
        if current_mode == "read-reject":
            self.send_json(503, {"message": "fixture read rejected"})
            return
        if current_mode == "malformed-read":
            self.send_json(200, {"data": [{"id": "partial"}]})
            return

        state = load_state()
        if path == PREFIX:
            self.send_json(200, {"data": state["machines"]})
            return
        segments = path[len(PREFIX) :].strip("/").split("/") if path.startswith(PREFIX + "/") else []
        if len(segments) == 1:
            machine = machine_by_id(state, segments[0])
            if machine is None:
                self.send_json(404, {"message": "machine not found"})
                return
            self.send_json(200, {"data": machine})
            return
        if len(segments) == 3 and segments[1] == "actions":
            job = state["jobs"].get(segments[2])
            if job is None or job["machine_id"] != segments[0]:
                self.send_json(404, {"message": "job not found"})
                return
            if current_mode == "timeout":
                self.disconnect()
                return
            job["polls"] += 1
            if current_mode == "job-fail" and job["polls"] >= 2:
                job["state"] = "failed"
            elif current_mode != "pending" and job["polls"] >= 2:
                job["state"] = "completed"
                apply_job(state, job)
            save_state(state)
            self.send_json(200, {"data": {"id": segments[2], "state": job["state"]}})
            return
        self.send_json(404, {"message": "not found"})

    def do_POST(self):
        if self.reject_bad_authorization():
            return
        path = urlparse(self.path).path
        record("POST", path)
        current_mode = mode()
        if current_mode == "disconnect":
            self.disconnect()
            return
        segments = path[len(PREFIX) :].strip("/").split("/") if path.startswith(PREFIX + "/") else []
        if len(segments) != 2 or segments[1] not in ("start", "stop", "restart"):
            self.send_json(404, {"message": "not found"})
            return
        state = load_state()
        if machine_by_id(state, segments[0]) is None:
            self.send_json(404, {"message": "machine not found"})
            return
        if current_mode == "reject":
            self.send_json(422, {"message": "fixture action rejected"})
            return
        state["next_job"] += 1
        job_id = f"job-{state['next_job']}"
        state["jobs"][job_id] = {
            "machine_id": segments[0],
            "action": segments[1],
            "state": "pending",
            "polls": 0,
        }
        save_state(state)
        if current_mode == "no-job":
            self.send_json(202, {"data": {"accepted": True}})
        else:
            self.send_json(202, {"data": {"id": job_id, "state": "pending"}})


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
