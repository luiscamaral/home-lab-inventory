# ──────────────────────────────────────────────
# Keycloak realms — `homelab` and `master` (Phase K0)
#
# Imported from the live server on 2026-11-11; the first plan after the
# import is "No changes". Attributes were captured from the admin API
# (`GET /admin/realms/<realm>`) and mapped to keycloak_realm (provider 5.10).
#
# What is deliberately NOT in here yet (the provider doesn't read these back on
# import, so declaring them would show a spurious change, or they are unused):
#   * security_defenses { headers, brute_force_detection }: added by the brute-force
#     change (K2, which turns bruteForceProtected on). The live headers are the
#     Keycloak defaults.
#   * `attributes` (ciba*, parRequestUriLifespan, realmReusableOtpCode: all defaults),
#     internationalization (off).
#   * events: managed by keycloak_realm_events (K4), not by this resource.
#   * require_resident_key in the web_authn policies: deprecated by Keycloak, left at the default.
#
# Durations use the Go format the provider normalizes to (3600 s = "1h0m0s").
# `prevent_destroy` guards both realms against an accidental `terraform destroy`
# (the provider's own terraform_deletion_protection would show as a diff after import).
# Provider config + admin credentials: provider.tf (admin password from Vault).
# ──────────────────────────────────────────────

# homelab realm (imported)
resource "keycloak_realm" "homelab" {
  realm        = "homelab"
  enabled      = true
  display_name = "Homelab"

  registration_allowed           = true
  registration_email_as_username = true
  edit_username_allowed          = false
  reset_password_allowed         = true
  remember_me                    = true
  verify_email                   = true
  login_with_email_allowed       = true
  duplicate_emails_allowed       = false
  ssl_required                   = "none"
  user_managed_access            = false
  organizations_enabled          = false
  admin_permissions_enabled      = false

  browser_flow               = "browser"
  registration_flow          = "registration"
  direct_grant_flow          = "direct grant"
  reset_credentials_flow     = "reset credentials"
  client_authentication_flow = "clients"
  docker_authentication_flow = "docker auth"
  first_broker_login_flow    = "first broker login"

  default_signature_algorithm          = "RS256"
  revoke_refresh_token                 = false
  refresh_token_max_reuse              = 0
  offline_session_max_lifespan_enabled = false

  access_token_lifespan                    = "1h0m0s"
  access_token_lifespan_for_implicit_flow  = "15m0s"
  access_code_lifespan                     = "1m0s"
  access_code_lifespan_login               = "30m0s"
  access_code_lifespan_user_action         = "5m0s"
  action_token_generated_by_admin_lifespan = "12h0m0s"
  action_token_generated_by_user_lifespan  = "5m0s"
  sso_session_idle_timeout                 = "24h0m0s"
  sso_session_max_lifespan                 = "168h0m0s"
  sso_session_idle_timeout_remember_me     = "0"
  sso_session_max_lifespan_remember_me     = "0"
  offline_session_idle_timeout             = "720h0m0s"
  offline_session_max_lifespan             = "1440h0m0s"
  client_session_idle_timeout              = "0"
  client_session_max_lifespan              = "0"
  oauth2_device_code_lifespan              = "10m0s"
  oauth2_device_polling_interval           = 5
  smtp_server {
    host                  = "postfix-relay"
    port                  = "25"
    from                  = "webmaster@lcamaral.com"
    from_display_name     = "Homelab"
    reply_to              = "webmaster@lcamaral.com"
    reply_to_display_name = "Homelab"
    envelope_from         = "webmaster@lcamaral.com"
    ssl                   = false
    starttls              = false
  }

  otp_policy {
    type              = "totp"
    algorithm         = "HmacSHA1"
    digits            = 6
    period            = 30
    initial_counter   = 0
    look_ahead_window = 1
    code_reusable     = false
  }


  web_authn_policy {
    relying_party_entity_name         = "keycloak"
    relying_party_id                  = ""
    signature_algorithms              = ["ES256", "RS256"]
    attestation_conveyance_preference = "not specified"
    authenticator_attachment          = "not specified"
    user_verification_requirement     = "not specified"
    create_timeout                    = 0
    avoid_same_authenticator_register = false
    acceptable_aaguids                = []
  }

  web_authn_passwordless_policy {
    relying_party_entity_name         = "keycloak"
    relying_party_id                  = ""
    signature_algorithms              = ["ES256", "RS256"]
    attestation_conveyance_preference = "not specified"
    authenticator_attachment          = "not specified"
    user_verification_requirement     = "not specified"
    create_timeout                    = 0
    avoid_same_authenticator_register = false
    acceptable_aaguids                = []
  }

  lifecycle {
    prevent_destroy = true
  }
}

