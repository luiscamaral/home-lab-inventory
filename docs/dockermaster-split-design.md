# Homelab Multi-Server Split Design

**Status**: Phase 1 complete — dockerserver-1 (VM 123) and dockerserver-2 (VM 124) provisioned.
vault-2 running (2-node Raft cluster). CPU affinity pinned: dockermaster + dockerserver-1 → socket 0,
dockerserver-2 → socket 1.

**Date**: 2026-04-11
**Branch**: `nas-docker-server`

## Motivation

| Problem | Impact |
|---------|--------|
| dockermaster is a single SPOF | One VM failure takes down all services |
| Vault single-node Raft | No quorum — data loss risk on any failure |
| Snapshot gap (last: 2025-09-15) | 7 months with no Vault backup (fixed in this branch) |
| All services on one VM | Noisy-neighbour risk; hard to right-size |

## Target Architecture

```text
Proxmox Hypervisor (20C/40T, 243 GB RAM)
│
├── VM 120 — dockermaster  (Control Plane — keep, lean)
│   ├── Portainer            managed UI for all endpoints
│   ├── Nginx-1 + Promtail   web ingress (active)
│   ├── cloudflared-1        CF tunnel bologna connector A
│   ├── Bind9-primary        authoritative DNS d.lcamaral.com
│   ├── Docker Registry      registry.cf.lcamaral.com
│   └── vault-1              Raft voter (leader candidate)
│
├── VM 123 — dockerserver-1  (Infra HA pair + App Plane A, short: ds-1)
│   ├── Nginx-2 + cloudflared-2  web ingress (active-active with dockermaster)
│   ├── Bind9-secondary          slave zone from dockermaster
│   ├── vault-2                  Raft voter
│   ├── Twingate A               sepia-hornet connector
│   ├── GitHub Runner            CI/CD worker
│   ├── Watchtower               auto-updates for ds-1 containers
│   ├── homelab-portal           login.cf.lcamaral.com
│   ├── Calibre + Calibre Web    ebook library
│   ├── Rundeck + PostgreSQL     job automation
│   ├── Prometheus stack         prometheus, alertmanager, snmp-exporter
│   ├── node-exporter + cadvisor scrape ds-1 host metrics
│   ├── MinIO                    S3 object storage
│   └── Keycloak-1 + PG-replica  SSO node A (DB replica for failover)
│
├── VM 124 — dockerserver-2  (App Plane B, short: ds-2)
│   ├── vault-3                  Raft voter
│   ├── Twingate B               golden-mussel connector
│   ├── Watchtower               auto-updates for ds-2 containers
│   ├── Keycloak-2 + PG-primary  SSO node B (authoritative DB)
│   ├── Ollama                   LLM inference server
│   ├── FreeSWITCH               VoIP/SIP server
│   ├── RustDesk                 hbbs + hbbr remote desktop relay
│   └── node-exporter + cadvisor scraped by Prometheus on ds-1
│
└── NAS — Synology  (Edge endpoint — unchanged)
    ├── portainer-agent          Edge agent
    ├── netbootxyz               PXE boot server
    ├── paperlessngx             document management
    └── speedtest                LAN speed test
```

### Key Design Decisions

- **dockermaster stays** — lean control plane, not decommissioned
- **Clone strategy** — clone dockermaster → ds-1 (carries NFS mounts, Docker config);
  clone again → ds-2 then prune to app-only services
- **NFS mount point** — `/nfs/dockermaster` on all three servers, same NAS export
  (`tnas:/volume2/servers/dockermaster`). No path changes in compose files.
- **Watchtower** — one instance per app server (ds-1, ds-2); removed from dockermaster
  (control-plane containers should not be auto-updated)
- **Vault HA** — 3 Raft voters on dockermaster + ds-1 + ds-2; NAS excluded
  (kernel 4.4 too old for reliable Vault)

## Nginx Green-Green + Cloudflare Tunnel

Two active Nginx instances share the same NFS-backed config. A config change
(new vhost, cert update) applies to both simultaneously on next reload.

