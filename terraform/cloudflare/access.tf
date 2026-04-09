# ──────────────────────────────────────────────
# Zero Trust: Keycloak Identity Provider
# ──────────────────────────────────────────────
resource "cloudflare_zero_trust_access_identity_provider" "keycloak" {
  account_id = var.account_id
  name       = "Keycloak Homelab"
  type       = "oidc"

  config = {
    client_id     = "cloudflare-access"
    client_secret = var.keycloak_client_secret
    auth_url      = "https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/auth"
    token_url     = "https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/token"
    certs_url     = "https://auth.cf.lcamaral.com/realms/homelab/protocol/openid-connect/certs"
    claims        = ["email", "preferred_username", "name"]
    scopes        = ["openid", "email", "profile"]
  }
}

# ──────────────────────────────────────────────
# Access Application: Portainer
# ──────────────────────────────────────────────
resource "cloudflare_zero_trust_access_application" "portainer" {
  zone_id                   = var.zone_id
  name                      = "Portainer"
  domain                    = "portainer.cf.lcamaral.com"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]

  policies = [{
    name       = "Allow homelab users"
    decision   = "allow"
    precedence = 1
    include = [{
      login_method = {
        id = cloudflare_zero_trust_access_identity_provider.keycloak.id
      }
    }]
  }]
}

# ──────────────────────────────────────────────
# Access Application: MinIO Console
# ──────────────────────────────────────────────
resource "cloudflare_zero_trust_access_application" "minio_console" {
  zone_id                   = var.zone_id
  name                      = "MinIO Console"
  domain                    = "minio.cf.lcamaral.com"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]

  policies = [{
    name       = "Allow homelab users"
    decision   = "allow"
    precedence = 1
    include = [{
      login_method = {
        id = cloudflare_zero_trust_access_identity_provider.keycloak.id
      }
    }]
  }]
}

# ──────────────────────────────────────────────
# Access Application: Docker Registry
# ──────────────────────────────────────────────
resource "cloudflare_zero_trust_access_application" "registry" {
  zone_id                   = var.zone_id
  name                      = "Docker Registry"
  domain                    = "registry.cf.lcamaral.com"
  type                      = "self_hosted"
  session_duration          = "720h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]

  policies = [{
    name       = "Allow homelab users"
    decision   = "allow"
    precedence = 1
    include = [{
      login_method = {
        id = cloudflare_zero_trust_access_identity_provider.keycloak.id
      }
    }]
  }]
}

# ──────────────────────────────────────────────
# Access Application: S3 API
# ──────────────────────────────────────────────
resource "cloudflare_zero_trust_access_application" "s3_api" {
  zone_id                   = var.zone_id
  name                      = "MinIO S3 API"
  domain                    = "s3.cf.lcamaral.com"
  type                      = "self_hosted"
  session_duration          = "720h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]

  policies = [{
    name       = "Allow homelab users"
    decision   = "allow"
    precedence = 1
    include = [{
      login_method = {
        id = cloudflare_zero_trust_access_identity_provider.keycloak.id
      }
    }]
  }]
}
