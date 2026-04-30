#!/usr/bin/env python3
"""
Reconcile pfSense ACME a_actionlist items from `pfsense/acme-actions.yml`
to the live pfSense REST API.

For each cert listed in the YAML, the script ensures the named action
commands exist with the desired status. Other actions present on pfSense
(e.g. the default rc.restart_webgui / haproxy.sh entries) are LEFT
ALONE — this is a "claim what we own" reconciler, not a wipe-and-replace.

Usage:
    scripts/sync-pfsense-acme-actions.py            # dry run, show diff
    scripts/sync-pfsense-acme-actions.py --apply    # POST/PATCH changes

Auth: pfSense API token from macOS Keychain (`pfsense-api-token`).
The pfSense API is reached via `ssh pfsense 'curl 127.0.0.1:56880'`
because it's bound to localhost.

Note: pfSense's ACME API can take 30+ seconds per call — be patient.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = REPO_ROOT / "pfsense" / "acme-actions.yml"

API_BASE = "http://127.0.0.1:56880/api/v2"
CERTS_PATH = "/services/acme/certificates"
ACTION_PATH = "/services/acme/certificate/action"


@dataclass(frozen=True)
class Action:
    command: str
    method: str
    status: str

    def key(self) -> tuple[str, str]:
        # Identity: (command, method). Status drift triggers an update.
        return (self.command, self.method)


def get_token() -> str:
    try:
        return subprocess.check_output(
            ["security", "find-generic-password", "-w", "-s", "pfsense-api-token", "-a",
             subprocess.check_output(["whoami"]).decode().strip()],
            text=True,
        ).strip()
    except subprocess.CalledProcessError as e:
        sys.exit(f"error: pfSense API token not in Keychain: {e}")


def api_call(method: str, path: str, token: str, body: dict | None = None, timeout_s: int = 90) -> dict:
    parts = ["curl", "-s", "--max-time", str(timeout_s), "-X", method,
             "-H", f"'X-API-Key: {token}'",
             "-H", "'Content-Type: application/json'"]
    if body is not None:
        parts += ["-d", f"'{json.dumps(body)}'"]
    parts.append(f"'{API_BASE}{path}'")
    cmd = " ".join(parts)
    result = subprocess.run(
        ["ssh", "pfsense", cmd],
        capture_output=True, text=True, check=False, timeout=timeout_s + 10,
    )
    if result.returncode != 0:
        sys.exit(f"error: ssh pfsense failed: {result.stderr}")
    out = result.stdout.strip()
    if not out:
        sys.exit(f"error: empty response from {method} {path}")
    try:
        data = json.loads(out)
    except json.JSONDecodeError as e:
        sys.exit(f"error: invalid JSON from {method} {path}: {e}\n{out[:300]}")
    if data.get("code", 0) >= 400:
        sys.exit(f"error: API {method} {path} returned {data.get('code')}: {data.get('message')}")
    return data


def fetch_certs(token: str) -> list[dict]:
    return api_call("GET", CERTS_PATH, token).get("data", [])


def desired_actions(cert_name: str, all_desired: list[dict]) -> list[Action]:
    for entry in all_desired:
        if entry["cert"] == cert_name:
            return [Action(command=a["command"], method=a["method"], status=a.get("status", "active"))
                    for a in entry.get("actions", [])]
    return []


def reconcile_cert(cert: dict, desired: list[Action], token: str, apply: bool) -> int:
    """Returns count of changes applied/planned."""
    cert_name = cert["name"]
    cert_id = cert["id"]
    live_actions = cert.get("a_actionlist") or []
    live_by_key = {(a["command"], a["method"]): a for a in live_actions}

    changes = 0
    for d in desired:
        live = live_by_key.get(d.key())
        if live is None:
            print(f"  [{cert_name}] CREATE: {d.command}")
            changes += 1
            if apply:
                api_call("POST", ACTION_PATH, token, body={
                    "parent_id": cert_id,
                    "command": d.command,
                    "method": d.method,
                    "status": d.status,
                })
        elif live.get("status") != d.status:
            print(f"  [{cert_name}] UPDATE: {d.command} (status {live.get('status')} → {d.status})")
            changes += 1
            if apply:
                api_call("PATCH", ACTION_PATH, token, body={
                    "parent_id": cert_id,
                    "id": live["id"],
                    "command": d.command,
                    "method": d.method,
                    "status": d.status,
                })
        # else: already in sync, nothing to do
    return changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="POST/PATCH changes (default: dry-run)")
    args = parser.parse_args()

    if not YAML_PATH.exists():
        sys.exit(f"error: {YAML_PATH} not found")
    with YAML_PATH.open() as f:
        desired_all = yaml.safe_load(f) or []

    token = get_token()
    print(f"Fetching cert state from pfSense (this may take ~30s)...")
    certs = fetch_certs(token)
    print(f"  {len(certs)} certificates on pfSense")

    total = 0
    for entry in desired_all:
        cert_name = entry["cert"]
        match = next((c for c in certs if c["name"] == cert_name), None)
        if match is None:
            print(f"  WARN: cert '{cert_name}' in YAML not found on pfSense — skipping")
            continue
        total += reconcile_cert(match, desired_actions(cert_name, desired_all), token, args.apply)

    if total == 0:
        print("All ACME actions in sync.")
    elif not args.apply:
        print(f"\n{total} change(s) — re-run with --apply to push.")
    else:
        print(f"\n{total} change(s) applied.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
