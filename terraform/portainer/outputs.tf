output "stacks" {
  description = "Managed Portainer stacks"
  value = {
    docker_registry   = portainer_stack.docker_registry.name
    cloudflare_tunnel = portainer_stack.cloudflare_tunnel.name
    bind_dns          = portainer_stack.bind_dns.name
    reverse_proxy     = portainer_stack.reverse_proxy.name
    vault             = portainer_stack.vault.name
    twingate_a        = portainer_stack.twingate_a.name
    twingate_b        = portainer_stack.twingate_b.name
    calibre           = portainer_stack.calibre.name
    github_runner     = portainer_stack.github_runner.name
    rustdesk          = portainer_stack.rustdesk.name
    rundeck           = portainer_stack.rundeck.name
    prometheus        = portainer_stack.prometheus.name
    watchtower        = portainer_stack.watchtower.name
    minio             = portainer_stack.minio.name
    ollama            = portainer_stack.ollama.name
    chisel            = portainer_stack.chisel.name
    freeswitch        = portainer_stack.freeswitch.name
    keycloak          = portainer_stack.keycloak.name
    postfix_relay     = portainer_stack.postfix_relay.name
    homelab_portal    = portainer_stack.homelab_portal.name
  }
}
