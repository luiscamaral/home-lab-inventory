#!/usr/bin/env bash
# metrics-assert.sh — Assert Prometheus metrics endpoint correctness
# Usage: tools/esp32c5/metrics-assert.sh <device_ip> [expected_metric ...]
#
# Curls http://<device_ip>/metrics and greps for each required metric name.
# Exits non-zero if any metric is missing or the endpoint is unreachable.
#
# Default required metrics match the v0 spec if none are specified.
# Example:
#   tools/esp32c5/metrics-assert.sh 192.168.4.50 wifi_client_connected probe_success

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <device_ip> [expected_metric ...]" >&2
  echo "Example: $0 192.168.4.50 wifi_client_connected probe_success" >&2
  exit 1
fi

DEVICE_IP="$1"
shift
METRICS_URL="http://${DEVICE_IP}/metrics"

# Default required metrics (v0 spec surface)
if [ $# -eq 0 ]; then
  set -- \
    wifi_client_connected \
    wifi_client_rssi_dbm \
    wifi_client_channel \
    wifi_client_bssid_info \
    wifi_client_disconnect_total \
    probe_success \
    probe_duration_seconds \
    probe_http_status_code \
    wifi_probe_uptime_seconds \
    wifi_probe_heap_free_bytes \
    wifi_probe_build_info
fi

echo "==> Fetching ${METRICS_URL}"
RESPONSE=$(curl -sf --max-time 10 "${METRICS_URL}" 2>&1) || {
  echo "FAIL: Could not reach ${METRICS_URL}" >&2
  echo "      Ensure the device is on the network and /metrics is responding." >&2
  exit 1
}

echo "==> Asserting ${#} metric families:"
PASS=0
FAIL=0
MISSING=()

for metric in "$@"; do
  if echo "${RESPONSE}" | grep -qE "^(#.*)?${metric}"; then
    printf "  PASS  %s\n" "${metric}"
    PASS=$((PASS + 1))
  else
    printf "  FAIL  %s  (not found)\n" "${metric}" >&2
    MISSING+=("${metric}")
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [ ${FAIL} -gt 0 ]; then
  echo ""
  echo "Missing metrics: ${MISSING[*]}"
  echo ""
  echo "--- Raw /metrics response (first 40 lines) ---"
  echo "${RESPONSE}" | head -40
  exit 1
fi

# Bonus: validate build_info shows esp32c5
if echo "${RESPONSE}" | grep -q 'wifi_probe_build_info'; then
  if echo "${RESPONSE}" | grep 'wifi_probe_build_info' | grep -q 'chip="esp32c5"'; then
    echo "PASS  chip label: esp32c5 confirmed"
  else
    echo "WARN  chip label not 'esp32c5' in wifi_probe_build_info — check firmware target" >&2
  fi
fi

echo ""
echo "All ${PASS} metric assertions passed."
