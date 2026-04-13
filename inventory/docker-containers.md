# Docker Container Inventory

> **Last refreshed:** 2026-04-12 after Phase 1-4 HA deployment
> **Source of truth:** `terraform/portainer/stacks.tf` (Portainer-managed) + on-host `docker ps`
> **HA topology:** see `docs/ha-architecture.md`

## NAS Server (Synology)

### System Information

- **Host**: nas (Synology NAS)
- **Docker**: 24.0.2 via Synology Container Manager (API 1.43)
- **Docker Compose**: v2.20.1
- **Docker Root**: `/volume2/@docker`
- **Storage Driver**: btrfs
- **Portainer**: Edge Agent endpoint ID 6 (name: "nas")
- **Edge Agent Image**: `portainer/agent:2.39.1`
- **Credentials**: `secret/homelab/portainer-nas-agent`
- **Compose files tracked at**: `nas/docker/`

### Running Containers on NAS (4 Portainer stacks + 1 agent)

#### Portainer Edge Agent

- **portainer-agent**
  - Image: `portainer/agent:2.39.1`
  - Compose: `nas/docker/portainer-agent/docker-compose.yml`
  - Connects outbound via WebSocket to `ws://192.168.59.2:8000`
  - Purpose: Edge agent enabling Portainer to manage NAS containers (NAS is not directly reachable from dockermaster)

#### NAS Portainer Stacks (Endpoint ID 6)

##### Twingate Connector (Stack ID: 28)

- **twingate-connector**
  - Network: macvlan
  - IP: 192.168.1.4
  - Compose: `nas/docker/twingate-connector/`
  - Purpose: Twingate zero-trust network connector on NAS

##### Speed Test (Stack ID: 29)

- **speed-test**
  - Image: openspeedtest/openspeedtest
  - Network: macvlan
  - IP: 192.168.4.234
  - Compose: `nas/docker/speed-test/`
  - Purpose: OpenSpeedTest local network speed test server

##### Paperless-NGX (Stack ID: 32)

- **paperlessngx** + **PostgreSQL** + **Redis**
  - Compose: `nas/docker/paperlessngx/`
  - Secrets: `secret/homelab/paperlessngx`
  - Purpose: Document management system with OCR (Paperless-NGX + PostgreSQL + Redis)

##### NetBoot.xyz (Stack ID: 34)

- **netbootxyz**
  - Image: lscr.io/linuxserver/netbootxyz (v0.7.6)
  - Network: macvlan
  - IP: 192.168.4.232
  - Compose: `nas/docker/netbootxyz/`
  - Purpose: Network boot server for PXE booting

---

## dockermaster (VM 120)

### System info

- **Host**: dockermaster (Proxmox VM 120)
- **OS**: Ubuntu 24.04 LTS
- **CPU**: 20 cores (Intel Xeon E5-2680 v2)
- **RAM**: 62 GB
- **Storage**: 192 GB SSD
- **Network**:
  - LAN: 192.168.48.44/20 (ens19)
  - Macvlan shim: 192.168.59.1/26 (`docker-servers-net`)
- **Docker**: 28.3.2 (API 1.51)
- **NFS mounts**: `/nfs/calibre`, `/nfs/dockermaster` (from NAS)
- **Role**: Control plane + edge + HA peers

### Running containers

#### Edge tier

- **rproxy** — `nginx:1.29-otel`
  - Networks: `docker-servers-net` (192.168.59.28) + `rproxy` bridge (172.24.0.6)
  - Volumes: `/nfs/dockermaster/docker/nginx-rproxy/nginx-rproxy` → `/etc/nginx`
  - **HA:** 1 of 3 (paired with rproxy-2 on ds-1, rproxy-3 on ds-2); shared vhost.d via NFS
  - Purpose: Nginx reverse proxy + SSL termination for `*.d.lcamaral.com`

