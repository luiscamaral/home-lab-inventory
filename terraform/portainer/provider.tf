terraform {
  required_version = ">= 1.5.0"

  required_providers {
    portainer = {
      source  = "portainer/portainer"
      version = "~> 1.11"
    }
  }
}

provider "portainer" {
  endpoint        = "https://portainer.d.lcamaral.com"
  api_user        = "admin"
  api_password    = var.portainer_password
  skip_ssl_verify = true
}
