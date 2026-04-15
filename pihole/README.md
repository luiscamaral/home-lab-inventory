# pihole

Internal-DNS records intended to migrate from bind9 (on dockermaster) to a
pi-hole HA pair. As of 2026-04-13 the migration is **partially done** —
the records are in pihole-1 (LXC 10000 on Proxmox at `192.168.100.254`)
and the bind9 container is still authoritative because the pfSense Unbound
forward-zone path doesn't deliver queries to pihole due to a `local-data`
collision (see [Migration status](#migration-status) below).

## Layout

| Path | Purpose |
|---|---|
| `dnsmasq.d/04-d-lcamaral-com.conf` | The translated bind9 zone for `d.lcamaral.com` in dnsmasq `address=` / `cname=` format. Deployed to pihole-1 at `/etc/dnsmasq.d/04-d-lcamaral-com.conf` and read by `pihole-FTL` after enabling `misc.etc_dnsmasq_d = true` in `/etc/pihole/pihole.toml`. |
| `lxc-hardening.md` | Pi-hole v6 config overlay for LXC environments — disables FTL NTP client, load check, and IPv6 resolver (all fail inside a Proxmox container). Apply to every pihole LXC. |

## Pi-hole inventory

| Instance | Where | IP | Status |
|---|---|---|---|
| pihole-1 | Proxmox LXC 10000 (Debian 12, Pi-hole v6.4.1) | `192.168.100.254` (vmbr0) | Running, has `04-d-lcamaral-com.conf` loaded, resolves d.lcamaral.com records correctly when queried directly. LXC hardening + ad-blocking applied 2026-04-13. |
| pihole-2 | Docker on dockerserver-1 (Pi-hole v6 image `2025.10.0`) | `192.168.59.50` (Docker-servers-net macvlan) | Deployed 2026-04-14 via `terraform/portainer/`. Healthy. dnsmasq.d injected via compose `configs:` content. All d.lcamaral.com records resolve correctly (multi-A, CNAME, NXDOMAIN, public forward). |
| pihole-3 | Docker on Synology NAS (Pi-hole v6 image `2025.10.0`) | `192.168.4.236` (home-net macvlan) | Deployed 2026-04-14 via `terraform/portainer/` (Edge agent endpoint id 6). Healthy. Same configs-injected dnsmasq.d as pihole-2. |

## Ad-blocking state (pihole-1)

As of 2026-04-13, pihole-1 has **1 adlist** subscribed:

| URL | Source | Domains | Added |
|---|---|---|---|
| `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` | StevenBlack unified-hosts | ~87 771 | 2026-04-13 |

Chosen as the conservative default (Option A from the `pihole -d`
diagnostic plan): low false-positive rate, single source, no allowlist
babysitting. Revisit when Pattern B is adopted and the LAN moves onto
pihole — more aggressive lists (OISD, 1Hosts) can be layered then.

`pihole -g` is already scheduled via `/etc/cron.d/pihole` weekly (Sunday 03:34).

## LXC hardening (pihole-1)

Four FTL v6 defaults do not work inside a Proxmox LXC. Applied
2026-04-13:

| Key | Value | Reason |
|---|---|---|
| `ntp.sync.active` | `false` | LXC lacks `CAP_SYS_TIME`; FTL NTP client can't adjust clock |
| `misc.check.load` | `false` | `/proc/loadavg` is host-wide inside the container; false "load > nproc" alerts |
| `resolver.resolveIPv6` | `false` | Container is v4-only; stops failed upstream AAAA lookups |
| `misc.nice` | `0` | LXC lacks `CAP_SYS_NICE`; default `-10` triggers warning every FTL restart |

Upstream DNS de-duplicated to single `192.168.4.1` (pfSense Unbound).

Full rationale, verify commands, and re-apply instructions in
[`lxc-hardening.md`](./lxc-hardening.md). Apply the same overlay to
`pihole-2` when it is deployed.

## Migration status

**Pattern B execution** (chosen 2026-04-14, see task #26):

The original Pattern A approach (pfSense Unbound forwards d.lcamaral.com →
pihole-1) was abandoned after the Phase 3c blocker. Switched to Pattern B
where clients query pihole as primary and pihole forwards public/unknown
queries upstream to pfSense Unbound. See "Better path forward" section
below for the full rationale.

- [x] **3a — Translate bind9 zone** to dnsmasq config
  (`04-d-lcamaral-com.conf`).
- [x] **3b — Apply records to pihole-1** and verify direct resolution.
- [x] **3e — Deploy pihole-2** on dockerserver-1 as Docker macvlan
  container (192.168.59.50). Done 2026-04-14 via Terraform.
- [x] **3e' — Deploy pihole-3** on NAS as Docker macvlan container
  (192.168.4.236). Done 2026-04-14 via Terraform — different physical
  host than pihole-1/2, survives Proxmox loss.
- [x] **3g — IaC capture** for pihole-2 + pihole-3. Stack content lives
  in `terraform/portainer/stacks/pihole-{2,3}.yml.tftpl`. The d.lcamaral
  zone is pulled from `pihole/dnsmasq.d/04-d-lcamaral-com.conf` (single
  source of truth) via `templatefile()` and injected into containers
  via Docker Compose `configs:` with inline `content:`. Re-deploy is
  automatic on file changes.
- [ ] **3f — orbital-sync DEFERRED.** Pi-hole v6 isn't supported by
  orbital-sync 1.x (uses old v5 PHP admin endpoints; Pi-hole v6 uses a
  new REST API). orbital-sync 2.x with v6 support is in progress
  upstream but not yet released as of 2026-04-14. Until then, gravity
  DB + adlist sync between piholes must be done manually via the
  Pi-hole Teleporter export/import in the v6 web UI. The dnsmasq.d
  records are not impacted — they are kept in sync automatically via
  the compose `configs:` mechanism.
- [x] **3c — pfSense DHCP option update**. Done 2026-04-14. HOME / SRVAN
  / IoT scopes now hand out `[pihole-1, pihole-2, pihole-3, pfSense]`
  (SRVAN omits pihole-3 due to cross-VLAN macvlan reachability to NAS).
- [x] **3d — Retire bind9** container. Done 2026-04-15. Removed from
  `terraform/portainer/stacks.tf`. pfSense Unbound forward-zones for
  `d.lcamaral.com` and `home` now load-balance across the three piholes
  via Custom Options multi-`forward-addr`.

## Records source of truth

All authoritative records served by the pihole HA trio live under
`pihole/dnsmasq.d/` in this repo. The Terraform pipeline reads each
file via `templatefile()` and injects them into pihole-2/-3 containers
through Docker Compose `configs:` content blocks. pihole-1 (LXC) is
updated manually via the procedure in "Manual deploy" below.

| File | Source | Owner |
|---|---|---|
| `04-d-lcamaral-com.conf` | hand-edited (translated from old bind9 `d-lcamaral-com.zone`) | repo |
| `05-home.conf` | hand-edited (translated from old bind9 `home.zone`) | repo |
| `06-host-overrides.conf` | **GENERATED** by `scripts/sync-host-overrides.py` from `pfsense/host-overrides.yml` | YAML |

The host-overrides file is dual-target: the same script that writes it
also pushes the entries to pfSense Unbound via the REST API, so pfSense
host_overrides and pihole dnsmasq records stay in lock-step.

### Workflow when records change

```bash
# d.lcamaral.com or home zones: edit the .conf file directly
$EDITOR pihole/dnsmasq.d/04-d-lcamaral-com.conf

# Host overrides: edit the YAML and re-generate
$EDITOR pfsense/host-overrides.yml
scripts/sync-host-overrides.py --apply   # writes 06-host-overrides.conf + pushes to pfSense

# Push to pihole-2 / pihole-3 (Terraform-managed)
terraform -chdir=terraform/portainer apply \
  -target=portainer_stack.pihole_2 \
  -target=portainer_stack.pihole_3

# Force-recreate the containers so Docker Compose re-renders configs
PORTAINER_PW=$(VAULT_TOKEN=$(security find-generic-password -w -s vault-root-token -a $USER) \
  VAULT_ADDR=http://vault.d.lcamaral.com vault kv get -field=admin_password secret/homelab/portainer)
JWT=$(curl -sk -X POST https://192.168.59.2:9443/api/auth \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$PORTAINER_PW\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["jwt"])')
for stack in 85; do
  curl -sk -X POST "https://192.168.59.2:9443/api/stacks/$stack/stop?endpointId=9" -H "Authorization: Bearer $JWT" >/dev/null
  sleep 2
  curl -sk -X POST "https://192.168.59.2:9443/api/stacks/$stack/start?endpointId=9" -H "Authorization: Bearer $JWT" >/dev/null
done

# Push to pihole-1 LXC (manual)
for f in 04-d-lcamaral-com.conf 05-home.conf 06-host-overrides.conf; do
  scp pihole/dnsmasq.d/$f proxmox:/tmp/$f
  ssh proxmox "SUDO_ASKPASS=\$HOME/.config/bin/answer.sh sudo -A pct push 10000 /tmp/$f /etc/dnsmasq.d/$f && \
    SUDO_ASKPASS=\$HOME/.config/bin/answer.sh sudo -A pct exec 10000 -- systemctl restart pihole-FTL && \
    rm /tmp/$f"
done
```

## Diagnostic plan for Phase 3c (next session)

The local-zone theory was wrong — `lab.home` has the same shape and
works. The real cause is most likely DNSSEC or cache. Diagnostic plan:

1. **Re-apply the forward-zone change** (PATCH custom_options to remove
   hardcoded forward, PATCH domain override to point at pihole, kill
   unbound, apply, restart).

2. **Verify state** with `grep -A3 "name: \"d.lcamaral.com\"" /var/unbound/unbound.conf`
   — the hardcoded forward should be gone, and the only forward should
   be from `domainoverrides.conf` pointing at .100.254.

3. **Force a totally unique fresh query** that has never been resolved
   before: `drill never-used-$(date +%s).d.lcamaral.com @127.0.0.1`.
   Watch the unbound resolver log in parallel:
   `tail -F /var/log/resolver.log | grep -iE "d.lcamaral|192.168.100"`

4. **Check the AUTHORITY section** of any failed answer. If it's a
   `lcamaral.com SOA from DreamHost`, the query went upstream. If it's
   something else, different cause.

5. **Test with `+bufsize=4096 +cd`** (CD = checking-disabled, skips
   DNSSEC) on the drill query. If that succeeds where the normal
   query fails, DNSSEC validation is the cause.

6. **Verify `domain-insecure: d.lcamaral.com`** is in the live
   unbound.conf and applies — search for it after restart and confirm
   it's at the right scope.

## Better path forward — switch to "Pattern B"

Rather than continue debugging the pfSense forward path, consider
restructuring as **Pattern B (collaboration)**:

- Clients use **pihole** as their primary DNS (DHCP option), with
  pfSense as secondary/fallback
- Pihole answers everything it knows authoritatively (lab.home,
  d.lcamaral.com, ad-blocking)
- Pihole's upstream is pfSense Unbound (already configured this way:
  `server=192.168.4.1` in pihole's dnsmasq.conf)
- pfSense Unbound recurses to internet for public DNS, serves
  `*.home.lcamaral.com` host overrides, handles DHCP-derived hostnames

Pros:

- Bypasses the Phase 3c blocker entirely (no pfSense → pihole forward
  needed)
- Brings ad-blocking to all LAN clients (currently only k8s lab subnet
  uses pihole)
- Clean separation: pihole owns ad-blocking + dev/Docker records,
  pfSense owns recursion + home-device records
- HA via DHCP serving multiple resolvers in priority order

Cons:

- Requires DHCP scope updates on pfSense (per-VLAN)
- Pi-hole becomes a (single) point in the data path for client DNS;
  mitigated by pfSense as the secondary

Decision pending — discuss next session.

## Design rationale (next-session reference)

Captured 2026-04-13 after a long Q&A. Covers the HA topology, loop
prevention, caching, sync, DHCP, and authority boundaries so the next
session can execute without re-deriving the architecture.

### Target topology — 3-node pihole HA

| Instance | Where | IP | Physical host |
|---|---|---|---|
| **pihole-1** | Proxmox LXC 10000 (existing, don't touch) | `192.168.100.254` (vmbr0) | Proxmox |
| **pihole-2** | New Docker stack via Portainer on dockerserver-1, macvlan | e.g. `192.168.59.50` | Proxmox (same box as pihole-1) |
| **pihole-3** | New Docker stack via Portainer **on the NAS** (Portainer Edge endpoint id 6) | e.g. `192.168.4.236` in NAS `home-net` macvlan | NAS (different physical box) |

Three instances across two physical machines. If Proxmox dies, pihole-3
still serves. If NAS dies, pihole-1 + pihole-2 cover.

Container requirements (baked-in lessons from today):

- `image: pihole/pihole:2025.xx` (match pihole-1's v6 line — required
  for orbital-sync compatibility)
- `dns: [192.168.48.1, 1.1.1.1]` — macvlan containers can't use
  Docker's 127.0.0.11 embedded DNS
- `restart: unless-stopped`
- Static macvlan IPs
- Local volumes for `/etc/pihole/` and `/etc/dnsmasq.d/` (NOT NFS —
  orbital-sync needs distinct datastores per instance)
- Env: `WEBPASSWORD`, `TZ`, `FTLCONF_LOCAL_IPV4`
- Apply the same `lxc-hardening.md` overlay adapted for Docker where
  relevant (load check, IPv6, NTP — cgroups may also need `misc.check.load`
  disabled since `/proc/loadavg` inside a container still reports the
  host's load average)

### Loop prevention (the circular-dependency question)

Pi-hole forwarding public queries to pfSense Unbound is safe **only if**
pihole is marked authoritative for its owned zones, otherwise an
unmatched query like `unknown.d.lcamaral.com` loops:
pihole → upstream pfSense → pfSense forwards d.lcamaral.com back → pihole
→ upstream → pfSense → ...

Fix: add `local=/<zone>/` lines to each dnsmasq.d file. `local=` tells
dnsmasq "I own this zone — return NXDOMAIN for unmatched names, do NOT
forward upstream." Loop closed:

```conf
# In pihole/dnsmasq.d/04-d-lcamaral-com.conf
local=/d.lcamaral.com/           # authoritative marker
address=/vault.d.lcamaral.com/192.168.59.28
address=/vault.d.lcamaral.com/192.168.59.48
# ... etc
```

Same goes for any other zone pihole owns authoritatively (e.g.
`local=/lab.home/` if/when those records are repo-managed).

### Caching

pihole-FTL has a built-in dnsmasq cache, size `10000` by default (set
in `/etc/pihole/dnsmasq.conf`). TTLs from upstream answers are honored.
In Pattern B this gives three wins for free:

1. Per-client query visibility in the pihole UI (pfSense sees only
   "client pihole" in that flow).
2. Sub-millisecond repeat-query response for cached answers.
3. Reduced recursive load on pfSense Unbound.

Cache is in-process memory — clears on `pihole-FTL` restart.

### orbital-sync

**Self-scheduled.** The official container exposes `INTERVAL_MINUTES`
(or `INTERVAL_HOURS`) — runs in a loop, no external cron required.
Uses Pi-hole's HTTP Teleporter API, not SSH — simpler than the legacy
gravity-sync model.

```yaml
services:
  orbital-sync:
    image: mattwebbio/orbital-sync:latest
    restart: unless-stopped
    environment:
      PRIMARY_HOST_BASE_URL: "http://192.168.100.254"
      PRIMARY_HOST_PASSWORD: "<pihole-1 password>"
      SECONDARY_HOST_1_BASE_URL: "http://192.168.59.50"
      SECONDARY_HOST_1_PASSWORD: "<pihole-2 password>"
      SECONDARY_HOST_2_BASE_URL: "http://192.168.4.236"
      SECONDARY_HOST_2_PASSWORD: "<pihole-3 password>"
      INTERVAL_MINUTES: "60"
      VERBOSE: "true"
```

**What orbital-sync DOES sync:** adlists, gravity DB, whitelist,
blacklist, regex rules, `pihole.toml` `dns.hosts` array, custom CNAMEs,
groups + clients.

**What orbital-sync does NOT sync:** `/etc/dnsmasq.d/*.conf` files.
These live outside the Teleporter backup scope.

So: if records live in `dnsmasq.d/*.conf` files (what we did today),
orbital-sync doesn't sync them — we need a different mechanism.
If records live in `pihole.toml` `dns.hosts`, orbital-sync DOES sync them
but toml-editing is awkward for IaC.

### Hybrid Option C — records via IaC, gravity via orbital-sync

The cleanest split:

| Concern | Mechanism | Why |
|---|---|---|
| Authoritative records (`d.lcamaral.com` etc.) | **Terraform writes the same `dnsmasq.d/*.conf` content to all 3 piholes** via volume bind mounts or Portainer stack re-deploys | IaC owns records; single source of truth in git; atomic all-or-nothing deploys; audit trail |
| Ad-block lists and gravity DB | **orbital-sync** scheduled hourly, pihole-1 → pihole-2/3 | Native to Pi-hole, handles gravity refresh automatically, runtime-friendly |
| Web-UI changes on pihole-1 | Limited to ad-block list subscriptions (repo-managed records are read-only from the UI's perspective) | Keeps UI changes out of the repo-authoritative path |
| Public DNS recursion | pfSense Unbound (unchanged) | pfSense is already doing this well |

### DHCP role — stays on pfSense

DHCP is NOT migrating to pihole. pfSense ISC dhcpd keeps serving every
VLAN scope as it does today. The only DHCP change for Pattern B is
updating the **DNS server option** per scope to hand out piholes first
with pfSense as the last-resort fallback:

```text
HOME VLAN scope DNS servers (in priority order):
  192.168.100.254   # pihole-1
  192.168.59.50     # pihole-2 (when deployed)
  192.168.4.236     # pihole-3 (when deployed)
  192.168.4.1       # pfSense Unbound (fallback)
```

Four-layer DNS HA via DHCP option ordering, no new infrastructure.
Needs the same update on HOME, SRVAN, IoT (and GUEST if desired).
pfSense GUI or API per scope.

**Why keep DHCP on pfSense:**

- pfSense ISC dhcpd has multi-VLAN scopes, user-alias filtering, and
  static reservations already configured — rebuilding on pihole buys
  nothing
- pfSense's `dhcpleases` process auto-updates Unbound's
  `dhcpleases_entries.conf` so DHCP-derived hostnames resolve as
  `<host>.home.lcamaral.com` — a critical integration that would
  break if DHCP moved
- pfSense DHCP is a SPOF either way (pfSense IS the router); same
  blast radius as today, no regression
- Pi-hole's DHCP is designed for single-pihole-as-router deployments,
  doesn't cluster, and loses the dhcpleases → Unbound pipeline

### DHCP-derived hostname resolution path in Pattern B

Concrete example, laptop `MacBook-Pro-LA-M2` on HOME VLAN:

```text
1. Laptop gets lease from pfSense → IP 192.168.0.7
2. pfSense dhcpleases writes local-data to Unbound:
   "MacBook-Pro-LA-M2.home.lcamaral.com. A 192.168.0.7"
3. Another LAN device queries the hostname
4. Query hits pihole-1 (DHCP option = pihole first)
5. Pihole has no record for *.home.lcamaral.com
6. Pihole forwards upstream → pfSense Unbound
7. pfSense Unbound answers from local-data
8. Pihole caches the answer and returns it
9. Subsequent queries for the same name hit pihole's cache directly
```

Result: DHCP-derived hostnames resolve correctly, plus pihole caches
them for free, plus pihole logs them for visibility.

### Authority boundaries — who owns what

```text
DHCP authority:          pfSense ISC dhcpd (unchanged)
  └ hands out DNS:       [pihole-1, pihole-2, pihole-3, pfSense]

DNS authority tiers:
  ┌─ pihole (tier 1, client-facing)
  │    authoritative:   d.lcamaral.com, lab.home (via local= + address=)
  │    feature:         ad-blocking (gravity DB, adlists)
  │    cache:           10000 entries for all upstream answers
  │    forwards to:     pfSense Unbound (upstream=192.168.4.1)
  │
  └─ pfSense Unbound (tier 2, recursive)
       authoritative:   *.home.lcamaral.com, *.iot.lcamaral.com,
                        *.admin.lcamaral.com (via host_entries.conf +
                        dhcpleases_entries.conf)
       recursive:       public DNS (.com, .org, etc.) with DNSSEC
       fallback target: also in DHCP option list as last resort
```

Each tool plays to its strengths:

- **pihole** = ad-blocking + dev/Docker records + UI + caching
- **pfSense Unbound** = recursive public DNS + device hostnames + DHCP
  integration
- **Terraform** = single source of truth for dnsmasq.d records across
  all pihole instances
- **orbital-sync** = gravity/adlist sync across pihole instances

### DHCP caveats worth remembering

1. **Client DNS server ordering matters.** Clients prefer the first
   listed DNS server. Pihole first, pfSense last — otherwise clients
   bypass pihole and you lose ad-blocking.
2. **DHCP option changes aren't instant.** Clients pick up new DNS
   option at lease renewal. Default pfSense lease is ~2 hours, so
   worst-case 2-hour rollout after changing the scope.
3. **DHCP itself is still a SPOF on pfSense.** Separate (bigger)
   problem; not something Pattern B addresses. ISC dhcpd supports
   `failover-peer` if you ever want a second DHCP server.

## Manual deploy of dnsmasq.d to pihole-1

```bash
# Translate file → LXC
scp pihole/dnsmasq.d/04-d-lcamaral-com.conf proxmox:/tmp/
ssh proxmox 'sudo -n pct push 10000 /tmp/04-d-lcamaral-com.conf /etc/dnsmasq.d/04-d-lcamaral-com.conf'

# Enable etc_dnsmasq_d (one-time)
ssh proxmox 'sudo -n pct exec 10000 -- /bin/bash -c "sed -i \"s/etc_dnsmasq_d = false/etc_dnsmasq_d = true/\" /etc/pihole/pihole.toml"'

# Reload
ssh proxmox 'sudo -n pct exec 10000 -- /bin/bash -c "systemctl restart pihole-FTL"'

# Test direct
dig +short @192.168.100.254 vault.d.lcamaral.com  # expect 3 A records
```
