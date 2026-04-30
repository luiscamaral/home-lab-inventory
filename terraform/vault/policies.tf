# ──────────────────────────────────────────────
# Vault Policies  (I3 – auth & policy audit)
# ──────────────────────────────────────────────
#
# 7 custom policies discovered in Vault.
# `default` and `root` are built-in and not managed here.

# ──────────────────────────────────────────────
# dockermaster-home-lab-inventory
# ──────────────────────────────────────────────
# Full CRUD on dockermaster dev secrets.
# Referenced by github team mapping: project-x-devs.
resource "vault_policy" "dockermaster_home_lab_inventory" {
  name = "dockermaster-home-lab-inventory"

  policy = <<-EOT
    path "secret/data/dockermaster/dev/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    path "secret/metadata/dockermaster/dev/" {
      capabilities = ["list"]
    }
  EOT
}

# ──────────────────────────────────────────────
# dockermaster-home-lab-inventory-ro
# ──────────────────────────────────────────────
# Read-only view of dockermaster dev secrets.
resource "vault_policy" "dockermaster_home_lab_inventory_ro" {
  name = "dockermaster-home-lab-inventory-ro"

  policy = <<-EOT
    path "secret/data/dockermaster/dev/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# ──────────────────────────────────────────────
# kubernetes-secrets
# ──────────────────────────────────────────────
# Read-only access to kubernetes secrets.
# NOTE: The kubernetes auth backend is unconfigured (no roles, no config).
#       This policy is currently unused.
resource "vault_policy" "kubernetes_secrets" {
  name = "kubernetes-secrets"

  policy = <<-EOT
    path "secret/data/kubernetes/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# ──────────────────────────────────────────────
# kv-app-readonly
# ──────────────────────────────────────────────
# Read-only access to a single KV path (app config).
resource "vault_policy" "kv_app_readonly" {
  name = "kv-app-readonly"

  policy = <<-EOT
    path "kv/data/app/config" {
      capabilities = ["read"]
    }
  EOT
}

# ──────────────────────────────────────────────
# prometheus-scrape
# ──────────────────────────────────────────────
# Read-only access to homelab monitoring credentials.
resource "vault_policy" "prometheus_scrape" {
  name = "prometheus-scrape"

  policy = <<-EOT
    path "secret/data/homelab/proxmox/api_token"            { capabilities = ["read"] }
    path "secret/data/homelab/home-assistant/metrics_token" { capabilities = ["read"] }
    path "secret/data/homelab/vault-metrics/token"          { capabilities = ["read"] }
    path "secret/data/homelab/unifi/controller_api"         { capabilities = ["read"] }
    path "secret/data/homelab/omada/api"                    { capabilities = ["read"] }
    path "secret/data/homelab/ilo/readonly"                 { capabilities = ["read"] }
    path "secret/data/homelab/pfsense/snmp"                 { capabilities = ["read"] }
  EOT
}

# ──────────────────────────────────────────────
# superuser
# ──────────────────────────────────────────────
# God-mode policy — full access + sudo on every path.
# Assigned to userpass user `lamaral`.
resource "vault_policy" "superuser" {
  name = "superuser"

  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

# ──────────────────────────────────────────────
# thanos-storage
# ──────────────────────────────────────────────
# Read-only access to Thanos S3 credentials.
resource "vault_policy" "thanos_storage" {
  name = "thanos-storage"

  policy = <<-EOT
    path "secret/data/homelab/thanos/s3" { capabilities = ["read"] }
  EOT
}
