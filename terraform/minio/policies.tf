# ──────────────────────────────────────────────
# IAM Policies
# Mapped to Keycloak client roles via OIDC claim
# ──────────────────────────────────────────────

# consoleAdmin is a built-in MinIO policy — no need to create it

# Read-write access to all buckets
resource "minio_iam_policy" "readwrite" {
  name   = "readwrite"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["arn:aws:s3:::*"]
      }
    ]
  })
}

# Read-only access to all buckets
resource "minio_iam_policy" "readonly" {
  name   = "readonly"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = ["arn:aws:s3:::*"]
      }
    ]
  })
}