- **reverse-proxy-promtail-1** — `grafana/promtail:latest`
  - Network: `rproxy` bridge
  - Purpose: Log shipping for Nginx access/error logs

- **cloudflare-tunnel-cloudflare-1** — `cloudflare/cloudflared:latest`
  - Network: `rproxy` bridge (172.24.0.8)
  - **HA:** replica 1 of 3 for tunnel `bologna`
  - Purpose: Forwards `*.cf.lcamaral.com` from Cloudflare edge to local Nginx

#### Auth tier

- **keycloak** — `keycloak/keycloak:26.3`
  - Networks: `docker-servers-net` (192.168.59.13) + `rproxy` bridge (172.24.0.7)
  - **HA:** Infinispan cluster with keycloak-2 (jdbc-ping discovery via `jgroups_ping` table)
  - Purpose: SSO identity provider (`auth.cf.lcamaral.com`)

- **keycloak-db-0** — `bitnamilegacy/postgresql-repmgr:17.6.0`
  - Network: `docker-servers-net` (192.168.59.44)
  - Volumes: NFS-backed
  - **HA:** repmgr primary (or standby after failover); paired with keycloak-db-1 on ds-1
  - Purpose: PostgreSQL backing store for Keycloak cluster

- **homelab-portal** — `registry.cf.lcamaral.com/homelab-portal:latest`
  - Networks: `docker-servers-net` (192.168.59.18) + `rproxy` bridge (172.24.0.9)
  - **HA:** stateless replica 1 of 2 (cookie-based session state, shared secrets)
  - Purpose: Custom SSO login UI (`login.cf.lcamaral.com`) backed by Keycloak

#### Backing services

- **vault** — `hashicorp/vault:1.21`
  - Networks: `docker-servers-net` (192.168.59.25) + `rproxy` bridge (172.24.0.5)
  - **HA:** Raft node 1 of 3 (voter)
  - Purpose: Secret management (`vault.d.lcamaral.com`, `vault.cf.lcamaral.com`)

- **bind-dns-bind9-1** — `ubuntu/bind9:9.20-24.10_edge`
  - Network: `docker-servers-net` (192.168.59.3)
  - Volumes: `/nfs/dockermaster/docker/bind9/{config,cache,records}`
  - Purpose: Authoritative DNS for `*.d.lcamaral.com` (single instance)

- **registry** — `registry:2`
  - Networks: `docker-servers-net` (192.168.59.16) + `rproxy` bridge (172.24.0.3)
  - Purpose: Private Docker image registry (`registry.cf.lcamaral.com`) — single instance

- **postfix-relay** — `boky/postfix:latest`
  - Network: `rproxy` bridge (172.24.0.2)
  - Purpose: Outbound SMTP relay via DreamHost — single instance

- **portainer** — `portainer/portainer-ce:latest`
  - Network: `docker-servers-net` (192.168.59.2)
  - Volumes: `/var/run/docker.sock`, `portainer_data`
  - Purpose: Docker management UI (bootstrap, not self-managed via Terraform)

#### Ancillary

- **watchtower** — `containrrr/watchtower:latest`
  - Network: internal bridge
  - Purpose: Auto-update opted-in images at 04:00 daily

---

## dockerserver-1 (VM 123)

### System info

- **Host**: dockerserver-1 (Proxmox VM 123)
- **OS**: Ubuntu 24.04.4 LTS (kernel 6.8.0-107-generic)
- **CPU**: 10 cores
- **RAM**: 23 GB
- **Storage**: 113 GB (`/dev/sda2`, 37% used)
- **Network**:
  - LAN: 192.168.48.45/20 (ens19)
  - Macvlan shim: 192.168.59.33/32 (`server-net-shim`)
- **Role**: Primary workloads + HA peers

### Running containers

#### Edge tier

- **rproxy-2** — `nginx:1.29-otel`
  - Networks: `docker-servers-net` (192.168.59.48) + local `rproxy` bridge (172.20.0.3)
  - Volumes: shared Nginx vhost.d via NFS
  - **HA:** 2 of 3
  - Purpose: Nginx reverse proxy replica

