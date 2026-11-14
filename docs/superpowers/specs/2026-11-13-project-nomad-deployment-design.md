# Project NOMAD — Deployment Design

**Date:** 2026-11-13
**Status:** Ready for PR & Apply
**Owner:** lamaral
**Service:** [Project NOMAD](https://github.com/Crosstalk-Solutions/project-nomad) — offline-first
knowledge, education, and RAG AI server

---

## 1. Overview

Deploy a self-hosted Project NOMAD instance on `dockerserver-2` (`ds-2`, VMID 124, Portainer
endpoint id 13) reachable internally at `https://nomad.d.lcamaral.com`.

Project NOMAD ("Command Center") is a Node.js/AdonisJS + React management server backed by MySQL 8.0
and Redis 7 that orchestrates offline knowledge tools (Kiwix Wikipedia/ZIM library, Kolibri courses,
ProtoMaps offline maps, FlatNotes, CyberChef) and an integrated RAG AI Assistant (Qdrant vector
database + LLM/embeddings).

Instead of running heavy LLM chat inference on Proxmox CPUs (which have no discrete GPU), this
design pairs Project NOMAD with two lightweight co-located services inside the same stack:

- **`ollama` (`nomad_embed_ollama`)**: An embeddings-only CPU Ollama container (`ollama/ollama:0.40.16`)
  serving `nomic-embed-text:v1.5` (768-dim, ~275 MB) so ZIM/PDF/EPUB Knowledge Base indexing stays
  100% local, private, and free. (The former standalone `ollama` stack on `ds-1` was removed in
  `7f6c3ba`.)
- **`litellm` (`nomad_litellm`)**: A LiteLLM Proxy (`ghcr.io/berriai/litellm:v1.108.8`) exposing an
  OpenAI-compatible endpoint (`http://litellm:4000`) that routes `nomic-embed-text:v1.5` to
  `http://ollama:11434` and routes chat completions (`/v1/chat/completions`, `/v1/models`) to
  curated external/subscription AI providers (OpenRouter, etc.) using API keys injected from Vault.

## 2. Goals

- Run Project NOMAD on `dockerserver-2`, reachable on LAN and Twingate as
  `https://nomad.d.lcamaral.com`.
- Follow the repository's strict IaC-first rule (`AGENTS.md` Rule #1): Compose template in repo,
  deployed via Terraform-managed Portainer stack, secrets sourced from Vault at apply time, DNS +
  Nginx vhost in repo, PR → merge → targeted apply from `main`.
- Hybrid AI routing via co-located `litellm` (`http://litellm:4000` on `project-nomad_default`):
  - Local embeddings on `nomad_embed_ollama` (`nomic-embed-text:v1.5`).
  - Curated external/subscription chat models via LiteLLM Proxy.
- Store bulk offline content (ZIM files, maps, books, uploaded docs) on NAS-backed NFS
  (`/nfs/dockermaster/nomad/storage`) while keeping latency/lock-sensitive MySQL, Redis, and Ollama
  model cache on `ds-2` local ext4 SSD (`/opt/project-nomad/{mysql,redis,ollama}`).

## 3. Non-goals

- Public internet exposure via Cloudflare tunnel (`*.cf.lcamaral.com`) — Project NOMAD has **no
  built-in authentication** by design. Access is restricted to LAN + Twingate (`nomad.d.lcamaral.com`).
- Running `nomad_ollama` for large local chat LLMs on `ds-2` CPU — chat is offloaded through
  LiteLLM to external providers.
- Running `nomad_updater` sidecar — upstream's updater mutates `/opt/project-nomad/compose.yml` on
  disk, which conflicts with Terraform + Portainer management. Container images are version-pinned
  and updated via IaC PRs.
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
          ┌──────────────────────────────────────────────────────────┐
          │               stack: nomad (dockerserver-2)              │
          │         network: project-nomad_default (bridge)          │
          │                                                          │
          │  ┌──────────────┐     ┌───────────────────────────────┐  │
          │  │ nomad_admin  │────►│ litellm (:4000)               │  │
          │  │ (:8080)      │     │ (OpenAI-compat AI router)     │  │
          │  │ .59.60       │     └──────┬─────────────────┬──────┘  │
          │  └──┬────────┬──┘            │                 │         │
          │     │        │               ▼                 │         │
          │  ┌──▼───┐ ┌──▼──────────┐ ┌──────────────────┐ │         │
          │  │mysql │ │redis        │ │nomad_embed_ollama│ │         │
          │  │8.0   │ │7-alpine     │ │(nomic-embed-text)│ │         │
          │  └──────┘ └─────────────┘ └──────────────────┘ │         │
          │  ┌───────────────────────┐                     │         │
          │  │nomad_disk_collector   │                     │         │
          │  └───────────────────────┘                     │         │
          │  ┌───────────────────────┐                     │         │
          │  │nomad_qdrant / kiwix.. │                     │         │
          │  │(spawned via DooD)     │                     │         │
          │  └───────────────────────┘                     │         │
          └────────────────────────────────────────────────┼─────────┘
                                                           │
                                                           ▼
                                            External / Subscription AI
                                            (OpenRouter via Vault key)
```

## 5. Components

| Service | Image (pinned) | Networks | Role |
|---------|----------------|----------|------|
| `admin` (`nomad_admin`) | `ghcr.io/crosstalk-solutions/project-nomad:v1.35.1` | `servers-net` (`.60`), `default` (`project-nomad_default`) | Command Center UI & API on `:8080`. Health: `GET /api/health`. |
| `mysql` (`nomad_mysql`) | `mysql:8.0` | `default` (`project-nomad_default`) | Command Center relational DB (`nomad`). |
| `redis` (`nomad_redis`) | `redis:7-alpine` | `default` (`project-nomad_default`) | BullMQ job queue (downloads, ZIM/RAG ingestion) + cache. |
| `disk-collector` (`nomad_disk_collector`) | `ghcr.io/crosstalk-solutions/project-nomad-disk-collector:v1.31.1` | `default` (`project-nomad_default`) | Reads host/NFS storage stats (`ro,rslave`) for Command Center UI. |
| `ollama` (`nomad_embed_ollama`) | `ollama/ollama:0.40.16` | `default` (`project-nomad_default`) | Embeddings-only Ollama (`nomic-embed-text:v1.5`), capped at 4 CPUs / 3G RAM. |
| `litellm` (`nomad_litellm`) | `ghcr.io/berriai/litellm:v1.108.8` | `default` (`project-nomad_default`) | OpenAI-compatible AI router on `:4000` bridging NOMAD to `ollama` embeddings + external chat models. |

Standard labels on all containers:

- `loki.logging=true` — Promtail ships container logs to Loki.
- `com.centurylinklabs.watchtower.enable=false` — all images are version-pinned and updated via IaC PRs.
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
   and uses `project-nomad_default` for internal communication.
3. **Avoid colliding with `nomad_ollama`:**
   The stack's embedding Ollama container is named `nomad_embed_ollama` (Compose service `ollama`)
   so NOMAD's built-in AI Assistant installer will never mistake it for a NOMAD-managed
   `nomad_ollama` container.

## 6. Hybrid AI & RAG Routing Design

### 6.1 How Project NOMAD's `OllamaService` and `RagService` Work

From `admin/app/services/ollama_service.ts` and `admin/app/services/rag_service.ts`:

1. NOMAD reads `ai.remoteOllamaUrl` from its `KVStore` table (configured in the UI under
   **Settings → AI Assistant → Remote Ollama/OpenAI API URL**).
2. When `ai.remoteOllamaUrl` points to `http://litellm:4000`:
   - NOMAD probes `GET http://litellm:4000/api/tags`, gets a `404`, and automatically switches to
     its **OpenAI-compatible client** (`baseURL: 'http://litellm:4000/v1'`, `apiKey: 'nomad'`).
3. For **Knowledge Base / ZIM RAG (`RagService`)**:
   - `RagService` hardcodes `EMBEDDING_MODEL_NAME = 'nomic-embed-text:v1.5'` and
     `EMBEDDING_DIMENSION = 768`.
   - Before embedding or searching Qdrant, `RagService` calls `ollamaService.getModels(true)`
     (`GET /v1/models`) and verifies that `nomic-embed-text:v1.5` is present in the returned list.
   - It then calls `POST /v1/embeddings` with `model: "nomic-embed-text:v1.5"`.
4. For **Chat (`OllamaService.getModels(false)`)**:
   - NOMAD calls `GET /v1/models`, filters out any model containing `embed` in its name, and
     populates the UI model selector with the remaining curated models.

### 6.2 LiteLLM Proxy Configuration (`litellm-config.yaml`)

Injected into the `litellm` container via Docker Compose inline `configs:` (rendered by Terraform):

```yaml
model_list:
  - model_name: nomic-embed-text:v1.5
    litellm_params:
      model: ollama/nomic-embed-text:v1.5
      api_base: http://ollama:11434

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

## 7. Networking

| Network | Driver | Scope | Purpose |
|---------|--------|-------|---------|
| `docker-servers-net` | macvlan (external) | host | LAN reachability for `nomad_admin` at **`192.168.59.60`**. |
| `default` (`project-nomad_default`) | bridge (stack) | stack | Internal stack network for `admin` ↔ `mysql`, `redis`, `ollama`, `litellm`, and DooD-spawned `nomad_*` containers (`nomad_qdrant`, `nomad_kiwix`, etc.). |

### 7.1 IP Allocation

`nomad_admin` is assigned **`192.168.59.60`** from the `192.168.59.0/26` pool (verified unused in
`terraform/`, `pihole/`, `dockermaster/docker/`, and `arping` from `ds-2` returned 0 replies).

## 8. Storage

Hybrid storage layout to avoid database locking issues on `soft,local_lock=none` NFS mounts (per the
`calibre-web` lesson in `inventory/docker-containers.md`):

| Host Path on `ds-2` | Container Mount | Backing Store | Purpose |
|---------------------|-----------------|---------------|---------|
| `/nfs/dockermaster/nomad/storage` | `/app/storage` (`admin`), `/storage` (`disk-collector`) | Synology NAS NFS (`/volume2/servers`) | ZIM files, offline maps, books, Qdrant vectors, KB uploads |
| `/opt/project-nomad/mysql` | `/var/lib/mysql` (`mysql`) | `ds-2` local ext4 SSD | MySQL 8.0 InnoDB tables |
| `/opt/project-nomad/redis` | `/data` (`redis`) | `ds-2` local ext4 SSD | Redis AOF/RDB queue state |
| `/opt/project-nomad/ollama` | `/root/.ollama` (`nomad_embed_ollama`) | `ds-2` local ext4 SSD | `nomic-embed-text:v1.5` weights (~275 MB) |

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
`terraform/portainer/stacks.tf`), matching the repository's standard Nginx vhost pattern
(`/etc/nginx/cert/d.lcamaral.com.{fullchain,key,crt}`, `http2 on`, `otel_trace_context propagate`,
`$connection_upgrade`, `proxy_buffering off`, `client_max_body_size 500m`).

## 11. Secrets (Vault)

New Vault KV-v2 path: `secret/homelab/nomad`

| Key | Description | Consumed by |
|-----|-------------|-------------|
| `app_key` | 32-char random hex string (`APP_KEY` >= 16 chars required by AdonisJS) | `nomad_admin` |
| `db_password` | MySQL `nomad_user` password | `nomad_admin`, `nomad_mysql` |
| `mysql_root_password` | MySQL root password | `nomad_mysql` |
| `openrouter_api_key` | OpenRouter API key (reused from `secret/homelab/honcho`) | `nomad_litellm` |

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
├── inventory/
│   └── docker-containers.md                  # Document nomad stack & .59.60 IP
└── terraform/portainer/
    ├── vault.tf                              # +1 data source: nomad
    └── stacks.tf                             # +1 portainer_stack: nomad (on ds2_endpoint_id)
```

## 13. Post-Deploy Steps (After Merge & Apply from `main`)

1. Pull `nomic-embed-text:v1.5` inside `nomad_embed_ollama`:
   `ssh dockerserver-2 'docker exec nomad_embed_ollama ollama pull nomic-embed-text:v1.5'`
2. Redeploy `reverse-proxy`, `reverse-proxy-2`, `reverse-proxy-3`, `pihole-2`, `pihole-3` via
   `scripts/portainer-redeploy.py` so the updated inline `configs:` mount into running containers.
3. Sync `04-d-lcamaral-com.conf` to `pihole-1` LXC via `scripts/sync-host-overrides.py --apply`.
4. Open `https://nomad.d.lcamaral.com` → **Settings → AI Assistant → Remote Connection** and set
   **Remote Ollama / OpenAI API URL** to `http://litellm:4000`.
5. Install the **AI Assistant** (Qdrant) in NOMAD's UI (or verify Qdrant runs alongside `litellm`).

## 14. Verification / Acceptance

1. All 6 containers in stack `nomad` healthy on `ds-2` (`docker ps --filter "label=com.docker.stack=nomad"`).
2. `docker exec nomad_admin curl -sf http://litellm:4000/v1/models` lists `nomic-embed-text:v1.5` +
   chat models.
3. Embedding round-trip via `http://litellm:4000/v1/embeddings` returns a 768-dim vector.
4. Chat completion test via `http://litellm:4000/v1/chat/completions` returns an OpenRouter response.
5. `curl -sf https://nomad.d.lcamaral.com/api/health` returns HTTP 200.

## 15. Known Risks / Mitigations

| Risk | Mitigation |
|------|------------|
| `ds-2` local disk space | Heavy NOMAD content (`storage/`) lives on `/nfs/dockermaster/nomad/storage`; `ds-2` local SSD (`61 GB` free) only holds MySQL/Redis (~200 MB), `nomic-embed-text:v1.5` (~275 MB), and images. |
| Child apps (`nomad_kiwix`, `nomad_kolibri`) bind ports `8090+` on `ds-2` | `ds-2` has those host ports free. |
| NOMAD AI Assistant installer starts `nomad_ollama` container by default | Configure `Remote Ollama/OpenAI API URL = http://litellm:4000` in Settings and stop `nomad_ollama` if created (upstream issue #662). |
