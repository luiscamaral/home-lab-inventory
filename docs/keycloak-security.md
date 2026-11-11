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
