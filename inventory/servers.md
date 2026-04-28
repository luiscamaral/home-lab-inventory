# 🖥️ Server Inventory

## Physical Servers

### pfSense — Main Router & Gateway

- **Hostname**: `pfsense.admin.lcamaral.com` (short: `pfsense`)
- **Role**: Main router, firewall, DNS resolver, DHCP, ACME CA, HAProxy edge, dual-WAN gateway
- **OS**: pfSense Plus **26.03-RELEASE** (build `20260401-1720`)
- **Kernel**: FreeBSD 16.0-CURRENT (`plus-RELENG_26_03-n256531`)
- **Hardware**:
  - **CPU**: Intel Core i3-N305 (8 cores, Alder Lake-N)
  - **RAM**: 16 GB
  - **Storage**: ZFS pool `pfSense`, 408 GB usable, 5 boot environments
  - **NICs**: 2× 10GbE SFP+ (`ix0`/`ix1`) + 4× 2.5GbE (`igc0`–`igc3`)
  - **Vendor OUI**: `a8:b8:e0` (Netgate) — likely Netgate 8200 (unconfirmed)
- **Network Configuration**:
  - **WAN1** (`igc0`): `192.168.28.3/24` — Google Fiber (primary)
  - **WAN2** (`igc1`): `192.168.12.2` + `192.168.12.32/24` — backup ISP
  - **ADMIN** (`igc3`): `192.168.32.33/27` — management subnet
  - **LAN trunk** (`ix0`, 10GbE) carries VLANs:
    - VLAN 10 **HOME**: `192.168.0.0/20` gw `192.168.4.1`
    - VLAN 28 **SRVAN**: `192.168.48.0/20` gw `192.168.48.1` (Docker macvlan)
    - VLAN 105 **GUEST**: `192.168.128.0/24` gw `192.168.128.1`
    - VLAN 205 **IoT**: `192.168.16.0/24` + ULA `fc00:1cd::/64` gw `192.168.16.1`
  - **Dual-WAN failover group**: `WAN1 GoogleFiber Preferred` (tier 1: WAN1, tier 2: WAN2, trigger: downloss)
- **Installed Packages**: Avahi, Cron, LADVD, Nexus, RESTAPI, Service_Watchdog,
  Shellcmd, acme, bandwidthd, haproxy, iperf, nmap, node_exporter,
  pfBlockerNG, sudo
- **Services Hosted**:
  - Unbound DNS resolver + DNS-over-TLS (853) on all VLANs (with DHCP lease integration)
  - ISC `dhcpd` DHCP server
  - HAProxy (LAN TLS edge on `192.168.4.1:443` and `192.168.48.1:443`)
  - ACME/LetsEncrypt issuer for `*.d.lcamaral.com`, `home.lcamaral.com`, `*.home.lcamaral.com`
  - pfBlockerNG (IP + DNS blocklists)
  - `node_exporter` on `192.168.4.1:9100` — Prometheus scrape target
  - NTP server for all LAN VLANs
  - DynDNS → DreamHost (updates `wan1`/`wan2`/`homelab`/`hbbs`/`hbbr`.home.lcamaral.com)
- **Access**: SSH via `ssh pfsense` (key-based, no username / password, port 3220)
- **Web GUI**: `https://pfsense.home.lcamaral.com`
- **REST API**: `https://pfsense.home.lcamaral.com/api/v2` (token from Keychain `pfsense-api-token`)
- **Full reference**: See `docs/network/pfsense.md` and `docs/network/pfsense-api.md`

### Proxmox Hypervisor

- **Hostname**: proxmox
- **OS**: Debian GNU/Linux 12 (bookworm)
- **Kernel**: Linux 6.8.12-9-pve
- **Proxmox Version**: 8.3.5
- **Hardware**:
  - **CPU**: 2x Intel Xeon E5-2680 v2 @ 2.80GHz (20 cores / 40 threads total)
  - **RAM**: 243 GB
  - **Architecture**: x86_64
