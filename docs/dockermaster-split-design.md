# Dockermaster Split: dockerserver-1 + dockerserver-2 + 3-Node Vault HA

**Status**: Design — pending implementation
**Date**: 2026-04-11
**Branch**: `nas-docker-server`

## Motivation

| Problem | Impact |
|---------|--------|
| dockermaster is a single SPOF | One VM failure takes down all services |
| Vault is single-node Raft | No quorum — unsealed-state loss on any failure |
| Snapshot gap (last: 2025-09-15) | 7 months with no Vault backup (fixed by this branch) |
| 20 vCPU / 62 GB on one VM | Hard to right-size; noisy-neighbour risk |

## Target Architecture

```text
Proxmox Hypervisor (20C/40T, 243 GB RAM)
├── VM 123 — dockerserver-1  (Control Plane)
│   ├── Portainer            (primary, manages all endpoints)
│   ├── Nginx reverse-proxy + Promtail
│   ├── Bind9 DNS            (primary for d.lcamaral.com)
│   ├── Cloudflare Tunnel    (bologna)
│   ├── Twingate A           (sepia-hornet)
│   ├── GitHub Runner
│   ├── Watchtower
│   ├── Docker Registry      (registry.cf.lcamaral.com)
│   ├── Chisel               (TCP tunnel)
│   ├── homelab-portal       (login.cf.lcamaral.com)
│   └── vault-1              (Raft leader candidate)
│
├── VM 124 — dockerserver-2  (Application Plane)
│   ├── Calibre + Calibre Web
│   ├── Rundeck + PostgreSQL
│   ├── Prometheus stack     (prometheus, node-exporter, alertmanager, cadvisor)
│   ├── MinIO                (S3 object storage)
│   ├── Ollama               (LLM inference)
│   ├── FreeSWITCH           (VoIP/SIP)
│   ├── Keycloak + PostgreSQL
│   ├── RustDesk Server
│   ├── n8n                  (workflow automation)
│   ├── Twingate B           (golden-mussel)
│   └── vault-2              (Raft voter)
│
└── Synology NAS             (existing Edge endpoint)
    ├── portainer-agent      (Edge)
    ├── vault-3              (Raft voter — lightweight)
    ├── netbootxyz
    ├── paperlessngx
    └── speedtest
```

## Vault Raft HA Cluster

### Quorum Math

- 3 voters → quorum = 2 — survives any single-node failure
- Automatic leader election, no manual intervention on node loss
- CE-compatible — no Enterprise features needed

### Failure Scenarios

| Failed node | Quorum | Leader |
|-------------|--------|--------|
| vault-1 (ds-1) | ds-2 + NAS = 2/3 ✅ | ds-2 or NAS elected |
| vault-2 (ds-2) | ds-1 + NAS = 2/3 ✅ | ds-1 or NAS |
| vault-3 (NAS) | ds-1 + ds-2 = 2/3 ✅ | ds-1 or ds-2 |
| ds-1 + ds-2 | NAS alone = 1/3 ❌ | No quorum, reads only |

### Network Requirements

All 3 nodes must reach each other on TCP 8200 (API) and 8201 (cluster).

| Pair | Current state | Action needed |
|------|--------------|---------------|
| ds-1 ↔ ds-2 | Same Proxmox VLAN (vmbr28) | None — direct L2 |
| ds-1 ↔ NAS | TCP works (NFS via 192.168.2.50) | Open NAS firewall: TCP 8200, 8201 |
| ds-2 ↔ NAS | Assumed TCP works (same path) | Open NAS firewall: TCP 8200, 8201 from ds-2 IP |

### IP Planning

IPs TBD once VMs are created.

| Node | Host IP | Vault macvlan IP | Cluster port |
|------|---------|-----------------|--------------|
| vault-1 (ds-1) | 192.168.48.45 (TBD) | 192.168.59.X | 8201 |
| vault-2 (ds-2) | 192.168.48.46 (TBD) | 192.168.59.Y | 8201 |
| vault-3 (NAS) | 192.168.2.50 (existing) | 192.168.4.235 | 8201 |

### config.hcl Template (per node)

```hcl
storage "raft" {
  path    = "/vault/raft"
  node_id = "vault-N"   # vault-1, vault-2, vault-3

  retry_join {
    leader_api_addr = "http://VAULT1_IP:8200"
  }
  retry_join {
    leader_api_addr = "http://VAULT2_IP:8200"
  }
  retry_join {
    leader_api_addr = "http://VAULT3_IP:8200"
  }
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://THIS_NODE_IP:8200"
cluster_addr = "http://THIS_NODE_IP:8201"

ui = true
```

### Bootstrap Procedure (New Cluster)

1. Start all 3 nodes simultaneously (retry_join is patient, ~5 min window)
2. `vault operator init` on any one node — generates root token + unseal keys
3. Store root token and unseal key in macOS Keychain short-term
4. `vault operator unseal` on all 3 nodes
5. Verify: `vault operator raft list-peers` → 3 voters

### Migration from Existing Single-Node

```bash
# Take snapshot before any migration
vault operator raft snapshot save /nfs/dockermaster/docker/vault/vault/snapshots/pre-ha-manual.snap
# Stop old vault-1 after ds-1 and ds-2 nodes are up and joined
# Restore snapshot on new cluster leader to carry all secrets forward
```

## Resource Planning

### dockerserver-1 (Control Plane, VM 123)

