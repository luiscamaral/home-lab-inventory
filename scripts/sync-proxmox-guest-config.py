#!/usr/bin/env python3
"""Sync guest boot order and EFI disks on the Proxmox host from hosts/proxmox/guest-config.json."""

import argparse
import json
import shlex
import subprocess
import time
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / "hosts/proxmox/guest-config.json"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "proxmox"]
SHUTDOWN_TIMEOUT = 180
AGENT_WAIT = 240


def remote(*args, timeout=60, check=True):
    command = shlex.join(["sudo", "-n", *args])
    return subprocess.run([*SSH, command], check=check, stdout=subprocess.PIPE, text=True,
                          timeout=timeout).stdout


def guest_config(node, kind, vmid):
    return json.loads(remote("pvesh", "get", f"/nodes/{node}/{kind}/{vmid}/config",
                             "--output-format", "json"))


def startup_changes(manifest):
    changes = []
    for vmid, want in manifest["guests"].items():
        conf = guest_config(manifest["node"], want["type"], vmid)
        name = conf.get("name") or conf.get("hostname")
        if name != want["name"]:
            raise ValueError(f"Guest {vmid} is {name!r}, expected {want['name']!r}. No changes made.")
        if conf.get("startup") != want["startup"]:
            changes.append((vmid, want["type"], conf.get("startup"), want["startup"]))
    return changes


def efidisk_changes(manifest):
    changes = []
    for vmid, spec in manifest["efidisks"].items():
        conf = guest_config(manifest["node"], "qemu", vmid)
        if conf.get("bios") != "ovmf":
            raise ValueError(f"VM {vmid} does not use OVMF. No changes made.")
        if "efidisk0" not in conf:
            changes.append((vmid, spec))
    return changes


def plan(manifest):
    startup = startup_changes(manifest)
    efidisks = efidisk_changes(manifest)
    for vmid, kind, old, new in startup:
        print(f"{kind} {vmid} startup: {old!r} -> {new!r}")
    for vmid, spec in efidisks:
        print(f"qemu {vmid} efidisk0: add {spec} (needs a VM shutdown and start)")
    if not startup and not efidisks:
        print("No changes.")
    return startup, efidisks


def apply_startup(manifest, changes):
    for vmid, kind, _, new in changes:
        tool = "qm" if kind == "qemu" else "pct"
        remote(tool, "set", vmid, "--startup", new)
    if startup_changes(manifest):
        raise ValueError("Startup readback differs from the manifest. Inspect before retrying.")
    print(f"Startup settings verified for {len(manifest['guests'])} guests.")


def wait_for_agent(vmid):
    deadline = time.monotonic() + AGENT_WAIT
    while time.monotonic() < deadline:
        if subprocess.run([*SSH, f"sudo -n qm agent {vmid} ping"], check=False, timeout=30).returncode == 0:
            return
        time.sleep(10)
    raise ValueError(f"VM {vmid} guest agent did not answer within {AGENT_WAIT} s.")


def apply_efidisk(manifest, vmid, spec):
    print(f"Shutting down VM {vmid} cleanly (timeout {SHUTDOWN_TIMEOUT} s).")
    remote("qm", "shutdown", vmid, "--timeout", str(SHUTDOWN_TIMEOUT), timeout=SHUTDOWN_TIMEOUT + 30)
    if "status: stopped" not in remote("qm", "status", vmid):
        raise ValueError(f"VM {vmid} did not stop. EFI disk not added.")
    remote("qm", "set", vmid, "--efidisk0", spec, timeout=120)
    remote("qm", "start", vmid, timeout=120)
    wait_for_agent(vmid)
    efidisk = guest_config(manifest["node"], "qemu", vmid).get("efidisk0")
    if not efidisk:
        raise ValueError(f"VM {vmid} has no efidisk0 after apply.")
    print(f"VM {vmid} is running with efidisk0: {efidisk}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Apply boot order changes")
    parser.add_argument("--efidisk", action="store_true",
                        help="With --apply, also add EFI disks (shuts down and starts each VM)")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    try:
        startup, efidisks = plan(manifest)
        if not args.apply:
            return
        if startup:
            apply_startup(manifest, startup)
        if args.efidisk:
            for vmid, spec in efidisks:
                apply_efidisk(manifest, vmid, spec)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"{exc}\nRead the live guest state before retrying.\n")


if __name__ == "__main__":
    main()
