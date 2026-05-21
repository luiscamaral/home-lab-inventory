# Ollama Embedding Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Deploy a single-container Ollama instance on ds-1 serving the
`qwen3-embedding:8b-q8_0` model at `ollama.d.lcamaral.com:11434` so Honcho can use it for
embeddings.

**Architecture:** Single Compose stack on ds-1 with one Ollama container on
`docker-servers-net` macvlan at `192.168.59.53`, NFS-backed model storage, direct HTTP API
(no Nginx-rproxy, no auth, no TLS — internal LAN only).

**Tech Stack:** Docker Compose, Portainer, Terraform (portainer provider), Ollama.

**Spec:** [Ollama deployment design](../specs/2026-05-21-ollama-deployment-design.md)

---

## Conventions

- File paths relative to repo root unless noted.
- SSH shortcuts from `~/.ssh/config`: `proxmox`, `dockerserver-1`, `dockerserver-2`, `pihole`.
- Non-interactive sudo on dockermaster/ds-1/ds-2: `SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A <cmd>`.
- On proxmox: `SUDO_ASKPASS=$HOME/.config/bin/answer.sh sudo -A <cmd>` (`.sh` suffix).
- Pre-commit hooks enforce markdownlint + conventional commit format.

---

## File Structure

| Action | Path | Purpose |
|--------|------|---------|
| Replace | `dockermaster/docker/compose/ollama/docker-compose.yml` | Delete stale legacy file |
| Create | `dockermaster/docker/compose/ollama/docker-compose.yml.tftpl` | New templated stack |
| Modify | `pihole/dnsmasq.d/04-d-lcamaral-com.conf` | +1 A record for ollama |
| Modify | `terraform/portainer/stacks.tf` | +1 `portainer_stack.ollama` resource on ds1_endpoint_id |
| Modify | `inventory/docker-containers.md` | Document the new stack |

---

## Task 1: Pre-flight verifications on ds-1

**Files:** None (verification only).

- [ ] **Step 1.1: Find macvlan parent interface on ds-1**

```bash
ssh dockerserver-1 'ip -o link show | grep -E "macvlan|server-net"'
```

Expected: a `server-net-shim` interface (or similar — note the actual name).

- [ ] **Step 1.2: arping 192.168.59.53 for collision**

```bash
ssh dockerserver-1 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A arping -I server-net-shim -c 3 192.168.59.53'
```

Expected: `0 packets received` / `100% unanswered`. If any reply → STOP, pick a different
free IP from the .59.0/26 range (.5, .8, .14, .33, .34, .36, .59, .60, .61, .62) and update
spec + plan before continuing.

- [ ] **Step 1.3: Create NFS storage directory**

```bash
ssh dockerserver-1 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A mkdir -p /nfs/dockermaster/ollama/data && \
                    ls -la /nfs/dockermaster/ollama/'
```

Expected: `data` directory listed.

- [ ] **Step 1.4: Verify NFS has enough free space**

```bash
ssh dockerserver-1 'df -h /nfs/dockermaster | tail -1'
```

Expected: at least 15 GB available (model is ~9 GB, give headroom).

- [ ] **Step 1.5: Confirm ds-1's Docker is up and the endpoint is reachable**

```bash
ssh dockerserver-1 'docker version --format "{{.Server.Version}}"'
```

Expected: a Docker server version string (no error).

- [ ] **Step 1.6: No commit needed**

---

## Task 2: Delete the stale compose file and write the new templated one

**Files:**

- Delete: `dockermaster/docker/compose/ollama/docker-compose.yml`
- Create: `dockermaster/docker/compose/ollama/docker-compose.yml.tftpl`

- [ ] **Step 2.1: Delete the stale file**

```bash
git rm dockermaster/docker/compose/ollama/docker-compose.yml
```

- [ ] **Step 2.2: Write the new templated stack**

```bash
cat > dockermaster/docker/compose/ollama/docker-compose.yml.tftpl <<'EOF'
name: ollama

# Ollama embedding service on ds-1.
# Spec: docs/superpowers/specs/2026-05-21-ollama-deployment-design.md
# Single container, macvlan IP 192.168.59.53, NFS-backed model storage.
# Embeddings only: qwen3-embedding:8b-q8_0 (4096-dim). Pulled post-deploy.

networks:
  servers-net:
    name: docker-servers-net
    external: true

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    hostname: ollama
    networks:
      servers-net:
        ipv4_address: 192.168.59.53
    volumes:
      - /nfs/dockermaster/ollama/data:/root/.ollama
    environment:
      OLLAMA_HOST: "0.0.0.0:11434"
      OLLAMA_KEEP_ALIVE: "30m"
    healthcheck:
      test: ["CMD-SHELL", "ollama list > /dev/null"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 12G
        reservations:
          memory: 1G
    labels:
      loki.logging: "true"
      com.centurylinklabs.watchtower.enable: "true"
      com.docker.stack: "ollama"
      com.docker.service: "ollama"
      portainer.autodeploy: "false"
EOF
```

