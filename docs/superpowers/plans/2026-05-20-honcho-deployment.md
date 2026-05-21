# Honcho Memory Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Honcho memory server on `dockerserver-1` reachable internally as
`honcho.d.lcamaral.com`, fully managed via Terraform + Portainer.

**Architecture:** 4-container Compose stack (`api` + `deriver` + pgvector-db + `redis`) on the
`docker-servers-net` macvlan, fronted by the existing 3-instance Nginx reverse-proxy fleet.
Chat LLM calls go to OpenRouter free tier; embeddings go to the existing Ollama on ds-2.

**Tech Stack:** Docker Compose, Portainer, Terraform (portainer + vault providers), Nginx,
PostgreSQL with pgvector, Redis, dnsmasq.

**Spec:** [Honcho deployment design](../specs/2026-05-20-honcho-deployment-design.md)

---

## Conventions

- All file paths are relative to the repo root.
- All `ssh` commands use the shortcuts already in `~/.ssh/config`
  (`dockerserver-1`, `dockerserver-2`, `proxmox`).
- `terraform` commands run from `terraform/portainer/` unless specified otherwise.
- Pre-commit hooks enforce markdownlint + commit format. Commit type/scope must use
  conventional commits with scope from the allowlist (`docker`, `inventory`, `docs`, etc.).
- Vault root token is in macOS Keychain (`vault-root-token`). Source it once per shell:

  ```bash
  export VAULT_ADDR=http://vault.d.lcamaral.com
  export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
  ```

---

## File Structure

| Action | Path | Purpose |
|--------|------|---------|
| Create | `dockermaster/docker/compose/honcho/docker-compose.yml.tftpl` | Compose stack (templated for Vault env injection) |
| Create | `dockermaster/docker/compose/honcho/database-init.sql` | pgvector extension creation, vendored from upstream |
| Create | `dockermaster/docker/compose/nginx-rproxy/vhost.d/honcho.d.lcamaral.com.conf` | Nginx vhost — auto-picked by `fileset()` in stacks.tf |
| Modify | `pihole/dnsmasq.d/04-d-lcamaral-com.conf` | Add 3 multi-A records for `honcho.d.lcamaral.com` |
| Modify | `terraform/portainer/vault.tf` | Add `data "vault_kv_secret_v2" "honcho"` |
| Modify | `terraform/portainer/stacks.tf` | Add `resource "portainer_stack" "honcho"` |
| Modify | `inventory/docker-containers.md` | Document the new stack |

---

## Task 1: Pre-flight verifications

**Files:** None (pure verification, no edits).

These checks are non-destructive and can be re-run any time. Run them up-front so we don't
discover IP collisions or missing Ollama models after writing 200 lines of Terraform.

- [ ] **Step 1.1: Confirm Proxmox + LXC inventory unchanged**

```bash
ssh proxmox 'SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A pct list'
```

Expected: `9000 tmpl-debian-devops`, `10000 pihole`, `10010 openclaw` (stopped),
`10020 hermes` (running). Confirms we're still in sync with `inventory/virtual-machines.md`.

- [ ] **Step 1.2: Arping the chosen macvlan IP for collisions**

```bash
ssh dockerserver-1 'ip -o link show | grep -E "macvlan|server-net"'
```

Expected: shows the macvlan parent interface name. If the name is NOT `server-net-shim`,
substitute the correct name below.

```bash
ssh dockerserver-1 'sudo arping -I server-net-shim -c 3 192.168.59.47'
```

Expected: `Received 0 replies`. If ANY reply, do NOT proceed — pick a different free IP
from the .59.0/26 range (gaps documented in spec §6.1) and update the spec + plan
references before continuing.

- [ ] **Step 1.3: Verify Ollama qwen3-embedding:8b-q8_0 model is pulled on ds-2**

```bash
ssh dockerserver-2 'docker exec ollama ollama list | grep qwen3-embedding:8b-q8_0'
```

If found: continue.
If missing:

```bash
ssh dockerserver-2 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'
```

Re-run the `list` check to confirm.

- [ ] **Step 1.4: Verify Ollama is reachable on the network**

```bash
ssh dockerserver-1 'curl -sf http://ollama.d.lcamaral.com/api/tags | head -c 200'
```

Expected: JSON with `models: [...]` array including `qwen3-embedding:8b-q8_0`. If DNS fails,
grep `pihole/dnsmasq.d/` for an `ollama` entry; add one if missing (out of scope for this
plan — log a follow-up issue).

