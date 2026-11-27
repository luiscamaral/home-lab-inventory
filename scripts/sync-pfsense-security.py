#!/usr/bin/env python3
"""Sync pfSense security settings from pfsense/security.yml.

Manages three things:
  * host alias with the block-list addresses (aliases/alias, matched by name)
  * two floating quick block rules (filter/rule, matched by fixed tracker IDs):
    destination in the alias, and source in the alias. They are placed first among the rules.
  * the miniupnpd master enable flag (installedpackages/miniupnpd/config/0/enable)

Write: PHP on pfSense with the same calls as the GUI pages: config_set_path, write_config,
filter_configure, sync_package_miniupnpd. It writes once and reads back. It never retries a write.
The SSH path is the ADMIN address (igc3). It does not depend on the ix0 trunk.

Usage:
    scripts/sync-pfsense-security.py           # plan
    scripts/sync-pfsense-security.py --apply   # write, reload, verify
"""

import argparse
import base64
import json
import subprocess
import sys
import time
from pathlib import Path

import yaml

SOURCE = Path(__file__).resolve().parents[1] / "pfsense/security.yml"
ADMIN_SSH = ["ssh", "-o", "HostName=192.168.32.33", "-o", "HostKeyAlias=[192.168.4.1]:3220",
             "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "pfsense"]
WRITE_FUNCTIONS = ("config_get_path", "config_set_path", "write_config", "filter_configure", "is_ipaddrv4",
                   "sync_package_miniupnpd")
INCLUDES = 'require_once("config.inc"); require_once("filter.inc"); require_once("util.inc");' \
           ' require_once("/usr/local/pkg/miniupnpd.inc");'

READ_PHP = INCLUDES + r"""
$want = json_decode(base64_decode("%s"), true);
$out = ["alias" => null, "rules" => [], "upnp_enable" => (string) config_get_path("installedpackages/miniupnpd/config/0/enable", "")];
foreach (config_get_path("aliases/alias", []) as $a) { if ($a["name"] == $want["alias"]) { $out["alias"] = $a; } }
foreach (config_get_path("filter/rule", []) as $i => $r) {
    if (in_array((string) ($r["tracker"] ?? ""), $want["trackers"], true)) { $r["_index"] = $i; $out["rules"][] = $r; }
}
echo json_encode($out), PHP_EOL;
"""

PREFLIGHT_PHP = INCLUDES + r"""
foreach (%s as $f) { if (!function_exists($f)) { echo $f, PHP_EOL; } }
"""

WRITE_PHP = INCLUDES + r"""
$w = json_decode(base64_decode("%s"), true);
foreach ($w["alias"]["address_list"] as $ip) { if (!is_ipaddrv4($ip)) { fwrite(STDERR, "bad address $ip\n"); exit(2); } }
$aliases = config_get_path("aliases/alias", []);
$aliases = array_values(array_filter($aliases, fn($a) => $a["name"] != $w["alias"]["name"]));
$aliases[] = ["name" => $w["alias"]["name"], "type" => "host", "address" => implode(" ", $w["alias"]["address_list"]),
              "descr" => $w["alias"]["descr"], "detail" => implode("||", $w["alias"]["detail_list"])];
config_set_path("aliases/alias", $aliases);
$rules = config_get_path("filter/rule", []);
$rules = array_values(array_filter($rules, fn($r) => !in_array((string) ($r["tracker"] ?? ""), $w["trackers"], true)));
$now = (string) time(); $who = "scripts/sync-pfsense-security.py";
$new = [];
foreach ($w["rules"] as $spec) {
    $new[] = ["tracker" => $spec["tracker"], "type" => "block", "interface" => $w["interfaces"], "ipprotocol" => "inet",
              "direction" => "any", "quick" => "yes", "floating" => "yes", "statetype" => "keep state", "log" => "",
              "source" => $spec["source"], "destination" => $spec["destination"], "descr" => $spec["descr"],
              "created" => ["time" => $now, "username" => $who], "updated" => ["time" => $now, "username" => $who]];
}
config_set_path("filter/rule", array_merge($new, $rules));
if ($w["upnp_enable"]) { config_set_path("installedpackages/miniupnpd/config/0/enable", "on"); }
else { config_set_path("installedpackages/miniupnpd/config/0/enable", ""); }
write_config("security: block list and UPnP set by scripts/sync-pfsense-security.py");
$rv = filter_configure();
sync_package_miniupnpd();
echo "written, filter_configure=", var_export($rv, true), PHP_EOL;
"""


def run(args, stdin=None, timeout=60, check=True):
    result = subprocess.run([*ADMIN_SSH, *args], input=stdin, text=True, capture_output=True,
                            timeout=timeout, check=False)
    if check and result.returncode:
        detail = (result.stderr.strip() or result.stdout.strip())[-500:]
        raise RuntimeError(f"pfSense command {args[0]} failed ({result.returncode}): {detail}")
    return result.stdout.strip()


def php(code, timeout=60):
    return run(["php"], stdin=code.join(("<?php\n", "\n")), timeout=timeout)


def b64(data):
    return base64.b64encode(json.dumps(data).encode()).decode()


def desired():
    data = yaml.safe_load(SOURCE.read_text())
    bl = data["blocklist"]
    alias = bl["alias"]
    return {
        "alias": {"name": alias, "descr": bl["descr"],
                  "address_list": [a["ip"] for a in bl["addresses"]],
                  "detail_list": [a["note"] for a in bl["addresses"]]},
        "interfaces": ",".join(bl["interfaces"]),
        "trackers": [str(bl["trackers"]["to"]), str(bl["trackers"]["from"])],
        "rules": [
            {"tracker": str(bl["trackers"]["to"]), "source": {"any": ""}, "destination": {"address": alias},
             "descr": f"Block traffic to {alias}"},
            {"tracker": str(bl["trackers"]["from"]), "source": {"address": alias}, "destination": {"any": ""},
             "descr": f"Block traffic from {alias}"},
        ],
        "upnp_enable": bool(data["upnp"]["enable"]),
    }


def live(want):
    return json.loads(php(READ_PHP % b64({"alias": want["alias"]["name"], "trackers": want["trackers"]})))


def differences(cur, want):
    diffs = []
    a = cur["alias"] or {}
    if a.get("address", "").split() != want["alias"]["address_list"] or a.get("type") != "host" \
            or a.get("descr") != want["alias"]["descr"]:
        diffs.append(f"alias {want['alias']['name']}: {a.get('address', '(missing)')!r} -> "
                     f"{' '.join(want['alias']['address_list'])!r}")
    rules = {r["tracker"]: r for r in cur["rules"]}
    for spec in want["rules"]:
        r = rules.get(spec["tracker"])
        ok = r and r.get("type") == "block" and r.get("floating") == "yes" and r.get("quick") == "yes" \
            and r.get("direction") == "any" and r.get("interface") == want["interfaces"] \
            and r.get("source") == spec["source"] and r.get("destination") == spec["destination"] \
            and "disabled" not in r
        if not ok:
            diffs.append(f"floating rule {spec['tracker']}: {'update' if r else 'add'} ({spec['descr']})")
    if sorted(r["_index"] for r in cur["rules"]) != list(range(len(cur["rules"]))) and cur["rules"]:
        diffs.append("floating rules: move to the top of the rule list")
    upnp_on = cur["upnp_enable"] == "on"
    if upnp_on != want["upnp_enable"]:
        diffs.append(f"miniupnpd enable: {upnp_on} -> {want['upnp_enable']}")
    return diffs


def verify(want):
    expected = sorted(want["alias"]["address_list"])
    for _ in range(12):
        table = sorted(run(["pfctl", "-t", want["alias"]["name"], "-T", "show"], check=False).split())
        rules = run(["grep", "-c", want["alias"]["name"], "/tmp/rules.debug"], check=False)
        if table == expected and rules not in ("", "0"):
            break
        time.sleep(5)
    else:
        raise RuntimeError(f"pf table {table} or rules ({rules} lines) not as expected after 60 s. Do not retry.")
    upnp = run(["pgrep", "-l", "miniupnpd"], check=False)
    if not want["upnp_enable"] and upnp:
        raise RuntimeError(f"miniupnpd still running: {upnp}. Do not retry; inspect the package state.")
    print(f"Verified: pf table has {len(table)} addresses, {rules} rule lines in rules.debug, "
          f"miniupnpd {'running' if upnp else 'not running'}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        missing = php(PREFLIGHT_PHP % f"json_decode('{json.dumps(WRITE_FUNCTIONS)}', true)").split()
        if missing:
            raise RuntimeError(f"pfSense lacks PHP functions the write needs: {missing}. No changes made.")
        want = desired()
        diffs = differences(live(want), want)
        for d in diffs:
            print(d)
        if not diffs:
            print("No changes.")
            return
        if not args.apply:
            return
        print(php(WRITE_PHP % b64(want), timeout=180))
        left = differences(live(want), want)
        if left:
            raise RuntimeError(f"Readback differs after the write: {left}. Do not retry; inspect the live config.")
        verify(want)
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit(f"{exc}\nRead the live pfSense config before retrying.")


if __name__ == "__main__":
    main()
