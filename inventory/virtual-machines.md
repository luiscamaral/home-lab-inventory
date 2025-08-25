# 🖥️ Virtual Machine Inventory

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
- **Status**: ✅ Running  
- **CPU**: 4 cores (host)
- **RAM**: 16 GB
- **Storage**:
  - 90 GB SSD (System)
  - 320 GB (Data, write-through cache)
- **Network**:
  - vmbr1 (Management)
  - vmbr10 (VLAN 10)
- **OS**: Linux
- **Auto-start**: Yes

#### VM 111 - Rootmaster
- **Status**: ✅ Running
- **CPU**: 2 cores (host)
- **RAM**: 2 GB
- **Storage**:
  - 80 GB SSD (System)
  - 16 GB SSD (Additional)
- **Network**: vmbr10 (VLAN 10)
- **OS**: Linux
- **Auto-start**: Yes

#### VM 120 - Docker Master
- **Status**: ✅ Running
- **CPU**: 20 cores (2 sockets × 10 cores, host)
- **RAM**: 64 GB
- **Storage**: 196 GB SSD
- **Network**: vmbr28
- **OS**: Linux
- **Purpose**: Main Docker container host
- **Auto-start**: Yes (startup delay: 30s)

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

#### VM 1000 - Lamint
- **Status**: ✅ Running
- **CPU**: 12 cores (host)
- **RAM**: 32 GB
- **Storage**: 64 GB SSD
- **Network**: vmbr10 (MTU 9000)
- **OS**: Linux
- **Auto-start**: Yes

### Container Orchestration (Stopped)

#### Docker Swarm Cluster
- **VM 230 - Swarm Manager 1**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 4 GB
  - Storage: 21 GB HDD
  - Network: vmbr28

- **VM 231 - Swarm Worker 1**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 4 GB
  - Storage: 21 GB SSD
  - Network: vmbr28

- **VM 232 - Swarm Worker 2**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 4 GB
  - Storage: 21 GB SSD
  - Network: vmbr28

#### Kubernetes Cluster
- **VM 240 - Kubernetes Master 1**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 7 GB
  - Storage: 21 GB SSD
  - Network: vmbr28

- **VM 241 - Kubernetes Worker 1**
  - Status: 🔴 Stopped
  - CPU: 6 cores
  - RAM: 18 GB
  - Storage: 21 GB SSD
  - Network: vmbr28

- **VM 242 - Kubernetes Worker 2**
  - Status: 🔴 Stopped
  - CPU: 6 cores
  - RAM: 18 GB
  - Storage: 21 GB SSD
  - Network: vmbr28

#### Talos Kubernetes Cluster
- **VM 250 - TKMaster 1**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 8 GB (4 GB balloon)
  - Storage: 96 GB SSD
  - Network: vmbr28

- **VM 251 - TKWorker 1**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 8 GB
  - Storage: 96 GB SSD
  - Network: vmbr28

- **VM 252 - TKWorker 2**
  - Status: 🔴 Stopped
  - CPU: 4 cores
  - RAM: 8 GB
  - Storage: 96 GB SSD
  - Network: vmbr28

### Templates & Testing

#### VM 101 - Tiny
- **Status**: 🔴 Stopped
- **CPU**: 4 cores
- **RAM**: 4 GB
- **Storage**: 120 GB SSD
- **Network**: vmbr10
- **OS**: Linux

#### VM 10001 - Ubuntu Server 22.04 Template
- **Status**: 📋 Template
- **CPU**: 4 cores
- **RAM**: 4 GB
- **Storage**: 21 GB HDD
- **Network**: vmbr28
- **OS**: Ubuntu Server 22.04
- **Purpose**: VM template for cloning

## Summary
- **Total VMs**: 18
- **Running**: 7
- **Stopped**: 10
- **Templates**: 1
- **Total Allocated RAM**: ~195 GB
- **Total Allocated Storage**: ~1.5 TB
