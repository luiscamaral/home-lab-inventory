#!/usr/bin/env python3
"""Sync pfSense firewall limits from pfsense/firewall-limits.yml.

Read:  PHP on pfSense prints the managed keys of <system>.
Write: PHP on pfSense, with the same calls as System > Advanced > Firewall & NAT
       (saveSystemAdvancedFirewall): config_set_path, write_config, filter_configure.
       It writes once and reads the result back. It never retries a write.
Check: pfctl -sm must show the new states hard limit.
The SSH path is the ADMIN address (igc3). It does not depend on the ix0 trunk.

Usage:
    scripts/sync-pfsense-firewall-limits.py           # plan
    scripts/sync-pfsense-firewall-limits.py --apply   # write, reload pf, verify
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml

SOURCE = Path(__file__).resolve().parents[1] / "pfsense/firewall-limits.yml"
ADMIN_SSH = ["ssh", "-o", "HostName=192.168.32.33", "-o", "HostKeyAlias=[192.168.4.1]:3220",
             "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "pfsense"]
KEYS = ("maximumstates",)
WRITE_FUNCTIONS = ("config_get_path", "config_set_path", "is_numericint", "write_config", "filter_configure")

PREFLIGHT_PHP = r"""
require_once("config.inc");
require_once("filter.inc");
require_once("util.inc");
foreach (%s as $f) { if (!function_exists($f)) { echo $f, PHP_EOL; } }
"""
READ_PHP = r"""
require_once("config.inc");
$out = [];
foreach (%s as $k) { $out[$k] = (string) config_get_path("system/$k", ""); }
echo json_encode($out), PHP_EOL;
"""
WRITE_PHP = r"""
require_once("config.inc");
require_once("filter.inc");
require_once("util.inc");
$want = json_decode('%s', true);
foreach ($want as $k => $v) {
    if (!is_numericint($v)) { fwrite(STDERR, "not an integer: $k\n"); exit(2); }
    config_set_path("system/$k", $v);
}
write_config("firewall limits set by scripts/sync-pfsense-firewall-limits.py");
$rv = filter_configure();
echo "written, filter_configure=", var_export($rv, true), PHP_EOL;
"""


def php(code, timeout=60):
    result = subprocess.run([*ADMIN_SSH, "php"], input=code.join(("<?php\n", "\n")), text=True,
                            capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        detail = (result.stderr.strip() or result.stdout.strip())[-500:]
        raise RuntimeError(f"PHP on pfSense failed ({result.returncode}): {detail}")
    return result.stdout.strip()


def desired():
    data = yaml.safe_load(SOURCE.read_text())
    return {k: str(data[k]) for k in KEYS}


def live():
    return json.loads(php(READ_PHP % f"json_decode('{json.dumps(KEYS)}', true)"))


def states_hard_limit():
    out = subprocess.run([*ADMIN_SSH, "pfctl", "-sm"], capture_output=True, text=True, timeout=30, check=True).stdout
    return int(re.search(r"^states\s+hard limit\s+(\d+)", out, re.MULTILINE).group(1))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        missing = php(PREFLIGHT_PHP % f"json_decode('{json.dumps(WRITE_FUNCTIONS)}', true)").split()
        if missing:
            raise RuntimeError(f"pfSense lacks PHP functions the write needs: {missing}. No changes made.")
        want = desired()
        current = live()
        changes = {k: (current.get(k), v) for k, v in want.items() if current.get(k) != v}
        print(f"pf states hard limit now: {states_hard_limit()}")
        for key, (old, new) in changes.items():
            print(f"system/{key}: {old!r} -> {new!r}")
        if not changes:
            print("No changes.")
            return
        if not args.apply:
            return
        print(php(WRITE_PHP % json.dumps(want), timeout=180))
        left = {k: v for k, v in want.items() if live().get(k) != v}
        if left:
            raise RuntimeError(f"Readback differs after the write: {left}. Do not retry; inspect the live config.")
        limit = states_hard_limit()
        if limit != int(want["maximumstates"]):
            raise RuntimeError(f"pfctl -sm shows {limit}, expected {want['maximumstates']}. Do not retry; inspect pf.")
        print(f"Verified: config matches, pf states hard limit {limit}.")
    except (OSError, RuntimeError, ValueError, AttributeError, subprocess.SubprocessError) as exc:
        sys.exit(f"{exc}\nRead the live pfSense config before retrying.")


if __name__ == "__main__":
    main()
