#!/usr/bin/env python3
"""
Sync repo-declared pfSense DHCP custom (numbered) options to the live
<dhcpd><optN><numberoptions><item> entries in pfSense's config.xml.

Source of truth: pfsense/dhcp-custom-options.yml
Read:  SSH to pfSense, awk the <dhcpd> block out of /cf/conf/config.xml.
Write: REST API /api/v2/services/dhcp_server/custom_option.
Auth:  macOS Keychain `pfsense-api-token` (same as every other pfSense API tool).

We read via SSH (not REST) because the DHCP list endpoints return 504 through
HAProxy on this build -- the HOME scope alone holds ~256 reservations and
serialising them exceeds the 30 s gateway timeout. Same approach as
sync-pfsense-dhcp-static-mappings.py.

!! WRITE PATH IS CURRENTLY BLOCKED ON THIS BUILD (measured 2026-08-21) !!
    PATCH via HAProxy (https://pfsense.home.lcamaral.com) -> 504 after 30 s.
    PATCH via the nginx backend direct (http://127.0.0.1:56880, plain HTTP --
    HAProxy is what terminates TLS) -> 504 after 180 s, nginx's own ceiling.
    So the PHP backend needs >180 s to service one custom_option write on the
    HOME scope; it appears to re-validate all ~256 static mappings per call.
    Four write attempts were made and NONE committed -- config.xml was verified
    unchanged with exactly one <number>121</number> item afterwards, so retries
    are safe and do not duplicate entries.

    Until that is faster, `--apply` will fail and the change must be applied via
    the GUI (Services > DHCP Server > HOME > Additional BOOTP/DHCP Options).
    This script still earns its place: the manifest is the version-controlled
    source of truth, and the dry run is a working drift detector (it reads over
    SSH, which is fast).

ENCODING: pfSense stores each option <value> base64-encoded in config.xml, but
the REST API (like the GUI field) takes the PLAIN string. This script decodes
what it reads before diffing, so the manifest stays human-readable and the diff
is meaningful.

Matching strategy: upsert by (interface, number). Options NOT listed in the
manifest are LEFT UNTOUCHED. The API addresses an option by (parent_id, id)
where parent_id is the interface name (e.g. "opt2") and id is the item's index
within that scope -- taken from config.xml ordering, the same ordering the API
exposes.

Workflow:
    scripts/sync-pfsense-dhcp-options.py            # dry run -- show diff
    scripts/sync-pfsense-dhcp-options.py --apply    # create/update + apply
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "pfsense" / "dhcp-custom-options.yml"

PFSENSE_API = "https://pfsense.home.lcamaral.com/api/v2"
TOKEN_KEYCHAIN_SERVICE = "pfsense-api-token"

# Fields we reconcile. `interface` and `number` form the key and are not diffed.
FIELDS = ("type", "value")


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


def _decode(value: str) -> str:
    """config.xml stores option values base64-encoded. Fall back to the raw
    string if it is not valid base64 -- older hand-made entries may be plain."""
    if not value:
        return ""
    try:
        return base64.b64decode(value, validate=True).decode("utf-8", "replace")
    except (binascii.Error, ValueError):
        return value


def fetch_live() -> dict[tuple[str, str], dict]:
    """Read <dhcpd> from config.xml via SSH.

    Returns {(interface, number): {type, value, index}} where `index` is the
    item's position within its scope's <numberoptions> (the API's `id`).

    Only SCOPE-level <numberoptions> are read. ElementTree's findall() matches
    direct children only, so the empty per-<staticmap> <numberoptions> elements
    are correctly skipped.
    """
    out = subprocess.run(
        ["ssh", "pfsense", "awk '/<dhcpd>/,/<\\/dhcpd>/' /cf/conf/config.xml"],
        capture_output=True, text=True, check=True,
    )
    # stdlib ElementTree, matching the sibling sync scripts. The input is our
    # own /cf/conf/config.xml pulled over authenticated SSH, not untrusted
    # input, and ElementTree does not resolve external entities.
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    tree = ET.fromstring("<root>" + out.stdout + "</root>")
    dhcpd = tree.find("dhcpd")
    live: dict[tuple[str, str], dict] = {}
    if dhcpd is None:
        return live
    for scope in dhcpd:
        iface = scope.tag
        index = 0
        for numopts in scope.findall("numberoptions"):
            for item in numopts.findall("item"):
                number = _text(item, "number")
                if not number:
                    continue
                live[(iface, number)] = {
                    "type": _text(item, "type"),
                    "value": _decode(_text(item, "value")),
                    "index": index,
                }
                index += 1
    return live


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="Create/update options and apply (default: dry-run)")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")
    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    declared = data.get("options", [])
    if not declared:
        print("no custom options declared in manifest")
        return 0

    live = fetch_live()
    print(f"live custom options across all scopes: {len(live)}")

    token = keychain_token() if args.apply else ""
    pending = 0

    for d in declared:
        iface = d["interface"]
        number = str(d["number"])
        label = f"{iface} option {number}"
        cur = live.get((iface, number))

        if cur is None:
            print(f"  + CREATE {label} = {d['value']!r}")
            pending += 1
            if args.apply:
                body = {
                    "parent_id": iface,
                    "number": int(number),
                    "type": d.get("type", "string"),
                    "value": d["value"],
                }
                resp = api("POST", "/services/dhcp_server/custom_option", token, body)
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
                "number": int(number),
                "type": d.get("type", "string"),
                "value": d["value"],
            }
            api("PATCH", "/services/dhcp_server/custom_option", token, body)
            print("    -> updated")

    if pending == 0:
        print("DHCP custom options in sync.")
        return 0

    if not args.apply:
        print(f"\n{pending} change(s) pending -- re-run with --apply.")
        return 0

    # Changes only reach dhcpd.conf once applied; this restarts the DHCP
    # service. Existing leases survive -- clients pick up new options on renewal.
    print("\napplying DHCP server changes (restarts dhcpd)...")
    api("POST", "/services/dhcp_server/apply", token, {})
    print("applied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