- **cloudflare-tunnel-2** — `cloudflare/cloudflared:latest`
  - Network: local `rproxy` bridge (172.20.0.2)
  - **HA:** replica 2 of 3 for tunnel `bologna`
  - Purpose: Tunnel to local Nginx on this host

#### Auth tier

- **keycloak-2** — `keycloak/keycloak:26.3`
  - Network: `docker-servers-net` (192.168.59.43)
  - **HA:** Infinispan peer with keycloak on dm
  - Purpose: Keycloak cluster peer

- **keycloak-db-1** — `bitnamilegacy/postgresql-repmgr:17.6.0`
  - Network: `docker-servers-net` (192.168.59.54)
  - Volumes: local disk
  - **HA:** repmgr standby (or primary after failover)
  - Purpose: PostgreSQL HA peer for Keycloak

- **homelab-portal-2** — `registry.cf.lcamaral.com/homelab-portal:latest`
  - Network: `docker-servers-net` (192.168.59.38)
  - **HA:** stateless replica 2 of 2
  - Purpose: Homelab portal replica

#### Backing services

- **vault-2** — `hashicorp/vault:1.21`
  - Network: `docker-servers-net` (192.168.59.9)
  - **HA:** Raft node 2 of 3 (voter)
  - Purpose: Vault cluster peer

- **minio-minio-1** — `minio/minio:latest`
  - Network: `docker-servers-net` (192.168.59.17)
  - Volumes: `/nfs/dockermaster/docker/MinIO/minio-data` (NFS)
  - **HA:** site replication peer 1 (paired with minio-2 on ds-2)
  - Purpose: S3-compatible object storage (`s3.cf.lcamaral.com`, `minio.cf.lcamaral.com`)

- **twingate-sepia-hornet** — `twingate/connector:1`
  - Network: `docker-servers-net` (192.168.59.12)
  - **HA:** 1 of 2 Twingate connectors (paired with golden-mussel on ds-2)
  - Purpose: Zero-trust remote access connector

#### Workloads (single instance)

- **calibre** — `linuxserver/calibre:latest`
  - Network: `docker-servers-net` (192.168.59.7)
  - Volumes: `/nfs/calibre/Library`, `/nfs/calibre/config`, `/nfs/calibre/upload`, `/nfs/calibre/plugins`
  - Purpose: E-book library management (single — SQLite store)

- **calibre-web** — `lscr.io/linuxserver/calibre-web:latest`
  - Network: `docker-servers-net` (192.168.59.6)
  - Volumes: `/nfs/calibre/calibre-web/{Library,config}`
  - Purpose: Web-based e-book reader UI

- `github-runner-homelab` — `myoung34/github-runner:latest`
  - Network: `docker-servers-net` (192.168.59.4)
  - Volumes: `/var/run/docker.sock`, `/nfs/dockermaster/Docker` (read-only)
  - Purpose: Self-hosted GitHub Actions runner for CI/CD

- **rundeck** — `registry.cf.lcamaral.com/la-rundeck:latest`
  - Network: `docker-servers-net` (192.168.59.22)
  - Volumes: `/nfs/dockermaster/docker/rundeck/data`, `/var/run/docker.sock`
  - Purpose: Job scheduler / runbook automation

- **postgres-rundeck** — `postgres:17`
  - Network: `docker-servers-net` (192.168.59.23)
  - Volumes: `/nfs/dockermaster/docker/rundeck/dbdata`
  - Purpose: Database backend for Rundeck

#### Monitoring stack (Prometheus)

- `prometheus-prometheus-1` — `prom/prometheus:latest`
  - Network: internal `prometheus_back-tier` bridge; host-published `:9090`
  - Purpose: Metrics TSDB (single instance)
- `prometheus-alertmanager-1` — `prom/alertmanager`
  - Purpose: Alert routing
