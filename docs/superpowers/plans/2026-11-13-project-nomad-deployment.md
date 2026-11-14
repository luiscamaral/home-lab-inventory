# Project NOMAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Project NOMAD (`nomad_admin`, `mysql`, `redis`, `disk-collector`) + a co-located
`litellm` AI router on `dockerserver-2` (`ds-2`), reachable internally at
`https://nomad.d.lcamaral.com`, fully managed via Terraform + Portainer.

**Architecture:** 5-container Compose stack on `dockerserver-2` (Portainer endpoint 13) attached to
`docker-servers-net` macvlan (`192.168.59.60`), `rproxy`, and `project-nomad_default` bridge
networks, fronted by the 3-host `nginx-rproxy` fleet. `litellm` routes RAG embeddings
(`nomic-embed-text:v1.5`) to the existing `ollama` service on `ds-1` (`192.168.59.53:11434`) and
routes chat completions to external/subscription AI models using credentials from Vault.

**Tech Stack:** Docker Compose, Portainer, Terraform (`portainer` + `vault` providers), LiteLLM
Proxy, Ollama, MySQL 8.0, Redis 7, Nginx, Pi-hole dnsmasq.

**Spec:** [Project NOMAD deployment design](../specs/2026-11-13-project-nomad-deployment-design.md)

---

## Conventions

- All file paths are relative to the repo root.
- All `ssh` commands use the shortcuts in `~/.ssh/config` (`dockermaster`, `dockerserver-1`,
  `dockerserver-2`).
- For `sudo` on `dockerserver-1` / `dockerserver-2`, set
  `SUDO_ASKPASS=$HOME/.config/bin/answer` with `sudo -A` if prompted.
- Vault root token is in macOS Keychain (`vault-root-token`). Source it once per shell:

  ```bash
  export VAULT_ADDR=http://192.168.59.25:8200
  export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
  ```

---

## File Structure

| Action | Path | Purpose |
|--------|------|---------|
| Create | `dockermaster/docker/compose/nomad/litellm-config.yaml` | LiteLLM Proxy model routing config (local Ollama embeddings + external chat models) |
| Create | `dockermaster/docker/compose/nomad/docker-compose.yml.tftpl` | Compose stack template rendered by Terraform |
| Create | `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf` | Nginx HTTPS vhost (auto-bundled into all 3 `rproxy` stacks via `fileset()`) |
| Modify | `pihole/dnsmasq.d/04-d-lcamaral-com.conf` | Add 3 multi-A records for `nomad.d.lcamaral.com` |
| Modify | `terraform/portainer/vault.tf` | Add `data "vault_kv_secret_v2" "nomad"` |
| Modify | `terraform/portainer/stacks.tf` | Add `resource "portainer_stack" "nomad"` on `var.ds2_endpoint_id` |
| Modify | `inventory/docker-containers.md` | Document the new stack and `.59.60` IP assignment |

---

## Task 1: Pre-flight Verifications & Host Directories

**Files:** None (verification + host directory preparation).

- [ ] **Step 1.1: Verify `dockerserver-2` disk space and host health**

```bash
ssh dockerserver-2 'df -h / /nfs/dockermaster'
```

Expected: `/` has >15 GB free (for MySQL/Redis + Docker images) and `/nfs/dockermaster` is mounted
from the NAS with >500 GB free.

- [ ] **Step 1.2: Verify `192.168.59.60` is unused on `docker-servers-net`**

```bash
ssh dockerserver-2 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A arping -I server-net-shim -c 3 192.168.59.60'
```

Expected: `Received 0 response(s)` (exit code 1). If any reply is received, stop and pick another
unused IP (e.g., `.61`, `.14`, `.8`, `.5`) and update the spec + plan before continuing.

- [ ] **Step 1.3: Pull `nomic-embed-text:v1.5` on `dockerserver-1` Ollama**

Project NOMAD hardcodes `nomic-embed-text:v1.5` (768 dimensions, ~275 MB) for Qdrant Knowledge Base
embeddings. Pull it onto the existing `ollama` container on `ds-1`:

```bash
ssh dockerserver-1 'docker exec ollama ollama pull nomic-embed-text:v1.5 && docker exec ollama ollama list'
```

Expected: `nomic-embed-text:v1.5` appears in `ollama list` alongside `qwen3-embedding:8b-q8_0`.

- [ ] **Step 1.4: Verify `ds-2` can reach `ds-1` Ollama (`192.168.59.53:11434`)**

```bash
ssh dockerserver-2 'curl -sf http://192.168.59.53:11434/api/tags | grep nomic-embed-text'
```

