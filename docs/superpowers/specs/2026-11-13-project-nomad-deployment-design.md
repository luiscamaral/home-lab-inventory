# Project NOMAD — Deployment Design

**Date:** 2026-11-13
**Status:** Draft (pending user approval)
**Owner:** lamaral
**Service:** [Project NOMAD](https://github.com/Crosstalk-Solutions/project-nomad) — offline-first
knowledge, education, and RAG AI server

---

## 1. Overview

Deploy a self-hosted Project NOMAD instance on `dockerserver-2` (ds-2, VMID 124, Portainer
endpoint id 13) reachable internally at `https://nomad.d.lcamaral.com`.

Project NOMAD ("Command Center") is a Node.js/AdonisJS + React management server backed by MySQL 8.0
and Redis 7 that orchestrates offline knowledge tools (Kiwix Wikipedia/ZIM library, Kolibri courses,
ProtoMaps offline maps, FlatNotes, CyberChef) and an integrated RAG AI Assistant (Qdrant vector
database + LLM/embeddings).

Instead of running heavy LLM chat inference on Proxmox CPUs (which have no discrete GPU), this
design includes a co-located **LiteLLM Proxy** sidecar inside the stack that:

- Routes **RAG embeddings** (`nomic-embed-text:v1.5`, 768-dim) to our existing **local Ollama**
  instance on `dockerserver-1` (`http://ollama.d.lcamaral.com:11434` / `192.168.59.53:11434`) so
  ZIM/PDF/EPUB indexing stays 100% local, private, and free.
- Routes **AI Chat** (`/v1/chat/completions` and `/v1/models`) to curated **external / subscription
  AI providers** (OpenRouter, OpenAI, Anthropic, or subscription OAuth bridges) using API keys
  injected from Vault.

## 2. Goals

- Run Project NOMAD on `dockerserver-2`, reachable on LAN and Twingate as
  `https://nomad.d.lcamaral.com`.
- Follow the repository's strict IaC-first rule: Compose template in repo, deployed via
  Terraform-managed Portainer stack, secrets sourced from Vault at apply time, DNS + Nginx vhost in
  repo.
- Hybrid AI routing via a co-located `litellm` service (`http://litellm:4000` on the stack network):
  - Local embeddings on `ds-1` Ollama (`nomic-embed-text:v1.5`).
  - Curated external/subscription chat models via LiteLLM Proxy.
- Store bulk offline content (ZIM files, maps, books, uploaded docs) on NAS-backed NFS
  (`/nfs/dockermaster/nomad/storage`) while keeping latency/lock-sensitive MySQL and Redis state on
  `ds-2` local ext4 SSD (`/opt/project-nomad/{mysql,redis}`).

## 3. Non-goals

- Public internet exposure via Cloudflare tunnel (`*.cf.lcamaral.com`) — Project NOMAD has **no
  built-in authentication** by design. Access is restricted to LAN + Twingate (`nomad.d.lcamaral.com`).
- Running `nomad_ollama` on `ds-2` — we reuse the existing `ollama` stack on `ds-1`
  (`192.168.59.53:11434`) and external AI providers for chat.
- Running `nomad_updater` sidecar — upstream's updater mutates `/opt/project-nomad/compose.yml` on
  disk, which conflicts with Terraform + Portainer management. Container updates are handled by
  Watchtower + Terraform.
- Running `nomad_dozzle` — logs are already shipped to Loki via Promtail (`loki.logging=true`) and
  viewable in Grafana / Portainer.

## 4. Architecture

```text
                          nomad.d.lcamaral.com (DNS multi-A)
                          ──────────────────────────────────
                            192.168.59.28 (rproxy-1, dm)
                            192.168.59.48 (rproxy-2, ds-1)
                            192.168.59.49 (rproxy-3, ds-2)
                                       │
                                  nginx-rproxy
                       (HTTPS, *.d.lcamaral.com wildcard cert)
                                       │
                              proxy_pass http://192.168.59.60:8080
                                       │
                                       ▼
          ┌────────────────────────────────────────────────────────┐
          │               stack: nomad (dockerserver-2)            │
          │         network: project-nomad_default (bridge)        │
          │                                                        │
          │  ┌──────────────┐     ┌─────────────────────────────┐  │
          │  │ nomad_admin  │────►│ litellm (:4000)             │  │
          │  │ (:8080)      │     │ (OpenAI-compat AI router)   │  │
          │  │ .59.60       │     └──────┬───────────────┬──────┘  │
          │  └──┬────────┬──┘            │               │         │
          │     │        │               │               │         │
          │  ┌──▼───┐ ┌──▼───────────┐   │               │         │
          │  │mysql │ │redis         │   │               │         │
          │  │8.0   │ │7-alpine      │   │               │         │
          │  └──────┘ └──────────────┘   │               │         │
          │  ┌───────────────────────┐   │               │         │
          │  │nomad_disk_collector   │   │               │         │
          │  └───────────────────────┘   │               │         │
          │  ┌───────────────────────┐   │               │         │
          │  │nomad_qdrant / kiwix.. │   │               │         │
          │  │(spawned via DooD)     │   │               │         │
          │  └───────────────────────┘   │               │         │
          └──────────────────────────────┼───────────────┼─────────┘
                                         │               │
                 POST /v1/embeddings     │               │ POST /v1/chat/completions
                 (nomic-embed-text:v1.5) │               │ (Bearer key from Vault)
                                         ▼               ▼
                           http://192.168.59.53:11434   External / Subscription AI
                             (ollama on ds-1, LAN)      (OpenRouter / OpenAI / Anthropic)
```

## 5. Components

| Service | Image | Networks | Role |
|---------|-------|----------|------|
| `admin` (`nomad_admin`) | `ghcr.io/crosstalk-solutions/project-nomad:latest` | `servers-net` (`.60`), `rproxy`, `default` (`project-nomad_default`) | Command Center UI & API on `:8080`. Health: `GET /api/health`. |
| `mysql` (`nomad_mysql`) | `mysql:8.0` | `default` (`project-nomad_default`) | Command Center relational DB (`nomad`). |
| `redis` (`nomad_redis`) | `redis:7-alpine` | `default` (`project-nomad_default`) | BullMQ job queue (downloads, ZIM/RAG ingestion) + cache. |
| `disk-collector` (`nomad_disk_collector`) | `ghcr.io/crosstalk-solutions/project-nomad-disk-collector:latest` | `default` (`project-nomad_default`) | Reads host/NFS storage stats (`ro,rslave`) for Command Center UI. |
| `litellm` (`nomad_litellm`) | `ghcr.io/berriai/litellm:main-stable` | `default` (`project-nomad_default`) | OpenAI-compatible AI router on `:4000` bridging NOMAD to local Ollama embeddings + external chat models. |

Standard labels on all containers:

- `loki.logging=true` — Promtail ships container logs to Loki.
- `com.centurylinklabs.watchtower.enable=true` for `admin`, `disk-collector`, and `litellm`;
  `false` for `mysql` and `redis` (stateful pinned tags).
- `com.docker.stack=nomad`, `com.docker.service=<name>`.
- `portainer.autodeploy=false` (Terraform-managed).

### 5.1 Critical DooD (Docker-outside-of-Docker) Requirements

Inspecting Project NOMAD's `DockerService` (`admin/app/services/docker_service.ts`) reveals two
hardcoded invariants that the Compose file **must** satisfy:

1. **Container name `nomad_admin` and `/app/storage` bind mount:**
   `DockerService._resolveHostStorageRoot()` inspects the container named `nomad_admin` via
   `/var/run/docker.sock`, finds the host source path mounted at `/app/storage`, and automatically
   rewrites the bind mounts of every child container it spawns (`nomad_kiwix`, `nomad_qdrant`,
   `nomad_kolibri`, etc.) to live under that same host directory. Setting both the volume
   `/nfs/dockermaster/nomad/storage:/app/storage` and `NOMAD_STORAGE_PATH=/nfs/dockermaster/nomad/storage`
   ensures all child apps store their data on the NAS NFS share.
2. **Bridge network name `project-nomad_default`:**
   When `nomad_admin` spawns child containers in production (`NODE_ENV=production`), it attaches
   them to `DockerService.NOMAD_NETWORK = 'project-nomad_default'` and connects to them by container
   name (e.g., `http://nomad_qdrant:6333`). Therefore, the Compose stack sets `name: project-nomad`
   and uses the default bridge network (`project-nomad_default`) for internal communication.

## 6. Hybrid AI & RAG Routing Design

### 6.1 How Project NOMAD's `OllamaService` and `RagService` Work

From `admin/app/services/ollama_service.ts` and `admin/app/services/rag_service.ts`:

1. NOMAD reads the `ai.remoteOllamaUrl` setting from its `KVStore` table (configurable in the UI
   under **Settings → AI Assistant → Remote Ollama/OpenAI API URL**).
2. When `ai.remoteOllamaUrl` points to `http://litellm:4000`:
   - NOMAD probes `GET http://litellm:4000/api/tags`, gets a `404`, and automatically switches to
     its **OpenAI-compatible client** (`baseURL: 'http://litellm:4000/v1'`, `apiKey: 'nomad'`).
3. For **Knowledge Base / ZIM RAG (`RagService`)**:
   - `RagService` hardcodes `EMBEDDING_MODEL_NAME = 'nomic-embed-text:v1.5'` and
     `EMBEDDING_DIMENSION = 768`.
   - Before embedding or searching Qdrant, `RagService` calls `ollamaService.getModels(true)`
     (`GET /v1/models`) and verifies that `nomic-embed-text:v1.5` is present in the returned model
     list.
   - It then calls `POST /v1/embeddings` with `model: "nomic-embed-text:v1.5"`.
4. For **Chat (`OllamaService.getModels(false)`)**:
   - NOMAD calls `GET /v1/models`, filters out any model containing `embed` in its name, and
     populates the UI model selector with the remaining models.

### 6.2 LiteLLM Proxy Configuration (`litellm-config.yaml`)

Injected into the `litellm` container via Docker Compose inline `configs:` (rendered by Terraform):

```yaml
model_list:
  # 1. Local RAG Embedding model — routed to existing Ollama on ds-1 (.59.53)
  # Must be named exactly "nomic-embed-text:v1.5" so NOMAD's RagService verification passes.
  - model_name: nomic-embed-text:v1.5
    litellm_params:
      model: ollama/nomic-embed-text:v1.5
      api_base: http://192.168.59.53:11434

  # 2. External / Subscription Chat Models (via OpenRouter or direct provider APIs)
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

  # 3. Optional Local Fallback Chat Model on ds-1 Ollama (for true internet-down offline mode)
  - model_name: llama3.2:3b-offline
    litellm_params:
      model: ollama/llama3.2:3b
      api_base: http://192.168.59.53:11434
```

> **Note:** Additional providers (direct `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or a subscription
> OAuth bridge container) can be added to `litellm-config.yaml` at any time without changing
> Project NOMAD's settings.

## 7. Networking

| Network | Driver | Scope | Purpose |
|---------|--------|-------|---------|
| `docker-servers-net` | macvlan (external) | host | LAN reachability for `nomad_admin` at **`192.168.59.60`**. |
| `rproxy` | bridge (external) | host | Local `rproxy-3` → `nomad_admin` bridge communication. |
| `default` (`project-nomad_default`) | bridge (stack) | stack | Internal stack network for `admin` ↔ `mysql`, `redis`, `litellm`, and DooD-spawned `nomad_*` containers (`nomad_qdrant`, `nomad_kiwix`, etc.). |

### 7.1 IP Allocation

`nomad_admin` is assigned **`192.168.59.60`** from the `192.168.59.0/26` pool (verified unused in
`terraform/portainer/stacks/` and `locals.tf`; `.59` is `portainer-agent` on `ds-2`, `.62` is
`server-net-shim` on `ds-2`).

Pre-apply verification:

```bash
ssh dockerserver-2 'sudo arping -I server-net-shim -c 3 192.168.59.60'
# Expect: 0 replies
```

## 8. Storage

Hybrid storage layout to avoid database locking issues on `soft,local_lock=none` NFS mounts (per the
`calibre-web` lesson in `inventory/docker-containers.md`):

| Host Path on `ds-2` | Container Mount | Backing Store | Purpose |
|---------------------|-----------------|---------------|---------|
| `/nfs/dockermaster/nomad/storage` | `/app/storage` (`admin`), `/storage` (`disk-collector`) | Synology NAS NFS (`/volume2/servers`) | ZIM files, offline maps, books, Qdrant vectors, KB uploads |
| `/opt/project-nomad/mysql` | `/var/lib/mysql` (`mysql`) | `ds-2` local ext4 SSD | MySQL 8.0 InnoDB tables |
| `/opt/project-nomad/redis` | `/data` (`redis`) | `ds-2` local ext4 SSD | Redis AOF/RDB queue state |

## 9. DNS

Add three multi-A records to `pihole/dnsmasq.d/04-d-lcamaral-com.conf` pointing at all three
`nginx-rproxy` instances (`.28`, `.48`, `.49`):

```ini
# Project NOMAD (single-host on ds-2, HA-fronted via all 3 rproxies)
address=/nomad.d.lcamaral.com/192.168.59.28
address=/nomad.d.lcamaral.com/192.168.59.48
address=/nomad.d.lcamaral.com/192.168.59.49
```

## 10. Reverse Proxy

New file: `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf` (auto-bundled
into all three `nginx-rproxy` stacks via `locals.rproxy_vhosts` `fileset()` in
`terraform/portainer/stacks.tf`):

```nginx
server {
    listen 443 ssl http2;
    server_name nomad.d.lcamaral.com;

    ssl_certificate     /etc/nginx/certs/d.lcamaral.com.crt;
    ssl_certificate_key /etc/nginx/certs/d.lcamaral.com.key;

    client_max_body_size 500m;  # Allow large PDF/EPUB/ZIM uploads to Knowledge Base

    location / {
        proxy_pass         http://192.168.59.60:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_buffering    off;              # Required for AdonisJS Transmit SSE + AI chat streaming
        proxy_read_timeout 300s;
    }
}
```

## 11. Secrets (Vault)

New Vault KV-v2 path: `secret/homelab/nomad`

| Key | Description | Consumed by |
|-----|-------------|-------------|
| `app_key` | 32-char random hex/alphanumeric string (`APP_KEY` >= 16 chars required by AdonisJS) | `nomad_admin` |
| `db_password` | MySQL `nomad_user` password | `nomad_admin`, `nomad_mysql` |
| `mysql_root_password` | MySQL root password | `nomad_mysql` |
| `openrouter_api_key` | OpenRouter API key (can reuse key from `secret/homelab/honcho` or dedicated key) | `nomad_litellm` |

Terraform data source in `terraform/portainer/vault.tf`:

```hcl
data "vault_kv_secret_v2" "nomad" {
  mount = "secret"
  name  = "homelab/nomad"
}
```

## 12. IaC Layout

```text
inventory/
├── dockermaster/docker/compose/nomad/
│   ├── docker-compose.yml.tftpl              # Compose stack template
│   └── litellm-config.yaml                   # LiteLLM router config (injected via configs:)
├── dockermaster/docker/compose/nginx-rproxy/vhost.d/
│   └── nomad.d.lcamaral.com.conf             # Nginx HTTPS vhost (auto-picked by fileset())
├── pihole/dnsmasq.d/
│   └── 04-d-lcamaral-com.conf                # +3 multi-A lines for nomad.d.lcamaral.com
└── terraform/portainer/
    ├── vault.tf                              # +1 data source: nomad
    └── stacks.tf                             # +1 portainer_stack: nomad (on ds2_endpoint_id)
```

## 13. Post-Deploy UI Configuration (One-Time)

Once `https://nomad.d.lcamaral.com` is up:

1. In Project NOMAD Command Center, go to **Settings → AI Assistant** (or run the Easy Setup
   Wizard).
2. Under **Remote Connection → Remote Ollama / OpenAI API URL**, enter:
   `http://litellm:4000`
3. Install the **AI Assistant** service in NOMAD (this spins up `nomad_qdrant` on `ds-2` for the
   Knowledge Base; if it also starts a local `nomad_ollama` container on `ds-2`, stop/disable
   `nomad_ollama` since `ai.remoteOllamaUrl` overrides it).

## 14. Verification / Acceptance

1. **All stack containers healthy on `ds-2`:**

   ```bash
   ssh dockerserver-2 'docker ps --filter "label=com.docker.stack=nomad" --format "table {{.Names}}\t{{.Status}}"'
   ```

2. **Pull `nomic-embed-text:v1.5` on `ds-1` Ollama and verify via LiteLLM:**

   ```bash
   ssh dockerserver-1 'docker exec ollama ollama pull nomic-embed-text:v1.5'
   ssh dockerserver-2 'docker exec nomad_admin curl -sf http://litellm:4000/v1/models'
   ```

   Expected: JSON listing `nomic-embed-text:v1.5` and the configured chat models.

3. **Command Center health endpoint responds via macvlan IP and via Nginx HTTPS:**

   ```bash
   curl -sf http://192.168.59.60:8080/api/health
   curl -sf https://nomad.d.lcamaral.com/api/health
   ```

4. **End-to-end RAG + Chat verification:**
   - Upload a test markdown/PDF file in NOMAD Knowledge Base → verify chunks embed into Qdrant
     via `ds-1` Ollama (`nomic-embed-text:v1.5`).
   - Send a chat prompt in NOMAD AI Assistant → verify streaming response returns via LiteLLM.

## 15. Known Risks / Mitigations

| Risk | Mitigation |
|------|------------|
| `ds-2` local disk space (`/var/lib/minio-data` growth) | Verify `df -h /` on `ds-2` in pre-flight; heavy NOMAD content (`storage/`) is placed on `/nfs/dockermaster/nomad/storage`, so `ds-2` root disk only holds small MySQL/Redis metadata (~500 MB) and container images. |
| Child apps (`nomad_kiwix`, `nomad_kolibri`) bind ports `8090+` on `ds-2` | `ds-2` only runs `rproxy-3`, `vault-3`, `minio-2`, `freeswitch`, and `rustdesk` (mostly on macvlan IPs); ports `8090–8099` on `ds-2` (`192.168.48.46`) are free. Can also add optional Nginx vhosts later if desired. |
| NOMAD AI Assistant installer starts `nomad_ollama` container by default | Configure `Remote Ollama/OpenAI API URL = http://litellm:4000` in Settings and stop `nomad_ollama` if created (tracked upstream in Crosstalk-Solutions/project-nomad#662). |
