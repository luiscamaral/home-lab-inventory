# ──────────────────────────────────────────────
# Docker Registry (already deployed via Portainer)
# ──────────────────────────────────────────────
resource "portainer_stack" "docker_registry" {
  name            = "docker-registry"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/docker-registry.yml")
}

# ──────────────────────────────────────────────
# Cloudflare Tunnel (replica 1 on dockermaster)
# Connects homelab to Cloudflare edge via tunnel "bologna"
# Token injected from Vault at apply time
# ──────────────────────────────────────────────
resource "portainer_stack" "cloudflare_tunnel" {
  name            = "cloudflare-tunnel"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cloudflare-tunnel.yml")

  env {
    name  = "TUNNEL_TOKEN"
    value = data.vault_kv_secret_v2.cloudflare.data["tunnel_token"]
  }
}

# ──────────────────────────────────────────────
# Cloudflare Tunnel (replica 2 on dockerserver-1)
# Second replica of the same tunnel for HA. Cloudflare balances across replicas.
# ──────────────────────────────────────────────
resource "portainer_stack" "cloudflare_tunnel_2" {
  name            = "cloudflare-tunnel-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cloudflare-tunnel-2.yml")

  env {
    name  = "TUNNEL_TOKEN"
    value = data.vault_kv_secret_v2.cloudflare.data["tunnel_token"]
  }
}

# ──────────────────────────────────────────────
# Cloudflare Tunnel (replica 3 on dockerserver-2)
# Third replica, completes 3-host edge HA
# ──────────────────────────────────────────────
resource "portainer_stack" "cloudflare_tunnel_3" {
  name            = "cloudflare-tunnel-3"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cloudflare-tunnel-3.yml")

  env {
    name  = "TUNNEL_TOKEN"
    value = data.vault_kv_secret_v2.cloudflare.data["tunnel_token"]
  }
}

# bind-dns retired 2026-04-15 (task #37). Authoritative records for
# d.lcamaral.com and the bare `home` zone moved to the pihole HA trio
# via Pattern B; pfSense Unbound's forward-zones now load-balance across
# pihole-1/2/3. See pihole/dnsmasq.d/04-d-lcamaral-com.conf and
# 05-home.conf for the new source of truth.

# ──────────────────────────────────────────────
# Nginx Reverse Proxy + Promtail (rproxy-1 on dockermaster)
# All services route through this — certs managed by pfSense
# ──────────────────────────────────────────────
resource "portainer_stack" "reverse_proxy" {
  name            = "reverse-proxy"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/reverse-proxy.yml")
}

# ──────────────────────────────────────────────
# Nginx Reverse Proxy (rproxy-2 on dockerserver-1)
# Second instance for HA — shares the same vhost.d config via NFS
# ──────────────────────────────────────────────
resource "portainer_stack" "reverse_proxy_2" {
  name            = "reverse-proxy-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/reverse-proxy-2.yml")
}

# ──────────────────────────────────────────────
# Nginx Reverse Proxy (rproxy-3 on dockerserver-2)
# Third instance for HA — completes the 3-host edge
# ──────────────────────────────────────────────
resource "portainer_stack" "reverse_proxy_3" {
  name            = "reverse-proxy-3"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/reverse-proxy-3.yml")
}

# ──────────────────────────────────────────────
# Vault Node 3 → dockerserver-2
# Third Raft peer — gives cluster quorum protection
# No secrets needed; joins existing cluster on first boot
# ──────────────────────────────────────────────
resource "portainer_stack" "vault_3" {
  name            = "vault-3"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/vault-3.yml")
}

# ──────────────────────────────────────────────
# Vault Raft cluster — second peer (vault-2 on ds-1)
# Brought under Portainer + Terraform after running as raw
# `docker run` outside IaC. See stacks/vault-2.yml.
# ──────────────────────────────────────────────
resource "portainer_stack" "vault_2" {
  name            = "vault-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/vault-2.yml")
}

# ──────────────────────────────────────────────
# HashiCorp Vault
# Secret management — env vars for internal CLI only
# ──────────────────────────────────────────────
resource "portainer_stack" "vault" {
  name            = "vault"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/vault.yml")

  env {
    name  = "VAULT_ADDR"
    value = "http://vault.d.lcamaral.com/"
  }

  env {
    name  = "VAULT_TOKEN"
    value = data.vault_kv_secret_v2.vault.data["vault_token"]
  }
}