- [ ] **Step 2.3: Sanity-check the YAML syntax**

```bash
docker compose -f dockermaster/docker/compose/ollama/docker-compose.yml.tftpl config > /dev/null && echo OK
```

Expected: `OK`. No template vars in this file, so it parses cleanly as plain YAML.

- [ ] **Step 2.4: Commit**

```bash
git add dockermaster/docker/compose/ollama/docker-compose.yml dockermaster/docker/compose/ollama/docker-compose.yml.tftpl
git commit -m "feat(docker): ollama embedding service compose stack (ds-1, macvlan .53)"
```

---

## Task 3: Add DNS record for ollama.d.lcamaral.com

**Files:**

- Modify: `pihole/dnsmasq.d/04-d-lcamaral-com.conf`

- [ ] **Step 3.1: Find a sensible insertion point**

```bash
grep -n "minio\|prometheus\|rmq" pihole/dnsmasq.d/04-d-lcamaral-com.conf | head -5
```

Pick an alphabetical position (between `nginx` block and `prometheus`/`pihole`).

- [ ] **Step 3.2: Insert the single-A record**

Open `pihole/dnsmasq.d/04-d-lcamaral-com.conf` and add the lines below at the chosen
position:

```text
# Ollama embedding service (single-host on ds-1, direct macvlan access — no rproxy)
address=/ollama.d.lcamaral.com/192.168.59.53
```

- [ ] **Step 3.3: Verify the edit**

```bash
grep "ollama" pihole/dnsmasq.d/04-d-lcamaral-com.conf
```

Expected: 1 `address=/ollama.d.lcamaral.com/192.168.59.53` line.

- [ ] **Step 3.4: Commit**

```bash
git add pihole/dnsmasq.d/04-d-lcamaral-com.conf
git commit -m "feat(network): DNS record for ollama.d.lcamaral.com"
```

---

## Task 4: Add portainer_stack resource to Terraform

**Files:**

- Modify: `terraform/portainer/stacks.tf`

- [ ] **Step 4.1: Append the resource at the END of `stacks.tf`**

```hcl

# ──────────────────────────────────────────────
# Ollama embedding service (ds-1)
# Spec: docs/superpowers/specs/2026-05-21-ollama-deployment-design.md
# Single container on docker-servers-net @ 192.168.59.53.
# Pulled post-deploy: qwen3-embedding:8b-q8_0 (4096-dim).
# Honcho's deriver consumes this for message/document embeddings.
# ──────────────────────────────────────────────
resource "portainer_stack" "ollama" {
  name            = "ollama"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/../../dockermaster/docker/compose/ollama/docker-compose.yml.tftpl")
}
```

Note: no `env {}` block needed — Ollama has no secrets, and the compose file uses no
templating placeholders (so `file()` is enough; no `templatefile()` required).

- [ ] **Step 4.2: Format + validate**

```bash
cd terraform/portainer
terraform fmt stacks.tf
terraform validate
cd ../..
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4.3: Commit**

```bash
git add terraform/portainer/stacks.tf
git commit -m "feat(deploy): portainer_stack for ollama on ds-1"
```

---

## Task 5: Terraform plan + apply

**Files:** None (state changes only).

- [ ] **Step 5.1: Source Vault token (the provider needs it even though Ollama has no secret)**

```bash
export VAULT_ADDR=http://vault.d.lcamaral.com
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
```

- [ ] **Step 5.2: Run `terraform plan`**

```bash
cd terraform/portainer
terraform plan -out=ollama.tfplan
```

Expected output:

```text
Terraform will perform the following actions:

  # portainer_stack.ollama will be created

