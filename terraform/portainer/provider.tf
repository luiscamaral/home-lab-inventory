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
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
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

# Keycloak provider — used scoped, only manages the OIDC clients we
# explicitly declare (e.g. `grafana`). The rest of the realm (users,
# groups, identity providers, the master realm) stays untouched because
# it isn't in terraform state. Admin creds sourced from Vault.
provider "keycloak" {
  client_id = "admin-cli"
  username  = "admin"
  password  = data.vault_kv_secret_v2.keycloak.data["admin_password"]
  url       = "https://keycloak.d.lcamaral.com"
  realm     = "master"
}
