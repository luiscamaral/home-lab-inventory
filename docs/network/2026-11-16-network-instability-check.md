# Network instability check, 2026-11-16 17:04 to 17:18 MST

Status: read-only check. Nothing was changed.
Raw files: `docs/network/evidence/2026-11-16-instability-check/`.

## Scope

| Source | Access | Checked |
|---|---|---|
| pfSense | SSH, read-only | Yes |
| switch24a (`192.168.32.39`) | SNMP v2c from pfSense. Community read from Vault and kept out of all files | Yes |
| NAS | SSH as `lamaral`, no sudo | Yes. `/var/log/messages` and `docker` were not readable |
| Thanos query (`192.168.59.26:10902`) | HTTP API | Yes |
| Mac on HOME Wi-Fi (`192.168.0.7`) | Local ping and TCP | Yes |
| Omada events, the AP-2.5G switch, Proxmox, Wi-Fi APs | Not checked | No |

## Findings

### F1. The ix0 remote-fault bursts started again at about 17:10:30

- After ix0 came back at 16:46:26, the remote-fault rate was 0 for about 24 minutes (`thanos-rf-burst-40m.txt`).
- The counter went from 16 at 17:08:34 to 619,372 at 17:15:50 (`pfsense-counters-3min.txt`,
  `pfsense-after-te27-lastchange.txt`).
- Direct sample, 17:15:58 to 17:16:43: about 2,260 per second (`live-rf-and-switch-5x.txt`).
- Direct sample, 17:17:36 to 17:18:07: about 2,100 per second (`pfsense-parallel-ping-final.txt`). The Thanos 2-minute
  rate showed about 1,000 per second. The two methods do not agree. The cause of the gap is unknown.
- Loss at 1400 bytes to `192.168.48.44`: 0 percent at 17:05, then 4 to 6 percent at 17:16. Thanos showed the same rise
  (`thanos-rf-burst-40m.txt`).
- Loss at 56 bytes from pfSense at 17:17: 0 to 2.7 percent on all LAN targets (`pfsense-parallel-ping-final.txt`).
- Switch side: `Te1/0/27` input errors rose about 3.5 per second (`live-rf-and-switch-5x.txt`).
- Link stayed up on pfSense. Local faults and CRC errors did not change.
- Traffic on ix0 was 3 to 40 Mb/s. Load does not explain the burst.

### F2. Only the switch reboot brought ix0 back after the 15:47 outage

- The switch uptime was 0:29:59 at 17:14:41. The switch therefore booted at about 16:44:41
  (`switch-snmp-10g-delta.txt`).
- pfSense `igc3` (switch port `Gi1/0/23`) went down at 16:44:21 and up at 16:46:21. ix0 came up at 16:46:26
  (`pfsense-logs-gw.txt`).
- All four NAS copper ports went down and up together, about 16:45:07 to 16:47:06 (`nas-dmesg-link-events.txt`). These
  times come from `dmesg` and may be off by tens of seconds.
- The earlier ix0 restart and the pfSense power cycle did not restore carrier (`2026-11-16-home-ix0-outage.md`).
- Direct observation: carrier returned only after the switch rebooted. Hypothesis: the switch port `Te1/0/27` was
  stuck. This is not proven. A combined fault at both ends is still possible.

### F3. `Te1/0/25` (AP-2.5G switch uplink) has a growing error rate

- Input errors: 62,482 at 17:14:41 and 64,403 at 17:15:41. That is about 1,900 per minute (`switch-snmp-10g-delta.txt`).
- Earlier today, at 13:54 MST, the same port showed 214 per minute (`2026-11-16-ix0-switch-evidence.md`). The new rate
  is about 9 times higher.
- `Te1/0/28` (Proxmox) has 0 errors. `Te1/0/26` stays at 49.

### F4. The NAS lost network reach twice while ix0 was clean

- Two events: 16:58 (about 1 minute) and 17:02 to 17:05 (about 3 minutes).
- In both, Prometheus replica B on the NAS lost almost all targets. At the same time, replica A on ds-1 lost the
  NAS-hosted targets (`thanos-up-per-replica-30m.txt`, `thanos-replica-down-detail.txt`).
- The remote-fault rate was 0 during both events. ix0 did not go down.
- The NAS kernel log shows no link event in that window (`nas-dmesg-link-events.txt`).
- At 17:09, pfSense pings to the NAS showed (`pfsense-ping-nas.txt`):
  - `192.168.2.50` (`eth4.10`, 2.5G, MTU 9000): 29 percent loss at 56 bytes, 11 percent at 1400 bytes
  - `192.168.4.237` (Prometheus replica B container, `prometheus-2`): 69 percent loss
  - `192.168.0.50`, `192.168.1.50`, `192.168.32.50` (copper and LAG): 0 to 1 percent loss
- At 17:17, the same paths showed 0.7 to 2 percent loss.
- The NAS `eth4` counters show 0 errors and 0 drops (`nas-macvlan-eth4.txt`).
- The NAS default route uses `eth4.10`. Three NAS interfaces share `192.168.0.0/20`. Policy routing rules exist for
  each source address.
- Hypothesis: the NAS `eth4` path runs through the AP-2.5G switch and `Te1/0/25` (F3). The 2.5G link speed suggests
  this. The physical path was not checked.

### F5. Brief ADMIN link flap

pfSense `igc3` went down at 17:05:59 and up at 17:06:02. The switch `Gi1/0/23` last-change time agrees
(`switch-port-lastchange.txt`). The cause is unknown.

The switch also shows a `Te1/0/27` last-change at about 17:15:38. pfSense logged no ix0 link change at that time. This
is not explained.

### F6. WAN is healthy

- Both gateways had 0 percent loss over the last 15 minutes (`thanos-post-recovery-15m.txt`, `pfsense-logs-gw.txt`).
- 24-hour average loss on WAN1 was 0.03 percent. The worst sample was 9 percent.
- pfSense to `8.8.8.8`: 0 percent loss at 1400 bytes (`pfsense-ping-1400.txt`).

### F7. Other observations

- The ix0 watchdog is paused and disarmed (no-bounce flag). If ix0 goes dark again, it will not act
  (`thanos-network-health.txt`).
- The Mac on Wi-Fi saw 3.3 percent loss and up to 93 ms delay to its gateway (`mac-ping.txt`). This was not separated
  from the wired faults.
- The Mac gets no ICMP replies from the NAS. TCP to the NAS works (`mac-nas-tcp.txt`). The cause was not checked.
- Switch port counters are not in Prometheus. Only pfSense `ifInErrors` series were found (`thanos-network-health.txt`).

## Not established

- Which part causes the ix0 remote faults: the pfSense NIC port, the DAC, or switch port `Te1/0/27`.
- Whether F1 and F3 share a cause in the switch.
- The physical path of NAS `eth4`.
- Why the burst restarted at 17:10.
