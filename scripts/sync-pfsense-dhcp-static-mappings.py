#!/usr/bin/env python3
"""
Sync repo-declared pfSense DHCP static mappings (reservations) to the live
<dhcpd><optN><staticmap> entries in pfSense's config.xml.

Source of truth: pfsense/dhcp-static-mappings.yml
Read:  SSH to pfSense, awk the <dhcpd> block out of /cf/conf/config.xml.
Write: REST API /api/v2/services/dhcp_server/static_mapping.
Auth:  macOS Keychain `pfsense-api-token` (same as every other pfSense API tool).

We read via SSH (not REST) because the static_mapping LIST endpoint returns 504
through HAProxy on this build -- the HOME scope alone holds ~256 reservations
and enumerating them exceeds the gateway timeout. Same approach as
sync-pfsense-outbound-nat.py and sync-pfsense-cron-jobs.py.

Matching strategy: upsert by (interface, mac). MAC is the identity. Any
reservation NOT listed in the manifest is LEFT UNTOUCHED -- the HOME scope is
full of hand-made entries that predate this manifest and must never be deleted.

Drift on a listed MAC (ipaddr/hostname/descr differ) is reported and, with
--apply, PATCHed. The pfSense API addresses a mapping by (parent_id, id) where
`id` is its index within the scope, so the index is taken from config.xml
ordering -- the same ordering the API exposes.

Workflow:
    scripts/sync-pfsense-dhcp-static-mappings.py            # dry run -- show diff
    scripts/sync-pfsense-dhcp-static-mappings.py --apply    # create/update
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
MANIFEST = REPO_ROOT / "pfsense" / "dhcp-static-mappings.yml"

PFSENSE_API = "https://pfsense.home.lcamaral.com/api/v2"
TOKEN_KEYCHAIN_SERVICE = "pfsense-api-token"

# Fields we reconcile. `mac` and `interface` form the key and are not diffed.
FIELDS = ("ipaddr", "hostname", "descr")


def keychain_token() -> str:
    out = subprocess.run(
        ["security", "find-generic-password", "-s", TOKEN_KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def api(method: str, path: str, token: str, body: dict | None = None,
        timeout: int = 60, retries: int = 3) -> dict:
    import ssl  # noqa: PLC0415
    import time  # noqa: PLC0415
    # pfSense API is fronted by HAProxy with a Let's Encrypt cert
    # (*.home.lcamaral.com), so default TLS verification works.
    ctx = ssl.create_default_context()
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
    raise RuntimeError(
        f"pfSense API {method} {path} failed after {retries} attempts: {last_err}")


def _text(el, tag: str) -> str:
    child = el.find(tag)
    return (child.text or "").strip() if child is not None and child.text else ""


def fetch_live() -> dict[tuple[str, str], dict]:
    """Read <dhcpd> from config.xml via SSH.

    Returns {(interface, mac_lower): {ipaddr, hostname, descr, index}} where
    `index` is the mapping's position within its scope (the API's `id`).
    """
    out = subprocess.run(
        ["ssh", "pfsense", "awk '/<dhcpd>/,/<\\/dhcpd>/' /cf/conf/config.xml"],
        capture_output=True, text=True, check=True,
    )
    # stdlib ElementTree, matching sync-pfsense-outbound-nat.py and
    # sync-pfsense-cron-jobs.py. The input is our own /cf/conf/config.xml pulled
    # over authenticated SSH, not untrusted input, and ElementTree does not
    # resolve external entities -- so defusedxml would add a dependency without
    # closing a reachable hole here.
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    tree = ET.fromstring("<root>" + out.stdout + "</root>")
    dhcpd = tree.find("dhcpd")
    live: dict[tuple[str, str], dict] = {}
    if dhcpd is None:
        return live
    for scope in dhcpd:
        iface = scope.tag
        for index, sm in enumerate(scope.findall("staticmap")):
            mac = _text(sm, "mac").lower()
            if not mac:
                continue
            live[(iface, mac)] = {
                "ipaddr": _text(sm, "ipaddr"),
                "hostname": _text(sm, "hostname"),
                "descr": _text(sm, "descr"),
                "index": index,
            }
    return live


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="Create/update mappings (default: dry-run)")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")
    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    declared = data.get("mappings", [])
    if not declared:
        print("no static mappings declared in manifest")
        return 0

    live = fetch_live()
    print(f"live reservations across all scopes: {len(live)}")

    token = keychain_token() if args.apply else ""
    pending = 0

    for d in declared:
        iface = d["interface"]
        mac = str(d["mac"]).lower()
        label = f"{iface} {mac} -> {d['ipaddr']}"
        cur = live.get((iface, mac))

        if cur is None:
            print(f"  + CREATE {label}  ({d.get('descr', '')})")
            pending += 1
            if args.apply:
                body = {
                    "parent_id": iface,
                    "mac": mac,
                    "ipaddr": d["ipaddr"],
                    "hostname": d.get("hostname", ""),
                    "descr": d.get("descr", ""),
                }
                resp = api("POST", "/services/dhcp_server/static_mapping", token, body)
                print(f"    -> id={resp.get('data', {}).get('id')}")
            continue

        diffs = {k: (cur[k], str(d.get(k, ""))) for k in FIELDS
                 if cur[k] != str(d.get(k, ""))}
        if not diffs:
            print(f"  = {label}: in sync")
            continue

        print(f"  ~ UPDATE {label}")
        for k, (was, want) in diffs.items():
            print(f"      {k}: {was!r} -> {want!r}")
        pending += 1
        if args.apply:
            body = {
                "parent_id": iface,
                "id": cur["index"],
                "mac": mac,
                "ipaddr": d["ipaddr"],
                "hostname": d.get("hostname", ""),
                "descr": d.get("descr", ""),
            }
            api("PATCH", "/services/dhcp_server/static_mapping", token, body)
            print("    -> updated")

    if pending == 0:
        print("DHCP static mappings in sync.")
    elif not args.apply:
        print(f"\n{pending} change(s) pending -- re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