Plan: 1 to add, 0 to change, 0 to destroy.
```

If anything else changes, STOP and investigate.

- [ ] **Step 5.3: Apply**

```bash
terraform apply ollama.tfplan
cd ../..
```

Expected: `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`

- [ ] **Step 5.4: Confirm the container is up on ds-1**

```bash
ssh dockerserver-1 'docker ps --filter name=ollama --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"'
```

Expected: `ollama  Up X seconds (health: starting)` then `(healthy)` after ~60 s.

- [ ] **Step 5.5: No commit (state-only)**

---

## Task 6: Pull the embedding model

**Files:** None (runtime state change inside the container).

- [ ] **Step 6.1: Pull qwen3-embedding:8b-q8_0**

```bash
ssh dockerserver-1 'docker exec ollama ollama pull qwen3-embedding:8b-q8_0'
```

Expected: download progress, ending with `success`. Takes ~5-10 minutes depending on your
internet speed.

- [ ] **Step 6.2: Confirm the model is loaded**

```bash
ssh dockerserver-1 'docker exec ollama ollama list'
```

Expected: a row showing `qwen3-embedding:8b-q8_0` with size ~9 GB.

- [ ] **Step 6.3: Verify the output dimensions (THE critical check)**

```bash
ssh dockerserver-1 \
  'docker exec ollama curl -s http://localhost:11434/api/embed \
    -d "{\"model\": \"qwen3-embedding:8b-q8_0\", \"input\": \"test\"}" \
    | python3 -c "import sys, json; d=json.load(sys.stdin); print(\"dims:\", len(d[\"embeddings\"][0]))"'
```

Expected: `dims: 4096`. If different, RECORD the actual value — Task 8 updates Honcho to
match it. Do not proceed past this step without recording the real dimension count.

---

## Task 7: Sync DNS and verify reachability

**Files:** None (deployment of file already committed in Task 3).

- [ ] **Step 7.1: Deploy the dnsmasq config to pihole**

```bash
scp pihole/dnsmasq.d/04-d-lcamaral-com.conf pihole:/tmp/04-d-lcamaral-com.conf
ssh pihole 'sudo mv /tmp/04-d-lcamaral-com.conf /etc/pihole/dnsmasq.d/04-d-lcamaral-com.conf && \
            sudo systemctl restart pihole-FTL && \
            sleep 2 && systemctl is-active pihole-FTL'
```

Expected: `active`.

- [ ] **Step 7.2: Verify DNS resolves**

```bash
dig +short @192.168.100.254 ollama.d.lcamaral.com
```

Expected: `192.168.59.53`.

- [ ] **Step 7.3: Verify the API is reachable from ds-1 (Honcho's vantage point)**

```bash
ssh dockerserver-1 'curl -sf http://ollama.d.lcamaral.com/api/tags | python3 -c "import sys, json; print(\"models:\", [m[\"name\"] for m in json.load(sys.stdin)[\"models\"]])"'
```

Expected: `models: ['qwen3-embedding:8b-q8_0']`.

- [ ] **Step 7.4: Verify the OpenAI-compatible endpoint works**

```bash
ssh dockerserver-1 \
  'curl -s http://ollama.d.lcamaral.com/v1/embeddings \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"qwen3-embedding:8b-q8_0\", \"input\": \"hello\"}" \
    | python3 -c "import sys, json; d=json.load(sys.stdin); print(\"dims:\", len(d[\"data\"][0][\"embedding\"]))"'
```

Expected: `dims: 4096` (or whatever value Task 6.3 returned).

---

## Task 8: Update Honcho spec + plan with verified embedding details

**Files:**

- Modify: `docs/superpowers/specs/2026-05-20-honcho-deployment-design.md`
- Modify: `docs/superpowers/plans/2026-05-20-honcho-deployment.md`

Honcho's docs currently say `nomic-embed-text` (768-dim). Update to the real values from
Task 6.3.

- [ ] **Step 8.1: Update model name + dimensions in the Honcho spec**

In `docs/superpowers/specs/2026-05-20-honcho-deployment-design.md`, replace
all occurrences of `nomic-embed-text` with `qwen3-embedding:8b-q8_0` and all occurrences
of `768` (used as the embedding dimension) with `4096` (or the actual value from Task 6.3).

```bash
# Verify the replacements with a dry run first:
grep -nE 'nomic-embed-text|EMBEDDING_VECTOR_DIMENSIONS' \
  docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
```

Apply replacements (carefully — `768` may appear in unrelated context like timeouts; check
each match):

```bash
sed -i.bak 's|nomic-embed-text|qwen3-embedding:8b-q8_0|g' \
  docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
sed -i.bak 's|EMBEDDING_VECTOR_DIMENSIONS=768|EMBEDDING_VECTOR_DIMENSIONS=4096|g' \
  docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
