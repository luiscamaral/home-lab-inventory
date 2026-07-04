# Scoped MinIO service accounts for external projects' Terraform state.
# All projects share the single "tfstate" bucket (terraform/lab-buckets), one
# prefix per project. Each service account's policy restricts it to its own
# prefix only — a leaked key for one project can't read/write another's state
# or any other bucket.
#
# GOTCHA: aminueza/minio v3.38.1's Read for minio_iam_service_account is
# broken against this MinIO server version — a normal `terraform plan` marks
# every already-existing entry "will be created" (false diff from a bad
# refresh, not real drift; confirmed via TF_LOG=warn: "produced an invalid
# plan... tolerating it because legacy plugin SDK"). Applying that plan
# recreates the service account (new access key) and overwrites its Vault
# secret out from under whatever already consumed the old one. Always run
# `terraform plan -refresh=false` / `terraform apply -refresh=false` in this
# directory. Also: creation itself intermittently errors "Provider produced
# inconsistent result after apply" (provider bug) — the account is usually
# created live regardless; check `terraform state list` before retrying to
# avoid leaving a duplicate, secret-less orphan on the server.

locals {
  tfstate_projects = ["modera-platform", "premium-sre-cell"]
}

# Site replication between minio-1/minio-2 only syncs service accounts owned
# by a real IAM user — accounts parented to root/admin are site-local by
# MinIO design (confirmed via `mc admin replicate status`: "User replication
# status: No Users present"). So every service account below is parented to
# this dedicated user instead of var.minio_user (root), letting them
# replicate across both nodes. This user's own policy is just the ceiling —
# each service account's own inline policy (below) narrows it down to that
# project's prefix; MinIO service-account permissions are the intersection
# of the two, so the ceiling never grants more than the per-account policy
# allows.
resource "minio_iam_user" "tfstate_provisioner" {
  name = "tfstate-provisioner"
}

resource "minio_iam_policy" "tfstate_bucket_ceiling" {
  name = "tfstate-bucket-ceiling"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::tfstate/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = ["arn:aws:s3:::tfstate"]
      }
    ]
  })
}

resource "minio_iam_user_policy_attachment" "tfstate_provisioner" {
  user_name   = minio_iam_user.tfstate_provisioner.id
  policy_name = minio_iam_policy.tfstate_bucket_ceiling.id
}

resource "minio_iam_service_account" "tfstate" {
  for_each = toset(local.tfstate_projects)

  target_user = minio_iam_user.tfstate_provisioner.id
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
