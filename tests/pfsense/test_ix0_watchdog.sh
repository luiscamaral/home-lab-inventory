#!/bin/sh
# Variables assigned below are read by the sourced watchdog script; the linter
# cannot follow a dynamic source, hence the file-wide SC2034 disable.
# shellcheck disable=SC2034
# Unit + scenario tests for pfsense/scripts/ix0-watchdog.sh.
# Runs anywhere with a POSIX sh (CI: dash; pfSense: FreeBSD sh). Never touches a
# real interface: ifconfig/ping/clock are stubbed and all state lives in a tmpdir.
#
#   sh tests/pfsense/test_ix0_watchdog.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../pfsense/scripts/ix0-watchdog.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

# --- load the script as a library, then sandbox it ---------------------------
IX0WD_LIB=1
# shellcheck disable=SC1090
. "$SCRIPT"
IFACE="ix0wdtest0"
STATE="$T/state"; LOG="$T/log"; PIDFILE="$T/pid"
NOBOUNCE_FLAG="$T/nobounce"; FLAP_FILE="$T/lastflap"; HOLD_FILE="$T/hold"
METRICS_DIR="$T/metrics"; METRICS="$METRICS_DIR/ix0_watchdog.prom"
log() { echo "$1" >> "$LOG"; }
LINK=up
link_status() { echo "$LINK"; }

reset_all() {
  rm -f "$STATE" "$LOG" "$NOBOUNCE_FLAG" "$FLAP_FILE" "$HOLD_FILE" "$T/bounces" "$T/injected"
  BOUNCES_BLACKOUT=0; BOUNCES_DEGRADED=0; LAST_BOUNCE_TS=0; LAST_BOUNCE_RESULT=-1
  CONSEC_FAILURES=0; DISARMED=0; DAY_STAMP=""; DAY_BOUNCES=0
  BLACKOUT_STREAK=0; DAY_BLACKOUTS=0; LINK=up
}

# =============================================================================
echo "blackout_decide"
reset_all
NOW=100000; LF=$((NOW - 10000))
d=$(blackout_decide "$NOW" "$LF" up); eq "clean state -> bounce" "${d%% *}" bounce
touch "$NOBOUNCE_FLAG"
d=$(blackout_decide "$NOW" "$LF" up); eq "paused -> nobounce" "${d%% *}" nobounce
rm -f "$NOBOUNCE_FLAG"
echo $((NOW + 60)) > "$HOLD_FILE"
d=$(blackout_decide "$NOW" "$LF" up); eq "hold active -> hold" "${d%% *}" hold
echo $((NOW - 1)) > "$HOLD_FILE"
d=$(blackout_decide "$NOW" "$LF" up); eq "hold expired -> bounce" "${d%% *}" bounce
echo "garbage" > "$HOLD_FILE"
d=$(blackout_decide "$NOW" "$LF" up); eq "garbage hold file ignored" "${d%% *}" bounce
rm -f "$HOLD_FILE"
BLACKOUT_STREAK=1
d=$(blackout_decide "$NOW" "$LF" up);   eq "streak 1, carrier up -> bounce" "${d%% *}" bounce
d=$(blackout_decide "$NOW" "$LF" down); eq "streak 1, NO carrier -> giveup" "${d%% *}" giveup
BLACKOUT_STREAK=2
d=$(blackout_decide "$NOW" "$LF" up);   eq "streak 2, carrier up -> giveup" "${d%% *}" giveup
BLACKOUT_STREAK=0; DAY_BLACKOUTS=$BLACKOUT_MAX_PER_DAY
d=$(blackout_decide "$NOW" "$LF" up);   eq "daily cap -> daycap" "${d%% *}" daycap
DAY_BLACKOUTS=0
d=$(blackout_decide "$NOW" "$((NOW - 100))" up); eq "recent flap -> ratelimit" "${d%% *}" ratelimit
BLACKOUT_STREAK=5; touch "$NOBOUNCE_FLAG"
d=$(blackout_decide "$NOW" "$LF" up);   eq "pause outranks giveup" "${d%% *}" nobounce

# =============================================================================
echo "sync_external_flap"
reset_all
last_flap=1000; LAST_BOUNCE_TS=900; fails=4; hist="11"
echo 2000 > "$FLAP_FILE"
if sync_external_flap; then ok "newer external flap adopted"; else bad "newer external flap adopted"; fi
eq "last_flap moved"        "$last_flap" 2000
eq "LAST_BOUNCE_TS moved"   "$LAST_BOUNCE_TS" 2000
eq "fails reset"            "$fails" 0
eq "degraded window reset"  "$hist" ""
if sync_external_flap; then bad "same flap adopted twice"; else ok "same flap not adopted twice"; fi
echo 1500 > "$FLAP_FILE"
if sync_external_flap; then bad "older flap adopted"; else ok "older flap ignored"; fi
rm -f "$FLAP_FILE"
if sync_external_flap; then bad "missing file adopted"; else ok "missing file ignored"; fi

# =============================================================================
echo "do_bounce stamps FLAP_FILE (stub iface, no real ifconfig effect)"
reset_all
DOWN_SECS=0
do_bounce unit-test 2>/dev/null
eq "FLAP_FILE == LAST_BOUNCE_TS" "$(read_epoch "$FLAP_FILE")" "$LAST_BOUNCE_TS"
[ "$LAST_BOUNCE_TS" -gt 0 ] && ok "LAST_BOUNCE_TS set" || bad "LAST_BOUNCE_TS set"

