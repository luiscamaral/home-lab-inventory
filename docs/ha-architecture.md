# Homelab HA Architecture

> **Status:** Current as of 2026-04-17. Authoritative for all HA topology.
> Source of truth for service placement: `terraform/portainer/stacks.tf`.
> Cross-host MAC collision fix, Vault auto-unseal, Twingate DNS fix, and
> dockermaster package damage recovery were applied during the
> 2026-04-12/13 recovery session.
>
> **DNS HA migration (Pattern B) completed 2026-04-14/17:** three-node
> pihole trio (pihole-1 LXC + pihole-2 on ds-1 + pihole-3 on NAS) now
> serves all authoritative records for `d.lcamaral.com`, `home`, and
> host-overrides. bind9 retired (`99d51b0`). NAS Portainer endpoint
> switched from Edge Agent to Direct Agent (`9d908bf`) to eliminate
> tunnel flakiness. See the new "DNS tier" section below.

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
| **Nginx reverse proxy** | rproxy (dm), rproxy-2 (ds-1), rproxy-3 (ds-2) | `.28`, `.48`, `.49` | pihole multi-A for `*.d.lcamaral.com`, shared vhosts via NFS |
| **cloudflared tunnel** | cf-tunnel (dm), cf-tunnel-2 (ds-1), cf-tunnel-3 (ds-2) | (bridge) | 3 replicas of tunnel `bologna`, CF load-balances |

**DNS resolution:**

- `*.d.lcamaral.com` → pihole multi-A returns 3 records (`.28`, `.48`, `.49`).
  Clients retry on connect failure. Authoritative records live in
  `pihole/dnsmasq.d/04-d-lcamaral-com.conf` in the repo.
- `*.cf.lcamaral.com` → Cloudflare edge → 3 tunnel replicas → each cloudflared
  forwards to its local `nginx-rproxy` (via the per-host `rproxy` Docker bridge).

**Per-host local stack:**
Each host has a local Docker bridge named `rproxy` with a cloudflared + Nginx
pair. This makes `https://nginx-rproxy:443` resolve to the host-local Nginx,
giving locality and isolation.

### DNS tier — Pi-hole 3-node

| Node | Host | IP | Type |
|---|---|---|---|
| pihole-1 | Proxmox LXC 10000 | `192.168.100.254` (vmbr0) | LXC (hardened) |
| pihole-2 | dockerserver-1 | `192.168.59.50` (SRVAN macvlan) | Terraform-managed Docker |
| pihole-3 | NAS | `192.168.4.236` (home-net macvlan) | Terraform-managed Docker |

- **Pattern B architecture** — clients query piholes as primary DNS (via DHCP
  option), piholes answer authoritatively for owned zones and forward
  unknown/public queries upstream to pfSense Unbound.
- **Authoritative zones on pihole:** `d.lcamaral.com`, `home` (flat TLD),
  host-overrides for `home.lcamaral.com`/`admin.lcamaral.com` (synced
  bidirectionally with pfSense via `scripts/sync-host-overrides.py`).
- **HA via DHCP order:** HOME/SRVAN/IoT scopes hand out
  `[pihole-1, pihole-2, pihole-3, pfSense]` (SRVAN excludes pihole-3
  was the original plan but re-added 2026-04-17 once `FTLCONF_dns_listeningMode=all`
  let it serve cross-subnet queries).
- **HA on the pfSense fallback path:** pfSense Unbound Custom Options has
  `forward-zone` entries for `d.lcamaral.com` and `home` with 3
  `forward-addr` lines, Unbound picks the fastest and fails over on timeout.
- **Records source of truth:** repo files in `pihole/dnsmasq.d/*.conf`
  injected into pihole-2/-3 via Terraform `templatefile()` + Docker Compose
  `configs: content:`; pihole-1 LXC is manual push via `pct` (documented
  in `pihole/README.md`).
- **Gravity/adlist sync:** not HA yet — see "Still-to-do" section.
- **Retired:** bind9 (container `bind-dns-bind9-1` on dm); authority moved
  to piholes on 2026-04-15 (commit `99d51b0`).

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
- **Auto-unseal** via `scripts/vault-auto-unseal/` — a systemd oneshot unit
  runs after `docker.service` on each host, reads the Shamir key from
  `/etc/vault/unseal.key` (mode 600 root-owned), and POSTs it to the local
  vault API. Boot-time reseal is now automatic; no human needed. The unseal
  key is also in macOS Keychain `vault-unseal-key` for manual fallback.

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
| Any pihole node | none — other 2 piholes answer via DHCP list + Unbound multi-addr | auto |
| Nginx `rproxy` on any host | none — pihole multi-A + CF replicas | clients/CF retry other hosts |
| cloudflared on any host | none — CF balances across replicas | auto |
| Combined: dockermaster fully down | degraded — some single-instance services lost (Portainer, registry) but all HA services continue via ds-1/ds-2 + NAS; pihole-2/-3 still serve DNS | manual recovery of singletons |