# ──────────────────────────────────────────────
# Twingate Connector A (sepia-hornet) → dockerserver-1
# VPN connector — tokens from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "twingate_a" {
  name            = "twingate-a"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/twingate-a.yml")

  env {
    name  = "TWINGATE_ACCESS_TOKEN"
    value = data.vault_kv_secret_v2.twingate_sepia_hornet.data["access_token"]
  }

  env {
    name  = "TWINGATE_REFRESH_TOKEN"
    value = data.vault_kv_secret_v2.twingate_sepia_hornet.data["refresh_token"]
  }
}

# ──────────────────────────────────────────────
# Twingate Connector B (golden-mussel) → dockerserver-2
# VPN connector — tokens from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "twingate_b" {
  name            = "twingate-b"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/twingate-b.yml")

  env {
    name  = "TWINGATE_ACCESS_TOKEN"
    value = data.vault_kv_secret_v2.twingate_golden_mussel.data["access_token"]
  }

  env {
    name  = "TWINGATE_REFRESH_TOKEN"
    value = data.vault_kv_secret_v2.twingate_golden_mussel.data["refresh_token"]
  }
}

# ──────────────────────────────────────────────
# Calibre (calibre + calibre-web) → dockerserver-1
# Ebook server — password from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "calibre" {
  name            = "calibre"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/calibre.yml")

  env {
    name  = "CALIBRE_PASSWORD"
    value = data.vault_kv_secret_v2.calibre.data["password"]
  }
}

# ──────────────────────────────────────────────
# GitHub Runner → dockerserver-1
# CI/CD self-hosted runner — PAT from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "github_runner" {
  name            = "github-runner"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/github-runner.yml")

  env {
    name  = "GITHUB_TOKEN"
    value = data.vault_kv_secret_v2.github_runner.data["github_token"]
  }
}

# ──────────────────────────────────────────────
# RustDesk (hbbs + hbbr) → dockerserver-2
# Remote desktop server — no secrets
# ──────────────────────────────────────────────
resource "portainer_stack" "rustdesk" {
  name            = "rust-server"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/rustdesk.yml")
}

# ──────────────────────────────────────────────
# Rundeck + PostgreSQL → dockerserver-1
# Automation server — DB and storage passwords from Vault
# Image pushed to registry as registry.cf.lcamaral.com/la-rundeck:latest
# ──────────────────────────────────────────────
resource "portainer_stack" "rundeck" {
  name            = "la-rundeck"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/rundeck.yml")

  env {
    name  = "RUNDECK_DB_PASSWORD"
    value = data.vault_kv_secret_v2.rundeck.data["db_password"]
  }

  env {
    name  = "RUNDECK_STORAGE_PASSWORD"
    value = data.vault_kv_secret_v2.rundeck.data["storage_converter_password"]
  }
}

# ──────────────────────────────────────────────
# Phase 1 Prometheus + Thanos monitoring core (replica A on ds-1)
#
# This block replaces the legacy bundled prometheus stack. The legacy stack
# bundled prometheus + node-exporter + snmp-exporter + alertmanager + cadvisor
# in one compose; here those concerns are split into 6 independent stacks so
# each can be lifecycled separately (and so node/cadvisor/snmp survive when
# the legacy stack is decommissioned in Phase 0):
#
#   portainer_stack.prometheus           — prometheus-1 + thanos-sidecar-1
#   portainer_stack.thanos_query         — thanos-query (on dockermaster)
#   portainer_stack.thanos_store         — thanos-store-gw (on ds-1)
#   portainer_stack.alertmanager_1       — alertmanager-1 (on ds-1)
#   portainer_stack.node_exporter_ds1    — node-exporter (host-mode on ds-1)
#   portainer_stack.cadvisor_ds1         — cadvisor (host-mode on ds-1)
#   portainer_stack.snmp_exporter        — snmp-exporter (on ds-1)
#
# Static IP allocations from 192.168.59.0/26 (docker-servers-net macvlan):
#   .19  prometheus-1
#   .20  thanos-sidecar-1
#   .21  thanos-store-gw
#   .26  thanos-query (on dockermaster)
#   .27  alertmanager-1
#   .29  snmp-exporter
# ──────────────────────────────────────────────

