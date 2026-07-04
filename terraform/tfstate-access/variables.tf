variable "minio_server" {
  description = "MinIO S3 API endpoint — Cloudflare-tunneled so off-LAN/off-VPN projects can reach it"
  type        = string
  default     = "s3.cf.lcamaral.com"
}

variable "minio_ssl" {
  description = "Use TLS for the MinIO connection"
  type        = bool
  default     = true
}

variable "minio_user" {
  description = "MinIO access key (from Vault secret/homelab/minio root_user)"
  type        = string
  sensitive   = true
}

variable "minio_password" {
  description = "MinIO secret key (from Vault secret/homelab/minio root_password)"
  type        = string
  sensitive   = true
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "http://vault.d.lcamaral.com"
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
}
