# ──────────────────────────────────────────────
# Homelab Docker Registry (registry:2) — LEGACY, cool-off period.
# registry.cf.lcamaral.com — credentials from Vault. Superseded by
# zot_registry below; remove both after cool-off (docs/zot-registry.md).
# ──────────────────────────────────────────────
resource "portainer_registry" "homelab_registry" {
  name           = "Homelab Registry"
  url            = "registry.cf.lcamaral.com"
  type           = 3
  authentication = true
  username       = data.vault_kv_secret_v2.registry.data["admin_user"]
  password       = data.vault_kv_secret_v2.registry.data["admin_password"]
}

# ──────────────────────────────────────────────
# Zot registry (LAN-only) — zot.d.lcamaral.com
# Lets Portainer pull authenticated homelab/* images for stacks.
# ──────────────────────────────────────────────
resource "portainer_registry" "zot_registry" {
  name           = "Zot Registry"
  url            = "zot.d.lcamaral.com"
  type           = 3
  authentication = true
  username       = data.vault_kv_secret_v2.zot.data["admin_user"]
  password       = data.vault_kv_secret_v2.zot.data["admin_password"]
}
