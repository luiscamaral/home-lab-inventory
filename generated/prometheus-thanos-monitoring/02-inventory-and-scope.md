# 02 — Inventory and Scope

Goal: enumerate every monitorable thing, classify it by importance, and pre-assign
the exporter + scrape host so phase 3 can execute without re-inventing scope.

## Priority tiers

- **T0 — Critical infra.** If this is down, the homelab is down. Always scrape. **Cadence: 15s**
- **T1 — Important services.** Meaningful user impact if broken; short SLO. **Cadence: 15s**
- **T2 — Network fabric.** Routers, APs, switches, managed controllers. **Cadence: 15s**
- **T3 — Applications + IoT.** End-user apps, smart devices (mostly via HA). **Cadence: 60s**
- **T4 — External & synthetic.** WAN health, public-DNS reachability. **Cadence: 60s**

Per-job override format:
```yaml
scrape_configs:
  - job_name: home-assistant
    scrape_interval: 60s     # T3 — entity-heavy
  - job_name: node
    scrape_interval: 15s     # T0/T1 — default
```

## Scrape-from-host policy

Both Prometheus replicas carry the **same scrape config**. They both
scrape every target across VLANs. This means:

- `prometheus-1` on ds-1 (SRVAN `192.168.48.0/20`) scrapes HOMELAB, IOT,
  ADMIN VLANs over existing cross-VLAN rules.
- `prometheus-2` on NAS (home-net `192.168.4.0/24`) scrapes the same
  targets — but its cross-VLAN rule set is DIFFERENT. New TCP rules
  required from `192.168.4.236` (NAS) to each scrape-target port per
  VLAN. See `07-secrets-and-security.md` for the rule delta.
- Dedupe at Thanos Query (via `replica` external label) makes this
  topology transparent to the user.

## T0 — Critical infrastructure

| Target | IP / Hostname | Exporter | Scrape from | Notes |
|---|---|---|---|---|
| pfSense | `192.168.4.1` | `snmp_exporter` (pfSense module) + `node_exporter_pfsense` package | prom-1 | SNMPv3 creds in Vault. See 05-exporters. |
| Proxmox host | `192.168.7.11` | `pve-exporter` | prom-1 | Proxmox API token in Vault |
| dockermaster (VM 120) | `192.168.48.44` | `node_exporter` + `cadvisor` | prom-1 | Already the control plane; many containers scraped directly |
| dockerserver-1 (VM 123) | `192.168.48.45` | `node_exporter` + `cadvisor` | prom-1 (self-scrape) | |
| dockerserver-2 (VM 124) | `192.168.48.46` | `node_exporter` + `cadvisor` | prom-1 | Self-scrape from prom-2 not applicable (prom-2 is on NAS now) |
| NAS (Synology) | `192.168.4.236` | `node_exporter` (DSM package) + `cadvisor` | prom-2 (self-scrape) | New in this iteration — prom-2 also self-scrapes its host |
| Home Assistant (VM 121) | `192.168.16.2` | Built-in `prometheus:` (already enabled) | prom-1 | Bearer token in Vault |
| nginx-rproxy | `192.168.59.28` | `nginx-prometheus-exporter` sidecar or stub_status | prom-1 | 3 replicas: `rproxy`, `rproxy-2`, `rproxy-3` |
| Keycloak | `192.168.59.x` (containers) | Keycloak native `/metrics` | prom-1 | Both keycloak + keycloak-2 |
| Vault | `vault.d.lcamaral.com` | Vault native `/v1/sys/metrics?format=prometheus` | prom-1 | Token in Vault (meta!) — use a dedicated metrics token with `sys/metrics` read |
| MinIO | `s3.d.lcamaral.com` | MinIO native `/minio/v2/metrics/cluster` | prom-1 | Both `minio` and `minio-2` |
| Keycloak Postgres (`keycloak-db-0/1`) | macvlan | `postgres_exporter` sidecar | prom-1 | Connection info in Vault |

## T1 — Important services

| Target | Exporter | Scrape from | Notes |
|---|---|---|---|
| Pi-hole-1 (LXC, `192.168.100.254`) | `pihole-exporter` | prom-1 | App password in Vault |
| Pi-hole-2 (ds-1, `192.168.59.50`) | `pihole-exporter` | prom-1 (local) | |
| Pi-hole-3 (NAS, `192.168.4.236`) | `pihole-exporter` | prom-1 | Memory note: 10× slower than peers — worth dashboarding |
| Calibre-web | HTTP blackbox (login page) | prom-1 | No native metrics |
| Rundeck | Rundeck `/metrics` (API v40+) | prom-1 | Token in Vault |
| GitHub runner | Docker logs → custom exporter OR `cadvisor` only | prom-1 | Runner itself has no metrics endpoint |
| Docker registry | registry `/metrics` (built-in) | prom-1 | |
| FreeSWITCH | `freeswitch_exporter` (community) OR ESL-based | prom-2 | ESL creds in Vault (`secret/homelab/freeswitch`) |
| RustDesk hbbs/hbbr | Log-based exporter OR blackbox TCP | prom-2 | No native metrics |
| Watchtower | `/v1/metrics` (HTTP API) | prom-1 + prom-2 (one per host) | Bearer token in Vault |
| Cloudflare tunnel | cloudflared `/metrics` | prom-1 | 3 replicas |
| Twingate connectors A/B | Official exporter | prom-1 / prom-2 | |
| Portainer | No native; blackbox HTTP | prom-1 | |

