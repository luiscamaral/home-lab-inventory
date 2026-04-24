# Pinned Versions

**Checked:** 2026-04-24 (against each project's `releases/latest` on GitHub).
**Re-check before each phase deploy.** All versions below should be re-verified
when the corresponding stack lands.

## Core stack (Prometheus / Thanos / Grafana ecosystem)

| Component | Image | Version | Source |
|---|---|---|---|
| Prometheus | `quay.io/prometheus/prometheus` | **`v3.11.2`** | <https://github.com/prometheus/prometheus/releases/latest> |
| Thanos (sidecar/query/store/compactor/ruler) | `quay.io/thanos/thanos` | **`v0.41.0`** | <https://github.com/thanos-io/thanos/releases/latest> |
| Grafana | `grafana/grafana-oss` | **`13.0.1`** | <https://github.com/grafana/grafana/releases/latest> |
| Alertmanager | `quay.io/prometheus/alertmanager` | **`v0.32.0`** | <https://github.com/prometheus/alertmanager/releases/latest> |
| node_exporter | `quay.io/prometheus/node-exporter` | **`v1.11.1`** | <https://github.com/prometheus/node_exporter/releases/latest> |
| cadvisor | `gcr.io/cadvisor/cadvisor` | **`v0.56.2`** | <https://github.com/google/cadvisor/releases/latest> |
| blackbox_exporter | `quay.io/prometheus/blackbox-exporter` | **`v0.28.0`** | <https://github.com/prometheus/blackbox_exporter/releases/latest> |
| snmp_exporter | `quay.io/prometheus/snmp-exporter` | **`v0.30.1`** | <https://github.com/prometheus/snmp_exporter/releases/latest> |

## Community / 3rd-party exporters

| Component | Image | Version | Source |
|---|---|---|---|
| pve-exporter | `prompve/prometheus-pve-exporter` | **`v3.8.2`** | <https://github.com/prometheus-pve/prometheus-pve-exporter/releases/latest> |
| unpoller (Unifi) | `ghcr.io/unpoller/unpoller` | **`v2.39.0`** | <https://github.com/unpoller/unpoller/releases/latest> |
| omada_exporter | `ghcr.io/charlie-haley/omada_exporter` | **`v0.13.1`** | <https://github.com/charlie-haley/omada_exporter/releases/latest> |
| pihole-exporter | `ghcr.io/eko/pihole-exporter` | **`v1.2.0`** | <https://github.com/eko/pihole-exporter/releases/latest> |
| nginx-prometheus-exporter | `nginx/nginx-prometheus-exporter` | **`v1.5.1`** | <https://github.com/nginx/nginx-prometheus-exporter/releases/latest> |
| postgres_exporter | `quay.io/prometheuscommunity/postgres-exporter` | **`v0.19.1`** | <https://github.com/prometheus-community/postgres_exporter/releases/latest> |
| ilo_exporter (HPE iLO) | `mauvesoftware/ilo_exporter` | **`1.0.3`** | <https://github.com/MauveSoftware/ilo_exporter/releases/latest> |

## Native /metrics endpoints (no exporter image to pin)

These services expose Prometheus-format metrics natively. Versions track the
service itself, not a separate exporter.

| Service | Endpoint | Notes |
|---|---|---|
| Vault | `/v1/sys/metrics?format=prometheus` | Already deployed |
| Keycloak | `/metrics` (Quarkus) | Already deployed |
| MinIO | `/minio/v2/metrics/cluster` | Already deployed |
| cloudflared | `:2000/metrics` | Built into the binary |
| Docker Registry | `/metrics` | Built-in |
| Home Assistant | `/api/prometheus` | Already enabled in `configuration.yaml` |
| Watchtower | `/v1/metrics` | HTTP API |
| Twingate | Via official exporter container | `ghcr.io/twingate/twingate-exporter:latest` (no semver release stream — track tags) |
| Rundeck | `/api/40/metrics/metrics` | Tied to Rundeck version |

## Refresh procedure

Before deploying any phase:

```bash
for repo in prometheus/prometheus thanos-io/thanos grafana/grafana \
           prometheus/alertmanager prometheus/node_exporter google/cadvisor \
           prometheus/blackbox_exporter prometheus/snmp_exporter; do
  tag=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | \
        python3 -c 'import sys,json; print(json.load(sys.stdin).get("tag_name"))')
  printf "%-40s  %s\n" "$repo" "$tag"
done
```

Compare to this file. If newer:

1. Read the changelog of the bumped component.
2. Look for breaking changes (especially around `external_labels`, retention
   semantics, TSDB format).
3. Bump in the relevant Terraform stack file under
   `terraform/portainer/stacks/`.
4. Update this VERSIONS.md and the `Checked:` date.

## Why we pin

- **Reproducibility:** the same plan rolled out twice produces the same
  cluster. `latest` does not.
- **Drift detection:** an image hash mismatch is easy to spot in a code
  review when the version is in the file.
- **Rollback:** to revert a bad upgrade, `git revert` the version bump.

## Why some are NOT pinned to a specific image

The native-metrics services (Vault, Keycloak, MinIO, etc.) are already pinned
in their own stacks — those pins live with the service, not the monitoring
plan. The monitoring plan only knows the **endpoint URL** and **scrape
config**, which are version-agnostic.
