# ──────────────────────────────────────────────
# Zone
# ──────────────────────────────────────────────
resource "cloudflare_zone" "lcamaral_com" {
  name   = "lcamaral.com"
  paused = false
  type   = "partial"

  account = {
    id = var.account_id
  }
}

resource "cloudflare_zone_dnssec" "lcamaral_com" {
  zone_id = cloudflare_zone.lcamaral_com.id
  status  = "disabled"
}

# ──────────────────────────────────────────────
# DNS Records
# ──────────────────────────────────────────────

# Tunnel CNAME: bologna.cf.lcamaral.com -> tunnel (primary)
resource "cloudflare_dns_record" "bologna_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "bologna.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Portainer: portainer.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "portainer_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "portainer.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Keycloak auth: auth.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "auth_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "auth.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# MinIO S3 API: s3.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "s3_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "s3.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# MinIO Console: minio.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "minio_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "minio.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Docker registry: registry.cf.lcamaral.com -> tunnel
resource "cloudflare_dns_record" "registry_cf_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "registry.cf.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Tunnel CNAME: bologna.lcamaral.com -> tunnel (legacy)
resource "cloudflare_dns_record" "bologna_tunnel" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "bologna.lcamaral.com"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bologna.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Root domain: lcamaral.com -> DreamHost
resource "cloudflare_dns_record" "root" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "lcamaral.com"
  content = "resolve-to.www.lcamaral.com"
  proxied = true
  ttl     = 1
}

# WWW: www.lcamaral.com -> DreamHost
resource "cloudflare_dns_record" "www" {
  zone_id = cloudflare_zone.lcamaral_com.id
  type    = "CNAME"
  name    = "www.lcamaral.com"
  content = "resolve-to.www.lcamaral.com"
  proxied = true
  ttl     = 1
}

# ──────────────────────────────────────────────
# Tunnel
# ──────────────────────────────────────────────
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
        hostname = "auth.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "bologna.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "registry.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "portainer.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "s3.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "minio.cf.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        hostname = "bologna.lcamaral.com"
        service  = "https://nginx-rproxy:443"
        origin_request = {
          no_tls_verify = true
        }
      },
      {
        service = "http_status:404"
      }
    ]
  }
}
