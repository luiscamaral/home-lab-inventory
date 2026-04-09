# Docker Container Inventory

## Docker Master Server

### System Information

- **Host**: dockermaster (VM 120)
- **OS**: Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel**: Linux 6.8.0-64-generic
- **CPU**: 20 cores (Intel Xeon E5-2680 v2 @ 2.80GHz)
- **RAM**: 62 GB total (4.2 GB used, 58 GB available)
- **Storage**: 192 GB SSD (35% used - 64GB used, 119GB available)
- **Network**:
  - Main IP: 192.168.48.44/20
  - Server Network: 192.168.59.1/26 (macvlan)
- **Docker Version**: 28.3.2 (API 1.51)
- **Docker Compose**: 20 active projects (9 Terraform-managed via Portainer, 11 standalone)

### NFS Mounts

- `/nfs/calibre` - Calibre library storage (from NAS)
- `/nfs/dockermaster` - Docker persistent data (from NAS)

---

## Running Containers (29 across 20 compose projects)

### Terraform-Managed Portainer Stacks

#### Calibre (Stack ID: 10)

- **calibre**
  - Image: calibre-calibre
  - Network: rproxy bridge (172.24.0.x)
  - Ports: 58080:8080, 58081:8081, 58181:8181, 58090:9090
  - Resources: 2.55% CPU, 553MB RAM (0.86%)
  - Volumes: `/nfs/calibre/Library`, `/nfs/calibre/config`, `/nfs/calibre/upload`, `/nfs/calibre/plugins`
  - Purpose: E-book library management server

- **calibre-web**
  - Image: lscr.io/linuxserver/calibre-web:latest
  - Network: rproxy bridge (172.24.0.x)
  - Ports: 58083:8083
  - Resources: 0.02% CPU, 199MB RAM (0.31%)
  - Volumes: `/nfs/calibre/calibre-web/Library`, `/nfs/calibre/calibre-web/config`
  - Purpose: Web-based e-book reader interface

#### Bind DNS (Stack ID: 4)

- **bind-dns-bind9-1**
  - Image: Ubuntu/bind9:9.20-24.10_edge
  - Network: docker-servers-net
  - IP: 192.168.59.3
  - Ports: 53/tcp, 53/udp
  - Resources: 0.00% CPU, 12MB RAM (0.02%)
  - Volumes: `/nfs/dockermaster/docker/bind9/config`, `/nfs/dockermaster/docker/bind9/cache`, `/nfs/dockermaster/docker/bind9/records`
  - Purpose: DNS server with custom zones

#### Cloudflare Tunnel (Stack ID: 2)

- **cloudflare-tunnel-cloudflare-1**
  - Image: cloudflare/cloudflared
  - Network: rproxy bridge (172.24.0.x)
  - Purpose: Cloudflare tunnel routing `*.cf.lcamaral.com` to nginx-rproxy

#### Docker Registry (Stack ID: 1)

- **registry**
  - Image: registry:2
  - Network: rproxy bridge (172.24.0.x)
  - Purpose: Private Docker image registry (exposed via `registry.cf.lcamaral.com`)

#### GitHub Runner (Stack ID: 9)

- **github-runner-homelab**
  - Image: myoung34/github-runner (or custom)
  - Network: docker-servers-net
  - IP: 192.168.59.4
  - Volumes: `/var/run/docker.sock`, `/nfs/dockermaster/Docker` (read-only)
  - Purpose: GitHub Actions self-hosted runner for CI/CD

#### Reverse Proxy (Stack ID: 8)

- **rproxy**
  - Image: nginx:1.27
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.28
  - Resources: 0.00% CPU, 3.6MB RAM (0.01%)
  - Volumes: `/nfs/dockermaster/docker/nginx-rproxy/nginx-rproxy` → `/etc/nginx`
  - Purpose: Nginx reverse proxy with SSL termination for `*.d.lcamaral.com`

- **reverse-proxy-promtail-1**
  - Image: grafana/promtail
  - Network: dual (macvlan + rproxy bridge)
  - Purpose: Log shipping for nginx access/error logs

#### Twingate A (Stack ID: 5)

- **twingate-sepia-hornet**
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.12
  - Purpose: Twingate connector node A for zero-trust remote access

#### Twingate B (Stack ID: 6)

- **twingate-golden-mussel**
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.24
  - Purpose: Twingate connector node B for zero-trust remote access (HA pair)

#### Vault (Stack ID: 7)

- **vault**
  - Image: hashicorp/vault
  - Network: rproxy bridge (172.24.0.x)
  - Purpose: HashiCorp Vault secret management (exposed via `vault.d.lcamaral.com`)
  - Notes: Root token stored in macOS Keychain; secrets at `secret/homelab/*`

---

### Standalone Docker Compose

#### Portainer CE

- **portainer**
  - Image: portainer/portainer-ce:latest
  - Network: docker-servers-net
  - IP: 192.168.59.2
  - Resources: 0.04% CPU, 72MB RAM (0.11%)
  - Volumes: `/var/run/docker.sock`, `portainer_data`
  - Purpose: Docker management UI (bootstrap — not self-managed via Terraform)

#### Rundeck (la-rundeck)

- **rundeck**
  - Image: la-rundeck-rundeck (custom build)
  - Network: docker-servers-net
  - IP: 192.168.59.22
  - Resources: 0.44% CPU, 2.25GB RAM (3.58%)
  - Volumes: `/nfs/dockermaster/docker/rundeck/data`, `/var/run/docker.sock`
  - Purpose: Job scheduler and runbook automation