```text
External:
  Cloudflare edge
    ├── connector A → cloudflared-1 (dockermaster) → Nginx-1
    └── connector B → cloudflared-2 (ds-1)         → Nginx-2

  Cloudflare automatically routes around a failed connector.

Internal (*.d.lcamaral.com):
  Bind9 returns two A records (low TTL 30s):
    - 192.168.59.28  Nginx-1 (dockermaster)
    - 192.168.59.7   Nginx-2 (ds-1)
  Round-robin DNS — not health-aware, acceptable for homelab.
```

Both cloudflared connectors use the same tunnel token (bologna).
Each points to its local Nginx: `https://nginx-rproxy:443` on the container network.

## Keycloak HA + PostgreSQL

```text
Nginx (both instances) ──health-check──► Keycloak-1 (ds-1)
                                      └► Keycloak-2 (ds-2)

Keycloak-1 ──normally──► PG primary (ds-2:5432 via host port)
Keycloak-2 ──normally──► PG primary (localhost via app bridge)

Failover (ds-2 dies):
  1. pg_promote on ds-1 replica
  2. Keycloak-1 switches to local PG (now primary)
  3. Keycloak-2 is down (same server as failed PG primary)
  4. SSO continues via Keycloak-1 alone
```

- **Keycloak config**: `KC_CACHE=local` — sessions stored in PostgreSQL,
  no JGroups inter-node session replication needed
- **PostgreSQL**: streaming replication, primary on ds-2, hot standby on ds-1
- **Failover**: manual `pg_promote` on ds-1; document as runbook, not automated
- **Rundeck PostgreSQL**: single-instance on ds-1, separate from Keycloak PG

## Vault Raft HA Cluster

### Quorum

3 voters → quorum = 2 → survives any single-node failure, fully automatic.

| Failed node | Remaining | Outcome |
|-------------|-----------|---------|
| vault-1 (dockermaster) | vault-2 + vault-3 = 2/3 ✅ | Auto-elect new leader |
| vault-2 (ds-1) | vault-1 + vault-3 = 2/3 ✅ | Auto-elect new leader |
| vault-3 (ds-2) | vault-1 + vault-2 = 2/3 ✅ | Auto-elect new leader |
| Any two nodes | 1/3 ❌ | Read-only, no writes |

### Network Requirements

All Vault nodes need TCP 8200 (API) and 8201 (cluster) reachable to each other.
All three are on the same Proxmox VLAN (vmbr28) → direct L2, no firewall changes needed.

### Vault config.hcl Template

```hcl
storage "raft" {
  path    = "/vault/raft"
  node_id = "vault-N"   # vault-1, vault-2, vault-3

  retry_join { leader_api_addr = "http://192.168.59.25:8200" }  # vault-1
  retry_join { leader_api_addr = "http://192.168.59.9:8200"  }  # vault-2
  retry_join { leader_api_addr = "http://192.168.59.15:8200" }  # vault-3
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://THIS_NODE_MACVLAN_IP:8200"
cluster_addr = "http://THIS_NODE_MACVLAN_IP:8201"
ui = true
```

### Snapshot Automation (Phase 2 — Rundeck)

Ofelia sidecar was removed. In a 3-node Raft cluster, a per-container scheduler
is unreliable — followers cannot snapshot, so two of three nodes would silently fail
every night. Snapshot job moves to Rundeck on ds-1 (single scheduler, leader-aware
via the API endpoint, alertable).

Rundeck job spec (Phase 2):

- **Schedule**: daily 02:00
- **Command**: `vault operator raft snapshot save /nfs/dockermaster/docker/vault/vault/snapshots/snap-$(date +%Y%m%d).snap`
- **Token**: dedicated snapshot policy token stored in `secret/homelab/vault`
- **Prune**: daily 02:30 — `find /nfs/.../snapshots -name snap-*.snap -mtime +30 -delete`
- **Storage**: `/nfs/dockermaster/docker/vault/vault/snapshots/` (NFS-backed, survives VM loss)

The snapshots volume mount is retained in `vault.yml` so the path is accessible
from inside the vault container if needed for manual saves.

Apply vault macvlan change: `terraform -chdir=terraform/portainer apply -target=portainer_stack.vault`

## Network Design

### Bridge Networks (per server, host-local)