- [ ] **Step 1.5: Create NFS directories on ds-1**

```bash
ssh dockerserver-1 'sudo mkdir -p /nfs/dockermaster/honcho/{pgdata,redis-data} && \
                    sudo chown -R 999:999 /nfs/dockermaster/honcho/pgdata && \
                    sudo chown -R 999:999 /nfs/dockermaster/honcho/redis-data && \
                    ls -la /nfs/dockermaster/honcho/'
```

Expected: both dirs listed, owned by uid 999 (PostgreSQL + Redis containers run as 999).

- [ ] **Step 1.6: Commit the pre-flight findings if anything was discovered**

Nothing to commit yet — this task is read-only. Move on.

---

## Task 2: Add Vault secrets

**Files:** None (Vault is external state; not version-controlled here).

- [ ] **Step 2.1: Source the Vault root token**

```bash
export VAULT_ADDR=http://vault.d.lcamaral.com
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
vault status
```

Expected: `Sealed: false`, `HA Mode: active`.

- [ ] **Step 2.2: Generate a postgres password locally**

```bash
HONCHO_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
echo "Generated DB password: $HONCHO_DB_PASSWORD"
```

Save the printed value somewhere ephemeral (paste buffer); don't commit it.

- [ ] **Step 2.3: Get the OpenRouter API key**

You must already have an OpenRouter account and free-tier API key (starts with `sk-or-`).
If not, sign up at <https://openrouter.ai>, generate a key, and save it.

- [ ] **Step 2.4: Write both secrets to Vault**

```bash
vault kv put secret/homelab/honcho \
  openrouter_api_key='sk-or-...your-actual-key...' \
  postgres_password="$HONCHO_DB_PASSWORD"
```

Expected: `Success! Data written to: secret/homelab/honcho`.

- [ ] **Step 2.5: Verify the secret round-trips**

```bash
vault kv get -field=openrouter_api_key secret/homelab/honcho | head -c 20; echo
vault kv get -field=postgres_password secret/homelab/honcho | head -c 20; echo
```

Expected: first 20 chars of each value print. Nothing committed yet.

---

## Task 3: Vendor the database init SQL

**Files:**

- Create: `dockermaster/docker/compose/honcho/database-init.sql`

- [ ] **Step 3.1: Create the directory and file**

```bash
mkdir -p dockermaster/docker/compose/honcho
cat > dockermaster/docker/compose/honcho/database-init.sql <<'EOF'
-- Honcho database init: enable pgvector extension on first boot.
-- Mirrored from upstream: https://github.com/plastic-labs/honcho/blob/main/database/init.sql
CREATE EXTENSION IF NOT EXISTS vector;
EOF
```

- [ ] **Step 3.2: Verify the file contents**

```bash
cat dockermaster/docker/compose/honcho/database-init.sql
```

Expected: 3 lines (comment + comment + `CREATE EXTENSION IF NOT EXISTS vector;`).

- [ ] **Step 3.3: Commit**

```bash
git add dockermaster/docker/compose/honcho/database-init.sql
git commit -m "feat(docker): vendor honcho database init.sql (pgvector extension)"
```

---

## Task 4: Write the Compose stack template

**Files:**

- Create: `dockermaster/docker/compose/honcho/docker-compose.yml.tftpl`

- [ ] **Step 4.1: Write the Compose template**

