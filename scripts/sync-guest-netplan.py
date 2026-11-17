#!/usr/bin/env python3
"""
Sync repo-managed netplan files to a Proxmox VM guest.

Source of truth: hosts/<guest>/etc/netplan/<file>
Destination:     /etc/netplan/<file> inside the guest (root:root, 0600)

The script reaches the guest through the Proxmox guest agent
(`ssh proxmox` -> `sudo -A qm guest exec`). The agent runs as root and keeps
working when the guest's IP changes. SSH to the guest does not, and it needs a
sudo password.

Safety design for a network change:
  * The dry run shows a diff of the repo file against the live file. It changes nothing.
  * --apply is idempotent. It does nothing if the live file already matches.
  * The repo file must match the expected address and gateway in GUESTS below.
  * The guest backs up the live file, writes the new file, and runs `netplan generate`.
    If generate fails, the backup is restored and nothing is applied.
  * A timed revert guard is armed BEFORE the change. It restores the backup and
    re-applies it if nobody cancels it.
  * `netplan apply` runs detached, so no connection has to survive the change.
  * The script checks the new address and default route through the agent.
    Only then does it cancel the revert guard.
  * If the check fails, the guard restores the old config on its own.

Workflow:
    scripts/sync-guest-netplan.py                         # dry run, all guests
    scripts/sync-guest-netplan.py --guest omada-controller --apply
"""

from __future__ import annotations

import argparse
import base64
import difflib
import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

PVE_SUDO = "SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A"
GUARD_SECS = 180   # the revert guard fires after this long unless cancelled
APPLY_DELAY = 3    # seconds before the detached netplan apply runs
VERIFY_SECS = 90   # how long to wait for the new address
GUARD_UNIT = "netplan-revert-guard"

GUESTS: dict[str, dict] = {
    "omada-controller": {
        "vmid": 100,
        "iface": "ens18",
        "files": ["01-netcfg.yaml"],
        "address": "192.168.32.40/27",
        "gateway": "192.168.32.33",
    },
}


def agent_exec(vmid: int, script: str, timeout: int = 40) -> tuple[int, str]:
    """Run a shell script in the guest through the Proxmox agent. Returns (exitcode, output)."""
    inner = f"{PVE_SUDO} qm guest exec {vmid} --timeout {timeout} -- /bin/sh -c {shlex.quote(script)}"
    r = subprocess.run(["ssh", "proxmox", inner], capture_output=True, text=True, timeout=timeout + 30)
    start = r.stdout.find("{")
    if start < 0:
        raise RuntimeError(f"no JSON from qm guest exec (exit {r.returncode}): {(r.stderr or r.stdout)[:300]}")
    data = json.loads(r.stdout[start:])
    return int(data.get("exitcode", 1)), (data.get("out-data", "") + data.get("err-data", ""))


def read_live(guest: dict, name: str) -> str:
    code, out = agent_exec(guest["vmid"], f"cat /etc/netplan/{name}")
    if code != 0:
        raise RuntimeError(f"cannot read /etc/netplan/{name}: {out.strip()}")
    return out


def check_repo_file(guest: dict, text: str) -> None:
    """Refuse a file that would move the guest to the wrong place."""
    cfg = yaml.safe_load(text)
    eth = cfg["network"]["ethernets"][guest["iface"]]
    if eth.get("dhcp4"):
        sys.exit("error: repo file leaves dhcp4 on, but this guest must be static")
    if guest["address"] not in (eth.get("addresses") or []):
        sys.exit(f"error: repo file does not carry {guest['address']} on {guest['iface']}")
    if not any(r.get("via") == guest["gateway"] for r in (eth.get("routes") or [])):
        sys.exit(f"error: repo file has no route via {guest['gateway']}")
    if not (eth.get("nameservers") or {}).get("addresses"):
        sys.exit("error: repo file has no DNS server")