| Network | Server(s) | Purpose |
|---------|-----------|---------|
| `rproxy` | dockermaster, ds-1 | Nginx ↔ upstream web services |
| `backend` | ds-1 | Rundeck ↔ PG, Keycloak-1 ↔ PG-replica |
| `app` | ds-2 | Keycloak-2 ↔ PG-primary, n8n, internal |
| `monitoring` | all three | Prometheus stack, node-exporter, cadvisor |

All bridge networks declared `internal: true`. Created by a `network-bootstrap` stack
deployed first on each server; all application stacks reference them as `external: true`.

### Macvlan Network (`docker-servers-net`)

Same physical subnet on all three servers. Each host creates its own macvlan
attached to the LAN interface (vmbr28 bridge).

**Subnet**: 192.168.48.0/20
**IPRange**: 192.168.59.0/26 (divided into per-server slices below)
**Gateway**: 192.168.48.1
**Host auxiliary**: 192.168.59.1 (dockermaster ↔ macvlan bridge)

Creation command per host (run once during bootstrap):

```bash
docker network create \
  --driver macvlan \
  --subnet 192.168.48.0/20 \
  --ip-range 192.168.59.X/28 \
  --gateway 192.168.48.1 \
  --aux-address "host=192.168.59.1" \
  --opt parent=ens18 \
  docker-servers-net
```

Replace `X/28` with the server's slice start address.

### Cross-Server Communication

Bridge networks are host-local. Cross-server traffic uses macvlan IPs or host-exposed ports.

| Pattern | Example |
|---------|---------|
| macvlan → macvlan | Vault Raft cluster, Bind9 zone transfer, Nginx-1 ↔ Nginx-2 (none needed — independent) |
| bridge → host port | Keycloak-1 (ds-1) → ds-2 host IP:5432 → PG primary |
| bridge → host port | Prometheus (ds-1) → dockermaster:9100 / ds-2:9100 → node-exporter |
| via Nginx | All HTTP services — clients hit Nginx macvlan IP, proxy to backend bridge |

PostgreSQL ports (5432) exposed on ds-1 and ds-2 host interfaces.
Firewall restricts access to specific source IPs only.

## IP Allocation — `docker-servers-net` (192.168.59.0/26)

### Current Assignments (complete map)

| IP | Container | Current server | Status in new arch |
|----|-----------|---------------|-------------------|
| .1 | host aux | dockermaster | reserved |
| .2 | Portainer | dockermaster | keep |
| .3 | Bind9-primary | dockermaster | keep |
| .4 | GitHub Runner | dockermaster | moves → ds-1, keeps IP |
| .10 | RustDesk hbbs | dockermaster | moves → ds-2, keeps IP |
| .11 | RustDesk hbbr | dockermaster | moves → ds-2, keeps IP |
| .12 | Twingate A | dockermaster | moves → ds-1, keeps IP |
| .13 | Keycloak | dockermaster | freed — behind Nginx in new arch |
| .20 | Ansible-observability | dockermaster | dropped — deleted |
| .21 | Ansible-observability | dockermaster | dropped — deleted |
| .22 | Rundeck | dockermaster | moves → ds-1, keeps IP |
| .23 | Rundeck PostgreSQL | dockermaster | moves → ds-1, keeps IP |
| .24 | Twingate B | dockermaster | moves → ds-2, keeps IP |
| .25 | elastic-search | dockermaster | dropped — old PoC |
| .28 | Nginx-1 | dockermaster | keep |
| .30 | n8n | dockermaster | dropped — old PoC |
| .40 | FreeSWITCH | dockermaster | moves → ds-2, keeps IP |
| .41 | LiteLLM | dockermaster | dropped — deleted |

### New Assignments

| IP | Container | Server | Notes |
|----|-----------|--------|-------|
| .5 | Docker Registry | dockermaster | NEW — macvlan for cross-server pulls |
| .25 | vault-1 | dockermaster | NEW — takes freed .25; add to vault.yml IaC |
| .7 | Nginx-2 | ds-1 | NEW |
| .8 | Bind9-secondary | ds-1 | NEW |
| .9 | vault-2 | ds-1 | NEW |
| .14 | MinIO | ds-1 | NEW — was bridge-only |
| .15 | vault-3 | ds-2 | NEW |

### Final IP Map by Server

**dockermaster** (slice: .2–.15, using .2–.5, .25, .28)

