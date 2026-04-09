variable "cloudflare_api_token" {
  description = "Cloudflare API Token (from macOS Keychain: cloudflare-api-token)"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string
  default     = "13538d3dbd6b9cd04da9359142bb8d10"
}

variable "zone_id" {
  description = "Cloudflare Zone ID for lcamaral.com"
  type        = string
  default     = "d91929b42a245625bebb527e5fd2e020"
}

variable "dreamhost_api_key" {
  description = "DreamHost API Key (from Vault: secret/homelab/dreamhost)"
  type        = string
  sensitive   = true
}

variable "keycloak_client_secret" {
  description = "Keycloak OIDC client secret for Cloudflare Access"
  type        = string
  sensitive   = true
}
