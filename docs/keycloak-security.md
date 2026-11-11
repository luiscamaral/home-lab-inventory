# Keycloak: realms in Terraform and exposure rules

Keycloak runs as two nodes (`keycloak` on dockermaster, `keycloak-2` on dockerserver-1) behind the rproxies.
Its public name is `auth.cf.lcamaral.com` (Cloudflare tunnel `bologna`); the LAN-only admin name is
`keycloak.d.lcamaral.com`. The hostname is fixed (`KC_HOSTNAME=https://auth.cf.lcamaral.com`), so every token
carries `iss=https://auth.cf.lcamaral.com/realms/homelab`.

## Realms are in Terraform (K0)

`terraform/portainer/keycloak_realms.tf` declares the `homelab` and `master` realms (`keycloak_realm`). They were
imported from the live server with `import` blocks, and the first plan after the import is **No changes**.
Both have `prevent_destroy`. The file header lists what is intentionally not captured yet
(`security_defenses`, events, `attributes`), and why.

To change a realm setting, edit the resource and apply with the provider (never in the admin console: the next plan
would show the drift). `homelab` still has `ssl_required = "none"` (captured as found); tightening it is a separate change.

## Exposure rules (K1)

- Self-registration is off in `homelab` (`registration_allowed = false`); accounts are created by an admin.
- The admin console, the Admin REST API and the `master` realm are served **only on `keycloak.d.lcamaral.com`**
  (LAN or Twingate). Two settings make that work with the fixed public hostname:
  `KC_HOSTNAME_ADMIN=https://keycloak.d.lcamaral.com` on both nodes (the console's own URLs), and the master realm's
  Frontend URL (`frontendUrl` attribute in `keycloak_realm.master`), which puts the master login form and the master
  tokens (`iss=https://keycloak.d.lcamaral.com/realms/master`) on that name too. Without the second one the master login
  form still posts to the public name. The `homelab` realm keeps `iss=https://auth.cf.lcamaral.com/realms/homelab`.
- The public names never expose the admin surface. On the Keycloak server blocks of `auth.cf.lcamaral.com.conf` (the
  named block and the explicit default server, which is what a tunnel hostname without its own vhost, such as
  `bologna.cf.lcamaral.com`, falls through to), `/admin`, `/realms/master` and the registration endpoints return 403.
- Source-IP allow-lists do not work on the `*.cf` blocks: tunnel traffic reaches Nginx from the cloudflared
  containers' LAN addresses. Blocking by public hostname is what works.
- Anything that talks to the master realm or the Admin API must use `keycloak.d` (the Terraform provider and
  `scripts/zot-e2e.py` do).

## Login and admin event history (K4)

`keycloak_realm_events.homelab` and `.master` keep **user events** and **admin events (with the request
representation)** for 90 days (`events_expiration = 7776000`). The event types are Keycloak's default set (no
`enabled_event_types`), which includes `LOGIN`, `LOGIN_ERROR`, `USER_DISABLED_BY_TEMPORARY_LOCKOUT`,
`SEND_RESET_PASSWORD` and `RESET_PASSWORD_ERROR`. The `jboss-logging` listener stays listed, otherwise the provider
removes it.

Read them with the admin API on the LAN name, for example:

```bash
curl -s -H "Authorization: Bearer $TOKEN" 'https://keycloak.d.lcamaral.com/admin/realms/homelab/events?type=LOGIN_ERROR&max=20'
curl -s -H "Authorization: Bearer $TOKEN" 'https://keycloak.d.lcamaral.com/admin/realms/homelab/admin-events?max=20'
```

Events are stored in the shared Keycloak database (`keycloak-db`), so the 90 days of history add a small, bounded
amount of data. Admin events with representation contain the bodies of admin requests (user attributes, but not
password values; Keycloak masks credentials).

## Open exposure items

- `portainer.cf.lcamaral.com` and `minio.cf.lcamaral.com` are in the tunnel ingress, so the Portainer UI and the MinIO
  console are reachable from the internet (behind their own logins).
- `homelab` has `ssl_required = "none"` (captured as found).
