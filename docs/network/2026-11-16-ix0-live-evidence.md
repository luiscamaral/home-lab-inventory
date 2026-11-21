# ix0 evidence record

## Scope and limits

Collected through read-only SSH to `pfsense` on 2026-11-16, 20:39:02–20:39:11 UTC.
This file records selected output from this session's tool results. It is not a complete raw transcript.
Omada Controller and the switch were not accessed. These readings are a historical snapshot, not continuous monitoring.
No network settings changed.

## E1: Link and cable

Commands: `ifconfig ix0`, `ifconfig -v ix0`, `ifconfig -l`.

```text
media: Ethernet autoselect (10Gbase-Twinax <full-duplex,rxpause,txpause>)
status: active
plugged: SFP/SFP+/SFP28 Unknown (Copper pigtail)
vendor: Cable Matters PN: 104033-1m-VN SN: URHDPSHL1 DATE: 2026-05-15
interfaces: ix0 ix1 igc0 igc1 igc2 igc3 enc0 lo0 pflog0 pfsync0 ix0.10 ix0.28 ix0.105 ix0.205 controltun0
```

Observation: the link was active at 10 Gbps. No `lagg0` appeared in the interface list.

## E2: Hardware counters

Command: `sysctl dev.ix.0.mac_stats.remote_faults dev.ix.0.mac_stats.local_faults dev.ix.0.mac_stats.crc_errs`.
The command ran twice with `sleep 5` between samples.

```text
UTC                       remote_faults  local_faults  crc_errs
2026-11-16 20:39:02        32792953       2985          9
2026-11-16 20:39:07        32795272       2985          9
```

Observation: remote faults increased by 2,319, about 464 per second. The other two counters stayed unchanged.
This does not identify a faulty cable or port. Switch-side evidence is missing.

## E3: Watchdog state and pause flag

Sources: `/var/db/ix0-watchdog.state`, `/var/db/ix0-watchdog.nobounce`.

```text
BOUNCES_BLACKOUT=21
BOUNCES_DEGRADED=16
LAST_BOUNCE_TS=1792908427
LAST_BOUNCE_RESULT=0
CONSEC_FAILURES=2
DISARMED=1
DAY_STAMP="20261025"
DAY_BOUNCES=0

2026-10-25 01:49:42 ix0 degraded; awaiting DAC/port replacement (2026-10-25)
```

Observation: saved state showed disarmed recovery. The pause flag also blocked automatic bounces.
The flag's text records an earlier assessment, not proof of the faulty component.

## E4: Exported probe results

Source: `/var/tmp/node_exporter/ix0_watchdog.prom`, read at about 20:39:11 UTC.

```text
pfsense_ix0_watchdog_up{device="ix0"} 1
pfsense_ix0_watchdog_last_run_timestamp_seconds{device="ix0"} 1794861508
pfsense_ix0_large_frame_loss_percent{device="ix0",target="192.168.48.44",size="1400"} 0
pfsense_ix0_large_frame_loss_percent{device="ix0",target="192.168.48.45",size="1400"} 0
pfsense_ix0_watchdog_disarmed{device="ix0"} 1
pfsense_ix0_watchdog_paused{device="ix0"} 1
```

Observation: the latest exported checks showed zero loss to these two targets.
These were existing watchdog results, not new manual packet-loss tests.

## E5: Recent log excerpt

Source: `tail -25 /var/log/ix0-watchdog.log`.
Log timestamps below have no timezone suffix.

```text
2026-11-11 15:37:02 all LAN targets unreachable (24/6, link=down)
2026-11-11 15:37:02 nobounce flag set — NOT bouncing (blackout)
2026-11-11 15:38:53 all LAN targets unreachable (1/6, link=down)
2026-11-11 15:39:24 recovered after 1 all-down probe(s)
```

## Unresolved questions

The faulty component remains unknown. A configuration mismatch has not been ruled out.
Collect switch port status, configuration, counters, and logs before comparing both ends.
Do not replace the cable, move ports, or bounce the link without explicit approval.
