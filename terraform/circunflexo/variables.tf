variable "dreamhost_api_key" {
  description = "DreamHost API Key (from Vault: secret/homelab/dreamhost, field api_token)"
  type        = string
  sensitive   = true
}
