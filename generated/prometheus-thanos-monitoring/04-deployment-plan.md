# 04 — Deployment Plan

Six phases, each a merge-able Terraform change + Portainer stack. Each
phase is independently valuable; nothing after phase 3 depends on
"everything" being done.

## Ground rules

- **Terraform-first.** No `docker compose up` on dockermaster by hand.
  Stacks live in `terraform/portainer/stacks/` and are rendered from
  `.yml.tftpl` templates where needed.
- **Vault for every secret.** No secret-looking strings in repo files,
  not even as examples. Use `vault_kv_secret_v2` data sources.
- **One change at a time.** Each phase ends with `terraform apply` and a
  smoke test before moving on.
- **Reverse-proxy only the UIs.** Prometheus/Alertmanager/Thanos stay on
  `docker-servers-net`. Only Grafana gets an nginx vhost and Cloudflare
  tunnel route.
- **Branch per phase.** Short-lived feature branches, merged to `main`
  once the phase is live.

## Phase 0 — Pre-work and decommission existing Prometheus

**Goal:** eliminate ambiguity; capture what's there; remove the
existing Prometheus stack so Phase 1 starts on a clean slate.

- [x] Answer **09-open-questions.md** — done (see `DECISIONS.md`).
- [x] Pin versions — done (see `VERSIONS.md`); re-verify on the day of
      each phase deploy.
- [ ] **Audit existing Prometheus on `ds-1`:**
      - Capture image tag: `docker inspect prometheus | jq '.[0].Config.Image'`
      - Copy `prometheus.yml` and any rule files into
        `generated/prometheus-thanos-monitoring/legacy-prom-snapshot/`
        for reference (NOT a full re-deploy — just the bits worth
        preserving as scrape-job seeds).
      - Note local retention and TSDB size: `docker exec prometheus
        ls -la /prometheus` and `du -sh`.
      - Identify the Portainer stack name + Terraform definition file
        managing it (likely `terraform/portainer/stacks/prometheus.yml`
        or similar — confirm).
- [ ] **Decommission existing Prometheus stack (Q10):**
      - Stop the container (Portainer or `docker stop`).
      - Remove the Terraform stack resource AND the underlying compose
        file in the same commit.
      - `terraform apply` to actually destroy the stack.
      - Delete the Prometheus persistent volume (only after the audit
        snapshot above is in repo).
- [ ] Audit existing MinIO capacity. Confirm `minio-2` replication is
      bucket-level or document that it isn't (adjust plan).
- [ ] Create Vault paths (empty for now) at the list in `07-secrets`.
- [ ] Confirm Keycloak can issue an OIDC client for Grafana.

**Exit criteria:** DECISIONS.md and VERSIONS.md merged; legacy
Prometheus snapshot saved in repo; legacy stack destroyed; Vault paths
exist; ds-1 has no `prometheus*` containers running.

## Phase 1 — Fresh Prometheus + Thanos MVP

**Goal:** clean install of `prometheus-1` + `thanos-sidecar-1` +
`thanos-query` + `thanos-store-gateway`, all with pinned versions from
`VERSIONS.md`. No HA yet.

- [ ] Create MinIO user `thanos`, bucket `thanos`, scoped policy. Save
      creds to `secret/homelab/thanos/s3`.
- [ ] **New** Portainer stack `prometheus-1` on `ds-1`:
      - Image: `quay.io/prometheus/prometheus:v3.11.2`
      - `external_labels: {cluster: homelab, replica: A, region: local}`
      - Local retention: `--storage.tsdb.retention.time=7d`
      - Scrape config seeded from the legacy snapshot (Phase 0) but
        with new job names matching the inventory in
        `02-inventory-and-scope.md`.
- [ ] Same stack: `thanos-sidecar` container (image
      `quay.io/thanos/thanos:v0.41.0`) reading the Prom `tsdb.path`,
      uploading to MinIO via `objstore.yml` rendered from Vault.
- [ ] New Terraform stack `thanos-query` on dockermaster
      (`quay.io/thanos/thanos:v0.41.0`).
- [ ] New Terraform stack `thanos-store-gw` on ds-1 (same image).
- [ ] Smoke test: from dockermaster, `curl thanos-query:10902/stores`
      — sidecar-1 and store-gw both visible.
      `curl 'thanos-query:10902/api/v1/query?query=up'` — returns data.

