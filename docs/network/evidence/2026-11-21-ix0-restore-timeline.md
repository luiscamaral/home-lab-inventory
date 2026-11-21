# What restored ix0 on 2026-11-16: timeline check

Collected 2026-11-21 ~07:00-07:10Z. Read-only. Sources: Thanos (switch24a `sysUpTime`), pfSense `uptime` over SSH,
and saved logs `2026-11-16-ix0-reboot-monitor.log`, `2026-11-16-home-ix0-outage.md`.
Not checked: switch syslog (NAS access denied earlier), switch CLI, Omada events for the switch, any event after 2026-11-16.

## Observed
- 15:47:14 MST: pfSense logs ix0 and its four VLANs DOWN. ix0 "no carrier" (`2026-11-16-home-ix0-outage.md`).
- 16:03 MST: one user-approved `ifconfig ix0 down/up` from pfSense. Still no carrier.
- 16:17 to 16:25 MST: pfSense unreachable on SSH (reboot). Back at 16:25:50. ix0 still `no carrier` (reboot monitor log).
  pfSense boot time from uptime (4 d 7 h 34 m at 00:01:58 MST 2026-11-21): about 16:27:58 MST.
- 16:28 to 16:44 MST: ix0 still `no carrier`, with two more short pfSense SSH gaps.
- Switch boot time from SNMP `sysUpTime` (37173175 ticks at 07:00:22Z): about 16:44:50 MST.
- 16:46:39 MST: ix0 `active`. 16:49:26: HOME HTTPS answers 503.
- switch24a `sysUpTime` at offsets 1 d, 2 d, 3 d ago: 79.3 h, 55.3 h, 31.3 h. Continuous. No switch reboot after 2026-11-16 16:44.
- pfSense uptime shows no reboot after 2026-11-16 16:28.

## Reading
- A pfSense reboot (NIC re-initialised) and a pfSense-side down/up did not restore carrier.
- Carrier came back about 2 minutes after the switch restarted.
- This points at the switch side (Te1/0/27 port or its PHY state) as the stuck end. It does not show why it stuck, and it does not explain the ongoing remote faults.
- Not excluded: the DAC (no unplug/reseat is recorded in these files).
- Discrepancy: the user described the event as "a couple days ago". The data shows 2026-11-16 (about 5 days ago) and no later switch power cycle. A later event would need its own evidence.
