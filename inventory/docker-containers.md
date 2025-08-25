# 🐳 Docker Container Inventory

## Docker Master Server

### System Information
- **Host**: dockermaster (VM 120)
- **OS**: Ubuntu 24.04.2 LTS (Noble Numbat)
- **Kernel**: Linux 6.8.0-64-generic
- **CPU**: 20 cores (Intel Xeon E5-2680 v2 @ 2.80GHz)
- **RAM**: 62 GB total (4.2 GB used, 58 GB available)
- **Storage**: 192 GB SSD (35% used - 64GB used, 119GB available)
- **Network**:
  - Main IP: 192.168.48.44/20
  - Server Network: 192.168.59.1/26 (macvlan)
- **Docker Version**: 28.3.2 (API 1.51)
- **Docker Compose**: Multiple stacks deployed

### NFS Mounts
- `/nfs/calibre` - Calibre library storage (from NAS)
- `/nfs/dockermaster` - Docker persistent data (from NAS)

---

## 🟢 Running Containers (8)

### 📚 Calibre Server
- **Image**: calibre-calibre
- **Status**: Up 7 days
- **Ports**:
  - 58080:8080 (Web UI)
  - 58081:8081 (Server)
  - 58181:8181
  - 58090:9090
- **Resources**: 2.55% CPU, 553MB RAM (0.86%)
- **Volumes**:
  - `/nfs/calibre/Library` → `/Library`
  - `/nfs/calibre/config` → `/config`
  - `/nfs/calibre/upload` → `/upload`
  - `/nfs/calibre/plugins` → `/plugins`
- **Purpose**: E-book library management server

### 📖 Calibre Web
- **Image**: lscr.io/linuxserver/calibre-web:latest
- **Status**: Up 7 days
- **Ports**: 58083:8083
- **Resources**: 0.02% CPU, 199MB RAM (0.31%)
- **Volumes**:
  - `/nfs/calibre/calibre-web/Library` → `/books`
  - `/nfs/calibre/calibre-web/config` → `/config`
- **Purpose**: Web-based e-book reader interface

### 🔧 Rundeck
- **Image**: la-rundeck-rundeck (custom build)
- **Status**: Up 12 days
- **Network**: 192.168.59.22 (macvlan)
- **Resources**: 0.44% CPU, 2.25GB RAM (3.58%)
- **Volumes**:
  - `/nfs/dockermaster/docker/rundeck/data` → `/home/rundeck/server/data`
  - `/nfs/dockermaster/docker/rundeck/container-plugins`
  - `/var/run/docker.sock` → `/var/run/docker.sock`
- **Database**: PostgreSQL (postgres-rundeck container)
- **Purpose**: Job scheduler and runbook automation
- **Compose Stack**: Yes

### 🗄️ PostgreSQL for Rundeck
- **Image**: postgres
- **Container**: postgres-rundeck
- **Status**: Up 12 days
- **Network**: 192.168.59.23 (macvlan)
- **Resources**: 0.01% CPU, 62MB RAM (0.10%)
- **Volumes**: `/nfs/dockermaster/docker/rundeck/dbdata`
- **Purpose**: Database backend for Rundeck

### 🤖 GitHub Actions Runner
- **Image**: myoung34/github-runner:latest
- **Container**: github-runner-homelab
- **Status**: Ready for deployment
- **Network**: docker-servers-net (macvlan)
- **Resources**:
  - Limits: 2 CPU, 4GB RAM
  - Reservations: 0.5 CPU, 512MB RAM
  - Idle usage: ~0.5% CPU, ~150MB RAM
- **Volumes**:
  - `/var/run/docker.sock` → `/var/run/docker.sock` (Docker access)
  - `./work` → `/tmp/runner/work` (Job workspace)
  - `./cache` → `/tmp/runner/_work/_tool` (Build cache)
  - `./config` → `/actions-runner` (Configuration)
  - `/nfs/dockermaster/docker` → `/deployment:ro` (Read-only deployment path)
- **Environment**:
  - **Labels**: self-hosted, linux, x64, dockermaster, docker
  - **Ephemeral**: false (persistent environment)
  - **Auto-update**: enabled
- **Features**:
  - Direct Docker socket access for container management
  - Access to internal networks via macvlan
  - Integration with local Portainer and services
  - Secure token management via environment variables
- **Purpose**: Self-hosted CI/CD runner for GitHub Actions
- **Compose Stack**: Yes (`dockermaster/github-runner/docker-compose.yml`)

### 🖥️ Portainer
- **Image**: portainer/portainer-ce:latest
- **Status**: Up 12 days
- **Network**: 192.168.59.2 (macvlan)
- **Resources**: 0.04% CPU, 72MB RAM (0.11%)
- **Volumes**:
  - `/var/run/docker.sock` → `/var/run/docker.sock`
  - `portainer_data` volume
