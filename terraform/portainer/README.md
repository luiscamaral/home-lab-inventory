# Portainer Terraform

Manage Portainer stacks and settings on dockermaster via IaC.

## Prerequisites

- Terraform >= 1.5.0
- Portainer admin password in Vault (`secret/homelab/portainer`)

## Usage

```bash
cd terraform/portainer

export TF_VAR_portainer_password=$(VAULT_ADDR="http://vault.d.lcamaral.com" \
  VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token) \
  vault kv get -field=admin_password secret/homelab/portainer)

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
  provider.tf       # Portainer provider v1.11
  variables.tf      # Endpoint ID, credentials
  stacks.tf         # Stack resources
  outputs.tf        # Stack names/IDs
  stacks/           # Compose files referenced by stacks
    docker-registry.yml
  .gitignore
```
