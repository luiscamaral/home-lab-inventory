# cf-service Module

Creates a Cloudflare DNS record for a service behind the `*.cf.lcamaral.com` tunnel.

## Usage

```hcl
module "registry" {
  source    = "../modules/cf-service"
  name      = "registry"
  zone_id   = cloudflare_zone.lcamaral_com.id
  tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.bologna.id
}
```

The tunnel ingress and nginx vhost must be configured separately.

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| `name` | Service name (becomes `<name>.cf.lcamaral.com`) | `string` | yes |
| `zone_id` | Cloudflare zone ID | `string` | yes |
| `tunnel_id` | Cloudflare tunnel ID | `string` | yes |

## Outputs

| Name | Description |
|------|-------------|
| `fqdn` | Full domain name |
| `dns_record_id` | Cloudflare DNS record ID |
