# Proxmox VE upgrade runbook, 2026-11-22

This runbook upgrades Proxmox VE from 9.1.7 to 9.2.32 with the 7.0.14-30 kernel.
The tool is `scripts/proxmox-upgrade.py`. The reviewed targets are in `hosts/proxmox/upgrade-20261122.json`.

## Known risks

The owner chose to go ahead with these risks open:

- On 2026-11-22, Proxmox did not read backups over NFS in a short check. No guest restore was tested.
- On 2026-11-22, the RAID controller reported a failed capacitor. The write cache stays on without battery protection.
  A power cut during the upgrade can corrupt data.
- Nobody tested the physical console or iLO access.

## Steps

Run every step from a clean checkout of merged `main`.

1. Run `./scripts/proxmox-upgrade.py`. It only reads. It must print `All pre-upgrade checks passed.`
2. Run `./scripts/proxmox-upgrade.py --download`. It refreshes the package lists and downloads the packages.
   It installs nothing. If the check then blocks on a new version, update the manifest in a new PR.
3. In the approved window, run `./scripts/proxmox-upgrade.py --apply`.
   It saves `/etc` to the NAS backup share, then starts the upgrade in a systemd unit.
   Guests keep running. Follow the unit with `journalctl -fu pve-upgrade-20261122`.
4. Check that `pveversion` shows 9.2.32 and that `dpkg --audit` is empty.
5. Reboot only after a separate approval. Guests with `onboot: 1` start again.
6. After the reboot, check `uname -r`, guest status, storage status, DNS and the Docker hosts.

## Rollback

If the new kernel does not boot, choose `6.17.13-2-pve` in the GRUB menu on the console.
This does not undo the package upgrade. APT has no automatic downgrade.
The `/etc` copy is at `/mnt/pve/pve-backups/host-config/proxmox-etc-pve-upgrade-20261122.tar.gz`.