## T2 — Network fabric

| Target | Exporter | Scrape from | Notes |
|---|---|---|---|
| Unifi Controller | `unpoller` (scrapes controller API) | prom-1 | Creds in Vault (`secret/homelab/unifi` — to be created) |
| UnifiAP-1/2/Pro | Via unpoller | prom-1 | *UnifiAP-1 currently offline — separate fix* |
| Omada Controller | `omada-exporter` (community) | prom-1 | API token in Vault |
| Omada switches/APs | Via Omada exporter | prom-1 | |
| HPE iLO | `hpilo-exporter` or Redfish exporter | prom-1 | Creds in Vault |
| `switch24a` | `snmp_exporter` (generic switch module) | prom-1 | SNMPv3 |
| Synology NAS | `node_exporter` via Synology package + Synology SNMP | prom-1 | Both sources for cross-check |
| pfSense **again** (HAProxy) | HAProxy `/metrics` (pfSense bundles this) | prom-1 | Surface HAProxy frontends/backends |

## T3 — Applications + IoT (mostly via Home Assistant)

| Source | How | Notes |
|---|---|---|
| HA entities (lights, sensors, switches, cameras, presence) | HA's `prometheus:` integration at `/api/prometheus` | Already enabled; single scrape pulls all HA-visible state |
| go2rtc streams | HA-side stats, or go2rtc `/api/streams` via blackbox | Frontyard North Cam 1, RTSP 192.168.0.37, etc. |
| Kiosk (192.168.4.101) | HA sensor + blackbox HTTP | |
| Hubitat Gateway | Hubitat `/health` via blackbox, OR Hubitat's Maker API polled | |
| Smart devices on `DEV_HOME_SmartDevices` | `blackbox_exporter` ICMP + TCP probes | Bulk-probe the alias membership (192.168.2.x /28 blocks) |

## T4 — External + synthetic

| Target | Exporter | Notes |
|---|---|---|
| WAN1 (Google Fiber upstream) | `blackbox_exporter` → ping 1.1.1.1 + 8.8.8.8 via WAN1 | Policy-route the probe explicitly |
| WAN2 (DHCP) | Same, policy-routed via WAN2 | |
| Public DNS reachability | `blackbox_exporter` DNS module | Detect ISP DNS hijacks |
| ACME cert expiry for `*.cf.lcamaral.com` + `*.d.lcamaral.com` + `*.home.lcamaral.com` | `blackbox_exporter` SSL probe | Alert at <14 days |
| Public homelab endpoints | `blackbox_exporter` HTTP probe of every `*.cf.lcamaral.com` via nginx | Validates tunnel, cert, reverse proxy |

## Things we explicitly do NOT monitor (with reason)

| Thing | Why not |
|---|---|
| The kiosk Pi itself | It reports to HA; no second path needed |
| Each individual smart plug's "online" state | HA already knows; duplicating creates alert storms |
| Backups of backups | Out of scope, handled by existing backup tooling |
| Laptop / phone health | Personal devices, not infra |
| Omada Kids / Guest VIP traffic details | Privacy — aggregate counts are fine; per-device unnecessary |

## Scale estimate (order of magnitude)

- T0 targets: ~15
- T1 targets: ~18
- T2 targets: ~10 (plus whatever `unpoller` / `omada-exporter` expose)
- T3: 1 big HA scrape (hundreds of entities = hundreds of series)
- T4: ~8 blackbox probes, replicated per interface = ~16 series

**Total series estimate:** ~80k–150k active series across both Prometheus
replicas. Well within a single 4 GB Prometheus. Storage math in
`03-thanos-design.md`.

## Gap callouts

- **Proxmox `amsd` + `cpqiScsi` pegged CPU** (previous session finding) —
  monitoring alone won't fix it but we'll **detect** the pattern once
  `pve-exporter` + `node_exporter` are in place.
- **UnifiAP-1 offline** — dashboard should surface this within 5 minutes of
  completing rollout.
- **HOMELAB gateway monitor thrashing** (fixing this is a separate
  engineering task; monitoring will make it visible).
