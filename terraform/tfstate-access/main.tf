# Scoped MinIO service accounts for external projects' Terraform state.
# All projects share the single "tfstate" bucket (terraform/lab-buckets), one
# prefix per project. Each service account's policy restricts it to its own
# prefix only — a leaked key for one project can't read/write another's state
# or any other bucket.

locals {
  tfstate_projects = ["modera-platform"]
}

resource "minio_iam_service_account" "tfstate" {
  for_each = toset(local.tfstate_projects)

  target_user = var.minio_user
  name        = "tfstate-${each.value}"
  description = "TF state access for ${each.value} (bucket: tfstate, prefix: ${each.value}/)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::tfstate/${each.value}/*"]
      },
      {
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::tfstate"]
        Condition = {
          StringLike = { "s3:prefix" = ["${each.value}/*"] }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = ["arn:aws:s3:::tfstate"]
      }
    ]
  })
}

resource "vault_kv_secret_v2" "tfstate" {
  for_each = toset(local.tfstate_projects)

  mount = "secret"
  name  = "homelab/minio/tfstate-${each.value}"
  data_json = jsonencode({
    access_key = minio_iam_service_account.tfstate[each.value].access_key
    secret_key = minio_iam_service_account.tfstate[each.value].secret_key
    endpoint   = var.minio_server
    bucket     = "tfstate"
    key_prefix = "${each.value}/"
  })
}
