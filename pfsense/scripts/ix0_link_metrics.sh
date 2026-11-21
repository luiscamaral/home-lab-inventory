#!/bin/sh
# pfsync-dest: /usr/local/bin/ix0_link_metrics.sh
# pfSense node_exporter textfile metrics for the ix0 10G SFP+ LAN trunk
# (pfSense -> switch24a port 27). Surfaces link flaps + optic DDM into
# Prometheus/Grafana.
#
# Deploy on pfSense:
#   - copy to /usr/local/bin/ix0_link_metrics.sh (chmod +x)
#   - cron (config.xml, every minute): */1 * * * * root /usr/local/bin/ix0_link_metrics.sh
#   - node_exporter already runs with --collector.textfile.directory=/var/tmp/node_exporter
#     and binds 192.168.4.1:9100 (scraped by Prometheus as instance="pfsense").
#
# Metrics:
#   pfsense_link_up{device="ix0"}                       1=active/up, 0=down
#   pfsense_link_flaps_total{device="ix0"}             count of UP transitions in syslog buffer
#   pfsense_link_last_down_timestamp_seconds{...}      epoch of most recent link DOWN (flap start)
#   pfsense_link_last_up_timestamp_seconds{...}        epoch of most recent link UP   (flap end)
#   pfsense_sfp_rx_power_dbm{device="ix0"}             optic RX power (switch->pfSense dir); healthy -3..-10, LOS ~ -17
#   pfsense_sfp_tx_power_dbm{device="ix0"}             optic TX power (pfSense->switch dir); only if the module reports it
#   pfsense_sfp_tx_bias_ma{device="ix0"}               laser TX bias current; a rising trend can flag a degrading laser
#   pfsense_sfp_temperature_celsius{device="ix0"}      module temperature (health < 70 C)
#   pfsense_sfp_voltage_volts{device="ix0"}            module supply voltage (~3.3 V nominal)
#   pfsense_ix0_remote_faults_total{device="ix0"}      partner-signalled Remote Fault ordered-sets
#   pfsense_ix0_local_faults_total{device="ix0"}       locally-detected faults (our RX side)
#   pfsense_ix0_crc_errs_total{device="ix0"}           RX CRC errors (our RX side)
#   pfsense_link_metrics_last_run_timestamp_seconds{...} collector heartbeat (staleness alerting)
#
# The flap counter is parsed from syslog, so it captures every flap regardless of
# poll rate; the gauge gives the live state for the Grafana state-timeline panel.
# The DDM values come from `ifconfig -v ix0` (the X520 exposes SFF-8472 there).
# RCA 2026-07-02: RX power -2.99 dBm proved the switch->pfSense direction is
# clean, localizing the fault to the pfSense-TX -> switch-RX strand. This trend
# lets a new optic's RX/TX power be compared against the failing OEM one.
#
# 2026-08-17: added the fault counters. `remote_faults` is THE leading indicator
# for this optic — it is the switch telling us it cannot cleanly receive our TX.
# Healthy = flat. During the 2026-08-13 incident it climbed at 60/s while
# local_faults and crc_errs stayed at 0, which is what pins the bad direction to
# pfSense-TX -> switch-RX. Rate is NOT proportional to packet loss (60/s gave
# 3-6% loss; 13.3/s gave 24%), so alert on it as an early warning and measure
# loss separately (ix0-watchdog.sh) for anything that decides to act.
#
# Also 2026-08-17: sourced counters from sysctl (authoritative, survives syslog
# rotation) and made temp-file cleanup unconditional. The previous revision
# ended the emit block with `[ -n "$UEP" ] && {...}`; when the syslog buffer had
# no UP event that returned non-zero, so `&& mv` never ran -- the metrics went
# stale for days AND leaked a temp file per minute (37,998 / 171 MB found on
# 2026-08-17, which also bloats node_exporter's textfile glob on every scrape).
DIR=/var/tmp/node_exporter
IFACE=ix0
mkdir -p "$DIR"
OUT="$DIR/ix0_link.prom"
LOG=/var/log/system.log
TMP="$(mktemp "$DIR/ix0_link.XXXXXX")" || exit 1
# Unconditional cleanup: never leak a temp again, whatever the exit path.
trap 'rm -f "$TMP"' EXIT HUP INT TERM

if ifconfig "$IFACE" 2>/dev/null | grep -q "status: active"; then UP=1; else UP=0; fi
FLAPS=$(grep -c "$IFACE: link state changed to UP" "$LOG" 2>/dev/null || echo 0)

last_evt() { grep "$IFACE: link state changed to $1" "$LOG" 2>/dev/null | tail -1 | awk '{print $1, $2, $3}'; }
to_epoch() { [ -n "$1" ] && date -j -f "%b %d %H:%M:%S" "$1 $(date +%H:%M:%S)" +%s 2>/dev/null; }
DSTR="$(last_evt DOWN)"; USTR="$(last_evt UP)"
DEP=$(to_epoch "$DSTR"); UEP=$(to_epoch "$USTR")

