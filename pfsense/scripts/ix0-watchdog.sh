#!/bin/sh
# pfsync-dest: /usr/local/sbin/ix0-watchdog.sh
# ix0-watchdog — recover the pfSense ix0 10G LAN trunk when the marginal optic
# on ix0 <-> switch24a Te1/0/27 corrupts the pfSense-TX -> switch-RX strand.
#
# TWO failure modes, two detectors — they are NOT the same shape:
#
#   BLACKOUT  — the trunk stops passing LAN traffic entirely. Every probe target
#               is unreachable. Detected with cheap 56 B pings. (Original 2026-06
#               behaviour, unchanged.)
#   DEGRADED  — the trunk stays UP and every host still answers, but 5-25% of
#               LARGE frames are silently dropped. Bulk TCP collapses via Mathis
#               (~1.22*MSS/(RTT*sqrt(p))): 20% loss at 14 ms RTT => ~2 Mbps, which
#               presents to humans as "the internet is slow", not as an outage.
#               Added 2026-08-17 after this mode ran undetected through three
#               incidents (2026-08-05, -08-13, -08-16).
#
# Why DEGRADED needs its own probe: the blackout probe uses default 56 B pings,
# and loss here is packet-size dependent (bit-error driven, so a longer frame is
# more exposed). Measured 2026-08-16: 56 B = 0.0% while 1400 B = 24.4% on the
# same path. A 56 B probe is structurally blind to this until it is nearly total.
#
# Why the bounce decision is made on measured LOSS and not on remote_faults:
# the fault RATE is not proportional to loss (2026-08-13: 60/s -> 3-6% loss;
# 2026-08-16: 13.3/s -> 24% loss). remote_faults is the right EARLY WARNING
# (Prometheus alerts on it, from ix0_link_metrics.sh) but the wrong trigger for
# anything that causes a 30-50 s outage. Measure what you care about.
#
# A bounce is a real outage: down/up drops EVERY LAN VLAN (HOME/IoT/SVR) for
# ~30-50 s while the link re-inits and STP reconverges, and NFS stalls briefly.
# So every trigger is heavily guarded: sustain window, cooldown, hard min-gap,
# per-day cap, and — for DEGRADED — verification that the bounce actually helped,
# with exponential backoff and eventual self-disarm when it stops helping.
#
# Self-disarm matters: the optic is decaying. 2026-08-13's bounce restored 0.0%
# loss; 2026-08-17's only reached 8.3%. Once bounces stop working, continuing to
# bounce is pure outage for no benefit — so the watchdog gives up and says so
# (metric + log) rather than becoming a 30-50 s outage generator.
#
# Modes: start | stop | status | check | testbounce | reset | run(internal)
#   testbounce — deliberate on-demand bounce with before/after measurement,
#                for validating the pipeline (costs a ~30-50 s LAN outage).
#   reset — clear a self-disarm (after the optic is replaced) and re-arm.
#
# Hardware runbook (the ACTUAL fix — replace the pfSense-side OEM optic):
#   docs/network/2026-06-28-ix0-optic-flap-handoff.md
# Disarm before rack work:  ix0-watchdog.sh stop   (re-arm: ix0-watchdog.sh start)
#
# IaC: installed via scripts/sync-pfsense-scripts.py --apply. Keepalive cron
# (config.xml) is declared in pfsense/cron-jobs.yml; boot start via the rc.d
# hook pfsense/scripts/ix0watchdog-rcd.sh.
set -u

IFACE="ix0"

# --- BLACKOUT detector (all targets unreachable) ---
TARGETS="192.168.48.44 192.168.0.50 192.168.1.50"   # dockermaster(SVR), NAS(HOME), NAS-bond
INTERVAL=30          # seconds between probes
THRESHOLD=6          # consecutive all-down probes before a flap (6 x 30s = 3 min)

