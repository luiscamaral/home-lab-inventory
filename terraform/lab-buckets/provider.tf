terraform {
  required_version = ">= 1.5.0"

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.2"
    }
  }
}

# Isolated bootstrap root: creates ONLY the lab-cluster buckets. Kept separate from
# terraform/minio (which manages IAM/OIDC and currently has lost local state) so this
# apply cannot touch those resources. Local state — this is the chicken-and-egg root
# that creates the very tfstate bucket the other roots use; migrate to S3 later if desired.
provider "minio" {
  minio_server   = var.minio_server
  minio_user     = var.minio_user
  minio_password = var.minio_password
  minio_ssl      = var.minio_ssl
  minio_insecure = var.minio_insecure
}
