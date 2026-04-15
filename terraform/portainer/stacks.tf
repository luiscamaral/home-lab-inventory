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
# Prometheus Monitoring Stack → dockerserver-1
# prometheus + node-exporter + snmp-exporter + alertmanager + cadvisor
# Internal back-tier network only, no secrets
# ──────────────────────────────────────────────
resource "portainer_stack" "prometheus" {
  name            = "prometheus"
  endpoint_id     = var.ds1_endpoint_id
  deployment_type = "standalone"
  method          = "string"

  stack_file_content = file("${path.module}/stacks/prometheus.yml")
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
  endpoint_id     = var.nas_endpoint_id
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
