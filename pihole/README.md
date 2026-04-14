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

## Pi-hole inventory

| Instance | Where | IP | Status |
|---|---|---|---|
| pihole-1 | Proxmox LXC 10000 (Debian 12, Pi-hole v6.3.3) | `192.168.100.254` (vmbr0) | Running, has `04-d-lcamaral-com.conf` loaded, resolves d.lcamaral.com records correctly when queried directly |
| pihole-2 | not deployed | — | Phase 3e — defer until Phase 3c-d unblocked |

## Migration status

**Phase progression** (see task #26):

- [x] **3a — Translate bind9 zone** to dnsmasq config
  (`04-d-lcamaral-com.conf`).
- [x] **3b — Apply records to pihole-1** and verify direct resolution.
- [ ] **3c — pfSense Unbound forward** to pihole-1. _Reverted_ on
  2026-04-13. The pfSense Unbound forward-zone for
  `d.lcamaral.com -> 192.168.100.254` was configured correctly via the
  API (both `domainoverrides.conf` and `custom_options` cleaned up), but
  Unbound never actually delivered queries to pihole. The blocking issue
  is that `host_entries.conf` has
  `local-data: "hbbs.d.lcamaral.com. A 192.168.59.10"` and
  `local-data: "hbbr.d.lcamaral.com. A 192.168.59.11"` — these create
  an implicit `local-zone "d.lcamaral.com."` that intercepts ALL queries
  for the zone, returning NODATA for anything not in the explicit
  local-data instead of falling through to the forward.
- [ ] **3d — Stop bind9** container.
- [ ] **3e — Deploy pihole-2** on ds-2 as Docker macvlan container.
- [ ] **3f — Configure orbital-sync** between pihole-1 and pihole-2.
- [ ] **3g — IaC capture + commit final state**.

## Three fix paths for Phase 3c (pick one next session)

1. **Add explicit `local-zone "d.lcamaral.com." transparent`** to pfSense
   Unbound's `custom_options`. This _should_ force the implicit local-zone
   to be transparent (which is the documented default) but pfSense may be
   setting it to "static" implicitly. Easy to test.

2. **Move `hbbs.d.lcamaral.com` and `hbbr.d.lcamaral.com` OUT of pfSense
   host overrides INTO pihole records.** With no local-data for
   `d.lcamaral.com` in pfSense, Unbound has nothing to intercept and the
   forward-zone takes over. This is the cleanest long-term fix because
   all `d.lcamaral.com` records live in one place (pihole).

3. **Use `stub-zone` instead of `forward-zone`** in domainoverrides.conf.
   Stub zones bypass the local-zone interception because they're treated
   as authoritative delegations. May require directly editing the
   generated unbound.conf since pfSense's domain override UI only emits
   forward-zones.

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
