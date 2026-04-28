# 01 — Architecture

## Design principles

1. **Reuse before add.** `ds-1` already runs Prometheus, MinIO, and is a
   symmetric peer of `ds-2`. Build on that topology instead of a new server.
2. **HA where cheap, single-instance where required.** Prometheus and
   Alertmanager are trivially HA (run two, dedupe). Thanos Compactor is
   NOT HA — running two against the same bucket corrupts blocks.
3. **Object storage is the long-term store.** Prometheus local disk is an
   ingestion buffer, not a vault. Everything meaningful lives in MinIO.
4. **Scrape local, query global.** Each Prometheus scrapes things reachable
   from its host. Thanos Query unifies them. No cross-VLAN scraping holes.
5. **Secrets via Vault, nothing on disk.** All tokens, S3 keys, and OIDC
   secrets sourced from Vault at stack start-up.
6. **Reverse-proxy only Grafana externally.** Prometheus/Thanos/Alertmanager
   remain internal to `docker-servers-net`.

## Component model

### Write path (scrape + store)

```
┌──────────────────────┐     ┌──────────────────────┐
│ exporters (scattered)│     │ push-style exporters │
│ node, cadvisor,      │     │ (rare; covered by    │
│ pfsense, unifi, …    │     │  blackbox/PushGW if  │
└──────────┬───────────┘     │  needed, TBD)        │
           │ pull (15s T0-T2, 60s T3-T4)              │
           ▼                             │
 ┌──────────────────┐      ┌──────────────────┐
 │ prometheus-1     │      │ prometheus-2     │
 │   on ds-1        │◄────►│   on NAS         │   ← identical scrape config
 │   local 7d TSDB  │      │   local 7d TSDB  │     (proxmox-independent)
 └──────────┬───────┘      └──────────┬───────┘
            │                         │
            │ thanos-sidecar-1        │ thanos-sidecar-2
            │ (upload 2h blocks)      │ (upload 2h blocks, cross-VLAN)
            ▼                         ▼
       ┌─────────────────────────────────┐
       │  MinIO bucket: thanos           │
       │  (replicated minio ↔ minio-2)   │
       └─────────────────────────────────┘
```

### Read path (query)

```
       ┌──────────────────────┐
       │ Grafana (ds-1)       │  ← SSO via Keycloak
       └──────────┬───────────┘
                  │ PromQL
                  ▼
       ┌──────────────────────┐
       │ Thanos Querier       │   on dockermaster
       └──────────┬───────────┘
      ┌───────────┼───────────┐
      ▼           ▼           ▼
   sidecar-1   sidecar-2   Thanos Store Gateway
  (ds-1, last (ds-2, last  (on ds-1, reads MinIO
   2h of raw) 2h of raw)    for everything older)
```

### Alert path

```
 prometheus-1 ──┐
                ├──► alertmanager-1 ◄─gossip─► alertmanager-2
 prometheus-2 ──┘          │
                           ▼
             configured receivers (see 06-dashboards-and-alerting.md)
```

### Downsample + compact

- `thanos-compactor` runs on **dockermaster** (single instance).
- Downsamples raw → 5m → 1h on the schedule defined in `03-thanos-design.md`.
- Deletes blocks older than configured retention tiers.

## Placement rationale

| Component | Host | Why that host |
|---|---|---|
| prometheus-1 + sidecar-1 | ds-1 | Already there; no migration |
| **prometheus-2 + sidecar-2** | **NAS (Synology)** | **Proxmox-independent redundancy per Q3=B.** Survives a Proxmox hypervisor outage |
| thanos-query | dockermaster | Control plane; low load; stable |
| thanos-store-gateway | ds-1 | Near MinIO primary — reduces read latency |
| **thanos-compactor** | **ds-2** | Colocated with `minio-2`; writes compacted blocks over loopback-fast path; single-instance (compactor is NOT HA). ds-2 is also the lightest-loaded of the three hosts |
| **thanos-ruler** | **ds-2** | Single instance (no HA pair) per decision; colocated with compactor for quiet ds-2 "batch plane" |
| alertmanager-1 | ds-1 | Colocated with prom-1 |
| **alertmanager-2** | **NAS** | **Moved with prometheus-2** — keeps the AM cluster geographically split so email alerts can still fire when Proxmox is down |
| grafana | ds-1 | Colocated with existing Prometheus data; room to move later. **This phase deploys Grafana + datasource + SSO only — no dashboards** (see `06-dashboards-and-alerting.md`) |

### ds-2 becomes a small "batch plane"

With compactor + ruler + prometheus-2 + sidecar-2 + alertmanager-2 all on
ds-2, that VM now owns more than just its share of the scrape HA. Losing
ds-2 means:

