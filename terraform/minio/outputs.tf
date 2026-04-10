output "oidc_provider" {
  description = "OIDC provider configuration"
  value       = minio_iam_idp_openid.keycloak.config_url
}

output "policies" {
  description = "IAM policies"
  value = {
    readwrite = minio_iam_policy.readwrite.name
    readonly  = minio_iam_policy.readonly.name
  }
}
