# ──────────────────────────────────────────────
# Docker Registry (already deployed via Portainer)
# ──────────────────────────────────────────────
resource "portainer_stack" "docker_registry" {
  name             = "docker-registry"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/docker-registry.yml")
}

# ──────────────────────────────────────────────
# Cloudflare Tunnel
# Connects homelab to Cloudflare edge via tunnel "bologna"
# Token injected from Vault at apply time
# ──────────────────────────────────────────────
resource "portainer_stack" "cloudflare_tunnel" {
  name             = "cloudflare-tunnel"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/cloudflare-tunnel.yml")

  env {
    name  = "TUNNEL_TOKEN"
    value = data.vault_kv_secret_v2.cloudflare.data["tunnel_token"]
  }
}

# ──────────────────────────────────────────────
# Bind9 DNS
# Authoritative DNS for d.lcamaral.com (internal LAN)
# No secrets needed — config is on NFS volumes
# ──────────────────────────────────────────────
resource "portainer_stack" "bind_dns" {
  name             = "bind-dns"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/bind-dns.yml")
}

# ──────────────────────────────────────────────
# Nginx Reverse Proxy + Promtail
# All services route through this — certs managed by pfSense
# ──────────────────────────────────────────────
resource "portainer_stack" "reverse_proxy" {
  name             = "reverse-proxy"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/reverse-proxy.yml")
}

# ──────────────────────────────────────────────
# Vault Node 3 → dockerserver-2
# Third Raft peer — gives cluster quorum protection
# No secrets needed; joins existing cluster on first boot
# ──────────────────────────────────────────────
resource "portainer_stack" "vault_3" {
  name             = "vault-3"
  endpoint_id      = var.ds2_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/vault-3.yml")
}

# ──────────────────────────────────────────────
# HashiCorp Vault
# Secret management — env vars for internal CLI only
# ──────────────────────────────────────────────
resource "portainer_stack" "vault" {
  name             = "vault"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "twingate-a"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "twingate-b"
  endpoint_id      = var.ds2_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "calibre"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "github-runner"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "rust-server"
  endpoint_id      = var.ds2_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/rustdesk.yml")
}

# ──────────────────────────────────────────────
# Rundeck + PostgreSQL → dockerserver-1
# Automation server — DB and storage passwords from Vault
# Image pushed to registry as registry.cf.lcamaral.com/la-rundeck:latest
# ──────────────────────────────────────────────
resource "portainer_stack" "rundeck" {
  name             = "la-rundeck"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "prometheus"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/prometheus.yml")
}

# ──────────────────────────────────────────────
# Watchtower → dockerserver-1
# Auto-updates opted-in containers daily at 4 AM
# ──────────────────────────────────────────────
resource "portainer_stack" "watchtower" {
  name             = "watchtower"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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

# ──────────────────────────────────────────────
# MinIO S3 Storage → dockerserver-1
# Object storage — root credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "minio" {
  name             = "minio"
  endpoint_id      = var.ds1_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "minio-2"
  endpoint_id      = var.ds2_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "freeswitch"
  endpoint_id      = var.ds2_endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
# Keycloak Identity Provider
# SSO + user management — credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "keycloak" {
  name             = "keycloak"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
# Postfix SMTP Relay
# Outbound mail via DreamHost SMTP — credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "postfix_relay" {
  name             = "postfix-relay"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
  name             = "homelab-portal"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

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