**Exit criteria:** Thanos Query returns data; one 2h block lands in
MinIO; no `prometheus*` containers running outside this Terraform
stack.

## Phase 2 — HA Prometheus (on NAS, per Q3=B)

**Goal:** kill `prometheus-1`, lose nothing. Survive Proxmox outage.

- [ ] **Firewall prep:** add pfSense rules allowing TCP from NAS
      (`192.168.4.236` / home-net) to every scrape-target port across
      SRVAN, HOMELAB, IOT, ADMIN VLANs. This is the delta over the
      existing ds-1→scrape-target rules.
- [ ] New stack on NAS (via Portainer Edge endpoint `6`, same
      mechanism as `pihole-3`):
      `prometheus-2` (`quay.io/prometheus/prometheus:v3.11.2`) +
      `thanos-sidecar-2` (`quay.io/thanos/thanos:v0.41.0`) +
      `alertmanager-2` (`quay.io/prometheus/alertmanager:v0.32.0`).
- [ ] Scrape config identical to `prometheus-1`; only
      `external_labels.replica` differs (`B` vs `A`).
- [ ] Add `alertmanager-2` to the gossip cluster (`--cluster.peer`
      points at alertmanager-1).
- [ ] Update `thanos-query` discovery to include sidecar-2.
- [ ] Curl test: query via Thanos; result set has 1 series per target
      (dedupe working).
- [ ] **Chaos test 1:** `docker stop prometheus-1`. Query still
      returns data. Restart; no gap.
- [ ] **Chaos test 2 (the one Q3=B is for):** power-off a Proxmox VM
      (e.g., dockermaster) and confirm prometheus-2 keeps ingesting
      targets it can reach (pihole-3, WAN, NAS self).

**Exit criteria:** dual-replica verified; dedupe confirmed; Proxmox
outage no longer halts monitoring.

## Phase 3 — Exporters (the long tail)

**Goal:** every inventory item in `02-inventory-and-scope.md` has a
scrape target in Prometheus.

Ordered by priority tier. Each sub-phase is a separate PR.

1. T0 (week 1):
   - pfSense (snmp_exporter)
   - Proxmox (pve-exporter)
   - All three VM hosts (node_exporter + cadvisor)
   - Home Assistant (already exposes `/api/prometheus`; just add scrape)
   - Vault, MinIO, Keycloak (native endpoints)
2. T1 (week 2):
   - Pi-hole × 3, Rundeck, Registry, FreeSWITCH, RustDesk, Watchtower,
     Cloudflare tunnel × 3, Twingate connectors × 2, Portainer
3. T2 (week 3):
   - Unifi (unpoller), Omada (omada-exporter), HPE iLO, switch24a
     (snmp), Synology NAS
4. T3 + T4 (week 4):
   - Blackbox probes (HTTP, ICMP, DNS, SSL), HA entity dashboards

**Exit criteria per sub-phase:** Grafana "Inventory" dashboard shows
`up{job=~"..."}` green for the set just added.

## Phase 4 — Grafana (connections only; no dashboards this phase)

**Goal:** Grafana is up, SSO works, the Thanos datasource returns query
results. Dashboards are **out of scope** and tracked as a future phase.

- [ ] Portainer stack: Grafana on ds-1
      (`grafana/grafana-oss:13.0.1`). SQLite backend (migrate to
      Postgres later if multi-user history matters).
- [ ] Datasource provisioned via `provisioning/datasources/thanos.yml`:
      - Primary: `Thanos` → `http://thanos-query:10902` (default, `prometheus` type)
      - Secondary (read-only, debug use): `Prometheus-1 (direct)` → `http://prometheus-1:9090`
- [ ] OIDC via Keycloak (`homelab` realm, new client `grafana`).
      Client secret in Vault at `secret/homelab/grafana/oidc`.
- [ ] nginx-rproxy vhost `grafana.cf.lcamaral.com`, published through
      the existing Cloudflare tunnel via the `modules/cf-service`
      Terraform module.
- [ ] **No dashboards are authored or imported in this phase** — the
      default Grafana home screen with no panels is the intended state.
      Users can construct ad-hoc panels via the Explore view if needed.

