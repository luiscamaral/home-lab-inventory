# 07 — Secrets and Security

## Vault paths (to be created in Phase 0)

All under `secret/homelab/monitoring/` unless otherwise noted.

| Path | Fields | Purpose |
|---|---|---|
| `secret/homelab/thanos/s3` | `access_key`, `secret_key`, `endpoint`, `bucket` | Thanos → MinIO |
| `secret/homelab/proxmox/api_token` | `token_id`, `token_secret` | pve-exporter |
| `secret/homelab/pfsense/snmp` | `username`, `auth_pass`, `priv_pass` | snmp_exporter |
| `secret/homelab/unifi/controller_api` | `username`, `password`, `url` | unpoller |
| `secret/homelab/omada/api` | `client_id`, `client_secret`, `omadac_id` | omada-exporter |
| `secret/homelab/ilo/readonly` | `username`, `password` | hpilo-exporter |
| `secret/homelab/home-assistant/metrics_token` | `token` | HA prometheus scrape (Q8=A: dedicated `prometheus-scrape` user, NOT the existing `HA-TOKEN`) |
| `secret/homelab/grafana/oidc` | `client_id`, `client_secret` | Grafana ↔ Keycloak |
| `secret/homelab/grafana/admin` | `password` | Grafana bootstrap admin (rotated later) |
| `secret/homelab/alertmanager/smtp` | `to_address` | Email recipient for all alert severities (Q5=Email). No SMTP auth — relays via internal postfix-relay |
| `secret/homelab/vault-metrics/token` | `token` | Vault-scraping vault, meta-circular. Use a policy allowing `sys/metrics` only. |

## Vault policies added

### `prometheus-scrape` (short-lived token, renewed via agent)

```hcl
path "secret/data/homelab/monitoring/+" {
  capabilities = ["read"]
}
path "secret/data/homelab/proxmox/api_token" {
  capabilities = ["read"]
}
path "secret/data/homelab/home-assistant/metrics_token" {
  capabilities = ["read"]
}
path "secret/data/homelab/vault-metrics/token" {
  capabilities = ["read"]
}
```

### `thanos-storage`

```hcl
path "secret/data/homelab/thanos/s3" {
  capabilities = ["read"]
}
```

## TLS

### External (reverse-proxied services)

- `grafana.cf.lcamaral.com` → Cloudflare edge TLS + nginx origin (same
  wildcard pattern as existing services).
- Thanos/Prometheus/Alertmanager: **NOT externally exposed**. If
  debugging from outside the LAN is needed, tunnel via SSH or
  Twingate.

### Internal (scrape traffic)

- Initial build uses HTTP on `docker-servers-net` (private macvlan).
- **Known gap:** scrape traffic for sensitive endpoints (Vault, HA) is
  therefore readable by anything on that network.
- **Mitigation options (post-MVP):**
  1. Generate an internal CA in Vault PKI engine.
  2. Issue per-exporter certs via Vault agent templates.
  3. Switch scrape configs to `scheme: https` + `tls_config`.
- Documented here because it WILL bite us when we add external
  auditors or more humans touching the homelab.

## Auth for scrape

Each scrape target falls into one of four modes:

1. **No auth (internal-only, low-sensitivity):** node_exporter,
   cadvisor, cloudflared metrics, nginx stub_status. Rely on network
   segmentation.
2. **Bearer token from Vault:** Home Assistant, Rundeck, Proxmox,
   Watchtower. Prometheus reads file from a mount populated by Vault
   agent sidecar.
3. **Basic auth:** Unifi controller (username/pw). Same Vault-agent
   pattern.
4. **SNMPv3:** pfSense, switches. Creds rendered into `snmp.yml` at
   container boot.

Pattern for Vault → Prometheus token delivery:

```
┌──────────────────┐    ┌────────────────────┐    ┌──────────────────┐
│ Vault KV v2      │──► │ Vault Agent sidecar │──► │ Prometheus      │
│ secret/homelab/..│    │ templates → files   │    │ reads token file │
└──────────────────┘    └────────────────────┘    └──────────────────┘
```

Prometheus scrape config references the mounted file:

```yaml
authorization:
  type: Bearer
  credentials_file: /etc/prometheus/tokens/ha
```

## Network posture

- **ds-1-hosted** monitoring: runs on `docker-servers-net`
  (192.168.48.0/20, macvlan). Includes: prometheus-1, sidecar-1,
  store-gw, grafana, alertmanager-1.
- **NAS-hosted** monitoring: runs on home-net macvlan
  (192.168.4.236). Includes: prometheus-2, sidecar-2, alertmanager-2,
  pihole-exporter for pihole-3.
- **ds-2-hosted** batch: runs on docker-servers-net. Includes:
  compactor, ruler.

### pfSense rules required (new, delta over current posture)

All TCP-only per `reference_pfsense_vlan_icmp.md`. Specific ports, not
"any".

1. **From NAS (192.168.4.236) to scrape targets across VLANs:**
   - → SRVAN 192.168.48.0/20: port 9100 (node), 8080 (cadvisor),
     9273 (HA), service-specific ports (Vault 8200, Keycloak 8080,
     MinIO 9000, etc.)
   - → HOMELAB 192.168.0.0/20: port 9100 (proxmox-pve-exporter)
   - → IOT 192.168.16.0/24: port 8123 (HA `/api/prometheus` via reverse
     proxy)
   - → ADMIN 192.168.32.0/27: SNMP 161 (iLO, switch24a), 443
     (unifi-controller), 8080 (omada)
2. **From NAS (AM-2) to postfix-relay** on docker-servers-net: port 25.
3. **From dockermaster (compactor on ds-2) + ds-1 (sidecar-1)** to
   MinIO: port 9000 (already allowed if MinIO is already reachable).
4. **From NAS (sidecar-2) to MinIO on ds-1 or ds-2:** port 9000.

### Grafana external access

- Only Grafana is externally reachable (Cloudflare tunnel →
  nginx-rproxy → Grafana on ds-1).
- No direct LAN access required for day-to-day use.

## Audit and change management

- Every Terraform change to `terraform/portainer/stacks/*.yml` reviewed
  in a PR.
- Vault audit log enabled (already on — see existing Vault config).
- Grafana admin user actions logged to DB (review quarterly).
- Alertmanager silence log reviewed weekly for forgotten silences
  (forgotten silences = silent outages).

## Known security gaps (not fixed in initial build; tracked)

- **Scrape traffic unencrypted on docker-servers-net.** Mitigate with
  Vault PKI in a follow-on project.
- **Grafana SQLite backend** is single-file; losing it loses dashboards.
  Mitigated by dashboards-as-code (source of truth is git).
- **Compactor runs as root** in the container. Not a homelab issue,
  but would be for production. Harden with user namespaces later.
- **Cloudflare tunnel exposes Grafana** — authentication only via
  Keycloak. Mitigate with Cloudflare Access policies (optional).
