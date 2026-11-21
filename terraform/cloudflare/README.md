# Cloudflare Terraform

Terraform configuration for managing Cloudflare and DreamHost DNS resources in the homelab.

## Architecture

```text
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

New services under `*.cf.lcamaral.com` need a Cloudflare DNS record and a tunnel
ingress entry here (DreamHost routing is handled by the wildcard), plus an Nginx
vhost whose `server_name` matches the `.cf` name. See
[Adding a public hostname](#adding-a-public-hostname).

## Resources

### Cloudflare

| Resource | Name | Description |
|----------|------|-------------|
| Zone | `lcamaral_com` | `lcamaral.com` (partial/CNAME setup, Free plan) |
| DNSSEC | `lcamaral_com` | DNSSEC status (disabled) |
| DNS CNAME | `bologna_cf_tunnel` | `bologna.cf.lcamaral.com` -> tunnel (primary) |
| DNS CNAME | `auth_cf_tunnel` | `auth.cf.lcamaral.com` -> tunnel (Keycloak) |
| DNS CNAME | `login_cf_tunnel` | `login.cf.lcamaral.com` -> tunnel (Keycloak, legacy URL) |
| DNS CNAME | `portainer_cf_tunnel` | `portainer.cf.lcamaral.com` -> tunnel |
| DNS CNAME | `s3_cf_tunnel` | `s3.cf.lcamaral.com` -> tunnel (MinIO S3 API) |
| DNS CNAME | `minio_cf_tunnel` | `minio.cf.lcamaral.com` -> tunnel (MinIO console) |
| DNS CNAME | `registry_cf_tunnel` | `registry.cf.lcamaral.com` -> tunnel (legacy registry:2) |
| DNS CNAME | `grafana_cf_tunnel` | `grafana.cf.lcamaral.com` -> tunnel (Grafana `root_url`) |
| DNS CNAME | `bologna_tunnel` | `bologna.lcamaral.com` -> tunnel (legacy) |
| DNS CNAME | `root` | `lcamaral.com` -> DreamHost |
| DNS CNAME | `www` | `www.lcamaral.com` -> DreamHost |
| Tunnel | `bologna` | Cloudflare Tunnel to `nginx-rproxy:443` |
| Tunnel Config | `bologna` | Ingress rules (remote-managed) |

### DreamHost

| Resource | Name | Description |
|----------|------|-------------|
| DNS CNAME | `cf_wildcard` | `*.cf.lcamaral.com` -> Cloudflare edge |
| DNS TXT | `circunflexo_spf`, `circunflexo_dkim` | circunflexo.com mail records. **Being moved** to its own root `terraform/circunflexo/`, which is applied but not merged yet. Until that lands, plans here show them as "to add", so apply this root with `-target`. |

## Public hostnames (tunnel ingress)

Every ingress entry routes to `https://nginx-rproxy:443` with `no_tls_verify`
(origin certs are `*.d.lcamaral.com`); the matching vhost picks the request by
`server_name`. The last rule is the `http_status:404` catch-all.

| Hostname | Nginx vhost file (`dockermaster/docker/compose/nginx-rproxy/vhost.d/`) |
|---|---|
| `auth.cf.lcamaral.com` | `auth.cf.lcamaral.com.conf` |
| `login.cf.lcamaral.com` | `login.cf.lcamaral.com.conf` |
| `registry.cf.lcamaral.com` | `registry.cf.lcamaral.com.conf` |
| `portainer.cf.lcamaral.com` | `portainer.d.lcamaral.com.conf` (extra `server_name`) |
| `s3.cf.lcamaral.com`, `minio.cf.lcamaral.com` | `s3.d.lcamaral.com.conf` (extra `server_name`) |
| `grafana.cf.lcamaral.com` | `grafana.d.lcamaral.com.conf` (extra `server_name`) |
| `bologna.cf.lcamaral.com`, `bologna.lcamaral.com` | default server |

## Adding a public hostname

1. Here: add a `cloudflare_dns_record` (proxied CNAME to the tunnel) and an
   ingress entry **above** the 404 catch-all.
2. Nginx: add the `.cf` name to the service's vhost `server_name`, or add a new
   `.conf`. Vhosts are rendered into the three rproxy stacks as Compose
   `configs:` by `terraform/portainer`.
3. Apply `terraform/portainer` for `portainer_stack.reverse_proxy{,_2,_3}`, then
   run `scripts/portainer-redeploy.py reverse-proxy-3`, then `reverse-proxy-2`,
   then `reverse-proxy`, one at a time. The provider does not recreate
   containers on `configs:`-only changes.
4. If the app builds absolute URLs (OAuth callbacks, `root_url`), point it at the
   `.cf` name and allow that name in its Keycloak client.

Apply order: Cloudflare first, then the rproxies, then the app. If the app
switches to the new URL before the tunnel route exists, it breaks.

## Troubleshooting

### `9109 Cannot use the access token from location: <ip>`

The API token (`b40dbcd0…`, account-owned) has **Client IP Address Filtering**
set. The token still verifies as active, but every zone and tunnel call fails
when the request comes from a non-allowed IP. All LAN hosts egress via pfSense
WAN1 (igc0, DHCP), so the filter breaks whenever the ISP changes the WAN1
address. This happened on 2026-10-17 (`136.36.139.5` -> `136.38.130.122`).

- Current WAN1 IP: `ssh pfsense "cat /conf/dyndns_wan*wan1*.cache"`, or
  `curl -s https://api.ipify.org` from any LAN host.
- Fix: in the Cloudflare dashboard (Manage Account -> Account API Tokens ->
  `b40dbcd0…` -> Client IP Address Filtering), add the new IP or remove the
  filter. The token cannot edit itself, and no other Cloudflare credential
  exists, so agents cannot fix this.
- Repeated failed calls trigger `10502 Too many authentication failures`.
  Stop probing for a few minutes.

## Prerequisites

- Terraform >= 1.5.0
- Cloudflare API token in Vault (`secret/homelab/cloudflare`)
- DreamHost API key in Vault (`secret/homelab/dreamhost`)

## Usage

```bash
cd terraform/cloudflare

# Bootstrap Vault access
export VAULT_ADDR="http://vault.d.lcamaral.com"
export VAULT_TOKEN=$(security find-generic-password -w -a lamaral -s vault-root-token)

# Set tokens from Vault
export TF_VAR_cloudflare_api_token=$(vault kv get -field=api_token secret/homelab/cloudflare)
export TF_VAR_dreamhost_api_key=$(vault kv get -field=api_token secret/homelab/dreamhost)

# Init, plan, apply
terraform init
terraform plan
terraform apply
```

## File Structure

```text
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