- **Network Configuration**:
  - **Management IP**: 192.168.32.61/27 (vmbr01)
  - **Secondary IP**: 192.168.32.62/27 (vmbr1)
  - **VLAN 10 IP**: 192.168.7.10/20 (vmbr10) - MTU 9000
  - **Secondary VLAN 10 IP**: 192.168.7.11/20 (vmbr010)
  - **Network Bridges**: vmbr01, vmbr1, vmbr10, vmbr010, vmbr28, vmbr205
- **Storage Configuration**:
  - **local**: 34GB total (37% used) - Root filesystem
  - **local-lvm**: 44GB LVM thin pool (0% used)
  - **thin-pool-ssd**: 1.76TB SSD thin pool (41% used)
  - **hdd-pool**: 1.09TB HDD LVM (4% used)
  - **pve-servers-shared**: 6TB NFS mount from NAS (95% used)
  - **pve-backups**: 6TB NFS mount from NAS (95% used)
- **Virtual Machines**: 18 total (7 running, 11 stopped)
- **Services**: Proxmox VE virtualization platform
- **Access**: SSH via `ssh proxmox`

### NAS Server

- **Type**: Synology NAS
- **Network Interfaces**:
  - `eth0`: 192.168.0.50
  - `bond0.10`: 192.168.1.50
  - `eth4.10`: 192.168.2.50 (NFS storage interface)
- **Hardware**:
  - **CPU**: x86_64 / 4 CPUs
  - **RAM**: 7.7 GiB
  - **Kernel**: 4.4.302+
- **Storage**:
  - `/volume2`: 25TB total, 6.7TB free, btrfs filesystem
- **Docker Environment** (Synology Container Manager):
  - **Docker Binary**: `/var/packages/ContainerManager/target/usr/bin/docker`
  - **Docker Version**: 24.0.2 (API 1.43)
  - **Docker Compose**: v2.20.1
  - **Docker Socket**: `/var/run/docker.sock` (group: `docker`)
  - **Docker Root**: `/volume2/@docker`
  - **Storage Driver**: btrfs
  - **containerd**: v1.7.1
- **Portainer Integration**:
  - **Mode**: Edge Agent (outbound WebSocket to Portainer at `ws://192.168.59.2:8000`)
  - **Endpoint ID**: 6 (name: "nas")
  - **Agent Image**: `portainer/agent:2.39.1`
  - **Credentials**: `secret/homelab/portainer-nas-agent` in Vault
  - **Note**: NAS is not directly reachable from dockermaster (different subnets). Edge Agent reverses the connection.
- **Services**:
  - NFS shares for VM storage and backups
  - Docker containers via Portainer Edge (4 active stacks — see `docker-containers.md`)
- **Access**: SSH via `ssh nas`

## Virtual Servers

> **HA topology:** Each VM hosts a slice of the active-active HA setup. See
> `docs/ha-architecture.md` for the full picture.

### dockermaster (VM 120) — control plane + edge

- **Hostname**: dockermaster
- **Type**: Virtual Machine on Proxmox (VMID 120)
- **OS**: Ubuntu 24.04 LTS
- **Hardware**:
  - **CPU**: 8 cores (reduced from 6 → 8 on 2026-04-12)
  - **RAM**: 62 GB
  - **Storage**: 120 GB SSD (shrunk from 196GB → 120GB on 2026-04-12)
