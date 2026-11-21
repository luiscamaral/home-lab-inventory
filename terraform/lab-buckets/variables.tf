variable "minio_server" {
  description = "MinIO S3 API endpoint (internal nginx; NOT the console minio.d, NOT Cloudflare s3.cf)"
  type        = string
  default     = "s3.d.lcamaral.com"
}

variable "minio_ssl" {
  description = "Use TLS for the MinIO connection"
  type        = bool
  default     = true
}

variable "minio_insecure" {
  description = "Skip TLS verification — the *.d.lcamaral.com LE cert chain omits the intermediate"
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