# --- DEGRADED detector (large-frame loss while still "up") ---
LOSS_TARGETS="192.168.48.44 192.168.48.45"  # dockermaster, ds-1 — both behind the switch
LOSS_PROBE_EVERY=2   # run the loss probe every Nth INTERVAL (2 x 30s = every 60s)
LOSS_PKTS=100        # packets per target per probe (~2 s at -i 0.02)
LOSS_SIZE=1400       # MUST be large; 56 B is blind to this failure mode
LOSS_TRIGGER_PCT=10  # MEAN loss across targets that counts as degraded
LOSS_MIN_TARGETS=2   # minimum measurable targets before we trust the mean
# Sustain rule is "N of the last M probes", NOT N consecutive. Observed
# 2026-08-17: loss oscillates 5-24% around the threshold, so a strict
# consecutive counter kept resetting on a single dip (logged 1/3, then
# "degraded cleared" at 7%/8%) and would rarely fire during a genuinely bad
# stretch. A sliding window tolerates the oscillation without lowering the bar.
DEGRADED_THRESHOLD=3 # degraded probes required within the window
DEGRADED_WINDOW=5    # window size (5 x 60s = last ~5 min)
DEGRADED_MIN_GAP=7200    # 2 h between degraded-triggered bounces (base, before backoff)
DEGRADED_MAX_PER_DAY=3   # hard daily cap on degraded-triggered bounces
SETTLE_SECS=180      # wait after a bounce before judging whether it worked
SUCCESS_LOSS_PCT=2   # post-bounce MEAN loss at or below this = bounce succeeded
MAX_CONSEC_FAILURES=2    # consecutive failed bounces before self-disarm

# --- shared guards ---
DOWN_SECS=5          # hold ix0 down this long during a flap
COOLDOWN=180         # pause probing this long right after a flap
MIN_FLAP_GAP=600     # hard floor between ANY two flaps (10 min) — anti flap-storm

PIDFILE="/var/run/ix0-watchdog.pid"
LOG="/var/log/ix0-watchdog.log"
STATE="/var/db/ix0-watchdog.state"
NOBOUNCE_FLAG="/var/db/ix0-watchdog.nobounce"   # touch to keep metrics but never bounce
METRICS_DIR="/var/tmp/node_exporter"
METRICS="$METRICS_DIR/ix0_watchdog.prom"

# --- persisted counters (survive daemon restarts; reset on reboot is fine,
#     Prometheus handles counter resets) ---
BOUNCES_BLACKOUT=0
BOUNCES_DEGRADED=0
LAST_BOUNCE_TS=0
LAST_BOUNCE_RESULT=-1    # 1=succeeded, 0=failed, -1=unknown/none yet
CONSEC_FAILURES=0
DISARMED=0
DAY_STAMP=""
DAY_BOUNCES=0

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
  logger -t ix0-watchdog -p daemon.notice "$1" 2>/dev/null
}
running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; }
link_status() { /sbin/ifconfig "$IFACE" 2>/dev/null | grep -q "status: active" && echo up || echo down; }

load_state() {
  [ -r "$STATE" ] || return 0
  # shellcheck disable=SC1090
  . "$STATE" 2>/dev/null || true
}
save_state() {
  mkdir -p "$(dirname "$STATE")" 2>/dev/null
  cat > "$STATE" <<EOF
BOUNCES_BLACKOUT=$BOUNCES_BLACKOUT
BOUNCES_DEGRADED=$BOUNCES_DEGRADED
LAST_BOUNCE_TS=$LAST_BOUNCE_TS
LAST_BOUNCE_RESULT=$LAST_BOUNCE_RESULT
CONSEC_FAILURES=$CONSEC_FAILURES
DISARMED=$DISARMED
DAY_STAMP="$DAY_STAMP"
DAY_BOUNCES=$DAY_BOUNCES
EOF
}

# --- probes -----------------------------------------------------------------

probe() {   # BLACKOUT: 0 = at least one target reachable (healthy); 1 = ALL unreachable
  for t in $TARGETS; do
    /sbin/ping -c1 -t1 "$t" >/dev/null 2>&1 && return 0
  done
  return 1
}