# prometheus-1 + thanos-sidecar-1 (replica A) on ds-1.
# Both scrape configs (`_a` and `_b`) live in locals.tf — that's the single
# source-of-truth for what gets scraped. Two near-identical bodies, the
# only intentional difference is `external_labels.replica`. Edit both.
# Reads scrape config from the local stub above; reads objstore creds from
# Vault and renders the LAN-side objstore.yml via templatefile().
resource "portainer_stack" "prometheus" {
  name            = "prometheus"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/prometheus.yml.tftpl", {
    prometheus_config = local.prometheus_scrape_config_a
    objstore_config = templatefile("${path.module}/stacks/objstore-ds1.yml.tftpl", {
      access_key = data.vault_kv_secret_v2.thanos.data["access_key"]
      secret_key = data.vault_kv_secret_v2.thanos.data["secret_key"]
    })
    # Phase 3d — Home Assistant scrape token (DECISIONS.md Q8).
    ha_token = data.vault_kv_secret_v2.ha_metrics_token.data["token"]
    # Phase 3a — Watchtower HTTP API bearer token (scraped on :8080/v1/metrics).
    watchtower_token = data.vault_kv_secret_v2.watchtower.data["api_token"]
    # Phase 3a — MinIO Prometheus bearer JWT (scraped on /minio/v2/metrics/cluster).
    minio_jwt = data.vault_kv_secret_v2.minio_metrics_jwt.data["token"]
    # Phase 3f — Rundeck API bearer token (scraped on :4440/metrics).
    rundeck_token = data.vault_kv_secret_v2.rundeck.data["api_token"]
    # Phase 3h — blackbox file_sd target lists (rendered as JSON in locals.tf).
    # Phase 3f extends with the tcp list (FreeSWITCH SIP, RustDesk hbbs/hbbr).
    blackbox_http_targets = local.blackbox_http_targets
    blackbox_icmp_targets = local.blackbox_icmp_targets
    blackbox_ssl_targets  = local.blackbox_ssl_targets
    blackbox_dns_targets  = local.blackbox_dns_targets
    blackbox_tcp_targets  = local.blackbox_tcp_targets
  })
}

# thanos-query — read fan-out, runs on dockermaster (control plane).
# Phase 1 wires sidecar-1 + store-gw; Phase 2 will append sidecar-2.
resource "portainer_stack" "thanos_query" {
  name            = "thanos-query"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/thanos-query.yml")
}

# thanos-store-gw — historical block reader, runs on ds-1.
# Same objstore.yml as the sidecar (LAN endpoint).
resource "portainer_stack" "thanos_store" {
  name            = "thanos-store"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/thanos-store.yml.tftpl", {
    objstore_config = templatefile("${path.module}/stacks/objstore-ds1.yml.tftpl", {
      access_key = data.vault_kv_secret_v2.thanos.data["access_key"]
      secret_key = data.vault_kv_secret_v2.thanos.data["secret_key"]
    })
  })
}

# alertmanager-1 (replica A) on ds-1.
# Phase 1 stub config; Phase 5 wires the real SMTP routing tree.
resource "portainer_stack" "alertmanager_1" {
  name            = "alertmanager"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  # alertmanager_config is defined later in this file (alongside the
  # prometheus_2 stub) and reused here so both replicas serve identical
  # configs. The local is referenced before its declaration in source order
  # but Terraform resolves locals graph-wide.
  stack_file_content = templatefile("${path.module}/stacks/alertmanager.yml.tftpl", {
    alertmanager_config = local.alertmanager_config
  })
}

# node-exporter on ds-1 (host network mode, no IP allocation needed).
# Phase 3 will add identical stacks for ds-2 and dockermaster.
resource "portainer_stack" "node_exporter_ds1" {
  name            = "node-exporter-ds1"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/node-exporter-ds1.yml")
}

# cadvisor on ds-1 (host network mode, privileged). Phase 3 expands.
resource "portainer_stack" "cadvisor_ds1" {
  name            = "cadvisor-ds1"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cadvisor-ds1.yml")
}

