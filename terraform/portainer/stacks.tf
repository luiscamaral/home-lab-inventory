# ──────────────────────────────────────────────
# Docker Registry (already deployed via Portainer)
# ──────────────────────────────────────────────
resource "portainer_stack" "docker_registry" {
  name             = "docker-registry"
  endpoint_id      = var.endpoint_id
  deployment_type  = "compose"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/docker-registry.yml")
}

# ──────────────────────────────────────────────
# Cloudflare Tunnel
# Connects homelab to Cloudflare edge via tunnel "bologna"
# Token injected from Vault at apply time
# ──────────────────────────────────────────────
resource "portainer_stack" "cloudflare_tunnel" {
  name             = "cloudflare-tunnel"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/cloudflare-tunnel.yml")

  env {
    name  = "TUNNEL_TOKEN"
    value = data.vault_kv_secret_v2.cloudflare.data["tunnel_token"]
  }
}

# ──────────────────────────────────────────────
# Bind9 DNS
# Authoritative DNS for d.lcamaral.com (internal LAN)
# No secrets needed — config is on NFS volumes
# ──────────────────────────────────────────────
resource "portainer_stack" "bind_dns" {
  name             = "bind-dns"
  endpoint_id      = var.endpoint_id
  deployment_type  = "standalone"
  method           = "string"

  stack_file_content = file("${path.module}/stacks/bind-dns.yml")
}
