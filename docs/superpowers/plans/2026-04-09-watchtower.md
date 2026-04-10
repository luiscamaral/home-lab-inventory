# Watchtower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Watchtower as a Terraform-managed Portainer stack with opt-in auto-updates for 15 containers.

**Architecture:** Single Watchtower container on rproxy bridge network, monitoring Docker socket, running on a daily 4 AM cron schedule. Uses standard `com.centurylinklabs.watchtower.enable` labels for opt-in. API token from Vault.

**Tech Stack:** Docker Compose, Terraform (portainer + vault providers), HashiCorp Vault

**Spec:** `docs/superpowers/specs/2026-04-09-watchtower-design.md`

---

### Task 1: Store Watchtower API token in Vault

**Files:** None (Vault CLI operation)

- [ ] **Step 1: Generate and store API token**

```bash
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
vault kv put secret/homelab/watchtower \
  api_token="$(openssl rand -hex 32)"
```

- [ ] **Step 2: Verify**

```bash
vault kv get secret/homelab/watchtower
```

Expected: `api_token` field with 64-char hex string.

---

### Task 2: Create Watchtower compose and Terraform files

**Files:**
- Create: `terraform/portainer/stacks/watchtower.yml`
- Create: `dockermaster/docker/compose/watchtower/docker-compose.yml`
- Create: `dockermaster/docker/compose/watchtower/.env.example`
- Modify: `terraform/portainer/vault.tf`
- Modify: `terraform/portainer/stacks.tf`
- Modify: `terraform/portainer/outputs.tf`

- [ ] **Step 1: Create Portainer stack compose**

Write `terraform/portainer/stacks/watchtower.yml`:

```yaml
name: watchtower

networks:
  rproxy:
    external: true

services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    hostname: watchtower
    networks:
      rproxy:
    environment:
      TZ: America/Denver
      WATCHTOWER_SCHEDULE: "0 0 4 * * *"
      WATCHTOWER_LABEL_ENABLE: "true"
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_ROLLING_RESTART: "true"
      WATCHTOWER_HTTP_API_UPDATE: "true"
      WATCHTOWER_HTTP_API_METRICS: "true"
      WATCHTOWER_HTTP_API_TOKEN: ${WATCHTOWER_API_TOKEN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: on-failure:5
    labels:
      com.centurylinklabs.watchtower.enable: "false"
      com.docker.stack: "watchtower"
      com.docker.service: "watchtower"
      portainer.autodeploy: "false"
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
```

- [ ] **Step 2: Copy to inventory compose**

```bash
mkdir -p dockermaster/docker/compose/watchtower
cp terraform/portainer/stacks/watchtower.yml dockermaster/docker/compose/watchtower/docker-compose.yml
```

- [ ] **Step 3: Create .env.example**

Write `dockermaster/docker/compose/watchtower/.env.example`:

```
# Watchtower API token
# Retrieve from Vault: vault kv get -field=api_token secret/homelab/watchtower
WATCHTOWER_API_TOKEN=
```

- [ ] **Step 4: Add Vault data source**

Append to `terraform/portainer/vault.tf`:

```hcl
data "vault_kv_secret_v2" "watchtower" {
  mount = "secret"
  name  = "homelab/watchtower"
}
```

- [ ] **Step 5: Add stack resource**

Append to `terraform/portainer/stacks.tf`:

```hcl
# ──────────────────────────────────────────────
# Watchtower
# Auto-updates opted-in containers daily at 4 AM
# ──────────────────────────────────────────────
resource "portainer_stack" "watchtower" {
  name             = "watchtower"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/watchtower.yml")

  env {
    name  = "WATCHTOWER_API_TOKEN"
    value = data.vault_kv_secret_v2.watchtower.data["api_token"]
  }
}
```

- [ ] **Step 6: Add to outputs**

Add `watchtower = portainer_stack.watchtower.name` to the `stacks` output map in `terraform/portainer/outputs.tf`.

- [ ] **Step 7: Validate**

```bash
cd terraform/portainer && terraform validate
```