measure_loss() {   # $1=target -> integer loss percent, or -1 if unmeasurable
  out=$(/sbin/ping -c "$LOSS_PKTS" -i 0.02 -s "$LOSS_SIZE" -q -t 5 "$1" 2>/dev/null)
  pct=$(printf '%s\n' "$out" | sed -n 's/.*, \([0-9.]*\)% packet loss.*/\1/p' | head -1)
  [ -n "$pct" ] || { echo -1; return 0; }
  awk -v p="$pct" 'BEGIN{printf "%d", p + 0.5}'
}

LOSS_KV=""        # "target=pct target=pct" from the most recent sweep
WORST_LOSS=-1
LOSS_MEAN=-1      # mean across measurable targets (-1 = not enough data)
LOSS_MIN=-1       # best target, used as the sick-host guard
LOSS_N=0          # how many targets were measurable
sweep_loss() {    # measure every LOSS_TARGET; sets LOSS_KV/WORST_LOSS/LOSS_MEAN/LOSS_MIN/LOSS_N
  LOSS_KV=""; WORST_LOSS=-1; LOSS_MEAN=-1; LOSS_MIN=-1; LOSS_N=0
  sum=0
  for t in $LOSS_TARGETS; do
    l=$(measure_loss "$t")
    LOSS_KV="$LOSS_KV $t=$l"
    [ "$l" -lt 0 ] && continue
    [ "$l" -gt "$WORST_LOSS" ] && WORST_LOSS="$l"
    if [ "$LOSS_MIN" -lt 0 ] || [ "$l" -lt "$LOSS_MIN" ]; then LOSS_MIN="$l"; fi
    sum=$((sum + l)); LOSS_N=$((LOSS_N + 1))
  done
  LOSS_KV="${LOSS_KV# }"
  [ "$LOSS_N" -gt 0 ] && LOSS_MEAN=$((sum / LOSS_N))
}

degraded() {      # 0 = degraded; 1 = healthy. Reads what sweep_loss computed.
  # AGGREGATE, then threshold -- do NOT threshold each target and count.
  # Measured 2026-08-17 with true loss ~10%: per-target estimates over 100
  # packets have a standard error of ~3% (sqrt(p(1-p)/n)), so they swing +-6%.
  # Requiring BOTH noisy estimates to independently clear 10% fired 0 times in
  # 6 paired samples (.44=16,9,6,15,12,14 vs .45=9,11,10,7,7,8) even though the
  # trunk was plainly degraded -- the automation was effectively inert.
  # Averaging doubles the effective sample and tests what we actually care
  # about: "is the trunk dropping ~10% of large frames right now".
  [ "$LOSS_N" -ge "$LOSS_MIN_TARGETS" ] || return 1   # need corroboration
  [ "$LOSS_MEAN" -ge "$LOSS_TRIGGER_PCT" ] || return 1
  # Sick-host guard, replacing what the count-based rule gave us: one broken
  # target must not drag the mean over on its own. If the trunk is genuinely
  # bad every target sees it, so require the BEST target to be at least half
  # the threshold. (100% + 0% averages to 50% but min=0 -> correctly rejected.)
  [ "$LOSS_MIN" -ge $((LOSS_TRIGGER_PCT / 2)) ] || return 1
  return 0
}

# --- metrics ----------------------------------------------------------------