Expected: matching JSON output containing `nomic-embed-text:v1.5`.

- [ ] **Step 1.5: Create NFS storage and local SSD state directories on `dockerserver-2`**

```bash
ssh dockerserver-2 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A mkdir -p \
  /nfs/dockermaster/nomad/storage/logs \
  /opt/project-nomad/mysql \
  /opt/project-nomad/redis && \
  SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A touch /nfs/dockermaster/nomad/storage/logs/admin.log && \
  ls -la /nfs/dockermaster/nomad/ /opt/project-nomad/'
```

Expected: `/nfs/dockermaster/nomad/storage/logs/admin.log` and `/opt/project-nomad/{mysql,redis}`
exist.

---

## Task 2: Store Secrets in Vault

**Files:** None (Vault external state).

- [ ] **Step 2.1: Authenticate to Vault**

```bash
export VAULT_ADDR=http://192.168.59.25:8200
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
vault status
```

Expected: `Sealed: false`.

- [ ] **Step 2.2: Generate NOMAD credentials and write `secret/homelab/nomad`**

If `secret/homelab/honcho` already has an `openrouter_api_key`, reuse it (or supply your preferred
external AI API key):

```bash
NOMAD_APP_KEY=$(openssl rand -hex 16)
NOMAD_DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
NOMAD_MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
OPENROUTER_KEY=$(vault kv get -field=openrouter_api_key secret/homelab/honcho 2>/dev/null || echo "REPLACE_WITH_API_KEY")

vault kv put secret/homelab/nomad \
  app_key="$NOMAD_APP_KEY" \
  db_password="$NOMAD_DB_PASSWORD" \
  mysql_root_password="$NOMAD_MYSQL_ROOT_PASSWORD" \
  openrouter_api_key="$OPENROUTER_KEY"
```

- [ ] **Step 2.3: Verify Vault secret keys**

```bash
vault kv get -format=json secret/homelab/nomad | jq '.data.data | keys'
```

Expected: `["app_key", "db_password", "mysql_root_password", "openrouter_api_key"]`.

---

## Task 3: Create LiteLLM Config & Docker Compose Template

**Files:**

- Create: `dockermaster/docker/compose/nomad/litellm-config.yaml`
- Create: `dockermaster/docker/compose/nomad/docker-compose.yml.tftpl`

- [ ] **Step 3.1: Create `dockermaster/docker/compose/nomad/litellm-config.yaml`**

```yaml
# LiteLLM Proxy configuration for Project NOMAD
# - Routes nomic-embed-text:v1.5 (768-dim) to local Ollama on ds-1 (192.168.59.53:11434)
# - Routes chat models to external/subscription AI providers via API key from Vault

model_list:
  # Required by Project NOMAD RagService (EMBEDDING_MODEL_NAME = 'nomic-embed-text:v1.5')
  - model_name: nomic-embed-text:v1.5
    litellm_params:
      model: ollama/nomic-embed-text:v1.5
      api_base: http://192.168.59.53:11434

  # External Chat Models (OpenRouter)
  - model_name: deepseek-v4-flash
    litellm_params:
      model: openrouter/deepseek/deepseek-v4-flash:free
      api_key: os.environ/OPENROUTER_API_KEY

  - model_name: claude-sonnet-4
    litellm_params:
      model: openrouter/anthropic/claude-sonnet-4
      api_key: os.environ/OPENROUTER_API_KEY

  - model_name: gpt-4o-mini
    litellm_params:
      model: openrouter/openai/gpt-4o-mini
      api_key: os.environ/OPENROUTER_API_KEY

litellm_settings:
  drop_params: true
  telemetry: false
```

- [ ] **Step 3.2: Create `dockermaster/docker/compose/nomad/docker-compose.yml.tftpl`**

Note: Terraform `templatefile()` interpolates `${ indent(4, litellm_config) }`, while Docker
Compose/Portainer interpolates `$${NOMAD_APP_KEY}` etc. at runtime from the stack `env` block.

