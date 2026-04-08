# Cloudflare Tunnel - "bologna"
resource "cloudflare_zero_trust_tunnel_cloudflared" "bologna" {
  account_id = var.account_id
  name       = "bologna"
  config_src = "cloudflare"
}

# Tunnel ingress configuration
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "bologna" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.bologna.id

  config = {
    ingress = [
      {
        hostname = "bologna.lcamaral.com"
        service  = "https://nginx-rproxy:443"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}
