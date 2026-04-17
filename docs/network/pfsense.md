# 🔥 pfSense — Main Router & Gateway

Primary firewall, router, DNS resolver, dual-WAN gateway, HAProxy edge, and ACME
certificate authority for the homelab. Every VLAN in the house routes through
this box, and it issues the wildcard certs that Nginx-rproxy on dockermaster
serves.

## Identity

| Field | Value |
| --- | --- |
| Hostname | `pfsense.admin.lcamaral.com` |
| Short name | `pfsense` |
| Role | Main router, firewall, DNS, DHCP, ACME, HAProxy edge |
| Access | `ssh pfsense` (key-based, no password / username needed, port **3220**) |
| Version | pfSense Plus **26.03-RELEASE** (build `20260401-1720`) |
| Kernel | FreeBSD 16.0-CURRENT (`plus-RELENG_26_03-n256531`) |
| Architecture | amd64 |
| Web GUI | `https://pfsense.home.lcamaral.com` (HAProxy TLS on 443) |
| REST API | `https://pfsense.home.lcamaral.com/api/v2` — see `docs/network/pfsense-api.md` |

## Hardware

| Field | Value |
| --- | --- |
| Vendor OUI | `a8:b8:e0` → **Netgate** |
| CPU | Intel Core **i3-N305** (8 cores, Alder Lake-N) |
| RAM | 16 GB |
| Storage | ZFS pool `pfSense`, 408 GB usable |
| Boot environments | 5 BEs — safe upgrade rollback via `bectl` |
| NICs | 2× 10GbE SFP+ (`ix0`, `ix1`) + 4× 2.5GbE (`igc0`–`igc3`) |

