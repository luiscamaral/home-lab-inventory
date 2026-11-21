#!/usr/bin/env python3
"""
Sync repo-declared pfSense DHCP static mappings (reservations) to the live
<dhcpd><optN><staticmap> entries in pfSense's config.xml.

Source of truth: pfsense/dhcp-static-mappings.yml
Read:  SSH to pfSense, awk the <dhcpd> block out of /cf/conf/config.xml.
Write: PHP on pfSense, run over SSH. It uses the same calls as the GUI page
       "Services > DHCP Server > edit static mapping": config_set_path,
       write_config and mark_subsystem_dirty.

Why not the REST API: on 2026-11-16 a REST write for the ADMIN scope ran for 180 s
and then timed out. The API loads every reservation (258 in the HOME scope) for
each call, and HAProxy cuts requests at 30 s. The PHP path takes a moment.

Matching strategy: upsert by (interface, mac). MAC is the identity. Any
reservation NOT listed in the manifest is LEFT UNTOUCHED -- the HOME scope is
full of hand-made entries that predate this manifest and must never be deleted.

Safety rules:
  * Each write is sent once. The script never resends a write.
  * pfSense validates the entry first: valid MAC and IPv4, inside the interface
    subnet, outside the dynamic range and pools, and not used by another MAC.
  * The dry run asks pfSense to validate each pending change without writing.
  * After a write the script reads the live config back and compares it.
  * If the outcome is unknown, the script stops. It does not retry.
  * The SSH path is the ADMIN address (igc3). It does not depend on the ix0 trunk.
  * write_config keeps its normal backup in /cf/conf/backup. To roll back, restore the
    previous revision in the GUI (Diagnostics > Backup & Restore > Config History).

A write changes the stored configuration only. The DHCP server keeps running its
old configuration until you pass --activate. That reloads only dhcpd, and existing
leases survive. It does not restart the DNS resolver. The resolver registers the
new static name at its next reload.

Workflow:
    scripts/sync-pfsense-dhcp-static-mappings.py                        # dry run + validate
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

PHP_TIMEOUT = 120  # seconds
# ADMIN path (igc3). It stays up when the ix0 trunk is down. The host key is
# stored under the HOME address, so HostKeyAlias keeps strict checking.
ADMIN_SSH = ["ssh", "-o", "HostName=192.168.32.33",
             "-o", "HostKeyAlias=[192.168.4.1]:3220",
             "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
             "pfsense"]

# Fields we reconcile. `mac` and `interface` form the key and are not diffed.
FIELDS = ("ipaddr", "hostname", "descr")

# PHP run on pfSense. The payload is JSON in a nowdoc, so nothing needs escaping.
PHP_TEMPLATE = r"""<?php
require_once("config.inc");
require_once("util.inc");
require_once("services.inc");
require_once("pfsense-utils.inc");
require_once("interfaces.inc");

function done(array $r): void {
    echo json_encode($r), "\n";
    exit($r['ok'] ? 0 : 1);
}
function fail(string $why): void {
    done(['ok' => false, 'error' => $why]);
}

$d = json_decode(<<<'JSON'
@@PAYLOAD@@
JSON, true);
if (!is_array($d) || !isset($d['op'])) {
    fail('bad payload');
}

if ($d['op'] === 'activate') {
    $rc = services_dhcpd_configure();
    if ($rc == 0) {
        clear_subsystem_dirty('dhcpd');
    }
    done(['ok' => $rc == 0, 'op' => 'activate', 'rc' => $rc]);
}

$if = (string)$d['interface'];
$mac = strtolower((string)$d['mac']);
$ip = (string)$d['ipaddr'];
if (!config_path_enabled("dhcpd/{$if}")) {
    fail("DHCP server is not enabled on {$if}");
}
if (!is_macaddr($mac)) {
    fail("bad MAC {$mac}");
}
if (!is_ipaddrv4($ip)) {
    fail("bad IPv4 {$ip}");
}
$ifip = config_get_path("interfaces/{$if}/ipaddr");
$bits = config_get_path("interfaces/{$if}/subnet");
if (!is_ipaddrv4($ifip) || !ip_in_subnet($ip, "{$ifip}/{$bits}")) {
    fail("{$ip} is outside the subnet of {$if}");
}
if ($ip === $ifip) {
    fail("{$ip} is the address of {$if} itself");
}
$from = config_get_path("dhcpd/{$if}/range/from");
$to = config_get_path("dhcpd/{$if}/range/to");
if ($from && $to && is_inrange_v4($ip, $from, $to)) {
    fail("{$ip} is inside the dynamic range {$from}-{$to}");
}
foreach (config_get_path("dhcpd/{$if}/pool", []) as $pool) {
    if (is_inrange_v4($ip, $pool['range']['from'], $pool['range']['to'])) {
        fail("{$ip} is inside an address pool");
    }
}

$maps = config_get_path("dhcpd/{$if}/staticmap", []);
$found = null;
foreach ($maps as $i => $m) {
    if (strtolower($m['mac'] ?? '') === $mac) {
        $found = $i;
    } elseif (($m['ipaddr'] ?? '') === $ip) {
        fail("{$ip} is already reserved for " . ($m['mac'] ?? '?'));
    }
}

