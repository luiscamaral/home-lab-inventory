# Proxmox upgrade and UI add-on: execution plan

This plan has two phases. Phase A upgrades Proxmox VE from 9.1.7 to 9.2.32.
Phase B adds hardware details to the node Summary page with the PVE-mods `node_info` add-on.
Phase B needs PVE 9.2. Its tool refuses to run on an older version.

Run every apply step from a clean, detached checkout of merged `main`.
Use the `pve-shell` Herdr pane (`w5:p6`, root on `proxmox`) to watch the host.

## Accepted risks

On 2026-11-22, the owner chose to go ahead with these risks:

- Proxmox did not read backups over NFS in a short check. No guest restore was tested.
- The RAID controller reported a failed capacitor. The write cache stays on without battery protection.
- Nobody tested the physical console or iLO access.

## To-do list

| Step | Task | Tool or command | Approval | Status |
| --- | --- | --- | --- | --- |
| A0 | Merge the upgrade tool, PR #180 | GitHub | No | Waiting for CI |
| A1 | Run the read-only pre-check | `scripts/proxmox-upgrade.py` | No | Ready |
| A2 | Download the packages only | `scripts/proxmox-upgrade.py --download` | Yes | Ready |
| A3 | Agree on a downtime window | Owner | Yes | Open |
| A4 | Save `/etc` and install the packages | `scripts/proxmox-upgrade.py --apply` | Yes | Ready |
| A5 | Reboot into kernel 7.0.14-30 | `reboot` in the `pve-shell` pane | Yes | Ready |
| A6 | Check the host and guests | Checks below | No | Ready |
| B0 | Merge the add-on tool and config | GitHub | No | In review |
| B1 | Run the read-only add-on plan | `scripts/sync-proxmox-pve-mods.py` | No | Ready after A6 |
| B2 | Install and patch the UI | `scripts/sync-proxmox-pve-mods.py --apply` | Yes | Ready after B1 |
| B3 | Check the node Summary page | Browser and checks below | No | Ready after B2 |

## Phase A: upgrade

1. A1: The pre-check must print `All pre-upgrade checks passed.`
2. A2: If the check blocks on a newer target version, update `hosts/proxmox/upgrade-20261122.json` in a new PR.
3. A4: Follow the unit with `journalctl -fu pve-upgrade-20261122` in the `pve-shell` pane.
   Then check that `pveversion` shows 9.2.32 and that `dpkg --audit` prints nothing.
4. A5: Guests with `onboot: 1` start again after the reboot.
5. A6: Check `uname -r`, `qm list`, `pct list`, `pvesm status`, DNS from Pi-hole, and the Docker hosts.

If kernel 7.0.14-30 does not boot, choose `6.17.13-2-pve` in the GRUB menu on the console.
This does not undo the package upgrade.

## Phase B: UI add-on

The add-on is PVE-mods 2.2.3 from `github.com/Meliox/PVE-mods`.
The tool checks the release file against the SHA-256 value in `hosts/proxmox/pve-mods/manifest.json`.
It also installs `lm-sensors`. The host already loads the `coretemp` driver.

The repo config turns on only `node_info`, with these parts:

- CPU and memory temperatures, and fan speeds, from `lm-sensors`
- System information
- Automatic re-patching after later `pve-manager` upgrades

Storage health stays off, because that part adds a root service.
The disks sit behind the RAID controller. Nobody tested whether the add-on can read their SMART data.
The RAID capacitor state is not part of this add-on. It needs a separate check.

B2 reloads `pveproxy`. Open web UI sessions can lose their connection for a few seconds. Guests keep running.
After B2, reload the node Summary page in the browser.
If `node_info` shows as `2` in `/etc/pve-mods/pve-mods.conf`, the patch did not fit this PVE version.

Rollback: run `scripts/sync-proxmox-pve-mods.py --remove`. The package removal reverts the UI patches.
