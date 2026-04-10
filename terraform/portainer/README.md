# Portainer Terraform

Manage Portainer stacks and settings on dockermaster via IaC.

## Prerequisites

- Terraform >= 1.5.0
- Portainer admin password in Vault (`secret/homelab/portainer`)
- Vault root token in macOS Keychain (`vault-root-token`)

## Usage

```bash
cd terraform/portainer

export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token)

export TF_VAR_portainer_password=$(vault kv get -field=admin_password secret/homelab/portainer)
export TF_VAR_vault_token=$VAULT_TOKEN

terraform init
terraform plan
terraform apply
```

## Importing Existing Stacks

To bring an existing compose project under Portainer management:

1. Add a `portainer_stack` resource in `stacks.tf`
2. Place the compose file in `stacks/<name>.yml`
3. Import: `terraform import portainer_stack.<name> <stack-id>`

## File Structure

```
portainer/
  provider.tf       # Portainer provider ~> 1.11, HashiCorp Vault provider ~> 4.0
  variables.tf      # Endpoint ID, credentials
  stacks.tf         # Stack resources
  vault.tf          # Vault data sources for stack secrets
  outputs.tf        # Stack names/IDs
  stacks/           # Compose files referenced by stacks
    bind-dns.yml
    calibre.yml
    cloudflare-tunnel.yml
    docker-registry.yml
    github-runner.yml
    reverse-proxy.yml
    twingate-a.yml
    twingate-b.yml
    vault.yml
  .gitignore
```
