# ──────────────────────────────────────────────
# KV v2 Secret Engine
# ──────────────────────────────────────────────
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  description = "Homelab secrets (KV v2)"

  options = {
    version = "2"
  }
}

# ──────────────────────────────────────────────
# SSH Secret Engine
# ──────────────────────────────────────────────
resource "vault_mount" "ssh" {
  path        = "ssh"
  type        = "ssh"
  description = "SSH certificates"
}

# ──────────────────────────────────────────────
# KV Secret Engine
# ──────────────────────────────────────────────
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv"
  description = "Key-value store (KV v2)"

  options = {
    version = "2"
  }
}
