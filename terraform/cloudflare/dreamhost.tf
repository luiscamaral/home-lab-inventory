# ──────────────────────────────────────────────
# DreamHost DNS - Cloudflare subdomain delegation
# ──────────────────────────────────────────────
# Wildcard CNAME delegates all *.cf.lcamaral.com
# to Cloudflare's edge via the partial CNAME setup.
# New services only need a Cloudflare DNS record;
# DreamHost routing is handled by this single wildcard.

resource "dreamhost_dns_record" "cf_wildcard" {
  record = "*.cf.lcamaral.com"
  type   = "CNAME"
  value  = "bologna.cf.lcamaral.com.cdn.cloudflare.net."
}
