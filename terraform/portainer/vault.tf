# ──────────────────────────────────────────────
# Vault Data Sources
# Read secrets at apply time for stack env injection
# ──────────────────────────────────────────────

data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret"
  name  = "homelab/cloudflare"
}

data "vault_kv_secret_v2" "twingate_sepia_hornet" {
  mount = "secret"
  name  = "homelab/twingate/sepia-hornet"
}

data "vault_kv_secret_v2" "twingate_golden_mussel" {
  mount = "secret"
  name  = "homelab/twingate/golden-mussel"
}

# Twingate connector C — "fresh-marmoset" on NAS (C1 in audit
# 2026-04-30). Migrated from Synology Container Manager where the
# tokens were sitting plaintext on the NAS filesystem.
data "vault_kv_secret_v2" "twingate_fresh_marmoset" {
  mount = "secret"
  name  = "homelab/twingate/fresh-marmoset"
}

data "vault_kv_secret_v2" "vault" {
  mount = "secret"
  name  = "homelab/vault"
}

data "vault_kv_secret_v2" "calibre" {
  mount = "secret"
  name  = "homelab/calibre"
}

data "vault_kv_secret_v2" "github_runner" {
  mount = "secret"
  name  = "homelab/github-runner"
}

data "vault_kv_secret_v2" "rundeck" {
  mount = "secret"
  name  = "homelab/rundeck"
  # Phase 3f — Prometheus scrapes Rundeck /metrics with a bearer-token
  # API key kept in this same secret under the new field `api_token`
  # (placeholder until orchestrator populates from the Rundeck UI).
}

data "vault_kv_secret_v2" "watchtower" {
  mount = "secret"
  name  = "homelab/watchtower"
}

data "vault_kv_secret_v2" "minio" {
  mount = "secret"
  name  = "homelab/minio"
}

data "vault_kv_secret_v2" "freeswitch" {
  mount = "secret"
  name  = "homelab/freeswitch"
}

data "vault_kv_secret_v2" "keycloak" {
  mount = "secret"
  name  = "homelab/keycloak"
}

data "vault_kv_secret_v2" "keycloak_clients" {
  mount = "secret"
  name  = "homelab/keycloak/clients"
}

# Phase 4 — Grafana admin password (for static admin user; bypass for
# OIDC SSO failures). Bootstrap-only — once Grafana's internal DB has
# additional admin users, this can rotate without disruption.
data "vault_kv_secret_v2" "grafana_admin" {
  mount = "secret"
  name  = "homelab/grafana/admin"
}

# Phase 4 — Grafana OIDC client credentials. Matches the Keycloak
# `grafana` client in the `homelab` realm. As of Gap 4 (2026-04-29),
# the client itself IS Terraform-managed via the keycloak/keycloak
# provider (see keycloak.tf) — only the client_secret rotation is
# kept out of TF state for now (Vault remains source of truth so the
# grafana stack and Keycloak stay in sync without a circular dep).
data "vault_kv_secret_v2" "grafana_oidc" {
  mount = "secret"
  name  = "homelab/grafana/oidc"
}

data "vault_kv_secret_v2" "registry" {
  mount = "secret"
  name  = "homelab/registry"
}

data "vault_kv_secret_v2" "smtp" {
  mount = "secret"
  name  = "homelab/smtp"
}

data "vault_kv_secret_v2" "portal" {
  mount = "secret"
  name  = "homelab/portal"
}

data "vault_kv_secret_v2" "pihole" {
  mount = "secret"
  name  = "homelab/pihole"
}

# Thanos S3 service-account credentials (MinIO svcacct scoped to the
# `thanos` bucket). Consumed by both prometheus-1's sidecar (Phase 1)
# and prometheus-2's sidecar (Phase 2). The two sidecars use different
# objstore endpoints (LAN vs nginx-rproxy) but the same access keys.
data "vault_kv_secret_v2" "thanos" {
  mount = "secret"
  name  = "homelab/thanos/s3"
}

# Alertmanager SMTP routing — recipient address read from Vault so it can
# rotate without a code change. Outbound SMTP itself flows through the
# existing postfix-relay on dockermaster; this secret only carries the
# destination email and any per-route overrides we add later.
# Fields: to_address
data "vault_kv_secret_v2" "alertmanager_smtp" {
  mount = "secret"
  name  = "homelab/alertmanager/smtp"
}

# Proxmox API token for pve-exporter (Phase 3c). The exporter uses an
# unprivileged read-only token `prometheus@pam!metrics` to walk the PVE
# API. Fields: token_id (= prometheus@pam!metrics), token_secret.
data "vault_kv_secret_v2" "proxmox_api_token" {
  mount = "secret"
  name  = "homelab/proxmox/api_token"
}

# Home Assistant long-lived access token used by Prometheus to scrape
# /api/prometheus on ha.home.lcamaral.com (Phase 3d). Dedicated user
# `prometheus-scrape` per DECISIONS.md Q8. Field: `token` (raw JWT).
#
# SECURITY NOTE: this token is rendered into the prometheus stack via
# docker `configs:` (i.e. baked into the compose body that Portainer
# stores). Acceptable for the homelab blast-radius and consistent with
# how other secrets (twingate, github-runner, freeswitch) are handled.
# A future hardening step would be a Vault-agent sidecar templating the
# token to a tmpfs file at runtime — see TODO in prometheus templates.
data "vault_kv_secret_v2" "ha_metrics_token" {
  mount = "secret"
  name  = "homelab/home-assistant/metrics_token"
}

# MinIO Prometheus bearer JWT (Phase 3a — minio scrape). Generated via
# `mc admin prometheus generate <alias>` against the dedicated `metrics`
# svcacct (access_key in secret/homelab/minio/metrics_svcacct). The same
# svcacct credentials are present on m1 and m2 because root-owned
# svcaccts do NOT replicate via MinIO site-replication — the svcacct was
# created with identical access/secret keys on both deployments so a
# single JWT is valid against both. The JWT is signed with the svcacct
# secret-key; long-lived (year ~2126 exp). Rotate by regenerating
# against the svcacct and `vault kv put`-ing this path.
#
# SECURITY NOTE: rendered into the prometheus stacks via docker
# `configs:`, same caveat as ha_metrics_token above.
data "vault_kv_secret_v2" "minio_metrics_jwt" {
  mount = "secret"
  name  = "homelab/minio/metrics_jwt"
}
