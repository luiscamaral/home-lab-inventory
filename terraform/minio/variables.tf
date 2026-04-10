variable "minio_server" {
  description = "MinIO server address (host:port)"
  type        = string
  default     = "s3.cf.lcamaral.com"
}

variable "minio_ssl" {
  description = "Use SSL for MinIO connection"
  type        = bool
  default     = true
}

variable "minio_user" {
  description = "MinIO root user"
  type        = string
  sensitive   = true
}

variable "minio_password" {
  description = "MinIO root password"
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

variable "keycloak_url" {
  description = "Keycloak base URL for OIDC discovery"
  type        = string
  default     = "https://auth.cf.lcamaral.com"
}
