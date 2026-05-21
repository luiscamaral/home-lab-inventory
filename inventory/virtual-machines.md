# Virtual Machine Inventory

## Proxmox Virtual Machines

### Infrastructure Services

#### VM 100 - Omada Controller

- **Status**: ✅ Running
- **CPU**: 2 cores (host)
- **RAM**: 2 GB
- **Storage**: 30 GB SSD
- **Network**: vmbr01 (Management network)
- **OS**: Linux
- **Purpose**: TP-Link Omada SDN Controller
- **Auto-start**: Yes (startup delay: 180s)

#### VM 110 - Laorion

- **Status**: 🔴 Stopped
- **CPU**: 4 cores (host)
- **RAM**: 16 GB
- **Storage**:
  - 90 GB SSD (System)
  - 320 GB (Data, write-through cache)
- **Network**:
  - vmbr1 (Management)
  - vmbr10 (VLAN 10)
- **OS**: Linux
- **Auto-start**: Yes (currently powered off)

#### VM 111 - Rootmaster

- **Status**: 🔴 Stopped
- **CPU**: 2 cores (host)
- **RAM**: 2 GB
- **Storage**:
  - 80 GB SSD (System)
  - 16 GB SSD (Additional)
- **Network**: vmbr10 (VLAN 10)
- **OS**: Linux
- **Auto-start**: Yes (currently powered off)

#### VM 120 - dockermaster (Docker Master)

- **Status**: ✅ Running
- **CPU**: 20 cores (2 sockets × 10 cores, host), pinned to socket 0 (CPUs 0-9,20-29)
- **RAM**: 64 GB
- **Storage**: 196 GB SSD
- **Network**: vmbr28
- **IP**: 192.168.48.44
- **OS**: Ubuntu Linux
- **Purpose**: Control plane — Portainer, Nginx-1, Bind9-primary, vault-1, Docker Registry, cloudflared-1
- **Auto-start**: Yes (startup delay: 30s)

#### VM 123 - dockerserver-1 (short: ds-1)

- **Status**: ✅ Running
- **CPU**: 10 cores (host), pinned to socket 0 (CPUs 0-9,20-29)
- **RAM**: 24 GB
- **Storage**: 120 GB SSD (thin-pool)
- **Network**: vmbr28
- **IP**: 192.168.48.45
- **OS**: Ubuntu Linux (clone of dockermaster)
- **Purpose**: App Plane A — vault-2, GitHub Runner, Twingate A, Calibre, Rundeck, Prometheus, MinIO, Keycloak-1
- **Portainer endpoint ID**: 9
- **Auto-start**: Yes (startup delay: 30s)

#### VM 124 - dockerserver-2 (short: ds-2)

- **Status**: ✅ Running
- **CPU**: 10 cores (host), pinned to socket 1 (CPUs 10-19,30-39)
- **RAM**: 24 GB
- **Storage**: 120 GB SSD (thin-pool)
- **Network**: vmbr28
- **IP**: 192.168.48.46
- **MAC**: bc:24:11:84:bc:16
- **OS**: Ubuntu Linux (clone of dockerserver-1, 2026-04-11)
- **Purpose**: App Plane B — vault-3, Twingate B, Keycloak-2, Ollama, FreeSWITCH, RustDesk, Watchtower
- **Portainer endpoint ID**: 13
- **Portainer agent macvlan IP**: 192.168.59.46
- **Auto-start**: Yes (startup order: 1, delay: 30s)

#### VM 121 - Home Assistant

- **Status**: ✅ Running
- **CPU**: 4 cores (SandyBridge)
- **RAM**: 16 GB
- **Storage**: 32 GB
- **Network**: vmbr205
- **OS**: Linux (UEFI/OVMF)
- **Purpose**: Home automation platform
- **Auto-start**: Yes (startup order: 1)

#### VM 122 - UniFi Controller

- **Status**: ✅ Running
- **CPU**: 2 cores (host)
- **RAM**: 2 GB
- **Storage**: 128 GB (write-through cache)
- **Network**:
  - vmbr010 (disabled)
  - vmbr1 (Management)