# ──────────────────────────────────────────────
# Phase 3b — node-exporter + cadvisor expansion (task #26)
#
# Deploy the same exporter pair on the three remaining hosts so every
# Docker host (and the NAS) reports node + container metrics. Both
# replicas of prometheus discover these via the static `node_exporters`
# and `cadvisors` jobs — no per-host scrape config needed beyond a
# target list.
#
# All exporters use network_mode: host, so no IP allocation from the
# macvlan pool is required. NAS variants diverge from the Linux template
# for DSM-specific paths (no /dev/disk, no systemd, docker root at
# /volume2/@docker) — see the per-file headers for details.
# ──────────────────────────────────────────────

# node-exporter on dockermaster (host network mode).
resource "portainer_stack" "node_exporter_dm" {
  name            = "node-exporter-dm"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/node-exporter-dm.yml")
}

# node-exporter on ds-2 (host network mode).
resource "portainer_stack" "node_exporter_ds2" {
  name            = "node-exporter-ds2"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/node-exporter-ds2.yml")
}

# node-exporter on the Synology NAS (DSM, host network mode).
resource "portainer_stack" "node_exporter_nas" {
  name            = "node-exporter-nas"
  endpoint_id     = portainer_environment.nas.id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/node-exporter-nas.yml")
}

# cadvisor on dockermaster (host network mode, privileged).
resource "portainer_stack" "cadvisor_dm" {
  name            = "cadvisor-dm"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cadvisor-dm.yml")
}

# cadvisor on ds-2 (host network mode, privileged).
resource "portainer_stack" "cadvisor_ds2" {
  name            = "cadvisor-ds2"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cadvisor-ds2.yml")
}

# cadvisor on the Synology NAS (DSM, host network mode, privileged).
# Docker root mounted from /volume2/@docker (DSM-specific path).
resource "portainer_stack" "cadvisor_nas" {
  name            = "cadvisor-nas"
  endpoint_id     = portainer_environment.nas.id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/cadvisor-nas.yml")
}

# snmp-exporter on ds-1. Bind-mounts the legacy ~17k-line snmp.yml from
# /nfs/dockermaster/docker/snmp-exporter/snmp.yml — the orchestrator must
# pre-stage this file before the legacy prometheus stack is destroyed in
# Phase 0 (or accept a brief snmp scrape gap).
resource "portainer_stack" "snmp_exporter" {
  name            = "snmp-exporter"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/snmp-exporter.yml")
}

# pve-exporter on dockermaster (Phase 3c — Proxmox VE metrics).
# Token credentials read from Vault; pve.yml rendered inline (single-host
# config, no point in a separate template file). The Prometheus scrape job
# `pve` lives in locals.tf and points at this exporter; relabel rewrites
# __address__ from the PVE node target back to pve-exporter:9221.
locals {
  pve_exporter_config = <<-EOT
    default:
      user: prometheus@pam
      token_name: metrics
      token_value: ${data.vault_kv_secret_v2.proxmox_api_token.data["token_secret"]}
      verify_ssl: false
  EOT
}

resource "portainer_stack" "pve_exporter" {
  name            = "pve-exporter"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/pve-exporter.yml.tftpl", {
    pve_config = local.pve_exporter_config
  })
}

# ──────────────────────────────────────────────
# Watchtower → dockerserver-1
# Auto-updates opted-in containers daily at 4 AM
# ──────────────────────────────────────────────
resource "portainer_stack" "watchtower" {
  name            = "watchtower"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/watchtower.yml")

  env {
    name  = "WATCHTOWER_API_TOKEN"
    value = data.vault_kv_secret_v2.watchtower.data["api_token"]
  }

  # Phase 3a: macvlan IP for Prometheus scrape of /v1/metrics on :8080
  env {
    name  = "WATCHTOWER_MACVLAN_IP"
    value = "192.168.59.36"
  }
}

# ──────────────────────────────────────────────
# Watchtower — dockermaster (control plane)
# Separate instance; removed in Phase 4 when dockermaster is slimmed
# ──────────────────────────────────────────────
resource "portainer_stack" "watchtower_dm" {
  name            = "watchtower"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/watchtower.yml")

  env {
    name  = "WATCHTOWER_API_TOKEN"
    value = data.vault_kv_secret_v2.watchtower.data["api_token"]
  }

  # Phase 3a: macvlan IP for Prometheus scrape of /v1/metrics on :8080
  env {
    name  = "WATCHTOWER_MACVLAN_IP"
    value = "192.168.59.33"
  }
}

