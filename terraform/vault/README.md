# Vault Terraform

Manage HashiCorp Vault secret engines and policies on dockermaster.

## Prerequisites

- Terraform >= 1.5.0
- Vault root token in macOS Keychain (`vault-root-token`)
- Vault server at `http://vault.d.lcamaral.com`

## Usage

```bash
cd terraform/vault

export TF_VAR_vault_token=$(security find-generic-password -w -a ${USER} -s vault-root-token)

terraform init
terraform plan
terraform apply
```

## Resources

| Resource | Path | Type |
|----------|------|------|
| Secret engine | `secret/` | KV v2 (homelab secrets) |
| SSH engine | `ssh/` | SSH certificates |
| KV engine | `kv/` | KV v2 |

## Extending

Add policies, auth methods, or additional secret engines as needed:

```hcl
resource "vault_policy" "readonly" {
  name   = "readonly"
  policy = file("policies/readonly.hcl")
}

resource "vault_auth_backend" "approle" {
  type = "approle"
}
```
