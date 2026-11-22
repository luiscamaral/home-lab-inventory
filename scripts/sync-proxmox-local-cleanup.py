#!/usr/bin/env python3
"""Remove reviewed Proxmox artifacts from the local root filesystem."""

import argparse
import base64
import json
import os
import socket
import stat
import subprocess
from pathlib import Path

ROOT = Path('/var/lib/vz')
GUESTS = Path('/etc/pve/nodes')
DIRECTORIES = {Path('dump'), Path('template/iso')}


def local_volume(path, root_source):
    result = subprocess.check_output(
        ['findmnt', '-n', '-o', 'SOURCE,TARGET,FSTYPE', '-T', str(path)], text=True
    ).strip()
    if result.split() != [root_source, '/', 'ext4']:
        raise ValueError(f'Not on the expected local root filesystem: {path}')


def check_references(node, retired_vmid, names):
    if not (GUESTS / node / 'qemu-server').is_dir():
        raise ValueError('The local Proxmox guest configuration directory is missing')
    for pattern in ('*/qemu-server/*.conf', '*/lxc/*.conf'):
        for config in GUESTS.glob(pattern):
            data = config.read_bytes()
            if config.stem == str(retired_vmid) or any(name in data for name in names):
                raise ValueError(f'Artifact or retired guest still referenced: {config}')


def inspect_file(path, size, root_source):
    local_volume(path.parent, root_source)
    protected = path.with_name(path.name + '.protected')
    if protected.exists() or protected.is_symlink():
        raise ValueError(f'Protected backup: {path}')
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size != size:
        raise ValueError(f'File type, link count, or size changed: {path}')
    if info.st_dev != ROOT.stat().st_dev:
        raise ValueError(f'Unexpected local device: {path}')
    open_check = subprocess.run(['fuser', '-s', str(path)], capture_output=True)
    if open_check.returncode != 1 or open_check.stderr:
        raise ValueError(f'File in use, or use check failed: {path}')
    return info


def target_path(rel):
    child = Path(rel)
    path = ROOT / child
    if child.parent not in DIRECTORIES or path.resolve() != path:
        raise ValueError(f'Path is outside the allowed directories or uses a symlink: {rel}')
    return path


def get_plan(manifest):
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != manifest['node']:
        raise ValueError('Run as root on the specified Proxmox node')
    files = manifest['files']
    paths = {target_path(rel): size for rel, size in files.items()}
    check_references(manifest['node'], manifest['retired_vmid'], [os.fsencode(p.name) for p in paths])
    return {path: inspect_file(path, size, manifest['root_source']) for path, size in paths.items()}


def execute(manifest, apply):
    plan = get_plan(manifest)
    for path, info in plan.items():
        action = 'absent' if info is None else 'remove' if apply else 'would remove'
        print(f'{action}: {path} ({info.st_blocks * 512 if info else 0} allocated bytes)', flush=True)
    if not apply:
        return
    if get_plan(manifest) != plan:
        raise ValueError('The plan changed before execution')
    for path, info in plan.items():
        if info is not None:
            current = path.lstat()
            original = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
            if (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) != original:
                raise ValueError(f'File changed before removal: {path}')
            path.unlink()
    if any(info is not None for info in get_plan(manifest).values()):
        raise ValueError('An approved file remains after cleanup')
    print('Verified all reviewed paths are absent', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest-base64', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        manifest = json.loads(base64.b64decode(args.manifest_base64, validate=True))
        execute(manifest, args.apply)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Stopped: {exc}\n')


if __name__ == '__main__':
    main()
