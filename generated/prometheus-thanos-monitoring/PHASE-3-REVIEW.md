# Phase 3 — Review and Recommended Sequence

**Date:** 2026-04-25 (post-Gate-2 review)
**Status:** Phase 1/2 deployed, all 9 monitoring containers healthy. Phase 3 is the long-tail exporter rollout.

## Reality check vs. the plan

The original plan in `04-deployment-plan.md` proposed week-by-week tier-ordered rollout (T0 → T1 → T2 → T3+T4 over 4 weekends). After getting the data plane up, a few realities reshape the order:

1. **The native `/metrics` endpoints are 10× the value-per-effort of any other category.** Vault, Keycloak, MinIO, cloudflared, Watchtower, Docker Registry — all already expose Prometheus metrics. Each is 5–15 lines of scrape config plus a token (where needed) and gives you cluster health, request rates, error rates, the works. **Tackle these first regardless of tier.**
2. **`node_exporter` and `cadvisor` on the *other* hosts** (ds-2, dockermaster, NAS) close the most "up=0" red dots in the current Prometheus targets list. ds-1 already has them; the other three need a new copy of the existing stack files with a different `endpoint_id`.
3. **`snmp-exporter` is stopped pending a v0.30-format `snmp.yml` regen.** Either (a) bring up the `snmp_exporter generator` against the pfSense MIB to produce a fresh module, or (b) pin the exporter to v0.20.x for legacy compat. Either way, separate work.
4. **Home Assistant is the single biggest cardinality contributor.** Worth doing early because the cardinality discoveries shape `metric_relabel_configs` choices for everything else.
5. **Phase 3 exit criteria** (from the plan) is "`up{job=~"..."}` green for the set just added" — but we don't have Grafana yet. Use Thanos Query API directly for verification until Phase 4.

## Recommended sequence (revised)

### 3a — Native /metrics endpoints (~30 min, almost no risk)

Single PR. Edit `terraform/portainer/locals.tf` (`prometheus_scrape_config_a` AND `_b` — keep both replicas in sync) to add:

| Job | Endpoint | Auth |
|---|---|---|
| `vault` | `vault.d.lcamaral.com:8200/v1/sys/metrics?format=prometheus` | Bearer token (need new dedicated metrics token in `secret/homelab/vault-metrics/token`) |
| `keycloak` | `keycloak:8080/metrics` (or 9000 for management interface) | None on internal net |
| `minio` | `192.168.59.17:9000/minio/v2/metrics/cluster` | Bearer JWT generated via MinIO admin token (or use existing `thanos` svcacct creds — but consider a dedicated `metrics` svcacct) |
| `minio-2` | `192.168.59.37:9000/minio/v2/metrics/cluster` | Same |
| `cloudflared-1/2/3` | `<cloudflared-ip>:2000/metrics` (need to find IPs / expose port) | None |
| `docker-registry` | `registry:5000/metrics` | None on internal net |
| `watchtower` | `<watchtower-ip>:8080/v1/metrics` | Bearer from `secret/homelab/watchtower` |

Vault paths to populate:
- `secret/homelab/vault-metrics/token` — make this token via `vault token create -policy=prometheus-scrape` (policy already exists from Phase 0)

**Decisions you make here:**
- Use the existing `thanos` MinIO svcacct for metrics scraping, or create a separate one? (cleaner = separate)
- Cloudflared metrics port — do we expose it on the macvlan? Already-working containers shouldn't need a stack restart.

### 3b — Host exporters everywhere (~1 evening)

3 new stacks each for node_exporter and cadvisor:

| Stack | Endpoint | Cost |
|---|---|---|
| `node-exporter-ds2` | `var.ds2_endpoint_id` | copy of `node-exporter-ds1.yml`, change `endpoint_id` |
| `node-exporter-dm` | `var.endpoint_id` | same |
| `node-exporter-nas` | `portainer_environment.nas.id` | same; binds DSM `/proc` |
| `cadvisor-ds2` | `var.ds2_endpoint_id` | same as ds1 |
| `cadvisor-dm` | `var.endpoint_id` | same |
| `cadvisor-nas` | `portainer_environment.nas.id` | DSM may need different mount paths — verify |

After this, the 4 `up=0` rows from `node` and `cadvisor` jobs become `up=1`.

### 3c — Proxmox via pve-exporter (~30 min)

One new stack on dockermaster. Requires:
- Create Proxmox API token `prometheus@pam!metrics` with `PVEAuditor` role (Proxmox UI: Datacenter → Permissions → API Tokens)
- Save to Vault `secret/homelab/proxmox/api_token` (path created in Phase 0; placeholder there now)
- Stack `pve-exporter` on dockermaster, scrapes Proxmox at `192.168.7.11:8006`

