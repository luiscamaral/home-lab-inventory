# Recon Findings (2026-04-24)

Five parallel recon agents reported. This file captures the **plan
corrections** that flow into the Terraform stacks and the inventory.

## Critical corrections (must apply before authoring)

| # | What the plan said | Recon found | Source of truth |
|---|---|---|---|
| 1 | NAS Portainer endpoint id = `6` (Edge agent) | id = **`14`** (regular Agent, type=2). id=6 was deleted; ghost stacks (paperlessngx, netbootxyz, speed-test, twingate-connector) still point there but functionally healthy. | Use `portainer_environment.nas.id` (not a hardcoded int) — same as `portainer_stack.pihole_3` does |
| 2 | `prometheus-2` lands at `192.168.4.236` | `.236` is occupied by `pihole-3-pihole-1`. Free in `192.168.4.232/29`: `.237`, `.238`, `.239` | `prometheus-2` IP = **`192.168.4.237`** |
| 3 | NAS host self-scrape via `192.168.4.236` | NAS host answers on macvlan aux address **`192.168.4.233`**. `.236` is the pihole container. | `prometheus-2` self-scrape target = `192.168.4.233:9100` (assuming node_exporter on DSM) |
| 4 | Existing Prometheus is a single-purpose stack | Stack `prometheus` bundles **prometheus + node-exporter + snmp-exporter + alertmanager + cadvisor** in one compose. | Phase 0 decommission destroys all 5; Phase 1 must redeploy `node-exporter`, `cadvisor`, `snmp-exporter` (as separate stacks per `05-exporters.md`) before retiring the old one — or accept a brief gap |
| 5 | MinIO m2 has plenty of capacity | m2 (ds-2, local disk) has only **76 GiB free**; site replication is full-mesh, so every Thanos block lands on m2 too | Either: (a) exclude `thanos` bucket from site-replication; (b) grow ds-2 disk; (c) accept m2 fills first and trips alarms before m1. **Decision needed before bucket creation.** |
| 6 | Existing Prometheus is some unknown version | Image is `prom/prometheus:latest` (Watchtower-managed, drifts every Watchtower run). Currently resolves to **`v3.11.1`** — one patch behind our pin (`v3.11.2`). | No surprise; clean install on `v3.11.2` is fine |
| 7 | Thanos sidecar talks to MinIO directly on :9000 | MinIO has **no direct port 9000** exposed on macvlan; everything goes via nginx-rproxy on :443 (`https://s3.d.lcamaral.com`) | ds-1 sidecar: `http://192.168.59.17:9000` (LAN, fast, internal). NAS sidecar: `https://s3.d.lcamaral.com:443` (TLS via nginx-rproxy). Different `objstore.yml` per replica. |

## Existing Prometheus details

- **Container:** `prometheus-prometheus-1` on ds-1
- **Image:** `prom/prometheus:latest` (`v3.11.1` at audit time)
- **Compose project (managed by Portainer):** `/data/compose/70`, host bind: `/nfs/dockermaster/docker/prometheus/`
- **Bundled services:** prometheus, node-exporter, snmp-exporter, alertmanager, cadvisor
- **Retention:** 15 d (default; no `--storage.tsdb.retention.*` flag)
- **Rules:** none (declared `rule_files: ['alert.rules']` but file does not exist)
- **TSDB:** 3.1 GB, 25 blocks, 14 d of history
- **Alertmanager config:** placeholder Slack route, all `slack_configs` commented — **no live alerting today**
- **Consumers:** only `prometheus.d.lcamaral.com` nginx vhost (internal). No Grafana datasource. No remote_write / federation. No external dashboards.
- **Repointing:** the nginx vhost upstream `192.168.48.45:9090` will need to move to whatever IP the new `prometheus-1` lands on.

## MinIO details

