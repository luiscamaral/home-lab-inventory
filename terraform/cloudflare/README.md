# Cloudflare Terraform

Terraform configuration for managing Cloudflare and DreamHost DNS resources in the homelab.

## Architecture

```
DreamHost (authoritative NS for lcamaral.com)
  *.cf.lcamaral.com  CNAME  bologna.cf.lcamaral.com.cdn.cloudflare.net.
       |
       v
Cloudflare (partial zone, proxied)
  bologna.cf.lcamaral.com  CNAME  <tunnel-id>.cfargotunnel.com
       |
       v
Cloudflare Tunnel "bologna"
  bologna.cf.lcamaral.com  ->  https://nginx-rproxy:443 (dockermaster)
```

New services under `*.cf.lcamaral.com` only need a Cloudflare DNS record
and a tunnel ingress entry -- DreamHost routing is handled by the wildcard.

## Resources

### Cloudflare

| Resource | Name | Description |
|----------|------|-------------|
| Zone | `lcamaral_com` | `lcamaral.com` (partial/CNAME setup, Free plan) |
| DNSSEC | `lcamaral_com` | DNSSEC status (disabled) |
| DNS CNAME | `bologna_cf_tunnel` | `bologna.cf.lcamaral.com` -> tunnel (primary) |
| DNS CNAME | `registry_cf_tunnel` | `registry.cf.lcamaral.com` -> tunnel |
| DNS CNAME | `bologna_tunnel` | `bologna.lcamaral.com` -> tunnel (legacy) |
| DNS CNAME | `root` | `lcamaral.com` -> DreamHost |
| DNS CNAME | `www` | `www.lcamaral.com` -> DreamHost |
| Tunnel | `bologna` | Cloudflare Tunnel to `nginx-rproxy:443` |
| Tunnel Config | `bologna` | Ingress rules (remote-managed) |

### DreamHost

| Resource | Name | Description |
|----------|------|-------------|
| DNS CNAME | `cf_wildcard` | `*.cf.lcamaral.com` -> Cloudflare edge |

## Prerequisites

- Terraform >= 1.5.0
- Cloudflare API token in macOS Keychain (`cloudflare-api-token`)
- DreamHost API key in Vault (`secret/homelab/dreamhost`)

## Usage

```bash
cd terraform/cloudflare

# Set tokens from Keychain and Vault
export TF_VAR_cloudflare_api_token=$(security find-generic-password -a ${USER} -s cloudflare-api-token -w)
export TF_VAR_dreamhost_api_key=$(VAULT_ADDR="http://vault.d.lcamaral.com" \
  VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token) \
  vault kv get -field=api_token secret/homelab/dreamhost)

# Init, plan, apply
terraform init
terraform plan
terraform apply
```

## File Structure

```
cloudflare/
  provider.tf    # Cloudflare v5 + DreamHost v0.3 providers
  variables.tf   # Input variables (account_id, zone_id, tokens)
  main.tf        # Cloudflare zone, DNS, tunnel resources
  dreamhost.tf   # DreamHost wildcard CNAME for *.cf delegation
  imports.tf     # HCL import blocks for existing resources
  outputs.tf     # Zone, tunnel, DNS outputs
  .gitignore     # Excludes state, .terraform/, tfvars, binary
```

## Notes

- State is local and gitignored. Back it up or migrate to remote backend as needed.
- The zone is **partial** (CNAME setup) -- DNS is hosted at DreamHost, Cloudflare
  proxies via CNAME flattening.
- The wildcard `*.cf.lcamaral.com` on DreamHost routes all `cf` subdomains to
  Cloudflare's edge. Cloudflare matches the `Host` header to the correct record.
- The tunnel is **remote-managed** (`config_src: cloudflare`). Ingress rules are
  controlled via `cloudflare_zero_trust_tunnel_cloudflared_config`.
- DreamHost DNS records are immutable in the provider -- changes trigger replace.