- **OS**: Linux
- **Purpose**: UniFi network management
- **Auto-start**: Yes (startup delay: 120s)

### Proxmox LXC Containers

#### LXC 10000 - pihole

- **Status**: ✅ Running
- **CPU**: 4 cores (limit 8)
- **RAM**: 1 GB (512 MB swap)
- **Storage**: 8 GB SSD (thin-pool)
- **Network**: vmbr0, IP 192.168.100.254/24, GW 192.168.100.1
- **OS**: Debian (unprivileged)
- **Auto-start**: Yes (startup order 1)
- **Purpose**: Pi-hole v6.3.3 DNS — authoritative for `*.lab.home` via `pihole.toml` hosts array
- **Search domain**: lab.lcamaral.com

#### LXC 10010 - openclaw

- **Status**: 🔴 Stopped (retired, replaced by hermes 10020)
- **CPU**: 6 cores
- **RAM**: 8 GB (8128 MB)
- **Storage**: 236 GB SSD (thin-pool)
- **Network**: vmbr0, IP 192.168.100.244/24, GW 192.168.100.1
- **OS**: Debian 12 (bookworm)
- **Features**: nesting=1, unprivileged
- **Snapshot**: `initial-installation` (2026-02-26) — used as source for template 9000
- **Purpose (legacy)**: Nginx reverse proxy for openclaw/byte application
- **⚠️ IP conflict**: configured for `192.168.100.244` — same as hermes 10020. Do not start while hermes is running.

#### LXC 10020 - hermes

- **Status**: ✅ Running (since 2026-05-20)
- **CPU**: 6 cores
- **RAM**: 8 GB (8128 MB)
- **Storage**: 236 GB SSD (thin-pool, full clone of base-9000-disk-0)
- **Network**: vmbr0, IP 192.168.100.244/24, GW 192.168.100.1, MAC `BC:24:11:9F:DE:1F`
- **OS**: Debian 12 (bookworm)
- **Features**: nesting=1, unprivileged
- **DNS**: nameserver 192.168.100.254 (pihole), searchdomain lab.lcamaral.com
- **Auto-start**: No (`onboot: 0`)
- **Cloned from**: template `tmpl-debian-devops` (9000) — full clone
- **Post-clone fixes applied**: machine-id regenerated, SSH host keys regenerated, locale `en_US.UTF-8` generated
- **DNS entries (pihole)**: `hermes.lab`, `hermes.lab.home`

#### LXC 102 - hermes (broken, pending cleanup)

- **Status**: 🔴 Stopped (no rootfs — interrupted creation)
- **Note**: Original hermes config, never finished provisioning. Replaced by 10020. Safe to `pct destroy 102`.

### Templates & Testing

#### LXC 9000 - tmpl-debian-devops 📋

- **Status**: 📋 Template (since 2026-05-20)
- **CPU**: 6 cores
- **RAM**: 8 GB (8128 MB)
- **Storage**: `base-9000-disk-0`, 236 GB declared (~1.7 GB used, thin-provisioned)
- **OS**: Debian 12 (bookworm) + dev/ops packages
- **Features**: nesting=1, unprivileged
- **Source**: full clone of `openclaw@initial-installation` snapshot
- **Purpose**: Base template for Debian dev/ops LXCs. Supports both linked and full clones.
- **Usage**: `pct clone 9000 <vmid> --hostname <name>` (linked) or add `--full --storage thin-pool-ssd` for independence.

#### VM 101 - Tiny

- **Status**: 🔴 Stopped
- **CPU**: 4 cores
- **RAM**: 4 GB
- **Storage**: 120 GB SSD
- **Network**: vmbr10
- **OS**: Linux

## Summary

- **Total VMs**: 9 (6 running: 100, 120, 121, 122, 123, 124; 3 stopped: 101, 110, 111)
- **Total LXCs**: 5 entries
  - Running: 10000 pihole, 10020 hermes
  - Stopped: 10010 openclaw
  - Template: 9000 tmpl-debian-devops
  - Broken/empty (pending cleanup): 102 hermes
- **Templates**: 1 LXC (`tmpl-debian-devops` 9000)
- **Last reconciled with live `qm list` / `pct list`**: 2026-05-20