```bash
cat > dockermaster/docker/compose/honcho/docker-compose.yml.tftpl <<'EOF'
name: honcho

# Honcho memory server — internal-only deployment on ds-1.
# Spec: docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
# Chat LLM via OpenRouter free tier; embeddings via Ollama on ds-2.
# Templated by Terraform: $${OPENROUTER_API_KEY} and $${HONCHO_DB_PASSWORD}
# are injected via portainer_stack `env {}` blocks, sourced from Vault.

networks:
  servers-net:
    name: docker-servers-net
    external: true
  rproxy:
    external: true
  honcho-internal:
    driver: bridge

services:
  api:
    image: ghcr.io/plastic-labs/honcho:latest
    container_name: honcho-api
    hostname: honcho-api
    networks:
      servers-net:
        ipv4_address: 192.168.59.47
      rproxy:
      honcho-internal:
    expose:
      - 8000
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      LOG_LEVEL: INFO
      AUTH_USE_AUTH: "false"
      DB_CONNECTION_URI: "postgresql+psycopg://honcho:$${HONCHO_DB_PASSWORD}@db:5432/honcho"
      CACHE_URL: "redis://redis:6379/0?suppress=true"
      CACHE_ENABLED: "true"
      # Chat features → OpenRouter (single model across all to consolidate quota)
      OPENROUTER_API_KEY: "$${OPENROUTER_API_KEY}"
      DERIVER_MODEL_CONFIG__TRANSPORT: openai
      DERIVER_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DERIVER_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      SUMMARY_MODEL_CONFIG__TRANSPORT: openai
      SUMMARY_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      SUMMARY_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DIALECTIC_LEVELS__minimal__MODEL_CONFIG__TRANSPORT: openai
      DIALECTIC_LEVELS__minimal__MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DIALECTIC_LEVELS__low__MODEL_CONFIG__TRANSPORT: openai
      DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DIALECTIC_LEVELS__medium__MODEL_CONFIG__TRANSPORT: openai
      DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DIALECTIC_LEVELS__high__MODEL_CONFIG__TRANSPORT: openai
      DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DIALECTIC_LEVELS__max__MODEL_CONFIG__TRANSPORT: openai
      DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT: openai
      DREAM_DEDUCTION_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT: openai
      DREAM_INDUCTION_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      # Embeddings → Ollama on ds-2 (zero per-call cost)
      EMBED_MESSAGES: "true"
      EMBEDDING_VECTOR_DIMENSIONS: "4096"
      EMBEDDING_MODEL_CONFIG__TRANSPORT: openai
      EMBEDDING_MODEL_CONFIG__MODEL: qwen3-embedding:8b-q8_0
      EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL: http://ollama.d.lcamaral.com/v1
      EMBEDDING_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OLLAMA_API_KEY
      OLLAMA_API_KEY: ollama
      # Workers: all enabled (spec §11)
      METRICS_ENABLED: "true"
    healthcheck:
      test:
        - CMD
        - /app/.venv/bin/python
        - -c
        - "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2).read()"
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "honcho"
      com.docker.service: "api"
      portainer.autodeploy: "false"

  deriver:
    image: ghcr.io/plastic-labs/honcho:latest
    container_name: honcho-deriver
    hostname: honcho-deriver
    entrypoint: ["/app/.venv/bin/python", "-m", "src.deriver"]
    networks:
      honcho-internal:
    depends_on:
      api:
        condition: service_healthy
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      LOG_LEVEL: INFO
      DB_CONNECTION_URI: "postgresql+psycopg://honcho:$${HONCHO_DB_PASSWORD}@db:5432/honcho"
      CACHE_URL: "redis://redis:6379/0?suppress=true"
      CACHE_ENABLED: "true"
      OPENROUTER_API_KEY: "$${OPENROUTER_API_KEY}"
      DERIVER_MODEL_CONFIG__TRANSPORT: openai
      DERIVER_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DERIVER_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      SUMMARY_MODEL_CONFIG__TRANSPORT: openai
      SUMMARY_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      SUMMARY_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT: openai
      DREAM_DEDUCTION_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT: openai
      DREAM_INDUCTION_MODEL_CONFIG__MODEL: deepseek/deepseek-v4-flash:free
      DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL: https://openrouter.ai/api/v1
      DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OPENROUTER_API_KEY
      EMBED_MESSAGES: "true"
      EMBEDDING_VECTOR_DIMENSIONS: "4096"
      EMBEDDING_MODEL_CONFIG__TRANSPORT: openai
      EMBEDDING_MODEL_CONFIG__MODEL: qwen3-embedding:8b-q8_0
      EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL: http://ollama.d.lcamaral.com/v1
      EMBEDDING_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: OLLAMA_API_KEY
      OLLAMA_API_KEY: ollama
    restart: unless-stopped
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "honcho"
      com.docker.service: "deriver"
      portainer.autodeploy: "false"

  db:
    image: pgvector/pgvector:pg15
    container_name: honcho-db
    hostname: honcho-db
    networks:
      honcho-internal:
    environment:
      POSTGRES_DB: honcho
      POSTGRES_USER: honcho
      POSTGRES_PASSWORD: "$${HONCHO_DB_PASSWORD}"
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - /nfs/dockermaster/honcho/pgdata:/var/lib/postgresql/data/
      - ${database_init_sql_path}:/docker-entrypoint-initdb.d/init.sql:ro
    command: ["postgres", "-c", "max_connections=200"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U honcho -d honcho"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "false"
      com.docker.stack: "honcho"
      com.docker.service: "db"
      portainer.autodeploy: "false"

  redis:
    image: redis:8.2
    container_name: honcho-redis
    hostname: honcho-redis
    networks:
      honcho-internal:
    volumes:
      - /nfs/dockermaster/honcho/redis-data:/data
    command: ["redis-server", "--appendonly", "yes"]
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    restart: unless-stopped
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "false"
      com.docker.stack: "honcho"
      com.docker.service: "redis"
      portainer.autodeploy: "false"
EOF
```

