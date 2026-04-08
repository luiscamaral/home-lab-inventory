output "tunnel_id" {
  description = "Bologna tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.bologna.id
}

output "tunnel_name" {
  description = "Bologna tunnel name"
  value       = cloudflare_zero_trust_tunnel_cloudflared.bologna.name
}
