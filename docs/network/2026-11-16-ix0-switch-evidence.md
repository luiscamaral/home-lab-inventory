# ix0 and switch24a evidence, 2026-11-16

## Scope

Read-only checks on 2026-11-16 (UTC). No configuration was changed.

| Source | Access | Time (UTC) |
|---|---|---|
| pfSense (`ix0`, counters, logs) | SSH, read-only | 20:39 to 20:55 |
| Omada Controller 6.2.10.17, site `LAHome` | Internal API, read-only GET calls | 20:49 to 20:52 |
| switch24a (`192.168.32.39`, TL-SG3428X) | SNMP v2c, read-only | 20:51 to 20:55 |

Not checked: switch CLI, switch web UI, Omada port error counters (not exposed by the API), NIC or DAC hardware counters beyond what pfSense reports.

Raw files: `docs/network/evidence/2026-11-16-ix0/`.

## E6: pfSense sampling, 273 seconds

File: `pfsense-samples-5min.txt` (10 samples, 30 s apart, 20:50:39 to 20:55:12).

| Metric | Result |
|---|---|
| Remote faults | +240,122 over 273 s, **880 per second** (per-sample range 24,386 to 28,926) |
| Local faults | No change (2,985) |
| CRC errors | No change (9) |
| Input errors, `ix0` | No change (22) |
| Output errors, `ix0` | No change (0) |
| Link | Active, 10 Gbps, full duplex, `rxpause,txpause` negotiated |

Note: My earlier figure of 464 per second came from a 5-second sample. The longer sample gives 880 per second. Rates vary over time.

## E7: Driver and log evidence on pfSense

File: `pfsense-driver-logs-2026-11-16.txt`.

- Driver setting `dev.ix.0.fc = 3`. This means pause frames are enabled in both directions on pfSense.
- Driver firmware: `eTrack 0x800003de`.
- The `dmesg` output has no link or PHY error lines.
- The system log shows repeated ARP "moved" messages on `ix0.28` (VLAN 28, Servers). Examples:
  - `192.168.59.33` moves between `02:00:00:00:00:21` and `b2:43:bf:e5:8a:66`.
  - `192.168.48.44`, `.45`, `.46` move between two MAC addresses each.
  - `192.168.59.3` and `192.168.59.1` also move.

  This means at least one IP address appears on two devices. This is a separate L2 or IP-address issue. It does not prove the cause of the link faults.

## E8: Omada port data for ports 25 to 28

File: `omada-switch-ports-25-28.json`. Omada API GET calls only.

| Port | Profile | Link | Speed/duplex | Flow control | Edge port (STP) |
|---|---|---|---|---|---|
| 25 (AP-2.5G switch) | Trunk-v2 | Up | 10G full | Off | Yes |
| 26 (HomeOffice) | HomeOffice-v2 | Up | 10G full | Off | Yes |
| **27 (pfSense `ix0`)** | **Trunk-v2** | **Up** | **10G full** | **Off** | **Yes** |
| 28 (Proxmox) | Trunk-v2 | Up | 10G full | Off | Yes |

Observations:

- Port 27 flow control is **off**. pfSense has pause frames **on** (`fc=3`). This is a configuration difference. It is not proven to cause the faults.
- Port 27 has STP edge-port mode enabled. It connects to a router, not an end device. This is a configuration observation.
- Omada shows port byte counters for port 27 but no error counters.

## E9: switch24a SNMP counters, Te1/0/27 (ifIndex 49179)

File: `switch-te1-0-27-snmp.txt`.

| Counter | Value (20:52:52) | Value (20:53:52) | Change |
|---|---|---|---|
| `ifOperStatus` | up | up | none |
| `ifInErrors` | 50,170 | 50,183 | **+13 per minute** |
| `ifOutErrors` | 0 | 0 | none |
| `ifInDiscards` | 0 | 0 | none |
| `ifOutDiscards` | 1,904 | 1,904 | none |
| `ifInOctets` | 3,663,490,953 | 3,754,521,228 | |
| `ifOutOctets` | 2,858,766,074 | 3,005,449,799 | |

Later snapshot (`switch-10g-ports-ifInErrors-delta.txt`): +12 errors in the next minute (50,184 to 50,196).

Interpretation:

- The switch counts receive errors on Te1/0/27. These errors are in the direction from pfSense to the switch.
- The switch counts no output errors on this port.
- The switch counts about 12 to 13 errors per minute. pfSense reports about 880 remote faults per second. The two counts measure different things. The gap is not explained yet.
- The "dot3" Ethernet error tables return zero or are not supported for this port. They do not give a separate FCS or symbol error count.

## E10: Other 10G switch ports

File: `switch-10g-ports-ifInErrors-delta.txt` and `switch-all-ports-errors-snmp.txt`.

| Port | Errors (20:54:08) | Errors (20:55:08) | Change per minute |
|---|---|---|---|
| Te1/0/25 (AP-2.5G switch) | 8,471,458 | 8,471,672 | **+214** |
| Te1/0/26 (HomeOffice) | 1,104 | 1,104 | 0 |
| Te1/0/27 (pfSense `ix0`) | 50,184 | 50,196 | +12 |
| Te1/0/28 (Proxmox) | 0 | 0 | 0 |

All 24 gigabit ports show 0 input errors.

Interpretation: Te1/0/25 has an active receive-error problem, which is larger than the Te1/0/27 problem. It is a separate link. It may use the same switch hardware, but this evidence does not show that.

## E11: What the evidence does not show

- It does not identify the faulty component. Candidates include pfSense transmit hardware, the DAC or its connectors, switch receive hardware, and driver or firmware behavior.
- It does not prove a configuration mismatch. Flow control differs, but this is not confirmed as the cause.
- It does not connect the 880 remote faults per second to the switch's error counts. The rates differ widely.
- It does not explain the ARP movement on VLAN 28.

## Next checks that need no changes

1. Read switch CLI or web UI counters for Te1/0/27 and Te1/0/25. Get the per-port error types and the link-event log. The switch IP access control blocks SSH. HTTPS works from the admin subnet.
2. Compare pfSense remote-fault rate with the switch's Te1/0/27 receive-error rate on the same minute grid.
3. Identify the device behind Te1/0/25 and check its link speed and cable.
4. Find which devices own `192.168.59.33` and `192.168.48.44` to `.46`. Check for duplicate IP assignment.

Any repair or port change needs explicit approval first.
