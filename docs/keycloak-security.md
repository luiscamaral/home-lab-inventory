# Keycloak: realms in Terraform and exposure rules

Keycloak runs as two nodes (`keycloak` on dockermaster, `keycloak-2` on dockerserver-1) behind the rproxies.
Its public name is `auth.cf.lcamaral.com` (Cloudflare tunnel `bologna`); the LAN-only admin name is
`keycloak.d.lcamaral.com`. The hostname is fixed (`KC_HOSTNAME=https://auth.cf.lcamaral.com`), so every token
carries `iss=https://auth.cf.lcamaral.com/realms/homelab`.

## Tests for the hardening (phase K)

`scripts/keycloak-hardening-test.py` checks the K2, K3 and K4 behaviour against the live realms. Each test creates its own
disposable users with the admin API on `keycloak.d.lcamaral.com` and deletes them in a `finally` block; it never touches
`admin` or the real account:

```bash
T="uv run --no-project --quiet --with requests python scripts/keycloak-hardening-test.py"
$T probe                                   # read-only
$T lockout --realm homelab
$T lockout --realm master
$T reset --mail-to you@example.com
$T events --realm homelab
```

`lockout` needs K2, `reset` needs K3a and K3b (the OTP user's mail goes to `--mail-to`, with a `+tag` added to the
local part), `events` needs K4.

## Realms are in Terraform (K0)

`terraform/portainer/keycloak_realms.tf` declares the `homelab` and `master` realms (`keycloak_realm`). They were
imported from the live server with `import` blocks, and the first plan after the import is **No changes**.
Both have `prevent_destroy`. The file header lists what is intentionally not captured yet
(`security_defenses`, events, `attributes`), and why.

To change a realm setting, edit the resource and apply with the provider (never in the admin console: the next plan
would show the drift). `homelab` still has `ssl_required = "none"` (captured as found); tightening it is a separate change.

## Brute-force lockout (K2)

Both realms (`homelab`, `master`) have `security_defenses.brute_force_detection` in `keycloak_realms.tf`:

| Setting | Value | Meaning |
|---|---|---|
| `max_login_failures` | 3 | the third failed login triggers the lockout |
| `wait_increment_seconds` | 1200 | a locked user waits 20 minutes |
| `max_failure_wait_seconds` | 1200 | the wait never exceeds 20 minutes |
| `failure_reset_time_seconds` | 1200 | the failure counter resets after 20 minutes without failures |
| `permanent_lockout` | false | never permanent; the user unlocks by itself |
| `quick_login_check_milli_seconds` / `minimum_quick_login_wait_seconds` | 1000 / 60 | unchanged defaults: failures less than 1 s apart add a 60 s wait |

The `headers` block next to it repeats the live values (Keycloak defaults) because the provider sends both blocks
together; it changes nothing.

- A locked user sees the normal "Invalid username or password" page (Keycloak does not reveal the lockout), also with the
  correct password, until the wait ends. The `USER_DISABLED_BY_TEMPORARY_LOCKOUT` event (K4) records it.
- Status and manual unlock (admin API, LAN name): `GET /admin/realms/<realm>/attack-detection/brute-force/users/<id>`
  returns `numFailures` and `disabled`; `DELETE` on the same path clears the failures and unlocks the user.
- The temporary lockout lets anyone who can reach the login page keep a known username locked (a denial of service for
  that user, not an access risk). Admin console logins are LAN-only (K1), so the `master` admin cannot be locked from the
  internet. If it happens to the real user, wait 20 minutes or unlock with the call above.
- Test: `scripts/keycloak-hardening-test.py lockout` uses disposable users in both realms. Never test against `admin`
  or the real account.

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

## Mail relay path (K3a)

Keycloak sends mail (password reset) from whichever node serves the request, and the realm's SMTP host is one setting for
both. `postfix-relay` used to live only on the dm-local `rproxy` bridge, so `keycloak-2` (ds-1) could not resolve or reach
it, and `postfix-relay.d.lcamaral.com` (the Alertmanager smarthost) did not exist in DNS (`NXDOMAIN`).

Since K3a the relay also sits on `docker-servers-net` with the static address `192.168.59.14`, and
`pfsense/host-overrides.yml` has `postfix-relay.d.lcamaral.com -> 192.168.59.14` (Pi-hole 1/2/3 and pfSense Unbound).
Both Keycloak nodes (K3b) and Alertmanager use that name. The image is pinned by digest (it was `latest` with Watchtower).

- The relay trusts `192.168.0.0/16` (`mynetworks`) and only relays sender domains `lcamaral.com`, `d.lcamaral.com` and
  `cf.lcamaral.com`. Reaching port 25 on a LAN address now works for any host on the LAN, as it already did for containers
  on the `rproxy` network.
- Alertmanager critical and warning alerts are configured to email `luiscamaral+homelab@gmail.com`. They could not be
  delivered before (NXDOMAIN); once the name resolves they will be.
