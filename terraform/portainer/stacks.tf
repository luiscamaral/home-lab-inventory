# ──────────────────────────────────────────────
# Docker Registry (already deployed via Portainer)
# ──────────────────────────────────────────────
resource "portainer_stack" "docker_registry" {
  name             = "docker-registry"
  endpoint_id      = var.endpoint_id
  deployment_type  = "compose"
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
# Twingate Connector A (sepia-hornet)
# VPN connector — tokens from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "twingate_a" {
  name             = "twingate-a"
  endpoint_id      = var.endpoint_id
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
# Twingate Connector B (golden-mussel)
# VPN connector — tokens from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "twingate_b" {
  name             = "twingate-b"
  endpoint_id      = var.endpoint_id
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
# Calibre (calibre + calibre-web)
# Ebook server — password from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "calibre" {
  name             = "calibre"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/calibre.yml")

  env {
    name  = "CALIBRE_PASSWORD"
    value = data.vault_kv_secret_v2.calibre.data["password"]
  }
}

# ──────────────────────────────────────────────
# GitHub Runner
# CI/CD self-hosted runner — PAT from Vault
# ──────────────────────────────────────────────
resource "portainer_stack" "github_runner" {
  name             = "github-runner"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/github-runner.yml")

  env {
    name  = "GITHUB_TOKEN"
    value = data.vault_kv_secret_v2.github_runner.data["github_token"]
  }
}

# ──────────────────────────────────────────────
# RustDesk (hbbs + hbbr)
# Remote desktop server — no secrets
# ──────────────────────────────────────────────
resource "portainer_stack" "rustdesk" {
  name             = "rust-server"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/rustdesk.yml")
}

# ──────────────────────────────────────────────
# Rundeck + PostgreSQL
# Automation server — DB and storage passwords from Vault
# Uses locally-built image (la-rundeck-rundeck:latest)
# ──────────────────────────────────────────────
resource "portainer_stack" "rundeck" {
  name             = "la-rundeck"
  endpoint_id      = var.endpoint_id
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
# Prometheus Monitoring Stack
# prometheus + node-exporter + snmp-exporter + alertmanager + cadvisor
# Internal back-tier network only, no secrets
# ──────────────────────────────────────────────
resource "portainer_stack" "prometheus" {
  name             = "prometheus"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/prometheus.yml")
}

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
