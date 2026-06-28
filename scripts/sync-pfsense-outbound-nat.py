#!/usr/bin/env python3
"""
Sync repo-declared pfSense outbound (source) NAT rules to the live
<nat><outbound> section in pfSense's config.xml.

Source of truth: pfsense/outbound-nat.yml
Read:  SSH to pfSense, awk the <outbound> block out of /cf/conf/config.xml.
Write: REST API /api/v2/firewall/nat/outbound/mode + /firewall/nat/outbound/mapping.
Auth:  macOS Keychain `pfsense-api-token` (same as every other pfSense API tool).

We read via SSH (not REST) because the REST list endpoints flake on this
pfSense build — same approach as sync-pfsense-cron-jobs.py.

Matching strategy: upsert by (interface, source). pfSense automatic rules and
any manual rule NOT listed in the manifest are LEFT UNTOUCHED.

NOTE on the NAT-id shift caveat (memory feedback_pfsense_api_id_shift): a PATCH
re-indexes mapping ids, so this tool only POSTs missing rules and never edits
existing ones by id — re-run dry-run after an apply to confirm convergence.

Workflow:
    scripts/sync-pfsense-outbound-nat.py            # dry run — show diff
    scripts/sync-pfsense-outbound-nat.py --apply    # set mode + POST missing rules
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
MANIFEST = REPO_ROOT / "pfsense" / "outbound-nat.yml"

PFSENSE_API = "https://pfsense.home.lcamaral.com/api/v2"
TOKEN_KEYCHAIN_SERVICE = "pfsense-api-token"


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
    raise RuntimeError(f"pfSense API {method} {path} failed after {retries} attempts: {last_err}")


def fetch_live() -> tuple[str, list[dict]]:
    """Read <nat><outbound> from config.xml via SSH. Return (mode, rules)
    where each rule is {interface, source}. config.xml stores a rule's source
    as <source><network>CIDR</network></source>."""
    out = subprocess.run(
        ["ssh", "pfsense",
         "awk '/<outbound>/,/<\\/outbound>/' /cf/conf/config.xml"],
        capture_output=True, text=True, check=True,
    )
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    tree = ET.fromstring("<root>" + out.stdout + "</root>")
    outbound = tree.find("outbound")
    if outbound is None:
        return ("", [])
    mode_el = outbound.find("mode")
    mode = (mode_el.text or "").strip() if mode_el is not None else ""
    rules: list[dict] = []
    for rule in outbound.findall("rule"):
        iface_el = rule.find("interface")
        src = rule.find("source")
        net = src.find("network") if src is not None else None
        rules.append({
            "interface": (iface_el.text or "").strip() if iface_el is not None else "",
            "source": (net.text or "").strip() if net is not None else "",
        })
    return (mode, rules)


def find_match(declared: dict, live: list[dict]) -> dict | None:
    for r in live:
        if r["interface"] == declared["interface"] and r["source"] == declared["source"]:
            return r
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="Set mode + POST missing rules (default: dry-run)")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")
    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    want_mode = data.get("mode", "hybrid")
    declared = data.get("rules", [])
    if not declared:
        print("no outbound NAT rules declared in manifest")
        return 0

    token = keychain_token()
    live_mode, live_rules = fetch_live()

    pending = 0

    if live_mode != want_mode:
        print(f"  ~ MODE {live_mode or '(unset)'} -> {want_mode}")
        pending += 1
        if args.apply:
            api("PATCH", "/firewall/nat/outbound/mode", token, {"mode": want_mode})
            print("    -> mode set")
    else:
        print(f"  = mode: {live_mode} (ok)")

    for d in declared:
        if find_match(d, live_rules):
            print(f"  = {d['interface']} {d['source']}: present")
            continue
        print(f"  + CREATE {d['interface']} {d['source']}  ({d.get('descr','')})")
        pending += 1
        if args.apply:
            body = {
                "interface": d["interface"],
                "source": d["source"],
                "destination": "any",
                "target": "",
                "descr": d.get("descr", ""),
            }
            resp = api("POST", "/firewall/nat/outbound/mapping", token, body)
            print(f"    -> id={resp.get('data', {}).get('id')}")

    if pending == 0:
        print("Outbound NAT in sync.")
    elif not args.apply:
        print(f"\n{pending} change(s) pending — re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
