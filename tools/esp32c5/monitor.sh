#!/usr/bin/env bash
# monitor.sh — Open serial monitor for ESP32-C5 project
# Usage: tools/esp32c5/monitor.sh <project_dir>
#
# Activates IDF, detects UART_PORT, opens idf.py monitor.
# Press Ctrl-] to exit the monitor.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project_dir>" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"

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

echo "==> Opening monitor on ${UART_PORT} (press Ctrl-] to exit)"
cd "${PROJECT_DIR}"
idf.py -p "${UART_PORT}" monitor
