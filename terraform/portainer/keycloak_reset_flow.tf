# ──────────────────────────────────────────────
# "Forgot password" only for users with a second factor (Phase K3)
#
# Replaces the built-in `reset credentials` flow in the homelab realm:
#
#   Choose User                                   REQUIRED
#   has-otp   (CONDITIONAL)
#       Condition - user configured               REQUIRED   true when the user has OTP configured
#       OTP Form                                  REQUIRED   the user must enter a valid TOTP code
#   no-otp    (CONDITIONAL)
#       Condition - sub-flow executed             REQUIRED   true when `has-otp` was NOT executed
#       Deny access                               REQUIRED   error page, nothing is sent
#   Send Reset Email                              REQUIRED
#   Reset Password                                REQUIRED
#
# A user without OTP (and an unknown user name) is denied before any email is sent; a user with OTP must
# pass the OTP form first. Admins reset passwords for users without OTP. The built-in flow stays in the
# realm, unused, so the rollback is to bind it again (`reset_credentials_flow` in keycloak_realms.tf).
#
# The realm id comes from the data source (keycloak.tf), not from keycloak_realm.homelab, because the
# realm resource references this flow's alias for its binding (a cycle otherwise).
# Executions are ordered by creation, so each one depends on the previous one.
# ──────────────────────────────────────────────
resource "keycloak_authentication_flow" "reset_credentials_otp" {
  realm_id    = data.keycloak_realm.homelab.id
  alias       = "reset credentials otp"
  description = "Forgot password: OTP required before the reset email; users without OTP are denied"
}

resource "keycloak_authentication_execution" "reset_choose_user" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.reset_credentials_otp.alias
  authenticator     = "reset-credentials-choose-user"
  requirement       = "REQUIRED"
}

# --- has-otp: users with a configured OTP must enter a code
resource "keycloak_authentication_subflow" "reset_has_otp" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.reset_credentials_otp.alias
  alias             = "reset - has otp"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"

  depends_on = [keycloak_authentication_execution.reset_choose_user]
}

resource "keycloak_authentication_execution" "reset_has_otp_condition" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.reset_has_otp.alias
  authenticator     = "conditional-user-configured"
  requirement       = "REQUIRED"
}

resource "keycloak_authentication_execution" "reset_has_otp_form" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.reset_has_otp.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution.reset_has_otp_condition]
}

# --- no-otp: everyone who did not go through has-otp is denied
resource "keycloak_authentication_subflow" "reset_no_otp" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.reset_credentials_otp.alias
  alias             = "reset - no otp"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"

  depends_on = [keycloak_authentication_execution.reset_has_otp_form]
}

resource "keycloak_authentication_execution" "reset_no_otp_condition" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.reset_no_otp.alias
  authenticator     = "conditional-sub-flow-executed"
  requirement       = "REQUIRED"
}

resource "keycloak_authentication_execution_config" "reset_no_otp_condition" {
  realm_id     = data.keycloak_realm.homelab.id
  execution_id = keycloak_authentication_execution.reset_no_otp_condition.id
  alias        = "reset - has otp not executed"
  config = {
    flow_to_check = keycloak_authentication_subflow.reset_has_otp.alias
    check_result  = "not-executed"
  }
}

resource "keycloak_authentication_execution" "reset_no_otp_deny" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.reset_no_otp.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution_config.reset_no_otp_condition]
}

resource "keycloak_authentication_execution_config" "reset_no_otp_deny" {
  realm_id     = data.keycloak_realm.homelab.id
  execution_id = keycloak_authentication_execution.reset_no_otp_deny.id
  alias        = "reset - deny without otp"
  config = {
    denyErrorMessage = "Password reset by email needs two-factor authentication on the account. Ask the administrator."
  }
}

# --- the actual reset
resource "keycloak_authentication_execution" "reset_send_email" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.reset_credentials_otp.alias
  authenticator     = "reset-credential-email"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution_config.reset_no_otp_deny]
}

resource "keycloak_authentication_execution" "reset_password" {
  realm_id          = data.keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.reset_credentials_otp.alias
  authenticator     = "reset-password"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution.reset_send_email]
}
