# LXC hardening overlay for Pi-hole v6 on Proxmox

FTL v6 assumes a bare-metal host. Four defaults misbehave inside a
Proxmox LXC (even privileged) because the container shares `/proc`
with the host and lacks `CAP_SYS_TIME` and `CAP_SYS_NICE`. Applying
the deltas below silences recurring alerts and failed syscalls
without touching DNS service behavior.

Applies to: `pihole-1` (Proxmox LXC 10000, 192.168.100.254). Apply to
`pihole-2` when it is deployed (Phase 3e).

## Deltas against Pi-hole v6 defaults

| Key | Default | LXC value | Reason |
|---|---|---|---|
| `ntp.sync.active` | `true` | **`false`** | FTL NTP client calls `clock_settime()`; LXC has no `CAP_SYS_TIME` → recurring `Insufficient permissions` errors every ~1h. Proxmox host owns the clock, container inherits it. |
| `misc.check.load` | `true` | **`false`** | FTL reads `/proc/loadavg` which is host-wide inside an LXC. A 20-core Xeon at idle load 4-5 trips the "load > nproc" alert in a 1-2 CPU container. False alarm. |
| `resolver.resolveIPv6` | `true` | **`false`** | LXC is v4-only (no IPv6 address on `eth0`, no IPv6 gateway). Setting this false stops FTL from attempting upstream AAAA lookups. Reverse the day IPv6 is added to the LXC. Note: `pihole -d` still shows a hardcoded `[✗] Failed to resolve doubleclick.com via 2001:4860:4860::8888` line because the debug script tests v6 reachability unconditionally; that is a script artifact, not a runtime issue. |
| `misc.nice` | `-10` | **`0`** | FTL tries to renice itself to -10 on startup; LXC lacks `CAP_SYS_NICE` → `WARNING: Insufficient permissions to set process priority` on every restart. Workload doesn't need elevated priority in a near-idle container. |

## `[ntp.ipv4]` and `[ntp.ipv6]` stay `active = true`

Those control pihole's NTP **server** role (serving time to DHCP
clients as the `ntp-server` DHCP option). Serving time does not
require `CAP_SYS_TIME`, only setting the local clock does. Keep the
server role enabled.

## Apply commands

```bash
# Run inside the LXC (or via ssh root@192.168.100.254):
pihole-FTL --config ntp.sync.active false
pihole-FTL --config misc.check.load false
pihole-FTL --config resolver.resolveIPv6 false
pihole-FTL --config misc.nice 0
systemctl restart pihole-FTL
```

The first three are picked up by FTL's live-reload, but `misc.nice`
is only read on process start — always include a restart.

FTL reloads configuration automatically; no manual restart needed.

## Verify

```bash
# Should all return the hardened values:
pihole-FTL --config ntp.sync.active       # false
pihole-FTL --config misc.check.load       # false
pihole-FTL --config resolver.resolveIPv6  # false
pihole-FTL --config misc.nice             # 0

# Should NOT show new NTP permission errors or load warnings:
tail -f /var/log/pihole/FTL.log

# pihole -d "Pi-hole diagnosis messages" section should be empty
# (or contain only new, unrelated messages).
pihole -d 2>&1 | awk '/Pi-hole diagnosis messages/,/DIAGNOSING/'
```

## Host-side: locale

Debian LXC template ships without a generated locale. Fixes the
`setlocale: LC_ALL: cannot change locale (en_US.UTF-8)` warning on
every SSH login.

```bash
apt-get install -y locales
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
```

## Upstreams

The v6 web UI saves duplicated upstreams when only one slot is
filled. De-dup:

```bash
pihole-FTL --config dns.upstreams '["192.168.4.1"]'
```

Single upstream is fine for now — pihole-1's upstream is pfSense
Unbound on 192.168.4.1 which itself does recursion. A real secondary
can be added in Phase 3e once pihole-2 is deployed (and even then,
do not make pihole-2 the upstream of pihole-1 — that is circular;
add pfSense directly on a second VIP or add a non-homelab resolver
as a fallback).
