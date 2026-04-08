output "stacks" {
  description = "Managed Portainer stacks"
  value = {
    docker_registry = portainer_stack.docker_registry.name
  }
}
