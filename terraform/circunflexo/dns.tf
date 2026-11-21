# ──────────────────────────────────────────────
# circunflexo.com DNS (DreamHost authoritative) — Google Workspace mail
# ──────────────────────────────────────────────
# MX records (ASPMX.L.GOOGLE.COM + ALT1-4) are DreamHost-managed
# (editable=0 via API) and already correct — intentionally NOT managed here.
# Values recommended by Google Admin > Apps > Google Workspace > Gmail.
#
# Note: adamantal/dreamhost records are immutable — any change = replace.
# Import id format: "TYPE|RECORD|VALUE".

resource "dreamhost_dns_record" "spf" {
  record = "circunflexo.com"
  type   = "TXT"
  value  = "v=spf1 include:_spf.google.com ~all"
}

# DKIM generated in Google Admin > Gmail > Authenticate email
# (2048-bit, selector "cfxo"). Public key only — not a secret.
resource "dreamhost_dns_record" "dkim" {
  record = "cfxo._domainkey.circunflexo.com"
  type   = "TXT"
  value  = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtNflsK41sbehVIgqh/HcQtLlTqHZZidyPisuWbWEb1t4t5jaKKyaGvkgy7CA99SeGLyk6ypbRIcoPr1e1tKM4Elvic7I9hn3t88s/5UXaj+6q3s7WEvL3zZw4310ob04IMFOnWOvnHbt1zMoJ/OZ2YaDvLrpPv7XG7A26fkBZuxLS3F0X3rSN/NxKX148wENF9SieMQ4IXlM4w8kKeSlVCtFwaAaDAivmSJcrEDanDJH8YLz630xjCfj5zWAJ0MQv/szWYrbc3myH1snHBTm1Ny8Vj41MMD/3ze5Tra0uOmF+Ff0bEj+u2nR32LxsoceTDnNcNUUSKwKaAgHrIniMQIDAQAB"
}