- **Network**:
  - **LAN IP**: 192.168.48.44/20
  - **Macvlan gateway**: 192.168.59.1/26 (host alias for `docker-servers-net`)
  - **Macvlan shim MAC**: `02:00:00:00:00:01` (explicit in
    `hosts/dockermaster/etc/systemd/network/10-server-net-shim.netdev` —
    see task #31)
  - **machine-id**: `2bd69dbe597b47edb0bbc1e571c208bf` (the original; ds-1
    and ds-2 were cloned from this host and regenerated theirs on
    2026-04-13)
- **Docker**: 28.3.2, systemd cgroup driver
- **NFS Mounts**:
  - `/nfs/calibre` — Calibre library (legacy mount, served from NAS)
  - `/nfs/dockermaster` — Persistent data, registry, configs
- **Services Hosted** (12 containers):
  - **Edge tier (HA 1/3):** rproxy (`.28`), cloudflare-tunnel-cloudflare-1, reverse-proxy-promtail-1
  - **Auth tier:** keycloak (`.13`, HA 1/2), keycloak-db-0 (`.44`, PG HA primary), homelab-portal (`.18`, HA 1/2)
  - **Backing:** vault (`.25`, raft 1/3), bind-dns-bind9-1 (`.3`), registry (`.16`), postfix-relay
  - **Management:** portainer (`.2`), watchtower
- **Access**: SSH via `ssh dockermaster`

### dockerserver-1 (VM 123) — primary workloads + HA peers

- **Hostname**: dockerserver-1
- **Type**: Virtual Machine on Proxmox (VMID 123)
- **OS**: Ubuntu 24.04 LTS
- **Hardware**:
  - **CPU**: 8 cores
  - **RAM**: 24 GB
  - **Storage**: 120 GB SSD
- **Network**:
  - **LAN IP**: 192.168.48.45/20
  - **Macvlan**: 192.168.59.33 (host alias in `docker-servers-net`)
  - **Macvlan shim MAC**: `02:00:00:00:00:21` (explicit, see task #31)
  - **machine-id**: `de152d98902944208fb3571dd969c3a9` (regenerated
    2026-04-13 — was identical to dm's before; caused shim MAC collision)
- **Docker**: Latest CE, Portainer agent endpoint ID 9
- **NFS Mounts**:
  - `/nfs/dockermaster` — Shared Docker persistent data via NFS
  - `/nfs/calibre` — Calibre library (NAS export added 2026-04-12)
- **Services Hosted** (21 containers):
  - **Edge tier (HA 2/3):** rproxy-2 (`.48`), cloudflare-tunnel-2 (local rproxy bridge)
  - **Auth tier:** keycloak-2 (`.43`, Infinispan peer), keycloak-db-1 (`.54`, PG HA standby), homelab-portal-2 (`.38`)
  - **HA backing:** vault-2 (`.9`, raft 2/3), minio (`.17`, site replication 1/2), twingate-sepia-hornet (`.12`)
  - **Workloads:** calibre (`.7`) + calibre-web (`.6`),
    GitHub-runner-homelab (`.4`), rundeck + postgres-rundeck (`.22`/`.23`)
  - **Monitoring:** Prometheus + node-exporter + snmp-exporter +
    alertmanager + cadvisor (host-published port 9090)
  - **Ancillary:** portainer-agent (`.34`), watchtower
- **Access**: SSH via `ssh dockerserver-1`

### dockerserver-2 (VM 124) — workloads + HA peers

- **Hostname**: dockerserver-2
- **Type**: Virtual Machine on Proxmox (VMID 124, cloned from VM 123)
- **OS**: Ubuntu 24.04 LTS
- **Hardware**:
  - **CPU**: 8 cores
  - **RAM**: 24 GB
  - **Storage**: 120 GB SSD (local for MinIO site replication)
- **Network**:
  - **LAN IP**: 192.168.48.46/20
  - **Macvlan**: 192.168.59.46 (host alias)
  - **Macvlan shim MAC**: `02:00:00:00:00:2e` (explicit, see task #31)
  - **machine-id**: `3b8d239a029a4afbb7cb0e562e8b407f` (regenerated
    2026-04-13)
- **Docker**: Latest CE, Portainer agent endpoint ID 13
- **NFS Mounts**:
  - `/nfs/dockermaster` — Shared Docker persistent data via NFS
- **Services Hosted** (9 containers):
  - **Edge tier (HA 3/3):** rproxy-3 (`.49`), cloudflare-tunnel-3 (local rproxy bridge)
  - **HA backing:** vault-3 (`.15`, raft 3/3), minio-2 (`.37`, site replication 2/2, local disk)
  - **Workloads:** twingate-golden-mussel (`.24`), freeswitch (`.40`), rustdesk hbbs (`.10`), rustdesk hbbr (`.11`)
  - **Ancillary:** portainer-agent (`.46`)
- **Access**: SSH via `ssh dockerserver-2`
