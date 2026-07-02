#!/usr/bin/env python3
"""
Sync the repo-managed Proxmox host DNS config to the Proxmox node.

Source of truth: hosts/proxmox/dns.yml
Apply mechanism: the Proxmox node DNS API via
                 `pvesh set /nodes/<node>/dns --search <s> --dns1 .. --dns2 .. --dns3 ..`
                 Proxmox regenerates /etc/resolv.conf from this, so the
                 change is reboot-safe and idempotent (no hand-edited file).

Why a custom script (not terraform): there is no terraform provider for
the Proxmox node DNS API, and resolv.conf is a host-level file, not a
container config. This mirrors the existing scripts/sync-*.py convention
(declarative source in the repo + a small reconciler that applies it).

Access: `ssh proxmox` logs in as an unprivileged user, and `pvesh` needs
root, so every pvesh call is wrapped with the project's askpass sudo:
    SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A pvesh ...

Workflow:
    scripts/sync-proxmox-dns.py           # dry-run: show current vs desired
    scripts/sync-proxmox-dns.py --apply   # push via pvesh, then verify

Rollback: re-run against a dns.yml with the previous values, or
    ssh proxmox 'SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A \\
        pvesh set /nodes/proxmox/dns --dns1 <old> --dns2 <old> --search <old>'
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DNS_YML = REPO_ROOT / "hosts" / "proxmox" / "dns.yml"

# ssh alias for the Proxmox host (see CLAUDE.md "Remote Servers").
SSH_TARGET = "proxmox"
# pvesh needs root; ssh logs in unprivileged. Project askpass sudo pattern.
SUDO = "SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A"


def load_desired() -> dict:
    """Parse hosts/proxmox/dns.yml. Falls back to a tiny hand parser if
    PyYAML is not installed, since this file is deliberately simple."""
    text = DNS_YML.read_text()
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
    except ModuleNotFoundError:
        data = _mini_parse(text)

    node = data["node"]
    search = data["search"]
    nameservers = [str(n) for n in data["nameservers"]]
    if not 1 <= len(nameservers) <= 3:
        sys.exit(f"error: need 1-3 nameservers (glibc MAXNS=3), got {len(nameservers)}")
    return {"node": node, "search": search, "nameservers": nameservers}


def _mini_parse(text: str) -> dict:
    """Minimal parser for this specific flat yaml (node/search/nameservers list)."""
    node = search = None
    nameservers: list[str] = []
    in_list = False
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if line.startswith("nameservers:"):
            in_list = True
            continue
        if in_list and line.lstrip().startswith("- "):
            nameservers.append(line.lstrip()[2:].strip())
            continue
        in_list = False
        if line.startswith("node:"):
            node = line.split(":", 1)[1].strip()
        elif line.startswith("search:"):
            search = line.split(":", 1)[1].strip()
    return {"node": node, "search": search, "nameservers": nameservers}


def ssh(cmd: str) -> tuple[int, str]:
    r = subprocess.run(
        ["ssh", SSH_TARGET, cmd], capture_output=True, text=True, timeout=30
    )
    return r.returncode, (r.stdout + r.stderr).strip()


def get_current(node: str) -> dict:
    rc, out = ssh(f"{SUDO} pvesh get /nodes/{node}/dns --output-format json")
    if rc != 0:
        sys.exit(f"error: pvesh get failed: {out}")
    # pvesh may prepend the askpass warning; grab the JSON object.
    start = out.find("{")
    if start < 0:
        sys.exit(f"error: no JSON in pvesh output: {out}")
    return json.loads(out[start:])


def desired_pvesh_args(desired: dict) -> list[str]:
    args = [f"--search {desired['search']}"]
    for i, ns in enumerate(desired["nameservers"], start=1):
        args.append(f"--dns{i} {ns}")
    return args


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="Apply via pvesh (default is dry-run).")
    args = ap.parse_args()

    desired = load_desired()
    node = desired["node"]
    current = get_current(node)

    cur_ns = [current[k] for k in ("dns1", "dns2", "dns3") if current.get(k)]
    print(f"Node:    {node}")
    print(f"Search:  current={current.get('search')!r}  desired={desired['search']!r}")
    print(f"DNS:     current={cur_ns}")
    print(f"         desired={desired['nameservers']}")

    same = cur_ns == desired["nameservers"] and current.get("search") == desired["search"]
    if same:
        print("\nIn sync — nothing to do.")
        return 0

    set_args = " ".join(desired_pvesh_args(desired))
    set_cmd = f"{SUDO} pvesh set /nodes/{node}/dns {set_args}"
    if not args.apply:
        print(f"\n(dry-run) would run:\n  ssh {SSH_TARGET} '{set_cmd}'")
        print("Re-run with --apply to push.")
        return 0

    print(f"\nApplying:\n  {set_cmd}")
    rc, out = ssh(set_cmd)
    if rc != 0:
        sys.exit(f"error: pvesh set failed: {out}")

    # Verify: Proxmox should have rewritten resolv.conf.
    after = get_current(node)
    after_ns = [after[k] for k in ("dns1", "dns2", "dns3") if after.get(k)]
    rc, resolv = ssh("cat /etc/resolv.conf")
    ok = after_ns == desired["nameservers"] and after.get("search") == desired["search"]
    print(f"\nVerify:  node dns={after_ns} search={after.get('search')!r}")
    print("--- /etc/resolv.conf ---")
    print(resolv)
    if not ok:
        sys.exit("error: post-apply state does not match desired")
    print("\nApplied and verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
