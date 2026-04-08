# Cloudflare Terraform

Terraform configuration for managing Cloudflare resources in the homelab.

## Resources

| Resource | Name | Description |
|----------|------|-------------|
| Zone | `lcamaral_com` | `lcamaral.com` (partial/CNAME setup via DreamHost, Free plan) |
| DNSSEC | `lcamaral_com` | DNSSEC status (currently disabled) |
| DNS CNAME | `bologna_tunnel` | `bologna.lcamaral.com` -> tunnel (proxied) |
| DNS CNAME | `root` | `lcamaral.com` -> `resolve-to.www.lcamaral.com` (proxied) |
| DNS CNAME | `www` | `www.lcamaral.com` -> `resolve-to.www.lcamaral.com` (proxied) |
| Tunnel | `bologna` | Cloudflare Tunnel routing to `nginx-rproxy:443` |
| Tunnel Config | `bologna` | Ingress rules (remote-managed) |

## Prerequisites

- Terraform >= 1.5.0
- Cloudflare API token in macOS Keychain (`cloudflare-api-token`)

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

| Scope | Access |
|-------|--------|
| Account list | Read |
| Tunnels | Read / Write / Config |
| Zone | Read / Edit |
| DNS | Read / Edit |
| Zone Settings | Read / Edit |
| Access Service Tokens | Read / Write |

## File Structure

```
cloudflare/
  provider.tf    # Terraform + Cloudflare provider v5 config
  variables.tf   # Input variables (account_id, zone_id, api_token)
  main.tf        # Zone, DNS, Tunnel resources
  imports.tf     # HCL import blocks for existing resources
  outputs.tf     # Zone, tunnel, DNS outputs
  .gitignore     # Excludes state, .terraform/, tfvars, binary
```

## Notes

- State is local and gitignored. Back it up or migrate to remote backend as needed.
- The zone is **partial** (CNAME setup) -- DNS is hosted at DreamHost, Cloudflare
  proxies via CNAME flattening.
- The tunnel is **remote-managed** (`config_src: cloudflare`). Ingress rules are
  controlled here via `cloudflare_zero_trust_tunnel_cloudflared_config`.
- The `imports.tf` file is only needed for the initial import. It can be removed
  after state is established, but keeping it is harmless.
