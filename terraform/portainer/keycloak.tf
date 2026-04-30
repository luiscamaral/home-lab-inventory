# ──────────────────────────────────────────────
# Keycloak — IaC-managed OIDC clients (Gap 4)
#
# Scoped management: Terraform only owns the client resources declared
# here. Realms, users, groups, and any other clients in the homelab
# realm remain untouched. To add a new client to TF management, declare
# it here and `terraform import` it into state.
#
# Provider config + admin creds live in provider.tf; the password comes
# from Vault via the existing data.vault_kv_secret_v2.keycloak data
# source (admin_password field).
# ──────────────────────────────────────────────

data "keycloak_realm" "homelab" {
  realm = "homelab"
}

# Grafana OIDC SSO client. Created originally via the Keycloak admin
# UI on 2026-04-29 and imported into TF state with:
#   terraform import keycloak_openid_client.grafana \
#     homelab/cf78e9f0-ac19-4a54-9de9-df987801f26b
#
# Client secret intentionally NOT set here — Vault is canonical for
# the grafana stack's `GRAFANA_OIDC_CLIENT_SECRET` env var, and
# Keycloak's UI rotation flow updates Vault out-of-band. Keeping the
# secret out of TF state avoids a circular write loop and keeps it
# human-rotatable without a `terraform apply`.
resource "keycloak_openid_client" "grafana" {
  realm_id            = data.keycloak_realm.homelab.id
  client_id           = "grafana"
  name                = "Grafana"
  description         = "Homelab Grafana — Phase 4 monitoring dashboards"
  enabled             = true
  access_type         = "CONFIDENTIAL"

  root_url  = "https://grafana.d.lcamaral.com"
  admin_url = "https://grafana.d.lcamaral.com"
  base_url  = "/"

  valid_redirect_uris = [
    "https://grafana.d.lcamaral.com/login/generic_oauth",
  ]
  web_origins = [
    "https://grafana.d.lcamaral.com",
  ]

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  access_token_lifespan = "300"

  # Match the live state captured at import (provider default is true,
  # but Grafana's OIDC integration handles re-auth on its own without
  # needing the refresh-token grant).
  use_refresh_tokens = false

  # The keycloak provider treats `client_secret` as a write-only
  # attribute when omitted: the resource is content-addressed by the
  # other fields and TF won't drift on the secret value. Rotation
  # happens via Keycloak UI → Vault out-of-band.
}