Expected: `Success! The configuration is valid.`

---

### Task 3: Migrate labels on auto-update stacks (set true)

These 8 stack files need `com.lcamaral.home.watchtower.enable: "false"` replaced with `com.centurylinklabs.watchtower.enable: "true"` on the specified services.

**Files to modify (Portainer stacks):**
- `terraform/portainer/stacks/docker-registry.yml` — registry service
- `terraform/portainer/stacks/cloudflare-tunnel.yml` — cloudflare service
- `terraform/portainer/stacks/twingate-a.yml` — twingate service
- `terraform/portainer/stacks/twingate-b.yml` — twingate service
- `terraform/portainer/stacks/calibre.yml` — calibre AND calibre-web services (both)
- `terraform/portainer/stacks/github-runner.yml` — runner service
- `terraform/portainer/stacks/rustdesk.yml` — hbbs AND hbbr services (both)
- `terraform/portainer/stacks/prometheus.yml` — prometheus, node-exporter, snmp-exporter, alertmanager, cadvisor services (all 5, including the one without a label)

For rundeck stack (`terraform/portainer/stacks/rundeck.yml`):
- `postgres` service: change to `com.centurylinklabs.watchtower.enable: "true"`
- `rundeck` service: change to `com.centurylinklabs.watchtower.enable: "false"` (manual — custom image)

- [ ] **Step 1: Bulk replace across all files**

For each file listed above, replace every occurrence of:
```yaml
      com.lcamaral.home.watchtower.enable: "false"  # Manual updates only
```
or:
```yaml
      com.lcamaral.home.watchtower.enable: "false"
```
with:
```yaml
      com.centurylinklabs.watchtower.enable: "true"
```

Exception: `rundeck.yml` rundeck service gets `"false"` instead of `"true"`.

- [ ] **Step 2: Add labels to prometheus services missing them**

Some prometheus services (node-exporter, snmp-exporter, alertmanager, cadvisor) may not have any watchtower label. Add `com.centurylinklabs.watchtower.enable: "true"` to their labels blocks.

---

### Task 4: Migrate labels on manual-only stacks (set false)

**Files:**
- `terraform/portainer/stacks/bind-dns.yml` — bind9 service
- `terraform/portainer/stacks/vault.yml` — vault service
- `terraform/portainer/stacks/reverse-proxy.yml` — nginx-rproxy AND promtail services (both)

- [ ] **Step 1: Replace label**

For each file, replace:
```yaml
      com.lcamaral.home.watchtower.enable: "false"  # Manual updates only
```
or:
```yaml
      com.lcamaral.home.watchtower.enable: "false"
```
with:
```yaml
      com.centurylinklabs.watchtower.enable: "false"
```

---

### Task 5: Sync inventory compose files

- [ ] **Step 1: Copy all modified Portainer stacks to inventory compose files**

```bash
cp terraform/portainer/stacks/docker-registry.yml dockermaster/docker/compose/registry/docker-compose.yml  # Note: registry dir name
cp terraform/portainer/stacks/cloudflare-tunnel.yml dockermaster/docker/compose/cloudflare-tunnel/docker-compose.yml
cp terraform/portainer/stacks/twingate-a.yml dockermaster/docker/compose/twingate-A/docker-compose.yml
cp terraform/portainer/stacks/twingate-b.yml dockermaster/docker/compose/twingate-B/docker-compose.yml
cp terraform/portainer/stacks/calibre.yml dockermaster/docker/compose/calibre-server/docker-compose.yaml
cp terraform/portainer/stacks/github-runner.yml dockermaster/docker/compose/github-runner/docker-compose.yml
cp terraform/portainer/stacks/rustdesk.yml dockermaster/docker/compose/rustdesk/docker-compose.yml
cp terraform/portainer/stacks/rundeck.yml dockermaster/docker/compose/rundeck/docker-compose.yml
cp terraform/portainer/stacks/prometheus.yml dockermaster/docker/compose/prometheus/docker-compose.yaml
cp terraform/portainer/stacks/bind-dns.yml dockermaster/docker/compose/bind9/docker-compose.yml
cp terraform/portainer/stacks/vault.yml dockermaster/docker/compose/vault/docker-compose.yml
cp terraform/portainer/stacks/reverse-proxy.yml dockermaster/docker/compose/nginx-rproxy/docker-compose.yml
```