def apply_script(name: str, text: str, stamp: str) -> str:
    b64 = base64.b64encode(text.encode()).decode()
    f = f"/etc/netplan/{name}"
    bak = f"{f}.bak-{stamp}"
    return f"""set -e
systemctl stop {GUARD_UNIT}.timer 2>/dev/null || true
systemctl reset-failed {GUARD_UNIT}.service 2>/dev/null || true
cp -p {f} {bak}
printf %s {b64} | base64 -d > {f}.new
chmod 600 {f}.new
mv {f}.new {f}
if ! netplan generate; then cp -p {bak} {f}; echo GENERATE_FAILED; exit 1; fi
systemd-run --quiet --unit={GUARD_UNIT} --on-active={GUARD_SECS} /bin/sh -c 'cp -p {bak} {f} && netplan apply'
systemd-run --quiet --unit=netplan-apply-now --on-active={APPLY_DELAY} /usr/sbin/netplan apply
echo SCHEDULED backup={bak}
"""


def state_ok(guest: dict, out: str) -> bool:
    return guest["address"] in out and f"default via {guest['gateway']}" in out


def read_state(guest: dict) -> str:
    code, out = agent_exec(
        guest["vmid"],
        f"ip -4 -o addr show dev {guest['iface']}; ip -4 route show default; "
        f"resolvectl status {guest['iface']} 2>/dev/null | grep -E 'DNS Servers|DNS Domain'")
    return out


def sync_one(name: str, guest: dict, apply: bool) -> int:
    rc = 0
    for fname in guest["files"]:
        repo = REPO_ROOT / "hosts" / name / "etc" / "netplan" / fname
        if not repo.is_file():
            sys.exit(f"error: {repo} not found")
        want = repo.read_text()
        check_repo_file(guest, want)
        live = read_live(guest, fname)
        if live == want:
            print(f"  = {name}:{fname} in sync")
            continue
        print(f"  ~ {name}:{fname} differs")
        sys.stdout.writelines(difflib.unified_diff(
            live.splitlines(True), want.splitlines(True), "live", "repo"))
        if not apply:
            rc = max(rc, 0)
            continue
        stamp = time.strftime("%Y%m%d-%H%M%S")
        code, out = agent_exec(guest["vmid"], apply_script(fname, want, stamp))
        print(f"    guest: {out.strip()}")
        if code != 0:
            sys.exit(f"error: guest step failed (exit {code}). Nothing was applied.")
        print(f"    netplan apply runs in {APPLY_DELAY}s. Revert guard fires in {GUARD_SECS}s unless cancelled.")
        deadline = time.time() + VERIFY_SECS
        verified = False
        state = ""
        time.sleep(APPLY_DELAY + 4)
        while time.time() < deadline:
            try:
                state = read_state(guest)
            except Exception as e:  # agent hiccup while the NIC reconfigures
                state = f"(agent: {e})"
            if state_ok(guest, state):
                verified = True
                break
            time.sleep(5)
        if not verified:
            print(f"    NOT verified. Last state:\n{state}")
            print(f"    The revert guard will restore the old config within {GUARD_SECS}s.")
            return 1
        code, out = agent_exec(guest["vmid"], f"systemctl stop {GUARD_UNIT}.timer; "
                               f"systemctl is-active {GUARD_UNIT}.timer || echo guard-cancelled")
        print(f"    verified:\n{state.rstrip()}")
        print(f"    revert guard: {out.strip().splitlines()[-1]}")
    return rc


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--guest", choices=sorted(GUESTS), help="One guest (default: all)")
    parser.add_argument("--apply", action="store_true", help="Push, apply and verify (default: dry run)")
    args = parser.parse_args()
    names = [args.guest] if args.guest else sorted(GUESTS)
    if args.apply and not args.guest:
        sys.exit("error: --apply needs --guest")
    rc = 0
    for n in names:
        rc = max(rc, sync_one(n, GUESTS[n], args.apply))
    return rc


if __name__ == "__main__":
    sys.exit(main())
