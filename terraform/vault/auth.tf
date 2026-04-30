# ──────────────────────────────────────────────
# Auth Methods  (I3 – auth & policy audit)
# ──────────────────────────────────────────────
#
# 4 auth methods discovered in Vault:
#   github/      – GitHub org login (tbiot2)
#   kubernetes/  – UNCONFIGURED — no host, cert, or roles
#   token/       – built-in (not managed by Terraform)
#   userpass/    – local user/password auth
#
# DANGLING REFERENCES found during audit:
#   - github team "lamaral-home-lab" maps to policy
#     "project-dockermaster-home-lab-inventory" which does NOT exist.
#   - userpass user "lamaral" references policies app-developer,
#     db-reader, pki-user — none of which exist. Only "superuser" is valid.

# ──────────────────────────────────────────────
# GitHub Auth
# ──────────────────────────────────────────────
resource "vault_github_auth_backend" "github" {
  organization = "tbiot2"
  path         = "github"
  description  = "GitHub auth – org tbiot2"
}

# Team → policy mappings
# DANGLING: policy "project-dockermaster-home-lab-inventory" does not exist.
#           Likely intended to be "dockermaster-home-lab-inventory".
resource "vault_github_team" "lamaral_home_lab" {
  backend  = vault_github_auth_backend.github.id
  team     = "lamaral-home-lab"
  policies = ["project-dockermaster-home-lab-inventory"]
}

resource "vault_github_team" "project_x_devs" {
  backend  = vault_github_auth_backend.github.id
  team     = "project-x-devs"
  policies = ["dockermaster-home-lab-inventory"]
}

# ──────────────────────────────────────────────
# Kubernetes Auth  (ZOMBIE — unconfigured)
# ──────────────────────────────────────────────
# This auth backend was enabled but never configured:
#   - No kubernetes_host set
#   - No CA cert or token reviewer JWT
#   - No roles defined
# Kept in Terraform for audit trail. Consider removing after review.
resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = "kubernetes"
  description = "Kubernetes auth (unconfigured)"
}

# ──────────────────────────────────────────────
# Userpass Auth
# ──────────────────────────────────────────────
resource "vault_auth_backend" "userpass" {
  type        = "userpass"
  path        = "userpass"
  description = "Username/password auth"
}

# User: lamaral
# Assigned policies: app-developer, db-reader, pki-user, superuser
# WARNING: 3 of 4 policies are DANGLING (do not exist in Vault):
#   - app-developer  ← does not exist
#   - db-reader      ← does not exist
#   - pki-user       ← does not exist
#   - superuser      ← EXISTS
#
# The user is managed via vault_generic_endpoint because the Vault
# provider has no dedicated userpass-user resource. disable_read
# prevents Terraform from reading back the password, and
# disable_delete avoids removing the user on resource destroy.
resource "vault_generic_endpoint" "userpass_lamaral" {
  path           = "auth/userpass/users/lamaral"
  disable_read   = true
  disable_delete = true

  data_json = jsonencode({
    policies = "app-developer,db-reader,pki-user,superuser"
  })

  lifecycle {
    ignore_changes = [data_json]
  }

  depends_on = [vault_auth_backend.userpass]
}