sed -i.bak 's|`nomic-embed-text` (768-dim)|`qwen3-embedding:8b-q8_0` (4096-dim)|g' \
  docs/superpowers/specs/2026-05-20-honcho-deployment-design.md
rm docs/superpowers/specs/2026-05-20-honcho-deployment-design.md.bak
diff <(git show HEAD:docs/superpowers/specs/2026-05-20-honcho-deployment-design.md) \
     docs/superpowers/specs/2026-05-20-honcho-deployment-design.md | head -30
```

- [ ] **Step 8.2: Same replacements in the Honcho plan**

```bash
grep -nE 'nomic-embed-text|EMBEDDING_VECTOR_DIMENSIONS=768' \
  docs/superpowers/plans/2026-05-20-honcho-deployment.md
sed -i.bak 's|nomic-embed-text|qwen3-embedding:8b-q8_0|g' \
  docs/superpowers/plans/2026-05-20-honcho-deployment.md
sed -i.bak 's|EMBEDDING_VECTOR_DIMENSIONS=768|EMBEDDING_VECTOR_DIMENSIONS=4096|g' \
  docs/superpowers/plans/2026-05-20-honcho-deployment.md
sed -i.bak 's|`nomic-embed-text` (768-dim)|`qwen3-embedding:8b-q8_0` (4096-dim)|g' \
  docs/superpowers/plans/2026-05-20-honcho-deployment.md
rm docs/superpowers/plans/2026-05-20-honcho-deployment.md.bak
```

- [ ] **Step 8.3: Spot-check the changes**

```bash
grep -nE 'qwen3-embedding|EMBEDDING_VECTOR_DIMENSIONS' \
  docs/superpowers/specs/2026-05-20-honcho-deployment-design.md \
  docs/superpowers/plans/2026-05-20-honcho-deployment.md | head -20
```

Expected: lines reference `qwen3-embedding:8b-q8_0` and `EMBEDDING_VECTOR_DIMENSIONS=4096`.
No leftover `nomic-embed-text` references.

- [ ] **Step 8.4: Commit**

```bash
git add docs/superpowers/specs/2026-05-20-honcho-deployment-design.md \
        docs/superpowers/plans/2026-05-20-honcho-deployment.md
git commit -m "docs(docker): retarget honcho embeddings to qwen3-embedding:8b-q8_0 (4096-dim)"
```

---

## Task 9: Update inventory documentation

**Files:**

- Modify: `inventory/docker-containers.md`

- [ ] **Step 9.1: Remove the "Removed" entry for Ollama**

```bash
grep -n "| ollama | Removed" inventory/docker-containers.md
```

Delete that line (Ollama is no longer "Removed").

- [ ] **Step 9.2: Add an active entry under the ds-1 section**

Open `inventory/docker-containers.md` and add (in the appropriate spot — ds-1 section):

```markdown
### ollama (embedding service)

- **Host:** dockerserver-1 (ds-1)
- **Stack:** `terraform/portainer/stacks.tf` → `portainer_stack.ollama`
- **Compose:** `dockermaster/docker/compose/ollama/docker-compose.yml.tftpl`
- **Containers:** `ollama`
- **Image:** `ollama/ollama:latest` (watchtower-managed)
- **Macvlan IP:** `192.168.59.53`
- **URL (internal):** <http://ollama.d.lcamaral.com:11434>
- **Models pulled:** `qwen3-embedding:8b-q8_0` (4096-dim, ~9 GB)
- **Resource limits:** 4 cores / 12 GB RAM
- **Storage:** `/nfs/dockermaster/ollama/data`
- **Vault:** none (Ollama has no auth, internal LAN only)
- **Consumed by:** Honcho deriver + api (embeddings)
- **Spec:** `docs/superpowers/specs/2026-05-21-ollama-deployment-design.md`
```

- [ ] **Step 9.3: Commit + push**

```bash
git add inventory/docker-containers.md
git commit -m "docs(inventory): activate ollama entry (embedding service on ds-1)"
git push origin main
```

Expected: commits from Tasks 2, 3, 4, 8, 9 ship to `origin/main`.

---

## After this plan

Honcho's pre-flight (Task 1) was paused at steps 1.4 and 1.5 (Ollama checks). Resume the
Honcho plan from there:

1. Re-run Honcho's Task 1.4 + 1.5 — both should now pass.
2. Continue with Honcho Tasks 2-12 as written, with the updated `qwen3-embedding:8b-q8_0`
   model name and 4096 dimensions baked in (via Task 8 of this plan).
