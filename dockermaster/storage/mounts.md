# Storage and Mount Configuration

## Local Storage

### Block Devices

| Device | Size | Type | Mount Point | Filesystem |
|--------|------|------|-------------|------------|
| sda | 196G | disk | - | - |
| ├─sda1 | 1M | partition | - | - |
| └─sda2 | 196G | partition | / | ext4 |

### Snap Loop Devices

| Device | Size | Type | Mount Point | Package |
|--------|------|------|-------------|---------|
| loop0 | 133.4M | loop | /snap/cmake/1186 | cmake |
| loop1 | 134.5M | loop | /snap/cmake/1204 | cmake |
| loop2 | 55.6M | loop | /snap/core18/2620 | core18 |
| loop3 | 55.6M | loop | /snap/core18/2632 | core18 |
| loop4 | 63.2M | loop | /snap/core20/1634 | core20 |
| loop5 | 63.2M | loop | /snap/core20/1695 | core20 |
| loop6 | 91.8M | loop | /snap/lxd/24061 | lxd |
| loop7 | 49.6M | loop | /snap/snapd/17883 | snapd |

## Disk Usage

| Filesystem | Size | Used | Available | Use% | Mount Point |
|------------|------|------|-----------|------|-------------|
| /dev/sda2 | 192G | 64G | 119G | 35% | / |
| tmpfs | 6.3G | 1.8M | 6.3G | 1% | /run |
| tmpfs | 32G | 0 | 32G | 0% | /dev/shm |
| tmpfs | 5.0M | 0 | 5.0M | 0% | /run/lock |
| tmpfs | 6.3G | 16K | 6.3G | 1% | /run/user/1027 |

## NFS Mounts

### Active NFS4 Mounts

| Remote Path | Local Mount Point | Server | Size | Used | Available | Use% |
|-------------|-------------------|--------|------|------|-----------|------|
| snas:/volume2/shared/02.Books/032.eBooks/calibre | /nfs/calibre | 192.168.1.50 | 6.0T | 5.7T | 321G | 95% |
| snas:/volume2/servers/dockermaster | /nfs/dockermaster | 192.168.1.50 | 1.0T | 54G | 971G | 6% |

### NFS Mount Options

Both NFS mounts are configured with the following options:
- **Version**: NFSv4.1
- **Read Size**: 131072 bytes
- **Write Size**: 131072 bytes
- **Name Length**: 255 characters
- **Mount Type**: soft
- **Protocol**: TCP
- **Timeout**: 60 seconds
- **Retransmissions**: 5
- **Security**: sys
- **Client Address**: 192.168.48.44
- **Local Lock**: none

## Docker Storage

### Docker Overlay2 Filesystems

Docker containers are using overlay2 storage driver with multiple active overlay filesystems:

| Overlay ID | Mount Point | Size | Used | Available | Use% |
|------------|-------------|------|------|-----------|------|
| 1382bdf896e3... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| 90d2eeff28a6... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| 89ea73a8fab1... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| aeebf0f918d3... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| 1c51b3e12bd1... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| d08760c2ec48... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |
| e07b9e09053c... | /var/lib/docker/overlay2/.../merged | 192G | 64G | 119G | 35% |

## Storage Summary

### Local Storage
- **Root Partition**: 196GB total, 64GB used (35% utilization)
- **Available Space**: 119GB free
- **Filesystem**: ext4

### Network Storage (NFS)
- **Calibre Library**: 6TB total, 5.7TB used (95% utilization) - read-only media storage
- **Dockermaster Data**: 1TB total, 54GB used (6% utilization) - container persistent data

### Docker Storage
- **Storage Driver**: overlay2 on ext4 backing filesystem
- **Container Storage**: Shares root partition space
- **Active Containers**: 7 containers with active overlay filesystems

*Last updated: 2025-08-09*