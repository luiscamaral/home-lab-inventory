#!/usr/bin/env bash
# flash.sh — Build and flash an ESP-IDF project to the ESP32-C5
# Usage: tools/esp32c5/flash.sh <project_dir> [idf.py extra args]
#
# Activates IDF, detects UART_PORT by VID/PID, then runs:
#   idf.py -p $UART_PORT set-target esp32c5 (skipped if sdkconfig exists)
#   idf.py -p $UART_PORT build flash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project_dir> [extra idf.py args]" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
shift
EXTRA_ARGS="${*:-}"

# Activate toolchain
# shellcheck source=idf-env.sh
source "${SCRIPT_DIR}/idf-env.sh" || exit 1

# Detect ports
# shellcheck source=detect-ports.sh
source "${SCRIPT_DIR}/detect-ports.sh"

if [ -z "${UART_PORT:-}" ]; then
  echo "ERROR: No UART port detected. Is the CH340 cable connected?" >&2
  exit 1
fi

echo "==> Flashing ${PROJECT_DIR} to ${UART_PORT}"
cd "${PROJECT_DIR}"

# Set target if not already set (no sdkconfig or wrong target)
if [ ! -f sdkconfig ] || ! grep -q "CONFIG_IDF_TARGET=\"esp32c5\"" sdkconfig 2>/dev/null; then
  echo "==> Setting target to esp32c5"
  idf.py set-target esp32c5
fi

# Build and flash
# shellcheck disable=SC2086
idf.py -p "${UART_PORT}" build flash ${EXTRA_ARGS}

echo "==> Flash complete. Run: tools/esp32c5/monitor.sh ${PROJECT_DIR}"