- `prometheus-cadvisor-1` — `gcr.io/cadvisor/cadvisor`
  - Purpose: Container resource metrics
- `prometheus-node-exporter-1` — `quay.io/prometheus/node-exporter:latest`
  - Purpose: Host metrics
- `prometheus-snmp-exporter-1` — `prom/snmp-exporter:v0.20.0`
  - Purpose: SNMP metrics for network devices

#### Ancillary

- **portainer-agent** — `portainer/agent:2.39.1`
  - Network: `docker-servers-net` (192.168.59.34)
  - Purpose: Portainer agent for managing ds-1 from the central Portainer

- **watchtower** — `containrrr/watchtower:latest`
  - Purpose: Local image auto-updater

---

## dockerserver-2 (VM 124)

### System info

- **Host**: dockerserver-2 (Proxmox VM 124)
- **OS**: Ubuntu 24.04.4 LTS (kernel 6.8.0-107-generic)
- **CPU**: 10 cores
- **RAM**: 23 GB
- **Storage**: 113 GB (`/dev/sda2`, 28% used)
- **Network**:
  - LAN: 192.168.48.46/20 (ens19)
  - Macvlan shim: 192.168.59.33/32 (`server-net-shim`)
- **Role**: Workloads + HA peers

### Running containers

#### Edge tier

- **rproxy-3** — `nginx:1.29-otel`
  - Networks: `docker-servers-net` (192.168.59.49) + local `rproxy` bridge (172.18.0.3)
  - **HA:** 3 of 3 (shared vhost.d via NFS)
  - Purpose: Nginx reverse proxy replica

- **cloudflare-tunnel-3** — `cloudflare/cloudflared:latest`
  - Network: local `rproxy` bridge (172.18.0.2)
  - **HA:** replica 3 of 3 for tunnel `bologna`
  - Purpose: Tunnel to local Nginx on this host

#### Backing services

- **vault-3** — `hashicorp/vault:1.21`
  - Network: `docker-servers-net` (192.168.59.15)
  - **HA:** Raft node 3 of 3 (voter)
  - Purpose: Vault cluster peer

