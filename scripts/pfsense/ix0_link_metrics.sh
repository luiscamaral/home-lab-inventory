#!/bin/sh
# pfSense node_exporter textfile metrics for the ix0 10G SFP+ LAN trunk
# (pfSense -> switch24a port 27). Surfaces link flaps into Prometheus/Grafana.
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
#
# The flap counter is parsed from syslog, so it captures every flap regardless of
# poll rate; the gauge gives the live state for the Grafana state-timeline panel.
DIR=/var/tmp/node_exporter
IFACE=ix0
mkdir -p "$DIR"
TMP="$(mktemp "$DIR/ix0_link.XXXXXX")"
OUT="$DIR/ix0_link.prom"
LOG=/var/log/system.log

if ifconfig "$IFACE" 2>/dev/null | grep -q "status: active"; then UP=1; else UP=0; fi
FLAPS=$(grep -c "$IFACE: link state changed to UP" "$LOG" 2>/dev/null || echo 0)

last_evt() { grep "$IFACE: link state changed to $1" "$LOG" 2>/dev/null | tail -1 | awk '{print $1, $2, $3}'; }
to_epoch() { [ -n "$1" ] && date -j -f "%b %d %H:%M:%S" "$1 $(date +%H:%M:%S)" +%s 2>/dev/null; }
DSTR="$(last_evt DOWN)"; USTR="$(last_evt UP)"
DEP=$(to_epoch "$DSTR"); UEP=$(to_epoch "$USTR")

{
  echo "# HELP pfsense_link_up Interface link state (1=active/up, 0=down)"
  echo "# TYPE pfsense_link_up gauge"
  echo "pfsense_link_up{device=\"$IFACE\"} $UP"
  echo "# HELP pfsense_link_flaps_total Count of link UP transitions in current syslog buffer"
  echo "# TYPE pfsense_link_flaps_total counter"
  echo "pfsense_link_flaps_total{device=\"$IFACE\"} $FLAPS"
  [ -n "$DEP" ] && { echo "# HELP pfsense_link_last_down_timestamp_seconds Epoch of most recent link DOWN"; echo "# TYPE pfsense_link_last_down_timestamp_seconds gauge"; echo "pfsense_link_last_down_timestamp_seconds{device=\"$IFACE\"} $DEP"; }
  [ -n "$UEP" ] && { echo "# HELP pfsense_link_last_up_timestamp_seconds Epoch of most recent link UP"; echo "# TYPE pfsense_link_last_up_timestamp_seconds gauge"; echo "pfsense_link_last_up_timestamp_seconds{device=\"$IFACE\"} $UEP"; }
} > "$TMP" && mv "$TMP" "$OUT"
chmod 644 "$OUT"
