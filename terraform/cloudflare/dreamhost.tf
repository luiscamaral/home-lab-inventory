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

# ──────────────────────────────────────────────
# DreamHost DNS - circunflexo.com (Google Workspace mail)
# ──────────────────────────────────────────────
# MX records (ASPMX.L.GOOGLE.COM + ALT1-4) are DreamHost-managed
# (non-editable via API) and already correct — not managed here.
# Values recommended by Google Admin > Apps > Gmail > Setup.

resource "dreamhost_dns_record" "circunflexo_spf" {
  record = "circunflexo.com"
  type   = "TXT"
  value  = "v=spf1 include:_spf.google.com ~all"
}

# DKIM: generated in Google Admin > Apps > Google Workspace > Gmail >
# Authenticate email (2048-bit, selector "cfxo"). After the record
# resolves publicly, click "Start authentication" in Google Admin.
# Public key only — not a secret.
resource "dreamhost_dns_record" "circunflexo_dkim" {
  record = "cfxo._domainkey.circunflexo.com"
  type   = "TXT"
  value  = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtNflsK41sbehVIgqh/HcQtLlTqHZZidyPisuWbWEb1t4t5jaKKyaGvkgy7CA99SeGLyk6ypbRIcoPr1e1tKM4Elvic7I9hn3t88s/5UXaj+6q3s7WEvL3zZw4310ob04IMFOnWOvnHbt1zMoJ/OZ2YaDvLrpPv7XG7A26fkBZuxLS3F0X3rSN/NxKX148wENF9SieMQ4IXlM4w8kKeSlVCtFwaAaDAivmSJcrEDanDJH8YLz630xjCfj5zWAJ0MQv/szWYrbc3myH1snHBTm1Ny8Vj41MMD/3ze5Tra0uOmF+Ff0bEj+u2nR32LxsoceTDnNcNUUSKwKaAgHrIniMQIDAQAB"
}
