# ──────────────────────────────────────────────
# Homelab Docker Registry
# registry.cf.lcamaral.com — credentials from Vault
# ──────────────────────────────────────────────
resource "portainer_registry" "homelab_registry" {
  name           = "Homelab Registry"
  url            = "registry.cf.lcamaral.com"
  type           = 3
  authentication = true
  username       = data.vault_kv_secret_v2.registry.data["admin_user"]
  password       = data.vault_kv_secret_v2.registry.data["admin_password"]
}