- **Purpose**: Docker management UI
- **Compose Stack**: Yes

### 🌐 Bind9 DNS
- **Image**: ubuntu/bind9:9.20-24.10_edge
- **Status**: Up 12 days
- **Ports**:
  - 53:53/tcp
  - 53:53/udp
- **Resources**: 0.00% CPU, 12MB RAM (0.02%)
- **Volumes**:
  - `/nfs/dockermaster/docker/bind9/config` → `/etc/bind`
  - `/nfs/dockermaster/docker/bind9/cache` → `/var/cache/bind`
  - `/nfs/dockermaster/docker/bind9/records` → `/var/lib/bind`
- **Purpose**: DNS server
- **Compose Stack**: Yes

### 🔀 Nginx Reverse Proxy
- **Image**: nginx:1.27
- **Container**: rproxy
- **Status**: Up 12 days
- **Resources**: 0.00% CPU, 3.6MB RAM (0.01%)
- **Volumes**: `/nfs/dockermaster/docker/nginx-rproxy/nginx-rproxy` → `/etc/nginx`
- **Purpose**: Reverse proxy server
- **Compose Stack**: Yes

---

## 🔴 Stopped Containers (6)

### 🤖 Ollama
- **Image**: ollama/ollama
- **Status**: Exited 2 weeks ago
- **Purpose**: Local LLM runtime
- **Volume**: `ollama_ollama`
- **Compose Stack**: Yes

### 🕷️ Crawl4AI
- **Image**: unclecode/crawl4ai:latest
- **Status**: Exited 3 weeks ago
- **Purpose**: Web crawling AI tool

### 🧠 LiteLLM Stack
- **LiteLLM Service**: ghcr.io/berriai/litellm:main-stable (Exited 3 weeks ago)
- **Prometheus**: prom/prometheus (Exited 2 weeks ago)
- **PostgreSQL**: postgres:16 (Exited 2 weeks ago)
- **Volumes**:
  - `litellm_postgres_data`
  - `litellm_prometheus_data`
- **Purpose**: LLM proxy and monitoring
- **Compose Stack**: Yes

### 👋 Hello World Test
- **Image**: hello-world
- **Container**: relaxed_elion
- **Status**: Exited 4 months ago
- **Purpose**: Docker test container

---

## 🌐 Docker Networks

### Active Networks
- **bridge**: Default bridge network
- **docker-servers-net**: Macvlan network for server IPs (192.168.59.0/26)
- **bind-dns_default**: Bind9 DNS service network
- **calibre_default**: Calibre services network
- **rproxy-test_default**: Nginx proxy network

### Inactive Networks
- **litellm_default**: LiteLLM stack network
- **ollama_default**: Ollama service network

---

## 💾 Docker Volumes

### Named Volumes
- `dockermaster-portainer_portainer_data` - Portainer configuration
- `litellm_postgres_data` - LiteLLM PostgreSQL data
- `litellm_prometheus_data` - Prometheus metrics data
- `ollama_ollama` - Ollama models and data

### NFS-backed Storage
- All persistent data stored on NAS via NFS mounts
- Configuration files in `/nfs/dockermaster/docker/`
- Calibre library in `/nfs/calibre/`

---

## 📁 Docker Compose Stacks

### Active Stacks
1. **Rundeck** (`/rundeck/docker-compose.yml`)
2. **Portainer** (`/portainer/docker-compose.yml`)
3. **Bind9 DNS** (`/bind9/docker-compose.yml`)
4. **Nginx Reverse Proxy** (`/nginx-rproxy/docker-compose.yml`)

### Available but Inactive
1. **Ollama** (`/ollama/docker-compose.yml`)
2. **LiteLLM** (`/litellm/docker-compose.yml`)
3. **N8N** (`/n8n-stack/docker-compose.yml`)
4. **Puppet** (`/puppet/docker-compose.yml`)
5. **Ansible Stack** (`/ansible-stack/netbox/docker-compose.yml`)
6. **Docker Vault** (`/docker-vault/docker-compose.yml`)
7. **Ansible Observability** (`/ansible-observability/docker-compose.yml`)

---

## 📊 Resource Summary
- **Total Containers**: 13 (7 running, 6 stopped)
- **Memory Usage**: ~3.1 GB of 62 GB (5%)
- **CPU Usage**: ~3% average
- **Storage**: Using NFS mounts for persistence
- **Network**: Macvlan network for service isolation

---

## Container Orchestration Platforms (VMs - Stopped)

### Docker Swarm Cluster
- Manager: VM 230
- Workers: VM 231, 232
- Status: 🔴 Stopped

### Kubernetes Clusters
- Standard K8s: VMs 240-242
- Talos K8s: VMs 250-252
- Status: 🔴 Stopped