# ──────────────────────────────────────────────
# MinIO S3 Storage → dockerserver-1
# Object storage — root credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "minio" {
  name            = "minio"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/minio.yml")

  env {
    name  = "MINIO_ROOT_USER"
    value = data.vault_kv_secret_v2.minio.data["root_user"]
  }

  env {
    name  = "MINIO_ROOT_PASSWORD"
    value = data.vault_kv_secret_v2.minio.data["root_password"]
  }

  env {
    name  = "MINIO_OIDC_CLIENT_SECRET"
    value = data.vault_kv_secret_v2.keycloak_clients.data["minio_client_secret"]
  }
}

# ──────────────────────────────────────────────
# MinIO S3 Replica → dockerserver-2
# Site replication peer for minio on ds-1
# Data on local disk (/var/lib/minio-data) for storage-level HA
# ──────────────────────────────────────────────
resource "portainer_stack" "minio_2" {
  name            = "minio-2"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/minio-2.yml")

  env {
    name  = "MINIO_ROOT_USER"
    value = data.vault_kv_secret_v2.minio.data["root_user"]
  }

  env {
    name  = "MINIO_ROOT_PASSWORD"
    value = data.vault_kv_secret_v2.minio.data["root_password"]
  }

  env {
    name  = "MINIO_OIDC_CLIENT_SECRET"
    value = data.vault_kv_secret_v2.keycloak_clients.data["minio_client_secret"]
  }
}

# ──────────────────────────────────────────────
# FreeSWITCH VoIP/SIP Server → dockerserver-2
# SIP credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "freeswitch" {
  name            = "freeswitch"
  endpoint_id     = var.ds2_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/freeswitch.yml")

  env {
    name  = "ESL_PASSWORD"
    value = data.vault_kv_secret_v2.freeswitch.data["esl_password"]
  }

  env {
    name  = "EXT_1001_PASS"
    value = data.vault_kv_secret_v2.freeswitch.data["ext_1001_pass"]
  }

  env {
    name  = "EXT_1002_PASS"
    value = data.vault_kv_secret_v2.freeswitch.data["ext_1002_pass"]
  }

  env {
    name  = "EXT_1003_PASS"
    value = data.vault_kv_secret_v2.freeswitch.data["ext_1003_pass"]
  }

  env {
    name  = "CC_USERNAME"
    value = data.vault_kv_secret_v2.freeswitch.data["cc_username"]
  }

  env {
    name  = "CC_PASSWORD"
    value = data.vault_kv_secret_v2.freeswitch.data["cc_password"]
  }

  env {
    name  = "CC_DID"
    value = data.vault_kv_secret_v2.freeswitch.data["cc_did"]
  }
}

# ──────────────────────────────────────────────
# Keycloak DB HA cluster — PostgreSQL with repmgr
# Node 0 (primary) on dockermaster, Node 1 (standby) on dockerserver-1
# Auto-failover via repmgr; JDBC clients use multi-host URL
# ──────────────────────────────────────────────
resource "portainer_stack" "keycloak_db_0" {
  name            = "keycloak-db-0"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/keycloak-db-0.yml")

  env {
    name  = "POSTGRES_ROOT_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["postgres_root_password"]
  }
  env {
    name  = "DB_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["db_password"]
  }
  env {
    name  = "REPMGR_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["repmgr_password"]
  }
}

resource "portainer_stack" "keycloak_db_1" {
  name            = "keycloak-db-1"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/keycloak-db-1.yml")

  env {
    name  = "POSTGRES_ROOT_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["postgres_root_password"]
  }
  env {
    name  = "DB_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["db_password"]
  }
  env {
    name  = "REPMGR_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["repmgr_password"]
  }
}

# ──────────────────────────────────────────────
# Keycloak Identity Provider
# SSO + user management — credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "keycloak" {
  name            = "keycloak"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/keycloak.yml")

  env {
    name  = "KC_HOSTNAME"
    value = "auth.cf.lcamaral.com"
  }

  env {
    name  = "KC_DB_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["db_password"]
  }

  env {
    name  = "KEYCLOAK_ADMIN_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["admin_password"]
  }
}