write_metrics() {
  mkdir -p "$METRICS_DIR" 2>/dev/null
  tmp="$(mktemp "$METRICS_DIR/ix0_watchdog.XXXXXX")" || return 0
  {
    echo "# HELP pfsense_ix0_watchdog_up ix0-watchdog daemon is running"
    echo "# TYPE pfsense_ix0_watchdog_up gauge"
    echo "pfsense_ix0_watchdog_up{device=\"$IFACE\"} 1"
    echo "# HELP pfsense_ix0_watchdog_last_run_timestamp_seconds Heartbeat of the watchdog loop (alert on staleness)"
    echo "# TYPE pfsense_ix0_watchdog_last_run_timestamp_seconds gauge"
    echo "pfsense_ix0_watchdog_last_run_timestamp_seconds{device=\"$IFACE\"} $(date +%s)"
    echo "# HELP pfsense_ix0_large_frame_loss_percent Measured packet loss at ${LOSS_SIZE}B payload (the size bulk TCP uses)"
    echo "# TYPE pfsense_ix0_large_frame_loss_percent gauge"
    for kv in $LOSS_KV; do
      t="${kv%%=*}"; l="${kv#*=}"
      [ "$l" -ge 0 ] && echo "pfsense_ix0_large_frame_loss_percent{device=\"$IFACE\",target=\"$t\",size=\"$LOSS_SIZE\"} $l"
    done
    if [ "$LOSS_MEAN" -ge 0 ]; then
      echo "# HELP pfsense_ix0_large_frame_loss_mean_percent Mean large-frame loss across probe targets (this is what the auto-bounce decides on)"
      echo "# TYPE pfsense_ix0_large_frame_loss_mean_percent gauge"
      echo "pfsense_ix0_large_frame_loss_mean_percent{device=\"$IFACE\",size=\"$LOSS_SIZE\"} $LOSS_MEAN"
    fi
    echo "# HELP pfsense_ix0_watchdog_bounces_total Link bounces performed by the watchdog, by trigger"
    echo "# TYPE pfsense_ix0_watchdog_bounces_total counter"
    echo "pfsense_ix0_watchdog_bounces_total{device=\"$IFACE\",reason=\"blackout\"} $BOUNCES_BLACKOUT"
    echo "pfsense_ix0_watchdog_bounces_total{device=\"$IFACE\",reason=\"degraded\"} $BOUNCES_DEGRADED"
    echo "# HELP pfsense_ix0_watchdog_last_bounce_timestamp_seconds Epoch of the most recent watchdog bounce"
    echo "# TYPE pfsense_ix0_watchdog_last_bounce_timestamp_seconds gauge"
    echo "pfsense_ix0_watchdog_last_bounce_timestamp_seconds{device=\"$IFACE\"} $LAST_BOUNCE_TS"
    echo "# HELP pfsense_ix0_watchdog_last_bounce_succeeded Did the last degraded bounce restore the link? 1=yes 0=no -1=unknown"
    echo "# TYPE pfsense_ix0_watchdog_last_bounce_succeeded gauge"
    echo "pfsense_ix0_watchdog_last_bounce_succeeded{device=\"$IFACE\"} $LAST_BOUNCE_RESULT"
    echo "# HELP pfsense_ix0_watchdog_consecutive_failures Consecutive degraded bounces that did NOT restore the link"
    echo "# TYPE pfsense_ix0_watchdog_consecutive_failures gauge"
    echo "pfsense_ix0_watchdog_consecutive_failures{device=\"$IFACE\"} $CONSEC_FAILURES"
    echo "# HELP pfsense_ix0_watchdog_disarmed Watchdog gave up auto-bouncing (bounces no longer help -> optic replacement required)"
    echo "# TYPE pfsense_ix0_watchdog_disarmed gauge"
    echo "pfsense_ix0_watchdog_disarmed{device=\"$IFACE\"} $DISARMED"
  } > "$tmp" || { rm -f "$tmp"; return 0; }
  # Explicit rm on every path rather than a trap: this runs inside a long-lived
  # daemon, where an EXIT trap would not fire until the daemon itself exits.
  if mv "$tmp" "$METRICS" 2>/dev/null; then
    chmod 644 "$METRICS" 2>/dev/null
  else
    rm -f "$tmp"
  fi
  return 0
}

# --- actions ----------------------------------------------------------------

do_bounce() {   # $1 = reason label
  log "ACTION: bouncing $IFACE (reason=$1, link=$(link_status))"
  /sbin/ifconfig "$IFACE" down; sleep "$DOWN_SECS"; /sbin/ifconfig "$IFACE" up
  LAST_BOUNCE_TS=$(date +%s)
  log "ACTION: $IFACE bounced (reason=$1); cooldown ${COOLDOWN}s"
}

roll_day() {    # reset the per-day cap when the date changes
  today=$(date +%Y%m%d)
  if [ "$DAY_STAMP" != "$today" ]; then DAY_STAMP="$today"; DAY_BOUNCES=0; fi
}