- **CPU**: 8 vCPUs
- **RAM**: 16 GB
- **Storage**: 100 GB SSD (thin-pool-ssd)
- **Network**: vmbr28 (same as current dockermaster)
- **Justification**: Nginx, Bind9, cloudflare-tunnel are all sub-100 MB RSS

### dockerserver-2 (Application Plane, VM 124)

- **CPU**: 12 vCPUs
- **RAM**: 32 GB
- **Storage**: 200 GB SSD (thin-pool-ssd)
- **Network**: vmbr28
- **Justification**: Ollama loads models into RAM (~8 GB/model); Keycloak + PG + MinIO need headroom

### Proxmox Capacity Check

- Total RAM: 243 GB
- Currently allocated (running VMs): ~195 GB
- ds-1 needs: 16 GB ✅
- ds-2 needs: 32 GB ✅
- dockermaster freed on decommission: 64 GB
- Net change: +48 GB consumed, +64 GB freed → positive headroom

## Open Questions Before Implementation

1. **Clone or fresh provision?**
   - Clone dockermaster → ds-1: faster, carries over Docker state + NFS mounts
   - Fresh Ubuntu → ds-1: cleaner, no legacy cruft
   - Recommendation: clone for ds-1 then prune ds-2 services; fresh for ds-2

2. **VMID assignments**: 123 and 124 appear free — confirm with `qm list` on proxmox.

3. **NFS mount naming**: `/nfs/dockermaster` is tied to the current VM hostname.
   Rename to `/nfs/docker-data` on both new servers or use per-server paths.

4. **Terraform workspace split**: Keep one `portainer/` workspace or split?
   - Recommendation: `terraform/portainer/ds1/` and `terraform/portainer/ds2/`
     sharing provider config via a common module

5. **Bind9 SPOF**: DNS goes down if ds-1 fails. Options:
   - Secondary Bind9 as slave on NAS (simplest)
   - Secondary Bind9 on ds-2
   - Recommendation: NAS — already managed by Portainer Edge

6. **Portainer endpoints**: ds-1 inherits dockermaster endpoint ID 3,
   or new endpoints are registered and dockermaster decommissioned cleanly.

## Implementation Phases

### Phase 0 — Immediate (done in this commit)

- [x] Vault snapshot automation via ofelia — daily at 02:00, 30-day retention
- [ ] Take manual snapshot now: `vault operator raft snapshot save
  /nfs/dockermaster/docker/vault/vault/snapshots/pre-split-manual.snap`

### Phase 1 — Provision dockerserver-1 (VM 123)

1. Create VM 123 on Proxmox (clone dockermaster or Ubuntu 24.04 fresh)
2. Assign host IP, configure macvlan (Docker-servers-net)
3. Install Docker CE 28.x
4. Mount NFS: `tnas:/volume2/servers/dockermaster` → `/nfs/docker-data`
5. Register as Portainer endpoint
6. Deploy infrastructure stacks via Terraform `portainer/ds1/`

### Phase 2 — Migrate Control-Plane Services to ds-1

- Stop services on dockermaster, start on ds-1 one by one
- Cutover DNS (Bind9), then Nginx, then Cloudflare tunnel
- Vault single-node running on ds-1 (still standalone at this point)

### Phase 3 — Provision dockerserver-2 (VM 124)

1. Create VM 124, fresh Ubuntu 24.04
2. Configure Docker, macvlan, NFS
3. Register as Portainer endpoint
4. Deploy application stacks via Terraform `portainer/ds2/`
5. Start vault-2, join to vault-1 (2-node — not yet quorum-safe)

### Phase 4 — Add vault-3 on NAS

1. Open NAS firewall: TCP 8200/8201 from ds-1 and ds-2 IPs
2. Deploy vault-3 container via Portainer Edge (NAS endpoint 6)
3. Join to cluster → 3 voters, quorum reached
4. Verify: `vault operator raft list-peers`

### Phase 5 — Decommission dockermaster

1. Confirm all services green on ds-1 / ds-2 / NAS
2. Take final snapshot
3. Remove dockermaster Portainer endpoint (ID 3)
4. Stop VM 120, archive or delete

## Terraform Structure (post-split)

```text
terraform/
├── cloudflare/          # unchanged
├── vault/               # unchanged
├── portainer/
│   ├── ds1/             # dockerserver-1 stacks
│   │   ├── provider.tf
│   │   ├── variables.tf
│   │   ├── stacks.tf    # control-plane stacks
│   │   ├── vault.tf
│   │   └── stacks/
│   └── ds2/             # dockerserver-2 stacks
│       ├── provider.tf
│       ├── variables.tf
│       ├── stacks.tf    # application stacks
│       ├── vault.tf
│       └── stacks/
└── modules/
    └── cf-service/      # unchanged
```

## Snapshot Automation (Phase 0 — implemented)

Added to `terraform/portainer/stacks/vault.yml`:

- **Ofelia** sidecar reads the vault container's labels
- **Schedule**: daily at 02:00 (`0 0 2 * * *` — 6-field cron with seconds)
- **Retention**: 30 days (`find ... -mtime +30 -delete` runs at 02:30)
- **Storage**: `/nfs/dockermaster/docker/vault/vault/snapshots/` (NFS-backed)
- **Command runs inside vault container** — inherits VAULT\_ADDR + VAULT\_TOKEN env vars

To apply: `terraform -chdir=terraform/portainer apply -target=portainer_stack.vault`
