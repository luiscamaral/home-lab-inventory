# NOMAD private child-network migration (operator guide)

NOMAD's admin container creates Qdrant, Kiwix, Kolibri and optional apps via the
host Docker socket. Their published host ports are not controlled by the NOMAD
Compose file. The private fork's opt-in `NOMAD_PRIVATE_MANAGED_PORTS=true` removes
those bindings on every managed-container creation path. Existing containers
retain their bindings until individually recreated.

## Access model

- Admin and Dozzle: existing `nomad.d.lcamaral.com` vhost.
- Kiwix: `https://kiwix.d.lcamaral.com` via the shared rproxy vhosts.
- Kolibri: `https://kolibri.d.lcamaral.com`; interactive ZIP content also
  requires HTTPS on port 8311 through those same rproxies. The fork's
  `NOMAD_KOLIBRI_ZIP_ORIGIN` sets Kolibri's `ZIP_CONTENT_ORIGIN` to that URL.
- Qdrant: only `nomad_qdrant:6333` on `project-nomad_default`; no public URL.

The `nomad_edge` Nginx container shares only admin's network namespace, so the
three remote rproxies can contact admin's existing macvlan address without a
new IP or host port. It allows requests only from rproxy addresses `.28`, `.48`
and `.49`; all other clients receive 403. Its backends use the NOMAD project
bridge. The app URL bootstrap sets NOMAD's existing `custom_url` fields.

## Deployment sequence

1. Merge the fork PR, build the pinned image, then merge inventory IaC after
   tests and a targeted Terraform plan. Apply only from clean merged `main`.
2. Apply the three rproxy stacks and Pi-hole-2/3 DNS sources using their existing
   Terraform resources. Sync Pi-hole-1's zone with `scripts/sync-host-overrides.py`
   (dry run first), then apply NOMAD. Verify `nomad_edge` starts and admin is
   healthy. No child bindings change in this step.
3. On the merged admin image, run `node ace managed-ports:reconcile SERVICE`
   inside `nomad_admin`, one service at a time: Qdrant, Kiwix, Kolibri.
   The command uses NOMAD's existing rename/health-gated rollback path and
   keeps bind-mounted data. Confirm each container's `NetworkSettings.Ports`
   has no host binding before continuing.
4. Check Qdrant from admin, Kiwix through all three rproxies, and Kolibri main
   UI **and an interactive ZIP lesson**. Verify the browser makes no direct
   request to ds-2 host ports. Check `docker ps` for any other `nomad_` child
   with a published host port; reconcile it before declaring completion.

Never run the destructive Qdrant reset as part of this network migration.

## Rollback

The previous image is `ghcr.io/luiscamaral/project-nomad:v1.35.1-custom-qdrant-timeout`.
Restore the previous IaC image and remove the opt-in environment variable, then
apply from merged main. If a child recreation fails, NOMAD's recreation path
restores the prior container. If a previously recreated child needs its old
binding, restore that child's prior config using a reviewed rollback procedure;
do not silently publish all children again.
