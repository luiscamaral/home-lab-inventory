#!/usr/bin/env python3
"""Install and configure the pinned PVE-mods node_info add-on on the Proxmox host."""

import argparse
import json
import shlex
import subprocess
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "hosts/proxmox/pve-mods"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "proxmox"]
CONFIGS = {"pve-mods.conf": "/etc/pve-mods/pve-mods.conf",
           "conf.d/node_info.conf": "/etc/pve-mods/conf.d/node_info.conf"}
DEB_PATH = "/var/cache/pve-mods/pve-mods_{version}_all.deb"
APPLY = "/usr/lib/pve-mods/apply-patches.sh"


def remote(*args, stdin=None, timeout=120, check=True):
    command = shlex.join(["sudo", "-n", "env", "LC_ALL=C", *args])
    return subprocess.run([*SSH, command], input=stdin, check=check, stdout=subprocess.PIPE,
                          text=True, timeout=timeout)


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def pve_manager_version():
    output = remote("pveversion").stdout
    return output.split("/")[1]


def installed_version():
    result = remote("dpkg-query", "-W", "-f=${Status} ${Version}", "pve-mods", check=False)
    return result.stdout.split()[-1] if "install ok installed" in result.stdout else None


def config_changes():
    changed = []
    for name, target in CONFIGS.items():
        live = remote("cat", target, check=False)
        if live.returncode or live.stdout != (SOURCE / name).read_text():
            changed.append(target)
    return changed


def plan(manifest):
    pve = pve_manager_version()
    current = installed_version()
    changes = config_changes()
    supported = version_tuple(pve)[:2] >= version_tuple(manifest["min_pve_manager"])
    print(f"pve-manager {pve}; pve-mods installed: {current or 'no'}; target {manifest['version']}")
    print(f"Config files to write: {changes or 'none'}")
    if not supported:
        print(f"BLOCKED: pve-mods {manifest['version']} needs pve-manager {manifest['min_pve_manager']}+.")
    return supported, current, changes


def install_package(manifest):
    deb = DEB_PATH.format(version=manifest["version"])
    remote("mkdir", "-p", str(Path(deb).parent))
    remote("curl", "-fsSL", "-o", deb, manifest["deb_url"], timeout=180)
    remote("sha256sum", "-c", "-", stdin=f"{manifest['deb_sha256']}  {deb}\n")
    remote("apt-get", "install", "-y", *manifest["apt_packages"], deb, timeout=600)


def apply(manifest):
    supported, current, _ = plan(manifest)
    if not supported:
        raise ValueError("Upgrade Proxmox VE first. No changes made.")
    if current != manifest["version"]:
        install_package(manifest)
    for name, target in CONFIGS.items():
        remote("install", "-D", "-m", "0644", "/dev/stdin", target, stdin=(SOURCE / name).read_text())
    remote(APPLY, timeout=300)
    verify()


def verify():
    state = remote("grep", "-E", "^node_info=", CONFIGS["pve-mods.conf"]).stdout.strip()
    if state != "node_info=1":
        raise ValueError(f"pve-mods marked node_info as {state}. 2 means the patch did not apply.")
    if config_changes():
        raise ValueError("Live config differs from the repo after apply.")
    print("node_info is enabled and its patches are applied. Reload the browser page.")


def remove():
    remote("apt-get", "purge", "-y", "pve-mods", timeout=300)
    print("pve-mods purged. Its package scripts revert the UI patches.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true", help="Install, configure and patch")
    action.add_argument("--remove", action="store_true", help="Purge pve-mods (rollback)")
    args = parser.parse_args()
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    try:
        if args.apply:
            apply(manifest)
        elif args.remove:
            remove()
        else:
            plan(manifest)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"{exc}\nRead the live host state before retrying.\n")


if __name__ == "__main__":
    main()
