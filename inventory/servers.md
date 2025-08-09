# Physical Servers Inventory

## Proxmox Hypervisor
- **Hardware**: Dell PowerEdge (or similar enterprise server)
- **CPU**: 2x Intel Xeon E5-2680 v2 @ 2.80GHz (20 cores, 40 threads total)
- **RAM**: 243 GB ECC DDR3
- **Storage**:
  - Local: System storage
  - thin-pool-ssd: 1.76 TB SSD storage pool
  - hdd-pool: 1.09 TB HDD storage pool
  - NFS mounts to NAS for backups and ISO storage
- **Network Interfaces**:
  - Management: 192.168.32.61/27
  - VM Bridge: 192.168.7.10/20
  - Multiple VLANs configured
- **OS**: Debian 12 (bookworm) with Proxmox VE 8.3.5
- **Kernel**: 6.11.0-1-pve
- **Services Running**:
  - Proxmox VE management
  - KVM/QEMU virtualization
  - ZFS storage management
  - Docker Engine 27.5.0
  - NFS client for NAS connectivity
- **Purpose**: Main virtualization host for home lab infrastructure
- **Uptime**: 3 days, 19:21 (as of last check)

## NAS Server (Synology)
- **Model**: Synology NAS (specific model TBD)
- **Storage**: Multiple TB (exact capacity TBD)
- **Services**:
  - SMB/CIFS file sharing
  - NFS exports for VM storage
  - Backup storage for Proxmox VMs
  - Docker container persistent storage
  - Media library storage
- **Network**: Accessible via `ssh nas`
- **Shares Mounted on Other Systems**:
  - `/mnt/pve/nfs-backup` on Proxmox
  - `/mnt/pve/nfs-vms` on Proxmox
  - `/nfs/*` mounts on Docker Master

## Network Infrastructure
- **VLANs Configured**:
  - VLAN 28: VM network segment
  - VLAN 205: Home Assistant network
  - VLAN 59: Docker macvlan network (192.168.59.0/26)
- **Primary Gateway**: 192.168.7.1
- **DNS Servers**: 
  - Primary: 192.168.59.53 (Bind9 container)
  - Secondary: 192.168.7.1