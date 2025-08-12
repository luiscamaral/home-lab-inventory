# Docker Master Server Configuration

This directory contains comprehensive documentation of the Docker Master server (VM 120) configuration and all hosted services.

## Server Overview

- **Hostname**: dockermaster
- **OS**: Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel**: Linux 6.8.0-64-generic
- **Architecture**: x86_64 (KVM virtual machine)
- **CPU**: Intel Xeon E5-2680 v2 @ 2.80GHz (20 cores)
- **Memory**: 62 GB RAM
- **Storage**: 196 GB local + NFS mounts to Synology NAS
- **Docker**: Version 28.3.2
- **Network**: Multiple Docker networks including macvlan for container isolation

## Directory Structure

```
dockermaster/
├── README.md                    # This file
├── system/                      # System configuration
│   └── info.md                 # OS, hardware, and kernel details
├── docker/                      # Docker configuration
│   ├── config.md               # Docker daemon configuration
│   └── compose/                # All Docker Compose projects
│       ├── STATUS.md           # Project status overview
│       ├── ansible-observability/  # [INACTIVE] Monitoring stack
│       ├── bind9/              # [ACTIVE] DNS server
│       ├── calibre-server/     # [ACTIVE] E-book library
│       ├── docker-dns/         # [INACTIVE] Dynamic DNS
│       ├── docker-vault/       # [INACTIVE] Secret management
│       ├── litellm/            # [INACTIVE] LLM proxy
│       ├── n8n-stack/          # [INACTIVE] Workflow automation
│       ├── nginx-rproxy/       # [ACTIVE] Reverse proxy
│       ├── ollama/             # [INACTIVE] Local LLM
│       ├── portainer/          # [ACTIVE] Docker management
│       ├── puppet/             # [INACTIVE] Config management
│       └── rundeck/            # [ACTIVE] Job scheduler
├── network/                     # Network configuration
│   └── interfaces.md           # Network interfaces and routing
├── storage/                     # Storage configuration
│   └── mounts.md               # Disk usage and NFS mounts
└── services/                    # System services
    └── systemd.md              # Running systemd services
```

## Active Services

### Currently Running (5 projects, 7 containers)

1. **Bind9 DNS** - DNS server for local network resolution
   - Container: bind-dns-bind9-1
   - Network: docker-servers-net

2. **Calibre Server** - E-book library management
   - Containers: calibre, calibre-web
   - Ports: 58080-58183
   - Storage: /nfs/calibre (6TB available)

3. **Nginx Reverse Proxy** - SSL termination and routing
   - Container: rproxy
   - IP: 192.168.59.28
   - SSL certificates managed

4. **Portainer** - Docker management UI
   - Container: portainer
   - IP: 192.168.59.2
   - Web UI for container management

5. **Rundeck** - Job automation platform
   - Containers: rundeck, postgres-rundeck
   - IPs: 192.168.59.22-23
   - PostgreSQL backend

## Inactive Projects Available

- ansible-observability (Prometheus + Grafana monitoring)
- docker-dns (Dynamic DNS for containers)
- docker-vault (HashiCorp Vault)
- litellm (LLM proxy service)
- n8n-stack (Workflow automation)
- ollama (Local LLM inference)
- puppet (Configuration management)

## Network Configuration

- **Primary Network**: docker-servers-net (macvlan)
- **IP Range**: 192.168.59.0/26
- **Gateway**: 192.168.7.1
- **DNS**: Local Bind9 at 192.168.59.53

## Storage

- **Local Storage**: 196GB (35% used)
- **NFS Mounts**:
  - `/nfs/calibre` - E-book library (6TB)
  - `/nfs/dockermaster` - Docker data (1TB)

## Security Notes

- All passwords and API keys have been redacted from configuration files
- SSH keys present in some projects (nginx-rproxy, rundeck)
- SSL certificates managed by nginx-rproxy
- Firewall managed via iptables/Docker

## Quick Commands

```bash
# SSH to server
ssh dockermaster

# View running containers
docker ps

# View all containers (including stopped)
docker ps -a

# View Docker networks
docker network ls

# View Docker volumes
docker volume ls

# Check disk usage
df -h

# View system resources
htop
```

## Maintenance Notes

1. **Uptime**: Services show 8-12 days uptime indicating stable operation
2. **Updates**: Ubuntu 24.04 LTS with regular security updates
3. **Monitoring**: Consider reactivating ansible-observability for better visibility
4. **Backup**: NFS volumes should be included in Synology backup strategy
5. **Security**: Rotate credentials periodically, especially for inactive services

## Additional Documentation

- See `STATUS.md` in docker/compose/ for detailed project status
- Individual project folders contain docker-compose.yml and related configs
- System configuration details in respective subdirectories

---
*Last Updated: 2025-08-09*