# State + backup buckets for the Talos lab cluster.
#   tfstate         — remote backend for the new TF roots (one key per root)
#   velero-k8s-lab  — Velero filesystem (kopia) backups
#   thanos-k8s-lab  — in-cluster Prometheus Thanos-sidecar blocks (distinct from existing "thanos")
#
# SSE-at-rest deferred (MinIO SSE needs KES/KMS, not configured here). Buckets are versioned.

locals {
  lab_buckets = ["tfstate", "velero-k8s-lab", "thanos-k8s-lab"]
}

resource "minio_s3_bucket" "lab" {
  for_each = toset(local.lab_buckets)

  bucket        = each.value
  acl           = "private"
  force_destroy = false
}

resource "minio_s3_bucket_versioning" "lab" {
  for_each = toset(local.lab_buckets)

  bucket = minio_s3_bucket.lab[each.value].bucket

  versioning_configuration {
    status = "Enabled"
  }
}
