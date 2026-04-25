# ──────────────────────────────────────────────
# Zone
# ──────────────────────────────────────────────
import {
  to = cloudflare_zone.lcamaral_com
  id = "d91929b42a245625bebb527e5fd2e020"
}

import {
  to = cloudflare_zone_dnssec.lcamaral_com
  id = "d91929b42a245625bebb527e5fd2e020"
}

# ──────────────────────────────────────────────
# DNS Records
# ──────────────────────────────────────────────
import {
  to = cloudflare_dns_record.bologna_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/2ff3bbf3e5c01afa565eb085a2a2ca37"
}

import {
  to = cloudflare_dns_record.registry_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/b930bcda2f991dd63f5ae85964d5b5c4"
}

import {
  to = cloudflare_dns_record.bologna_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/0b078b9289609a983116061d279c12c2"
}

import {
  to = cloudflare_dns_record.root
  id = "d91929b42a245625bebb527e5fd2e020/5d4808d545d2ba2055e66a39513f75d9"
}

import {
  to = cloudflare_dns_record.www
  id = "d91929b42a245625bebb527e5fd2e020/fc65d8a0c4316934a39c65342c1870b6"
}

import {
  to = cloudflare_dns_record.auth_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/3093ea96e589e6f383fe1a8a0b4a2d21"
}

import {
  to = cloudflare_dns_record.login_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/66d2660ab04b419c601914d1372a389d"
}

import {
  to = cloudflare_dns_record.portainer_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/82638815d06761fddc205fe4b2090292"
}

import {
  to = cloudflare_dns_record.s3_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/c2c6eec78e80e84532343f4fc3da26f1"
}

import {
  to = cloudflare_dns_record.minio_cf_tunnel
  id = "d91929b42a245625bebb527e5fd2e020/e3f66706109de276de89aec2ebbca1d0"
}

# ──────────────────────────────────────────────
# DreamHost DNS
# ──────────────────────────────────────────────
# Note: adamantal/dreamhost provider v0.3.2 import id format is TYPE|RECORD|VALUE
# (pipe-separated, type first), NOT the documented record;type;value pattern.
import {
  to = dreamhost_dns_record.cf_wildcard
  id = "CNAME|*.cf.lcamaral.com|bologna.cf.lcamaral.com.cdn.cloudflare.net."
}

# ──────────────────────────────────────────────
# Tunnel
# ──────────────────────────────────────────────
import {
  to = cloudflare_zero_trust_tunnel_cloudflared.bologna
  id = "13538d3dbd6b9cd04da9359142bb8d10/eb4461ec-689f-4f8a-98f1-321cb246bb65"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.bologna
  id = "13538d3dbd6b9cd04da9359142bb8d10/eb4461ec-689f-4f8a-98f1-321cb246bb65"
}