```yaml
# Project NOMAD + LiteLLM AI Router — dockerserver-2
# Spec: docs/superpowers/specs/2026-11-13-project-nomad-deployment-design.md
# Managed by Terraform (terraform/portainer/stacks.tf -> portainer_stack.nomad)
name: project-nomad

configs:
  litellm_config:
    content: |
      ${indent(6, litellm_config)}

services:
  admin:
    image: ghcr.io/crosstalk-solutions/project-nomad:latest
    container_name: nomad_admin
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    expose:
      - "8080"
    volumes:
      - /nfs/dockermaster/nomad/storage:/app/storage
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - NODE_ENV=production
      - NOMAD_STORAGE_PATH=/nfs/dockermaster/nomad/storage
      - PORT=8080
      - LOG_LEVEL=info
      - APP_KEY=$${NOMAD_APP_KEY}
      - HOST=0.0.0.0
      - URL=https://nomad.d.lcamaral.com
      - DB_HOST=mysql
      - DB_PORT=3306
      - DB_DATABASE=nomad
      - DB_USER=nomad_user
      - DB_PASSWORD=$${NOMAD_DB_PASSWORD}
      - DB_NAME=nomad
      - DB_SSL=false
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - DISABLE_COMPRESSION=false
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      servers-net:
        ipv4_address: 192.168.59.60
      rproxy:
      default:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "nomad"
      com.docker.service: "nomad-admin"
      portainer.autodeploy: "false"

  mysql:
    image: mysql:8.0
    container_name: nomad_mysql
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=$${NOMAD_MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=nomad
      - MYSQL_USER=nomad_user
      - MYSQL_PASSWORD=$${NOMAD_DB_PASSWORD}
    volumes:
      - /opt/project-nomad/mysql:/var/lib/mysql
    networks:
      - default
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 10
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "false"
      com.docker.stack: "nomad"
      com.docker.service: "nomad-mysql"
      portainer.autodeploy: "false"

  redis:
    image: redis:7-alpine
    container_name: nomad_redis
    restart: unless-stopped
    volumes:
      - /opt/project-nomad/redis:/data
    networks:
      - default
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "false"
      com.docker.stack: "nomad"
      com.docker.service: "nomad-redis"
      portainer.autodeploy: "false"

  disk-collector:
    image: ghcr.io/crosstalk-solutions/project-nomad-disk-collector:latest
    container_name: nomad_disk_collector
    restart: unless-stopped
    volumes:
      - /:/host:ro,rslave
      - /nfs/dockermaster/nomad/storage:/storage
    networks:
      - default
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "nomad"
      com.docker.service: "nomad-disk-collector"
      portainer.autodeploy: "false"

  litellm:
    image: ghcr.io/berriai/litellm:main-stable
    container_name: nomad_litellm
    restart: unless-stopped
    command: ["--config", "/etc/litellm/config.yaml", "--port", "4000"]
    configs:
      - source: litellm_config
        target: /etc/litellm/config.yaml
    environment:
      - OPENROUTER_API_KEY=$${OPENROUTER_API_KEY}
      - LITELLM_LOG=INFO
    expose:
      - "4000"
    networks:
      - default
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness', timeout=3)\""]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "nomad"
      com.docker.service: "nomad-litellm"
      portainer.autodeploy: "false"

networks:
  servers-net:
    external: true
    name: docker-servers-net
  rproxy:
    external: true
    name: rproxy
  default:
    name: project-nomad_default
    driver: bridge
```

---

## Task 4: Add Nginx Vhost & Internal DNS Record

**Files:**

- Create: `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf`
- Modify: `pihole/dnsmasq.d/04-d-lcamaral-com.conf`

- [ ] **Step 4.1: Create `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf`**

```nginx
server {
    listen 443 ssl http2;
    server_name nomad.d.lcamaral.com;

    ssl_certificate     /etc/nginx/certs/d.lcamaral.com.crt;
    ssl_certificate_key /etc/nginx/certs/d.lcamaral.com.key;

    client_max_body_size 500m;

    location / {
        proxy_pass         http://192.168.59.60:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_buffering    off;
        proxy_read_timeout 300s;
    }
}
```

- [ ] **Step 4.2: Add `nomad.d.lcamaral.com` multi-A records to `pihole/dnsmasq.d/04-d-lcamaral-com.conf`**

Append under the HA Nginx reverse proxy section:

```ini
address=/nomad.d.lcamaral.com/192.168.59.28
address=/nomad.d.lcamaral.com/192.168.59.48
address=/nomad.d.lcamaral.com/192.168.59.49
```

---

## Task 5: Wire Terraform (`vault.tf` & `stacks.tf`) and Apply

**Files:**

- Modify: `terraform/portainer/vault.tf`
- Modify: `terraform/portainer/stacks.tf`

- [ ] **Step 5.1: Add `data "vault_kv_secret_v2" "nomad"` to `terraform/portainer/vault.tf`**

```hcl
data "vault_kv_secret_v2" "nomad" {
  mount = "secret"
  name  = "homelab/nomad"
}
```

- [ ] **Step 5.2: Add `resource "portainer_stack" "nomad"` to `terraform/portainer/stacks.tf`**

