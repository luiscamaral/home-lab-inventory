# Virtual Machines Inventory

## Running VMs

### Docker Master (VM 120)
- **OS**: Ubuntu 24.04.2 LTS
- **CPU**: 20 cores
- **RAM**: 64 GB
- **Storage**: 196 GB on thin-pool-ssd
- **Network**: vmbr28
- **Boot Order**: 2 (30s startup delay)
- **Status**: Running
- **Purpose**: Main Docker container host
- **Key Services**: Docker, Portainer, various containerized applications

### Home Assistant (VM 121)
- **OS**: Home Assistant OS
- **CPU**: 4 cores
- **RAM**: 16 GB
- **Storage**: 32 GB on local-zfs
- **Network**: vmbr205
- **Boot Order**: 1 (first to start)
- **Status**: Running
- **Purpose**: Home automation platform

### k8s-ctrl-1 (VM 210)
- **OS**: Linux (Kubernetes control plane)
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Storage**: 100 GB on thin-pool-ssd
- **Network**: vmbr7
- **Status**: Running
- **Purpose**: Kubernetes control plane node 1

### k8s-worker-1 (VM 211)
- **OS**: Linux (Kubernetes worker)
- **CPU**: 16 cores
- **RAM**: 32 GB
- **Storage**: 200 GB on thin-pool-ssd
- **Network**: vmbr7
- **Status**: Running
- **Purpose**: Kubernetes worker node 1

### k8s-worker-2 (VM 212)
- **OS**: Linux (Kubernetes worker)
- **CPU**: 16 cores
- **RAM**: 32 GB
- **Storage**: 200 GB on thin-pool-ssd
- **Network**: vmbr7
- **Status**: Running
- **Purpose**: Kubernetes worker node 2

### k8s-worker-3 (VM 213)
- **OS**: Linux (Kubernetes worker)
- **CPU**: 16 cores
- **RAM**: 32 GB
- **Storage**: 200 GB on thin-pool-ssd
- **Network**: vmbr7
- **Status**: Running
- **Purpose**: Kubernetes worker node 3

### Windows 11 Pro (VM 201)
- **OS**: Windows 11 Professional
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Storage**: 250 GB on thin-pool-ssd
- **Network**: vmbr7
- **Boot**: OVMF (UEFI)
- **Display**: VirtIO-GPU
- **Status**: Running
- **Purpose**: Windows development/testing environment

## Stopped VMs

### Ubuntu 22.04 Template (VM 100)
- **OS**: Ubuntu 22.04 LTS
- **CPU**: 2 cores
- **RAM**: 2 GB
- **Storage**: 20 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: Template for Ubuntu VMs

### Ubuntu Desktop (VM 101)
- **OS**: Ubuntu Desktop
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Storage**: 50 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: Desktop Linux environment

### Plex Media Server (VM 102)
- **OS**: Ubuntu Server
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Storage**: 50 GB system + NFS media storage
- **Status**: Stopped
- **Purpose**: Media streaming server

### pfSense (VM 103)
- **OS**: pfSense
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 20 GB on local-zfs
- **Network**: Multiple interfaces for routing
- **Status**: Stopped
- **Purpose**: Firewall/Router (testing)

### TrueNAS (VM 104)
- **OS**: TrueNAS CORE
- **CPU**: 4 cores
- **RAM**: 16 GB
- **Storage**: 32 GB system + additional storage pools
- **Status**: Stopped
- **Purpose**: Storage/NAS testing

### OpenWrt (VM 105)
- **OS**: OpenWrt
- **CPU**: 1 core
- **RAM**: 512 MB
- **Storage**: 4 GB on local-zfs
- **Status**: Stopped
- **Purpose**: Router/Network testing

### Kali Linux (VM 106)
- **OS**: Kali Linux
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Storage**: 40 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: Security testing/penetration testing

### Debian 12 (VM 107)
- **OS**: Debian 12 Bookworm
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Storage**: 32 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: General purpose Linux server

### Rocky Linux (VM 108)
- **OS**: Rocky Linux 9
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Storage**: 40 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: RHEL-compatible testing

### AlmaLinux (VM 109)
- **OS**: AlmaLinux 9
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Storage**: 40 GB on thin-pool-ssd
- **Status**: Stopped
- **Purpose**: RHEL-compatible testing

### Windows Server 2022 (VM 200)
- **OS**: Windows Server 2022
- **CPU**: 8 cores
- **RAM**: 16 GB
- **Storage**: 100 GB on thin-pool-ssd
- **Boot**: OVMF (UEFI)
- **Status**: Stopped
- **Purpose**: Windows Server testing/AD lab

## VM Summary Statistics
- **Total VMs**: 18
- **Running**: 7
- **Stopped**: 11
- **Total Allocated CPU Cores**: 110
- **Total Allocated RAM**: 292 GB
- **Primary Storage Pool**: thin-pool-ssd (SSD)
- **Secondary Storage**: local-zfs, NFS mounts