- Half the scrape HA stops (prom-1 keeps going)
- Compactor halts → blocks accumulate in MinIO but **no corruption**
  (compactor is idempotent; it resumes cleanly on restart)
- Ruler halts → any Thanos-sourced alert rules stop firing
- Prometheus-native alert rules on prom-1 keep firing through alertmanager-1

Net: a ds-2 outage causes **alerting gaps only for Thanos-Ruler rules**, not
for Prometheus-native rules. This is why 06 recommends Ruler for
long-window rules (e.g., storage growth) and keeps short-window, highly
critical rules in Prometheus-native.

## Data-flow cadences (locked per DECISIONS.md)

- **Scrape interval (Q2=B):**
  - `15s` for T0 / T1 / T2 scrape jobs (infra, services, network fabric).
  - `60s` for T3 (IoT, Home Assistant entities) and T4 (blackbox probes).
  - Applied per-`scrape_config` override; global default stays `15s`.
- **TSDB block cut:** 2h (Prometheus default).
- **Sidecar upload:** every 2h block + WAL backlog.
- **Compactor downsample:** raw → 5m after 40h; 5m → 1h after 10d (Thanos
  defaults).
- **Retention tiers (Q1=B, frugal):**
  - Local Prometheus: 7d raw
  - Thanos raw: 90d
  - Thanos 5m-downsampled: 365d (1y)
  - Thanos 1h-downsampled: 730d (2y)
  - Expected MinIO footprint year 1: ~200 GB (see `03-thanos-design.md`
    for the math).

## HA semantics

- Two Prometheus scrape the **same targets with the same config**. They
  will produce near-identical samples (small jitter).
- Both upload to MinIO. Blocks are tagged with `external_labels`
  (`replica: A` / `replica: B`).
- Thanos Querier is configured with `--query.replica-label=replica` so it
  deduplicates at read time.
- Losing `ds-1` costs: local Prometheus-1 data from the last ~2h on that
  replica (until the next block upload), Grafana UI, and the Store
  Gateway read path for historical data. Historical queries route
  through Store Gateway — so until Store Gateway is brought back
  (re-deploy on another host), queries older than Prometheus-2's local
  7d fall back on "retry later". Alerts keep firing from `prometheus-2`
  via `alertmanager-2` on the NAS.
- Losing MinIO (both instances): historical reads break; writes buffer in
  the sidecar and the last-block-in-flight. Recovery = restore MinIO from
  backup or from its replica.

## Failure modes explicitly designed for

| Failure | Impact | Mitigation |
|---|---|---|
| One Prometheus down | None (dedupe) | HA pair |
| Proxmox hypervisor down | `prometheus-1`, `alertmanager-1`, `store-gw`, `grafana`, `compactor`, `ruler` all go. `prometheus-2` + `alertmanager-2` on NAS keep running and scraping everything the NAS can still reach (WAN, pihole-3, NAS-local). Email alerts keep firing. | **Q3=B placement** — NAS is Proxmox-independent |
| NAS down | `prometheus-2` + `alertmanager-2` + `pihole-3` go. `prometheus-1` + `alertmanager-1` carry on. Batch plane (compactor/ruler) unaffected. | — |
| Both Prometheus down | No new data until one returns | Rare: requires simultaneous Proxmox + NAS outage |
| One MinIO down | None (replication) | MinIO bucket replication |
| Both MinIO down | No long-term reads; sidecars buffer writes locally until `local retention` runs out (7 days) | Backup job → NAS |
| Compactor crashes | Blocks accumulate, no downsampling | Auto-restart; monitored; single-instance is OK because the compactor is idempotent |
| ds-2 down | Compactor + Ruler stop. Prometheus scraping continues on ds-1 + NAS. Short-window alerts still fire. Trend/long-window (Ruler-evaluated) rules stop. | Documented in runbook |
| Querier down | Grafana blank; alerts still fire (Prom-native goes direct to AM) | Trivial to restart; optionally HA later |
| Alertmanager split-brain | Alert duplication or silence | Use gossip cluster of 2; document recovery |

## What this architecture does NOT solve (on purpose)

- **Metrics cardinality runaway.** Each new label adds a time series.
  Governance of label budgets is an ops concern, documented in the runbook.
- **Cross-replica alert dedup.** Both Prometheus will fire the same alert;
  Alertmanager cluster dedupes. If the cluster gossip breaks, you get
  duplicate notifications.
- **Push-based short-lived jobs.** If we ever need them, add Pushgateway.
  Not in the initial build.
- **Multi-tenancy.** Everything is a single tenant. Adding tenants later
  means Thanos Receive + tenant-aware Thanos components — large refactor.

## See also

- [diagrams/topology.mmd](./diagrams/topology.mmd) — editable Mermaid source
  for the diagram (render in the Grafana docs or preview in an IDE).
