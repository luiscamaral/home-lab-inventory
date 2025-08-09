# Home Lab Infrastructure Inventory

Documentation and tracking system for home lab infrastructure including servers, VMs, and Docker containers.

## Structure

- `inventory/servers.md` - Physical servers documentation
- `inventory/virtual-machines.md` - VMs running on Proxmox
- `inventory/docker-containers.md` - Docker containers on Docker Master
- `inventory/commands-available.md` - Available commands and versions

## Infrastructure Overview

### Physical Servers
- **Proxmox Hypervisor** - Main virtualization host (40 threads, 243GB RAM)
- **Synology NAS** - Storage and backup server

### Virtual Machines
- 18 VMs total (7 running, 11 stopped)
- Kubernetes cluster (1 control plane, 3 workers)
- Docker Master host
- Home Assistant
- Various testing environments

### Docker Services
- Container management (Portainer)
- Media services (Calibre)
- Automation (Rundeck)
- DNS (Bind9)
- Databases (PostgreSQL)