output "environments" {
  description = "Portainer environment IDs"
  value = {
    dockermaster  = var.endpoint_id
    dockerserver1 = portainer_environment.ds1.id
    dockerserver2 = portainer_environment.ds2.id
  }
}

output "registries" {
  description = "Managed Portainer registries"
  value = {
    homelab_registry = portainer_registry.homelab_registry.name
  }
}

output "stacks" {
  description = "Managed Portainer stacks"
  value = {
    docker_registry   = portainer_stack.docker_registry.name
    cloudflare_tunnel   = portainer_stack.cloudflare_tunnel.name
    cloudflare_tunnel_2 = portainer_stack.cloudflare_tunnel_2.name
    bind_dns          = portainer_stack.bind_dns.name
    reverse_proxy     = portainer_stack.reverse_proxy.name
    reverse_proxy_2   = portainer_stack.reverse_proxy_2.name
    vault             = portainer_stack.vault.name
    vault_3           = portainer_stack.vault_3.name
    twingate_a        = portainer_stack.twingate_a.name
    twingate_b        = portainer_stack.twingate_b.name
    calibre           = portainer_stack.calibre.name
    github_runner     = portainer_stack.github_runner.name
    rustdesk          = portainer_stack.rustdesk.name
    rundeck           = portainer_stack.rundeck.name
    prometheus        = portainer_stack.prometheus.name
    watchtower        = portainer_stack.watchtower.name
    minio             = portainer_stack.minio.name
    minio_2           = portainer_stack.minio_2.name
    freeswitch        = portainer_stack.freeswitch.name
    keycloak          = portainer_stack.keycloak.name
    keycloak_2        = portainer_stack.keycloak_2.name
    keycloak_db_0     = portainer_stack.keycloak_db_0.name
    keycloak_db_1     = portainer_stack.keycloak_db_1.name
    postfix_relay     = portainer_stack.postfix_relay.name
    homelab_portal    = portainer_stack.homelab_portal.name
    homelab_portal_2  = portainer_stack.homelab_portal_2.name
  }
}