## Still-to-do / known gaps

- **Registry HA** — replicate images to a second registry
- **Rundeck HA** — supported upstream, deferred
- **pfSense HA** — requires a second pfSense box + CARP
- **Pi-hole gravity sync (ad-block list sync)** — deferred; `orbital-sync`
  1.x targets Pi-hole v5 only, and v2.x (v6 support) has been unreleased
  upstream since 2025-01 with no active development. Gravity DB and
  adlists are currently out of sync between pihole-1/2/3. The authoritative
  DNS records (d.lcamaral.com, home, host-overrides) ARE kept in sync via
  Terraform-injected `configs: content:` blocks, so only the ad-block
  side drifts. Revisit when v6-compatible sync tooling ships, or replace
  with a small custom script that hits Pi-hole v6's Teleporter API.
- **dockermaster latent file damage** — ~81k files missing from the
  2026-04-12 disk shrink (docs, `/usr/src/linux-headers-*`, Perl XS
  modules, plymouth renderers). Boot-critical set was restored by reinstalling
  25 packages. Remainder are mostly cosmetic; fix opportunistically with
  `apt install --reinstall` per-package as symptoms surface. `needrestart`
  is currently broken due to missing `Module/Find.pm`.
- **VM backups (vzdump) were silently failing for 2 months** due to a
  full Synology quota. Fixed: pruned, added ds-1 and ds-2 to the job,
  switched to zstd, retention `keep-daily=1,keep-weekly=1`.

## Session fixes applied 2026-04-12/13

This section captures non-obvious config invariants applied during the
recovery session. Re-read before making structural changes.

### Macvlan cross-host L2 depends on unique shim MACs

All 3 Docker hosts initially derived their `server-net-shim` MAC from
`/etc/machine-id`, which was identical across the three (VM clone artifact).
The result: three hosts with the same shim MAC collided at the switch MAC
table, breaking cross-host macvlan traffic silently. Fixed with:

1. Regenerate `/etc/machine-id` on ds-1 and ds-2.
2. Pin an explicit `MACAddress=` in each host's
   `/etc/systemd/network/10-server-net-shim.netdev` (captured in IaC under
   `hosts/<h>/etc/systemd/network/`). Values: dm `02:00:00:00:00:01`,
   ds-1 `02:00:00:00:00:21`, ds-2 `02:00:00:00:00:2e`.

### Twingate connectors need explicit DNS

Both `twingate-sepia-hornet` (ds-1) and `twingate-golden-mussel` (ds-2)
are macvlan-only Docker containers. Docker writes `127.0.0.11` to their
`resolv.conf` unconditionally, but that address isn't routable on macvlan
networks — the containers silently had no DNS and flapped Offline/Online
with `pubnub-lib` errors. Fixed: `dns: [192.168.48.1, 1.1.1.1]` in both
compose files (commit `c6bb5a1`). Same pattern applies to any future
macvlan-only container that needs outbound public DNS.

### Restart policy on HA stacks

Previously 12 stacks used `restart: on-failure:5` which skipped clean-exit
recovery — any container that exited with code 0 wouldn't come back
automatically after a host reboot. Changed to `restart: unless-stopped`
across all affected stacks (commit `71ca18a`).

### Keycloak DB HA rejoin after long gaps

Bitnami `postgresql-repmgr` has a 60s default `POSTGRESQL_PGCTLTIMEOUT`
that is too short when a standby needs to replay hours of WAL after
rejoining. Both compose files now set `POSTGRESQL_PGCTLTIMEOUT=600`.
Additionally, the current primary has `wal_sender_timeout=0` set via
`ALTER SYSTEM` (persisted in `postgresql.auto.conf` inside the data
volume) to prevent the walsender from terminating during slow catch-up.
See commits `4aa8d6f`, `7172d61`.

## Test plan & evidence

See commit history for live failover tests (grep for `ha-test`):

- Vault: `feat(network): ha-enable nginx vhosts for vault, minio console, prometheus`
- MinIO: same commit, Phase 1 test
- Postgres/Keycloak/Portal: `feat(security): phases 2-4 — postgres + keycloak + portal HA`

Every HA service was tested with explicit node stop → verify data-plane +
control-plane → restart → verify recovery.
