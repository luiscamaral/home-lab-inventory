# ──────────────────────────────────────────────
# circunflexo.com — independent domain, DreamHost-only root
# ──────────────────────────────────────────────
# Deliberately separate from terraform/cloudflare/ (which owns lcamaral.com's
# Cloudflare zone + the *.cf.lcamaral.com delegation). This root needs only
# the DreamHost API key — no Cloudflare credentials.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    dreamhost = {
      source  = "adamantal/dreamhost"
      version = "~> 0.3"
    }
  }
}

provider "dreamhost" {
  api_key = var.dreamhost_api_key
}
