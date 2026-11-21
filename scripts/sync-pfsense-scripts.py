#!/usr/bin/env python3
"""
Sync repo-managed shell scripts to pfSense.

Source of truth: pfsense/scripts/*.sh in the repo.
Destination: /root/<filename> by default, or the path declared in a
`# pfsync-dest: <abs/path>` header line inside the script.
Owner/mode: root:wheel, 0755.

Used to keep pfSense's ACME post-deploy hooks (under /root), the
node_exporter textfile collectors (under /usr/local/bin), and any other
root-side helpers under version control. Companion script
sync-pfsense-cron-jobs.py reconciles the cron entries that invoke them.

Workflow:
    scripts/sync-pfsense-scripts.py            # dry run (shows diff)
    scripts/sync-pfsense-scripts.py --apply    # push every changed script

Why a custom script: pfSense doesn't have a Terraform provider for
arbitrary shell content on the filesystem. The pfSense REST API can
manage ACME action_list items and cron jobs but not the actual files
they exec — that needs scp/ssh.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "pfsense" / "scripts"
DEFAULT_DEST_DIR = "/root"

# Header form: `# pfsync-dest: /usr/local/bin/foo.sh`
DEST_HEADER_RE = re.compile(r"^#\s*pfsync-dest:\s*(\S+)\s*$", re.MULTILINE)


def parse_dest(content: str, fallback_name: str) -> str:
    """Return the destination path declared in the script header, or
    fall back to /root/<filename>."""
    m = DEST_HEADER_RE.search(content)
    if m:
        return m.group(1)
    return f"{DEFAULT_DEST_DIR}/{fallback_name}"


def fetch_remote(dest: str) -> str | None:
    result = subprocess.run(
        ["ssh", "pfsense", f"cat {dest} 2>/dev/null"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0 or not result.stdout:
        return None
    return result.stdout


def push(name: str, dest: str, content: str) -> None:
    # Stage to /tmp via stdin (no sudo needed; we're root on pfSense)
    write = subprocess.run(
        ["ssh", "pfsense", f"cat > /tmp/{name}"],
        input=content, capture_output=True, text=True, check=False,
    )
    if write.returncode != 0:
        sys.exit(f"error: stage to /tmp/{name} failed: {write.stderr}")

    install = subprocess.run(
        ["ssh", "pfsense",
         f"install -o root -g wheel -m 0755 /tmp/{name} {dest} && rm /tmp/{name}"],
        capture_output=True, text=True, check=False,
    )
    if install.returncode != 0:
        sys.exit(f"error: install on pfSense failed: {install.stderr}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--apply", action="store_true",
        help="Push changed scripts (default: dry-run)")
    args = parser.parse_args()

    if not SCRIPTS_DIR.is_dir():
        sys.exit(f"error: {SCRIPTS_DIR} not found")

    scripts = sorted(
        p for p in SCRIPTS_DIR.iterdir() if p.is_file() and p.suffix == ".sh")
    if not scripts:
        print("no .sh scripts to sync")
        return 0

    changed = 0
    for path in scripts:
        local = path.read_text()
        dest = parse_dest(local, path.name)
        remote = fetch_remote(dest)
        rel = path.relative_to(REPO_ROOT)
        if remote == local:
            print(f"  {rel} -> {dest}: up to date")
            continue
        changed += 1
        verb = "CREATE" if remote is None else "UPDATE"
        print(f"  {rel} -> {dest}: would {verb}")
        if args.apply:
            push(path.name, dest, local)
            print(f"    PUSHED ({len(local.splitlines())} lines)")

    if changed == 0:
        print("All scripts up to date.")
    elif not args.apply:
        print(f"\n{changed} script(s) need updating — re-run with --apply to push.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
