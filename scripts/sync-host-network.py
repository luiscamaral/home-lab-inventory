#!/usr/bin/env python3
"""
Sync repo-managed systemd-networkd configs to each docker-host.

Source of truth: dockermaster/host-network/<host>/*.{netdev,network}
Destination:     /etc/systemd/network/<filename>   (root:root, 0644)
Reload trigger:  if any file changed for a host, `systemctl restart
                 systemd-networkd` on that host (NOT cluster-wide).

Why a custom script: there's no terraform provider for arbitrary
files under /etc/systemd/network/. The pfSense pattern (configs:
in Compose) doesn't apply because these are host-level configs,
not container configs.

Hosts and ssh aliases:

    dm    -> dockermaster   (192.168.48.44)
    ds-1  -> 192.168.48.45  (no ssh alias today)
    ds-2  -> 192.168.48.46  (no ssh alias today)

Workflow:

    scripts/sync-host-network.py            # dry-run, shows diff
    scripts/sync-host-network.py --apply    # push + restart per host

Restart cost: ~1-3 s of host<->macvlan disruption per host. Containers
on the macvlan stay reachable from each other (the shim only matters
for host process -> macvlan container traffic). nginx-rproxy on the
restarting host loses its path to macvlan upstreams for those few
seconds; the two other rproxies still serve.

`--apply` processes hosts sequentially (dm -> ds-1 -> ds-2) and
verifies each host before moving to the next. If a host fails
verification, the script aborts before touching the next one.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HOST_NETWORK_DIR = REPO_ROOT / "dockermaster" / "host-network"

# host short-name -> ssh target (alias or IP)
HOSTS: dict[str, str] = {
    "dm":   "dockermaster",
    "ds-1": "192.168.48.45",
    "ds-2": "192.168.48.46",
}

# Files we manage in each per-host subdir
MANAGED_FILES = (
    "10-server-net-shim.netdev",
    "10-server-net-shim.network",
)

DEST_DIR = "/etc/systemd/network"


def ssh_run(host: str, cmd: str, stdin: str | None = None) -> subprocess.CompletedProcess:
    """Run a command on `host` via ssh. SUDO_ASKPASS already configured
    on each docker-host per the project setup (see CLAUDE.md)."""
    return subprocess.run(
        ["ssh", host, cmd],
        input=stdin, capture_output=True, text=True, check=False,
    )


def fetch_remote(host: str, filename: str) -> str | None:
    """Read /etc/systemd/network/<filename> on `host`. Returns None if missing."""
    r = ssh_run(host, f"cat {DEST_DIR}/{filename} 2>/dev/null")
    if r.returncode != 0 or not r.stdout:
        return None
    return r.stdout


def push(host: str, filename: str, content: str) -> None:
    """Stage to /tmp on host, then sudo-install to /etc/systemd/network/."""
    stage = ssh_run(host, f"cat > /tmp/{filename}", stdin=content)
    if stage.returncode != 0:
        sys.exit(f"  ERR: stage to /tmp/{filename} on {host} failed: {stage.stderr}")

    install_cmd = (
        f"SUDO_ASKPASS=$HOME/.config/bin/answer "
        f"sudo -A install -o root -g root -m 0644 "
        f"/tmp/{filename} {DEST_DIR}/{filename} "
        f"&& rm /tmp/{filename}"
    )
    inst = ssh_run(host, install_cmd)
    if inst.returncode != 0:
        sys.exit(f"  ERR: install on {host} failed: {inst.stderr or inst.stdout}")


def restart_networkd(host: str) -> None:
    """Restart systemd-networkd on `host`. Brief host<->macvlan disruption."""
    cmd = "SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A systemctl restart systemd-networkd"
    r = ssh_run(host, cmd)
    if r.returncode != 0:
        sys.exit(f"  ERR: systemd-networkd restart on {host} failed: {r.stderr or r.stdout}")


def verify_shim(host: str, expected_ip: str) -> bool:
    """Check `ip -br addr show server-net-shim` on `host` reports expected_ip."""
    r = ssh_run(host, "ip -br addr show server-net-shim 2>&1")
    if r.returncode != 0:
        print(f"  VERIFY FAIL on {host}: {r.stderr or r.stdout}")
        return False
    if expected_ip not in r.stdout:
        print(f"  VERIFY FAIL on {host}: expected {expected_ip} in '{r.stdout.strip()}'")
        return False
    return True


def expected_ip_for_host(label: str) -> str:
    """Parse the IP out of the repo's <label>/10-server-net-shim.network."""
    p = HOST_NETWORK_DIR / label / "10-server-net-shim.network"
    for line in p.read_text().splitlines():
        s = line.strip()
        if s.startswith("Address="):
            ip = s.split("=", 1)[1].split("/")[0].strip()
            return ip
    sys.exit(f"  ERR: no Address= line in {p}")


def diff_summary(local: str, remote: str | None) -> str:
    """One-line diff summary for dry-run output."""
    if remote is None:
        return "CREATE"
    if local == remote:
        return "ok"
    return "UPDATE"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--apply", action="store_true",
        help="Push changed files and restart systemd-networkd per host")
    parser.add_argument(
        "--only", action="append", choices=list(HOSTS),
        help="Limit to one or more hosts (default: all)")
    args = parser.parse_args()

    if not HOST_NETWORK_DIR.is_dir():
        sys.exit(f"error: {HOST_NETWORK_DIR} not found")

    targets = args.only or list(HOSTS)
    overall_changed = 0

    for label in targets:
        host = HOSTS[label]
        subdir = HOST_NETWORK_DIR / label
        if not subdir.is_dir():
            print(f"  {label}: subdir {subdir} not found, skipping")
            continue

        print(f"\n=== {label} ({host}) ===")
        per_host_changes: list[str] = []
        for filename in MANAGED_FILES:
            local_path = subdir / filename
            if not local_path.exists():
                print(f"  {filename}: missing in repo, skipping")
                continue
            local = local_path.read_text()
            remote = fetch_remote(host, filename)
            verdict = diff_summary(local, remote)
            print(f"  {filename}: {verdict}")
            if verdict != "ok":
                per_host_changes.append(filename)
                if args.apply:
                    push(host, filename, local)
                    print("    pushed")

        if not per_host_changes:
            continue
        overall_changed += len(per_host_changes)

        if not args.apply:
            continue

        # Restart systemd-networkd and verify
        print(f"  restart systemd-networkd on {label}...")
        restart_networkd(host)
        # systemd-networkd is fast but give it a beat for the link to settle
        time.sleep(2)
        expected = expected_ip_for_host(label)
        if verify_shim(host, expected):
            print(f"  verified: server-net-shim has {expected}")
        else:
            sys.exit(f"  aborting before next host: {label} verify failed")

    if overall_changed == 0:
        print("\nAll hosts up to date.")
    elif not args.apply:
        print(f"\n{overall_changed} file(s) need updating — re-run with --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