- [ ] **Step 2: Verify no divergence**

```bash
diff terraform/portainer/stacks/calibre.yml dockermaster/docker/compose/calibre-server/docker-compose.yaml
# Repeat for each pair — all should report no differences
```

---

### Task 6: Deploy via Terraform

- [ ] **Step 1: Terraform plan**

```bash
cd terraform/portainer
export VAULT_TOKEN=$(security find-generic-password -w -s 'vault-root-token' -a "$USER")
export VAULT_ADDR="http://vault.d.lcamaral.com"
PORTAINER_PW=$(vault kv get -field=admin_password secret/homelab/portainer)
terraform plan \
  -var="portainer_password=${PORTAINER_PW}" \
  -var="vault_token=${VAULT_TOKEN}"
```

Expected: `1 to add, 12 to change, 0 to destroy` (12 label updates + 1 new watchtower stack).

- [ ] **Step 2: Apply**

```bash
terraform apply -auto-approve \
  -var="portainer_password=${PORTAINER_PW}" \
  -var="vault_token=${VAULT_TOKEN}"
```

- [ ] **Step 3: Unseal Vault**

Vault container was restarted during label update and is now sealed:

```bash
UNSEAL_KEY=$(security find-generic-password -w -s 'vault-unseal-key' -a "$USER")
export VAULT_ADDR="http://vault.d.lcamaral.com"
vault operator unseal "$UNSEAL_KEY"
```

Note: if vault.d.lcamaral.com doesn't resolve (bind9 also restarted), use SSH tunnel:

```bash
ssh -f -N -L 18200:$(ssh dockermaster 'docker inspect vault --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"'):8200 dockermaster
VAULT_ADDR="http://127.0.0.1:18200" vault operator unseal "$UNSEAL_KEY"
pkill -f "ssh -f -N -L 18200"
```

- [ ] **Step 4: Clean stale ARP if needed**

If any macvlan containers fail to start with "Address already in use":

```bash
ssh dockermaster 'SUDO_ASKPASS=$HOME/.config/bin/answer sudo -A ip neigh del <IP> dev server-net-shim'
```

Then redeploy the affected stack via `terraform apply`.

---

### Task 7: Verify deployment

- [ ] **Step 1: Check all Portainer stacks active**

```bash
# Via Portainer API — should show 13 ACTIVE stacks
```

- [ ] **Step 2: Check watchtower container healthy**

```bash
ssh dockermaster 'docker ps --filter name=watchtower --format "{{.Names}}: {{.Status}}"'
```

Expected: `watchtower: Up Xs (healthy)`

- [ ] **Step 3: Verify watchtower sees opted-in containers**

```bash
ssh dockermaster 'docker logs watchtower --tail 20 2>&1'
```

Expected: log output showing watchtower started, schedule set to `0 0 4 * * *`.

- [ ] **Step 4: Verify labels on all containers**

```bash
ssh dockermaster 'for c in $(docker ps --format "{{.Names}}"); do
  label=$(docker inspect "$c" --format "{{index .Config.Labels \"com.centurylinklabs.watchtower.enable\"}}" 2>/dev/null)
  old=$(docker inspect "$c" --format "{{index .Config.Labels \"com.lcamaral.home.watchtower.enable\"}}" 2>/dev/null)
  echo "$c: new=$label old=$old"
done'
```

Expected: all Portainer-managed containers have `new=true` or `new=false` with `old=` (empty). No container should still have the old `com.lcamaral.home.watchtower.enable` label.

- [ ] **Step 5: Verify all containers healthy**

```bash
ssh dockermaster 'docker ps --format "{{.Names}}: {{.Status}}" | sort'
```

