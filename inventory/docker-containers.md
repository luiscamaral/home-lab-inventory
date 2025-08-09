# Docker Containers Inventory

## Docker Master Server Containers

### Running Containers

#### Calibre Server
- **Container Name**: calibre
- **Image**: lscr.io/linuxserver/calibre:latest
- **Status**: Up 7 days
- **Ports**: 58080-58083/tcp, 58090/tcp, 58181/tcp
- **Networks**: calibre_default
- **Compose Stack**: calibre
- **Description**: E-book library management server

#### Calibre Web
- **Container Name**: calibre-web
- **Image**: lscr.io/linuxserver/calibre-web:latest
- **Status**: Up 7 days
- **Ports**: 58080-58083/tcp
- **Networks**: calibre_default
- **Compose Stack**: calibre
- **Description**: Web interface for Calibre library

#### Rundeck
- **Container Name**: rundeck
- **Image**: rundeck/rundeck:SNAPSHOT
- **Status**: Up 13 hours
- **Ports**: None (uses macvlan)
- **Networks**: rundeck_macvlan (192.168.59.22)
- **Compose Stack**: rundeck
- **Description**: Job scheduler and runbook automation

#### Portainer
- **Container Name**: portainer
- **Image**: portainer/portainer-ce:latest
- **Status**: Up 10 days
- **Ports**: None (uses macvlan)
- **Networks**: macvlan (192.168.59.2)
- **Description**: Docker management UI

#### Bind9 DNS
- **Container Name**: bind9
- **Image**: internetsystemsconsortium/bind9:9.20
- **Status**: Up 13 hours
- **Ports**: None (uses macvlan)
- **Networks**: macvlan (192.168.59.53)
- **Description**: DNS server

#### PostgreSQL for Rundeck
- **Container Name**: postgres
- **Image**: postgres:16
- **Status**: Up 13 hours
- **Ports**: None
- **Networks**: rundeck_default
- **Compose Stack**: rundeck
- **Description**: Database backend for Rundeck

#### Nginx
- **Container Name**: nginx-nginx-1
- **Image**: nginx:latest
- **Status**: Up 3 days
- **Ports**: 0.0.0.0:80->80/tcp
- **Networks**: nginx_default
- **Compose Stack**: nginx
- **Description**: Web server and reverse proxy

### Stopped Containers

#### Ollama
- **Container Name**: ollama
- **Image**: ollama/ollama:latest
- **Status**: Exited (13 hours ago)
- **Ports**: 11434/tcp
- **Networks**: bridge
- **Description**: Local LLM runtime

#### LiteLLM
- **Container Name**: litellm
- **Image**: ghcr.io/berriai/litellm:main-latest
- **Status**: Exited (13 hours ago)
- **Ports**: 4000/tcp
- **Networks**: bridge
- **Description**: LLM proxy service

#### Wizarr
- **Container Name**: wizarr
- **Image**: ghcr.io/wizarrrr/wizarr:latest
- **Status**: Exited (13 hours ago)
- **Ports**: 5690/tcp
- **Networks**: bridge
- **Description**: Invitation system for Plex/Jellyfin

#### OpenWebUI
- **Container Name**: open-webui
- **Image**: ghcr.io/open-webui/open-webui:main
- **Status**: Exited (13 hours ago)
- **Ports**: None
- **Networks**: bridge
- **Description**: Web UI for LLMs

#### MongoDB
- **Container Name**: mongodb
- **Image**: mongo
- **Status**: Exited (13 hours ago)
- **Ports**: 27017/tcp
- **Networks**: bridge
- **Description**: NoSQL database

#### PostgreSQL (Standalone)
- **Container Name**: postgresql
- **Image**: postgres:16-alpine
- **Status**: Exited (13 hours ago)
- **Ports**: None
- **Networks**: bridge
- **Description**: PostgreSQL database server

## Docker Networks

### Bridge Networks
- **bridge**: Default Docker bridge
- **calibre_default**: Calibre stack network
- **nginx_default**: Nginx stack network
- **rundeck_default**: Rundeck internal network

### Macvlan Networks
- **macvlan**: Main macvlan network (192.168.59.0/26)
- **rundeck_macvlan**: Dedicated Rundeck macvlan

## Docker Volumes

### Named Volumes
- **bind9_cache**: Bind9 DNS cache
- **bind9_config**: Bind9 configuration
- **bind9_records**: Bind9 DNS records
- **ollama_data**: Ollama model storage
- **portainer_data**: Portainer configuration
- **rundeck_postgres_data**: Rundeck PostgreSQL data

### NFS Mounts
- **/nfs/calibre**: Calibre library storage
- **/nfs/dockermaster**: General Docker storage
- **/nfs/bind9**: DNS server data
- **/nfs/rundeck**: Rundeck data

## Docker Compose Stacks

### Active Stacks
1. **calibre**: E-book management (2 services)
2. **nginx**: Web server (1 service)
3. **rundeck**: Automation platform (2 services)
4. **portainer**: Docker management (standalone)

### Available but Inactive
1. **ollama**: LLM runtime
2. **litellm**: LLM proxy
3. **wizarr**: Media server invitations
4. **open-webui**: LLM web interface
5. **mongodb**: NoSQL database
6. **postgresql**: SQL database
7. **bind9**: DNS server (running standalone)