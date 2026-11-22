# Proxmox storage monitoring and custom UI panel: plan

This plan adds health data for the HP Smart Array P420i to Prometheus, Grafana, alerts and the Proxmox UI.
Every part lives in the repo, and a sync tool applies it. A Proxmox update can remove the UI change.
In that case, the host puts it back by itself, and the sync tool can also put it back.

## Facts this plan uses

Checked on 2026-11-22. The evidence is in `docs/operations/evidence/2026-11-22-pve-upgrade-apply/`.

- Proxmox sees two RAID 5 logical volumes, `sda` and `sdb`. Its Disks view shows health `UNKNOWN`.
- `smartctl --scan-open` finds no drives, so the PVE-mods storage health part shows nothing.
- `smartctl -d cciss,N` reads SMART data from each physical drive. `ssacli` reads drives, volumes, cache and capacitor.
- The capacitor reports `Failed`, and `No-Battery Write Cache` is `Enabled`. Nothing alerts on this today.
- No `node_exporter` runs on Proxmox. The Prometheus `node` job in `terraform/portainer/locals.tf` has no Proxmox target.
- `pve-firewall` is disabled on the host.
- `pveproxy` serves `/pve2/js/` without a login. The API needs a login. Drive data must not go to a static file.
- The node Notes field is empty. Notes come through the API, so a login is needed to read them.

## Design

One collector feeds all outputs. It only reads the controller and the drives.

- **Collector**: `homelab-smart-array-collect` runs every 5 minutes from a systemd timer.
  It calls `ssacli` and `smartctl -d cciss,N`. It writes metrics for the `node_exporter` textfile collector.
  It also writes a status block into the node Notes between fixed markers. Other Notes text stays as it is.
- **Metrics**: controller, cache and capacitor state, and the no-battery write cache setting.
  Also volume state, drive state, drive temperature, SSD wear, and the time of the last good run.
- **Proxmox UI**: one script tag in `index.html.tpl` loads `homelab-storage.js` from `/pve2/js/`.
  The script holds code only, no data. It adds a "Storage (Smart Array)" panel to the node Summary.
  The panel reads the Notes block through the API with the login session of the user.
  If an update removes the script tag, the Notes panel still shows the same status.
- **Reapply after updates**: an APT hook `/etc/apt/apt.conf.d/99homelab-pve-ui` runs
  `homelab-pve-ui reapply` after every `dpkg` run. The script adds the tag only if it is missing.
  It reloads `pveproxy` only after a change. It does not touch the files that PVE-mods patches.
- **Sync tool**: `scripts/sync-proxmox-storage-monitoring.py` with read-only plan, `--apply` and `--remove`.
  It also has `--check-ui`, which reports whether the tag and the script are in place.

## Repo layout

| Path | Contents |
| --- | --- |
| `hosts/proxmox/storage-monitoring/manifest.json` | APT packages, file targets, modes, timer interval |
| `hosts/proxmox/storage-monitoring/homelab-smart-array-collect` | Collector script |
| `hosts/proxmox/storage-monitoring/*.service`, `*.timer` | systemd units |
| `hosts/proxmox/storage-monitoring/prometheus-node-exporter.default` | `node_exporter` arguments |
| `hosts/proxmox/pve-ui/homelab-storage.js` | UI panel code |
| `hosts/proxmox/pve-ui/index-html-tpl.patch` | The one-line script tag patch |
| `hosts/proxmox/pve-ui/homelab-pve-ui`, `99homelab-pve-ui` | Reapply script and APT hook |
| `terraform/portainer/locals.tf` | New `192.168.7.11:9100` target and alert rules |
| `terraform/portainer/stacks/grafana-dashboards/proxmox-smart-array.json` | Dashboard |
| `tests/test_smart_array_collect.py` | Parser tests with saved `ssacli` and `smartctl` output |

## Steps

Each step is one PR. Steps 2 and 3 need step 1, and step 4 needs step 1.

| Step | PR | Host change | Downtime |
| --- | --- | --- | --- |
| 1 | `node_exporter`, collector, timer, Notes block, Prometheus target | Installs 1 package, adds files and a timer | None |
| 2 | Grafana dashboard | None on Proxmox | None |
| 3 | Alert rules: capacitor failed, write cache without capacitor, drive or volume not OK, collector stale, SSD wear | None on Proxmox | None |
| 4 | Custom UI panel, reapply script, APT hook | Patches `index.html.tpl`, reloads `pveproxy` | A few seconds of UI reconnect |

## Tests before merge

The owner asked to test each change in place, in the `pve-shell` pane, before the merge.
Rule #1 forbids live changes before a merge unless the owner approves that specific action.
These are the actions that need that approval:

1. Step 1: run the collector once by hand and print its output. This reads only. Then install
   `prometheus-node-exporter`, copy the files, start the timer, and write the Notes block.
2. Step 4: copy the UI files, apply the patch and reload `pveproxy`. Then run `apt reinstall pve-manager`
   to prove that the hook puts back the tag and PVE-mods puts back its patches.

Steps 2 and 3 change nothing on Proxmox, so they follow the normal order.

After each merge, apply again from clean `main`. The plan must then show no changes.
Each PR body says which actions ran before the merge.

## Checks for each step

- Step 1: the collector output parses in `promtool check metrics`. Prometheus shows the target as up.
  The Notes block lists 8 drives, 2 volumes, and the capacitor as failed.
- Step 2: the dashboard loads in Grafana and shows the 8 drives.
- Step 3: `promtool check rules` passes. The capacitor alert fires, because the fault exists now.
- Step 4: the Summary panel shows the same data as the Notes block. A user without a login gets no drive data.
  After `apt reinstall pve-manager`, the panel and the PVE-mods sensors come back without manual steps.

## Rollback

- Steps 1 and 4: `sync-proxmox-storage-monitoring.py --remove` stops the timer and removes the files, the hook and the tag.
  It also removes the Notes block. Removing `prometheus-node-exporter` is a separate choice.
- Steps 2 and 3: revert the PR and apply Terraform.
