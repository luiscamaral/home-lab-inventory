# Homelab HA Architecture

> **Status:** Current as of 2026-04-12. Authoritative for all HA topology.
> Source of truth for service placement: `terraform/portainer/stacks.tf`.

## Host roster

| Host | LAN IP | Macvlan (Docker-servers-net) | Primary role |
|---|---|---|---|
| dockermaster (VM 120) | 192.168.48.44 | 192.168.59.1/26 | Control plane + edge + HA peers |
| dockerserver-1 (VM 123) | 192.168.48.45 | 192.168.59.33 | Primary workloads + HA peers |
| dockerserver-2 (VM 124) | 192.168.48.46 | 192.168.59.46 | Workloads + HA peers |

## HA services — active-active

### Edge tier (3 nodes each)

| Component | Instances | IPs | Topology |
|---|---|---|---|
| **Nginx reverse proxy** | rproxy (dm), rproxy-2 (ds-1), rproxy-3 (ds-2) | `.28`, `.48`, `.49` | bind9 multi-A, shared vhosts via NFS |
| **cloudflared tunnel** | cf-tunnel (dm), cf-tunnel-2 (ds-1), cf-tunnel-3 (ds-2) | (bridge) | 3 replicas of tunnel `bologna`, CF load-balances |

**DNS resolution:**

- `*.d.lcamaral.com` → bind9 returns 3 A records (`.28`, `.48`, `.49`).
  Clients retry on connect failure.
- `*.cf.lcamaral.com` → Cloudflare edge → 3 tunnel replicas → each cloudflared
  forwards to its local `nginx-rproxy` (via the per-host `rproxy` Docker bridge).

**Per-host local stack:**
Each host has a local Docker bridge named `rproxy` with a cloudflared + Nginx
pair. This makes `https://nginx-rproxy:443` resolve to the host-local Nginx,
giving locality and isolation.

### Secrets tier — Vault Raft 3-node

| Node | Host | IP | Role |
|---|---|---|---|
| vault-1 | dockermaster | `192.168.59.25` | voter |
| vault-2 | dockerserver-1 | `192.168.59.9` | voter |
| vault-3 | dockerserver-2 | `192.168.59.15` | voter |

- Failure tolerance: 1 (can lose any 1 node)
- Nginx fronts via `upstream vault_cluster { }` with passive health
  (`max_fails=2 fail_timeout=10s`) + `proxy_next_upstream` + `proxy_connect_timeout 2s`
- Vault's built-in request forwarding routes writes to leader from any node

### Object storage — MinIO site replication

| Node | Host | IP | Storage |
|---|---|---|---|
| minio-1 | dockerserver-1 | `192.168.59.17` | NFS (`/nfs/dockermaster/docker/MinIO/minio-data`) |
| minio-2 | dockerserver-2 | `192.168.59.37` | Local disk (`/var/lib/minio-data`) |

- Active-active bidirectional replication (3/3 buckets, 5/5 policies in sync)
- Independent storage — both sites must be gone to lose data
- **S3 API** (`s3.cf.lcamaral.com` → Nginx → upstream `minio_s3 { least_conn }`)
- **Console** (`minio.cf.lcamaral.com` → Nginx → upstream
  `minio_console { hash $cookie_token consistent }`) — cookie-hash sticky
  sessions for login state

### Identity — Keycloak 2-node cluster

| Node | Host | IP | Cluster role |
|---|---|---|---|
| keycloak | dockermaster | `192.168.59.13` | Infinispan peer |
| keycloak-2 | dockerserver-1 | `192.168.59.43` | Infinispan peer |

- **Cluster discovery:** `KC_CACHE=ispn`, `KC_CACHE_STACK=jdbc-ping` —
  JGroups uses the shared DB (`jgroups_ping` table) for peer discovery,
  no etcd/consul
- **Caches replicated:** user sessions, offline sessions, clientSessions,
  login failures, work, actionTokens
- **Nginx** fronts both via
  `upstream keycloak_cluster { hash $cookie_AUTH_SESSION_ID consistent }`
  (sticky sessions minimize cache misses)
- **Failover:** tested both directions — stopping either node leaves auth
  flows serving HTTP 200

### Keycloak DB — PostgreSQL HA (repmgr)

