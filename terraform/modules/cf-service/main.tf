# Cloudflare DNS record pointing to tunnel
resource "cloudflare_dns_record" "service" {
  zone_id = var.zone_id
  type    = "CNAME"
  name    = "${var.name}.cf.lcamaral.com"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
