variable "vault_address" {
  description = "Vault server URL"
  type        = string
  default     = "http://vault.d.lcamaral.com"
}

variable "vault_token" {
  description = "Vault root token (from macOS Keychain: vault-root-token)"
  type        = string
  sensitive   = true
}