# Effective gap between degraded bounces, doubled per consecutive failure so a
# decaying optic backs the automation off instead of looping outages.
degraded_gap() {
  gap="$DEGRADED_MIN_GAP"
  i=0
  while [ "$i" -lt "$CONSEC_FAILURES" ]; do gap=$((gap * 2)); i=$((i + 1)); done
  echo "$gap"
}

handle_degraded_bounce() {
  do_bounce degraded
  BOUNCES_DEGRADED=$((BOUNCES_DEGRADED + 1))
  DAY_BOUNCES=$((DAY_BOUNCES + 1))
  save_state; write_metrics

  log "verifying: settling ${SETTLE_SECS}s before re-measuring loss"
  sleep "$SETTLE_SECS"
  sweep_loss
  # Judge on the MEAN, inclusively, and consistently with the trigger.
  # 2026-08-17: the first real auto-bounce took loss 12% -> 2%/1% and was scored
  # FAILED, because the test was `worst < 2` and worst was exactly 2. That is a
  # plainly successful retrain reported as a failure -- which raises a critical
  # alert and counts toward self-disarm. Two errors: an exclusive comparison on
  # a boundary value, and judging on `worst`, the noisiest available statistic
  # (single-target estimates swing +-6% at these packet counts) rather than the
  # mean the bounce decision itself uses.
  if [ "$LOSS_N" -ge "$LOSS_MIN_TARGETS" ] && [ "$LOSS_MEAN" -le "$SUCCESS_LOSS_PCT" ]; then
    LAST_BOUNCE_RESULT=1; CONSEC_FAILURES=0
    log "RESULT: bounce SUCCEEDED — mean loss ${LOSS_MEAN}% (<= ${SUCCESS_LOSS_PCT}%) [$LOSS_KV]"
  else
    LAST_BOUNCE_RESULT=0; CONSEC_FAILURES=$((CONSEC_FAILURES + 1))
    log "RESULT: bounce FAILED — mean loss ${LOSS_MEAN}% (> ${SUCCESS_LOSS_PCT}%) [$LOSS_KV]; consecutive failures=$CONSEC_FAILURES"
    if [ "$CONSEC_FAILURES" -ge "$MAX_CONSEC_FAILURES" ]; then
      DISARMED=1
      log "DISARM: $CONSEC_FAILURES consecutive failed bounces — auto-bounce DISABLED. Bouncing no longer restores this link; the optic must be replaced (docs/network/2026-06-28-ix0-optic-flap-handoff.md). Re-arm with: ix0-watchdog.sh reset"
    fi
  fi
  save_state; write_metrics
}

