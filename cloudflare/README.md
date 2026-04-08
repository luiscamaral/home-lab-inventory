# Cloudflare Terraform

Terraform configuration for managing Cloudflare resources in the homelab.

## Resources

| Resource | Name | Description |
|----------|------|-------------|
| Tunnel | `bologna` | Cloudflare Tunnel routing `bologna.lcamaral.com` to `nginx-rproxy:443` |
| Tunnel Config | `bologna` | Ingress rules for the tunnel (remote-managed) |

## Prerequisites

- Terraform >= 1.5.0
- Cloudflare API token in macOS Keychain (`cloudflare-api-token`)
- Token requires **Cloudflare Tunnel:Edit** permission on the account

## Usage

```bash
cd cloudflare

# Set the token from Keychain
export TF_VAR_cloudflare_api_token=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)

# Init, plan, apply
terraform init
terraform plan
terraform apply
```

## Token Permissions

The current API token has access to:

| Scope | Access |
|-------|--------|
| Account list | Read |
| Tunnels | Read / Write / Config |
| Zones | No access |
| Account settings | No access |

To manage DNS or zone settings, extend the token permissions in the
[Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens).

## File Structure

```
cloudflare/
  provider.tf    # Terraform + Cloudflare provider config
  variables.tf   # Input variables (account_id, api_token)
  main.tf        # Tunnel and tunnel config resources
  imports.tf     # Import blocks for existing resources
  outputs.tf     # Tunnel ID and name outputs
  .gitignore     # Excludes state, .terraform/, tfvars
```

## Notes

- State is local and gitignored. Back it up or migrate to remote backend as needed.
- The tunnel is **remote-managed** (`config_src: cloudflare`). Ingress rules are
  controlled here via `cloudflare_zero_trust_tunnel_cloudflared_config`.
- The `imports.tf` file is only needed for the initial import. It can be removed
  after state is established, but keeping it is harmless.
