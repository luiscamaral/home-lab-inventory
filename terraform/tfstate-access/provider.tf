terraform {
  required_version = ">= 1.5.0"

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

# Isolated root: creates scoped IAM service accounts (one per external project)
# against the existing "tfstate" bucket (created by terraform/lab-buckets). Kept
# separate from terraform/minio (which manages IAM/OIDC and currently has lost
# local state) so this apply cannot touch those resources.
provider "minio" {
  minio_server   = var.minio_server
  minio_user     = var.minio_user
  minio_password = var.minio_password
  minio_ssl      = var.minio_ssl
}

provider "vault" {
  address         = var.vault_addr
  token           = var.vault_token
  skip_tls_verify = true
}
