# 🖥️ Server Inventory

## Physical Servers

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
- **Services**:
  - NFS shares for VM storage and backups
  - Shared storage at 192.168.2.50
- **Access**: SSH via `ssh nas`

## Virtual Servers

### Docker Master Server (VM 120)
- **Hostname**: dockermaster
- **Type**: Virtual Machine on Proxmox (VMID 120)
- **OS**: Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel**: Linux 6.8.0-64-generic
- **Hardware**:
  - **CPU**: 20 cores (Intel Xeon E5-2680 v2 @ 2.80GHz virtualized)
  - **RAM**: 62 GB allocated (4.2 GB used, 58 GB available)
  - **Storage**: 192 GB SSD (35% used - 64GB/119GB)
- **Network Configuration**:
  - **Primary IP**: 192.168.48.44/20
  - **Server Network**: 192.168.59.1/26 (macvlan for containers)
  - **Docker Networks**: 5 active bridge networks, 1 macvlan
- **Docker Environment**:
  - **Docker Version**: 28.3.2 (Engine Community)
  - **Docker API**: 1.51
  - **Containerd**: 1.7.27
  - **Running Containers**: 7
  - **Stopped Containers**: 6
  - **Compose Stacks**: 11 available (4 active)
- **NFS Mounts**:
  - `/nfs/calibre` - Calibre library from NAS (6TB volume)
  - `/nfs/dockermaster` - Docker persistent data (1TB volume)
- **Services Hosted**:
  - Calibre Server & Web (E-book library)
  - Rundeck (Job automation)
  - Portainer (Docker management)
  - Bind9 DNS Server
  - Nginx Reverse Proxy
  - PostgreSQL (for Rundeck)
- **Resource Usage**:
  - **CPU**: ~3% average utilization
  - **Memory**: ~3.1 GB used of 62 GB (5%)
  - **Containers**: 13 total (7 running)
- **Access**: SSH via `ssh dockermaster`