# --- SFP DDM (SFF-8472 via `ifconfig -v`) ---
# Sample lines:
#   module temperature: 52.49 C voltage: 3.25 Volts
#   lane 1: RX power: 0.50 mW (-2.99 dBm) TX bias: 6.86 mA
DDM="$(ifconfig -v "$IFACE" 2>/dev/null)"
SFP_TEMP=$(printf '%s\n' "$DDM"   | sed -n 's/.*module temperature: \([-.0-9]*\) C.*/\1/p' | head -1)
SFP_VOLT=$(printf '%s\n' "$DDM"   | sed -n 's/.*voltage: \([-.0-9]*\) Volts.*/\1/p' | head -1)
SFP_RXDBM=$(printf '%s\n' "$DDM"  | sed -n 's/.*RX power:[^(]*(\([-.0-9]*\) dBm).*/\1/p' | head -1)
SFP_TXDBM=$(printf '%s\n' "$DDM"  | sed -n 's/.*TX power:[^(]*(\([-.0-9]*\) dBm).*/\1/p' | head -1)
SFP_TXBIAS=$(printf '%s\n' "$DDM" | sed -n 's/.*TX bias: \([-.0-9]*\) mA.*/\1/p' | head -1)

# --- MAC fault counters (sysctl; authoritative and rotation-proof) ---
# Note: mac_stats.checksum_errs is deliberately NOT exported. Per the
# 2026-07-02 analysis it is a benign reporting change (pfSense bug #12904),
# not a real error, and trending it sends people down a dead end.
MAC_STATS=dev.ix.0.mac_stats     # sysctl node for ix0 (driver "ix", unit 0)
RFAULTS=$(sysctl -n "$MAC_STATS.remote_faults" 2>/dev/null)
LFAULTS=$(sysctl -n "$MAC_STATS.local_faults"  2>/dev/null)
CRCERRS=$(sysctl -n "$MAC_STATS.crc_errs"      2>/dev/null)

emit() { # name help value
  [ -n "$3" ] || return 0
  echo "# HELP $1 $2"; echo "# TYPE $1 gauge"; echo "$1{device=\"$IFACE\"} $3"
}
emit_counter() { # name help value
  [ -n "$3" ] || return 0
  echo "# HELP $1 $2"; echo "# TYPE $1 counter"; echo "$1{device=\"$IFACE\"} $3"
}

{
  echo "# HELP pfsense_link_up Interface link state (1=active/up, 0=down)"
  echo "# TYPE pfsense_link_up gauge"
  echo "pfsense_link_up{device=\"$IFACE\"} $UP"
  echo "# HELP pfsense_link_flaps_total Count of link UP transitions in current syslog buffer"
  echo "# TYPE pfsense_link_flaps_total counter"
  echo "pfsense_link_flaps_total{device=\"$IFACE\"} $FLAPS"
  [ -n "$DEP" ] && { echo "# HELP pfsense_link_last_down_timestamp_seconds Epoch of most recent link DOWN"; echo "# TYPE pfsense_link_last_down_timestamp_seconds gauge"; echo "pfsense_link_last_down_timestamp_seconds{device=\"$IFACE\"} $DEP"; }
  [ -n "$UEP" ] && { echo "# HELP pfsense_link_last_up_timestamp_seconds Epoch of most recent link UP"; echo "# TYPE pfsense_link_last_up_timestamp_seconds gauge"; echo "pfsense_link_last_up_timestamp_seconds{device=\"$IFACE\"} $UEP"; }
  emit pfsense_sfp_rx_power_dbm "SFP RX optical power (dBm) - switch->pfSense direction; healthy -3..-10, LOS ~ -17" "$SFP_RXDBM"
  emit pfsense_sfp_tx_power_dbm "SFP TX optical power (dBm) - pfSense->switch direction (not all modules report this)" "$SFP_TXDBM"
  emit pfsense_sfp_tx_bias_ma "SFP laser TX bias current (mA); a rising trend can indicate a degrading laser" "$SFP_TXBIAS"
  emit pfsense_sfp_temperature_celsius "SFP module temperature (C); health < 70" "$SFP_TEMP"
  emit pfsense_sfp_voltage_volts "SFP module supply voltage (V); ~3.3 nominal" "$SFP_VOLT"
  emit_counter pfsense_ix0_remote_faults_total "Remote Fault ordered-sets signalled BY THE PARTNER (switch cannot cleanly receive our TX). Leading indicator for the marginal optic; healthy = flat" "$RFAULTS"
  emit_counter pfsense_ix0_local_faults_total "Faults detected locally (our RX side). Stays flat while only the pfSense-TX strand is bad" "$LFAULTS"
  emit_counter pfsense_ix0_crc_errs_total "RX CRC errors (our RX side). Stays flat while only the pfSense-TX strand is bad" "$CRCERRS"
  echo "# HELP pfsense_link_metrics_last_run_timestamp_seconds Epoch of the last successful collector run (alert on staleness)"
  echo "# TYPE pfsense_link_metrics_last_run_timestamp_seconds gauge"
  echo "pfsense_link_metrics_last_run_timestamp_seconds{device=\"$IFACE\"} $(date +%s)"
} > "$TMP" || exit 1
# Publish atomically. `mv` is its own statement (not chained off the emit block)
# so a falsy last metric can never suppress the update -- that was the 2026-08-17
# staleness/leak bug.
mv "$TMP" "$OUT" || exit 1
chmod 644 "$OUT"
