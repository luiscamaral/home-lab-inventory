# Ollama Embedding Service — Deployment Design

**Date:** 2026-05-21
**Status:** Approved (precursor to Honcho deployment)
**Owner:** lamaral
**Service:** [Ollama](https://ollama.com) — local LLM/embedding runtime

---

## 1. Overview

Deploy a minimal Ollama instance on `dockerserver-1` (ds-1, Portainer endpoint id 9) to
serve embeddings for the upcoming Honcho memory server. Embeddings only — no chat models.

This is a precursor sub-project to the Honcho deployment (see
[Honcho design](2026-05-20-honcho-deployment-design.md)). Honcho's embedding pipeline points
at this Ollama instance; without it, the Honcho deployment cannot complete acceptance §15.

## 2. Goals

- Single-container Ollama instance reachable at `ollama.d.lcamaral.com` from the homelab LAN.
- Pull a single model: `qwen3-embedding:8b-q8_0` (4096-dim output, 8-bit quantized).
- Internal-only (no Cloudflare tunnel). HTTP only (Ollama has no native TLS).
- All IaC: compose template, Terraform-managed Portainer stack, DNS in repo.

## 3. Non-goals

- Chat / generation models — Honcho's chat pipeline goes through OpenRouter, not Ollama.
- GPU acceleration — ds-1 has no GPU; CPU inference only.
- Authentication — Ollama has no built-in auth; access is gated by LAN reachability.
- HTTPS in front via Nginx — overkill for internal HTTP traffic; skip the rproxy layer.
- Multi-host HA — single instance is enough; embeddings can re-run if the service blips.

## 4. Architecture

```text
Honcho services on ds-1 (api + deriver)
  │
  │  POST /v1/embeddings    {"model": "qwen3-embedding:8b-q8_0",
  │                          "input": "..."}
  │
  ▼
ollama.d.lcamaral.com (DNS single-A → 192.168.59.53)
  │
  ▼
ds-1 ──── docker-servers-net macvlan ──── 192.168.59.53:11434
              │
              ▼
        ┌─────────────┐
        │ ollama      │
        │ /root/.ollama → /nfs/dockermaster/ollama/data
        └─────────────┘
```

Single container. Single macvlan IP. Direct HTTP from Honcho.

## 5. Components

| Service | Image | Network | Role |
|---------|-------|---------|------|
| `ollama` | `ollama/ollama:latest` | `docker-servers-net` macvlan @ 192.168.59.53 | Serves Ollama HTTP API on :11434 |

Standard labels:

- `loki.logging=true`
- `com.centurylinklabs.watchtower.enable=true` (Ollama auto-updates)
- `com.docker.stack=ollama`, `com.docker.service=ollama`
- `portainer.autodeploy=false` (Terraform-managed)

### Resource limits (Compose `deploy.resources`)

- `cpus: 4` (embedding inference is CPU-bound; ds-1 has 10 cores)
- `memory: 12G` (q8_0 8B uses ~8-9 GB at inference; 12 GB cap gives headroom)
- `reservations.memory: 1G`

Healthcheck: `ollama list` via `wget` against `/api/tags`.

## 6. Networking

- `docker-servers-net` (macvlan, external) — pinned IP **192.168.59.53**.
- No bridge networks — nothing else in the stack to talk to internally.
- Honcho on ds-1 reaches Ollama via cross-host macvlan routing (same way it'd reach any
  other `.59.x` service).

### IP allocation verification

Pre-apply: `ssh dockerserver-1 'sudo arping -I server-net-shim -c 3 192.168.59.53'`.
Expect zero replies.

## 7. Storage

NFS-backed bind mount:

```text
/nfs/dockermaster/ollama/data → /root/.ollama (in container)
```

Pre-deploy: `ssh dockerserver-1 'sudo mkdir -p /nfs/dockermaster/ollama/data'`.

The `qwen3-embedding:8b-q8_0` model is ~9 GB on disk; ensure the underlying NFS volume has
that available before pulling.

Backups: inherits Synology NFS snapshot policy on `/volume2/servers`. Model files are
re-pullable from `ollama.com` if storage is ever lost — no critical state.

## 8. DNS

Single-A record (no multi-A across rproxies, since we're bypassing rproxy):

```text
# Ollama embedding service (single-host on ds-1, direct macvlan access)
address=/ollama.d.lcamaral.com/192.168.59.53
```

Lives in `pihole/dnsmasq.d/04-d-lcamaral-com.conf`.

## 9. Reverse proxy

**None.** Direct HTTP to the macvlan IP. Ollama's native HTTP API on :11434 is what Honcho
talks to. Adding rproxy would introduce TLS termination complexity and buffering issues for
streaming embedding endpoints, with no real benefit for an internal-only service.

## 10. Secrets

**None.** No Vault path needed. Ollama has no auth tokens.

## 11. Model management

Single model: `qwen3-embedding:8b-q8_0`.

- Disk footprint: ~9 GB
- Inference RAM: ~8-9 GB
- Vector output dimensions: **4096** (verified post-pull by inspecting model metadata)
- Quantization: q8_0 (8-bit, near-lossless quality for embeddings)

Pull happens post-deploy as a one-off:

```bash
ssh dockerserver-1 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'
```

After the pull, verify dimensions with:

```bash
ssh dockerserver-1 \
  'docker exec ollama curl -s http://localhost:11434/api/embed \
   -d "{\"model\": \"qwen3-embedding:8b-q8_0\", \"input\": \"test\"}" \
   | python3 -c "import sys, json; print(len(json.load(sys.stdin)[\"embeddings\"][0]))"'
```

Expected: `4096`. If it returns a different number, update the Honcho spec + plan to match.

## 12. IaC layout

```text
inventory/
├── dockermaster/docker/compose/ollama/
│   └── docker-compose.yml.tftpl       # NEW (replaces stale legacy file)
├── pihole/dnsmasq.d/
│   └── 04-d-lcamaral-com.conf         # +1 line (ollama A record)
└── terraform/portainer/
    └── stacks.tf                       # +1 portainer_stack: ollama (on ds1_endpoint_id)
```

The existing `dockermaster/docker/compose/ollama/docker-compose.yml` is a stale legacy
bind-mount-style file and will be **replaced** by the new templated version. No Vault data
source needed.

## 13. Deployment workflow

```text
1. Pre-flight:
   - arping 192.168.59.53 on ds-1 → expect 0 replies
   - mkdir /nfs/dockermaster/ollama/data on ds-1
2. Write new compose template (replaces stale file).
3. Add DNS record to pihole/dnsmasq.d/04-d-lcamaral-com.conf.
4. Add portainer_stack resource to terraform/portainer/stacks.tf.
5. terraform -chdir=terraform/portainer plan + apply.
6. Pull model: docker exec ollama ollama pull qwen3-embedding:8b-q8_0.
7. Verify vector dimensions (§11).
8. Sync DNS to pihole instances + verify resolution from ds-1.
9. Update Honcho spec + plan with the verified embedding model name + dimensions.
```

## 14. Operations

- **Updates:** Watchtower auto-updates `ollama/ollama:latest`. Model files persist across
  image upgrades (volume bind mount).
- **Adding more models:** `docker exec ollama ollama pull <model>` — runtime command, no
  IaC change needed.
- **Backups:** NFS snapshot policy. Models are re-pullable; no critical state.
- **Monitoring:** cadvisor-ds1 picks up the container automatically. No Prometheus metrics
  endpoint on Ollama (yet); skip dashboard work for now.

## 15. Verification / acceptance

After `terraform apply` and model pull:

1. **Container healthy:**

   ```bash
   ssh dockerserver-1 'docker ps --filter name=ollama --format "{{.Status}}"'
   ```

   Expected: `Up X minutes (healthy)`.

2. **Model present:**

   ```bash
   ssh dockerserver-1 'docker exec ollama ollama list | grep qwen3-embedding'
   ```

   Expected: a row showing `qwen3-embedding:8b-q8_0`, size ~9 GB.

3. **API reachable via macvlan IP:**

   ```bash
   curl -sf http://192.168.59.53:11434/api/tags
   ```

   Expected: JSON with the model listed.

4. **API reachable via DNS from ds-1 (Honcho's vantage point):**

   ```bash
   ssh dockerserver-1 'curl -sf http://ollama.d.lcamaral.com/api/tags'
   ```

   Expected: same JSON.

5. **Embedding endpoint returns 4096-dim vector:**

   ```bash
   ssh dockerserver-1 \
     'curl -s http://ollama.d.lcamaral.com/api/embed \
       -d "{\"model\": \"qwen3-embedding:8b-q8_0\", \"input\": \"hello\"}" \
       | python3 -c "import sys, json; print(len(json.load(sys.stdin)[\"embeddings\"][0]))"'
   ```

   Expected: `4096`.

6. **OpenAI-compatible endpoint also works** (Honcho uses `/v1/embeddings`):

   ```bash
   ssh dockerserver-1 \
     'curl -s http://ollama.d.lcamaral.com/v1/embeddings \
       -H "Content-Type: application/json" \
       -d "{\"model\": \"qwen3-embedding:8b-q8_0\", \"input\": \"hello\"}" \
       | python3 -c "import sys, json; print(len(json.load(sys.stdin)[\"data\"][0][\"embedding\"]))"'
   ```

   Expected: `4096`.

If any check fails, debug before declaring done.

## 16. Known risks / open items

| Risk | Mitigation |
|------|------------|
| Cross-host macvlan routing flaky | Documented in `feedback_macvlan_ip_collisions.md`. Pin stable MAC for the container if observed. |
| 8B model OOMs ds-1 (24 GB total) | 12 GB compose limit + 1 GB reservation. Other ds-1 stacks (vault-3, keycloak-2, etc.) use ~10 GB combined. Should be safe with 2 GB+ headroom. |
| First pull takes ~5-10 min on local internet | One-time post-deploy step; not part of `terraform apply`. |
| CPU inference is slow (~2-5 s per embed) | Embeddings are async on Honcho's deriver; throughput matters more than latency. Accept. |
| Ollama `:latest` image may break compatibility | Watchtower-managed. Model API has been stable for 18+ months; low risk. |

## 17. Out of scope

- Pulling chat models.
- GPU acceleration / discrete GPU procurement.
- Adding `nginx-rproxy` HTTPS frontend.
- Prometheus exporter for Ollama.
- Cloudflare tunnel public exposure.
- Auth proxy (mTLS or bearer-token middleware).
