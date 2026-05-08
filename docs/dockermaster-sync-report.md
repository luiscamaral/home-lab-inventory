# Dockermaster Synchronization Report

**Date:** 2025-08-27  
**Source:** dockermaster:/nfs/dockermaster/Docker/  
**Repository:** home-lab-inventory

## 📊 Service Inventory Summary

### Total Services on Dockermaster: 32

### Services in Repository: 12

### Services Missing from Repository: 20

## 🔍 Detailed Comparison

### ✅ Services Present in Both (12)

| Service | Dockermaster Path | Repository Path | Status |
|---------|------------------|-----------------|--------|
| Ansible-observability | `/docker/ansible-observability/` | `/dockermaster/docker/compose/ansible-observability/` | Active |
| bind9 | `/docker/bind9/` | `/dockermaster/docker/compose/bind9/` | Active |
| calibre-server | `/docker/calibre-server/` | `/dockermaster/docker/compose/calibre-server/` | Active |
| Docker-dns | `/docker/docker-dns/` | `/dockermaster/docker/compose/docker-dns/` | Active |
| Docker-vault | `/docker/docker-vault/` | `/dockermaster/docker/compose/docker-vault/` | Active |
| litellm | `/docker/litellm/` | `/dockermaster/docker/compose/litellm/` | Mixed |
| n8n-stack | `/docker/n8n-stack/` | `/dockermaster/docker/compose/n8n-stack/` | Not Running |
| Nginx-rproxy | `/docker/nginx-rproxy/` | `/dockermaster/docker/compose/nginx-rproxy/` | Active |
| ollama | `/docker/ollama/` | `/dockermaster/docker/compose/ollama/` | Active |
| portainer | `/docker/portainer/` | `/dockermaster/docker/compose/portainer/` | Active |
| puppet | `/docker/puppet/` | `/dockermaster/docker/compose/puppet/` | Not Running |
| rundeck | `/docker/rundeck/` | `/dockermaster/docker/compose/rundeck/` | Active |

### 🆕 Services Only on Dockermaster (20)

| Service | Path | Container Status | Priority |
|---------|------|-----------------|----------|
| **GitHub-runner** | `/docker/github-runner/` | ✅ Running | **HIGH** - CI/CD |
| **vault** | `/docker/vault/` | ⚠️ Unhealthy | **HIGH** - Security |
| **keycloak** | `/docker/keycloak/` | ✅ Starting | **HIGH** - Auth |
| **rabbitmq** | `/docker/rabbitmq/` | ❌ Exited | **MEDIUM** |
| **Prometheus** | `/docker/prometheus/` | Not Deployed | **HIGH** - Monitoring |
| Ansible-stack | `/docker/ansible-stack/` | Not Deployed | LOW |
| bitwarden | `/docker/bitwarden/` | Not Deployed | LOW |
| docspell | `/docker/docspell/` | ❌ Exited | LOW |
| fluentd | `/docker/fluentd/` | Not Deployed | LOW |
| ghost.io | `/docker/ghost.io/` | Not Deployed | LOW |
| Grafana(old) | `/docker/grafana(old)/` | Not Deployed | DEPRECATED |
| home-lab-inventory | `/docker/home-lab-inventory/` | Meta-repo | SKIP |
| kafka | `/docker/kafka/` | Not Deployed | LOW |
| MongoDB | `/docker/mongodb/` | Not Deployed | LOW |
| network | `/docker/network/` | Config Only | INFO |
| opentelemetry-home | `/docker/opentelemetry-home/` | Not Deployed | LOW |
| otel | `/docker/otel/` | Not Deployed | LOW |
| pablo | `/docker/pablo/` | Not Deployed | PERSONAL |
| Prometheus.new | `/docker/prometheus.new/` | Not Deployed | TESTING |
| solr | `/docker/solr/` | ❌ Exited | LOW |

## 🐳 Currently Running Containers

### Active Services (10)

1. **GitHub-runner-homelab** - `myoung34/github-runner:latest` - ✅ Healthy
2. **keycloak** - `keycloak/keycloak:26.3` - 🔄 Starting
3. **postgres** (Keycloak) - `postgres:17` - ✅ Healthy
4. **rproxy** - `nginx:1.27` - ✅ Running
5. **bind-dns-bind9-1** - `ubuntu/bind9:9.20-24.10_edge` - ✅ Running
6. **vault** - `hashicorp/vault:1.16` - ⚠️ Unhealthy
7. **portainer** - `portainer/portainer-ce:latest` - ✅ Running
8. **rundeck** + postgres - ✅ Running
9. **calibre** + calibre-web - ✅ Running
10. **ollama** - `ollama/ollama` - ✅ Running

### Stopped/Exited Services (6)

1. **rabbitmq** - Exited 22 hours ago
2. **Docspell** stack - All containers exited
3. **litellm** - Exited 6 weeks ago
4. **crawl4ai** - Exited 6 weeks ago

## 🔄 Migration Requirements

### High Priority Services to Add

1. **GitHub-runner** - Critical for CI/CD pipeline
2. **vault** - Central secret management (needs health fix)
3. **keycloak** - Authentication service
4. **Prometheus** - Monitoring infrastructure

### Directory Structure Change Required

```bash
# Current Structure (Repository)
dockermaster/docker/compose/<service_name>/docker-compose.yml

# Target Structure (Dockermaster)
dockermaster/docker/<service_name>/docker-compose.yml
```

## 🔐 Secret Management Status

### Services with Hardcoded Secrets

- Ansible-observability: `GF_SECURITY_ADMIN_PASSWORD`
- Multiple services: Database passwords
- GitHub runner: `ACCESS_TOKEN` (in .env)

### Vault Migration Plan

All secrets should be migrated to:

- **Vault URL:** <http://vault.d.lcamaral.com>
- **Path Structure:** `secret/dockermaster/<service_name>/<key>`

## 📋 Next Steps

1. **Immediate Actions**
   - Fix Vault container health issue
   - Add GitHub-runner service to repository
   - Migrate repository structure to match dockermaster

2. **Portainer Integration**
   - Configure all services as Portainer stacks
   - Set up GitOps with repository
   - Enable webhook deployments

3. **Secret Migration**
   - Store all secrets in Vault
   - Configure GitHub runner Vault access
   - Update Docker-compose files with placeholders

## 🌐 Network Configuration

**Network:** Docker-servers-net (macvlan)

- **Subnet:** 192.168.48.0/20
- **IP Range:** 192.168.59.0/26
- **Gateway:** 192.168.48.1

### Assigned IPs

- 192.168.59.2 - Portainer
- 192.168.59.20 - Prometheus
- 192.168.59.21 - Grafana
- 192.168.59.28 - Nginx Reverse Proxy
- 192.168.59.30 - N8N

## 📝 Notes

- The `home-lab-inventory` folder on dockermaster appears to be a meta-repository
- `grafana(old)` should be deprecated in favor of Ansible-observability stack
- Several services have volume mounts to `/nfs/dockermaster/volumes/`
- GitHub runner has read-only access to `/deployment` path
