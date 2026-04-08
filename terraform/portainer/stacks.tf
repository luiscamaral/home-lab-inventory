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
