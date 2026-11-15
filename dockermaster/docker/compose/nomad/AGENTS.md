# NOMAD integration maintenance (AI agents)

Read the repository's `.claude/operating-rules.md` before changing or applying
anything. The human deployment/rollback runbook is `docs/nomad-private-network.md`.

The private fork lives at `third_party/project-nomad` and is pinned by gitlink.
Upstream NOMAD 1.35.1 manages children with Dockerode; it does not use the
inventory Compose file for their ports. Our opt-in fork delta is concentrated
in `admin/app/services/docker_service.ts`: `createManagedContainer` strips
`HostConfig.PortBindings` and sets `PublishAllPorts=false` when
`NOMAD_PRIVATE_MANAGED_PORTS=true`. Every child-creation call must go through
that helper, including Kiwix migration and image updates. `getServiceURL`
selects the internal exposed port under this policy. The separate
`NOMAD_KOLIBRI_ZIP_ORIGIN` opt-in wires the alternate HTTPS origin through
the curated Kolibri seed record without hardcoding a homelab domain upstream.
The separate
`managed-ports:reconcile` Ace command uses the existing guarded recreate path
for already-running children. Kiwix binds IPv4 because ds-2 has no IPv6.

On upstream upgrades, diff each `docker.createContainer` call and confirm
the helper still covers them all. Verify the gateway config is injected through
`terraform/portainer/stacks.tf`, DNS through `pihole/dnsmasq.d/`, and rproxy
vhosts through the shared `vhost.d` collection (all three proxies). Do not
add direct child `ports:` or Docker `PortBindings`. Check Kolibri's ZIP origin
separately from its UI. Never apply from a feature branch or migrate child
containers before the proxy paths are live.
