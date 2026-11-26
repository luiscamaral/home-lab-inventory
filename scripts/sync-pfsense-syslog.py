#!/usr/bin/env python3
"""Sync pfSense remote syslog settings from pfsense/syslog.yml.

Read:  PHP on pfSense prints the managed keys of the <syslog> config as JSON.
Write: PHP on pfSense, with the same calls as Status > System Logs > Settings:
       config_set_path, write_config, system_sshguard_stop, system_syslogd_start.
       It writes once and reads the result back. It never retries a write.
The SSH path is the ADMIN address (igc3). It does not depend on the ix0 trunk.

Usage:
    scripts/sync-pfsense-syslog.py            # plan: show the diff, change nothing
    scripts/sync-pfsense-syslog.py --apply    # write, reload syslogd, verify
    scripts/sync-pfsense-syslog.py --test     # send one tagged test message with logger
"""

import argparse
import base64
import json
import subprocess
import sys
import uuid
from pathlib import Path

import yaml

SOURCE = Path(__file__).resolve().parents[1] / "pfsense/syslog.yml"
# pfSense's SSH host key is stored under the HOME address, so HostKeyAlias keeps strict checking.
ADMIN_SSH = ["ssh", "-o", "HostName=192.168.32.33", "-o", "HostKeyAlias=[192.168.4.1]:3220",
             "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "pfsense"]
GENERATED_CONF = "/var/etc/syslog.d/pfSense.conf"
STRING_KEYS = ("remoteserver", "remoteserver2", "remoteserver3", "sourceip", "ipproto")
BOOL_KEYS = ("enable", "logall", "system", "dpinger", "routing", "auth", "filter", "resolver", "dhcp")

READ_PHP = r"""
require_once("config.inc");
$keys = %s;
$out = [];
foreach ($keys["string"] as $k) { $out[$k] = (string) config_get_path("syslog/$k", ""); }
foreach ($keys["bool"] as $k) { $out[$k] = config_path_enabled("syslog", $k); }
echo json_encode($out), PHP_EOL;
"""

WRITE_PHP = r"""
require_once("config.inc");
require_once("system.inc");
require_once("syslog.inc");
$want = json_decode(base64_decode("%s"), true);
$parts = explode(":", $want["remoteserver"]);
if ($want["enable"] && !(count($parts) == 2 && is_ipaddrv4($parts[0]) && is_port($parts[1]))) {
    fwrite(STDERR, "invalid remoteserver, expected IPv4:port\n"); exit(2);
}
if (!array_key_exists($want["sourceip"], config_get_path("interfaces", []))) {
    fwrite(STDERR, "unknown sourceip interface\n"); exit(2);
}
foreach (%s as $k) { config_set_path("syslog/$k", $want[$k]); }
foreach (%s as $k) { config_set_path("syslog/$k", $want[$k] ? true : false); }
write_config("syslog: remote logging set by scripts/sync-pfsense-syslog.py");
system_sshguard_stop();
system_syslogd_start();
echo "written", PHP_EOL;
"""


# Every PHP function WRITE_PHP calls. The plan checks they exist on the live pfSense.
# is_valid_syslog_server is not listed: it lives only in the GUI page, not in an include.
WRITE_FUNCTIONS = ("config_get_path", "config_set_path", "is_ipaddrv4", "is_port", "write_config",
                   "system_sshguard_stop", "system_syslogd_start")

PREFLIGHT_PHP = r"""
require_once("config.inc");
require_once("system.inc");
require_once("syslog.inc");
foreach (%s as $f) { if (!function_exists($f)) { echo $f, PHP_EOL; } }
"""


def php(code, timeout=60):
    result = subprocess.run([*ADMIN_SSH, "php"], input=code.join(("<?php\n", "\n")), text=True,
                            capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        detail = (result.stderr.strip() or result.stdout.strip())[-500:]
        raise RuntimeError(f"PHP on pfSense failed ({result.returncode}): {detail}")
    return result.stdout.strip()


def preflight():
    missing = php(PREFLIGHT_PHP % f"json_decode('{json.dumps(WRITE_FUNCTIONS)}', true)").split()
    if missing:
        raise RuntimeError(f"pfSense lacks PHP functions the write needs: {missing}. No changes made.")


def desired():
    data = yaml.safe_load(SOURCE.read_text())
    want = {k: str(data.get(k) or "") for k in STRING_KEYS}
    want.update({k: bool(data.get(k)) for k in BOOL_KEYS})
    return want


def live():
    keys = json.dumps({"string": STRING_KEYS, "bool": BOOL_KEYS})
    return json.loads(php(READ_PHP % f"json_decode('{keys}', true)"))


def diff(current, want):
    return {k: (current.get(k), v) for k, v in want.items() if current.get(k) != v}


def apply(want):
    payload = base64.b64encode(json.dumps(want).encode()).decode()
    out = php(WRITE_PHP % (payload, f"json_decode('{json.dumps(STRING_KEYS)}', true)",
                           f"json_decode('{json.dumps(BOOL_KEYS)}', true)"), timeout=120)
    print(out)
    left = diff(live(), want)
    if left:
        raise RuntimeError(f"Readback differs after the write: {left}. Do not retry; inspect the live config.")
    # /etc/syslog.conf only includes /var/etc/syslog.d. pfSense writes the remote rules there.
    conf = subprocess.run([*ADMIN_SSH, "grep", "-c", "@" + want["remoteserver"], GENERATED_CONF],
                          capture_output=True, text=True, timeout=30, check=False).stdout.strip()
    if want["enable"] and conf in ("", "0"):
        raise RuntimeError(f"{GENERATED_CONF} has no line for the remote server")
    print(f"Verified: config matches, {GENERATED_CONF} has {conf} remote lines.")


def send_test():
    tag = f"homelab-syslog-test-{uuid.uuid4().hex[:12]}"
    subprocess.run([*ADMIN_SSH, "logger", "-p", "user.notice", "-t", "homelab-syslog-test", tag],
                   check=True, timeout=30)
    print(tag)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--apply", action="store_true")
    group.add_argument("--test", action="store_true")
    args = parser.parse_args()
    try:
        if args.test:
            send_test()
            return
        want = desired()
        preflight()
        changes = diff(live(), want)
        for key, (old, new) in changes.items():
            print(f"syslog/{key}: {old!r} -> {new!r}")
        if not changes:
            print("No changes.")
        elif args.apply:
            apply(want)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as exc:
        sys.exit(f"{exc}\nRead the live pfSense config before retrying.")


if __name__ == "__main__":
    main()
