output "access_keys" {
  description = "Access key (public identifier, not secret) per project"
  value       = { for k, sa in minio_iam_service_account.tfstate : k => sa.access_key }
}

output "vault_paths" {
  description = "Where each project's full credential (access_key + secret_key) landed in Vault"
  value       = { for k in local.tfstate_projects : k => "secret/homelab/minio/tfstate-${k}" }
}
