# ──────────────────────────────────────────────
# Vault Data Sources
# Read secrets at apply time for stack env injection
# ──────────────────────────────────────────────

data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret"
  name  = "homelab/cloudflare"
}

data "vault_kv_secret_v2" "twingate_sepia_hornet" {
  mount = "secret"
  name  = "homelab/twingate/sepia-hornet"
}

data "vault_kv_secret_v2" "twingate_golden_mussel" {
  mount = "secret"
  name  = "homelab/twingate/golden-mussel"
}

data "vault_kv_secret_v2" "vault" {
  mount = "secret"
  name  = "homelab/vault"
}

data "vault_kv_secret_v2" "calibre" {
  mount = "secret"
  name  = "homelab/calibre"
}

data "vault_kv_secret_v2" "github_runner" {
  mount = "secret"
  name  = "homelab/github-runner"
}

data "vault_kv_secret_v2" "rundeck" {
  mount = "secret"
  name  = "homelab/rundeck"
}

data "vault_kv_secret_v2" "watchtower" {
  mount = "secret"
  name  = "homelab/watchtower"
}

data "vault_kv_secret_v2" "minio" {
  mount = "secret"
  name  = "homelab/minio"
}

data "vault_kv_secret_v2" "freeswitch" {
  mount = "secret"
  name  = "homelab/freeswitch"
}
