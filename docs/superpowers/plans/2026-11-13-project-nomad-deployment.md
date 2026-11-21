# Project NOMAD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Project NOMAD (`nomad_admin`, `mysql`, `redis`, `disk-collector`) + an
embeddings-only `ollama` (`nomad_embed_ollama`) + a co-located `litellm` AI router on
`dockerserver-2` (`ds-2`), reachable internally at `https://nomad.d.lcamaral.com`, fully managed
via Terraform + Portainer and deployed per `AGENTS.md` Rule #1 (PR → merge → apply from `main`).

**Architecture:** 6-container Compose stack on `dockerserver-2` (Portainer endpoint 13) with
`nomad_admin` on `docker-servers-net` macvlan (`192.168.59.60`) and all services on the
`project-nomad_default` bridge network, fronted by the 3-host `nginx-rproxy` fleet. `litellm`
routes RAG embeddings (`nomic-embed-text:v1.5`) to `nomad_embed_ollama` (`http://ollama:11434`)
and routes chat completions to external/subscription AI models using credentials from Vault.

**Tech Stack:** Docker Compose, Portainer, Terraform (`portainer` + `vault` providers), LiteLLM
Proxy, Ollama, MySQL 8.0, Redis 7, Nginx, Pi-hole dnsmasq.

**Spec:** [Project NOMAD deployment design](../specs/2026-11-13-project-nomad-deployment-design.md)

---

## Conventions

- All file paths are relative to the repo root.
- Follow `AGENTS.md` **RULE #1**: develop + run `terraform plan` on a branch/worktree off
  `origin/main`, open a PR, wait for CI + squash-merge, and run `terraform apply -target=...`
  **only** from a clean checkout of merged `main`.
- All `ssh` commands use `~/.ssh/config` (`dockermaster`, `dockerserver-1`, `dockerserver-2`).
- For `sudo` on `ds-2`, set `SUDO_ASKPASS=$HOME/.config/bin/answer` with `sudo -A`.
- Vault auth:

  ```bash
  export VAULT_ADDR=http://192.168.59.25:8200
  export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
  ```

---

## File Structure

| Action | Path | Purpose |
|--------|------|---------|
| Create | `dockermaster/docker/compose/nomad/litellm-config.yaml` | LiteLLM Proxy model routing config (local Ollama embeddings + external chat models) |
| Create | `dockermaster/docker/compose/nomad/docker-compose.yml.tftpl` | Compose stack template rendered by Terraform (all images version-pinned) |
| Create | `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf` | Nginx HTTPS vhost (auto-bundled into all 3 `rproxy` stacks via `fileset()`) |
| Modify | `pihole/dnsmasq.d/04-d-lcamaral-com.conf` | Add 3 multi-A records for `nomad.d.lcamaral.com` |
| Modify | `terraform/portainer/vault.tf` | Add `data "vault_kv_secret_v2" "nomad"` |
| Modify | `terraform/portainer/stacks.tf` | Add `resource "portainer_stack" "nomad"` on `var.ds2_endpoint_id` |
| Modify | `inventory/docker-containers.md` | Document the new stack and `.59.60` IP assignment |

---

## Task 1: Pre-flight Verifications & Host Directories (Completed)

- [x] **Step 1.1: Verify `ds-2` disk space (`61G` free on `/`, `2.3T` free on `/nfs/dockermaster`)**
- [x] **Step 1.2: Verify `192.168.59.60` unused via `arping` (`0 packets received`) and repo grep**
- [x] **Step 1.3: Create `/nfs/dockermaster/nomad/storage/logs/admin.log` and
  `/opt/project-nomad/{mysql,redis,ollama}` on `ds-2`**

---

## Task 2: Store Secrets in Vault (Completed)

- [x] **Step 2.1: Write `secret/homelab/nomad` (`app_key`, `db_password`, `mysql_root_password`, `openrouter_api_key`)**

---

## Task 3: Author IaC Files, Validate & Plan on Branch

- [x] **Step 3.1: Create `dockermaster/docker/compose/nomad/litellm-config.yaml` and
  `docker-compose.yml.tftpl` (pinned tags)**
- [x] **Step 3.2: Create `dockermaster/docker/compose/nginx-rproxy/vhost.d/nomad.d.lcamaral.com.conf`
  and update `pihole/dnsmasq.d/04-d-lcamaral-com.conf`**
- [x] **Step 3.3: Wire `terraform/portainer/vault.tf`, `terraform/portainer/stacks.tf`, and
  `inventory/docker-containers.md`**
- [ ] **Step 3.4: Run `pre-commit` + `terraform validate` + targeted `terraform plan`
  (`1 to add, 5 to change, 0 to destroy`)**

---

## Task 4: PR → CI → Squash-Merge (`AGENTS.md` Rule #1)

- [ ] **Step 4.1: Push `feat/project-nomad` and open PR to `main` listing targets, expected diff, and rollback**
- [ ] **Step 4.2: Wait for required CI checks (`PR Validation`, etc.) to pass, then squash-merge to `main`**

---

## Task 5: Targeted Apply from Clean `main`

- [ ] **Step 5.1: Pull merged `main` in the primary checkout and run targeted `terraform apply`**

```bash
export VAULT_ADDR=http://192.168.59.25:8200
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
export TF_VAR_vault_addr="$VAULT_ADDR"
export TF_VAR_vault_token="$VAULT_TOKEN"
export TF_VAR_portainer_password=$(vault kv get -field=admin_password secret/homelab/portainer)

terraform -chdir=terraform/portainer apply \
  -target=portainer_stack.nomad \
  -target=portainer_stack.reverse_proxy \
  -target=portainer_stack.reverse_proxy_2 \
  -target=portainer_stack.reverse_proxy_3 \
  -target=portainer_stack.pihole_2 \
  -target=portainer_stack.pihole_3
```

- [ ] **Step 5.2: Redeploy `reverse-proxy*` and `pihole-*` stacks so updated `configs:` mount, and sync `pihole-1` LXC**

```bash
scripts/portainer-redeploy.py reverse-proxy reverse-proxy-2 reverse-proxy-3 pihole-2 pihole-3
scripts/sync-host-overrides.py --apply
```

- [ ] **Step 5.3: Pull `nomic-embed-text:v1.5` inside `nomad_embed_ollama` on `ds-2`**

```bash
ssh dockerserver-2 'docker exec nomad_embed_ollama ollama pull nomic-embed-text:v1.5'
```

---

## Task 6: Verification & Post-Apply Evidence

- [ ] **Step 6.1: Verify all 6 containers in stack `nomad` are healthy on `ds-2`**

```bash
ssh dockerserver-2 'docker ps --filter "label=com.docker.stack=nomad" --format "table {{.Names}}\t{{.Status}}"'
```

- [ ] **Step 6.2: Verify LiteLLM `/v1/models`, `/v1/embeddings` (768-dim), and `/v1/chat/completions`**
- [ ] **Step 6.3: Verify `https://nomad.d.lcamaral.com/api/health` returns HTTP 200**
- [ ] **Step 6.4: Post verification evidence as a comment on the merged PR and clean up worktree**
