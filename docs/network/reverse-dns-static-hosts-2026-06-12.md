# Reverse DNS (PTR) for static hosts — diagnosis & fix

**Date:** 2026-06-12
**Status:** ✅ Deployed & verified 2026-06-12 — `dns.bogusPriv=false` on all
three piholes; `PTR 192.168.1.44` → `GARAGE-WIFI-PROBE.home.lcamaral.com`
resolves trio-wide.
**Scope:** Static hosts only. Dynamic DHCP leases stay out (no `regdhcp`).

## 🐛 Symptom

```text
$ nslookup -type=PTR 192.168.1.44 192.168.100.254   # pihole-1
** server can't find 44.1.168.192.in-addr.arpa: NXDOMAIN
```

## 🔬 Root cause (proven by boundary test)

| Query | pfSense Unbound `192.168.4.1` | pihole-1 `192.168.100.254` |
|---|---|---|
| PTR `192.168.1.44` | ✅ `GARAGE-WIFI-PROBE.home.lcamaral.com` | ❌ NXDOMAIN |
| PTR `192.168.4.1` | ✅ `pfsense.home.lcamaral.com` | ❌ NXDOMAIN |

- **pfSense Unbound already has the reverse data.** The static DHCP mapping is
  registered (forward + PTR) — `regdhcpstatic` is on. **The pfSense side needs
  no change.**
- **pihole NXDOMAINs _every_ private PTR** (even the gateway's) while resolving
  forward names fine. That asymmetry is the signature of Pi-hole v6's default
  **`dns.bogusPriv = true`** — _"never forward reverse lookups for private IP
  ranges; answer NXDOMAIN locally."_
- The pihole trio's only upstream is **pfSense Unbound itself**
  (`FTLCONF_dns_upstreams: 192.168.4.1`), which is authoritative for these
  reverse zones. So `bogusPriv` is not protecting against a public-DNS leak —
  it is breaking the intended pihole → Unbound reverse path.

**This is a forwarding misconfiguration on pihole, not a missing record.**
Earlier theories about `host-overrides.yml` being forward-only were a red
herring — the probe is already known to Unbound; hand-maintaining PTRs in
pihole would mask the real problem.

## 🛠️ Fix — pihole trio only

Make pihole forward private-range reverse queries to its Unbound upstream.

### Preferred: disable `bogusPriv`

Safe here because the sole upstream is your own authoritative resolver. Private
IPs Unbound doesn't know still return NXDOMAIN at Unbound (correct), so dynamic
leases stay unresolved exactly as desired.

**pihole-2 / pihole-3** (`terraform/portainer/stacks/pihole-{2,3}.yml.tftpl`),
add next to the other `FTLCONF_dns_*` keys:

```yaml
      FTLCONF_dns_bogusPriv: "false"
```

then `terraform -chdir=terraform/portainer apply`.

**pihole-1 LXC** (same pattern as the `dns.upstreams` override in
`lxc-hardening.md`):

```bash
ssh proxmox 'sudo -n pct exec 10000 -- pihole-FTL --config dns.bogusPriv false'
ssh proxmox 'sudo -n pct exec 10000 -- systemctl restart pihole-FTL'
```

### Alternative: surgical `rev-server` routes

If you prefer to keep `bogusPriv` protective and only forward specific
in-house subnets, add a managed `pihole/dnsmasq.d/07-reverse.conf` with one
line per internal subnet (forwarded to Unbound, exempt from bogus-priv):

```conf
rev-server=192.168.1.0/24,192.168.4.1
rev-server=192.168.4.0/24,192.168.4.1
# … one per pfSense-served subnet
```

Trade-off: more precise, but you must enumerate every subnet and keep the list
current — miss one and its reverse silently breaks. Disabling `bogusPriv` needs
no per-subnet maintenance.

## 📈 Cache quality — is forward + cache good enough?

Measured against Unbound (`dig -x`, 2026-06-12):

- **Positive answers: 3600s (1h), fixed.** Unbound serves these PTRs
  authoritatively; pihole caches each reverse hit for an hour. Upstream is the
  gateway — no failure mode beyond what forward resolution already carries.
- **Negative answers: up to 10800s (3h).** The `168.192.in-addr.arpa` SOA
  minimum is 10800. A reverse query for an IP Unbound doesn't know yet (a
  _newly-added_ static mapping, or any dynamic lease) is NXDOMAIN-cached on the
  trio for up to 3h.

Implication: after adding a static DHCP reservation, its reverse may be
shadowed by a stale NXDOMAIN for up to 3h. Two ways to keep cache "good
enough":

1. **Flush on change** — `pihole reloaddns` (or restart pihole-FTL) on the trio
   after editing static mappings. Zero standing cost.
2. **Bound the staleness** — add `neg-ttl=300` to a managed `dnsmasq.d` file so
   stale NXDOMAINs expire in ≤5 min without a manual flush. Negligible extra
   upstream load; does not affect ad-blocking (gravity blocks are positive
   answers, not NXDOMAIN).

Verdict: **good enough.** Positive caching is the common path and is solid;
the only sharp edge is the 3h negative cache on brand-new mappings, covered by
either mitigation above.

## ✅ Verify

```bash
for s in 192.168.100.254 192.168.59.50 192.168.4.236; do
  echo "== $s =="; nslookup -type=PTR 192.168.1.44 $s
done
# expect: 44.1.168.192.in-addr.arpa  name = GARAGE-WIFI-PROBE.home.lcamaral.com
```

## 🚫 Out of scope

- **Dynamic DHCP leases** — `regdhcp` stays off; dynamic PTRs not served. With
  `bogusPriv` off, pihole forwards their reverse queries to Unbound, which
  returns NXDOMAIN (no dynamic registration) — the intended outcome.
- **`host-overrides.yml` changes** — none needed. Reverse comes from pfSense's
  static-mapping registration, not the host-override pipeline.

## 📄 Documentation touched

- `pihole/README.md` — "Reverse DNS (PTR) for static hosts" section.
- `pihole/lxc-hardening.md` — `dns.bogusPriv` override for pihole-1.
- This file.
