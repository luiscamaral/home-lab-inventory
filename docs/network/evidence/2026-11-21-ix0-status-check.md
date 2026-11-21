# ix0 status check 2026-11-21 (live, read-only)

Collected 2026-11-21T05:39Z to 05:52Z UTC. No changes made.
Sources: Thanos query API 192.168.59.26:10902; `ssh pfsense` (read-only: ifconfig, sysctl, ls, cat, ping, netstat, curl of local node_exporter); repo files.
Not checked: switch24a directly (Thanos SNMP data only), Grafana itself (dashboard JSON in repo only; not queried live), Omada.

## Direct observations: pfSense (05:51Z)

- `ifconfig -v ix0`: status active, 10Gbase-Twinax full-duplex, flags UP,RUNNING,LOWER_UP.
- Module: Cable Matters 104033-1m-VN (passive DAC), "SFP/SFP+/SFP28 Unknown (Copper pigtail)". No DDM data on a DAC.
- `sysctl dev.ix.0.mac_stats`: remote_faults 120312064, local_faults 3008, crc_errs 20 (lifetime counters).
- Remote-fault delta over 30 s: 42 (about 1.4 per second).
- `netstat -I ix0`: Ierrs 22, Idrop 0, Oerrs 0.
- `ping -c5 -s1400 -D 192.168.48.44`: 0.0% loss, avg 0.40 ms.
- `ix0-watchdog.sh status`: running; bounces blackout=21 degraded=16; last_result=0; consec_failures=2; disarmed=1;
  PAUSED (nobounce flag) since 2026-10-25 01:49:42, "awaiting DAC/port replacement".
- pfSense uptime 4 d 6 h.

## Direct observations: Thanos (05:39Z)

- Firing: Ix0AutoBounceFailed, Ix0WatchdogDisarmed.
- `pfsense_ix0_watchdog_disarmed` 1, `..._paused` 1, `..._last_bounce_succeeded` 0, `..._consecutive_failures` 2.
- Last bounce timestamp: 2026-10-25 06:07:07 UTC (about 27 days ago). Watchdog heartbeat 18 s old.
- `pfsense_ix0_large_frame_loss_mean_percent` 0. Per-target loss max 1% in the last hour, 0 now.
- node_exporter ix0 rx 21 Mb/s, tx 10.6 Mb/s, error and drop rates 0.
- switch24a Te1/0/27 (ifIndex 49179): ifOperStatus up for the last hour; ifInErrors rose 90,000 to 90,300 in 60 min (about 0.08 per second).

## Direct observation: metric gap (monitoring defect)

These series have no data in Thanos for at least 12 h, and none from 3 days ago either:
`pfsense_link_up`, `pfsense_link_flaps_total`, `pfsense_sfp_*`, `pfsense_ix0_remote_faults_total`, `local_faults_total`, `crc_errs_total`, `pfsense_link_metrics_last_run_timestamp_seconds`.

On pfSense:
- `/var/tmp/node_exporter/ix0_link.prom` is rewritten every minute (mtime fresh).
- Its content has a stray line `0` right after `pfsense_link_flaps_total{device="ix0"} 0`.
- Local node_exporter `:9100/metrics` shows `node_textfile_scrape_error 1`.
  `ix0_link.prom` is missing from `node_textfile_mtime_seconds`. The other three .prom files are listed.
- Local scrape has 0 `pfsense_ix0_remote_faults` lines.

Cause (supported by the script, not yet tested): `pfsense/scripts/ix0_link_metrics.sh` line 59:
`FLAPS=$(grep -c "..." "$LOG" 2>/dev/null || echo 0)`.
When nothing matches, `grep -c` prints `0` and exits 1, so `echo 0` adds a second `0`. `$FLAPS` becomes two lines.
The unparseable file is dropped whole.

Unknown: when exactly the file became malformed (between 2026-11-16 and 2026-11-18 by Thanos offset queries; the 5-day and 7-day queries timed out).