- [ ] **Step 4.2: Note the `$${VAR}` escaping**

Compose templates that go through `templatefile()` need `$$` to produce a literal `$` in the
output (Terraform's escape). At Compose-parse time, that single `$` is then interpreted as a
variable reference picked up from the `env {}` block on the `portainer_stack` resource.
Don't change `$$` to `$` — it will break.

The one exception is `${database_init_sql_path}` (single `$`) which IS a Terraform variable
interpolated at apply time, not a Compose runtime var.

- [ ] **Step 4.3: Sanity-check the YAML structure (no Terraform yet)**

We can't fully validate without running templatefile, but we can check basic YAML by
substituting placeholders manually:

```bash
sed -e 's/$$/$/g; s|${database_init_sql_path}|/tmp/init.sql|g' \
    dockermaster/docker/compose/honcho/docker-compose.yml.tftpl > /tmp/honcho-compose-check.yml
docker compose -f /tmp/honcho-compose-check.yml config > /dev/null && echo OK
```

Expected: `OK`. If syntax errors, fix the template and re-run.

- [ ] **Step 4.4: Commit**

```bash
git add dockermaster/docker/compose/honcho/docker-compose.yml.tftpl
git commit -m "feat(docker): honcho compose stack template with OpenRouter + Ollama wiring"
```

---

## Task 5: Write the Nginx vhost

**Files:**

- Create: `dockermaster/docker/compose/nginx-rproxy/vhost.d/honcho.d.lcamaral.com.conf`

- [ ] **Step 5.1: Look at an existing vhost as a reference**

```bash
cat dockermaster/docker/compose/nginx-rproxy/vhost.d/keycloak.d.lcamaral.com.conf
```

Note the cert path pattern (`/etc/nginx/certs/d.lcamaral.com.{crt,key}`) and the
`proxy_set_header` block — Honcho will use the same.

- [ ] **Step 5.2: Write the new vhost**

```bash
cat > dockermaster/docker/compose/nginx-rproxy/vhost.d/honcho.d.lcamaral.com.conf <<'EOF'
# Honcho memory server — proxies to honcho-api on ds-1 macvlan IP.
# Spec: docs/superpowers/specs/2026-05-20-honcho-deployment-design.md

server {
    listen 443 ssl http2;
    server_name honcho.d.lcamaral.com;

    ssl_certificate     /etc/nginx/certs/d.lcamaral.com.crt;
    ssl_certificate_key /etc/nginx/certs/d.lcamaral.com.key;

    # Honcho default MAX_FILE_SIZE = 5 MB; headroom for chunked uploads.
    client_max_body_size 25m;

    location / {
        proxy_pass         http://192.168.59.47:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        # Background reasoning can take >30 s for the first call after a
        # cold start; bump the read timeout above Nginx's 60 s default.
        proxy_read_timeout 120s;
    }

    # MCP transport may stream — disable buffering, allow long-lived
    # connections, drop the default Connection: close header.
    location /mcp/ {
        proxy_pass         http://192.168.59.47:8000/mcp/;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_buffering    off;
        proxy_read_timeout 300s;
    }
}
EOF
```

- [ ] **Step 5.3: Commit**

```bash
git add dockermaster/docker/compose/nginx-rproxy/vhost.d/honcho.d.lcamaral.com.conf
git commit -m "feat(network): nginx vhost for honcho.d.lcamaral.com"
```

The `fileset()` iteration in `terraform/portainer/stacks.tf` picks up this file
automatically on the next `terraform apply` — no Terraform edit needed for this part.

---

## Task 6: Add DNS records to pihole dnsmasq config

**Files:**

- Modify: `pihole/dnsmasq.d/04-d-lcamaral-com.conf`

- [ ] **Step 6.1: Locate the right insertion point**

```bash
grep -n "calibre\|rundeck" pihole/dnsmasq.d/04-d-lcamaral-com.conf | head -10
```

Pick a sensible alphabetic position (after `grafana` and before `keycloak`, for example).

- [ ] **Step 6.2: Open the file and add the records**

Edit `pihole/dnsmasq.d/04-d-lcamaral-com.conf` and insert the 3 lines below at the chosen
position. Use the multi-A pattern (3 rproxy IPs) like calibre/rundeck:

```text
# Honcho memory server (single-host on ds-1, but DNS HA-fronted via all 3 rproxies)
address=/honcho.d.lcamaral.com/192.168.59.28
address=/honcho.d.lcamaral.com/192.168.59.48
address=/honcho.d.lcamaral.com/192.168.59.49
```

- [ ] **Step 6.3: Verify the edit**

```bash
grep "honcho" pihole/dnsmasq.d/04-d-lcamaral-com.conf
```

Expected: 3 `address=/honcho.d.lcamaral.com/...` lines.

- [ ] **Step 6.4: Commit**

```bash
git add pihole/dnsmasq.d/04-d-lcamaral-com.conf
git commit -m "feat(network): DNS records for honcho.d.lcamaral.com (multi-A across rproxy fleet)"
```

---

## Task 7: Add Vault data source to Terraform

**Files:**

- Modify: `terraform/portainer/vault.tf`

- [ ] **Step 7.1: Append the honcho data source**

Append the block below to the END of `terraform/portainer/vault.tf`:

```hcl

# Honcho memory server — openrouter chat API key + postgres password
data "vault_kv_secret_v2" "honcho" {
  mount = "secret"
  name  = "homelab/honcho"
}
```

- [ ] **Step 7.2: Verify Terraform syntax**

```bash
cd terraform/portainer
terraform fmt vault.tf
terraform validate
cd ../..
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7.3: Commit**

```bash
git add terraform/portainer/vault.tf
git commit -m "feat(deploy): vault data source for secret/homelab/honcho"
```

---

## Task 8: Add the portainer_stack resource to Terraform

**Files:**

- Modify: `terraform/portainer/stacks.tf`

- [ ] **Step 8.1: Append the resource at the END of `stacks.tf`**

```hcl

# ──────────────────────────────────────────────
# Honcho memory server (ds-1)
# Spec: docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
# - api dual-homes on docker-servers-net (192.168.59.47) and rproxy bridge
# - deriver/db/redis on the stack-internal bridge only
# - Chat LLM via OpenRouter free tier; embeddings via Ollama on ds-2
# - DB init.sql vendored under dockermaster/docker/compose/honcho/
# ──────────────────────────────────────────────
resource "portainer_stack" "honcho" {
  name            = "honcho"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile(
    "${path.module}/../../dockermaster/docker/compose/honcho/docker-compose.yml.tftpl",
    {
      database_init_sql_path = "${path.module}/../../dockermaster/docker/compose/honcho/database-init.sql"
    }
  )

  env {
    name  = "OPENROUTER_API_KEY"
    value = data.vault_kv_secret_v2.honcho.data["openrouter_api_key"]
  }

  env {
    name  = "HONCHO_DB_PASSWORD"
    value = data.vault_kv_secret_v2.honcho.data["postgres_password"]
  }
}
```

- [ ] **Step 8.2: Format + validate**

```bash
cd terraform/portainer
terraform fmt stacks.tf
terraform validate
cd ../..
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 8.3: Commit**

```bash
git add terraform/portainer/stacks.tf
git commit -m "feat(deploy): portainer_stack for honcho on ds-1"
```

---

## Task 9: Plan + apply the Terraform changes

**Files:** None (state changes only).

- [ ] **Step 9.1: Source Vault token**

```bash
export VAULT_ADDR=http://vault.d.lcamaral.com
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
```

- [ ] **Step 9.2: Run `terraform plan`**

```bash
cd terraform/portainer
terraform plan -out=honcho.tfplan
```

Expected output (relevant parts):

```text
data.vault_kv_secret_v2.honcho: Reading...
data.vault_kv_secret_v2.honcho: Read complete after Xs

Terraform will perform the following actions:

  # portainer_stack.honcho will be created

  # portainer_stack.reverse_proxy_2 will be updated in-place
  # (vhost.d/honcho.d.lcamaral.com.conf added to vhosts map)
  # Same for reverse_proxy and reverse_proxy_3.

Plan: 1 to add, 3 to change, 0 to destroy.
```

If the plan shows anything else changing, STOP and investigate. Do NOT apply.

- [ ] **Step 9.3: Apply**

```bash
terraform apply honcho.tfplan
cd ../..
```

Expected: `Apply complete! Resources: 1 added, 3 changed, 0 destroyed.`

- [ ] **Step 9.4: Confirm the stack is up on ds-1**

```bash
ssh dockerserver-1 'docker ps --filter label=com.docker.stack=honcho \
                    --format "table {{.Names}}\t{{.Status}}"'
```

Expected: all 4 containers — `honcho-api`, `honcho-deriver`, `honcho-db`, `honcho-redis` —
showing `Up` and `(healthy)` (allow ~60 s for `start_period`).

- [ ] **Step 9.5: Tail logs for any obvious startup errors**

```bash
ssh dockerserver-1 'docker logs honcho-api --tail 50'
```

Expected: FastAPI startup messages, no traceback. If you see DB connection errors,
double-check `postgres_password` matches what's in Vault.

- [ ] **Step 9.6: No commit needed (state-only change)**

---

## Task 10: Deploy DNS records to the pihole instances

**Files:** None (deployment step — file already committed in Task 6).

The `pihole/dnsmasq.d/` directory is the source of truth in this repo. Deployment to the
live pihole-1/2/3 instances is currently a manual sync (see `feedback_iac_first_principle.md`
memory — known IaC gap).

- [ ] **Step 10.1: Copy the file to the pihole LXC**

```bash
scp pihole/dnsmasq.d/04-d-lcamaral-com.conf \
    pihole:/tmp/04-d-lcamaral-com.conf
ssh pihole 'sudo mv /tmp/04-d-lcamaral-com.conf /etc/pihole/dnsmasq.d/04-d-lcamaral-com.conf && \
            sudo systemctl restart pihole-FTL && \
            sleep 2 && systemctl is-active pihole-FTL'
```

Expected: `active`.

If there are pihole-2 and pihole-3 Docker instances on dm/ds-1/ds-2, repeat the equivalent
sync for them (current state TBD — check `dockermaster/docker/compose/` for `pihole-2`,
`pihole-3` dirs). If the sync mechanism is automated (Rundeck job, etc.), trigger it.

- [ ] **Step 10.2: Verify DNS resolves**

```bash
dig +short @192.168.100.254 honcho.d.lcamaral.com
```

Expected: 3 lines — `192.168.59.28`, `192.168.59.48`, `192.168.59.49` (order may vary).

---

## Task 11: Acceptance verification

**Files:** None (verification only).

Run all 7 checks from spec §15. Each should pass before declaring the deployment done.

- [ ] **Step 11.1: All containers healthy**

```bash
ssh dockerserver-1 'docker compose -p honcho ps --format "table {{.Service}}\t{{.Status}}"'
```

Expected: every row shows `Up X minutes (healthy)`.

- [ ] **Step 11.2: API answers via macvlan IP**

```bash
curl -sf http://192.168.59.47:8000/health
```

Expected: HTTP 200 with a small JSON payload (something like `{"status":"ok"}`).

- [ ] **Step 11.3: API answers via Nginx + DNS**

```bash
curl -sf https://honcho.d.lcamaral.com/health
```

Expected: same as 11.2. If TLS errors, verify the cert path on Nginx matches what the
vhost references.

- [ ] **Step 11.4: pgvector extension installed**

```bash
ssh dockerserver-1 \
  'docker exec honcho-db psql -U honcho -d honcho -c "\dx" | grep vector'
```

Expected: a `vector | 0.x.x | public | vector data type ...` row.

- [ ] **Step 11.5: Embedding round-trip via Ollama works**

Use the v3 API to write a message; the deriver should embed it shortly after.

```bash
curl -X POST https://honcho.d.lcamaral.com/v3/workspaces/test/peers/alice/messages \
  -H 'Content-Type: application/json' \
  -d '{"content": "hello world"}'

# Wait ~10 s for deriver to pick it up.
sleep 10
ssh dockerserver-1 \
  'docker exec honcho-db psql -U honcho -d honcho \
     -c "SELECT count(*) FROM messages WHERE workspace_id='\''test'\'';"'
```

Expected: count >= 1.

- [ ] **Step 11.6: Deriver has no LLM errors**

```bash
ssh dockerserver-1 'docker logs honcho-deriver --tail 100 2>&1 | grep -iE "error|429|401"'
```

Expected: no auth errors, no 401, no 429 yet (free tier may hit later under load).
Occasional connection retries in the first 30 s are fine.

- [ ] **Step 11.7: MCP endpoint reachable**

```bash
curl -sI https://honcho.d.lcamaral.com/mcp/
```

Expected: HTTP 200 or 405 (Method Not Allowed for GET), NOT 502 (Bad Gateway).

If any of the 7 checks fail, debug before continuing. Common issues and fixes:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `honcho-db` unhealthy | NFS perms wrong on `pgdata` | `chown -R 999:999 /nfs/.../pgdata` |
| `honcho-api` healthy but 502 via `nginx-rproxy` | vhost not yet rolled out | re-`terraform apply`; check rproxy containers restarted |
| Deriver loops on auth errors | `OPENROUTER_API_KEY` malformed in Vault | re-run `vault kv put` with the correct key |
| Embedding writes fail | `qwen3-embedding:8b-q8_0` model not pulled | `ssh dockerserver-2 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'` |
| `arping` parent iface wrong on ds-1 | macvlan parent named differently | re-check Task 1 step 1.2, pick the right name |

---

## Task 12: Update inventory documentation

**Files:**

- Modify: `inventory/docker-containers.md`

- [ ] **Step 12.1: Look at how other recent Docker stacks are documented**

```bash
grep -n -B 1 -A 10 "keycloak\|rundeck\|minio" inventory/docker-containers.md | head -40
```

Note the format — copy it for honcho.

- [ ] **Step 12.2: Add a honcho entry under the ds-1 section**

Open `inventory/docker-containers.md` and add an entry like this in the appropriate spot
(ds-1 / dockerserver-1 section):

```markdown
### honcho (memory server)

- **Host:** dockerserver-1 (ds-1)
- **Stack:** `terraform/portainer/stacks.tf` → `portainer_stack.honcho`
- **Compose:** `dockermaster/docker/compose/honcho/docker-compose.yml.tftpl`
- **Containers:** `honcho-api`, `honcho-deriver`, `honcho-db`, `honcho-redis`
- **Image:** `ghcr.io/plastic-labs/honcho:latest` (api + deriver, watchtower-managed)
- **Database:** `pgvector/pgvector:pg15` (pinned)
- **Cache:** `redis:8.2` (pinned)
- **Macvlan IP:** `192.168.59.47` (api only)
- **URL (internal):** <https://honcho.d.lcamaral.com>
- **Chat LLM:** OpenRouter free tier — `deepseek/deepseek-v4-flash:free`
- **Embeddings:** Ollama on ds-2 — `qwen3-embedding:8b-q8_0` (4096-dim)
- **Storage:** `/nfs/dockermaster/honcho/{pgdata,redis-data}`
- **Vault:** `secret/homelab/honcho` (`openrouter_api_key`, `postgres_password`)
- **Spec:** `docs/superpowers/specs/2026-05-20-honcho-deployment-design.md`
```

- [ ] **Step 12.3: Verify the file still passes lint**

```bash
git diff inventory/docker-containers.md | head -50
awk '{ print length, NR }' inventory/docker-containers.md | sort -rn | head -3
```

Expected: longest lines under 120 chars (tables exempt, but plain lines counted).

- [ ] **Step 12.4: Commit**

```bash
git add inventory/docker-containers.md
git commit -m "docs(inventory): document honcho stack on ds-1"
```

- [ ] **Step 12.5: Push everything**

```bash
git push origin main
```

Expected: all the commits from Tasks 3, 4, 5, 6, 7, 8, 12 ship to `origin/main`.

---

## Post-deployment housekeeping (optional)

The following are out of scope for this plan but make sense as next steps:

1. Add a Prometheus scrape config for Honcho's `/metrics` endpoint
   (Honcho exposes it because `METRICS_ENABLED=true` is set in Task 4).
2. Wire a Grafana dashboard for Honcho queue depth + LLM call rate.
3. Add Honcho as an MCP source to your `hermes` LXC.
4. Document the OpenRouter quota status check as a Rundeck job
   (so you get notified before hitting the daily cap).
5. Revisit the spec's "Out of scope" list (§17) once usage patterns are clear.
