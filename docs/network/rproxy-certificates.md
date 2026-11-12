# rproxy certificates (which certificate serves which name)

The three Nginx reverse proxies (`rproxy`, `rproxy-2`, `rproxy-3`) read their certificates from the shared NFS directory
`/nfs/dockermaster/docker/nginx-rproxy/config/cert/`. pfSense ACME issues them and
`pfsense/scripts/sync-certs-to-rproxy.sh <cert>` copies `<cert>.{crt,key,fullchain,ca}` there and reloads all three
proxies after each renewal (see `pfsense/acme-actions.yml`).

| Certificate (ACME name) | Names | Used by |
|---|---|---|
| `d.lcamaral.com` | `*.d.lcamaral.com` | every `*.d` vhost, and the **default server** (see below) |
| `cf.lcamaral.com` | the `*.cf.lcamaral.com` names listed in `pfsense/acme-certificates.yml` (explicit SANs, no wildcard) | the `*.cf` server blocks |
| `home.lcamaral.com` | `home.lcamaral.com`, `*.home.lcamaral.com` | `*.home` vhosts |

## Why the `cf` certificate exists

Browsers reach the `*.cf` names through Cloudflare, which terminates TLS, so they never see the rproxy certificate.
A LAN client that resolves a `*.cf` name straight to the rproxies (zot reaching Keycloak at `auth.cf.lcamaral.com`,
because Keycloak's issuer is that name) needs a publicly trusted certificate for it. Before this certificate, the
rproxies answered those names with the `*.d` certificate, which does not match.

The cert lists explicit names because the pfSense REST API rejects wildcard names when it creates an ACME
certificate (see `docs/network/pfsense-api.md`). `scripts/sync-pfsense-acme-certificates.py --check` fails when a
`*.cf` name served by a vhost is missing from the cert.

## Server blocks

Nginx picks one certificate per server block, so a vhost that serves a `*.d` name and a `*.cf` name has two `443`
server blocks (identical apart from `server_name` and the certificate paths), and a `*.cf`-only vhost uses the `cf`
certificate directly. The port-80 redirect blocks are shared. Keep the pairs identical when you edit one.

To add a new `*.cf` vhost:

1. Add the name to the `cf.lcamaral.com` domains in `pfsense/acme-certificates.yml` (and, if it must also exist as
   `*.d`, create the `*.d` block).
2. `scripts/sync-pfsense-acme-certificates.py --cert cf.lcamaral.com --apply`, then renew the certificate so the new
   name is in its SANs (pfSense renewals are scheduled by its own cron; a forced renewal is a pfSense-side action).
3. Add the vhost with a `listen 443 ssl` block that uses `/etc/nginx/cert/cf.lcamaral.com.*`.

## Default server (unknown SNI, IP-only connections)

`auth.cf.lcamaral.com.conf` defines the explicit default servers (`listen 80 default_server`,
`listen 443 ssl default_server`, `server_name _`). Before the `cf` certificate existed, that vhost was the implicit
default only because its file is loaded first. Anything that does not match a `server_name` (an IP-only connection, an
unknown SNI or Host) keeps getting the `*.d` certificate and the Keycloak proxy, and port 80 keeps redirecting to
`https://$host`. This is deliberately unchanged behaviour: changing it (for example to a `421`) is a separate decision.

## Checking a replica

```bash
for ip in 192.168.59.28 192.168.59.48 192.168.59.49; do
  echo "$ip"
  echo | openssl s_client -connect $ip:443 -servername auth.cf.lcamaral.com 2>/dev/null | openssl x509 -noout -issuer -subject
  echo | openssl s_client -connect $ip:443 -servername vault.d.lcamaral.com 2>/dev/null | openssl x509 -noout -subject
  echo | openssl s_client -connect $ip:443 2>/dev/null | openssl x509 -noout -subject   # no SNI: the *.d certificate
done
```
