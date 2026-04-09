output "stacks" {
  description = "Managed Portainer stacks"
  value = {
    docker_registry  = portainer_stack.docker_registry.name
    cloudflare_tunnel = portainer_stack.cloudflare_tunnel.name
    bind_dns          = portainer_stack.bind_dns.name
  }
}
