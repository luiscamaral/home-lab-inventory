# 05 — Exporters

One row per scrape target. When multiple exporters can cover a target,
the choice is explained.

> **Version pins:** all images are pinned in [`VERSIONS.md`](./VERSIONS.md).
> Inline references below are kept consistent with that file. If the two
> ever disagree, **`VERSIONS.md` wins**.

## Host + VM layer

### `node_exporter` (every Linux host)

- **Version pin:** `quay.io/prometheus/node-exporter:v1.11.1` (latest
  stable as of planning date — verify before Phase 1).
- **Targets:** dockermaster, ds-1, ds-2, HA VM, unifi-controller VM,
  omada-controller VM, NAS (if installable).
- **Deployment:** Docker container with `net: host`, `pid: host`,
  `--path.procfs=/host/proc --path.rootfs=/host/root`. Bind-mount
  `/proc`, `/sys`, `/` read-only.
- **Port:** 9100.
- **Collectors enabled:** default + `systemd`, `processes`, `textfile`.
- **Collectors disabled:** `wifi` (noisy, irrelevant here).

### `cadvisor` (every Docker host)

- **Version pin:** `gcr.io/cadvisor/cadvisor:v0.55.1`.
- **Targets:** dockermaster, ds-1, ds-2, NAS.
- **Deployment:** per-host container, privileged, bind-mounts
  `/var/run`, `/sys`, `/var/lib/docker`, `/dev/disk`.
- **Port:** 8080.
- **Metric filter:** disable `disk` and `network` container-level
  collectors if cardinality becomes an issue (revisit at Phase 3).

### `pve-exporter` (Proxmox)

- **Image:** `prompve/prometheus-pve-exporter:v3.8.2`.
- **Auth:** dedicated Proxmox API token `prometheus@pam!metrics` with
  `PVEAuditor` role. Token stored in Vault at
  `secret/homelab/proxmox/api_token`.
- **Target:** runs in a container on dockermaster, scrapes Proxmox at
  `192.168.7.11:8006`.
- **Scrape-time URL:** `http://pve-exporter:9221/pve?target=192.168.7.11`.
- **Metrics:** VM/LXC state, CPU/mem/disk, storage pools, replication,
  HA status.

## Network layer

### pfSense — SNMP + native

Two options, pick one for initial, add the other later:

1. **`snmp_exporter` (generic, requires module config):**
   - Image `quay.io/prometheus/snmp-exporter:v0.29.0`.
   - pfSense community SNMP module or generate via
     `snmp_exporter`'s `generator` against the pfSense MIB bundle.
   - SNMPv3 creds in Vault.
2. **pfSense REST v2 metrics (newer, recommended):**
   - Custom lightweight exporter that queries `/api/v2/status/*`
     endpoints (gateway status, state table, interface counters).
   - Reuses the `pfsense-api-token` we already have in Keychain /
     Vault.

**Recommendation:** start with `snmp_exporter` (off-the-shelf),
switch to REST-based once you validate metric coverage.

### Unifi — `unpoller`

- **Image:** `ghcr.io/unpoller/unpoller:release`.
- **Config:** controller URL `https://192.168.32.41:8443`, creds in
  Vault at `secret/homelab/unifi/controller_api`.
- **Metrics:** per-AP client counts, RSSI distribution, radio airtime,
  switch port counters (if you have a Unifi switch later).
- **Note:** `unpoller` polls the controller every `influx_interval`
  (override to 60s for homelab-scale).

### Omada — `omada-exporter`

- **Image:** `ghcr.io/charlie-haley/omada_exporter:latest` (community;
  verify before pinning).
- **Config:** controller URL + `omadacId` + API creds in Vault.
- **Metrics:** AP status, client counts, site health.

### HPE iLO — `hpilo-exporter`

- **Image:** `ghcr.io/incountry/hpilo-exporter:latest` (or fork).
- **Creds:** iLO user in Vault at `secret/homelab/ilo/readonly`.
- **Metrics:** server health, temperatures, fan speeds, power draw.

### `switch24a` (unmanaged/managed switch with SNMP)

- Use the shared `snmp_exporter` with the `if_mib` module.
- SNMPv3 creds in Vault.

### Synology NAS

- **Primary:** install Synology's own `node_exporter` package (DSM has
  it as a community package) and scrape port 9100.
