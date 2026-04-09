# ──────────────────────────────────────────────
# Vault Data Sources
# Read secrets at apply time for stack env injection
# ──────────────────────────────────────────────

data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret"
  name  = "homelab/cloudflare"
}