# ──────────────────────────────────────────────
# Keycloak 2 (on dockerserver-1) — Infinispan cluster peer
# ──────────────────────────────────────────────
resource "portainer_stack" "keycloak_2" {
  name            = "keycloak-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/keycloak-2.yml")

  env {
    name  = "KC_HOSTNAME"
    value = "auth.cf.lcamaral.com"
  }

  env {
    name  = "KC_DB_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["db_password"]
  }

  env {
    name  = "KEYCLOAK_ADMIN_PASSWORD"
    value = data.vault_kv_secret_v2.keycloak.data["admin_password"]
  }
}

# ──────────────────────────────────────────────
# Postfix SMTP Relay
# Outbound mail via DreamHost SMTP — credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "postfix_relay" {
  name            = "postfix-relay"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/postfix-relay.yml")

  env {
    name  = "SMTP_USERNAME"
    value = data.vault_kv_secret_v2.smtp.data["username"]
  }

  env {
    name  = "SMTP_PASSWORD"
    value = data.vault_kv_secret_v2.smtp.data["password"]
  }
}

# ──────────────────────────────────────────────
# Homelab Portal (login.cf.lcamaral.com)
# Custom SSO login UI backed by Keycloak
# Secrets from Vault: keycloak/clients + portal
# ──────────────────────────────────────────────
resource "portainer_stack" "homelab_portal" {
  name            = "homelab-portal"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/homelab-portal.yml")

  env {
    name  = "KEYCLOAK_CLIENT_SECRET"
    value = data.vault_kv_secret_v2.keycloak_clients.data["homelab_portal_secret"]
  }

  env {
    name  = "SESSION_SECRET"
    value = data.vault_kv_secret_v2.portal.data["session_secret"]
  }

  env {
    name  = "SESSION_ENCRYPTION_KEY"
    value = data.vault_kv_secret_v2.portal.data["session_encryption_key"]
  }
}

# ──────────────────────────────────────────────
# Homelab Portal replica 2 on dockerserver-1 — stateless, no sticky needed
# ──────────────────────────────────────────────
resource "portainer_stack" "homelab_portal_2" {
  name            = "homelab-portal-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/homelab-portal-2.yml")

  env {
    name  = "KEYCLOAK_CLIENT_SECRET"
    value = data.vault_kv_secret_v2.keycloak_clients.data["homelab_portal_secret"]
  }

  env {
    name  = "SESSION_SECRET"
    value = data.vault_kv_secret_v2.portal.data["session_secret"]
  }

  env {
    name  = "SESSION_ENCRYPTION_KEY"
    value = data.vault_kv_secret_v2.portal.data["session_encryption_key"]
  }
}

# ──────────────────────────────────────────────
# Pi-hole HA — Pattern B execution (task #26)
#
# Three pihole instances across two physical hosts:
#   pihole-1 (existing) — Proxmox LXC 10000, 192.168.100.254
#   pihole-2 (this)     — Docker on dockerserver-1, macvlan 192.168.59.50
#   pihole-3 (this)     — Docker on NAS, macvlan 192.168.4.236
#
# Authoritative records for d.lcamaral.com live in the repo at
# pihole/dnsmasq.d/04-d-lcamaral-com.conf (single source of truth).
# The compose templates use docker `configs:` with inline `content:` to
# inject the file at the target path inside each container — terraform
# `templatefile()` interpolates the content at apply time. When the source
# file changes, the rendered stack content changes, terraform sees the
# diff, and Portainer re-deploys the stack. No host filesystem coupling.
# ──────────────────────────────────────────────

locals {
  pihole_dnsmasq_zone   = file("${path.module}/../../pihole/dnsmasq.d/04-d-lcamaral-com.conf")
  pihole_home_zone      = file("${path.module}/../../pihole/dnsmasq.d/05-home.conf")
  pihole_host_overrides = file("${path.module}/../../pihole/dnsmasq.d/06-host-overrides.conf")
}

resource "portainer_stack" "pihole_2" {
  name            = "pihole-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/pihole-2.yml.tftpl", {
    dnsmasq_content        = local.pihole_dnsmasq_zone
    home_content           = local.pihole_home_zone
    host_overrides_content = local.pihole_host_overrides
  })

  env {
    name  = "WEBPASSWORD"
    value = data.vault_kv_secret_v2.pihole.data["admin_password"]
  }
}

