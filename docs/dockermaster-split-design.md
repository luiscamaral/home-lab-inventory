# Homelab Multi-Server Split Design

> **✅ COMPLETE (2026-04-12)** — all planned phases executed. Current state is
> in `docs/ha-architecture.md` which supersedes this design doc as the
> authoritative topology reference. This file is retained as the historical
> record of what was planned and why.
>
> **Phases executed:**
>
> - Phase 1: ds-1 provisioned, base migration
> - Phase 2: service migration from dm → ds-1 (calibre, rundeck, Prometheus,
>   GitHub-runner, watchtower, minio, twingate-a)
> - Phase 3: ds-2 provisioned, additional migration (freeswitch, twingate-b,
>   rustdesk-hbbs/hbbr, vault-3, minio-2)
> - Phase 4 (HA hardening, 2026-04-12):
>   - Nginx/cloudflared 3-replica edge HA (rproxy-2 ds-1, rproxy-3 ds-2)
>   - Keycloak 2-node Infinispan cluster (keycloak dm + keycloak-2 ds-1)
>   - Postgres-repmgr HA cluster for keycloak-db (db-0 dm + db-1 ds-1)
>   - homelab-portal 2-replica (dm + ds-1)
>   - Nginx vhosts converted to upstream blocks with cookie-hash sticky
>   - bind9 multi-A records for all HA-backed hostnames
>
> **Deviations from original plan:**
>
> - Keycloak-1 lives on dm (not ds-1); keycloak-2 on ds-1 (not ds-2).
>   PG HA uses db-0/db-1 both on dm/ds-1.
> - Ollama not deployed (dropped from scope).
> - Bind9-secondary on ds-1 not yet implemented (known gap).

**Date**: 2026-04-11 (plan) → 2026-04-12 (execution complete)
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
  clone dockerserver-1 → ds-2 then prune to app-only services
  *(Note: ds-2 was cloned from dockerserver-1, not dockermaster)*
- **NFS mount point** — `/nfs/dockermaster` on all three servers, same NAS export
  (`tnas:/volume2/servers/dockermaster`). No path changes in compose files.
- **Watchtower** — one instance per app server (ds-1, ds-2); removed from dockermaster
  (control-plane containers should not be auto-updated)
- **Vault HA** — 3 Raft voters on dockermaster + ds-1 + ds-2; NAS excluded
  (kernel 4.4 too old for reliable Vault)

## Current State (2026-04-11)

### What Is Running Where

**dockermaster (VM 120)** — still the monolith, migration pending:

| Container | Target |
|-----------|--------|
| portainer | keep on dockermaster |
| rproxy (Nginx-1 + Promtail) | keep on dockermaster |
| cloudflare-tunnel | keep on dockermaster |
| bind-dns (Bind9-primary) | keep on dockermaster |
| registry | keep on dockermaster |
| vault (vault-1, macvlan .25) | keep on dockermaster |
| GitHub-runner-homelab | → move to ds-1 |
| twingate-sepia-hornet (A) | → move to ds-1 |
| twingate-golden-mussel (B) | → move to ds-2 |
| calibre, calibre-web | → move to ds-1 |
| rundeck, postgres-rundeck | → move to ds-1 |
| Prometheus stack | → move to ds-1 |
| minio | → move to ds-1 |
| homelab-portal | → move to ds-1 |
| keycloak, keycloak-db | → move to ds-1 (node A) + ds-2 (node B + PG primary) |
| hbbs, hbbr (RustDesk) | → move to ds-2 |
| freeswitch ⚠️ unhealthy | → move to ds-2 |
| ollama | → move to ds-2 |
| watchtower | → remove from dockermaster |
| postfix-relay | utility — keep or remove (not in target arch) |
| nas-solr, nas-tika | Synology Search indexers — decide keep/move/remove |

**dockerserver-1 (VM 123)** — provisioned, Phase 2 pending:

| Container | Notes |
|-----------|-------|
| portainer-agent (macvlan .34) | permanent |
| vault-2 (macvlan .9) | permanent — Raft follower |

**dockerserver-2 (VM 124)** — provisioned, Phase 3 remaining items pending:

| Container | Notes |
|-----------|-------|
| portainer-agent (macvlan .46) | permanent |
| vault-3 | not yet deployed |

### Vault Cluster State

- vault-1 (dockermaster, 192.168.59.25): leader ✅
- vault-2 (dockerserver-1, 192.168.59.9): follower ✅ — 2-node cluster, no quorum
- vault-3 (dockerserver-2, 192.168.59.15): **not yet deployed** ❌

