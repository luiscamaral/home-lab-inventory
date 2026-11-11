# pfSense REST API v2 Reference

pfSense runs `pfSense-pkg-RESTAPI-2.10_2` (pfSense Plus 26.07 build) — a comprehensive REST API with 200+
endpoints covering firewall, routing, DNS, DHCP, HAProxy, ACME, certs, VPN, and
system management. Source: [pfrest/pfSense-pkg-RESTAPI](https://github.com/pfrest/pfSense-pkg-RESTAPI).

## Reinstall after pfSense upgrades

The package is third-party, so a pfSense upgrade or patch can drop it silently. Every
`/api/v2/...` call then returns the GUI's HTML **404** page, and
`/usr/local/www/api/v2/` holds only an empty `schema/` dir. This happened between
the 26.07 patch (2026-09-10) and 2026-09-12. The API stayed down until
2026-11-10, which also broke the `scripts/sync-pfsense-*.py` reconcilers that
use it.

Reinstall the asset that matches `cat /etc/version`. Settings and API keys come
back from `/usr/local/share/pfSense-pkg-RESTAPI/backup.json` (`keep_backup` is
enabled):

```bash
V=v2.10.2; PF=26.07   # release tag + pfSense version
gh api repos/pfrest/pfSense-pkg-RESTAPI/releases/tags/$V \
  -q ".assets[]|select(.name==\"pfSense-$PF-pkg-RESTAPI.pkg\")|.digest"   # expected sha256
ssh pfsense "cd /tmp && fetch -o restapi.pkg https://github.com/pfrest/pfSense-pkg-RESTAPI/releases/download/$V/pfSense-$PF-pkg-RESTAPI.pkg \
  && sha256 -q restapi.pkg && pkg-static add restapi.pkg && rm restapi.pkg"   # compare sha256 first
```

Rollback: `pkg-static delete pfSense-pkg-RESTAPI`. History: 2026-11-10 reinstalled
2.10_2 (break-glass, approved by the user; recorded post-hoc in the PR that added this
section). The `sha256` was verified against the release digest.

## ACME and other slow endpoints (the 504s)

`GET /services/acme/certificates` through `https://pfsense.home.lcamaral.com/api/v2` returns
**504**, but the API itself works: called directly on the box it answers 200 after about 57 s
(a single cert read takes about 43 s, `/system/certificates` about 20 s, `/services/haproxy/backends`
about 9 s, `/system/version` 2 s). The 504 comes from HAProxy: the web front end has
`timeout server 30000`, so anything slower than 30 s is cut off. The same limit explains the
`/services/cron/jobs` 504 that `scripts/sync-pfsense-cron-jobs.py` already works around.

The time is spent in the PHP worker, not in the config size (`config.xml` is 490 KB) or the network:
while an ACME call runs, the worker forks `/sbin/sysctl` thousands of times (`getSchedulers()` in
`/etc/inc/shaper.inc`, about 1500 loops in 20 s), with almost no CPU use. It is a behaviour of the
installed package (`pfSense-pkg-RESTAPI-2.10_2` on 26.07), not a fault of the ACME data.

**Use the local port instead of HAProxy.** The sync tools run
`ssh pfsense 'curl --max-time 170 http://127.0.0.1:56880/api/v2/...'` (the pfSense web server, reachable
only on the box) and need no pfSense change. `scripts/sync-pfsense-acme-actions.py`,
`scripts/sync-pfsense-acme-certificates.py` and `scripts/sync-host-overrides.py` do this. Expect about
a minute per ACME read and plan for the same per write. Raising HAProxy's `timeout server` for the API
frontend would hide the 504 but isn't needed, so it is not done.

History of the earlier `sync-host-overrides.py` 404: that was the missing package (see
[Reinstall after pfSense upgrades](#reinstall-after-pfsense-upgrades)), not the slow endpoints.
It works again since the 2026-11-10 reinstall (a full run takes about 2 min).

## ACME certificate definitions (IaC)

`pfsense/acme-certificates.yml` declares the certificates (name, account, key length, renewal,
domains and challenge method). `scripts/sync-pfsense-acme-certificates.py` compares it with
pfSense (dry run by default) and creates or patches one cert at a time (`--cert NAME --apply`).
Issuing and renewing is a separate explicit step (`--cert NAME --issue`, `--renew`): it contacts
Let's Encrypt and adds, then removes, a DNS TXT record at DreamHost. Post-renewal commands stay in
`pfsense/acme-actions.yml` (`scripts/sync-pfsense-acme-actions.py`).

**Wildcard names can't be created through the REST API.** The ACME domain `name` is validated as a plain FQDN
(`HostnameValidator(allow_fqdn: true)`), so `POST /services/acme/certificate` with `*.cf.lcamaral.com` fails with
`HOSTNAME_VALIDATOR_FAILED` (still true on pfSense-pkg-RESTAPI 2.11.0 and on its main branch). The wildcard certs
`d.lcamaral.com`, `home.lcamaral.com` and `pfsense` were created in the GUI and are only _captured_ by the YAML.
Certificates that need new names are declared with explicit SANs (see `cf.lcamaral.com`); the script warns when a
`*.cf` name served by a vhost is missing from that list.

**Issuing through the REST API has a 300 s limit.** `POST /services/acme/certificate/issue` and `/renew` run the
package through a dispatcher (`dispatch.sh … 300`, i.e. `timeout 300`). A certificate with `dnssleep` of 300 s can't
finish inside that budget: the dispatcher is killed during validation and the package's own import step then fails
with `Reload error` (the cert is issued by Let's Encrypt but never imported). 2026-11-11, `cf.lcamaral.com`: first run
killed at 02:38:48, validation ran at 02:38:54, `Reload error` at 02:39:15; a second run hung for the whole 300 s without
starting `acme.sh`. Keep `dnssleep` of API-issued certs below about 150 s. pfSense's own nightly renewal
(`acme_command.sh renewall` from cron) has no such limit, so renewals of the existing certs are not affected.
`--issue` and `--renew` in `scripts/sync-pfsense-acme-certificates.py` watch the box (`pgrep` and only the new
bytes of the acme log) instead of polling the API, and report Let's Encrypt and the package import separately.

The DreamHost DNS token is a write-only field in the REST API, so it can't be diffed. It lives in
Vault (`secret/homelab/dreamhost`, field `api_token`) and is sent only when a domain is created.
Nothing secret is stored in the repo.

## Connection Details

| Field | Value |
| --- | --- |
| Base URL | `https://pfsense.home.lcamaral.com/api/v2` |
| Protocol | **HTTPS** via HAProxy (TLS on port 443) |
| Auth header | `X-API-Key: <token>` |
| Token source | macOS Keychain: `security find-generic-password -a ${USER} -s pfsense-api-token -w` |
| Allowed interface | HOME VLAN (`192.168.4.1`) |
| Auth methods | `KeyAuth`, `JWTAuth` |
| GraphQL | `https://pfsense.home.lcamaral.com/api/v2/graphql` |
| Docs (web) | `https://pfsense.home.lcamaral.com/api/v2/documentation` (requires session login, not API key) |

## Authentication

```bash
TOKEN=$(security find-generic-password -a ${USER} -s pfsense-api-token -w)
curl -sk -H "X-API-Key: $TOKEN" https://pfsense.home.lcamaral.com/api/v2/status/system
```

The token authenticates as user `lamaral`. API keys are managed in pfSense GUI:
**System → REST API → Keys**, or via `/api/v2/auth/keys`.

## Quick Reference — Most Useful Endpoints

### System & Status (read-only GET)

| Endpoint | Returns |
| --- | --- |
| `/status/system` | CPU, RAM, temp, uptime, disk, platform |
| `/status/interfaces` | All interface status (UP/DOWN, stats) |
| `/status/gateways` | Gateway status, latency, packet loss |
| `/status/services` | All running services with PID, status |
| `/status/dhcp_server/leases` | All DHCP leases |
| `/status/carp` | CARP status |
| `/system/version` | pfSense version, build, patch |
| `/system/restapi/version` | REST API version, update availability |
| `/system/hostname` | Hostname and domain |
| `/diagnostics/arp_table` | ARP table |

### Firewall

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/firewall/rules` | GET, POST | All firewall rules |
| `/firewall/rule` | GET, PATCH, DELETE | Single rule by ID |
| `/firewall/aliases` | GET | All aliases |
| `/firewall/alias` | GET, POST, PATCH, DELETE | Single alias |
| `/firewall/states` | GET, DELETE | PF state table |
| `/firewall/states/size` | GET, PATCH | Max states, current count |
| `/firewall/nat/port_forwards` | GET | Port forward rules |
| `/firewall/nat/outbound/mappings` | GET | Outbound NAT rules |
| `/firewall/virtual_ips` | GET | Virtual IPs |
| `/firewall/apply` | POST | Apply pending firewall changes |

### Routing

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/routing/gateways` | GET | All gateways |
| `/routing/gateway/default` | GET, PATCH | Default gateway config |
| `/routing/gateway/groups` | GET | Gateway groups (failover) |
| `/routing/static_routes` | GET | Static routes |
| `/routing/apply` | POST | Apply routing changes |

### Interfaces

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/interfaces` | GET | All configured interfaces |
| `/interface` | GET, POST, PATCH, DELETE | Single interface |
| `/interface/vlans` | GET | All VLANs |
| `/interface/available_interfaces` | GET | Unassigned physical interfaces |

### DNS (Unbound Resolver)

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/services/dns_resolver/settings` | GET, PATCH | Resolver config |
| `/services/dns_resolver/host_overrides` | GET | DNS host overrides |
| `/services/dns_resolver/domain_overrides` | GET | Domain overrides |
| `/services/dns_resolver/access_lists` | GET | Access control lists |
| `/services/dns_resolver/apply` | POST | Apply DNS changes |

### DHCP Server

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/services/dhcp_servers` | GET | All DHCP server configs |
| `/services/dhcp_server/static_mappings` | GET | Static DHCP reservations |
| `/services/dhcp_server/address_pools` | GET | Address pools |
| `/services/dhcp_server/apply` | POST | Apply DHCP changes |

### HAProxy

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/services/haproxy/frontends` | GET | All frontends |
| `/services/haproxy/backends` | GET | All backends |
| `/services/haproxy/backend/servers` | GET | Backend server list |
| `/services/haproxy/frontend/certificates` | GET | Frontend SSL certs |
| `/services/haproxy/settings` | GET, PATCH | Global HAProxy settings |
| `/services/haproxy/apply` | POST | Apply HAProxy changes |

### ACME / Certificates

| Endpoint | Methods | Returns |
| --- | --- | --- |
| `/services/acme/certificates` | GET | All ACME certs |
| `/services/acme/certificate/issue` | POST | Issue new cert |
| `/services/acme/certificate/renew` | POST | Renew existing cert |
| `/services/acme/account_keys` | GET | ACME account keys |
| `/services/acme/settings` | GET, PATCH | ACME global settings |
| `/system/certificates` | GET | All system certificates |
| `/system/certificate_authorities` | GET | All CAs |

### Logs

| Endpoint | Returns |
| --- | --- |
| `/status/logs/system` | System logs |
| `/status/logs/firewall` | Firewall logs |
| `/status/logs/dhcp` | DHCP logs |
| `/status/logs/auth` | Auth logs |
| `/status/logs/packages/restapi` | REST API logs |

### Diagnostics (use with caution)

| Endpoint | Methods | Notes |
| --- | --- | --- |
| `/diagnostics/arp_table` | GET | ARP table dump |
| `/diagnostics/ping` | POST | Ping from pfSense |
| `/diagnostics/command_prompt` | POST | **Execute shell commands** |
| `/diagnostics/config_history/revisions` | GET | Config backup history |
| `/diagnostics/reboot` | POST | **Reboot system** |
| `/diagnostics/halt_system` | POST | **Halt system** |

### VPN (available but not currently in use)

Endpoints exist for IPsec, OpenVPN, and WireGuard — full CRUD for tunnels,
peers, phases, etc. Not documented in detail since no VPN is currently active.

## Full Endpoint List (200+ URLs)

Organized by category:

### Auth (3)

`/auth/jwt`, `/auth/key`, `/auth/keys`

### Diagnostics (8)

`/diagnostics/arp_table`, `/diagnostics/arp_table/entry`,
`/diagnostics/command_prompt`, `/diagnostics/config_history/revision`,
`/diagnostics/config_history/revisions`, `/diagnostics/halt_system`,
`/diagnostics/ping`, `/diagnostics/reboot`

### Firewall (24)

`/firewall/advanced_settings`, `/firewall/alias`, `/firewall/aliases`,
`/firewall/apply`, `/firewall/nat/one_to_one/mapping`,
`/firewall/nat/one_to_one/mappings`, `/firewall/nat/outbound/mapping`,
`/firewall/nat/outbound/mappings`, `/firewall/nat/outbound/mode`,
`/firewall/nat/port_forward`, `/firewall/nat/port_forwards`,
`/firewall/rule`, `/firewall/rules`, `/firewall/schedule`,
`/firewall/schedule/time_range`, `/firewall/schedule/time_ranges`,
`/firewall/schedules`, `/firewall/state`, `/firewall/states`,
`/firewall/states/size`, `/firewall/traffic_shaper*` (8 endpoints),
`/firewall/virtual_ip*` (3 endpoints)

### GraphQL (1)

`/graphql`

### Interfaces (12)

`/interface`, `/interface/apply`, `/interface/available_interfaces`,
`/interface/bridge`, `/interface/bridges`, `/interface/gre`,
`/interface/gres`, `/interface/group`, `/interface/groups`,
`/interface/lagg`, `/interface/laggs`, `/interface/vlan`,
`/interface/vlans`, `/interfaces`

### Routing (11)

`/routing/apply`, `/routing/gateway`, `/routing/gateway/default`,
`/routing/gateway/group`, `/routing/gateway/group/priorities`,
`/routing/gateway/group/priority`, `/routing/gateway/groups`,
`/routing/gateways`, `/routing/static_route`, `/routing/static_routes`

### Services (70+)

ACME (12), BIND (12), Cron (2), DHCP Relay (1), DHCP Server (10),
DNS Forwarder (5), DNS Resolver (11), FreeRADIUS (6), HAProxy (26),
NTP (3), Service Watchdog (2), SSH (1), Wake on LAN (1)

### Status (20)

`/status/carp`, `/status/dhcp_server/leases`, `/status/gateways`,
`/status/interfaces`, `/status/ipsec/*` (4), `/status/logs/*` (6),
`/status/openvpn/*` (6), `/status/service`, `/status/services`,
`/status/system`

### System (25)

`/system/certificate*` (8), `/system/certificate_authority*` (4),
`/system/console`, `/system/crl*` (3), `/system/dns`,
`/system/hostname`, `/system/notifications/email_settings`,
`/system/package*` (3), `/system/restapi/*` (5), `/system/timezone`,
`/system/tunable*` (2), `/system/version`,
`/system/webgui/settings`

### Users (5)

`/user`, `/user/auth_server`, `/user/auth_servers`, `/user/group`,
`/user/groups`, `/users`

### VPN (25)

IPsec (9), OpenVPN (9), WireGuard (10)

## Safety Classification for Automation

### Safe (GET only, read-only)

All `/status/*`, `/diagnostics/arp_table`, all GET-method list endpoints

### Confirm First (state-changing POST/PATCH)

- `*/apply` endpoints (apply pending changes)
- `service *` restarts
- DHCP/DNS/HAProxy config changes
- ACME cert issue/renew

### Never Automate

- `/diagnostics/reboot`, `/diagnostics/halt_system`
- `/diagnostics/command_prompt` (arbitrary shell execution)
- Bulk DELETE on firewall rules, states
- User/auth changes
