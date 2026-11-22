#!/usr/bin/env python3
"""Sync Smart Array monitoring and the storage UI panel on the Proxmox host.

Source: hosts/proxmox/storage-monitoring/manifest.json. File sources are relative to hosts/proxmox.
"""

import argparse
import hashlib
import json
import shlex
import subprocess
from pathlib import Path

HOSTS = Path(__file__).resolve().parents[1] / "hosts/proxmox"
SOURCE = HOSTS / "storage-monitoring"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "proxmox"]
METRICS_FILE = "/var/lib/prometheus/node-exporter/smart_array.prom"


def remote(*args, stdin=None, timeout=120, check=True):
    command = shlex.join(["sudo", "-n", "env", "LC_ALL=C", *args])
    return subprocess.run([*SSH, command], input=stdin, check=check, stdout=subprocess.PIPE,
                          text=True, timeout=timeout)


def file_changes(manifest):
    changed = []
    for item in manifest["files"]:
        want = hashlib.sha256((HOSTS / item["src"]).read_bytes()).hexdigest()
        live = remote("sh", "-c", f'stat -c %a {shlex.quote(item["dest"])} && sha256sum {shlex.quote(item["dest"])}',
                      check=False).stdout.split()
        if len(live) < 2 or live[1] != want or live[0] != item["mode"].lstrip("0"):
            changed.append(item)
    return changed


def missing_packages(manifest):
    missing = []
    for package in manifest["packages"]:
        status = remote("dpkg-query", "-W", "-f=${Status}", package, check=False).stdout
        if "install ok installed" not in status:
            missing.append(package)
    return missing


def inactive_units(manifest):
    return [unit for unit in manifest["enable"]
            if remote("systemctl", "is-enabled", unit, check=False).stdout.strip() != "enabled"
            or remote("systemctl", "is-active", unit, check=False).stdout.strip() != "active"]


def plan(manifest):
    packages, files, units = missing_packages(manifest), file_changes(manifest), inactive_units(manifest)
    for package in packages:
        print(f"install package {package} (no recommends)")
    for item in files:
        print(f"write {item['dest']} mode {item['mode']}")
    for unit in units:
        print(f"enable and start {unit}")
    failed = [c for c in manifest.get("checks", []) if remote(*c, check=False).returncode]
    for command in failed:
        print(f"run {' '.join(manifest['post_apply'][0])} (check failed: {' '.join(command)})")
    if not packages and not files and not units and not failed:
        print("No changes.")
    return packages, files, units


def apply(manifest):
    packages, files, units = plan(manifest)
    if packages:
        remote("apt-get", "install", "-y", "--no-install-recommends", *packages, timeout=600)
    for item in files:
        remote("install", "-D", "-m", item["mode"], "/dev/stdin", item["dest"],
               stdin=(HOSTS / item["src"]).read_text())
    remote("systemctl", "daemon-reload")
    for unit in {item["restart"] for item in files if item.get("restart")}:
        remote("systemctl", "restart", unit)
    if units:
        remote("systemctl", "enable", "--now", *units)
    remote("systemctl", "start", manifest["run_after_apply"], timeout=330)
    for command in manifest.get("post_apply", []):
        print(remote(*command, timeout=120).stdout.strip())
    verify(manifest)


def verify(manifest):
    problems = [f"package {p} missing" for p in missing_packages(manifest)]
    problems += [f"{i['dest']} differs" for i in file_changes(manifest)]
    problems += [f"{u} not enabled and active" for u in inactive_units(manifest)]
    result = remote("systemctl", "show", manifest["run_after_apply"], "-p", "Result", "--value").stdout.strip()
    if result != "success":
        problems.append(f"{manifest['run_after_apply']} result is {result}")
    scrape = remote("curl", "-fsS", "--max-time", "10", "http://127.0.0.1:9100/metrics", check=False).stdout
    count = sum(1 for line in scrape.splitlines() if line.startswith("homelab_smart_array_physical_drive_ok{"))
    if count == 0:
        problems.append("node_exporter serves no homelab_smart_array_physical_drive_ok series")
    for command in manifest.get("checks", []):
        if remote(*command, check=False).returncode:
            problems.append(f"check failed: {' '.join(command)}")
    if problems:
        raise ValueError("; ".join(problems))
    print(f"Verified. node_exporter serves {count} drive series.")


def remove(manifest):
    remote("systemctl", "disable", "--now", "homelab-smart-array-collect.timer", check=False)
    for command in manifest.get("pre_remove", []):
        remote(*command, check=False)
    for item in manifest["files"]:
        if item.get("remove"):
            remote("rm", "-f", item["dest"])
    remote("rm", "-f", METRICS_FILE)
    remote("systemctl", "daemon-reload")
    print("Removed the collector, its timer, the UI panel, the APT hook, the metrics file and the Notes block. "
          "prometheus-node-exporter and its settings stay installed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true")
    action.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    try:
        if args.apply:
            apply(manifest)
        elif args.remove:
            remove(manifest)
        else:
            plan(manifest)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"{exc}\nRead the live host state before retrying.\n")


if __name__ == "__main__":
    main()
