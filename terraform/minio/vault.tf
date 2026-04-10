# ──────────────────────────────────────────────
# Vault Data Sources
# ──────────────────────────────────────────────

data "vault_kv_secret_v2" "keycloak_clients" {
  mount = "secret"
  name  = "homelab/keycloak/clients"
}
