# Honcho Memory Server — Deployment Design

**Date:** 2026-05-20
**Status:** Draft (pending user approval)
**Owner:** lamaral
**Service:** [Honcho](https://github.com/plastic-labs/honcho) — FastAPI-based memory infrastructure
for AI agents

---

## 1. Overview

Deploy a self-hosted Honcho memory server on `dockerserver-1` (ds-1, VMID 123, Portainer endpoint
id 9) for internal use by homelab clients (Claude Code, hermes LXC, future MCP-aware agents).

Honcho is a stateful memory layer that:

- Stores conversation messages, events, and documents grouped into peers/sessions/workspaces.
- Runs background workers (deriver, summary, dream) that call an LLM to extract observations,
  build per-peer representations, and consolidate insights.
- Exposes a chat endpoint that returns prompt-ready context.
- Exposes an MCP endpoint for agent integration (Claude Code, OpenCode, Hermes, OpenClaw).

## 2. Goals

- Run Honcho on ds-1, reachable internally as `honcho.d.lcamaral.com`.
- Use OpenRouter free-tier chat models (zero per-token cost; rate-limited).
- Use Ollama on ds-1 for embeddings (zero per-token cost).
- Follow the project's IaC-first pattern: compose in repo, deployed via Terraform-managed
  Portainer stack, secrets sourced from Vault at apply time, DNS + Nginx vhost in repo.
- All four workers enabled (deriver + summary + dialectic + dream).

## 3. Non-goals

- Public internet exposure via Cloudflare tunnel — not in this iteration. Architecture leaves
  the door open by dual-homing the API container so the tunnel ingress can be added later
  without rearchitecture.
- Authentication (JWT). LAN-only access; `AUTH_USE_AUTH=false`. Revisit if/when exposing
  publicly.
- Honcho's optional Sentry/CloudEvents telemetry. Disabled to keep the surface minimal.

## 4. Architecture

```text
                          honcho.d.lcamaral.com (DNS multi-A)
                          ──────────────────────────────────
                            192.168.59.28 (rproxy-1, dm)
                            192.168.59.48 (rproxy-2, ds-1)
                            192.168.59.49 (rproxy-3, ds-2)
                                       │
                                  nginx-rproxy
                       (HTTPS, *.d.lcamaral.com wildcard cert)
                                       │
                              proxy_pass http://192.168.59.47:8000
                                       │
                                       ▼
                          ┌──────────────────────────┐
                          │   stack: honcho (ds-1)   │
                          │                          │
                          │  ┌─api──┐   ┌─deriver──┐ │
                          │  │ 8000 │   │ worker   │ │
                          │  └──┬───┘   └────┬─────┘ │
                          │     │            │       │
                          │  ┌──▼────────────▼─────┐ │
                          │  │ db (pgvector pg15)  │ │
                          │  │ redis 8.2           │ │
                          │  └─────────────────────┘ │
                          └──────────────────────────┘

    Embeddings call out to Ollama on ds-1 (separate stack, already running):
        api/deriver  ──HTTP──>  http://ollama.d.lcamaral.com/v1/embeddings
                                model: qwen3-embedding:8b-q8_0 (4096-dim)
```

## 5. Components

| Service | Image | Networks | Role |
|---------|-------|----------|------|
| `honcho-api` | `ghcr.io/plastic-labs/honcho:latest` | servers-net (.47), rproxy, honcho-internal | FastAPI on :8000. Health: `GET /health`. |
| `honcho-deriver` | `ghcr.io/plastic-labs/honcho:latest` | honcho-internal | Background worker. `entrypoint: python -m src.deriver`. |
| `honcho-db` | `pgvector/pgvector:pg15` | honcho-internal | Postgres with pgvector extension. Custom password from Vault. |
| `honcho-redis` | `redis:8.2` | honcho-internal | Cache + deriver work queue. AOF persistence. |

Every container gets the standard labels:

- `loki.logging=true` — promtail picks up logs.
- `com.centurylinklabs.watchtower.enable=true` for `honcho-api` and `honcho-deriver`
  (auto-update on new `:latest`). `false` for `db` and `redis` (pinned tags).
- `com.docker.stack=honcho`, `com.docker.service=<name>`.
- `portainer.autodeploy=false` (managed by Terraform, not the Portainer UI).

### 5.1 `honcho-api`

- `depends_on`: `db` (healthy), `redis` (healthy).
- `healthcheck`: `urllib.request.urlopen('http://localhost:8000/health', timeout=2)`,
  interval 30s, retries 5, start_period 30s (image cold-start is slow).
- `restart: unless-stopped`.
- `expose: 8000` (`nginx-rproxy` reaches via `honcho-api.rproxy` bridge DNS).
- Connects to `Docker-servers-net` at fixed IP for direct LAN access if needed.

### 5.2 honcho-deriver

- `depends_on`: `api` (healthy), `db` (healthy), `redis` (healthy).
- Same image, different entrypoint.
- No exposed ports.
- `restart: unless-stopped`.

### 5.3 honcho-db

- Image: `pgvector/pgvector:pg15` (Honcho upstream convention; supports vector columns).
- Volume: bind-mount `/nfs/dockermaster/honcho/pgdata` → `/var/lib/postgresql/data/`.
- Init: bind-mount `database/init.sql` from the upstream repo (creates pgvector extension).
- Env:
  - `POSTGRES_DB=honcho`
  - `POSTGRES_USER=honcho`
  - `POSTGRES_PASSWORD=${HONCHO_DB_PASSWORD}` (from Vault via Terraform).
  - `PGDATA=/var/lib/postgresql/data/pgdata` (subdirectory for clean bind mount).
- Healthcheck: `pg_isready -U honcho -d honcho`.

### 5.4 `honcho-redis`

- Image: `redis:8.2`.
- Volume: bind-mount `/nfs/dockermaster/honcho/redis-data` → `/data`.
- Healthcheck: `redis-cli ping`.

## 6. Networking

Three Docker networks:

| Network | Driver | Scope | Purpose |
|---------|--------|-------|---------|
| `docker-servers-net` | macvlan (external) | host | LAN reachability for `honcho-api` only. |
| `rproxy` | bridge (external) | host | `nginx-rproxy` → `honcho-api.rproxy` DNS resolution. |
| `honcho-internal` | bridge (stack-local) | stack | Inter-service: `api`↔`db`, `api`↔`redis`, `deriver`↔`db`, `deriver`↔`redis`. |

`honcho-api` joins all three. Other services join only `honcho-internal`.

### 6.1 IP allocation

The `honcho-api` container gets **`192.168.59.47`** on `docker-servers-net`. Verified against
`grep -rhE "ipv4_address: 192.168.59" terraform/portainer/stacks/` (2026-05-20) — .47 is unused.

**Pre-apply verification (per memory `feedback_macvlan_ip_collisions.md`):**

```bash
ssh dockerserver-1 'arping -I server-net-shim -c 3 192.168.59.47'
# Expect: no replies. Any reply = collision, pick a different IP.
```

## 7. Storage

NFS-backed bind mounts (ds-1 has `/nfs/dockermaster/` mounted from tnas:/volume2/servers):

```text
/nfs/dockermaster/honcho/
├── pgdata/        # PostgreSQL + pgvector data
└── redis-data/    # Redis AOF + RDB
```

Pre-deploy step: `ssh dockerserver-1 'mkdir -p /nfs/dockermaster/honcho/{pgdata,redis-data}'`.

Backups: inherits Synology snapshot policy on `/volume2/servers`. No new backup wiring.

## 8. DNS

Add three multi-A records to `pihole/dnsmasq.d/04-d-lcamaral-com.conf` in this repo (same
pattern as calibre, rundeck — pointing at all three rproxy macvlan IPs for HA at the entry
point, even though Honcho itself runs only on ds-1):

```text
# Honcho memory server (single-host on ds-1, but DNS HA-fronted via all 3 rproxies)
address=/honcho.d.lcamaral.com/192.168.59.28
address=/honcho.d.lcamaral.com/192.168.59.48
address=/honcho.d.lcamaral.com/192.168.59.49
```

Deployment of this file to the pihole instances follows the existing pihole-sync mechanism
(out of scope for this spec; same gap noted in
`feedback_iac_first_principle.md`).

## 9. Reverse proxy

New file: `dockermaster/docker/compose/nginx-rproxy/vhost.d/honcho.d.lcamaral.com.conf`.

```nginx
server {
    listen 443 ssl http2;
    server_name honcho.d.lcamaral.com;

    ssl_certificate     /etc/nginx/certs/d.lcamaral.com.crt;
    ssl_certificate_key /etc/nginx/certs/d.lcamaral.com.key;

    client_max_body_size 25m;  # Honcho default MAX_FILE_SIZE = 5MB; headroom for uploads

    location / {
        proxy_pass         http://192.168.59.47:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;  # background reasoning can take >30s for first call
    }

    # MCP transport may require HTTP streaming
    location /mcp/ {
        proxy_pass              http://192.168.59.47:8000/mcp/;
        proxy_http_version      1.1;
        proxy_set_header        Connection "";
        proxy_buffering         off;
        proxy_read_timeout      300s;
    }
}
```

This file is picked up automatically by the existing
`locals.rproxy_vhosts` `fileset()` iteration in `terraform/portainer/stacks.tf` (rolls out
to all three Nginx instances on `terraform apply`).

## 10. Secrets (Vault)

New path: `secret/homelab/honcho` with these keys:

| Key | Source | Used by |
|-----|--------|---------|
| `openrouter_api_key` | manual one-time `vault kv put` | `api`, `deriver` (chat features) |
| `postgres_password` | manual one-time `vault kv put` (generated locally) | `db`, `api`, `deriver` |

No OpenAI key needed — chat goes through OpenRouter, embeddings through Ollama (no
authentication required on the Ollama endpoint).

Terraform data source in `terraform/portainer/vault.tf`:

```hcl
data "vault_kv_secret_v2" "honcho" {
  mount = "secret"
  name  = "homelab/honcho"
}
```

Injected as Compose env vars (never written to disk), following the keycloak/cloudflare
pattern in `terraform/portainer/stacks.tf`.

## 11. LLM configuration

Honcho separates LLM config per feature. All chat features point at OpenRouter; the
embedding feature points at Ollama on ds-1.

### 11.1 Chat features (deriver, summary, dialectic, dream)

```text
# Single model for all chat features to consolidate the OpenRouter free-tier quota
DERIVER_MODEL_CONFIG__TRANSPORT=openai
DERIVER_MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DERIVER_MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

SUMMARY_MODEL_CONFIG__TRANSPORT=openai
SUMMARY_MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
SUMMARY_MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

# Dialectic — same model across all five reasoning levels (minimal/low/medium/high/max)
# Each level needs its own full block (Honcho doesn't fall back to a global default).
DIALECTIC_LEVELS__minimal__MODEL_CONFIG__TRANSPORT=openai
DIALECTIC_LEVELS__minimal__MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DIALECTIC_LEVELS__low__MODEL_CONFIG__TRANSPORT=openai
DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DIALECTIC_LEVELS__medium__MODEL_CONFIG__TRANSPORT=openai
DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DIALECTIC_LEVELS__high__MODEL_CONFIG__TRANSPORT=openai
DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DIALECTIC_LEVELS__max__MODEL_CONFIG__TRANSPORT=openai
DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT=openai
DREAM_DEDUCTION_MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT=openai
DREAM_INDUCTION_MODEL_CONFIG__MODEL=deepseek/deepseek-v4-flash:free
DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL=https://openrouter.ai/api/v1
DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OPENROUTER_API_KEY

OPENROUTER_API_KEY=${vault.openrouter_api_key}
```

### 11.2 Embeddings

```text
EMBED_MESSAGES=true
EMBEDDING_VECTOR_DIMENSIONS=4096
EMBEDDING_MODEL_CONFIG__TRANSPORT=openai
EMBEDDING_MODEL_CONFIG__MODEL=qwen3-embedding:8b-q8_0
EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL=http://ollama.d.lcamaral.com/v1
# Ollama needs an API key var to be set (any non-empty string) for the openai SDK
EMBEDDING_MODEL_CONFIG__OVERRIDES__API_KEY_ENV=OLLAMA_API_KEY
OLLAMA_API_KEY=ollama
```

**Pre-deploy verification:** ensure `qwen3-embedding:8b-q8_0` is pulled on the ds-2 Ollama instance:

```bash
ssh dockerserver-1 'docker exec ollama ollama list | grep nomic'
# If missing: ssh dockerserver-1 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'
```

### 11.3 Rate-limit awareness

OpenRouter free tier is ~200 requests/day per model. Mitigations baked in:

- Single model across all chat features (consolidates quota).
- `DERIVER_DEDUPLICATE=true` (default) collapses repeated work.
- `DERIVER_FLUSH_ENABLED=false` (default) waits for batches, doesn't fire on every message.
- Honcho's deriver queue retains errors for 30 days, so 429s back up but don't lose data.

If quota becomes a real problem (visible as growing queue depth via
`honcho.queue_status()`), the upgrade path is OpenAI API with hard monthly cap — same wiring,
swap `BASE_URL` and `MODEL`.

## 12. IaC layout

```text
inventory/                                    (this repo root)
├── dockermaster/docker/compose/honcho/
│   ├── docker-compose.yml.tftpl              # Compose stack (templated)
│   └── database-init.sql                     # pgvector init, vendored from upstream
│
├── dockermaster/docker/compose/nginx-rproxy/vhost.d/
│   └── honcho.d.lcamaral.com.conf            # NEW — auto-picked by fileset()
│
├── pihole/dnsmasq.d/
│   └── 04-d-lcamaral-com.conf                # +3 lines for honcho
│
└── terraform/portainer/
    ├── vault.tf                              # +1 data source: honcho
    └── stacks.tf                             # +1 portainer_stack: honcho
```

The compose stack file lives under `dockermaster/docker/compose/honcho/` (not
`terraform/portainer/stacks/`) to match the keycloak/freeswitch/registry pattern where the
service has multiple supporting files. Terraform reads the `.tftpl` via `templatefile()`.

## 13. Deployment workflow

```text
1. Add openrouter_api_key to Vault (manual, one-time):
   vault kv put secret/homelab/honcho \
     openrouter_api_key=sk-or-... \
     postgres_password=$(openssl rand -base64 32 | tr -d '=+/')

2. Pre-create NFS dirs on ds-1:
   ssh dockerserver-1 'mkdir -p /nfs/dockermaster/honcho/{pgdata,redis-data}'

3. Pre-verify macvlan IP availability:
   ssh dockerserver-1 'arping -I server-net-shim -c 3 192.168.59.47'
   # Expect zero replies. If any reply, pick a different IP and update the spec.

4. Pre-verify Ollama embedding model:
   ssh dockerserver-1 'docker exec ollama ollama list | grep qwen3-embedding:8b-q8_0' \
     || ssh dockerserver-1 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'

5. Add files to repo (compose, vhost, dnsmasq, terraform).

6. terraform -chdir=terraform/portainer apply
   # Creates the portainer_stack, which pulls images, brings up containers.

7. Deploy pihole dnsmasq config (existing sync mechanism).

8. Verify (see §15).
```

## 14. Operations

- **Updates:** Watchtower auto-updates `:latest` on `honcho-api` + `honcho-deriver`.
  Postgres and Redis pinned (manual updates only when intentional).
- **Backups:** `pgdata` and `redis-data` ride the Synology NFS snapshot policy. No
  service-specific backup wiring.
- **Monitoring:**
  - `cadvisor-ds1` automatically scrapes per-container CPU/mem/IO.
  - Honcho exposes Prometheus metrics at `/metrics` when `METRICS_ENABLED=true` — add a
    Prometheus scrape config in a follow-up if desired.
  - Loki picks up logs via the `loki.logging=true` label and the existing promtail on ds-1.
- **Redeploy after `configs:` change** (per memory `feedback_portainer_stack_redeploy.md`):
  If a future change only modifies the inline `configs:` content, `terraform apply` may
  succeed without restarting the container. Chase with stack stop/start via Portainer API.

## 15. Verification / acceptance

After `terraform apply`:

1. **All containers healthy:**

   ```bash
   ssh dockerserver-1 'docker compose -p honcho ps'
   # Expect: api, deriver, db, redis all "Up (healthy)"
   ```

2. **API answers health check via macvlan IP:**

   ```bash
   curl -sf http://192.168.59.47:8000/health
   ```

3. **API answers via `nginx-rproxy` + DNS:**

   ```bash
   curl -sf https://honcho.d.lcamaral.com/health
   ```

4. **DB has pgvector extension:**

   ```bash
   ssh dockerserver-1 \
     'docker exec honcho-db psql -U honcho -d honcho -c "\dx" | grep vector'
   ```

5. **Embedding round-trip works (creates a peer, adds a message, embedding written):**

   ```bash
   curl -X POST https://honcho.d.lcamaral.com/v3/workspaces/test/peers/alice/messages \
     -H 'Content-Type: application/json' \
     -d '{"content": "hello world"}'
   # Then check DB:
   ssh dockerserver-1 \
     'docker exec honcho-db psql -U honcho -d honcho \
        -c "SELECT count(*) FROM messages WHERE workspace_id=\$\$test\$\$;"'
   ```

6. **Deriver consumes from queue (no LLM errors blocking):**

   ```bash
   ssh dockerserver-1 'docker logs honcho-deriver --tail 50 | grep -i error'
   # Expect: no 429s, no auth errors. Initial queue scan messages OK.
   ```

7. **MCP endpoint reachable:**

   ```bash
   curl -sI https://honcho.d.lcamaral.com/mcp/
   # Expect: 200 or 405 (method not allowed for GET), not 502.
   ```

## 16. Known risks / open items

| Risk | Mitigation |
|------|------------|
| OpenRouter free tier rate-limited (~200/day) | Single model across features, deduplicate enabled. Upgrade path documented (§11.3). |
| `ollama.d.lcamaral.com` not yet a DNS record | Verify before deploy; add to `04-d-lcamaral-com.conf` if missing. |
| Honcho `:latest` rolling tag may break compatibility | Watchtower auto-rollback NOT configured. Pin to a specific tag if instability shows up. |
| pgvector + pg15 minor version drift | Pin `pgvector/pgvector:pg15` — same major as Honcho upstream uses. Re-evaluate on pg16+. |
| Nginx vhost cert path assumes pfSense ACME wildcard | Verified path is `/etc/nginx/certs/d.lcamaral.com.{crt,key}` (same as keycloak vhost). |
| Watchtower MAY update `api` but not `deriver` in same window | Both labeled enabled; Watchtower processes them in the same poll. Acceptable risk. |
| `arping` interface name may not be `server-net-shim` on ds-1 | Verify during step 3; substitute the actual macvlan parent if different. |

## 17. Out of scope (future iterations)

- Cloudflare tunnel exposure for public MCP access.
- JWT authentication.
- Multi-host HA for Honcho itself (`api`+`deriver` replicas; `deriver` currently single-instance).
- Migration from pgvector to turbopuffer or LanceDB if vector store size becomes a problem.
- Prometheus scrape config for Honcho's `/metrics` endpoint.
- Backup tooling specific to Honcho (full DB dumps on a schedule).