2-node Raft has no quorum protection — losing either node makes the cluster read-only.
Deploying vault-3 is therefore a prerequisite before extended Phase 2 migration work.

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

## Network Design

### Bridge Networks (per server, host-local)

| Network | Server(s) | Purpose |
|---------|-----------|---------|
| `rproxy` | dockermaster, ds-1 | Nginx ↔ upstream web services |
| `backend` | ds-1 | Rundeck ↔ PG, Keycloak-1 ↔ PG-replica |
| `app` | ds-2 | Keycloak-2 ↔ PG-primary, internal |
| `monitoring` | all three | Prometheus stack, node-exporter, cadvisor |

All bridge networks declared `internal: true`. Created by a `network-bootstrap` stack
deployed first on each server; all application stacks reference them as `external: true`.

### Macvlan Network (`docker-servers-net`)

Same physical subnet on all three servers. Each host creates its own macvlan
attached to the LAN interface (ens19, which is vmbr28 inside the VM).

**Subnet**: 192.168.48.0/20
**IPRange**: 192.168.59.0/26 (divided into per-server slices below)
**Gateway**: 192.168.48.1
**Host auxiliary**: 192.168.59.1 (dockermaster ↔ macvlan bridge)

Creation command per host (run once during bootstrap):

```bash
docker network create \
  --driver macvlan \
  --opt macvlan_mode=bridge \
  --opt parent=ens19 \
  --subnet 192.168.48.0/20 \
  --ip-range 192.168.59.X/28 \
  --gateway 192.168.48.1 \
  --aux-address "host=192.168.59.1" \
  docker-servers-net
```

Replace `X/28` with the server's slice start address.

**Note**: Portainer (and its provider) communicates with agent containers via macvlan
container-to-container paths, not host ports. Agent endpoint URLs must use macvlan IPs
with `tcp://` scheme (e.g. `tcp://192.168.59.34:9001`).

### Cross-Server Communication

Bridge networks are host-local. Cross-server traffic uses macvlan IPs or host-exposed ports.

| Pattern | Example |
|---------|---------|
| macvlan → macvlan | Vault Raft cluster, Bind9 zone transfer |
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
| .22 | Rundeck | dockermaster | moves → ds-1, keeps IP |
| .23 | Rundeck PostgreSQL | dockermaster | moves → ds-1, keeps IP |
| .24 | Twingate B | dockermaster | moves → ds-2, keeps IP |
| .25 | vault-1 | dockermaster | keep |
| .28 | Nginx-1 | dockermaster | keep |
| .40 | FreeSWITCH | dockermaster | moves → ds-2, keeps IP |

### New Assignments

| IP | Container | Server | Notes |
|----|-----------|--------|-------|
| .5 | Docker Registry | dockermaster | NEW — macvlan for cross-server pulls |
| .7 | Nginx-2 | ds-1 | NEW |
| .8 | Bind9-secondary | ds-1 | NEW |
| .9 | vault-2 | ds-1 | ✅ active |
| .14 | MinIO | ds-1 | NEW — was bridge-only |
| .15 | vault-3 | ds-2 | pending deployment |
| .34 | portainer-agent | ds-1 | ✅ active (Portainer endpoint ID 9) |
| .46 | portainer-agent | ds-2 | ✅ active (Portainer endpoint ID 13) |

### Final IP Map by Server

**dockermaster** (slice: .2–.5, .25, .28)

| IP | Container |
|----|-----------|
| 192.168.59.2 | Portainer |
| 192.168.59.3 | Bind9-primary |
| 192.168.59.5 | Docker Registry |
| 192.168.59.25 | vault-1 |
| 192.168.59.28 | Nginx-1 |

**ds-1** (slice: .4, .7–.9, .12, .14, .22–.23, .34)

| IP | Container |
|----|-----------|
| 192.168.59.4 | GitHub Runner |
| 192.168.59.7 | Nginx-2 |
| 192.168.59.8 | Bind9-secondary |
| 192.168.59.9 | vault-2 ✅ |
| 192.168.59.12 | Twingate A |
| 192.168.59.14 | MinIO |
| 192.168.59.22 | Rundeck |
| 192.168.59.23 | Rundeck PostgreSQL |
| 192.168.59.34 | portainer-agent ✅ |

**ds-2** (slice: .10–.11, .15, .24, .40, .46)

| IP | Container |
|----|-----------|
| 192.168.59.10 | RustDesk hbbs |
| 192.168.59.11 | RustDesk hbbr |
| 192.168.59.15 | vault-3 (pending) |
| 192.168.59.24 | Twingate B |
| 192.168.59.40 | FreeSWITCH |
| 192.168.59.46 | portainer-agent ✅ |