- **Secondary/cross-check:** `snmp_exporter` with `synology`
  submodule. Duplication is useful here because NAS is the object-store
  floor — we want two paths to detect trouble.

## Application layer (native endpoints, where possible)

| Service | Endpoint | Auth | Notes |
|---|---|---|---|
| Vault | `/v1/sys/metrics?format=prometheus` | Vault token (sys/metrics read) | Use a dedicated metrics policy |
| Keycloak | `/metrics` (Quarkus) | None on internal network | Enable `quarkus.metrics.enabled=true` (already in our build) |
| MinIO | `/minio/v2/metrics/cluster` | MinIO access/secret key | Creds in Vault |
| cloudflared | `/metrics` on 2000 | None | Per-replica scrape |
| Registry | `/metrics` | Bearer (if `auth.token` configured) | |
| nginx | `nginx-prometheus-exporter` sidecar reading `stub_status` | None | Add `stub_status` to nginx.conf |
| Rundeck | `/api/40/metrics/metrics` | Rundeck token | Token in Vault |
| Watchtower | `/v1/metrics` | Bearer from `secret/homelab/watchtower` | |
| Twingate | Official exporter `ghcr.io/twingate/twingate-exporter` | Read-only API key | |
| FreeSWITCH | Custom: ESL-based exporter (community) | ESL creds | Or skip and rely on blackbox TCP |
| Postfix (mail relay) | `postfix_exporter` sidecar | None | If we actually use email alerts |

## Home Assistant — the single biggest scrape

- **Endpoint:** `https://ha.home.lcamaral.com/api/prometheus`
  (via the reverse proxy we just built).
- **Auth (Q8=A, locked):** dedicated bearer token under a purpose-built
  HA user `prometheus-scrape` (read-only scope via HA's policy system).
  Stored in Vault at `secret/homelab/home-assistant/metrics_token`.
  The existing `HA-TOKEN` in Keychain is NOT reused — it has broad
  write scope; leaking a metrics-only token has far smaller blast
  radius.
- **Config:**
  ```yaml
  - job_name: home-assistant
    metrics_path: /api/prometheus
    scheme: https
    scrape_interval: 30s
    static_configs:
      - targets: ['ha.home.lcamaral.com']
    authorization:
      credentials_file: /etc/prometheus/ha_token
  ```
- **Cardinality note:** HA exposes every entity. Big homes easily hit
  10k+ series from HA alone. Use `metric_relabel_configs` to drop
  irrelevant classes (e.g., `sun`, per-device-diagnostics). A starter
  drop list goes in the Prometheus config.

## Synthetic probes (`blackbox_exporter`)

- **Image:** `quay.io/prometheus/blackbox-exporter:v0.28.0`.
- **Modules:**
  - `http_2xx` — for web endpoints.
  - `icmp` — for device-is-alive probes (run the container with
    `NET_RAW` capability).
  - `dns_lcamaral` — for local DNS resolution health.
  - `tcp_connect` — for RustDesk ports, SSH, etc.
  - `ssl_expiry` — for cert expiry alerting.
- **Targets:** defined in `file_sd` config; one file per probe class,
  readable by Prometheus via `file_sd_configs`.

## Summary: component count

Expect to deploy (roughly) these per-host exporter containers:

| Host | Containers added |
|---|---|
| dockermaster | node, cadvisor, pve-exporter, thanos-query, blackbox, snmp |
| ds-1 | node, cadvisor, **prometheus-1**, **thanos-sidecar-1**, thanos-store-gw, unpoller, omada-exporter, pihole-exporter(×1 for pihole-2), grafana, alertmanager-1 |
| ds-2 | node, cadvisor, **thanos-compactor**, **thanos-ruler** |
| **NAS** | node (DSM package), cadvisor, pihole-exporter (pihole-3), **prometheus-2**, **thanos-sidecar-2**, **alertmanager-2** |

**Placement note (Q3=B):** prometheus-1 + sidecar-1 + alertmanager-1 stay on ds-1; prometheus-2 + sidecar-2 + alertmanager-2 move to the NAS. The earlier draft had prom-2 + AM-2 on ds-2; updated here to reflect the locked decision.

ds-2 hosts the "batch plane": compactor (writer), ruler (evaluator), both single-instance.
