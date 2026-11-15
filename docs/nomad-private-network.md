# NOMAD private child-network migration (operator guide)

NOMAD's admin container creates Qdrant, Kiwix, Kolibri and optional apps via the
host Docker socket. Their published host ports are not controlled by the NOMAD
Compose file. The private fork's opt-in `NOMAD_PRIVATE_MANAGED_PORTS=true` removes
those bindings on every managed-container creation path, and
`NOMAD_MANAGED_MACVLAN_IPS` attaches Kiwix and Kolibri to the routable
`docker-servers-net` macvlan with a stable IP. Existing containers retain their
bindings until individually recreated.

## Access model

- Admin and Dozzle: existing `nomad.d.lcamaral.com` vhost.
- Kiwix: `https://kiwix.d.lcamaral.com` → macvlan `192.168.59.8:8080`.
- Kolibri: `https://kolibri.d.lcamaral.com` → macvlan `192.168.59.3:8080`;
  interactive ZIP content also requires HTTPS on port 8311 at the same IP. The
  fork's `NOMAD_KOLIBRI_ZIP_ORIGIN` sets Kolibri's `ZIP_CONTENT_ORIGIN` to that URL.
- Qdrant: only `nomad_qdrant:6333` on `project-nomad_default`; no macvlan IP and
  no public URL.

The rproxies proxy directly to the child macvlan IPs — the same one-hop pattern
used by every other service in the homelab. No edge gateway, no shared network
namespace, and no dependency on `nomad_admin`'s health. The app URL bootstrap
sets NOMAD's existing `custom_url` fields.

## Deployment sequence

1. Merge the fork PR, build the pinned image, then merge inventory IaC after
   tests and a targeted Terraform plan. Apply only from clean merged `main`.
2. Apply the three rproxy stacks and Pi-hole-2/3 DNS sources using their existing
   Terraform resources. Sync Pi-hole-1's zone with `scripts/sync-host-overrides.py`
   (dry run first), then apply NOMAD. Verify admin is healthy. No child bindings
   change in this step.
3. On the merged admin image, run `node ace managed-ports:reconcile SERVICE`
   inside `nomad_admin`, one service at a time: Qdrant, Kiwix, Kolibri.
   The command uses NOMAD's existing rename/health-gated rollback path and
   keeps bind-mounted data. Confirm each child's `NetworkSettings.Ports` has no
   host binding, and that Kiwix/Kolibri carry the macvlan IP, before continuing.
4. Check Qdrant from admin, Kiwix through all three rproxies, and Kolibri main
   UI **and an interactive ZIP lesson**. Check `docker ps` for any other `nomad_`
   child with a published host port; reconcile it before declaring completion.

Never run the destructive Qdrant reset as part of this network migration.

## Rollback

The previous image is `ghcr.io/luiscamaral/project-nomad:v1.35.1-custom-private-ports-2`.
Restore the previous IaC image and remove the `NOMAD_MANAGED_MACVLAN_IPS`
variable, then apply from merged main. If a child recreation fails, NOMAD's
recreation path restores the prior container. If a previously recreated child
needs its old binding, restore that child's prior config using a reviewed
rollback procedure; do not silently publish all children again.