**Available for future use**: .6, .16–.21, .26–.27, .29–.33, .35–.39, .41–.45, .47–.62

### Resolved Issues

1. ✅ **vault-1 macvlan** — `vault.yml` updated with `docker-servers-net` + `.25`; applied.
2. ✅ **Standalone leftovers removed** — `elasticsearch`, `lemonldap`, `phpldapadmin`,
   `openldap`, `chisel`, `n8n` stopped and removed from live dockermaster.
3. ✅ **Docker-servers-net on ds-2** — recreated after Docker prune during provisioning;
   uses `--opt parent=ens19`, `--opt macvlan_mode=bridge`, no IP slice restriction.

## Resource Planning

### dockermaster (VM 120 — unchanged)

- **CPU**: 20 vCPU (keep — already provisioned), pinned to socket 0 (CPUs 0-9, 20-29)
- **RAM**: 64 GB (keep — already provisioned)
- **Storage**: 196 GB SSD

After migration, dockermaster will be lightly loaded (6–7 lightweight containers).
Can be right-sized down to 8 vCPU / 16 GB in a future maintenance window if desired.

### dockerserver-1 (VM 123)

- **CPU**: 10 vCPU (host), pinned to socket 0 (CPUs 0-9, 20-29)
- **RAM**: 24 GB
- **Storage**: 120 GB SSD (thin-pool)
- **Network**: vmbr28

### dockerserver-2 (VM 124)

- **CPU**: 10 vCPU (host), pinned to socket 1 (CPUs 10-19, 30-39)
- **RAM**: 24 GB
- **Storage**: 120 GB SSD (thin-pool)
- **Network**: vmbr28
- ⚠️ **Ollama note**: LLM models (~8 GB each) may require a RAM increase to 32 GB
  before deploying Ollama in production. Proxmox allows hot-add memory with balloon driver.

### Proxmox Capacity

| | RAM |
|--|-----|
| Total | 243 GB |
| Currently running (8 VMs) | ~158 GB |
| Available headroom | ~85 GB |
| ds-1 + ds-2 | 48 GB |
| Remaining after split | ~37 GB ✅ |

## Implementation Phases

### Phase 0 — Immediate (complete ✅)

- [x] Vault snapshot path provisioned — NFS snapshots dir created, pre-split manual snap taken
- [x] Vault snapshot automation — moved to Rundeck (Phase 2); ofelia sidecar removed (not HA-safe)
- [x] Drop Chisel, Ansible-observability, LiteLLM — IaC removed, committed
- [x] Stop and remove standalone leftovers on live dockermaster:
  `elasticsearch`, `lemonldap`, `phpldapadmin`, `openldap`, `chisel` — all stopped and removed
- [x] Add vault-1 macvlan IP to `vault.yml` IaC:
  `docker-servers-net` network + `ipv4_address: 192.168.59.25`
- [x] Manual snapshot before any migration work:
  `pre-split-manual.snap` saved to NFS snapshots dir (99K, 2026-04-11)

### Phase 1 — Provision dockerserver-1 (complete ✅)

- [x] Clone VM 120 (dockermaster) → VM 123 in Proxmox
- [x] Boot, set hostname to `dockerserver-1`, change host IP to 192.168.48.45
- [x] pfSense DHCP static map: MAC → 192.168.48.45, DNS `dockerserver-1.srv.lcamaral.com`
- [x] Proxmox VM name set to `dockerserver-1`, affinity pinned to socket 0 (CPUs 0-9,20-29)
- [x] Specs: 10 vCPU / 24 GB RAM (thin-pool 120 GB, trimmed from 196 GB clone)
- [x] Create macvlan (`docker-servers-net`, parent ens19, macvlan bridge mode)
- [x] Register as Portainer endpoint: ID 9, agent at `tcp://192.168.59.34:9001`, type=2
  - Managed via `terraform/portainer/environments.tf`
- [x] Bridge networks present from clone: `rproxy`, `prometheus_back-tier`, `keycloak_keycloak-internal`
- [x] Bring up vault-2 (macvlan .9) — joined vault-1, 2-node Raft active
  - vault-1: leader (192.168.59.25), vault-2: follower (192.168.59.9)

### Phase 1b — Provision dockerserver-2 (infrastructure ready ✅, vault-3 pending)

*Executed out of planned order — ds-2 infrastructure was provisioned before Phase 2 migration.*

