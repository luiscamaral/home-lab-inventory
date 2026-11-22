# Homelab glass panel: metric scan, gaps and design

This document proposes one Grafana dashboard that answers "is anything wrong?" for the whole homelab.
Each tile links to the detailed dashboard behind it.
The scan behind it ran on 2026-11-22 between 15:38 and 15:42 UTC.
The evidence is in `docs/operations/evidence/2026-11-22-observability-scan/`.

## What the scan found

| Area | Finding | Evidence |
| --- | --- | --- |
| Scrape targets | 92 targets in 29 jobs. 4 targets are down: `minio-2` (HTTP 403), `watchtower-dm` (HTML reply), `zot-meta-backup` (refused). | 01 |
| Data volume | About 48,000 head series per Prometheus. `node` and `cadvisor` give most samples. | 02 |
| Alerts | 47 rules in Prometheus, plus long-window rules in Thanos Ruler. 15 distinct alerts fire, 4 of them critical. | 02, 04 |
| Grafana | Version 13.0.1. One data source, Thanos. 17 dashboards in 2 folders. 8 have no fixed `uid`. No home dashboard is set. | 03 |
| Thanos | Every Thanos component reports its last upload as 0. No upload happened after the restart at about 08:00 UTC. `ThanosBucketUploadsStalled` is critical. | 04 |
| Backups | The `pve-backups` NFS share is 97.7% full. All 5 guests without a backup are stopped guests or templates. | 04 |
| Alert copies | Each alert reaches Alertmanager twice, once per Prometheus replica, because the `replica` label differs. | 02 |

## Gaps

Each gap names the fix and where the fix lives in the repo. P1 gaps hide problems that already happened.

| Priority | Gap | Why it matters | Proposed fix |
| --- | --- | --- | --- |
| P1 | No backup freshness metric | The Pi-hole backup failed from at least 2026-11-16 and nothing alerted. | Textfile metric on Proxmox: last good `vzdump` time per guest. Alert when older than 4 days. |
| P1 | No NFS client latency | Grafana and FreeSWITCH stalled on NFS on 2026-11-22. No metric shows NFS delay. | Turn on the `mountstats` collector on the Docker hosts and Proxmox. |
| P1 | NAS disk and RAID health unknown | The NAS `node_exporter` runs in a container and sees only container mounts. | Synology SNMP through the existing `snmp-exporter`, with the Synology module. |
| P2 | Broken scrapes: `minio-2`, `watchtower-dm`, `zot-meta-backup` | Each one fires a warning all the time and hides new failures. | Fix the token, path or service in their stacks. |
| P2 | Duplicate alerts | Every alert email arrives twice. | Drop the `replica` label in `alert_relabel_configs`. |
| P2 | No Omada or UniFi metrics | Access point and client health come only from the WiFi probes. | `omada-exporter` and `unpoller`, already listed as C.1 and C.2 in the coverage gap document. |
| P2 | No container health state | cAdvisor shows running containers but not Docker `unhealthy`. | A small textfile collector on each Docker host for `docker ps` health. |
| P3 | No server hardware data | No fan, power supply or UPS data. | iLO SNMP, or `ilo_exporter` (C.5). UPS only if a UPS exists. |
| P3 | No logs in Grafana | Problems still need SSH and `journalctl`. | Out of scope for this panel. Loki is a separate project. |
| P3 | 8 dashboards without a fixed `uid` | A link to them can break after a reload. | Add a fixed `uid` to each JSON file. The glass panel needs this for its links. |

## Glass panel design

- Name "Homelab: Glass Panel", uid `homelab-glass`, folder Homelab.
- It becomes the Grafana home dashboard through `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`.
- Layout for a 1920 × 1080 screen with no scrolling for rows A to C. Refresh every minute. Time range 24 hours.
- Data source `thanos` only. Every tile has a link to the dashboard that explains it.
- Colors: green means fine, orange means look soon, red means act now. A tile without data shows "no data" in grey, never green.

### Row A: verdict strip

| Tile | Query (verified) | Green / orange / red | Link |
| --- | --- | --- | --- |
| Critical alerts | `count(ALERTS{alertstate="firing",severity="critical"}) or vector(0)` | 0 / - / 1 or more | Alert table, row D |
| Warning alerts | `count(ALERTS{alertstate="firing",severity="warning"}) or vector(0)` | 0 / 1 or more / - | Alert table, row D |
| Targets down | `count(up == 0) or vector(0)` | 0 / 1 / 3 | Thanos & Prometheus |
| Internet | `max by (gateway) (pfsense_gateway_loss_ratio)` and delay in ms | loss 0 / over 0.02 / 1 | pfSense WAN Quality |
| DNS | `avg(probe_success{job="blackbox-dns"})` | 1 / under 1 / 0 | Internet & Network |
| Public endpoints | `sum(probe_success{job="blackbox-rproxy"})` of `count(...)` | all / 1 down / 3 down | Blackbox |
| Next TLS expiry | `min((probe_ssl_earliest_cert_expiry - time()) / 86400)` days | over 21 / under 21 / under 7 | TLS Cert Expiry |
| Backups | `pve-backups` used ratio and running guests without backup | under 85% / 85% / 95% | Proxmox via Prometheus |

### Row B: layer health

Four groups of small status tiles, one group for each layer.

- **Network**: WAN gateways, `switch24a` ports up and input errors per second.
  Also stale WiFi probes and Cloudflare tunnel connections.
- **Compute**: guests running, and guests set to start at boot but stopped (templates excluded).
  Also the Smart Array capacitor, bad drives, and host reboots in the last 24 hours.
- **Platform**: containers per Docker host and containers started in the last 15 minutes.
  Also Prometheus head series and the Thanos last upload age.
- **Services**: Vault unsealed, Keycloak 2 of 2, Postgres 3 of 3, and MinIO health and offline drives.
  Also Pi-hole 3 of 3 and Home Assistant up.

The Thanos tile shows "never since restart" when the upload time is 0. Today the raw value reads as 57 years.
The query is `(time() - max(thanos_objstore_bucket_last_successful_upload_time > 0))`, with a mapping for no data.

### Row C: capacity

Bar gauges, sorted from fullest down:

- root file system used per host
- memory used per host
- Proxmox storage used per pool. One of the pools is `pve-backups`.
- NAS volume used, from `mountpoint="/home"` on the NAS, the only mount that shows the real volume

### Row D: what is firing

A table built from `max by (alertname, severity, instance) (ALERTS{alertstate="firing"})`.
The table sorts rows by severity, then name. Each row links to the matching layer dashboard by `category` label.

### Row E: 24-hour trends

Three time series: WAN delay and loss, public endpoint success ratio, and CPU busy per host.
They show when a problem started, not only that it exists.

## Build and apply

1. One PR adds `terraform/portainer/stacks/grafana-dashboards/homelab-glass.json`.
   The same PR adds a fixed `uid` to the 8 dashboards without one.
   It also sets the home dashboard path in `terraform/portainer/stacks/grafana.yml.tftpl`.
2. A test in the PR runs every tile query against Thanos and fails on an empty result.
3. After merge, apply Terraform for `portainer_stack.grafana` and run `scripts/portainer-redeploy.py grafana`.
4. Check in Firefox that the home page opens the glass panel and that every link works.

The gap fixes follow as separate PRs, in priority order. Each new metric then becomes a tile.
