terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  # Local state — matches every existing root (cloudflare/portainer/vault/minio). The MinIO S3
  # backend was deferred: operator-side MinIO-over-HTTPS access from the workstation is flaky
  # (Cloudflare 502 on s3.cf writes; *.d.lcamaral.com LE chain omits the intermediate). The
  # tfstate/velero/thanos buckets exist for cluster-internal use; migrate this root to the S3
  # backend later once a reliable operator endpoint exists (`terraform init -migrate-state`).
}
