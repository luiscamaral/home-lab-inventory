terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  # Local state — see lab-network/providers.tf. MinIO S3 backend deferred (flaky operator-side
  # MinIO-over-HTTPS access); migrate later with `terraform init -migrate-state`.
}