**Exit criteria:**
- Grafana reachable at `https://grafana.cf.lcamaral.com`.
- Keycloak SSO: a realm user can log in; role mapping works (admin/viewer).
- In Grafana Explore, `up{}` query against `Thanos` datasource returns
  non-empty results from both replicas (deduped).

**Deferred (future phase, separate PRD):** dashboards-as-code, baseline
dashboards set, alerting-side panels. Will be tackled after Phase 6 once
data shape is stable.

## Phase 5 — Alerting (Alertmanager + Ruler)

**Goal:** the fleet actively tells you when it's broken.

- [ ] Alertmanager × 2 (gossip pair, image
      `quay.io/prometheus/alertmanager:v0.32.0`) —
      `alertmanager-1` on ds-1 (deployed earlier in Phase 2 prep),
      `alertmanager-2` on **NAS** (deployed with prometheus-2 in Phase 2).
- [ ] **Thanos Ruler × 1 on ds-2**
      (`quay.io/thanos/thanos:v0.41.0`, single instance, no HA pair per
      decision). Points at thanos-query. Sends to BOTH alertmanagers
      (ds-1 + NAS).
- [ ] Prometheus rule files (short-window, fire from both replicas):
      - `node_exporter` (disk full, load, OOM risk)
      - pfSense (gateway flap, WAN loss)
      - Container (restart loop, high memory)
      - Service up-checks (Vault, Keycloak, MinIO)
      - Thanos self-health (sidecar up, store gw up)
- [ ] Thanos Ruler rule files (long-window, require historical data):
      - TLS cert expiry < 14d
      - MinIO bucket growth > 20% month-over-month
      - Storage projected to fill within 30d (linear regression)
- [ ] Alertmanager routing (**Q5=Email**):
      - Critical → `luiscamaral+homelab@gmail.com` via `postfix-relay`
        on dockermaster. Subject prefix `[CRIT]`.
      - Warn → same mailbox, subject prefix `[WARN]`, separate
        `group_interval` so bursts don't flood.
      - Info → log-only (no notification).
- [ ] Runbook URLs embedded in alert annotations.

**Exit criteria:** a known-fault injection (e.g., stop `freeswitch`)
produces a routed alert in ≤2 minutes from Prometheus-native rules.
A Ruler-sourced rule (e.g., a dev rule with `for: 1m` instead of 30d)
fires within its evaluation window.

## Phase 6 — Compactor + long-term retention

**Goal:** storage footprint stays sane indefinitely.

- [ ] Portainer stack: `thanos-compactor` on **ds-2**
      (`quay.io/thanos/thanos:v0.41.0`, single instance only; enforced
      via `portainer.autodeploy: "false"` + explicit single-replica
      deploy).
- [ ] Retention flags **(Q1=B frugal)**:
      `--retention.resolution-raw=90d`
      `--retention.resolution-5m=365d`
      `--retention.resolution-1h=730d`
- [ ] Verify: after first run, bucket size drops slightly (old blocks
      replaced by compacted 5m blocks).
- [ ] Add MinIO bucket-size metric capture (panel lives in a future
      dashboards phase — for now, just confirm the metric is scraped).

**Exit criteria:** `thanos-compactor` logs show successful
downsampling passes; storage growth curve flattens.

## Rollback plan (per phase)

Each phase is reversible:

- Phase 1: stop thanos-sidecar; Prometheus continues as before.
- Phase 2: stop prometheus-2 + sidecar-2; queries fall back to single
  replica.
- Phase 3: disable individual `scrape_config` entries.
- Phase 4: disable Grafana vhost; internal curl still works.
- Phase 5: silence all routes in Alertmanager.
- Phase 6: stop compactor; bucket growth resumes (but nothing breaks).

## Estimated calendar

| Phase | Effort (solo) | Depends on |
|---|---|---|
| 0 | 1 evening | — |
| 1 | 1 weekend | 0 |
| 2 | 1 evening | 1 |
| 3 | 4 weekends (staggered) | 2 |
| 4 | 1 weekend | 2 (min); 3 for richer dashboards |
| 5 | 1 weekend | 4 |
| 6 | 1 evening | 1 |

Total: ~6–8 weekends to fully production-ready.
