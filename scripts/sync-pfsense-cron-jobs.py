#!/usr/bin/env python3
"""
Sync repo-declared pfSense cron jobs to the live `<cron>` section in
pfSense's config.xml.

Source of truth: pfsense/cron-jobs.yml
Read:  SSH to pfSense, grep `<cron>` block out of /cf/conf/config.xml.
Write: REST API /api/v2/services/cron/job (POST/PATCH/DELETE).
Auth:  macOS Keychain `pfsense-api-token` (same as every other API tool).

We read via SSH (not REST) because the REST list endpoint
`/services/cron/jobs` returns 504 Gateway Time-out on this pfSense
build — known flake. The single-job GET works, but you need the id
first, which the list endpoint was supposed to provide. SSH+grep
sidesteps the bug.

Matching strategy: upsert by (command, who) tuple. Jobs in pfSense that
are NOT listed in cron-jobs.yml are left untouched — that's how pfSense's
shipped entries (newsyslog, rc.periodic, ACME, RESTAPI cache, etc.) stay
out of the way.

Workflow:
    scripts/sync-pfsense-cron-jobs.py            # dry run — show diff
    scripts/sync-pfsense-cron-jobs.py --apply    # POST / PATCH as needed
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "pfsense" / "cron-jobs.yml"

PFSENSE_API = "https://pfsense.home.lcamaral.com/api/v2"
TOKEN_KEYCHAIN_SERVICE = "pfsense-api-token"

# Fields we own on each entry. `description` in the YAML is for git
# audit only and is NOT sent to pfSense (the cron API has no
# description column).
SYNC_FIELDS = ("minute", "hour", "mday", "month", "wday", "who", "command")


def keychain_token() -> str:
    out = subprocess.run(
        ["security", "find-generic-password", "-s", TOKEN_KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def api(method: str, path: str, token: str, body: dict | None = None,
        timeout: int = 60, retries: int = 3) -> dict:
    """Call the pfSense REST API. List endpoints (GET /jobs) are
    occasionally slow; retry transient timeouts with a backoff."""
    import ssl  # noqa: PLC0415
    import time  # noqa: PLC0415
    # pfSense uses a self-signed cert; the cert is for the homelab and the
    # token is the actual auth, so we skip cert verification here.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(
            f"{PFSENSE_API}{path}",
            method=method,
            headers={"X-API-Key": token, "Content-Type": "application/json"},
            data=json.dumps(body).encode() if body is not None else None,
        )
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=timeout) as r:
                return json.loads(r.read())
        except (TimeoutError, urllib.error.URLError) as e:
            last_err = e
            if attempt < retries:
                time.sleep(2 * attempt)
    raise RuntimeError(f"pfSense API {method} {path} failed after {retries} attempts: {last_err}")


def fetch_live(token: str) -> list[dict]:
    """Read the <cron> section out of pfSense's config.xml via SSH and
    parse it into the same shape the REST API would return. Each entry
    gets an `id` matching its 0-indexed position in the <cron> list —
    that's how pfSense's REST API derives id from config.xml ordering."""
    out = subprocess.run(
        ["ssh", "pfsense",
         "awk '/<cron>/,/<\\/cron>/' /cf/conf/config.xml"],
        capture_output=True, text=True, check=True,
    )
    xml = "<root>" + out.stdout + "</root>"
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    tree = ET.fromstring(xml)
    cron = tree.find("cron")
    if cron is None:
        return []
    jobs: list[dict] = []
    for idx, item in enumerate(cron.findall("item")):
        job = {"id": idx}
        for f in SYNC_FIELDS:
            el = item.find(f)
            job[f] = (el.text or "") if el is not None else ""
        jobs.append(job)
    return jobs


def find_match(declared: dict, live: list[dict]) -> dict | None:
    for j in live:
        if j.get("command") == declared["command"] and j.get("who") == declared["who"]:
            return j
    return None


def diff_fields(declared: dict, live: dict) -> list[str]:
    return [f for f in SYNC_FIELDS if str(declared.get(f, "")) != str(live.get(f, ""))]


def post(token: str, body: dict) -> dict:
    return api("POST", "/services/cron/job", token, body)


def patch(token: str, body: dict) -> dict:
    return api("PATCH", "/services/cron/job", token, body)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--apply", action="store_true",
        help="POST / PATCH cron jobs to pfSense (default: dry-run)")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")

    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    declared = data.get("jobs", [])
    if not declared:
        print("no cron jobs declared in manifest")
        return 0

    token = keychain_token()
    live = fetch_live(token)

    creates = 0
    updates = 0
    for d in declared:
        body = {k: d[k] for k in SYNC_FIELDS if k in d}
        match = find_match(d, live)
        if match is None:
            print(f"  + CREATE {d['command']}  ({d['minute']} {d['hour']} {d['mday']} {d['month']} {d['wday']})")
            creates += 1
            if args.apply:
                resp = post(token, body)
                print(f"    -> id={resp['data']['id']}")
            continue
        diffs = diff_fields(d, match)
        if not diffs:
            print(f"  = {d['command']}: up to date  (id={match['id']})")
            continue
        print(f"  ~ UPDATE {d['command']}  (id={match['id']}, fields: {', '.join(diffs)})")
        updates += 1
        if args.apply:
            body_with_id = {"id": match["id"], **body}
            resp = patch(token, body_with_id)
            print("    -> patched")

    total = creates + updates
    if total == 0:
        print("All cron jobs up to date.")
    elif not args.apply:
        print(f"\n{creates} create(s), {updates} update(s) pending — re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
