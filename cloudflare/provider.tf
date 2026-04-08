terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    dreamhost = {
      source  = "adamantal/dreamhost"
      version = "~> 0.3"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "dreamhost" {
  api_key = var.dreamhost_api_key
}