- **minio-2-minio-1** — `minio/minio:latest`
  - Network: `docker-servers-net` (192.168.59.37)
  - Volumes: `/var/lib/minio-data` (local disk — storage-level HA from ds-1's NFS)
  - **HA:** site replication peer 2 (bidirectional active-active)
  - Purpose: MinIO S3 replica

- **twingate-golden-mussel** — `twingate/connector:1`
  - Network: `docker-servers-net` (192.168.59.24)
  - **HA:** 2 of 2 Twingate connectors
  - Purpose: Zero-trust remote access connector

#### Workloads (single instance)

- **freeswitch** — `ghcr.io/patrickbaus/freeswitch-docker`
  - Network: `docker-servers-net` (192.168.59.40)
  - Purpose: VoIP / SIP softswitch (stateful — single by design)

- **hbbs** — `rustdesk/rustdesk-server:latest`
  - Network: `docker-servers-net` (192.168.59.10)
  - Purpose: RustDesk ID / rendezvous server

- **hbbr** — `rustdesk/rustdesk-server:latest`
  - Network: `docker-servers-net` (192.168.59.11)
  - Purpose: RustDesk relay server

#### Ancillary

- **portainer-agent** — `portainer/agent:latest`
  - Network: `docker-servers-net` (192.168.59.46)
  - Purpose: Portainer agent for managing ds-2 from the central Portainer

---

## Network / IP assignments (`docker-servers-net`, 192.168.59.0/26)

| IP | Container | Host |
|---|---|---|
| .1 | gateway / dockermaster macvlan shim | dm |
| .2 | portainer | dm |
| .3 | bind-dns-bind9-1 | dm |
| .4 | `github-runner-homelab` | ds-1 |
| .6 | calibre-web | ds-1 |
| .7 | calibre | ds-1 |
| .9 | vault-2 | ds-1 |
| .10 | hbbs (RustDesk ID) | ds-2 |
| .11 | hbbr (RustDesk relay) | ds-2 |
| .12 | twingate-sepia-hornet | ds-1 |
| .13 | keycloak | dm |
| .15 | vault-3 | ds-2 |
| .16 | registry | dm |
| .17 | minio-minio-1 | ds-1 |
| .18 | homelab-portal | dm |
| .22 | rundeck | ds-1 |
| .23 | postgres-rundeck | ds-1 |
| .24 | twingate-golden-mussel | ds-2 |
| .25 | vault | dm |
| .28 | rproxy (edge 1/3) | dm |
| .33 | server-net-shim (ds-1 & ds-2 host shim) | ds-1, ds-2 |
| .34 | portainer-agent | ds-1 |
| .37 | minio-2-minio-1 | ds-2 |
| .38 | homelab-portal-2 | ds-1 |
| .40 | freeswitch | ds-2 |
| .43 | keycloak-2 | ds-1 |
| .44 | keycloak-db-0 | dm |
| .46 | portainer-agent | ds-2 |
| .48 | rproxy-2 (edge 2/3) | ds-1 |
| .49 | rproxy-3 (edge 3/3) | ds-2 |
| .54 | keycloak-db-1 | ds-1 |

## Removed services (since last refresh)

The following services were present in the pre-HA inventory and have been removed or superseded:

| Service | Reason |
|---|---|
| chisel | Removed — replaced by Twingate + Cloudflare tunnel |
| ldap-lcamaral-com (openldap, lemonldap, phpldapadmin) | Removed — superseded by Keycloak |
| ollama | Removed |
| `elasticsearch` | Removed |
| `nas-solr`, `nas-tika` | Removed from dockermaster (NAS search now handled differently) |
| `ansible-observability`, `docker-dns`, `docker-vault`, `litellm`, `n8n-stack`, `puppet` | Removed (were already stopped) |
| vault on NAS | Superseded by 3-node Vault Raft cluster |
| ocr-photo-tag on NAS | Removed (non-portable) |

## Terraform-managed Portainer stacks

Authoritative list in `terraform/portainer/stacks.tf`:

| Stack | Endpoint |
|---|---|
| `docker-registry` | dm |
| `cloudflare-tunnel`, `cloudflare-tunnel-2`, `cloudflare-tunnel-3` | dm, ds-1, ds-2 |
| `bind-dns` | dm |
| `reverse-proxy`, `reverse-proxy-2`, `reverse-proxy-3` | dm, ds-1, ds-2 |
| `vault`, `vault-3` (vault-2 runs alongside) | dm, ds-2 (+ ds-1) |
| `twingate-a`, `twingate-b` | ds-1, ds-2 |
| `calibre` | ds-1 |
| `github-runner` | ds-1 |
| `rust-server` | ds-2 |
| `la-rundeck` | ds-1 |
| `prometheus` | ds-1 |
| `watchtower`, `watchtower_dm` | ds-1, dm |
| `minio`, `minio-2` | ds-1, ds-2 |
| `freeswitch` | ds-2 |
| `keycloak-db-0`, `keycloak-db-1` | dm, ds-1 |
| `keycloak`, `keycloak-2` | dm, ds-1 |
| `postfix-relay` | dm |
| `homelab-portal`, `homelab-portal-2` | dm, ds-1 |

Portainer itself (on dm, `192.168.59.2`) is bootstrap and not Terraform-managed.

## Notes

- All `.cf.lcamaral.com` traffic enters via Cloudflare tunnel → nearest
  cloudflared replica → local Nginx on the same host.
- All `.d.lcamaral.com` traffic is LAN-only; bind9 returns 3 A records for
  HA vhosts (`.28`, `.48`, `.49`).
- HA failure modes and tested failover scenarios: see `docs/ha-architecture.md`.
