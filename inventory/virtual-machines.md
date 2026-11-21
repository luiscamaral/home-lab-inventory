# Virtual Machine Inventory

Live state and allocations checked 2026-11-18, 16:59–17:04 UTC.
Sources: [assessment evidence E3, E6, and E12](../docs/operations/2026-11-18-proxmox-assessment.md#evidence-index).
Application roles and IP notes remain historical unless the assessment confirms them.

## Proxmox Virtual Machines

### Infrastructure Services

#### VM 100 - Omada Controller

- **Status**: ✅ Running
- **CPU**: 2 cores (host)
- **RAM**: 4 GiB maximum, 2 GiB balloon minimum
- **Storage**: 30 GiB SSD
- **Network**: vmbr01 (Management network)
- **OS**: Ubuntu 24.04.5 LTS
- **Purpose**: TP-Link Omada SDN Controller
- **Auto-start**: Yes (startup delay: 180s)

#### VM 110 - Laorion, historical record

- **Status**: Not present in the live VM list. Allocations below are historical.
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
- **CPU**: 4 cores (host)
- **RAM**: 8096 MiB maximum, 2048 MiB balloon minimum
- **Storage**:
  - 80 GB SSD (System)
  - 16 GB SSD (Additional)
- **Network**: vmbr10 (VLAN 10)
- **OS**: Not queried while stopped
- **Auto-start**: No explicit onboot setting

#### VM 120 - dockermaster (Docker Master)

- **Status**: ✅ Running
- **CPU**: 8 cores (one socket, host), pinned to socket 0 (CPUs 0-9,20-29)
- **RAM**: 16256 MiB maximum, 4192 MiB balloon minimum
- **Storage**: 120 GiB SSD. LVM mapping warning needs review.
- **Network**: vmbr28
- **IP**: 192.168.48.44
- **OS**: Ubuntu 24.04.4 LTS
- **Purpose**: Control plane, Portainer, Nginx-1, Bind9-primary, vault-1, Docker Registry, cloudflared-1
- **Auto-start**: Yes (startup delay: 30s)

#### VM 123 - dockerserver-1 (short: ds-1)

- **Status**: ✅ Running
- **CPU**: 10 cores (host), pinned to socket 0 (CPUs 0-9,20-29)
- **RAM**: 24 GB
- **Storage**: 120 GB SSD (thin-pool)
- **Network**: vmbr28
- **IP**: 192.168.48.45
- **OS**: Ubuntu 24.04.4 LTS (clone of dockermaster)
- **Purpose**: App Plane A, vault-2, GitHub Runner, Twingate A, Calibre, Rundeck, Prometheus, MinIO, Keycloak-1
- **Portainer endpoint ID**: 9
- **Auto-start**: Yes (startup delay: 30s)

#### VM 124 - dockerserver-2 (short: ds-2)

- **Status**: ✅ Running
- **CPU**: 10 cores (host), pinned to socket 1 (CPUs 10-19,30-39)
- **RAM**: 48 GiB
- **Storage**: 120 GiB SSD (thin-pool)
- **Network**: vmbr28
- **IP**: 192.168.48.46
- **MAC**: bc:24:11:84:bc:16
- **OS**: Ubuntu 24.04.4 LTS (clone of dockerserver-1, 2026-04-11)
- **Purpose**: App Plane B — vault-3, Twingate B, Keycloak-2, FreeSWITCH, RustDesk, Watchtower
- **Portainer endpoint ID**: 13
- **Portainer agent macvlan IP**: 192.168.59.59. The old .46 address collided with otel-collector, then .42 with pihole-exporter-2.
  Moved 2026-11-05.
- **Portainer agent MAC**: Not pinned. Docker assigns a random MAC on recreation because the compose file sets none.
- **Auto-start**: Yes (startup order: 1, delay: 30s)

#### VM 121 - Home Assistant

- **Status**: ✅ Running
- **CPU**: 4 cores (host)
- **RAM**: 16 GiB
- **Storage**: 64 GiB
- **Network**: vmbr205
- **OS**: Home Assistant OS 18.4 (UEFI/OVMF)
- **Purpose**: Home automation platform
- **Auto-start**: Yes (startup order: 2)

#### VM 122 - UniFi Controller

- **Status**: ✅ Running
- **CPU**: 2 cores (x86-64-v2-AES)
- **RAM**: 8 GiB maximum, 2 GiB balloon minimum
- **Storage**: 128 GB (write-through cache)
- **Network**:
  - net0 vmbr010 (HOME VLAN, `link_down=1` / disabled)
  - net1 vmbr01 (ADMIN, untagged/eno1). Historical IP: `192.168.32.41`.
    Previously on vmbr1 (tagged-VID1/eno2). Re-homed 2026-06-26 after the switch24a Omada rebuild.
- **OS**: Ubuntu 20.04.6 LTS. Standard support ended 2025-05-31. Extended support status was not checked.
- **Purpose**: UniFi network management
- **Auto-start**: Yes (startup delay: 120s)

### Proxmox LXC Containers

#### LXC 10000 - pihole

- **Status**: ✅ Running
- **CPU**: 4 cores (limit 8)
- **RAM**: 1 GB (512 MB swap)
- **Storage**: 8 GB SSD (thin-pool)
- **Network**: vmbr0, IP 192.168.100.254/24, GW 192.168.100.1
- **OS**: Debian 12 (unprivileged), verified through a read-only container command
- **Auto-start**: Yes (startup order 1)
- **Purpose**: Pi-hole v6.3.3 DNS, authoritative for `*.lab.home` via `pihole.toml` hosts array
- **Search domain**: lab.lcamaral.com

#### LXC 10010 - openclaw, historical record

- **Status**: Not present in the live container list. Retired and replaced by hermes 10020.
  The configuration below is historical.
- **CPU**: 6 cores
- **RAM**: 8 GB (8128 MB)
- **Storage**: 236 GB SSD (thin-pool)
- **Network**: vmbr0, IP 192.168.100.244/24, GW 192.168.100.1
- **OS**: Debian 12 (bookworm)
- **Features**: nesting=1, unprivileged
- **Snapshot**: `initial-installation` (2026-02-26), used as source for template 9000
- **Purpose (legacy)**: Nginx reverse proxy for openclaw/byte application
- **Historical IP conflict**: Used `192.168.100.244`, the same address as hermes 10020.
  Check address ownership before any recovery.

#### LXC 10020 - hermes

- **Status**: 🔴 Stopped at the 2026-11-18 check
- **CPU**: 6 cores
- **RAM**: 8 GB (8128 MB)
- **Storage**: 236 GB SSD (thin-pool, full clone of base-9000-disk-0)
- **Network**: vmbr0, IP 192.168.100.244/24, GW 192.168.100.1, MAC `BC:24:11:9F:DE:1F`
- **OS**: Debian 12 (bookworm)
- **Features**: nesting=1, unprivileged
- **DNS**: nameserver 192.168.100.254 (pihole), searchdomain lab.lcamaral.com
- **Auto-start**: No (`onboot: 0`)
- **Cloned from**: template `tmpl-debian-devops` (9000), full clone
- **Post-clone fixes applied**: machine-id regenerated, SSH host keys regenerated, locale `en_US.UTF-8` generated
- **DNS entries (pihole)**: `hermes.lab`, `hermes.lab.home`

#### VM 130 - lab-router

- **Status**: 🔴 Stopped
- **CPU**: 2 cores (host)
- **RAM**: 2 GiB
- **Storage**: 8 GiB SSD, plus cloud-init disk
- **Network**: vmbr30, vmbr28, vmbr10, vmbr0
- **OS**: Not queried while stopped
- **Auto-start**: No explicit onboot setting

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

- **Total VMs**: 9. Six running: 100, 120, 121, 122, 123, 124. Three stopped: 101, 111, 130.
- **Total live LXC entries**: 3
  - Running: 10000 pihole
  - Stopped: 10020 hermes
  - Template: 9000 tmpl-debian-devops
- **Historical entries absent from live lists**: VM 110 and LXC 10010
- **Templates**: 1 LXC (`tmpl-debian-devops` 9000)
- **Last reconciled with live `qm list` / `pct list`**: 2026-11-18