$new = ($found !== null) ? $maps[$found] : [];
$new['mac'] = $mac;
$new['cid'] = $new['cid'] ?? '';
$new['ipaddr'] = $ip;
$new['hostname'] = (string)$d['hostname'];
$new['descr'] = (string)$d['descr'];

$action = 'create';
if ($found !== null) {
    $same = ($maps[$found]['ipaddr'] ?? '') === $ip
        && ($maps[$found]['hostname'] ?? '') === $new['hostname']
        && ($maps[$found]['descr'] ?? '') === $new['descr'];
    $action = $same ? 'noop' : 'update';
}
if (!empty($d['dry']) || $action === 'noop') {
    done(['ok' => true, 'action' => $action, 'dry' => !empty($d['dry'])]);
}

if ($found !== null) {
    $maps[$found] = $new;
} else {
    $maps[] = $new;
}
usort($maps, fn($a, $b) => ipcmp($a['ipaddr'], $b['ipaddr']));
config_set_path("dhcpd/{$if}/staticmap", $maps);
write_config("DHCP static mapping {$new['hostname']} ({$mac}) set by sync-pfsense-dhcp-static-mappings.py");
mark_subsystem_dirty('dhcpd');
done(['ok' => true, 'action' => $action, 'dry' => false]);
"""


class OutcomeUnknown(RuntimeError):
    """A write was sent but its result is not known. Do not retry blindly."""


def php_run(payload: dict) -> dict:
    """Run the PHP above once on pfSense. Returns its JSON answer."""
    body = json.dumps(payload)
    try:
        r = subprocess.run(ADMIN_SSH + ["php -q"], input=PHP_TEMPLATE.replace("@@PAYLOAD@@", body),
                           capture_output=True, text=True, timeout=PHP_TIMEOUT)
    except subprocess.TimeoutExpired as e:
        raise OutcomeUnknown(f"no answer after {e.timeout}s") from e
    lines = [ln for ln in r.stdout.splitlines() if ln.startswith("{")]
    if not lines:
        raise OutcomeUnknown(f"ssh/php exit {r.returncode}, no JSON answer: {(r.stderr or r.stdout).strip()[:300]}")
    try:
        answer = json.loads(lines[-1])
    except json.JSONDecodeError as e:
        raise OutcomeUnknown(f"unreadable answer: {lines[-1][:200]!r}") from e
    if not answer.get("ok"):
        raise SystemExit(f"error: pfSense refused: {answer.get('error', answer)}")
    return answer


def _text(el, tag: str) -> str:
    child = el.find(tag)
    return (child.text or "").strip() if child is not None and child.text else ""


def fetch_live() -> dict[tuple[str, str], dict]:
    """Read <dhcpd> from config.xml via SSH.

    Returns {(interface, mac_lower): {ipaddr, hostname, descr, index}} where
    `index` is the mapping's position within its scope.
    """
    out = subprocess.run(
        ADMIN_SSH + ["awk '/<dhcpd>/,/<\\/dhcpd>/' /cf/conf/config.xml"],
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


def _payload(want: dict, dry: bool) -> dict:
    return {"op": "upsert", "interface": want["interface"], "mac": str(want["mac"]).lower(),
            "ipaddr": want["ipaddr"], "hostname": want.get("hostname", ""),
            "descr": want.get("descr", ""), "dry": dry}


def validate(want: dict) -> None:
    """Ask pfSense to validate one mapping without writing it."""
    try:
        answer = php_run(_payload(want, dry=True))
    except OutcomeUnknown as e:
        sys.exit(f"error: could not validate on pfSense: {e}")
    print(f"    pfSense accepts it ({answer['action']}, nothing written)")


def write_and_verify(want: dict) -> None:
    """Send one write, then read the live config back and compare."""
    iface, mac = want["interface"], str(want["mac"]).lower()
    try:
        php_run(_payload(want, dry=False))
    except OutcomeUnknown as e:
        sys.exit(f"outcome unknown: {e}\nDo NOT retry. Run the dry run to see the live state.")
    cur = fetch_live().get((iface, mac))
    if cur is None or any(cur[k] != str(want.get(k, "")) for k in FIELDS):
        sys.exit(f"error: pfSense answered, but live config does not match for {iface} {mac}: {cur}")
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
            php_run({"op": "activate"})
        except OutcomeUnknown as e:
            sys.exit(f"outcome unknown: {e}\nDo NOT retry. Check dhcpd on pfSense first.")
        print("reload done.")
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

    pending = 0

    for d in declared:
        iface = d["interface"]
        mac = str(d["mac"]).lower()
        label = f"{iface} {mac} -> {d['ipaddr']}"
        cur = live.get((iface, mac))

        if cur is None:
            print(f"  + CREATE {label}  ({d.get('descr', '')})")
        else:
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
            write_and_verify(d)
        else:
            validate(d)

    if pending == 0:
        print("DHCP static mappings in sync.")
    elif not args.apply:
        print(f"\n{pending} change(s) pending -- re-run with --apply.")
    else:
        print("\nStored. dhcpd still runs its old config: use --activate to reload it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