resource "portainer_stack" "pihole_3" {
  name            = "pihole-3"
  endpoint_id     = portainer_environment.nas.id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/pihole-3.yml.tftpl", {
    dnsmasq_content        = local.pihole_dnsmasq_zone
    home_content           = local.pihole_home_zone
    host_overrides_content = local.pihole_host_overrides
  })

  env {
    name  = "WEBPASSWORD"
    value = data.vault_kv_secret_v2.pihole.data["admin_password"]
  }
}

# ──────────────────────────────────────────────
# Phase 3e — pihole-exporter × 3 (eko/pihole-exporter v1.2.0)
#
# One exporter per pihole instance, each running on the same physical
# host as its target pihole. The PIHOLE_PASSWORD comes from Vault
# (`secret/homelab/pihole`, key `admin_password`) — single shared
# password across all three. Three separate stacks (rather than one
# multi-target exporter) give each a clean lifecycle and a distinct
# `instance:` label in Prometheus.
#
# Static IPs:
#   pihole-exporter-1 (dm)   → 192.168.59.41 → scrapes pihole-1 (192.168.100.254)
#   pihole-exporter-2 (ds-1) → 192.168.59.42 → scrapes pihole-2 (192.168.59.50)
#   pihole-exporter-3 (NAS)  → 192.168.4.240 → scrapes pihole-3 (192.168.4.236)
#
# The Prometheus scrape job lives in locals.tf under `pihole`. Both
# replicas pull it.
# ──────────────────────────────────────────────

resource "portainer_stack" "pihole_exporter_1" {
  name            = "pihole-exporter-1"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/pihole-exporter-1.yml")

  env {
    name  = "PIHOLE_PASSWORD"
    value = data.vault_kv_secret_v2.pihole.data["admin_password"]
  }
}

resource "portainer_stack" "pihole_exporter_2" {
  name            = "pihole-exporter-2"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/pihole-exporter-2.yml")

  env {
    name  = "PIHOLE_PASSWORD"
    value = data.vault_kv_secret_v2.pihole.data["admin_password"]
  }
}

resource "portainer_stack" "pihole_exporter_3" {
  name            = "pihole-exporter-3"
  endpoint_id     = portainer_environment.nas.id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/pihole-exporter-3.yml")

  env {
    name  = "PIHOLE_PASSWORD"
    value = data.vault_kv_secret_v2.pihole.data["admin_password"]
  }
}

# ──────────────────────────────────────────────
# orbital-sync — DEFERRED
#
# Pi-hole v6 is not yet supported by orbital-sync (latest 1.8.4 still
# targets the v5 PHP admin endpoints; v6 introduced a new REST API at
# /api/auth which 1.x cannot speak). orbital-sync v2.x with v6 support
# is in progress upstream but unreleased as of 2026-04-14.
#
# Until then, gravity DB + adlist sync between pihole-1/2/3 must be done
# manually (Pi-hole v6 has Teleporter export/import in the web UI). The
# /etc/dnsmasq.d/04-d-lcamaral-com.conf records on all 3 instances are
# kept in sync automatically via the compose `configs:` block above —
# only the gravity/adlist side is impacted by this gap.
#
# When orbital-sync 2.x ships, restore this resource pointing at
# stacks/orbital-sync.yml with image bumped to the v6 tag.
# ──────────────────────────────────────────────

# ──────────────────────────────────────────────
# Prometheus + Thanos HA (Phase 2 — replica B on NAS)
#
# `prometheus-2` + `thanos-sidecar-2` + `alertmanager-2` deployed as a
# single Portainer stack on the Synology NAS endpoint, on the home-net
# macvlan. Replica A (`prometheus-1` + `thanos-sidecar-1` + `alertmanager-1`)
# lives on ds-1; the pair survives a Proxmox outage.
#
# IPs are allocated from the home-net 192.168.4.232/29 pool — see the
# header comment in stacks/prometheus-2.yml.tftpl for the .237/.238/.239
# assignment.
#
# Three template variables are interpolated by templatefile():
#   prometheus_config   — full prometheus.yml body (scrape jobs +
#                         external_labels + alerting + rule_files).
#                         Identical to prometheus-1 except for the
#                         `replica: B` external label.
#   alertmanager_config — full alertmanager.yml body. Same SMTP routing
#                         as alertmanager-1 (intentionally duplicated;
#                         the gossip cluster keeps state in sync).
#   objstore_config_nas — Thanos S3 objstore config rendered from
#                         stacks/objstore-nas.yml.tftpl. The NAS sidecar
#                         reaches MinIO via https://s3.d.lcamaral.com:443
#                         (TLS, via nginx-rproxy) — the ds-1 sidecar uses
#                         the internal http://192.168.59.17:9000.
#
# `prometheus_scrape_config` and `alertmanager_config` locals live in
# locals.tf — that's the single source of truth for both replicas. Edit
# there to update the scrape jobs or alert routing; the resource block
# below picks up changes on next `terraform apply`.
# ──────────────────────────────────────────────

