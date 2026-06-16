variable "proxmox_token_vault_path" {
  description = <<-EOT
    Vault KV path for the Proxmox API token. Defaults to the existing read-only metrics token
    (`prometheus@pam!metrics`) so `terraform validate`/`plan` work today. Switch to a write-capable
    token (e.g. `homelab/proxmox/iac_token`) to `apply` — see README for the pveum role.
  EOT
  type        = string
  default     = "homelab/proxmox/api_token"
}

data "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = var.proxmox_token_vault_path
}