| IP | Container |
|----|-----------|
| 192.168.59.2 | Portainer |
| 192.168.59.3 | Bind9-primary |
| 192.168.59.5 | Docker Registry |
| 192.168.59.25 | vault-1 (add to IaC) |
| 192.168.59.28 | Nginx-1 |

**ds-1** (slice: .4, .7–.9, .12, .14, .22–.23 — mix of kept + new)

| IP | Container |
|----|-----------|
| 192.168.59.4 | GitHub Runner |
| 192.168.59.7 | Nginx-2 |
| 192.168.59.8 | Bind9-secondary |
| 192.168.59.9 | vault-2 |
| 192.168.59.12 | Twingate A |
| 192.168.59.14 | MinIO |
| 192.168.59.22 | Rundeck |
| 192.168.59.23 | Rundeck PostgreSQL |

**ds-2** (slice: .10–.11, .15, .24, .40)

| IP | Container |
|----|-----------|
| 192.168.59.10 | RustDesk hbbs |
| 192.168.59.11 | RustDesk hbbr |
| 192.168.59.15 | vault-3 |
| 192.168.59.24 | Twingate B |
| 192.168.59.40 | FreeSWITCH |

**Available for future use**: .6, .16–.19, .26–.27, .29–.31, .33–.39, .41–.62

### Resolved Issues

1. ✅ **vault-1 macvlan** — `vault.yml` updated with `docker-servers-net` + `.25`; applied.
2. ✅ **Standalone leftovers removed** — `elasticsearch`, `lemonldap`, `phpldapadmin`,
   `openldap`, `chisel`, `n8n` stopped and removed from live dockermaster.
3. ✅ **IPs freed**: .0, .6, .20, .21, .25, .30, .41 — available for future use.

## Resource Planning

### dockermaster (VM 120 — unchanged)

- **CPU**: 20 vCPU (keep — already provisioned)
- **RAM**: 62 GB (keep — already provisioned)
- **Storage**: 196 GB SSD

After migration, dockermaster will be lightly loaded (6–7 lightweight containers).
Can be right-sized down to 8 vCPU / 16 GB in a future maintenance window if desired.

### ds-1 (VM 123 — new)

- **CPU**: 10 vCPU
- **RAM**: 24 GB (Prometheus + MinIO + Keycloak-1 + PG-replica need headroom)
- **Storage**: 150 GB SSD (thin-pool-ssd)
- **Network**: vmbr28

### ds-2 (VM 124 — new)

- **CPU**: 12 vCPU
- **RAM**: 32 GB (Ollama models ~8 GB each, Keycloak-2 + PG-primary, FreeSWITCH)
- **Storage**: 200 GB SSD (thin-pool-ssd)
- **Network**: vmbr28

### Proxmox Capacity

| | RAM |
|--|-----|
| Total | 243 GB |
| Currently running (7 VMs) | ~134 GB |
| Available headroom | ~109 GB |
| ds-1 + ds-2 | 56 GB |
| Remaining after split | ~53 GB ✅ |

## Implementation Phases

### Phase 0 — Immediate (done)

- [x] Vault snapshot path provisioned — NFS snapshots dir created, pre-split manual snap taken
- [x] Vault snapshot automation — moved to Rundeck (Phase 2); ofelia sidecar removed (not HA-safe)
- [x] Drop Chisel, Ansible-observability, LiteLLM — IaC removed, committed
- [x] Stop and remove standalone leftovers on live dockermaster:
  `elasticsearch`, `lemonldap`, `phpldapadmin`, `openldap`, `chisel` — all stopped and removed
- [x] Add vault-1 macvlan IP to `vault.yml` IaC:
  `docker-servers-net` network + `ipv4_address: 192.168.59.25`
- [x] Manual snapshot before any migration work:
  `pre-split-manual.snap` saved to NFS snapshots dir (99K, 2026-04-11)

### Phase 1 — Provision ds-1 (VM 123)

