# NOMAD integration maintenance (AI agents)

Read the repository's `.claude/operating-rules.md` before changing or applying
anything. The human deployment/rollback runbook is `docs/nomad-private-network.md`.

The private fork lives at `third_party/project-nomad` and is pinned by gitlink.
Upstream NOMAD 1.35.1 manages children with Dockerode; it does not use the
inventory Compose file for their ports. Our opt-in fork delta is concentrated
in `admin/app/services/docker_service.ts`: `createManagedContainer` strips
`HostConfig.PortBindings` and sets `PublishAllPorts=false` when
`NOMAD_PRIVATE_MANAGED_PORTS=true`, and — for any service named in the
`NOMAD_MANAGED_MACVLAN_IPS` JSON map (service_name -> IPv4) — also attaches a
second `docker-servers-net` endpoint with that static IP. Every child-creation
call must go through that helper, including Kiwix migration and image updates.
`getServiceURL` selects the internal exposed port under this policy. The
`NOMAD_KOLIBRI_ZIP_ORIGIN` opt-in wires the alternate HTTPS origin through the
curated Kolibri seed record without hardcoding a homelab domain upstream. The
`managed-ports:reconcile` Ace command uses the existing guarded recreate path
for already-running children. Kiwix binds IPv4 because ds-2 has no IPv6.

Macvlan IPs are homelab-specific and must stay env-driven (never hardcoded in
the fork). Current allocation: Kiwix `192.168.59.8`, Kolibri `192.168.59.3`,
reserved in `inventory/docker-containers.md` and `dockermaster/templates/README.md`.
The rproxies proxy directly to those IPs via the shared `vhost.d` collection
(all three proxies); DNS is via `pihole/dnsmasq.d/`. On upstream upgrades, diff
each `docker.createContainer` call and confirm the helper still covers them all.
Do not add direct child `ports:` or Docker `PortBindings`, and do not reintroduce
an edge/gateway hop. Check Kolibri's ZIP origin separately from its UI. Never
apply from a feature branch or migrate child containers before the proxy paths
are live.
