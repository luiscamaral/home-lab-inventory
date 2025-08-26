# Docker Compose Projects Status

Last updated: 2025-08-09

## Overview

This document provides a comprehensive status of all Docker Compose projects on dockermaster server.

## Currently Running Containers

Based on `docker ps` output:

| Container Name | Image | Status | Project |
|---|---|---|---|
| calibre | calibre-calibre | Up 8 days | calibre-server |
| calibre-web | lscr.io/linuxserver/calibre-web:latest | Up 8 days | calibre-server |
| rundeck | la-rundeck-rundeck | Up 12 days | rundeck |
| portainer | portainer/portainer-ce:latest | Up 12 days | portainer |
| bind-dns-bind9-1 | Ubuntu/bind9:9.20-24.10_edge | Up 12 days | bind9 |
| postgres-rundeck | postgres | Up 12 days | rundeck |
| rproxy | Nginx:1.27 | Up 12 days | Nginx-rproxy |

## Project Status Summary

### 🟢 ACTIVE Projects (5)

| Project | Status | Containers | Description | Network | IP Address |
|---|---|---|---|---|---|
| **bind9** | ACTIVE | bind-dns-bind9-1 | DNS server with custom zones | Docker-servers-net | 192.168.59.x |
| **calibre-server** | ACTIVE | calibre, calibre-web | E-book library management | bridge | ports 58080-58183 |
| **Nginx-rproxy** | ACTIVE | rproxy | Reverse proxy with SSL termination | Docker-servers-net | 192.168.59.28 |
| **portainer** | ACTIVE | portainer | Docker management UI | Docker-servers-net | 192.168.59.2 |
| **rundeck** | ACTIVE | rundeck, postgres-rundeck | Job scheduler with PostgreSQL | Docker-servers-net | 192.168.59.22/23 |

### 🔴 INACTIVE Projects (7)

| Project | Status | Last Known Config | Description |
|---|---|---|---|
| **Ansible-observability** | INACTIVE | Prometheus + Grafana | Monitoring for Ansible/AWX |
| **Docker-dns** | INACTIVE | phensley/Docker-dns | Dynamic DNS for Docker containers |
| **Docker-vault** | INACTIVE | HashiCorp Vault 1.4.2 | Secret management |
| **litellm** | INACTIVE | LiteLLM + PostgreSQL | LLM proxy with database |
| **n8n-stack** | INACTIVE | n8n + PostgreSQL | Workflow automation platform |
| **ollama** | INACTIVE | Ollama | Local LLM inference server |
| **puppet** | INACTIVE | Puppet Server | Configuration management |


## Network Configuration

Most projects use the external `docker-servers-net` macvlan network with static IP addresses in the 192.168.59.x range:

- 192.168.59.2 - portainer
- 192.168.59.22 - rundeck  
- 192.168.59.23 - postgres-rundeck
- 192.168.59.28 - rproxy
- 192.168.59.30 - n8n (when active)

## Storage Configuration

Several projects use NFS-mounted volumes under `/nfs/dockermaster/volumes/`:

- litellm (Prometheus_data, postgres_data)
- n8n-stack (pgdata, n8n_data)  
- ollama (ollama)

## Security Notes

- Sensitive data has been redacted from extracted configurations
- Several projects contain passwords and API keys in environment variables
- SSH keys are present in Nginx-rproxy and rundeck projects
- SSL certificates are managed by Nginx-rproxy

## Recommendations

1. **Security**: Rotate passwords and API keys, especially for inactive services
2. **Cleanup**: Consider removing unused volumes and containers from inactive projects  
3. **Documentation**: Update project documentation for configuration changes
4. **Monitoring**: Consider reactivating Ansible-observability for better monitoring
5. **Backup**: Ensure NFS-mounted volumes are included in backup strategy