- [x] Clone VM 120 (dockermaster) → VM 123 in Proxmox
- [x] Boot, change hostname to `ds-1`, change host IP (192.168.48.45 / shim 192.168.59.33)
- [x] Create macvlan with ds-1 IP slice (`docker-servers-net`, shim at 192.168.59.33/32)
- [x] Register as new Portainer endpoint (ID 9, agent at 192.168.59.34:9001, type=2)
  - Portainer agent: `portainer/agent:2.39.1`, macvlan IP 192.168.59.34
  - Managed via `terraform/portainer/environments.tf`
- [x] Bridge networks confirmed present (cloned from dockermaster): `rproxy` (172.24/16),
  `prometheus_back-tier` (172.21/16), `keycloak_keycloak-internal`
- [x] Bring up vault-2 (192.168.59.9) — joined vault-1, 2-node Raft cluster active
  - vault-1: leader (192.168.59.25), vault-2: follower (192.168.59.9)
  - Both voters, both unsealed

### Phase 2 — Migrate App Services to ds-1

Services to start on ds-1 (stop on dockermaster first):

- GitHub Runner, Twingate A, Calibre, Rundeck + PG
- MinIO, homelab-portal, Prometheus stack
- Keycloak-1, PG-replica (streaming from dockermaster Keycloak PG)
- Nginx-2 + cloudflared-2 (add second CF tunnel connector to bologna tunnel)
- Bind9-secondary (configure zone transfer from dockermaster Bind9)
- Watchtower (manages ds-1 containers only)

### Phase 3 — Provision ds-2 (VM 124)

1. Clone VM 120 (dockermaster) → VM 124
2. Boot, change hostname to `ds-2`, change host IP
3. Create macvlan with ds-2 IP slice
4. Register as new Portainer endpoint
5. Deploy `network-bootstrap` stack
6. Bring up vault-3 — joins Raft cluster → 3 voters, quorum reached ✅
7. Verify: `vault operator raft list-peers` shows 3 voters

### Phase 4 — Migrate App Services to ds-2

Services to start on ds-2 (stop on dockermaster first):

- Twingate B, RustDesk, FreeSWITCH, Ollama
- Keycloak-2 + PG-primary (Keycloak-1 switches connection to ds-2 PG)
- Watchtower (manages ds-2 containers only)

### Phase 5 — Slim dockermaster

Remove from dockermaster (now running on ds-1 or ds-2):

- Twingate A, Twingate B
- GitHub Runner, Watchtower
- Keycloak, Rundeck, RustDesk, FreeSWITCH, Ollama, MinIO, Calibre

Keep on dockermaster (control plane):

- Portainer, Nginx-1, cloudflared-1, Bind9-primary
- Docker Registry, vault-1

### Phase 6 — PostgreSQL Streaming Replication (Keycloak)

1. Configure PG primary on ds-2 for streaming replication
2. Set up PG hot standby on ds-1
3. Verify replication lag: `SELECT * FROM pg_stat_replication;`
4. Document failover runbook: `pg_promote` on ds-1 + update Keycloak-1 connection string

## Terraform Structure (post-split)

```text
terraform/
├── cloudflare/          # unchanged
├── vault/               # unchanged
├── portainer/
│   ├── dockermaster/    # control-plane stacks (renamed from portainer/)
│   │   ├── provider.tf
│   │   ├── variables.tf
│   │   ├── stacks.tf
│   │   ├── vault.tf
│   │   └── stacks/
│   ├── ds1/             # ds-1 stacks
│   │   ├── provider.tf
│   │   ├── variables.tf
│   │   ├── stacks.tf
│   │   ├── vault.tf
│   │   └── stacks/
│   └── ds2/             # ds-2 stacks
│       ├── provider.tf
│       ├── variables.tf
│       ├── stacks.tf
│       ├── vault.tf
│       └── stacks/
└── modules/
    └── cf-service/      # unchanged
```

## Portainer Network Management

Portainer manages networks through a **bootstrap-first** pattern:

- **Macvlan** (`docker-servers-net`): created by host bootstrap script (host-specific
  interface + IP slice); Portainer reads and displays but does not own
- **Bridge networks** (`rproxy`, `backend`, `app`, `monitoring`): defined in a
  `network-bootstrap` Portainer stack deployed before any app stack; all app stacks
  reference as `external: true`
- **Stack-local networks**: declared inline in compose, owned by the stack

This keeps network definitions version-controlled in compose files, visible in
Portainer UI, and not fragile to stack deletion order.