| Node | Host | IP | Storage |
|---|---|---|---|
| keycloak-db-0 | dockermaster | `192.168.59.44` | NFS |
| keycloak-db-1 | dockerserver-1 | `192.168.59.54` | Local disk |

- **Image:** `bitnamilegacy/postgresql-repmgr:17.6.0`
- **Replication:** PostgreSQL streaming replication, managed by repmgr
- **Failover:** automatic via `repmgrd` (promotes standby when primary goes down)
- **Client connection:** Keycloak uses JDBC multi-host URL:

  ```text
  jdbc:postgresql://192.168.59.44:5432,192.168.59.54:5432/keycloak?targetServerType=primary&loadBalanceHosts=false
  ```

  The PG JDBC driver transparently reconnects to whichever node is primary.
- **Failback:** not automatic — a previous primary rejoins as standby after
  repmgr promotes the other.

### Portal — homelab-portal 2-replica stateless

| Instance | Host | IP |
|---|---|---|
| homelab-portal | dockermaster | `192.168.59.18` |
| homelab-portal-2 | dockerserver-1 | `192.168.59.38` |

- Stateless — session state is encrypted cookies (shared `SESSION_SECRET`
  and `SESSION_ENCRYPTION_KEY`)
- Nginx: `upstream homelab_portal { least_conn; }` — no sticky needed
- Both replicas point at Keycloak (different nodes) for OIDC

### Twingate connectors — active-active redundancy

| Connector | Host | IP |
|---|---|---|
| sepia-hornet | dockerserver-1 | `192.168.59.12` |
| golden-mussel | dockerserver-2 | `192.168.59.24` |

- Both connectors register with Twingate cloud; traffic auto-distributed.

## Single-instance services

These are not HA — either by design (stateful single-instance apps) or because
HA is out of scope for the homelab:

| Service | Host | IP | Why single |
|---|---|---|---|
| bind-dns (bind9) | dm | `192.168.59.3` | Internal DNS; pfSense is fallback resolver |
| Docker registry | dm | `192.168.59.16` + rproxy bridge | Single; no HA yet |
| postfix-relay | dm | (rproxy bridge) | Outbound SMTP queue; tolerates brief outages |
| portainer | dm | `192.168.59.2` | Management plane only |
| Prometheus + exporters | ds-1 | host-published `:9090` | Metric store; single TSDB |
| calibre / calibre-web | ds-1 | `.7` / `.6` | SQLite library, inherently single |
| GitHub-runner-homelab | ds-1 | `.4` | CI runner |
| rundeck + postgres-rundeck | ds-1 | `.22` / `.23` | Job scheduler; future HA candidate |
| freeswitch | ds-2 | `.40` | SIP/RTP stateful |
| rustdesk hbbs/hbbr | ds-2 | `.10` / `.11` | Signalling / relay |
| watchtower | per-host | — | Local image updater, not user-facing |

## Proven failure modes tolerated

| Failure | Impact | Recovery |
|---|---|---|
| Any vault node (including leader) | none — cluster stays above quorum | auto, unseal on restart |
| Either minio site | none — other site serves S3 + console | writes during outage sync on rejoin |
| keycloak-db-0 primary | none — keycloak-db-1 auto-promoted | manual failback optional |
| Either keycloak app instance | none — Infinispan cluster survives | auto |
| Either portal replica | none — stateless LB | auto |
| Nginx `rproxy` on any host | none — bind9 multi-A + CF replicas | clients/CF retry other hosts |
| cloudflared on any host | none — CF balances across replicas | auto |
| Combined: dockermaster fully down | degraded — some single-instance services lost (DNS, Portainer, etc.) but all HA services continue via ds-1/ds-2 | manual recovery of singletons |

## Still-to-do / known gaps

- **bind9 HA** — a second bind9 on ds-1 with zone transfer from dm primary
- **Registry HA** — replicate images to a second registry
- **Rundeck HA** — supported upstream, deferred
- **pfSense HA** — requires a second pfSense box + CARP

## Test plan & evidence

See commit history for live failover tests (grep for `ha-test`):

- Vault: `feat(network): ha-enable nginx vhosts for vault, minio console, prometheus`
- MinIO: same commit, Phase 1 test
- Postgres/Keycloak/Portal: `feat(security): phases 2-4 — postgres + keycloak + portal HA`

Every HA service was tested with explicit node stop → verify data-plane +
control-plane → restart → verify recovery.