run() {
  load_state; roll_day
  log "started (iface=$IFACE blackout='${THRESHOLD}x${INTERVAL}s' degraded='mean >=${LOSS_TRIGGER_PCT}% @${LOSS_SIZE}B over >=${LOSS_MIN_TARGETS} targets, ${DEGRADED_THRESHOLD} of last ${DEGRADED_WINDOW} probes' min_gap=${MIN_FLAP_GAP}s degraded_gap=$(degraded_gap)s cap=${DEGRADED_MAX_PER_DAY}/day disarmed=$DISARMED)"
  fails=0; degraded_count=0; tick=0; hist=""
  # Warm-up guard: treat daemon start as if we had just flapped, so starting (or
  # the cron keepalive restarting) the daemon into an ALREADY-degraded link can
  # not bounce immediately — MIN_FLAP_GAP must elapse first. Deploying this into
  # a live fault must not itself cause an unapproved outage.
  last_flap=$(date +%s)

  while :; do
    tick=$((tick + 1))
    roll_day

    # ---- BLACKOUT ----
    if probe; then
      [ "$fails" -gt 0 ] && log "recovered after ${fails} all-down probe(s)"
      fails=0
    else
      fails=$((fails + 1))
      log "all LAN targets unreachable (${fails}/${THRESHOLD})"
      if [ "$fails" -ge "$THRESHOLD" ]; then
        now=$(date +%s)
        if [ -f "$NOBOUNCE_FLAG" ]; then
          log "nobounce flag set — NOT bouncing (blackout)"
        elif [ $((now - last_flap)) -lt "$MIN_FLAP_GAP" ]; then
          log "rate-limited: last flap $((now - last_flap))s ago (< ${MIN_FLAP_GAP}s) — NOT flapping"
        else
          do_bounce blackout
          BOUNCES_BLACKOUT=$((BOUNCES_BLACKOUT + 1))
          last_flap=$(date +%s); fails=0; degraded_count=0
          save_state; write_metrics
          sleep "$COOLDOWN"
          continue
        fi
      fi
      sleep "$INTERVAL"
      continue          # link is blacked out; a loss probe would be meaningless
    fi

    # ---- DEGRADED (every LOSS_PROBE_EVERY ticks) ----
    if [ $((tick % LOSS_PROBE_EVERY)) -eq 0 ]; then
      sweep_loss
      # Sliding window of the last DEGRADED_WINDOW verdicts, newest on the right.
      if degraded; then hist="${hist}1"; else hist="${hist}0"; fi
      hist=$(printf '%s' "$hist" | tail -c "$DEGRADED_WINDOW")
      degraded_count=$(printf '%s' "$hist" | tr -cd '1' | wc -c | tr -d ' ')
      if degraded; then
        log "degraded: mean ${LOSS_MEAN}% >= ${LOSS_TRIGGER_PCT}% (${degraded_count}/${DEGRADED_THRESHOLD} in last ${DEGRADED_WINDOW} probes) [$LOSS_KV]"
        if [ "$degraded_count" -ge "$DEGRADED_THRESHOLD" ]; then
          now=$(date +%s); gap=$(degraded_gap)
          # Every suppressed path clears the window so we re-observe from
          # scratch rather than re-triggering on the next single bad probe.
          if [ "$DISARMED" -eq 1 ]; then
            log "DISARMED — not bouncing; replace the optic (worst loss ${WORST_LOSS}%)"
            hist=""
          elif [ -f "$NOBOUNCE_FLAG" ]; then
            log "nobounce flag set — NOT bouncing (degraded, worst ${WORST_LOSS}%)"
            hist=""
          elif [ "$DAY_BOUNCES" -ge "$DEGRADED_MAX_PER_DAY" ]; then
            log "daily cap reached ($DAY_BOUNCES/${DEGRADED_MAX_PER_DAY}) — NOT bouncing"
            hist=""
          elif [ $((now - last_flap)) -lt "$MIN_FLAP_GAP" ] || [ $((now - LAST_BOUNCE_TS)) -lt "$gap" ]; then
            log "rate-limited: last bounce $((now - LAST_BOUNCE_TS))s ago (< ${gap}s effective gap) — NOT bouncing"
            hist=""
          else
            handle_degraded_bounce
            last_flap=$(date +%s); hist=""
            sleep "$COOLDOWN"
            continue
          fi
        fi
      elif [ "$degraded_count" -gt 0 ]; then
        # Below threshold on THIS probe, but the window still holds recent bad
        # ones -- report it rather than looking silently healthy.
        log "below threshold this probe (mean ${LOSS_MEAN}%), window still ${degraded_count}/${DEGRADED_THRESHOLD} [$LOSS_KV]"
      fi
      write_metrics
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
  status)
    load_state
    running && echo "running (pid $(cat "$PIDFILE"))" || echo "not running"
    echo "bounces: blackout=$BOUNCES_BLACKOUT degraded=$BOUNCES_DEGRADED  last_result=$LAST_BOUNCE_RESULT consec_failures=$CONSEC_FAILURES disarmed=$DISARMED"
    # Trailing `[ ] && echo` would make this case exit 1 whenever the flag is
    # absent (the normal state) -- the same falsy-last-command class of bug that
    # silently broke ix0_link_metrics.sh. Keep the exit status deliberate.
    if [ -f "$NOBOUNCE_FLAG" ]; then echo "NOBOUNCE flag is set (metrics only, will not bounce)"; fi
    exit 0
    ;;
  check)
    probe || { echo "BLACKOUT: all LAN targets unreachable (ix0 link=$(link_status))"; exit 0; }
    sweep_loss
    echo "reachable; large-frame(${LOSS_SIZE}B) loss: $LOSS_KV  worst=${WORST_LOSS}%"
    # `degraded` populates LOSS_MEAN, so evaluate it before reporting.
    if degraded; then verdict="DEGRADED — would count toward a bounce"; else verdict="not degraded by the trigger rule"; fi
    echo "mean=${LOSS_MEAN}% (trigger at >=${LOSS_TRIGGER_PCT}% over >=${LOSS_MIN_TARGETS} targets)"
    echo "STATUS: $verdict"
    exit 0
    ;;
  testbounce)
    # Deliberate on-demand bounce, for validating the pipeline end to end.
    # Exercises the REAL path: measure -> bounce -> settle -> re-measure ->
    # score with the same criterion production uses. Bypasses only the
    # rate-limit/daily-cap guards, since those exist to stop the DAEMON from
    # acting too often, not to stop a human testing deliberately.
    # It does NOT touch CONSEC_FAILURES/DISARMED: a test run against an
    # already-healthy link would otherwise push the watchdog toward disarming
    # itself for no reason.
    if [ -f "$NOBOUNCE_FLAG" ]; then
      echo "refusing: $NOBOUNCE_FLAG is set (rack work in progress?)"; exit 1
    fi
    load_state
    echo "=== BEFORE ==="
    sweep_loss
    echo "  loss@${LOSS_SIZE}B: $LOSS_KV"
    echo "  mean=${LOSS_MEAN}%  worst=${WORST_LOSS}%  link=$(link_status)"
    rf_before=$(sysctl -n dev.ix.0.mac_stats.remote_faults 2>/dev/null)
    echo "  remote_faults=$rf_before"
    before_mean="$LOSS_MEAN"

    log "TEST: manual testbounce requested (before: mean ${LOSS_MEAN}% [$LOSS_KV])"
    do_bounce manual-test
    LAST_BOUNCE_TS=$(date +%s)

    echo "=== settling ${SETTLE_SECS}s ==="
    sleep "$SETTLE_SECS"

    echo "=== AFTER ==="
    sweep_loss
    echo "  loss@${LOSS_SIZE}B: $LOSS_KV"
    echo "  mean=${LOSS_MEAN}%  worst=${WORST_LOSS}%  link=$(link_status)"
    rf_after=$(sysctl -n dev.ix.0.mac_stats.remote_faults 2>/dev/null)
    echo "  remote_faults=$rf_after (delta=$((rf_after - rf_before)) over the run)"

    if [ "$LOSS_N" -ge "$LOSS_MIN_TARGETS" ] && [ "$LOSS_MEAN" -le "$SUCCESS_LOSS_PCT" ]; then
      LAST_BOUNCE_RESULT=1
      echo "  VERDICT: SUCCEEDED (mean ${LOSS_MEAN}% <= ${SUCCESS_LOSS_PCT}%)"
      log "TEST: testbounce SUCCEEDED — mean ${before_mean}% -> ${LOSS_MEAN}% [$LOSS_KV]"
    else
      LAST_BOUNCE_RESULT=0
      echo "  VERDICT: FAILED (mean ${LOSS_MEAN}% > ${SUCCESS_LOSS_PCT}%)"
      log "TEST: testbounce FAILED — mean ${before_mean}% -> ${LOSS_MEAN}% [$LOSS_KV]"
    fi
    save_state; write_metrics
    exit 0
    ;;
  reset)
    load_state
    DISARMED=0; CONSEC_FAILURES=0; LAST_BOUNCE_RESULT=-1
    save_state
    log "reset: disarm cleared, failure counter zeroed (re-armed)"
    echo "re-armed"
    ;;
  *) echo "usage: $0 {start|stop|status|check|testbounce|reset}"; exit 1 ;;
esac
