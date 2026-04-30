# ──────────────────────────────────────────────
# Secret Engines
# ──────────────────────────────────────────────
import {
  to = vault_mount.secret
  id = "secret"
}

import {
  to = vault_mount.ssh
  id = "ssh"
}

import {
  to = vault_mount.kv
  id = "kv"
}

# ──────────────────────────────────────────────
# Policies  (I3)
# ──────────────────────────────────────────────
import {
  to = vault_policy.dockermaster_home_lab_inventory
  id = "dockermaster-home-lab-inventory"
}

import {
  to = vault_policy.dockermaster_home_lab_inventory_ro
  id = "dockermaster-home-lab-inventory-ro"
}

import {
  to = vault_policy.kubernetes_secrets
  id = "kubernetes-secrets"
}

import {
  to = vault_policy.kv_app_readonly
  id = "kv-app-readonly"
}

import {
  to = vault_policy.prometheus_scrape
  id = "prometheus-scrape"
}

import {
  to = vault_policy.superuser
  id = "superuser"
}

import {
  to = vault_policy.thanos_storage
  id = "thanos-storage"
}

# ──────────────────────────────────────────────
# Auth Backends  (I3)
# ──────────────────────────────────────────────
import {
  to = vault_github_auth_backend.github
  id = "github"
}

import {
  to = vault_auth_backend.kubernetes
  id = "kubernetes"
}

import {
  to = vault_auth_backend.userpass
  id = "userpass"
}

# ──────────────────────────────────────────────
# GitHub Team Mappings  (I3)
# ──────────────────────────────────────────────
import {
  to = vault_github_team.lamaral_home_lab
  id = "auth/github/map/teams/lamaral-home-lab"
}

import {
  to = vault_github_team.project_x_devs
  id = "auth/github/map/teams/project-x-devs"
}

# ──────────────────────────────────────────────
# Userpass Users  (I3)
# ──────────────────────────────────────────────
import {
  to = vault_generic_endpoint.userpass_lamaral
  id = "auth/userpass/users/lamaral"
}