# master realm (imported)
resource "keycloak_realm" "master" {
  realm             = "master"
  enabled           = true
  display_name      = "Keycloak"
  display_name_html = "<div class=\"kc-logo-text\"><span>Keycloak</span></div>"

  registration_allowed           = false
  registration_email_as_username = false
  edit_username_allowed          = false
  reset_password_allowed         = false
  remember_me                    = false
  verify_email                   = false
  login_with_email_allowed       = true
  duplicate_emails_allowed       = false
  ssl_required                   = "external"
  user_managed_access            = false
  organizations_enabled          = false
  admin_permissions_enabled      = false

  browser_flow               = "browser"
  registration_flow          = "registration"
  direct_grant_flow          = "direct grant"
  reset_credentials_flow     = "reset credentials"
  client_authentication_flow = "clients"
  docker_authentication_flow = "docker auth"
  first_broker_login_flow    = "first broker login"

  default_signature_algorithm          = "RS256"
  revoke_refresh_token                 = false
  refresh_token_max_reuse              = 0
  offline_session_max_lifespan_enabled = false

  access_token_lifespan                    = "1m0s"
  access_token_lifespan_for_implicit_flow  = "15m0s"
  access_code_lifespan                     = "1m0s"
  access_code_lifespan_login               = "30m0s"
  access_code_lifespan_user_action         = "5m0s"
  action_token_generated_by_admin_lifespan = "12h0m0s"
  action_token_generated_by_user_lifespan  = "5m0s"
  sso_session_idle_timeout                 = "30m0s"
  sso_session_max_lifespan                 = "10h0m0s"
  sso_session_idle_timeout_remember_me     = "0"
  sso_session_max_lifespan_remember_me     = "0"
  offline_session_idle_timeout             = "720h0m0s"
  offline_session_max_lifespan             = "1440h0m0s"
  client_session_idle_timeout              = "0"
  client_session_max_lifespan              = "0"
  oauth2_device_code_lifespan              = "10m0s"
  oauth2_device_polling_interval           = 5
  otp_policy {
    type              = "totp"
    algorithm         = "HmacSHA1"
    digits            = 6
    period            = 30
    initial_counter   = 0
    look_ahead_window = 1
    code_reusable     = false
  }


  web_authn_policy {
    relying_party_entity_name         = "keycloak"
    relying_party_id                  = ""
    signature_algorithms              = ["ES256", "RS256"]
    attestation_conveyance_preference = "not specified"
    authenticator_attachment          = "not specified"
    user_verification_requirement     = "not specified"
    create_timeout                    = 0
    avoid_same_authenticator_register = false
    acceptable_aaguids                = []
  }

  web_authn_passwordless_policy {
    relying_party_entity_name         = "keycloak"
    relying_party_id                  = ""
    signature_algorithms              = ["ES256", "RS256"]
    attestation_conveyance_preference = "not specified"
    authenticator_attachment          = "not specified"
    user_verification_requirement     = "not specified"
    create_timeout                    = 0
    avoid_same_authenticator_register = false
    acceptable_aaguids                = []
  }

  lifecycle {
    prevent_destroy = true
  }
}

# One-time import into the shared state (K0). Safe to keep: Terraform ignores an import block
# whose target is already in state; remove them in a later cleanup.
import {
  to = keycloak_realm.homelab
  id = "homelab"
}

import {
  to = keycloak_realm.master
  id = "master"
}
