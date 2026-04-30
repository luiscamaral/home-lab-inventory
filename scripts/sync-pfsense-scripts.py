#!/usr/bin/env python3
"""
Sync repo-managed shell scripts to pfSense's /root.

Source of truth: pfsense/scripts/*.sh in the repo.
Destination: /root/<filename> on pfSense, owned by root:wheel, 0755.

Used to keep pfSense's ACME post-deploy hooks (and any other root-side
helpers) under version control. The pfSense ACME package then references
these scripts by name in its action_list `shellcommand` items.

Workflow:
    scripts/sync-pfsense-scripts.py            # dry run (shows diff)
    scripts/sync-pfsense-scripts.py --apply    # push every changed script

Why a custom script: pfSense doesn't have a Terraform provider for
arbitrary shell content under /root. The pfSense REST API can manage
ACME action_list items (gap 6) but not the actual filesystem they
exec — that needs scp/ssh.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "pfsense" / "scripts"
DEST_DIR = "/root"


def fetch_remote(name: str) -> str | None:
    result = subprocess.run(
        ["ssh", "pfsense", f"cat {DEST_DIR}/{name} 2>/dev/null"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0 or not result.stdout:
        return None
    return result.stdout


def push(name: str, content: str) -> None:
    # Stage to /tmp via stdin (no sudo needed; we're root on pfSense)
    write = subprocess.run(
        ["ssh", "pfsense", f"cat > /tmp/{name}"],
        input=content, capture_output=True, text=True, check=False,
    )
    if write.returncode != 0:
        sys.exit(f"error: stage to /tmp/{name} failed: {write.stderr}")

    install = subprocess.run(
        ["ssh", "pfsense", f"install -o root -g wheel -m 0755 /tmp/{name} {DEST_DIR}/{name} && rm /tmp/{name}"],
        capture_output=True, text=True, check=False,
    )
    if install.returncode != 0:
        sys.exit(f"error: install on pfSense failed: {install.stderr}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="Push changed scripts (default: dry-run)")
    args = parser.parse_args()

    if not SCRIPTS_DIR.is_dir():
        sys.exit(f"error: {SCRIPTS_DIR} not found")

    scripts = sorted(p for p in SCRIPTS_DIR.iterdir() if p.is_file() and p.suffix == ".sh")
    if not scripts:
        print("no .sh scripts to sync")
        return 0

    changed = 0
    for path in scripts:
        local = path.read_text()
        remote = fetch_remote(path.name)
        rel = path.relative_to(REPO_ROOT)
        if remote == local:
            print(f"  {rel}: up to date")
            continue
        changed += 1
        if remote is None:
            print(f"  {rel}: would CREATE on pfSense:/root/{path.name}")
        else:
            print(f"  {rel}: would UPDATE pfSense:/root/{path.name}")
        if args.apply:
            push(path.name, local)
            print(f"    PUSHED ({len(local.splitlines())} lines)")

    if changed == 0:
        print("All scripts up to date.")
    elif not args.apply:
        print(f"\n{changed} script(s) need updating — re-run with --apply to push.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