**Decision:** PVEAuditor is the minimum-privilege role; do you want broader access (e.g., to scrape backup status, replication state) which needs a higher role?

### 3d — Home Assistant (~20 min)

- Create HA user `prometheus-scrape` with read-only role
- Generate long-lived access token under that user
- Save to Vault `secret/homelab/home-assistant/metrics_token` (path created in Phase 0)
- Add scrape job referencing `https://ha.home.lcamaral.com/api/prometheus` with bearer token
- Apply `metric_relabel_configs: drop` for noisy metric classes (`sun`, per-device-diagnostics) — refine after first scrape

**Decision:** What's your cardinality budget for HA? A "drop everything except automation/script/sensor" filter may be aggressive but keeps storage bounded.

### 3e — Pi-hole × 3 (~30 min)

`ghcr.io/eko/pihole-exporter:v1.2.0` × 3 instances, one per pihole. Each needs the pihole's web password (in `secret/homelab/pihole`).

3 new stacks.

### 3f — Twingate, Rundeck, FreeSWITCH, RustDesk, Portainer (~1 evening)

- Twingate exporter (1 stack, monitors both connectors via the API)
- Rundeck `/api/40/metrics/metrics` with token
- FreeSWITCH ESL-based exporter (community, 1 stack)
- RustDesk: blackbox TCP only (no native metrics)
- Portainer: blackbox HTTP only (no native metrics)

### 3g — Network fabric: Unifi, Omada, HPE iLO, switch24a, NAS DSM (~1 weekend)

Each is its own moderate-effort exploration:
- **unpoller** for Unifi — controller creds, watch out for AP-1 being offline (it'll show as `down`)
- **omada-exporter** for Omada controller
- **MauveSoftware/ilo_exporter** for HPE iLO
- **snmp_exporter** for switch24a — same regen-blocker as pfSense; could share an snmp.yml once we have one
- Synology DSM: install `node_exporter` package via DSM Package Center, scrape at `192.168.4.233:9100`

### 3h — Blackbox probes (~1 weekend)

- Deploy `blackbox_exporter` on dockermaster (needs `NET_RAW` cap for ICMP)
- File-SD targets:
  - `http_2xx`: every `*.cf.lcamaral.com` and `*.d.lcamaral.com` endpoint
  - `icmp`: every `<DEV_HOME_SmartDevices>` member
  - `tcp_connect`: RustDesk ports (21114-21119), SSH on every host
  - `ssl_expiry`: same HTTPS list, alert at <14d
  - `dns`: every pihole resolver (cross-check)

### 3i — snmp-exporter regen (deferred from Phase 1)

- Run `snmp_exporter`'s `generator` against the pfSense MIB bundle to produce a fresh `snmp.yml` in v0.30 schema
- Bind-mount or `configs:` inject into the existing `snmp-exporter` stack
- Bump pin from v0.29 back to v0.30.1
- Restart the stack

## Decisions you should make before sub-agents go to work

1. **Cardinality budget for Home Assistant.** Aggressive (drop most) or permissive (keep most)?
2. **MinIO scrape svcacct.** Reuse `thanos` (already created) or new `metrics` (cleaner)?
3. **PVEAuditor or higher Proxmox role.** Default-low or include backup/replication metrics?
4. **Order preference.** I recommend 3a → 3b → 3c → 3d → 3e (one-shot per evening). 3f, 3g, 3h, 3i can interleave with whatever you care about most.

## Effort estimates (orchestrated with sub-agents, similar style to Phase 0/1/2)

- 3a + 3b + 3c + 3d together: 1 long evening (~3h) — the biggest value chunk
- 3e + 3f: 1 evening (~2h)
- 3g: 1 weekend (~6h, varied component complexity)
- 3h: 1 evening (~2h once probe targets are decided)
- 3i: 1 evening (~2h once new snmp.yml is generated)

Total Phase 3: ~3 evenings + 1 weekend if you keep momentum.

## What Phase 3 enables

- Phase 4 (Grafana connection) becomes useful — there's actually data to query
- Phase 5 (Alertmanager rules) gets concrete signals to alert on (e.g., MinIO bucket capacity, Vault sealed status)
- Phase 6 (Compactor + retention) starts producing meaningful storage metrics

## Out-of-scope reminders (stay in `09-open-questions.md` for now)

- Cardinality runaway protection — handled by per-job `metric_relabel_configs`, not a separate framework.
- Push-based jobs — no Pushgateway in this build.
- Multi-tenancy — single tenant; revisit if homelab grows to family/friends.
