# Remote Servers

- Access proxmox (Linux) server with `ssh proxmox`
- For execute sudo on proxmox, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer.sh`.
- Access NAS server (synology) with `ssh nas`
- Access dockermaster (Ubuntu Linux) server, repository of all home Docker container, with command `ssh dockermaster`
- For execute sudo on dockermaster, set this first `SUDO_ASKPASS=$HOME/.config/bin/answer`.
- Containers can run on internal LAN using Docker-servers-net, and still have access to internet.
    {
        "Name": "Docker-servers-net",
        "Id": "42c3a8018724a236c20c1470c97a1aa7ddc8c69ff0a2c7f1a01cdedf8d428e3d",
        "Created": "2025-03-31T11:26:54.534393079-06:00",
        "Scope": "local",
        "Driver": "macvlan",
        "EnableIPv4": true,
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "192.168.48.0/20",
                    "IPRange": "192.168.59.0/26",
                    "Gateway": "192.168.48.1",
                    "AuxiliaryAddresses": {
                        "host": "192.168.59.1"
                    }
                }
            ]
        },...
- GitHub runner service (GitHub-runner-homelab) is a Terraform-managed Portainer stack running on dockermaster for CI/CD.
- Vault server at <http://vault.d.lcamaral.com> (192.168.59.25) for secret management.
- Portainer at 192.168.59.2 for container management (Terraform-managed via `terraform/portainer/`).
- Docker registry at <https://registry.cf.lcamaral.com> (Terraform-managed Portainer stack).

# Infrastructure as Code (Terraform)

- All IaC lives under `terraform/` with independent state per domain:
  - `terraform/cloudflare/` -- Zone, DNS, tunnel, DreamHost wildcard (Cloudflare + DreamHost providers)
  - `terraform/portainer/` -- Portainer stacks, settings (Portainer provider)
  - `terraform/vault/` -- Secret engines, policies (Vault provider)
  - `terraform/modules/cf-service/` -- Reusable module for `*.cf.lcamaral.com` services
- See `terraform/README.md` for full auth, workflows, and credentials reference.

# DNS and Cloudflare Tunnel

- Domain `lcamaral.com` is registered at DreamHost (authoritative NS: ns1/ns2/ns3.dreamhost.com).
- Cloudflare zone is **partial** (CNAME setup, Free plan) -- DreamHost remains authoritative.
- Wildcard `*.cf.lcamaral.com` on DreamHost CNAMEs to Cloudflare edge for subdomain delegation.
- Cloudflare tunnel **bologna** routes `*.cf.lcamaral.com` traffic to `nginx-rproxy:443` on dockermaster.
- Tunnel uses `noTLSVerify` for origin (nginx certs are for `*.d.lcamaral.com`).
- Adding a new service: DNS record + tunnel ingress in `terraform/cloudflare/`, nginx vhost on dockermaster, Portainer stack in `terraform/portainer/`; if the service needs secrets, add a `vault_kv_secret_v2` data source in `terraform/portainer/vault.tf`.
- SSL certs are auto-provisioned by Cloudflare (free, ~90-day rotation).

# Secret Management

- All secrets are centralized in Vault. Only the Vault root token is in macOS Keychain (`vault-root-token`).
- Vault paths:
  - `secret/homelab/cloudflare` (API token + tunnel token)
  - `secret/homelab/dreamhost` (DreamHost API key)
  - `secret/homelab/portainer` (admin password)
  - `secret/homelab/twingate/sepia-hornet` (connector A tokens)
  - `secret/homelab/twingate/golden-mussel` (connector B tokens)
  - `secret/homelab/vault` (operational token)
  - `secret/homelab/calibre` (admin password)
  - `secret/homelab/github-runner` (GitHub PAT)
  - `secret/homelab/bind9/dnssec` (DNSSEC keys backup)
  - `secret/homelab/rundeck` (DB + storage converter passwords)
  - `secret/homelab/watchtower` (HTTP API token)
  - `secret/homelab/minio` (root user + password)
  - `secret/homelab/freeswitch` (ESL, SIP extension, calling card credentials)
  - `secret/homelab/keycloak` (admin + DB password)
  - `secret/homelab/keycloak/clients` (OIDC client secrets: `minio_client_secret`, `homelab_portal_secret`)
  - `secret/homelab/portal` (session signing + encryption keys for homelab-portal)
  - `secret/homelab/smtp` (DreamHost SMTP relay credentials for postfix-relay)
  - `secret/homelab/registry` (local Docker registry admin credentials)
- Terraform vars are sourced from Vault at runtime, never stored in files.

# Docker Services Structure

- Current and valid services are stored at dockermaster:/nfs/dockermaster/Docker/<service_name>/
- Each service has its own directory with Docker-compose.yml and configuration files
- Services use Docker-servers-net macvlan network for internal LAN communication
- Secrets should be stored in Vault at <http://vault.d.lcamaral.com>
- GitHub runner has read-only access to /nfs/dockermaster/Docker for deployments

# Inventory

- Document all servers, VMs and Containers on the files: `inventory/servers.md`, `inventory/virtual-machines.md`, and `inventory/docker-containers.md`
- Document all commands used and versions available, identifying the servers, on the file: `inventory/commands-available.md`
- Current project status and documents must be stored at `docs` directory.
  - Create documents for architecture, CI/CD, special scripts and or translations.
- Inventory documentation should be on `inventory`
- Use memory tool mcp to register documentation tips, keywords or indexes

# General Instructions

- Use the MCP think-tool, documentation, context7, and filesystem as preferences.
- Keep an updated note of this project using MCP memory.
- Use any other MCP available that can improve the results or facilitate the task you are working with or planning.
- _Always plan the task and optimize on subtasks that can be executed in parallel. Then spinout subagents with very refined and detailed instructions to complete those tasks. Instruct these agents to always use sequentialthinking and any other MCP relevant to their tasks._
- Docker Compose use `docker compose` command. Always use the latest Docker ce version.
- Use memory MCP to enhance context before each task.
- Register entities, relations and notes about the project on memory MCP.
- Don't consider using frameworks, tools or systems that are under a paywall of any sort. Even if have a freetier.
- Use multiple sub-agents to perform tasks organized by to do. The agents must receive detailed instructions, use think-tool and Sonnet model.
- We use mise, and should use mise if a different version of npm or any tool is needed.
- Create branches for big changes
- Commit between feature implementations
- Keep branches for history, don't delete them unless commanded to do it
- Prefer to use GitHub MCP over gh command when possible