> **Likely model**: Netgate 8200 (i3-N305 + 2× 10GbE SFP+ + 4× 2.5GbE is that
> appliance's exact fingerprint). Unconfirmed in config — update when verified.

## Physical Interface Map

| FreeBSD if | Speed | Role | IPv4 | Link | Notes |
| --- | --- | --- | --- | --- | --- |
| `ix0` | 10G SFP+ | **LAN trunk** | — | 10Gbase-SR, active | Parent of all VLANs |
| `ix1` | 10G SFP+ | — | — | no carrier | Spare |
| `igc0` | 2.5G | **WAN1** | `192.168.28.3/24` | active | Google Fiber (behind ISP router `192.168.28.1`) |
| `igc1` | 2.5G | **WAN2** | `192.168.12.2` + `192.168.12.32/24` | active (1GbE) | Backup WAN — two IPs, see note below |
| `igc2` | 2.5G | — | — | no carrier | Spare |
| `igc3` | 2.5G | **ADMIN** | `192.168.32.33/27` | active | Management subnet |

> **WAN2 dual-IP**: `igc1` carries both `192.168.12.2` and `192.168.12.32` in
> the same /24. Config labels it `WAN2_DHCP` but pfSense is pinning both — this
> is either a DHCP-assigned + static override or a CARP / VIP setup. Worth
> confirming before relying on failover.

## VLAN Map (all on `ix0` trunk)

| VLAN | ifname | Name | Subnet | Gateway | Purpose |
| --- | --- | --- | --- | --- | --- |
| 10 | `ix0.10` | **HOME** | `192.168.0.0/20` | `192.168.4.1` | Main LAN — hosts, laptops, phones, printers |
| 28 | `ix0.28` | **SRVAN** | `192.168.48.0/20` | `192.168.48.1` | Server VLAN — Docker macvlan `Docker-servers-net` lives here |
| 105 | `ix0.105` | **GUEST** | `192.168.128.0/24` | `192.168.128.1` | Isolated guest Wi-Fi |
| 205 | `ix0.205` | **IoT** | `192.168.16.0/24` + ULA `fc00:1cd::/64` | `192.168.16.1` / `fc00:1cd::1` | IoT devices — only VLAN with IPv6 |

### Cross-references

- Docker `Docker-servers-net` macvlan = SRVAN VLAN 28, container range
  `192.168.59.0/26` is carved out of the /20 for static macvlan assignments.
- Proxmox bridges `vmbr10`/`vmbr28`/`vmbr205` map to HOME / SRVAN / IoT.
- Management subnet `192.168.32.32/27` (ADMIN) is where Proxmox
  (`192.168.32.61`), dockermaster management, and pfSense itself live.

## Routing & Dual-WAN Failover

**Default route**: `192.168.28.1` via WAN1 (`igc0`)

### Static routes

| Destination | Via | Interface |
| --- | --- | --- |
| `8.8.0.0/16` + `8.8.8.8` | `192.168.28.1` | WAN1 — keeps DNS monitoring bound to WAN1 |
| `192.168.100.0/24` | `192.168.7.10` | `ix0.10` (HOME) — routes through Proxmox to an inner lab net |

**Gateway group**: `WAN1 GoogleFiber Preferred`

| Tier | Member | Trigger |
| --- | --- | --- |
| 1 | `WAN1GW` (Google Fiber) | `downloss` — fail over on packet loss OR link down |
| 2 | `WAN2_DHCP` (backup ISP) | |

## DNS

- **Resolver**: Unbound (`/usr/local/sbin/unbound`), running on **all VLAN
  gateways**:

  | Interface | DNS (53) | DoT (853) | Control (953) |
  | --- | --- | --- | --- |
  | `127.0.0.1` (localhost) | yes | yes | yes |
  | `192.168.32.33` (ADMIN) | yes | yes | — |
  | `192.168.4.1` (HOME) | yes | yes | — |
  | `192.168.48.1` (SRVAN) | yes | yes | — |
  | `192.168.128.1` (GUEST) | yes | yes | — |
  | `192.168.16.1` (IoT) | yes | yes | — |

- **DHCP → DNS integration**: `dhcpleases` daemon writes leases into
  `/var/unbound/dhcpleases_entries.conf` so DHCP clients are resolvable by
  hostname immediately.
- **Primary LAN domain**: `home.lcamaral.com`
- **Management domain**: `admin.lcamaral.com` (pfSense, Proxmox mgmt, etc.)
- **DHCP server**: ISC `dhcpd` on UDP/67 (not Kea) — lease database at
  `/var/dhcpd/var/db/dhcpd.leases`.

## DynDNS (DreamHost)

pfSense updates DreamHost DNS records with current WAN IPs:

| Hostname | Source |
| --- | --- |
| `homelab.lcamaral.com` | WAN1 |
| `wan1.home.lcamaral.com` | WAN1 |
| `wan2.home.lcamaral.com` | WAN2 |
| `hbbs.home.lcamaral.com` | WAN1 — RustDesk signal server |
| `hbbr.home.lcamaral.com` | WAN1 — RustDesk relay server |

Current WAN IPs: check `/conf/dyndns_*.cache` or query the REST API.

## Certificates (ACME / LetsEncrypt)

pfSense runs the **ACME package** and is the authoritative issuer for the
homelab wildcard certs. Certs live under `/conf/acme/`:

| Cert name | Subject (CN) | Expires | Files | Used by |
| --- | --- | --- | --- | --- |
| `d.lcamaral.com` | `*.d.lcamaral.com` | **2026-07-01** | `.crt` `.key` `.fullchain` `.ca` `.all.pem` | Nginx-rproxy on dockermaster (`terraform/portainer/stacks.tf:48`) |
| `home.lcamaral.com` | `home.lcamaral.com` | **2026-07-04** | same set | HAProxy shared-frontend, LAN services |
| `pfsense` | `*.home.lcamaral.com` | **2026-06-13** | same set | Web GUI, HAProxy — this is a **wildcard** for the LAN domain, not a self-signed cert |

> **Integration note**: `terraform/portainer/stacks.tf` says _"All services
> route through Nginx — certs managed by pfSense"_. This is the box it's
> talking about. Any cert rotation happens here.

## HAProxy

Installed as a pfSense package. Config at `/var/etc/haproxy/haproxy.cfg`.

**Bind listeners** (from `sockstat`):

| Address | Port | Purpose |
| --- | --- | --- |
| `127.0.0.1` | 2200 | `localstats` — local HAProxy stats socket |
| `192.168.4.1` (HOME) | 80, 443 | LAN edge — HTTP-to-HTTPS redirect + TLS frontend |
| `192.168.48.1` (SRVAN) | 443 | Server VLAN TLS frontend |
| `192.168.32.33` (ADMIN) | 80 | Management redirect |

**Frontends**: `shared-frontend` (multi-SNI), `http-to-https` (redirect)
**Backends**: `pfsense.local_ipvANY` (WebGUI passthrough via ACL
`pfsense1acl`), others TBD

## pfBlockerNG

Installed and active. Feeds deployed under `/var/db/pfblockerng/`:

- `deny/`, `match/`, `permit/` — IPv4 block/match/permit lists
- `dnsbl/`, `dnsblalias/`, `dnsblorig/` — DNS-level blocklists
- `top-1m.csv`, `pfbalexawhitelist.txt` — allowlist inputs

Default deny rule is **active** (counting hits in `pfctl -s labels`).

## Installed Packages

`Avahi`, `Cron`, `LADVD` (LLDP/CDP), `Nexus` (Netgate), `RESTAPI` (v2.7_6),
`Service_Watchdog`, `Shellcmd`, `acme`, `bandwidthd`, `haproxy`, `iperf`,
`nmap`, `node_exporter`, `pfBlockerNG`, `sudo`

## Exposed Services (from `sockstat -4l`)

| Service | Listen | Notes |
| --- | --- | --- |
| `sshd` | `*:3220` | **Non-standard SSH port** — key-based auth, root shell |
| Web GUI (Nginx) | `*:56880` | Non-standard port |
| `node_exporter` | `192.168.4.1:9100` | **Prometheus scrape target** — running and healthy |
| Unbound DNS | all VLAN gateways `:53` | DNS resolver for all VLANs |
| Unbound DoT | all VLAN gateways `:853` | DNS-over-TLS on all VLANs |
| Unbound control | `127.0.0.1:953` | Unbound control channel |
| `ntpd` | all interfaces `:123` | NTP server for LAN |
| ISC `dhcpd` | `*:67` | DHCP |
| `syslogd` | `*:514` | Remote syslog receiver |
| `avahi-daemon` | `*:5353` | mDNS |
| `miniupnpd` | `*:1900/2189` | UPnP IGD — exposed on HOME/SRVAN/ADMIN/IoT |
| HAProxy | see above | LAN TLS edge |

## Integration Points

- **Prometheus (dockermaster)**: scrapes pfSense via `node_exporter` at
  `192.168.4.1:9100` (running and healthy), plus SNMP.
- **Nginx-rproxy (dockermaster)**: consumes the `d.lcamaral.com` wildcard cert
  issued by the ACME package here.
- **Cloudflare tunnel (`bologna`)**: lives in front of Nginx-rproxy, not
  pfSense — pfSense only sees return traffic for `*.cf.lcamaral.com`.
- **DreamHost DNS**: updated by the DynDNS client for WAN tracking hostnames.
- **Proxmox**: uses pfSense as default gateway on the HOME/SRVAN/IoT bridges.

## REST API

pfSense runs `pfSense-pkg-RESTAPI-2.7_6` — 200+ endpoints for full CRUD on
firewall, routing, DNS, DHCP, HAProxy, ACME, certs, and system config.

- **Base URL**: `https://pfsense.home.lcamaral.com/api/v2`
- **Auth**: `X-API-Key` header — token from macOS Keychain (`pfsense-api-token`)
- **GraphQL**: also available at `/api/v2/graphql`
- **Full reference**: see `docs/network/pfsense-api.md`

```bash
TOKEN=$(security find-generic-password -a ${USER} -s pfsense-api-token -w)
curl -sk -H "X-API-Key: $TOKEN" https://pfsense.home.lcamaral.com/api/v2/status/system
```

## Operational Notes

- **Config backups**: `/cf/conf/config.xml` plus `config.xml.bak.*` timestamped
  copies — kept by the system. Vault does **not** back these up today.
- **SSH auth**: key-based on non-standard port **3220**, no username prompt
  (`ssh pfsense` just works via ~/.SSH/config). There is no password. Do not
  change this without coordinating with the management-workstation keys.
- **Sudo package** is installed, so non-root command execution is possible if
  later needed for an automation account.
- **`Service_Watchdog`** restarts crashed services automatically — if HAProxy
  dies it should come back within ~1 min.
- **`Shellcmd`** package runs `service node_exporter onestart` at boot — this is
  how node_exporter gets started (it's not a standard pfSense service).

## Known Gaps / Things To Verify

1. **Hardware model** — confirm Netgate 8200 vs. 6100 Max vs. custom build.
2. **WAN2 dual-IP on `igc1`** — clarify whether `192.168.12.2` is a CARP VIP,
   alias, or manual override on top of DHCP.
3. **`192.168.100.0/24` route** — what lives behind Proxmox at that subnet?
4. **Firewall rule inventory** — not captured here; `/tmp/rules.debug` has the
   full compiled ruleset if a full audit is needed.
5. **Config.XML snapshot** — not stored in this repo. Decide whether to push
   periodic redacted exports into `backups/` or into Vault.
6. **IPv6** — only IoT VLAN has ULA. No public IPv6 delegation from either WAN.
