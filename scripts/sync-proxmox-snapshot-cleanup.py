#!/usr/bin/env python3
"""Remove one approved Proxmox VM snapshot. Default to a dry run."""

import argparse
import base64
import json
import os
import socket
import subprocess


def output(*args):
    return subprocess.check_output(args, text=True, timeout=15)


def get_json(path):
    return json.loads(output('pvesh', 'get', path, '--output-format', 'json'))


def get_config(vmid, *args):
    text = output('qm', 'config', vmid, *args)
    return dict(line.split(': ', 1) for line in text.splitlines() if ': ' in line)


def inspect(manifest):
    node = manifest['node']
    vmid = str(manifest['vmid'])
    base = f'/nodes/{node}/qemu/{vmid}'
    config = get_config(vmid, '--current', '1')
    if config.get('name') != manifest['name'] or config.get('lock'):
        raise ValueError('Unexpected VM name or active lock')
    if config.get('scsi0', '').split(',')[0] != manifest['disk']:
        raise ValueError('Active disk has changed')
    snapshots = {row['name']: row for row in get_json(f'{base}/snapshot')}
    keep = set(manifest['keep']) | {'current'}
    target = manifest['snapshot']
    if keep != snapshots.keys() - {target} or target in keep:
        raise ValueError('Snapshot list differs from the approved plan')
    status = get_json(f'{base}/status/current')
    if status.get('status') != 'running' or not status.get('pid'):
        raise ValueError('Expected the VM to be running')
    volumes = set(output('lvs', '--noheadings', '-o', 'lv_name', manifest['vg']).split())
    target_volumes = {manifest['snapshot_lv'], manifest['state_lv']}
    if target not in snapshots:
        if volumes & target_volumes:
            raise ValueError('Snapshot entry is absent but a recorded volume still exists')
        return False, status['pid']
    if not target_volumes <= volumes or snapshots[target]['snaptime'] != manifest['snapshot_epoch']:
        raise ValueError('Snapshot identity or backing volumes changed')
    saved = get_config(vmid, '--snapshot', target)
    expected_state = manifest['disk'].split(':', 1)[0] + ':' + manifest['state_lv']
    if saved.get('vmstate') != expected_state or saved.get('scsi0', '').split(',')[0] != manifest['disk']:
        raise ValueError('Snapshot disk or RAM-state reference differs from the plan')
    return True, status['pid']


def execute(manifest, apply):
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != manifest['node']:
        raise ValueError('Run as root on the specified Proxmox node')
    pending, pid = inspect(manifest)
    target = f"VM {manifest['vmid']} / {manifest['snapshot']}"
    if not pending:
        print(f'Already absent: {target}', flush=True)
        return
    if not apply:
        print(f'Would delete only {target}; keep {len(manifest["keep"])} other snapshots; VM PID {pid}', flush=True)
        return
    subprocess.run(['qm', 'delsnapshot', str(manifest['vmid']), manifest['snapshot']], check=True)
    remaining, after_pid = inspect(manifest)
    if remaining or after_pid != pid:
        raise ValueError('Snapshot removal or VM process verification failed')
    print(f'Verified {target} and both backing volumes absent; VM PID unchanged: {pid}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest-base64', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        manifest = json.loads(base64.b64decode(args.manifest_base64, validate=True))
        execute(manifest, args.apply)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        parser.exit(1, f'Stopped: {exc}\n')


if __name__ == '__main__':
    main()