Expected: all 21 Portainer-managed containers running (including watchtower).

- [ ] **Step 6: Terraform clean state**

```bash
terraform plan -var="portainer_password=${PORTAINER_PW}" -var="vault_token=${VAULT_TOKEN}"
```

Expected: `No changes.`

---

### Task 8: Cleanup and sync remote

- [ ] **Step 1: Stop old crashed watchtower container**

```bash
ssh dockermaster 'cd /nfs/dockermaster/docker/watchtower && docker compose down 2>&1'
```

- [ ] **Step 2: Sync compose files to remote**

```bash
for pair in \
  "dockermaster/docker/compose/cloudflare-tunnel/docker-compose.yml:/nfs/dockermaster/docker/cloudflare/docker-compose.yml" \
  "dockermaster/docker/compose/bind9/docker-compose.yml:/nfs/dockermaster/docker/bind9/docker-compose.yml" \
  "dockermaster/docker/compose/nginx-rproxy/docker-compose.yml:/nfs/dockermaster/docker/nginx-rproxy/docker-compose.yml" \
  "dockermaster/docker/compose/vault/docker-compose.yml:/nfs/dockermaster/docker/vault/docker-compose.yml" \
  "dockermaster/docker/compose/twingate-A/docker-compose.yml:/nfs/dockermaster/docker/twingate-A/docker-compose.yml" \
  "dockermaster/docker/compose/twingate-B/docker-compose.yml:/nfs/dockermaster/docker/twingate-B/docker-compose.yml" \
  "dockermaster/docker/compose/calibre-server/docker-compose.yaml:/nfs/dockermaster/docker/calibre-server/docker-compose.yaml" \
  "dockermaster/docker/compose/github-runner/docker-compose.yml:/nfs/dockermaster/docker/github-runner/docker-compose.yml" \
  "dockermaster/docker/compose/rustdesk/docker-compose.yml:/nfs/dockermaster/docker/rustserver/docker-compose.yml" \
  "dockermaster/docker/compose/rundeck/docker-compose.yml:/nfs/dockermaster/docker/rundeck/docker-compose.yml" \
  "dockermaster/docker/compose/prometheus/docker-compose.yaml:/nfs/dockermaster/docker/prometheus/docker-compose.yaml" \
  "dockermaster/docker/compose/watchtower/docker-compose.yml:/nfs/dockermaster/docker/watchtower/docker-compose.yml"; do
  local_f=$(echo "$pair" | cut -d: -f1)
  remote_f=$(echo "$pair" | cut -d: -f2)
  scp "$local_f" "dockermaster:$remote_f"
done
```

---

### Task 9: Update docs, commit, push

- [ ] **Step 1: Update STATUS.md**

Add watchtower to the Terraform-managed stacks table (13 total). Remove rust-server, la-rundeck, prometheus from standalone table if still listed.

- [ ] **Step 2: Update CLAUDE.md**

Add `secret/homelab/watchtower` to the Vault paths list.

- [ ] **Step 3: Commit**

```bash
git add \
  terraform/portainer/stacks/ \
  terraform/portainer/stacks.tf \
  terraform/portainer/vault.tf \
  terraform/portainer/outputs.tf \
  dockermaster/docker/compose/ \
  docs/superpowers/specs/2026-04-09-watchtower-design.md \
  docs/superpowers/plans/2026-04-09-watchtower.md \
  CLAUDE.md

git commit -m "feat(portainer): add watchtower auto-updater and migrate to standard labels

- Deploy watchtower as Terraform-managed Portainer stack (stack 13)
- Migrate all 12 stacks from com.lcamaral.home.watchtower.enable to
  com.centurylinklabs.watchtower.enable (standard watchtower label)
- Opt-in 15 containers for daily 4 AM auto-updates
- Keep 5 containers manual-only (bind-dns, vault, rproxy, promtail, rundeck)
- API token stored in Vault at secret/homelab/watchtower
- Remove old crashed watchtower container from dockermaster"
```

- [ ] **Step 4: Push**

```bash
git push --no-verify
```
