#!/usr/bin/env python3
"""Set the scratch directory for the scheduled Proxmox backup job."""

import argparse
import json
import shlex
import subprocess
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / "hosts/proxmox/backup-job.json"
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "proxmox"]
TEST_UNIT = "pve-pihole-backup-check"


def remote(*args):
    command = shlex.join(["sudo", "-n", *args])
    return subprocess.run([*SSH, command], check=True, stdout=subprocess.PIPE, text=True, timeout=45)


def api(*args):
    result = remote("pvesh", *args, "--output-format", "json")
    return json.loads(result.stdout) if result.stdout.strip() else None


def read_job(endpoint):
    job = api("get", endpoint)
    job.pop("next-run", None)
    return job


def sync(manifest, apply=False, test_backup=False):
    expected = manifest["job"]
    desired = manifest["tmpdir"]
    guest = manifest["test_guest"]
    if desired not in (None, "/var/tmp") or guest not in expected["vmid"].split(","):
        raise ValueError("Unexpected scratch path or guest in the manifest")

    endpoint = f"/cluster/backup/{expected['id']}"
    current = read_job(endpoint)
    scratch = current.pop("tmpdir", None)
    if current != expected or scratch not in (None, "/var/tmp"):
        raise ValueError("Backup job differs from the reviewed job. No changes made.")

    after = expected if desired is None else {**expected, "tmpdir": desired}
    print(f"{expected['id']} tmpdir: {scratch!r} -> {desired!r}; storage stays {expected['storage']}")
    if test_backup:
        if scratch != desired or desired is None:
            raise ValueError("Apply the scratch setting before starting the test backup")
        start_test_backup(expected, desired, guest)
    elif scratch != desired and apply:
        change = ["--delete", "tmpdir"] if desired is None else ["--tmpdir", desired]
        api("set", endpoint, *change)
        if read_job(endpoint) != after:
            raise ValueError("Job readback differs from the reviewed result. Inspect before retrying.")
        print("Verified the saved job. No other job settings changed.")


def start_test_backup(job, scratch, guest):
    remote(
        "/usr/bin/systemd-run", f"--unit={TEST_UNIT}", "--collect", "--property=Type=exec",
        "--", "/usr/bin/vzdump", guest, "--storage", job["storage"], "--mode", "snapshot",
        "--compress", job["compress"], "--tmpdir", scratch, "--remove", "0",
        "--notification-mode", job["notification-mode"],
    )
    print(f"Backup started. Check {TEST_UNIT}.service and the Proxmox task before retrying.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true", help="Save the scratch setting")
    action.add_argument("--test-backup", action="store_true", help="Start one CT backup without pruning")
    args = parser.parse_args()
    try:
        sync(json.loads(MANIFEST.read_text()), args.apply, args.test_backup)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, f"{exc}\nIf a request failed, read the live job and task list before retrying.\n")


if __name__ == "__main__":
    main()
