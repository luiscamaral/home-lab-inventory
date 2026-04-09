# Docker Compose Projects Status

Last updated: 2026-04-09

## Overview

This document provides a comprehensive status of all Docker Compose projects on dockermaster server.

## Deployment Model

Portainer stacks are provisioned and managed via Terraform in `terraform/portainer/`. Each stack is declared as a `portainer_stack` resource. Standalone projects (not in Terraform) are deployed directly via `docker compose` on dockermaster.

---

## Terraform-Managed Portainer Stacks (13)

| Stack | Portainer ID | Containers | Network | IP | Auto-update |
|---|---|---|---|---|---|
| docker-registry | 1 | registry | rproxy bridge | 172.24.0.x | yes |
| cloudflare-tunnel | 2 | cloudflare-tunnel-cloudflare-1 | rproxy bridge | 172.24.0.x | yes |
| bind-dns | 4 | bind-dns-bind9-1 | docker-servers-net | 192.168.59.3 | no |
| twingate-a | 5 | twingate-sepia-hornet | dual (macvlan + rproxy) | 192.168.59.12 | yes |
| twingate-b | 6 | twingate-golden-mussel | dual (macvlan + rproxy) | 192.168.59.24 | yes |
| vault | 7 | vault | rproxy bridge | 172.24.0.x | no |
| reverse-proxy | 8 | rproxy, promtail | dual (macvlan + rproxy) | 192.168.59.28 | no |
| github-runner | 9 | github-runner-homelab | docker-servers-net | 192.168.59.4 | yes |
| calibre | 10 | calibre, calibre-web | rproxy bridge | 172.24.0.x | yes |
| rust-server | 11 | hbbs, hbbr | dual (macvlan + rproxy) | 192.168.59.10, .11 | yes |
| prometheus | 12 | prometheus, node-exporter, snmp-exporter, alertmanager, cadvisor | back-tier | -- | yes |
| la-rundeck | 13 | rundeck (no), postgres-rundeck (yes) | docker-servers-net | 192.168.59.22, .23 | mixed |
| watchtower | 14 | watchtower | rproxy bridge | 172.24.0.x | no |

---

## Standalone Docker Compose (NOT Terraform-Managed)

| Project | Containers | Network | IP |
|---|---|---|---|
| portainer-ce | portainer | docker-servers-net | 192.168.59.2 |
| ldap-lcamaral-com | lemonldap, openldap, phpldapadmin | rproxy bridge | -- |
| minio | minio | rproxy bridge | -- |
| ollama | ollama | rproxy bridge | -- |
| chisel | chisel | dual (macvlan + rproxy) | 192.168.59.0 |
| freeswitch | freeswitch | docker-servers-net | 192.168.59.40 |
| elastic-search | elasticsearch | docker-servers-net | 192.168.59.25 |
| synology-search | nas-solr, nas-tika | docker-servers-net | 192.168.59.31, 192.168.59.32 |

> **Note**: portainer-ce is standalone because Portainer cannot manage its own bootstrap stack via Terraform.

---

## Inactive Projects

| Project | Description |
|---|---|
| ansible-observability | Prometheus + Grafana for Ansible/AWX monitoring |
| docker-dns | Dynamic DNS for Docker containers |
| docker-vault | Legacy standalone Vault (replaced by Terraform-managed vault stack) |
| litellm | LiteLLM proxy + PostgreSQL |
| n8n-stack | n8n workflow automation + PostgreSQL |
| puppet | Puppet configuration management server |

---

## Network Configuration

| IP | Service |
|---|---|
| 192.168.59.0 | chisel |
| 192.168.59.2 | portainer |
| 192.168.59.3 | bind-dns (bind9) |
| 192.168.59.4 | github-runner |
| 192.168.59.10 | rust-server (hbbs) |
| 192.168.59.11 | rust-server (hbbr) |
| 192.168.59.12 | twingate-a |
| 192.168.59.22 | rundeck |
| 192.168.59.23 | postgres-rundeck |
| 192.168.59.24 | twingate-b |
| 192.168.59.25 | elastic-search |
| 192.168.59.28 | reverse-proxy (rproxy) |
| 192.168.59.31 | synology-search (nas-solr) |
| 192.168.59.32 | synology-search (nas-tika) |
| 192.168.59.40 | freeswitch |
| 172.24.0.x | rproxy bridge (registry, cloudflare-tunnel, vault, calibre, ldap, minio, ollama) |

---

## Storage Configuration

Persistent data stored on NAS via NFS mounts:

- `/nfs/dockermaster/docker/<service>` — per-service config and data
- `/nfs/calibre/` — Calibre library

---

## Security Notes

- All secrets are centralized in Vault (`http://vault.d.lcamaral.com`)
- Terraform sources credentials from Vault at runtime via `terraform/vault/`
- SSL certificates provisioned automatically by Cloudflare (via cloudflare-tunnel stack)
- Nginx certs cover `*.d.lcamaral.com`; tunnel uses `noTLSVerify` for origin
