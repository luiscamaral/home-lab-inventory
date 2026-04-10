# ──────────────────────────────────────────────
# Keycloak OIDC Identity Provider
# ──────────────────────────────────────────────
resource "minio_iam_idp_openid" "keycloak" {
  name          = "keycloak"
  config_url    = "${var.keycloak_url}/realms/homelab/.well-known/openid-configuration"
  client_id     = "minio"
  client_secret = data.vault_kv_secret_v2.keycloak_clients.data["minio_client_secret"]
  display_name  = "Login with Keycloak"
  claim_name    = "policy"
  scopes        = "openid,email"
  enable        = true
}
