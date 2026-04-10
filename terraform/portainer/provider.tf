terraform {
  required_version = ">= 1.5.0"

  required_providers {
    portainer = {
      source  = "portainer/portainer"
      version = "~> 1.11"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "portainer" {
  endpoint        = var.portainer_endpoint
  api_user        = "admin"
  api_password    = var.portainer_password
  skip_ssl_verify = true
}

provider "vault" {
  address         = var.vault_addr
  token           = var.vault_token
  skip_tls_verify = true
}
