#!/usr/bin/env python3
"""Check, download and start the reviewed Proxmox VE package upgrade. Never reboots."""

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / "hosts/proxmox/upgrade-20261122.json"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "proxmox"]
APT_OPTS = ["-o", "Dpkg::Options::=--force-confdef", "-o", "Dpkg::Options::=--force-confold"]
CONFIG_ARCHIVE = "/mnt/pve/pve-backups/host-config/proxmox-etc-{unit}.tar.gz"


def remote(*args, timeout=120):
    command = shlex.join(["sudo", "-n", "env", "LC_ALL=C", *args])
    result = subprocess.run(
        [*SSH, command], check=True, stdout=subprocess.PIPE, text=True, timeout=timeout,
    )
    return result.stdout


def simulation_problems(output, packages):
    problems = []
    removals = [line for line in output.splitlines() if line.startswith("Remv ")]
    if removals:
        problems.append(f"APT would remove {len(removals)} package(s): {removals[:5]}")
    for name, version in packages.items():
        match = re.search(rf"^Inst {re.escape(name)} (?:\[[^]]*\] )?\(([^ )]+)", output, re.MULTILINE)
        if not match:
            problems.append(f"{name} is not in the upgrade set")
        elif match.group(1) != version:
            problems.append(f"{name} target is {match.group(1)}, reviewed {version}")
    return problems


def host_problems(manifest):
    problems = []
    if remote("dpkg", "--audit").strip():
        problems.append("dpkg --audit reports broken packages")
    if remote("apt-mark", "showhold").strip():
        problems.append("Some packages are on hold")
    free = int(remote("df", "--output=avail", "-B1", "/").split()[-1]) / 2**30
    if free < manifest["min_root_free_gib"]:
        problems.append(f"Root has {free:.1f} GiB free, need {manifest['min_root_free_gib']}")
    tasks = json.loads(remote("pvesh", "get", "/nodes/proxmox/tasks", "--source", "active",
                              "--output-format", "json"))
    if tasks:
        problems.append(f"{len(tasks)} Proxmox task(s) are running")
    grub = remote("cat", "/boot/grub/grub.cfg")
    if f"with Linux {manifest['current_kernel']}'" not in grub:
        problems.append(f"GRUB has no entry for fallback kernel {manifest['current_kernel']}")
    return problems


def check(manifest):
    print(remote("pveversion").strip())
    simulation = remote("apt-get", "-s", "dist-upgrade")
    summary = [line for line in simulation.splitlines() if "upgraded," in line]
    print(summary[0] if summary else "No APT summary line")
    problems = simulation_problems(simulation, manifest["packages"]) + host_problems(manifest)
    for problem in problems:
        print(f"BLOCKED: {problem}")
    if not problems:
        print("All pre-upgrade checks passed.")
    return not problems


def download():
    remote("apt-get", "update", timeout=300)
    remote("apt-get", "-d", "-y", "dist-upgrade", timeout=1800)
    print("Packages downloaded to the APT cache. Nothing was installed.")


def start_upgrade(manifest):
    unit = manifest["unit"]
    archive = CONFIG_ARCHIVE.format(unit=unit)
    remote("mkdir", "-p", str(Path(archive).parent))
    remote("tar", "-czf", archive, "/etc", timeout=300)
    print(f"Saved /etc to {archive} on the NAS backup share.")
    remote(
        "/usr/bin/systemd-run", f"--unit={unit}", "--property=Type=exec",
        "--setenv=DEBIAN_FRONTEND=noninteractive", "--", "/usr/bin/apt-get", "-y",
        *APT_OPTS, "dist-upgrade",
    )
    print(f"Upgrade started in {unit}.service. Follow: journalctl -fu {unit}. No reboot is done.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--download", action="store_true", help="Refresh lists and download only")
    action.add_argument("--apply", action="store_true", help="Back up /etc and start the upgrade")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    try:
        if args.download:
            download()
        if not check(manifest):
            sys.exit(1)
        if args.apply:
            start_upgrade(manifest)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"{exc}\nRead the live host state before retrying.\n")


if __name__ == "__main__":
    main()
