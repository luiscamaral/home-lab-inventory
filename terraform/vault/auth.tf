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
# AppRole Auth — CI/CD machine access
# ──────────────────────────────────────────────
resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole auth for CI/CD pipelines"
}

# premium-sre-cell's CI reads exactly one secret (its MinIO TF-state
# credential) and nothing else. Every layer is single-use/short-lived:
# secret_id dies after one login or 10min, the resulting token dies after
# one read or 5min. A stored static secret_id only survives ONE pipeline
# run under these settings — the CI job must mint a fresh secret_id per
# run (via a separate, narrower bootstrap credential scoped to nothing but
# `auth/approle/role/premium-sre-cell-ci/secret-id`), not reuse a stored one.
resource "vault_approle_auth_backend_role" "premium_sre_cell_ci" {
  backend        = vault_auth_backend.approle.path
  role_name      = "premium-sre-cell-ci"
  token_policies = [vault_policy.tfstate_premium_sre_cell_reader.name]

  bind_secret_id     = true
  secret_id_ttl      = 600
  secret_id_num_uses = 1

  token_ttl      = 300
  token_max_ttl  = 600
  token_num_uses = 1
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
