#!/bin/sh
# pfsync-dest: /usr/local/bin/dpinger_textfile.sh
#
# Read dpinger gateway-monitor sockets and emit Prometheus textfile
# metrics for the node_exporter textfile collector.
#
# dpinger output format (one line per socket):
#   <NAME> <DELAY_us> <STDDEV_us> <LOSS_percent>
#
# Output file: /var/tmp/node_exporter/dpinger.prom (atomic via .tmp + rename)
#
# Scheduled via the pfSense cron entry declared in
# pfsense/cron-jobs.yml; sync-pfsense-cron-jobs.py applies it through
# the pfSense REST API. Companion script dpinger_textfile_30s.sh runs
# this twice per minute to give 30 s effective cadence (cron's
# minimum is 1 minute).

OUT_DIR=/var/tmp/node_exporter
OUT_FILE="$OUT_DIR/dpinger.prom"
TMP_FILE="$OUT_FILE.$$.tmp"

mkdir -p "$OUT_DIR"

{
  printf "# HELP pfsense_gateway_delay_seconds Gateway latency from dpinger\n"
  printf "# TYPE pfsense_gateway_delay_seconds gauge\n"
  printf "# HELP pfsense_gateway_stddev_seconds Gateway latency stddev from dpinger\n"
  printf "# TYPE pfsense_gateway_stddev_seconds gauge\n"
  printf "# HELP pfsense_gateway_loss_ratio Gateway packet loss ratio (0.0-1.0)\n"
  printf "# TYPE pfsense_gateway_loss_ratio gauge\n"
  printf "# HELP pfsense_dpinger_scrape_unixtime Unix time of last successful scrape\n"
  printf "# TYPE pfsense_dpinger_scrape_unixtime gauge\n"

  for sock in /var/run/dpinger_*.sock; do
    [ -S "$sock" ] || continue
    base=$(basename "$sock" .sock | sed "s/^dpinger_//")
    name=$(echo "$base" | cut -d"~" -f1)
    src=$(echo "$base" | cut -d"~" -f2)
    mon=$(echo "$base" | cut -d"~" -f3)
    echo "" | nc -U "$sock" 2>/dev/null | \
      awk -v name="$name" -v src="$src" -v mon="$mon" '
        NF >= 4 {
          lbls=sprintf("gateway=\"%s\",source=\"%s\",monitor=\"%s\"", name, src, mon)
          printf "pfsense_gateway_delay_seconds{%s} %.9f\n",   lbls, $2/1000000
          printf "pfsense_gateway_stddev_seconds{%s} %.9f\n",  lbls, $3/1000000
          printf "pfsense_gateway_loss_ratio{%s} %.6f\n",      lbls, $4/100
        }'
  done
  printf "pfsense_dpinger_scrape_unixtime %d\n" "$(date +%s)"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
