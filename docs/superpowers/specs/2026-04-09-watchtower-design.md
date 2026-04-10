# Watchtower Auto-Update Design

Date: 2026-04-09
Status: Approved

## Overview

Deploy Watchtower as a Terraform-managed Portainer stack to automatically pull and restart containers with updated images on a daily schedule. Opt-in model using standard Watchtower labels.

## Architecture

- Image: `containrrr/watchtower:latest`
- Schedule: daily at 4 AM Denver time (cron: `0 0 4 * * *`, 6-field with seconds)
- Mode: opt-in via `com.centurylinklabs.watchtower.enable=true` (standard label)
- Cleanup: removes old images after successful update (`WATCHTOWER_CLEANUP=true`)
- Notifications: log-only (Promtail already collects container logs)
- Network: `rproxy` bridge (access to Docker socket is sufficient for all containers)
- Managed by: Terraform via `portainer_stack.watchtower`

## Container Update Policy

### Auto-update (15 containers)

| Stack | Containers | Rationale |
|---|---|---|
| docker-registry | registry | Official image, stateless |
| cloudflare-tunnel | cloudflare | Official image, stateless |
| twingate-a | twingate-sepia-hornet | Official image, stateless |
| twingate-b | twingate-golden-mussel | Official image, stateless |
| calibre | calibre, calibre-web | Official linuxserver images |
| github-runner | github-runner-homelab | Needs latest runner version |
| la-rundeck | postgres-rundeck | Official postgres image |
| rust-server | hbbs, hbbr | Official rustdesk images |
| prometheus | prometheus, node-exporter, alertmanager, cadvisor | Official Prometheus ecosystem |
| prometheus | snmp-exporter | Pinned to v0.20.0 -- will not update until tag is changed to :latest |

### Manual-only (5 containers)

| Stack | Containers | Rationale |
|---|---|---|
| bind-dns | bind-dns-bind9-1 | DNS -- bad update = all services unreachable |
| vault | vault | Requires manual unseal after restart |
| reverse-proxy | rproxy, promtail | Reverse proxy -- bad update = all services down |
| la-rundeck | rundeck | Custom-built local image, nothing to pull |

## Secrets

New Vault path: `secret/homelab/watchtower`

| Key | Purpose | Source |
|---|---|---|
| api_token | HTTP API authentication for on-demand update triggers | Generate new token |

## Compose Definition

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
    # Healthcheck: image has built-in CMD [/watchtower --health-check], no override needed
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

Note: Private registry auth (Docker Hub + GHCR credentials) is deferred. All auto-updated images are public. When needed, add `DOCKER_CONFIG: /config` env var and mount a config.json with registry credentials.

## Label Migration

All 12 existing Portainer stacks must replace the custom label:
- Remove: `com.lcamaral.home.watchtower.enable: "false"`
- Add: `com.centurylinklabs.watchtower.enable: "true"` or `"false"` per the update policy above

This is a bulk edit across all `terraform/portainer/stacks/*.yml` and corresponding `dockermaster/docker/compose/*/docker-compose.{yml,yaml}` files.

## GitHub Actions Integration

The existing `.github/workflows/deploy.yml` has a `notify-watchtower` job, but it runs on `ubuntu-latest` (GitHub cloud) and cannot reach Watchtower's internal network. Making this work requires either a Cloudflare tunnel ingress rule for watchtower or changing the workflow to run on the self-hosted runner. This is deferred to a follow-up task.

## Terraform Resources

```hcl
# vault.tf
data "vault_kv_secret_v2" "watchtower" {
  mount = "secret"
  name  = "homelab/watchtower"
}

# stacks.tf
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

## Files to Create

| File | Purpose |
|---|---|
| `terraform/portainer/stacks/watchtower.yml` | Portainer stack compose |
| `dockermaster/docker/compose/watchtower/docker-compose.yml` | Inventory compose |
| `dockermaster/docker/compose/watchtower/.env.example` | Env template |

## Files to Modify

| File | Change |
|---|---|
| `terraform/portainer/stacks.tf` | Add `portainer_stack.watchtower` |
| `terraform/portainer/vault.tf` | Add `vault_kv_secret_v2.watchtower` |
| `terraform/portainer/outputs.tf` | Add `watchtower` to output |
| 12 stack YMLs in `terraform/portainer/stacks/` | Replace label namespace + set true/false |
| 11 inventory compose files in `dockermaster/docker/compose/` | Same label changes |
| `dockermaster/docker/compose/STATUS.md` | Add watchtower to managed stacks (13 total) |

## Deployment Order

1. Store secrets in Vault (`secret/homelab/watchtower`)
2. Update labels on all 12 existing stacks + deploy watchtower stack (single terraform apply)
3. Unseal Vault (container restarts during label update will seal it)
4. Verify: all containers healthy, watchtower running, labels correct
5. Sync remote compose files
6. Stop old watchtower container on dockermaster (the crashed standalone one)
7. Commit and push

## Out of Scope

- Email/Slack notifications (can be added later via env vars)
- Private registry auth via config.json mount and DOCKER_CONFIG env var (can be added later; public images update without it)
- GitHub Actions `notify-watchtower` integration (needs tunnel ingress or workflow change)
- Watchtower monitoring dashboard in Grafana
- Automatic Vault unseal after watchtower-triggered restarts
