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

Checked 2026-11-18, 16:59–17:04 UTC on `proxmox`.
See [assessment evidence E1–E12](../docs/operations/2026-11-18-proxmox-assessment.md#evidence-index).

- **Proxmox manager**: 9.1.7
- **OS**: Debian 13 (trixie)
- **Kernel**: 6.17.13-2-pve
- **QEMU**: 10.1.2-7
- **LXC runtime**: 6.0.5-4
- **Corosync**: 3.1.10-pve2 installed. No Corosync cluster configuration.
- **LVM**: 2.03.31-2+pmx1
- **smartmontools**: 7.4-pve1
- **ssacli**: 6.15-11.0
- **hponcfg**: 6.0.0-0

### Read-only assessment commands

These commands ran on `proxmox`. The SSH account needs sudo for privileged queries.

- `hostnamectl`, `uname -a`, `uptime`, `lscpu`, `free -h`, `vmstat 1 3`: OS, hardware, and load.
- `dmidecode -t system -t baseboard -t bios -t memory`, `lspci -nn`: Hardware details.
- `qm list`, `pct list`, `pvesh get /cluster/resources --type vm`: Guest state.
- `qm guest cmd <vmid> get-osinfo`, `qm guest cmd <vmid> get-fsinfo`: Guest-agent OS and filesystem data.
- `pvesh get /nodes/proxmox/status`, `pvecm status`: Node and cluster state.
- `lsblk`, `findmnt`, `df -hT`, `pvesm status`, `pvs`, `vgs`, `lvs`: Storage layout and allocation.
- `ssacli ctrl all show status`, `ssacli ctrl all show config`, `ssacli ctrl all show detail`: P420i RAID health.
- `smartctl -H /dev/sda`: Reports that physical-drive access needs `-d cciss,N`. This query did not establish drive health.
- `pvesh get /cluster/backup`, `pvesh get /nodes/proxmox/tasks`: Backup configuration and history.
- `pvesm list pve-backups --content backup`: Backup archive inventory.
- `ip -br address`, `ip route`, `ip -d link show`, `bridge vlan show`, `ethtool <nic>`: Network state.
- `ss -lntup`, `sshd -T`, `pve-firewall status`, `nft list tables`, `iptables -S`, `ip6tables -S`: Host access controls.
- `chronyc tracking`, `chronyc sources -v`: Time synchronization.
- `apt-cache policy <package>`, `apt list --upgradable`, `apt-mark showhold`: Cached update candidates.
- `apt-get --simulate dist-upgrade`: Package simulation only. Proposed 275 upgrades and seven additions.
- `systemctl --failed`, `systemctl list-timers --all`, `journalctl`: Services, schedules, and logs.
- `proxmox-boot-tool status`, `pvenode cert info`: Boot setup and public certificates.
- `zpool status`, `ceph -s`: No ZFS pools. Ceph did not identify monitors.
- `pct exec 10000 -- grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release`: Pi-hole container OS.

On `nas`, `df -h`, `stat -f`, and `ls -ldn` checked storage capacity and backup path ownership without sudo.
The workstation queried primary Prometheus through `/api/v1/query` for the PVE scrape and version.
No installs, metadata refresh, service changes, or restores took place.

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

## NAS Server (Synology)

### Docker via Container Manager

> Synology Container Manager installs the NAS Docker binary at a non-standard path.

```bash
# Full path required unless added to PATH
/var/packages/ContainerManager/target/usr/bin/docker

# Convenience: add to session PATH
export PATH="/var/packages/ContainerManager/target/usr/bin:$PATH"
```

### Docker Container Management

- `docker ps` - List running containers
- `docker ps -a` - List all containers (including stopped)
- `docker logs <container>` - View container logs
- `docker exec -it <container> sh` - Enter container shell
- `docker inspect <container>` - Detailed container information
- `docker stats` - Real-time resource usage statistics

### Docker Compose

- `docker compose up -d` - Start stack in detached mode
- `docker compose down` - Stop and remove stack
- `docker compose ps` - List stack containers
- `docker compose logs` - View stack logs
- `docker compose pull` - Update stack images

### Docker System

- `docker system df` - Show disk usage
- `docker version` - Docker version info
- `docker info` - System-wide information

### Version Information

- **Docker Engine**: 24.0.2
- **Docker API**: 1.43
- **containerd**: v1.7.1
- **Docker Compose**: v2.20.1
- **Docker Root**: `/volume2/@docker`
- **Storage Driver**: btrfs

---

## pfSense (Main Router & Gateway)

> FreeBSD-based. Most commands run as root through key authentication, without a `sudo` prompt.
> Destructive operations need approval. See the
> `pfsense-manage` skill for safe workflows.

### System Information

- `uname -a` - Kernel, hostname, architecture
- `cat /etc/version` - pfSense Plus version (for example, `26.07-RELEASE`)
- `cat /etc/version.buildtime` - Build timestamp
- `sysctl -n hw.model hw.ncpu hw.physmem` - CPU model, core count, RAM bytes
- `uptime` / `top -b` - Load and processes
- `df -h` - Disk usage (ZFS)
- `bectl list` - ZFS boot environments (for safe upgrades/rollback)

### Networking

- `ifconfig -a` - All interfaces and VLANs such as `ix0.10`
- `netstat -rn4` / `netstat -rn6` - IPv4/IPv6 routing tables
- `pfctl -s info` - pf firewall status and counters
- `pfctl -s labels` - Rule hit counts with descriptions
- `pfctl -s states | head` - Current state table entries
- `pfctl -s rules` - Active rules (verbose, prefer GUI for reading)
- `pfctl -s nat` - NAT rules
- `sockstat -4l` / `sockstat -6l` - IPv4/IPv6 listening sockets

### DHCP & DNS

- `cat /var/dhcpd/var/db/dhcpd.leases` - ISC DHCP lease database
- `grep "^lease" /var/dhcpd/var/db/dhcpd.leases | wc -l` - Lease count
- `service unbound status` / `ps auxw | grep unbound` - Unbound resolver
- `cat /var/unbound/dhcpleases_entries.conf` - DHCP-to-DNS host mappings
- `drill example.com @127.0.0.1` - Local DNS test

### Packages

- `pkg info | grep pfSense-pkg-` - Installed pfSense packages
- `pfSense-upgrade -l` - Check for updates (does not apply)

### HAProxy

- `cat /var/etc/haproxy/haproxy.cfg` - Compiled HAProxy config
- `ls /var/etc/haproxy/` - Frontend cert lists, error pages
- `echo "show stat" | socat stdio /tmp/haproxy.socket` - Runtime stats
- `service haproxy status` - Service status

### ACME / Certificates

- `ls /conf/acme/` - Issued certs (`.crt`, `.key`, `.fullchain`, `.ca`)
- `openssl x509 -in /conf/acme/d.lcamaral.com.crt -text -noout | head -20` - Inspect a cert
- pfSense GUI: **System → Cert Manager** for issue/renew

### pfBlockerNG

- `ls /var/db/pfblockerng/` - Deployed feeds (`deny`, `match`, `permit`, `dnsbl`)
- `wc -l /var/db/pfblockerng/deny/*.txt` - Block list sizes

### Config

- `cat /cf/conf/config.xml` - **Main config** (sensitive, contains hashed passwords and PSKs)
- `ls /cf/conf/backup/` - Automatic config backups (timestamped)
- `ls /cf/conf/config.xml.bak.*` - Recent change snapshots

### Packaged Utilities

- `iperf3 -s` / `iperf3 -c <host>` - Throughput testing (iperf package)
- `nmap -sn 192.168.4.0/20` - Network discovery (nmap package)
- `ladvd -q` - LLDP/CDP neighbor info (LADVD package)

### REST API (pfSense-pkg-RESTAPI v2.10_2)

> 200+ endpoints. Prefer API for structured JSON data. Full reference:
> `docs/network/pfsense-api.md`

```bash
# Setup
TOKEN=$(security find-generic-password -a ${USER} -s pfsense-api-token -w)
API="https://pfsense.home.lcamaral.com/api/v2"

# Examples
curl -sk -H "X-API-Key: $TOKEN" "$API/status/system"             # System status
curl -sk -H "X-API-Key: $TOKEN" "$API/status/interfaces"         # Interface status
curl -sk -H "X-API-Key: $TOKEN" "$API/status/gateways"           # Gateway health
curl -sk -H "X-API-Key: $TOKEN" "$API/status/services"           # Service status
curl -sk -H "X-API-Key: $TOKEN" "$API/status/dhcp_server/leases" # DHCP leases
curl -sk -H "X-API-Key: $TOKEN" "$API/firewall/rules"            # Firewall rules
curl -sk -H "X-API-Key: $TOKEN" "$API/services/acme/certificates" # ACME certs
curl -sk -H "X-API-Key: $TOKEN" "$API/diagnostics/arp_table"     # ARP table
```

### Version Information

Verified 2026-11-10 (`cat /etc/version`, `pkg info | grep pfSense-pkg-`):

- **pfSense Plus**: 26.07-RELEASE
- **FreeBSD**: 16.0-CURRENT
- **REST API pkg**: 2.10_2 (reinstalled 2026-11-10; pfSense upgrades can drop it)
- **HAProxy pkg**: 0.65.7
- **acme pkg**: 1.3.2
- **frr pkg**: 2.1.3_2
- **node_exporter pkg**: 0.18.1_8
- **pfBlockerNG**: not installed

---

## Home Assistant (VM 121)

### HA CLI Commands

To be documented - connect to HA to inventory

---

## Access Commands

- `ssh proxmox` - Access Proxmox hypervisor
- `ssh nas` - Access Synology NAS
- `ssh dockermaster` - Access Docker master server
- `ssh pfsense` - Access pfSense router (key-based, no username / password)

---

> Note: Use `SUDO_ASKPASS=$HOME/.config/bin/answer.sh` for sudo commands on
> Proxmox and dockermaster. pfSense uses root-by-default via SSH key auth.