- **Site-replication mesh:** m1 (`192.168.59.17`, NFS-backed, 1 TiB) ↔ m2 (`192.168.59.37`, local-disk, 106 GiB total / 76 GiB free).
- **Existing buckets:** `homelab`, `obsidian`, `testbucket2` (3 buckets, 564 KiB total — basically empty).
- **Auth model:** Keycloak OIDC for humans (claim → policy). No local users.
- **Recommended Thanos auth:** MinIO **service account** (svcacct) scoped to a custom `thanos` policy on `arn:aws:s3:::thanos/*`. Define policy in `terraform/minio/policies.tf`. Save creds to Vault `secret/homelab/thanos`.

## Keycloak details

- **Realm:** `homelab` (display name "Homelab"), version **`26.3.5`**.
- **Existing pattern to mirror:** `minio` client uses confidential OIDC + `oidc-usermodel-client-role-mapper` → claim `policy`. Grafana follows the same shape.
- **No groups, no custom realm roles.** Roles for Grafana will be **client-scoped** (e.g., `grafanaAdmin`, `editor`, `viewer`) and assigned to users post-create.
- **Discovery URL:** `https://auth.cf.lcamaral.com/realms/homelab/.well-known/openid-configuration` — works.
- **Client name to add:** `grafana` (no collision; confirmed).

## Terraform inventory details

- **`portainer_stack.prometheus`** at `terraform/portainer/stacks.tf:274-281`, compose `terraform/portainer/stacks/prometheus.yml`. Bound to `var.ds1_endpoint_id`.
- **All 11 Vault paths planned** are unused — no collisions.
- **Both Vault policies planned** (`prometheus-scrape`, `thanos-storage`) — no collisions.
- **NAS endpoint variable:** `portainer_environment.nas.id` (dynamic). The `id=6` figure in the plan was stale.
- **Pattern to follow for NAS stacks:** `pihole-3.yml.tftpl` — `templatefile()`, `configs:` with inline content, `home-net` macvlan, NAS-native paths under `/volume2/docker/...`, `com.centurylinklabs.watchtower.enable: "false"`.

## Action items derived from recon (added to phase plans)

1. Update `02-inventory-and-scope.md` and `01-architecture.md` with the corrected NAS IP (`192.168.4.237`) and self-scrape IP (`192.168.4.233`).
2. Update `04-deployment-plan.md` Phase 1 to also redeploy `node-exporter`, `cadvisor`, `snmp-exporter` as separate stacks (decoupled from Prometheus).
3. Update `04-deployment-plan.md` Phase 0 to call out the bundled services that disappear when the legacy stack is destroyed.
4. Update `03-thanos-design.md` storage section with the m2-capacity caveat and the site-replication decision.
5. Update `05-exporters.md` and any reference using `portainer_environment.nas.id` (was hardcoded id=6 implicitly).
6. Update Phase 1 Terraform to use sidecar S3 endpoint `http://192.168.59.17:9000` (ds-1 internal); Phase 2 NAS sidecar uses `https://s3.d.lcamaral.com:443` — two different `objstore.yml` files.
7. **Add ad-hoc decision required:** exclude `thanos` from MinIO site-replication, OR grow ds-2 disk, OR accept m2 fills first. Default proposal: **exclude thanos from site-replication for now** — m1 holds the bucket; if m1 dies the blocks are lost (Prometheus local TSDB is the failover for last 7 d). Sized argument: m1 has 1 TiB, can absorb full 200 GB Thanos budget without strain; m2's 76 GiB shouldn't be the bottleneck for monitoring.

## Soft warnings (don't block deploy)

- **NAS Portainer agent**: snapshotter is producing empty `DockerSnapshotRaw` (last successful: 2026-04-22 ~22:00 UTC). Stack deploys still work; UI just doesn't show container state for NAS endpoint.
- **4 ghost stack records** on dead endpoint id=6: paperlessngx, netbootxyz, speed-test, twingate-connector. Cleanup task — not a blocker.
- **NAS RAM:** 4.9 GB available, 1.7 GB swap in use. Adding `prometheus-2` (~500 MB) + sidecar (~150 MB) is fine but worth watching.
- **Keycloak is single-node:** `keycloak` + `keycloak-db-0` only on dockermaster. No HA. If Keycloak dies, Grafana login fails (existing sessions continue until token expiry). Documented as accepted risk.