```hcl
# ──────────────────────────────────────────────
# Project NOMAD + LiteLLM AI Router (ds-2)
# Spec: docs/superpowers/specs/2026-11-13-project-nomad-deployment-design.md
# Single macvlan IP 192.168.59.60 for nomad_admin; litellm runs on
# project-nomad_default bridge network and routes embeddings to ds-1
# Ollama (192.168.59.53:11434) + chat to external AI via Vault key.
# ──────────────────────────────────────────────
resource "portainer_stack" "nomad" {
  name            = "nomad"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/../../dockermaster/docker/compose/nomad/docker-compose.yml.tftpl", {
    litellm_config = file("${path.module}/../../dockermaster/docker/compose/nomad/litellm-config.yaml")
  })

  env {
    name  = "NOMAD_APP_KEY"
    value = data.vault_kv_secret_v2.nomad.data["app_key"]
  }

  env {
    name  = "NOMAD_DB_PASSWORD"
    value = data.vault_kv_secret_v2.nomad.data["db_password"]
  }

  env {
    name  = "NOMAD_MYSQL_ROOT_PASSWORD"
    value = data.vault_kv_secret_v2.nomad.data["mysql_root_password"]
  }

  env {
    name  = "OPENROUTER_API_KEY"
    value = data.vault_kv_secret_v2.nomad.data["openrouter_api_key"]
  }
}
```

- [ ] **Step 5.3: Run `terraform plan` and `terraform apply` in `terraform/portainer`**

```bash
export VAULT_ADDR=http://192.168.59.25:8200
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
export TF_VAR_portainer_password=$(vault kv get -field=admin_password secret/homelab/portainer)

terraform -chdir=terraform/portainer plan
```

Expected:

- 1 to add (`portainer_stack.nomad`)
- 5 to update in-place (`reverse_proxy`, `reverse_proxy_2`, `reverse_proxy_3` for the new vhost;
  `pihole_2`, `pihole_3` for the new DNS record).

After reviewing the plan:

```bash
terraform -chdir=terraform/portainer apply
```

> **Note:** Because `reverse_proxy*` and `pihole_*` receive updated inline `configs:`, redeploy
> those stacks via `scripts/portainer-redeploy.py` if Portainer does not automatically recreate
> their containers on `configs:` content changes.

---

## Task 6: Verification & Inventory Update

**Files:**

- Modify: `inventory/docker-containers.md`

- [ ] **Step 6.1: Verify all 5 containers in the `nomad` stack are healthy on `ds-2`**

```bash
ssh dockerserver-2 'docker ps --filter "label=com.docker.stack=nomad" --format "table {{.Names}}\t{{.Status}}"'
```

Expected: `nomad_admin`, `nomad_mysql`, `nomad_redis`, `nomad_litellm` all `Up ... (healthy)`, and
`nomad_disk_collector` `Up ...`.

- [ ] **Step 6.2: Verify LiteLLM serves both `nomic-embed-text:v1.5` and chat models**

```bash
ssh dockerserver-2 'docker exec nomad_admin curl -sf http://litellm:4000/v1/models | jq ".data[].id"'
```

Expected: lists `"nomic-embed-text:v1.5"`, `"deepseek-v4-flash"`, `"claude-sonnet-4"`,
`"gpt-4o-mini"`.

- [ ] **Step 6.3: Test embedding round-trip through LiteLLM → `ds-1` Ollama**

```bash
ssh dockerserver-2 'docker exec nomad_admin curl -sf http://litellm:4000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"nomic-embed-text:v1.5\", \"input\": [\"search_query: water purification\"]}" \
  | jq ".data[0].embedding | length"'
```

Expected: `768`.

- [ ] **Step 6.4: Verify HTTPS reachability via `nomad.d.lcamaral.com`**

```bash
curl -sf https://nomad.d.lcamaral.com/api/health
```

Expected: HTTP 200 JSON health response.

- [ ] **Step 6.5: Configure Remote AI URL in Project NOMAD UI**

1. Open `https://nomad.d.lcamaral.com` in the browser.
2. Navigate to **Settings → AI Assistant → Remote Connection**.
3. Set **Remote Ollama / OpenAI API URL** to `http://litellm:4000` and save.

- [ ] **Step 6.6: Update `inventory/docker-containers.md` and commit**

Add the `nomad` stack under `dockerserver-2 (VM 124)`, `.60` in the `docker-servers-net` IP table,
and `nomad` in the Terraform-managed Portainer stacks table. Commit all changes following
conventional commit conventions (`feat(docker): add Project NOMAD and LiteLLM stack on ds-2`).
