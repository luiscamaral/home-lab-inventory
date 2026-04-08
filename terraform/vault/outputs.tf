output "secret_engine_path" {
  description = "KV v2 secret engine mount path"
  value       = vault_mount.secret.path
}

output "ssh_engine_path" {
  description = "SSH secret engine mount path"
  value       = vault_mount.ssh.path
}