- [x] Clone VM 123 (dockerserver-1) → VM 124 in Proxmox
- [x] Boot, set hostname to `dockerserver-2`, change host IP to 192.168.48.46
- [x] pfSense DHCP static map: MAC bc:24:11:84:bc:16 → 192.168.48.46,
  DNS `dockerserver-2.srv.lcamaral.com`
- [x] Proxmox VM name set to `dockerserver-2`, affinity pinned to socket 1 (CPUs 10-19,30-39)
- [x] Specs: 10 vCPU / 24 GB RAM (thin-pool 120 GB)
- [x] Recreate macvlan (`docker-servers-net`, parent ens19, macvlan bridge mode)
- [x] Register as Portainer endpoint: ID 13, agent at `tcp://192.168.59.46:9001`, type=2
  - Managed via `terraform/portainer/environments.tf`
- [x] Docker prune — removed clone artifacts (images, stopped containers, volumes)
- [ ] **Deploy vault-3** (macvlan .15) — join Raft cluster → 3 voters, quorum reached
  - Do this before starting Phase 2 migration

### Phase 2 — Migrate App Services to dockerserver-1 (next)

**Prerequisite**: vault-3 deployed on ds-2 (3-node quorum) before extended migration work.

Migration order (stop on dockermaster, start on ds-1):

1. **Twingate A** (sepia-hornet) — macvlan .12; low-risk, no state
2. **GitHub Runner** — macvlan .4; stop runner, start on ds-1, verify CI
3. **Calibre + Calibre Web** — NFS-backed data; stop on dockermaster, start on ds-1
4. **MinIO** — macvlan .14; verify NFS data path, test bucket access after move
5. **Rundeck + PostgreSQL** — macvlan .22/.23; stop on dockermaster, start on ds-1
6. **Prometheus stack** — bridge `monitoring`; scrape targets update to ds-1 host
7. **homelab-portal** — NFS-backed config; stop on dockermaster, start on ds-1
8. **Nginx-2 + cloudflared-2** — macvlan .7; add second bologna connector to CF tunnel
9. **Bind9-secondary** — macvlan .8; configure zone transfer from dockermaster Bind9
10. **Watchtower (ds-1)** — start after all ds-1 services up; watches ds-1 containers only
11. **Keycloak-1 + PG-replica** — macvlan .13→bridge; streaming replica from dockermaster PG

### Phase 3 — Migrate App Services to dockerserver-2

Services to start on ds-2 (stop on dockermaster first):

1. **Twingate B** (golden-mussel) — macvlan .24; low-risk, no state
2. **RustDesk** (hbbs .10, hbbr .11) — macvlan; stop on dockermaster, start on ds-2
3. **FreeSWITCH** ⚠️ — macvlan .40; currently unhealthy on dockermaster, investigate first
4. **Ollama** — NFS model storage; ensure ds-2 has 24+ GB free RAM for models
5. **Keycloak-2 + PG-primary** — start PG primary on ds-2, then Keycloak-2
6. **Watchtower (ds-2)** — start after all ds-2 services up

### Phase 4 — Slim dockermaster

Remove from dockermaster once confirmed running on ds-1/ds-2:

- Twingate A, Twingate B, GitHub Runner, Watchtower
- Keycloak + PG, Rundeck + PG, RustDesk, FreeSWITCH, Ollama, MinIO, Calibre
- homelab-portal, Prometheus stack

Remaining cleanup decisions:

- **postfix-relay** — not in target arch; decide to keep as utility or remove
- **nas-solr + nas-tika** — Synology Search indexers; decide where these live long-term

Keep on dockermaster (control plane):

- Portainer, Nginx-1 + Promtail, cloudflared-1, Bind9-primary
- Docker Registry, vault-1

### Phase 5 — PostgreSQL Streaming Replication (Keycloak)

1. Configure PG primary on ds-2 for streaming replication
2. Set up PG hot standby on ds-1
3. Verify replication lag: `SELECT * FROM pg_stat_replication;`
4. Document failover runbook: `pg_promote` on ds-1 + update Keycloak-1 connection string

## Terraform Structure (post-split)

```text
terraform/
├── cloudflare/          # unchanged
├── vault/               # unchanged
├── portainer/           # current: all stacks in one module
│   ├── provider.tf
│   ├── variables.tf
│   ├── environments.tf  # ds1 (ID 9) + ds2 (ID 13) registered
│   ├── stacks.tf
│   ├── vault.tf
│   └── stacks/
└── modules/
    └── cf-service/      # unchanged
```

*Future refactor (post-Phase 2)*: split `portainer/` into per-server subdirectories
(`dockermaster/`, `ds1/`, `ds2/`) once stack ownership is clear.

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
