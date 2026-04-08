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
