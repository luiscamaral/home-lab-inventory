# 📋 Commands & Tools Available

## Proxmox Server

### System Information
- `pveversion -v` - Proxmox version and components
- `qm list` - List all VMs
- `qm config <vmid>` - Show VM configuration
- `qm start/stop/restart <vmid>` - VM control
- `qm guest cmd <vmid> network-get-interfaces` - Get VM network info
- `pvesm status` - Storage status

### Networking
- `ip addr show` - Network interfaces
- `ip neigh show` - ARP table
- `brctl show` - Bridge configuration

### Monitoring
- `pvesh get /nodes` - Node information
- `pvesh get /cluster/resources` - Cluster resources
- `htop` - Process monitoring
- `iostat -x` - I/O statistics

### Version Information
- **Proxmox VE**: 8.3.5
- **Kernel**: 6.8.12-9-pve
- **QEMU**: 9.2.0-2
- **Corosync**: 3.1.7-pve3

---

## Docker Master (VM 120)

### Docker Container Management
- `docker ps` - List running containers
- `docker ps -a` - List all containers (including stopped)
- `docker start/stop/restart <container>` - Container control
- `docker logs <container>` - View container logs
- `docker exec -it <container> bash` - Enter container shell
- `docker inspect <container>` - Detailed container information
- `docker stats` - Real-time resource usage statistics
- `docker rm <container>` - Remove stopped container

### Docker Image Management
- `docker images` - List local images
- `docker pull <image>` - Download image from registry
- `docker build -t <tag> .` - Build image from Dockerfile
- `docker rmi <image>` - Remove image
- `docker image prune` - Remove unused images

### Docker Compose
- `docker compose up -d` - Start stack in detached mode
- `docker compose down` - Stop and remove stack
- `docker compose ps` - List stack containers
- `docker compose logs` - View stack logs
- `docker compose restart` - Restart stack services
- `docker compose pull` - Update stack images

### Docker Network
- `docker network ls` - List networks
- `docker network inspect <network>` - Network details
- `docker network create <name>` - Create network
- `docker network rm <network>` - Remove network

### Docker Volumes
- `docker volume ls` - List volumes
- `docker volume inspect <volume>` - Volume details
- `docker volume create <name>` - Create volume
- `docker volume rm <volume>` - Remove volume
- `docker volume prune` - Remove unused volumes

### Docker System
- `docker system df` - Show disk usage
- `docker system prune` - Clean up unused resources
- `docker version` - Docker version info
- `docker info` - System-wide information

### Version Information
- **Docker Engine**: 28.3.2
- **Docker API**: 1.51
- **Containerd**: 1.7.27
- **Docker Compose**: v2 (integrated)
- **OS**: Ubuntu 24.04.2 LTS

---

## Home Assistant (VM 121)

### HA CLI Commands
*To be documented - connect to HA to inventory*

---

## Access Commands
- `ssh proxmox` - Access Proxmox hypervisor
- `ssh nas` - Access Synology NAS
- `ssh dockermaster` - Access Docker master server

---

*Note: Use SUDO_ASKPASS=$HOME/.config/bin/answer.sh for sudo commands on Proxmox*