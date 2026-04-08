output "zone_id" {
  description = "lcamaral.com zone ID"
  value       = cloudflare_zone.lcamaral_com.id
}

output "zone_status" {
  description = "lcamaral.com zone status"
  value       = cloudflare_zone.lcamaral_com.status
}

output "tunnel_id" {
  description = "Bologna tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.bologna.id
}

output "tunnel_name" {
  description = "Bologna tunnel name"
  value       = cloudflare_zero_trust_tunnel_cloudflared.bologna.name
}

output "dns_records" {
  description = "DNS record summary"
  value = {
    bologna = cloudflare_dns_record.bologna_tunnel.name
    root    = cloudflare_dns_record.root.name
    www     = cloudflare_dns_record.www.name
  }
}
