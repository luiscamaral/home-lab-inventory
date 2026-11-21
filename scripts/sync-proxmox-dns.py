#!/usr/bin/env python3
"""
Sync the repo-managed Proxmox host DNS config to the Proxmox node.

Source of truth: hosts/proxmox/dns.yml
Apply mechanism: the Proxmox node DNS API via
                 `pvesh set /nodes/<node>/dns --search <s> --dns1 .. --dns2 .. --dns3 ..`
                 Proxmox regenerates /etc/resolv.conf from this (full-replace:
                 it drops any nameserver not in the passed dns1..dns3), so the
                 change is reboot-safe and idempotent — no hand-edited file.

Why a custom script (not terraform): there is no terraform provider for
the Proxmox node DNS API, and resolv.conf is a host-level file, not a
container config. This mirrors the existing scripts/sync-*.py convention.

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
import shlex
import subprocess
import sys
from pathlib import Path

try:
    import yaml  # preferred; may be absent on a bare system python
except ModuleNotFoundError:
    yaml = None

REPO_ROOT = Path(__file__).resolve().parent.parent
DNS_YML = REPO_ROOT / "hosts" / "proxmox" / "dns.yml"

# ssh alias for the Proxmox host (see CLAUDE.md "Remote Servers").
SSH_TARGET = "proxmox"
# pvesh needs root; ssh logs in unprivileged. Project askpass sudo pattern.
SUDO = "SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A"
SSH_TIMEOUT = 30


def _mini_parse(text: str) -> dict:
    """Fallback parser for this specific flat yaml when PyYAML is absent.
    Strips surrounding quotes and inline comments so it matches
    yaml.safe_load semantics for the simple node/search/nameservers-list
    shape (the divergence that a naive parser would introduce)."""
    def scalar(v: str) -> str:
        v = v.split("#", 1)[0].strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        return v.strip()

    data: dict = {}
    nameservers: list[str] = []
    in_list = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.split("#", 1)[0].strip():
            continue
        if line.startswith("nameservers:"):
            in_list = True
            continue
        if in_list and line.lstrip().startswith("- "):
            nameservers.append(scalar(line.lstrip()[2:]))
            continue
        in_list = False
        if ":" in line:
            k, v = line.split(":", 1)
            data[k.strip()] = scalar(v)
    if nameservers:
        data["nameservers"] = nameservers
    return data


def load_desired() -> dict:
    """Parse + validate hosts/proxmox/dns.yml (fail clearly on bad input)."""
    try:
        text = DNS_YML.read_text()
    except OSError as e:
        sys.exit(f"error: cannot read {DNS_YML}: {e}")
    try:
        data = yaml.safe_load(text) if yaml else _mini_parse(text)
    except Exception as e:  # yaml.YAMLError or a mini-parse issue
        sys.exit(f"error: cannot parse {DNS_YML}: {e}")
    if not isinstance(data, dict):
        sys.exit(f"error: {DNS_YML} is not a mapping")

    missing = [k for k in ("node", "search", "nameservers") if k not in data]
    if missing:
        sys.exit(f"error: {DNS_YML} missing required key(s): {', '.join(missing)}")

    nameservers = [str(n).strip() for n in data["nameservers"]]
    if not 1 <= len(nameservers) <= 3:
        sys.exit(f"error: need 1-3 nameservers (glibc MAXNS=3), got {len(nameservers)}")
    for ns in nameservers + [str(data["search"]).strip()]:
        # These are interpolated into a remote shell command; reject anything
        # that isn't a plain hostname/IP token so shlex.quote isn't papering
        # over a genuinely malformed value.
        if not ns or any(c.isspace() for c in ns):
            sys.exit(f"error: invalid whitespace in dns.yml value: {ns!r}")
    return {
        "node": str(data["node"]).strip(),
        "search": str(data["search"]).strip(),
        "nameservers": nameservers,
    }


def ssh(cmd: str) -> tuple[int, str, str]:
    """Run a remote command; return (rc, stdout, stderr) SEPARATELY so JSON
    parsing never sees stderr noise. Fails clearly if the host is unreachable."""
    try:
        r = subprocess.run(
            ["ssh", SSH_TARGET, cmd], capture_output=True, text=True, timeout=SSH_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        sys.exit(f"error: `ssh {SSH_TARGET}` timed out after {SSH_TIMEOUT}s "
                 f"(Proxmox unreachable? this tool runs during DNS outages — "
                 f"check the ix0/LAN path).")
    except OSError as e:
        sys.exit(f"error: could not run ssh: {e}")
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def get_current(node: str) -> dict:
    rc, out, err = ssh(f"{SUDO} pvesh get /nodes/{node}/dns --output-format json")
    if rc != 0:
        sys.exit(f"error: pvesh get failed (rc={rc}): {err or out}")
    try:
        return json.loads(out)  # stdout only — no stderr concatenation
    except json.JSONDecodeError as e:
        sys.exit(f"error: could not parse pvesh JSON: {e}\noutput: {out!r}")


def desired_pvesh_args(desired: dict) -> str:
    parts = [f"--search {shlex.quote(desired['search'])}"]
    for i, ns in enumerate(desired["nameservers"], start=1):
        parts.append(f"--dns{i} {shlex.quote(ns)}")
    return " ".join(parts)


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

    if cur_ns == desired["nameservers"] and current.get("search") == desired["search"]:
        print("\nIn sync — nothing to do.")
        return 0

    set_cmd = f"{SUDO} pvesh set /nodes/{node}/dns {desired_pvesh_args(desired)}"
    if not args.apply:
        print(f"\n(dry-run) would run:\n  ssh {SSH_TARGET} '{set_cmd}'")
        print("Re-run with --apply to push.")
        return 0

    print(f"\nApplying:\n  {set_cmd}")
    rc, out, err = ssh(set_cmd)
    if rc != 0:
        sys.exit(f"error: pvesh set failed (rc={rc}): {err or out}")

    # Verify BOTH the node DB round-trip AND the regenerated resolv.conf, so a
    # green result actually means the host will resolve via the new servers.
    after = get_current(node)
    after_ns = [after[k] for k in ("dns1", "dns2", "dns3") if after.get(k)]
    rc, resolv, err = ssh("cat /etc/resolv.conf")
    if rc != 0:
        sys.exit(f"error: could not read /etc/resolv.conf to verify: {err or resolv}")
    db_ok = after_ns == desired["nameservers"] and after.get("search") == desired["search"]
    file_ok = all(ns in resolv for ns in desired["nameservers"])
    print(f"\nVerify:  node dns={after_ns} search={after.get('search')!r}")
    print("--- /etc/resolv.conf ---")
    print(resolv)
    if not (db_ok and file_ok):
        sys.exit("error: post-apply state does not match desired "
                 f"(db_ok={db_ok}, resolv.conf_ok={file_ok})")
    print("\nApplied and verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