- **postgres-rundeck**
  - Image: postgres
  - Network: docker-servers-net
  - IP: 192.168.59.23
  - Resources: 0.01% CPU, 62MB RAM (0.10%)
  - Volumes: `/nfs/dockermaster/docker/rundeck/dbdata`
  - Purpose: Database backend for Rundeck

#### Prometheus

- **alertmanager**
  - Purpose: Alert routing and notification management

- **cadvisor**
  - Purpose: Container resource usage and performance monitoring

- **snmp-exporter**
  - Purpose: SNMP metrics export for network devices

#### LDAP (ldap-lcamaral-com)

- **lemonldap**
  - Network: rproxy bridge
  - Purpose: LemonLDAP::NG SSO portal

- **openldap**
  - Network: rproxy bridge
  - Purpose: OpenLDAP directory server

- **phpldapadmin**
  - Network: rproxy bridge
  - Purpose: Web UI for OpenLDAP administration

#### MinIO

- **minio**
  - Network: rproxy bridge
  - Purpose: S3-compatible object storage

#### Ollama

- **ollama**
  - Network: rproxy bridge
  - Purpose: Local LLM inference server

#### Chisel

- **chisel**
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.0
  - Purpose: TCP/UDP tunnel over HTTP

#### Rust Server (RustDesk relay)

- **hbbs**
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.10
  - Purpose: RustDesk ID/rendezvous server

- **hbbr**
  - Network: dual (macvlan + rproxy bridge)
  - IP: 192.168.59.11
  - Purpose: RustDesk relay server

#### FreeSWITCH

- **freeswitch**
  - Network: docker-servers-net
  - IP: 192.168.59.40
  - Purpose: VoIP / SIP softswitch

#### Elastic Search

- **elasticsearch**
  - Network: docker-servers-net
  - IP: 192.168.59.25
  - Purpose: Full-text search and analytics engine

#### Synology Search

- **nas-solr**
  - Network: docker-servers-net
  - IP: 192.168.59.31
  - Purpose: Solr search backend for NAS indexing

- **nas-tika**
  - Network: docker-servers-net
  - IP: 192.168.59.32
  - Purpose: Apache Tika document content extraction

---

## Inactive Projects

| Project | Last State | Description |
|---|---|---|
| ansible-observability | Stopped | Prometheus + Grafana for Ansible/AWX monitoring |
| docker-dns | Stopped | Dynamic DNS for Docker containers |
| docker-vault | Stopped | Legacy standalone Vault (superseded by vault Portainer stack) |
| litellm | Stopped | LiteLLM proxy + PostgreSQL |
| n8n-stack | Stopped | n8n workflow automation + PostgreSQL |
| puppet | Stopped | Puppet configuration management server |

---

## Docker Networks

### Active Networks

- **docker-servers-net**: Macvlan network for static server IPs (192.168.59.0/26)
- **rproxy bridge** (172.24.0.0/16): Internal bridge shared by nginx-rproxy and connected stacks
- **bind-dns_default**: Bind9 internal network
- **calibre_default**: Calibre services network
- **prometheus_default**: Prometheus stack network

### IP Assignment (docker-servers-net)

| IP | Container / Service |
|---|---|
| 192.168.59.0 | chisel |
| 192.168.59.2 | portainer |
| 192.168.59.3 | bind-dns |
| 192.168.59.4 | github-runner |
| 192.168.59.10 | hbbs (RustDesk) |
| 192.168.59.11 | hbbr (RustDesk) |
| 192.168.59.12 | twingate-a |
| 192.168.59.22 | rundeck |
| 192.168.59.23 | postgres-rundeck |
| 192.168.59.24 | twingate-b |
| 192.168.59.25 | elasticsearch |
| 192.168.59.28 | rproxy |
| 192.168.59.31 | nas-solr |
| 192.168.59.32 | nas-tika |
| 192.168.59.40 | freeswitch |

---

## Docker Volumes

### Named Volumes

- `dockermaster-portainer_portainer_data` - Portainer configuration
- `ollama_ollama` - Ollama models and data

### NFS-backed Storage

- All persistent data stored on NAS via NFS mounts
- Configuration files in `/nfs/dockermaster/docker/`
- Calibre library in `/nfs/calibre/`

---

## Docker Compose Stacks

### Terraform-Managed (via `terraform/portainer/`)

| Stack | Portainer ID |
|---|---|
| docker-registry | 1 |
| cloudflare-tunnel | 2 |
| bind-dns | 4 |
| twingate-a | 5 |
| twingate-b | 6 |
| vault | 7 |
| reverse-proxy | 8 |
| github-runner | 9 |
| calibre | 10 |

### Standalone (direct `docker compose`)

1. portainer-ce
2. la-rundeck
3. prometheus
4. ldap-lcamaral-com
5. minio
6. ollama
7. chisel
8. rust-server
9. freeswitch
10. elastic-search
11. synology-search

---

## Resource Summary

- **Total Containers**: 29 running across 20 active compose projects
- **Terraform-managed stacks**: 9 (via Portainer)
- **Standalone compose projects**: 11
- **Inactive projects**: 6
- **Memory Usage**: ~3.5 GB of 62 GB (~5.6%)
- **CPU Usage**: ~3% average
- **Storage**: Persistent data on NFS mounts
- **Network**: Macvlan (docker-servers-net) for static IPs; rproxy bridge for internal service communication

---

## Container Orchestration Platforms (VMs - Stopped)

### Docker Swarm Cluster

- Manager: VM 230
- Workers: VM 231, 232
- Status: Stopped

### Kubernetes Clusters

- Standard K8s: VMs 240-242
- Talos K8s: VMs 250-252
- Status: Stopped