# =============================================================================
echo "state persistence"
reset_all
BLACKOUT_STREAK=1; DAY_BLACKOUTS=3; DISARMED=1; save_state
BLACKOUT_STREAK=0; DAY_BLACKOUTS=0; DISARMED=0; load_state
eq "BLACKOUT_STREAK round-trips" "$BLACKOUT_STREAK" 1
eq "DAY_BLACKOUTS round-trips"   "$DAY_BLACKOUTS" 3
printf 'BOUNCES_BLACKOUT=20\nDISARMED=1\n' > "$STATE"     # pre-2026-10-24 state file
BLACKOUT_STREAK=0; DAY_BLACKOUTS=0; load_state
eq "old state file: streak defaults to 0" "$BLACKOUT_STREAK" 0
DAY_STAMP="19700101"; DAY_BLACKOUTS=4; roll_day
eq "roll_day resets DAY_BLACKOUTS" "$DAY_BLACKOUTS" 0

# =============================================================================
# Scenario harness: run the REAL daemon loop (run) against a fake clock.
#   CLOCK file   - fake epoch, advanced by the sleep() stub
#   PROBE        - "fail" or "ok" (or "ok_after:<epoch>")
#   INJECT_AT    - epoch at which a simulated MANUAL testbounce happens while the
#                  daemon is running: stamps FLAP_FILE, sets HOLD_FILE, LINK=down
# do_bounce is replaced by a recorder; everything else is production code.
date() {
  if [ "${1:-}" = "+%s" ]; then cat "$T/clock"; else command date "$@"; fi
}
INJECT_AT=0
sleep() {
  c=$(( $(cat "$T/clock") + ${1%.*} )); echo "$c" > "$T/clock"
  if [ "$INJECT_AT" -gt 0 ] && [ "$c" -ge "$INJECT_AT" ]; then
    echo "$c" > "$FLAP_FILE"                                     # testbounce's do_bounce
    echo $((c + DOWN_SECS + SETTLE_SECS + 300)) > "$HOLD_FILE"   # testbounce's hold
    echo "$c" > "$T/injected"
    LINK=down; PROBE=fail; INJECT_AT=0
  fi
  [ "$c" -ge "$END" ] && exit 0
  return 0
}
probe() {
  case "$PROBE" in
    ok) return 0 ;;
    fail) return 1 ;;
    ok_after:*) [ "$(cat "$T/clock")" -ge "${PROBE#ok_after:}" ] ;;
  esac
}
sweep_loss() { LOSS_KV=""; WORST_LOSS=0; LOSS_MEAN=0; LOSS_MIN=0; LOSS_N=2; }
do_bounce() {
  LAST_BOUNCE_TS=$(cat "$T/clock")
  echo "$LAST_BOUNCE_TS" > "$FLAP_FILE"
  echo "$LAST_BOUNCE_TS $1" >> "$T/bounces"
}
bounces() { [ -f "$T/bounces" ] && wc -l < "$T/bounces" | tr -d ' ' || echo 0; }
run_daemon() { ( run ) >/dev/null 2>&1; load_state; }

echo "scenario: 2026-10-24 replay (manual testbounce -> NO CARRIER, never recovers)"
reset_all
T0=1792900000
echo "$T0" > "$T/clock"; END=$((T0 + 5 * 3600))
# Daemon has been running on a healthy link for an hour; then the manual
# testbounce fires and the link never comes back (no carrier).
LINK=up; PROBE=ok; INJECT_AT=$((T0 + 3600))
run_daemon
INJECT_AT=0
TI=$(cat "$T/injected")
eq "exactly ONE daemon bounce in 4 h (was: every 10 min forever)" "$(bounces)" 1
first=$(cut -d' ' -f1 "$T/bounces" | head -1)
[ "$((first - TI))" -ge "$MIN_FLAP_GAP" ] \
  && ok "daemon waited >= MIN_FLAP_GAP after the manual bounce ($((first - TI))s; was 3 min)" \
  || bad "daemon bounced $((first - TI))s after the manual bounce (< ${MIN_FLAP_GAP}s)"
eq "GIVE UP logged exactly once" "$(grep -c 'GIVE UP' "$LOG")" 1
grep -q "held by a manual operation" "$LOG" && ok "hold was honoured and logged" || bad "hold not logged"
grep -q "external bounce detected" "$LOG" && ok "manual bounce adopted" || bad "manual bounce not adopted"
grep -q 'blackout_gave_up{device="ix0wdtest0"} 1' "$METRICS" && ok "gave_up metric = 1" || bad "gave_up metric"

echo "scenario: blackout with carrier UP (2026-06-18 STP-block shape)"
reset_all
T0=1792900000; echo "$T0" > "$T/clock"; END=$((T0 + 4 * 3600))
LINK=up; PROBE=fail
run_daemon
eq "carrier up: exactly $BLACKOUT_MAX_STREAK bounces then stop" "$(bounces)" "$BLACKOUT_MAX_STREAK"

echo "scenario: recovery resets the streak"
reset_all
T0=1792900000; echo "$T0" > "$T/clock"; END=$((T0 + 2 * 3600))
LINK=up; PROBE="ok_after:$((T0 + 1000))"   # recovers before a 2nd bounce is due (~+1200s)
run_daemon
eq "one bounce before recovery" "$(bounces)" 1
eq "streak back to 0 after traffic flows" "$BLACKOUT_STREAK" 0

echo "scenario: operator pause blocks every bounce"
reset_all
T0=1792900000; echo "$T0" > "$T/clock"; END=$((T0 + 4 * 3600))
touch "$NOBOUNCE_FLAG"; LINK=down; PROBE=fail
run_daemon
eq "paused: zero bounces" "$(bounces)" 0

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