# Phase 2 prometheus-2 references:
#   local.prometheus_scrape_config — shared with prometheus-1 (locals.tf)
#   local.alertmanager_config      — shared with alertmanager-1 (locals.tf)
# The replica differentiation (external_labels.replica = B) is injected
# inside the prometheus-2.yml.tftpl compose via a per-stack CLI flag, not
# in the YAML body — this keeps a single source-of-truth scrape config.
resource "portainer_stack" "prometheus_2" {
  name            = "prometheus-2"
  endpoint_id     = portainer_environment.nas.id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/prometheus-2.yml.tftpl", {
    prometheus_config   = local.prometheus_scrape_config_b
    alertmanager_config = local.alertmanager_config
    objstore_config_nas = templatefile("${path.module}/stacks/objstore-nas.yml.tftpl", {
      access_key = data.vault_kv_secret_v2.thanos.data["access_key"]
      secret_key = data.vault_kv_secret_v2.thanos.data["secret_key"]
    })
    # Phase 3d — Home Assistant scrape token (DECISIONS.md Q8).
    ha_token = data.vault_kv_secret_v2.ha_metrics_token.data["token"]
    # Phase 3a — Watchtower HTTP API bearer token (scraped on :8080/v1/metrics).
    watchtower_token = data.vault_kv_secret_v2.watchtower.data["api_token"]
    # Phase 3a — MinIO Prometheus bearer JWT (scraped on /minio/v2/metrics/cluster).
    minio_jwt = data.vault_kv_secret_v2.minio_metrics_jwt.data["token"]
    # Phase 3f — Rundeck API bearer token (scraped on :4440/metrics).
    rundeck_token = data.vault_kv_secret_v2.rundeck.data["api_token"]
    # Phase 3h — blackbox file_sd target lists (rendered as JSON in locals.tf).
    # Phase 3f extends with the tcp list (FreeSWITCH SIP, RustDesk hbbs/hbbr).
    blackbox_http_targets = local.blackbox_http_targets
    blackbox_icmp_targets = local.blackbox_icmp_targets
    blackbox_ssl_targets  = local.blackbox_ssl_targets
    blackbox_dns_targets  = local.blackbox_dns_targets
    blackbox_tcp_targets  = local.blackbox_tcp_targets
  })
}

# ──────────────────────────────────────────────
# Phase 3h: blackbox-exporter on dockermaster
#
# Provides HTTP/ICMP/TCP/SSL/DNS probes consumed by the `blackbox-*`
# Prometheus jobs (defined in locals.tf for both replicas). Pinned image
# v0.28.0 per generated/prometheus-thanos-monitoring/VERSIONS.md.
#
# Static IP 192.168.59.45 from the docker-servers-net free pool. Lives
# on dockermaster (control-plane) so probes can reach the home-net
# (NAS, pfSense, Pi-holes) and the cf-tunnel origins via the same edge
# Prometheus reaches today.
#
# blackbox.yml is rendered from local.blackbox_config and injected via
# docker `configs:` — same pattern as the rest of the monitoring stacks.
# ──────────────────────────────────────────────
resource "portainer_stack" "blackbox_exporter" {
  name            = "blackbox-exporter"
  endpoint_id     = var.endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = templatefile("${path.module}/stacks/blackbox-exporter.yml.tftpl", {
    blackbox_config = local.blackbox_config
  })
}

# Phase 3f: Twingate metrics are now scraped natively from the
# connector containers (TWINGATE_METRICS_PORT=9999) — see twingate-a.yml
# and twingate-b.yml. The earlier twingate-exporter stack (Admin-API
# poller) was removed when we discovered (a) no upstream image exists
# and (b) the connector itself exposes /metrics in v1.80+.
