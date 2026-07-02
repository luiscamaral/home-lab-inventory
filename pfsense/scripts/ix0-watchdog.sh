#!/bin/sh
# pfsync-dest: /usr/local/sbin/ix0-watchdog.sh
# ix0-watchdog — recover the pfSense ix0 10G LAN trunk when it "islands".
# Root cause is a marginal SFP+/fiber on ix0 <-> switch Te1/0/27; the trunk
# intermittently stops passing LAN traffic while WAN+admin stay healthy.
# Detection: ALL probe targets (always-on LAN hosts behind the switch) are
# unreachable for >= THRESHOLD consecutive probes. Action: flap ix0 (down/up).
# Heavily guarded against false flaps: needs every target down, a 3-min sustain,
# a post-flap cooldown, and a hard min-gap between flaps.
# Modes: start | stop | status | check | run(internal)
#
# IaC: installed via scripts/sync-pfsense-scripts.py --apply. Keepalive cron
# (config.xml) is declared in pfsense/cron-jobs.yml; boot start via the rc.d
# hook pfsense/scripts/ix0watchdog-rcd.sh. Runbook:
# docs/network/2026-06-28-ix0-optic-flap-handoff.md
set -u

IFACE="ix0"
TARGETS="192.168.48.44 192.168.0.50 192.168.1.50"   # dockermaster(SVR), NAS(HOME), NAS-bond
INTERVAL=30          # seconds between probes
THRESHOLD=6          # consecutive all-down probes before a flap (6 x 30s = 180s = 3 min)
DOWN_SECS=5          # hold ix0 down this long during a flap
COOLDOWN=180         # pause probing this long right after a flap (let it recover)
MIN_FLAP_GAP=600     # hard floor between flaps (10 min) — prevents any flap storm
PIDFILE="/var/run/ix0-watchdog.pid"
LOG="/var/log/ix0-watchdog.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
  logger -t ix0-watchdog -p daemon.notice "$1" 2>/dev/null
}
running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; }
link_status() { /sbin/ifconfig "$IFACE" 2>/dev/null | grep -q "status: active" && echo up || echo down; }
probe() {   # 0 = at least one target reachable (healthy); 1 = ALL unreachable
  for t in $TARGETS; do
    /sbin/ping -c1 -t1 "$t" >/dev/null 2>&1 && return 0
  done
  return 1
}
flap() {
  log "ACTION: all LAN targets unreachable ~$((THRESHOLD*INTERVAL))s (ix0 link=$(link_status)) -> flapping $IFACE"
  /sbin/ifconfig "$IFACE" down; sleep "$DOWN_SECS"; /sbin/ifconfig "$IFACE" up
  log "ACTION: $IFACE bounced; cooldown ${COOLDOWN}s"
}
run() {
  log "started (iface=$IFACE targets='$TARGETS' threshold=${THRESHOLD}x${INTERVAL}s cooldown=${COOLDOWN}s min_flap_gap=${MIN_FLAP_GAP}s)"
  fails=0; last_flap=0
  while :; do
    if probe; then
      [ "$fails" -gt 0 ] && log "recovered after ${fails} all-down probe(s)"
      fails=0
    else
      fails=$((fails+1))
      log "all LAN targets unreachable (${fails}/${THRESHOLD})"
      if [ "$fails" -ge "$THRESHOLD" ]; then
        now=$(date +%s)
        if [ $((now - last_flap)) -lt "$MIN_FLAP_GAP" ]; then
          log "rate-limited: last flap $((now-last_flap))s ago (< ${MIN_FLAP_GAP}s) — NOT flapping"
        else
          flap; last_flap=$(date +%s); fails=0; sleep "$COOLDOWN"
        fi
      fi
    fi
    sleep "$INTERVAL"
  done
}

case "${1:-}" in
  start)
    running && exit 0
    nohup "$0" run >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    ;;
  run)    run ;;
  stop)   running && kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"; log "stopped" ;;
  status) running && echo "running (pid $(cat "$PIDFILE"))" || echo "not running" ;;
  check)  probe && echo "healthy: a LAN target is reachable" || echo "DOWN: all LAN targets unreachable (ix0 link=$(link_status))" ;;
  *) echo "usage: $0 {start|stop|status|check}"; exit 1 ;;
esac
