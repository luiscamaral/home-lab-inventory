#!/bin/sh
# Read-only sampler: 10 samples, 30 s apart, of ix0 counters and link state on pfsense.
OUT="$1"
for i in $(seq 1 10); do
  ssh -o BatchMode=yes -o ConnectTimeout=10 pfsense '
    echo "== $(date -u +%FT%TZ) sample"
    ifconfig ix0 | grep -E "media|status"
    sysctl dev.ix.0.mac_stats.remote_faults dev.ix.0.mac_stats.local_faults dev.ix.0.mac_stats.crc_errs
    netstat -I ix0 -bn | head -3
    netstat -I ix0 -s 2>/dev/null | head -0
  ' 2>&1
  [ "$i" -lt 10 ] && sleep 30
done > "$OUT"
echo "DONE $(date -u +%FT%TZ)" >> "$OUT"
