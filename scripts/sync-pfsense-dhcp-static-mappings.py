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

Writes: each write is sent ONCE. The script never resends a write after a
timeout. pfSense serves these endpoints slowly (one-mapping reads took ~56 s on
2026-11-16), and HAProxy cuts requests at 30 s. So writes bypass HAProxy: the
script runs curl on pfSense against the local web listener, over the ADMIN path
(igc3), which does not depend on the ix0 trunk. After a write, the script reads
the live config back and reports the real outcome. If the outcome is unknown, it
stops and tells you to inspect the live state. It does not retry.

Writes change the stored configuration only. The DHCP server keeps its running
configuration until you pass --activate, which reloads dhcpd (existing leases
survive).

Workflow:
    scripts/sync-pfsense-dhcp-static-mappings.py                        # dry run
    scripts/sync-pfsense-dhcp-static-mappings.py --apply --only lan MAC # write one
    scripts/sync-pfsense-dhcp-static-mappings.py --activate             # reload dhcpd
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "pfsense" / "dhcp-static-mappings.yml"

# Writes use pfSense's local web listener, past HAProxy's 30 s gateway timeout.
LOCAL_API = "http://127.0.0.1:56880/api/v2"
WRITE_TIMEOUT = 240  # seconds, below nginx fastcgi_read_timeout (360)
# ADMIN path (igc3). It stays up when the ix0 trunk is down. The host key is
# stored under the HOME address, so HostKeyAlias keeps strict checking.
ADMIN_SSH = ["ssh", "-o", "HostName=192.168.32.33",
             "-o", "HostKeyAlias=[192.168.4.1]:3220",
             "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
             "pfsense"]
TOKEN_KEYCHAIN_SERVICE = "pfsense-api-token"

# Fields we reconcile. `mac` and `interface` form the key and are not diffed.
FIELDS = ("ipaddr", "hostname", "descr")


def keychain_token() -> str:
    out = subprocess.run(
        ["security", "find-generic-password", "-s", TOKEN_KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


class OutcomeUnknown(RuntimeError):
    """A write was sent but its result is not known. Do not retry blindly."""


def _cfg(value: str) -> str:
    """Quote a value for a curl config file."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_api(method: str, path: str, token: str, body: dict) -> dict:
    """Send ONE write to the local pfSense API. Never retries.

    The request goes through ssh to curl on pfSense. The token and body travel
    on stdin as a curl config, so they do not appear in any process list.
    """
    cfg = "\n".join([
        f"url = {_cfg(LOCAL_API + path)}",
        f"request = {_cfg(method)}",
        f"header = {_cfg('X-API-Key: ' + token)}",
        'header = "Content-Type: application/json"',
        f"data = {_cfg(json.dumps(body))}",
        "silent",
        "show-error",
        f"max-time = {WRITE_TIMEOUT}",
    ]) + "\n"
    try:
        r = subprocess.run(ADMIN_SSH + ["curl -K -"], input=cfg, capture_output=True,
                           text=True, timeout=WRITE_TIMEOUT + 30)
    except subprocess.TimeoutExpired as e:
        raise OutcomeUnknown(f"{method} {path}: no answer after {e.timeout}s") from e
    if r.returncode != 0:
        raise OutcomeUnknown(f"{method} {path}: curl/ssh exit {r.returncode}: {r.stderr.strip()[:200]}")
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError as e:
        raise OutcomeUnknown(f"{method} {path}: unreadable answer: {r.stdout[:200]!r}") from e


def _check(resp: dict, what: str) -> dict:
    """Fail on an API error answer. The API reports errors in `code`."""
    if int(resp.get("code", 200)) >= 400:
        raise SystemExit(f"error: {what}: API returned {resp.get('code')} "
                         f"{resp.get('message', '')} ({resp.get('response_id', '')})")
    return resp


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
    # Use stdlib ElementTree, like the outbound NAT and cron sync scripts.
    # The input is /cf/conf/config.xml over authenticated SSH. ElementTree does
    # not resolve external entities, so defusedxml adds no protection here.
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


def write_and_verify(method: str, token: str, body: dict, want: dict) -> None:
    """Send one write, then read the live config back and compare."""
    iface, mac = want["interface"], str(want["mac"]).lower()
    try:
        _check(write_api(method, "/services/dhcp_server/static_mapping", token, body),
               f"{method} {iface} {mac}")
    except OutcomeUnknown as e:
        sys.exit(f"outcome unknown: {e}\nDo NOT retry. Run the dry run to see the live state.")
    cur = fetch_live().get((iface, mac))
    if cur is None or any(cur[k] != str(want.get(k, "")) for k in FIELDS):
        sys.exit(f"error: {method} answered, but live config does not match for {iface} {mac}: {cur}")
    print(f"    -> verified live: {iface} {mac} -> {cur['ipaddr']}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="Create/update mappings (default: dry-run)")
    parser.add_argument("--only", nargs=2, metavar=("INTERFACE", "MAC"),
                        help="Reconcile only the specified interface and MAC")
    parser.add_argument("--activate", action="store_true",
                        help="Reload dhcpd so stored changes take effect (no mapping writes)")
    args = parser.parse_args()

    if args.activate:
        if args.apply or args.only:
            sys.exit("error: --activate runs alone")
        print("reloading dhcpd (existing leases survive)...")
        try:
            _check(write_api("POST", "/services/dhcp_server/apply", keychain_token(), {}),
                   "dhcp apply")
        except OutcomeUnknown as e:
            sys.exit(f"outcome unknown: {e}\nDo NOT retry. Check dhcpd on pfSense first.")
        print("reload requested.")
        return 0

    if not MANIFEST.is_file():
        sys.exit(f"error: {MANIFEST} not found")
    with MANIFEST.open() as f:
        data = yaml.safe_load(f) or {}
    declared = data.get("mappings", [])
    if args.only:
        iface, mac = args.only
        declared = [d for d in declared
                    if d["interface"] == iface and str(d["mac"]).lower() == mac.lower()]
        if len(declared) != 1:
            sys.exit(f"error: expected one mapping for {iface} {mac}, found {len(declared)}")
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
                write_and_verify("POST", token, body, d)
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
            write_and_verify("PATCH", token, body, d)

    if pending == 0:
        print("DHCP static mappings in sync.")
    elif not args.apply:
        print(f"\n{pending} change(s) pending -- re-run with --apply.")
    else:
        print("\nStored. dhcpd still runs its old config: use --activate to reload it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
