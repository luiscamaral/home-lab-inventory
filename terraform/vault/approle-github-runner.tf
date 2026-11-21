# ──────────────────────────────────────────────
# AppRole for the GitHub Actions runner
# ──────────────────────────────────────────────
# The self-hosted runner logs in with a role_id + secret_id (stored as
# GitHub Actions secrets VAULT_ROLE_ID and VAULT_SECRET_ID). The short-lived
# token can read only the Portainer admin password, which the deploy and
# rollback workflows use to drive the Portainer API. Least privilege: no
# other path is reachable.

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole auth for the GitHub Actions runner"
}

resource "vault_policy" "github_runner_portainer" {
  name = "github-runner-portainer"

  policy = <<-EOT
    path "secret/data/homelab/portainer" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "github_runner" {
  backend        = vault_auth_backend.approle.path
  role_name      = "github-runner"
  token_policies = [vault_policy.github_runner_portainer.name]

  # A deploy or rollback run finishes in well under 15 minutes.
  token_ttl     = 900
  token_max_ttl = 900

  # The secret_id never expires on its own; rotation is manual by
  # generating a new one and updating the GitHub secret.
  secret_id_ttl = 0
}
