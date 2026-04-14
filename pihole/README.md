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
| pihole-1 | Proxmox LXC 10000 (Debian 12, Pi-hole v6.4.1) | `192.168.100.254` (vmbr0) | Running, has `04-d-lcamaral-com.conf` loaded, resolves d.lcamaral.com records correctly when queried directly. LXC hardening + ad-blocking applied 2026-04-13 (see below). |
| pihole-2 | not deployed | — | Phase 3e — defer until Phase 3c-d unblocked |

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

**Phase progression** (see task #26):

- [x] **3a — Translate bind9 zone** to dnsmasq config
  (`04-d-lcamaral-com.conf`).
- [x] **3b — Apply records to pihole-1** and verify direct resolution.
- [ ] **3c — pfSense Unbound forward** to pihole-1. _Reverted_ on
  2026-04-13. The pfSense Unbound forward-zone for
  `d.lcamaral.com -> 192.168.100.254` was configured correctly via the
  API (both `domainoverrides.conf` and `custom_options` cleaned up), but
  Unbound never actually delivered queries to pihole. **The original
  local-zone interception theory is wrong** — the existing
  `lab.home -> pihole-1` forward also has a `local-data` entry inside
  the zone (`pihole.lab.home`) and works fine. Real cause is unknown,
  more likely DNSSEC chain validation against the parent `lcamaral.com`
  zone, or stale negative cache from before the forward took effect.
  Empty `drill vault.d.lcamaral.com` answers had a `lcamaral.com. SOA`
  from DreamHost in the AUTHORITY section — that's the smoking gun:
  the query went UPSTREAM to public DNS and got NODATA, bypassing the
  forward entirely. `domain-insecure: d.lcamaral.com` is supposed to
  prevent that but evidently didn't apply during the test.
- [ ] **3d — Stop bind9** container.
- [ ] **3e — Deploy pihole-2** on ds-2 as Docker macvlan container.
- [ ] **3f — Configure orbital-sync** between pihole-1 and pihole-2.
- [ ] **3g — IaC capture + commit final state**.

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

Recommended: **option 2** (longer-term clean), with option 1 as a quick test.

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
